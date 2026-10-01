// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef KEY_SCHEDULE_CORE_H
#define KEY_SCHEDULE_CORE_H

// key_schedule's record layout as one source the host and the device both compile (engine_table.md item 11(f)(a), the
// compiler on the device): each step laid out for the device from its term, its register placed in the file, and each
// output placed in the record. The host's key_schedule_record_layout runs it and builds the layout; the device runs it
// in one thread, since each place is taken from what the steps before it freed. The lists it works in are the caller's,
// each as long as the program has steps

#include "../../../../c/engine/engine_config.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define KEY_SCHEDULE_CORE __host__ __device__ static inline
#else
#define KEY_SCHEDULE_CORE static inline
#endif

// how a layout ends: every step laid out; a step errored, the one at `at`; the file past ENGINE_RECORD_LIMBS_MAX; or
// the record's bits past a 31-bit count
enum KeyScheduleCoreEnd
{
    KEY_SCHEDULE_CORE_OK = 0,
    KEY_SCHEDULE_CORE_STEP = 1,
    KEY_SCHEDULE_CORE_FILE = 2,
    KEY_SCHEDULE_CORE_OUTPUT = 3
};

// a run of free limbs in the file
struct KeyScheduleBlock
{
    unsigned int offset;
    unsigned int limbs;
};

// a layout: the key's terms, outputs and tables' sizes, the fields' offsets and the members' limbs it reads, and
// whether registers are reused; each step laid out; its lists, each as long as the steps, the endings' firsts and the
// blocks free one more; each table's first word, and past the last the tables' words; the file's limbs and the record's
// bits it laid out; and where it ended, and at what
struct KeyScheduleCoreLayout
{
    const EngineRecordTerm *terms;
    unsigned int step_count;
    const unsigned int *outputs;
    unsigned int output_count;
    const EngineRecordTable *tables;
    unsigned int table_count;
    const unsigned int *field_offset;
    unsigned int fields;
    const unsigned int *in_limbs;
    int reuse;
    DeviceRecordStep *steps;
    unsigned int *last_use;
    unsigned int *ending_first;
    unsigned int *ending;
    KeyScheduleBlock *freed;
    unsigned long long *table_offset;
    unsigned long long file_limbs;
    unsigned long long out_bits;
    unsigned int end;
    unsigned int at;
};

// The step indices a term reads, by which a register is freed once its last reader has run. A field, a constant and the
// lane's number read no register; a table, an absolute and a wrap read one; the rest read two.
KEY_SCHEDULE_CORE unsigned int key_schedule_core_refs(const EngineRecordTerm *term, unsigned int *refs)
{
    if ((term->operation == ENGINE_RECORD_PRODUCT) || (term->operation == ENGINE_RECORD_SUM) ||
        (term->operation == ENGINE_RECORD_DIFFERENCE) || (term->operation == ENGINE_RECORD_LADDER) ||
        (term->operation == ENGINE_RECORD_COMPARE) || (term->operation == ENGINE_RECORD_QUOTIENT) ||
        (term->operation == ENGINE_RECORD_REMAINDER) || (term->operation == ENGINE_RECORD_GCD) ||
        (term->operation == ENGINE_RECORD_EXACT_QUOTIENT) || (term->operation == ENGINE_RECORD_XOR) ||
        (term->operation == ENGINE_RECORD_AND))
    {
        refs[0] = term->left;
        refs[1] = term->right;
        return 2u;
    }
    if ((term->operation == ENGINE_RECORD_ABSOLUTE) || (term->operation == ENGINE_RECORD_TABLE) ||
        (term->operation == ENGINE_RECORD_WRAP))
    {
        refs[0] = term->left;
        return 1u;
    }
    return 0u;
}

