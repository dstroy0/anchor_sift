// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "max_tree.h"

#include <cuda_runtime.h>
#include <cub/cub.cuh>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TREE_BLOCK 256u

#define MAX_TREE_TICKS 8u

#define MAX_TREE_JUMPS 2u

#define MAX_TREE_KEY_WORDS ((MAX_TREE_KEY_LIMBS + 1u) / 2u)

#define MAX_TREE_BUCKETS 256u

#define MAX_TREE_KEY_BYTES (ENGINE_RESIDUAL_LIMBS * 4u)

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define MAX_TREE_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define MAX_TREE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

__global__ static void max_tree_admit_kernel(const unsigned int *residual, unsigned int voxels,
                                             unsigned int *admits)
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
                                             unsigned int held, unsigned int at, unsigned int *counts)
{
    __shared__ unsigned int mine[MAX_TREE_BUCKETS];
    for (unsigned int bucket = threadIdx.x; bucket < MAX_TREE_BUCKETS; bucket += blockDim.x)
    {
        mine[bucket] = 0u;
    }
    __syncthreads();
    const unsigned int first = blockIdx.x * blockDim.x;
    const unsigned int slot = first + threadIdx.x;
    if (slot < held)
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
                                               unsigned int held, unsigned int at, const unsigned int *places,
                                               unsigned int *sorted)
{
    const unsigned int block = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int first = block * MAX_TREE_BLOCK;
    if (first >= held)
    {
        return;
    }
    unsigned int running[MAX_TREE_BUCKETS];
    for (unsigned int bucket = 0u; bucket < MAX_TREE_BUCKETS; bucket += 1u)
    {
        running[bucket] = places[((size_t)block * MAX_TREE_BUCKETS) + bucket];
    }
    const unsigned int past = ((first + MAX_TREE_BLOCK) < held) ? (first + MAX_TREE_BLOCK) : held;
    for (unsigned int slot = first; slot < past; slot += 1u)
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
    if (MAX_TREE_HELD(admitted >= 0L, residual, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return 0;
    }
    const size_t voxels = (size_t)depth * height * width;
    const unsigned int held = host.admitted;
    unsigned int *device_residual = NULL;
    unsigned int *device_admits = NULL;
    unsigned int *device_offsets = NULL;
    unsigned int *device_order = NULL;
    unsigned int *device_sorted = NULL;
    unsigned int *device_counts = NULL;
    unsigned int *device_places = NULL;
    const unsigned int blocks = (unsigned int)((held + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    const unsigned int spread = (unsigned int)((voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    int ok = MAX_TREE_TOOK(cudaMalloc((void **)&device_residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                           &device_residual, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_admits, voxels * sizeof(unsigned int)), &device_admits, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_offsets, voxels * sizeof(unsigned int)), &device_offsets, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_order, ((size_t)held + 1u) * sizeof(unsigned int)),
                           &device_order, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_sorted, ((size_t)held + 1u) * sizeof(unsigned int)),
                           &device_sorted, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_counts, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int)),
                           &device_counts, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_places, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int)),
                           &device_places, error);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(device_residual, residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int),
                                        cudaMemcpyHostToDevice),
                             device_residual, error);
    if (ok != 0)
    {
        max_tree_admit_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, (unsigned int)voxels,
                                                          device_admits);
        ok = MAX_TREE_TOOK(cudaGetLastError(), device_admits, error);
    }
    unsigned int *const admits = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const offsets = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    ok = ok && MAX_TREE_HELD(admits != NULL, &admits, error, ENGINE_ERROR_RESOURCE)
            && MAX_TREE_HELD(offsets != NULL, &offsets, error, ENGINE_ERROR_RESOURCE);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(admits, device_admits, voxels * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                             admits, error);
    unsigned int running = 0u;
    for (size_t voxel = 0u; (ok != 0) && (voxel < voxels); voxel += 1u)
    {
        offsets[voxel] = running;
        running += admits[voxel];
    }
    ok = ok && MAX_TREE_HELD(running == held, admits, error, ENGINE_ERROR_LOGIC);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(device_offsets, offsets, voxels * sizeof(unsigned int), cudaMemcpyHostToDevice),
                             device_offsets, error);
    if (ok != 0)
    {
        max_tree_gather_kernel<<<spread, MAX_TREE_BLOCK>>>(device_admits, device_offsets,
                                                           (unsigned int)voxels, device_order);
        ok = MAX_TREE_TOOK(cudaGetLastError(), device_order, error);
    }
    unsigned int *const counts = (unsigned int *)malloc((size_t)blocks * MAX_TREE_BUCKETS
                                                         * sizeof(unsigned int));
    ok = ok && MAX_TREE_HELD(counts != NULL, &counts, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int at = 0u; (ok != 0) && (at < MAX_TREE_KEY_BYTES); at += 1u)
    {
        max_tree_count_kernel<<<blocks, MAX_TREE_BLOCK>>>(device_residual, device_order, held, at,
                                                           device_counts);
        ok = MAX_TREE_TOOK(cudaGetLastError(), device_counts, error);
        ok = ok && MAX_TREE_TOOK(cudaMemcpy(counts, device_counts, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
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
        ok = ok && MAX_TREE_HELD(place == held, counts, error, ENGINE_ERROR_LOGIC);
        ok = ok && MAX_TREE_TOOK(cudaMemcpy(device_places, counts, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
                                            cudaMemcpyHostToDevice),
                                 device_places, error);
        if (ok != 0)
        {
            const unsigned int walkers = (unsigned int)((blocks + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
            max_tree_scatter_kernel<<<walkers, MAX_TREE_BLOCK>>>(device_residual, device_order, held, at,
                                                                  device_places, device_sorted);
            ok = MAX_TREE_TOOK(cudaGetLastError(), device_sorted, error);
        }
        unsigned int *const swap = device_order;
        device_order = device_sorted;
        device_sorted = swap;
    }
    unsigned int *const theirs = (unsigned int *)malloc(((size_t)held + 1u) * sizeof(unsigned int));
    ok = ok && MAX_TREE_HELD(theirs != NULL, &theirs, error, ENGINE_ERROR_RESOURCE);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(theirs, device_order, (size_t)held * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                             theirs, error);
    int agrees = ok;
    for (unsigned int at = 0u; (agrees != 0) && (at < held); at += 1u)
    {
        agrees = MAX_TREE_HELD(theirs[at] == host.order[at], &theirs[at], error, ENGINE_ERROR_LOGIC);
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

__device__ static unsigned int max_tree_admitted(const unsigned int *residual, unsigned int voxel)
{
    const unsigned int *const limbs = &residual[(size_t)voxel * ENGINE_RESIDUAL_LIMBS];
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        any |= limbs[limb];
    }
    return (unsigned int)(((limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) == 0u) && (any != 0u));
}

__device__ static unsigned int max_tree_below(const unsigned int *residual, unsigned int left, unsigned int right)
{
    const unsigned int *const one = &residual[(size_t)left * ENGINE_RESIDUAL_LIMBS];
    const unsigned int *const other = &residual[(size_t)right * ENGINE_RESIDUAL_LIMBS];
    unsigned int decided = 0u;
    unsigned int below = 0u;
    for (unsigned int limb = ENGINE_RESIDUAL_LIMBS; limb > 0u; limb -= 1u)
    {
        const unsigned int differs = (unsigned int)(one[limb - 1u] != other[limb - 1u]) & (decided ^ 1u);
        below |= differs & (unsigned int)(one[limb - 1u] < other[limb - 1u]);
        decided |= differs;
    }
    return below;
}

__device__ static unsigned int max_tree_key_limb(const unsigned int *residual, unsigned int weaker,
                                                 unsigned int name, unsigned int limb)
{
    const unsigned int above = (unsigned int)((limb >= 1u) && (limb <= ENGINE_RESIDUAL_LIMBS));
    const unsigned int value = residual[((size_t)weaker * ENGINE_RESIDUAL_LIMBS) + ((limb - 1u) * above)];
    return (limb == 0u) ? ~name : (value * above);
}

__device__ static unsigned long long max_tree_key_word(const unsigned int *residual, unsigned int weaker,
                                                       unsigned int name, unsigned int word)
{
    const unsigned long long low = max_tree_key_limb(residual, weaker, name, word * 2u);
    const unsigned long long high = max_tree_key_limb(residual, weaker, name, (word * 2u) + 1u);
    return (high << 32u) | low;
}

__device__ static unsigned int max_tree_leads(const unsigned int *residual, unsigned int weaker, unsigned int name,
                                              unsigned int word, const unsigned long long *best)
{
    unsigned int ties = 1u;
    for (unsigned int above = word + 1u; above < MAX_TREE_KEY_WORDS; above += 1u)
    {
        ties &= (unsigned int)(best[above] == max_tree_key_word(residual, weaker, name, above));
    }
    return ties;
}

__global__ static void max_tree_faces_kernel(const unsigned int *residual, unsigned int depth, unsigned int height,
                                             unsigned int width, unsigned char *faces)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int here = max_tree_admitted(residual, voxel);
    unsigned int flags = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        const unsigned int binds = inside[axis] & here & max_tree_admitted(residual, beside);
        const unsigned int far_weaker = max_tree_below(residual, beside, voxel);
        flags |= (binds << axis) | ((binds & far_weaker) << (axis + 3u));
    }
    faces[voxel] = (unsigned char)flags;
}

__global__ static void max_tree_start_kernel(unsigned int voxels, unsigned int *belongs,
                                             unsigned long long *strongest, unsigned char *bound)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = voxel;
    for (unsigned int word = 0u; word < MAX_TREE_KEY_WORDS; word += 1u)
    {
        strongest[((size_t)voxel * MAX_TREE_KEY_WORDS) + word] = 0ull;
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        bound[((size_t)voxel * 3u) + axis] = 0u;
    }
}

__global__ static void max_tree_jump_kernel(unsigned int voxels, unsigned int *belongs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = belongs[belongs[voxel]];
}

__global__ static void max_tree_flatten_kernel(unsigned int voxels, unsigned int *belongs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    unsigned int at = belongs[voxel];
    while (belongs[at] != at)
    {
        at = belongs[at];
    }
    belongs[voxel] = at;
}

__global__ static void max_tree_choose_kernel(const unsigned int *residual, const unsigned char *faces,
                                              const unsigned int *belongs, unsigned int depth, unsigned int height,
                                              unsigned int width, unsigned int word, unsigned long long *strongest)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int flags = faces[voxel];
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int binds = (flags >> axis) & 1u;
        const unsigned int beside = voxel + (stride[axis] * binds);
        const unsigned int other = belongs[beside];
        if (other == one)
        {
            continue;
        }
        const unsigned int weaker = (((flags >> (axis + 3u)) & 1u) != 0u) ? beside : voxel;
        const unsigned int name = (voxel * 3u) + axis;
        const unsigned long long mine = max_tree_key_word(residual, weaker, name, word);
        if (max_tree_leads(residual, weaker, name, word, &strongest[(size_t)one * MAX_TREE_KEY_WORDS]) != 0u)
        {
            atomicMax(&strongest[((size_t)one * MAX_TREE_KEY_WORDS) + word], mine);
        }
        if (max_tree_leads(residual, weaker, name, word, &strongest[(size_t)other * MAX_TREE_KEY_WORDS]) != 0u)
        {
            atomicMax(&strongest[((size_t)other * MAX_TREE_KEY_WORDS) + word], mine);
        }
    }
}

__global__ static void max_tree_partner_kernel(const unsigned long long *strongest, const unsigned int *belongs,
                                               unsigned int depth, unsigned int height, unsigned int width,
                                               unsigned int *partner)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long low = strongest[(size_t)voxel * MAX_TREE_KEY_WORDS];
    const unsigned int chose = (unsigned int)((belongs[voxel] == voxel) && (low != 0ull));
    if (chose == 0u)
    {
        partner[voxel] = voxel;
        return;
    }
    const unsigned int name = ~(unsigned int)(low & 0xFFFFFFFFull);
    const unsigned int lower = name / 3u;
    const unsigned int axis = name % 3u;
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[lower];
    const unsigned int other = belongs[lower + stride[axis]];
    partner[voxel] = (one == voxel) ? other : one;
}

__global__ static void max_tree_hook_kernel(unsigned long long *strongest, const unsigned int *partner,
                                            unsigned int voxels, unsigned int tick, unsigned int *belongs,
                                            unsigned char *bound, unsigned int *moved, unsigned int *last)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long low = strongest[(size_t)voxel * MAX_TREE_KEY_WORDS];
    for (unsigned int word = 0u; word < MAX_TREE_KEY_WORDS; word += 1u)
    {
        strongest[((size_t)voxel * MAX_TREE_KEY_WORDS) + word] = 0ull;
    }
    const unsigned int other = partner[voxel];
    const unsigned int mutual = (unsigned int)(partner[other] == voxel);
    const unsigned int joins = (unsigned int)(other != voxel) & ((mutual ^ 1u) | (unsigned int)(voxel > other));
    if (joins == 0u)
    {
        return;
    }
    belongs[voxel] = other;
    bound[~(unsigned int)(low & 0xFFFFFFFFull)] = 1u;
    moved[0] = 1u;
    last[0] = tick + 1u;
}

