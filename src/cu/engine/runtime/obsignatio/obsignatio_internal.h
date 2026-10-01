// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the obsignatio_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef OBSIGNATIO_INTERNAL_H
#define OBSIGNATIO_INTERNAL_H

#include "../../../../engine/runtime/obsignatio/obsignatio.h"

// a part with no CUDA toolchain (the Pi, tessera on every target) compiles the seal as C++: the functions the host and
// the device share are the host's alone, and the kernels and the calls that launch them are left out
#if defined(__CUDACC__)
#include <cuda_runtime.h>
#define OBSIGNATIO_SHARED __host__ __device__
#else
#define OBSIGNATIO_SHARED
#endif

#include <string.h>

#if defined(__CUDACC__)
static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");
#endif

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define OBSIGNATIO_STATUS_CHECK(call_, evacaddr_, error_)                                                              \
    engine_status_check((int)(call_), ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__, (const void *)(evacaddr_),     \
                        (error_))

#define OBSIGNATIO_CHECK(condition_, evacaddr_, error_)                                                                \
    engine_error_check((condition_), ENGINE_ERROR_REQUEST, ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__,           \
                       (const void *)(evacaddr_), (error_))

#define OBSIGNATIO_BLOCK_BYTES 64u

#define OBSIGNATIO_CHUNK_SHIFT 10u

#define OBSIGNATIO_CHUNK_BYTES (1u << OBSIGNATIO_CHUNK_SHIFT)

#define OBSIGNATIO_DEPTH (64u - OBSIGNATIO_CHUNK_SHIFT)

#define OBSIGNATIO_CHAINING_WORDS 8u

#define OBSIGNATIO_BLOCK_WORDS 16u

#define OBSIGNATIO_ROUNDS 7u

#define OBSIGNATIO_CHUNK_START 1u

#define OBSIGNATIO_CHUNK_END 2u

#define OBSIGNATIO_PARENT 4u

#define OBSIGNATIO_ROOT 8u

#define OBSIGNATIO_IV0 0x6A09E667u
#define OBSIGNATIO_IV1 0xBB67AE85u
#define OBSIGNATIO_IV2 0x3C6EF372u
#define OBSIGNATIO_IV3 0xA54FF53Au
#define OBSIGNATIO_IV4 0x510E527Fu
#define OBSIGNATIO_IV5 0x9B05688Cu
#define OBSIGNATIO_IV6 0x1F83D9ABu
#define OBSIGNATIO_IV7 0x5BE0CD19u

typedef struct
{
    unsigned int words[OBSIGNATIO_CHAINING_WORDS];
} ObsignatioKey;

typedef struct
{
    unsigned int chaining[OBSIGNATIO_CHAINING_WORDS];
    unsigned int block[OBSIGNATIO_BLOCK_WORDS];
    unsigned long long counter;
    unsigned int block_bytes;
    unsigned int flags;
} ObsignatioNode;

#define OBSIGNATIO_LENGTH_BYTES 8ull

typedef struct
{
    const unsigned char *bytes;
    const unsigned int *limbs;
    unsigned long long first_bit;
    unsigned long long bits;
    unsigned long long count;
} ObsignatioSource;

OBSIGNATIO_SHARED static inline unsigned int obsignatio_rotate(unsigned int word, unsigned int count)
{
    return (word >> count) | (word << (32u - count));
}

OBSIGNATIO_SHARED static inline void obsignatio_mix(unsigned int *state, unsigned int first, unsigned int second,
                                                    unsigned int third, unsigned int fourth, unsigned int message_first,
                                                    unsigned int message_second)
{
    state[first] = state[first] + state[second] + message_first;
    state[fourth] = obsignatio_rotate(state[fourth] ^ state[first], 16u);
    state[third] = state[third] + state[fourth];
    state[second] = obsignatio_rotate(state[second] ^ state[third], 12u);
    state[first] = state[first] + state[second] + message_second;
    state[fourth] = obsignatio_rotate(state[fourth] ^ state[first], 8u);
    state[third] = state[third] + state[fourth];
    state[second] = obsignatio_rotate(state[second] ^ state[third], 7u);
}

OBSIGNATIO_SHARED static inline void obsignatio_round(unsigned int *state, const unsigned int *message)
{
    obsignatio_mix(state, 0u, 4u, 8u, 12u, message[0], message[1]);
    obsignatio_mix(state, 1u, 5u, 9u, 13u, message[2], message[3]);
    obsignatio_mix(state, 2u, 6u, 10u, 14u, message[4], message[5]);
    obsignatio_mix(state, 3u, 7u, 11u, 15u, message[6], message[7]);
    obsignatio_mix(state, 0u, 5u, 10u, 15u, message[8], message[9]);
    obsignatio_mix(state, 1u, 6u, 11u, 12u, message[10], message[11]);
    obsignatio_mix(state, 2u, 7u, 8u, 13u, message[12], message[13]);
    obsignatio_mix(state, 3u, 4u, 9u, 14u, message[14], message[15]);
}

