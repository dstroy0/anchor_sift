// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// lowering_primitives.h: carry chains, negation, masks, selection, bits, fields and constants (lowering.h includes the
// parts in order)
#ifndef LOWERING_PRIMITIVES_H
#define LOWERING_PRIMITIVES_H

// Each record operation's forms: the carry chains, the selects and tests, and one function an operation, from a
// field to the ladder (codegen_core.h)

#include "machine_ir.h"

// the carry chains: the add chain, the subtract chain, and the subtract chain whose top limb leaves its borrow for
// codegen_borrowed to read
CODEGEN_CORE CarryChain codegen_add_chain(void)
{
    const CarryChain chain = {OPCODE_ADD_ALONE, OPCODE_ADD_FIRST, OPCODE_ADD_MIDDLE, OPCODE_ADD_LAST};
    return chain;
}

CODEGEN_CORE CarryChain codegen_subtract_chain(void)
{
    const CarryChain chain = {OPCODE_SUBTRACT_ALONE, OPCODE_SUBTRACT_FIRST, OPCODE_SUBTRACT_MIDDLE,
                              OPCODE_SUBTRACT_LAST};
    return chain;
}

CODEGEN_CORE CarryChain codegen_borrow_chain(void)
{
    const CarryChain chain = {OPCODE_BORROW_ALONE, OPCODE_BORROW_FIRST, OPCODE_BORROW_MIDDLE, OPCODE_BORROW_LAST};
    return chain;
}

// the lane leaves the step being decided refused where `refused` holds, for the store of the record words it has not
// stored yet: those whose last put is this step's or a later one's
CODEGEN_CORE void codegen_refuse(MachineFunction *lane, MachineOperand refused)
{
    lane->refuses = 1u;
    codegen_instr2(lane, OPCODE_REFUSE, refused, codegen_number(lane->at));
}

// one chain emitted through `limbs` limbs from the lowest: each limb of `to` is left's and right's by the chain's form
// for its place in the chain
CODEGEN_CORE void codegen_chain(MachineFunction *lane, CarryChain chain, const MachineOperandRange &to,
                                const MachineOperandRange &left, const MachineOperandRange &right, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned int form = (limbs == 1u)
                                      ? chain.alone
                                      : ((at == 0u) ? chain.first : ((at == (limbs - 1u)) ? chain.last : chain.middle));
        codegen_instr3(lane, form, codegen_at(to, at), codegen_at(left, at), codegen_at(right, at));
    }
}

// to = -from modulo 2^(32 limbs), the two's complement, as zero less the register
CODEGEN_CORE void codegen_negate(MachineFunction *lane, const MachineOperandRange &to, const MachineOperandRange &from,
                                 unsigned int limbs)
{
    codegen_chain(lane, codegen_subtract_chain(), to, codegen_none(limbs), from, limbs);
}

// a predicate set where the borrow chain just emitted borrowed past its top limb, read from the borrow it left
CODEGEN_CORE MachineOperand codegen_borrowed(MachineFunction *lane)
{
    const MachineOperand borrow = codegen_temporary(lane);
    const MachineOperand borrowed = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_BORROW_READ, borrow, borrowed);
    return borrowed;
}

// a limb kept to its low `kept` bits where kept is under 32; kept is reckoned as the interpreter reckons it, in 32
// bits, wrapping
CODEGEN_CORE void codegen_mask(MachineFunction *lane, MachineOperand limb, unsigned int kept)
{
    if (kept < 32u)
    {
        codegen_instr3(lane, OPCODE_WORD_AND, limb, limb, codegen_immediate((1u << kept) - 1u));
    }
}

// to = chosen where `where` holds, else otherwise, limb by limb
CODEGEN_CORE void codegen_select(MachineFunction *lane, const MachineOperandRange &to,
                                 const MachineOperandRange &chosen, const MachineOperandRange &otherwise,
                                 MachineOperand where, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        codegen_instr4(lane, OPCODE_WORD_SELECT, codegen_at(to, at), codegen_at(chosen, at), codegen_at(otherwise, at),
                       where);
    }
}

