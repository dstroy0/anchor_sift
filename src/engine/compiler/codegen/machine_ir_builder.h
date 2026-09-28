// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// machine_ir_builder.h: operands and instructions built (machine_ir.h includes the parts in order)
#ifndef MACHINE_IR_BUILDER_H
#define MACHINE_IR_BUILDER_H

#include "machine_ir_types.h"

// the arguments
CODEGEN_CORE MachineOperand codegen_register(unsigned int bank, unsigned int number)
{
    const MachineOperand argument = {OPERAND_REGISTER, bank, number};
    return argument;
}

// a word's value written into a form, as the ruleset's bank `immediate` writes a number: a language whose bare numbers
// are narrower than a word writes it as a word
CODEGEN_CORE MachineOperand codegen_immediate(unsigned int value)
{
    return codegen_register(REGCLASS_IMMEDIATE, value);
}

CODEGEN_CORE MachineOperand codegen_physreg(unsigned int fixed)
{
    const MachineOperand argument = {OPERAND_PHYSREG, fixed, 0u};
    return argument;
}

CODEGEN_CORE MachineOperand codegen_number(unsigned int value)
{
    const MachineOperand argument = {OPERAND_NUMBER, 0u, value};
    return argument;
}

// -1, the one negative number a form is written with, as its two's complement word
CODEGEN_CORE MachineOperand codegen_minus_one(void)
{
    const MachineOperand argument = {OPERAND_SIGNED, 0u, 0xFFFFFFFFu};
    return argument;
}

CODEGEN_CORE MachineOperand codegen_zero(void)
{
    return codegen_physreg(PHYSREG_ZERO);
}

CODEGEN_CORE MachineOperand codegen_file(unsigned int place)
{
    return codegen_register(REGCLASS_FILE, place);
}

CODEGEN_CORE MachineOperand codegen_sign(unsigned int place)
{
    return codegen_register(REGCLASS_SIGN, place);
}

// the ranges
CODEGEN_CORE MachineOperandRange codegen_range(MachineOperand first, unsigned int count, unsigned int width)
{
    const MachineOperandRange range = {first, (count < width) ? count : width, width};
    return range;
}

CODEGEN_CORE MachineOperand codegen_at(const MachineOperandRange &range, unsigned int at)
{
    MachineOperand element = range.first;
    element.number += at;
    return (at < range.count) ? element : codegen_zero();
}

// `width` of a range's elements from its element `low`
CODEGEN_CORE MachineOperandRange codegen_slice(const MachineOperandRange &range, unsigned int low, unsigned int width)
{
    const unsigned int count = (range.count > low) ? (range.count - low) : 0u;
    return codegen_range((count != 0u) ? codegen_at(range, low) : codegen_zero(), count, width);
}

// a register alone, and none at all as wide as `width`, which reads 0 throughout
CODEGEN_CORE MachineOperandRange codegen_one(MachineOperand argument)
{
    return codegen_range(argument, 1u, 1u);
}

CODEGEN_CORE MachineOperandRange codegen_none(unsigned int width)
{
    return codegen_range(codegen_zero(), 0u, width);
}

// a register's first `count` limbs at `place`, then the zero register up to `width`: a register read past its limbs
// reads 0
CODEGEN_CORE MachineOperandRange codegen_limbs(unsigned int place, unsigned int count, unsigned int width)
{
    return codegen_range(codegen_file(place), count, width);
}

// a form decided into the lane's sink, or counted where the sink holds none. A form the ruleset gives as a construct
// takes its scratch as the step's own temporaries, 64-bit temporaries and predicates, fresh for it, from where each
// bank stands, and declared with them; a construct that takes scratch of another bank breaks the lane
CODEGEN_CORE void codegen_instr(MachineFunction *lane, unsigned int form, unsigned int count, MachineOperand first,
                                MachineOperand second, MachineOperand third, MachineOperand fourth)
{
    if ((lane->items != NULL) && (lane->count < lane->capacity))
    {
        MachineInstr *const item = &lane->items[lane->count];
        item->form = form;
        item->count = count;
        item->arguments[0] = first;
        item->arguments[1] = second;
        item->arguments[2] = third;
        item->arguments[3] = fourth;
        item->scratch[0] = lane->temps;
        item->scratch[1] = lane->wides;
        item->scratch[2] = lane->predicates;
    }
    lane->count += 1ull;
    const unsigned int *const scratch = &lane->program->scratch[4u * form];
    lane->temps += scratch[0];
    lane->wides += scratch[1];
    lane->predicates += scratch[2];
    lane->broken = lane->broken | scratch[3];
    lane->temps_max = (lane->temps > lane->temps_max) ? lane->temps : lane->temps_max;
    lane->wides_max = (lane->wides > lane->wides_max) ? lane->wides : lane->wides_max;
    lane->predicates_max = (lane->predicates > lane->predicates_max) ? lane->predicates : lane->predicates_max;
}

