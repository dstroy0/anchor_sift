// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_device_terms.h: terms reduced on the device (included by chaitin_omega_internal.h)
#ifndef CHAITIN_OMEGA_DEVICE_TERMS_H
#define CHAITIN_OMEGA_DEVICE_TERMS_H

// the counts in global memory through the read-only cache: lanes read different entries, which constant memory
// would serialize
static inline __device__ unsigned long long omega_device_count(const unsigned long long *__restrict__ counts,
                                                               unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    return __ldg(&counts[(length * (OMEGA_LENGTH_MAX + 2u)) + ((depth < (length - 1u)) ? depth : (length - 1u))]);
}

// omega_unrank with the pending right parts on a stack; each application leaves one more. A term of at most
// 60 bits leaves at most 15. The kernel's buffers hold shorts and the engine's pool long longs.
template <typename Token>
static __device__ unsigned int omega_device_unrank(const unsigned long long *__restrict__ counts, unsigned int length,
                                                   unsigned long long index, Token *term)
{
    unsigned char lengths[16];
    unsigned char depths[16];
    unsigned long long indices[16];
    unsigned int pending = 1u;
    unsigned int size = 0u;
    lengths[0] = (unsigned char)length;
    depths[0] = 0u;
    indices[0] = index;
    while (pending > 0u)
    {
        pending -= 1u;
        unsigned int part = lengths[pending];
        unsigned int depth = depths[pending];
        unsigned long long rank = indices[pending];
        for (;;)
        {
            if ((part - 1u) <= depth)
            {
                if (rank == 0ull)
                {
                    term[size] = (Token)(part - 1u);
                    size += 1u;
                    break;
                }
                rank -= 1ull;
            }
            const unsigned long long bodies = omega_device_count(counts, part - 2u, depth + 1u);
            if (rank < bodies)
            {
                term[size] = OMEGA_LAMBDA;
                size += 1u;
                part -= 2u;
                depth += 1u;
                continue;
            }
            rank -= bodies;
            for (unsigned int left = 2u; (left + 4u) <= part; left += 1u)
            {
                const unsigned long long lefts = omega_device_count(counts, left, depth);
                const unsigned long long rights = omega_device_count(counts, part - 2u - left, depth);
                if (rank < (lefts * rights))
                {
                    term[size] = OMEGA_APPLY;
                    size += 1u;
                    lengths[pending] = (unsigned char)(part - 2u - left);
                    depths[pending] = (unsigned char)depth;
                    indices[pending] = rank % rights;
                    pending += 1u;
                    part = left;
                    rank /= rights;
                    break;
                }
                rank -= lefts * rights;
            }
        }
    }
    return size;
}

static inline __device__ unsigned int omega_device_end(const short *term, unsigned int at)
{
    int need = 1;
    while (need > 0)
    {
        const short token = term[at];
        at += 1u;
        need += (token == OMEGA_APPLY) ? 1 : ((token == OMEGA_LAMBDA) ? 0 : -1);
    }
    return at;
}

// a token started under the open frames: it fills one of the top frame's children, and a lambda or an
// application opens a frame of its own
static inline __device__ void omega_device_open(unsigned char *stack, unsigned int base, unsigned int *top, short token)
{
    if (*top > base)
    {
        stack[*top - 1u] -= 1u;
    }
    if (token == OMEGA_LAMBDA)
    {
        stack[*top] = (unsigned char)(OMEGA_FRAME_LAMBDA | 1u);
        *top += 1u;
    }
    else if (token == OMEGA_APPLY)
    {
        stack[*top] = 2u;
        *top += 1u;
    }
}

// a variable ends every frame whose children have all started; returns the lambdas closed
static inline __device__ int omega_device_close(const unsigned char *stack, unsigned int base, unsigned int *top)
{
    int closed = 0;
    while ((*top > base) && ((stack[*top - 1u] & 3u) == 0u))
    {
        closed += ((stack[*top - 1u] & OMEGA_FRAME_LAMBDA) != 0u) ? 1 : 0;
        *top -= 1u;
    }
    return closed;
}

