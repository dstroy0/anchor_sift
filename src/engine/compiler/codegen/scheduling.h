// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SCHEDULING_H
#define SCHEDULING_H

#include "prologue_epilogue.h"

// The schedule: the lane's body, its opening, steps and close in the order they run, split into states, a clock each,
// then the dispatch state, which sends a refused lane to its refusal's first state

// 1 where the form names a memory address to read, which a clocked target reads by the next state, and the memory
// writes the form makes
CODEGEN_CORE int codegen_asks(unsigned int form)
{
    return (form == OPCODE_LAUNCH_ASK) || (form == OPCODE_GLOBAL_ASK) || (form == OPCODE_GUARDED_ASK) ||
           (form == OPCODE_COUNT_ASK);
}

CODEGEN_CORE unsigned int codegen_writes(unsigned int form)
{
    return ((form == OPCODE_RECORD_STORE) || (form == OPCODE_COUNT_ADD)) ? 1u : 0u;
}

// a state begun in the schedule
CODEGEN_CORE void codegen_state_open(MachineFunction *lane, Schedule *schedule)
{
    codegen_instr1(lane, OPCODE_STATE_OPEN, codegen_number(schedule->state));
    schedule->chained = 0u;
    schedule->writes = 0u;
    schedule->filled = 0u;
    schedule->ending = 0u;
    schedule->left = 0u;
}

// the next state begun, the one before going on to it unless the lane was refused in it
CODEGEN_CORE void codegen_state_next(MachineFunction *lane, Schedule *schedule)
{
    schedule->state += 1u;
    codegen_instr2(lane, OPCODE_STATE_NEXT, codegen_number(schedule->state), codegen_number(SCHEDULE_STATE_DISPATCH));
    codegen_state_open(lane, schedule);
}

// the schedule begun: its first state opened. The writes a state may make are at least the one write a form makes
CODEGEN_CORE void codegen_schedule_open(MachineFunction *lane, Schedule *schedule, unsigned int writes,
                                        unsigned int ports)
{
    schedule->writes_max = (writes < ports) ? writes : ports;
    schedule->writes_max = (schedule->writes_max == 0u) ? 1u : schedule->writes_max;
    schedule->state = SCHEDULE_STATE_FIRST;
    schedule->maximum = 0u;
    schedule->over = 0u;
    schedule->dispatch_count = 0u;
    for (unsigned int loop = 0u; loop < schedule->loop_count; loop += 1u)
    {
        schedule->loop_state[loop] = CODEGEN_UNBEGUN;
    }
    codegen_instr1(lane, OPCODE_STATE_START, codegen_number(SCHEDULE_STATE_FIRST));
    codegen_state_open(lane, schedule);
}

// one of the body's forms laid out into the schedule. A refusal's label begins a state of its own, which the dispatch
// state sends the lane to, and a loop's label begins one the loop's branch back goes back to; a form that would take
// the state past its budget or its writes, or follows one that ends a state, begins the next state, which the state
// before goes on to unless the lane was refused in it. A refusal's test and a memory read's address end their state, a
// loop's branch back ends its state going back or on by its predicate, and a return leaves the lane. A form after a
// return other than a refusal's label, or a branch back to a loop not begun, is a lane the pass cannot split
CODEGEN_CORE void codegen_schedule_instr(MachineFunction *lane, Schedule *schedule, const MachineInstr *item)
{
    const unsigned int form = item->form;
    if ((form == OPCODE_LABEL_REFUSED_OPEN) || (form == OPCODE_LABEL_REFUSED))
    {
        schedule->state += 1u;
        codegen_state_open(lane, schedule);
        if (schedule->dispatch_count < schedule->dispatch_max)
        {
            schedule->dispatch_refusal[schedule->dispatch_count] =
                (form == OPCODE_LABEL_REFUSED_OPEN) ? codegen_minus_one() : item->arguments[0];
            schedule->dispatch_state[schedule->dispatch_count] = schedule->state;
        }
        lane->broken = lane->broken | ((schedule->dispatch_count < schedule->dispatch_max) ? 0u : 1u);
        schedule->dispatch_count += 1u;
        codegen_take(lane, item);
        return;
    }
    if (schedule->left != 0u)
    {
        lane->broken = 1u;
        return;
    }
    if (form == OPCODE_LOOP_LABEL)
    {
        if ((schedule->ending != 0u) || (schedule->filled != 0u))
        {
            codegen_state_next(lane, schedule);
        }
        const unsigned int loop = item->arguments[0].number;
        if (loop < schedule->loop_count)
        {
            schedule->loop_state[loop] = schedule->state;
        }
        lane->broken = lane->broken | ((loop < schedule->loop_count) ? 0u : 1u);
        codegen_take(lane, item);
        return;
    }
    const unsigned int cost = schedule->cost[form];
    const unsigned int writes = codegen_writes(form);
    // a cost or a count checked against its bound by subtraction, where no sum can pass 2^32
    const int full =
        (cost > (schedule->budget - schedule->chained)) || (writes > (schedule->writes_max - schedule->writes));
    if ((schedule->ending != 0u) || ((schedule->filled != 0u) && full))
    {
        codegen_state_next(lane, schedule);
    }
    schedule->over += (cost > schedule->budget) ? 1u : 0u;
    codegen_take(lane, item);
    // a form alone past the budget is counted over and stays alone in its state, and the sum stays under 2^32 as well
    schedule->chained = (cost > (schedule->budget - schedule->chained)) ? schedule->budget : (schedule->chained + cost);
    schedule->writes += writes;
    schedule->filled = 1u;
    schedule->maximum = (schedule->chained > schedule->maximum) ? schedule->chained : schedule->maximum;
    schedule->ending =
        ((form == OPCODE_REFUSE) || (form == OPCODE_OPEN_REFUSED_UNLESS) || codegen_asks(form)) ? 1u : 0u;
    if (form == OPCODE_LOOP_BACK)
    {
        const unsigned int loop = item->arguments[0].number;
        const unsigned int begun = (loop < schedule->loop_count) ? schedule->loop_state[loop] : CODEGEN_UNBEGUN;
        if (begun == CODEGEN_UNBEGUN)
        {
            lane->broken = 1u;
            return;
        }
        schedule->state += 1u;
        codegen_instr3(lane, OPCODE_STATE_LOOP, codegen_number(begun), item->arguments[1],
                       codegen_number(schedule->state));
        codegen_state_open(lane, schedule);
    }
    if (form == OPCODE_RETURN)
    {
        codegen_instr0(lane, OPCODE_STATE_EXIT);
        schedule->left = 1u;
    }
}

// the schedule ended: the dispatch state, which sends a refused lane to its refusal's first state. The states are
// schedule->state
CODEGEN_CORE void codegen_schedule_close(MachineFunction *lane, Schedule *schedule)
{
    codegen_instr1(lane, OPCODE_STATE_OPEN, codegen_number(SCHEDULE_STATE_DISPATCH));
    const unsigned int recorded =
        (schedule->dispatch_count < schedule->dispatch_max) ? schedule->dispatch_count : schedule->dispatch_max;
    for (unsigned int refusal = 0u; refusal < recorded; refusal += 1u)
    {
        codegen_instr2(lane, OPCODE_DISPATCH_TO, schedule->dispatch_refusal[refusal],
                       codegen_number(schedule->dispatch_state[refusal]));
    }
}

#endif
