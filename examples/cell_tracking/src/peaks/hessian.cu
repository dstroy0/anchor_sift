// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "hessian.h"

#include <cuda_runtime.h>

#include <string.h>

#define HESSIAN_THREADS 256u

#define HESSIAN_ALL_ONES 0xFFFFFFFFu

typedef struct
{
    unsigned int *voxels;
    unsigned int *faces;
    unsigned int *differences;
    size_t point_capacity;
    size_t difference_capacity;
} HessianResident;

static HessianResident s_hessian_resident;

// adds a term of `limbs` limbs into a sum of limbs + 1, the term widened by its sign; `flip` is 0 to add the term and
// all ones to take it away, since sum - term is sum + ~term + 1
__device__ static void hessian_add(unsigned int *sum, const unsigned int *term, unsigned int limbs, unsigned int flip)
{
    const unsigned int extension = ((term[limbs - 1u] >> 31u) != 0u) ? HESSIAN_ALL_ONES : 0u;
    unsigned int carry = flip & 1u;
    for (unsigned int limb = 0u; limb <= limbs; limb += 1u)
    {
        const unsigned int word = ((limb < limbs) ? term[limb] : extension) ^ flip;
        const unsigned long long sum_word = (unsigned long long)sum[limb] + word + carry;
        // the low half of the sum is the limb
        sum[limb] = (unsigned int)(sum_word & 0xFFFFFFFFull);
        // the high half is the carry, 0 or 1
        carry = (unsigned int)(sum_word >> 32u);
    }
}

// one thread a point's entry; the entry's first thread writes the point's faces. Four terms of a residual below
// 2^(32 limbs - 1) in size sum below 2^(32 limbs + 1). Limbs + 1 limbs hold every difference exactly
__global__ static void hessian_kernel(const unsigned int *residual, unsigned int depth, unsigned int height,
                                      unsigned int width, unsigned int limbs, unsigned int count,
                                      const unsigned int *voxels, unsigned int *faces, unsigned int *differences)
{
    const unsigned long long thread = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (thread >= ((unsigned long long)count * HESSIAN_ENTRIES))
    {
        return;
    }
    // the thread is below count * 6. Its point is below count and its entry below 6, each fitting unsigned int
    const unsigned int point = (unsigned int)(thread / HESSIAN_ENTRIES);
    const unsigned int entry = (unsigned int)(thread % HESSIAN_ENTRIES);
    const unsigned int plane = height * width;
    const unsigned int voxel = voxels[point];
    const unsigned int place[3] = {voxel / plane, (voxel % plane) / width, voxel % width};
    const unsigned int extent[3] = {depth, height, width};
    const unsigned int stride[3] = {plane, width, 1u};
    unsigned int face_bits = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        face_bits |= ((place[axis] == 0u) ? 1u : 0u) << (2u * axis);
        face_bits |= (((place[axis] + 1u) == extent[axis]) ? 2u : 0u) << (2u * axis);
    }
    if (entry == 0u)
    {
        faces[point] = face_bits;
    }
    // the pure entries read one axis each; the mixed ones read the pairs (z, y), (z, x) and (y, x)
    const unsigned int first = (entry < 3u) ? entry : ((entry == 5u) ? 1u : 0u);
    const unsigned int second = (entry < 3u) ? entry : ((entry == 3u) ? 1u : 2u);
    const unsigned int wide = limbs + 1u;
    unsigned int *const sum = &differences[thread * wide];
    for (unsigned int limb = 0u; limb < wide; limb += 1u)
    {
        sum[limb] = 0u;
    }
    const int defined = (((face_bits >> (2u * first)) & 3u) == 0u) && (((face_bits >> (2u * second)) & 3u) == 0u);
    if (defined == 0)
    {
        return;
    }
    // an axis with neither face cutting has a neighbor on both sides. Every index read is inside the frame
    if (entry < 3u)
    {
        const unsigned int step = stride[first];
        hessian_add(sum, &residual[(size_t)(voxel + step) * limbs], limbs, 0u);
        hessian_add(sum, &residual[(size_t)(voxel - step) * limbs], limbs, 0u);
        hessian_add(sum, &residual[(size_t)voxel * limbs], limbs, HESSIAN_ALL_ONES);
        hessian_add(sum, &residual[(size_t)voxel * limbs], limbs, HESSIAN_ALL_ONES);
    }
    else
    {
        const unsigned int one = stride[first];
        const unsigned int other = stride[second];
        hessian_add(sum, &residual[(size_t)((voxel + one) + other) * limbs], limbs, 0u);
        hessian_add(sum, &residual[(size_t)((voxel + one) - other) * limbs], limbs, HESSIAN_ALL_ONES);
        hessian_add(sum, &residual[(size_t)((voxel - one) + other) * limbs], limbs, HESSIAN_ALL_ONES);
        hessian_add(sum, &residual[(size_t)((voxel - one) - other) * limbs], limbs, 0u);
    }
}

