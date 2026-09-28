// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// lowering_operations.h: products, tables, bitwise, wrap, division, gcd and ladders (lowering.h includes the parts in
// order)
#ifndef LOWERING_OPERATIONS_H
#define LOWERING_OPERATIONS_H

#include "lowering_primitives.h"

// the product truncated to the step's limbs, the operands' signs multiplied as the interpreter takes it: unrolled up
// to CODEGEN_PRODUCT_MAX limb products, and past it a loop of one row a pass. The loop keeps the running sum's
// limbs from the row's own limb up. Each pass adds the left's lowest limb left times the right at the same
// registers, then shifts the sum and the left down a limb, the sum's lowest limb, which no later row reaches, going
// to the top of the product's low limbs as they shift down too
CODEGEN_CORE void codegen_product(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperandRange left = codegen_limbs(at->left_place, step->left_limbs, step->left_limbs);
    const MachineOperandRange right = codegen_limbs(at->right_place, step->right_limbs, step->right_limbs);
    if (((unsigned long long)step->left_limbs * step->right_limbs) <= CODEGEN_PRODUCT_MAX)
    {
        codegen_multiply(lane, value, left, right);
    }
    else
    {
        const MachineOperand zero = codegen_zero();
        const unsigned int rows = (step->left_limbs < limbs) ? step->left_limbs : limbs;
        const MachineOperandRange sum = codegen_temporaries(lane, limbs);
        const MachineOperandRange multiplier = codegen_temporaries(lane, rows);
        const MachineOperandRange low = codegen_temporaries(lane, rows);
        const MachineOperand count = codegen_temporary(lane);
        const MachineOperand carry = codegen_temporary(lane);
        const MachineOperand upper = codegen_temporary(lane);
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(sum, limb), codegen_number(0u));
        }
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(multiplier, limb), codegen_at(left, limb));
        }
        codegen_instr2(lane, OPCODE_WORD_SET, count, codegen_immediate(rows));
        const MachineOperand loop = codegen_loop_open(lane);
        codegen_row(lane, sum, codegen_at(multiplier, 0u), right, limbs, carry, upper);
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(low, limb),
                           ((limb + 1u) < rows) ? codegen_at(low, limb + 1u) : codegen_at(sum, 0u));
        }
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(sum, limb),
                           ((limb + 1u) < limbs) ? codegen_at(sum, limb + 1u) : zero);
        }
        for (unsigned int limb = 0u; limb < rows; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(multiplier, limb),
                           ((limb + 1u) < rows) ? codegen_at(multiplier, limb + 1u) : zero);
        }
        codegen_instr3(lane, OPCODE_SUBTRACT_ALONE, count, count, codegen_immediate(1u));
        const MachineOperand going = codegen_predicate(lane);
        codegen_instr2(lane, OPCODE_TEST_NONZERO, going, count);
        codegen_loop_back(lane, loop, going);
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(value, limb),
                           (limb < rows) ? codegen_at(low, limb) : codegen_at(sum, limb - rows));
        }
    }
    codegen_instr3(lane, OPCODE_SIGN_MULTIPLY, codegen_sign(at->place), codegen_sign(at->left_place),
                   codegen_sign(at->right_place));
}

// a table's row: the source's low index_bits select it, and its limbs are loaded from the program's tables at
// table_offset + index . limbs, reckoned in 32 bits as the interpreter reckons it
CODEGEN_CORE void codegen_table(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    lane->tables = 1u;
    const MachineOperand index = codegen_temporary(lane);
    const MachineOperand source = codegen_file(at->left_place);
    if (step->index_bits >= 32u)
    {
        codegen_instr2(lane, OPCODE_WORD_COPY, index, source);
    }
    else
    {
        codegen_instr3(lane, OPCODE_WORD_AND, index, source, codegen_immediate((1u << step->index_bits) - 1u));
    }
    codegen_instr3(lane, OPCODE_WORD_MULTIPLY, index, index, codegen_immediate(step->limbs));
    codegen_instr3(lane, OPCODE_ADD_ALONE, index, index, codegen_immediate(step->table_offset));
    const MachineOperand address = codegen_wide(lane);
    codegen_instr3(lane, OPCODE_WIDE_MULTIPLY_WORD, address, index, codegen_number(4u));
    codegen_instr3(lane, OPCODE_WIDE_ADD, address, codegen_physreg(PHYSREG_TABLES), address);
    const MachineOperandRange value = codegen_limbs(at->place, step->limbs, step->limbs);
    for (unsigned int limb = 0u; limb < step->limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_GLOBAL_ASK, address, codegen_number(4u * limb));
        codegen_instr3(lane, OPCODE_GLOBAL_LOAD, codegen_at(value, limb), address, codegen_number(4u * limb));
    }
    codegen_signed(lane, at, codegen_number(1u));
}