// `limbs` taken from the first free block that holds them, else from the file's top; the blocks free are `*count` in
// offset order
KEY_SCHEDULE_CORE unsigned int key_schedule_core_alloc(KeyScheduleBlock *freed, unsigned int *count, unsigned int limbs,
                                                       unsigned int *top)
{
    for (unsigned int block = 0u; block < *count; block += 1u)
    {
        if (freed[block].limbs >= limbs)
        {
            const unsigned int offset = freed[block].offset;
            if (freed[block].limbs == limbs)
            {
                for (unsigned int after = block; (after + 1u) < *count; after += 1u)
                {
                    freed[after] = freed[after + 1u];
                }
                *count -= 1u;
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

// `limbs` at `offset` given back, laid out in offset order and joined with every block it meets
KEY_SCHEDULE_CORE void key_schedule_core_free(KeyScheduleBlock *freed, unsigned int *count, unsigned int offset,
                                              unsigned int limbs)
{
    unsigned int at = 0u;
    while ((at < *count) && (freed[at].offset < offset))
    {
        at += 1u;
    }
    for (unsigned int after = *count; after > at; after -= 1u)
    {
        freed[after] = freed[after - 1u];
    }
    freed[at].offset = offset;
    freed[at].limbs = limbs;
    *count += 1u;
    for (unsigned int block = 0u; (block + 1u) < *count;)
    {
        if ((freed[block].offset + freed[block].limbs) == freed[block + 1u].offset)
        {
            freed[block].limbs += freed[block + 1u].limbs;
            for (unsigned int after = block + 1u; (after + 1u) < *count; after += 1u)
            {
                freed[after] = freed[after + 1u];
            }
            *count -= 1u;
        }
        else
        {
            block += 1u;
        }
    }
}

// The register file's total limbs: with reuse, a register is freed once its last reader has run, and a later step takes
// its place, and a long chain runs within ENGINE_RECORD_LIMBS_MAX; without reuse, every step keeps its own place, the
// layout the proven programs were measured against. 0 where the file passes ENGINE_RECORD_LIMBS_MAX
KEY_SCHEDULE_CORE int key_schedule_core_places(KeyScheduleCoreLayout *layout)
{
    const unsigned int steps = layout->step_count;
    if (layout->reuse == 0)
    {
        unsigned long long place = 0ull;
        for (unsigned int step = 0u; step < steps; step += 1u)
        {
            // a place past ENGINE_RECORD_LIMBS_MAX errors on the layout below, and a place laid out is a 32-bit count
            layout->steps[step].place = (unsigned int)place;
            place += layout->steps[step].limbs;
        }
        layout->file_limbs = place;
        return place <= (unsigned long long)ENGINE_RECORD_LIMBS_MAX;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        layout->last_use[step] = step;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        unsigned int refs[2];
        const unsigned int count = key_schedule_core_refs(&layout->terms[step], refs);
        for (unsigned int ref = 0u; ref < count; ref += 1u)
        {
            layout->last_use[refs[ref]] = step;
        }
    }
    // each register waits under its last reader, and is freed as the step after that reader begins: the registers
    // ending under each step laid out in step order, a stable count of them by their last reader: they are freed at the
    // same steps, in the same order, as a scan of every earlier step would free them
    for (unsigned int step = 0u; step <= steps; step += 1u)
    {
        layout->ending_first[step] = 0u;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        layout->ending_first[layout->last_use[step] + 1u] += 1u;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        layout->ending_first[step + 1u] += layout->ending_first[step];
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        // the step laid out after those before it ending under the same reader, the reader's first counted up past it
        const unsigned int reader = layout->last_use[step];
        layout->ending[layout->ending_first[reader]] = step;
        layout->ending_first[reader] += 1u;
    }
    // each reader's first is now its next reader's first; moved back up one
    for (unsigned int step = steps; step > 0u; step -= 1u)
    {
        layout->ending_first[step] = layout->ending_first[step - 1u];
    }
    layout->ending_first[0] = 0u;
    unsigned int freed_count = 0u;
    unsigned int top = 0u;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        if (step > 0u)
        {
            for (unsigned int ended = layout->ending_first[step - 1u]; ended < layout->ending_first[step]; ended += 1u)
            {
                const unsigned int earlier = layout->ending[ended];
                key_schedule_core_free(layout->freed, &freed_count, layout->steps[earlier].place,
                                       layout->steps[earlier].limbs);
            }
        }
        layout->steps[step].place =
            key_schedule_core_alloc(layout->freed, &freed_count, layout->steps[step].limbs, &top);
        if (top > (unsigned int)ENGINE_RECORD_LIMBS_MAX)
        {
            return 0;
        }
    }
    layout->file_limbs = top;
    return 1;
}

// the layout ended at `at` as `end`; 0, which the layout returns
KEY_SCHEDULE_CORE int key_schedule_core_error(KeyScheduleCoreLayout *layout, unsigned int end, unsigned int at)
{
    layout->end = end;
    layout->at = at;
    return 0;
}

// Each step laid out for the device from its term, as key_schedule_record_layout lays it out: its limbs, operands and
// fields, each table's first word, each register's place, and each output's offset and bits in the record: 1 where it
// holds, else 0 with where it ended in `end` and `at`
KEY_SCHEDULE_CORE int key_schedule_core_record_layout(KeyScheduleCoreLayout *layout)
{
    layout->end = KEY_SCHEDULE_CORE_OK;
    layout->at = 0u;
    unsigned long long table_words = 0ull;
    for (unsigned int table = 0u; table < layout->table_count; table += 1u)
    {
        layout->table_offset[table] = table_words;
        // index_bits is at most 32, and the entry count at most 2^32
        const unsigned long long entries = 1ull << layout->tables[table].index_bits;
        table_words += entries * (unsigned long long)((layout->tables[table].out_bits + 31u) / 32u);
    }
    layout->table_offset[layout->table_count] = table_words;
    for (unsigned int step = 0u; step < layout->step_count; step += 1u)
    {
        const EngineRecordTerm *const term = &layout->terms[step];
        DeviceRecordStep *const device = &layout->steps[step];
        device->operation = (unsigned int)term->operation;
        device->left = term->left;
        device->right = term->right;
        device->limbs = (term->bits + 31u) / 32u;
        device->place = 0u;
        device->left_limbs = 0u;
        device->right_limbs = 0u;
        device->out_offset = 0u;
        device->out_bits = 0u;
        device->member = 0u;
        device->table_offset = 0u;
        device->index_bits = 0u;
        device->wrap_bits = 0u;
        if ((term->operation == ENGINE_RECORD_FIELD) || (term->operation == ENGINE_RECORD_FIELD_SIGNED))
        {
            if (!((layout->field_offset != NULL) && (term->left < layout->fields) &&
                  (((unsigned long long)layout->field_offset[term->left] + term->bits) <=
                   (32ull * (unsigned long long)layout->in_limbs[term->member]))))
            {
                return key_schedule_core_error(layout, KEY_SCHEDULE_CORE_STEP, step);
            }
            device->left = layout->field_offset[term->left];
            device->right = term->bits;
            device->member = term->member;
        }
        else if (term->operation == ENGINE_RECORD_CONSTANT)
        {
            device->left = (unsigned int)(term->constant & 0xFFFFFFFFull);
            device->right = (unsigned int)(term->constant >> 32u);
        }
        else if (term->operation == ENGINE_RECORD_TABLE)
        {
            if (!((layout->tables != NULL) && (term->right < layout->table_count) &&
                  (layout->table_offset[term->right] <= 0x7FFFFFFFull)))
            {
                return key_schedule_core_error(layout, KEY_SCHEDULE_CORE_STEP, step);
            }
            device->left = term->left;
            device->index_bits = layout->tables[term->right].index_bits;
            device->table_offset = (unsigned int)layout->table_offset[term->right];
        }
        else if (term->operation == ENGINE_RECORD_WRAP)
        {
            // keymath took the width from the step's right, at least ENGINE_RECORD_WRAP_BITS_LEAST and an unsigned int
            device->left_limbs = layout->steps[term->left].limbs;
            device->right_limbs = layout->steps[term->right].limbs;
            device->wrap_bits = (unsigned int)term->constant;
        }
        else if (term->operation == ENGINE_RECORD_LANE)
        {
            // the lane's number reads no register, and the step carries no operand's limbs
            device->left_limbs = 0u;
            device->right_limbs = 0u;
        }
        else
        {
            device->left_limbs = layout->steps[term->left].limbs;
            device->right_limbs = layout->steps[term->right].limbs;
        }
    }
    if (key_schedule_core_places(layout) == 0)
    {
        return key_schedule_core_error(layout, KEY_SCHEDULE_CORE_FILE, 0u);
    }
    layout->out_bits = 0ull;
    for (unsigned int output = 0u; output < layout->output_count; output += 1u)
    {
        DeviceRecordStep *const device = &layout->steps[layout->outputs[output]];
        // the record's bits are bounded by a 31-bit count below, and an offset laid out is below them
        device->out_offset = (unsigned int)layout->out_bits;
        device->out_bits = layout->terms[layout->outputs[output]].bits + 1u;
        layout->out_bits += (unsigned long long)device->out_bits;
    }
    if (layout->out_bits > 0x7FFFFFFFull)
    {
        return key_schedule_core_error(layout, KEY_SCHEDULE_CORE_OUTPUT, 0u);
    }
    return 1;
}

#endif