CODEGEN_CORE void codegen_instr0(MachineFunction *lane, unsigned int form)
{
    const MachineOperand none = codegen_zero();
    codegen_instr(lane, form, 0u, none, none, none, none);
}

CODEGEN_CORE void codegen_instr1(MachineFunction *lane, unsigned int form, MachineOperand first)
{
    const MachineOperand none = codegen_zero();
    codegen_instr(lane, form, 1u, first, none, none, none);
}

CODEGEN_CORE void codegen_instr2(MachineFunction *lane, unsigned int form, MachineOperand first, MachineOperand second)
{
    const MachineOperand none = codegen_zero();
    codegen_instr(lane, form, 2u, first, second, none, none);
}

CODEGEN_CORE void codegen_instr3(MachineFunction *lane, unsigned int form, MachineOperand first, MachineOperand second,
                                 MachineOperand third)
{
    codegen_instr(lane, form, 3u, first, second, third, codegen_zero());
}

CODEGEN_CORE void codegen_instr4(MachineFunction *lane, unsigned int form, MachineOperand first, MachineOperand second,
                                 MachineOperand third, MachineOperand fourth)
{
    codegen_instr(lane, form, 4u, first, second, third, fourth);
}

// a form decided before into the lane's sink as it was, its scratch where it was taken
CODEGEN_CORE void codegen_take(MachineFunction *lane, const MachineInstr *item)
{
    if ((lane->items != NULL) && (lane->count < lane->capacity))
    {
        lane->items[lane->count] = *item;
    }
    lane->count += 1ull;
}

// the next of a bank's registers for the step, the most any step took kept for the lane to declare
CODEGEN_CORE MachineOperand codegen_temporary(MachineFunction *lane)
{
    const MachineOperand taken = codegen_register(REGCLASS_TEMPORARY, lane->temps);
    lane->temps += 1u;
    lane->temps_max = (lane->temps > lane->temps_max) ? lane->temps : lane->temps_max;
    return taken;
}

CODEGEN_CORE MachineOperandRange codegen_temporaries(MachineFunction *lane, unsigned int count)
{
    const MachineOperandRange taken = codegen_range(codegen_register(REGCLASS_TEMPORARY, lane->temps), count, count);
    lane->temps += count;
    lane->temps_max = (lane->temps > lane->temps_max) ? lane->temps : lane->temps_max;
    return taken;
}

CODEGEN_CORE MachineOperand codegen_wide(MachineFunction *lane)
{
    const MachineOperand taken = codegen_register(REGCLASS_WIDE, lane->wides);
    lane->wides += 1u;
    lane->wides_max = (lane->wides > lane->wides_max) ? lane->wides : lane->wides_max;
    return taken;
}

CODEGEN_CORE MachineOperand codegen_predicate(MachineFunction *lane)
{
    const MachineOperand taken = codegen_register(REGCLASS_PREDICATE, lane->predicates);
    lane->predicates += 1u;
    lane->predicates_max = (lane->predicates > lane->predicates_max) ? lane->predicates : lane->predicates_max;
    return taken;
}

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
CODEGEN_CORE int codegen_operand(const IrProgram *program, unsigned int at, unsigned int operand, unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= program->steps[operand].limbs);
}

// 1 where the operation reads a right register, and where it reads a left one: every one but the fields, the constant
// and the lane's number (ir_reads_right and ir_reads_left, target_parse.cu)
CODEGEN_CORE int codegen_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM) ||
           (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER) ||
           (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) ||
           (operation == ENGINE_RECORD_AND) || (operation == ENGINE_RECORD_QUOTIENT) ||
           (operation == ENGINE_RECORD_REMAINDER) || (operation == ENGINE_RECORD_GCD) ||
           (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

CODEGEN_CORE int codegen_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED) &&
           (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid out (ir_step_valid, target_parse.cu)
CODEGEN_CORE int codegen_step_valid(const IrProgram *program, unsigned int at)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    const int reads_left = codegen_reads_left(operation);
    const int reads_left_all = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at)) &&
           !(reads_left_all && !codegen_operand(program, at, step->left, step->left_limbs)) &&
           !(codegen_reads_right(operation) && !codegen_operand(program, at, step->right, step->right_limbs)) &&
           (((unsigned long long)step->place + step->limbs) <= (unsigned long long)program->file_limbs) &&
           (!field || (step->member < program->members)) &&
           ((operation != ENGINE_RECORD_FIELD_SIGNED) ||
            ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// the atom words a field step reads, [*low, *high) of its member's: each limb's word and, where the field is shifted
// within a word, the word after it, below the member's limbs; none for any other step or one the lane does not hold
CODEGEN_CORE void codegen_atom_words(const IrProgram *program, unsigned int at, unsigned int *low, unsigned int *high)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const int field = (step->operation == ENGINE_RECORD_FIELD) || (step->operation == ENGINE_RECORD_FIELD_SIGNED);
    *low = 0u;
    *high = 0u;
    if (!field || !codegen_step_valid(program, at))
    {
        return;
    }
    const unsigned long long first = step->left / 32u;
    const unsigned long long end = first + step->limbs + (((step->left % 32u) != 0u) ? 1u : 0u);
    const unsigned long long limbs = program->in_limbs[step->member];
    // clipped to the member's limbs, 32-bit counts
    *low = (unsigned int)((first < limbs) ? first : limbs);
    *high = (unsigned int)((end < limbs) ? end : limbs);
}