// the xor or the and of two registers' two's complements, each taken over the step's limbs by negating where its sign
// is negative, then read back as a magnitude: negated again where the result's sign is negative, the xor's where
// exactly one operand is and the and's where both are
CODEGEN_CORE void codegen_bitwise(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperand left_negative = codegen_predicate(lane);
    const MachineOperand right_negative = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_NEGATIVE, left_negative, codegen_sign(at->left_place));
    codegen_instr2(lane, OPCODE_TEST_NEGATIVE, right_negative, codegen_sign(at->right_place));
    const MachineOperandRange left = codegen_limbs(at->left_place, step->left_limbs, limbs);
    const MachineOperandRange right = codegen_limbs(at->right_place, step->right_limbs, limbs);
    const MachineOperandRange one = codegen_temporaries(lane, limbs);
    const MachineOperandRange other = codegen_temporaries(lane, limbs);
    codegen_negate(lane, one, left, limbs);
    codegen_select(lane, one, one, left, left_negative, limbs);
    codegen_negate(lane, other, right, limbs);
    codegen_select(lane, other, other, right, right_negative, limbs);
    const int exclusive = (step->operation == ENGINE_RECORD_XOR);
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        codegen_instr3(lane, (exclusive != 0) ? OPCODE_WORD_XOR : OPCODE_WORD_AND, codegen_at(value, limb),
                       codegen_at(one, limb), codegen_at(other, limb));
    }
    const MachineOperand negative = codegen_predicate(lane);
    codegen_instr3(lane, (exclusive != 0) ? OPCODE_PREDICATE_XOR : OPCODE_PREDICATE_AND, negative, left_negative,
                   right_negative);
    const MachineOperandRange negated = codegen_temporaries(lane, limbs);
    codegen_negate(lane, negated, value, limbs);
    codegen_select(lane, value, negated, value, negative, limbs);
    codegen_signed_negative(lane, at, negative);
}

// the left register wrapped to wrap_bits of two's complement and read back signed, as cycle_record_wrap wraps it: a
// wrap wider than the step's limbs passes the register through, and any other takes its two's complement over the
// limbs, keeps the wrap's bits, and negates within them where the top one is set
CODEGEN_CORE void codegen_wrap(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int limbs = step->limbs;
    const unsigned int bits = step->wrap_bits;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperandRange left = codegen_limbs(at->left_place, step->left_limbs, limbs);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    if (bits > (32u * limbs))
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(value, limb), codegen_at(left, limb));
        }
        codegen_instr2(lane, OPCODE_WORD_COPY, codegen_sign(at->place), left_sign);
        return;
    }
    const MachineOperand left_negative = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_NEGATIVE, left_negative, left_sign);
    const MachineOperandRange complement = codegen_temporaries(lane, limbs);
    codegen_negate(lane, complement, left, limbs);
    codegen_select(lane, value, complement, left, left_negative, limbs);
    const unsigned int kept = bits - (32u * (limbs - 1u));
    codegen_mask(lane, codegen_at(value, limbs - 1u), kept);
    const MachineOperand negative = codegen_bit(lane, value, bits - 1u);
    const MachineOperandRange negated = codegen_temporaries(lane, limbs);
    codegen_negate(lane, negated, value, limbs);
    codegen_mask(lane, codegen_at(negated, limbs - 1u), kept);
    codegen_select(lane, value, negated, value, negative, limbs);
    codegen_signed_negative(lane, at, negative);
}

