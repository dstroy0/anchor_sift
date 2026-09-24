// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "contact_side.h"

#include <string.h>

typedef struct
{
    EngineRecordStep *program;
    unsigned int room;
    unsigned int written;
} ContactSideWriter;

static unsigned long long contact_side_common_unit(unsigned long long first, unsigned long long second)
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

static unsigned int contact_side_put(ContactSideWriter *writer, EngineRecordOperation operation, unsigned int left,
                                     unsigned int right, unsigned int member)
{
    const unsigned int at = writer->written;
    if (at < writer->room)
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

static unsigned int contact_side_constant(ContactSideWriter *writer, unsigned long long value)
{
    return contact_side_put(writer, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull),
                            (unsigned int)(value >> 32u), 0u);
}

extern "C" long contact_side_difference_program(const ContactSideDifferenceRequest *request,
                                                EngineRecordStep program[CONTACT_SIDE_DIFFERENCE_STEPS],
                                                unsigned int outputs[CONTACT_SIDE_DIFFERENCE_OUTPUTS])
{
    if ((request->voxel_pm[0] == 0ull) || (request->voxel_pm[1] == 0ull) || (request->voxel_pm[2] == 0ull))
    {
        return CONTACT_SIDE_REFUSED;
    }
    const unsigned long long unit = contact_side_common_unit(
        contact_side_common_unit(request->voxel_pm[0], request->voxel_pm[1]), request->voxel_pm[2]);
    memset(program, 0, CONTACT_SIDE_DIFFERENCE_STEPS * sizeof(EngineRecordStep));
    ContactSideWriter writer = {program, CONTACT_SIDE_DIFFERENCE_STEPS, 0u};
    const unsigned int one_mass = contact_side_put(&writer, ENGINE_RECORD_FIELD, request->mass_field, 0u,
                                                   CONTACT_SIDE_ONE);
    const unsigned int other_mass = contact_side_put(&writer, ENGINE_RECORD_FIELD, request->mass_field, 0u,
                                                     CONTACT_SIDE_OTHER);
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const unsigned int scale = contact_side_constant(&writer, request->voxel_pm[axis] / unit);
        const unsigned int one_sum = contact_side_put(&writer, ENGINE_RECORD_FIELD, request->sum_field[axis], 0u,
                                                      CONTACT_SIDE_ONE);
        const unsigned int other_sum = contact_side_put(&writer, ENGINE_RECORD_FIELD, request->sum_field[axis], 0u,
                                                        CONTACT_SIDE_OTHER);
        const unsigned int one_cross = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, one_sum, other_mass, 0u);
        const unsigned int other_cross = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, other_sum, one_mass, 0u);
        const unsigned int apart = contact_side_put(&writer, ENGINE_RECORD_DIFFERENCE, one_cross, other_cross, 0u);
        outputs[axis] = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, apart, scale, 0u);
    }
    return (writer.written == CONTACT_SIDE_DIFFERENCE_STEPS) ? (long)CONTACT_SIDE_DIFFERENCE_STEPS
                                                             : CONTACT_SIDE_REFUSED;
}

extern "C" long contact_side_kept_program(const ContactSideKeptRequest *request,
                                          EngineRecordStep program[CONTACT_SIDE_KEPT_STEPS],
                                          unsigned int outputs[CONTACT_SIDE_KEPT_OUTPUTS])
{
    memset(program, 0, CONTACT_SIDE_KEPT_STEPS * sizeof(EngineRecordStep));
    ContactSideWriter writer = {program, CONTACT_SIDE_KEPT_STEPS, 0u};
    const unsigned int one = contact_side_constant(&writer, 1ull);
    unsigned int dot = 0u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const unsigned int before = contact_side_put(&writer, ENGINE_RECORD_FIELD_SIGNED, request->difference_field[axis],
                                                     0u, CONTACT_SIDE_BEFORE);
        const unsigned int after = contact_side_put(&writer, ENGINE_RECORD_FIELD_SIGNED, request->difference_field[axis],
                                                    0u, CONTACT_SIDE_AFTER);
        const unsigned int term = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, before, after, 0u);
        dot = (axis == 0u) ? term : contact_side_put(&writer, ENGINE_RECORD_SUM, dot, term, 0u);
    }
    outputs[CONTACT_SIDE_DOT] = dot;
    const unsigned int raised = contact_side_put(&writer, ENGINE_RECORD_SUM, dot, one, 0u);
    const unsigned int side = contact_side_put(&writer, ENGINE_RECORD_COMPARE, raised, one, 0u);
    const unsigned int above = contact_side_put(&writer, ENGINE_RECORD_SUM, side, one, 0u);
    outputs[CONTACT_SIDE_KEPT] = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, side, above, 0u);
    const unsigned int below = contact_side_put(&writer, ENGINE_RECORD_DIFFERENCE, side, one, 0u);
    outputs[CONTACT_SIDE_CROSSED] = contact_side_put(&writer, ENGINE_RECORD_PRODUCT, side, below, 0u);
    return (writer.written == CONTACT_SIDE_KEPT_STEPS) ? (long)CONTACT_SIDE_KEPT_STEPS : CONTACT_SIDE_REFUSED;
}
