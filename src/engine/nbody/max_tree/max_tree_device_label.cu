// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_label.cu: labeling
#include "max_tree_device_internal.h"

__global__ static void max_tree_ranges_kernel(const unsigned int *residual, unsigned int voxels, unsigned int level,
                                              unsigned char *ranges)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    ranges[voxel] = (unsigned char)(max_tree_selected(residual, voxel) & (max_tree_below(residual, voxel, level) ^ 1u));
}

__global__ static void max_tree_label_start_kernel(const unsigned char *ranges, unsigned int voxels,
                                                   unsigned int *label)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    label[voxel] = (ranges[voxel] != 0u) ? voxel : MAX_TREE_ABSENT;
}

__global__ static void max_tree_spread_kernel(const unsigned char *ranges, const unsigned char *bound,
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
    const unsigned int here = ranges[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        const unsigned int crosses = inside[axis] & here & (unsigned int)ranges[beside] &
                                     (every | (unsigned int)bound[((size_t)voxel * 3u) + axis]);
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
    const unsigned int target = label[voxel];
    if (target != MAX_TREE_ABSENT)
    {
        label[voxel] = label[target];
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

static int max_tree_label(const unsigned char *ranges, const unsigned char *bound, unsigned int every,
                          unsigned int depth, unsigned int height, unsigned int width, unsigned int *label,
                          unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done, EngineError *error)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int spread = (voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_label_start_kernel<<<spread, MAX_TREE_BLOCK>>>(ranges, voxels, label);
    int ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), label, error);
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_STATUS_CHECK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            max_tree_spread_kernel<<<spread, MAX_TREE_BLOCK>>>(ranges, bound, every, depth, height, width, label,
                                                               &moved[parity]);
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_label_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(voxels, label);
            }
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), label, error);
        }
        ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                         cudaMemcpyDeviceToHost, 0),
                                         &pinned_moved[parity], error);
        ok = ok && MAX_TREE_STATUS_CHECK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_STATUS_CHECK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    return (ok != 0) && MAX_TREE_STATUS_CHECK(cudaDeviceSynchronize(), label, error);
}

