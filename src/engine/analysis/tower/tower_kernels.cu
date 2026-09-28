// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tower_kernels.cu: the tower's kernels and plan
#include "tower_internal.h"

__device__ static long long tower_floor_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

__device__ static unsigned long long tower_line(const TowerStep &step, unsigned long long index,
                                                unsigned long long *along)
{
    unsigned long long offset = 0ull;
    unsigned long long rest = index;
    for (unsigned int axis = 4u; axis > 0u; axis -= 1u)
    {
        const unsigned long long digit = rest % step.extent[axis - 1u];
        rest /= step.extent[axis - 1u];
        offset += digit * step.stride[axis - 1u];
        if ((axis - 1u) == step.axis)
        {
            *along = digit;
        }
    }
    return offset - (*along * step.stride[step.axis]);
}

__device__ static long long tower_high(const int *from, unsigned long long line, unsigned long long stride,
                                       unsigned long long length, unsigned long long j)
{
    const long long left = from[line + (2ull * j * stride)];
    const long long right = ((2ull * j + 2ull) < length) ? (long long)from[line + ((2ull * j + 2ull) * stride)] : left;
    return (long long)from[line + ((2ull * j + 1ull) * stride)] - tower_floor_shift(left + right, 1u);
}

__global__ void tower_forward_kernel(const int *from, int *to, TowerStep step, unsigned int *overflow)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < step.count;
         index += jump)
    {
        unsigned long long along = 0ull;
        const unsigned long long line = tower_line(step, index, &along);
        const unsigned long long stride = step.stride[step.axis];
        const unsigned long long length = step.extent[step.axis];
        const unsigned long long lows = (length + 1ull) / 2ull;
        const unsigned long long highs = length / 2ull;
        long long value = 0ll;
        if (along < lows)
        {
            const long long before = (along > 0ull) ? tower_high(from, line, stride, length, along - 1ull)
                                                    : tower_high(from, line, stride, length, 0ull);
            const long long after = (along < highs) ? tower_high(from, line, stride, length, along) : before;
            value = (long long)from[line + (2ull * along * stride)] + tower_floor_shift(before + after + 2ll, 2u);
        }
        else
        {
            value = tower_high(from, line, stride, length, along - lows);
        }
        if ((value >= TOWER_LIMIT) || (value <= -TOWER_LIMIT))
        {
            atomicOr(overflow, 1u);
        }
        to[line + (along * stride)] = (int)value;
    }
}

__device__ static long long tower_even(const int *from, unsigned long long line, unsigned long long stride,
                                       unsigned long long lows, unsigned long long highs, unsigned long long i)
{
    const long long before = (long long)from[line + ((lows + ((i > 0ull) ? (i - 1ull) : 0ull)) * stride)];
    const long long after = (i < highs) ? (long long)from[line + ((lows + i) * stride)] : before;
    return (long long)from[line + (i * stride)] - tower_floor_shift(before + after + 2ll, 2u);
}

__global__ void tower_inverse_kernel(const int *from, int *to, TowerStep step)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < step.count;
         index += jump)
    {
        unsigned long long along = 0ull;
        const unsigned long long line = tower_line(step, index, &along);
        const unsigned long long stride = step.stride[step.axis];
        const unsigned long long length = step.extent[step.axis];
        const unsigned long long lows = (length + 1ull) / 2ull;
        const unsigned long long highs = length / 2ull;
        long long value = 0ll;
        if ((along % 2ull) == 0ull)
        {
            value = tower_even(from, line, stride, lows, highs, along / 2ull);
        }
        else
        {
            const unsigned long long j = along / 2ull;
            const long long left = tower_even(from, line, stride, lows, highs, j);
            const long long right =
                ((2ull * j + 2ull) < length) ? tower_even(from, line, stride, lows, highs, j + 1ull) : left;
            value = (long long)from[line + ((lows + j) * stride)] + tower_floor_shift(left + right, 1u);
        }
        to[line + (along * stride)] = (int)value;
    }
}

__global__ void tower_copy_kernel(const int *from, int *to, TowerStep step)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < step.count;
         index += jump)
    {
        unsigned long long along = 0ull;
        const unsigned long long lane = tower_line(step, index, &along) + (along * step.stride[step.axis]);
        to[lane] = from[lane];
    }
}

