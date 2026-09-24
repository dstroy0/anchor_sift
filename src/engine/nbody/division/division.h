// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DIVISION_H
#define DIVISION_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DIVISION_REFUSED (-1L)

#define DIVISION_PARENT 0u

#define DIVISION_CHILD 1u

#define DIVISION_SIBLING 2u

#define DIVISION_MEMBERS 3u

#define DIVISION_MOMENTS 6u

#define DIVISION_STEPS 100u

#define DIVISION_MASS_HOLDS 0u

#define DIVISION_AXIS_HOLDS 1u

#define DIVISION_BOTH_HOLD 2u

#define DIVISION_OUTPUTS 3u

typedef struct
{
    unsigned int mass_field;
    unsigned int sum_field[ENGINE_AXES];
    unsigned int moment_field[DIVISION_MOMENTS];
    unsigned long long voxel_pm[ENGINE_AXES];
} DivisionRequest;

long division_program(const DivisionRequest *request, EngineRecordStep program[DIVISION_STEPS],
                      unsigned int outputs[DIVISION_OUTPUTS]);

#ifdef __cplusplus
}
#endif

#endif
