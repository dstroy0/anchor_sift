// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "key_schedule.h"

#include <stdlib.h>
#include <string.h>

#include <vector>

#define KEY_SCHEDULE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_KEY_SCHEDULE, (unsigned int)__LINE__, \
                       (const void *)(evacaddr_), (error_))

static const unsigned int KEY_SCHEDULE_SWEEP_AXES[ENGINE_AXES] = {0u, 2u, 1u};

static unsigned long long key_schedule_count_growth_bits(unsigned long long count)
{
    unsigned long long less = count - 1ull;
    unsigned long long bits = 0ull;
    while (less != 0ull)
    {
        bits += 1ull;
        less >>= 1u;
    }
    return bits;
}

extern "C" long key_schedule_lay(const EngineKey *key, EngineKeyLayout *layout, EngineError *error)
{
    if (error == NULL)
    {
        return KEY_SCHEDULE_REFUSED;
    }
    if (!KEY_SCHEDULE_HELD((key != NULL) && (layout != NULL), key, error, ENGINE_ERROR_REQUEST)
     || !KEY_SCHEDULE_HELD((key->terms != 0u) && (key->term != NULL) && (key->limbs != NULL), key, error,
                           ENGINE_ERROR_REQUEST))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    memset(layout, 0, sizeof(*layout));
    const unsigned int count = key->terms;
    std::vector<DeviceTerm> terms(count);
    std::vector<unsigned int> weights;
    unsigned long long widest = 0ull;
    unsigned int columns = 0u;
    unsigned int planes = 0u;
    unsigned long long reach[3] = {0ull, 0ull, 0ull};
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const EngineKeyTerm &term = key->term[index];
        DeviceTerm &device = terms[index];
        memset(&device, 0, sizeof(device));
        device.negative = term.negative;
        unsigned long long bits = 16ull;
        unsigned int in_limbs = 1u;
        unsigned int in_plane = ENGINE_FROM_ATOM;
        for (unsigned int sweep = 0u; sweep < ENGINE_AXES; sweep += 1u)
        {
            const unsigned int axis = KEY_SCHEDULE_SWEEP_AXES[sweep];
            const EngineKeyRow &row = term.row[axis];
            bits += row.growth_bits;
            if (!KEY_SCHEDULE_HELD((row.taps * row.limbs) < (1ull << 30u), &row, error, ENGINE_ERROR_REQUEST))
            {
                return KEY_SCHEDULE_REFUSED;
            }
            DeviceSweep &out = device.sweep[sweep];
            out.axis = axis;
            out.taps = (unsigned int)row.taps;
            out.row_limbs = (unsigned int)row.limbs;
            out.in_limbs = in_limbs;
            out.out_limbs = (unsigned int)((bits + 31ull) / 32ull);
            out.in_plane = in_plane;
            out.out_plane = ENGINE_FROM_ATOM;
            out.weights = (unsigned long long)weights.size();
            weights.insert(weights.end(), &key->limbs[row.first], &key->limbs[row.first + (row.limbs * row.taps)]);
            const unsigned int used = out.row_limbs + out.in_limbs + 2u;
            columns = (used > columns) ? used : columns;
            const unsigned long long half = (unsigned long long)(out.taps / 2u);
            reach[out.axis] = (half > reach[out.axis]) ? half : reach[out.axis];
            if (sweep < (ENGINE_AXES - 1u))
            {
                out.out_plane = planes;
                planes += out.out_limbs;
            }
            in_limbs = out.out_limbs;
            in_plane = out.out_plane;
        }
        if (!KEY_SCHEDULE_HELD(term.shift <= 0x7FFFFFFFull, &term.shift, error, ENGINE_ERROR_REQUEST))
        {
            return KEY_SCHEDULE_REFUSED;
        }
        device.shift = (unsigned int)term.shift;
        widest = ((bits + term.shift) > widest) ? (bits + term.shift) : widest;
    }
    const unsigned long long lane_bits = widest + key_schedule_count_growth_bits((unsigned long long)count) + 1ull;
    if (!KEY_SCHEDULE_HELD(lane_bits <= 0x7FFFFFFFull, key, error, ENGINE_ERROR_REQUEST))
    {
        return KEY_SCHEDULE_REFUSED;
    }

    layout->term_table = (DeviceTerm *)malloc(terms.size() * sizeof(DeviceTerm));
    layout->weights = (unsigned int *)malloc((weights.size() + 1u) * sizeof(unsigned int));
    if (!KEY_SCHEDULE_HELD((layout->term_table != NULL) && (layout->weights != NULL), layout, error,
                           ENGINE_ERROR_RESOURCE))
    {
        key_schedule_release(layout);
        return KEY_SCHEDULE_REFUSED;
    }
    memcpy(layout->term_table, terms.data(), terms.size() * sizeof(DeviceTerm));
    memcpy(layout->weights, weights.data(), weights.size() * sizeof(unsigned int));
    layout->weight_count = (unsigned long long)weights.size();
    layout->terms = count;
    layout->bits = (unsigned int)lane_bits;
    layout->columns = columns;
    layout->planes = planes;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        layout->reach[axis] = reach[axis];
    }
    return (long)lane_bits;
}

