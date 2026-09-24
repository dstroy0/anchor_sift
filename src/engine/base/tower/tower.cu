// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tower.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#include <vector>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define TOWER_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_TOWER, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define TOWER_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_TOWER, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define TOWER_THREADS 256u

#define TOWER_LIMIT ENGINE_COEFFICIENT_LIMIT

struct TowerStep
{
    unsigned long long extent[4];
    unsigned long long stride[4];
    unsigned long long count;
    unsigned int axis;
};

__device__ static long long tower_floor_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

__device__ static unsigned long long tower_line(const TowerStep &step, unsigned long long index, unsigned long long *along)
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

__global__ static void tower_forward_kernel(const int *from, int *to, TowerStep step, unsigned int *overflow)
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

__global__ static void tower_inverse_kernel(const int *from, int *to, TowerStep step)
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
            const long long right = ((2ull * j + 2ull) < length) ? tower_even(from, line, stride, lows, highs, j + 1ull)
                                                                 : left;
            value = (long long)from[line + ((lows + j) * stride)] + tower_floor_shift(left + right, 1u);
        }
        to[line + (along * stride)] = (int)value;
    }
}

__global__ static void tower_copy_kernel(const int *from, int *to, TowerStep step)
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

__global__ static void tower_edge_kernel(int *state, TowerStep region, const unsigned int *table, unsigned int index_bits)
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
        // the low index_bits are permuted, the high bits pass through, so the map is a bijection on the word
        const unsigned int word = (unsigned int)state[offset];
        state[offset] = (int)((word & ~mask) | table[word & mask]);
    }
}

__global__ static void tower_widen_kernel(const unsigned short *lanes, unsigned long long count, int *to)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; index < count;
         index += jump)
    {
        // a 16-bit lane widens to int exactly
        to[index] = (int)lanes[index];
    }
}