// a division by a divisor of one limb, cycle_record_divide's one-limb long division unrolled from the numerator's top
// limb down: each limb's quotient word by div, and the carried remainder the limb less the quotient word times the
// divisor, which is exact in 32 bits since it is below the divisor. The numerator's zero limbs above its used ones
// divide to zero and carry nothing, as the interpreter's skipping them does. A zero divisor refuses the lane; an exact
// quotient refuses a remainder and a quotient that outgrows its register, as the inverse's multiply back does. The
// quotient's words are the step's own limbs where the step keeps them, below `kept`, and its own temporaries above
CODEGEN_CORE void codegen_short_division(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperand divisor = codegen_file(at->right_place);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    const MachineOperand nothing = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_ZERO, nothing, divisor);
    codegen_refuse(lane, nothing);
    const MachineOperand carried = codegen_temporary(lane);
    const MachineOperand taken = codegen_temporary(lane);
    const MachineOperand wide_divisor = codegen_wide(lane);
    const MachineOperand part = codegen_wide(lane);
    const unsigned int kept = (operation == ENGINE_RECORD_REMAINDER) ? 0u : ((limbs < left_limbs) ? limbs : left_limbs);
    const MachineOperandRange above = codegen_temporaries(lane, left_limbs - kept);
    codegen_instr2(lane, OPCODE_WIDE_FROM_WORD, wide_divisor, divisor);
    for (unsigned int word = left_limbs; word > 0u; word -= 1u)
    {
        const MachineOperand numerator = codegen_file(at->left_place + word - 1u);
        const MachineOperand quotient_word =
            ((word - 1u) < kept) ? codegen_at(value, word - 1u) : codegen_at(above, (word - 1u) - kept);
        if (word == left_limbs)
        {
            // nothing is carried into the top limb, and its word divides alone
            codegen_instr3(lane, OPCODE_WORD_DIVIDE, quotient_word, numerator, divisor);
        }
        else
        {
            codegen_instr3(lane, OPCODE_WIDE_PACK, part, numerator, carried);
            codegen_instr3(lane, OPCODE_WIDE_DIVIDE, part, part, wide_divisor);
            codegen_instr2(lane, OPCODE_WORD_FROM_WIDE, quotient_word, part);
        }
        codegen_instr3(lane, OPCODE_WORD_MULTIPLY, taken, quotient_word, divisor);
        codegen_instr3(lane, OPCODE_SUBTRACT_ALONE, carried, numerator, taken);
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(value, 0u), carried);
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(value, limb), codegen_number(0u));
        }
        codegen_signed(lane, at, left_sign);
        return;
    }
    for (unsigned int limb = left_limbs; limb < limbs; limb += 1u)
    {
        codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(value, limb), codegen_number(0u));
    }
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        const MachineOperand remains = codegen_predicate(lane);
        codegen_instr2(lane, OPCODE_TEST_NONZERO, remains, carried);
        codegen_refuse(lane, remains);
        if (left_limbs > limbs)
        {
            // the words past the step's limbs are the temporaries above it, every one
            codegen_refuse(lane, codegen_nonzero(lane, above, left_limbs - limbs));
        }
    }
    const MachineOperand operand = codegen_temporary(lane);
    codegen_instr3(lane, OPCODE_SIGN_MULTIPLY, operand, left_sign, codegen_sign(at->right_place));
    codegen_signed(lane, at, operand);
}

// to[k] = from[k] for the limbs from spans and 0 above them
CODEGEN_CORE void codegen_copy_out(MachineFunction *lane, const MachineOperandRange &to,
                                   const MachineOperandRange &from)
{
    for (unsigned int limb = 0u; limb < to.width; limb += 1u)
    {
        if (limb < from.width)
        {
            codegen_instr2(lane, OPCODE_WORD_COPY, codegen_at(to, limb), codegen_at(from, limb));
        }
        else
        {
            codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(to, limb), codegen_number(0u));
        }
    }
}

