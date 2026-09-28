// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the zstd_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef ZSTD_INTERNAL_H
#define ZSTD_INTERNAL_H

#include "zstd.h"

#include <stdlib.h>
#include <string.h>

#define ZSTD_FRAME_MAGIC 0xFD2FB528ull
#define ZSTD_SKIPPABLE_MAGIC 0x184D2A50ull
#define ZSTD_SKIPPABLE_MASK 0xFFFFFFF0ull
#define ZSTD_BLOCK_MAXIMUM 131072ull
#define ZSTD_RESULT_MAXIMUM 0x7FFFFFFFFFFFFFFFull
#define ZSTD_REPEATS 3u
#define ZSTD_HUFFMAN_BITS_MAXIMUM 11u
#define ZSTD_HUFFMAN_CELLS 2048u
#define ZSTD_HUFFMAN_WEIGHTS 256u
#define ZSTD_HUFFMAN_DESCRIBED_MAXIMUM 255u
#define ZSTD_WEIGHT_ACCURACY_MAXIMUM 6u
#define ZSTD_WEIGHT_SYMBOLS 12u
#define ZSTD_FSE_ACCURACY_MAXIMUM 9u
#define ZSTD_FSE_CELLS 512u
#define ZSTD_FSE_SYMBOLS 64u
#define ZSTD_LITERAL_LENGTH_SYMBOLS 36u
#define ZSTD_MATCH_LENGTH_SYMBOLS 53u
#define ZSTD_OFFSET_SYMBOLS 32u
#define ZSTD_OFFSET_PREDEFINED_SYMBOLS 29u
#define ZSTD_XXH64_PRIME_ONE 0x9E3779B185EBCA87ull
#define ZSTD_XXH64_PRIME_TWO 0xC2B2AE3D27D4EB4Full
#define ZSTD_XXH64_PRIME_THREE 0x165667B19E3779F9ull
#define ZSTD_XXH64_PRIME_FOUR 0x85EBCA77C2B2AE63ull
#define ZSTD_XXH64_PRIME_FIVE 0x27D4EB2F165667C5ull

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
} ZstdSpan;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    unsigned long long position;
} ZstdForwardStream;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    long long position;
} ZstdBackwardStream;

typedef struct
{
    unsigned short baseline;
    unsigned char symbol;
    unsigned char bits;
} ZstdFseCell;

typedef struct
{
    ZstdFseCell cells[ZSTD_FSE_CELLS];
    unsigned int accuracy;
    int ready;
} ZstdFseTable;

typedef struct
{
    const long *predefined;
    unsigned int predefined_symbols;
    unsigned int predefined_accuracy;
    unsigned int symbols;
    unsigned int accuracy;
} ZstdTableKind;

typedef struct
{
    unsigned char symbol;
    unsigned char bits;
} ZstdHuffmanCell;

typedef struct
{
    unsigned char literal_buffer[ZSTD_BLOCK_MAXIMUM];
    ZstdHuffmanCell huffman[ZSTD_HUFFMAN_CELLS];
    unsigned int huffman_bits;
    int huffman_ready;
    ZstdFseTable literal_lengths;
    ZstdFseTable match_lengths;
    ZstdFseTable offsets;
    unsigned long long repeat[ZSTD_REPEATS];
    const unsigned char *literals;
    unsigned long long literal_count;
    unsigned long long literals_used;
    unsigned char *out;
    unsigned long long out_capacity;
    unsigned long long written;
    unsigned long long frame_start;
    unsigned long long block_start;
    unsigned long long window;
    unsigned long long block_maximum;
} ZstdDecoder;

unsigned long long zstd_little_endian(const unsigned char *bytes, unsigned int count);

void zstd_advance(ZstdSpan *span, unsigned long long count);

unsigned int zstd_high_bit(unsigned long long value);

int zstd_backward_open(ZstdBackwardStream *stream, const unsigned char *bytes, unsigned long long length);

unsigned long long zstd_backward_peek(const ZstdBackwardStream *stream, unsigned int count);

unsigned long long zstd_backward_read(ZstdBackwardStream *stream, unsigned int count);

int zstd_fse_describe(ZstdSpan *input, const ZstdTableKind *kind, long *counts, unsigned int *accuracy);

int zstd_fse_build(ZstdFseTable *table, const long *counts, unsigned int symbols, unsigned int accuracy);

int zstd_weights_decode(const ZstdFseTable *table, const ZstdSpan *payload, unsigned char *weights,
                        unsigned int *described);

int zstd_literals(ZstdDecoder *decoder, ZstdSpan *input);

int zstd_table_prepare(ZstdSpan *input, unsigned int mode, const ZstdTableKind *kind, ZstdFseTable *table);

int zstd_output_fits(const ZstdDecoder *decoder, unsigned long long length);

int zstd_literal_copy(ZstdDecoder *decoder, unsigned long long length);

int zstd_match_copy(ZstdDecoder *decoder, unsigned long long offset, unsigned long long length);

int zstd_offset_resolve(ZstdDecoder *decoder, unsigned long long offset_value, unsigned long long literal_length,
                        unsigned long long *offset);

#endif
