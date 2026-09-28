// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the period_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef PERIOD_TEST_INTERNAL_H
#define PERIOD_TEST_INTERNAL_H

#include "period.h"

#include "device_pool.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define TEST_LOW_HALF 0xFFFFFFFFull

// the largest volume, 32 x 64 x 64, and the most agreement entries, the one-axis line's 4096 / 2
#define TEST_VOXELS_MAX (32ull * 64ull * 64ull)

#define TEST_ENTRIES_MAX 2048ull

#define TEST_RANDOM_VOLUMES 64u

#define TEST_DRAWS 8ull

#define TEST_SMOOTH_VOLUMES 16u

typedef struct
{
    unsigned long long high;
    unsigned long long low;
} TestWide;

unsigned long long test_next(void);

unsigned long long test_reference_counts(const unsigned short *volume, unsigned int rank,
                                         const unsigned long long *extent, unsigned long long *counts);

unsigned long long test_reference_select(const unsigned long long *same, unsigned long long lags,
                                         unsigned long long pairs, const PeriodMargin *top,
                                         unsigned long long *candidate_out, PeriodMargin *margin);

int test_read(const unsigned short *volume, unsigned int rank, const unsigned long long *extent,
              PeriodMeasurement *measurement, unsigned long long *counts, unsigned long long capacity,
              PeriodMargin *band, EngineError *error);

int test_band_valid(const PeriodAxis *axis, const PeriodMargin *band);

int test_draws_and_given_top(const unsigned short *volume, unsigned int rank, const unsigned long long *extent,
                             const PeriodMeasurement *measurement, const PeriodMargin *band);

#endif
