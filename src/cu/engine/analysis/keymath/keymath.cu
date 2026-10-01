// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "../../../../engine/compiler/keymath/keymath.h"
#include "keymath_core.h"

#include <stdlib.h>
#include <string.h>

#include <vector>

#define KEYMATH_CHECK(condition_, evacaddr_, error_, kind_)                                                            \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_KEYMATH, (unsigned int)__LINE__,                           \
                       (const void *)(evacaddr_), (error_))

typedef std::vector<unsigned int> ExactLimbs;

struct EncodeTerm
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
        const unsigned long long total =
            carry + ((limb < left.size()) ? left[limb] : 0u) + ((limb < right.size()) ? right[limb] : 0u);
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

static void encode_unit_step(std::vector<ExactLimbs> &row)
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

extern "C" long keymath_encode(const KeymathEncodeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_ERROR;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_CHECK((request->key != NULL) && (request->steps != NULL) && (request->count != 0u), request, error,
                       ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_ERROR;
    }
    memset(request->key, 0, sizeof(*request->key));

    std::vector<EncodeTerm> running(1u);
    running[0].negative = 0u;
    running[0].shift = 0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        running[0].rows[axis].assign(1u, ExactLimbs(1u, 1u));
    }
    std::vector<EncodeTerm> kept;
    int have_kept = 0;
    // whether the running terms' and the kept terms' centers sit half a voxel before the voxel on each axis: an order
    // o's window starts floor((o + 1) / 2) before it, and the center moves half a voxel with each odd order
    unsigned int running_half[ENGINE_AXES] = {0u, 0u, 0u};
    unsigned int kept_half[ENGINE_AXES] = {0u, 0u, 0u};
    for (unsigned int step = 0u; step < request->count; step += 1u)
    {
        const EngineStep &doing = request->steps[step];
        if (doing.operation == ENGINE_SMOOTH)
        {
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                running_half[axis] ^= doing.orders[axis] & 1u;
                for (EncodeTerm &term : running)
                {
                    for (unsigned int unit = 0u; unit < doing.orders[axis]; unit += 1u)
                    {
                        encode_unit_step(term.rows[axis]);
                    }
                }
            }
        }
        else if (doing.operation == ENGINE_KEEP)
        {
            kept = running;
            have_kept = 1;
            memcpy(kept_half, running_half, sizeof(kept_half));
        }
        else if ((doing.operation == ENGINE_SCALE_SUBTRACT) && (have_kept != 0))
        {
            // terms subtracted half a voxel apart are no residual of one voxel
            if (!KEYMATH_CHECK(memcmp(kept_half, running_half, sizeof(kept_half)) == 0, &doing, error,
                               ENGINE_ERROR_REQUEST))
            {
                return KEYMATH_ERROR;
            }
            std::vector<EncodeTerm> next = kept;
            for (EncodeTerm &term : next)
            {
                term.shift += (unsigned long long)doing.shift;
            }
            for (EncodeTerm term : running)
            {
                term.negative ^= 1u;
                next.push_back(term);
            }
            running.swap(next);
        }
        else
        {
            KEYMATH_CHECK(0, &doing, error, ENGINE_ERROR_REQUEST);
            return KEYMATH_ERROR;
        }
    }

    std::vector<EngineKeyTerm> table(running.size());
    std::vector<unsigned int> limbs;
    for (size_t index = 0u; index < running.size(); index += 1u)
    {
        const EncodeTerm &term = running[index];
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
    if (!KEYMATH_CHECK((key->term != NULL) && (key->limbs != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_key_release(key);
        return KEYMATH_ERROR;
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

// The record encoding: each step's term, width and form laid out by keymath_core_record_encode (keymath_core.h), which
// the device runs as well, and the key laid out from the terms, the outputs and the tables
extern "C" long keymath_record_encode(const KeymathRecordRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEYMATH_ERROR;
    }
    EngineError *const error = request->error;
    if (!KEYMATH_CHECK((request->key != NULL) && (request->steps != NULL) && (request->count != 0u) &&
                           (request->outputs != NULL) && (request->output_count != 0u) &&
                           (request->output_count <= request->count) && (request->members != 0u) &&
                           (request->members <= ENGINE_RECORD_MEMBERS_MAX),
                       request, error, ENGINE_ERROR_REQUEST))
    {
        return KEYMATH_ERROR;
    }
    memset(request->key, 0, sizeof(*request->key));
    std::vector<EngineRecordTerm> terms(request->count);
    std::vector<unsigned char> never_negative(request->count, (unsigned char)0u);
    std::vector<KeymathCoreAffine> forms(request->count);
    std::vector<KeymathCoreTerm> arena;
    unsigned int bound[KEYMATH_BOUND_LIMBS];
    KeymathCoreEncode encoding{};
    encoding.steps = request->steps;
    encoding.count = request->count;
    encoding.field_bits = request->field_bits;
    encoding.fields = request->fields;
    encoding.members = request->members;
    encoding.outputs = request->outputs;
    encoding.output_count = request->output_count;
    encoding.tables = request->tables;
    encoding.table_count = request->table_count;
    encoding.terms = terms.data();
    encoding.never_negative = never_negative.data();
    encoding.forms = forms.data();
    encoding.bound = bound;
    unsigned long long capacity = (unsigned long long)request->count * KEYMATH_ARENA_PER_STEP;
    int ok = 0;
    do
    {
        arena.resize((size_t)capacity);
        encoding.arena.terms = arena.data();
        encoding.arena.capacity = capacity;
        ok = keymath_core_record_encode(&encoding);
        capacity *= 2ull;
    } while ((ok == 0) && (encoding.end == KEYMATH_CORE_FULL));
    if (ok == 0)
    {
        // the step, its table or the output the encoding ended at
        const void *const evacaddr =
            (encoding.end == KEYMATH_CORE_OUTPUT)  ? (const void *)&request->outputs[encoding.at]
            : (encoding.end == KEYMATH_CORE_TABLE) ? (const void *)&request->tables[request->steps[encoding.at].right]
                                                   : (const void *)&request->steps[encoding.at];
        KEYMATH_CHECK(0, evacaddr, error, ENGINE_ERROR_REQUEST);
        return KEYMATH_ERROR;
    }
    EngineRecordKey *const key = request->key;
    key->term = (EngineRecordTerm *)malloc(terms.size() * sizeof(EngineRecordTerm));
    key->output = (unsigned int *)malloc((size_t)request->output_count * sizeof(unsigned int));
    if (!KEYMATH_CHECK((key->term != NULL) && (key->output != NULL), key, error, ENGINE_ERROR_RESOURCE))
    {
        keymath_record_release(key);
        return KEYMATH_ERROR;
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
        if (!KEYMATH_CHECK(key->table != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_ERROR;
        }
        for (unsigned int table = 0u; table < request->table_count; table += 1u)
        {
            const EngineRecordTable &source = request->tables[table];
            // index_bits is at most 32, and the entry count at most 2^32, which an unsigned long long holds
            const unsigned long long entries = 1ull << source.index_bits;
            const unsigned int out_limbs = (source.out_bits + 31u) / 32u;
            key->table[table].index_bits = source.index_bits;
            key->table[table].out_bits = source.out_bits;
            key->table[table].values = NULL;
            values.insert(values.end(), source.values, source.values + (entries * out_limbs));
        }
        key->table_values = (unsigned int *)malloc((values.size() + 1u) * sizeof(unsigned int));
        if (!KEYMATH_CHECK(key->table_values != NULL, key, error, ENGINE_ERROR_RESOURCE))
        {
            keymath_record_release(key);
            return KEYMATH_ERROR;
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
