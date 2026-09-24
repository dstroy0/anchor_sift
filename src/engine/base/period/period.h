// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PERIOD_H
#define PERIOD_H

#include "engine_config.h"

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PERIOD_REFUSED (-1L)

typedef struct
{
    unsigned long long numerator;
    unsigned long long denominator;
} PeriodMargin;

typedef struct
{
    unsigned long long extent;
    unsigned long long period;
    unsigned long long candidate;
    unsigned long long lags;
    unsigned long long pairs_per_lag;
    unsigned long long agreement_at_candidate;
    unsigned long long agreement_beside_candidate;
    unsigned long long agreement_at_double;
    unsigned long long agreement_beside_double;
    PeriodMargin margin;
    unsigned long long band_count;
    PeriodMargin band_bottom;
    PeriodMargin band_top;
} PeriodAxis;

typedef struct
{
    unsigned int rank;
    unsigned long long voxels;
    unsigned long long collisions;
    unsigned long long draws;
    PeriodAxis axis[ENGINE_ARRAY_RANK];
} PeriodReading;

typedef struct
{
    const unsigned short *device_lanes;
    unsigned int rank;
    unsigned long long shape[ENGINE_ARRAY_RANK];
    unsigned long long draws;
    EngineSignum content;
    const PeriodMargin *null_top;
    unsigned long long *agreement;
    unsigned long long agreement_room;
    PeriodMargin *band;
    unsigned long long band_room;
    PeriodReading *reading;
    EngineError *error;
} PeriodRequest;

unsigned long long period_agreement_entries(unsigned int rank, const unsigned long long *shape);

long period_read(const PeriodRequest *request);

long period_draw(const PeriodRequest *request, unsigned long long draw, PeriodMargin *heights);

int period_print(const PeriodReading *reading, FILE *file);

#ifdef __cplusplus
}
#endif

#endif
