// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef COMPRESSION_H
#define COMPRESSION_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define COMPRESSION_REFUSED (-1L)

typedef struct
{
    const int *device_coefficients;
    unsigned long long count;
    unsigned int *device_scratch;
    unsigned long long *chunks;
    unsigned long long *bits;
    const unsigned long long **offsets;
    const unsigned int **stream;
    EngineError *error;
} CompressionEncodeRequest;

long compression_encode(const CompressionEncodeRequest *request);

typedef struct
{
    const unsigned long long *offsets;
    unsigned long long chunks;
    const unsigned int *stream;
    unsigned long long bits;
    unsigned long long count;
    int *device_coefficients;
    EngineError *error;
} CompressionDecodeRequest;

long compression_decode(const CompressionDecodeRequest *request);

unsigned long long compression_chunks(unsigned long long count);

#ifdef __cplusplus
}
#endif

#endif