__global__ static void max_tree_reaches_kernel(const unsigned int *residual, unsigned int voxels,
                                               unsigned int level, unsigned char *reaches)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    reaches[voxel] = (unsigned char)(max_tree_admitted(residual, voxel)
                                     & (max_tree_below(residual, voxel, level) ^ 1u));
}

__global__ static void max_tree_label_start_kernel(const unsigned char *reaches, unsigned int voxels,
                                                   unsigned int *label)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    label[voxel] = (reaches[voxel] != 0u) ? voxel : MAX_TREE_ABSENT;
}

__global__ static void max_tree_spread_kernel(const unsigned char *reaches, const unsigned char *bound,
                                              unsigned int every, unsigned int depth, unsigned int height,
                                              unsigned int width, unsigned int *label, unsigned int *moved)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int here = reaches[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        const unsigned int crosses = inside[axis] & here & (unsigned int)reaches[beside]
                                   & (every | (unsigned int)bound[((size_t)voxel * 3u) + axis]);
        if (crosses == 0u)
        {
            continue;
        }
        const unsigned int mine = label[voxel];
        const unsigned int theirs = label[beside];
        if (mine == theirs)
        {
            continue;
        }
        const unsigned int was_mine = atomicMin(&label[voxel], theirs);
        const unsigned int was_theirs = atomicMin(&label[beside], mine);
        if ((theirs < was_mine) || (mine < was_theirs))
        {
            moved[0] = 1u;
        }
    }
}

__global__ static void max_tree_label_jump_kernel(unsigned int voxels, unsigned int *label)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int held = label[voxel];
    if (held != MAX_TREE_ABSENT)
    {
        label[voxel] = label[held];
    }
}

__global__ static void max_tree_differ_kernel(const unsigned int *across_every, const unsigned int *across_chosen,
                                              unsigned int voxels, unsigned int *differ)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (across_every[voxel] != across_chosen[voxel])
    {
        atomicAdd(differ, 1u);
    }
}

static int max_tree_label(const unsigned char *reaches, const unsigned char *bound, unsigned int every,
                          unsigned int depth, unsigned int height, unsigned int width, unsigned int *label,
                          unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                          EngineError *error)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int spread = (voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_label_start_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, voxels, label);
    int ok = MAX_TREE_TOOK(cudaGetLastError(), label, error);
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_TOOK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            max_tree_spread_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, bound, every, depth, height, width, label,
                                                               &moved[parity]);
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_label_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(voxels, label);
            }
            ok = MAX_TREE_TOOK(cudaGetLastError(), label, error);
        }
        ok = ok && MAX_TREE_TOOK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                 cudaMemcpyDeviceToHost, 0),
                                 &pinned_moved[parity], error);
        ok = ok && MAX_TREE_TOOK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_TOOK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    return (ok != 0) && MAX_TREE_TOOK(cudaDeviceSynchronize(), label, error);
}

static int max_tree_contract(const unsigned int *residual, unsigned int depth, unsigned int height,
                             unsigned int width, unsigned char *faces, unsigned int *belongs,
                             unsigned long long *strongest, unsigned int *partner, unsigned char *bound,
                             unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                             EngineError *error)
{
    const unsigned int count = depth * height * width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_faces_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, depth, height, width, faces);
    max_tree_start_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs, strongest, bound);
    int ok = MAX_TREE_TOOK(cudaGetLastError(), bound, error);
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_TOOK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs);
            }
            max_tree_flatten_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs);
            for (unsigned int word = MAX_TREE_KEY_WORDS; word > 0u; word -= 1u)
            {
                max_tree_choose_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, faces, belongs, depth, height, width,
                                                                   word - 1u, strongest);
            }
            max_tree_partner_kernel<<<spread, MAX_TREE_BLOCK>>>(strongest, belongs, depth, height, width, partner);
            max_tree_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(strongest, partner, count, (block * MAX_TREE_TICKS) + tick,
                                                             belongs, bound, &moved[parity], &moved[2]);
            ok = MAX_TREE_TOOK(cudaGetLastError(), belongs, error);
        }
        ok = ok && MAX_TREE_TOOK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                 cudaMemcpyDeviceToHost, 0),
                                 &pinned_moved[parity], error);
        ok = ok && MAX_TREE_TOOK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_TOOK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    return (ok != 0) && MAX_TREE_TOOK(cudaDeviceSynchronize(), bound, error);
}

extern "C" long max_tree_bind(const MaxTreeBindRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const size_t voxels = (size_t)request->depth * request->height * request->width;
    const int asked = MAX_TREE_HELD(request->residual != NULL, &request->residual, error, ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD(request->bound != NULL, &request->bound, error, ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD((request->level_count == 0u) || (request->levels != NULL), &request->levels, error,
                                    ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD((voxels != 0u) && ((voxels * 3u) < 0xFFFFFFFFull), &request->depth, error,
                                    ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_REFUSED;
    }
    const unsigned int depth = request->depth;
    const unsigned int height = request->height;
    const unsigned int width = request->width;
    unsigned int *device_residual = NULL;
    unsigned char *device_faces = NULL;
    unsigned int *device_belongs = NULL;
    unsigned long long *device_strongest = NULL;
    unsigned int *device_partner = NULL;
    unsigned char *device_bound = NULL;
    unsigned int *device_moved = NULL;
    unsigned int *pinned_moved = NULL;
    unsigned char *device_reaches = NULL;
    unsigned int *device_across_every = NULL;
    unsigned int *device_across_chosen = NULL;
    unsigned int *device_differ = NULL;
    const unsigned int proved_at = (request->level_count != 0u) ? request->level_count : 1u;
    cudaEvent_t blocks_done[2] = {NULL, NULL};
    int ok = MAX_TREE_TOOK(cudaMalloc((void **)&device_residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                           &device_residual, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_faces, voxels), &device_faces, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_belongs, voxels * sizeof(unsigned int)), &device_belongs, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_strongest, voxels * MAX_TREE_KEY_WORDS * sizeof(unsigned long long)),
                           &device_strongest, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_partner, voxels * sizeof(unsigned int)), &device_partner, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_bound, voxels * 3u), &device_bound, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_moved, 3u * sizeof(unsigned int)), &device_moved, error)
          && MAX_TREE_TOOK(cudaMallocHost((void **)&pinned_moved, 2u * sizeof(unsigned int)), &pinned_moved, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_differ, proved_at * sizeof(unsigned int)), &device_differ, error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&blocks_done[0], cudaEventDisableTiming), &blocks_done[0], error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&blocks_done[1], cudaEventDisableTiming), &blocks_done[1], error);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(device_residual, request->residual,
                                        voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int), cudaMemcpyHostToDevice),
                             device_residual, error);
    ok = ok && MAX_TREE_TOOK(cudaMemset(device_moved, 0, 3u * sizeof(unsigned int)), device_moved, error);
    ok = ok && MAX_TREE_TOOK(cudaMemset(device_differ, 0, proved_at * sizeof(unsigned int)), device_differ, error);
    ok = ok && MAX_TREE_TOOK(cudaDeviceSynchronize(), device_residual, error);
    const unsigned long long began = engine_clock_microseconds();
    const unsigned int count = (unsigned int)voxels;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    ok = ok && max_tree_contract(device_residual, depth, height, width, device_faces, device_belongs,
                                 device_strongest, device_partner, device_bound, device_moved, pinned_moved,
                                 blocks_done, error);
    const unsigned long long bound_at = engine_clock_microseconds();

    if ((ok != 0) && (request->level_count != 0u))
    {
        ok = MAX_TREE_TOOK(cudaMalloc((void **)&device_reaches, voxels), &device_reaches, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_across_every, voxels * sizeof(unsigned int)),
                           &device_across_every, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_across_chosen, voxels * sizeof(unsigned int)),
                           &device_across_chosen, error);
    }
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->level_count); taken += 1u)
    {
        max_tree_reaches_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, count, request->levels[taken],
                                                            device_reaches);
        ok = MAX_TREE_TOOK(cudaGetLastError(), device_reaches, error);
        ok = ok && max_tree_label(device_reaches, device_bound, 1u, depth, height, width, device_across_every,
                                  device_moved, pinned_moved, blocks_done, error);
        ok = ok && max_tree_label(device_reaches, device_bound, 0u, depth, height, width, device_across_chosen,
                                  device_moved, pinned_moved, blocks_done, error);
        if (ok != 0)
        {
            max_tree_differ_kernel<<<spread, MAX_TREE_BLOCK>>>(device_across_every, device_across_chosen, count,
                                                               &device_differ[taken]);
            ok = MAX_TREE_TOOK(cudaGetLastError(), &device_differ[taken], error);
        }
    }
    ok = ok && MAX_TREE_TOOK(cudaDeviceSynchronize(), device_differ, error);
    const unsigned long long proved_at_end = engine_clock_microseconds();

    unsigned int last = 0u;
    unsigned int *const differ = (unsigned int *)malloc(proved_at * sizeof(unsigned int));
    ok = ok && MAX_TREE_HELD(differ != NULL, &differ, error, ENGINE_ERROR_RESOURCE)
            && MAX_TREE_TOOK(cudaMemcpy(request->bound, device_bound, voxels * 3u, cudaMemcpyDeviceToHost),
                             request->bound, error)
            && MAX_TREE_TOOK(cudaMemcpy(&last, &device_moved[2], sizeof(unsigned int), cudaMemcpyDeviceToHost), &last,
                             error)
            && MAX_TREE_TOOK(cudaMemcpy(differ, device_differ, proved_at * sizeof(unsigned int),
                                        cudaMemcpyDeviceToHost),
                             differ, error);
    long chosen = MAX_TREE_REFUSED;
    unsigned int held = 0u;
    if (ok != 0)
    {
        chosen = 0L;
        for (size_t face = 0u; face < (voxels * 3u); face += 1u)
        {
            chosen += (long)(request->bound[face] != 0u);
        }
        for (unsigned int taken = 0u; taken < request->level_count; taken += 1u)
        {
            held += (unsigned int)(differ[taken] == 0u);
        }
        ok = MAX_TREE_HELD(held == request->level_count, differ, error, ENGINE_ERROR_LOGIC);
        chosen = (ok != 0) ? chosen : MAX_TREE_REFUSED;
    }
    if (request->rounds != NULL)
    {
        *request->rounds = last;
    }
    if (request->levels_held != NULL)
    {
        *request->levels_held = held;
    }
    if (request->bound_microseconds != NULL)
    {
        *request->bound_microseconds = bound_at - began;
    }
    if (request->proved_microseconds != NULL)
    {
        *request->proved_microseconds = proved_at_end - bound_at;
    }
    free(differ);
    cudaFree(device_residual);
    cudaFree(device_faces);
    cudaFree(device_belongs);
    cudaFree(device_strongest);
    cudaFree(device_partner);
    cudaFree(device_bound);
    cudaFree(device_moved);
    cudaFreeHost(pinned_moved);
    cudaFree(device_reaches);
    cudaFree(device_across_every);
    cudaFree(device_across_chosen);
    cudaFree(device_differ);
    cudaEventDestroy(blocks_done[0]);
    cudaEventDestroy(blocks_done[1]);
    return chosen;
}

#define MAX_TREE_CHUNK 256u

__global__ static void max_tree_iota_kernel(unsigned int voxels, unsigned int *order)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    order[place] = place;
}

__global__ static void max_tree_code_gather_kernel(const unsigned int *residual, const unsigned int *order,
                                                   unsigned int voxels, unsigned int limb, unsigned int *keys)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    keys[place] = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb] * max_tree_admitted(residual, voxel);
}

__global__ static void max_tree_code_flags_kernel(const unsigned int *residual, const unsigned int *order,
                                                  unsigned int voxels, unsigned int *flags)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    const unsigned int before = order[place - (unsigned int)(place > 0u)];
    const unsigned int one = max_tree_admitted(residual, voxel);
    const unsigned int other = max_tree_admitted(residual, before);
    unsigned int differs = one ^ other;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        differs |= one & other
                 & (unsigned int)(residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb]
                                  != residual[((size_t)before * ENGINE_RESIDUAL_LIMBS) + limb]);
    }
    flags[place] = differs;
}

__global__ static void max_tree_code_scatter_kernel(const unsigned int *residual, const unsigned int *order,
                                                    const unsigned int *ranks, unsigned int voxels, unsigned int *code)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    code[voxel] = (ranks[place] + 1u) * max_tree_admitted(residual, voxel);
}

