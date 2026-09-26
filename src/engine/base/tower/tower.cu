// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tower.h"

#include "device_pool.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#include <utility>
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

__global__ static void tower_take_kernel(const int *values, unsigned long long count, int *to, unsigned int *overflow)
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

// the coefficients, the scratch, the flag and the mismatch count are slices of one pool, held for the most lanes asked
// so far; the edge table grows apart, only when an edge is laid
struct TowerHeld
{
    DevicePool pool;
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

#define TOWER_SLICES 4u

// the pool's slices for `lanes`, in the order they are laid and taken: the coefficients, the scratch, the flag and the
// mismatch count; the plan is laid from them, and a pool held from it takes them
static DevicePoolPlan tower_plan(size_t lanes, EngineError *error, DevicePoolTakeRequest takes[TOWER_SLICES])
{
    TowerHeld *const held = &s_tower_held;
    const DevicePoolTakeRequest laid[TOWER_SLICES] = {
        {&held->pool, lanes * sizeof(int), (void **)&held->coefficients, error},
        {&held->pool, lanes * sizeof(int), (void **)&held->scratch, error},
        {&held->pool, sizeof(unsigned int), (void **)&held->flag, error},
        {&held->pool, sizeof(unsigned long long), (void **)&held->mismatches, error}};
    DevicePoolPlan plan = {0ull, 0ull, 0};
    for (unsigned int at = 0u; at < TOWER_SLICES; at += 1u)
    {
        takes[at] = laid[at];
        device_pool_plan_slice(&plan, laid[at].bytes);
    }
    return plan;
}

static int tower_hold(size_t lanes, EngineError *error)
{
    TowerHeld *const held = &s_tower_held;
    if (lanes <= held->lanes)
    {
        return 1;
    }
    device_pool_release(&held->pool);
    held->coefficients = NULL;
    held->scratch = NULL;
    held->flag = NULL;
    held->mismatches = NULL;
    held->lanes = 0u;
    DevicePoolTakeRequest takes[TOWER_SLICES];
    const DevicePoolPlan plan = tower_plan(lanes, error, takes);
    const DevicePoolHoldRequest hold = {&plan, &held->pool, error};
    int ok = device_pool_hold(&hold) == 0L;
    // the slices are taken in the plan's order, so each lands where the plan laid it and none is refused
    for (unsigned int at = 0u; (ok != 0) && (at < TOWER_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    held->lanes = (ok != 0) ? lanes : 0u;
    return ok;
}

extern "C" unsigned long long tower_hold_bytes(unsigned long long lanes)
{
    // past 2^60 lanes the two int slices alone pass the plan's 2^62 bytes, which spoils it; refused here before the
    // product could wrap
    if ((lanes == 0ull) || (lanes > (1ull << 60u)))
    {
        return 0ull;
    }
    DevicePoolTakeRequest takes[TOWER_SLICES];
    // a size_t holds 64 bits, which device_pool asserts, so the lane count converts exactly
    const DevicePoolPlan plan = tower_plan((size_t)lanes, NULL, takes);
    return device_pool_plan_bytes(&plan);
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
    if (!TOWER_HELD(((request->device_lanes != NULL) || (request->device_values != NULL))
                        && (request->coefficients != NULL) && (request->scratch != NULL) && (request->floors != NULL),
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
    if ((ok != 0) && (request->device_values != NULL))
    {
        tower_take_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(request->device_values, lanes, held->coefficients,
                                                                  held->flag);
        ok = TOWER_TOOK(cudaGetLastError(), held->coefficients, error);
    }
    else if (ok != 0)
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

// the ruleset tower_forward_kernel and tower_inverse_kernel run: the highs less floor((x_2j + x_(2j+2)) / 2), then the
// lows plus floor((d_(j-1) + d_j + 2) / 4)
static const TowerLiftingStep s_tower_five_three[2] = {{TOWER_BAND_HIGH, -1, 2u, {0, 1}, {1, 1}, 0u, 1u},
                                                       {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

// the record floors' writer: every step is counted, and written only where the caller's program is held. Each
// constant is laid once, where it is first read, and its register kept beside its value.
struct TowerRecordEmit
{
    EngineRecordStep *steps;
    unsigned long long count;
    std::vector<std::pair<unsigned long long, unsigned int>> constants;
};

static unsigned int tower_record_emit(TowerRecordEmit *emit, EngineRecordOperation operation, unsigned int left,
                                      unsigned int right)
{
    if (emit->steps != NULL)
    {
        emit->steps[emit->count] = EngineRecordStep{operation, left, right, 0u};
    }
    emit->count += 1ull;
    // a program is written only once its count is held to 2^32 - 1, and a counted name past that is refused unread
    return (unsigned int)(emit->count - 1ull);
}

static unsigned int tower_record_constant(TowerRecordEmit *emit, unsigned long long value)
{
    for (const std::pair<unsigned long long, unsigned int> &held : emit->constants)
    {
        if (held.first == value)
        {
            return held.second;
        }
    }
    // a constant step holds its value's low 32 bits in `left` and its high 32 in `right`
    const unsigned int laid = tower_record_emit(emit, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull),
                                                (unsigned int)(value >> 32u));
    emit->constants.push_back(std::pair<unsigned long long, unsigned int>(value, laid));
    return laid;
}

// floor(v / 2^shift), toward minus infinity as tower_floor_shift: v's residue, the and with 2^shift - 1, is never
// negative, and v less it divides exactly
static unsigned int tower_record_floor_shift(TowerRecordEmit *emit, unsigned int value, unsigned int shift)
{
    if (shift == 0u)
    {
        return value;
    }
    const unsigned int mask = tower_record_constant(emit, (1ull << shift) - 1ull);
    const unsigned int residue = tower_record_emit(emit, ENGINE_RECORD_AND, value, mask);
    const unsigned int whole = tower_record_emit(emit, ENGINE_RECORD_DIFFERENCE, value, residue);
    return tower_record_emit(emit, ENGINE_RECORD_EXACT_QUOTIENT, whole, tower_record_constant(emit, 1ull << shift));
}

// one lifting step over a band: each value moves by sign * floor((rounding + sum_k weight_k * other[a + offset_k]) /
// 2^shift), an index past either end of the other band taken at that end, and `undo` turns the sign
static void tower_record_lifting_step(TowerRecordEmit *emit, const TowerLiftingStep &rule, int undo,
                                      std::vector<unsigned int> &target, const std::vector<unsigned int> &other)
{
    // both bands of a lifted line hold at least one value, and far fewer than 2^31
    const long long last = (long long)other.size() - 1ll;
    for (size_t at = 0u; at < target.size(); at += 1u)
    {
        unsigned int sum = 0u;
        int summed = 0;
        if (rule.rounding != 0u)
        {
            sum = tower_record_constant(emit, rule.rounding);
            summed = 1;
        }
        for (unsigned int tap = 0u; tap < rule.taps; tap += 1u)
        {
            const long long wanted = (long long)at + (long long)rule.offset[tap];
            const long long taken = (wanted < 0ll) ? 0ll : ((wanted > last) ? last : wanted);
            unsigned int term = other[(size_t)taken];
            // a weight is never INT_MIN, so its magnitude is an int
            const unsigned int magnitude = (unsigned int)((rule.weight[tap] < 0) ? -rule.weight[tap] : rule.weight[tap]);
            if (magnitude != 1u)
            {
                term = tower_record_emit(emit, ENGINE_RECORD_PRODUCT, term, tower_record_constant(emit, magnitude));
            }
            if (summed == 0)
            {
                sum = (rule.weight[tap] > 0) ? term
                                             : tower_record_emit(emit, ENGINE_RECORD_DIFFERENCE,
                                                                 tower_record_constant(emit, 0ull), term);
                summed = 1;
            }
            else
            {
                sum = tower_record_emit(emit, (rule.weight[tap] > 0) ? ENGINE_RECORD_SUM : ENGINE_RECORD_DIFFERENCE, sum,
                                        term);
            }
        }
        const unsigned int moved = tower_record_floor_shift(emit, sum, rule.shift);
        const int adds = (rule.sign > 0) != (undo != 0);
        target[at] = tower_record_emit(emit, adds ? ENGINE_RECORD_SUM : ENGINE_RECORD_DIFFERENCE, target[at], moved);
    }
}

// one level along one line of `length` values, or its undoing. Lifting splits the line into its evens, the lows,
// and its odds, the highs, runs the ruleset's steps in order and lays the lows first and the highs after them, as
// tower_forward_kernel lays them; lowering reads the two bands back from there, runs the steps last first with each
// sign turned, and interleaves them again, as tower_inverse_kernel does.
static void tower_record_line(TowerRecordEmit *emit, const TowerLiftingStep *rules, unsigned int rule_count,
                              std::vector<unsigned int> &registers, unsigned long long line, unsigned long long stride,
                              unsigned long long length, int inverse)
{
    const unsigned long long lows = (length + 1ull) / 2ull;
    const unsigned long long highs = length / 2ull;
    // a band's k-th value sits at 2k or 2k + 1 along the interleaved line, and at k or lows + k along the lifted one
    std::vector<unsigned int> low((size_t)lows);
    std::vector<unsigned int> high((size_t)highs);
    for (unsigned long long k = 0ull; k < lows; k += 1ull)
    {
        low[(size_t)k] = registers[(size_t)(line + (((inverse != 0) ? k : (2ull * k)) * stride))];
    }
    for (unsigned long long k = 0ull; k < highs; k += 1ull)
    {
        high[(size_t)k] = registers[(size_t)(line + (((inverse != 0) ? (lows + k) : ((2ull * k) + 1ull)) * stride))];
    }
    for (unsigned int walked = 0u; walked < rule_count; walked += 1u)
    {
        const TowerLiftingStep &rule = rules[(inverse != 0) ? (rule_count - 1u - walked) : walked];
        if (rule.target == TOWER_BAND_HIGH)
        {
            tower_record_lifting_step(emit, rule, inverse, high, low);
        }
        else
        {
            tower_record_lifting_step(emit, rule, inverse, low, high);
        }
    }
    for (unsigned long long k = 0ull; k < lows; k += 1ull)
    {
        registers[(size_t)(line + (((inverse != 0) ? (2ull * k) : k) * stride))] = low[(size_t)k];
    }
    for (unsigned long long k = 0ull; k < highs; k += 1ull)
    {
        registers[(size_t)(line + (((inverse != 0) ? ((2ull * k) + 1ull) : (lows + k)) * stride))] = high[(size_t)k];
    }
}

// the first position of every line along `axis` in a level's active region, in t, z, y, x order
static std::vector<unsigned long long> tower_record_lines(const TowerStep &step, unsigned int axis)
{
    unsigned long long across[4];
    unsigned long long lines = 1ull;
    for (unsigned int each = 0u; each < 4u; each += 1u)
    {
        across[each] = (each == axis) ? 1ull : step.extent[each];
        lines *= across[each];
    }
    std::vector<unsigned long long> first((size_t)lines);
    for (unsigned long long index = 0ull; index < lines; index += 1ull)
    {
        unsigned long long rest = index;
        unsigned long long offset = 0ull;
        for (unsigned int each = 4u; each > 0u; each -= 1u)
        {
            offset += (rest % across[each - 1u]) * step.stride[each - 1u];
            rest /= across[each - 1u];
        }
        first[(size_t)index] = offset;
    }
    return first;
}

// T, or T^-1 run from the last level and axis back, over a block's registers in place: the levels and axes
// tower_lift and tower_lower walk, each axis whose active extent is 2 or more
static void tower_record_build(TowerRecordEmit *emit, const TowerLiftingStep *rules, unsigned int rule_count,
                               const std::vector<TowerStep> &floors, std::vector<unsigned int> &registers, int inverse)
{
    const size_t levels = floors.size();
    for (size_t walked = 0u; walked < levels; walked += 1u)
    {
        const TowerStep &step = floors[(inverse != 0) ? (levels - 1u - walked) : walked];
        for (unsigned int turn = 0u; turn < 4u; turn += 1u)
        {
            const unsigned int axis = (inverse != 0) ? (3u - turn) : turn;
            if (step.extent[axis] < 2ull)
            {
                continue;
            }
            for (const unsigned long long line : tower_record_lines(step, axis))
            {
                tower_record_line(emit, rules, rule_count, registers, line, step.stride[axis], step.extent[axis],
                                  inverse);
            }
        }
    }
}

static long tower_record_run(const TowerRecordRequest *request, int inverse)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_REFUSED;
    }
    EngineError *const error = request->error;
    if (!TOWER_HELD((request->in_registers != NULL) && (request->out_registers != NULL) && (request->count != NULL),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    if (!TOWER_HELD((lanes != 0ull) && (lanes <= 0xFFFFFFFFull), request->extent, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    // no ruleset named is the kernels' 5/3
    const int named_rules = (request->rules != NULL) || (request->rule_count != 0u);
    const TowerLiftingStep *const rules = (named_rules != 0) ? request->rules : s_tower_five_three;
    const unsigned int rule_count = (named_rules != 0) ? request->rule_count : 2u;
    if (!TOWER_HELD((rules != NULL) && (rule_count != 0u), request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    for (unsigned int at = 0u; at < rule_count; at += 1u)
    {
        const TowerLiftingStep *const rule = &rules[at];
        int held = ((rule->target == TOWER_BAND_LOW) || (rule->target == TOWER_BAND_HIGH))
                && ((rule->sign == 1) || (rule->sign == -1)) && (rule->taps >= 1u) && (rule->taps <= TOWER_RULE_TAPS_MOST)
                && (rule->shift <= TOWER_RULE_SHIFT_MOST);
        for (unsigned int tap = 0u; (held != 0) && (tap < rule->taps); tap += 1u)
        {
            // a weight's magnitude is an int, so INT_MIN is refused with 0
            held = (rule->weight[tap] != 0) && (rule->weight[tap] != INT_MIN);
        }
        if (!TOWER_HELD(held, rule, error, ENGINE_ERROR_REQUEST))
        {
            return TOWER_REFUSED;
        }
    }
    const unsigned int start = *request->count;
    std::vector<unsigned int> registers((size_t)lanes);
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        // a value the block reads is an earlier step's register
        if (!TOWER_HELD(request->in_registers[lane] < start, &request->in_registers[lane], error, ENGINE_ERROR_REQUEST))
        {
            return TOWER_REFUSED;
        }
        registers[(size_t)lane] = request->in_registers[lane];
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    // counted first, so a program its step names or the caller's room cannot hold is refused before a step is written
    TowerRecordEmit counted = {NULL, start, {}};
    std::vector<unsigned int> named = registers;
    tower_record_build(&counted, rules, rule_count, floors, named, inverse);
    if (!TOWER_HELD((counted.count <= 0xFFFFFFFFull)
                        && ((request->steps == NULL) || (counted.count <= (unsigned long long)request->step_room)),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_REFUSED;
    }
    if (request->steps != NULL)
    {
        TowerRecordEmit written = {request->steps, start, {}};
        tower_record_build(&written, rules, rule_count, floors, registers, inverse);
    }
    memcpy(request->out_registers, named.data(), (size_t)lanes * sizeof(unsigned int));
    // the count was held to 2^32 - 1 above, so it narrows to the program's next step exactly
    *request->count = (unsigned int)counted.count;
    return 0L;
}

extern "C" long tower_record_lift(const TowerRecordRequest *request)
{
    return tower_record_run(request, 0);
}

extern "C" long tower_record_lower(const TowerRecordRequest *request)
{
    return tower_record_run(request, 1);
}
