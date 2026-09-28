// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_record_operate.h: gcd, exact quotient, and one record step operated on the device (included by
// cycle_record_internal.h)
#ifndef CYCLE_RECORD_OPERATE_H
#define CYCLE_RECORD_OPERATE_H

// Euclid's gcd of the magnitudes by the long division above, into `limbs` of value; scratch holds 5 * WIDE + 2
template <unsigned int WIDE>
__device__ static void cycle_record_gcd(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                        unsigned int right_limbs, unsigned int *value, unsigned int limbs,
                                        unsigned int *scratch)
{
    unsigned int *larger = scratch;
    unsigned int *smaller = &scratch[WIDE];
    unsigned int *rest = &scratch[2u * WIDE];
    for (unsigned int at = 0u; at < WIDE; at += 1u)
    {
        larger[at] = cycle_record_limb(left, left_limbs, at);
        smaller[at] = cycle_record_limb(right, right_limbs, at);
    }
    while (cycle_record_used(smaller, WIDE) != 0u)
    {
        cycle_record_divide<WIDE>(larger, WIDE, smaller, WIDE, NULL, 0u, rest, WIDE, &scratch[3u * WIDE]);
        unsigned int *const temporary = larger;
        larger = smaller;
        smaller = rest;
        rest = temporary;
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = larger[at];
    }
}

