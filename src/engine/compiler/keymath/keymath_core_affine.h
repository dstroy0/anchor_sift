// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// keymath_core_affine.h: word bits, reads, magnitudes and the forms (keymath_core.h includes the parts in order)
#ifndef KEYMATH_CORE_AFFINE_H
#define KEYMATH_CORE_AFFINE_H

// keymath's record encoding as one source the host and the device both compile (engine_table.md item 11(f)(a), the
// compiler on the device): each step's term and width, read from its operation and its operands' in step order, and
// each register's linear form, which narrows the width where it is tighter. The host's keymath_record_encode runs it
// and lays out the key; the device runs it in one thread, since each step reads the steps before it. A linear form's
// terms are held in an arena the caller gives, each form a run of it; an arena too small for the forms is reported, and
// the caller gives a larger one and runs the encoding again, which decides the same

#include "engine_config.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define KEYMATH_CORE __host__ __device__ static inline
#else
#define KEYMATH_CORE static inline
#endif

// a coefficient or constant of a linear form stays within this. A sum of two and the product by a constant are then
// checked in one word before either is formed: two at the limit sum to 2^63, past a signed word
#define KEYMATH_COEFFICIENT_MAX (1ll << 62)

// the limbs a form's bound takes: an atom's register is at most 32 ENGINE_RECORD_LIMBS_MAX bits and a coefficient at
// most 2^62. Each term is below 2^(32 ENGINE_RECORD_LIMBS_MAX + 63), and the sum of fewer than 2^32 of them below
// 2^(32 ENGINE_RECORD_LIMBS_MAX + 95)
#define KEYMATH_BOUND_LIMBS (ENGINE_RECORD_LIMBS_MAX + 3u)

// the terms an encode's first run gives each step's linear form, on the host and the device; a run that fills its
// arena runs again with one twice the size, which decides the same
#define KEYMATH_ARENA_PER_STEP 8u

// how an encode ends: every step held; a step refused, or a step's table, or an output, the one at `at`; or the arena
// too small for the forms
enum KeymathCoreEnd
{
    KEYMATH_CORE_OK = 0,
    KEYMATH_CORE_STEP = 1,
    KEYMATH_CORE_TABLE = 2,
    KEYMATH_CORE_OUTPUT = 3,
    KEYMATH_CORE_FULL = 4
};

// one term of a linear form: an atom, an earlier register the form does not open, and its coefficient
struct KeymathCoreTerm
{
    unsigned int atom;
    long long coefficient;
};

// a register as a linear form: integer coefficients over atoms, each an earlier register the form does not open (a
// field, or any register no sum, difference or product by a constant made), plus a constant. Every register has one;
// an atom's is itself with coefficient 1. Its terms are `count` of the arena from `first`, ordered by atom. Its width
// is read from the form (A16, Mathai and Thiang's bulk-boundary map read as a restriction on the dual side): |x| <= |c|
// + sum |c_i| (2^(b_i) - 1) over the atoms' widths b_i
struct KeymathCoreAffine
{
    long long constant;
    unsigned long long first;
    unsigned long long count;
};

// the terms the forms are laid out in: `capacity` of them, `used` taken, and 1 in `full` once a form found no room
struct KeymathCoreArena
{
    KeymathCoreTerm *terms;
    unsigned long long capacity;
    unsigned long long used;
    int full;
};

// an encode: its steps and the fields', members' and tables' sizes it reads, its outputs; each step's term, 1 where
// its register is never negative, and its form, in step order; the arena; KEYMATH_BOUND_LIMBS words a form's bound is
// summed in, the caller's, since they are past what a device thread's stack holds; and where it ended, and at what
struct KeymathCoreEncode
{
    const EngineRecordStep *steps;
    unsigned int count;
    const unsigned int *field_bits;
    unsigned int fields;
    unsigned int members;
    const unsigned int *outputs;
    unsigned int output_count;
    const EngineRecordTable *tables;
    unsigned int table_count;
    EngineRecordTerm *terms;
    unsigned char *never_negative;
    KeymathCoreAffine *forms;
    KeymathCoreArena arena;
    unsigned int *bound;
    unsigned int end;
    unsigned int at;
};

KEYMATH_CORE unsigned int keymath_core_word_bits(unsigned long long value)
{
    unsigned int bits = 0u;
    while (value != 0ull)
    {
        bits += 1u;
        value >>= 1u;
    }
    return bits;
}

KEYMATH_CORE int keymath_core_record_reads(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM) ||
           (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER) ||
           (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_COMPARE) ||
           (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER) ||
           (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT) ||
           (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND);
}

// whether a step's register is never negative, read from its operation and its operands': a field read unsigned, a
// constant, an absolute value, a gcd, a table's entry and the lane's number are never negative; so are a sum, product,
// quotient, exact quotient or xor of two such, a remainder of one such (it carries the numerator's sign), an and with
// one such, and a wrap that passes one such through unchanged
KEYMATH_CORE unsigned char keymath_core_never_negative(const EngineRecordStep *doing,
                                                       const unsigned char *never_negative, int wrap_passes)
{
    const unsigned int operation = doing->operation;
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT) ||
        (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_GCD) ||
        (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_LANE))
    {
        return 1u;
    }
    if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_PRODUCT) ||
        (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_EXACT_QUOTIENT) ||
        (operation == ENGINE_RECORD_XOR))
    {
        return ((never_negative[doing->left] != 0u) && (never_negative[doing->right] != 0u)) ? 1u : 0u;
    }
    if (operation == ENGINE_RECORD_REMAINDER)
    {
        return never_negative[doing->left];
    }
    if (operation == ENGINE_RECORD_AND)
    {
        return ((never_negative[doing->left] != 0u) || (never_negative[doing->right] != 0u)) ? 1u : 0u;
    }
    if (operation == ENGINE_RECORD_WRAP)
    {
        return ((wrap_passes != 0) && (never_negative[doing->left] != 0u)) ? 1u : 0u;
    }
    return 0u;
}

