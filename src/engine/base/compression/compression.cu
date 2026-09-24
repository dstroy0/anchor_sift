// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "compression.h"

#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#include <vector>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define COMPRESSION_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_COMPRESSION, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define COMPRESSION_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_COMPRESSION, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define COMPRESSION_THREADS 256u

#define COMPRESSION_BLOCK 64ull

#define COMPRESSION_CHUNK_BLOCKS 64ull

#define COMPRESSION_CHUNK (COMPRESSION_BLOCK * COMPRESSION_CHUNK_BLOCKS)

#define COMPRESSION_K_BITS 5u

#define COMPRESSION_ESCAPE 24u

__device__ static unsigned int compression_block_k(const unsigned int *values, unsigned long long take,
                                                   unsigned long long *bits)
{
    unsigned long long sum = 0ull;
    for (unsigned long long at = 0ull; at < take; at += 1ull)
    {
        sum += values[at];
    }
    unsigned int guess = 0u;
    while ((guess < 32u) && (((sum / take) >> guess) != 0ull))
    {
        guess += 1u;
    }
    const unsigned int low = (guess > 2u) ? (guess - 2u) : 0u;
    const unsigned int high = ((guess + 1u) < 31u) ? (guess + 1u) : 31u;
    unsigned long long best = ~0ull;
    unsigned int chosen = low;
    for (unsigned int k = low; k <= high; k += 1u)
    {
        unsigned long long cost = COMPRESSION_K_BITS;
        for (unsigned long long at = 0ull; at < take; at += 1ull)
        {
            const unsigned int quotient = values[at] >> k;
            cost += (quotient < COMPRESSION_ESCAPE) ? ((unsigned long long)quotient + 1ull + k) : (COMPRESSION_ESCAPE + 32ull);
        }
        if (cost < best)
        {
            best = cost;
            chosen = k;
        }
    }
    *bits = best;
    return chosen;
}

__global__ static void compression_zigzag_kernel(const int *from, unsigned long long count, unsigned int *to)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        const int value = from[index];
        to[index] = (value >= 0) ? (2u * (unsigned int)value) : ((2u * (unsigned int)(-value)) - 1u);
    }
}

__global__ static void compression_measure_kernel(const unsigned int *values, unsigned long long count,
                                                  unsigned long long chunks, unsigned long long *chunk_bits)
{
    const unsigned long long chunk = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= chunks)
    {
        return;
    }
    unsigned long long total = 0ull;
    for (unsigned long long start = chunk * COMPRESSION_CHUNK;
         (start < count) && (start < ((chunk + 1ull) * COMPRESSION_CHUNK)); start += COMPRESSION_BLOCK)
    {
        const unsigned long long take = ((count - start) < COMPRESSION_BLOCK) ? (count - start) : COMPRESSION_BLOCK;
        unsigned long long bits = 0ull;
        (void)compression_block_k(&values[start], take, &bits);
        total += bits;
    }
    chunk_bits[chunk] = total;
}

__device__ static void compression_put(unsigned int *stream, unsigned long long at, unsigned int field, unsigned int width)
{
    if (width == 0u)
    {
        return;
    }
    const unsigned int shift = (unsigned int)(at % 32ull);
    atomicOr(&stream[at / 32ull], field << shift);
    if ((shift + width) > 32u)
    {
        atomicOr(&stream[(at / 32ull) + 1ull], field >> (32u - shift));
    }
}

