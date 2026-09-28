// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_record_arithmetic.h: the record interpreter's limb arithmetic on the device (included by
// cycle_record_internal.h)
#ifndef CYCLE_RECORD_ARITHMETIC_H
#define CYCLE_RECORD_ARITHMETIC_H

// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

struct CycleRecordLaunch
{
    const DeviceRecordStep *steps;
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *error;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    unsigned int step_count;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
};

#define CYCLE_RECORD_BLOCKS_MAX 4096ull

__device__ static inline unsigned int cycle_record_limb(const unsigned int *value, unsigned int limbs, unsigned int at)
{
    return (at < limbs) ? value[at] : 0u;
}

__device__ static inline int cycle_record_compare(const unsigned int *left, unsigned int left_limbs,
                                                  const unsigned int *right, unsigned int right_limbs)
{
    unsigned int at = (left_limbs > right_limbs) ? left_limbs : right_limbs;
    while (at > 0u)
    {
        at -= 1u;
        const unsigned int one = cycle_record_limb(left, left_limbs, at);
        const unsigned int other = cycle_record_limb(right, right_limbs, at);
        if (one != other)
        {
            return (one < other) ? -1 : 1;
        }
    }
    return 0;
}

__device__ static inline int cycle_record_is_zero(const unsigned int *value, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        if (value[at] != 0u)
        {
            return 0;
        }
    }
    return 1;
}

__device__ static inline void cycle_record_field(const unsigned int *atom, unsigned int in_limbs, unsigned int offset,
                                                 unsigned int bits, unsigned int *value, unsigned int limbs)
{
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int bit = offset + (32u * limb);
        const unsigned int word = bit / 32u;
        const unsigned int shift = bit % 32u;
        unsigned int gathered = cycle_record_limb(atom, in_limbs, word) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_record_limb(atom, in_limbs, word + 1u) << (32u - shift);
        }
        const unsigned int left = bits - (32u * limb);
        value[limb] = (left < 32u) ? (gathered & ((1u << left) - 1u)) : gathered;
    }
}

__device__ static inline void cycle_record_negate(unsigned int *value, unsigned int limbs, unsigned int bits)
{
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (unsigned long long)(~value[at]) + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    const unsigned int left = bits - (32u * (limbs - 1u));
    value[limbs - 1u] = (left < 32u) ? (value[limbs - 1u] & ((1u << left) - 1u)) : value[limbs - 1u];
}

// limb `at` of a register's two's complement: the magnitude's limb, or its complement where the sign is negative,
// with `carry` running the negation's one up the limbs; it starts at 1 and the limbs are taken from the lowest up
__device__ static inline unsigned int cycle_record_complement(const unsigned int *value, unsigned int limbs,
                                                              unsigned int at, int sign, unsigned long long *carry)
{
    const unsigned int limb_value = cycle_record_limb(value, limbs, at);
    if (sign >= 0)
    {
        return limb_value;
    }
    const unsigned long long total = (unsigned long long)(~limb_value) + *carry;
    *carry = total >> 32u;
    return (unsigned int)(total & 0xFFFFFFFFull);
}

