// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_pool.cu: the pool's program, its kernels and admission
#include "chaitin_omega_internal.h"

static void omega_program_step(EngineRecordStep *steps, unsigned int *count, EngineRecordOperation operation,
                               unsigned int left, unsigned int right, unsigned int member)
{
    steps[*count].operation = operation;
    steps[*count].left = left;
    steps[*count].right = right;
    steps[*count].member = member;
    *count += 1u;
}

int omega_program_load(OmegaProgram *program, EngineError *error)
{
    EngineRecordStep steps[OMEGA_PROGRAM_OUT + 1u];
    unsigned int count = 0u;
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 s
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 1u, 0u, 1u);        // 1 p
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 2u, 0u, 1u);        // 2 b
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 3u, 0u, 1u);        // 3 body
    omega_program_step(steps, &count, ENGINE_RECORD_FIELD, 4u, 0u, 1u);        // 4 argument
    omega_program_step(steps, &count, ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);     // 5 1
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 1u, 5u, 0u);          // 6 p + 1
    omega_program_step(steps, &count, ENGINE_RECORD_COMPARE, 0u, 6u, 0u);      // 7 sign(s - p - 1)
    omega_program_step(steps, &count, ENGINE_RECORD_ABSOLUTE, 7u, 0u, 0u);     // 8
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);          // 9 2 [s > p + 1]
    omega_program_step(steps, &count, ENGINE_RECORD_CONSTANT, 2u, 0u, 0u);     // 10 2
    omega_program_step(steps, &count, ENGINE_RECORD_QUOTIENT, 9u, 10u, 0u);    // 11 [s > p + 1]
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 11u, 0u);     // 12 the body's move in
    omega_program_step(steps, &count, ENGINE_RECORD_COMPARE, 0u, 2u, 0u);      // 13 sign(s - b)
    omega_program_step(steps, &count, ENGINE_RECORD_ABSOLUTE, 13u, 0u, 0u);    // 14
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 13u, 14u, 0u);        // 15 2 [s > b]
    omega_program_step(steps, &count, ENGINE_RECORD_QUOTIENT, 15u, 10u, 0u);   // 16 [s > b]
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 16u, 1u, 0u);     // 17 [s > b] p
    omega_program_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 17u, 0u);     // 18 the argument's move out
    omega_program_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 0u, 12u, 0u);  // 19
    omega_program_step(steps, &count, ENGINE_RECORD_SUM, 19u, 18u, 0u);        // 20 the reduct's token
    const unsigned int field_bits[5] = {program->token_bits, program->depth_bits, program->bound_bits, 1u, 1u};
    const unsigned int field_offset[5] = {0u, 0u, program->depth_bits, program->depth_bits + program->bound_bits,
                                          program->depth_bits + program->bound_bits + 1u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {
        (program->token_bits + 31u) / 32u, (program->depth_bits + program->bound_bits + 2u + 31u) / 32u, 0u};
    const unsigned int outputs[1] = {OMEGA_PROGRAM_OUT};
    memset(&program->key, 0, sizeof(program->key));
    memset(&program->layout, 0, sizeof(program->layout));
    program->record = NULL;
    const KeymathRecordRequest encode_request = {steps, count, field_bits,    5u,   2u, outputs, 1u,
                                                 NULL,  0u,    &program->key, error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, 5u, in_limbs, 1,
                                                     &program->layout, error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&program->key);
        return 0;
    }
    if (cycle_record_load(&program->layout, &program->record, error) == CYCLE_ERROR)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    program->out_offset = program->layout.step_table[OMEGA_PROGRAM_OUT].out_offset;
    program->out_bits = program->layout.step_table[OMEGA_PROGRAM_OUT].out_bits;
    return 1;
}

void omega_program_free(OmegaProgram *program)
{
    cycle_record_release(program->record);
    key_schedule_record_release(&program->layout);
    keymath_record_release(&program->key);
}