extern "C" void key_schedule_release(EngineKeyLayout *layout)
{
    free(layout->term_table);
    free(layout->weights);
    memset(layout, 0, sizeof(*layout));
}

typedef struct
{
    unsigned int offset;
    unsigned int limbs;
} KeyScheduleBlock;

// The step indices a term reads, so a register can be freed once its last reader has run. A field or
// constant reads no register; a table, an absolute and a wrap read one; the rest read two.
static unsigned int key_schedule_refs(const EngineRecordTerm *term, unsigned int *refs)
{
    if ((term->operation == ENGINE_RECORD_PRODUCT) || (term->operation == ENGINE_RECORD_SUM)
        || (term->operation == ENGINE_RECORD_DIFFERENCE) || (term->operation == ENGINE_RECORD_LADDER)
        || (term->operation == ENGINE_RECORD_COMPARE) || (term->operation == ENGINE_RECORD_QUOTIENT)
        || (term->operation == ENGINE_RECORD_REMAINDER) || (term->operation == ENGINE_RECORD_GCD)
        || (term->operation == ENGINE_RECORD_EXACT_QUOTIENT) || (term->operation == ENGINE_RECORD_XOR)
        || (term->operation == ENGINE_RECORD_AND))
    {
        refs[0] = term->left;
        refs[1] = term->right;
        return 2u;
    }
    if ((term->operation == ENGINE_RECORD_ABSOLUTE) || (term->operation == ENGINE_RECORD_TABLE)
        || (term->operation == ENGINE_RECORD_WRAP))
    {
        refs[0] = term->left;
        return 1u;
    }
    return 0u;
}

static unsigned int key_schedule_alloc(std::vector<KeyScheduleBlock> &freed, unsigned int limbs, unsigned int *top)
{
    for (size_t block = 0u; block < freed.size(); block += 1u)
    {
        if (freed[block].limbs >= limbs)
        {
            const unsigned int offset = freed[block].offset;
            if (freed[block].limbs == limbs)
            {
                freed.erase(freed.begin() + (long)block);
            }
            else
            {
                freed[block].offset += limbs;
                freed[block].limbs -= limbs;
            }
            return offset;
        }
    }
    const unsigned int offset = *top;
    *top += limbs;
    return offset;
}

static void key_schedule_free(std::vector<KeyScheduleBlock> &freed, unsigned int offset, unsigned int limbs)
{
    KeyScheduleBlock block = {offset, limbs};
    size_t at = 0u;
    while ((at < freed.size()) && (freed[at].offset < offset))
    {
        at += 1u;
    }
    freed.insert(freed.begin() + (long)at, block);
    for (size_t block_at = 0u; (block_at + 1u) < freed.size();)
    {
        if ((freed[block_at].offset + freed[block_at].limbs) == freed[block_at + 1u].offset)
        {
            freed[block_at].limbs += freed[block_at + 1u].limbs;
            freed.erase(freed.begin() + (long)(block_at + 1u));
        }
        else
        {
            block_at += 1u;
        }
    }
}

