// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_pool_terms.h: the pool's terms, walks and records on the device (included by chaitin_omega_internal.h)
#ifndef CHAITIN_OMEGA_POOL_TERMS_H
#define CHAITIN_OMEGA_POOL_TERMS_H

static inline __device__ unsigned long long omega_pool_end(const OmegaToken *term, unsigned long long at)
{
    long long need = 1;
    while (need > 0)
    {
        const OmegaToken token = term[at];
        at += 1ull;
        need += (token == OMEGA_APPLY) ? 1 : ((token == OMEGA_LAMBDA) ? 0 : -1);
    }
    return at;
}

// omega_spine on a pool term: the spine subterm ends into `ends`, and the leading applications returned
static inline __device__ unsigned long long omega_pool_spine(const OmegaToken *term, unsigned long long size,
                                                             unsigned long long *ends)
{
    unsigned long long range = 0ull;
    while ((range < size) && (term[range] == OMEGA_APPLY))
    {
        range += 1ull;
    }
    unsigned long long end = omega_pool_end(term, range);
    ends[range] = end;
    for (unsigned long long position = range; position > 0ull; position -= 1ull)
    {
        end = omega_pool_end(term, end);
        ends[position - 1ull] = end;
    }
    return range;
}

static inline __device__ unsigned long long omega_pool_head(const OmegaToken *term, unsigned long long size)
{
    unsigned long long range = 0ull;
    while ((range < size) && (term[range] == OMEGA_APPLY))
    {
        range += 1ull;
    }
    return ((range > 0ull) && (range < size) && (term[range] == OMEGA_LAMBDA)) ? (range - 1ull) : OMEGA_ENGINE_NONE;
}

static inline __device__ int omega_pool_same(const OmegaToken *one, const OmegaToken *other, unsigned long long size)
{
    for (unsigned long long at = 0ull; at < size; at += 1ull)
    {
        if (one[at] != other[at])
        {
            return 0;
        }
    }
    return 1;
}

// omega_grows_forever on a pool term, its spine ends written to `ends`
static inline __device__ int omega_pool_grows(const OmegaToken *stored, const unsigned long long *stored_ends,
                                              unsigned long long stored_range, const OmegaToken *term,
                                              unsigned long long size, unsigned long long least,
                                              unsigned long long *ends)
{
    const unsigned long long range = omega_pool_spine(term, size, ends);
    const unsigned long long deepest = (least < stored_range) ? least : stored_range;
    for (unsigned long long from = 0ull; from <= deepest; from += 1ull)
    {
        const unsigned long long part = stored_ends[from] - from;
        for (unsigned long long to = from + 1ull; to <= range; to += 1ull)
        {
            if (((ends[to] - to) == part) && (omega_pool_same(&stored[from], &term[to], part) != 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// A walk over one subterm keeping the lambdas above each token. The frames, one byte each in the pool's frame
// buffer at the term's own place, hold the children still to start and whether the frame is a lambda; a subterm has
// no more frames open than it has tokens.
typedef struct
{
    unsigned char *frames;
    unsigned long long top;
    unsigned long long depth;
} OmegaWalk;

static inline __device__ void omega_walk_open(OmegaWalk *walk, OmegaToken token)
{
    if (walk->top > 0ull)
    {
        walk->frames[walk->top - 1ull] -= 1u;
    }
    if (token == OMEGA_LAMBDA)
    {
        walk->frames[walk->top] = (unsigned char)(OMEGA_FRAME_LAMBDA | 1u);
        walk->top += 1ull;
        walk->depth += 1ull;
    }
    else if (token == OMEGA_APPLY)
    {
        walk->frames[walk->top] = 2u;
        walk->top += 1ull;
    }
}

// after a variable: every frame whose children have all started is ended
static inline __device__ void omega_walk_close(OmegaWalk *walk)
{
    while ((walk->top > 0ull) && ((walk->frames[walk->top - 1ull] & 3u) == 0u))
    {
        walk->depth -= ((walk->frames[walk->top - 1ull] & OMEGA_FRAME_LAMBDA) != 0u) ? 1ull : 0ull;
        walk->top -= 1ull;
    }
}

static inline unsigned int omega_engine_bits_of(unsigned long long value)
{
    unsigned int bits = 1u;
    while ((bits < 64u) && ((value >> bits) != 0ull))
    {
        bits += 1u;
    }
    return bits;
}

// `bits` of a value into a record at `offset`, two's complement when negative
static inline __device__ void omega_pool_put(unsigned int *record, unsigned int offset, unsigned int bits,
                                             OmegaToken value)
{
    const unsigned long long word = (unsigned long long)value;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int bit_value = (bit < 64u) ? (unsigned int)((word >> bit) & 1ull) : ((value < 0) ? 1u : 0u);
        const unsigned int to = offset + bit;
        record[to / 32u] |= bit_value << (to % 32u);
    }
}

// `bits` of a record at `offset` as two's complement; 0 where the value does not fit a token
static inline __device__ int omega_pool_take(const unsigned int *record, unsigned int offset, unsigned int bits,
                                             OmegaToken *value)
{
    const unsigned int top = offset + bits - 1u;
    const unsigned int sign = (record[top / 32u] >> (top % 32u)) & 1u;
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        const unsigned int bit_value = (record[from / 32u] >> (from % 32u)) & 1u;
        if (bit < 64u)
        {
            word |= (unsigned long long)bit_value << bit;
        }
        else if (bit_value != sign)
        {
            return 0;
        }
    }
    if ((bits < 64u) && (sign != 0u))
    {
        word |= ~0ull << bits;
    }
    *value = (OmegaToken)word;
    return 1;
}

// the reduct's token from the source token s and its plan: a body token at depth p, or an argument's token put
// under p lambdas with b lambdas above it inside the argument, or a copy
//   s - body . [s > p + 1] + argument . [s > b] . p
typedef struct
{
    unsigned int token_bits;
    unsigned int depth_bits;
    unsigned int bound_bits;
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    unsigned int out_offset;
    unsigned int out_bits;
} OmegaProgram;

#define OMEGA_PROGRAM_OUT 20u
#endif