// every index of [0, count) once across the launch's threads
#define OMEGA_POOL_EACH(at_, count_)                                                                                   \
    for (unsigned long long at_ = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; at_ < (count_);         \
         at_ += (unsigned long long)gridDim.x * blockDim.x)

// phase one of a round, a thread a term: the redex, what the reduct holds, and the widths its values need; a normal
// form settles. A settled term reduces to nothing. Its out size is 0.
__global__ void omega_pool_survey(OmegaTerm *terms, unsigned long long live, const OmegaToken *tokens,
                                  unsigned char *frames, unsigned long long *out_sizes, OmegaRoundTotals *totals)
{
    OMEGA_POOL_EACH(at, live)
    {
        OmegaTerm *const term = &terms[at];
        const OmegaToken *const text = &tokens[term->base];
        const unsigned long long size = term->size;
        atomicMax(&totals->max_tokens, size);
        term->head = omega_pool_head(text, size);
        term->redex = OMEGA_ENGINE_NONE;
        term->out_size = 0ull;
        out_sizes[at] = 0ull;
        unsigned long long max_token = 1ull;
        for (unsigned long long token = 0ull; token < size; token += 1ull)
        {
            const unsigned long long magnitude = (unsigned long long)((text[token] < 0) ? -text[token] : text[token]);
            max_token = (magnitude > max_token) ? magnitude : max_token;
            if ((term->redex == OMEGA_ENGINE_NONE) && ((token + 1ull) < size) && (text[token] == OMEGA_APPLY) &&
                (text[token + 1ull] == OMEGA_LAMBDA))
            {
                term->redex = token;
            }
        }
        if (term->redex == OMEGA_ENGINE_NONE)
        {
            unsigned long long bits = 0ull;
            for (unsigned long long token = 0ull; token < size; token += 1ull)
            {
                bits += (text[token] <= 0) ? 2ull : ((unsigned long long)text[token] + 1ull);
            }
            term->fate = OMEGA_HALTS;
            term->bits = bits;
            continue;
        }
        term->argument = omega_pool_end(text, term->redex + 1ull);
        term->after = omega_pool_end(text, term->argument);
        OmegaWalk walk = {&frames[term->base], 0ull, 0ull};
        unsigned long long uses = 0ull;
        unsigned long long max_depth = 0ull;
        for (unsigned long long token = term->redex + 2ull; token < term->argument; token += 1ull)
        {
            omega_walk_open(&walk, text[token]);
            max_depth = (walk.depth > max_depth) ? walk.depth : max_depth;
            if (text[token] > 0)
            {
                uses += (text[token] == (OmegaToken)(walk.depth + 1ull)) ? 1ull : 0ull;
                omega_walk_close(&walk);
            }
        }
        walk.top = 0ull;
        walk.depth = 0ull;
        unsigned long long max_bound = 0ull;
        for (unsigned long long token = term->argument; token < term->after; token += 1ull)
        {
            omega_walk_open(&walk, text[token]);
            max_bound = (walk.depth > max_bound) ? walk.depth : max_bound;
            if (text[token] > 0)
            {
                omega_walk_close(&walk);
            }
        }
        const unsigned long long body = term->argument - (term->redex + 2ull);
        const unsigned long long argument = term->after - term->argument;
        term->out_size = term->redex + (body - uses) + (uses * argument) + (size - term->after);
        out_sizes[at] = term->out_size;
        atomicMax(&totals->max_token, max_token);
        atomicMax(&totals->max_depth, max_depth);
        atomicMax(&totals->max_bound, max_bound);
    }
}

// phase two: the round's records. Every token of the pool becomes a record of member 0, and each reduct token a
// plan record of member 1 with the source it gathers.
__global__ void omega_pool_pack(const OmegaToken *tokens, unsigned long long count, OmegaRoundWidths widths,
                                unsigned int *packed)
{
    OMEGA_POOL_EACH(at, count)
    {
        unsigned int *const record = &packed[at * widths.token_limbs];
        for (unsigned int limb = 0u; limb < widths.token_limbs; limb += 1u)
        {
            record[limb] = 0u;
        }
        omega_pool_put(record, 0u, widths.token_bits, tokens[at]);
    }
}