// the quotient of an exact division by a multiply with the divisor's inverse and a mask: both are shifted past the
// divisor's low zero bits, the odd divisor's inverse modulo 2^(32 limbs) is grown by Newton's x(2 - dx) from one
// word, and the quotient is the low limbs of numerator . inverse; multiplying back proves it. 0 for a zero divisor or
// a remainder. scratch holds 5 * WIDE limbs.
template <unsigned int WIDE>
__device__ static int cycle_record_exact_quotient(const unsigned int *top, unsigned int top_limbs,
                                                  const unsigned int *bottom, unsigned int bottom_limbs,
                                                  unsigned int *value, unsigned int limbs, unsigned int *scratch)
{
    const unsigned int divisor_used = cycle_record_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = 0u;
    }
    if (cycle_record_used(top, top_limbs) == 0u)
    {
        return 1;
    }
    unsigned int low_zeros = 0u;
    while (bottom[low_zeros / 32u] == 0u)
    {
        low_zeros += 32u;
    }
    low_zeros += (unsigned int)(__ffs((int)bottom[low_zeros / 32u]) - 1);
    for (unsigned int bit = 0u; bit < low_zeros; bit += 1u)
    {
        if (((cycle_record_limb(top, top_limbs, bit / 32u) >> (bit % 32u)) & 1u) != 0u)
        {
            return 0;
        }
    }
    unsigned int *const numerator = scratch;
    unsigned int *const divisor = &scratch[WIDE];
    unsigned int *const inverse = &scratch[2u * WIDE];
    unsigned int *const stepped = &scratch[3u * WIDE];
    unsigned int *const grown = &scratch[4u * WIDE];
    // the work runs at the numerator's width: a quotient by a constant can be narrower than its numerator, and the
    // multiply back must see the numerator whole
    const unsigned int work = (top_limbs > limbs) ? top_limbs : limbs;
    cycle_record_shift_down(top, top_limbs, low_zeros, numerator, work);
    cycle_record_shift_down(bottom, bottom_limbs, low_zeros, divisor, divisor_used);
    // an odd word is its own inverse to 3 bits, and each step doubles the bits: 6, 12, 24, 48
    unsigned int word = divisor[0];
    for (unsigned int round = 0u; round < 4u; round += 1u)
    {
        word *= 2u - (divisor[0] * word);
    }
    inverse[0] = word;
    for (unsigned int precise_limbs = 1u; precise_limbs < work;)
    {
        const unsigned int range = ((2u * precise_limbs) < work) ? (2u * precise_limbs) : work;
        cycle_record_product(divisor, (divisor_used < range) ? divisor_used : range, inverse, precise_limbs, stepped,
                             range);
        // 2 - d x modulo 2^(32 range): the two's complement of d x, plus 2
        unsigned long long carry = 2ull;
        for (unsigned int at = 0u; at < range; at += 1u)
        {
            const unsigned long long total = (unsigned long long)(~stepped[at]) + ((at == 0u) ? 1ull : 0ull) + carry;
            stepped[at] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        cycle_record_product(inverse, precise_limbs, stepped, range, grown, range);
        for (unsigned int at = 0u; at < range; at += 1u)
        {
            inverse[at] = grown[at];
        }
        precise_limbs = range;
    }
    // the whole quotient lands in grown; the inverse and its step product then lie together, room for the whole
    // product of the quotient and the divisor
    unsigned int *const estimate = grown;
    cycle_record_product(numerator, work, inverse, work, estimate, work);
    unsigned int *const back = inverse;
    cycle_record_product(estimate, work, divisor, divisor_used, back, work + divisor_used);
    if (cycle_record_compare(back, work + divisor_used, numerator, work) != 0)
    {
        return 0;
    }
    // a quotient past its register's limbs outgrew it
    for (unsigned int at = limbs; at < work; at += 1u)
    {
        if (estimate[at] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = estimate[at];
    }
    return 1;
}

__device__ static inline void cycle_record_put(unsigned int *record, unsigned int offset, unsigned int bits,
                                               const unsigned int *value, unsigned int limbs, int sign)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int bit_value = (bit < (32u * limbs)) ? ((value[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
        unsigned int written = bit_value;
        if (sign < 0)
        {
            const unsigned int flipped = (bit_value ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        record[to / 32u] |= written << (to % 32u);
    }
}

// one step that reads registers: the left, and the right, where a table reads the left alone (its right names the
// table, not a step). Each operand's sign is read beside it, at its place in the file, and the result's sign is left
// in `sign_out`; `ok` falls to 0 for a lane the step refuses.
template <unsigned int WIDE, unsigned int DIVIDES>
__device__ static void cycle_record_operate(const CycleRecordLaunch &launch, const DeviceRecordStep &step,
                                            const unsigned int *file, const signed char *sign, unsigned int *scratch,
                                            unsigned int *value, signed char *sign_out, int *ok)
{
    const unsigned int left_place = launch.steps[step.left].place;
    const unsigned int right_place =
        (step.operation == ENGINE_RECORD_TABLE) ? left_place : launch.steps[step.right].place;
    const unsigned int *const left = &file[left_place];
    const unsigned int *const right = &file[right_place];
    const int left_sign = sign[left_place];
    const int right_sign = sign[right_place];
    if (step.operation == ENGINE_RECORD_PRODUCT)
    {
        cycle_record_product(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
        *sign_out = (signed char)(left_sign * right_sign);
    }
    else if ((step.operation == ENGINE_RECORD_SUM) || (step.operation == ENGINE_RECORD_DIFFERENCE))
    {
        const int addend_sign = (step.operation == ENGINE_RECORD_SUM) ? right_sign : -right_sign;
        if ((left_sign == addend_sign) || (addend_sign == 0) || (left_sign == 0))
        {
            cycle_record_add(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *sign_out = (signed char)((left_sign != 0) ? left_sign : addend_sign);
        }
        else if (cycle_record_compare(left, step.left_limbs, right, step.right_limbs) >= 0)
        {
            cycle_record_subtract(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *sign_out = (signed char)left_sign;
        }
        else
        {
            cycle_record_subtract(right, step.right_limbs, left, step.left_limbs, value, step.limbs);
            *sign_out = (signed char)addend_sign;
        }
        *sign_out = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : *sign_out;
    }
    else if (step.operation == ENGINE_RECORD_LADDER)
    {
        *ok = (right_sign > 0) ? 1 : 0;
        unsigned int band = 0u;
        if (*ok != 0)
        {
            cycle_record_ladder<WIDE>(left, step.left_limbs, right, step.right_limbs, &band);
        }
        value[0] = band;
        *sign_out = (band == 0u) ? 0 : (signed char)left_sign;
    }
    else if (step.operation == ENGINE_RECORD_ABSOLUTE)
    {
        for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
        {
            value[limb] = cycle_record_limb(left, step.left_limbs, limb);
        }
        *sign_out = (left_sign != 0) ? 1 : 0;
    }
    else if (step.operation == ENGINE_RECORD_COMPARE)
    {
        const int order = (left_sign != right_sign)
                              ? ((left_sign > right_sign) ? 1 : -1)
                              : (left_sign * cycle_record_compare(left, step.left_limbs, right, step.right_limbs));
        value[0] = (order != 0) ? 1u : 0u;
        *sign_out = (signed char)order;
    }
    else if (step.operation == ENGINE_RECORD_TABLE)
    {
        // the low index_bits of the source register (index_bits <= 32, one limb) select a row
        const unsigned int index = (step.index_bits >= 32u) ? left[0] : (left[0] & ((1u << step.index_bits) - 1u));
        const unsigned int *const entry = &launch.tables[step.table_offset + (index * step.limbs)];
        for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
        {
            value[limb] = entry[limb];
        }
        *sign_out = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
    }
    else if ((step.operation == ENGINE_RECORD_XOR) || (step.operation == ENGINE_RECORD_AND))
    {
        *sign_out = (signed char)cycle_record_bitwise(step.operation, left, step.left_limbs, left_sign, right,
                                                      step.right_limbs, right_sign, value, step.limbs);
    }
    else if (step.operation == ENGINE_RECORD_WRAP)
    {
        *sign_out = (signed char)cycle_record_wrap(left, step.left_limbs, left_sign, step.wrap_bits, value, step.limbs);
    }
    else if ((DIVIDES != 0u) && (cycle_record_divides(step.operation) != 0))
    {
        int result_sign = 1;
        if (step.operation == ENGINE_RECORD_QUOTIENT)
        {
            *ok = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, NULL, 0u,
                                            scratch);
            result_sign = left_sign * right_sign;
        }
        else if (step.operation == ENGINE_RECORD_REMAINDER)
        {
            *ok = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, NULL, 0u, value, step.limbs,
                                            scratch);
            result_sign = left_sign;
        }
        else if (step.operation == ENGINE_RECORD_GCD)
        {
            cycle_record_gcd<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, scratch);
        }
        else
        {
            *ok = cycle_record_exact_quotient<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs,
                                                    scratch);
            result_sign = left_sign * right_sign;
        }
        *sign_out = (signed char)((cycle_record_is_zero(value, step.limbs) != 0) ? 0 : result_sign);
    }
    else
    {
        *ok = 0;
    }
}
#endif
