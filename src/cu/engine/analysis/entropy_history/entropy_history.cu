// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "../../../../engine/analysis/entropy_history/entropy_history.h"

#include "crc.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX: the status converts to int exactly
#define ENTROPY_HISTORY_STATUS_CHECK(call_, evacaddr_, error_)                                                         \
    engine_status_check((int)(call_), ENGINE_MODULE_ENTROPY_HISTORY, (unsigned int)__LINE__,                           \
                        (const void *)(evacaddr_), (error_))

#define ENTROPY_HISTORY_CHECK(condition_, evacaddr_, error_, kind_)                                                    \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_ENTROPY_HISTORY, (unsigned int)__LINE__,                   \
                       (const void *)(evacaddr_), (error_))

#define ENTROPY_HISTORY_THREADS 256u

static_assert(ENGINE_HISTORY_WINDOW <= 15u, "entropy_history: a window's count must fit a nibble");
static_assert((ENGINE_HISTORY_BITS * 4u) == 64u, "entropy_history: a window's counts must fill one 64 bit word");

#define ENTROPY_HISTORY_DENSITY_MAX ((unsigned long long)ENGINE_HISTORY_WINDOW * 65535ull)

__global__ static void entropy_history_kernel(const unsigned short *lanes, unsigned long long frames,
                                              unsigned long long voxels, unsigned int windows,
                                              unsigned long long *history, unsigned long long *broken,
                                              unsigned long long *cloud)
{
    __shared__ unsigned long long overlap[ENGINE_HISTORY_WINDOWS_MAX * ENGINE_HISTORY_WINDOWS_MAX];
    for (unsigned int entry = threadIdx.x; entry < (windows * windows); entry += blockDim.x)
    {
        overlap[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long breaks = 0ull;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        unsigned int density[ENGINE_HISTORY_WINDOWS_MAX];
        unsigned int counts[ENGINE_HISTORY_BITS];
        unsigned int totals[ENGINE_HISTORY_BITS];
#pragma unroll
        for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
        {
            counts[bit] = 0u;
            totals[bit] = 0u;
        }
        const unsigned int first = lanes[voxel];
        unsigned int before = first;
        unsigned long long window = 0ull;
        unsigned int in_window = 0u;
        for (unsigned long long frame = 1ull; frame < frames; frame += 1ull)
        {
            const unsigned int now = lanes[(frame * voxels) + voxel];
            const unsigned int flipped = now ^ before;
            before = now;
#pragma unroll
            for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
            {
                counts[bit] += (flipped >> bit) & 1u;
                totals[bit] += (flipped >> bit) & 1u;
            }
            in_window += 1u;
            if ((in_window == ENGINE_HISTORY_WINDOW) || (frame == (frames - 1ull)))
            {
                unsigned long long packed = 0ull;
                unsigned int changed = 0u;
#pragma unroll
                for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
                {
                    packed |= (unsigned long long)counts[bit] << (4u * bit);
                    changed += counts[bit] << bit;
                    counts[bit] = 0u;
                }
                history[(window * voxels) + voxel] = packed;
                density[window] = changed;
                window += 1ull;
                in_window = 0u;
            }
        }
        const unsigned int net = first ^ before;
        unsigned int parity_ok = 1u;
#pragma unroll
        for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
        {
            parity_ok &= (unsigned int)((totals[bit] & 1u) == ((net >> bit) & 1u));
        }
        breaks += (parity_ok != 0u) ? 0ull : 1ull;
        for (unsigned int one = 0u; one < windows; one += 1u)
        {
            for (unsigned int other = one; other < windows; other += 1u)
            {
                atomicAdd(&overlap[(one * windows) + other], (unsigned long long)density[one] * density[other]);
            }
        }
    }
    if (breaks != 0ull)
    {
        atomicAdd(broken, breaks);
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < (windows * windows); entry += blockDim.x)
    {
        if (overlap[entry] != 0ull)
        {
            atomicAdd(&cloud[entry], overlap[entry]);
        }
    }
}

extern "C" long entropy_history_windows(const unsigned long long extent[4], EngineError *error)
{
    if (error == NULL)
    {
        return ENTROPY_HISTORY_ERROR;
    }
    if (!ENTROPY_HISTORY_CHECK(extent != NULL, &extent, error, ENGINE_ERROR_REQUEST))
    {
        return ENTROPY_HISTORY_ERROR;
    }
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    if (!ENTROPY_HISTORY_CHECK(frames >= 2ull, &extent[0], error, ENGINE_ERROR_REQUEST))
    {
        return ENTROPY_HISTORY_ERROR;
    }
    const unsigned long long windows = ((frames - 1ull) + ENGINE_HISTORY_WINDOW - 1ull) / ENGINE_HISTORY_WINDOW;
    const int bounded =
        (windows <= ENGINE_HISTORY_WINDOWS_MAX) &&
        (voxels <= (0xFFFFFFFFFFFFFFFFull / (ENTROPY_HISTORY_DENSITY_MAX * ENTROPY_HISTORY_DENSITY_MAX)));
    return ENTROPY_HISTORY_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST) ? (long)windows : ENTROPY_HISTORY_ERROR;
}

