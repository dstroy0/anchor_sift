// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "obsignatio.h"

#include <cuda_runtime.h>

#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define OBSIGNATIO_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define OBSIGNATIO_HELD(held_, evacaddr_, error_) \
    engine_error_check((held_), ENGINE_ERROR_REQUEST, ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__, \
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

__host__ __device__ static inline unsigned int obsignatio_rotate(unsigned int word, unsigned int count)
{
    return (word >> count) | (word << (32u - count));
}

__host__ __device__ static inline void obsignatio_mix(unsigned int *state, unsigned int first, unsigned int second,
                                                      unsigned int third, unsigned int fourth,
                                                      unsigned int message_first, unsigned int message_second)
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

__host__ __device__ static inline void obsignatio_round(unsigned int *state, const unsigned int *message)
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

__host__ __device__ static inline void obsignatio_permute(unsigned int *message)
{
    const unsigned int held[OBSIGNATIO_BLOCK_WORDS] = {message[2],  message[6],  message[3],  message[10],
                                                       message[7],  message[0],  message[4],  message[13],
                                                       message[1],  message[11], message[12], message[5],
                                                       message[9],  message[14], message[15], message[8]};
    for (unsigned int word = 0u; word < OBSIGNATIO_BLOCK_WORDS; word += 1u)
    {
        message[word] = held[word];
    }
}

__host__ __device__ static inline void obsignatio_compress(const unsigned int *chaining, const unsigned int *block,
                                                           unsigned long long counter, unsigned int block_bytes,
                                                           unsigned int flags, unsigned int *out)
{
    unsigned int message[OBSIGNATIO_BLOCK_WORDS];
    for (unsigned int word = 0u; word < OBSIGNATIO_BLOCK_WORDS; word += 1u)
    {
        message[word] = block[word];
    }
    // the counter splits into its low and high 32-bit halves, each kept whole
    unsigned int state[OBSIGNATIO_BLOCK_WORDS] = {chaining[0], chaining[1], chaining[2], chaining[3],
                                                  chaining[4], chaining[5], chaining[6], chaining[7],
                                                  OBSIGNATIO_IV0, OBSIGNATIO_IV1, OBSIGNATIO_IV2, OBSIGNATIO_IV3,
                                                  (unsigned int)counter, (unsigned int)(counter >> 32u), block_bytes,
                                                  flags};
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

__host__ __device__ static inline unsigned int obsignatio_source_byte(const ObsignatioSource *source,
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
    // the take is at most one byte's 8 bits, so it fits an unsigned int
    const unsigned int take = (remain < 8ull) ? (unsigned int)remain : 8u;
    const unsigned long long place = source->first_bit + first;
    // a place taken modulo 32 fits an unsigned int
    const unsigned int shift = (unsigned int)(place % 32ull);
    unsigned long long pair = source->limbs[place / 32ull];
    if ((shift + take) > 32u)
    {
        pair |= (unsigned long long)source->limbs[(place / 32ull) + 1ull] << 32u;
    }
    // the value is masked to at most 8 bits, so it fits an unsigned int
    return (unsigned int)((pair >> shift) & ((1ull << take) - 1ull));
}

__host__ __device__ static inline void obsignatio_block_load(const ObsignatioSource *source, unsigned long long start,
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

__host__ __device__ static inline void obsignatio_chunk(const unsigned int *key, unsigned int mode,
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
        node->flags = mode | ((block == 0u) ? OBSIGNATIO_CHUNK_START : 0u)
                    | (((block + 1u) == blocks) ? OBSIGNATIO_CHUNK_END : 0u);
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

__host__ __device__ static inline void obsignatio_parent(const unsigned int *key, unsigned int mode,
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

__host__ __device__ static inline void obsignatio_chaining(const ObsignatioNode *node, unsigned int *chaining)
{
    unsigned int out[OBSIGNATIO_BLOCK_WORDS];
    obsignatio_compress(node->chaining, node->block, node->counter, node->block_bytes, node->flags, out);
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        chaining[word] = out[word];
    }
}

__host__ __device__ static inline void obsignatio_root(const ObsignatioNode *node, unsigned char *out,
                                                       unsigned long long out_bytes)
{
    for (unsigned long long start = 0ull; start < out_bytes; start += OBSIGNATIO_BLOCK_BYTES)
    {
        unsigned int words[OBSIGNATIO_BLOCK_WORDS];
        obsignatio_compress(node->chaining, node->block, start / OBSIGNATIO_BLOCK_BYTES, node->block_bytes,
                            node->flags | OBSIGNATIO_ROOT, words);
        const unsigned long long remain = out_bytes - start;
        // the take is at most one block's 64 bytes, so it fits an unsigned int
        const unsigned int take = (remain < OBSIGNATIO_BLOCK_BYTES) ? (unsigned int)remain : OBSIGNATIO_BLOCK_BYTES;
        for (unsigned int byte = 0u; byte < take; byte += 1u)
        {
            // a word shifted down to its low byte keeps only that byte
            out[start + byte] = (unsigned char)(words[byte / 4u] >> (8u * (byte % 4u)));
        }
    }
}

__host__ __device__ static inline void obsignatio_digest(const unsigned int *key, unsigned int mode,
                                                         const ObsignatioSource *source, unsigned char *out,
                                                         unsigned long long out_bytes)
{
    const unsigned long long chunks = (source->count == 0ull)
                                        ? 1ull
                                        : ((source->count + OBSIGNATIO_CHUNK_BYTES - 1ull) >> OBSIGNATIO_CHUNK_SHIFT);
    unsigned int stack[OBSIGNATIO_DEPTH][OBSIGNATIO_CHAINING_WORDS];
    unsigned int depth = 0u;
    ObsignatioNode node;
    for (unsigned long long chunk = 0ull; chunk < chunks; chunk += 1ull)
    {
        const unsigned long long start = chunk << OBSIGNATIO_CHUNK_SHIFT;
        const unsigned long long remain = source->count - start;
        // the take is at most one chunk's 1024 bytes, so it fits an unsigned int
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

static int obsignatio_mode_held(unsigned int mode, const unsigned char *key)
{
    const int unkeyed = (mode == OBSIGNATIO_MODE_HASH) || (mode == OBSIGNATIO_MODE_CONTEXT);
    const int keyed = (mode == OBSIGNATIO_MODE_KEYED) || (mode == OBSIGNATIO_MODE_MATERIAL);
    return (unkeyed && (key == NULL)) || (keyed && (key != NULL));
}

static ObsignatioKey obsignatio_key_load(const unsigned char *key)
{
    ObsignatioKey loaded;
    if (key == NULL)
    {
        loaded.words[0] = OBSIGNATIO_IV0;
        loaded.words[1] = OBSIGNATIO_IV1;
        loaded.words[2] = OBSIGNATIO_IV2;
        loaded.words[3] = OBSIGNATIO_IV3;
        loaded.words[4] = OBSIGNATIO_IV4;
        loaded.words[5] = OBSIGNATIO_IV5;
        loaded.words[6] = OBSIGNATIO_IV6;
        loaded.words[7] = OBSIGNATIO_IV7;
        return loaded;
    }
    for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
    {
        loaded.words[word] = 0u;
        for (unsigned int byte = 0u; byte < 4u; byte += 1u)
        {
            // an unsigned char widens to unsigned int exactly, so the shift into the top byte stays defined
            loaded.words[word] |= (unsigned int)key[(word * 4u) + byte] << (8u * byte);
        }
    }
    return loaded;
}

extern "C" long obsignatio_signum(const ObsignatioSignumRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_HELD(((request->bytes != NULL) || (request->count == 0ull))
                            && ((request->out != NULL) || (request->out_bytes == 0ull))
                            && obsignatio_mode_held(request->mode, request->key),
                        request, error)
        == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    const ObsignatioSource source = {request->bytes, NULL, 0ull, 0ull, request->count};
    obsignatio_digest(key.words, request->mode, &source, request->out, request->out_bytes);
    return 0L;
}

__global__ static void obsignatio_chunk_kernel(const unsigned char *bytes, unsigned long long messages,
                                               unsigned long long length, unsigned long long stride,
                                               unsigned long long chunks, ObsignatioKey key, unsigned int mode,
                                               unsigned int *chaining, unsigned char *signa)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         index < (messages * chunks); index += jump)
    {
        const unsigned long long message = index / chunks;
        const unsigned long long chunk = index % chunks;
        const unsigned long long start = chunk << OBSIGNATIO_CHUNK_SHIFT;
        const unsigned long long remain = length - start;
        // the take is at most one chunk's 1024 bytes, so it fits an unsigned int
        const unsigned int take = (remain < OBSIGNATIO_CHUNK_BYTES) ? (unsigned int)remain : OBSIGNATIO_CHUNK_BYTES;
        const ObsignatioSource source = {&bytes[message * stride], NULL, 0ull, 0ull, length};
        ObsignatioNode node;
        obsignatio_chunk(key.words, mode, &source, start, take, chunk, &node);
        if (chunks == 1ull)
        {
            obsignatio_root(&node, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
        }
        else
        {
            obsignatio_chaining(&node, &chaining[index * OBSIGNATIO_CHAINING_WORDS]);
        }
    }
}

__global__ static void obsignatio_level_kernel(const unsigned int *from, unsigned long long messages,
                                               unsigned long long width, ObsignatioKey key, unsigned int mode,
                                               unsigned int *to, unsigned char *signa)
{
    const unsigned long long half = (width + 1ull) / 2ull;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         index < (messages * half); index += jump)
    {
        const unsigned long long message = index / half;
        const unsigned long long pair = index % half;
        const unsigned int *const left = &from[((message * width) + (2ull * pair)) * OBSIGNATIO_CHAINING_WORDS];
        unsigned int *const out = &to[index * OBSIGNATIO_CHAINING_WORDS];
        if (((2ull * pair) + 1ull) < width)
        {
            ObsignatioNode node;
            obsignatio_parent(key.words, mode, left, left + OBSIGNATIO_CHAINING_WORDS, &node);
            if (width == 2ull)
            {
                obsignatio_root(&node, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
            }
            else
            {
                obsignatio_chaining(&node, out);
            }
        }
        else
        {
            for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
            {
                out[word] = left[word];
            }
        }
    }
}

static int obsignatio_launch_shape(const void *kernel, unsigned long long work, unsigned int *grid,
                                   unsigned int *threads, EngineError *error)
{
    int least_grid = 0;
    int block = 0;
    if (OBSIGNATIO_TOOK(cudaOccupancyMaxPotentialBlockSize(&least_grid, &block, kernel), kernel, error) == 0)
    {
        return 0;
    }
    // the occupancy query returns positive counts below INT_MAX, so both convert to unsigned exactly
    const unsigned long long wanted = (work + (unsigned long long)block - 1ull) / (unsigned long long)block;
    // the grid is capped at the occupancy grid, which fits an unsigned int
    *grid = (wanted < (unsigned long long)least_grid) ? (unsigned int)wanted : (unsigned int)least_grid;
    // a positive block size below INT_MAX converts to unsigned exactly
    *threads = (unsigned int)block;
    return 1;
}

extern "C" long obsignatio_many(const ObsignatioManyRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_HELD(((request->messages == 0ull)
                         || ((request->device_bytes != NULL) && (request->device_signa != NULL)))
                            && obsignatio_mode_held(request->mode, request->key),
                        request, error)
        == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    if (request->messages == 0ull)
    {
        return 0L;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    const unsigned long long chunks = (request->length == 0ull)
                                        ? 1ull
                                        : ((request->length + OBSIGNATIO_CHUNK_BYTES - 1ull) >> OBSIGNATIO_CHUNK_SHIFT);
    const unsigned long long halves = (chunks + 1ull) / 2ull;
    unsigned int *wide = NULL;
    unsigned int *narrow = NULL;
    const size_t wide_bytes = (size_t)(request->messages * chunks * OBSIGNATIO_CHAINING_WORDS * sizeof(unsigned int));
    const size_t narrow_bytes = (size_t)(request->messages * halves * OBSIGNATIO_CHAINING_WORDS * sizeof(unsigned int));
    unsigned int grid = 0u;
    unsigned int threads = 0u;
    int good = ((chunks == 1ull)
                || (OBSIGNATIO_TOOK(cudaMalloc((void **)&wide, wide_bytes), &wide, error)
                    && OBSIGNATIO_TOOK(cudaMalloc((void **)&narrow, narrow_bytes), &narrow, error)))
            && obsignatio_launch_shape((const void *)obsignatio_chunk_kernel, request->messages * chunks, &grid,
                                       &threads, error);
    if (good)
    {
        obsignatio_chunk_kernel<<<grid, threads>>>(request->device_bytes, request->messages, request->length,
                                                   request->stride, chunks, key, request->mode, wide,
                                                   request->device_signa);
        good = OBSIGNATIO_TOOK(cudaGetLastError(), request->device_bytes, error);
    }
    unsigned int *from = wide;
    unsigned int *to = narrow;
    for (unsigned long long width = chunks; good && (width > 1ull); width = (width + 1ull) / 2ull)
    {
        good = obsignatio_launch_shape((const void *)obsignatio_level_kernel,
                                       request->messages * ((width + 1ull) / 2ull), &grid, &threads, error);
        if (good)
        {
            obsignatio_level_kernel<<<grid, threads>>>(from, request->messages, width, key, request->mode, to,
                                                       request->device_signa);
            good = OBSIGNATIO_TOOK(cudaGetLastError(), from, error);
        }
        unsigned int *const swapped = from;
        from = to;
        to = swapped;
    }
    good = good && OBSIGNATIO_TOOK(cudaDeviceSynchronize(), request->device_signa, error);
    cudaFree(wide);
    cudaFree(narrow);
    return good ? 0L : OBSIGNATIO_REFUSED;
}

__global__ static void obsignatio_bits_check_kernel(const unsigned long long *offsets, unsigned long long messages,
                                                    unsigned long long bits, unsigned int *broken)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long message = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; message < messages;
         message += jump)
    {
        const unsigned long long end = ((message + 1ull) < messages) ? offsets[message + 1ull] : bits;
        if ((offsets[message] > end) || (end > bits))
        {
            atomicOr(broken, 1u);
        }
    }
}

__global__ static void obsignatio_bits_kernel(const unsigned int *limbs, const unsigned long long *offsets,
                                              unsigned long long messages, unsigned long long bits, ObsignatioKey key,
                                              unsigned int mode, unsigned char *signa)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long message = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; message < messages;
         message += jump)
    {
        const unsigned long long end = ((message + 1ull) < messages) ? offsets[message + 1ull] : bits;
        const unsigned long long length = end - offsets[message];
        const ObsignatioSource source = {NULL, limbs, offsets[message], length,
                                         OBSIGNATIO_LENGTH_BYTES + ((length + 7ull) / 8ull)};
        obsignatio_digest(key.words, mode, &source, &signa[message * OBSIGNATIO_SIGNUM_BYTES],
                          OBSIGNATIO_SIGNUM_BYTES);
    }
}

extern "C" long obsignatio_bits(const ObsignatioBitsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_HELD(((request->messages == 0ull)
                         || ((request->device_offsets != NULL) && (request->device_signa != NULL)
                             && ((request->device_limbs != NULL) || (request->bits == 0ull))))
                            && obsignatio_mode_held(request->mode, request->key),
                        request, error)
        == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    if (request->messages == 0ull)
    {
        return 0L;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    unsigned int *device_broken = NULL;
    unsigned int broken = 0u;
    unsigned int grid = 0u;
    unsigned int threads = 0u;
    int good = OBSIGNATIO_TOOK(cudaMalloc((void **)&device_broken, sizeof(unsigned int)), &device_broken, error)
            && OBSIGNATIO_TOOK(cudaMemset(device_broken, 0, sizeof(unsigned int)), device_broken, error)
            && obsignatio_launch_shape((const void *)obsignatio_bits_check_kernel, request->messages, &grid, &threads,
                                       error);
    if (good)
    {
        obsignatio_bits_check_kernel<<<grid, threads>>>(request->device_offsets, request->messages, request->bits,
                                                        device_broken);
        good = OBSIGNATIO_TOOK(cudaGetLastError(), request->device_offsets, error)
            && OBSIGNATIO_TOOK(cudaMemcpy(&broken, device_broken, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                               device_broken, error)
            && OBSIGNATIO_HELD(broken == 0u, request->device_offsets, error)
            && obsignatio_launch_shape((const void *)obsignatio_bits_kernel, request->messages, &grid, &threads, error);
    }
    if (good)
    {
        obsignatio_bits_kernel<<<grid, threads>>>(request->device_limbs, request->device_offsets, request->messages,
                                                  request->bits, key, request->mode, request->device_signa);
        good = OBSIGNATIO_TOOK(cudaGetLastError(), request->device_limbs, error)
            && OBSIGNATIO_TOOK(cudaDeviceSynchronize(), request->device_signa, error);
    }
    cudaFree(device_broken);
    return good ? 0L : OBSIGNATIO_REFUSED;
}

#define OBSIGNATIO_CONTEXT_PREFIX "obsignatio aeterna 2026-09-23 "

extern "C" const char *obsignatio_level_context(ObsignatioLevel level)
{
    switch (level)
    {
        case OBSIGNATIO_LEVEL_ROW:
            return OBSIGNATIO_CONTEXT_PREFIX "row";
        case OBSIGNATIO_LEVEL_PLANE:
            return OBSIGNATIO_CONTEXT_PREFIX "plane";
        case OBSIGNATIO_LEVEL_VOLUME:
            return OBSIGNATIO_CONTEXT_PREFIX "volume";
        case OBSIGNATIO_LEVEL_LANES:
            return OBSIGNATIO_CONTEXT_PREFIX "lanes";
        case OBSIGNATIO_LEVEL_CHUNK:
            return OBSIGNATIO_CONTEXT_PREFIX "chunk";
        case OBSIGNATIO_LEVEL_STREAM:
            return OBSIGNATIO_CONTEXT_PREFIX "stream";
        case OBSIGNATIO_LEVEL_SIDE:
            return OBSIGNATIO_CONTEXT_PREFIX "side";
        case OBSIGNATIO_LEVEL_MEMBERS:
            return OBSIGNATIO_CONTEXT_PREFIX "members";
        case OBSIGNATIO_LEVEL_SAMPLE:
            return OBSIGNATIO_CONTEXT_PREFIX "sample";
        case OBSIGNATIO_LEVEL_SET:
            return OBSIGNATIO_CONTEXT_PREFIX "set";
        case OBSIGNATIO_LEVEL_FILE:
            return OBSIGNATIO_CONTEXT_PREFIX "file";
        case OBSIGNATIO_LEVEL_UNIVERSAL:
            return OBSIGNATIO_CONTEXT_PREFIX "universal";
        case OBSIGNATIO_LEVEL_SIDE_STORED:
            return OBSIGNATIO_CONTEXT_PREFIX "side stored";
        case OBSIGNATIO_LEVEL_SIDE_INFLATED:
            return OBSIGNATIO_CONTEXT_PREFIX "side inflated";
        default:
            return NULL;
    }
}

extern "C" long obsignatio_level_key(ObsignatioLevel level, unsigned char *key, EngineError *error)
{
    if (error == NULL)
    {
        return OBSIGNATIO_REFUSED;
    }
    const char *const context = obsignatio_level_context(level);
    if (OBSIGNATIO_HELD((context != NULL) && (key != NULL), key, error) == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    // the context's chars are hashed as the unsigned bytes they are stored as
    const ObsignatioSignumRequest request = {(const unsigned char *)context, strlen(context), NULL,
                                             OBSIGNATIO_MODE_CONTEXT, key, OBSIGNATIO_KEY_BYTES, error};
    return obsignatio_signum(&request);
}

extern "C" long obsignatio_seal(const ObsignatioSealRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    if ((OBSIGNATIO_HELD(request->signum != NULL, request, request->error) == 0)
        || (obsignatio_level_key(OBSIGNATIO_LEVEL_FILE, key, request->error) != 0L))
    {
        return OBSIGNATIO_REFUSED;
    }
    const ObsignatioSignumRequest signum = {request->bytes, request->count, key, OBSIGNATIO_MODE_KEYED,
                                            request->signum, OBSIGNATIO_SIGNUM_BYTES, request->error};
    return obsignatio_signum(&signum);
}

extern "C" long obsignatio_seal_holds(const ObsignatioSealRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    unsigned char rebuilt[OBSIGNATIO_SIGNUM_BYTES];
    const ObsignatioSealRequest again = {request->bytes, request->count, rebuilt, request->error};
    if ((OBSIGNATIO_HELD(request->signum != NULL, request, request->error) == 0) || (obsignatio_seal(&again) != 0L))
    {
        return OBSIGNATIO_REFUSED;
    }
    return (memcmp(rebuilt, request->signum, OBSIGNATIO_SIGNUM_BYTES) == 0) ? 1L : 0L;
}

extern "C" unsigned long long obsignatio_lanes_nodes(const unsigned long long *extent)
{
    if ((extent == NULL) || (extent[0] == 0ull) || (extent[1] == 0ull) || (extent[2] == 0ull) || (extent[3] == 0ull))
    {
        return 0ull;
    }
    const unsigned long long volumes = extent[0];
    const unsigned long long planes = volumes * extent[1];
    const unsigned long long rows = planes * extent[2];
    return rows + planes + volumes + 1ull;
}

extern "C" long obsignatio_lanes(const ObsignatioLanesRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_REFUSED;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_HELD((request->device_lanes != NULL) && (request->device_nodes != NULL)
                            && (obsignatio_lanes_nodes(request->extent) != 0ull),
                        request, error)
        == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    unsigned char row_key[OBSIGNATIO_KEY_BYTES];
    unsigned char plane_key[OBSIGNATIO_KEY_BYTES];
    unsigned char volume_key[OBSIGNATIO_KEY_BYTES];
    unsigned char lanes_key[OBSIGNATIO_KEY_BYTES];
    const int keyed = (obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, row_key, error) == 0L)
                   && (obsignatio_level_key(OBSIGNATIO_LEVEL_PLANE, plane_key, error) == 0L)
                   && (obsignatio_level_key(OBSIGNATIO_LEVEL_VOLUME, volume_key, error) == 0L)
                   && (obsignatio_level_key(OBSIGNATIO_LEVEL_LANES, lanes_key, error) == 0L);
    if (keyed == 0)
    {
        return OBSIGNATIO_REFUSED;
    }
    const unsigned long long *const extent = request->extent;
    const unsigned long long volumes = extent[0];
    const unsigned long long planes = volumes * extent[1];
    const unsigned long long rows = planes * extent[2];
    const unsigned long long row_bytes = extent[3] * sizeof(unsigned short);
    unsigned char *const row_nodes = request->device_nodes;
    unsigned char *const plane_nodes = &row_nodes[rows * OBSIGNATIO_SIGNUM_BYTES];
    unsigned char *const volume_nodes = &plane_nodes[planes * OBSIGNATIO_SIGNUM_BYTES];
    unsigned char *const lanes_node = &volume_nodes[volumes * OBSIGNATIO_SIGNUM_BYTES];
    // the device is little-endian, so the lanes' bytes are their little-endian u16 form
    const unsigned char *const lane_bytes = (const unsigned char *)request->device_lanes;
    const ObsignatioManyRequest levels[OBSIGNATIO_EXTENT_AXES] = {
        {lane_bytes, rows, row_bytes, row_bytes, row_key, OBSIGNATIO_MODE_KEYED, row_nodes, error},
        {row_nodes, planes, extent[2] * OBSIGNATIO_SIGNUM_BYTES, extent[2] * OBSIGNATIO_SIGNUM_BYTES, plane_key,
         OBSIGNATIO_MODE_KEYED, plane_nodes, error},
        {plane_nodes, volumes, extent[1] * OBSIGNATIO_SIGNUM_BYTES, extent[1] * OBSIGNATIO_SIGNUM_BYTES, volume_key,
         OBSIGNATIO_MODE_KEYED, volume_nodes, error},
        {volume_nodes, 1ull, volumes * OBSIGNATIO_SIGNUM_BYTES, volumes * OBSIGNATIO_SIGNUM_BYTES, lanes_key,
         OBSIGNATIO_MODE_KEYED, lanes_node, error}};
    for (unsigned int level = 0u; level < OBSIGNATIO_EXTENT_AXES; level += 1u)
    {
        if (obsignatio_many(&levels[level]) != 0L)
        {
            return OBSIGNATIO_REFUSED;
        }
    }
    return 0L;
}
