/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_raster_cuda.cu
 * @brief The device arm of the direct renderer. Same configuration, same bytes as the host arm.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * ONE THREAD PER ALIGNMENT. Rendering is the search, so the parallel decomposition is the search's:
 * every alignment is independent until it reduces into a pixel. Nothing is tiled and nothing is
 * staged in shared memory, because each thread reads a handful of bytes and writes one value.
 *
 * WHY THIS AGREES WITH THE HOST BYTE FOR BYTE. Three properties hold it together. The value a thread
 * computes is integer arithmetic on the same inputs, so no rounding can differ. The cell a thread
 * targets comes from integer division and a permutation, neither of which depends on which thread
 * runs. And the reduction is a minimum or a maximum, both associative and commutative, so the
 * scheduler may interleave the atomics in any order and reach the same result. A reduction selecting
 * by arrival would have made the device answer depend on scheduling and could not have been graded
 * against the host at all.
 *
 * @note The transform and the channel are reimplemented here rather than linked, because the host
 *       arm is built by MinGW through CMake and this is built by nvcc driving MSVC. The two cannot
 *       link, which is the same split maint/engine/build_gpu_arm.sh already documents for the exact
 *       arm. bench_raster grading the two rasters byte for byte is what keeps the copies honest.
 * @warning A copy is a defect waiting to happen, and this one is only safe because a grader compares
 *          the outputs on every configuration. Delete that grader and this file becomes a second
 *          renderer nobody checks.
 */

#include <cuda_runtime.h>
#include <cstdio>

extern "C" {
#include "anchor_raster.h"
}

/** @brief Death level step in the gray ramp. Matches ANCHOR_RASTER_STEP in anchor_raster.c. */
#define RASTER_STEP 40u

/** @brief Brightest value a death level may reach. Matches ANCHOR_RASTER_CEILING. */
#define RASTER_CEILING 250u

/** @brief Probe as the kernel reads it, laid out to match AnchorRasterProbe exactly. */
struct DeviceProbe
{
    unsigned long long origin;
    unsigned long long step;
    unsigned long long length;
};

/** @brief Configuration as the kernel reads it. Only the fields a thread needs are carried. */
struct DeviceConfig
{
    unsigned long long width;
    unsigned long long height;
    int layout;
    int channel;
    int reduce;
    unsigned int gain;
};

/** @brief The level at which one alignment died, matching raster_death_level on the host. */
__device__ static unsigned long long device_death_level(const unsigned char *corpus,
                                                        const unsigned char *needle,
                                                        unsigned long long needle_len,
                                                        const DeviceProbe *probes,
                                                        unsigned long long probe_count,
                                                        unsigned long long at, int *matched)
{
    *matched = 0;

    for (unsigned long long slot = 0u; slot < probe_count; slot += 1u)
    {
        for (unsigned long long step = 0u; step < probes[slot].length; step += 1u)
        {
            const unsigned long long offset = probes[slot].origin + (step * probes[slot].step);
            if (corpus[at + offset] != needle[offset])
            {
                return slot;
            }
        }
    }
    for (unsigned long long step = 0u; step < needle_len; step += 1u)
    {
        if (corpus[at + step] != needle[step])
        {
            return probe_count;
        }
    }
    *matched = 1;
    return probe_count;
}

/** @brief Gray value for a death level, matching raster_value on the host. */
__device__ static unsigned char device_value(unsigned long long level, int matched)
{
    if (matched != 0)
    {
        return (unsigned char)ANCHOR_RASTER_MATCH;
    }
    const unsigned long long scaled = 1u + (level * RASTER_STEP);
    return (unsigned char)((scaled > RASTER_CEILING) ? RASTER_CEILING : scaled);
}