// the record words a step's put writes, [*low, *high): its out_bits' words from out_offset / 32, one more where the put
// is shifted within a word, and none at or past the record's limbs; empty for a step that puts nothing
CODEGEN_CORE void codegen_put_words(const IrProgram *program, const DeviceRecordStep *step, unsigned int *low,
                                    unsigned int *high)
{
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int first = step->out_offset / 32u;
    const unsigned long long words_end =
        (unsigned long long)first + words + (((step->out_offset % 32u) != 0u) ? 1u : 0u);
    // clipped to the record's limbs, a 32-bit count
    const unsigned int end = (unsigned int)((words_end < program->out_limbs) ? words_end : program->out_limbs);
    *low = (step->out_bits == 0u) ? 0u : ((first < end) ? first : end);
    *high = (step->out_bits == 0u) ? 0u : end;
}

// the loops step `at` writes, which the loop numbers each step begins at are the running sum of: the gcd's two, and one
// for the ladder, a division by more than one limb and a product too wide to unroll
CODEGEN_CORE unsigned int codegen_loops(const IrProgram *program, unsigned int at)
{
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER) ||
                        (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    const int wide_product = (operation == ENGINE_RECORD_PRODUCT) &&
                             (((unsigned long long)step->left_limbs * step->right_limbs) > CODEGEN_PRODUCT_MAX);
    return (operation == ENGINE_RECORD_GCD)
               ? 2u
               : (((divides && (step->right_limbs > 1u)) || (operation == ENGINE_RECORD_LADDER) || wide_product) ? 1u
                                                                                                                 : 0u);
}

// the resident's arguments in its parameters' order: the launch's size, and by their byte offsets its count, hot words,
// block, number, time to live and check-in, the hot words' next lane, start, thread blocks finished and check-ins, and
// the block's owner, command, state, offset, step, launch time, running time, check-in and check-in time; then the
// commands and states it reads and writes
CODEGEN_CORE unsigned long long codegen_unit(unsigned int at)
{
    const unsigned long long values[PROGRAM_UNIT_PARAMETERS] = {sizeof(CycleCompiledLaunch),
                                                                offsetof(CycleCompiledLaunch, count),
                                                                offsetof(CycleCompiledLaunch, hot),
                                                                offsetof(CycleCompiledLaunch, block),
                                                                offsetof(CycleCompiledLaunch, launch_number),
                                                                offsetof(CycleCompiledLaunch, ttl),
                                                                offsetof(CycleCompiledLaunch, checkin_every),
                                                                offsetof(CycleHot, next_lane),
                                                                offsetof(CycleHot, launch_start),
                                                                offsetof(CycleHot, finished),
                                                                offsetof(CycleHot, checkins),
                                                                offsetof(EngineProgramBlock, owner),
                                                                offsetof(EngineProgramBlock, command),
                                                                offsetof(EngineProgramBlock, state),
                                                                offsetof(EngineProgramBlock, offset),
                                                                offsetof(EngineProgramBlock, step),
                                                                offsetof(EngineProgramBlock, launch_time),
                                                                offsetof(EngineProgramBlock, exectime),
                                                                offsetof(EngineProgramBlock, checkin),
                                                                offsetof(EngineProgramBlock, checkin_time),
                                                                (unsigned long long)ENGINE_PROGRAM_RUN,
                                                                (unsigned long long)ENGINE_PROGRAM_STOP,
                                                                (unsigned long long)ENGINE_PROGRAM_DONE,
                                                                (unsigned long long)ENGINE_PROGRAM_STOPPED,
                                                                (unsigned long long)ENGINE_PROGRAM_YIELDED};
    return (at < PROGRAM_UNIT_PARAMETERS) ? values[at] : 0ull;
}

#endif
