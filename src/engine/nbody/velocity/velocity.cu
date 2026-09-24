// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "velocity.h"

#include <string.h>

#define VELOCITY_EARLIER_MASS 0u

#define VELOCITY_LATER_MASS 1u

#define VELOCITY_ONE 2u

#define VELOCITY_MASSES 3u

#define VELOCITY_AXIS_FIRST 4u

static void velocity_step(EngineRecordStep *step, EngineRecordOperation operation, unsigned int left, unsigned int right,
                          unsigned int member)
{
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = member;
}

extern "C" long velocity_program(const VelocityRequest *request, EngineRecordStep program[VELOCITY_STEPS],
                                 unsigned int outputs[VELOCITY_OUTPUTS])
{
    memset(program, 0, VELOCITY_STEPS * sizeof(EngineRecordStep));
    velocity_step(&program[VELOCITY_EARLIER_MASS], ENGINE_RECORD_FIELD, request->mass_field, 0u, VELOCITY_EARLIER);
    velocity_step(&program[VELOCITY_LATER_MASS], ENGINE_RECORD_FIELD, request->mass_field, 0u, VELOCITY_LATER);
    velocity_step(&program[VELOCITY_ONE], ENGINE_RECORD_CONSTANT, 1u, 0u, 0u);
    velocity_step(&program[VELOCITY_MASSES], ENGINE_RECORD_PRODUCT, VELOCITY_EARLIER_MASS, VELOCITY_LATER_MASS, 0u);
    outputs[VELOCITY_DENOMINATOR] = VELOCITY_MASSES;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const unsigned int first = VELOCITY_AXIS_FIRST + (VELOCITY_PER_AXIS * axis);
        velocity_step(&program[first], ENGINE_RECORD_FIELD, request->sum_field[axis], 0u, VELOCITY_EARLIER);
        velocity_step(&program[first + 1u], ENGINE_RECORD_FIELD, request->sum_field[axis], 0u, VELOCITY_LATER);
        velocity_step(&program[first + 2u], ENGINE_RECORD_PRODUCT, first + 1u, VELOCITY_EARLIER_MASS, 0u);
        velocity_step(&program[first + 3u], ENGINE_RECORD_PRODUCT, first, VELOCITY_LATER_MASS, 0u);
        velocity_step(&program[first + 4u], ENGINE_RECORD_DIFFERENCE, first + 2u, first + 3u, 0u);
        velocity_step(&program[first + 5u], ENGINE_RECORD_FIELD_SIGNED, request->lag_field[axis], 0u, VELOCITY_LAG);
        velocity_step(&program[first + 6u], ENGINE_RECORD_PRODUCT, first + 5u, VELOCITY_MASSES, 0u);
        velocity_step(&program[first + 7u], ENGINE_RECORD_DIFFERENCE, first + 4u, first + 6u, 0u);
        velocity_step(&program[first + 8u], ENGINE_RECORD_ABSOLUTE, first + 7u, 0u, 0u);
        velocity_step(&program[first + 9u], ENGINE_RECORD_COMPARE, VELOCITY_MASSES, first + 8u, 0u);
        velocity_step(&program[first + 10u], ENGINE_RECORD_SUM, first + 9u, VELOCITY_ONE, 0u);
        velocity_step(&program[first + 11u], ENGINE_RECORD_PRODUCT, first + 9u, first + 10u, 0u);
        outputs[VELOCITY_CHANGE + axis] = first + 4u;
        outputs[VELOCITY_AGREES + axis] = first + 11u;
    }
    const unsigned int both = VELOCITY_AXIS_FIRST + (VELOCITY_PER_AXIS * ENGINE_AXES);
    velocity_step(&program[both], ENGINE_RECORD_PRODUCT, outputs[VELOCITY_AGREES], outputs[VELOCITY_AGREES + 1u], 0u);
    velocity_step(&program[both + 1u], ENGINE_RECORD_PRODUCT, both, outputs[VELOCITY_AGREES + 2u], 0u);
    outputs[VELOCITY_ALL_AGREE] = both + 1u;
    return (long)VELOCITY_STEPS;
}
