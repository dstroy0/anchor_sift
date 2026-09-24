// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "fingerprint.h"

#include <string.h>

static const unsigned int FINGERPRINT_FIRST_AXIS[FINGERPRINT_MOMENTS] = {0u, 1u, 2u, 0u, 0u, 1u};

static const unsigned int FINGERPRINT_SECOND_AXIS[FINGERPRINT_MOMENTS] = {0u, 1u, 2u, 1u, 2u, 2u};

#define FINGERPRINT_MASS 0u

#define FINGERPRINT_SUMS 1u

#define FINGERPRINT_SECONDS 4u

#define FINGERPRINT_SCALES 10u

#define FINGERPRINT_ONE 13u

#define FINGERPRINT_MASS_BAND 14u

#define FINGERPRINT_MASS_SQUARE 15u

#define FINGERPRINT_PER_MOMENT 6u

static unsigned long long fingerprint_common_unit(unsigned long long first, unsigned long long second)
{
    unsigned long long larger = first;
    unsigned long long smaller = second;
    while (smaller != 0ull)
    {
        const unsigned long long rest = larger % smaller;
        larger = smaller;
        smaller = rest;
    }
    return larger;
}

static void fingerprint_step(EngineRecordStep *step, EngineRecordOperation operation, unsigned int left,
                             unsigned int right)
{
    step->operation = operation;
    step->left = left;
    step->right = right;
}

extern "C" long fingerprint_program(const FingerprintRequest *request, EngineRecordStep program[FINGERPRINT_STEPS],
                                    unsigned int outputs[FINGERPRINT_OUTPUTS])
{
    const unsigned long long unit = fingerprint_common_unit(
        fingerprint_common_unit(request->voxel_pm[0], request->voxel_pm[1]), request->voxel_pm[2]);
    if ((request->voxel_pm[0] == 0ull) || (request->voxel_pm[1] == 0ull) || (request->voxel_pm[2] == 0ull))
    {
        return FINGERPRINT_REFUSED;
    }
    memset(program, 0, FINGERPRINT_STEPS * sizeof(EngineRecordStep));
    fingerprint_step(&program[FINGERPRINT_MASS], ENGINE_RECORD_FIELD, request->mass_field, 0u);
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        fingerprint_step(&program[FINGERPRINT_SUMS + axis], ENGINE_RECORD_FIELD, request->sum_field[axis], 0u);
        const unsigned long long scale = request->voxel_pm[axis] / unit;
        fingerprint_step(&program[FINGERPRINT_SCALES + axis], ENGINE_RECORD_CONSTANT,
                         (unsigned int)(scale & 0xFFFFFFFFull), (unsigned int)(scale >> 32u));
    }
    for (unsigned int moment = 0u; moment < FINGERPRINT_MOMENTS; moment += 1u)
    {
        fingerprint_step(&program[FINGERPRINT_SECONDS + moment], ENGINE_RECORD_FIELD, request->moment_field[moment], 0u);
    }
    fingerprint_step(&program[FINGERPRINT_ONE], ENGINE_RECORD_CONSTANT, 1u, 0u);
    fingerprint_step(&program[FINGERPRINT_MASS_BAND], ENGINE_RECORD_LADDER, FINGERPRINT_MASS, FINGERPRINT_ONE);
    fingerprint_step(&program[FINGERPRINT_MASS_SQUARE], ENGINE_RECORD_PRODUCT, FINGERPRINT_MASS, FINGERPRINT_MASS);
    outputs[0] = FINGERPRINT_MASS_BAND;
    for (unsigned int moment = 0u; moment < FINGERPRINT_MOMENTS; moment += 1u)
    {
        const unsigned int first = FINGERPRINT_MASS_SQUARE + 1u + (FINGERPRINT_PER_MOMENT * moment);
        const unsigned int axis_one = FINGERPRINT_FIRST_AXIS[moment];
        const unsigned int axis_two = FINGERPRINT_SECOND_AXIS[moment];
        fingerprint_step(&program[first], ENGINE_RECORD_PRODUCT, FINGERPRINT_MASS, FINGERPRINT_SECONDS + moment);
        fingerprint_step(&program[first + 1u], ENGINE_RECORD_PRODUCT, FINGERPRINT_SUMS + axis_one,
                         FINGERPRINT_SUMS + axis_two);
        fingerprint_step(&program[first + 2u], ENGINE_RECORD_DIFFERENCE, first, first + 1u);
        fingerprint_step(&program[first + 3u], ENGINE_RECORD_PRODUCT, first + 2u, FINGERPRINT_SCALES + axis_one);
        fingerprint_step(&program[first + 4u], ENGINE_RECORD_PRODUCT, first + 3u, FINGERPRINT_SCALES + axis_two);
        fingerprint_step(&program[first + 5u], ENGINE_RECORD_LADDER, first + 4u, FINGERPRINT_MASS_SQUARE);
        outputs[1u + moment] = first + 5u;
    }
    return (long)FINGERPRINT_STEPS;
}