// The register file's total limbs: with reuse, a register is freed once its last reader has run, and a
// later step takes its place, so a long chain runs within ENGINE_RECORD_LIMBS_MOST; without reuse, every
// step keeps its own place, the layout the proven programs were measured against.
static int key_schedule_places(const EngineRecordKey *key, std::vector<DeviceRecordStep> &steps, int reuse,
                               unsigned long long *file_limbs)
{
    if (reuse == 0)
    {
        unsigned long long place = 0ull;
        for (unsigned int step = 0u; step < key->steps; step += 1u)
        {
            steps[step].place = (unsigned int)place;
            place += steps[step].limbs;
        }
        *file_limbs = place;
        return place <= (unsigned long long)ENGINE_RECORD_LIMBS_MOST;
    }
    std::vector<unsigned int> last_use(key->steps);
    for (unsigned int step = 0u; step < key->steps; step += 1u)
    {
        last_use[step] = step;
    }
    for (unsigned int step = 0u; step < key->steps; step += 1u)
    {
        unsigned int refs[2];
        const unsigned int count = key_schedule_refs(&key->term[step], refs);
        for (unsigned int ref = 0u; ref < count; ref += 1u)
        {
            last_use[refs[ref]] = step;
        }
    }
    std::vector<KeyScheduleBlock> freed;
    std::vector<char> released(key->steps, 0);
    unsigned int top = 0u;
    for (unsigned int step = 0u; step < key->steps; step += 1u)
    {
        for (unsigned int earlier = 0u; earlier < step; earlier += 1u)
        {
            if ((released[earlier] == 0) && (last_use[earlier] < step))
            {
                key_schedule_free(freed, steps[earlier].place, steps[earlier].limbs);
                released[earlier] = 1;
            }
        }
        steps[step].place = key_schedule_alloc(freed, steps[step].limbs, &top);
        if (top > (unsigned int)ENGINE_RECORD_LIMBS_MOST)
        {
            return 0;
        }
    }
    *file_limbs = top;
    return 1;
}

