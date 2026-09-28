// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the zarr_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef ZARR_INTERNAL_H
#define ZARR_INTERNAL_H

#include "zarr.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZARR_PATH_CAPACITY ENGINE_PATH_CAPACITY

#define ZARR_N5_HEAD_MAX (4u + (4u * ENGINE_ARRAY_RANK))

#define ZARR_EMPTY_ENTRY 0xFFFFFFFFFFFFFFFFull

typedef struct
{
    const ZarrReadRequest *request;
    unsigned int rank;
    unsigned int element_bytes;
    const unsigned long long *leaf;
    unsigned long long grid[ENGINE_ARRAY_RANK];
    unsigned long long row_bytes;
    unsigned char *chunk;
    unsigned long long chunk_capacity;
    unsigned char *raw;
    unsigned long long raw_capacity;
    unsigned long long cached_shard[ENGINE_ARRAY_RANK];
    unsigned int shard_valid;
    unsigned long long *shard_index;
    unsigned long long shard_entries;
} ZarrWalk;

unsigned int zarr_crc32c(const unsigned char *bytes, unsigned long long count);

unsigned long long zarr_little(const unsigned char *bytes, unsigned int count);

unsigned long long zarr_big(const unsigned char *bytes, unsigned int count);

int zarr_reserve(unsigned char **buffer, unsigned long long *capacity, unsigned long long wanted);

int zarr_key(const ZarrLayout *layout, const char *root, const unsigned long long *position, unsigned int rank,
             char *path);

long long zarr_file_read(const ZarrWalk *walk, const char *path, unsigned long long offset, unsigned long long bytes,
                         unsigned char *out);

long long zarr_unchain(const ZarrWalk *walk, const ZarrChain *chain, unsigned char *raw, unsigned long long raw_bytes,
                       unsigned char *out, unsigned long long expected);

void zarr_swap(unsigned char *bytes, unsigned long long elements, unsigned int element_bytes);

void zarr_place(const ZarrWalk *walk, const unsigned long long *position, const unsigned long long *actual,
                unsigned long long elements);

#endif