// a division by a divisor of more than one limb, the magnitudes' long division a bit a pass as a divider in
// hardware does it: the numerator's limbs, which become the quotient, and a rest one limb wider than the divisor are
// shifted up a bit together; the divisor is taken from the rest where it does not borrow, and the quotient's new low
// bit is 1 where it was. After 32 passes a numerator limb, the quotient and the rest are cycle_record_divide's. A zero
// divisor refuses the lane; an exact quotient refuses a rest and a quotient that outgrows its register, as the
// inverse's multiply back does
CODEGEN_CORE void codegen_long_division(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int operation = step->operation;
    const unsigned int limbs = step->limbs;
    const unsigned int left_limbs = step->left_limbs;
    const unsigned int right_limbs = step->right_limbs;
    const MachineOperand zero = codegen_zero();
    const MachineOperandRange value = codegen_limbs(at->place, limbs, limbs);
    const MachineOperandRange divisor = codegen_limbs(at->right_place, right_limbs, right_limbs + 1u);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    codegen_refuse(lane, codegen_zeroed(lane, divisor, right_limbs));
    const MachineOperandRange quotient = codegen_temporaries(lane, left_limbs);
    const MachineOperandRange rest = codegen_temporaries(lane, right_limbs + 1u);
    const MachineOperandRange taken = codegen_temporaries(lane, right_limbs + 1u);
    const MachineOperand count = codegen_temporary(lane);
    const MachineOperand bit = codegen_temporary(lane);
    codegen_copy_out(lane, quotient, codegen_limbs(at->left_place, left_limbs, left_limbs));
    codegen_copy_out(lane, rest, codegen_none(0u));
    codegen_instr2(lane, OPCODE_WORD_SET, count, codegen_immediate(32u * left_limbs));
    const MachineOperand loop = codegen_loop_open(lane);
    codegen_double(lane, rest, rest, codegen_at(quotient, left_limbs - 1u));
    codegen_double(lane, quotient, quotient, zero);
    codegen_chain(lane, codegen_borrow_chain(), taken, rest, divisor, right_limbs + 1u);
    const MachineOperand below = codegen_borrowed(lane);
    codegen_select(lane, rest, rest, taken, below, right_limbs + 1u);
    codegen_instr4(lane, OPCODE_WORD_SELECT, bit, zero, codegen_immediate(1u), below);
    codegen_instr3(lane, OPCODE_WORD_OR, codegen_at(quotient, 0u), codegen_at(quotient, 0u), bit);
    codegen_instr3(lane, OPCODE_SUBTRACT_ALONE, count, count, codegen_immediate(1u));
    const MachineOperand going = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_NONZERO, going, count);
    codegen_loop_back(lane, loop, going);
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        codegen_copy_out(lane, value, codegen_slice(rest, 0u, right_limbs));
        codegen_signed(lane, at, left_sign);
        return;
    }
    codegen_copy_out(lane, value, (left_limbs > limbs) ? codegen_slice(quotient, 0u, limbs) : quotient);
    if (operation == ENGINE_RECORD_EXACT_QUOTIENT)
    {
        codegen_refuse(lane, codegen_nonzero(lane, rest, right_limbs));
        if (left_limbs > limbs)
        {
            codegen_refuse(
                lane, codegen_nonzero(lane, codegen_slice(quotient, limbs, left_limbs - limbs), left_limbs - limbs));
        }
    }
    const MachineOperand operand = codegen_temporary(lane);
    codegen_instr3(lane, OPCODE_SIGN_MULTIPLY, operand, left_sign, codegen_sign(at->right_place));
    codegen_signed(lane, at, operand);
}

