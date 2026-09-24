// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ZARR_H
#define ZARR_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ZARR_REFUSED (-1LL)

#define ZARR_CODECS 4u

typedef enum
{
    ZARR_FORMAT_V2 = 2,
    ZARR_FORMAT_V3 = 3,
    ZARR_FORMAT_N5 = 5
} ZarrFormat;

typedef struct
{
    unsigned int count;
    EngineCodec codec[ZARR_CODECS];
    unsigned int crc32c;
} ZarrChain;

typedef struct
{
    ZarrFormat format;
    EngineArrayShape shape;
    unsigned long long chunk[ENGINE_ARRAY_RANK];
    char separator;
    unsigned int prefixed;
    unsigned int big_endian;
    unsigned int order[ENGINE_ARRAY_RANK];
    ZarrChain chain;
    unsigned int sharded;
    unsigned long long inner[ENGINE_ARRAY_RANK];
    ZarrChain inner_chain;
    ZarrChain index_chain;
    unsigned int index_big_endian;
    unsigned int index_at_start;
    unsigned char fill[8];
} ZarrLayout;

typedef struct
{
    const char *root;
    const ZarrLayout *layout;
    const EngineIngestTools *tools;
    unsigned long long first;
    unsigned long long past;
    unsigned char *out;
    unsigned long long out_room;
} ZarrReadRequest;

long long zarr_read(const ZarrReadRequest *request);

#ifdef __cplusplus
}
#endif

#endif
