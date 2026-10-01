// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_select.cu: admission, gather, count and scatter
#include "max_tree_device_internal.h"

__global__ static void max_tree_select_kernel(const unsigned int *residual, unsigned int voxels, unsigned int *admits)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int *const limbs = &residual[(size_t)voxel * ENGINE_RESIDUAL_LIMBS];
    const unsigned int negative = (limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) & 1u;
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        any |= limbs[limb];
    }
    admits[voxel] = (unsigned int)((negative == 0u) && (any != 0u));
}

__global__ static void max_tree_gather_kernel(const unsigned int *admits, const unsigned int *offsets,
                                              unsigned int voxels, unsigned int *order)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (admits[voxel] != 0u)
    {
        order[offsets[voxel]] = voxel;
    }
}

__global__ static void max_tree_count_kernel(const unsigned int *residual, const unsigned int *order,
                                             unsigned int selected_count, unsigned int at, unsigned int *counts)
{
    __shared__ unsigned int mine[MAX_TREE_BUCKETS];
    for (unsigned int bucket = threadIdx.x; bucket < MAX_TREE_BUCKETS; bucket += blockDim.x)
    {
        mine[bucket] = 0u;
    }
    __syncthreads();
    const unsigned int first = blockIdx.x * blockDim.x;
    const unsigned int slot = first + threadIdx.x;
    if (slot < selected_count)
    {
        const unsigned int voxel = order[slot];
        const unsigned int limb = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + (at / 4u)];
        const unsigned int byte = (~(limb >> ((at % 4u) * 8u))) & 0xFFu;
        atomicAdd(&mine[byte], 1u);
    }
    __syncthreads();
    for (unsigned int bucket = threadIdx.x; bucket < MAX_TREE_BUCKETS; bucket += blockDim.x)
    {
        counts[((size_t)blockIdx.x * MAX_TREE_BUCKETS) + bucket] = mine[bucket];
    }
}

__global__ static void max_tree_scatter_kernel(const unsigned int *residual, const unsigned int *order,
                                               unsigned int selected_count, unsigned int at, const unsigned int *places,
                                               unsigned int *sorted)
{
    const unsigned int block = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int first = block * MAX_TREE_BLOCK;
    if (first >= selected_count)
    {
        return;
    }
    unsigned int running[MAX_TREE_BUCKETS];
    for (unsigned int bucket = 0u; bucket < MAX_TREE_BUCKETS; bucket += 1u)
    {
        running[bucket] = places[((size_t)block * MAX_TREE_BUCKETS) + bucket];
    }
    const unsigned int end = ((first + MAX_TREE_BLOCK) < selected_count) ? (first + MAX_TREE_BLOCK) : selected_count;
    for (unsigned int slot = first; slot < end; slot += 1u)
    {
        const unsigned int voxel = order[slot];
        const unsigned int limb = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + (at / 4u)];
        const unsigned int byte = (~(limb >> ((at % 4u) * 8u))) & 0xFFu;
        sorted[running[byte]] = voxel;
        running[byte] += 1u;
    }
}

