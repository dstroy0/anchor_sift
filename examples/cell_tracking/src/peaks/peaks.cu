// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "peaks.h"

#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include <string.h>

#define PEAKS_THREADS 256u

typedef struct
{
    unsigned int *flags;
    unsigned int *ranks;
    unsigned int *found;
    unsigned int *levels;
    void *scratch;
    size_t scratch_bytes;
    size_t voxels;
    size_t found_capacity;
    size_t level_capacity;
} PeaksResident;

static PeaksResident s_peaks_resident;

__device__ static int peaks_order(const unsigned int *one, const unsigned int *other, unsigned int limbs)
{
    int order = 0;
    for (unsigned int limb = limbs; (limb > 0u) && (order == 0); limb -= 1u)
    {
        const unsigned int sign = (limb == limbs) ? 0x80000000u : 0u;
        const unsigned int left = one[limb - 1u] ^ sign;
        const unsigned int right = other[limb - 1u] ^ sign;
        order = (left > right) ? 1 : ((left < right) ? -1 : 0);
    }
    return order;
}

__global__ static void peaks_flag_kernel(const unsigned int *residual, unsigned int depth, unsigned int height,
                                         unsigned int width, unsigned int limbs, unsigned int *flags)
{
    const unsigned int plane = height * width;
    const unsigned int voxels = depth * plane;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int *const here = &residual[(size_t)voxel * limbs];
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        any |= here[limb];
    }
    unsigned int peak = (unsigned int)(((here[limbs - 1u] >> 31u) == 0u) && (any != 0u));
    // each coordinate is below its extent, and every extent is below 2^32. Each widens to long long exactly
    const long long place[3] = {(long long)(voxel / plane), (long long)((voxel % plane) / width),
                                (long long)(voxel % width)};
    // the extents are below 2^32. Each widens to long long exactly
    const long long extent[3] = {(long long)depth, (long long)height, (long long)width};
    for (unsigned int step = 0u; (peak != 0u) && (step < 27u); step += 1u)
    {
        // each digit of step is 0, 1 or 2. Each offset is -1, 0 or 1 once taken signed
        const long long offset[3] = {(long long)(step / 9u) - 1ll, (long long)((step / 3u) % 3u) - 1ll,
                                     (long long)(step % 3u) - 1ll};
        const long long beside[3] = {place[0] + offset[0], place[1] + offset[1], place[2] + offset[2]};
        const int inside = (step != 13u) && (beside[0] >= 0ll) && (beside[0] < extent[0]) && (beside[1] >= 0ll) &&
                           (beside[1] < extent[1]) && (beside[2] >= 0ll) && (beside[2] < extent[2]);
        if (inside)
        {
            // an inside neighbor's index is below the volume's voxel count, which is below 2^32
            const unsigned int other = (unsigned int)((((beside[0] * extent[1]) + beside[1]) * extent[2]) + beside[2]);
            const int order = peaks_order(&residual[(size_t)other * limbs], here, limbs);
            peak = (unsigned int)((order < 0) || ((order == 0) && (other > voxel)));
        }
    }
    flags[voxel] = peak;
}

__global__ static void peaks_place_kernel(const unsigned int *residual, const unsigned int *flags,
                                          const unsigned int *ranks, unsigned int voxels, unsigned int limbs,
                                          unsigned int *found, unsigned int *levels)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (flags[voxel] == 0u))
    {
        return;
    }
    const unsigned int at = ranks[voxel];
    found[at] = voxel;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        levels[((size_t)at * limbs) + limb] = residual[((size_t)voxel * limbs) + limb];
    }
}

static void peaks_release_resident(void)
{
    PeaksResident *const resident = &s_peaks_resident;
    cudaFree(resident->flags);
    cudaFree(resident->ranks);
    cudaFree(resident->found);
    cudaFree(resident->levels);
    cudaFree(resident->scratch);
    memset(resident, 0, sizeof(*resident));
}

