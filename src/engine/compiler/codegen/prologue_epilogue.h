// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PROLOGUE_EPILOGUE_H
#define PROLOGUE_EPILOGUE_H

#include "instruction_selection.h"

// The lane's own forms, decided after every step from what the steps left in the lane: the most of each bank any step
// took, whether any reads the tables, and which can leave the lane errored. Each is decided in the order the lane was
// always written, the note, the lane's opening and its declarations, then its opening, its close, and where the body is
// split, the schedule, then the body's opening and the lane's end, since a construct's scratch goes on from where each
// bank stands; they are laid out into the text in another order (code_generator.cu)

// the program's note, which the assembly printer writes from the step count it holds and the target
CODEGEN_CORE void codegen_note(MachineFunction *lane)
{
    const MachineOperand none = codegen_zero();
    codegen_instr(lane, OPCODE_PROGRAM_NOTE, 6u, codegen_number(lane->program->step_count), none, none, none);
}

// the lane's registers, each bank as many as the lane takes
CODEGEN_CORE void codegen_declare(MachineFunction *lane, unsigned int atoms)
{
    const IrProgram *const program = lane->program;
    if (lane->predicates_max != 0u)
    {
        codegen_instr1(lane, OPCODE_DECLARE_PREDICATES, codegen_number(lane->predicates_max));
    }
    codegen_instr0(lane, OPCODE_DECLARE_FIXED_PREDICATES);
    codegen_instr1(lane, OPCODE_DECLARE_FILE, codegen_number(program->file_limbs));
    codegen_instr1(lane, OPCODE_DECLARE_SIGNS, codegen_number(program->file_limbs));
    codegen_instr1(lane, OPCODE_DECLARE_OUT, codegen_number(program->out_limbs));
    if (atoms != 0u)
    {
        codegen_instr1(lane, OPCODE_DECLARE_ATOMS, codegen_number(atoms));
    }
    codegen_instr1(lane, OPCODE_DECLARE_TEMPORARIES, codegen_number(lane->temps_max));
    codegen_instr1(lane, OPCODE_DECLARE_WIDES, codegen_number(lane->wides_max));
    codegen_instr0(lane, OPCODE_DECLARE_FIXED_WORDS);
    codegen_instr0(lane, OPCODE_DECLARE_FIXED_WIDES);
    codegen_instr1(lane, OPCODE_DECLARE_MEMBERS, codegen_number(ENGINE_RECORD_MEMBERS_MAX));
}

// a 64-bit field of the launch read into `to` from its offset: asked for, then taken, as a language that clocks the
// lane reads its memory a clock after it names the address
CODEGEN_CORE void codegen_launch(MachineFunction *lane, MachineOperand to, unsigned int offset)
{
    codegen_instr1(lane, OPCODE_LAUNCH_ASK, codegen_number(offset));
    codegen_instr2(lane, OPCODE_LAUNCH_LOAD, to, codegen_number(offset));
}