__global__ static void max_tree_code_faces_kernel(const unsigned int *code, unsigned int depth, unsigned int height,
                                                  unsigned int width, unsigned char *faces)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int mine = code[voxel];
    unsigned int flags = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        const unsigned int theirs = code[beside];
        const unsigned int binds = inside[axis] & (unsigned int)(mine != 0u) & (unsigned int)(theirs != 0u);
        flags |= (binds << axis) | ((binds & (unsigned int)(theirs < mine)) << (axis + 3u));
    }
    faces[voxel] = (unsigned char)flags;
}

__global__ static void max_tree_code_start_kernel(unsigned int voxels, unsigned int *belongs, unsigned long long *best,
                                                  unsigned char *bound)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = voxel;
    best[voxel] = 0ull;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        bound[((size_t)voxel * 3u) + axis] = 0u;
    }
}

__global__ static void max_tree_code_choose_kernel(const unsigned int *code, const unsigned char *faces,
                                                   const unsigned int *belongs, unsigned int depth, unsigned int height,
                                                   unsigned int width, unsigned long long *best)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int flags = faces[voxel];
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int binds = (flags >> axis) & 1u;
        const unsigned int beside = voxel + (stride[axis] * binds);
        const unsigned int other = belongs[beside];
        if (other == one)
        {
            continue;
        }
        const unsigned int weaker = (((flags >> (axis + 3u)) & 1u) != 0u) ? beside : voxel;
        const unsigned int name = (voxel * 3u) + axis;
        const unsigned long long key = ((unsigned long long)code[weaker] << 32u) | (unsigned long long)(~name);
        if (key > best[one])
        {
            atomicMax(&best[one], key);
        }
        if (key > best[other])
        {
            atomicMax(&best[other], key);
        }
    }
}

__global__ static void max_tree_code_partner_kernel(const unsigned long long *best, const unsigned int *belongs,
                                                    unsigned int depth, unsigned int height, unsigned int width,
                                                    unsigned int *partner)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long key = best[voxel];
    if ((belongs[voxel] != voxel) || (key == 0ull))
    {
        partner[voxel] = voxel;
        return;
    }
    const unsigned int name = ~(unsigned int)(key & 0xFFFFFFFFull);
    const unsigned int lower = name / 3u;
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[lower];
    const unsigned int other = belongs[lower + stride[name % 3u]];
    partner[voxel] = (one == voxel) ? other : one;
}

__global__ static void max_tree_code_hook_kernel(unsigned long long *best, const unsigned int *partner,
                                                 unsigned int voxels, unsigned int tick, unsigned int *belongs,
                                                 unsigned char *bound, unsigned int *moved, unsigned int *last)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long key = best[voxel];
    best[voxel] = 0ull;
    const unsigned int other = partner[voxel];
    const unsigned int mutual = (unsigned int)(partner[other] == voxel);
    const unsigned int joins = (unsigned int)(other != voxel) & ((mutual ^ 1u) | (unsigned int)(voxel > other));
    if (joins == 0u)
    {
        return;
    }
    belongs[voxel] = other;
    bound[~(unsigned int)(key & 0xFFFFFFFFull)] = 1u;
    moved[0] = 1u;
    last[0] = tick + 1u;
}

static int max_tree_code_contract(const unsigned int *code, unsigned int depth, unsigned int height,
                                  unsigned int width, unsigned char *faces, unsigned int *belongs,
                                  unsigned long long *best, unsigned int *partner, unsigned char *bound,
                                  unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                                  EngineError *error)
{
    const unsigned int count = depth * height * width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_code_faces_kernel<<<spread, MAX_TREE_BLOCK>>>(code, depth, height, width, faces);
    max_tree_code_start_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs, best, bound);
    int ok = MAX_TREE_TOOK(cudaGetLastError(), bound, error);
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_TOOK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs);
            }
            max_tree_flatten_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs);
            max_tree_code_choose_kernel<<<spread, MAX_TREE_BLOCK>>>(code, faces, belongs, depth, height, width, best);
            max_tree_code_partner_kernel<<<spread, MAX_TREE_BLOCK>>>(best, belongs, depth, height, width, partner);
            max_tree_code_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(best, partner, count, (block * MAX_TREE_TICKS) + tick,
                                                                  belongs, bound, &moved[parity], &moved[2]);
            ok = MAX_TREE_TOOK(cudaGetLastError(), belongs, error);
        }
        ok = ok && MAX_TREE_TOOK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                 cudaMemcpyDeviceToHost, 0),
                                 &pinned_moved[parity], error);
        ok = ok && MAX_TREE_TOOK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_TOOK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    return (ok != 0) && MAX_TREE_TOOK(cudaDeviceSynchronize(), bound, error);
}

__global__ static void max_tree_faces_differ_kernel(const unsigned char *one, const unsigned char *other,
                                                    unsigned int faces, unsigned int *differ)
{
    const unsigned int face = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((face < faces) && (one[face] != other[face]))
    {
        atomicAdd(differ, 1u);
    }
}

__global__ static void max_tree_code_levels_kernel(const unsigned int *code, const unsigned char *bound,
                                                   unsigned int depth, unsigned int height, unsigned int width,
                                                   int *change)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (code[voxel] == 0u))
    {
        return;
    }
    const unsigned int mine = code[voxel];
    atomicAdd(&change[mine], 1);
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if (bound[((size_t)voxel * 3u) + axis] != 0u)
        {
            const unsigned int theirs = code[voxel + stride[axis]];
            atomicSub(&change[(theirs < mine) ? theirs : mine], 1);
        }
    }
}

__global__ static void max_tree_reverse_kernel(const int *change, unsigned int top, int *reversed)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= top)
    {
        return;
    }
    reversed[place] = change[top - place];
}

__global__ static void max_tree_level_pick_kernel(const int *counts, unsigned int top, const int *most,
                                                  unsigned int *level)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((place < top) && (counts[place] == most[0]))
    {
        atomicMin(level, top - place);
    }
}

__global__ static void max_tree_cc_start_kernel(const unsigned int *code, unsigned int voxels, unsigned int level,
                                                unsigned char *reaches, unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int reached = (unsigned int)(code[voxel] >= level);
    reaches[voxel] = (unsigned char)reached;
    parent[voxel] = (reached != 0u) ? voxel : MAX_TREE_ABSENT;
}

__device__ static unsigned int max_tree_cc_root(const unsigned int *parent, unsigned int voxel)
{
    unsigned int at = voxel;
    while (parent[at] != at)
    {
        at = parent[at];
    }
    return at;
}

__global__ static void max_tree_cc_hook_kernel(const unsigned char *reaches, unsigned int depth, unsigned int height,
                                               unsigned int width, unsigned int *parent, unsigned int *moved)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u))
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        if ((inside[axis] & (unsigned int)reaches[beside]) == 0u)
        {
            continue;
        }
        const unsigned int mine = max_tree_cc_root(parent, voxel);
        const unsigned int theirs = max_tree_cc_root(parent, beside);
        if (mine == theirs)
        {
            continue;
        }
        const unsigned int high = (mine > theirs) ? mine : theirs;
        const unsigned int low = (mine > theirs) ? theirs : mine;
        atomicMin(&parent[high], low);
        moved[0] = 1u;
    }
}

__global__ static void max_tree_cc_jump_kernel(const unsigned char *reaches, unsigned int voxels, unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u))
    {
        return;
    }
    parent[voxel] = parent[parent[voxel]];
}

__global__ static void max_tree_cc_flatten_kernel(const unsigned char *reaches, unsigned int voxels,
                                                  unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u))
    {
        return;
    }
    parent[voxel] = max_tree_cc_root(parent, voxel);
}

static int max_tree_cc(const unsigned char *reaches, unsigned int depth, unsigned int height, unsigned int width,
                       unsigned int *parent, unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                       EngineError *error)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int spread = (voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    int ok = 1;
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_TOOK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            max_tree_cc_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, depth, height, width, parent, &moved[parity]);
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_cc_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, voxels, parent);
            }
            ok = MAX_TREE_TOOK(cudaGetLastError(), parent, error);
        }
        ok = ok && MAX_TREE_TOOK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                 cudaMemcpyDeviceToHost, 0),
                                 &pinned_moved[parity], error);
        ok = ok && MAX_TREE_TOOK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_TOOK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    if (ok != 0)
    {
        max_tree_cc_flatten_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, voxels, parent);
        ok = MAX_TREE_TOOK(cudaGetLastError(), parent, error);
    }
    return (ok != 0) && MAX_TREE_TOOK(cudaDeviceSynchronize(), parent, error);
}

__global__ static void max_tree_roots_kernel(const unsigned char *reaches, const unsigned int *label,
                                             unsigned int voxels, unsigned int *roots)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u) || (label[voxel] != voxel))
    {
        return;
    }
    atomicAdd(roots, 1u);
}

__device__ static unsigned int max_tree_peak_of(const unsigned long long *best, unsigned int root)
{
    return ~(unsigned int)(best[root] & 0xFFFFFFFFull);
}

__global__ static void max_tree_peak_kernel(const unsigned int *code, const unsigned char *reaches,
                                            const unsigned int *label, unsigned int voxels, unsigned long long *best)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u))
    {
        return;
    }
    const unsigned long long key = ((unsigned long long)code[voxel] << 32u) | (unsigned long long)(~voxel);
    unsigned long long *const held = &best[label[voxel]];
    if (key > held[0])
    {
        atomicMax(held, key);
    }
}

__global__ static void max_tree_mark_kernel(const unsigned int *residual, const unsigned int *code,
                                            const unsigned char *reaches, const unsigned int *label,
                                            const unsigned long long *best, unsigned int voxels, unsigned int writing,
                                            unsigned int *at_chunk, unsigned int *slot_at, EngineBody *bodies)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int first = chunk * MAX_TREE_CHUNK;
    if (first >= voxels)
    {
        return;
    }
    const unsigned int past = ((voxels - first) < MAX_TREE_CHUNK) ? voxels : (first + MAX_TREE_CHUNK);
    unsigned int slot = (writing != 0u) ? at_chunk[chunk] : 0u;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        const unsigned int inside = (unsigned int)(reaches[voxel] != 0u);
        const unsigned int root = (inside != 0u) ? label[voxel] : voxel;
        const unsigned int peak = inside & (unsigned int)(max_tree_peak_of(best, root) == voxel);
        if ((peak & writing) != 0u)
        {
            EngineBody *const body = &bodies[slot];
            body->peak = voxel;
            body->code = code[voxel];
            body->parent = 0xFFFFFFFFu;
            body->forward = -1;
            body->backward = -1;
            for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
            {
                body->level[limb] = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb];
            }
            slot_at[voxel] = slot;
        }
        slot += peak;
    }
    if (writing == 0u)
    {
        at_chunk[chunk] = slot;
    }
}

__global__ static void max_tree_object_census_kernel(const unsigned char *reaches, const unsigned int *label,
                                                     const unsigned long long *best, const unsigned int *slot_at,
                                                     unsigned int depth, unsigned int height, unsigned int width,
                                                     EngineBody *bodies, unsigned int *labels)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (reaches[voxel] == 0u)
    {
        labels[voxel] = voxel;
        return;
    }
    const unsigned int peak = max_tree_peak_of(best, label[voxel]);
    labels[voxel] = peak;
    EngineBody *const body = &bodies[slot_at[peak]];
    const unsigned int plane = height * width;
    const unsigned long long z = (unsigned long long)(voxel / plane);
    const unsigned long long y = (unsigned long long)((voxel % plane) / width);
    const unsigned long long x = (unsigned long long)(voxel % width);
    atomicAdd(&body->mass, 1u);
    atomicAdd(&body->sums[0], z);
    atomicAdd(&body->sums[1], y);
    atomicAdd(&body->sums[2], x);
    atomicAdd(&body->moments[0], z * z);
    atomicAdd(&body->moments[1], y * y);
    atomicAdd(&body->moments[2], x * x);
    atomicAdd(&body->moments[3], z * y);
    atomicAdd(&body->moments[4], z * x);
    atomicAdd(&body->moments[5], y * x);
    const unsigned int faces = (unsigned int)(z == 0ull) | ((unsigned int)(z + 1ull == depth) << 1u)
                             | ((unsigned int)(y == 0ull) << 2u) | ((unsigned int)(y + 1ull == height) << 3u)
                             | ((unsigned int)(x == 0ull) << 4u) | ((unsigned int)(x + 1ull == width) << 5u);
    if (faces != 0u)
    {
        atomicOr(&body->touches, faces);
    }
}

__global__ static void max_tree_pack_kernel(const unsigned int *residual, unsigned int voxels, unsigned int words,
                                            unsigned long long *packed)
{
    const unsigned int word = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (word >= words)
    {
        return;
    }
    const unsigned int first = word * 64u;
    const unsigned int past = ((voxels - first) < 64u) ? voxels : (first + 64u);
    unsigned long long bits = 0ull;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        bits |= (unsigned long long)max_tree_admitted(residual, voxel) << (voxel - first);
    }
    packed[word] = bits;
}