// a predicate set by `test`, TEST_NONZERO or TEST_ZERO, on the first `limbs` limbs or'd together
CODEGEN_CORE MachineOperand codegen_any(MachineFunction *lane, const MachineOperandRange &value, unsigned int limbs,
                                        unsigned int test)
{
    const MachineOperand predicate = codegen_predicate(lane);
    if (limbs == 1u)
    {
        codegen_instr2(lane, test, predicate, codegen_at(value, 0u));
        return predicate;
    }
    const MachineOperand any = codegen_temporary(lane);
    codegen_instr3(lane, OPCODE_WORD_OR, any, codegen_at(value, 0u), codegen_at(value, 1u));
    for (unsigned int at = 2u; at < limbs; at += 1u)
    {
        codegen_instr3(lane, OPCODE_WORD_OR, any, any, codegen_at(value, at));
    }
    codegen_instr2(lane, test, predicate, any);
    return predicate;
}

// a predicate set where any of the first `limbs` limbs is not zero, and one where every one of them is zero
CODEGEN_CORE MachineOperand codegen_nonzero(MachineFunction *lane, const MachineOperandRange &value, unsigned int limbs)
{
    return codegen_any(lane, value, limbs, OPCODE_TEST_NONZERO);
}

CODEGEN_CORE MachineOperand codegen_zeroed(MachineFunction *lane, const MachineOperandRange &value, unsigned int limbs)
{
    return codegen_any(lane, value, limbs, OPCODE_TEST_ZERO);
}

// a predicate set where bit `bit` of the register is 1
CODEGEN_CORE MachineOperand codegen_bit(MachineFunction *lane, const MachineOperandRange &value, unsigned int bit)
{
    const MachineOperand operand = codegen_temporary(lane);
    const MachineOperand set = codegen_predicate(lane);
    codegen_instr3(lane, OPCODE_WORD_AND, operand, codegen_at(value, bit / 32u), codegen_immediate(1u << (bit % 32u)));
    codegen_instr2(lane, OPCODE_TEST_NONZERO, set, operand);
    return set;
}

// the step's sign: `value`, a register or a number, where its register is not zero, and 0 where it is
CODEGEN_CORE void codegen_signed(MachineFunction *lane, const IrStep *at, MachineOperand value)
{
    const unsigned int limbs = at->step->limbs;
    const MachineOperand nonzero = codegen_nonzero(lane, codegen_limbs(at->place, limbs, limbs), limbs);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, codegen_sign(at->place), value, codegen_number(0u), nonzero);
}

// the step's sign as -1 where `negative` holds and 1 where not, and 0 where its register is zero
CODEGEN_CORE void codegen_signed_negative(MachineFunction *lane, const IrStep *at, MachineOperand negative)
{
    const MachineOperand operand = codegen_temporary(lane);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, operand, codegen_minus_one(), codegen_number(1u), negative);
    codegen_signed(lane, at, operand);
}

// word `word` of a member's atom, loaded at its first reader, and the zero register past the atom's limbs. The lane
// runs its steps in one straight line, which a refused lane leaves for good: every later reader follows the load. A
// field reads its words in order: a word the step has read already is below the one past the last it read
CODEGEN_CORE MachineOperand codegen_atom(MachineFunction *lane, unsigned int member, unsigned int word)
{
    const IrProgram *const program = lane->program;
    if (word >= program->in_limbs[member])
    {
        return codegen_zero();
    }
    const unsigned int at = program->atom_first[member] + word;
    const MachineOperand name = codegen_register(REGCLASS_ATOM, at);
    if ((program->atom_reader[at] == lane->at) && (at >= lane->atom_seen))
    {
        const MachineOperand address = codegen_register(REGCLASS_MEMBER, member);
        codegen_instr2(lane, OPCODE_GLOBAL_ASK, address, codegen_number(4u * word));
        codegen_instr3(lane, OPCODE_GLOBAL_LOAD, name, address, codegen_number(4u * word));
    }
    lane->atom_seen = (at >= lane->atom_seen) ? (at + 1u) : lane->atom_seen;
    return name;
}

