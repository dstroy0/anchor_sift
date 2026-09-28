// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef KEYMATH_CORE_H
#define KEYMATH_CORE_H

// keymath's record imprint as one source the host and the device both compile (engine_table.md item 11(f)(a), the
// compiler on the device): each step's term and width, read from its operation and its operands' in step order, and each
// register's linear form, which narrows the width where it is tighter. The host's keymath_record_imprint runs it and
// lays the key; the device runs it in one thread, since each step reads the steps before it. A linear form's terms are
// held in an arena the caller gives, each form a run of it; an arena too small for the forms is reported, and the
// caller gives a larger one and runs the imprint again, which decides the same

#include "engine_config.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define KEYMATH_CORE __host__ __device__ static inline
#else
#define KEYMATH_CORE static inline
#endif

// a coefficient or constant of a linear form stays within this. A sum of two and the product by a constant are then
// checked in one word before either is formed: two at the limit sum to 2^63, past a signed word
#define KEYMATH_COEFFICIENT_MOST (1ll << 62)

// the limbs a form's bound takes: an atom's register is at most 32 ENGINE_RECORD_LIMBS_MOST bits and a coefficient at
// most 2^62. Each term is below 2^(32 ENGINE_RECORD_LIMBS_MOST + 63), and the sum of fewer than 2^32 of them below
// 2^(32 ENGINE_RECORD_LIMBS_MOST + 95)
#define KEYMATH_BOUND_LIMBS (ENGINE_RECORD_LIMBS_MOST + 3u)

// the terms an imprint's first run gives each step's linear form, on the host and the device; a run that fills its arena
// runs again with one twice the size, which decides the same
#define KEYMATH_ARENA_PER_STEP 8u

// how an imprint ends: every step held; a step refused, or a step's table, or an output, the one at `at`; or the arena
// too small for the forms
enum KeymathCoreEnd
{
    KEYMATH_CORE_HELD = 0,
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
// an atom's is itself with coefficient 1. Its terms are `count` of the arena from `first`, ordered by atom. Its width is
// read from the form (A16, Mathai and Thiang's bulk-boundary map read as a restriction on the dual side):
// |x| <= |c| + sum |c_i| (2^(b_i) - 1) over the atoms' widths b_i
struct KeymathCoreForm
{
    long long constant;
    unsigned long long first;
    unsigned long long count;
};

// the terms the forms are laid in: `capacity` of them, `used` taken, and 1 in `full` once a form found no room
struct KeymathCoreArena
{
    KeymathCoreTerm *terms;
    unsigned long long capacity;
    unsigned long long used;
    int full;
};

// an imprint: its steps and the fields', members' and tables' shapes it reads, its outputs; each step's term, 1 where
// its register is never negative, and its form, in step order; the arena; KEYMATH_BOUND_LIMBS words a form's bound is
// summed in, the caller's, since they are past what a device thread's stack holds; and where it ended, and at what
struct KeymathCoreImprint
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
    KeymathCoreForm *forms;
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
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_COMPARE)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
        || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND);
}

// whether a step's register is never negative, read from its operation and its operands': a field read unsigned, a
// constant, an absolute value, a gcd, a table's entry and the lane's number are never negative; so are a sum, product,
// quotient, exact quotient or xor of two such, a remainder of one such (it carries the numerator's sign), an and with
// one such, and a wrap that passes one such through unchanged
KEYMATH_CORE unsigned char keymath_core_never_negative(const EngineRecordStep *doing,
                                                       const unsigned char *never_negative, int wrap_passes)
{
    const unsigned int operation = doing->operation;
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_CONSTANT)
        || (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_GCD)
        || (operation == ENGINE_RECORD_TABLE) || (operation == ENGINE_RECORD_LANE))
    {
        return 1u;
    }
    if ((operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_PRODUCT)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_EXACT_QUOTIENT)
        || (operation == ENGINE_RECORD_XOR))
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

