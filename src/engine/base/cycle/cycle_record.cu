// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

struct CycleRecordLaunch
{
    const DeviceRecordStep *steps;
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *refused;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    unsigned int step_count;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
};

#define CYCLE_RECORD_BLOCKS_MOST 4096ull

__device__ static unsigned int cycle_record_limb(const unsigned int *value, unsigned int limbs, unsigned int at)
{
    return (at < limbs) ? value[at] : 0u;
}

__device__ static int cycle_record_compare(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                           unsigned int right_limbs)
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

__device__ static int cycle_record_is_zero(const unsigned int *value, unsigned int limbs)
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

__device__ static void cycle_record_field(const unsigned int *atom, unsigned int in_limbs, unsigned int offset,
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

__device__ static void cycle_record_negate(unsigned int *value, unsigned int limbs, unsigned int bits)
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
__device__ static unsigned int cycle_record_complement(const unsigned int *value, unsigned int limbs, unsigned int at,
                                                       int sign, unsigned long long *carry)
{
    const unsigned int held = cycle_record_limb(value, limbs, at);
    if (sign >= 0)
    {
        return held;
    }
    const unsigned long long total = (unsigned long long)(~held) + *carry;
    *carry = total >> 32u;
    return (unsigned int)(total & 0xFFFFFFFFull);
}

// the xor or the and of two registers' two's complements over `limbs`, read back as a magnitude; returns its sign.
// The sign is the operands': the xor is negative where exactly one is, the and where both are. A negative result has
// the extra bit over the wider operand in its limbs, so its low limbs read back to the magnitude; a result keymath
// narrowed (an and with a register never negative, an xor of two) is never negative and is its low limbs.
__device__ static int cycle_record_bitwise(unsigned int operation, const unsigned int *left, unsigned int left_limbs,
                                          int left_sign, const unsigned int *right, unsigned int right_limbs,
                                          int right_sign, unsigned int *value, unsigned int limbs)
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
    const int negative = (operation == ENGINE_RECORD_XOR) ? (left_negative ^ right_negative)
                                                          : (left_negative & right_negative);
    if (negative != 0)
    {
        cycle_record_negate(value, limbs, 32u * limbs);
    }
    return (cycle_record_is_zero(value, limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
}

// a register wrapped to `bits` of two's complement, read back signed as a magnitude over `limbs`; returns its sign.
// keymath gave the step the fewer of the source's bits and the wrap's, so a wrap wider than the step's 32 limbs is a
// source already inside the signed range, passed through, and any other step holds exactly the wrap's limbs.
__device__ static int cycle_record_wrap(const unsigned int *source, unsigned int source_limbs, int source_sign,
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

__device__ static void cycle_record_add(const unsigned int *left, unsigned int left_limbs, const unsigned int *right,
                                        unsigned int right_limbs, unsigned int *value, unsigned int limbs)
{
    unsigned long long carry = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (unsigned long long)cycle_record_limb(left, left_limbs, at)
                                       + (unsigned long long)cycle_record_limb(right, right_limbs, at) + carry;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__device__ static void cycle_record_subtract(const unsigned int *left, unsigned int left_limbs,
                                             const unsigned int *right, unsigned int right_limbs, unsigned int *value,
                                             unsigned int limbs)
{
    unsigned long long borrow = 0ull;
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        const unsigned long long total = (1ull << 32u) + (unsigned long long)cycle_record_limb(left, left_limbs, at)
                                       - (unsigned long long)cycle_record_limb(right, right_limbs, at) - borrow;
        value[at] = (unsigned int)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__device__ static void cycle_record_product(const unsigned int *left, unsigned int left_limbs,
                                            const unsigned int *right, unsigned int right_limbs, unsigned int *value,
                                            unsigned int limbs)
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
            const unsigned long long total = ((unsigned long long)left[low] * (unsigned long long)right[high])
                                           + (unsigned long long)value[low + high] + carry;
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

__device__ static int cycle_record_divides(unsigned int operation)
{
    return (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

__device__ static unsigned int cycle_record_used(const unsigned int *value, unsigned int limbs)
{
    while ((limbs > 0u) && (value[limbs - 1u] == 0u))
    {
        limbs -= 1u;
    }
    return limbs;
}

// value shifted toward the low end by `bits` (below 32 times the limbs), into `limbs` of out
__device__ static void cycle_record_shift_down(const unsigned int *value, unsigned int value_limbs, unsigned int bits,
                                               unsigned int *out, unsigned int limbs)
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
        const unsigned long long part = ((unsigned long long)numerator[at + divisor_used] << 32u)
                                      | (unsigned long long)numerator[at + divisor_used - 1u];
        unsigned long long guess = part / lead;
        unsigned long long over = part % lead;
        while ((guess >> 32u) != 0ull
               || ((guess * next) > ((over << 32u) | (unsigned long long)numerator[at + divisor_used - 2u])))
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
            const unsigned long long held = (unsigned long long)numerator[at + limb];
            numerator[at + limb] = (unsigned int)((held - (taken & 0xFFFFFFFFull)) & 0xFFFFFFFFull);
            borrow = (taken >> 32u) + ((held < (taken & 0xFFFFFFFFull)) ? 1ull : 0ull);
        }
        const unsigned long long held = (unsigned long long)numerator[at + divisor_used];
        numerator[at + divisor_used] = (unsigned int)((held - borrow) & 0xFFFFFFFFull);
        if (held < borrow)
        {
            // the guess was one too many (Knuth D6): add the divisor back
            guess -= 1ull;
            unsigned long long carry = 0ull;
            for (unsigned int limb = 0u; limb < divisor_used; limb += 1u)
            {
                const unsigned long long total = (unsigned long long)numerator[at + limb]
                                               + (unsigned long long)divisor[limb] + carry;
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
        unsigned int *const held = larger;
        larger = smaller;
        smaller = rest;
        rest = held;
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
    for (unsigned int held = 1u; held < work;)
    {
        const unsigned int reach = ((2u * held) < work) ? (2u * held) : work;
        cycle_record_product(divisor, (divisor_used < reach) ? divisor_used : reach, inverse, held, stepped, reach);
        // 2 - d x modulo 2^(32 reach): the two's complement of d x, plus 2
        unsigned long long carry = 2ull;
        for (unsigned int at = 0u; at < reach; at += 1u)
        {
            const unsigned long long total = (unsigned long long)(~stepped[at]) + ((at == 0u) ? 1ull : 0ull) + carry;
            stepped[at] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
        cycle_record_product(inverse, held, stepped, reach, grown, reach);
        for (unsigned int at = 0u; at < reach; at += 1u)
        {
            inverse[at] = grown[at];
        }
        held = reach;
    }
    // the whole quotient lands in grown; the inverse and its step product then lie together, room for the whole
    // product of the quotient and the divisor
    unsigned int *const whole = grown;
    cycle_record_product(numerator, work, inverse, work, whole, work);
    unsigned int *const back = inverse;
    cycle_record_product(whole, work, divisor, divisor_used, back, work + divisor_used);
    if (cycle_record_compare(back, work + divisor_used, numerator, work) != 0)
    {
        return 0;
    }
    // a quotient past its register's limbs outgrew it
    for (unsigned int at = limbs; at < work; at += 1u)
    {
        if (whole[at] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int at = 0u; at < limbs; at += 1u)
    {
        value[at] = whole[at];
    }
    return 1;
}

__device__ static void cycle_record_put(unsigned int *record, unsigned int offset, unsigned int bits,
                                        const unsigned int *value, unsigned int limbs, int sign)
{
    unsigned int carry = 1u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int held = (bit < (32u * limbs)) ? ((value[bit / 32u] >> (bit % 32u)) & 1u) : 0u;
        unsigned int written = held;
        if (sign < 0)
        {
            const unsigned int flipped = (held ^ 1u) + carry;
            written = flipped & 1u;
            carry = flipped >> 1u;
        }
        const unsigned int to = offset + bit;
        record[to / 32u] |= written << (to % 32u);
    }
}

// one step that reads registers: the left, and the right, where a table reads the left alone (its right names the
// table, not a step). Each operand's sign is read beside it, at its place in the file, and the result's sign is left
// in `held`; `good` falls to 0 for a lane the step refuses.
template <unsigned int WIDE, unsigned int DIVIDES>
__device__ static void cycle_record_operate(const CycleRecordLaunch &launch, const DeviceRecordStep &step,
                                            const unsigned int *file, const signed char *sign, unsigned int *scratch,
                                            unsigned int *value, signed char *held, int *good)
{
    const unsigned int left_place = launch.steps[step.left].place;
    const unsigned int right_place = (step.operation == ENGINE_RECORD_TABLE) ? left_place
                                                                             : launch.steps[step.right].place;
    const unsigned int *const left = &file[left_place];
    const unsigned int *const right = &file[right_place];
    const int left_sign = sign[left_place];
    const int right_sign = sign[right_place];
    if (step.operation == ENGINE_RECORD_PRODUCT)
    {
        cycle_record_product(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
        *held = (signed char)(left_sign * right_sign);
    }
    else if ((step.operation == ENGINE_RECORD_SUM) || (step.operation == ENGINE_RECORD_DIFFERENCE))
    {
        const int addend_sign = (step.operation == ENGINE_RECORD_SUM) ? right_sign : -right_sign;
        if ((left_sign == addend_sign) || (addend_sign == 0) || (left_sign == 0))
        {
            cycle_record_add(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *held = (signed char)((left_sign != 0) ? left_sign : addend_sign);
        }
        else if (cycle_record_compare(left, step.left_limbs, right, step.right_limbs) >= 0)
        {
            cycle_record_subtract(left, step.left_limbs, right, step.right_limbs, value, step.limbs);
            *held = (signed char)left_sign;
        }
        else
        {
            cycle_record_subtract(right, step.right_limbs, left, step.left_limbs, value, step.limbs);
            *held = (signed char)addend_sign;
        }
        *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : *held;
    }
    else if (step.operation == ENGINE_RECORD_LADDER)
    {
        *good = (right_sign > 0) ? 1 : 0;
        unsigned int band = 0u;
        if (*good != 0)
        {
            cycle_record_ladder<WIDE>(left, step.left_limbs, right, step.right_limbs, &band);
        }
        value[0] = band;
        *held = (band == 0u) ? 0 : (signed char)left_sign;
    }
    else if (step.operation == ENGINE_RECORD_ABSOLUTE)
    {
        for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
        {
            value[limb] = cycle_record_limb(left, step.left_limbs, limb);
        }
        *held = (left_sign != 0) ? 1 : 0;
    }
    else if (step.operation == ENGINE_RECORD_COMPARE)
    {
        const int order = (left_sign != right_sign)
                        ? ((left_sign > right_sign) ? 1 : -1)
                        : (left_sign * cycle_record_compare(left, step.left_limbs, right, step.right_limbs));
        value[0] = (order != 0) ? 1u : 0u;
        *held = (signed char)order;
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
        *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
    }
    else if ((step.operation == ENGINE_RECORD_XOR) || (step.operation == ENGINE_RECORD_AND))
    {
        *held = (signed char)cycle_record_bitwise(step.operation, left, step.left_limbs, left_sign, right,
                                                  step.right_limbs, right_sign, value, step.limbs);
    }
    else if (step.operation == ENGINE_RECORD_WRAP)
    {
        *held = (signed char)cycle_record_wrap(left, step.left_limbs, left_sign, step.wrap_bits, value, step.limbs);
    }
    else if ((DIVIDES != 0u) && (cycle_record_divides(step.operation) != 0))
    {
        int held_sign = 1;
        if (step.operation == ENGINE_RECORD_QUOTIENT)
        {
            *good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, NULL,
                                              0u, scratch);
            held_sign = left_sign * right_sign;
        }
        else if (step.operation == ENGINE_RECORD_REMAINDER)
        {
            *good = cycle_record_divide<WIDE>(left, step.left_limbs, right, step.right_limbs, NULL, 0u, value,
                                              step.limbs, scratch);
            held_sign = left_sign;
        }
        else if (step.operation == ENGINE_RECORD_GCD)
        {
            cycle_record_gcd<WIDE>(left, step.left_limbs, right, step.right_limbs, value, step.limbs, scratch);
        }
        else
        {
            *good = cycle_record_exact_quotient<WIDE>(left, step.left_limbs, right, step.right_limbs, value,
                                                      step.limbs, scratch);
            held_sign = left_sign * right_sign;
        }
        *held = (signed char)((cycle_record_is_zero(value, step.limbs) != 0) ? 0 : held_sign);
    }
    else
    {
        *good = 0;
    }
}

// DIVIDES is 1 for a program holding a division operation, which alone carries the division scratch
template <unsigned int WIDE, unsigned int DIVIDES>
__global__ static void cycle_record_kernel(CycleRecordLaunch launch)
{
    unsigned int file[WIDE];
    unsigned int scratch[(DIVIDES != 0u) ? CYCLE_RECORD_SCRATCH(WIDE) : 1u];
    // a register's sign lies beside it, at its place in the file, so the steps are bounded by nothing held per step
    signed char sign[WIDE];
    const DeviceRecordStep *const steps = launch.steps;
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; lane < launch.count;
         lane += stride)
    {
        const unsigned int *atom[ENGINE_RECORD_MEMBERS_MAX];
        int good = 1;
        for (unsigned int member = 0u; member < launch.members; member += 1u)
        {
            const unsigned long long body = (launch.index != NULL)
                                          ? (unsigned long long)launch.index[(lane * launch.members) + member]
                                          : ((launch.bodies[member] == 1ull) ? 0ull : lane);
            good = good && (body < launch.bodies[member]);
            atom[member] = &launch.in[member][((good != 0) ? body : 0ull) * launch.in_limbs[member]];
        }
        unsigned int *const record = &launch.out[lane * launch.out_limbs];
        for (unsigned int limb = 0u; limb < launch.out_limbs; limb += 1u)
        {
            record[limb] = 0u;
        }
        for (unsigned int at = 0u; (good != 0) && (at < launch.step_count); at += 1u)
        {
            const DeviceRecordStep step = steps[at];
            unsigned int *const value = &file[step.place];
            signed char *const held = &sign[step.place];
            if (step.operation == ENGINE_RECORD_FIELD)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_FIELD_SIGNED)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                const unsigned int top = step.right - 1u;
                const int negative = (((value[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
                if (negative != 0)
                {
                    cycle_record_negate(value, step.limbs, step.right);
                }
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
            }
            else if (step.operation == ENGINE_RECORD_CONSTANT)
            {
                value[0] = step.left;
                if (step.limbs > 1u)
                {
                    value[1] = step.right;
                }
                *held = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_LANE)
            {
                for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
                {
                    value[limb] = (limb == 0u) ? (unsigned int)(lane & 0xFFFFFFFFull)
                                               : ((limb == 1u) ? (unsigned int)(lane >> 32u) : 0u);
                }
                *held = (lane == 0ull) ? 0 : 1;
            }
            else
            {
                cycle_record_operate<WIDE, DIVIDES>(launch, step, file, sign, scratch, value, held, &good);
            }
            if ((good != 0) && (step.out_bits != 0u))
            {
                cycle_record_put(record, step.out_offset, step.out_bits, value, step.limbs, *held);
            }
        }
        if (good == 0)
        {
            atomicAdd(launch.refused, 1u);
        }
    }
}

// the block's CRC-64 over every word before its checksum
static unsigned long long cycle_block_seal(const EngineProgramBlock *block)
{
    // the block is 64-bit words throughout, asserted above, so it reads as them
    return crc_words(CRC_TABLE, (const unsigned long long *)block, offsetof(EngineProgramBlock, checksum) / 8u);
}

extern "C" int cycle_record_compiled(const CycleRecord *record)
{
    return ((record != NULL) && (record->compiled != 0u)) ? 1 : 0;
}

extern "C" const EngineProgramBlock *cycle_record_block(const CycleRecord *record)
{
    return (record != NULL) ? record->block : NULL;
}

// the compiled program's registers laid in shared memory: a thread's places a word each and the file's signs a byte
// each, for as many threads as one thread block's shared memory holds beside the kernel's own, a whole number of warps
// up to CYCLE_BLOCK where a warp fits. A program written as PTX that calls nothing holds its registers itself and takes
// no places, and runs CYCLE_BLOCK threads a thread block. The kernel is let take that much and prefers shared memory to
// L1, and the device is asked how many such thread blocks it holds at once. 0 where not one thread's registers fit or
// the runtime refuses any of it, which leaves the program on the interpreter
static int cycle_record_share(CycleRecord *record, size_t kernel_bytes)
{
    int device = 0;
    int most = 0;
    int processors = 0;
    if ((cudaGetDevice(&device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&most, cudaDevAttrMaxSharedMemoryPerBlockOptin, device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&processors, cudaDevAttrMultiProcessorCount, device) != cudaSuccess))
    {
        return 0;
    }
    const unsigned long long thread_bytes = (record->places != 0u) ? ((4ull * record->places) + record->file_limbs)
                                                                    : 0ull;
    // a device's shared memory a thread block is never negative
    const unsigned long long room = ((unsigned long long)most > kernel_bytes) ? ((unsigned long long)most - kernel_bytes)
                                                                               : 0ull;
    const unsigned long long fit = (thread_bytes != 0ull) ? (room / thread_bytes) : CYCLE_BLOCK;
    const unsigned long long held = (fit < CYCLE_BLOCK) ? fit : CYCLE_BLOCK;
    const unsigned long long threads = (held >= 32ull) ? (held - (held % 32ull)) : held;
    if (threads == 0ull)
    {
        return 0;
    }
    // at most CYCLE_BLOCK threads, and at most the device's shared memory a thread block, both far under 2^31
    record->threads = (unsigned int)threads;
    record->thread_bytes = thread_bytes;
    // a count of processors is positive where the runtime gave it
    record->processors = (unsigned long long)processors;
    record->register_bytes = threads * thread_bytes;
    record->shared_bytes = record->register_bytes + kernel_bytes;
    int blocks = 0;
    const int ok = (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributeMaxDynamicSharedMemorySize,
                                         (int)record->register_bytes) == cudaSuccess)
                && (cudaFuncSetAttribute((const void *)record->kernel, cudaFuncAttributePreferredSharedMemoryCarveout,
                                         (int)cudaSharedmemCarveoutMaxShared) == cudaSuccess)
                && (cudaOccupancyMaxActiveBlocksPerMultiprocessor(&blocks, (const void *)record->kernel,
                                                                  (int)record->threads,
                                                                  (size_t)record->register_bytes) == cudaSuccess)
                && (blocks > 0);
    // a count of thread blocks and of processors are positive where the runtime gave them
    record->resident = (ok != 0) ? ((unsigned long long)blocks * (unsigned long long)processors) : 0ull;
    return ok;
}

extern "C" long cycle_record_load(const EngineRecordLayout *layout, CycleRecord **record_out, EngineError *error)
{
    if (error == NULL)
    {
        return CYCLE_REFUSED;
    }
    int asked = CYCLE_HELD((layout != NULL) && (record_out != NULL), layout, error, ENGINE_ERROR_REQUEST)
             && CYCLE_HELD((layout->step_table != NULL) && (layout->steps != 0u)
                               && (layout->file_limbs <= ENGINE_RECORD_LIMBS_MOST) && (layout->out_limbs != 0u)
                               && (layout->members != 0u) && (layout->members <= ENGINE_RECORD_MEMBERS_MAX),
                           layout, error, ENGINE_ERROR_REQUEST);
    for (unsigned int member = 0u; (asked != 0) && (member < layout->members); member += 1u)
    {
        asked = CYCLE_HELD(layout->in_limbs[member] != 0u, &layout->in_limbs[member], error, ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return CYCLE_REFUSED;
    }
    *record_out = NULL;
    CycleRecord *const record = (CycleRecord *)calloc(1u, sizeof(CycleRecord));
    int ok = CYCLE_HELD(record != NULL, record_out, error, ENGINE_ERROR_RESOURCE);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_steps, (size_t)layout->steps * sizeof(DeviceRecordStep)),
                    &record->device_steps, error);
    ok = ok
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_refused, sizeof(unsigned int)), &record->device_refused, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(record->device_steps, layout->step_table,
                               (size_t)layout->steps * sizeof(DeviceRecordStep), cudaMemcpyHostToDevice),
                    record->device_steps, error);
    if ((ok != 0) && (layout->table_word_count != 0ull))
    {
        ok = CYCLE_TOOK(cudaMalloc((void **)&record->device_tables,
                                   (size_t)layout->table_word_count * sizeof(unsigned int)),
                        &record->device_tables, error)
          && CYCLE_TOOK(cudaMemcpy(record->device_tables, layout->table_values,
                                   (size_t)layout->table_word_count * sizeof(unsigned int), cudaMemcpyHostToDevice),
                        record->device_tables, error);
    }
    // the block lies in device memory, where the program's thread blocks check in without leaving the device; the host
    // keeps its own copy, read back once each launch has ended
    record->block = (EngineProgramBlock *)calloc(1u, sizeof(EngineProgramBlock));
    ok = ok && CYCLE_HELD(record->block != NULL, &record->block, error, ENGINE_ERROR_RESOURCE)
      && CYCLE_TOOK(cudaMalloc((void **)&record->device_block, sizeof(EngineProgramBlock)), &record->device_block, error)
      && CYCLE_TOOK(cudaMalloc((void **)&record->hot, sizeof(CycleHot)), &record->hot, error);
    if (ok == 0)
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    // the program is its steps, its shape and its tables, and its signum is taken over all three in that order
    const unsigned int shape[6] = {layout->members,   layout->in_limbs[0], layout->in_limbs[1],
                                   layout->in_limbs[2], layout->out_bits,  layout->file_limbs};
    std::vector<unsigned char> program((size_t)layout->steps * sizeof(DeviceRecordStep));
    memcpy(program.data(), layout->step_table, program.size());
    // a word's bytes are read as bytes, as the signum takes them
    const unsigned char *const shape_bytes = (const unsigned char *)shape;
    program.insert(program.end(), shape_bytes, shape_bytes + sizeof(shape));
    if (layout->table_word_count != 0ull)
    {
        // a table's words are read as bytes, as the signum takes them
        const unsigned char *const table_bytes = (const unsigned char *)layout->table_values;
        program.insert(program.end(), table_bytes,
                       table_bytes + ((size_t)layout->table_word_count * sizeof(unsigned int)));
    }
    const ObsignatioSignumRequest signum = {program.data(), program.size(), NULL, OBSIGNATIO_MODE_HASH,
                                            record->block->signature.bytes, ENGINE_SIGNUM_BYTES, error};
    if (obsignatio_signum(&signum) == OBSIGNATIO_REFUSED)
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    record->block->span = layout->file_limbs;
    record->block->state = ENGINE_PROGRAM_LAID;
    record->block->checksum = cycle_block_seal(record->block);
    if (!CYCLE_TOOK(cudaMemcpy(record->device_block, record->block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                    record->device_block, error))
    {
        cycle_record_release(record);
        return CYCLE_REFUSED;
    }
    record->steps = layout->steps;
    record->members = layout->members;
    record->file_limbs = layout->file_limbs;
    memcpy(record->in_limbs, layout->in_limbs, sizeof(record->in_limbs));
    record->out_limbs = layout->out_limbs;
    for (unsigned int step = 0u; step < layout->steps; step += 1u)
    {
        const unsigned int operation = layout->step_table[step].operation;
        record->divides |= ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
                            || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
                         ? 1u : 0u;
    }
    if ((cycle_environment_set("CYCLE_RECORD_INTERPRET") == 0) && (cycle_record_compile(layout, record) == 0))
    {
        // every call above held, and an error the runtime still holds is the attempt's own: the interpreter runs in
        // its place, and the error is dropped before a run reads the runtime's last error as its own
        cudaGetLastError();
    }
    cudaFuncAttributes attributes;
    const int attributed = (record->compiled != 0u)
                        && (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) == cudaSuccess);
    if (attributed != 0)
    {
        // a register count and a frame's bytes are never negative
        record->registers = (unsigned long long)attributes.numRegs;
        record->local_bytes = (unsigned long long)attributes.localSizeBytes;
    }
    // a compiled program whose registers shared memory cannot hold runs on the interpreter
    record->compiled = ((attributed != 0) && cycle_record_share(record, attributes.sharedSizeBytes)) ? 1u : 0u;
    if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (record->compiled != 0u))
    {
        fprintf(stderr, "  cycle: the program holds %llu registers a thread, a %llu-byte local frame and %u places a "
                        "thread in shared memory: %u threads a thread block in %llu bytes, %llu thread blocks at once\n",
                record->registers, record->local_bytes, record->places, record->threads, record->shared_bytes,
                record->resident);
    }
    else if ((cycle_environment_set("CYCLE_RECORD_REPORT") != 0) && (attributed != 0))
    {
        fprintf(stderr, "  cycle: a program of %u places a thread runs on the interpreter (shared memory does not "
                        "hold one thread's)\n",
                record->places);
    }
    // a grant the runtime could not read is left 0, and its error is dropped as the attempt's own
    cudaGetLastError();
    *record_out = record;
    return (long)layout->out_bits;
}

extern "C" void cycle_record_release(CycleRecord *record)
{
    if (record == NULL)
    {
        return;
    }
    cudaFree(record->device_steps);
    cudaFree(record->device_refused);
    cudaFree(record->device_tables);
    cudaFree(record->hot);
    cudaFree(record->device_block);
    // the record gives back its hold on the program it loaded, compiled or left on the interpreter after
    cycle_program_release(record->kernel);
    free(record->block);
    free(record);
}

extern "C" unsigned int cycle_record_out_limbs(const CycleRecord *record)
{
    return (record != NULL) ? record->out_limbs : 0u;
}

extern "C" unsigned int cycle_record_members(const CycleRecord *record)
{
    return (record != NULL) ? record->members : 0u;
}

extern "C" unsigned int cycle_record_in_limbs(const CycleRecord *record, unsigned int member)
{
    return ((record != NULL) && (member < record->members)) ? record->in_limbs[member] : 0u;
}

// The compiled program run resident. Its block is laid for this run and sent to the device, and the program is
// launched, then launched again from where its block says it stands, until every lane is done. The host reads the
// block back only between launches, when it is sealed: a device block whose seal does not hold (written while no launch
// held it), a launch that failed, or a launch that left the block anywhere but yielded or done refuses the run, and
// the host's copy is left sealed at the fault with the error's module and site. It runs on as many thread blocks as the
// device holds at once, or fewer where the lanes need fewer. A thread block takes the threads its registers' shared
// memory holds, or where the lanes are few, their share of the device's processors in whole warps, so that a launch of
// a few thousand lanes reaches every processor and not only a few thread blocks' worth.
static int cycle_record_resident(const CycleRecord *record, CycleCompiledLaunch program, EngineError *error)
{
    const unsigned long long share = (program.count + record->processors - 1ull) / record->processors;
    const unsigned long long warps = ((share + 31ull) / 32ull) * 32ull;
    // at most record->threads, itself at most CYCLE_BLOCK
    const unsigned int threads = (unsigned int)((warps < record->threads) ? warps : record->threads);
    const unsigned long long needed = (program.count + threads - 1ull) / threads;
    // the device's thread blocks at once are a small count, far under 2^31
    const unsigned int blocks = (unsigned int)((needed < record->resident) ? needed : record->resident);
    const unsigned long long register_bytes = threads * record->thread_bytes;
    EngineProgramBlock *const block = record->block;
    const unsigned long long ttl = 1000ull * cycle_environment_microseconds("CYCLE_RECORD_TTL",
                                                                              CYCLE_PROGRAM_TTL_MICROSECONDS);
    const unsigned long long wdt = 1000ull * CYCLE_PROGRAM_WDT_MICROSECONDS;
    const EngineSignum signature = block->signature;
    const unsigned long long generation = block->generation + 1ull;
    memset(block, 0, sizeof(EngineProgramBlock));
    block->signature = signature;
    block->generation = generation;
    block->command = ENGINE_PROGRAM_RUN;
    block->grant_registers = record->registers;
    block->grant_threads = (unsigned long long)blocks * threads;
    block->grant_bytes = record->local_bytes * block->grant_threads;
    // the kernel's own shared memory, and its threads' registers at this launch's threads
    block->grant_shared = (record->shared_bytes - record->register_bytes) + register_bytes;
    block->state = ENGINE_PROGRAM_LAID;
    block->span = record->file_limbs;
    block->ttl = ttl;
    block->wdt = wdt;
    block->lanes = program.count;
    // a device address is held as a 64-bit word, as every word of the block is
    block->result = (unsigned long long)(uintptr_t)program.out;
    block->result_words = program.count * record->out_limbs;
    block->checksum = cycle_block_seal(block);
    program.hot = record->hot;
    // the block is 64-bit words throughout, and the program reads it as them at its device address
    program.block = (unsigned long long *)record->device_block;
    program.ttl = ttl;
    program.checkin_every = wdt / CYCLE_PROGRAM_CHECKINS_PER_WDT;
    program.places = record->places;
    EngineProgramBlock *const device_block = record->device_block;
    int ok = CYCLE_TOOK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                        device_block, error)
          && CYCLE_TOOK(cudaMemset(record->hot, 0, sizeof(CycleHot)), record->hot, error);
    int running = ok;
    while (running != 0)
    {
        ok = CYCLE_TOOK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost), device_block,
                        error)
          && CYCLE_HELD(block->checksum == cycle_block_seal(block), block, error, ENGINE_ERROR_LOGIC);
        if (ok == 0)
        {
            break;
        }
        block->launches += 1ull;
        block->owner = block->launches;
        block->state = ENGINE_PROGRAM_RUNNING;
        program.launch_number = block->launches;
        ok = CYCLE_TOOK(cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice),
                        device_block, error);
        // a launch's start and its thread blocks gone begin at 0, and the next lane runs on from the last launch's
        ok = ok
          && CYCLE_TOOK(cudaMemset(&record->hot->launch_start, 0, 2u * sizeof(unsigned long long)), record->hot, error);
        void *arguments[1] = {&program};
        // a library's kernel handle is what the runtime launches in place of a kernel's address
        ok = ok
          && CYCLE_TOOK(cudaLaunchKernel((const void *)record->kernel, dim3(blocks), dim3(threads), arguments,
                                         (size_t)register_bytes, 0),
                        program.out, error);
        ok = ok && CYCLE_TOOK(cudaDeviceSynchronize(), program.out, error);
        unsigned int refused = 0u;
        ok = ok
          && CYCLE_TOOK(cudaMemcpy(&refused, record->device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                        record->device_refused, error)
          && CYCLE_TOOK(cudaMemcpy(block, device_block, sizeof(EngineProgramBlock), cudaMemcpyDeviceToHost),
                        device_block, error);
        const unsigned long long state = block->state;
        ok = ok && CYCLE_HELD((state == ENGINE_PROGRAM_YIELDED) || (state == ENGINE_PROGRAM_DONE), block, error,
                              ENGINE_ERROR_LOGIC);
        block->refused = refused;
        block->runtime += block->exectime;
        if (ok == 0)
        {
            block->state = ENGINE_PROGRAM_FAULT;
            // an engine module and a site are small non-negative counts, held whole in a 64-bit word
            block->error_module = (unsigned long long)error->module;
            block->error_site = (unsigned long long)error->site;
        }
        block->checksum = cycle_block_seal(block);
        // the sealed block goes back to the device, where the next launch finds it; a fault is left sealed on the
        // host's copy whether or not the device can still take it
        const cudaError_t sent = cudaMemcpy(device_block, block, sizeof(EngineProgramBlock), cudaMemcpyHostToDevice);
        ok = ok && CYCLE_TOOK(sent, device_block, error);
        running = (ok != 0) && (state == ENGINE_PROGRAM_YIELDED);
    }
    return ok;
}

// one launch of a record program, compiled or on the interpreter, run to its end: a compiled program runs resident,
// launched again until it is done. With `milliseconds` it is timed by events on either side of it, the device's own
// time between them
static int cycle_record_launch(const CycleRecord *record, const CycleRecordLaunch &launch, unsigned int blocks,
                               int compiled, float *milliseconds, EngineError *error)
{
    cudaEvent_t began = NULL;
    cudaEvent_t ended = NULL;
    int ok = (milliseconds == NULL)
          || (CYCLE_TOOK(cudaEventCreate(&began), &began, error) && CYCLE_TOOK(cudaEventCreate(&ended), &ended, error)
              && CYCLE_TOOK(cudaEventRecord(began, 0), began, error));
    if ((ok != 0) && (compiled != 0))
    {
        CycleCompiledLaunch program;
        memset(&program, 0, sizeof(program));
        for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
        {
            program.in[member] = launch.in[member];
            program.bodies[member] = launch.bodies[member];
        }
        program.index = launch.index;
        program.tables = launch.tables;
        program.out = launch.out;
        program.refused = launch.refused;
        program.count = launch.count;
        ok = cycle_record_resident(record, program, error);
    }
    else if ((ok != 0) && (record->file_limbs <= 64u) && (record->divides != 0u))
    {
        cycle_record_kernel<64u, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if ((ok != 0) && (record->file_limbs <= 64u))
    {
        cycle_record_kernel<64u, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if ((ok != 0) && (record->divides != 0u))
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 1u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    else if (ok != 0)
    {
        cycle_record_kernel<ENGINE_RECORD_LIMBS_MOST, 0u><<<blocks, CYCLE_BLOCK>>>(launch);
    }
    // the launch's own error is read and reset whichever way it launched
    const cudaError_t launched = cudaGetLastError();
    ok = ok && CYCLE_TOOK(launched, launch.out, error);
    ok = ok && ((milliseconds == NULL) || CYCLE_TOOK(cudaEventRecord(ended, 0), ended, error));
    ok = ok && CYCLE_TOOK(cudaDeviceSynchronize(), launch.out, error);
    ok = ok && ((milliseconds == NULL) || CYCLE_TOOK(cudaEventElapsedTime(milliseconds, began, ended), milliseconds, error));
    if (began != NULL)
    {
        cudaEventDestroy(began);
    }
    if (ended != NULL)
    {
        cudaEventDestroy(ended);
    }
    return ok;
}

// CYCLE_RECORD_CHECK: the compiled program has run into the request's records; the interpreter runs the same lanes
// into records of its own, and both runs' records and refusals must be the same word for word. The compiled run's
// refusals are put back for the run to read
static int cycle_record_check(const CycleRecord *record, CycleRecordLaunch launch, unsigned int blocks,
                              float compiled_milliseconds, int report, EngineError *error)
{
    const size_t words = (size_t)launch.count * record->out_limbs;
    std::vector<unsigned int> compiled_records(words);
    std::vector<unsigned int> interpreted_records(words);
    unsigned int compiled_refused = 0u;
    unsigned int interpreted_refused = 0u;
    unsigned int *interpreted = NULL;
    float interpreted_milliseconds = 0.0f;
    int ok = CYCLE_TOOK(cudaMemcpy(&compiled_refused, record->device_refused, sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost),
                        record->device_refused, error)
          && CYCLE_TOOK(cudaMemcpy(compiled_records.data(), launch.out, words * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost),
                        launch.out, error)
          && CYCLE_TOOK(cudaMalloc((void **)&interpreted, words * sizeof(unsigned int)), &interpreted, error)
          && CYCLE_TOOK(cudaMemset(record->device_refused, 0, sizeof(unsigned int)), record->device_refused, error);
    launch.out = interpreted;
    ok = ok && cycle_record_launch(record, launch, blocks, 0, (report != 0) ? &interpreted_milliseconds : NULL, error);
    ok = ok
      && CYCLE_TOOK(cudaMemcpy(&interpreted_refused, record->device_refused, sizeof(unsigned int),
                               cudaMemcpyDeviceToHost),
                    record->device_refused, error)
      && CYCLE_TOOK(cudaMemcpy(interpreted_records.data(), interpreted, words * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost),
                    interpreted, error)
      && CYCLE_TOOK(cudaMemcpy(record->device_refused, &compiled_refused, sizeof(unsigned int), cudaMemcpyHostToDevice),
                    record->device_refused, error);
    cudaFree(interpreted);
    size_t differs = words;
    for (size_t at = 0u; (ok != 0) && (differs == words) && (at < words); at += 1u)
    {
        differs = (compiled_records[at] != interpreted_records[at]) ? at : words;
    }
    const int same = (differs == words) && (compiled_refused == interpreted_refused);
    if ((ok != 0) && (report != 0))
    {
        fprintf(stderr, "  cycle: %llu lanes, compiled %.3f ms, interpreted %.3f ms, refused %u and %u, %s\n",
                launch.count, compiled_milliseconds, interpreted_milliseconds, compiled_refused, interpreted_refused,
                (same != 0) ? "the same records" : "records differ");
    }
    if ((ok != 0) && (same == 0) && (differs != words))
    {
        fprintf(stderr, "  cycle: the compiled record program differs from the interpreter at lane %zu, word %zu: %08x "
                        "against %08x\n",
                differs / record->out_limbs, differs % record->out_limbs, compiled_records[differs],
                interpreted_records[differs]);
    }
    return ok && CYCLE_HELD(same != 0, record->device_refused, error, ENGINE_ERROR_LOGIC);
}

extern "C" long cycle_record_run(const CycleRecordRunRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!CYCLE_HELD((request->record != NULL) && (request->device_out != NULL) && (request->count != 0ull), request,
                    error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    const CycleRecord *const record = request->record;
    CycleRecordLaunch launch;
    memset(&launch, 0, sizeof(launch));
    for (unsigned int member = 0u; member < record->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        if (!CYCLE_HELD((request->device_in[member] != NULL) && (request->bodies[member] != 0ull)
                            && ((request->device_index != NULL) || (request->count <= request->bodies[member])
                                || (request->bodies[member] == 1ull)),
                        &request->device_in[member], error, ENGINE_ERROR_REQUEST))
        {
            return CYCLE_REFUSED;
        }
        launch.in[member] = request->device_in[member];
        launch.bodies[member] = request->bodies[member];
        launch.in_limbs[member] = record->in_limbs[member];
    }
    launch.steps = record->device_steps;
    launch.index = request->device_index;
    launch.tables = record->device_tables;
    launch.out = request->device_out;
    launch.refused = record->device_refused;
    launch.count = request->count;
    launch.step_count = record->steps;
    launch.members = record->members;
    launch.out_limbs = record->out_limbs;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MOST) ? needed : CYCLE_RECORD_BLOCKS_MOST);
    const int compiled = (record->compiled != 0u) ? 1 : 0;
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int check = (compiled != 0) && (cycle_environment_set("CYCLE_RECORD_CHECK") != 0);
    unsigned int refused = 1u;
    size_t stack = 0u;
    float milliseconds = 0.0f;
    int ok = CYCLE_TOOK(cudaDeviceGetLimit(&stack, cudaLimitStackSize), &stack, error)
          && CYCLE_TOOK(cudaMemset(record->device_refused, 0, sizeof(unsigned int)), record->device_refused, error);
    ok = ok && cycle_record_launch(record, launch, blocks, compiled, (report != 0) ? &milliseconds : NULL, error);
    ok = ok && ((check == 0) || cycle_record_check(record, launch, blocks, milliseconds, report, error));
    if ((ok != 0) && (report != 0) && (check == 0))
    {
        fprintf(stderr, "  cycle: %llu lanes %s in %.3f ms\n", request->count,
                (compiled != 0) ? "compiled" : "interpreted", milliseconds);
    }
    if ((ok != 0) && (report != 0) && (compiled != 0))
    {
        fprintf(stderr, "  cycle: the program ran %llu launches, %llu check-ins, %.3f ms on the device, %llu threads\n",
                record->block->launches, record->block->checkin, (double)record->block->runtime / 1e6,
                record->block->grant_threads);
    }
    // the frame's reservation is given back whether or not the sweep held
    const int returned = cycle_stack_return(stack, request->device_out, error);
    ok = ok && returned
      && CYCLE_TOOK(cudaMemcpy(&refused, record->device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    record->device_refused, error)
      && CYCLE_HELD(refused == 0u, record->device_refused, error, ENGINE_ERROR_REQUEST);
    return (ok != 0) ? (long)request->count : CYCLE_REFUSED;
}

// 1 where a record's `bits` bits at `offset` are not all zero
__device__ static int cycle_latch_holds(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned int held = 0u;
    for (unsigned int bit = offset; bit < (offset + bits);)
    {
        const unsigned int shift = bit % 32u;
        const unsigned int left = offset + bits - bit;
        const unsigned int taken = (left < (32u - shift)) ? left : (32u - shift);
        const unsigned int mask = (taken == 32u) ? 0xFFFFFFFFu : (((1u << taken) - 1u) << shift);
        held |= record[bit / 32u] & mask;
        bit += taken;
    }
    return (held != 0u) ? 1 : 0;
}

// the latch over the records: each thread scans its lanes from its lowest and stops at the first whose output holds,
// each warp takes the least of its threads' by a tree of shuffles, and each warp's goes to one atomic minimum over the
// device. Every thread of a warp reaches the shuffles, the block being whole warps
__global__ static void cycle_latch_kernel(const unsigned int *records, unsigned long long count, unsigned int out_limbs,
                                          unsigned int offset, unsigned int bits, unsigned long long *first)
{
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long found = CYCLE_LATCH_NONE;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         (found == CYCLE_LATCH_NONE) && (lane < count); lane += stride)
    {
        found = (cycle_latch_holds(&records[lane * out_limbs], offset, bits) != 0) ? lane : CYCLE_LATCH_NONE;
    }
    for (unsigned int reach = 16u; reach > 0u; reach /= 2u)
    {
        const unsigned long long other = __shfl_down_sync(0xFFFFFFFFu, found, reach);
        found = (other < found) ? other : found;
    }
    if (((threadIdx.x % 32u) == 0u) && (found != CYCLE_LATCH_NONE))
    {
        atomicMin(first, found);
    }
}

static_assert((CYCLE_BLOCK % 32u) == 0u, "cycle: the latch's thread blocks are whole warps");

extern "C" long cycle_record_latch(const CycleRecordLatchRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return CYCLE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!CYCLE_HELD((request->records != NULL) && (request->first != NULL) && (request->count != 0ull)
                        && (request->out_limbs != 0u) && (request->bits != 0u)
                        && (((unsigned long long)request->offset + request->bits)
                            <= (32ull * (unsigned long long)request->out_limbs)),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return CYCLE_REFUSED;
    }
    unsigned long long *device_first = NULL;
    unsigned long long first = CYCLE_LATCH_NONE;
    const unsigned long long needed = (request->count + CYCLE_BLOCK - 1ull) / CYCLE_BLOCK;
    const unsigned int blocks = (unsigned int)((needed < CYCLE_RECORD_BLOCKS_MOST) ? needed : CYCLE_RECORD_BLOCKS_MOST);
    int ok = CYCLE_TOOK(cudaMalloc((void **)&device_first, sizeof(unsigned long long)), &device_first, error)
          && CYCLE_TOOK(cudaMemcpy(device_first, &first, sizeof(unsigned long long), cudaMemcpyHostToDevice),
                        device_first, error);
    if (ok != 0)
    {
        cycle_latch_kernel<<<blocks, CYCLE_BLOCK>>>(request->records, request->count, request->out_limbs,
                                                    request->offset, request->bits, device_first);
    }
    ok = ok && CYCLE_TOOK(cudaGetLastError(), device_first, error)
      && CYCLE_TOOK(cudaDeviceSynchronize(), device_first, error)
      && CYCLE_TOOK(cudaMemcpy(&first, device_first, sizeof(unsigned long long), cudaMemcpyDeviceToHost), device_first,
                    error);
    cudaFree(device_first);
    if (ok == 0)
    {
        return CYCLE_REFUSED;
    }
    *request->first = first;
    return (long)request->count;
}
