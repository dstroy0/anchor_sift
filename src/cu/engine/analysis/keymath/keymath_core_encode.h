// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// keymath_core_encode.h: form bits, errors and the record's encoding (keymath_core.h includes the parts in order)
#ifndef KEYMATH_CORE_ENCODE_H
#define KEYMATH_CORE_ENCODE_H

#include "keymath_core_affine.h"

// the bits a form's value needs: with B = |c| + sum |c_i| 2^(b_i), the value is at most B - 1 where any atom is read,
// since each atom is below 2^(b_i), and at most |c| where none is; B summed in `bound`, KEYMATH_BOUND_LIMBS words
KEYMATH_CORE unsigned int keymath_core_affine_bits(const KeymathCoreArena *arena, const KeymathCoreAffine *form,
                                                   const EngineRecordTerm *terms, unsigned int *bound)
{
    for (unsigned int limb = 0u; limb < KEYMATH_BOUND_LIMBS; limb += 1u)
    {
        bound[limb] = 0u;
    }
    // a magnitude within KEYMATH_COEFFICIENT_MAX fits an unsigned word
    keymath_core_add_shifted(bound, (unsigned long long)keymath_core_magnitude(form->constant), 0ull);
    for (unsigned long long at = 0ull; at < form->count; at += 1ull)
    {
        const KeymathCoreTerm *const term = &arena->terms[form->first + at];
        // a coefficient within KEYMATH_COEFFICIENT_MAX fits an unsigned word
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

// the encoding ended at `at` as `end`; 0, which the encoding returns
KEYMATH_CORE int keymath_core_error(KeymathCoreEncode *encoding, unsigned int end, unsigned int at)
{
    encoding->end = end;
    encoding->at = at;
    return 0;
}

// Each step's term, width, never-negative mark and linear form, in step order, as keymath_record_encode lays them out:
// 1 where every step and output holds, else 0 with where it ended in `end` and `at`
KEYMATH_CORE int keymath_core_record_encode(KeymathCoreEncode *encoding)
{
    encoding->end = KEYMATH_CORE_OK;
    encoding->at = 0u;
    encoding->arena.used = 0ull;
    encoding->arena.full = 0;
    EngineRecordTerm *const terms = encoding->terms;
    for (unsigned int step = 0u; step < encoding->count; step += 1u)
    {
        const EngineRecordStep *const doing = &encoding->steps[step];
        EngineRecordTerm *const term = &terms[step];
        term->operation = doing->operation;
        term->left = doing->left;
        term->right = doing->right;
        term->bits = 0u;
        term->member = 0u;
        term->constant = 0ull;
        if (keymath_core_record_reads(doing->operation) &&
            !((doing->left < step) && ((doing->operation == ENGINE_RECORD_ABSOLUTE) || (doing->right < step))))
        {
            return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
        }
        if ((doing->operation == ENGINE_RECORD_FIELD) || (doing->operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!((encoding->field_bits != NULL) && (doing->left < encoding->fields) &&
                  (doing->member < encoding->members)))
            {
                return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
            }
            term->bits = encoding->field_bits[doing->left];
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
            // 2^(L - floor(log2 c)). A zero constant narrows nothing and errors where it divides.
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
            const int left_kept = (encoding->never_negative[doing->left] != 0u) ? 1 : 0;
            const int right_kept = (encoding->never_negative[doing->right] != 0u) ? 1 : 0;
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
                return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
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
            if (!((encoding->tables != NULL) && (doing->left < step) && (doing->right < encoding->table_count)))
            {
                return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
            }
            const EngineRecordTable *const table = &encoding->tables[doing->right];
            if (!((table->index_bits >= 1u) && (table->index_bits <= ENGINE_RECORD_TABLE_INDEX_BITS_MAX) &&
                  (table->index_bits <= terms[doing->left].bits) && (table->out_bits != 0u) && (table->values != NULL)))
            {
                return keymath_core_error(encoding, KEYMATH_CORE_TABLE, step);
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
            return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
        }
        const int wrap_passes = (doing->operation == ENGINE_RECORD_WRAP) && (terms[doing->left].bits < doing->right);
        // the register's form: a sum or difference adds its operands', a product by a constant scales the other's, a
        // constant is its value, and a wrap that passes its register through keeps that register's form. The form's
        // bound narrows the width the operation's own rule gave where it is tighter; where a form would outgrow its
        // words, or for any other register, the register is an atom. A form found no room for leaves the arena full
        KeymathCoreAffine *const form = &encoding->forms[step];
        KeymathCoreArena *const arena = &encoding->arena;
        const unsigned long long begun = arena->used;
        int formed = 0;
        if ((doing->operation == ENGINE_RECORD_SUM) || (doing->operation == ENGINE_RECORD_DIFFERENCE))
        {
            formed = keymath_core_affine_add(arena, &encoding->forms[doing->left], &encoding->forms[doing->right],
                                             (doing->operation == ENGINE_RECORD_SUM) ? 1ll : -1ll, form);
        }
        else if ((doing->operation == ENGINE_RECORD_PRODUCT) && (encoding->forms[doing->right].count == 0ull))
        {
            formed = keymath_core_affine_scale(arena, &encoding->forms[doing->left],
                                               encoding->forms[doing->right].constant, form);
        }
        else if ((doing->operation == ENGINE_RECORD_PRODUCT) && (encoding->forms[doing->left].count == 0ull))
        {
            formed = keymath_core_affine_scale(arena, &encoding->forms[doing->right],
                                               encoding->forms[doing->left].constant, form);
        }
        else if ((doing->operation == ENGINE_RECORD_CONSTANT) &&
                 (term->constant <= (unsigned long long)KEYMATH_COEFFICIENT_MAX))
        {
            // the constant is at most KEYMATH_COEFFICIENT_MAX, and it fits a signed word
            form->constant = (long long)term->constant;
            form->first = arena->used;
            form->count = 0ull;
            formed = 1;
        }
        else if (wrap_passes != 0)
        {
            // the passed register's form, its terms shared where they lie
            *form = encoding->forms[doing->left];
            formed = 1;
        }
        if (arena->full != 0)
        {
            return keymath_core_error(encoding, KEYMATH_CORE_FULL, step);
        }
        if (formed != 0)
        {
            const unsigned int bound = keymath_core_affine_bits(arena, form, terms, encoding->bound);
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
                return keymath_core_error(encoding, KEYMATH_CORE_FULL, step);
            }
        }
        term->bits = (term->bits == 0u) ? 1u : term->bits;
        if (term->bits > (32u * ENGINE_RECORD_LIMBS_MAX))
        {
            return keymath_core_error(encoding, KEYMATH_CORE_STEP, step);
        }
        encoding->never_negative[step] = keymath_core_never_negative(doing, encoding->never_negative, wrap_passes);
    }
    for (unsigned int output = 0u; output < encoding->output_count; output += 1u)
    {
        if (encoding->outputs[output] >= encoding->count)
        {
            return keymath_core_error(encoding, KEYMATH_CORE_OUTPUT, output);
        }
        for (unsigned int before = 0u; before < output; before += 1u)
        {
            if (encoding->outputs[before] == encoding->outputs[output])
            {
                return keymath_core_error(encoding, KEYMATH_CORE_OUTPUT, output);
            }
        }
    }
    return 1;
}

#endif
