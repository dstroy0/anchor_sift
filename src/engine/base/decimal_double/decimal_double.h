// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DECIMAL_DOUBLE_H
#define DECIMAL_DOUBLE_H

#include "engine_config.h"
#include "exact_integer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    long long e2;
    int fits;
    int terminates;
    unsigned long long needed_bits;
} DecimalDoubleHeld;

typedef struct
{
    const char *digits;
    size_t digit_count;
    int ex;
    int neg;
    AnchorExactInteger *candidate;
    DecimalDoubleHeld *held;
    EngineError *error;
} DecimalDoubleRequest;

int decimal_double_expand(const DecimalDoubleRequest *request);

#ifdef __cplusplus
}
#endif

#endif
