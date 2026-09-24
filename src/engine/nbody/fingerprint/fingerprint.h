// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef FINGERPRINT_H
#define FINGERPRINT_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define FINGERPRINT_REFUSED (-1L)

#define FINGERPRINT_MOMENTS 6u

#define FINGERPRINT_STEPS (16u + (6u * FINGERPRINT_MOMENTS))

#define FINGERPRINT_OUTPUTS (1u + FINGERPRINT_MOMENTS)

typedef struct
{
    unsigned int mass_field;
    unsigned int sum_field[3];
    unsigned int moment_field[FINGERPRINT_MOMENTS];
    unsigned long long voxel_pm[3];
} FingerprintRequest;

long fingerprint_program(const FingerprintRequest *request, EngineRecordStep program[FINGERPRINT_STEPS],
                         unsigned int outputs[FINGERPRINT_OUTPUTS]);

#ifdef __cplusplus
}
#endif

#endif
