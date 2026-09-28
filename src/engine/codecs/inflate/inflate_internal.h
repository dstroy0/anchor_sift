// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the inflate_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef INFLATE_INTERNAL_H
#define INFLATE_INTERNAL_H

#include "inflate.h"

#include <limits.h>
#include <string.h>

#define INFLATE_MAXIMUM_BITS 15u
#define INFLATE_FAST_BITS 10u
#define INFLATE_FAST_SIZE 1024u
#define INFLATE_LITERAL_CODES 288u
#define INFLATE_DISTANCE_CODES 32u
#define INFLATE_CODE_LENGTH_CODES 19u
#define INFLATE_LITERAL_LIMIT 286u
#define INFLATE_DISTANCE_LIMIT 30u
#define INFLATE_END_OF_BLOCK 256u
#define INFLATE_ADLER_MODULUS 65521u
#define INFLATE_ADLER_RUN 5552u
#define INFLATE_GZIP_HEADER 10u
#define INFLATE_GZIP_TRAILER 8u

_Static_assert(UINT_MAX == 0xFFFFFFFFu, "inflate: unsigned int must be 32 bits wide for the CRC-32 and Adler-32 words");
_Static_assert(INFLATE_FAST_SIZE == (1u << INFLATE_FAST_BITS),
               "inflate: INFLATE_FAST_SIZE must equal 1 << INFLATE_FAST_BITS");
_Static_assert((INFLATE_LITERAL_CODES << 4u) <= 0xFFFFu,
               "inflate: a fast entry packs symbol << 4 into an unsigned short");

typedef struct
{
    unsigned short counts[INFLATE_MAXIMUM_BITS + 1u];
    unsigned short symbols[INFLATE_LITERAL_CODES];
    unsigned short fast[INFLATE_FAST_SIZE];
} InflateHuffman;

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned long long at;
    unsigned long long bits;
    unsigned int bit_count;
    unsigned char *out;
    unsigned long long out_capacity;
    unsigned long long written;
} InflateStream;

int inflate_take(InflateStream *stream, unsigned int count, unsigned int *value);

void inflate_align(InflateStream *stream);

int inflate_build(InflateHuffman *huffman, const unsigned char *lengths, unsigned int count, int single_permitted);

int inflate_symbol(InflateStream *stream, const InflateHuffman *huffman, unsigned int *symbol);

int inflate_codes(InflateStream *stream, const InflateHuffman *literals, const InflateHuffman *distances);

#endif