extern "C" int max_tree_order_agrees(const unsigned int *residual, unsigned int depth, unsigned int height,
                                     unsigned int width, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    MaxTree host;
    const long admitted = max_tree_build(residual, depth, height, width, &host);
    if (MAX_TREE_CHECK(admitted >= 0L, residual, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return 0;
    }
    const size_t voxels = (size_t)depth * height * width;
    const unsigned int selected_count = host.admitted;
    unsigned int *device_residual = NULL;
    unsigned int *device_admits = NULL;
    unsigned int *device_offsets = NULL;
    unsigned int *device_order = NULL;
    unsigned int *device_sorted = NULL;
    unsigned int *device_counts = NULL;
    unsigned int *device_places = NULL;
    const unsigned int blocks = (unsigned int)((selected_count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    const unsigned int spread = (unsigned int)((voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    int ok =
        MAX_TREE_STATUS_CHECK(
            cudaMalloc((void **)&device_residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
            &device_residual, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_admits, voxels * sizeof(unsigned int)), &device_admits,
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_offsets, voxels * sizeof(unsigned int)), &device_offsets,
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_order, ((size_t)selected_count + 1u) * sizeof(unsigned int)),
                              &device_order, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_sorted, ((size_t)selected_count + 1u) * sizeof(unsigned int)),
                              &device_sorted, error) &&
        MAX_TREE_STATUS_CHECK(
            cudaMalloc((void **)&device_counts, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int)),
            &device_counts, error) &&
        MAX_TREE_STATUS_CHECK(
            cudaMalloc((void **)&device_places, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int)),
            &device_places, error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(device_residual, residual,
                                                voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int),
                                                cudaMemcpyHostToDevice),
                                     device_residual, error);
    if (ok != 0)
    {
        max_tree_select_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, (unsigned int)voxels, device_admits);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_admits, error);
    }
    unsigned int *const admits = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const offsets = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    ok = ok && MAX_TREE_CHECK(admits != NULL, &admits, error, ENGINE_ERROR_RESOURCE) &&
         MAX_TREE_CHECK(offsets != NULL, &offsets, error, ENGINE_ERROR_RESOURCE);
    ok = ok &&
         MAX_TREE_STATUS_CHECK(cudaMemcpy(admits, device_admits, voxels * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                               admits, error);
    unsigned int running = 0u;
    for (size_t voxel = 0u; (ok != 0) && (voxel < voxels); voxel += 1u)
    {
        offsets[voxel] = running;
        running += admits[voxel];
    }
    ok = ok && MAX_TREE_CHECK(running == selected_count, admits, error, ENGINE_ERROR_LOGIC);
    ok = ok && MAX_TREE_STATUS_CHECK(
                   cudaMemcpy(device_offsets, offsets, voxels * sizeof(unsigned int), cudaMemcpyHostToDevice),
                   device_offsets, error);
    if (ok != 0)
    {
        max_tree_gather_kernel<<<spread, MAX_TREE_BLOCK>>>(device_admits, device_offsets, (unsigned int)voxels,
                                                           device_order);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_order, error);
    }
    unsigned int *const counts = (unsigned int *)malloc((size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int));
    ok = ok && MAX_TREE_CHECK(counts != NULL, &counts, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int at = 0u; (ok != 0) && (at < MAX_TREE_KEY_BYTES); at += 1u)
    {
        max_tree_count_kernel<<<blocks, MAX_TREE_BLOCK>>>(device_residual, device_order, selected_count, at,
                                                          device_counts);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_counts, error);
        ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(counts, device_counts,
                                                    (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
                                                    cudaMemcpyDeviceToHost),
                                         counts, error);
        unsigned int place = 0u;
        for (unsigned int bucket = 0u; (ok != 0) && (bucket < MAX_TREE_BUCKETS); bucket += 1u)
        {
            for (unsigned int block = 0u; block < blocks; block += 1u)
            {
                const size_t slot = ((size_t)block * MAX_TREE_BUCKETS) + bucket;
                const unsigned int many = counts[slot];
                counts[slot] = place;
                place += many;
            }
        }
        ok = ok && MAX_TREE_CHECK(place == selected_count, counts, error, ENGINE_ERROR_LOGIC);
        ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(device_places, counts,
                                                    (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
                                                    cudaMemcpyHostToDevice),
                                         device_places, error);
        if (ok != 0)
        {
            const unsigned int walkers = (unsigned int)((blocks + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
            max_tree_scatter_kernel<<<walkers, MAX_TREE_BLOCK>>>(device_residual, device_order, selected_count, at,
                                                                 device_places, device_sorted);
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_sorted, error);
        }
        unsigned int *const swap = device_order;
        device_order = device_sorted;
        device_sorted = swap;
    }
    unsigned int *const theirs = (unsigned int *)malloc(((size_t)selected_count + 1u) * sizeof(unsigned int));
    ok = ok && MAX_TREE_CHECK(theirs != NULL, &theirs, error, ENGINE_ERROR_RESOURCE);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(theirs, device_order, (size_t)selected_count * sizeof(unsigned int),
                                                cudaMemcpyDeviceToHost),
                                     theirs, error);
    int agrees = ok;
    for (unsigned int at = 0u; (agrees != 0) && (at < selected_count); at += 1u)
    {
        agrees = MAX_TREE_CHECK(theirs[at] == host.order[at], &theirs[at], error, ENGINE_ERROR_LOGIC);
    }
    free(admits);
    free(offsets);
    free(counts);
    free(theirs);
    cudaFree(device_residual);
    cudaFree(device_admits);
    cudaFree(device_offsets);
    cudaFree(device_order);
    cudaFree(device_sorted);
    cudaFree(device_counts);
    cudaFree(device_places);
    max_tree_release(&host);
    return agrees;
}