__global__ static void max_tree_code_values_kernel(const unsigned int *residual, const unsigned int *order,
                                                   const unsigned int *flags, const unsigned int *code,
                                                   unsigned int voxels, unsigned int *values)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    const unsigned int first = (unsigned int)((place == 0u) || (flags[place] != 0u));
    if ((first & max_tree_admitted(residual, voxel)) == 0u)
    {
        return;
    }
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        values[((size_t)code[voxel] * ENGINE_RESIDUAL_LIMBS) + limb]
            = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb];
    }
}

struct MaxTreeHeld
{
    size_t voxels;
    unsigned int *code;
    unsigned int *order[2];
    unsigned int *keys[2];
    void *scratch;
    size_t scratch_bytes;
    unsigned char *faces;
    unsigned int *belongs;
    unsigned long long *best;
    unsigned int *partner;
    unsigned char *bound;
    unsigned char *reaches;
    unsigned int *label;
    int *change;
    int *counts;
    int *most;
    unsigned int *level;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    unsigned int *roots;
    unsigned int *at_chunk;
    unsigned int *host_chunks;
    unsigned long long *packed;
    size_t body_room;
    EngineBody *bodies;
    size_t last_bodies;
    unsigned int top;
    unsigned int cut_level;
    unsigned int last_depth;
    unsigned int last_height;
    unsigned int last_width;
    int keeping;
    unsigned int kept_current;
    unsigned int *kept_code[2];
    unsigned int *kept_values[2];
    unsigned int kept_top[2];
    unsigned int kept_ready[2];
};

static MaxTreeHeld s_max_tree_held;

static void max_tree_release_held(MaxTreeHeld *held)
{
    cudaFree(held->code);
    cudaFree(held->order[0]);
    cudaFree(held->order[1]);
    cudaFree(held->keys[0]);
    cudaFree(held->keys[1]);
    cudaFree(held->scratch);
    cudaFree(held->faces);
    cudaFree(held->belongs);
    cudaFree(held->best);
    cudaFree(held->partner);
    cudaFree(held->bound);
    cudaFree(held->reaches);
    cudaFree(held->label);
    cudaFree(held->change);
    cudaFree(held->counts);
    cudaFree(held->most);
    cudaFree(held->level);
    cudaFree(held->moved);
    cudaFreeHost(held->pinned_moved);
    if (held->blocks_done[0] != NULL)
    {
        cudaEventDestroy(held->blocks_done[0]);
    }
    if (held->blocks_done[1] != NULL)
    {
        cudaEventDestroy(held->blocks_done[1]);
    }
    cudaFree(held->roots);
    cudaFree(held->at_chunk);
    free(held->host_chunks);
    cudaFree(held->packed);
    cudaFree(held->bodies);
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        cudaFree(held->kept_code[slot]);
        cudaFree(held->kept_values[slot]);
    }
    const int keeping = held->keeping;
    memset(held, 0, sizeof(*held));
    held->keeping = keeping;
}

static int max_tree_hold(size_t voxels, EngineError *error)
{
    MaxTreeHeld *const held = &s_max_tree_held;
    if ((held->voxels == voxels) && (voxels != 0u))
    {
        return 1;
    }
    max_tree_release_held(held);
    const size_t chunks = (voxels + MAX_TREE_CHUNK - 1u) / MAX_TREE_CHUNK;
    const size_t words = (voxels + 63u) / 64u;
    const int items = (int)voxels;
    size_t sort_bytes = 0u;
    size_t scan_bytes = 0u;
    size_t most_bytes = 0u;
    cub::DoubleBuffer<unsigned int> no_keys(NULL, NULL);
    cub::DoubleBuffer<unsigned int> no_values(NULL, NULL);
    int ok = MAX_TREE_TOOK(cub::DeviceRadixSort::SortPairs(NULL, sort_bytes, no_keys, no_values, items), &sort_bytes,
                           error)
          && MAX_TREE_TOOK(cub::DeviceScan::InclusiveSum(NULL, scan_bytes, (const unsigned int *)NULL,
                                                         (unsigned int *)NULL, items),
                           &scan_bytes, error)
          && MAX_TREE_TOOK(cub::DeviceReduce::Max(NULL, most_bytes, (const int *)NULL, (int *)NULL, items),
                           &most_bytes, error);
    held->scratch_bytes = (sort_bytes > scan_bytes) ? sort_bytes : scan_bytes;
    held->scratch_bytes = (most_bytes > held->scratch_bytes) ? most_bytes : held->scratch_bytes;
    ok = ok && MAX_TREE_TOOK(cudaMalloc((void **)&held->code, voxels * sizeof(unsigned int)), &held->code, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->order[0], voxels * sizeof(unsigned int)), &held->order[0], error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->order[1], voxels * sizeof(unsigned int)), &held->order[1], error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->keys[0], voxels * sizeof(unsigned int)), &held->keys[0], error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->keys[1], voxels * sizeof(unsigned int)), &held->keys[1], error)
       && MAX_TREE_TOOK(cudaMalloc(&held->scratch, held->scratch_bytes), &held->scratch, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->faces, voxels), &held->faces, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->belongs, voxels * sizeof(unsigned int)), &held->belongs, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->best, voxels * sizeof(unsigned long long)), &held->best, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->partner, voxels * sizeof(unsigned int)), &held->partner, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->bound, voxels * 3u), &held->bound, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->reaches, voxels), &held->reaches, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->label, voxels * sizeof(unsigned int)), &held->label, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->change, (voxels + 2u) * sizeof(int)), &held->change, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->counts, (voxels + 2u) * sizeof(int)), &held->counts, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->most, sizeof(int)), &held->most, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->level, sizeof(unsigned int)), &held->level, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->moved, 3u * sizeof(unsigned int)), &held->moved, error)
       && MAX_TREE_TOOK(cudaMallocHost((void **)&held->pinned_moved, 2u * sizeof(unsigned int)), &held->pinned_moved,
                        error)
       && MAX_TREE_TOOK(cudaEventCreateWithFlags(&held->blocks_done[0], cudaEventDisableTiming), &held->blocks_done[0],
                        error)
       && MAX_TREE_TOOK(cudaEventCreateWithFlags(&held->blocks_done[1], cudaEventDisableTiming), &held->blocks_done[1],
                        error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->roots, sizeof(unsigned int)), &held->roots, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->at_chunk, chunks * sizeof(unsigned int)), &held->at_chunk, error)
       && MAX_TREE_TOOK(cudaMalloc((void **)&held->packed, words * sizeof(unsigned long long)), &held->packed, error);
    held->host_chunks = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    ok = ok && MAX_TREE_HELD(held->host_chunks != NULL, &held->host_chunks, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int slot = 0u; (held->keeping != 0) && (slot < 2u); slot += 1u)
    {
        ok = ok
          && MAX_TREE_TOOK(cudaMalloc((void **)&held->kept_code[slot], voxels * sizeof(unsigned int)),
                           &held->kept_code[slot], error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&held->kept_values[slot],
                                      (voxels + 2u) * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                           &held->kept_values[slot], error);
    }
    if (ok == 0)
    {
        max_tree_release_held(held);
        return 0;
    }
    held->voxels = voxels;
    return 1;
}

static int max_tree_grow_bodies(size_t bodies, EngineError *error)
{
    MaxTreeHeld *const held = &s_max_tree_held;
    if ((bodies + 1u) <= held->body_room)
    {
        return 1;
    }
    const size_t room = (bodies + 1u) + ((bodies + 1u) / 2u);
    cudaFree(held->bodies);
    held->bodies = NULL;
    const int ok = MAX_TREE_TOOK(cudaMalloc((void **)&held->bodies, room * sizeof(EngineBody)), &held->bodies, error);
    held->body_room = (ok != 0) ? room : 0u;
    return ok;
}

#define MAX_TREE_STAGES 9u
static const char *const MAX_TREE_STAGE_NAMES[MAX_TREE_STAGES] = {"codes", "contract", "levels", "label",
                                                                  "peak", "mark", "census", "download", "grade"};
static unsigned long long s_max_tree_stage_us[MAX_TREE_STAGES];
static int s_max_tree_profile = -1;

static void max_tree_stage(unsigned int stage, unsigned long long *mark)
{
    if (s_max_tree_profile <= 0)
    {
        return;
    }
    (void)cudaDeviceSynchronize();
    const unsigned long long now = engine_clock_microseconds();
    s_max_tree_stage_us[stage] += now - *mark;
    *mark = now;
}

extern "C" void max_tree_profile_report(void)
{
    for (unsigned int stage = 0u; (s_max_tree_profile > 0) && (stage < MAX_TREE_STAGES); stage += 1u)
    {
        printf("    %-10s %8llu ms\n", MAX_TREE_STAGE_NAMES[stage], s_max_tree_stage_us[stage] / 1000ull);
    }
}

static int max_tree_grade_codes(const unsigned int *residual, unsigned int depth, unsigned int height,
                                unsigned int width, const unsigned char *coded, unsigned int *differ,
                                EngineError *error)
{
    const size_t voxels = (size_t)depth * height * width;
    unsigned char *faces = NULL;
    unsigned int *belongs = NULL;
    unsigned long long *strongest = NULL;
    unsigned int *partner = NULL;
    unsigned char *bound = NULL;
    unsigned int *moved = NULL;
    unsigned int *pinned = NULL;
    unsigned int *device_differ = NULL;
    cudaEvent_t done[2] = {NULL, NULL};
    int ok = MAX_TREE_TOOK(cudaMalloc((void **)&faces, voxels), &faces, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&belongs, voxels * sizeof(unsigned int)), &belongs, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&strongest, voxels * MAX_TREE_KEY_WORDS * sizeof(unsigned long long)),
                           &strongest, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&partner, voxels * sizeof(unsigned int)), &partner, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&bound, voxels * 3u), &bound, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&moved, 3u * sizeof(unsigned int)), &moved, error)
          && MAX_TREE_TOOK(cudaMallocHost((void **)&pinned, 2u * sizeof(unsigned int)), &pinned, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_differ, sizeof(unsigned int)), &device_differ, error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&done[0], cudaEventDisableTiming), &done[0], error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&done[1], cudaEventDisableTiming), &done[1], error)
          && MAX_TREE_TOOK(cudaMemset(moved, 0, 3u * sizeof(unsigned int)), moved, error)
          && MAX_TREE_TOOK(cudaMemset(device_differ, 0, sizeof(unsigned int)), device_differ, error);
    ok = ok && max_tree_contract(residual, depth, height, width, faces, belongs, strongest, partner, bound, moved,
                                 pinned, done, error);
    const unsigned int face_count = (unsigned int)(voxels * 3u);
    if (ok != 0)
    {
        max_tree_faces_differ_kernel<<<(face_count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
            bound, coded, face_count, device_differ);
        ok = MAX_TREE_TOOK(cudaGetLastError(), device_differ, error);
    }
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(differ, device_differ, sizeof(unsigned int), cudaMemcpyDeviceToHost), differ,
                             error);
    ok = ok && MAX_TREE_HELD(*differ == 0u, coded, error, ENGINE_ERROR_LOGIC);
    cudaFree(faces);
    cudaFree(belongs);
    cudaFree(strongest);
    cudaFree(partner);
    cudaFree(bound);
    cudaFree(moved);
    cudaFreeHost(pinned);
    cudaFree(device_differ);
    if (done[0] != NULL)
    {
        cudaEventDestroy(done[0]);
    }
    if (done[1] != NULL)
    {
        cudaEventDestroy(done[1]);
    }
    return ok;
}

