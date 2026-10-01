// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_contract.cu: contraction (max_tree_contract) and its kernels
#include "max_tree_device_internal.h"

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
    const unsigned int here = max_tree_selected(residual, voxel);
    unsigned int flags = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int beside = voxel + (stride[axis] * inside[axis]);
        const unsigned int binds = inside[axis] & here & max_tree_selected(residual, beside);
        const unsigned int far_weaker = max_tree_below(residual, beside, voxel);
        flags |= (binds << axis) | ((binds & far_weaker) << (axis + 3u));
    }
    faces[voxel] = (unsigned char)flags;
}

__global__ static void max_tree_start_kernel(unsigned int voxels, unsigned int *belongs, unsigned long long *strongest,
                                             unsigned char *bound)
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

__global__ void max_tree_jump_kernel(unsigned int voxels, unsigned int *belongs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = belongs[belongs[voxel]];
}

__global__ void max_tree_flatten_kernel(unsigned int voxels, unsigned int *belongs)
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

int max_tree_contract(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                      unsigned char *faces, unsigned int *belongs, unsigned long long *strongest, unsigned int *partner,
                      unsigned char *bound, unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                      EngineError *error)
{
    const unsigned int count = depth * height * width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_faces_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, depth, height, width, faces);
    max_tree_start_kernel<<<spread, MAX_TREE_BLOCK>>>(count, belongs, strongest, bound);
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
            for (unsigned int word = MAX_TREE_KEY_WORDS; word > 0u; word -= 1u)
            {
                max_tree_choose_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, faces, belongs, depth, height, width,
                                                                   word - 1u, strongest);
            }
            max_tree_partner_kernel<<<spread, MAX_TREE_BLOCK>>>(strongest, belongs, depth, height, width, partner);
            max_tree_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(strongest, partner, count, (block * MAX_TREE_TICKS) + tick,
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