// the lane's opening: its launch and number, the record's words no put writes stored as 0, and each member's atom found
// as the interpreter finds it, a lane whose atom lies past its member errored before any step; then the words a
// error would leave unlaid stored as 0, the program's tables where `tables` is 1, and where the language holds the
// file in shared memory, its `places` there and where its signs begin after them. `errors` is 1 for each step that can
// leave the lane errored
CODEGEN_CORE void codegen_open(MachineFunction *lane, const unsigned int *errors, unsigned int tables,
                               unsigned int places)
{
    const IrProgram *const program = lane->program;
    const MachineOperand zero = codegen_zero();
    const MachineOperand lane_number = codegen_physreg(PHYSREG_LANE_NUMBER);
    const MachineOperand record = codegen_physreg(PHYSREG_RECORD);
    const MachineOperand index = codegen_physreg(PHYSREG_INDEX);
    const MachineOperand body = codegen_physreg(PHYSREG_BODY);
    const MachineOperand bodies = codegen_physreg(PHYSREG_BODIES);
    const MachineOperand indexed = codegen_physreg(PHYSREG_INDEXED);
    const MachineOperand one = codegen_physreg(PHYSREG_ONE);
    const MachineOperand ok = codegen_physreg(PHYSREG_OK);
    // the opening's own 32- and 64-bit temporaries, the first of each bank, which no step has taken yet
    const MachineOperand temporary = codegen_register(REGCLASS_TEMPORARY, 0u);
    const MachineOperand wide = codegen_register(REGCLASS_WIDE, 0u);
    // the launch's offsets are a few dozen bytes
    codegen_instr0(lane, OPCODE_OPEN_LAUNCH);
    codegen_launch(lane, record, (unsigned int)offsetof(CycleCompiledLaunch, out));
    codegen_instr1(lane, OPCODE_TO_GLOBAL, record);
    codegen_instr3(lane, OPCODE_WIDE_MULTIPLY, wide, lane_number, codegen_immediate(4u * program->out_limbs));
    codegen_instr3(lane, OPCODE_WIDE_ADD, record, record, wide);
    // a word no put writes is 0 on every lane, errored or not, and is stored before anything can error
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if (program->put_last[word] == 0u)
        {
            codegen_instr2(lane, OPCODE_RECORD_STORE, codegen_number(4u * word), zero);
        }
    }
    codegen_launch(lane, index, (unsigned int)offsetof(CycleCompiledLaunch, index));
    codegen_instr2(lane, OPCODE_TEST_WIDE_NONZERO, indexed, index);
    codegen_instr1(lane, OPCODE_TO_GLOBAL, index);
    for (unsigned int member = 0u; member < program->members; member += 1u)
    {
        const MachineOperand address = codegen_register(REGCLASS_MEMBER, member);
        // with no index, lane i reads record i of a member, or its one record where it has one
        codegen_launch(lane, bodies, (unsigned int)offsetof(CycleCompiledLaunch, bodies) + (8u * member));
        codegen_instr3(lane, OPCODE_TEST_WIDE_EQUAL, one, bodies, codegen_number(1u));
        codegen_instr4(lane, OPCODE_WIDE_SELECT, body, codegen_number(0u), lane_number, one);
        codegen_instr3(lane, OPCODE_WIDE_MULTIPLY, wide, lane_number, codegen_immediate(program->members));
        codegen_instr3(lane, OPCODE_WIDE_ADD_UNSIGNED, wide, wide, codegen_immediate(member));
        codegen_instr3(lane, OPCODE_WIDE_SHIFT_LEFT, wide, wide, codegen_number(2u));
        codegen_instr3(lane, OPCODE_WIDE_ADD, wide, index, wide);
        codegen_instr2(lane, OPCODE_GUARDED_ASK, indexed, wide);
        codegen_instr3(lane, OPCODE_GUARDED_LOAD, indexed, temporary, wide);
        codegen_instr3(lane, OPCODE_GUARDED_WIDEN, indexed, body, temporary);
        if (member == 0u)
        {
            codegen_instr3(lane, OPCODE_TEST_WIDE_BELOW, ok, body, bodies);
        }
        else
        {
            codegen_instr4(lane, OPCODE_TEST_WIDE_BELOW_AND, ok, body, bodies, ok);
        }
        codegen_instr4(lane, OPCODE_WIDE_SELECT, body, body, codegen_number(0u), ok);
        codegen_launch(lane, address, (unsigned int)offsetof(CycleCompiledLaunch, in) + (8u * member));
        codegen_instr1(lane, OPCODE_TO_GLOBAL, address);
        codegen_instr3(lane, OPCODE_WIDE_MULTIPLY, wide, body, codegen_immediate(4u * program->in_limbs[member]));
        codegen_instr3(lane, OPCODE_WIDE_ADD, address, address, wide);
    }
    codegen_instr1(lane, OPCODE_OPEN_ERROR_UNLESS, ok);
    // a word whose first put comes at or after a step the lane can leave errored is 0 in the record until its last put
    // stores it, and the error stores only the words it holds in flight
    unsigned int error_first = program->step_count;
    for (unsigned int at = 0u; (at < program->step_count) && (error_first == program->step_count); at += 1u)
    {
        error_first = (errors[at] != 0u) ? at : error_first;
    }
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if ((program->put_last[word] != 0u) && (program->put_first[word] >= error_first))
        {
            codegen_instr2(lane, OPCODE_RECORD_STORE, codegen_number(4u * word), zero);
        }
    }
    if (tables != 0u)
    {
        const MachineOperand table_address = codegen_physreg(PHYSREG_TABLES);
        codegen_launch(lane, table_address, (unsigned int)offsetof(CycleCompiledLaunch, tables));
        codegen_instr1(lane, OPCODE_TO_GLOBAL, table_address);
    }
    if (places != 0u)
    {
        // a word's address is its place . threads + thread, a sign's 4 places . threads + place . threads + thread
        const MachineOperand sign_base = codegen_physreg(PHYSREG_SIGN_BASE);
        codegen_instr0(lane, OPCODE_SHARED_OPEN);
        codegen_instr4(lane, OPCODE_WORD_MULTIPLY_ADD, sign_base, codegen_physreg(PHYSREG_THREADS),
                       codegen_immediate(4u * places), sign_base);
        codegen_instr0(lane, OPCODE_SHARED_CLOSE);
    }
}

