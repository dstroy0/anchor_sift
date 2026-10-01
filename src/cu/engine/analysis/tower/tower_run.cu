// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tower_run.cu: holding, edges, lifting and lowering
#include "tower_internal.h"

static int tower_reserve(size_t lanes, EngineError *error)
{
    TowerResident *const resident = &g_tower_resident;
    if (lanes <= resident->lanes)
    {
        return 1;
    }
    device_pool_release(&resident->pool);
    resident->coefficients = NULL;
    resident->scratch = NULL;
    resident->flag = NULL;
    resident->mismatches = NULL;
    resident->lanes = 0u;
    DevicePoolTakeRequest takes[TOWER_SLICES];
    const DevicePoolPlan plan = tower_plan(lanes, error, takes);
    const DevicePoolReserveRequest reserve = {&plan, &resident->pool, error};
    int ok = device_pool_reserve(&reserve) == 0L;
    // the slices are taken in the plan's order. Each lands where the plan laid it out and none errors
    for (unsigned int at = 0u; (ok != 0) && (at < TOWER_SLICES); at += 1u)
    {
        ok = device_pool_take(&takes[at]) == 0L;
    }
    resident->lanes = (ok != 0) ? lanes : 0u;
    return ok;
}

extern "C" unsigned long long tower_reserve_bytes(unsigned long long lanes)
{
    // past 2^60 lanes the two int slices alone pass the plan's 2^62 bytes, which spoils it; errored here before the
    // product could wrap
    if ((lanes == 0ull) || (lanes > (1ull << 60u)))
    {
        return 0ull;
    }
    DevicePoolTakeRequest takes[TOWER_SLICES];
    // a size_t holds 64 bits, which device_pool asserts. The lane count converts exactly
    const DevicePoolPlan plan = tower_plan((size_t)lanes, NULL, takes);
    return device_pool_plan_bytes(&plan);
}

unsigned long long tower_lanes(const unsigned long long *extent)
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
        if (!TOWER_CHECK((edge->forward != NULL) && (edge->index_bits >= 1u) &&
                             (edge->index_bits <= TOWER_EDGE_INDEX_BITS_MAX) && (edge->floor <= levels),
                         edge, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        const unsigned long long entries = 1ull << edge->index_bits;
        unsigned char *const seen = (unsigned char *)calloc((size_t)entries, sizeof(unsigned char));
        if (!TOWER_CHECK(seen != NULL, edge, error, ENGINE_ERROR_RESOURCE))
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
        if (!TOWER_CHECK(permutation != 0, edge, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
    }
    return 1;
}

static void tower_active_extent(const std::vector<TowerStep> &floors, const unsigned long long *extent,
                                unsigned int slot, unsigned long long out[4])
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
    TowerResident *const resident = &g_tower_resident;
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
    // a lift walks a slot's edges in array order, a lower walks them in reverse. A slot inverts as a stack
    for (unsigned int scan = 0u; (ok != 0) && (scan < edge_count); scan += 1u)
    {
        const unsigned int at = (inverse != 0) ? (edge_count - 1u - scan) : scan;
        const TowerEdge *const edge = &edges[at];
        if (edge->floor != slot)
        {
            continue;
        }
        const unsigned long long entries = 1ull << edge->index_bits;
        if (tower_edge_reserve((unsigned int)entries, error) == 0)
        {
            return 0;
        }
        const unsigned int *upload = edge->forward;
        unsigned int *inverted = NULL;
        if (inverse != 0)
        {
            inverted = (unsigned int *)malloc((size_t)entries * sizeof(unsigned int));
            if (!TOWER_CHECK(inverted != NULL, edge, error, ENGINE_ERROR_RESOURCE))
            {
                return 0;
            }
            for (unsigned long long index = 0ull; index < entries; index += 1ull)
            {
                inverted[edge->forward[index]] = (unsigned int)index;
            }
            upload = inverted;
        }
        ok = TOWER_STATUS_CHECK(
            cudaMemcpy(resident->edge_table, upload, (size_t)entries * sizeof(unsigned int), cudaMemcpyHostToDevice),
            resident->edge_table, error);
        if (ok != 0)
        {
            tower_edge_kernel<<<tower_blocks(region.count), TOWER_THREADS>>>(resident->coefficients, region,
                                                                             resident->edge_table, edge->index_bits);
            ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->coefficients, error);
        }
        free(inverted);
    }
    return ok;
}

