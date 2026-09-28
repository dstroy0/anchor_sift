// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef KEY_SCHEDULE_CORE_H
#define KEY_SCHEDULE_CORE_H

// key_schedule's record lay as one source the host and the device both compile (engine_table.md item 11(f)(a), the
// compiler on the device): each step laid for the device from its term, its register placed in the file, and each
// output placed in the record. The host's key_schedule_record_lay runs it and lays the layout; the device runs it in one
// thread, since each place is taken from what the steps before it freed. The lists it works in are the caller's, each
// as long as the program has steps

#include "engine_config.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define KEY_SCHEDULE_CORE __host__ __device__ static inline
#else
#define KEY_SCHEDULE_CORE static inline
#endif

// how a lay ends: every step laid; a step refused, the one at `at`; the file past ENGINE_RECORD_LIMBS_MOST; or the
// record's bits past a 31-bit count
enum KeyScheduleCoreEnd
{
    KEY_SCHEDULE_CORE_HELD = 0,
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

// a lay: the key's terms, outputs and tables' shapes, the fields' offsets and the members' limbs it reads, and whether
// registers are reused; each step laid; its lists, each as long as the steps, the endings' firsts and the blocks free
// one more; each table's first word, and past the last the tables' words; the file's limbs and the record's bits it
// laid; and where it ended, and at what
struct KeyScheduleCoreLay
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

// `limbs` at `offset` given back, laid in offset order and joined with every block it meets
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
// its place, and a long chain runs within ENGINE_RECORD_LIMBS_MOST; without reuse, every step keeps its own place, the
// layout the proven programs were measured against. 0 where the file passes ENGINE_RECORD_LIMBS_MOST
KEY_SCHEDULE_CORE int key_schedule_core_places(KeyScheduleCoreLay *lay)
{
    const unsigned int steps = lay->step_count;
    if (lay->reuse == 0)
    {
        unsigned long long place = 0ull;
        for (unsigned int step = 0u; step < steps; step += 1u)
        {
            // a place past ENGINE_RECORD_LIMBS_MOST refuses the lay below, and a place laid is a 32-bit count
            lay->steps[step].place = (unsigned int)place;
            place += lay->steps[step].limbs;
        }
        lay->file_limbs = place;
        return place <= (unsigned long long)ENGINE_RECORD_LIMBS_MOST;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        lay->last_use[step] = step;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        unsigned int refs[2];
        const unsigned int count = key_schedule_core_refs(&lay->terms[step], refs);
        for (unsigned int ref = 0u; ref < count; ref += 1u)
        {
            lay->last_use[refs[ref]] = step;
        }
    }
    // each register waits under its last reader, and is freed as the step after that reader begins: the registers
    // ending under each step laid in step order, a stable count of them by their last reader: they are freed at the
    // same steps, in the same order, as a scan of every earlier step would free them
    for (unsigned int step = 0u; step <= steps; step += 1u)
    {
        lay->ending_first[step] = 0u;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        lay->ending_first[lay->last_use[step] + 1u] += 1u;
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        lay->ending_first[step + 1u] += lay->ending_first[step];
    }
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        // the step laid after those before it ending under the same reader, the reader's first counted up past it
        const unsigned int reader = lay->last_use[step];
        lay->ending[lay->ending_first[reader]] = step;
        lay->ending_first[reader] += 1u;
    }
    // each reader's first is now its next reader's first; moved back up one
    for (unsigned int step = steps; step > 0u; step -= 1u)
    {
        lay->ending_first[step] = lay->ending_first[step - 1u];
    }
    lay->ending_first[0] = 0u;
    unsigned int freed_count = 0u;
    unsigned int top = 0u;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        if (step > 0u)
        {
            for (unsigned int ended = lay->ending_first[step - 1u]; ended < lay->ending_first[step]; ended += 1u)
            {
                const unsigned int earlier = lay->ending[ended];
                key_schedule_core_free(lay->freed, &freed_count, lay->steps[earlier].place, lay->steps[earlier].limbs);
            }
        }
        lay->steps[step].place = key_schedule_core_alloc(lay->freed, &freed_count, lay->steps[step].limbs, &top);
        if (top > (unsigned int)ENGINE_RECORD_LIMBS_MOST)
        {
            return 0;
        }
    }
    lay->file_limbs = top;
    return 1;
}