/** @brief Cell an alignment lands on, matching anchor_raster_cell on the host. */
__device__ static unsigned long long device_cell(const DeviceConfig *config,
                                                 unsigned long long at,
                                                 unsigned long long alignments)
{
    const unsigned long long cells = config->width * config->height;
    const unsigned long long linear = (at * cells) / alignments;
    const unsigned long long row = linear / config->width;
    const unsigned long long column = linear % config->width;

    if (config->layout == ANCHOR_LAYOUT_SERPENTINE)
    {
        const unsigned long long flipped = ((row % 2u) == 0u)
                                         ? column
                                         : (config->width - 1u - column);
        return (row * config->width) + flipped;
    }
    if (config->layout == ANCHOR_LAYOUT_COLUMNS)
    {
        const unsigned long long turned_row = linear % config->height;
        const unsigned long long turned_column = linear / config->height;
        if (turned_column >= config->width)
        {
            return linear;
        }
        return (turned_row * config->width) + turned_column;
    }
    if (config->layout == ANCHOR_LAYOUT_DIAGONAL)
    {
        const unsigned long long shifted = (column + row) % config->width;
        return (row * config->width) + shifted;
    }
    return linear;
}

/** @brief Value an alignment contributes, matching anchor_raster_sample on the host. */
__device__ static unsigned char device_sample(const DeviceConfig *config,
                                              const unsigned char *corpus,
                                              const unsigned char *needle,
                                              unsigned long long needle_len,
                                              const DeviceProbe *probes,
                                              unsigned long long probe_count,
                                              unsigned long long at,
                                              const unsigned long long *occurrences,
                                              unsigned long long total)
{
    const unsigned int gain = (config->gain == 0u) ? 1u : config->gain;

    if (config->channel == ANCHOR_CHANNEL_BYTE)
    {
        return corpus[at];
    }
    if (config->channel == ANCHOR_CHANNEL_RARITY)
    {
        if (total == 0u)
        {
            return 1u;
        }
        const unsigned long long missing = total - occurrences[corpus[at]];
        return (unsigned char)(1u + ((missing * 254u) / total));
    }

    int matched = 0;
    const unsigned long long level = device_death_level(corpus, needle, needle_len, probes,
                                                        probe_count, at, &matched);
    if (config->channel == ANCHOR_CHANNEL_SURVIVED)
    {
        return (level >= probe_count) ? (unsigned char)ANCHOR_RASTER_MATCH : (unsigned char)1u;
    }
    return device_value(level * (unsigned long long)gain, matched);
}

/**
 * @brief Renders every alignment into the raster, one thread each.
 *
 * @note The atomics run on a 32-bit staging buffer because CUDA has no 8-bit atomicMin. The host
 *       narrows the result afterward, which costs one pass over the cells and keeps the reduction
 *       exact.
 */
__global__ static void render_alignments(unsigned int *staging, DeviceConfig config,
                                         const unsigned char *corpus,
                                         unsigned long long corpus_len,
                                         const unsigned char *needle,
                                         unsigned long long needle_len, const DeviceProbe *probes,
                                         unsigned long long probe_count,
                                         const unsigned long long *occurrences,
                                         unsigned long long total)
{
    const unsigned long long alignments = (corpus_len - needle_len) + 1u;
    const unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (at >= alignments)
    {
        return;
    }

    const unsigned char value = device_sample(&config, corpus, needle, needle_len, probes,
                                              probe_count, at, occurrences, total);
    const unsigned long long cell = device_cell(&config, at, alignments);

    if (config.reduce == ANCHOR_REDUCE_MAX)
    {
        atomicMax(&staging[cell], (unsigned int)value);
    }
    else
    {
        atomicMin(&staging[cell], (unsigned int)value);
    }
}

extern "C" int anchor_raster_device_available(void)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }
    return 1;
}