// omega_lift: the argument [at, end) copied under `lifted` more lambdas; 0 where it outgrows the buffer
static inline __device__ int omega_device_lift(const short *term, unsigned int at, unsigned int end, int lifted,
                                               short *next, unsigned int *out, unsigned int buffer,
                                               unsigned char *stack, unsigned int base)
{
    if ((*out + (end - at)) > buffer)
    {
        return 0;
    }
    if (lifted == 0)
    {
        for (unsigned int from = at; from < end; from += 1u)
        {
            next[*out + (from - at)] = term[from];
        }
        *out += end - at;
        return 1;
    }
    unsigned int top = base;
    int bound = 0;
    for (unsigned int from = at; from < end; from += 1u)
    {
        const short token = term[from];
        omega_device_open(stack, base, &top, token);
        if (token <= 0)
        {
            next[*out] = token;
            *out += 1u;
            bound += (token == OMEGA_LAMBDA) ? 1 : 0;
            continue;
        }
        // an index is at most the lambdas above it, within the buffer. The sum fits a short
        next[*out] = (short)((token > bound) ? (token + lifted) : token);
        *out += 1u;
        bound -= omega_device_close(stack, base, &top);
    }
    return 1;
}

// omega_substitute: the body [at, end) with the argument [argument, argument_end) put for its lambda's variable
static inline __device__ int omega_device_substitute(const short *term, unsigned int at, unsigned int end,
                                                     unsigned int argument, unsigned int argument_end, short *next,
                                                     unsigned int *out, unsigned int buffer, unsigned char *stack)
{
    unsigned int top = 0u;
    int depth = 0;
    for (unsigned int from = at; from < end; from += 1u)
    {
        if (*out >= buffer)
        {
            return 0;
        }
        const short token = term[from];
        omega_device_open(stack, 0u, &top, token);
        if (token <= 0)
        {
            next[*out] = token;
            *out += 1u;
            depth += (token == OMEGA_LAMBDA) ? 1 : 0;
            continue;
        }
        if (token == (depth + 1))
        {
            if (omega_device_lift(term, argument, argument_end, depth, next, out, buffer, stack, top) == 0)
            {
                return 0;
            }
        }
        else
        {
            next[*out] = (short)((token > (depth + 1)) ? (token - 1) : token);
            *out += 1u;
        }
        depth -= omega_device_close(stack, 0u, &top);
    }
    return 1;
}

// omega_step into a buffer of `buffer` tokens
static inline __device__ unsigned int omega_device_step(const short *term, unsigned int size, short *next,
                                                        unsigned int *next_size, unsigned int buffer,
                                                        unsigned char *stack)
{
    for (unsigned int at = 0u; (at + 1u) < size; at += 1u)
    {
        if ((term[at] == OMEGA_APPLY) && (term[at + 1u] == OMEGA_LAMBDA))
        {
            const unsigned int argument = omega_device_end(term, at + 1u);
            const unsigned int after = omega_device_end(term, argument);
            for (unsigned int copy = 0u; copy < at; copy += 1u)
            {
                next[copy] = term[copy];
            }
            unsigned int out = at;
            if (omega_device_substitute(term, at + 2u, argument, argument, after, next, &out, buffer, stack) == 0)
            {
                return OMEGA_STEP_OVERFLOW;
            }
            if ((out + (size - after)) > buffer)
            {
                return OMEGA_STEP_OVERFLOW;
            }
            for (unsigned int copy = after; copy < size; copy += 1u)
            {
                next[out + (copy - after)] = term[copy];
            }
            *next_size = out + (size - after);
            return OMEGA_STEP_TAKEN;
        }
    }
    return OMEGA_STEP_NORMAL;
}

static inline __device__ unsigned int omega_device_spine(const short *term, unsigned int size, unsigned short *ends)
{
    unsigned int range = 0u;
    while ((range < size) && (term[range] == OMEGA_APPLY))
    {
        range += 1u;
    }
    unsigned int end = omega_device_end(term, range);
    ends[range] = (unsigned short)end;
    for (unsigned int position = range; position > 0u; position -= 1u)
    {
        end = omega_device_end(term, end);
        ends[position - 1u] = (unsigned short)end;
    }
    return range;
}