// A reduct token's plan and the index pair that gathers it. The source is below OMEGA_ENGINE_INDEX_MAX, which the
// host checks before the round, and the plan's place restarts at each sweep. Both fit the engine's 32-bit index.
static __device__ void omega_pool_plan(const OmegaRoundWidths *widths, unsigned int *plans, unsigned int *index,
                                       unsigned long long out, unsigned long long source, unsigned long long depth,
                                       unsigned long long bound, unsigned int body, unsigned int argument)
{
    unsigned int *const plan = &plans[out * widths->plan_limbs];
    for (unsigned int limb = 0u; limb < widths->plan_limbs; limb += 1u)
    {
        plan[limb] = 0u;
    }
    omega_pool_put(plan, 0u, widths->depth_bits, (OmegaToken)depth);
    omega_pool_put(plan, widths->depth_bits, widths->bound_bits, (OmegaToken)bound);
    omega_pool_put(plan, widths->depth_bits + widths->bound_bits, 1u, (OmegaToken)body);
    omega_pool_put(plan, widths->depth_bits + widths->bound_bits + 1u, 1u, (OmegaToken)argument);
    index[2ull * out] = (unsigned int)source;
    index[(2ull * out) + 1ull] = (unsigned int)(out % OMEGA_ENGINE_SWEEP);
}

// a thread a stepping term lays out its reduct's plans at the term's out base
__global__ void omega_pool_place(const OmegaTerm *terms, unsigned long long live, const OmegaToken *tokens,
                                 const unsigned long long *out_bases, unsigned char *frames,
                                 unsigned char *inner_frames, OmegaRoundWidths widths, unsigned int *plans,
                                 unsigned int *index)
{
    OMEGA_POOL_EACH(at, live)
    {
        const OmegaTerm *const term = &terms[at];
        if (term->fate >= 0)
        {
            continue;
        }
        const OmegaToken *const text = &tokens[term->base];
        unsigned long long out = out_bases[at];
        for (unsigned long long token = 0ull; token < term->redex; token += 1ull)
        {
            omega_pool_plan(&widths, plans, index, out, term->base + token, 0ull, 0ull, 0u, 0u);
            out += 1ull;
        }
        OmegaWalk walk = {&frames[term->base], 0ull, 0ull};
        for (unsigned long long token = term->redex + 2ull; token < term->argument; token += 1ull)
        {
            omega_walk_open(&walk, text[token]);
            if ((text[token] > 0) && (text[token] == (OmegaToken)(walk.depth + 1ull)))
            {
                OmegaWalk inner = {&inner_frames[term->base], 0ull, 0ull};
                for (unsigned long long copy = term->argument; copy < term->after; copy += 1ull)
                {
                    omega_walk_open(&inner, text[copy]);
                    omega_pool_plan(&widths, plans, index, out, term->base + copy, walk.depth, inner.depth, 0u, 1u);
                    out += 1ull;
                    if (text[copy] > 0)
                    {
                        omega_walk_close(&inner);
                    }
                }
            }
            else
            {
                omega_pool_plan(&widths, plans, index, out, term->base + token, walk.depth, 0ull, 1u, 0u);
                out += 1ull;
            }
            if (text[token] > 0)
            {
                omega_walk_close(&walk);
            }
        }
        for (unsigned long long token = term->after; token < term->size; token += 1ull)
        {
            omega_pool_plan(&widths, plans, index, out, term->base + token, 0ull, 0ull, 0u, 0u);
            out += 1ull;
        }
    }
}

// a sweep's reduct tokens read back out of the machine's records; one that does not fit a token is marked unread
__global__ void omega_pool_unpack(const unsigned int *out, unsigned long long lanes, unsigned int out_limbs,
                                  unsigned int offset, unsigned int bits, OmegaToken *reducts, OmegaRoundTotals *totals)
{
    OMEGA_POOL_EACH(lane, lanes)
    {
        if (omega_pool_take(&out[lane * out_limbs], offset, bits, &reducts[lane]) == 0)
        {
            atomicExch(&totals->unread, 1u);
        }
    }
}