KEYMATH_CORE long long keymath_core_magnitude(long long value)
{
    return (value < 0ll) ? -value : value;
}

// left + right, each within KEYMATH_COEFFICIENT_MAX, into *sum; 0, and *sum 0, where the sum would pass it. The test
// is made before the sum is formed, and each side of it stays within the limit: no word overflows
KEYMATH_CORE int keymath_core_sum_fits(long long left, long long right, long long *sum)
{
    const int fits =
        (right >= 0ll) ? (left <= (KEYMATH_COEFFICIENT_MAX - right)) : (left >= (-KEYMATH_COEFFICIENT_MAX - right));
    *sum = fits ? (left + right) : 0ll;
    return fits;
}

// a term taken onto the arena's end; 0, and the arena marked full, where it has no room
KEYMATH_CORE int keymath_core_push(KeymathCoreArena *arena, unsigned int atom, long long coefficient)
{
    if (arena->used >= arena->capacity)
    {
        arena->full = 1;
        return 0;
    }
    arena->terms[arena->used].atom = atom;
    arena->terms[arena->used].coefficient = coefficient;
    arena->used += 1ull;
    return 1;
}

// left + sign right, the terms merged by atom, laid out at the arena's end into *sum; 0 where a coefficient or the
// constant would pass KEYMATH_COEFFICIENT_MAX or the arena is full
KEYMATH_CORE int keymath_core_affine_add(KeymathCoreArena *arena, const KeymathCoreAffine *left,
                                         const KeymathCoreAffine *right, long long sign, KeymathCoreAffine *sum)
{
    sum->first = arena->used;
    sum->count = 0ull;
    int ok = keymath_core_sum_fits(left->constant, sign * right->constant, &sum->constant);
    unsigned long long at_left = 0ull;
    unsigned long long at_right = 0ull;
    while (ok && ((at_left < left->count) || (at_right < right->count)))
    {
        const KeymathCoreTerm *const left_term = &arena->terms[left->first + at_left];
        const KeymathCoreTerm *const right_term = &arena->terms[right->first + at_right];
        const int take_left =
            (at_right == right->count) || ((at_left < left->count) && (left_term->atom <= right_term->atom));
        const int take_right =
            (at_left == left->count) || ((at_right < right->count) && (right_term->atom <= left_term->atom));
        const unsigned int atom = take_left ? left_term->atom : right_term->atom;
        long long coefficient = 0ll;
        ok = keymath_core_sum_fits(take_left ? left_term->coefficient : 0ll,
                                   take_right ? (sign * right_term->coefficient) : 0ll, &coefficient);
        at_left += take_left ? 1ull : 0ull;
        at_right += take_right ? 1ull : 0ull;
        if (ok && (coefficient != 0ll))
        {
            ok = keymath_core_push(arena, atom, coefficient);
            sum->count += ok ? 1ull : 0ull;
        }
    }
    return ok;
}

// the form times a constant, laid out at the arena's end into *scaled; 0 where a coefficient or the constant would pass
// KEYMATH_COEFFICIENT_MAX or the arena is full
KEYMATH_CORE int keymath_core_affine_scale(KeymathCoreArena *arena, const KeymathCoreAffine *form, long long factor,
                                           KeymathCoreAffine *scaled)
{
    const long long maximum =
        (factor == 0ll) ? KEYMATH_COEFFICIENT_MAX : (KEYMATH_COEFFICIENT_MAX / keymath_core_magnitude(factor));
    int ok = keymath_core_magnitude(form->constant) <= maximum;
    scaled->constant = ok ? (form->constant * factor) : 0ll;
    scaled->first = arena->used;
    scaled->count = 0ull;
    for (unsigned long long at = 0ull; ok && (at < form->count) && (factor != 0ll); at += 1ull)
    {
        const KeymathCoreTerm term = arena->terms[form->first + at];
        ok = keymath_core_magnitude(term.coefficient) <= maximum;
        // a coefficient past the limit is not multiplied, since its product can pass a signed word
        if (ok)
        {
            ok = keymath_core_push(arena, term.atom, term.coefficient * factor);
            scaled->count += ok ? 1ull : 0ull;
        }
    }
    return ok;
}

// a magnitude of at most 2^62 shifted up by `shift` bits, added into the bound's limbs; the bound holds the sum
KEYMATH_CORE void keymath_core_add_shifted(unsigned int *bound, unsigned long long magnitude, unsigned long long shift)
{
    const unsigned int part = (unsigned int)(shift % 32ull);
    // the shift is below 32 KEYMATH_BOUND_LIMBS, and its whole limbs fit an unsigned int
    const unsigned int limb_shift = (unsigned int)(shift / 32ull);
    // the magnitude is at most 2^62, and shifted by fewer than 32 bits it spans at most three limbs
    const unsigned long long low = magnitude << part;
    const unsigned long long high = (part == 0u) ? 0ull : (magnitude >> (64u - part));
    const unsigned int added[3] = {(unsigned int)(low & 0xFFFFFFFFull), (unsigned int)(low >> 32u), (unsigned int)high};
    unsigned long long carry = 0ull;
    // past the three limbs added, the sum changes only while a carry runs
    for (unsigned int limb = limb_shift;
         (limb < KEYMATH_BOUND_LIMBS) && (((limb - limb_shift) < 3u) || (carry != 0ull)); limb += 1u)
    {
        const unsigned long long total =
            carry + bound[limb] + (((limb - limb_shift) < 3u) ? added[limb - limb_shift] : 0u);
        bound[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

#endif