// an errored lane counted in the launch's errors
CODEGEN_CORE void codegen_count_error(MachineFunction *lane)
{
    const MachineOperand wide = codegen_register(REGCLASS_WIDE, 0u);
    codegen_launch(lane, wide, (unsigned int)offsetof(CycleCompiledLaunch, error));
    codegen_instr1(lane, OPCODE_TO_GLOBAL, wide);
    codegen_instr1(lane, OPCODE_COUNT_ASK, wide);
    codegen_instr1(lane, OPCODE_COUNT_ADD, wide);
}

// the lane's close. A lane that ran every step has stored each record word as its last put wrote it, and returns. A
// lane errored leaves its record as its puts wrote it before it ended, as the interpreter does: errored at the open,
// every word the steps write is 0; errored at a step, it stores the words it holds in flight, their first put before
// that step and their last put that step or a later one. Every other word is already in the record, written or 0
CODEGEN_CORE void codegen_close(MachineFunction *lane, const unsigned int *errors)
{
    const IrProgram *const program = lane->program;
    codegen_instr0(lane, OPCODE_RETURN);
    codegen_instr0(lane, OPCODE_LABEL_ERROR_OPEN);
    codegen_count_error(lane);
    for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
    {
        if (program->put_last[word] != 0u)
        {
            codegen_instr2(lane, OPCODE_RECORD_STORE, codegen_number(4u * word), codegen_zero());
        }
    }
    codegen_instr0(lane, OPCODE_RETURN);
    for (unsigned int at = 0u; at < program->step_count; at += 1u)
    {
        if (errors[at] == 0u)
        {
            continue;
        }
        codegen_instr1(lane, OPCODE_LABEL_ERROR, codegen_number(at));
        codegen_count_error(lane);
        for (unsigned int word = 0u; word < program->out_limbs; word += 1u)
        {
            // put_last is 1 past the last put's step
            if ((program->put_last[word] > at) && (program->put_first[word] < at))
            {
                codegen_instr2(lane, OPCODE_RECORD_STORE, codegen_number(4u * word),
                               codegen_register(REGCLASS_OUT, word));
            }
        }
        codegen_instr0(lane, OPCODE_RETURN);
    }
}

// the body's opening: where it is split, the states it was split into, declared first; and the lane's end, its close
// and the program resident around it, the kernel or the circuit that runs a launch's lanes, which the assembly printer
// writes from the launch's layout (codegen_unit)
CODEGEN_CORE void codegen_body_open(MachineFunction *lane, int scheduled, unsigned int states)
{
    if (scheduled != 0)
    {
        codegen_instr1(lane, OPCODE_STATES_DECLARE, codegen_number(states));
    }
    codegen_instr0(lane, OPCODE_LANE_BODY);
}

CODEGEN_CORE void codegen_end(MachineFunction *lane)
{
    const MachineOperand none = codegen_zero();
    codegen_instr0(lane, OPCODE_LANE_CLOSE);
    codegen_instr(lane, OPCODE_PROGRAM_UNIT, PROGRAM_UNIT_PARAMETERS, none, none, none, none);
}

#endif