// the lay ended at `at` as `end`; 0, which the lay returns
KEY_SCHEDULE_CORE int key_schedule_core_refuse(KeyScheduleCoreLay *lay, unsigned int end, unsigned int at)
{
    lay->end = end;
    lay->at = at;
    return 0;
}

// Each step laid for the device from its term, as key_schedule_record_lay lays it: its limbs, operands and fields, each
// table's first word, each register's place, and each output's offset and bits in the record: 1 where it holds, else 0
// with where it ended in `end` and `at`
KEY_SCHEDULE_CORE int key_schedule_core_record_lay(KeyScheduleCoreLay *lay)
{
    lay->end = KEY_SCHEDULE_CORE_HELD;
    lay->at = 0u;
    unsigned long long table_words = 0ull;
    for (unsigned int table = 0u; table < lay->table_count; table += 1u)
    {
        lay->table_offset[table] = table_words;
        // index_bits is at most 32, and the entry count at most 2^32
        const unsigned long long entries = 1ull << lay->tables[table].index_bits;
        table_words += entries * (unsigned long long)((lay->tables[table].out_bits + 31u) / 32u);
    }
    lay->table_offset[lay->table_count] = table_words;
    for (unsigned int step = 0u; step < lay->step_count; step += 1u)
    {
        const EngineRecordTerm *const term = &lay->terms[step];
        DeviceRecordStep *const device = &lay->steps[step];
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
            if (!((lay->field_offset != NULL) && (term->left < lay->fields)
                  && (((unsigned long long)lay->field_offset[term->left] + term->bits)
                      <= (32ull * (unsigned long long)lay->in_limbs[term->member]))))
            {
                return key_schedule_core_refuse(lay, KEY_SCHEDULE_CORE_STEP, step);
            }
            device->left = lay->field_offset[term->left];
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
            if (!((lay->tables != NULL) && (term->right < lay->table_count)
                  && (lay->table_offset[term->right] <= 0x7FFFFFFFull)))
            {
                return key_schedule_core_refuse(lay, KEY_SCHEDULE_CORE_STEP, step);
            }
            device->left = term->left;
            device->index_bits = lay->tables[term->right].index_bits;
            device->table_offset = (unsigned int)lay->table_offset[term->right];
        }
        else if (term->operation == ENGINE_RECORD_WRAP)
        {
            // keymath took the width from the step's right, at least ENGINE_RECORD_WRAP_BITS_LEAST and an unsigned int
            device->left_limbs = lay->steps[term->left].limbs;
            device->right_limbs = lay->steps[term->right].limbs;
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
            device->left_limbs = lay->steps[term->left].limbs;
            device->right_limbs = lay->steps[term->right].limbs;
        }
    }
    if (key_schedule_core_places(lay) == 0)
    {
        return key_schedule_core_refuse(lay, KEY_SCHEDULE_CORE_FILE, 0u);
    }
    lay->out_bits = 0ull;
    for (unsigned int output = 0u; output < lay->output_count; output += 1u)
    {
        DeviceRecordStep *const device = &lay->steps[lay->outputs[output]];
        // the record's bits are held to a 31-bit count below, and an offset laid is below them
        device->out_offset = (unsigned int)lay->out_bits;
        device->out_bits = lay->terms[lay->outputs[output]].bits + 1u;
        lay->out_bits += (unsigned long long)device->out_bits;
    }
    if (lay->out_bits > 0x7FFFFFFFull)
    {
        return key_schedule_core_refuse(lay, KEY_SCHEDULE_CORE_OUTPUT, 0u);
    }
    return 1;
}

#endif