// a field, unsigned or signed, gathered as cycle_record_field gathers it: each limb its two atom words funnel-shifted,
// masked to the bits left where fewer than 32 are. A signed field whose top bit is set is negated within its bits, the
// magnitude kept and the sign -1
CODEGEN_CORE void codegen_field(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->right;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = step->left + (32u * limb);
        const unsigned int shift = bit % 32u;
        const MachineOperand low = codegen_atom(lane, step->member, bit / 32u);
        if (shift == 0u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(value, limb), low);
        }
        else
        {
            const MachineOperand high = codegen_atom(lane, step->member, (bit / 32u) + 1u);
            codegen_instr4(lane, OPCODE_WORD_FUNNEL_RIGHT, codegen_at(value, limb), low, high, codegen_number(shift));
        }
        codegen_mask(lane, codegen_at(value, limb), bits - (32u * limb));
    }
    if (step->operation == ENGINE_RECORD_FIELD)
    {
        codegen_signed(lane, at, codegen_number(1u));
        return;
    }
    const MachineOperand negative = codegen_bit(lane, value, bits - 1u);
    const MachineOperandRange negated = codegen_temporaries(lane, limbs);
    codegen_negate(lane, negated, value, limbs);
    codegen_mask(lane, codegen_at(negated, limbs - 1u), bits - (32u * (limbs - 1u)));
    codegen_select(lane, value, negated, value, negative, limbs);
    codegen_signed_negative(lane, at, negative);
}

// a constant's two words, every limb above them cleared, its sign known as it is written
CODEGEN_CORE void codegen_constant(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        const unsigned int word = (limb == 0u) ? step->left : ((limb == 1u) ? step->right : 0u);
        codegen_instr2(lane, OPCODE_WORD_SET, codegen_file(at->place + limb), codegen_immediate(word));
    }
    const int nonzero = (step->left != 0u) || ((step->limbs > 1u) && (step->right != 0u));
    codegen_instr2(lane, OPCODE_SIGN_SET, codegen_sign(at->place), codegen_number(nonzero ? 1u : 0u));
}

// the lane's own number, its two words and every limb above them cleared; never negative
CODEGEN_CORE void codegen_own_number(MachineFunction *lane, const IrStep *at)
{
    const unsigned int limbs = at->step->limbs;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperand lane_number = codegen_physreg(PHYSREG_LANE_NUMBER);
    if (limbs == 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_FROM_WIDE, codegen_at(value, 0u), lane_number);
    }
    else
    {
        codegen_instr3(lane, OPCODE_WIDE_UNPACK, codegen_at(value, 0u), codegen_at(value, 1u), lane_number);
    }
    for (unsigned int limb = 2u; limb < limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(value, limb), codegen_number(0u));
    }
    const MachineOperand counted = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_WIDE_NONZERO, counted, lane_number);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, codegen_sign(at->place), codegen_number(1u), codegen_number(0u), counted);
}

// the magnitude, and a sign of 1 for any register not zero
CODEGEN_CORE void codegen_absolute(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const MachineOperandRange value = codegen_limbs(at->place, step->limbs, step->limbs);
    const MachineOperandRange left = codegen_limbs(at->left_place, step->left_limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(value, limb), codegen_at(left, limb));
    }
    codegen_instr2(lane, OPCODE_SIGN_ABSOLUTE, codegen_sign(at->place), codegen_sign(at->left_place));
}