// the gcd of the magnitudes, Stein's binary gcd, which is Euclid's gcd since the gcd is one number. While neither is
// zero, a pass halves each even one, takes the lesser from the greater and halves the difference where both are odd,
// and counts the twos both shared; the one left not zero is then shifted up by the shared twos, a bit a pass. Each
// pass is emitted whole and taken only where its predicate holds: a loop the lane leaves at once changes nothing
CODEGEN_CORE void codegen_gcd(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int width = (step->left_limbs > step->right_limbs) ? step->left_limbs : step->right_limbs;
    const MachineOperand zero = codegen_zero();
    const MachineOperand one = codegen_immediate(1u);
    const MachineOperandRange left = codegen_temporaries(lane, width);
    const MachineOperandRange right = codegen_temporaries(lane, width);
    const MachineOperandRange difference = codegen_temporaries(lane, width);
    const MachineOperandRange turned = codegen_temporaries(lane, width);
    const MachineOperandRange left_half = codegen_temporaries(lane, width);
    const MachineOperandRange right_half = codegen_temporaries(lane, width);
    const MachineOperandRange difference_half = codegen_temporaries(lane, width);
    const MachineOperandRange turned_half = codegen_temporaries(lane, width);
    const MachineOperandRange chosen = codegen_temporaries(lane, width);
    const MachineOperand twos = codegen_temporary(lane);
    const MachineOperand counted = codegen_temporary(lane);
    const MachineOperand left_odd = codegen_temporary(lane);
    const MachineOperand right_odd = codegen_temporary(lane);
    const MachineOperand odd = codegen_temporary(lane);
    codegen_copy_out(lane, left, codegen_limbs(at->left_place, step->left_limbs, step->left_limbs));
    codegen_copy_out(lane, right, codegen_limbs(at->right_place, step->right_limbs, step->right_limbs));
    codegen_instr2(lane, OPCODE_WORD_SET, twos, codegen_number(0u));
    const MachineOperand halving = codegen_loop_open(lane);
    const MachineOperand going = codegen_predicate(lane);
    // the two tests are taken in the order a call's arguments were, the left's first
    const MachineOperand left_going = codegen_nonzero(lane, left, width);
    const MachineOperand right_going = codegen_nonzero(lane, right, width);
    codegen_instr3(lane, OPCODE_PREDICATE_AND, going, left_going, right_going);
    codegen_instr3(lane, OPCODE_WORD_AND, left_odd, codegen_at(left, 0u), one);
    codegen_instr3(lane, OPCODE_WORD_AND, right_odd, codegen_at(right, 0u), one);
    const MachineOperand left_even = codegen_predicate(lane);
    const MachineOperand right_even = codegen_predicate(lane);
    const MachineOperand both_odd = codegen_predicate(lane);
    const MachineOperand both_even = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_ZERO, left_even, left_odd);
    codegen_instr2(lane, OPCODE_TEST_ZERO, right_even, right_odd);
    codegen_instr3(lane, OPCODE_WORD_AND, odd, left_odd, right_odd);
    codegen_instr2(lane, OPCODE_TEST_NONZERO, both_odd, odd);
    codegen_instr3(lane, OPCODE_WORD_OR, odd, left_odd, right_odd);
    codegen_instr2(lane, OPCODE_TEST_ZERO, both_even, odd);
    codegen_chain(lane, codegen_borrow_chain(), difference, left, right, width);
    const MachineOperand below = codegen_borrowed(lane);
    codegen_negate(lane, turned, difference, width);
    codegen_halve(lane, left_half, left);
    codegen_halve(lane, right_half, right);
    codegen_halve(lane, difference_half, difference);
    codegen_halve(lane, turned_half, turned);
    // the left: halved where even, else the halved difference where both are odd and it is not below, else itself
    codegen_select(lane, chosen, left, difference_half, below, width);
    codegen_select(lane, chosen, chosen, left, both_odd, width);
    codegen_select(lane, chosen, left_half, chosen, left_even, width);
    codegen_select(lane, left, chosen, left, going, width);
    // the right: halved where even, else the halved difference turned where both are odd and the left is below
    codegen_select(lane, chosen, turned_half, right, below, width);
    codegen_select(lane, chosen, chosen, right, both_odd, width);
    codegen_select(lane, chosen, right_half, chosen, right_even, width);
    codegen_select(lane, right, chosen, right, going, width);
    codegen_instr3(lane, OPCODE_ADD_ALONE, counted, twos, one);
    codegen_instr4(lane, OPCODE_WORD_SELECT, counted, counted, twos, both_even);
    codegen_instr4(lane, OPCODE_WORD_SELECT, twos, counted, twos, going);
    codegen_loop_back(lane, halving, going);
    // one of the two is zero, and the other is their or
    for (unsigned int limb = 0u; limb < width; limb += 1u)
    {
        codegen_instr3(lane, OPCODE_WORD_OR, codegen_at(left, limb), codegen_at(left, limb), codegen_at(right, limb));
    }
    const MachineOperand doubling = codegen_loop_open(lane);
    const MachineOperand shifting = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_NONZERO, shifting, twos);
    codegen_double(lane, left_half, left, zero);
    codegen_select(lane, left, left_half, left, shifting, width);
    codegen_instr3(lane, OPCODE_SUBTRACT_ALONE, counted, twos, one);
    codegen_instr4(lane, OPCODE_WORD_SELECT, twos, counted, twos, shifting);
    codegen_loop_back(lane, doubling, shifting);
    codegen_copy_out(lane, codegen_limbs(at->place, step->limbs, step->limbs),
                     (width > step->limbs) ? codegen_slice(left, 0u, step->limbs) : left);
    codegen_signed(lane, at, codegen_number(1u));
}

