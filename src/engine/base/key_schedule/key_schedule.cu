// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "key_schedule.h"
#include "key_schedule_core.h"

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

// The record lay: each step laid for the device and placed, and each output placed in the record, by
// key_schedule_core_record_lay (key_schedule_core.h), which the device runs as well; the layout laid from them and the
// key's tables
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
    std::vector<unsigned int> last_use(key->steps);
    std::vector<unsigned int> ending_first((size_t)key->steps + 1u);
    std::vector<unsigned int> ending(key->steps);
    std::vector<KeyScheduleBlock> freed((size_t)key->steps + 1u);
    std::vector<unsigned long long> table_offset((size_t)key->tables + 1u, 0ull);
    KeyScheduleCoreLay lay{};
    lay.terms = key->term;
    lay.step_count = key->steps;
    lay.outputs = key->output;
    lay.output_count = key->outputs;
    lay.tables = key->table;
    lay.table_count = key->tables;
    lay.field_offset = request->field_offset;
    lay.fields = request->fields;
    lay.in_limbs = request->in_limbs;
    lay.reuse = request->reuse;
    lay.steps = steps.data();
    lay.last_use = last_use.data();
    lay.ending_first = ending_first.data();
    lay.ending = ending.data();
    lay.freed = freed.data();
    lay.table_offset = table_offset.data();
    if (key_schedule_core_record_lay(&lay) == 0)
    {
        // the step, the key or the outputs the lay ended at
        const void *const evacaddr = (lay.end == KEY_SCHEDULE_CORE_STEP) ? (const void *)&key->term[lay.at]
                                   : (lay.end == KEY_SCHEDULE_CORE_FILE) ? (const void *)key
                                                                         : (const void *)key->output;
        KEY_SCHEDULE_HELD(0, evacaddr, error, ENGINE_ERROR_REQUEST);
        return KEY_SCHEDULE_REFUSED;
    }
    layout->step_table = (DeviceRecordStep *)malloc(steps.size() * sizeof(DeviceRecordStep));
    if (!KEY_SCHEDULE_HELD(layout->step_table != NULL, layout, error, ENGINE_ERROR_RESOURCE))
    {
        return KEY_SCHEDULE_REFUSED;
    }
    memcpy(layout->step_table, steps.data(), steps.size() * sizeof(DeviceRecordStep));
    if (table_offset[key->tables] != 0ull)
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
    // the file is at most ENGINE_RECORD_LIMBS_MOST limbs and the record's bits a 31-bit count, as the lay holds them
    layout->file_limbs = (unsigned int)lay.file_limbs;
    for (unsigned int member = 0u; member < key->members; member += 1u)
    {
        layout->in_limbs[member] = request->in_limbs[member];
    }
    layout->out_bits = (unsigned int)lay.out_bits;
    layout->out_limbs = (unsigned int)((lay.out_bits + 31ull) / 32ull);
    return (long)layout->file_limbs;
}

extern "C" void key_schedule_record_release(EngineRecordLayout *layout)
{
    free(layout->step_table);
    free(layout->table_values);
    memset(layout, 0, sizeof(*layout));
}