extern "C" long max_tree_objects(const MaxTreeObjectsRequest *request)
{
    if (s_max_tree_profile < 0)
    {
        s_max_tree_profile = (getenv("MAX_TREE_PROFILE") != NULL) ? 1 : 0;
    }
    unsigned long long stage_mark = engine_clock_microseconds();
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const unsigned int depth = request->depth;
    const unsigned int height = request->height;
    const unsigned int width = request->width;
    const size_t voxels = (size_t)depth * height * width;
    const int asked = MAX_TREE_HELD(request->device_residual != NULL, &request->device_residual, error,
                                    ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD((request->room == 0u) || (request->bodies != NULL), &request->bodies, error,
                                    ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD((voxels != 0u) && ((voxels * 3u) < 0xFFFFFFFFull), &request->depth, error,
                                    ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_REFUSED;
    }
    MaxTreeHeld *const held = &s_max_tree_held;
    int ok = max_tree_hold(voxels, error);
    const unsigned int count = (unsigned int)voxels;
    const int items = (int)count;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int chunks = (count + MAX_TREE_CHUNK - 1u) / MAX_TREE_CHUNK;
    const unsigned int chunk_spread = (chunks + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int words = (count + 63u) / 64u;
    const unsigned int *const residual = request->device_residual;

    cub::DoubleBuffer<unsigned int> keys(held->keys[0], held->keys[1]);
    cub::DoubleBuffer<unsigned int> order(held->order[0], held->order[1]);
    if (ok != 0)
    {
        max_tree_iota_kernel<<<spread, MAX_TREE_BLOCK>>>(count, order.Current());
        ok = MAX_TREE_TOOK(cudaGetLastError(), order.Current(), error);
    }
    for (unsigned int limb = 0u; (ok != 0) && (limb < ENGINE_RESIDUAL_LIMBS); limb += 1u)
    {
        max_tree_code_gather_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), count, limb, keys.Current());
        size_t bytes = held->scratch_bytes;
        ok = MAX_TREE_TOOK(cudaGetLastError(), keys.Current(), error)
          && MAX_TREE_TOOK(cub::DeviceRadixSort::SortPairs(held->scratch, bytes, keys, order, items), held->scratch,
                           error);
    }
    unsigned int *const flags = keys.Current();
    unsigned int *const ranks = keys.Alternate();
    if (ok != 0)
    {
        max_tree_code_flags_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), count, flags);
        size_t bytes = held->scratch_bytes;
        ok = MAX_TREE_TOOK(cudaGetLastError(), flags, error)
          && MAX_TREE_TOOK(cub::DeviceScan::InclusiveSum(held->scratch, bytes, flags, ranks, items), ranks, error);
    }
    if (ok != 0)
    {
        max_tree_code_scatter_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), ranks, count, held->code);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->code, error);
    }
    unsigned int top = 0u;
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(&top, &ranks[count - 1u], sizeof(unsigned int), cudaMemcpyDeviceToHost),
                             &ranks[count - 1u], error);
    top += 1u;
    max_tree_stage(0u, &stage_mark);

    ok = ok && MAX_TREE_TOOK(cudaMemset(held->moved, 0, 3u * sizeof(unsigned int)), held->moved, error);
    ok = ok && max_tree_code_contract(held->code, depth, height, width, held->faces, held->belongs, held->best,
                                      held->partner, held->bound, held->moved, held->pinned_moved, held->blocks_done,
                                      error);
    max_tree_stage(1u, &stage_mark);
    unsigned int faces_differ = 0u;
    ok = ok && ((request->grade == 0u)
                || max_tree_grade_codes(residual, depth, height, width, held->bound, &faces_differ, error));
    max_tree_stage(8u, &stage_mark);

    ok = ok && MAX_TREE_TOOK(cudaMemset(held->change, 0, ((size_t)top + 1u) * sizeof(int)), held->change, error);
    if (ok != 0)
    {
        max_tree_code_levels_kernel<<<spread, MAX_TREE_BLOCK>>>(held->code, held->bound, depth, height, width,
                                                                held->change);
        max_tree_reverse_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(held->change, top,
                                                                                                 held->counts);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->counts, error);
    }
    if (ok != 0)
    {
        size_t bytes = held->scratch_bytes;
        ok = MAX_TREE_TOOK(cub::DeviceScan::InclusiveSum(held->scratch, bytes, held->counts, held->counts, (int)top),
                           held->counts, error);
        bytes = held->scratch_bytes;
        ok = ok && MAX_TREE_TOOK(cub::DeviceReduce::Max(held->scratch, bytes, held->counts, held->most, (int)top),
                                 held->most, error);
    }
    ok = ok && MAX_TREE_TOOK(cudaMemset(held->level, 0xFF, sizeof(unsigned int)), held->level, error);
    if (ok != 0)
    {
        max_tree_level_pick_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(held->counts, top,
                                                                                                    held->most,
                                                                                                    held->level);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->level, error);
    }
    int expected = 0;
    unsigned int level_code = 0u;
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(&expected, held->most, sizeof(int), cudaMemcpyDeviceToHost), held->most, error);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(&level_code, held->level, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                             held->level, error);
    level_code = ((top > 1u) && (level_code != 0xFFFFFFFFu)) ? level_code : 1u;
    max_tree_stage(2u, &stage_mark);

    if (ok != 0)
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(held->code, count, level_code, held->reaches,
                                                             held->label);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->label, error);
    }
    ok = ok && max_tree_cc(held->reaches, depth, height, width, held->label, held->moved, held->pinned_moved,
                           held->blocks_done, error);
    unsigned int found = 0u;
    ok = ok && MAX_TREE_TOOK(cudaMemset(held->roots, 0, sizeof(unsigned int)), held->roots, error);
    if (ok != 0)
    {
        max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(held->reaches, held->label, count, held->roots);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->roots, error);
    }
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(&found, held->roots, sizeof(unsigned int), cudaMemcpyDeviceToHost), held->roots,
                             error);
    max_tree_stage(3u, &stage_mark);

    ok = ok && MAX_TREE_TOOK(cudaMemset(held->best, 0, voxels * sizeof(unsigned long long)), held->best, error);
    if (ok != 0)
    {
        max_tree_peak_kernel<<<spread, MAX_TREE_BLOCK>>>(held->code, held->reaches, held->label, count, held->best);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->best, error);
    }
    max_tree_stage(4u, &stage_mark);

    if (ok != 0)
    {
        max_tree_mark_kernel<<<chunk_spread, MAX_TREE_BLOCK>>>(residual, held->code, held->reaches, held->label,
                                                               held->best, count, 0u, held->at_chunk, NULL, NULL);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->at_chunk, error);
    }
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(held->host_chunks, held->at_chunk, (size_t)chunks * sizeof(unsigned int),
                                        cudaMemcpyDeviceToHost),
                             held->host_chunks, error);
    unsigned long long bodies = 0ull;
    for (unsigned int chunk = 0u; (ok != 0) && (chunk < chunks); chunk += 1u)
    {
        const unsigned int here = held->host_chunks[chunk];
        held->host_chunks[chunk] = (unsigned int)bodies;
        bodies += (unsigned long long)here;
    }
    ok = ok && max_tree_grow_bodies((size_t)bodies, error);
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(held->at_chunk, held->host_chunks, (size_t)chunks * sizeof(unsigned int),
                                        cudaMemcpyHostToDevice),
                             held->at_chunk, error);
    ok = ok && MAX_TREE_TOOK(cudaMemset(held->bodies, 0, ((size_t)bodies + 1u) * sizeof(EngineBody)), held->bodies,
                             error);
    if (ok != 0)
    {
        max_tree_mark_kernel<<<chunk_spread, MAX_TREE_BLOCK>>>(residual, held->code, held->reaches, held->label,
                                                               held->best, count, 1u, held->at_chunk, held->partner,
                                                               held->bodies);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->bodies, error);
    }
    max_tree_stage(5u, &stage_mark);
    if (ok != 0)
    {
        max_tree_object_census_kernel<<<spread, MAX_TREE_BLOCK>>>(held->reaches, held->label, held->best,
                                                                  held->partner, depth, height, width, held->bodies,
                                                                  held->belongs);
        if (request->positive_words != NULL)
        {
            max_tree_pack_kernel<<<(words + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(residual, count,
                                                                                                   words, held->packed);
        }
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->bodies, error);
    }
    max_tree_stage(6u, &stage_mark);
    ok = ok && MAX_TREE_HELD(((long long)found == (long long)expected) && ((unsigned long long)found == bodies),
                             held->roots, error, ENGINE_ERROR_LOGIC);
    ok = ok && MAX_TREE_HELD((request->bodies == NULL) || (bodies <= (unsigned long long)request->room),
                             &request->room, error, ENGINE_ERROR_REQUEST);
    ok = ok && ((request->labels == NULL)
                || MAX_TREE_TOOK(cudaMemcpy(request->labels, held->belongs, voxels * sizeof(unsigned int),
                                            cudaMemcpyDeviceToHost),
                                 request->labels, error));
    ok = ok && ((request->positive_words == NULL)
                || MAX_TREE_TOOK(cudaMemcpy(request->positive_words, held->packed,
                                            (size_t)words * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                                 request->positive_words, error));
    ok = ok && ((request->bodies == NULL) || (bodies == 0ull)
                || MAX_TREE_TOOK(cudaMemcpy(request->bodies, held->bodies, (size_t)bodies * sizeof(EngineBody),
                                            cudaMemcpyDeviceToHost),
                                 request->bodies, error));
    max_tree_stage(7u, &stage_mark);
    const unsigned int keep_slot = held->kept_current ^ 1u;
    if ((ok != 0) && (held->keeping != 0))
    {
        held->kept_ready[keep_slot] = 0u;
        ok = MAX_TREE_TOOK(cudaMemcpy(held->kept_code[keep_slot], held->code, voxels * sizeof(unsigned int),
                                      cudaMemcpyDeviceToDevice),
                           held->kept_code[keep_slot], error)
          && MAX_TREE_TOOK(cudaMemset(held->kept_values[keep_slot], 0,
                                      ((size_t)top + 1u) * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                           held->kept_values[keep_slot], error);
    }
    if ((ok != 0) && (held->keeping != 0))
    {
        max_tree_code_values_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), flags, held->code, count,
                                                                held->kept_values[keep_slot]);
        ok = MAX_TREE_TOOK(cudaGetLastError(), held->kept_values[keep_slot], error);
        held->kept_top[keep_slot] = top;
        held->kept_ready[keep_slot] = (unsigned int)ok;
        held->kept_current = keep_slot;
    }
    if (request->level_code != NULL)
    {
        *request->level_code = level_code;
    }
    if (request->faces_differ != NULL)
    {
        *request->faces_differ = faces_differ;
    }
    if (request->proof_held != NULL)
    {
        *request->proof_held = (unsigned int)(ok != 0);
    }
    if (ok == 0)
    {
        max_tree_release_held(held);
        return MAX_TREE_REFUSED;
    }
    held->last_bodies = (size_t)bodies;
    held->top = top;
    held->cut_level = level_code;
    held->last_depth = depth;
    held->last_height = height;
    held->last_width = width;
    return (long)bodies;
}

__global__ static void max_tree_slide_gather_kernel(const unsigned int *probe_voxels, unsigned int probes,
                                                    const unsigned char *reaches, const unsigned int *label,
                                                    unsigned int *probe_labels)
{
    const unsigned int probe = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (probe >= probes)
    {
        return;
    }
    const unsigned int voxel = probe_voxels[probe];
    probe_labels[probe] = (reaches[voxel] != 0u) ? label[voxel] : MAX_TREE_ABSENT;
}

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int top;
    unsigned int probes;
    const unsigned int *device_probes;
    unsigned char *reaches;
    unsigned int *label;
    unsigned int *probe_labels;
    unsigned int *roots;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    unsigned int *raw;
    MaxTreeSlideStep *steps;
    unsigned int *partitions;
    unsigned int step_room;
    unsigned int step_count;
    unsigned int labelings;
    EngineError *error;
} MaxTreeSlide;