static int hessian_reserve(size_t count, size_t words)
{
    HessianResident *const resident = &s_hessian_resident;
    int ok = 1;
    if (count > resident->point_capacity)
    {
        cudaFree(resident->voxels);
        cudaFree(resident->faces);
        resident->voxels = NULL;
        resident->faces = NULL;
        ok = (cudaMalloc((void **)&resident->voxels, count * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&resident->faces, count * sizeof(unsigned int)) == cudaSuccess);
        resident->point_capacity = (ok != 0) ? count : 0u;
    }
    if ((ok != 0) && (words > resident->difference_capacity))
    {
        cudaFree(resident->differences);
        resident->differences = NULL;
        ok = (cudaMalloc((void **)&resident->differences, words * sizeof(unsigned int)) == cudaSuccess);
        resident->difference_capacity = (ok != 0) ? words : 0u;
    }
    return ok;
}

extern "C" long hessian_find(const HessianRequest *request)
{
    if ((request == NULL) || (request->device_residual == NULL) || (request->depth == 0u) || (request->height == 0u) ||
        (request->width == 0u) || (request->limbs == 0u) || (request->limbs == HESSIAN_ALL_ONES))
    {
        return HESSIAN_ERROR;
    }
    const unsigned long long plane = (unsigned long long)request->height * request->width;
    const int sized = (plane <= 0x7FFFFFFFull) && ((unsigned long long)request->depth <= (0x7FFFFFFFull / plane));
    const unsigned long long voxels = sized ? ((unsigned long long)request->depth * plane) : 0ull;
    const unsigned long long wide = (unsigned long long)request->limbs + 1ull;
    const unsigned long long count = request->count;
    const int placed =
        (count == 0ull) || ((request->voxels != NULL) && (request->faces != NULL) && (request->differences != NULL));
    if ((sized == 0) || (count > voxels) || (placed == 0) ||
        ((count != 0ull) && (wide > ((0xFFFFFFFFFFFFFFFFull / sizeof(unsigned int)) / (HESSIAN_ENTRIES * count)))))
    {
        return HESSIAN_ERROR;
    }
    for (unsigned long long point = 0ull; point < count; point += 1ull)
    {
        if (request->voxels[point] >= voxels)
        {
            return HESSIAN_ERROR;
        }
    }
    if (count == 0ull)
    {
        return 0L;
    }
    const size_t words = (size_t)(count * HESSIAN_ENTRIES * wide);
    HessianResident *const resident = &s_hessian_resident;
    int ok = hessian_reserve((size_t)count, words) &&
             (cudaMemcpy(resident->voxels, request->voxels, (size_t)count * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess);
    const unsigned long long threads = count * HESSIAN_ENTRIES;
    // the count is below 2^31. Its threads are below 6 * 2^31 and its blocks below 2^26, fitting unsigned int
    const unsigned int blocks = (unsigned int)((threads + HESSIAN_THREADS - 1ull) / HESSIAN_THREADS);
    if (ok != 0)
    {
        // the count is at most the frame's voxels, below 2^31. It narrows to unsigned int exactly
        hessian_kernel<<<blocks, HESSIAN_THREADS>>>(request->device_residual, request->depth, request->height,
                                                    request->width, request->limbs, (unsigned int)count,
                                                    resident->voxels, resident->faces, resident->differences);
        ok = (cudaGetLastError() == cudaSuccess) &&
             (cudaMemcpy(request->faces, resident->faces, (size_t)count * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess) &&
             (cudaMemcpy(request->differences, resident->differences, words * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    // a count that is at most the frame's voxels is below 2^31. It narrows to long exactly
    return (ok != 0) ? (long)count : HESSIAN_ERROR;
}
