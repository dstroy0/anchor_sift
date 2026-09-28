// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_overlap_kernels.cu: the overlap kernels
#include "max_tree_device_internal.h"

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

__global__ void max_tree_overlap_threshold_kernel(const unsigned int *values, unsigned int top,
                                                  const unsigned int *value, unsigned int *threshold)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= top)
    {
        return;
    }
    const unsigned int code = place + 1u;
    const unsigned int ranges = max_tree_row_below(&values[(size_t)code * ENGINE_RESIDUAL_LIMBS], value) ^ 1u;
    const unsigned int under =
        (unsigned int)(code == 1u) | max_tree_row_below(&values[(size_t)(code - 1u) * ENGINE_RESIDUAL_LIMBS], value);
    if ((ranges & under) != 0u)
    {
        atomicMin(threshold, code);
    }
}

__global__ void max_tree_overlap_pairs_kernel(const unsigned char *earlier_ranges, const unsigned int *earlier_label,
                                              const unsigned char *later_ranges, const unsigned int *later_label,
                                              unsigned int depth, unsigned int height, unsigned int width, int lag_z,
                                              int lag_y, int lag_x, unsigned long long *pairs)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    // each coordinate is below 2^32. It widens from unsigned int to long long exactly and the signed lag adds
    // without wrap
    const long long z = (long long)(voxel / plane) + (long long)lag_z;
    // as for z, the row widens to long long exactly
    const long long y = (long long)((voxel % plane) / width) + (long long)lag_y;
    // as for z, the column widens to long long exactly
    const long long x = (long long)(voxel % width) + (long long)lag_x;
    const unsigned int inside = (unsigned int)((z >= 0LL) && (z < (long long)depth) && (y >= 0LL) &&
                                               (y < (long long)height) && (x >= 0LL) && (x < (long long)width));
    // the landing is only read inside the view, where it is a voxel index below 2^32 and narrows to unsigned int
    // exactly
    const unsigned int landed = (unsigned int)((((z * (long long)height) + y) * (long long)width) + x) * inside;
    const unsigned int alive =
        inside & (unsigned int)(earlier_ranges[voxel] != 0u) & (unsigned int)(later_ranges[landed] != 0u);
    pairs[voxel] = (alive != 0u) ? (((unsigned long long)earlier_label[voxel] << 32u) | later_label[landed]) : ~0ull;
}

__global__ void max_tree_overlap_partners_kernel(const unsigned long long *sorted, unsigned int count,
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
    // the high half holds an earlier label below 2^32. It narrows to unsigned int exactly
    atomicAdd(&earlier_partners[(unsigned int)(pair >> 32u)], 1u);
    // the low half holds a later label below 2^32. It narrows to unsigned int exactly
    atomicAdd(&later_partners[(unsigned int)(pair & 0xFFFFFFFFull)], 1u);
}

__global__ void max_tree_overlap_one_kernel(const unsigned char *ranges, const unsigned int *label,
                                            const unsigned int *partners, unsigned int voxels, unsigned int *ones)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u) || (label[voxel] != voxel) || (partners[voxel] != 1u))
    {
        return;
    }
    atomicAdd(ones, 1u);
}

__global__ void max_tree_overlap_backs_kernel(const unsigned long long *sorted, unsigned int count,
                                              const unsigned int *earlier_partners, const unsigned int *later_partners,
                                              unsigned int *earlier_backs, unsigned int *later_backs)
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
    // the high half holds an earlier label below 2^32. It narrows to unsigned int exactly
    const unsigned int earlier = (unsigned int)(pair >> 32u);
    // the low half holds a later label below 2^32. It narrows to unsigned int exactly
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

__global__ void max_tree_overlap_census_kernel(const unsigned char *ranges, const unsigned int *label,
                                               const unsigned int *partners, const unsigned int *backs,
                                               unsigned int voxels, unsigned int *census)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u) || (label[voxel] != voxel))
    {
        return;
    }
    const unsigned int many = partners[voxel];
    const unsigned int all_back = (unsigned int)(backs[voxel] == many);
    const unsigned int kind = (many == 0u) ? 0u : ((((many == 1u) || (many == 2u)) && (all_back != 0u)) ? many : 3u);
    if (kind < 3u)
    {
        atomicAdd(&census[kind], 1u);
    }
}

__device__ static unsigned int max_tree_overlap_valid(const unsigned long long *sorted, unsigned int count,
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

__global__ void max_tree_overlap_probe_kernel(const unsigned int *probe_voxels, unsigned int probes,
                                              const unsigned char *ranges, const unsigned int *label,
                                              const unsigned int *partners, const unsigned int *backs,
                                              MaxTreeOverlapProbe *out)
{
    const unsigned int probe = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (probe >= probes)
    {
        return;
    }
    const unsigned int voxel = probe_voxels[probe];
    const unsigned int inside = (unsigned int)(ranges[voxel] != 0u);
    const unsigned int root = (inside != 0u) ? label[voxel] : MAX_TREE_ABSENT;
    out[probe].root = root;
    out[probe].degree = (inside != 0u) ? partners[root] : 0u;
    out[probe].backs = (inside != 0u) ? backs[root] : 0u;
}

__global__ void max_tree_overlap_link_kernel(const unsigned int *probe_links, unsigned int links,
                                             const MaxTreeOverlapProbe *earlier, const MaxTreeOverlapProbe *later,
                                             const unsigned long long *sorted, unsigned int count,
                                             unsigned char *links_present)
{
    const unsigned int link = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (link >= links)
    {
        return;
    }
    const unsigned int one = earlier[probe_links[(size_t)link * 2u]].root;
    const unsigned int other = later[probe_links[((size_t)link * 2u) + 1u]].root;
    const unsigned int both = (unsigned int)((one != MAX_TREE_ABSENT) && (other != MAX_TREE_ABSENT));
    links_present[link] =
        (unsigned char)(both & max_tree_overlap_valid(sorted, count, ((unsigned long long)one << 32u) | other));
}