static int max_tree_slide_partition(MaxTreeSlide *slide, unsigned int level, unsigned int *partition,
                                    MaxTreeSlideStep *step)
{
    const MaxTreeHeld *const held = &s_max_tree_held;
    EngineError *const error = slide->error;
    const unsigned int count = slide->depth * slide->height * slide->width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    step->level = level;
    step->components = 0u;
    int ok = 1;
    if (level > slide->top)
    {
        for (unsigned int probe = 0u; probe < slide->probes; probe += 1u)
        {
            slide->raw[probe] = MAX_TREE_ABSENT;
        }
    }
    else
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(held->code, count, level, slide->reaches, slide->label);
        ok = MAX_TREE_TOOK(cudaGetLastError(), slide->label, error)
          && max_tree_cc(slide->reaches, slide->depth, slide->height, slide->width, slide->label, slide->moved,
                         slide->pinned_moved, slide->blocks_done, error)
          && MAX_TREE_TOOK(cudaMemset(slide->roots, 0, sizeof(unsigned int)), slide->roots, error);
        if (ok != 0)
        {
            max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(slide->reaches, slide->label, count, slide->roots);
            if (slide->probes != 0u)
            {
                max_tree_slide_gather_kernel<<<(slide->probes + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                               MAX_TREE_BLOCK>>>(slide->device_probes, slide->probes, slide->reaches,
                                                                 slide->label, slide->probe_labels);
            }
            ok = MAX_TREE_TOOK(cudaGetLastError(), slide->probe_labels, error);
        }
        unsigned int roots = 0u;
        int components = 0;
        ok = ok
          && MAX_TREE_TOOK(cudaMemcpy(&roots, slide->roots, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                           slide->roots, error)
          && MAX_TREE_TOOK(cudaMemcpy(&components, &held->counts[slide->top - level], sizeof(int),
                                      cudaMemcpyDeviceToHost),
                           &held->counts[slide->top - level], error)
          && ((slide->probes == 0u)
              || MAX_TREE_TOOK(cudaMemcpy(slide->raw, slide->probe_labels, (size_t)slide->probes * sizeof(unsigned int),
                                          cudaMemcpyDeviceToHost),
                               slide->raw, error));
        // components counts the superlevel set's pieces, never negative, so it re-signs to unsigned int exactly
        step->components = (unsigned int)components;
        ok = ok && MAX_TREE_HELD(roots == step->components, slide->roots, error, ENGINE_ERROR_LOGIC);
        slide->labelings += 1u;
    }
    for (unsigned int probe = 0u; probe < slide->probes; probe += 1u)
    {
        unsigned int first = probe;
        for (unsigned int earlier = probe; earlier > 0u; earlier -= 1u)
        {
            first = (slide->raw[earlier - 1u] == slide->raw[probe]) ? (earlier - 1u) : first;
        }
        partition[probe] = (slide->raw[probe] == MAX_TREE_ABSENT) ? MAX_TREE_ABSENT : first;
    }
    return ok;
}

static int max_tree_slide_search(MaxTreeSlide *slide, unsigned int low, unsigned int high,
                                 const unsigned int *low_partition, const MaxTreeSlideStep *low_step,
                                 const unsigned int *high_partition)
{
    EngineError *const error = slide->error;
    if (memcmp(low_partition, high_partition, (size_t)slide->probes * sizeof(unsigned int)) == 0)
    {
        return 1;
    }
    if ((high - low) == 1u)
    {
        if (!MAX_TREE_HELD(slide->step_count < slide->step_room, &slide->step_room, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        slide->steps[slide->step_count] = *low_step;
        if (slide->partitions != NULL)
        {
            memcpy(&slide->partitions[(size_t)slide->step_count * slide->probes], low_partition,
                   (size_t)slide->probes * sizeof(unsigned int));
        }
        slide->step_count += 1u;
        return 1;
    }
    const unsigned int middle = low + ((high - low) / 2u);
    unsigned int *const middle_partition = (unsigned int *)malloc(((size_t)slide->probes + 1u) * sizeof(unsigned int));
    MaxTreeSlideStep middle_step;
    const int ok = MAX_TREE_HELD(middle_partition != NULL, &middle_partition, error, ENGINE_ERROR_RESOURCE)
                && max_tree_slide_partition(slide, middle, middle_partition, &middle_step)
                && max_tree_slide_search(slide, middle, high, middle_partition, &middle_step, high_partition)
                && max_tree_slide_search(slide, low, middle, low_partition, low_step, middle_partition);
    free(middle_partition);
    return ok;
}

extern "C" long max_tree_slide(const MaxTreeSlideRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const MaxTreeHeld *const held = &s_max_tree_held;
    int asked = MAX_TREE_HELD((request->step_count != NULL) && (request->steps != NULL), request, error,
                              ENGINE_ERROR_REQUEST)
             && MAX_TREE_HELD((request->probe_count == 0u) || (request->probe_voxels != NULL), &request->probe_voxels,
                              error, ENGINE_ERROR_REQUEST)
             && MAX_TREE_HELD((held->code != NULL) && (held->top != 0u) && (held->last_depth != 0u), held, error,
                              ENGINE_ERROR_REQUEST);
    for (unsigned int probe = 0u; (asked != 0) && (probe < request->probe_count); probe += 1u)
    {
        asked = MAX_TREE_HELD(request->probe_voxels[probe] < held->voxels, &request->probe_voxels[probe], error,
                              ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return MAX_TREE_REFUSED;
    }
    MaxTreeSlide slide;
    memset(&slide, 0, sizeof(slide));
    slide.depth = held->last_depth;
    slide.height = held->last_height;
    slide.width = held->last_width;
    slide.top = held->top;
    slide.probes = request->probe_count;
    slide.steps = request->steps;
    slide.partitions = request->partitions;
    slide.step_room = request->step_room;
    slide.error = error;
    const size_t voxels = held->voxels;
    const size_t probe_room = (size_t)request->probe_count + 1u;
    unsigned int *device_probes = NULL;
    slide.raw = (unsigned int *)malloc(probe_room * sizeof(unsigned int));
    unsigned int *const low_partition = (unsigned int *)malloc(probe_room * sizeof(unsigned int));
    unsigned int *const high_partition = (unsigned int *)malloc(probe_room * sizeof(unsigned int));
    int ok = MAX_TREE_HELD(slide.raw != NULL, &slide.raw, error, ENGINE_ERROR_RESOURCE)
          && MAX_TREE_HELD(low_partition != NULL, &low_partition, error, ENGINE_ERROR_RESOURCE)
          && MAX_TREE_HELD(high_partition != NULL, &high_partition, error, ENGINE_ERROR_RESOURCE)
          && MAX_TREE_TOOK(cudaMalloc((void **)&device_probes, probe_room * sizeof(unsigned int)), &device_probes,
                           error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&slide.probe_labels, probe_room * sizeof(unsigned int)),
                           &slide.probe_labels, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&slide.reaches, voxels), &slide.reaches, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&slide.label, voxels * sizeof(unsigned int)), &slide.label, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&slide.roots, sizeof(unsigned int)), &slide.roots, error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&slide.moved, 3u * sizeof(unsigned int)), &slide.moved, error)
          && MAX_TREE_TOOK(cudaMallocHost((void **)&slide.pinned_moved, 2u * sizeof(unsigned int)), &slide.pinned_moved,
                           error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&slide.blocks_done[0], cudaEventDisableTiming),
                           &slide.blocks_done[0], error)
          && MAX_TREE_TOOK(cudaEventCreateWithFlags(&slide.blocks_done[1], cudaEventDisableTiming),
                           &slide.blocks_done[1], error)
          && ((request->probe_count == 0u)
              || MAX_TREE_TOOK(cudaMemcpy(device_probes, request->probe_voxels,
                                          (size_t)request->probe_count * sizeof(unsigned int), cudaMemcpyHostToDevice),
                               device_probes, error));
    slide.device_probes = device_probes;
    MaxTreeSlideStep low_step;
    MaxTreeSlideStep high_step;
    ok = ok && max_tree_slide_partition(&slide, 1u, low_partition, &low_step)
      && max_tree_slide_partition(&slide, slide.top + 1u, high_partition, &high_step)
      && max_tree_slide_search(&slide, 1u, slide.top + 1u, low_partition, &low_step, high_partition);
    cudaFree(device_probes);
    cudaFree(slide.probe_labels);
    cudaFree(slide.reaches);
    cudaFree(slide.label);
    cudaFree(slide.roots);
    cudaFree(slide.moved);
    cudaFreeHost(slide.pinned_moved);
    if (slide.blocks_done[0] != NULL)
    {
        cudaEventDestroy(slide.blocks_done[0]);
    }
    if (slide.blocks_done[1] != NULL)
    {
        cudaEventDestroy(slide.blocks_done[1]);
    }
    free(slide.raw);
    free(low_partition);
    free(high_partition);
    if (ok == 0)
    {
        return MAX_TREE_REFUSED;
    }
    *request->step_count = slide.step_count;
    if (request->top_level != NULL)
    {
        *request->top_level = held->top;
    }
    if (request->cut_level != NULL)
    {
        *request->cut_level = held->cut_level;
    }
    if (request->labelings != NULL)
    {
        *request->labelings = slide.labelings;
    }
    return 0L;
}

extern "C" int max_tree_keep_frames(void)
{
    MaxTreeHeld *const held = &s_max_tree_held;
    if (held->keeping == 0)
    {
        held->keeping = 1;
        max_tree_release_held(held);
    }
    return 1;
}

#define MAX_TREE_OVERLAP_TALLIES 10u

__device__ static unsigned int max_tree_row_below(const unsigned int *one, const unsigned int *other)
{
    unsigned int decided = 0u;
    unsigned int below = 0u;
    for (unsigned int limb = ENGINE_RESIDUAL_LIMBS; limb > 0u; limb -= 1u)
    {
        const unsigned int differs = (unsigned int)(one[limb - 1u] != other[limb - 1u]) & (decided ^ 1u);
        below |= differs & (unsigned int)(one[limb - 1u] < other[limb - 1u]);
        decided |= differs;
    }
    return below;
}

__global__ static void max_tree_overlap_threshold_kernel(const unsigned int *values, unsigned int top,
                                                         const unsigned int *value, unsigned int *threshold)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= top)
    {
        return;
    }
    const unsigned int code = place + 1u;
    const unsigned int reaches = max_tree_row_below(&values[(size_t)code * ENGINE_RESIDUAL_LIMBS], value) ^ 1u;
    const unsigned int under = (unsigned int)(code == 1u)
                             | max_tree_row_below(&values[(size_t)(code - 1u) * ENGINE_RESIDUAL_LIMBS], value);
    if ((reaches & under) != 0u)
    {
        atomicMin(threshold, code);
    }
}

__global__ static void max_tree_overlap_pairs_kernel(const unsigned char *earlier_reaches, const unsigned int *earlier_label,
                                                     const unsigned char *later_reaches, const unsigned int *later_label,
                                                     unsigned int depth, unsigned int height, unsigned int width,
                                                     int lag_z, int lag_y, int lag_x, unsigned long long *pairs)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    // each coordinate is below 2^32, so it widens from unsigned int to long long exactly and the signed lag adds without wrap
    const long long z = (long long)(voxel / plane) + (long long)lag_z;
    // as for z, the row widens to long long exactly
    const long long y = (long long)((voxel % plane) / width) + (long long)lag_y;
    // as for z, the column widens to long long exactly
    const long long x = (long long)(voxel % width) + (long long)lag_x;
    const unsigned int inside = (unsigned int)((z >= 0LL) && (z < (long long)depth) && (y >= 0LL)
                                               && (y < (long long)height) && (x >= 0LL) && (x < (long long)width));
    // the landing is only read inside the view, where it is a voxel index below 2^32 and narrows to unsigned int exactly
    const unsigned int landed = (unsigned int)((((z * (long long)height) + y) * (long long)width) + x) * inside;
    const unsigned int alive = inside & (unsigned int)(earlier_reaches[voxel] != 0u)
                             & (unsigned int)(later_reaches[landed] != 0u);
    pairs[voxel] = (alive != 0u) ? (((unsigned long long)earlier_label[voxel] << 32u) | later_label[landed]) : ~0ull;
}

__global__ static void max_tree_overlap_partners_kernel(const unsigned long long *sorted, unsigned int count,
                                                        unsigned int *earlier_partners, unsigned int *later_partners)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= count)
    {
        return;
    }
    const unsigned long long pair = sorted[place];
    if ((pair == ~0ull) || ((place > 0u) && (sorted[place - 1u] == pair)))
    {
        return;
    }
    // the high half holds an earlier label below 2^32, so it narrows to unsigned int exactly
    atomicAdd(&earlier_partners[(unsigned int)(pair >> 32u)], 1u);
    // the low half holds a later label below 2^32, so it narrows to unsigned int exactly
    atomicAdd(&later_partners[(unsigned int)(pair & 0xFFFFFFFFull)], 1u);
}

__global__ static void max_tree_overlap_one_kernel(const unsigned char *reaches, const unsigned int *label,
                                                   const unsigned int *partners, unsigned int voxels, unsigned int *ones)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u) || (label[voxel] != voxel) || (partners[voxel] != 1u))
    {
        return;
    }
    atomicAdd(ones, 1u);
}

__global__ static void max_tree_overlap_backs_kernel(const unsigned long long *sorted, unsigned int count,
                                                     const unsigned int *earlier_partners,
                                                     const unsigned int *later_partners, unsigned int *earlier_backs,
                                                     unsigned int *later_backs)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= count)
    {
        return;
    }
    const unsigned long long pair = sorted[place];
    if ((pair == ~0ull) || ((place > 0u) && (sorted[place - 1u] == pair)))
    {
        return;
    }
    // the high half holds an earlier label below 2^32, so it narrows to unsigned int exactly
    const unsigned int earlier = (unsigned int)(pair >> 32u);
    // the low half holds a later label below 2^32, so it narrows to unsigned int exactly
    const unsigned int later = (unsigned int)(pair & 0xFFFFFFFFull);
    if (later_partners[later] == 1u)
    {
        atomicAdd(&earlier_backs[earlier], 1u);
    }
    if (earlier_partners[earlier] == 1u)
    {
        atomicAdd(&later_backs[later], 1u);
    }
}

__global__ static void max_tree_overlap_census_kernel(const unsigned char *reaches, const unsigned int *label,
                                                      const unsigned int *partners, const unsigned int *backs,
                                                      unsigned int voxels, unsigned int *census)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (reaches[voxel] == 0u) || (label[voxel] != voxel))
    {
        return;
    }
    const unsigned int many = partners[voxel];
    const unsigned int whole = (unsigned int)(backs[voxel] == many);
    const unsigned int kind = (many == 0u) ? 0u : ((((many == 1u) || (many == 2u)) && (whole != 0u)) ? many : 3u);
    if (kind < 3u)
    {
        atomicAdd(&census[kind], 1u);
    }
}

