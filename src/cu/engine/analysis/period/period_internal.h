// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the period_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef PERIOD_INTERNAL_H
#define PERIOD_INTERNAL_H

#include "../../../../c/engine/analysis/period/period.h"

#include "../../../../c/engine/runtime/device_pool/device_pool.h"
#include "../../../../c/engine/runtime/scriptura/scriptura.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define PERIOD_STATUS_CHECK(call_, evacaddr_, error_)                                                                  \
    engine_status_check((int)(call_), ENGINE_MODULE_PERIOD, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define PERIOD_CHECK(condition_, evacaddr_, error_, kind_)                                                             \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_PERIOD, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define PERIOD_THREADS 256u

#define PERIOD_VALUES 65536u

#define PERIOD_GRID_ROWS_MAX 65535u

#define PERIOD_VOXELS_MAX 0xFFFFFFFFull

#define PERIOD_LOW_HALF 0xFFFFFFFFull

#define PERIOD_ROUNDS 4u

#define PERIOD_SEED_WORDS 4u

#define PERIOD_ROW_TEXT 576ull

static_assert((PERIOD_SEED_WORDS * 8u) == ENGINE_SIGNUM_BYTES, "period: the seed words must cover the content signum");

typedef struct
{
    unsigned int rank;
    unsigned int extent[ENGINE_ARRAY_RANK];
    unsigned int stride[ENGINE_ARRAY_RANK];
    unsigned int usable[ENGINE_ARRAY_RANK];
    unsigned int pairs[ENGINE_ARRAY_RANK];
    unsigned long long first[ENGINE_ARRAY_RANK];
    unsigned long long lag_total;
    unsigned long long voxels;
} PeriodLattice;

typedef struct
{
    unsigned int keys[PERIOD_ROUNDS];
} PeriodShuffle;

typedef struct
{
    unsigned long long candidate;
    unsigned long long at;
    unsigned long long beside;
    unsigned long long doubled;
    unsigned long long beside_double;
    unsigned long long height;
} PeriodPeak;

typedef struct
{
    unsigned long long high;
    unsigned long long low;
} PeriodWide;

typedef struct
{
    const unsigned short *lanes;
    unsigned long long voxels;
    unsigned int columns;
    unsigned int *device_histogram;
    unsigned long long *device_agreement;
    unsigned int *histogram;
    unsigned long long *agreement;
    size_t agreement_entries;
} PeriodPass;

// the histogram, the agreement and the shuffled lanes are slices of one pool, kept after the call and sized for the
// most voxels and the most agreement entries asked so far
typedef struct
{
    DevicePool pool;
    unsigned int *histogram;
    unsigned long long *agreement;
    unsigned short *shuffled;
    unsigned long long voxels;
    unsigned long long entries;
} PeriodResident;

extern PeriodResident g_period_resident;

#define PERIOD_SLICES 3u

__global__ void period_histogram_kernel(const unsigned short *lanes, unsigned long long voxels,
                                        unsigned int *histogram);

__global__ void period_agreement_kernel(const unsigned short *lanes, PeriodLattice lattice,
                                        unsigned long long *agreement);

__global__ void period_line_shuffle_kernel(unsigned short *shuffled, PeriodShuffle shuffle, PeriodLattice lattice,
                                           unsigned int axis, unsigned long long lines);

int period_margin_compare(const void *one, const void *other);

void period_shuffle_fill(PeriodShuffle *shuffle, const EngineSignum *content, unsigned long long counter);

void period_strongest(const unsigned long long *same, PeriodAxis *axis);

int period_fundamental(const unsigned long long *same, const PeriodMargin *top, PeriodAxis *axis);

int period_reserve(unsigned long long voxels, unsigned long long entries, EngineError *error);

#endif