extern "C" long max_tree_bind(const MaxTreeBindRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const size_t voxels = (size_t)request->depth * request->height * request->width;
    const int asked =
        MAX_TREE_CHECK(request->residual != NULL, &request->residual, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK(request->bound != NULL, &request->bound, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->level_count == 0u) || (request->levels != NULL), &request->levels, error,
                       ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((voxels != 0u) && ((voxels * 3u) < 0xFFFFFFFFull), &request->depth, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_ERROR;
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
    unsigned char *device_ranges = NULL;
    unsigned int *device_across_every = NULL;
    unsigned int *device_across_chosen = NULL;
    unsigned int *device_differ = NULL;
    const unsigned int proved_at = (request->level_count != 0u) ? request->level_count : 1u;
    cudaEvent_t blocks_done[2] = {NULL, NULL};
    int ok =
        MAX_TREE_STATUS_CHECK(
            cudaMalloc((void **)&device_residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
            &device_residual, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_faces, voxels), &device_faces, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_belongs, voxels * sizeof(unsigned int)), &device_belongs,
                              error) &&
        MAX_TREE_STATUS_CHECK(
            cudaMalloc((void **)&device_strongest, voxels * MAX_TREE_KEY_WORDS * sizeof(unsigned long long)),
            &device_strongest, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_partner, voxels * sizeof(unsigned int)), &device_partner,
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_bound, voxels * 3u), &device_bound, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_moved, 3u * sizeof(unsigned int)), &device_moved, error) &&
        MAX_TREE_STATUS_CHECK(cudaMallocHost((void **)&pinned_moved, 2u * sizeof(unsigned int)), &pinned_moved,
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_differ, proved_at * sizeof(unsigned int)), &device_differ,
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&blocks_done[0], cudaEventDisableTiming), &blocks_done[0],
                              error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&blocks_done[1], cudaEventDisableTiming), &blocks_done[1],
                              error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(device_residual, request->residual,
                                                voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int),
                                                cudaMemcpyHostToDevice),
                                     device_residual, error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(device_moved, 0, 3u * sizeof(unsigned int)), device_moved, error);
    ok = ok &&
         MAX_TREE_STATUS_CHECK(cudaMemset(device_differ, 0, proved_at * sizeof(unsigned int)), device_differ, error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaDeviceSynchronize(), device_residual, error);
    const unsigned long long began = engine_clock_microseconds();
    const unsigned int count = (unsigned int)voxels;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    ok = ok && max_tree_contract(device_residual, depth, height, width, device_faces, device_belongs, device_strongest,
                                 device_partner, device_bound, device_moved, pinned_moved, blocks_done, error);
    const unsigned long long bound_at = engine_clock_microseconds();

    if ((ok != 0) && (request->level_count != 0u))
    {
        ok = MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_ranges, voxels), &device_ranges, error) &&
             MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_across_every, voxels * sizeof(unsigned int)),
                                   &device_across_every, error) &&
             MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_across_chosen, voxels * sizeof(unsigned int)),
                                   &device_across_chosen, error);
    }
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->level_count); taken += 1u)
    {
        max_tree_ranges_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, count, request->levels[taken],
                                                           device_ranges);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_ranges, error);
        ok = ok && max_tree_label(device_ranges, device_bound, 1u, depth, height, width, device_across_every,
                                  device_moved, pinned_moved, blocks_done, error);
        ok = ok && max_tree_label(device_ranges, device_bound, 0u, depth, height, width, device_across_chosen,
                                  device_moved, pinned_moved, blocks_done, error);
        if (ok != 0)
        {
            max_tree_differ_kernel<<<spread, MAX_TREE_BLOCK>>>(device_across_every, device_across_chosen, count,
                                                               &device_differ[taken]);
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), &device_differ[taken], error);
        }
    }
    ok = ok && MAX_TREE_STATUS_CHECK(cudaDeviceSynchronize(), device_differ, error);
    const unsigned long long proved_at_end = engine_clock_microseconds();

    unsigned int last = 0u;
    unsigned int *const differ = (unsigned int *)malloc(proved_at * sizeof(unsigned int));
    ok =
        ok && MAX_TREE_CHECK(differ != NULL, &differ, error, ENGINE_ERROR_RESOURCE) &&
        MAX_TREE_STATUS_CHECK(cudaMemcpy(request->bound, device_bound, voxels * 3u, cudaMemcpyDeviceToHost),
                              request->bound, error) &&
        MAX_TREE_STATUS_CHECK(cudaMemcpy(&last, &device_moved[2], sizeof(unsigned int), cudaMemcpyDeviceToHost), &last,
                              error) &&
        MAX_TREE_STATUS_CHECK(
            cudaMemcpy(differ, device_differ, proved_at * sizeof(unsigned int), cudaMemcpyDeviceToHost), differ, error);
    long chosen = MAX_TREE_ERROR;
    unsigned int levels_equal = 0u;
    if (ok != 0)
    {
        chosen = 0L;
        for (size_t face = 0u; face < (voxels * 3u); face += 1u)
        {
            chosen += (long)(request->bound[face] != 0u);
        }
        for (unsigned int taken = 0u; taken < request->level_count; taken += 1u)
        {
            levels_equal += (unsigned int)(differ[taken] == 0u);
        }
        ok = MAX_TREE_CHECK(levels_equal == request->level_count, differ, error, ENGINE_ERROR_LOGIC);
        chosen = (ok != 0) ? chosen : MAX_TREE_ERROR;
    }
    if (request->rounds != NULL)
    {
        *request->rounds = last;
    }
    if (request->levels_equal != NULL)
    {
        *request->levels_equal = levels_equal;
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
    cudaFree(device_ranges);
    cudaFree(device_across_every);
    cudaFree(device_across_chosen);
    cudaFree(device_differ);
    cudaEventDestroy(blocks_done[0]);
    cudaEventDestroy(blocks_done[1]);
    return chosen;
}