// left + right, each within KEYMATH_COEFFICIENT_MOST, into *sum; 0, and *sum 0, where the sum would pass it. The test
// is made before the sum is formed, and each side of it stays within the limit: no word overflows
KEYMATH_CORE int keymath_core_sum_held(long long left, long long right, long long *sum)
{
    const int held = (right >= 0ll) ? (left <= (KEYMATH_COEFFICIENT_MOST - right))
                                    : (left >= (-KEYMATH_COEFFICIENT_MOST - right));
    *sum = held ? (left + right) : 0ll;
    return held;
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

// left + sign right, the terms merged by atom, laid at the arena's end into *sum; 0 where a coefficient or the
// constant would pass KEYMATH_COEFFICIENT_MOST or the arena is full
KEYMATH_CORE int keymath_core_form_add(KeymathCoreArena *arena, const KeymathCoreForm *left,
                                       const KeymathCoreForm *right, long long sign, KeymathCoreForm *sum)
{
    sum->first = arena->used;
    sum->count = 0ull;
    int held = keymath_core_sum_held(left->constant, sign * right->constant, &sum->constant);
    unsigned long long at_left = 0ull;
    unsigned long long at_right = 0ull;
    while (held && ((at_left < left->count) || (at_right < right->count)))
    {
        const KeymathCoreTerm *const left_term = &arena->terms[left->first + at_left];
        const KeymathCoreTerm *const right_term = &arena->terms[right->first + at_right];
        const int take_left = (at_right == right->count)
                           || ((at_left < left->count) && (left_term->atom <= right_term->atom));
        const int take_right = (at_left == left->count)
                            || ((at_right < right->count) && (right_term->atom <= left_term->atom));
        const unsigned int atom = take_left ? left_term->atom : right_term->atom;
        long long coefficient = 0ll;
        held = keymath_core_sum_held(take_left ? left_term->coefficient : 0ll,
                                     take_right ? (sign * right_term->coefficient) : 0ll, &coefficient);
        at_left += take_left ? 1ull : 0ull;
        at_right += take_right ? 1ull : 0ull;
        if (held && (coefficient != 0ll))
        {
            held = keymath_core_push(arena, atom, coefficient);
            sum->count += held ? 1ull : 0ull;
        }
    }
    return held;
}

// the form times a constant, laid at the arena's end into *scaled; 0 where a coefficient or the constant would pass
// KEYMATH_COEFFICIENT_MOST or the arena is full
KEYMATH_CORE int keymath_core_form_scale(KeymathCoreArena *arena, const KeymathCoreForm *form, long long factor,
                                         KeymathCoreForm *scaled)
{
    const long long most = (factor == 0ll) ? KEYMATH_COEFFICIENT_MOST
                                           : (KEYMATH_COEFFICIENT_MOST / keymath_core_magnitude(factor));
    int held = keymath_core_magnitude(form->constant) <= most;
    scaled->constant = held ? (form->constant * factor) : 0ll;
    scaled->first = arena->used;
    scaled->count = 0ull;
    for (unsigned long long at = 0ull; held && (at < form->count) && (factor != 0ll); at += 1ull)
    {
        const KeymathCoreTerm term = arena->terms[form->first + at];
        held = keymath_core_magnitude(term.coefficient) <= most;
        // a coefficient past the limit is not multiplied, since its product can pass a signed word
        if (held)
        {
            held = keymath_core_push(arena, term.atom, term.coefficient * factor);
            scaled->count += held ? 1ull : 0ull;
        }
    }
    return held;
}

// a magnitude of at most 2^62 shifted up by `shift` bits, added into the bound's limbs; the bound holds the sum
KEYMATH_CORE void keymath_core_add_shifted(unsigned int *bound, unsigned long long magnitude, unsigned long long shift)
{
    const unsigned int part = (unsigned int)(shift % 32ull);
    // the shift is below 32 KEYMATH_BOUND_LIMBS, and its whole limbs fit an unsigned int
    const unsigned int whole = (unsigned int)(shift / 32ull);
    // the magnitude is at most 2^62, and shifted by fewer than 32 bits it spans at most three limbs
    const unsigned long long low = magnitude << part;
    const unsigned long long high = (part == 0u) ? 0ull : (magnitude >> (64u - part));
    const unsigned int added[3] = {(unsigned int)(low & 0xFFFFFFFFull), (unsigned int)(low >> 32u), (unsigned int)high};
    unsigned long long carry = 0ull;
    // past the three limbs added, the sum changes only while a carry runs
    for (unsigned int limb = whole; (limb < KEYMATH_BOUND_LIMBS) && (((limb - whole) < 3u) || (carry != 0ull));
         limb += 1u)
    {
        const unsigned long long total = carry + bound[limb] + (((limb - whole) < 3u) ? added[limb - whole] : 0u);
        bound[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

// the bits a form's value needs: with B = |c| + sum |c_i| 2^(b_i), the value is at most B - 1 where any atom is read,
// since each atom is below 2^(b_i), and at most |c| where none is; B summed in `bound`, KEYMATH_BOUND_LIMBS words
KEYMATH_CORE unsigned int keymath_core_form_bits(const KeymathCoreArena *arena, const KeymathCoreForm *form,
                                                 const EngineRecordTerm *terms, unsigned int *bound)
{
    for (unsigned int limb = 0u; limb < KEYMATH_BOUND_LIMBS; limb += 1u)
    {
        bound[limb] = 0u;
    }
    // a magnitude within KEYMATH_COEFFICIENT_MOST fits an unsigned word
    keymath_core_add_shifted(bound, (unsigned long long)keymath_core_magnitude(form->constant), 0ull);
    for (unsigned long long at = 0ull; at < form->count; at += 1ull)
    {
        const KeymathCoreTerm *const term = &arena->terms[form->first + at];
        // a coefficient within KEYMATH_COEFFICIENT_MOST fits an unsigned word
        keymath_core_add_shifted(bound, (unsigned long long)keymath_core_magnitude(term->coefficient),
                                 terms[term->atom].bits);
    }
    // an atom's coefficient is never 0: a form of any term bounds at least 1, and 1 less it takes no borrow past it
    for (unsigned int limb = 0u; (form->count != 0ull) && (limb < KEYMATH_BOUND_LIMBS); limb += 1u)
    {
        const unsigned int was = bound[limb];
        bound[limb] = was - 1u;
        if (was != 0u)
        {
            break;
        }
    }
    for (unsigned int limb = KEYMATH_BOUND_LIMBS; limb > 0u; limb -= 1u)
    {
        if (bound[limb - 1u] != 0u)
        {
            return (32u * (limb - 1u)) + keymath_core_word_bits(bound[limb - 1u]);
        }
    }
    return 0u;
}

// the imprint ended at `at` as `end`; 0, which the imprint returns
KEYMATH_CORE int keymath_core_refuse(KeymathCoreImprint *imprint, unsigned int end, unsigned int at)
{
    imprint->end = end;
    imprint->at = at;
    return 0;
}

// Each step's term, width, never-negative mark and linear form, in step order, as keymath_record_imprint lays them: 1
// where every step and output holds, else 0 with where it ended in `end` and `at`
KEYMATH_CORE int keymath_core_record_imprint(KeymathCoreImprint *imprint)
{
    imprint->end = KEYMATH_CORE_HELD;
    imprint->at = 0u;
    imprint->arena.used = 0ull;
    imprint->arena.full = 0;
    EngineRecordTerm *const terms = imprint->terms;
    for (unsigned int step = 0u; step < imprint->count; step += 1u)
    {
        const EngineRecordStep *const doing = &imprint->steps[step];
        EngineRecordTerm *const term = &terms[step];
        term->operation = doing->operation;
        term->left = doing->left;
        term->right = doing->right;
        term->bits = 0u;
        term->member = 0u;
        term->constant = 0ull;
        if (keymath_core_record_reads(doing->operation)
            && !((doing->left < step) && ((doing->operation == ENGINE_RECORD_ABSOLUTE) || (doing->right < step))))
        {
            return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
        }
        if ((doing->operation == ENGINE_RECORD_FIELD) || (doing->operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!((imprint->field_bits != NULL) && (doing->left < imprint->fields) && (doing->member < imprint->members)))
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
            }
            term->bits = imprint->field_bits[doing->left];
            term->member = doing->member;
        }
        else if (doing->operation == ENGINE_RECORD_CONSTANT)
        {
            term->constant = ((unsigned long long)doing->right << 32u) | (unsigned long long)doing->left;
            term->bits = keymath_core_word_bits(term->constant);
        }
        else if (doing->operation == ENGINE_RECORD_PRODUCT)
        {
            term->bits = terms[doing->left].bits + terms[doing->right].bits;
        }
        else if ((doing->operation == ENGINE_RECORD_SUM) || (doing->operation == ENGINE_RECORD_DIFFERENCE))
        {
            const unsigned int wider = (terms[doing->left].bits > terms[doing->right].bits) ? terms[doing->left].bits
                                                                                          : terms[doing->right].bits;
            term->bits = wider + 1u;
        }
        else if (doing->operation == ENGINE_RECORD_LADDER)
        {
            term->bits = keymath_core_word_bits((unsigned long long)ENGINE_GOLDEN_RUNGS - 1ull);
        }
        else if (doing->operation == ENGINE_RECORD_ABSOLUTE)
        {
            term->bits = terms[doing->left].bits;
            term->right = doing->left;
        }
        else if (doing->operation == ENGINE_RECORD_COMPARE)
        {
            term->bits = 1u;
        }
        else if ((doing->operation == ENGINE_RECORD_QUOTIENT) || (doing->operation == ENGINE_RECORD_EXACT_QUOTIENT))
        {
            // a nonzero divisor is at least 1, and the quotient no wider than the numerator. A constant divisor c
            // takes floor(log2 c) bits off: |left| < 2^L and c >= 2^floor(log2 c) put |left| / c below
            // 2^(L - floor(log2 c)). A zero constant narrows nothing and is refused where it divides.
            term->bits = terms[doing->left].bits;
            if (terms[doing->right].operation == ENGINE_RECORD_CONSTANT)
            {
                const unsigned int dropped = (terms[doing->right].bits == 0u) ? 0u : (terms[doing->right].bits - 1u);
                term->bits = (term->bits > dropped) ? (term->bits - dropped) : 1u;
            }
        }
        else if (doing->operation == ENGINE_RECORD_REMAINDER)
        {
            // the remainder is below both the divisor and the numerator
            term->bits = (terms[doing->left].bits < terms[doing->right].bits) ? terms[doing->left].bits
                                                                             : terms[doing->right].bits;
        }
        else if (doing->operation == ENGINE_RECORD_GCD)
        {
            // gcd(a, 0) = |a|: only the wider operand bounds it
            term->bits = (terms[doing->left].bits > terms[doing->right].bits) ? terms[doing->left].bits
                                                                             : terms[doing->right].bits;
        }
        else if ((doing->operation == ENGINE_RECORD_XOR) || (doing->operation == ENGINE_RECORD_AND))
        {
            // both operands lie in the signed range of one bit over the wider, and so does any bitwise result there,
            // down to -2^wider, whose magnitude takes that bit. An and with a register never negative lies between 0
            // and that register, and the xor of two never negative lies below 2^wider; neither takes the extra bit.
            const unsigned int left_bits = terms[doing->left].bits;
            const unsigned int right_bits = terms[doing->right].bits;
            const unsigned int wider = (left_bits > right_bits) ? left_bits : right_bits;
            const unsigned int narrower = (left_bits < right_bits) ? left_bits : right_bits;
            const int left_kept = (imprint->never_negative[doing->left] != 0u) ? 1 : 0;
            const int right_kept = (imprint->never_negative[doing->right] != 0u) ? 1 : 0;
            term->bits = wider + 1u;
            if ((doing->operation == ENGINE_RECORD_AND) && (left_kept != 0) && (right_kept != 0))
            {
                term->bits = narrower;
            }
            else if ((doing->operation == ENGINE_RECORD_AND) && ((left_kept != 0) || (right_kept != 0)))
            {
                term->bits = (left_kept != 0) ? left_bits : right_bits;
            }
            else if ((left_kept != 0) && (right_kept != 0))
            {
                term->bits = wider;
            }
        }
        else if (doing->operation == ENGINE_RECORD_WRAP)
        {
            if (!((doing->left < step) && (doing->right >= ENGINE_RECORD_WRAP_BITS_LEAST)))
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
            }
            // a register of fewer bits than the wrap already lies in its signed range and passes through; a wider one
            // lands in [-2^(right - 1), 2^(right - 1)), whose magnitude takes all `right` bits at -2^(right - 1)
            term->bits = (terms[doing->left].bits < doing->right) ? terms[doing->left].bits : doing->right;
            // the one register read is the left, as the absolute's; the width rides in the term's constant
            term->right = doing->left;
            term->constant = (unsigned long long)doing->right;
        }
        else if (doing->operation == ENGINE_RECORD_TABLE)
        {
            if (!((imprint->tables != NULL) && (doing->left < step) && (doing->right < imprint->table_count)))
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
            }
            const EngineRecordTable *const table = &imprint->tables[doing->right];
            if (!((table->index_bits >= 1u) && (table->index_bits <= ENGINE_RECORD_TABLE_INDEX_BITS_MOST)
                  && (table->index_bits <= terms[doing->left].bits) && (table->out_bits != 0u)
                  && (table->values != NULL)))
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_TABLE, step);
            }
            term->bits = table->out_bits;
        }
        else if (doing->operation == ENGINE_RECORD_LANE)
        {
            // the lane's number is known only at the sweep, and its register holds any lane a sweep can count; it reads
            // nothing, and the step's left and right name nothing
            term->bits = ENGINE_RECORD_LANE_BITS;
            term->left = 0u;
            term->right = 0u;
        }
        else
        {
            return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
        }
        const int wrap_passes = (doing->operation == ENGINE_RECORD_WRAP) && (terms[doing->left].bits < doing->right);
        // the register's form: a sum or difference adds its operands', a product by a constant scales the other's, a
        // constant is its value, and a wrap that passes its register through keeps that register's form. The form's
        // bound narrows the width the operation's own rule gave where it is tighter; where a form would outgrow its
        // words, or for any other register, the register is an atom. A form found no room for leaves the arena full
        KeymathCoreForm *const form = &imprint->forms[step];
        KeymathCoreArena *const arena = &imprint->arena;
        const unsigned long long begun = arena->used;
        int formed = 0;
        if ((doing->operation == ENGINE_RECORD_SUM) || (doing->operation == ENGINE_RECORD_DIFFERENCE))
        {
            formed = keymath_core_form_add(arena, &imprint->forms[doing->left], &imprint->forms[doing->right],
                                           (doing->operation == ENGINE_RECORD_SUM) ? 1ll : -1ll, form);
        }
        else if ((doing->operation == ENGINE_RECORD_PRODUCT) && (imprint->forms[doing->right].count == 0ull))
        {
            formed = keymath_core_form_scale(arena, &imprint->forms[doing->left], imprint->forms[doing->right].constant,
                                             form);
        }
        else if ((doing->operation == ENGINE_RECORD_PRODUCT) && (imprint->forms[doing->left].count == 0ull))
        {
            formed = keymath_core_form_scale(arena, &imprint->forms[doing->right], imprint->forms[doing->left].constant,
                                             form);
        }
        else if ((doing->operation == ENGINE_RECORD_CONSTANT)
                 && (term->constant <= (unsigned long long)KEYMATH_COEFFICIENT_MOST))
        {
            // the constant is at most KEYMATH_COEFFICIENT_MOST, and it fits a signed word
            form->constant = (long long)term->constant;
            form->first = arena->used;
            form->count = 0ull;
            formed = 1;
        }
        else if (wrap_passes != 0)
        {
            // the passed register's form, its terms shared where they lie
            *form = imprint->forms[doing->left];
            formed = 1;
        }
        if (arena->full != 0)
        {
            return keymath_core_refuse(imprint, KEYMATH_CORE_FULL, step);
        }
        if (formed != 0)
        {
            const unsigned int bound = keymath_core_form_bits(arena, form, terms, imprint->bound);
            term->bits = (bound < term->bits) ? bound : term->bits;
        }
        else
        {
            // the terms a form not formed left on the arena are given back, and the register is an atom
            arena->used = begun;
            form->constant = 0ll;
            form->first = arena->used;
            form->count = 1ull;
            if (keymath_core_push(arena, step, 1ll) == 0)
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_FULL, step);
            }
        }
        term->bits = (term->bits == 0u) ? 1u : term->bits;
        if (term->bits > (32u * ENGINE_RECORD_LIMBS_MOST))
        {
            return keymath_core_refuse(imprint, KEYMATH_CORE_STEP, step);
        }
        imprint->never_negative[step] = keymath_core_never_negative(doing, imprint->never_negative, wrap_passes);
    }
    for (unsigned int output = 0u; output < imprint->output_count; output += 1u)
    {
        if (imprint->outputs[output] >= imprint->count)
        {
            return keymath_core_refuse(imprint, KEYMATH_CORE_OUTPUT, output);
        }
        for (unsigned int before = 0u; before < output; before += 1u)
        {
            if (imprint->outputs[before] == imprint->outputs[output])
            {
                return keymath_core_refuse(imprint, KEYMATH_CORE_OUTPUT, output);
            }
        }
    }
    return 1;
}

#endif
