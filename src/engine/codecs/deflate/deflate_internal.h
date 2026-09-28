// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the deflate_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef DEFLATE_INTERNAL_H
#define DEFLATE_INTERNAL_H

#include "deflate.h"

#include <stdlib.h>
#include <string.h>

#define DEFLATE_WINDOW 32768ull
#define DEFLATE_MATCH_FLOOR 3ull
#define DEFLATE_MATCH_CEILING 258ull
#define DEFLATE_STORED_CEILING 65535ull
#define DEFLATE_STORED_FRAME 5ull
#define DEFLATE_KEYS (1ull << 24u)
#define DEFLATE_LITERAL_CODES 286u
#define DEFLATE_DISTANCE_CODES 30u
#define DEFLATE_CODE_LENGTH_CODES 19u
#define DEFLATE_END_OF_BLOCK 256u
#define DEFLATE_CODE_BITS 15u
#define DEFLATE_CODE_LENGTH_BITS 7u
#define DEFLATE_LENGTH_SLOTS 29u

typedef struct
{
    unsigned short length;
    unsigned short value;
} DeflateToken;

typedef struct
{
    unsigned long long weight;
    unsigned int leaf;
    unsigned int left;
    unsigned int right;
} DeflateNode;

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned long long *heads;
    unsigned long long *previous;
    unsigned long long mask;
    unsigned int key_bits;
} DeflateMatcher;

typedef struct
{
    unsigned char *out;
    unsigned long long capacity;
    unsigned long long written;
    unsigned long long bits;
    unsigned int count;
    int overflow;
} DeflateWriter;

typedef struct
{
    unsigned char lengths[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned int codes[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned char code_length_lengths[DEFLATE_CODE_LENGTH_CODES];
    unsigned int code_length_codes[DEFLATE_CODE_LENGTH_CODES];
    unsigned char run_symbols[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned char run_extras[DEFLATE_LITERAL_CODES + DEFLATE_DISTANCE_CODES];
    unsigned int run_count;
    unsigned int literal_count;
    unsigned int distance_count;
    unsigned int code_length_count;
} DeflateTrees;

static const unsigned short deflate_length_base[DEFLATE_LENGTH_SLOTS] = {
    3u,  4u,  5u,  6u,  7u,  8u,  9u,  10u, 11u,  13u,  15u,  17u,  19u,  23u, 27u,
    31u, 35u, 43u, 51u, 59u, 67u, 83u, 99u, 115u, 131u, 163u, 195u, 227u, 258u};

static const unsigned short deflate_distance_base[DEFLATE_DISTANCE_CODES] = {
    1u,   2u,   3u,   4u,   5u,   7u,    9u,    13u,   17u,   25u,   33u,   49u,   65u,    97u,    129u,
    193u, 257u, 385u, 513u, 769u, 1025u, 1537u, 2049u, 3073u, 4097u, 6145u, 8193u, 12289u, 16385u, 24577u};

unsigned int deflate_length_slot(unsigned int length);

unsigned int deflate_distance_slot(unsigned int distance);

unsigned long long deflate_parse(DeflateMatcher *matcher, DeflateToken *tokens);

int deflate_lengths(const unsigned long long *frequency, unsigned int count, unsigned int limit,
                    unsigned char *lengths);

void deflate_codes(const unsigned char *lengths, unsigned int count, unsigned int *codes);

#endif