static int peaks_reserve(size_t voxels)
{
    PeaksResident *const resident = &s_peaks_resident;
    if (voxels <= resident->voxels)
    {
        return 1;
    }
    peaks_release_resident();
    size_t scratch_bytes = 0u;
    // the voxel count is below 2^31, as the caller checks. It narrows to int exactly
    const int items = (int)voxels;
    int ok = (cub::DeviceScan::ExclusiveSum(NULL, scratch_bytes, (const unsigned int *)NULL, (unsigned int *)NULL,
                                            items) == cudaSuccess) &&
             (cudaMalloc((void **)&resident->flags, voxels * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&resident->ranks, voxels * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc(&resident->scratch, scratch_bytes) == cudaSuccess);
    resident->scratch_bytes = scratch_bytes;
    resident->voxels = (ok != 0) ? voxels : 0u;
    if (ok == 0)
    {
        peaks_release_resident();
    }
    return ok;
}

static int peaks_reserve_found(size_t count, size_t level_words)
{
    PeaksResident *const resident = &s_peaks_resident;
    int ok = 1;
    if (count > resident->found_capacity)
    {
        cudaFree(resident->found);
        resident->found = NULL;
        ok = (cudaMalloc((void **)&resident->found, count * sizeof(unsigned int)) == cudaSuccess);
        resident->found_capacity = (ok != 0) ? count : 0u;
    }
    if ((ok != 0) && (level_words > resident->level_capacity))
    {
        cudaFree(resident->levels);
        resident->levels = NULL;
        ok = (cudaMalloc((void **)&resident->levels, level_words * sizeof(unsigned int)) == cudaSuccess);
        resident->level_capacity = (ok != 0) ? level_words : 0u;
    }
    return ok;
}

extern "C" long peaks_find(const PeaksRequest *request)
{
    if ((request == NULL) || (request->device_residual == NULL) || (request->depth == 0u) || (request->height == 0u) ||
        (request->width == 0u) || (request->limbs == 0u))
    {
        return PEAKS_ERROR;
    }
    const unsigned long long voxels = (unsigned long long)request->depth * request->height * request->width;
    if ((voxels > 0x7FFFFFFFull) ||
        (((unsigned long long)request->capacity != 0ull) && ((request->voxels == NULL) || (request->levels == NULL))))
    {
        return PEAKS_ERROR;
    }
    PeaksResident *const resident = &s_peaks_resident;
    if (peaks_reserve((size_t)voxels) == 0)
    {
        return PEAKS_ERROR;
    }
    // the voxel count is below 2^31, checked above. It narrows to unsigned int and to int exactly
    const unsigned int count = (unsigned int)voxels;
    const unsigned int blocks = (count + PEAKS_THREADS - 1u) / PEAKS_THREADS;
    peaks_flag_kernel<<<blocks, PEAKS_THREADS>>>(request->device_residual, request->depth, request->height,
                                                 request->width, request->limbs, resident->flags);
    size_t scratch_bytes = resident->scratch_bytes;
    int ok = (cudaGetLastError() == cudaSuccess) &&
             (cub::DeviceScan::ExclusiveSum(resident->scratch, scratch_bytes, resident->flags, resident->ranks,
                                            (int)count) == cudaSuccess);
    unsigned int last_rank = 0u;
    unsigned int last_flag = 0u;
    ok = ok &&
         (cudaMemcpy(&last_rank, &resident->ranks[count - 1u], sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
          cudaSuccess) &&
         (cudaMemcpy(&last_flag, &resident->flags[count - 1u], sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
          cudaSuccess);
    const unsigned int found = last_rank + last_flag;
    if ((ok == 0) || (found > request->capacity))
    {
        return (ok == 0) ? PEAKS_ERROR : (long)found;
    }
    const size_t level_words = (size_t)found * request->limbs;
    ok = (found == 0u) || (peaks_reserve_found((size_t)found, level_words) != 0);
    if (ok && (found != 0u))
    {
        peaks_place_kernel<<<blocks, PEAKS_THREADS>>>(request->device_residual, resident->flags, resident->ranks, count,
                                                      request->limbs, resident->found, resident->levels);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(request->voxels, resident->found, (size_t)found * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess) &&
             (cudaMemcpy(request->levels, resident->levels, level_words * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    return (ok != 0) ? (long)found : PEAKS_ERROR;
}
