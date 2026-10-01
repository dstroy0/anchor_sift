// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the apxrep_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef APXREP_INTERNAL_H
#define APXREP_INTERNAL_H

#include "../../engine/formats/apxrep/apxrep.h"

#include "crc.h"

#include <stdlib.h>
#include <string.h>

#define APXREP_CHECK(condition_, evacaddr_, error_, kind_)                                                             \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_APXREP, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define APXREP_IO(condition_, evacaddr_, error_)                                                                       \
    engine_io_check((condition_), ENGINE_MODULE_APXREP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

extern "C" int apxrep_words_write(FILE *file, const unsigned long long *words, size_t count);

extern "C" int apxrep_words_read(FILE *file, unsigned long long *words, size_t count);

extern "C" int apxrep_limbs_read(FILE *file, unsigned int *limbs, size_t count);

extern "C" int apxrep_head_write(FILE *file, const char *kind);

extern "C" int apxrep_head_read(FILE *file, const char *kind);

typedef enum
{
    APXREP_HEAD_EXTENT = 0,
    APXREP_HEAD_CHUNKS = 4,
    APXREP_HEAD_BITS = 5,
    APXREP_HEAD_LANE_OFFSET = 6,
    APXREP_HEAD_LEAVES = 7,
    APXREP_HEAD_SIDE_BYTES = 8,
    APXREP_HEAD_PACKED_BYTES = 9,
    APXREP_HEAD_NAMES_BYTES = 10,
    APXREP_HEAD_LANE_NODES = 11
} ApxrepInputHead;

static_assert(APXREP_HEAD_LANE_NODES + 1 == APXREP_INPUT_HEAD_WORDS, "the crystal's head words end at its lane nodes");

static_assert(sizeof(EngineSignum) == ENGINE_SIGNUM_BYTES, "a signum is its 32 bytes and nothing more");

unsigned long long apxrep_lanes(const unsigned long long extent[4]);

int apxrep_seal_read(FILE *iapx, const unsigned long long head[APXREP_INPUT_HEAD_WORDS], EngineSeal *seal,
                     EngineError *error);

int apxrep_input_head_from(const char *path, FILE *iapx, EngineStream *stream,
                           unsigned long long head[APXREP_INPUT_HEAD_WORDS], EngineError *error);

#endif