static inline __device__ unsigned int omega_device_head_redex(const short *term, unsigned int size)
{
    unsigned int range = 0u;
    while ((range < size) && (term[range] == OMEGA_APPLY))
    {
        range += 1u;
    }
    return ((range > 0u) && (range < size) && (term[range] == OMEGA_LAMBDA)) ? (range - 1u) : OMEGA_NOT_HEAD;
}

static inline __device__ int omega_device_same(const short *one, const short *other, unsigned int size)
{
    for (unsigned int at = 0u; at < size; at += 1u)
    {
        if (one[at] != other[at])
        {
            return 0;
        }
    }
    return 1;
}

// omega_grows_forever
static inline __device__ int omega_device_grows_forever(const OmegaBuffers *buffers, unsigned int stored_range,
                                                        const short *term, unsigned int size, unsigned int least)
{
    const unsigned int range = omega_device_spine(term, size, buffers->ends);
    const unsigned int deepest = (least < stored_range) ? least : stored_range;
    for (unsigned int from = 0u; from <= deepest; from += 1u)
    {
        const unsigned int part = (unsigned int)buffers->stored_ends[from] - from;
        for (unsigned int to = from + 1u; to <= range; to += 1u)
        {
            if ((((unsigned int)buffers->ends[to] - to) == part) &&
                (omega_device_same(&buffers->stored[from], &term[to], part) != 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// omega_run; the term ends in *term (the buffers' term and next swap as it steps), and a step that outgrows the buffer
// returns OMEGA_HOST_RUNS
static inline __device__ unsigned int omega_device_run(const OmegaBuffers *buffers, short **term, short **next,
                                                       unsigned int *size, unsigned int steps, unsigned int tokens,
                                                       unsigned int buffer, unsigned int *taken)
{
    for (unsigned int at = 0u; at < *size; at += 1u)
    {
        buffers->stored[at] = (*term)[at];
    }
    unsigned int stored_size = *size;
    unsigned int stored_range = omega_device_spine(buffers->stored, stored_size, buffers->stored_ends);
    unsigned int least = OMEGA_NOT_HEAD - 1u;
    unsigned int power = 1u;
    unsigned int since = 0u;
    *taken = steps;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int redex = omega_device_head_redex(*term, *size);
        unsigned int next_size = 0u;
        const unsigned int stepped = omega_device_step(*term, *size, *next, &next_size, buffer, buffers->stack);
        if (stepped == OMEGA_STEP_NORMAL)
        {
            *taken = step;
            return OMEGA_HALTS;
        }
        if (stepped == OMEGA_STEP_OVERFLOW)
        {
            return OMEGA_HOST_RUNS;
        }
        least = ((redex == OMEGA_NOT_HEAD) || (least == OMEGA_NOT_HEAD)) ? OMEGA_NOT_HEAD
                                                                         : ((redex < least) ? redex : least);
        short *const swap = *term;
        *term = *next;
        *next = swap;
        *size = next_size;
        if ((*size == stored_size) && (omega_device_same(*term, buffers->stored, stored_size) != 0))
        {
            return OMEGA_LOOPS;
        }
        if ((least != OMEGA_NOT_HEAD) && (omega_device_grows_forever(buffers, stored_range, *term, *size, least) != 0))
        {
            return OMEGA_DIVERGES;
        }
        if (*size > tokens)
        {
            return OMEGA_GREW;
        }
        since += 1u;
        if (since == power)
        {
            for (unsigned int at = 0u; at < *size; at += 1u)
            {
                buffers->stored[at] = (*term)[at];
            }
            stored_size = *size;
            stored_range = omega_device_spine(buffers->stored, stored_size, buffers->stored_ends);
            least = OMEGA_NOT_HEAD - 1u;
            power *= 2u;
            since = 0u;
        }
    }
    for (unsigned int at = 0u; (at + 1u) < *size; at += 1u)
    {
        if (((*term)[at] == OMEGA_APPLY) && ((*term)[at + 1u] == OMEGA_LAMBDA))
        {
            return OMEGA_OPEN;
        }
    }
    return OMEGA_HALTS;
}
#endif
