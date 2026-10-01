// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the krep_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef KREP_INTERNAL_H
#define KREP_INTERNAL_H

#include "../../../../c/types/file_defs/krep/krep.h"

#include "crc.h"

#include <stdlib.h>
#include <string.h>

#define KREP_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_KREP, (unsigned int)__LINE__, (const void *)(evacaddr_),   \
                       (error_))

#define KREP_IO(condition_, evacaddr_, error_)                                                                         \
    engine_io_check((condition_), ENGINE_MODULE_KREP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

extern "C" int krep_words_write(FILE *file, const unsigned long long *words, size_t count);

extern "C" int krep_words_read(FILE *file, unsigned long long *words, size_t count);

extern "C" int krep_limbs_read(FILE *file, unsigned int *limbs, size_t count);

extern "C" int krep_head_write(FILE *file, const char *kind);

extern "C" int krep_head_read(FILE *file, const char *kind);

typedef enum
{
    KREP_HEAD_EXTENT = 0,
    KREP_HEAD_CHUNKS = 4,
    KREP_HEAD_BITS = 5,
    KREP_HEAD_LANE_OFFSET = 6,
    KREP_HEAD_LEAVES = 7,
    KREP_HEAD_SIDE_BYTES = 8,
    KREP_HEAD_PACKED_BYTES = 9,
    KREP_HEAD_NAMES_BYTES = 10,
    KREP_HEAD_LANE_NODES = 11
} KrepCrystalHead;

static_assert(KREP_HEAD_LANE_NODES + 1 == KREP_CRYSTAL_HEAD_WORDS, "the crystal's head words end at its lane nodes");

static_assert(sizeof(EngineSignum) == ENGINE_SIGNUM_BYTES, "a signum is its 32 bytes and nothing more");

unsigned long long krep_lanes(const unsigned long long extent[4]);

int krep_seal_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineSeal *seal,
                   EngineError *error);

int krep_crystal_head_from(const char *path, FILE *crystal, EngineStream *stream,
                           unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineError *error);

int krep_side_read(FILE *crystal, const unsigned long long head[KREP_CRYSTAL_HEAD_WORDS], EngineSideSection *section,
                   EngineError *error);

#endif
