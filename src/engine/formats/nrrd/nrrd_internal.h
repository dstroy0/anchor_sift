// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the nrrd_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef NRRD_INTERNAL_H
#define NRRD_INTERNAL_H

#include "nrrd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NRRD_BYTES_LIMIT 9223372036854775807ull
#define NRRD_SKIP_CHUNK 4096u
#define NRRD_GZIP_SMALLEST 18ull

typedef enum
{
    NRRD_KIND_OTHER = 0,
    NRRD_KIND_SPACE = 1,
    NRRD_KIND_TIME = 2
} NrrdKind;

typedef enum
{
    NRRD_UNSET = 0,
    NRRD_LITTLE = 1,
    NRRD_BIG = 2
} NrrdEndian;

typedef enum
{
    NRRD_ENCODING_UNSET = 0,
    NRRD_ENCODING_RAW = 1,
    NRRD_ENCODING_GZIP = 2
} NrrdEncoding;

typedef struct
{
    const char *name;
    unsigned int element_bytes;
    EngineElementKind element_kind;
} NrrdType;

typedef struct
{
    const char *name;
    unsigned int timed;
} NrrdSpace;

typedef struct
{
    const char *text;
    unsigned long long length;
} NrrdSpan;

typedef struct
{
    unsigned int dimension;
    unsigned int typed;
    unsigned int element_bytes;
    EngineElementKind element_kind;
    NrrdEndian endian;
    NrrdEncoding encoding;
    unsigned int sizes_count;
    unsigned long long sizes[ENGINE_ARRAY_RANK];
    unsigned int kinds_count;
    NrrdKind kinds[ENGINE_ARRAY_RANK];
    unsigned int directions_count;
    unsigned int directions[ENGINE_ARRAY_RANK];
    unsigned int spaced;
    unsigned int space_timed;
    unsigned long long line_skip;
    unsigned long long byte_skip;
    unsigned int skip_to_end;
    NrrdSpan data_file;
    unsigned int ended;
    unsigned long long header_end;
} NrrdFields;

typedef struct
{
    EngineArrayExtent extent;
    unsigned int big_endian;
    unsigned int gzip;
    char *data_path;
    unsigned long long data_offset;
    unsigned long long data_bytes;
    unsigned long long byte_skip;
    unsigned long long file_bytes;
} NrrdLayout;

unsigned int nrrd_fits_memory(unsigned long long bytes);

unsigned int nrrd_multiply(unsigned long long left, unsigned long long right, unsigned long long *product);

unsigned int nrrd_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
                        unsigned long long bytes, unsigned char *out);

void nrrd_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes);

NrrdSpan nrrd_trim(NrrdSpan span);

unsigned int nrrd_equals(NrrdSpan span, const char *word);

unsigned int nrrd_listed(NrrdSpan span, const char *const *words, size_t count);

unsigned int nrrd_token(NrrdSpan *rest, NrrdSpan *token);

unsigned int nrrd_single(NrrdSpan value, unsigned long long *number);

unsigned int nrrd_type(NrrdSpan value, NrrdFields *fields);

unsigned int nrrd_encoding(NrrdSpan value, NrrdFields *fields);

unsigned int nrrd_space(NrrdSpan value, NrrdFields *fields);

unsigned int nrrd_sizes(NrrdSpan value, NrrdFields *fields);

unsigned int nrrd_kinds(NrrdSpan value, NrrdFields *fields);

unsigned int nrrd_directions(NrrdSpan value, NrrdFields *fields);

#endif