// the golden ladder's band, as cycle_record_ladder counts it: a right that is not positive refuses the lane; else
// each pass multiplies the right by the next Fibonacci number and counts the rung where the multiple stays at or below
// the left's magnitude, until one does not or the rungs run out. The pass is taken only while the ladder climbs. The
// band is the register's low limb, its sign the left's
CODEGEN_CORE void codegen_ladder(MachineFunction *lane, const IrStep *at)
{
    const DeviceRecordStep *const step = at->step;
    const unsigned int right_limbs = step->right_limbs;
    const unsigned int range = right_limbs + 2u;
    const unsigned int width = (step->left_limbs > range) ? step->left_limbs : range;
    const MachineOperand zero = codegen_zero();
    const MachineOperand one = codegen_immediate(1u);
    const MachineOperand left_sign = codegen_sign(at->left_place);
    // the right's sign less 1 is negative where the sign is not positive
    const MachineOperand lessened = codegen_temporary(lane);
    const MachineOperand not_positive = codegen_predicate(lane);
    codegen_instr3(lane, OPCODE_SUBTRACT_ALONE, lessened, codegen_sign(at->right_place), one);
    codegen_instr2(lane, OPCODE_TEST_NEGATIVE, not_positive, lessened);
    codegen_refuse(lane, not_positive);
    const MachineOperandRange fibonacci_lower = codegen_temporaries(lane, 2u);
    const MachineOperandRange fibonacci_upper = codegen_temporaries(lane, 2u);
    const MachineOperandRange fibonacci_next = codegen_temporaries(lane, 2u);
    const MachineOperandRange reached = codegen_temporaries(lane, range);
    const MachineOperandRange difference = codegen_temporaries(lane, width);
    const MachineOperand band = codegen_temporary(lane);
    const MachineOperand rung = codegen_temporary(lane);
    const MachineOperand climbing = codegen_temporary(lane);
    const MachineOperand counted = codegen_temporary(lane);
    const MachineOperand moved = codegen_temporary(lane);
    codegen_copy_out(lane, fibonacci_lower, codegen_none(0u));
    codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(fibonacci_upper, 0u), one);
    codegen_instr2(lane, OPCODE_WORD_SET, codegen_at(fibonacci_upper, 1u), codegen_number(0u));
    codegen_instr2(lane, OPCODE_WORD_SET, band, codegen_number(0u));
    codegen_instr2(lane, OPCODE_WORD_SET, rung, one);
    codegen_instr2(lane, OPCODE_WORD_SET, climbing, one);
    const MachineOperand loop = codegen_loop_open(lane);
    const MachineOperand going = codegen_predicate(lane);
    codegen_instr2(lane, OPCODE_TEST_NONZERO, going, climbing);
    codegen_multiply(lane, reached, codegen_limbs(at->right_place, right_limbs, right_limbs), fibonacci_upper);
    codegen_chain(lane, codegen_borrow_chain(), difference, codegen_limbs(at->left_place, step->left_limbs, width),
                  codegen_range(reached.first, range, width), width);
    const MachineOperand over = codegen_borrowed(lane);
    codegen_instr4(lane, OPCODE_WORD_SELECT, counted, zero, one, over);
    codegen_instr3(lane, OPCODE_ADD_ALONE, moved, band, counted);
    codegen_instr4(lane, OPCODE_WORD_SELECT, band, moved, band, going);
    codegen_chain(lane, codegen_add_chain(), fibonacci_next, fibonacci_lower, fibonacci_upper, 2u);
    codegen_select(lane, fibonacci_lower, fibonacci_upper, fibonacci_lower, going, 2u);
    codegen_select(lane, fibonacci_upper, fibonacci_next, fibonacci_upper, going, 2u);
    codegen_instr3(lane, OPCODE_ADD_ALONE, moved, rung, one);
    codegen_instr4(lane, OPCODE_WORD_SELECT, rung, moved, rung, going);
    // the ladder climbs on where this rung counted and the next is still below ENGINE_GOLDEN_RUNGS
    codegen_chain(lane, codegen_borrow_chain(), codegen_one(moved), codegen_one(rung),
                  codegen_one(codegen_immediate(ENGINE_GOLDEN_RUNGS)), 1u);
    const MachineOperand within = codegen_borrowed(lane);
    codegen_instr4(lane, OPCODE_WORD_SELECT, moved, counted, zero, within);
    codegen_instr4(lane, OPCODE_WORD_SELECT, climbing, moved, climbing, going);
    codegen_loop_back(lane, loop, going);
    codegen_copy_out(lane, codegen_limbs(at->place, step->limbs, step->limbs), codegen_one(band));
    codegen_signed(lane, at, left_sign);
}

#endif