OBSIGNATIO_SHARED static inline void obsignatio_permute(unsigned int *message)
{
    const unsigned int permuted[OBSIGNATIO_BLOCK_WORDS] = {
        message[2], message[6],  message[3],  message[10], message[7], message[0],  message[4],  message[13],
        message[1], message[11], message[12], message[5],  message[9], message[14], message[15], message[8]};
    for (unsigned int word = 0u; word < OBSIGNATIO_BLOCK_WORDS; word += 1u)
    {
        message[word] = permuted[word];
    }
}

OBSIGNATIO_SHARED static inline void obsignatio_compress(const unsigned int *chaining, const unsigned int *block,
                                                         unsigned long long counter, unsigned int block_bytes,
                                                         unsigned int flags, unsigned int *out)
{
    unsigned int message[OBSIGNATIO_BLOCK_WORDS];
    for (unsigned int word = 0u; word < OBSIGNATIO_BLOCK_WORDS; word += 1u)
    {
        message[word] = block[word];
    }
    // the counter splits into its low and high 32-bit halves, each kept whole
    unsigned int state[OBSIGNATIO_BLOCK_WORDS] = {chaining[0],           chaining[1],
                                                  chaining[2],           chaining[3],
                                                  chaining[4],           chaining[5],
                                                  chaining[6],           chaining[7],
                                                  OBSIGNATIO_IV0,        OBSIGNATIO_IV1,
                                                  OBSIGNATIO_IV2,        OBSIGNATIO_IV3,
                                                  (unsigned int)counter, (unsigned int)(counter >> 32u),
                                                  block_bytes,           flags};
    for (unsigned int round = 0u; round < OBSIGNATIO_ROUNDS; round += 1u)
    {
        obsignatio_round(state, message);
        obsignatio_permute(message);
    }
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        out[word] = state[word] ^ state[word + OBSIGNATIO_CHAINING_WORDS];
        out[word + OBSIGNATIO_CHAINING_WORDS] = state[word + OBSIGNATIO_CHAINING_WORDS] ^ chaining[word];
    }
}

OBSIGNATIO_SHARED static inline unsigned int obsignatio_source_byte(const ObsignatioSource *source,
                                                                    unsigned long long at)
{
    if (source->bytes != NULL)
    {
        return source->bytes[at];
    }
    if (at < OBSIGNATIO_LENGTH_BYTES)
    {
        // one byte of the bit length, shifted down and masked, fits an unsigned int
        return (unsigned int)((source->bits >> (8ull * at)) & 0xFFull);
    }
    const unsigned long long first = (at - OBSIGNATIO_LENGTH_BYTES) * 8ull;
    const unsigned long long remain = source->bits - first;
    // the take is at most one byte's 8 bits. It fits an unsigned int
    const unsigned int take = (remain < 8ull) ? (unsigned int)remain : 8u;
    const unsigned long long place = source->first_bit + first;
    // a place taken modulo 32 fits an unsigned int
    const unsigned int shift = (unsigned int)(place % 32ull);
    unsigned long long pair = source->limbs[place / 32ull];
    if ((shift + take) > 32u)
    {
        pair |= (unsigned long long)source->limbs[(place / 32ull) + 1ull] << 32u;
    }
    // the value is masked to at most 8 bits. It fits an unsigned int
    return (unsigned int)((pair >> shift) & ((1ull << take) - 1ull));
}

OBSIGNATIO_SHARED static inline void obsignatio_block_load(const ObsignatioSource *source, unsigned long long start,
                                                           unsigned int count, unsigned int *block)
{
    for (unsigned int word = 0u; word < OBSIGNATIO_BLOCK_WORDS; word += 1u)
    {
        block[word] = 0u;
    }
    for (unsigned int byte = 0u; byte < count; byte += 1u)
    {
        block[byte / 4u] |= obsignatio_source_byte(source, start + byte) << (8u * (byte % 4u));
    }
}

OBSIGNATIO_SHARED static inline void obsignatio_chunk(const unsigned int *key, unsigned int mode,
                                                      const ObsignatioSource *source, unsigned long long offset,
                                                      unsigned int count, unsigned long long chunk,
                                                      ObsignatioNode *node)
{
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        node->chaining[word] = key[word];
    }
    const unsigned int blocks = (count == 0u) ? 1u : ((count + OBSIGNATIO_BLOCK_BYTES - 1u) / OBSIGNATIO_BLOCK_BYTES);
    for (unsigned int block = 0u; block < blocks; block += 1u)
    {
        const unsigned int start = block * OBSIGNATIO_BLOCK_BYTES;
        const unsigned int take = ((count - start) < OBSIGNATIO_BLOCK_BYTES) ? (count - start) : OBSIGNATIO_BLOCK_BYTES;
        obsignatio_block_load(source, offset + start, take, node->block);
        node->counter = chunk;
        node->block_bytes = take;
        node->flags = mode | ((block == 0u) ? OBSIGNATIO_CHUNK_START : 0u) |
                      (((block + 1u) == blocks) ? OBSIGNATIO_CHUNK_END : 0u);
        if ((block + 1u) < blocks)
        {
            unsigned int out[OBSIGNATIO_BLOCK_WORDS];
            obsignatio_compress(node->chaining, node->block, node->counter, node->block_bytes, node->flags, out);
            for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
            {
                node->chaining[word] = out[word];
            }
        }
    }
}