// the xor or the and of two registers' two's complements over `limbs`, read back as a magnitude; returns its sign.
// The sign is the operands': the xor is negative where exactly one is, the and where both are. A negative result has
// the extra bit over the wider operand in its limbs. Its low limbs read back to the magnitude; a result keymath
// narrowed (an and with a register never negative, an xor of two) is never negative and is its low limbs.
__device__ static inline int cycle_record_bitwise(unsigned int operation, const unsigned int *left,
                                                  unsigned int left_limbs, int left_sign, const unsigned int *right,
                                                  unsigned int right_limbs, int right_sign, unsigned int *value,
                                                  unsigned int limbs)
{
    unsigned long long left_carry = 1ull;
    unsigned long long right_carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned int one = cycle_record_complement(left, left_limbs, at, left_sign, &left_carry);
        const unsigned int other = cycle_record_complement(right, right_limbs, at, right_sign, &right_carry);
        value[at] = (operation == ENGINE_RECORD_XOR) ? (one ^ other) : (one & other);
    }
    const int left_negative = (left_sign < 0) ? 1 : 0;
    const int right_negative = (right_sign < 0) ? 1 : 0;
    const int negative =
        (operation == ENGINE_RECORD_XOR) ? (left_negative ^ right_negative) : (left_negative & right_negative);
    if (negative != 0)
    {
        cycle_record_negate(value, limbs, 32u * limbs);
    }
    return (cycle_record_is_zero(value, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a register wrapped to `bits` of two's complement, read back signed as a magnitude over `limbs`; returns its sign.
// keymath gave the step the fewer of the source's bits and the wrap's. A wrap wider than the step's 32 limbs is a
// source already inside the signed range, passed through, and any other step holds exactly the wrap's limbs.
__device__ static inline int cycle_record_wrap(const unsigned int *source, unsigned int source_limbs, int source_sign,
                                               unsigned int bits, unsigned int *value, unsigned int limbs)
{
    if (bits > (32u * limbs))
    {
        for (unsigned int at = 0u; at < limbs; at += 1u)
        {
            value[at] = cycle_record_limb(source, source_limbs, at);
        }
        return source_sign;
    }
    unsigned long long carry = 1ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = cycle_record_complement(source, source_limbs, at, source_sign, &carry);
    }
    const unsigned int kept = bits - (32u * (limbs - 1u));
    value[limbs - 1u] = (kept < 32u) ? (value[limbs - 1u] & ((1u << kept) - 1u)) : value[limbs - 1u];
    const unsigned int top = bits - 1u;
    const int negative = (((value[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
    if (negative != 0)
    {
        cycle_record_negate(value, limbs, bits);
    }
    return (cycle_record_is_zero(value, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

__device__ static inline void cycle_record_add(const unsigned int *left, unsigned int left_limbs,
                                               const unsigned int *right, unsigned int right_limbs, unsigned int *value,
                                               unsigned int limbs)
{
    unsigned long long carry = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (unsigned long long)cycle_record_limb(left, left_limbs, at) +
                                         (unsigned long long)cycle_record_limb(right, right_limbs, at) + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static inline void cycle_record_subtract(const unsigned int *left, unsigned int left_limbs,
                                                    const unsigned int *right, unsigned int right_limbs,
                                                    unsigned int *value, unsigned int limbs)
{
    unsigned long long borrow = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (1ull << 32u) + (unsigned long long)cycle_record_limb(left, left_limbs, at) -
                                         (unsigned long long)cycle_record_limb(right, right_limbs, at) - borrow;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__device__ static inline void cycle_record_product(const unsigned int *left, unsigned int left_limbs,
                                                   const unsigned int *right, unsigned int right_limbs,
                                                   unsigned int *value, unsigned int limbs)
{
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = 0u;
    }
    for (unsigned int low = 0u; low < left_limbs; low += 1u)
    {
        unsigned long long carry = 0ull;
        for (unsigned int high = 0u; (high < right_limbs) && ((low + high) < limbs); high += 1u)
        {
            const unsigned long long total = ((unsigned long long)left[low] * (unsigned long long)right[high]) +
                                             (unsigned long long)value[low + high] + carry;
            value[low + high] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        for (unsigned int at = low + right_limbs; (carry != 0ull) && (at < limbs); at += 1u)
        {
            const unsigned long long total = (unsigned long long)value[at] + carry;
            value[at] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

template <unsigned int WIDE>
__device__ static int cycle_record_ladder(const unsigned int *numerator, unsigned int numerator_limbs,
                                          const unsigned int *denominator, unsigned int denominator_limbs,
                                          unsigned int *band)
{
    unsigned int reached[WIDE + 2u];
    unsigned long long lower = 0ull;
    unsigned long long upper = 1ull;
    unsigned int counted = 0u;
    int below = 1;
    for (unsigned int rung = 1u; (below != 0) && (rung < ENGINE_GOLDEN_RUNGS); rung += 1u)
    {
        const unsigned int step[2] = {(unsigned int)(upper & 0xFFFFFFFFull), (unsigned int)(upper >> 32u)};
        cycle_record_product(denominator, denominator_limbs, step, 2u, reached, denominator_limbs + 2u);
        below = (cycle_record_compare(reached, denominator_limbs + 2u, numerator, numerator_limbs) <= 0) ? 1 : 0;
        counted += (unsigned int)below;
        const unsigned long long next = lower + upper;
        lower = upper;
        upper = next;
    }
    *band = counted;
    return 1;
}

__device__ static inline int cycle_record_divides(unsigned int operation)
{
    return (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER) ||
           (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

__device__ static inline unsigned int cycle_record_used(const unsigned int *value, unsigned int limbs)
{
    while ((limbs > 0u) && (value[limbs - 1u] == 0u))
    {
        limbs -= 1u;
    }
    return limbs;
}

// value shifted toward the low end by `bits` (below 32 times the limbs), into `limbs` of out
__device__ static inline void cycle_record_shift_down(const unsigned int *value, unsigned int value_limbs,
                                                      unsigned int bits, unsigned int *out, unsigned int limbs)
{
    const unsigned int words = bits / 32u;
    const unsigned int shift = bits % 32u;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        unsigned int gathered = cycle_record_limb(value, value_limbs, at + words) >> shift;
        if (shift != 0u)
        {
            gathered |= cycle_record_limb(value, value_limbs, at + words + 1u) << (32u - shift);
        }
        out[at] = gathered;
    }
}

// Knuth's Algorithm D on the magnitudes: top = quotient . bottom + rest, each output kept to its own limbs and
// either one left out when NULL; 0 for a zero divisor. scratch holds 2 * WIDE + 2 limbs.
template <unsigned int WIDE>
__device__ static int cycle_record_divide(const unsigned int *top, unsigned int top_limbs, const unsigned int *bottom,
                                          unsigned int bottom_limbs, unsigned int *quotient,
                                          unsigned int quotient_limbs, unsigned int *rest, unsigned int rest_limbs,
                                          unsigned int *scratch)
{
    const unsigned int divisor_used = cycle_record_used(bottom, bottom_limbs);
    if (divisor_used == 0u)
    {
        return 0;
    }
    const unsigned int numerator_used = cycle_record_used(top, top_limbs);
    for (unsigned int at = 0u; (quotient != NULL) && (at < quotient_limbs); at += 1u)
    {
        quotient[at] = 0u;
    }
    if (numerator_used < divisor_used)
    {
        for (unsigned int at = 0u; (rest != NULL) && (at < rest_limbs); at += 1u)
        {
            rest[at] = cycle_record_limb(top, numerator_used, at);
        }
        return 1;
    }
    if (divisor_used == 1u)
    {
        const unsigned long long divisor = (unsigned long long)bottom[0];
        unsigned long long carried = 0ull;
        for (unsigned int at = numerator_used; at > 0u; at -= 1u)
        {
            const unsigned long long part = (carried << 32u) | (unsigned long long)top[at - 1u];
            if ((quotient != NULL) && ((at - 1u) < quotient_limbs))
            {
                quotient[at - 1u] = (unsigned int)(part / divisor);
            }
            carried = part % divisor;
        }
        for (unsigned int at = 0u; (rest != NULL) && (at < rest_limbs); at += 1u)
        {
            rest[at] = (at == 0u) ? (unsigned int)carried : 0u;
        }
        return 1;
    }
    unsigned int *const numerator = scratch;
    unsigned int *const divisor = &scratch[WIDE + 2u];
    const unsigned int shift = (unsigned int)__clz(bottom[divisor_used - 1u]);
    for (unsigned int at = 0u; at < divisor_used; at += 1u)
    {
        const unsigned int below = ((shift != 0u) && (at > 0u)) ? (bottom[at - 1u] >> (32u - shift)) : 0u;
        divisor[at] = (bottom[at] << shift) | below;
    }
    for (unsigned int at = 0u; at <= numerator_used; at += 1u)
    {
        const unsigned int here = cycle_record_limb(top, numerator_used, at);
        const unsigned int below = ((shift != 0u) && (at > 0u)) ? (top[at - 1u] >> (32u - shift)) : 0u;
        numerator[at] = (here << shift) | below;
    }
    const unsigned long long lead = (unsigned long long)divisor[divisor_used - 1u];
    const unsigned long long next = (unsigned long long)divisor[divisor_used - 2u];
    for (unsigned int place = numerator_used - divisor_used + 1u; place > 0u; place -= 1u)
    {
        const unsigned int at = place - 1u;
        const unsigned long long part = ((unsigned long long)numerator[at + divisor_used] << 32u) |
                                        (unsigned long long)numerator[at + divisor_used - 1u];
        unsigned long long guess = part / lead;
        unsigned long long over = part % lead;
        while ((guess >> 32u) != 0ull ||
               ((guess * next) > ((over << 32u) | (unsigned long long)numerator[at + divisor_used - 2u])))
        {
            guess -= 1ull;
            over += lead;
            if ((over >> 32u) != 0ull)
            {
                break;
            }
        }
        unsigned long long borrow = 0ull;
        for (unsigned int limb = 0u; limb < divisor_used; limb += 1u)
        {
            const unsigned long long taken = (guess * (unsigned long long)divisor[limb]) + borrow;
            const unsigned long long limb_value = (unsigned long long)numerator[at + limb];
            numerator[at + limb] = (unsigned int)((limb_value - (taken & 0xFFFFFFFFull)) & 0xFFFFFFFFull);
            borrow = (taken >> 32u) + ((limb_value < (taken & 0xFFFFFFFFull)) ? 1ull : 0ull);
        }
        const unsigned long long limb_value = (unsigned long long)numerator[at + divisor_used];
        numerator[at + divisor_used] = (unsigned int)((limb_value - borrow) & 0xFFFFFFFFull);
        if (limb_value < borrow)
        {
            // the guess was one too many (Knuth D6): add the divisor back
            guess -= 1ull;
            unsigned long long carry = 0ull;
            for (unsigned int limb = 0u; limb < divisor_used; limb += 1u)
            {
                const unsigned long long total =
                    (unsigned long long)numerator[at + limb] + (unsigned long long)divisor[limb] + carry;
                numerator[at + limb] = (unsigned int)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
            numerator[at + divisor_used] = (unsigned int)((numerator[at + divisor_used] + carry) & 0xFFFFFFFFull);
        }
        if ((quotient != NULL) && (at < quotient_limbs))
        {
            quotient[at] = (unsigned int)guess;
        }
    }
    if (rest != NULL)
    {
        cycle_record_shift_down(numerator, divisor_used + 1u, shift, rest, rest_limbs);
        for (unsigned int at = divisor_used; at < rest_limbs; at += 1u)
        {
            rest[at] = 0u;
        }
    }
    return 1;
}
#endif