__global__ static void tower_differ_kernel(const int *rebuilt, const unsigned short *lanes, unsigned long long count,
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

__global__ static void tower_narrow_kernel(const int *rebuilt, unsigned long long count, unsigned short *to,
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

static unsigned int tower_blocks(unsigned long long count)
{
    const unsigned long long needed = (count + TOWER_THREADS - 1ull) / TOWER_THREADS;
    return (unsigned int)((needed < 65536ull) ? ((needed == 0ull) ? 1ull : needed) : 65536ull);
}

static std::vector<TowerStep> tower_floors(const unsigned long long *extent)
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

struct TowerHeld
{
    int *coefficients;
    int *scratch;
    size_t lanes;
    unsigned int *flag;
    unsigned long long *mismatches;
    unsigned int *edge_table;
    size_t edge_entries;
};

static TowerHeld s_tower_held;

static int tower_edge_hold(unsigned int entries, EngineError *error)
{
    TowerHeld *const held = &s_tower_held;
    if ((size_t)entries > held->edge_entries)
    {
        cudaFree(held->edge_table);
        held->edge_table = NULL;
        held->edge_entries = 0u;
        if (TOWER_TOOK(cudaMalloc((void **)&held->edge_table, (size_t)entries * sizeof(unsigned int)), &held->edge_table,
                       error)
            == 0)
        {
            return 0;
        }
        held->edge_entries = entries;
    }
    return 1;
}

static int tower_hold(size_t lanes, EngineError *error)
{
    TowerHeld *const held = &s_tower_held;
    int ok = 1;
    if (lanes > held->lanes)
    {
        cudaFree(held->coefficients);
        cudaFree(held->scratch);
        held->coefficients = NULL;
        held->scratch = NULL;
        held->lanes = 0u;
        ok = TOWER_TOOK(cudaMalloc((void **)&held->coefficients, lanes * sizeof(int)), &held->coefficients, error)
          && TOWER_TOOK(cudaMalloc((void **)&held->scratch, lanes * sizeof(int)), &held->scratch, error);
        held->lanes = (ok != 0) ? lanes : 0u;
    }
    if ((ok != 0) && (held->flag == NULL))
    {
        ok = TOWER_TOOK(cudaMalloc((void **)&held->flag, sizeof(unsigned int)), &held->flag, error)
          && TOWER_TOOK(cudaMalloc((void **)&held->mismatches, sizeof(unsigned long long)), &held->mismatches, error);
    }
    return ok;
}

static unsigned long long tower_lanes(const unsigned long long *extent)
{
    unsigned long long lanes = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        if ((extent[axis] == 0ull) || (lanes > (0xFFFFFFFFFFFFFFFFull / extent[axis])))
        {
            return 0ull;
        }
        lanes *= extent[axis];
    }
    return lanes;
}

static int tower_edge_check(const TowerEdge *edges, unsigned int edge_count, unsigned int levels, EngineError *error)
{
    for (unsigned int at = 0u; at < edge_count; at += 1u)
    {
        const TowerEdge *const edge = &edges[at];
        if (!TOWER_HELD((edge->forward != NULL) && (edge->index_bits >= 1u)
                            && (edge->index_bits <= TOWER_EDGE_INDEX_BITS_MOST) && (edge->floor <= levels),
                        edge, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        const unsigned long long entries = 1ull << edge->index_bits;
        unsigned char *const seen = (unsigned char *)calloc((size_t)entries, sizeof(unsigned char));
        if (!TOWER_HELD(seen != NULL, edge, error, ENGINE_ERROR_RESOURCE))
        {
            return 0;
        }
        int permutation = 1;
        for (unsigned long long index = 0ull; (permutation != 0) && (index < entries); index += 1ull)
        {
            const unsigned int value = edge->forward[index];
            if ((value >= entries) || (seen[value] != 0u))
            {
                permutation = 0;
            }
            else
            {
                seen[value] = 1u;
            }
        }
        free(seen);
        if (!TOWER_HELD(permutation != 0, edge, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
    }
    return 1;
}

static void tower_active_extent(const std::vector<TowerStep> &floors, const unsigned long long *extent, unsigned int slot,
                                unsigned long long out[4])
{
    if (floors.empty())
    {
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            out[axis] = extent[axis];
        }
        return;
    }
    if (slot < floors.size())
    {
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            out[axis] = floors[slot].extent[axis];
        }
    }
    else
    {
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            out[axis] = (floors.back().extent[axis] + 1ull) / 2ull;
        }
    }
}

static int tower_edge_run(const TowerEdge *edges, unsigned int edge_count, const std::vector<TowerStep> &floors,
                          const unsigned long long *extent, unsigned int slot, int inverse, EngineError *error)
{
    TowerHeld *const held = &s_tower_held;
    TowerStep region;
    memset(&region, 0, sizeof(region));
    // the global strides are the full-extent strides, held constant across the in-place lifting levels
    region.stride[3] = 1ull;
    region.stride[2] = extent[3];
    region.stride[1] = extent[2] * extent[3];
    region.stride[0] = extent[1] * extent[2] * extent[3];
    unsigned long long active[4];
    tower_active_extent(floors, extent, slot, active);
    region.count = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        region.extent[axis] = active[axis];
        region.count *= active[axis];
    }
    int ok = 1;
    // a lift walks a slot's edges in array order, a lower walks them in reverse, so a slot inverts as a stack
    for (unsigned int scan = 0u; (ok != 0) && (scan < edge_count); scan += 1u)
    {
        const unsigned int at = (inverse != 0) ? (edge_count - 1u - scan) : scan;
        const TowerEdge *const edge = &edges[at];
        if (edge->floor != slot)
        {
            continue;
        }
        const unsigned long long entries = 1ull << edge->index_bits;
        if (tower_edge_hold((unsigned int)entries, error) == 0)
        {
            return 0;
        }
        const unsigned int *upload = edge->forward;
        unsigned int *inverted = NULL;
        if (inverse != 0)
        {
            inverted = (unsigned int *)malloc((size_t)entries * sizeof(unsigned int));
            if (!TOWER_HELD(inverted != NULL, edge, error, ENGINE_ERROR_RESOURCE))
            {
                return 0;
            }
            for (unsigned long long index = 0ull; index < entries; index += 1ull)
            {
                inverted[edge->forward[index]] = (unsigned int)index;
            }
            upload = inverted;
        }
        ok = TOWER_TOOK(cudaMemcpy(held->edge_table, upload, (size_t)entries * sizeof(unsigned int),
                                   cudaMemcpyHostToDevice),
                        held->edge_table, error);
        if (ok != 0)
        {
            tower_edge_kernel<<<tower_blocks(region.count), TOWER_THREADS>>>(held->coefficients, region,
                                                                            held->edge_table, edge->index_bits);
            ok = TOWER_TOOK(cudaGetLastError(), held->coefficients, error);
        }
        free(inverted);
    }
    return ok;
}

extern "C" long tower_lift(const TowerLiftRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_REFUSED;
    }
    EngineError *const error = request->error;
    if (!TOWER_HELD((request->device_lanes != NULL) && (request->coefficients != NULL) && (request->scratch != NULL)
                        && (request->floors != NULL),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    TowerHeld *const held = &s_tower_held;
    if (!TOWER_HELD(lanes != 0ull, request->extent, error, ENGINE_ERROR_REQUEST)
        || (tower_hold((size_t)lanes, error) == 0))
    {
        return TOWER_REFUSED;
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    if (tower_edge_check(request->edges, request->edge_count, (unsigned int)floors.size(), error) == 0)
    {
        return TOWER_REFUSED;
    }
    int ok = TOWER_TOOK(cudaMemset(held->flag, 0, sizeof(unsigned int)), held->flag, error);
    if (ok != 0)
    {
        tower_widen_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(request->device_lanes, lanes, held->coefficients);
        ok = TOWER_TOOK(cudaGetLastError(), held->coefficients, error);
    }
    // floor 0 stands before the first lifting level
    ok = ok && tower_edge_run(request->edges, request->edge_count, floors, request->extent, 0u, 0, error);
    for (size_t level = 0u; (ok != 0) && (level < floors.size()); level += 1u)
    {
        for (unsigned int axis = 0u; (ok != 0) && (axis < 4u); axis += 1u)
        {
            TowerStep step = floors[level];
            if (step.extent[axis] < 2ull)
            {
                continue;
            }
            step.axis = axis;
            tower_forward_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(held->coefficients, held->scratch, step,
                                                                              held->flag);
            tower_copy_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(held->scratch, held->coefficients, step);
            ok = TOWER_TOOK(cudaGetLastError(), held->coefficients, error);
        }
        // the edge for the next floor is laid on the approximation this level just produced
        ok = ok && tower_edge_run(request->edges, request->edge_count, floors, request->extent,
                                  (unsigned int)(level + 1u), 0, error);
    }
    unsigned int overflow = 1u;
    ok = ok && TOWER_TOOK(cudaMemcpy(&overflow, held->flag, sizeof(unsigned int), cudaMemcpyDeviceToHost), &overflow, error)
      && TOWER_HELD(overflow == 0u, &overflow, error, ENGINE_ERROR_REQUEST);
    if (ok == 0)
    {
        return TOWER_REFUSED;
    }
    *request->coefficients = held->coefficients;
    *request->scratch = (unsigned int *)held->scratch;
    *request->floors = (unsigned int)floors.size();
    return 0L;
}

extern "C" long tower_room(const unsigned long long extent[4], int **coefficients, EngineError *error)
{
    if (error == NULL)
    {
        return TOWER_REFUSED;
    }
    if (!TOWER_HELD((extent != NULL) && (coefficients != NULL), &coefficients, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    const unsigned long long lanes = tower_lanes(extent);
    if (!TOWER_HELD(lanes != 0ull, extent, error, ENGINE_ERROR_REQUEST) || (tower_hold((size_t)lanes, error) == 0))
    {
        return TOWER_REFUSED;
    }
    *coefficients = s_tower_held.coefficients;
    return 0L;
}

extern "C" long tower_lower(const TowerLowerRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_REFUSED;
    }
    EngineError *const error = request->error;
    if (!TOWER_HELD((request->mismatches != NULL) && (request->device_rebuilt != NULL), request, error,
                    ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    TowerHeld *const held = &s_tower_held;
    if (!TOWER_HELD((lanes != 0ull) && (lanes <= held->lanes), request->extent, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    if (tower_edge_check(request->edges, request->edge_count, (unsigned int)floors.size(), error) == 0)
    {
        return TOWER_REFUSED;
    }
    // the collapsed floor's edge is undone first, then each level and the edge that preceded it, in reverse
    int ok = tower_edge_run(request->edges, request->edge_count, floors, request->extent, (unsigned int)floors.size(),
                            1, error);
    for (size_t level = floors.size(); (ok != 0) && (level > 0u); level -= 1u)
    {
        for (unsigned int axis = 4u; (ok != 0) && (axis > 0u); axis -= 1u)
        {
            TowerStep step = floors[level - 1u];
            if (step.extent[axis - 1u] < 2ull)
            {
                continue;
            }
            step.axis = axis - 1u;
            tower_inverse_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(held->coefficients, held->scratch, step);
            tower_copy_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(held->scratch, held->coefficients, step);
            ok = TOWER_TOOK(cudaGetLastError(), held->coefficients, error);
        }
        // undo the edge that stood before this level's lifting on the lift pass
        ok = ok && tower_edge_run(request->edges, request->edge_count, floors, request->extent,
                                  (unsigned int)(level - 1u), 1, error);
    }
    ok = ok && TOWER_TOOK(cudaMemset(held->mismatches, 0, sizeof(unsigned long long)), held->mismatches, error);
    if ((ok != 0) && (request->device_lanes != NULL))
    {
        tower_differ_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(held->coefficients, request->device_lanes, lanes,
                                                                   held->mismatches);
        ok = TOWER_TOOK(cudaGetLastError(), held->mismatches, error);
    }
    ok = ok
      && TOWER_TOOK(cudaMemcpy(request->mismatches, held->mismatches, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                    request->mismatches, error);
    // the scratch holds lanes ints, so its first half holds the lanes' 16-bit narrowing with room to spare
    unsigned short *const narrowed = (unsigned short *)held->scratch;
    unsigned int outside = 1u;
    ok = ok && TOWER_TOOK(cudaMemset(held->flag, 0, sizeof(unsigned int)), held->flag, error);
    if (ok != 0)
    {
        tower_narrow_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(held->coefficients, lanes, narrowed, held->flag);
        ok = TOWER_TOOK(cudaGetLastError(), narrowed, error);
    }
    ok = ok && TOWER_TOOK(cudaMemcpy(&outside, held->flag, sizeof(unsigned int), cudaMemcpyDeviceToHost), &outside, error)
      && TOWER_HELD(outside == 0u, &outside, error, ENGINE_ERROR_LOGIC);
    if ((ok != 0) && (request->rebuilt != NULL))
    {
        ok = TOWER_TOOK(cudaMemcpy(request->rebuilt, narrowed, (size_t)lanes * sizeof(unsigned short),
                                   cudaMemcpyDeviceToHost),
                        request->rebuilt, error);
    }
    if (ok == 0)
    {
        return TOWER_REFUSED;
    }
    *request->device_rebuilt = narrowed;
    return 0L;
}