OBSIGNATIO_SHARED static inline void obsignatio_parent(const unsigned int *key, unsigned int mode,
                                                       const unsigned int *left, const unsigned int *right,
                                                       ObsignatioNode *node)
{
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        node->chaining[word] = key[word];
        node->block[word] = left[word];
        node->block[word + OBSIGNATIO_CHAINING_WORDS] = right[word];
    }
    node->counter = 0ull;
    node->block_bytes = OBSIGNATIO_BLOCK_BYTES;
    node->flags = mode | OBSIGNATIO_PARENT;
}

OBSIGNATIO_SHARED static inline void obsignatio_chaining(const ObsignatioNode *node, unsigned int *chaining)
{
    unsigned int out[OBSIGNATIO_BLOCK_WORDS];
    obsignatio_compress(node->chaining, node->block, node->counter, node->block_bytes, node->flags, out);
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        chaining[word] = out[word];
    }
}

OBSIGNATIO_SHARED static inline void obsignatio_root(const ObsignatioNode *node, unsigned char *out,
                                                     unsigned long long out_bytes)
{
    for (unsigned long long start = 0ull; start < out_bytes; start += OBSIGNATIO_BLOCK_BYTES)
    {
        unsigned int words[OBSIGNATIO_BLOCK_WORDS];
        obsignatio_compress(node->chaining, node->block, start / OBSIGNATIO_BLOCK_BYTES, node->block_bytes,
                            node->flags | OBSIGNATIO_ROOT, words);
        const unsigned long long remain = out_bytes - start;
        // the take is at most one block's 64 bytes. It fits an unsigned int
        const unsigned int take = (remain < OBSIGNATIO_BLOCK_BYTES) ? (unsigned int)remain : OBSIGNATIO_BLOCK_BYTES;
        for (unsigned int byte = 0u; byte < take; byte += 1u)
        {
            // a word shifted down to its low byte keeps only that byte
            out[start + byte] = (unsigned char)(words[byte / 4u] >> (8u * (byte % 4u)));
        }
    }
}

OBSIGNATIO_SHARED static inline void obsignatio_digest(const unsigned int *key, unsigned int mode,
                                                       const ObsignatioSource *source, unsigned char *out,
                                                       unsigned long long out_bytes)
{
    const unsigned long long chunks =
        (source->count == 0ull) ? 1ull : ((source->count + OBSIGNATIO_CHUNK_BYTES - 1ull) >> OBSIGNATIO_CHUNK_SHIFT);
    unsigned int stack[OBSIGNATIO_DEPTH][OBSIGNATIO_CHAINING_WORDS];
    unsigned int depth = 0u;
    ObsignatioNode node;
    for (unsigned long long chunk = 0ull; chunk < chunks; chunk += 1ull)
    {
        const unsigned long long start = chunk << OBSIGNATIO_CHUNK_SHIFT;
        const unsigned long long remain = source->count - start;
        // the take is at most one chunk's 1024 bytes. It fits an unsigned int
        const unsigned int take = (remain < OBSIGNATIO_CHUNK_BYTES) ? (unsigned int)remain : OBSIGNATIO_CHUNK_BYTES;
        obsignatio_chunk(key, mode, source, start, take, chunk, &node);
        if ((chunk + 1ull) == chunks)
        {
            break;
        }
        unsigned int chaining[OBSIGNATIO_CHAINING_WORDS];
        obsignatio_chaining(&node, chaining);
        for (unsigned long long total = chunk + 1ull; (total & 1ull) == 0ull; total >>= 1u)
        {
            depth -= 1u;
            ObsignatioNode parent;
            obsignatio_parent(key, mode, stack[depth], chaining, &parent);
            obsignatio_chaining(&parent, chaining);
        }
        for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
        {
            stack[depth][word] = chaining[word];
        }
        depth += 1u;
    }
    while (depth > 0u)
    {
        depth -= 1u;
        unsigned int chaining[OBSIGNATIO_CHAINING_WORDS];
        obsignatio_chaining(&node, chaining);
        obsignatio_parent(key, mode, stack[depth], chaining, &node);
    }
    obsignatio_root(&node, out, out_bytes);
}

int obsignatio_mode_valid(unsigned int mode, const unsigned char *key);

ObsignatioKey obsignatio_key_load(const unsigned char *key);

extern "C" long obsignatio_signum(const ObsignatioSignumRequest *request);
#if (defined(__CUDACC__))

__global__ void obsignatio_chunk_kernel(const unsigned char *bytes, unsigned long long messages,
                                        unsigned long long length, unsigned long long stride, unsigned long long chunks,
                                        ObsignatioKey key, unsigned int mode, unsigned int *chaining,
                                        unsigned char *signa);
#endif

#endif
