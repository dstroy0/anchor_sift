// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef OBSIGNATIO_H
#define OBSIGNATIO_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define OBSIGNATIO_REFUSED (-1L)

#define OBSIGNATIO_SIGNUM_BYTES 32u

#define OBSIGNATIO_KEY_BYTES 32u

#define OBSIGNATIO_MODE_HASH 0u

#define OBSIGNATIO_MODE_KEYED 16u

#define OBSIGNATIO_MODE_CONTEXT 32u

#define OBSIGNATIO_MODE_MATERIAL 64u

#define OBSIGNATIO_EXTENT_AXES 4u

typedef struct
{
    const unsigned char *bytes;
    unsigned long long count;
    const unsigned char *key;
    unsigned int mode;
    unsigned char *out;
    unsigned long long out_bytes;
    EngineError *error;
} ObsignatioSignumRequest;

long obsignatio_signum(const ObsignatioSignumRequest *request);

typedef struct
{
    const unsigned char *device_bytes;
    unsigned long long messages;
    unsigned long long length;
    unsigned long long stride;
    const unsigned char *key;
    unsigned int mode;
    unsigned char *device_signa;
    EngineError *error;
} ObsignatioManyRequest;

long obsignatio_many(const ObsignatioManyRequest *request);

typedef struct
{
    const unsigned int *device_limbs;
    const unsigned long long *device_offsets;
    unsigned long long messages;
    unsigned long long bits;
    const unsigned char *key;
    unsigned int mode;
    unsigned char *device_signa;
    EngineError *error;
} ObsignatioBitsRequest;

long obsignatio_bits(const ObsignatioBitsRequest *request);

typedef enum
{
    OBSIGNATIO_LEVEL_ROW = 0,
    OBSIGNATIO_LEVEL_PLANE = 1,
    OBSIGNATIO_LEVEL_VOLUME = 2,
    OBSIGNATIO_LEVEL_LANES = 3,
    OBSIGNATIO_LEVEL_CHUNK = 4,
    OBSIGNATIO_LEVEL_STREAM = 5,
    OBSIGNATIO_LEVEL_SIDE = 6,
    OBSIGNATIO_LEVEL_MEMBERS = 7,
    OBSIGNATIO_LEVEL_SAMPLE = 8,
    OBSIGNATIO_LEVEL_SET = 9,
    OBSIGNATIO_LEVEL_FILE = 10,
    OBSIGNATIO_LEVEL_UNIVERSAL = 11,
    OBSIGNATIO_LEVEL_SIDE_STORED = 12,
    OBSIGNATIO_LEVEL_SIDE_INFLATED = 13,
    OBSIGNATIO_LEVELS = 14
} ObsignatioLevel;

const char *obsignatio_level_context(ObsignatioLevel level);

long obsignatio_level_key(ObsignatioLevel level, unsigned char *key, EngineError *error);

typedef struct
{
    const unsigned char *bytes;
    unsigned long long count;
    unsigned char *signum;
    EngineError *error;
} ObsignatioSealRequest;

long obsignatio_seal(const ObsignatioSealRequest *request);

long obsignatio_seal_holds(const ObsignatioSealRequest *request);

unsigned long long obsignatio_lanes_nodes(const unsigned long long *extent);

typedef struct
{
    const unsigned short *device_lanes;
    const unsigned long long *extent;
    unsigned char *device_nodes;
    EngineError *error;
} ObsignatioLanesRequest;

long obsignatio_lanes(const ObsignatioLanesRequest *request);

#ifdef __cplusplus
}
#endif

#endif
