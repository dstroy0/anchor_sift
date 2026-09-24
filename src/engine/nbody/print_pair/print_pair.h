// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PRINT_PAIR_H
#define PRINT_PAIR_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PRINT_PAIR_REFUSED (-1L)

#define PRINT_PAIR_BANDS 7u

#define PRINT_PAIR_STEPS ((5u * PRINT_PAIR_BANDS) + 1u)

#define PRINT_PAIR_OUTPUTS 1u

#define PRINT_PAIR_CEILING \
    ((PRINT_PAIR_BANDS * 2ull * ((unsigned long long)ENGINE_GOLDEN_RUNGS - 1ull)) + 1ull)

long print_pair_program(EngineRecordStep program[PRINT_PAIR_STEPS], unsigned int outputs[PRINT_PAIR_OUTPUTS]);

#ifdef __cplusplus
}
#endif

#endif
