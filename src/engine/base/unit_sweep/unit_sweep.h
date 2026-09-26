// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef UNIT_SWEEP_H
#define UNIT_SWEEP_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define UNIT_SWEEP_REFUSED (-1L)

typedef struct
{
    const unsigned short *device_volume;
    const unsigned int *device_planes;
    unsigned int input_bits;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    unsigned int limbs;
    unsigned int *device_out;
    EngineError *error;
} UnitSweepRequest;

long unit_sweep_residual(const UnitSweepRequest *request);

typedef struct
{
    const unsigned int *device_left;
    const unsigned int *device_right;
    unsigned long long lanes;
    unsigned int limbs;
    unsigned long long *disagreements;
    EngineError *error;
} UnitSweepComparison;

long unit_sweep_lanes_compare(const UnitSweepComparison *comparison);

void unit_sweep_release(void);

#ifdef __cplusplus
}
#endif

#endif
