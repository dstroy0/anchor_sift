// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_code.cu: the code kernels, levels and connected components
#include "max_tree_device_internal.h"

__global__ void max_tree_iota_kernel(unsigned int voxels, unsigned int *order)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    order[place] = place;
}

__global__ void max_tree_code_gather_kernel(const unsigned int *residual, const unsigned int *order,
                                            unsigned int voxels, unsigned int limb, unsigned int *keys)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    keys[place] = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb] * max_tree_selected(residual, voxel);
}

__global__ void max_tree_code_flags_kernel(const unsigned int *residual, const unsigned int *order, unsigned int voxels,
                                           unsigned int *flags)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    const unsigned int before = order[place - (unsigned int)(place > 0u)];
    const unsigned int one = max_tree_selected(residual, voxel);
    const unsigned int other = max_tree_selected(residual, before);
    unsigned int differs = one ^ other;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        differs |= one & other &
                   (unsigned int)(residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb] !=
                                  residual[((size_t)before * ENGINE_RESIDUAL_LIMBS) + limb]);
    }
    flags[place] = differs;
}

__global__ void max_tree_code_scatter_kernel(const unsigned int *residual, const unsigned int *order,
                                             const unsigned int *ranks, unsigned int voxels, unsigned int *code)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    code[voxel] = (ranks[place] + 1u) * max_tree_selected(residual, voxel);
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

int max_tree_code_contract(const unsigned int *code, unsigned int depth, unsigned int height, unsigned int width,
                           unsigned char *faces, unsigned int *belongs, unsigned long long *best, unsigned int *partner,
                           unsigned char *bound, unsigned int *moved, unsigned int *pinned_moved,
                           cudaEvent_t *blocks_done, EngineError *error)
{
    const unsigned int count = depth * height * width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_code_faces_kernel<<<spread, MAX_TREE_BLOCK>>>(code, depth, height, width, faces);
    max_tree_code_start_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs, best, bound);
    int ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), bound, error);
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_STATUS_CHECK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
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
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), belongs, error);
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
    return (ok != 0) && MAX_TREE_STATUS_CHECK(cudaDeviceSynchronize(), bound, error);
}

__global__ void max_tree_faces_differ_kernel(const unsigned char *one, const unsigned char *other, unsigned int faces,
                                             unsigned int *differ)
{
    const unsigned int face = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((face < faces) && (one[face] != other[face]))
    {
        atomicAdd(differ, 1u);
    }
}

__global__ void max_tree_code_levels_kernel(const unsigned int *code, const unsigned char *bound, unsigned int depth,
                                            unsigned int height, unsigned int width, int *change)
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

__global__ void max_tree_reverse_kernel(const int *change, unsigned int top, int *reversed)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= top)
    {
        return;
    }
    reversed[place] = change[top - place];
}

__global__ void max_tree_level_pick_kernel(const int *counts, unsigned int top, const int *maximum, unsigned int *level)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((place < top) && (counts[place] == maximum[0]))
    {
        atomicMin(level, top - place);
    }
}

__global__ void max_tree_cc_start_kernel(const unsigned int *code, unsigned int voxels, unsigned int level,
                                         unsigned char *ranges, unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int reached = (unsigned int)(code[voxel] >= level);
    ranges[voxel] = (unsigned char)reached;
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

__global__ void max_tree_cc_hook_kernel(const unsigned char *ranges, unsigned int depth, unsigned int height,
                                        unsigned int width, unsigned int *parent, unsigned int *moved)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u))
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
        if ((inside[axis] & (unsigned int)ranges[beside]) == 0u)
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

__global__ void max_tree_cc_jump_kernel(const unsigned char *ranges, unsigned int voxels, unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u))
    {
        return;
    }
    parent[voxel] = parent[parent[voxel]];
}

__global__ void max_tree_cc_flatten_kernel(const unsigned char *ranges, unsigned int voxels, unsigned int *parent)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u))
    {
        return;
    }
    parent[voxel] = max_tree_cc_root(parent, voxel);
}
