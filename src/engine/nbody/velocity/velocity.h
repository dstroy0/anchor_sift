// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef VELOCITY_H
#define VELOCITY_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VELOCITY_REFUSED (-1L)

#define VELOCITY_EARLIER 0u

#define VELOCITY_LATER 1u

#define VELOCITY_LAG 2u

#define VELOCITY_MEMBERS 3u

#define VELOCITY_PER_AXIS 12u

#define VELOCITY_STEPS (4u + (VELOCITY_PER_AXIS * ENGINE_AXES) + 2u)

#define VELOCITY_CHANGE 0u

#define VELOCITY_DENOMINATOR ENGINE_AXES

#define VELOCITY_AGREES (ENGINE_AXES + 1u)

#define VELOCITY_ALL_AGREE ((2u * ENGINE_AXES) + 1u)

#define VELOCITY_OUTPUTS ((2u * ENGINE_AXES) + 2u)

typedef struct
{
    unsigned int mass_field;
    unsigned int sum_field[ENGINE_AXES];
    unsigned int lag_field[ENGINE_AXES];
} VelocityRequest;

long velocity_program(const VelocityRequest *request, EngineRecordStep program[VELOCITY_STEPS],
                      unsigned int outputs[VELOCITY_OUTPUTS]);

#ifdef __cplusplus
}
#endif

#endif
