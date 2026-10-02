// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tower_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef TOWER_INTERNAL_H
#define TOWER_INTERNAL_H

#include "../../../../c/engine/analysis/tower/tower.h"

#include "../../../../c/engine/runtime/device_pool/device_pool.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#include <utility>
#include <vector>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define TOWER_STATUS_CHECK(call_, evacaddr_, error_)                                                                   \
    engine_status_check((int)(call_), ENGINE_MODULE_TOWER, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define TOWER_CHECK(condition_, evacaddr_, error_, kind_)                                                              \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_TOWER, (unsigned int)__LINE__, (const void *)(evacaddr_),  \
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

__global__ void tower_forward_kernel(const int *from, int *to, TowerStep step, unsigned int *overflow);

__global__ void tower_inverse_kernel(const int *from, int *to, TowerStep step);

__global__ void tower_copy_kernel(const int *from, int *to, TowerStep step);

__global__ void tower_edge_kernel(int *state, TowerStep region, const unsigned int *table, unsigned int index_bits);

__global__ void tower_widen_kernel(const unsigned short *lanes, unsigned long long count, int *to);

__global__ void tower_take_kernel(const int *values, unsigned long long count, int *to, unsigned int *overflow);

__global__ void tower_differ_kernel(const int *rebuilt, const unsigned short *lanes, unsigned long long count,
                                    unsigned long long *mismatches);

__global__ void tower_narrow_kernel(const int *rebuilt, unsigned long long count, unsigned short *to,
                                    unsigned int *outside);

unsigned int tower_blocks(unsigned long long count);

std::vector<TowerStep> tower_floors(const unsigned long long *extent);

// the coefficients, the scratch, the flag and the mismatch count are slices of one pool, sized for the most lanes asked
// so far; the edge table grows apart, only when an edge is laid out
struct TowerResident
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

extern TowerResident g_tower_resident;

int tower_edge_reserve(unsigned int entries, EngineError *error);

#define TOWER_SLICES 4u

DevicePoolPlan tower_plan(size_t lanes, EngineError *error, DevicePoolTakeRequest takes[TOWER_SLICES]);

unsigned long long tower_lanes(const unsigned long long *extent);

// the record floors' writer: every step is counted, and written only where the caller's program is held. Each
// constant is laid out once, where it is first read, and its register kept beside its value.
struct TowerRecordBuilder
{
    EngineRecordStep *steps;
    unsigned long long count;
    std::vector<std::pair<unsigned long long, unsigned int>> constants;
};

#endif
