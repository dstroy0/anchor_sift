// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "print_pair.h"

#include <string.h>

#define PRINT_PAIR_OTHER PRINT_PAIR_BANDS

#define PRINT_PAIR_APART (2u * PRINT_PAIR_BANDS)

#define PRINT_PAIR_MAGNITUDE (3u * PRINT_PAIR_BANDS)

#define PRINT_PAIR_DISTANCE (4u * PRINT_PAIR_BANDS)

static void print_pair_step(EngineRecordStep *step, EngineRecordOperation operation, unsigned int left,
                            unsigned int right, unsigned int member)
{
    step->operation = operation;
    step->left = left;
    step->right = right;
    step->member = member;
}

extern "C" long print_pair_program(EngineRecordStep program[PRINT_PAIR_STEPS], unsigned int outputs[PRINT_PAIR_OUTPUTS])
{
    memset(program, 0, PRINT_PAIR_STEPS * sizeof(EngineRecordStep));
    for (unsigned int band = 0u; band < PRINT_PAIR_BANDS; band += 1u)
    {
        print_pair_step(&program[band], ENGINE_RECORD_FIELD_SIGNED, band, 0u, 0u);
        print_pair_step(&program[PRINT_PAIR_OTHER + band], ENGINE_RECORD_FIELD_SIGNED, band, 0u, 1u);
        print_pair_step(&program[PRINT_PAIR_APART + band], ENGINE_RECORD_DIFFERENCE, band, PRINT_PAIR_OTHER + band, 0u);
        print_pair_step(&program[PRINT_PAIR_MAGNITUDE + band], ENGINE_RECORD_ABSOLUTE, PRINT_PAIR_APART + band, 0u,
                        0u);
    }
    print_pair_step(&program[PRINT_PAIR_DISTANCE], ENGINE_RECORD_SUM, PRINT_PAIR_MAGNITUDE, PRINT_PAIR_MAGNITUDE + 1u,
                    0u);
    for (unsigned int band = 2u; band < PRINT_PAIR_BANDS; band += 1u)
    {
        print_pair_step(&program[PRINT_PAIR_DISTANCE + band - 1u], ENGINE_RECORD_SUM, PRINT_PAIR_DISTANCE + band - 2u,
                        PRINT_PAIR_MAGNITUDE + band, 0u);
    }
    const unsigned int distance = PRINT_PAIR_DISTANCE + PRINT_PAIR_BANDS - 2u;
    const unsigned long long ceiling = PRINT_PAIR_CEILING;
    print_pair_step(&program[distance + 1u], ENGINE_RECORD_CONSTANT, (unsigned int)(ceiling & 0xFFFFFFFFull),
                    (unsigned int)(ceiling >> 32u), 0u);
    print_pair_step(&program[distance + 2u], ENGINE_RECORD_DIFFERENCE, distance + 1u, distance, 0u);
    outputs[0] = distance + 2u;
    return (long)PRINT_PAIR_STEPS;
}