__device__ static unsigned int max_tree_overlap_holds(const unsigned long long *sorted, unsigned int count,
                                                      unsigned long long pair)
{
    unsigned int low = 0u;
    unsigned int high = count;
    while (low < high)
    {
        const unsigned int middle = low + ((high - low) / 2u);
        const unsigned int before = (unsigned int)(sorted[middle] < pair);
        low = (before != 0u) ? (middle + 1u) : low;
        high = (before != 0u) ? high : middle;
    }
    return (unsigned int)((low < count) && (sorted[low] == pair));
}

__global__ static void max_tree_overlap_probe_kernel(const unsigned int *probe_voxels, unsigned int probes,
                                                     const unsigned char *reaches, const unsigned int *label,
                                                     const unsigned int *partners, const unsigned int *backs,
                                                     MaxTreeOverlapProbe *out)
{
    const unsigned int probe = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (probe >= probes)
    {
        return;
    }
    const unsigned int voxel = probe_voxels[probe];
    const unsigned int inside = (unsigned int)(reaches[voxel] != 0u);
    const unsigned int root = (inside != 0u) ? label[voxel] : MAX_TREE_ABSENT;
    out[probe].root = root;
    out[probe].degree = (inside != 0u) ? partners[root] : 0u;
    out[probe].backs = (inside != 0u) ? backs[root] : 0u;
}

__global__ static void max_tree_overlap_link_kernel(const unsigned int *probe_links, unsigned int links,
                                                    const MaxTreeOverlapProbe *earlier, const MaxTreeOverlapProbe *later,
                                                    const unsigned long long *sorted, unsigned int count,
                                                    unsigned char *held)
{
    const unsigned int link = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (link >= links)
    {
        return;
    }
    const unsigned int one = earlier[probe_links[(size_t)link * 2u]].root;
    const unsigned int other = later[probe_links[((size_t)link * 2u) + 1u]].root;
    const unsigned int both = (unsigned int)((one != MAX_TREE_ABSENT) && (other != MAX_TREE_ABSENT));
    held[link] = (unsigned char)(both & max_tree_overlap_holds(sorted, count, ((unsigned long long)one << 32u) | other));
}

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    int lag[3];
    unsigned int probe_counts[2];
    const unsigned int *probe_voxels[2];
    MaxTreeOverlapProbe *probes[2];
    const unsigned int *probe_links;
    unsigned int link_count;
    unsigned char *links_held;
    unsigned int slot[2];
    unsigned char *reaches[2];
    unsigned int *label[2];
    unsigned int *partners[2];
    unsigned int *backs[2];
    unsigned long long *pairs[2];
    void *scratch;
    size_t scratch_bytes;
    unsigned int *thresholds;
    unsigned int *tallies;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    EngineError *error;
} MaxTreeOverlap;

static int max_tree_overlap_step(MaxTreeOverlap *overlap, unsigned int origin, unsigned int level,
                                 MaxTreeOverlapStep *step, MaxTreeOverlapProbe *probes, unsigned char *links_held)
{
    const MaxTreeHeld *const held = &s_max_tree_held;
    EngineError *const error = overlap->error;
    const unsigned int count = overlap->depth * overlap->height * overlap->width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int origin_slot = overlap->slot[origin];
    if (!MAX_TREE_HELD((level != 0u) && (level <= held->kept_top[origin_slot]), step, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned int *const value = &held->kept_values[origin_slot][(size_t)level * ENGINE_RESIDUAL_LIMBS];
    unsigned int thresholds[2] = {0u, 0u};
    int ok = 1;
    for (unsigned int frame = 0u; (ok != 0) && (frame < 2u); frame += 1u)
    {
        const unsigned int slot = overlap->slot[frame];
        const unsigned int top = held->kept_top[slot];
        thresholds[frame] = top + 1u;
        ok = MAX_TREE_TOOK(cudaMemcpy(&overlap->thresholds[frame], &thresholds[frame], sizeof(unsigned int),
                                      cudaMemcpyHostToDevice),
                           &overlap->thresholds[frame], error);
        if (ok != 0)
        {
            max_tree_overlap_threshold_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
                held->kept_values[slot], top, value, &overlap->thresholds[frame]);
            ok = MAX_TREE_TOOK(cudaGetLastError(), &overlap->thresholds[frame], error);
        }
    }
    ok = ok
      && MAX_TREE_TOOK(cudaMemcpy(thresholds, overlap->thresholds, 2u * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                       overlap->thresholds, error)
      && MAX_TREE_TOOK(cudaMemset(overlap->tallies, 0, MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int)),
                       overlap->tallies, error);
    for (unsigned int frame = 0u; (ok != 0) && (frame < 2u); frame += 1u)
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(held->kept_code[overlap->slot[frame]], count,
                                                             thresholds[frame], overlap->reaches[frame],
                                                             overlap->label[frame]);
        ok = MAX_TREE_TOOK(cudaGetLastError(), overlap->label[frame], error)
          && max_tree_cc(overlap->reaches[frame], overlap->depth, overlap->height, overlap->width,
                         overlap->label[frame], overlap->moved, overlap->pinned_moved, overlap->blocks_done, error)
          && MAX_TREE_TOOK(cudaMemset(overlap->partners[frame], 0, (size_t)count * sizeof(unsigned int)),
                           overlap->partners[frame], error)
          && MAX_TREE_TOOK(cudaMemset(overlap->backs[frame], 0, (size_t)count * sizeof(unsigned int)),
                           overlap->backs[frame], error);
        if (ok != 0)
        {
            max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->reaches[frame], overlap->label[frame], count,
                                                              &overlap->tallies[frame]);
            ok = MAX_TREE_TOOK(cudaGetLastError(), &overlap->tallies[frame], error);
        }
    }
    if (ok != 0)
    {
        max_tree_overlap_pairs_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->reaches[0], overlap->label[0],
                                                                  overlap->reaches[1], overlap->label[1],
                                                                  overlap->depth, overlap->height, overlap->width,
                                                                  overlap->lag[0], overlap->lag[1], overlap->lag[2],
                                                                  overlap->pairs[0]);
        size_t bytes = overlap->scratch_bytes;
        // the voxel count was held below 2^32 when the frame was cut, and the sort takes it as int
        ok = MAX_TREE_TOOK(cudaGetLastError(), overlap->pairs[0], error)
          && MAX_TREE_TOOK(cub::DeviceRadixSort::SortKeys(overlap->scratch, bytes, overlap->pairs[0], overlap->pairs[1],
                                                          (int)count),
                           overlap->pairs[1], error);
    }
    if (ok != 0)
    {
        max_tree_overlap_partners_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->pairs[1], count, overlap->partners[0],
                                                                     overlap->partners[1]);
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            max_tree_overlap_one_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->reaches[frame], overlap->label[frame],
                                                                    overlap->partners[frame], count,
                                                                    &overlap->tallies[2u + frame]);
        }
        max_tree_overlap_backs_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->pairs[1], count, overlap->partners[0],
                                                                  overlap->partners[1], overlap->backs[0],
                                                                  overlap->backs[1]);
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            max_tree_overlap_census_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->reaches[frame], overlap->label[frame],
                                                                       overlap->partners[frame], overlap->backs[frame],
                                                                       count, &overlap->tallies[4u + (3u * frame)]);
        }
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            if (overlap->probe_counts[frame] != 0u)
            {
                max_tree_overlap_probe_kernel<<<(overlap->probe_counts[frame] + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                                MAX_TREE_BLOCK>>>(overlap->probe_voxels[frame],
                                                                  overlap->probe_counts[frame], overlap->reaches[frame],
                                                                  overlap->label[frame], overlap->partners[frame],
                                                                  overlap->backs[frame], overlap->probes[frame]);
            }
        }
        if (overlap->link_count != 0u)
        {
            max_tree_overlap_link_kernel<<<(overlap->link_count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                           MAX_TREE_BLOCK>>>(overlap->probe_links, overlap->link_count,
                                                             overlap->probes[0], overlap->probes[1], overlap->pairs[1],
                                                             count, overlap->links_held);
        }
        ok = MAX_TREE_TOOK(cudaGetLastError(), overlap->tallies, error);
    }
    ok = ok
      && ((overlap->probe_counts[0] == 0u)
          || MAX_TREE_TOOK(cudaMemcpy(probes, overlap->probes[0],
                                      (size_t)overlap->probe_counts[0] * sizeof(MaxTreeOverlapProbe),
                                      cudaMemcpyDeviceToHost),
                           probes, error))
      && ((overlap->probe_counts[1] == 0u)
          || MAX_TREE_TOOK(cudaMemcpy(&probes[overlap->probe_counts[0]], overlap->probes[1],
                                      (size_t)overlap->probe_counts[1] * sizeof(MaxTreeOverlapProbe),
                                      cudaMemcpyDeviceToHost),
                           &probes[overlap->probe_counts[0]], error))
      && ((overlap->link_count == 0u)
          || MAX_TREE_TOOK(cudaMemcpy(links_held, overlap->links_held, overlap->link_count, cudaMemcpyDeviceToHost),
                           links_held, error));
    unsigned int tallies[MAX_TREE_OVERLAP_TALLIES] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    ok = ok
      && MAX_TREE_TOOK(cudaMemcpy(tallies, overlap->tallies, MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int),
                                  cudaMemcpyDeviceToHost),
                       overlap->tallies, error);
    step->origin = origin;
    step->level = level;
    step->earlier_code = thresholds[0];
    step->later_code = thresholds[1];
    step->earlier_components = tallies[0];
    step->later_components = tallies[1];
    step->earlier_one = tallies[2];
    step->later_one = tallies[3];
    step->earlier_unpaired = tallies[4];
    step->earlier_mutual = tallies[5];
    step->earlier_forked = tallies[6];
    step->later_unpaired = tallies[7];
    step->later_mutual = tallies[8];
    step->later_forked = tallies[9];
    return ok;
}