__global__ static void compression_write_kernel(const unsigned int *values, unsigned long long count,
                                                unsigned long long chunks, const unsigned long long *offsets,
                                                unsigned int *stream)
{
    const unsigned long long chunk = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= chunks)
    {
        return;
    }
    unsigned long long at = offsets[chunk];
    for (unsigned long long start = chunk * COMPRESSION_CHUNK;
         (start < count) && (start < ((chunk + 1ull) * COMPRESSION_CHUNK)); start += COMPRESSION_BLOCK)
    {
        const unsigned long long take = ((count - start) < COMPRESSION_BLOCK) ? (count - start) : COMPRESSION_BLOCK;
        unsigned long long bits = 0ull;
        const unsigned int k = compression_block_k(&values[start], take, &bits);
        compression_put(stream, at, k, COMPRESSION_K_BITS);
        at += COMPRESSION_K_BITS;
        for (unsigned long long index = 0ull; index < take; index += 1ull)
        {
            const unsigned int value = values[start + index];
            const unsigned int quotient = value >> k;
            if (quotient < COMPRESSION_ESCAPE)
            {
                compression_put(stream, at, (1u << quotient) - 1u, quotient);
                at += (unsigned long long)quotient + 1ull;
                compression_put(stream, at, value & ((k == 0u) ? 0u : (0xFFFFFFFFu >> (32u - k))), k);
                at += k;
            }
            else
            {
                compression_put(stream, at, (1u << COMPRESSION_ESCAPE) - 1u, COMPRESSION_ESCAPE);
                at += COMPRESSION_ESCAPE;
                compression_put(stream, at, value, 32u);
                at += 32ull;
            }
        }
    }
}

__device__ static unsigned int compression_get(const unsigned int *stream, unsigned long long at, unsigned int width)
{
    if (width == 0u)
    {
        return 0u;
    }
    const unsigned int shift = (unsigned int)(at % 32ull);
    const unsigned long long pair = (unsigned long long)stream[at / 32ull]
                                  | ((unsigned long long)stream[(at / 32ull) + 1ull] << 32u);
    return (unsigned int)((pair >> shift) & ((width == 32u) ? 0xFFFFFFFFull : ((1ull << width) - 1ull)));
}

__global__ static void compression_read_kernel(const unsigned int *stream, const unsigned long long *offsets,
                                               unsigned long long count, unsigned long long chunks, int *to)
{
    const unsigned long long chunk = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= chunks)
    {
        return;
    }
    unsigned long long at = offsets[chunk];
    for (unsigned long long start = chunk * COMPRESSION_CHUNK;
         (start < count) && (start < ((chunk + 1ull) * COMPRESSION_CHUNK)); start += COMPRESSION_BLOCK)
    {
        const unsigned long long take = ((count - start) < COMPRESSION_BLOCK) ? (count - start) : COMPRESSION_BLOCK;
        const unsigned int k = compression_get(stream, at, COMPRESSION_K_BITS);
        at += COMPRESSION_K_BITS;
        for (unsigned long long index = 0ull; index < take; index += 1ull)
        {
            const unsigned int window = compression_get(stream, at, COMPRESSION_ESCAPE);
            const unsigned int quotient = (window == ((1u << COMPRESSION_ESCAPE) - 1u))
                                        ? COMPRESSION_ESCAPE : (unsigned int)(__ffs(~window) - 1);
            unsigned int value = 0u;
            if (quotient < COMPRESSION_ESCAPE)
            {
                at += (unsigned long long)quotient + 1ull;
                value = (quotient << k) | compression_get(stream, at, k);
                at += k;
            }
            else
            {
                at += COMPRESSION_ESCAPE;
                value = compression_get(stream, at, 32u);
                at += 32ull;
            }
            to[start + index] = ((value & 1u) == 0u) ? (int)(value >> 1u) : -(int)((value + 1u) >> 1u);
        }
    }
}

static unsigned int compression_blocks(unsigned long long count)
{
    const unsigned long long needed = (count + COMPRESSION_THREADS - 1ull) / COMPRESSION_THREADS;
    return (unsigned int)((needed < 65536ull) ? ((needed == 0ull) ? 1ull : needed) : 65536ull);
}

struct CompressionHeld
{
    unsigned long long *chunk_bits;
    unsigned long long *chunk_offsets;
    size_t chunk_room;
    unsigned int *stream;
    size_t stream_room;
    void *scan;
    size_t scan_bytes;
    std::vector<unsigned long long> host_offsets;
    std::vector<unsigned int> host_stream;
};

static CompressionHeld s_compression_held;

