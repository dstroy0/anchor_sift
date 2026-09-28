// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef INSTRUCTION_SELECTION_H
#define INSTRUCTION_SELECTION_H

// A step's forms: its operation's, and its put's into the record (codegen_core.h)

#include "lowering.h"

// 1 where an operation's register is never negative: its put needs no two's complement
CODEGEN_CORE int codegen_never_negative(unsigned int operation)
{
    return (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT) ||
           (operation == ENGINE_RECORD_LANE) || (operation == ENGINE_RECORD_ABSOLUTE) ||
           (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_GCD);
}

// each record word stored as the last put that lays it out ends; the lane does not hold it to its end
CODEGEN_CORE void codegen_store_placed(MachineFunction *lane, const DeviceRecordStep *step)
{
    unsigned int low = 0u;
    unsigned int high = 0u;
    codegen_put_words(lane->program, step, &low, &high);
    for (unsigned int word = low; word < high; word += 1u)
    {
        if (lane->program->put_last[word] == (lane->at + 1u))
        {
            codegen_instr2(lane, OPCODE_RECORD_STORE, codegen_number(4u * word), codegen_register(REGCLASS_OUT, word));
        }
    }
}

// the step's register written into the record's words at out_offset, out_bits of it, as two's complement where its sign
// is negative, as cycle_put writes it; each word is the lane's own register until its last put
CODEGEN_CORE void codegen_put(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int words = (step->out_bits + 31u) / 32u;
    const unsigned int top = step->out_bits - (32u * (words - 1u));
    const unsigned int first = step->out_offset / 32u;
    const unsigned int shift = step->out_offset % 32u;
    const unsigned int out_limbs = lane->program->out_limbs;
    const MachineOperandRange source = codegen_limbs(at->place, step->limbs, words);
    const MachineOperandRange word = codegen_temporaries(lane, words);
    if (codegen_never_negative(step->operation) != 0)
    {
        for (unsigned int each = 0u; each < words; each += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(word, each), codegen_at(source, each));
        }
    }
    else
    {
        const MachineOperand negative = codegen_predicate(lane);
        codegen_instr2(lane, OPCODE_TEST_NEGATIVE, negative, codegen_sign(at->place));
        const MachineOperandRange negated = codegen_temporaries(lane, words);
        codegen_negate(lane, negated, source, words);
        codegen_select(lane, word, negated, source, negative, words);
    }
    codegen_mask(lane, codegen_at(word, words - 1u), top);
    unsigned int low_word = 0u;
    unsigned int high_word = 0u;
    codegen_put_words(lane->program, step, &low_word, &high_word);
    for (unsigned int word_at = low_word; word_at < high_word; word_at += 1u)
    {
        if (lane->program->put_first[word_at] == lane->at)
        {
            // the word's first put: its register begins here, cleared, and not at the lane's open
            codegen_instr2(lane, OPCODE_WORD_SET, codegen_register(REGCLASS_OUT, word_at), codegen_number(0u));
        }
    }
    const MachineOperand moved = codegen_temporary(lane);
    for (unsigned int each = 0u; each < words; each += 1u)
    {
        const unsigned int low = first + each;
        if ((low < out_limbs) && (shift == 0u))
        {
            const MachineOperand record = codegen_register(REGCLASS_OUT, low);
            codegen_instr3(lane, OPCODE_WORD_OR, record, record, codegen_at(word, each));
        }
        else if (low < out_limbs)
        {
            const MachineOperand record = codegen_register(REGCLASS_OUT, low);
            codegen_instr3(lane, OPCODE_WORD_SHIFT_LEFT, moved, codegen_at(word, each), codegen_number(shift));
            codegen_instr3(lane, OPCODE_WORD_OR, record, record, moved);
        }
        if ((shift != 0u) && ((low + 1u) < out_limbs))
        {
            const MachineOperand record = codegen_register(REGCLASS_OUT, low + 1u);
            codegen_instr3(lane, OPCODE_WORD_SHIFT_RIGHT, moved, codegen_at(word, each), codegen_number(32u - shift));
            codegen_instr3(lane, OPCODE_WORD_OR, record, record, moved);
        }
    }
}

// one step of the lane and its put, from the loop number the step begins at, which lane->loops holds; 0 for a step the
// lane does not hold, which leaves the program to the C source. The step's temporaries, 64-bit temporaries and
// predicates are its own from 0: what it took is lane->temps and lane->wides after it; lane->refuses is 1 where it
// can leave the lane refused
CODEGEN_CORE int codegen_step(MachineFunction *lane, unsigned int at)
{
    const IrProgram *const program = lane->program;
    const DeviceRecordStep *const step = &program->steps[at];
    const unsigned int operation = step->operation;
    // a wrap of no bits has no top bit to read
    if (!codegen_step_valid(program, at) || ((operation == ENGINE_RECORD_WRAP) && (step->wrap_bits == 0u)))
    {
        return 0;
    }
    IrStep view;
    view.step = step;
    view.place = step->place;
    view.left_place = codegen_reads_left(operation) ? program->steps[step->left].place : 0u;
    view.right_place = codegen_reads_right(operation) ? program->steps[step->right].place : 0u;
    lane->at = at;
    lane->temps = 0u;
    lane->wides = 0u;
    lane->predicates = 0u;
    lane->refuses = 0u;
    lane->atom_seen = 0u;
    codegen_instr2(lane, OPCODE_STEP_NOTE, codegen_number(at), codegen_number(operation));
    const int divides = (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER) ||
                        (operation == ENGINE_RECORD_EXACT_QUOTIENT);
    if (divides && (step->right_limbs > 1u))
    {
        codegen_long_division(lane, &view);
    }
    else if (operation == ENGINE_RECORD_GCD)
    {
        codegen_gcd(lane, &view);
    }
    else if (operation == ENGINE_RECORD_LADDER)
    {
        codegen_ladder(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        codegen_field(lane, &view);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        codegen_constant(lane, &view);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        codegen_own_number(lane, &view);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        codegen_absolute(lane, &view);
    }
    else if (operation == ENGINE_RECORD_COMPARE)
    {
        codegen_compare(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE))
    {
        codegen_sum(lane, &view);
    }
    else if (operation == ENGINE_RECORD_PRODUCT)
    {
        codegen_product(lane, &view);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        codegen_table(lane, &view);
    }
    else if ((operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        codegen_bitwise(lane, &view);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        codegen_wrap(lane, &view);
    }
    else if (divides)
    {
        codegen_short_division(lane, &view);
    }
    else
    {
        // an operation this lane does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        codegen_put(lane, &view);
        codegen_store_placed(lane, step);
    }
    return 1;
}

#endif