extern "C" long max_tree_overlap(const MaxTreeOverlapRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const MaxTreeHeld *const held = &s_max_tree_held;
    int asked =
        MAX_TREE_HELD((request->step_count != NULL) && (request->steps != NULL), request, error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((held->keeping != 0) && (held->kept_ready[0] != 0u) && (held->kept_ready[1] != 0u)
                          && (held->last_depth != 0u),
                      held, error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->earlier_level_count == 0u) || (request->earlier_levels != NULL),
                      &request->earlier_levels, error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->later_level_count == 0u) || (request->later_levels != NULL), &request->later_levels,
                      error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->probe_counts[0] == 0u) || (request->probe_voxels[0] != NULL),
                      &request->probe_voxels[0], error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->probe_counts[1] == 0u) || (request->probe_voxels[1] != NULL),
                      &request->probe_voxels[1], error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD(((request->probe_counts[0] + request->probe_counts[1]) == 0u) || (request->probes != NULL),
                      &request->probes, error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->link_count == 0u) || ((request->probe_links != NULL) && (request->links_held != NULL)),
                      &request->probe_links, error, ENGINE_ERROR_REQUEST)
     && MAX_TREE_HELD((request->earlier_level_count + request->later_level_count) <= request->step_room,
                      &request->step_room, error, ENGINE_ERROR_REQUEST);
    const size_t voxels = held->voxels;
    for (unsigned int frame = 0u; (asked != 0) && (frame < 2u); frame += 1u)
    {
        for (unsigned int probe = 0u; (asked != 0) && (probe < request->probe_counts[frame]); probe += 1u)
        {
            asked = MAX_TREE_HELD(request->probe_voxels[frame][probe] < voxels, &request->probe_voxels[frame][probe],
                                  error, ENGINE_ERROR_REQUEST);
        }
    }
    for (unsigned int link = 0u; (asked != 0) && (link < request->link_count); link += 1u)
    {
        asked = MAX_TREE_HELD((request->probe_links[2u * link] < request->probe_counts[0])
                                  && (request->probe_links[(2u * link) + 1u] < request->probe_counts[1]),
                              &request->probe_links[2u * link], error, ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return MAX_TREE_REFUSED;
    }
    MaxTreeOverlap overlap;
    memset(&overlap, 0, sizeof(overlap));
    overlap.depth = held->last_depth;
    overlap.height = held->last_height;
    overlap.width = held->last_width;
    overlap.slot[0] = held->kept_current ^ 1u;
    overlap.slot[1] = held->kept_current;
    overlap.link_count = request->link_count;
    overlap.error = error;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        overlap.lag[axis] = request->lag[axis];
    }
    unsigned int *device_probe_voxels[2] = {NULL, NULL};
    unsigned int *device_links = NULL;
    int ok = 1;
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        const size_t probes = request->probe_counts[frame];
        overlap.probe_counts[frame] = request->probe_counts[frame];
        ok = ok
          && ((probes == 0u)
              || (MAX_TREE_TOOK(cudaMalloc((void **)&device_probe_voxels[frame], probes * sizeof(unsigned int)),
                                &device_probe_voxels[frame], error)
                  && MAX_TREE_TOOK(cudaMemcpy(device_probe_voxels[frame], request->probe_voxels[frame],
                                              probes * sizeof(unsigned int), cudaMemcpyHostToDevice),
                                   device_probe_voxels[frame], error)
                  && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.probes[frame], probes * sizeof(MaxTreeOverlapProbe)),
                                   &overlap.probes[frame], error)));
        overlap.probe_voxels[frame] = device_probe_voxels[frame];
    }
    const size_t link_words = (size_t)request->link_count * 2u;
    ok = ok
      && ((request->link_count == 0u)
          || (MAX_TREE_TOOK(cudaMalloc((void **)&device_links, link_words * sizeof(unsigned int)), &device_links, error)
              && MAX_TREE_TOOK(cudaMemcpy(device_links, request->probe_links, link_words * sizeof(unsigned int),
                                          cudaMemcpyHostToDevice),
                               device_links, error)
              && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.links_held, request->link_count), &overlap.links_held,
                               error)));
    overlap.probe_links = device_links;
    // the voxel count was held below 2^32 when the frame was cut, and the sort takes it as int
    ok = ok
      && MAX_TREE_TOOK(cub::DeviceRadixSort::SortKeys(NULL, overlap.scratch_bytes, (const unsigned long long *)NULL,
                                                      (unsigned long long *)NULL, (int)voxels),
                       &overlap.scratch_bytes, error)
      && MAX_TREE_TOOK(cudaMalloc(&overlap.scratch, overlap.scratch_bytes), &overlap.scratch, error)
      && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.thresholds, 2u * sizeof(unsigned int)), &overlap.thresholds, error)
      && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.tallies, MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int)),
                       &overlap.tallies, error)
      && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.moved, 3u * sizeof(unsigned int)), &overlap.moved, error)
      && MAX_TREE_TOOK(cudaMallocHost((void **)&overlap.pinned_moved, 2u * sizeof(unsigned int)),
                       &overlap.pinned_moved, error)
      && MAX_TREE_TOOK(cudaEventCreateWithFlags(&overlap.blocks_done[0], cudaEventDisableTiming),
                       &overlap.blocks_done[0], error)
      && MAX_TREE_TOOK(cudaEventCreateWithFlags(&overlap.blocks_done[1], cudaEventDisableTiming),
                       &overlap.blocks_done[1], error);
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        ok = ok
          && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.reaches[frame], voxels), &overlap.reaches[frame], error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.label[frame], voxels * sizeof(unsigned int)),
                           &overlap.label[frame], error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.partners[frame], voxels * sizeof(unsigned int)),
                           &overlap.partners[frame], error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.backs[frame], voxels * sizeof(unsigned int)),
                           &overlap.backs[frame], error)
          && MAX_TREE_TOOK(cudaMalloc((void **)&overlap.pairs[frame], voxels * sizeof(unsigned long long)),
                           &overlap.pairs[frame], error);
    }
    const size_t probes_a_step = (size_t)request->probe_counts[0] + request->probe_counts[1];
    unsigned int written = 0u;
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->earlier_level_count); taken += 1u)
    {
        ok = max_tree_overlap_step(&overlap, 0u, request->earlier_levels[taken], &request->steps[written],
                                   &request->probes[written * probes_a_step],
                                   &request->links_held[(size_t)written * request->link_count]);
        written += 1u;
    }
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->later_level_count); taken += 1u)
    {
        ok = max_tree_overlap_step(&overlap, 1u, request->later_levels[taken], &request->steps[written],
                                   &request->probes[written * probes_a_step],
                                   &request->links_held[(size_t)written * request->link_count]);
        written += 1u;
    }
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        cudaFree(device_probe_voxels[frame]);
        cudaFree(overlap.probes[frame]);
    }
    cudaFree(device_links);
    cudaFree(overlap.links_held);
    cudaFree(overlap.scratch);
    cudaFree(overlap.thresholds);
    cudaFree(overlap.tallies);
    cudaFree(overlap.moved);
    cudaFreeHost(overlap.pinned_moved);
    if (overlap.blocks_done[0] != NULL)
    {
        cudaEventDestroy(overlap.blocks_done[0]);
    }
    if (overlap.blocks_done[1] != NULL)
    {
        cudaEventDestroy(overlap.blocks_done[1]);
    }
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        cudaFree(overlap.reaches[frame]);
        cudaFree(overlap.label[frame]);
        cudaFree(overlap.partners[frame]);
        cudaFree(overlap.backs[frame]);
        cudaFree(overlap.pairs[frame]);
    }
    if (ok == 0)
    {
        return MAX_TREE_REFUSED;
    }
    *request->step_count = written;
    return 0L;
}

static unsigned int max_tree_bits_for(unsigned long long bound)
{
    unsigned int bits = 1u;
    while ((bits < 64u) && ((bound >> bits) != 0ull))
    {
        bits += 1u;
    }
    return bits;
}

extern "C" void max_tree_layout(unsigned int depth, unsigned int height, unsigned int width, unsigned int frames,
                                unsigned int samples, MaxTreeLayout *layout)
{
    const unsigned long long voxels = (unsigned long long)depth * height * width;
    const unsigned long long reach[3] = {(depth > 0u) ? (depth - 1u) : 0u, (height > 0u) ? (height - 1u) : 0u,
                                         (width > 0u) ? (width - 1u) : 0u};
    memset(layout, 0, sizeof(*layout));
    layout->bits[MAX_TREE_FIELD_MOMENT_ZZ] = max_tree_bits_for(voxels * reach[0] * reach[0]);
    layout->bits[MAX_TREE_FIELD_MOMENT_YY] = max_tree_bits_for(voxels * reach[1] * reach[1]);
    layout->bits[MAX_TREE_FIELD_MOMENT_XX] = max_tree_bits_for(voxels * reach[2] * reach[2]);
    layout->bits[MAX_TREE_FIELD_MOMENT_ZY] = max_tree_bits_for(voxels * reach[0] * reach[1]);
    layout->bits[MAX_TREE_FIELD_MOMENT_ZX] = max_tree_bits_for(voxels * reach[0] * reach[2]);
    layout->bits[MAX_TREE_FIELD_MOMENT_YX] = max_tree_bits_for(voxels * reach[1] * reach[2]);
    layout->bits[MAX_TREE_FIELD_SUM_Z] = max_tree_bits_for(voxels * reach[0]);
    layout->bits[MAX_TREE_FIELD_SUM_Y] = max_tree_bits_for(voxels * reach[1]);
    layout->bits[MAX_TREE_FIELD_SUM_X] = max_tree_bits_for(voxels * reach[2]);
    layout->bits[MAX_TREE_FIELD_PEAK] = max_tree_bits_for((voxels > 0ull) ? (voxels - 1ull) : 0ull);
    layout->bits[MAX_TREE_FIELD_TOUCHES] = 6u;
    layout->bits[MAX_TREE_FIELD_MASS] = max_tree_bits_for(voxels);
    layout->bits[MAX_TREE_FIELD_LEVEL] = (ENGINE_RESIDUAL_LIMBS * 32u) - 1u;
    layout->bits[MAX_TREE_FIELD_FRAME] = max_tree_bits_for((frames > 0u) ? (frames - 1u) : 0u);
    layout->bits[MAX_TREE_FIELD_SAMPLE] = max_tree_bits_for((samples > 0u) ? (samples - 1u) : 0u);
    unsigned int at = 0u;
    for (unsigned int field = 0u; field < MAX_TREE_FIELDS; field += 1u)
    {
        layout->offset[field] = at;
        at += layout->bits[field];
    }
    layout->total_bits = at;
    layout->limbs = (at + 31u) / 32u;
}

__device__ static unsigned int max_tree_put_field(unsigned int *magnitude, unsigned int offset, unsigned int bits,
                                                  const unsigned int *value, unsigned int limbs)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int within = (unsigned int)(bit < (limbs * 32u));
        const unsigned int set = ((value[(bit / 32u) * within] >> (bit % 32u)) & 1u) & within;
        const unsigned int to = offset + bit;
        magnitude[to / 32u] |= set << (to % 32u);
    }
    unsigned int lost = 0u;
    for (unsigned int bit = 0u; bit < (limbs * 32u); bit += 1u)
    {
        const unsigned int set = (value[bit / 32u] >> (bit % 32u)) & 1u;
        const unsigned int to = offset + bit;
        const unsigned int inside = (unsigned int)(bit < bits);
        const unsigned int held = inside & ((magnitude[(to / 32u) * inside] >> (to % 32u)) & 1u);
        lost += set ^ held;
    }
    return lost;
}

__global__ static void max_tree_pack_bodies_kernel(const EngineBody *bodies, unsigned int count, MaxTreeLayout layout,
                                                   unsigned int sample, unsigned int frame, unsigned int *magnitudes,
                                                   unsigned long long *mismatches)
{
    const unsigned int slot = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (slot >= count)
    {
        return;
    }
    const EngineBody *const body = &bodies[slot];
    unsigned int *const magnitude = &magnitudes[(size_t)slot * layout.limbs];
    for (unsigned int limb = 0u; limb < layout.limbs; limb += 1u)
    {
        magnitude[limb] = 0u;
    }
    unsigned int lost = 0u;
    for (unsigned int moment = 0u; moment < 6u; moment += 1u)
    {
        const unsigned int limbs[2] = {(unsigned int)(body->moments[moment] & 0xFFFFFFFFull),
                                       (unsigned int)(body->moments[moment] >> 32u)};
        lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_MOMENT_ZZ + moment],
                                   layout.bits[MAX_TREE_FIELD_MOMENT_ZZ + moment], limbs, 2u);
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int limbs[2] = {(unsigned int)(body->sums[axis] & 0xFFFFFFFFull),
                                       (unsigned int)(body->sums[axis] >> 32u)};
        lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_SUM_Z + axis],
                                   layout.bits[MAX_TREE_FIELD_SUM_Z + axis], limbs, 2u);
    }
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_PEAK], layout.bits[MAX_TREE_FIELD_PEAK],
                               &body->peak, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_TOUCHES], layout.bits[MAX_TREE_FIELD_TOUCHES],
                               &body->touches, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_MASS], layout.bits[MAX_TREE_FIELD_MASS],
                               &body->mass, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_LEVEL], layout.bits[MAX_TREE_FIELD_LEVEL],
                               body->level, ENGINE_RESIDUAL_LIMBS);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_FRAME], layout.bits[MAX_TREE_FIELD_FRAME],
                               &frame, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_SAMPLE], layout.bits[MAX_TREE_FIELD_SAMPLE],
                               &sample, 1u);
    if (lost != 0u)
    {
        atomicAdd(mismatches, (unsigned long long)lost);
    }
}

extern "C" long max_tree_pack(const MaxTreePackRequest *request)
{
    MaxTreeHeld *const held = &s_max_tree_held;
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const int asked = MAX_TREE_HELD(request->layout != NULL, &request->layout, error, ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD(request->device_magnitudes != NULL, &request->device_magnitudes, error,
                                    ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD(request->mismatches != NULL, &request->mismatches, error, ENGINE_ERROR_REQUEST)
                   && MAX_TREE_HELD(held->voxels != 0u, &held->voxels, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_REFUSED;
    }
    const unsigned int bodies = (unsigned int)held->last_bodies;
    unsigned long long *device_lost = NULL;
    int ok = MAX_TREE_TOOK(cudaMalloc((void **)&device_lost, sizeof(unsigned long long)), &device_lost, error)
          && MAX_TREE_TOOK(cudaMemset(device_lost, 0, sizeof(unsigned long long)), device_lost, error);
    if ((ok != 0) && (bodies != 0u))
    {
        max_tree_pack_bodies_kernel<<<(bodies + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
            held->bodies, bodies, *request->layout, request->sample, request->frame, request->device_magnitudes,
            device_lost);
        ok = MAX_TREE_TOOK(cudaGetLastError(), request->device_magnitudes, error);
    }
    unsigned long long lost = 0ull;
    ok = ok && MAX_TREE_TOOK(cudaMemcpy(&lost, device_lost, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                             device_lost, error);
    cudaFree(device_lost);
    *request->mismatches = lost;
    ok = ok && MAX_TREE_HELD(lost == 0ull, request->device_magnitudes, error, ENGINE_ERROR_LOGIC);
    return (ok != 0) ? (long)bodies : MAX_TREE_REFUSED;
}
