// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef KEYMATH_H
#define KEYMATH_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KEYMATH_REFUSED (-1L)

typedef struct
{
    const EngineStep *steps;
    unsigned int count;
    EngineKey *key;
    EngineError *error;
} KeymathImprintRequest;

long keymath_imprint(const KeymathImprintRequest *request);

void keymath_key_release(EngineKey *key);

typedef struct
{
    const EngineRecordStep *steps;
    unsigned int count;
    const unsigned int *field_bits;
    unsigned int fields;
    unsigned int members;
    const unsigned int *outputs;
    unsigned int output_count;
    const EngineRecordTable *tables;
    unsigned int table_count;
    EngineRecordKey *key;
    EngineError *error;
} KeymathRecordRequest;

long keymath_record_imprint(const KeymathRecordRequest *request);

void keymath_record_release(EngineRecordKey *key);

#ifdef __cplusplus
}
#endif

#endif