// the order of two signed registers, as cycle_record_operate takes it: signs that differ order the registers alone,
// and signs that agree order them by their magnitudes, read from their difference's borrow and whether it is zero,
// times the sign. The order is the step's sign, and its low limb 1 where the registers differ
CODEGEN_CORE void codegen_compare(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const MachineOperandRange difference = codegen_temporaries(lane, width);
    codegen_chain(lane, codegen_borrow_chain(), difference, codegen_limbs(at->left_place, step->left_limbs, width),
                  codegen_limbs(at->right_place, step->right_limbs, width), width);
    const MachineOperand below = codegen_borrowed(lane);
    const MachineOperand differs = codegen_nonzero(lane, difference, width);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    const MachineOperand right_sign = codegen_sign(at->right_place);
    const MachineOperand sign = codegen_sign(at->place);
    const MachineOperand order = codegen_temporary(lane);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, order, codegen_minus_one(), codegen_number(1u), below);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, order, order, codegen_number(0u), differs);
    codegen_instr3(lane, OPCODE_SIGN_MULTIPLY, order, left_sign, order);
    const MachineOperand greater = codegen_predicate(lane);
    const MachineOperand apart = codegen_temporary(lane);
    codegen_instr3(lane, OPCODE_TEST_SIGNED_GREATER, greater, left_sign, right_sign);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, apart, codegen_number(1u), codegen_minus_one(), greater);
    const MachineOperand unlike = codegen_predicate(lane);
    codegen_instr3(lane, OPCODE_TEST_SIGNED_DIFFER, unlike, left_sign, right_sign);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, sign, apart, order, unlike);
    const MachineOperandRange value = codegen_limbs(at->place, step->limbs, step->limbs);
    codegen_instr2(lane, OPCODE_SIGN_ABSOLUTE, codegen_at(value, 0u), sign);
    for (unsigned int limb = 1u; limb < step->limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(value, limb), codegen_number(0u));
    }
}

// the sum or the difference of two signed registers, branch-free: the magnitudes' sum, their difference with its
// borrow, and that difference negated are all taken, and the signs choose among them as cycle_record_operate does.
// Signs that agree, or either one zero, add, and take the left's sign where it has one; signs that differ subtract the
// lesser magnitude from the greater, the borrow saying which is greater, and take the greater's sign
CODEGEN_CORE void codegen_sum(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const unsigned int range = (width > limbs) ? width : limbs;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    codegen_chain(lane, codegen_add_chain(), value, codegen_limbs(at->left_place, step->left_limbs, limbs),
                  codegen_limbs(at->right_place, step->right_limbs, limbs), limbs);
    // the difference runs over every limb either operand holds, and its borrow is their order
    const MachineOperandRange difference = codegen_temporaries(lane, range);
    codegen_chain(lane, codegen_borrow_chain(), difference, codegen_limbs(at->left_place, step->left_limbs, range),
                  codegen_limbs(at->right_place, step->right_limbs, range), range);
    const MachineOperand below = codegen_borrowed(lane);
    const MachineOperandRange negated = codegen_temporaries(lane, limbs);
    codegen_negate(lane, negated, difference, limbs);
    MachineOperand addend_sign = codegen_sign(at->right_place);
    if (step->operation == ENGINE_RECORD_DIFFERENCE)
    {
        const MachineOperand turned = codegen_temporary(lane);
        codegen_instr2(lane, OPCODE_SIGN_NEGATE, turned, addend_sign);
        addend_sign = turned;
    }
    const MachineOperand signs = codegen_temporary(lane);
    const MachineOperand opposed = codegen_predicate(lane);
    codegen_instr3(lane, OPCODE_SIGN_MULTIPLY, signs, left_sign, addend_sign);
    codegen_instr2(lane, OPCODE_TEST_NEGATIVE, opposed, signs);
    codegen_select(lane, difference, negated, difference, below, limbs);
    codegen_select(lane, value, difference, value, opposed, limbs);
    const MachineOperand greater = codegen_temporary(lane);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, greater, addend_sign, left_sign, below);
    const MachineOperand leads = codegen_predicate(lane);
    const MachineOperand kept = codegen_temporary(lane);
    codegen_instr3(lane, OPCODE_TEST_SIGNED_DIFFER, leads, left_sign, codegen_number(0u));
    codegen_instr4(lane, OPCODE_SIGN_SELECT, kept, left_sign, addend_sign, leads);
    codegen_instr4(lane, OPCODE_SIGN_SELECT, greater, greater, kept, opposed);
    codegen_signed(lane, at, greater);
}