// Phase three, a thread a stepping term: its reduct watched as omega_run watches it. The spine ends of the reduct
// go to `ends` at the term's out base plus its place in the pool, which leaves each term out_size + 1 of them.
__global__ void omega_pool_watch(OmegaTerm *terms, unsigned long long live, const OmegaToken *reducts,
                                 const unsigned long long *out_bases, const OmegaToken *stored,
                                 const unsigned long long *stored_ends, unsigned long long *ends)
{
    OMEGA_POOL_EACH(at, live)
    {
        OmegaTerm *const term = &terms[at];
        if (term->fate >= 0)
        {
            continue;
        }
        term->out_base = out_bases[at];
        term->stored_again = 0u;
        const OmegaToken *const text = &reducts[term->out_base];
        const unsigned long long size = term->out_size;
        term->least = ((term->head == OMEGA_ENGINE_NONE) || (term->least == OMEGA_ENGINE_NONE))
                          ? OMEGA_ENGINE_NONE
                          : ((term->head < term->least) ? term->head : term->least);
        term->steps += 1ull;
        if ((size == term->stored_size) && (omega_pool_same(text, &stored[term->stored_base], size) != 0))
        {
            term->fate = OMEGA_LOOPS;
            continue;
        }
        if ((term->least != OMEGA_ENGINE_NONE) &&
            (omega_pool_grows(&stored[term->stored_base], &stored_ends[term->ends_base], term->stored_range, text, size,
                              term->least, &ends[term->out_base + at]) != 0))
        {
            term->fate = OMEGA_DIVERGES;
            continue;
        }
        term->since += 1ull;
        if (term->since == term->power)
        {
            term->stored_again = 1u;
            term->least = OMEGA_ENGINE_NONE - 1ull;
            term->power *= 2ull;
            term->since = 0ull;
        }
    }
}

// every settled term as one record for the host, in no fixed order
__global__ void omega_pool_settled(const OmegaTerm *terms, unsigned long long live, OmegaSettled *settled,
                                   OmegaRoundTotals *totals)
{
    OMEGA_POOL_EACH(at, live)
    {
        const OmegaTerm *const term = &terms[at];
        if (term->fate < 0)
        {
            continue;
        }
        const unsigned long long slot = atomicAdd(&totals->settled, 1ull);
        settled[slot].length = term->length;
        settled[slot].job = term->job;
        settled[slot].index = term->index;
        settled[slot].fate = term->fate;
        settled[slot].steps = term->steps;
        settled[slot].bits = term->bits;
    }
}

// the sizes each kept term takes in the next round's buffers: its place, its tokens, its watcher's copy and that
// copy's spine ends; a settled term takes none
__global__ void omega_pool_kept_sizes(const OmegaTerm *terms, unsigned long long live, unsigned long long *places,
                                      unsigned long long *token_sizes, unsigned long long *stored_sizes,
                                      unsigned long long *end_sizes)
{
    OMEGA_POOL_EACH(at, live)
    {
        const OmegaTerm *const term = &terms[at];
        const unsigned long long kept = (term->fate < 0) ? 1ull : 0ull;
        const unsigned long long stored_count = (term->stored_again != 0u) ? term->out_size : term->stored_size;
        places[at] = kept;
        token_sizes[at] = kept * term->out_size;
        stored_sizes[at] = kept * stored_count;
        end_sizes[at] = kept * (stored_count + 1ull);
    }
}