extern "C" long key_schedule_record_lay(const KeyScheduleRecordRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!KEY_SCHEDULE_HELD((request->key != NULL) && (request->layout != NULL) && (request->in_limbs != NULL), request,
                           error, ENGINE_ERROR_REQUEST)
     || !KEY_SCHEDULE_HELD((request->key->steps != 0u) && (request->key->term != NULL) && (request->key->output != NULL)
                               && (request->key->members != 0u) && (request->key->members <= ENGINE_RECORD_MEMBERS_MAX),
                           request->key, error, ENGINE_ERROR_REQUEST))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    for (unsigned int member = 0u; member < request->key->members; member += 1u)
    {
        if (!KEY_SCHEDULE_HELD(request->in_limbs[member] != 0u, &request->in_limbs[member], error, ENGINE_ERROR_REQUEST))
        {
            return KEY_SCHEDULE_REFUSED;
        }
    }
    const EngineRecordKey *const key = request->key;
    EngineRecordLayout *const layout = request->layout;
    memset(layout, 0, sizeof(*layout));
    std::vector<DeviceRecordStep> steps(key->steps);
    std::vector<unsigned long long> table_offset((size_t)key->tables + 1u, 0ull);
    unsigned long long table_words = 0ull;
    for (unsigned int table = 0u; table < key->tables; table += 1u)
    {
        table_offset[table] = table_words;
        // index_bits is at most 32, so the entry count is at most 2^32
        const unsigned long long entries = 1ull << key->table[table].index_bits;
        table_words += entries * (unsigned long long)((key->table[table].out_bits + 31u) / 32u);
    }
    for (unsigned int step = 0u; step < key->steps; step += 1u)
    {
        const EngineRecordTerm &term = key->term[step];
        DeviceRecordStep &device = steps[step];
        memset(&device, 0, sizeof(device));
        device.operation = (unsigned int)term.operation;
        device.left = term.left;
        device.right = term.right;
        device.limbs = (term.bits + 31u) / 32u;
        if ((term.operation == ENGINE_RECORD_FIELD) || (term.operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!KEY_SCHEDULE_HELD((request->field_offset != NULL) && (term.left < request->fields)
                                       && (((unsigned long long)request->field_offset[term.left] + term.bits)
                                           <= (32ull * (unsigned long long)request->in_limbs[term.member])),
                                   &term, error, ENGINE_ERROR_REQUEST))
            {
                return KEY_SCHEDULE_REFUSED;
            }
            device.left = request->field_offset[term.left];
            device.right = term.bits;
            device.member = term.member;
        }
        else if (term.operation == ENGINE_RECORD_CONSTANT)
        {
            device.left = (unsigned int)(term.constant & 0xFFFFFFFFull);
            device.right = (unsigned int)(term.constant >> 32u);
        }
        else if (term.operation == ENGINE_RECORD_TABLE)
        {
            if (!KEY_SCHEDULE_HELD((key->table != NULL) && (term.right < key->tables)
                                       && (table_offset[term.right] <= 0x7FFFFFFFull),
                                   &term, error, ENGINE_ERROR_REQUEST))
            {
                return KEY_SCHEDULE_REFUSED;
            }
            device.left = term.left;
            device.index_bits = key->table[term.right].index_bits;
            device.table_offset = (unsigned int)table_offset[term.right];
        }
        else if (term.operation == ENGINE_RECORD_WRAP)
        {
            // keymath took the width from the step's right, at least ENGINE_RECORD_WRAP_BITS_LEAST and an unsigned int
            device.left_limbs = steps[term.left].limbs;
            device.right_limbs = steps[term.right].limbs;
            device.wrap_bits = (unsigned int)term.constant;
        }
        else
        {
            device.left_limbs = steps[term.left].limbs;
            device.right_limbs = steps[term.right].limbs;
        }
    }
    unsigned long long file_limbs = 0ull;
    if (!KEY_SCHEDULE_HELD(key_schedule_places(key, steps, request->reuse, &file_limbs) != 0, key, error,
                           ENGINE_ERROR_REQUEST))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    unsigned long long out_bits = 0ull;
    for (unsigned int output = 0u; output < key->outputs; output += 1u)
    {
        DeviceRecordStep &device = steps[key->output[output]];
        device.out_offset = (unsigned int)out_bits;
        device.out_bits = key->term[key->output[output]].bits + 1u;
        out_bits += (unsigned long long)device.out_bits;
    }
    if (!KEY_SCHEDULE_HELD(out_bits <= 0x7FFFFFFFull, key->output, error, ENGINE_ERROR_REQUEST))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    layout->step_table = (DeviceRecordStep *)malloc(steps.size() * sizeof(DeviceRecordStep));
    if (!KEY_SCHEDULE_HELD(layout->step_table != NULL, layout, error, ENGINE_ERROR_RESOURCE))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    memcpy(layout->step_table, steps.data(), steps.size() * sizeof(DeviceRecordStep));
    if (table_words != 0ull)
    {
        layout->table_values = (unsigned int *)malloc((size_t)(key->table_word_count + 1u) * sizeof(unsigned int));
        if (!KEY_SCHEDULE_HELD(layout->table_values != NULL, layout, error, ENGINE_ERROR_RESOURCE))
        {
            key_schedule_record_release(layout);
            return KEY_SCHEDULE_REFUSED;
        }
        memcpy(layout->table_values, key->table_values, (size_t)key->table_word_count * sizeof(unsigned int));
        layout->table_word_count = key->table_word_count;
    }
    layout->steps = key->steps;
    layout->members = key->members;
    layout->file_limbs = (unsigned int)file_limbs;
    for (unsigned int member = 0u; member < key->members; member += 1u)
    {
        layout->in_limbs[member] = request->in_limbs[member];
    }
    layout->out_bits = (unsigned int)out_bits;
    layout->out_limbs = (unsigned int)((out_bits + 31ull) / 32ull);
    return (long)layout->file_limbs;
}

extern "C" void key_schedule_record_release(EngineRecordLayout *layout)
{
    free(layout->step_table);
    free(layout->table_values);
    memset(layout, 0, sizeof(*layout));
}