static int compression_hold_chunks(size_t chunks, EngineError *error)
{
    CompressionHeld *const held = &s_compression_held;
    if (chunks <= held->chunk_room)
    {
        return 1;
    }
    cudaFree(held->chunk_bits);
    cudaFree(held->chunk_offsets);
    cudaFree(held->scan);
    held->chunk_bits = NULL;
    held->chunk_offsets = NULL;
    held->scan = NULL;
    held->chunk_room = 0u;
    held->scan_bytes = 0u;
    const int ok = COMPRESSION_TOOK(cudaMalloc((void **)&held->chunk_bits, chunks * sizeof(unsigned long long)),
                                    &held->chunk_bits, error)
                && COMPRESSION_TOOK(cudaMalloc((void **)&held->chunk_offsets, chunks * sizeof(unsigned long long)),
                                    &held->chunk_offsets, error)
                && COMPRESSION_TOOK(cub::DeviceScan::ExclusiveSum(NULL, held->scan_bytes, held->chunk_bits,
                                                                  held->chunk_offsets, (int)chunks),
                                    &held->scan_bytes, error)
                && COMPRESSION_TOOK(cudaMalloc(&held->scan, held->scan_bytes), &held->scan, error);
    held->chunk_room = (ok != 0) ? chunks : 0u;
    return ok;
}

static int compression_hold_stream(size_t limbs, EngineError *error)
{
    CompressionHeld *const held = &s_compression_held;
    if ((limbs + 1u) <= held->stream_room)
    {
        return 1;
    }
    cudaFree(held->stream);
    held->stream = NULL;
    held->stream_room = 0u;
    const int ok = COMPRESSION_TOOK(cudaMalloc((void **)&held->stream, (limbs + 1u) * sizeof(unsigned int)),
                                    &held->stream, error);
    held->stream_room = (ok != 0) ? (limbs + 1u) : 0u;
    return ok;
}

extern "C" unsigned long long compression_chunks(unsigned long long count)
{
    const unsigned long long chunks = (count + COMPRESSION_CHUNK - 1ull) / COMPRESSION_CHUNK;
    return ((count != 0ull) && (chunks < 0x7FFFFFFFull)) ? chunks : 0ull;
}

extern "C" long compression_encode(const CompressionEncodeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return COMPRESSION_REFUSED;
    }
    EngineError *const error = request->error;
    if (!COMPRESSION_HELD((request->device_coefficients != NULL) && (request->device_scratch != NULL)
                              && (request->chunks != NULL) && (request->bits != NULL) && (request->offsets != NULL)
                              && (request->stream != NULL),
                          request, error, ENGINE_ERROR_REQUEST))
    {
        return COMPRESSION_REFUSED;
    }
    CompressionHeld *const held = &s_compression_held;
    const unsigned long long count = request->count;
    const unsigned long long chunks = compression_chunks(count);
    if (!COMPRESSION_HELD(chunks != 0ull, &request->count, error, ENGINE_ERROR_REQUEST)
        || (compression_hold_chunks((size_t)chunks, error) == 0))
    {
        return COMPRESSION_REFUSED;
    }
    unsigned int *const naturals = request->device_scratch;
    compression_zigzag_kernel<<<compression_blocks(count), COMPRESSION_THREADS>>>(request->device_coefficients, count,
                                                                                naturals);
    const unsigned int chunk_blocks = (unsigned int)((chunks + COMPRESSION_THREADS - 1ull) / COMPRESSION_THREADS);
    compression_measure_kernel<<<chunk_blocks, COMPRESSION_THREADS>>>(naturals, count, chunks, held->chunk_bits);
    size_t bytes = held->scan_bytes;
    int ok = COMPRESSION_TOOK(cudaGetLastError(), naturals, error)
          && COMPRESSION_TOOK(cub::DeviceScan::ExclusiveSum(held->scan, bytes, held->chunk_bits, held->chunk_offsets,
                                                            (int)chunks),
                              held->chunk_offsets, error);
    unsigned long long last_offset = 0ull;
    unsigned long long last_bits = 0ull;
    ok = ok
      && COMPRESSION_TOOK(cudaMemcpy(&last_offset, &held->chunk_offsets[chunks - 1ull], sizeof(unsigned long long),
                                     cudaMemcpyDeviceToHost),
                          &last_offset, error)
      && COMPRESSION_TOOK(cudaMemcpy(&last_bits, &held->chunk_bits[chunks - 1ull], sizeof(unsigned long long),
                                     cudaMemcpyDeviceToHost),
                          &last_bits, error);
    const unsigned long long bits = last_offset + last_bits;
    const size_t limbs = (size_t)((bits + 31ull) / 32ull);
    ok = ok && compression_hold_stream(limbs, error)
      && COMPRESSION_TOOK(cudaMemset(held->stream, 0, (limbs + 1u) * sizeof(unsigned int)), held->stream, error);
    if (ok != 0)
    {
        compression_write_kernel<<<chunk_blocks, COMPRESSION_THREADS>>>(naturals, count, chunks, held->chunk_offsets,
                                                                       held->stream);
        ok = COMPRESSION_TOOK(cudaGetLastError(), held->stream, error);
    }
    if (ok != 0)
    {
        held->host_offsets.resize((size_t)chunks);
        held->host_stream.resize(limbs + 1u);
        ok = COMPRESSION_TOOK(cudaMemcpy(held->host_offsets.data(), held->chunk_offsets,
                                         (size_t)chunks * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                              held->host_offsets.data(), error)
          && COMPRESSION_TOOK(cudaMemcpy(held->host_stream.data(), held->stream, limbs * sizeof(unsigned int),
                                         cudaMemcpyDeviceToHost),
                              held->host_stream.data(), error);
    }
    if (ok == 0)
    {
        return COMPRESSION_REFUSED;
    }
    *request->chunks = chunks;
    *request->bits = bits;
    *request->offsets = held->host_offsets.data();
    *request->stream = held->host_stream.data();
    return 0L;
}