extern "C" int anchor_raster_device(uint8_t *pixels, const AnchorRasterConfig *config,
                                    const uint8_t *corpus, size_t corpus_len,
                                    const uint8_t *needle, size_t needle_len,
                                    const AnchorRasterProbe *probes, size_t probe_count)
{
    if ((pixels == NULL) || (config == NULL) || (corpus == NULL) || (needle == NULL)
     || (config->width == 0u) || (config->height == 0u) || (needle_len == 0u)
     || (needle_len > corpus_len))
    {
        return 0;
    }
    if ((probes == NULL) && (probe_count != 0u))
    {
        return 0;
    }
    if (anchor_raster_device_available() == 0)
    {
        return 0;
    }

    const size_t cells = config->width * config->height;
    const size_t alignments = (corpus_len - needle_len) + 1u;

    /* The census is built on the host and uploaded. It is one pass over the corpus either way, and
     * building it here would add a second reduction to grade against the host's. */
    unsigned long long occurrences[256];
    for (size_t symbol = 0u; symbol < 256u; symbol += 1u)
    {
        occurrences[symbol] = 0u;
    }
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        occurrences[corpus[at]] += 1u;
    }

    DeviceConfig plan;
    plan.width = config->width;
    plan.height = config->height;
    plan.layout = (int)config->layout;
    plan.channel = (int)config->channel;
    plan.reduce = (int)config->reduce;
    plan.gain = config->gain;

    DeviceProbe staged[16];
    if (probe_count > 16u)
    {
        return 0;
    }
    for (size_t slot = 0u; slot < probe_count; slot += 1u)
    {
        staged[slot].origin = probes[slot].origin;
        staged[slot].step = probes[slot].step;
        staged[slot].length = probes[slot].length;
    }

    unsigned int *device_staging = NULL;
    unsigned char *device_corpus = NULL;
    unsigned char *device_needle = NULL;
    DeviceProbe *device_probes = NULL;
    unsigned long long *device_occurrences = NULL;
    int ok = 1;

    ok = ok && (cudaMalloc((void **)&device_staging, cells * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_corpus, corpus_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_needle, needle_len) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&device_occurrences, sizeof(occurrences)) == cudaSuccess);
    if (probe_count > 0u)
    {
        ok = ok && (cudaMalloc((void **)&device_probes,
                               probe_count * sizeof(DeviceProbe)) == cudaSuccess);
    }

    if (ok != 0)
    {
        /* An empty cell is the identity for whichever reduction runs, so the fill differs by rule.
         * The host marks empty with zero and fills on first arrival; here the staging buffer starts
         * at the identity and the narrowing pass below turns any untouched cell back into zero. */
        const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX) ? 0u : 0xFFFFFFFFu;
        unsigned int *seed = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (seed == NULL)
        {
            ok = 0;
        }
        else
        {
            for (size_t cell = 0u; cell < cells; cell += 1u)
            {
                seed[cell] = identity;
            }
            ok = ok && (cudaMemcpy(device_staging, seed, cells * sizeof(unsigned int),
                                   cudaMemcpyHostToDevice) == cudaSuccess);
            free(seed);
        }
    }

    ok = ok && (cudaMemcpy(device_corpus, corpus, corpus_len,
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(device_needle, needle, needle_len,
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(device_occurrences, occurrences, sizeof(occurrences),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if ((ok != 0) && (probe_count > 0u))
    {
        ok = ok && (cudaMemcpy(device_probes, staged, probe_count * sizeof(DeviceProbe),
                               cudaMemcpyHostToDevice) == cudaSuccess);
    }

    if (ok != 0)
    {
        const unsigned int threads = 256u;
        const unsigned int blocks = (unsigned int)((alignments + threads - 1u) / threads);
        render_alignments<<<blocks, threads>>>(device_staging, plan, device_corpus,
                                               (unsigned long long)corpus_len, device_needle,
                                               (unsigned long long)needle_len, device_probes,
                                               (unsigned long long)probe_count,
                                               device_occurrences,
                                               (unsigned long long)corpus_len);
        ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    }

    if (ok != 0)
    {
        unsigned int *result = (unsigned int *)malloc(cells * sizeof(unsigned int));
        if (result == NULL)
        {
            ok = 0;
        }
        else
        {
            ok = ok && (cudaMemcpy(result, device_staging, cells * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost) == cudaSuccess);
            if (ok != 0)
            {
                const unsigned int identity = (config->reduce == ANCHOR_REDUCE_MAX)
                                            ? 0u
                                            : 0xFFFFFFFFu;
                for (size_t cell = 0u; cell < cells; cell += 1u)
                {
                    pixels[cell] = (result[cell] == identity)
                                 ? (uint8_t)ANCHOR_RASTER_EMPTY
                                 : (uint8_t)result[cell];
                }
            }
            free(result);
        }
    }

    cudaFree(device_staging);
    cudaFree(device_corpus);
    cudaFree(device_needle);
    cudaFree(device_occurrences);
    cudaFree(device_probes);
    return ok;
}