extern "C" long tower_lift(const TowerLiftRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_ERROR;
    }
    EngineError *const error = request->error;
    if (!TOWER_CHECK(((request->device_lanes != NULL) || (request->device_values != NULL)) &&
                         (request->coefficients != NULL) && (request->scratch != NULL) && (request->floors != NULL),
                     request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    TowerResident *const resident = &g_tower_resident;
    if (!TOWER_CHECK(lanes != 0ull, request->extent, error, ENGINE_ERROR_REQUEST) ||
        (tower_reserve((size_t)lanes, error) == 0))
    {
        return TOWER_ERROR;
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    if (tower_edge_check(request->edges, request->edge_count, (unsigned int)floors.size(), error) == 0)
    {
        return TOWER_ERROR;
    }
    int ok = TOWER_STATUS_CHECK(cudaMemset(resident->flag, 0, sizeof(unsigned int)), resident->flag, error);
    if ((ok != 0) && (request->device_values != NULL))
    {
        tower_take_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(request->device_values, lanes, resident->coefficients,
                                                                  resident->flag);
        ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->coefficients, error);
    }
    else if (ok != 0)
    {
        tower_widen_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(request->device_lanes, lanes,
                                                                   resident->coefficients);
        ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->coefficients, error);
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
            tower_forward_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(resident->coefficients, resident->scratch,
                                                                              step, resident->flag);
            tower_copy_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(resident->scratch, resident->coefficients,
                                                                           step);
            ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->coefficients, error);
        }
        // the edge for the next floor is laid out on the approximation this level just produced
        ok = ok && tower_edge_run(request->edges, request->edge_count, floors, request->extent,
                                  (unsigned int)(level + 1u), 0, error);
    }
    unsigned int overflow = 1u;
    ok = ok &&
         TOWER_STATUS_CHECK(cudaMemcpy(&overflow, resident->flag, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                            &overflow, error) &&
         TOWER_CHECK(overflow == 0u, &overflow, error, ENGINE_ERROR_REQUEST);
    if (ok == 0)
    {
        return TOWER_ERROR;
    }
    *request->coefficients = resident->coefficients;
    *request->scratch = (unsigned int *)resident->scratch;
    *request->floors = (unsigned int)floors.size();
    return 0L;
}

extern "C" long tower_capacity(const unsigned long long extent[4], int **coefficients, EngineError *error)
{
    if (error == NULL)
    {
        return TOWER_ERROR;
    }
    if (!TOWER_CHECK((extent != NULL) && (coefficients != NULL), &coefficients, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    const unsigned long long lanes = tower_lanes(extent);
    if (!TOWER_CHECK(lanes != 0ull, extent, error, ENGINE_ERROR_REQUEST) || (tower_reserve((size_t)lanes, error) == 0))
    {
        return TOWER_ERROR;
    }
    *coefficients = g_tower_resident.coefficients;
    return 0L;
}

extern "C" long tower_lower(const TowerLowerRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_ERROR;
    }
    EngineError *const error = request->error;
    if (!TOWER_CHECK((request->mismatches != NULL) && (request->device_rebuilt != NULL), request, error,
                     ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    TowerResident *const resident = &g_tower_resident;
    if (!TOWER_CHECK((lanes != 0ull) && (lanes <= resident->lanes), request->extent, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    if (tower_edge_check(request->edges, request->edge_count, (unsigned int)floors.size(), error) == 0)
    {
        return TOWER_ERROR;
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
            tower_inverse_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(resident->coefficients, resident->scratch,
                                                                              step);
            tower_copy_kernel<<<tower_blocks(step.count), TOWER_THREADS>>>(resident->scratch, resident->coefficients,
                                                                           step);
            ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->coefficients, error);
        }
        // undo the edge that stood before this level's lifting on the lift pass
        ok = ok && tower_edge_run(request->edges, request->edge_count, floors, request->extent,
                                  (unsigned int)(level - 1u), 1, error);
    }
    ok = ok && TOWER_STATUS_CHECK(cudaMemset(resident->mismatches, 0, sizeof(unsigned long long)), resident->mismatches,
                                  error);
    if ((ok != 0) && (request->device_lanes != NULL))
    {
        tower_differ_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(resident->coefficients, request->device_lanes,
                                                                    lanes, resident->mismatches);
        ok = TOWER_STATUS_CHECK(cudaGetLastError(), resident->mismatches, error);
    }
    ok = ok && TOWER_STATUS_CHECK(cudaMemcpy(request->mismatches, resident->mismatches, sizeof(unsigned long long),
                                             cudaMemcpyDeviceToHost),
                                  request->mismatches, error);
    // the scratch holds lanes ints. Its first half holds the lanes' 16-bit narrowing with room to spare
    unsigned short *const narrowed = (unsigned short *)resident->scratch;
    unsigned int outside = 1u;
    ok = ok && TOWER_STATUS_CHECK(cudaMemset(resident->flag, 0, sizeof(unsigned int)), resident->flag, error);
    if (ok != 0)
    {
        tower_narrow_kernel<<<tower_blocks(lanes), TOWER_THREADS>>>(resident->coefficients, lanes, narrowed,
                                                                    resident->flag);
        ok = TOWER_STATUS_CHECK(cudaGetLastError(), narrowed, error);
    }
    ok = ok &&
         TOWER_STATUS_CHECK(cudaMemcpy(&outside, resident->flag, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                            &outside, error) &&
         TOWER_CHECK(outside == 0u, &outside, error, ENGINE_ERROR_LOGIC);
    if ((ok != 0) && (request->rebuilt != NULL))
    {
        ok = TOWER_STATUS_CHECK(
            cudaMemcpy(request->rebuilt, narrowed, (size_t)lanes * sizeof(unsigned short), cudaMemcpyDeviceToHost),
            request->rebuilt, error);
    }
    if (ok == 0)
    {
        return TOWER_ERROR;
    }
    *request->device_rebuilt = narrowed;
    return 0L;
}