extern "C" long entropy_history_project(const EntropyHistoryProjectRequest *request, unsigned long long *broken)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENTROPY_HISTORY_ERROR;
    }
    EngineError *const error = request->error;
    if (!ENTROPY_HISTORY_CHECK((request->history != NULL) && (request->volume != NULL) && (broken != NULL), request,
                               error, ENGINE_ERROR_REQUEST))
    {
        return ENTROPY_HISTORY_ERROR;
    }
    const long counted = entropy_history_windows(request->extent, error);
    if (counted == ENTROPY_HISTORY_ERROR)
    {
        return ENTROPY_HISTORY_ERROR;
    }
    EngineHistory *const history = request->history;
    const unsigned long long windows = (unsigned long long)counted;
    const unsigned long long frames = request->extent[0];
    const unsigned long long voxels = request->extent[1] * request->extent[2] * request->extent[3];
    const size_t words = (size_t)(windows * voxels);
    const size_t entries = (size_t)(windows * windows);

    unsigned short *device_lanes = NULL;
    unsigned long long *device_history = NULL;
    unsigned long long *device_broken = NULL;
    unsigned long long *device_cloud = NULL;
    *broken = 1ull;
    int ok =
        ENTROPY_HISTORY_STATUS_CHECK(
            cudaMalloc((void **)&device_lanes, (size_t)(frames * voxels) * sizeof(unsigned short)), &device_lanes,
            error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMalloc((void **)&device_history, words * sizeof(unsigned long long)),
                                     &device_history, error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMalloc((void **)&device_broken, sizeof(unsigned long long)), &device_broken,
                                     error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMalloc((void **)&device_cloud, entries * sizeof(unsigned long long)),
                                     &device_cloud, error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMemset(device_broken, 0, sizeof(unsigned long long)), device_broken, error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMemset(device_cloud, 0, entries * sizeof(unsigned long long)), device_cloud,
                                     error) &&
        ENTROPY_HISTORY_STATUS_CHECK(cudaMemcpy(device_lanes, request->volume,
                                                (size_t)(frames * voxels) * sizeof(unsigned short),
                                                cudaMemcpyHostToDevice),
                                     device_lanes, error);
    if (ok != 0)
    {
        const unsigned long long needed = (voxels + ENTROPY_HISTORY_THREADS - 1ull) / ENTROPY_HISTORY_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        entropy_history_kernel<<<blocks, ENTROPY_HISTORY_THREADS>>>(device_lanes, frames, voxels, (unsigned int)windows,
                                                                    device_history, device_broken, device_cloud);
        ok = ENTROPY_HISTORY_STATUS_CHECK(cudaGetLastError(), device_history, error);
    }
    ok = ok &&
         ENTROPY_HISTORY_STATUS_CHECK(
             cudaMemcpy(history->history, device_history, words * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
             history->history, error) &&
         ENTROPY_HISTORY_STATUS_CHECK(
             cudaMemcpy(history->cloud, device_cloud, entries * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
             history->cloud, error) &&
         ENTROPY_HISTORY_STATUS_CHECK(
             cudaMemcpy(broken, device_broken, sizeof(unsigned long long), cudaMemcpyDeviceToHost), broken, error);
    cudaFree(device_lanes);
    cudaFree(device_history);
    cudaFree(device_broken);
    cudaFree(device_cloud);
    if ((ok == 0) || !ENTROPY_HISTORY_CHECK(*broken == 0ull, broken, error, ENGINE_ERROR_LOGIC))
    {
        return ENTROPY_HISTORY_ERROR;
    }
    for (unsigned long long one = 0ull; one < windows; one += 1ull)
    {
        for (unsigned long long other = 0ull; other < one; other += 1ull)
        {
            history->cloud[(size_t)((one * windows) + other)] = history->cloud[(size_t)((other * windows) + one)];
        }
    }
    memcpy(history->extent, request->extent, sizeof(history->extent));
    history->windows = windows;
    history->sample = request->sample;
    history->payload_crc = crc_words(CRC_TABLE, history->history, words);
    history->cloud_crc = crc_words(CRC_TABLE, history->cloud, entries);
    return 0L;
}

static void entropy_history_report_cloud(const EngineHistory *history)
{
    const unsigned long long windows = history->windows;
    printf("    the cloud: each floor's quietest partner, the first floor its nulls are drawn from:\n      floor");
    for (unsigned long long floor = 0ull; floor < windows; floor += 1ull)
    {
        printf(" %2llu", floor);
    }
    printf("\n      quiet");
    for (unsigned long long floor = 0ull; floor < windows; floor += 1ull)
    {
        unsigned long long quietest = (floor == 0ull) ? 1ull : 0ull;
        for (unsigned long long other = 0ull; other < windows; other += 1ull)
        {
            const int better = (other != floor) && (history->cloud[(size_t)((floor * windows) + other)] <
                                                    history->cloud[(size_t)((floor * windows) + quietest)]);
            quietest = better ? other : quietest;
        }
        printf(" %2llu", quietest);
    }
    printf("\n");
}

extern "C" void entropy_history_report(const EngineHistory *history)
{
    const unsigned long long frames = history->extent[0];
    const unsigned long long voxels = history->extent[1] * history->extent[2] * history->extent[3];
    const unsigned long long windows = history->windows;
    printf("    flips per thousand transitions, bit by window:\n      bit");
    for (unsigned long long window = 0ull; window < windows; window += 1ull)
    {
        printf(" %5llu", window);
    }
    printf("\n");
    for (unsigned int bit = ENGINE_HISTORY_BITS; bit > 0u; bit -= 1u)
    {
        printf("      %3u", bit - 1u);
        for (unsigned long long window = 0ull; window < windows; window += 1ull)
        {
            const unsigned long long first = (window * ENGINE_HISTORY_WINDOW) + 1ull;
            const unsigned long long last = ((first + ENGINE_HISTORY_WINDOW - 1ull) < frames)
                                                ? (first + ENGINE_HISTORY_WINDOW - 1ull)
                                                : (frames - 1ull);
            const unsigned long long taken = last - first + 1ull;
            unsigned long long flips = 0ull;
            const unsigned long long *const row = &history->history[(size_t)(window * voxels)];
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                flips += (row[voxel] >> (4u * (bit - 1u))) & 0xFull;
            }
            printf(" %5llu", (1000ull * flips) / (taken * voxels));
        }
        printf("\n");
    }
    entropy_history_report_cloud(history);
}