// a block a kept term moves its reduct, its watcher's copy and that copy's spine ends into the next round's buffers
__global__ void omega_pool_keep(const OmegaTerm *terms, unsigned long long live, const OmegaToken *reducts,
                                const OmegaToken *stored, const unsigned long long *stored_ends,
                                const unsigned long long *places, const unsigned long long *token_bases,
                                const unsigned long long *stored_bases, const unsigned long long *end_bases,
                                OmegaTerm *kept, OmegaToken *kept_tokens, OmegaToken *kept_stored,
                                unsigned long long *kept_ends)
{
    for (unsigned long long at = blockIdx.x; at < live; at += gridDim.x)
    {
        const OmegaTerm *const term = &terms[at];
        if (term->fate >= 0)
        {
            continue;
        }
        const OmegaToken *const reduct = &reducts[term->out_base];
        const OmegaToken *const copy = (term->stored_again != 0u) ? reduct : &stored[term->stored_base];
        const unsigned long long copy_size = (term->stored_again != 0u) ? term->out_size : term->stored_size;
        for (unsigned long long token = threadIdx.x; token < term->out_size; token += blockDim.x)
        {
            kept_tokens[token_bases[at] + token] = reduct[token];
        }
        for (unsigned long long token = threadIdx.x; token < copy_size; token += blockDim.x)
        {
            kept_stored[stored_bases[at] + token] = copy[token];
        }
        if (term->stored_again == 0u)
        {
            for (unsigned long long end = threadIdx.x; end <= term->stored_range; end += blockDim.x)
            {
                kept_ends[end_bases[at] + end] = stored_ends[term->ends_base + end];
            }
        }
        if (threadIdx.x == 0u)
        {
            OmegaTerm moved = *term;
            moved.base = token_bases[at];
            moved.size = term->out_size;
            moved.stored_base = stored_bases[at];
            moved.stored_size = copy_size;
            moved.ends_base = end_bases[at];
            if (term->stored_again != 0u)
            {
                // read from the reduct, which the block's other threads are still copying out of, not into
                moved.stored_range = omega_pool_spine(reduct, term->out_size, &kept_ends[end_bases[at]]);
            }
            kept[places[at]] = moved;
        }
    }
}

// the sizes of a job's terms, each unranked into the thread's own buffer; a term of L bits has fewer than L tokens
__global__ void omega_pool_insert_sizes(const unsigned long long *counts, unsigned int length, unsigned long long from,
                                        unsigned long long count, unsigned long long *sizes)
{
    OmegaToken term[OMEGA_LENGTH_MAX];
    OMEGA_POOL_EACH(at, count)
    {
        sizes[at] = omega_device_unrank(counts, length, from + at, term);
    }
}

// a job's terms admitted after the pool's `live` terms, their tokens, copies and spine ends after the buffers' ends
__global__ void omega_pool_insert(const unsigned long long *counts, unsigned int length, unsigned int job,
                                  unsigned long long from, unsigned long long count, const unsigned long long *offsets,
                                  unsigned long long live, unsigned long long token_end, unsigned long long stored_end,
                                  unsigned long long ends_end, OmegaTerm *terms, OmegaToken *tokens, OmegaToken *stored,
                                  unsigned long long *stored_ends)
{
    OMEGA_POOL_EACH(at, count)
    {
        const unsigned long long offset = offsets[at];
        OmegaToken *const text = &tokens[token_end + offset];
        const unsigned int size = omega_device_unrank(counts, length, from + at, text);
        for (unsigned int token = 0u; token < size; token += 1u)
        {
            stored[stored_end + offset + token] = text[token];
        }
        OmegaTerm term;
        term.index = from + at;
        term.steps = 0ull;
        term.power = 1ull;
        term.since = 0ull;
        term.least = OMEGA_ENGINE_NONE - 1ull;
        term.base = token_end + offset;
        term.size = size;
        term.stored_base = stored_end + offset;
        term.stored_size = size;
        term.ends_base = ends_end + offset + at;
        term.stored_range = omega_pool_spine(text, size, &stored_ends[term.ends_base]);
        term.head = OMEGA_ENGINE_NONE;
        term.redex = OMEGA_ENGINE_NONE;
        term.argument = 0ull;
        term.after = 0ull;
        term.out_size = 0ull;
        term.out_base = 0ull;
        term.bits = 0ull;
        term.length = length;
        term.job = job;
        term.fate = -1;
        term.stored_again = 0u;
        terms[live + at] = term;
    }
}
