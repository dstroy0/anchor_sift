// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CONTACT_SIDE_H
#define CONTACT_SIDE_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CONTACT_SIDE_REFUSED (-1L)

#define CONTACT_SIDE_ONE 0u

#define CONTACT_SIDE_OTHER 1u

#define CONTACT_SIDE_MEMBERS 2u

#define CONTACT_SIDE_DIFFERENCE_STEPS (2u + (7u * ENGINE_AXES))

#define CONTACT_SIDE_DIFFERENCE_OUTPUTS ENGINE_AXES

#define CONTACT_SIDE_BEFORE 0u

#define CONTACT_SIDE_AFTER 1u

#define CONTACT_SIDE_KEPT_STEPS (1u + (3u * ENGINE_AXES) + (ENGINE_AXES - 1u) + 6u)

#define CONTACT_SIDE_DOT 0u

#define CONTACT_SIDE_KEPT 1u

#define CONTACT_SIDE_CROSSED 2u

#define CONTACT_SIDE_KEPT_OUTPUTS 3u

typedef struct
{
    unsigned int mass_field;
    unsigned int sum_field[ENGINE_AXES];
    unsigned long long voxel_pm[ENGINE_AXES];
} ContactSideDifferenceRequest;

typedef struct
{
    unsigned int difference_field[ENGINE_AXES];
} ContactSideKeptRequest;

long contact_side_difference_program(const ContactSideDifferenceRequest *request,
                                     EngineRecordStep program[CONTACT_SIDE_DIFFERENCE_STEPS],
                                     unsigned int outputs[CONTACT_SIDE_DIFFERENCE_OUTPUTS]);

long contact_side_kept_program(const ContactSideKeptRequest *request, EngineRecordStep program[CONTACT_SIDE_KEPT_STEPS],
                               unsigned int outputs[CONTACT_SIDE_KEPT_OUTPUTS]);

#ifdef __cplusplus
}
#endif

#endif
