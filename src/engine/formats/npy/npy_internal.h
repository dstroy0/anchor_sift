// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the npy_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef NPY_INTERNAL_H
#define NPY_INTERNAL_H

#include "npy.h"

#include "zip.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NPY_CHECK(condition_, evacaddr_, error_, kind_)                                                                \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_NPY, (unsigned int)__LINE__, (const void *)(evacaddr_),    \
                       (error_))

#define NPY_FORTRAN_BLOCK 16777216ull
#define NPY_BYTES_LIMIT 9223372036854775807ull

typedef struct
{
    const EngineIngestTools *tools;
    const char *path;
    unsigned long long base;
    unsigned long long length;
    const unsigned char *memory;
} NpySource;

typedef struct
{
    EngineArrayExtent extent;
    unsigned int big_endian;
    unsigned int fortran_order;
    unsigned long long data_offset;
    unsigned long long data_bytes;
} NpyLayout;

typedef struct
{
    const unsigned char *text;
    unsigned long long length;
    unsigned long long at;
} NpyText;

unsigned long long npy_load(const unsigned char *bytes, unsigned int count);

unsigned int npy_fits_memory(unsigned long long bytes);

unsigned int npy_multiply(unsigned long long left, unsigned long long right, unsigned long long *product);

unsigned int npy_file_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
                            unsigned long long bytes, unsigned char *out);

unsigned int npy_source_fetch(const NpySource *source, unsigned long long offset, unsigned long long bytes,
                              unsigned char *out);

void npy_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes);

unsigned int npy_dictionary(const unsigned char *header, unsigned long long length, NpyLayout *layout);

#endif
