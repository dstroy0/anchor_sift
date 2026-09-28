// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tiff_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TIFF_INTERNAL_H
#define TIFF_INTERNAL_H

#include "tiff.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TIFF_LEADING_AXES 3u
#define TIFF_ENTRIES_MAX 65535ull
#define TIFF_TILE_SAMPLES_MAX 16777216ull
#define TIFF_LZW_CODES 4096u
#define TIFF_LZW_CLEAR 256u
#define TIFF_LZW_END 257u
#define TIFF_LZW_FIRST 258u
#define TIFF_LZW_WIDTH_FIRST 9u
#define TIFF_LZW_WIDTH_LAST 12u

typedef enum
{
    TIFF_TAG_WIDTH = 0,
    TIFF_TAG_LENGTH = 1,
    TIFF_TAG_BITS_PER_SAMPLE = 2,
    TIFF_TAG_COMPRESSION = 3,
    TIFF_TAG_FILL_ORDER = 4,
    TIFF_TAG_DESCRIPTION = 5,
    TIFF_TAG_STRIP_OFFSETS = 6,
    TIFF_TAG_SAMPLES_PER_PIXEL = 7,
    TIFF_TAG_ROWS_PER_STRIP = 8,
    TIFF_TAG_STRIP_BYTE_COUNTS = 9,
    TIFF_TAG_PLANAR_CONFIGURATION = 10,
    TIFF_TAG_PREDICTOR = 11,
    TIFF_TAG_TILE_WIDTH = 12,
    TIFF_TAG_TILE_LENGTH = 13,
    TIFF_TAG_TILE_OFFSETS = 14,
    TIFF_TAG_TILE_BYTE_COUNTS = 15,
    TIFF_TAG_SAMPLE_FORMAT = 16,
    TIFF_TAGS = 17
} TiffTag;

typedef struct
{
    const char *path;
    const EngineIngestTools *tools;
    unsigned long long file_bytes;
    unsigned long long first_ifd;
    unsigned int bigtiff;
    unsigned int big_endian;
    const char *reason;
    char detail[160u];
} TiffFile;

typedef struct
{
    unsigned int present;
    unsigned int type;
    unsigned long long count;
    unsigned char value[8u];
} TiffEntry;

typedef struct
{
    unsigned long long width;
    unsigned long long height;
    unsigned long long page_bytes;
    unsigned int element_bytes;
    EngineElementKind element_kind;
    unsigned long long compression;
    unsigned long long predictor;
    unsigned long long chunk_width;
    unsigned long long chunk_height;
    unsigned long long chunks_across;
    unsigned long long chunks_down;
    TiffEntry offsets;
    TiffEntry byte_counts;
    TiffEntry description;
    unsigned long long next;
} TiffPage;

typedef struct
{
    unsigned int leading;
    unsigned long long extent[TIFF_LEADING_AXES];
    unsigned long long stride[TIFF_LEADING_AXES];
    char axes[TIFF_LEADING_AXES];
} TiffLayout;

typedef struct
{
    unsigned long long *offsets;
    unsigned long long count;
    unsigned long long capacity;
    unsigned long long highest;
} TiffChain;

typedef struct
{
    unsigned char *packed;
    unsigned long long packed_capacity;
    unsigned char *chunk;
    unsigned long long chunk_capacity;
} TiffScratch;

int tiff_fail(TiffFile *file, const char *reason);

int tiff_fail_number(TiffFile *file, const char *before, unsigned long long number, const char *after);

int tiff_fail_named(TiffFile *file, const char *before, const char *name);

int tiff_multiply(TiffFile *file, unsigned long long left, unsigned long long right, unsigned long long *product);

int tiff_reserve(TiffFile *file, unsigned char **buffer, unsigned long long *capacity, unsigned long long needed);

int tiff_fetch(TiffFile *file, unsigned long long offset, unsigned long long bytes, unsigned char *out);

unsigned long long tiff_unpack(const TiffFile *file, const unsigned char *raw, unsigned int width);

int tiff_open(TiffFile *file, const char *path, const char *member, const EngineIngestTools *tools);

unsigned int tiff_type_bytes(unsigned int type);

int tiff_entry_bytes(TiffFile *file, const TiffEntry *entry, unsigned long long total, unsigned char *out);

int tiff_entry_integers(TiffFile *file, const TiffEntry *entry, unsigned long long *values, unsigned long long count);

int tiff_entry_scalar(TiffFile *file, const TiffEntry *entry, unsigned long long fallback, unsigned long long *value);

int tiff_ifd_next(TiffFile *file, unsigned long long ifd, unsigned long long *next);

int tiff_page(TiffFile *file, unsigned long long ifd, TiffPage *page);

int tiff_page_same(const TiffPage *first, const TiffPage *page);

int tiff_page_chunks(TiffFile *file, const TiffPage *page, unsigned long long **offsets, unsigned long long **counts);

int tiff_chunk_decode(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long offset,
                      unsigned long long bytes, unsigned long long rows);

int tiff_page_rows(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long row_first,
                   unsigned long long row_end, unsigned char *out);

int tiff_chain_add(TiffFile *file, TiffChain *chain, unsigned long long offset);

char *tiff_description(TiffFile *file, const TiffEntry *entry);

void tiff_layout_axis(TiffLayout *layout, char axis, unsigned long long extent, unsigned long long stride);

int tiff_imagej(TiffFile *file, const char *text, unsigned long long pages, unsigned int pages_known,
                TiffLayout *layout);

int tiff_ome(TiffFile *file, const TiffPage *page, const char *text, unsigned long long pages, unsigned int pages_known,
             TiffLayout *layout);

const char *tiff_ome_start(const char *text);

#endif
