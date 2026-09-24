// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BLOSC_H
#define BLOSC_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    EngineBytesRequest bytes;
    const EngineBytesDecode *decode;
} BloscDecodeRequest;

long long blosc_decode(const BloscDecodeRequest *request);

long long blosclz_decode(const EngineBytesRequest *request);

#ifdef __cplusplus
}
#endif

#endif
