// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "keymath.h"

#include <stdlib.h>
#include <string.h>

#include <vector>

#define KEYMATH_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_KEYMATH, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

typedef std::vector<unsigned int> ExactLimbs;

struct ImprintTerm
{
    unsigned int negative;
    unsigned long long shift;
    std::vector<ExactLimbs> rows[ENGINE_AXES];
};

static ExactLimbs exact_sum(const ExactLimbs &left, const ExactLimbs &right)
{
    const size_t wider = (left.size() > right.size()) ? left.size() : right.size();
    ExactLimbs sum(wider + 1u, 0u);
    unsigned long long carry = 0ull;
    for (size_t limb = 0u; limb < wider; limb += 1u)
    {
        const unsigned long long total = carry + ((limb < left.size()) ? left[limb] : 0u)
                                       + ((limb < right.size()) ? right[limb] : 0u);
        sum[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    sum[wider] = (unsigned int)carry;
    while ((sum.size() > 1u) && (sum.back() == 0u))
    {
        sum.pop_back();
    }
    return sum;
}

static unsigned long long exact_bit_length(const ExactLimbs &value)
{
    for (size_t limb = value.size(); limb > 0u; limb -= 1u)
    {
        unsigned int top = value[limb - 1u];
        if (top != 0u)
        {
            unsigned long long bits = (unsigned long long)(limb - 1u) * 32ull;
            while (top != 0u)
            {
                bits += 1ull;
                top >>= 1u;
            }
            return bits;
        }
    }
    return 0ull;
}

static ExactLimbs exact_less_one(ExactLimbs value)
{
    for (size_t limb = 0u; limb < value.size(); limb += 1u)
    {
        const unsigned int was = value[limb];
        value[limb] = was - 1u;
        if (was != 0u)
        {
            break;
        }
    }
    return value;
}

static void imprint_unit_step(std::vector<ExactLimbs> &row)
{
    const ExactLimbs zero(1u, 0u);
    std::vector<ExactLimbs> stepped(row.size() + 1u);
    for (size_t tap = 0u; tap < stepped.size(); tap += 1u)
    {
        const ExactLimbs &here = (tap < row.size()) ? row[tap] : zero;
        const ExactLimbs &before = (tap > 0u) ? row[tap - 1u] : zero;
        stepped[tap] = exact_sum(here, before);
    }
    row.swap(stepped);
}

extern "C" long keymath_imprint(const KeymathImprintRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_REFUSED;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_HELD((request->key != NULL) && (request->steps != NULL) && (request->count != 0u), request, error,
                      ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_REFUSED;
    }
    memset(request->key, 0, sizeof(*request->key));

    std::vector<ImprintTerm> running(1u);
    running[0].negative = 0u;
    running[0].shift = 0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        running[0].rows[axis].assign(1u, ExactLimbs(1u, 1u));
    }
    std::vector<ImprintTerm> kept;
    int have_kept = 0;
    for (unsigned int step = 0u; step < request->count; step += 1u)
    {
        const EngineStep &doing = request->steps[step];
        if (doing.operation == ENGINE_SMOOTH)
        {
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                if (!KEYMATH_HELD((doing.orders[axis] % 2u) == 0u, &doing.orders[axis], error, ENGINE_ERROR_REQUEST))
                {
                    return KEYMATH_REFUSED;
                }
                for (ImprintTerm &term : running)
                {
                    for (unsigned int unit = 0u; unit < doing.orders[axis]; unit += 1u)
                    {
                        imprint_unit_step(term.rows[axis]);
                    }
                }
            }
        }
        else if (doing.operation == ENGINE_KEEP)
        {
            kept = running;
            have_kept = 1;
        }
        else if ((doing.operation == ENGINE_SCALE_SUBTRACT) && (have_kept != 0))
        {
            std::vector<ImprintTerm> next = kept;
            for (ImprintTerm &term : next)
            {
                term.shift += (unsigned long long)doing.shift;
            }
            for (ImprintTerm term : running)
            {
                term.negative ^= 1u;
                next.push_back(term);
            }
            running.swap(next);
        }
        else
        {
            KEYMATH_HELD(0, &doing, error, ENGINE_ERROR_REQUEST);
            return KEYMATH_REFUSED;
        }
    }

    std::vector<EngineKeyTerm> table(running.size());
    std::vector<unsigned int> limbs;
    for (size_t index = 0u; index < running.size(); index += 1u)
    {
        const ImprintTerm &term = running[index];
        EngineKeyTerm &out = table[index];
        memset(&out, 0, sizeof(out));
        out.negative = term.negative;
        out.shift = term.shift;
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            const std::vector<ExactLimbs> &row = term.rows[axis];
            size_t widest = 1u;
            ExactLimbs sum(1u, 0u);
            for (const ExactLimbs &weight : row)
            {
                widest = (weight.size() > widest) ? weight.size() : widest;
                sum = exact_sum(sum, weight);
            }
            EngineKeyRow &placed = out.row[axis];
            placed.taps = (unsigned long long)row.size();
            placed.limbs = (unsigned long long)widest;
            placed.first = (unsigned long long)limbs.size();
            placed.growth_bits = exact_bit_length(exact_less_one(sum));
            for (size_t limb = 0u; limb < widest; limb += 1u)
            {
                for (const ExactLimbs &weight : row)
                {
                    limbs.push_back((limb < weight.size()) ? weight[limb] : 0u);
                }
            }
        }
    }
    EngineKey *const key = request->key;
    key->term = (EngineKeyTerm *)malloc((table.size() + 1u) * sizeof(EngineKeyTerm));
    key->limbs = (unsigned int *)malloc((limbs.size() + 1u) * sizeof(unsigned int));
    if (!KEYMATH_HELD((key->term != NULL) && (key->limbs != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_key_release(key);
        return KEYMATH_REFUSED;
    }
    memcpy(key->term, table.data(), table.size() * sizeof(EngineKeyTerm));
    memcpy(key->limbs, limbs.data(), limbs.size() * sizeof(unsigned int));
    key->terms = (unsigned int)table.size();
    key->limb_count = (unsigned long long)limbs.size();
    return (long)key->terms;
}

extern "C" void keymath_key_release(EngineKey *key)
{
    free(key->term);
    free(key->limbs);
    memset(key, 0, sizeof(*key));
}

static unsigned int keymath_word_bits(unsigned long long value)
{
    unsigned int bits = 0u;
    while (value != 0ull)
    {
        bits += 1u;
        value >>= 1u;
    }
    return bits;
}

static int keymath_record_reads(EngineRecordOperation operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_ABSOLUTE) || (operation == ENGINE_RECORD_COMPARE)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

extern "C" long keymath_record_imprint(const KeymathRecordRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_REFUSED;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_HELD((request->key != NULL) && (request->steps != NULL) && (request->count != 0u)
                          && (request->count <= ENGINE_RECORD_STEPS_MAX) && (request->outputs != NULL)
                          && (request->output_count != 0u) && (request->output_count <= request->count)
                          && (request->members != 0u) && (request->members <= ENGINE_RECORD_MEMBERS_MAX),
                      request, error, ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_REFUSED;
    }
    memset(request->key, 0, sizeof(*request->key));
    std::vector<EngineRecordTerm> terms(request->count);
    for (unsigned int step = 0u; step < request->count; step += 1u)
    {
        const EngineRecordStep &doing = request->steps[step];
        EngineRecordTerm &term = terms[step];
        memset(&term, 0, sizeof(term));
        term.operation = doing.operation;
        term.left = doing.left;
        term.right = doing.right;
        if (!KEYMATH_HELD(!keymath_record_reads(doing.operation)
                              || ((doing.left < step)
                                  && ((doing.operation == ENGINE_RECORD_ABSOLUTE) || (doing.right < step))),
                          &doing, error, ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
        if ((doing.operation == ENGINE_RECORD_FIELD) || (doing.operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!KEYMATH_HELD((request->field_bits != NULL) && (doing.left < request->fields)
                                  && (doing.member < request->members),
                              &doing, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            term.bits = request->field_bits[doing.left];
            term.member = doing.member;
        }
        else if (doing.operation == ENGINE_RECORD_CONSTANT)
        {
            term.constant = ((unsigned long long)doing.right << 32u) | (unsigned long long)doing.left;
            term.bits = keymath_word_bits(term.constant);
        }
        else if (doing.operation == ENGINE_RECORD_PRODUCT)
        {
            term.bits = terms[doing.left].bits + terms[doing.right].bits;
        }
        else if ((doing.operation == ENGINE_RECORD_SUM) || (doing.operation == ENGINE_RECORD_DIFFERENCE))
        {
            const unsigned int wider = (terms[doing.left].bits > terms[doing.right].bits) ? terms[doing.left].bits
                                                                                        : terms[doing.right].bits;
            term.bits = wider + 1u;
        }
        else if (doing.operation == ENGINE_RECORD_LADDER)
        {
            term.bits = keymath_word_bits((unsigned long long)ENGINE_GOLDEN_RUNGS - 1ull);
        }
        else if (doing.operation == ENGINE_RECORD_ABSOLUTE)
        {
            term.bits = terms[doing.left].bits;
            term.right = doing.left;
        }
        else if (doing.operation == ENGINE_RECORD_COMPARE)
        {
            term.bits = 1u;
        }
        else if ((doing.operation == ENGINE_RECORD_QUOTIENT) || (doing.operation == ENGINE_RECORD_EXACT_QUOTIENT))
        {
            // a nonzero divisor is at least 1, so the quotient is no wider than the numerator
            term.bits = terms[doing.left].bits;
        }
        else if (doing.operation == ENGINE_RECORD_REMAINDER)
        {
            // the remainder is below both the divisor and the numerator
            term.bits = (terms[doing.left].bits < terms[doing.right].bits) ? terms[doing.left].bits
                                                                          : terms[doing.right].bits;
        }
        else if (doing.operation == ENGINE_RECORD_GCD)
        {
            // gcd(a, 0) = |a|, so only the wider operand bounds it
            term.bits = (terms[doing.left].bits > terms[doing.right].bits) ? terms[doing.left].bits
                                                                          : terms[doing.right].bits;
        }
        else if (doing.operation == ENGINE_RECORD_TABLE)
        {
            if (!KEYMATH_HELD((request->tables != NULL) && (doing.left < step)
                                  && (doing.right < request->table_count),
                              &doing, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            const EngineRecordTable &table = request->tables[doing.right];
            if (!KEYMATH_HELD((table.index_bits >= 1u) && (table.index_bits <= ENGINE_RECORD_TABLE_INDEX_BITS_MOST)
                                  && (table.index_bits <= terms[doing.left].bits) && (table.out_bits != 0u)
                                  && (table.values != NULL),
                              &table, error, ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
            term.bits = table.out_bits;
        }
        else
        {
            KEYMATH_HELD(0, &doing, error, ENGINE_ERROR_REQUEST);
            return KEYMATH_REFUSED;
        }
        term.bits = (term.bits == 0u) ? 1u : term.bits;
        if (!KEYMATH_HELD(term.bits <= (32u * ENGINE_RECORD_LIMBS_MOST), &doing, error, ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
    }
    for (unsigned int output = 0u; output < request->output_count; output += 1u)
    {
        if (!KEYMATH_HELD(request->outputs[output] < request->count, &request->outputs[output], error,
                          ENGINE_ERROR_REQUEST))
        {
            return KEYMATH_REFUSED;
        }
        for (unsigned int before = 0u; before < output; before += 1u)
        {
            if (!KEYMATH_HELD(request->outputs[before] != request->outputs[output], &request->outputs[output], error,
                              ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_REFUSED;
            }
        }
    }
    EngineRecordKey *const key = request->key;
    key->term = (EngineRecordTerm *)malloc(terms.size() * sizeof(EngineRecordTerm));
    key->output = (unsigned int *)malloc((size_t)request->output_count * sizeof(unsigned int));
    if (!KEYMATH_HELD((key->term != NULL) && (key->output != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_record_release(key);
        return KEYMATH_REFUSED;
    }
    memcpy(key->term, terms.data(), terms.size() * sizeof(EngineRecordTerm));
    memcpy(key->output, request->outputs, (size_t)request->output_count * sizeof(unsigned int));
    key->steps = request->count;
    key->members = request->members;
    key->outputs = request->output_count;
    key->tables = request->table_count;
    if (request->table_count != 0u)
    {
        std::vector<unsigned int> values;
        key->table = (EngineRecordTable *)malloc((size_t)request->table_count * sizeof(EngineRecordTable));
        if (!KEYMATH_HELD(key->table != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_REFUSED;
        }
        for (unsigned int table = 0u; table < request->table_count; table += 1u)
        {
            const EngineRecordTable &source = request->tables[table];
            // index_bits is at most 32, so the entry count is at most 2^32 and fits an unsigned long long
            const unsigned long long entries = 1ull << source.index_bits;
            const unsigned int out_limbs = (source.out_bits + 31u) / 32u;
            key->table[table].index_bits = source.index_bits;
            key->table[table].out_bits = source.out_bits;
            key->table[table].values = NULL;
            values.insert(values.end(), source.values, source.values + (entries * out_limbs));
        }
        key->table_values = (unsigned int *)malloc((values.size() + 1u) * sizeof(unsigned int));
        if (!KEYMATH_HELD(key->table_values != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_REFUSED;
        }
        memcpy(key->table_values, values.data(), values.size() * sizeof(unsigned int));
        key->table_word_count = (unsigned long long)values.size();
    }
    return (long)key->steps;
}

extern "C" void keymath_record_release(EngineRecordKey *key)
{
    free(key->term);
    free(key->output);
    free(key->table);
    free(key->table_values);
    memset(key, 0, sizeof(*key));
}
