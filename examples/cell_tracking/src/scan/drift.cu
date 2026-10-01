// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "drift.h"

#include <cuda_runtime.h>

#include <string.h>

#define DRIFT_THREADS 256u

#define DRIFT_WARP 32u

#define DRIFT_SIGMA_MAX 0xFFFFull

typedef struct
{
    unsigned long long *words;
    unsigned long long *positives;
    size_t word_capacity;
} DriftResident;

static DriftResident s_drift_resident;

// one thread a voxel; each warp's ballot is 32 bits of the set, which on a little-endian device are the low or high
// half of its 64-bit word. Every thread of the warp votes, a thread past the frame voting no
__global__ static void drift_pack_kernel(const unsigned int *residual, unsigned int voxels, unsigned int limbs,
                                         unsigned int *halves, unsigned long long *positives)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    unsigned int positive = 0u;
    if (voxel < voxels)
    {
        const unsigned int *const here = &residual[(size_t)voxel * limbs];
        unsigned int any = 0u;
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            any |= here[limb];
        }
        positive = (unsigned int)(((here[limbs - 1u] >> 31u) == 0u) && (any != 0u));
    }
    const unsigned int ballot = __ballot_sync(0xFFFFFFFFu, positive != 0u);
    if (((threadIdx.x % DRIFT_WARP) == 0u) && (voxel < voxels))
    {
        halves[voxel / DRIFT_WARP] = ballot;
        // a count of 32 bits at most widens to unsigned long long exactly
        atomicAdd(positives, (unsigned long long)__popc(ballot));
    }
}

static int drift_reserve(size_t words)
{
    DriftResident *const resident = &s_drift_resident;
    int ok = (resident->positives != NULL) ||
             (cudaMalloc((void **)&resident->positives, sizeof(unsigned long long)) == cudaSuccess);
    if ((ok != 0) && (words > resident->word_capacity))
    {
        cudaFree(resident->words);
        resident->words = NULL;
        ok = (cudaMalloc((void **)&resident->words, words * sizeof(unsigned long long)) == cudaSuccess);
        resident->word_capacity = (ok != 0) ? words : 0u;
    }
    return ok;
}

extern "C" long drift_positive(const DriftPositiveRequest *request)
{
    if ((request == NULL) || (request->device_residual == NULL) || (request->positive == NULL) ||
        (request->depth == 0u) || (request->height == 0u) || (request->width == 0u) || (request->limbs == 0u))
    {
        return DRIFT_ERROR;
    }
    const unsigned long long plane = (unsigned long long)request->height * request->width;
    if ((plane > 0x7FFFFFFFull) || ((unsigned long long)request->depth > (0x7FFFFFFFull / plane)))
    {
        return DRIFT_ERROR;
    }
    // the voxels are below 2^31, checked above. They narrow to unsigned int exactly
    const unsigned int voxels = (unsigned int)((unsigned long long)request->depth * plane);
    const size_t words = (size_t)DRIFT_WORDS(voxels);
    DriftResident *const resident = &s_drift_resident;
    int ok = drift_reserve(words) &&
             (cudaMemset(resident->words, 0, words * sizeof(unsigned long long)) == cudaSuccess) &&
             (cudaMemset(resident->positives, 0, sizeof(unsigned long long)) == cudaSuccess);
    const unsigned int blocks = (voxels + DRIFT_THREADS - 1u) / DRIFT_THREADS;
    unsigned long long positives = 0ull;
    if (ok != 0)
    {
        drift_pack_kernel<<<blocks, DRIFT_THREADS>>>(request->device_residual, voxels, request->limbs,
                                                     (unsigned int *)resident->words, resident->positives);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(request->positive, resident->words, words * sizeof(unsigned long long),
                         cudaMemcpyDeviceToHost) == cudaSuccess) &&
             (cudaMemcpy(&positives, resident->positives, sizeof(positives), cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    // the positives are at most the voxels, below 2^31. They narrow to long exactly
    return (ok != 0) ? (long)positives : DRIFT_ERROR;
}

extern "C" int drift_weights(const unsigned long long voxel_pm[ENGINE_AXES], unsigned int weights[ENGINE_AXES])
{
    int ok = (voxel_pm != NULL) && (weights != NULL);
    unsigned long long common = 0ull;
    for (unsigned int axis = 0u; ok && (axis < ENGINE_AXES); axis += 1u)
    {
        ok = (voxel_pm[axis] != 0ull);
        unsigned long long one = common;
        unsigned long long other = voxel_pm[axis];
        while (other != 0ull)
        {
            const unsigned long long rest = one % other;
            one = other;
            other = rest;
        }
        common = one;
    }
    unsigned int squared[ENGINE_AXES];
    for (unsigned int axis = 0u; ok && (axis < ENGINE_AXES); axis += 1u)
    {
        const unsigned long long sigma = voxel_pm[axis] / common;
        ok = (sigma <= DRIFT_SIGMA_MAX);
        // a sigma below 2^16 squares below 2^32
        squared[axis] = ok ? (unsigned int)(sigma * sigma) : 0u;
    }
    if (ok)
    {
        memcpy(weights, squared, sizeof(squared));
    }
    return ok;
}