// one schoolbook row: `value` += multiplier . right over value's `limbs`, each limb product a low and high pair on the
// carry with the row's carry added in, and the row's last carry run up the limbs above it. `carry` and `upper` are the
// row's two temporaries
CODEGEN_CORE void codegen_row(MachineFunction *lane, const MachineOperandRange &value, MachineOperand multiplier,
                              const MachineOperandRange &right, unsigned int limbs, MachineOperand carry,
                              MachineOperand upper)
{
    const MachineOperand zero = codegen_zero();
    const unsigned int right_limbs = right.width;
    for (unsigned int high = 0u; (high < right_limbs) && (high < limbs); high += 1u)
    {
        const MachineOperand to = codegen_at(value, high);
        codegen_instr4(lane, OPCODE_PRODUCT_LOW, to, multiplier, codegen_at(right, high), to);
        if (high == 0u)
        {
            codegen_instr3(lane, OPCODE_PRODUCT_HIGH, carry, multiplier, codegen_at(right, high));
        }
        else
        {
            codegen_instr3(lane, OPCODE_PRODUCT_HIGH, upper, multiplier, codegen_at(right, high));
            codegen_instr3(lane, OPCODE_ADD_FIRST, to, to, carry);
            codegen_instr3(lane, OPCODE_ADD_LAST, carry, upper, zero);
        }
    }
    if (right_limbs < limbs)
    {
        const unsigned int above = limbs - right_limbs;
        const MachineOperandRange run = codegen_slice(value, right_limbs, above);
        codegen_chain(lane, codegen_add_chain(), run, run, codegen_range(carry, 1u, above), above);
    }
}

// value = left . right truncated to value's limbs, cycle_record_product's schoolbook rows unrolled
CODEGEN_CORE void codegen_multiply(MachineFunction *lane, const MachineOperandRange &value,
                                   const MachineOperandRange &left, const MachineOperandRange &right)
{
    const unsigned int limbs = value.width;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(value, limb), codegen_number(0u));
    }
    const MachineOperand carry = codegen_temporary(lane);
    const MachineOperand upper = codegen_temporary(lane);
    for (unsigned int low = 0u; (low < left.width) && (low < limbs); low += 1u)
    {
        codegen_row(lane, codegen_slice(value, low, limbs - low), codegen_at(left, low), right, limbs - low, carry,
                    upper);
    }
}

// the loops a lane has written, each named by its number: a label, and a branch back to it where `where` holds
CODEGEN_CORE MachineOperand codegen_loop_open(MachineFunction *lane)
{
    const MachineOperand loop = codegen_number(lane->loops);
    lane->loops += 1u;
    codegen_instr1(lane, OPCODE_LOOP_LABEL, loop);
    return loop;
}

CODEGEN_CORE void codegen_loop_back(MachineFunction *lane, MachineOperand loop, MachineOperand where)
{
    codegen_instr2(lane, OPCODE_LOOP_BACK, loop, where);
}

// to = from shifted one bit toward the low end, the top limb's bit from 0; in place where to is from
CODEGEN_CORE void codegen_halve(MachineFunction *lane, const MachineOperandRange &to, const MachineOperandRange &from)
{
    const unsigned int limbs = to.width;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const MachineOperand high = ((at + 1u) < limbs) ? codegen_at(from, at + 1u) : codegen_zero();
        codegen_instr4(lane, OPCODE_WORD_FUNNEL_RIGHT, codegen_at(to, at), codegen_at(from, at), high,
                       codegen_number(1u));
    }
}

// to = from shifted one bit toward the high end, the low limb's bit from `below`'s top bit; in place where to is
// from, which the limbs taken from the top down allow
CODEGEN_CORE void codegen_double(MachineFunction *lane, const MachineOperandRange &to, const MachineOperandRange &from,
                                 MachineOperand below)
{
    const unsigned int limbs = to.width;
    for (unsigned int at = limbs; at > 0u; at -= 1u)
    {
        const MachineOperand low = (at > 1u) ? codegen_at(from, at - 2u) : below;
        codegen_instr4(lane, OPCODE_WORD_FUNNEL_RIGHT, codegen_at(to, at - 1u), low, codegen_at(from, at - 1u),
                       codegen_number(31u));
    }
}

#endif
