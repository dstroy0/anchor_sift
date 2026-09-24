// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "division.h"

#include <string.h>

static const unsigned int DIVISION_FIRST_AXIS[DIVISION_MOMENTS] = {0u, 1u, 2u, 0u, 0u, 1u};

static const unsigned int DIVISION_SECOND_AXIS[DIVISION_MOMENTS] = {0u, 1u, 2u, 1u, 2u, 2u};

typedef struct
{
    EngineRecordStep *program;
    unsigned int written;
} DivisionWriter;

static unsigned long long division_common_unit(unsigned long long first, unsigned long long second)
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

static unsigned int division_put(DivisionWriter *writer, EngineRecordOperation operation, unsigned int left,
                                 unsigned int right, unsigned int member)
{
    const unsigned int at = writer->written;
    if (at < DIVISION_STEPS)
    {
        EngineRecordStep *const step = &writer->program[at];
        step->operation = operation;
        step->left = left;
        step->right = right;
        step->member = member;
    }
    writer->written = at + 1u;
    return at;
}

static unsigned int division_constant(DivisionWriter *writer, unsigned long long value)
{
    return division_put(writer, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull),
                        (unsigned int)(value >> 32u), 0u);
}

extern "C" long division_program(const DivisionRequest *request, EngineRecordStep program[DIVISION_STEPS],
                                 unsigned int outputs[DIVISION_OUTPUTS])
{
    if ((request->voxel_pm[0] == 0ull) || (request->voxel_pm[1] == 0ull) || (request->voxel_pm[2] == 0ull))
    {
        return DIVISION_REFUSED;
    }
    const unsigned long long unit = division_common_unit(
        division_common_unit(request->voxel_pm[0], request->voxel_pm[1]), request->voxel_pm[2]);
    memset(program, 0, DIVISION_STEPS * sizeof(EngineRecordStep));
    DivisionWriter writer = {program, 0u};
    const unsigned int parent_mass = division_put(&writer, ENGINE_RECORD_FIELD, request->mass_field, 0u, DIVISION_PARENT);
    const unsigned int child_mass = division_put(&writer, ENGINE_RECORD_FIELD, request->mass_field, 0u, DIVISION_CHILD);
    const unsigned int sibling_mass = division_put(&writer, ENGINE_RECORD_FIELD, request->mass_field, 0u,
                                                   DIVISION_SIBLING);
    const unsigned int one = division_constant(&writer, 1ull);
    const unsigned int dimensions = division_constant(&writer, ENGINE_AXES);
    const unsigned int joined = division_put(&writer, ENGINE_RECORD_SUM, child_mass, sibling_mass, 0u);
    const unsigned int parent_band = division_put(&writer, ENGINE_RECORD_LADDER, parent_mass, one, 0u);
    const unsigned int joined_band = division_put(&writer, ENGINE_RECORD_LADDER, joined, one, 0u);
    const unsigned int band_order = division_put(&writer, ENGINE_RECORD_COMPARE, joined_band, parent_band, 0u);
    const unsigned int band_apart = division_put(&writer, ENGINE_RECORD_ABSOLUTE, band_order, 0u, 0u);
    outputs[DIVISION_MASS_HOLDS] = division_put(&writer, ENGINE_RECORD_DIFFERENCE, one, band_apart, 0u);
    unsigned int scale[ENGINE_AXES];
    unsigned int parent_sum[ENGINE_AXES];
    unsigned int child_sum[ENGINE_AXES];
    unsigned int sibling_sum[ENGINE_AXES];
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        scale[axis] = division_constant(&writer, request->voxel_pm[axis] / unit);
        parent_sum[axis] = division_put(&writer, ENGINE_RECORD_FIELD, request->sum_field[axis], 0u, DIVISION_PARENT);
        child_sum[axis] = division_put(&writer, ENGINE_RECORD_FIELD, request->sum_field[axis], 0u, DIVISION_CHILD);
        sibling_sum[axis] = division_put(&writer, ENGINE_RECORD_FIELD, request->sum_field[axis], 0u, DIVISION_SIBLING);
    }
    unsigned int apart[ENGINE_AXES];
    unsigned int square[ENGINE_AXES];
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const unsigned int child_cross = division_put(&writer, ENGINE_RECORD_PRODUCT, child_sum[axis], sibling_mass, 0u);
        const unsigned int sibling_cross = division_put(&writer, ENGINE_RECORD_PRODUCT, sibling_sum[axis], child_mass,
                                                        0u);
        const unsigned int difference = division_put(&writer, ENGINE_RECORD_DIFFERENCE, child_cross, sibling_cross, 0u);
        apart[axis] = division_put(&writer, ENGINE_RECORD_PRODUCT, difference, scale[axis], 0u);
        square[axis] = division_put(&writer, ENGINE_RECORD_PRODUCT, apart[axis], apart[axis], 0u);
    }
    unsigned int spread[DIVISION_MOMENTS];
    unsigned int term[DIVISION_MOMENTS];
    for (unsigned int moment = 0u; moment < DIVISION_MOMENTS; moment += 1u)
    {
        const unsigned int axis_one = DIVISION_FIRST_AXIS[moment];
        const unsigned int axis_two = DIVISION_SECOND_AXIS[moment];
        const unsigned int second = division_put(&writer, ENGINE_RECORD_FIELD, request->moment_field[moment], 0u,
                                                 DIVISION_PARENT);
        const unsigned int weighed = division_put(&writer, ENGINE_RECORD_PRODUCT, parent_mass, second, 0u);
        const unsigned int crossed = division_put(&writer, ENGINE_RECORD_PRODUCT, parent_sum[axis_one],
                                                  parent_sum[axis_two], 0u);
        const unsigned int central = division_put(&writer, ENGINE_RECORD_DIFFERENCE, weighed, crossed, 0u);
        const unsigned int once = division_put(&writer, ENGINE_RECORD_PRODUCT, central, scale[axis_one], 0u);
        spread[moment] = division_put(&writer, ENGINE_RECORD_PRODUCT, once, scale[axis_two], 0u);
        if (axis_one == axis_two)
        {
            term[moment] = division_put(&writer, ENGINE_RECORD_PRODUCT, square[axis_one], spread[moment], 0u);
        }
        else
        {
            const unsigned int paired = division_put(&writer, ENGINE_RECORD_PRODUCT, apart[axis_one], apart[axis_two],
                                                     0u);
            const unsigned int half = division_put(&writer, ENGINE_RECORD_PRODUCT, paired, spread[moment], 0u);
            term[moment] = division_put(&writer, ENGINE_RECORD_SUM, half, half, 0u);
        }
    }
    unsigned int form = term[0];
    for (unsigned int moment = 1u; moment < DIVISION_MOMENTS; moment += 1u)
    {
        form = division_put(&writer, ENGINE_RECORD_SUM, form, term[moment], 0u);
    }
    const unsigned int trace_part = division_put(&writer, ENGINE_RECORD_SUM, spread[0], spread[1], 0u);
    const unsigned int trace = division_put(&writer, ENGINE_RECORD_SUM, trace_part, spread[2], 0u);
    const unsigned int length_part = division_put(&writer, ENGINE_RECORD_SUM, square[0], square[1], 0u);
    const unsigned int length = division_put(&writer, ENGINE_RECORD_SUM, length_part, square[2], 0u);
    const unsigned int along = division_put(&writer, ENGINE_RECORD_PRODUCT, dimensions, form, 0u);
    const unsigned int even = division_put(&writer, ENGINE_RECORD_PRODUCT, trace, length, 0u);
    const unsigned int axis_order = division_put(&writer, ENGINE_RECORD_COMPARE, along, even, 0u);
    outputs[DIVISION_AXIS_HOLDS] = division_put(&writer, ENGINE_RECORD_SUM, axis_order, one, 0u);
    outputs[DIVISION_BOTH_HOLD] = division_put(&writer, ENGINE_RECORD_PRODUCT, outputs[DIVISION_MASS_HOLDS],
                                               outputs[DIVISION_AXIS_HOLDS], 0u);
    return (writer.written == DIVISION_STEPS) ? (long)DIVISION_STEPS : DIVISION_REFUSED;
}