__global__ void tower_edge_kernel(int *state, TowerStep region, const unsigned int *table, unsigned int index_bits)
{
    const unsigned int mask = (1u << index_bits) - 1u;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < region.count;
         index += jump)
    {
        unsigned long long offset = 0ull;
        unsigned long long rest = index;
        for (unsigned int axis = 4u; axis > 0u; axis -= 1u)
        {
            const unsigned long long digit = rest % region.extent[axis - 1u];
            rest /= region.extent[axis - 1u];
            offset += digit * region.stride[axis - 1u];
        }
        // the low index_bits are permuted, the high bits pass through. The map is a bijection on the word
        const unsigned int word = (unsigned int)state[offset];
        state[offset] = (int)((word & ~mask) | table[word & mask]);
    }
}

__global__ void tower_widen_kernel(const unsigned short *lanes, unsigned long long count, int *to)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        // a 16-bit lane widens to int exactly
        to[index] = (int)lanes[index];
    }
}

__global__ void tower_take_kernel(const int *values, unsigned long long count, int *to, unsigned int *overflow)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        const int value = values[index];
        if ((value >= TOWER_LIMIT) || (value <= -TOWER_LIMIT))
        {
            atomicOr(overflow, 1u);
        }
        to[index] = value;
    }
}

__global__ void tower_differ_kernel(const int *rebuilt, const unsigned short *lanes, unsigned long long count,
                                    unsigned long long *mismatches)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long differ = 0ull;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        differ += (rebuilt[index] != (int)lanes[index]) ? 1ull : 0ull;
    }
    if (differ != 0ull)
    {
        atomicAdd(mismatches, differ);
    }
}

__global__ void tower_narrow_kernel(const int *rebuilt, unsigned long long count, unsigned short *to,
                                    unsigned int *outside)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    unsigned int wide = 0u;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        const int value = rebuilt[index];
        wide |= ((value & ~0xFFFF) != 0) ? 1u : 0u;
        // the value is masked to its low 16 bits, which an unsigned short holds exactly
        to[index] = (unsigned short)((unsigned int)value & 0xFFFFu);
    }
    if (wide != 0u)
    {
        atomicOr(outside, 1u);
    }
}

unsigned int tower_blocks(unsigned long long count)
{
    const unsigned long long needed = (count + TOWER_THREADS - 1ull) / TOWER_THREADS;
    return (unsigned int)((needed < 65536ull) ? ((needed == 0ull) ? 1ull : needed) : 65536ull);
}

std::vector<TowerStep> tower_floors(const unsigned long long *extent)
{
    std::vector<TowerStep> floors;
    TowerStep step;
    memset(&step, 0, sizeof(step));
    step.stride[3] = 1ull;
    step.stride[2] = extent[3];
    step.stride[1] = extent[2] * extent[3];
    step.stride[0] = extent[1] * extent[2] * extent[3];
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        step.extent[axis] = extent[axis];
    }
    while ((step.extent[0] > 1ull) || (step.extent[1] > 1ull) || (step.extent[2] > 1ull) || (step.extent[3] > 1ull))
    {
        step.count = step.extent[0] * step.extent[1] * step.extent[2] * step.extent[3];
        floors.push_back(step);
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            step.extent[axis] = (step.extent[axis] + 1ull) / 2ull;
        }
    }
    return floors;
}

TowerResident g_tower_resident;

int tower_edge_reserve(unsigned int entries, EngineError *error)
{
    TowerResident *const resident = &g_tower_resident;
    if ((size_t)entries > resident->edge_entries)
    {
        cudaFree(resident->edge_table);
        resident->edge_table = NULL;
        resident->edge_entries = 0u;
        if (TOWER_STATUS_CHECK(cudaMalloc((void **)&resident->edge_table, (size_t)entries * sizeof(unsigned int)),
                               &resident->edge_table, error) == 0)
        {
            return 0;
        }
        resident->edge_entries = entries;
    }
    return 1;
}

// the pool's slices for `lanes`, in the order they are laid out and taken: the coefficients, the scratch, the flag and
// the mismatch count; the plan is laid out from them, and a pool reserved from it takes them
DevicePoolPlan tower_plan(size_t lanes, EngineError *error, DevicePoolTakeRequest takes[TOWER_SLICES])
{
    TowerResident *const resident = &g_tower_resident;
    const DevicePoolTakeRequest requests[TOWER_SLICES] = {
        {&resident->pool, lanes * sizeof(int), (void **)&resident->coefficients, error},
        {&resident->pool, lanes * sizeof(int), (void **)&resident->scratch, error},
        {&resident->pool, sizeof(unsigned int), (void **)&resident->flag, error},
        {&resident->pool, sizeof(unsigned long long), (void **)&resident->mismatches, error}};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < TOWER_SLICES; at += 1u)
    {
        takes[at] = requests[at];
        device_pool_plan_slice(&plan, requests[at].bytes);
    }
    return plan;
}