extern "C" long compression_decode(const CompressionDecodeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return COMPRESSION_REFUSED;
    }
    EngineError *const error = request->error;
    if (!COMPRESSION_HELD((request->offsets != NULL) && (request->stream != NULL)
                              && (request->device_coefficients != NULL),
                          request, error, ENGINE_ERROR_REQUEST))
    {
        return COMPRESSION_REFUSED;
    }
    CompressionHeld *const held = &s_compression_held;
    const unsigned long long chunks = compression_chunks(request->count);
    const size_t limbs = (size_t)((request->bits + 31ull) / 32ull);
    if (!COMPRESSION_HELD(chunks != 0ull, &request->count, error, ENGINE_ERROR_REQUEST)
        || !COMPRESSION_HELD(request->chunks == chunks, &request->chunks, error, ENGINE_ERROR_LOGIC)
        || (compression_hold_chunks((size_t)chunks, error) == 0) || (compression_hold_stream(limbs, error) == 0))
    {
        return COMPRESSION_REFUSED;
    }
    for (unsigned long long chunk = 0ull; chunk < chunks; chunk += 1ull)
    {
        if (!COMPRESSION_HELD((request->offsets[chunk] <= request->bits)
                                  && ((chunk == 0ull) || (request->offsets[chunk] >= request->offsets[chunk - 1ull])),
                              &request->offsets[chunk], error, ENGINE_ERROR_LOGIC))
        {
            return COMPRESSION_REFUSED;
        }
    }
    int ok = COMPRESSION_TOOK(cudaMemset(held->stream, 0, (limbs + 1u) * sizeof(unsigned int)), held->stream, error)
          && COMPRESSION_TOOK(cudaMemcpy(held->stream, request->stream, limbs * sizeof(unsigned int),
                                         cudaMemcpyHostToDevice),
                              held->stream, error)
          && COMPRESSION_TOOK(cudaMemcpy(held->chunk_offsets, request->offsets, (size_t)chunks * sizeof(unsigned long long),
                                         cudaMemcpyHostToDevice),
                              held->chunk_offsets, error);
    if (ok != 0)
    {
        const unsigned int chunk_blocks = (unsigned int)((chunks + COMPRESSION_THREADS - 1ull) / COMPRESSION_THREADS);
        compression_read_kernel<<<chunk_blocks, COMPRESSION_THREADS>>>(held->stream, held->chunk_offsets, request->count,
                                                                      chunks, request->device_coefficients);
        ok = COMPRESSION_TOOK(cudaGetLastError(), request->device_coefficients, error);
    }
    return (ok != 0) ? 0L : COMPRESSION_REFUSED;
}
