// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SCRIPTURA_H
#define SCRIPTURA_H

#include "engine_config.h"

#include <stdio.h>
#include <string.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SCRIPTURA_WORD_BYTES 8u
#define SCRIPTURA_WORD_BITS 64u
#define SCRIPTURA_ONES 0x0101010101010101ull
#define SCRIPTURA_HIGH 0x8080808080808080ull
#define SCRIPTURA_LOW_SEVEN 0x7F7F7F7F7F7F7F7Full
#define SCRIPTURA_ALL 0xFFFFFFFFFFFFFFFFull
#define SCRIPTURA_FAMILY_CASE 0x60u
#define SCRIPTURA_FAMILY_CAPITALS 0x40u
#define SCRIPTURA_FAMILY_DIGITS 0xF0u
#define SCRIPTURA_BLOCK_DIGITS 0x30u

#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#error "scriptura: the lane walks read words little endian, so the first lane in memory is the lowest"
#endif

typedef struct
{
    char *out;
    unsigned long long room;
    unsigned long long at;
} ScripturaLine;

void scriptura_counted(ScripturaLine *line, const char *text, unsigned long long length);

void scriptura_text(ScripturaLine *line, const char *text);

void scriptura_text_columns(ScripturaLine *line, const char *text, unsigned int columns);

void scriptura_character(ScripturaLine *line, char character);

void scriptura_decimal(ScripturaLine *line, unsigned long long value, unsigned int digits_least);

void scriptura_decimal_columns(ScripturaLine *line, unsigned long long value, unsigned int columns);

void scriptura_signed(ScripturaLine *line, long long value);

void scriptura_hex(ScripturaLine *line, unsigned long long value, unsigned int digits_least);

unsigned long long scriptura_finish(ScripturaLine *line);

int scriptura_held(const ScripturaLine *line);

int scriptura_write(ScripturaLine *line, FILE *file);

unsigned long long scriptura_length(const char *text, unsigned long long room);

unsigned long long scriptura_find(const void *from, unsigned char value, unsigned long long bytes);

void scriptura_copy(void *to, const void *from, unsigned long long bytes);

void scriptura_move_up(void *to, const void *from, unsigned long long bytes);

int scriptura_compare(const void *one, const void *other, unsigned long long bytes);

void scriptura_fill(void *to, unsigned char value, unsigned long long bytes);

const char *scriptura_arm(void);

static inline unsigned long long scriptura_word_load(const void *at)
{
    unsigned long long word = 0ull;
    memcpy(&word, at, SCRIPTURA_WORD_BYTES);
    return word;
}

static inline void scriptura_word_store(void *at, unsigned long long word)
{
    memcpy(at, &word, SCRIPTURA_WORD_BYTES);
}

static inline unsigned long long scriptura_word_count(unsigned long long bytes)
{
    return (bytes / SCRIPTURA_WORD_BYTES) + (((bytes & (SCRIPTURA_WORD_BYTES - 1u)) != 0ull) ? 1ull : 0ull);
}

static inline unsigned long long scriptura_lane_at_least(unsigned long long word, unsigned char byte)
{
    return (word & SCRIPTURA_HIGH) | (((word | SCRIPTURA_HIGH) - (SCRIPTURA_ONES * byte)) & SCRIPTURA_HIGH);
}

static inline unsigned long long scriptura_lane_at_most(unsigned long long word, unsigned char byte)
{
    return ~word & ((((SCRIPTURA_ONES * byte) | SCRIPTURA_HIGH) - (word & ~SCRIPTURA_HIGH)) & SCRIPTURA_HIGH);
}

static inline unsigned long long scriptura_lane_difference_seven(unsigned long long word, unsigned char byte)
{
    return ((word | SCRIPTURA_HIGH) - (SCRIPTURA_ONES * byte)) & SCRIPTURA_LOW_SEVEN;
}

static inline unsigned long long scriptura_lane_zero(unsigned long long word)
{
    return ~(((word & SCRIPTURA_LOW_SEVEN) + SCRIPTURA_LOW_SEVEN) | word) & SCRIPTURA_HIGH;
}

static inline unsigned long long scriptura_lane_letter(unsigned long long word)
{
    const unsigned long long lowered = word | (SCRIPTURA_ONES * 0x20u);
    const unsigned long long in_range = lowered & SCRIPTURA_LOW_SEVEN;
    return scriptura_lane_at_least(in_range, 'a') & scriptura_lane_at_most(in_range, 'z') & ~lowered;
}

static inline unsigned long long scriptura_lane_differ(unsigned long long word, unsigned long long other,
                                                       int ignore_case)
{
    const unsigned long long difference = word ^ other;
    return (ignore_case == 0) ? difference : (difference & ~(scriptura_lane_letter(word) >> 2u));
}

static inline unsigned long long scriptura_lane_equal(unsigned long long word, unsigned char byte, int ignore_case)
{
    return scriptura_lane_zero(scriptura_lane_differ(word, SCRIPTURA_ONES * byte, ignore_case));
}

static inline unsigned long long scriptura_lane_family_equal(unsigned long long word, unsigned char byte,
                                                             unsigned char family)
{
    return scriptura_lane_zero((word & (SCRIPTURA_ONES * family)) ^ (SCRIPTURA_ONES * (byte & family)));
}

static inline unsigned long long scriptura_lane_capital_block(unsigned long long word)
{
    return scriptura_lane_family_equal(word, SCRIPTURA_FAMILY_CAPITALS, SCRIPTURA_FAMILY_CASE);
}

static inline unsigned long long scriptura_lane_digit_block(unsigned long long word)
{
    return scriptura_lane_family_equal(word, SCRIPTURA_BLOCK_DIGITS, SCRIPTURA_FAMILY_DIGITS);
}

static inline unsigned long long scriptura_lane_count(unsigned long long mask)
{
    return ((mask >> 7u) * SCRIPTURA_ONES) >> (SCRIPTURA_WORD_BITS - 8u);
}

static inline unsigned long long scriptura_lane_lowest(unsigned long long mask)
{
    if (mask == 0ull)
    {
        return SCRIPTURA_WORD_BYTES;
    }
#if ENGINE_HAS_BUILTIN(__builtin_ctzll)
    // the trailing count of a non-zero 64 bit mask is 0 to 63, and over eight it is the lane index
    return (unsigned long long)((unsigned int)__builtin_ctzll(mask) >> 3u);
#elif defined(_MSC_VER)
    unsigned long index = 0ul;
    _BitScanForward64(&index, mask);
    // the bit index of a non-zero 64 bit mask is 0 to 63, and over eight it is the lane index
    return (unsigned long long)(index >> 3u);
#else
    return scriptura_lane_count((mask - 1ull) & ~mask & SCRIPTURA_HIGH);
#endif
}

static inline unsigned long long scriptura_mask_smear(unsigned long long mask)
{
    unsigned long long smeared = mask;
    for (unsigned int shift = 8u; shift < SCRIPTURA_WORD_BITS; shift <<= 1u)
    {
        smeared |= smeared >> shift;
    }
    return smeared;
}

static inline unsigned long long scriptura_lane_highest(unsigned long long mask)
{
    if (mask == 0ull)
    {
        return SCRIPTURA_WORD_BYTES;
    }
    return scriptura_lane_count(scriptura_mask_smear(mask)) - 1ull;
}

static inline unsigned long long scriptura_mask_spread(unsigned long long mask)
{
    return mask + (mask - (mask >> 7u));
}

static inline unsigned long long scriptura_mask_drop_lowest(unsigned long long mask)
{
    return mask & (mask - 1ull);
}

static inline unsigned long long scriptura_mask_drop_highest(unsigned long long mask)
{
    const unsigned long long smeared = scriptura_mask_smear(mask);
    return mask & ~(smeared ^ (smeared >> 8u));
}

static inline unsigned long long scriptura_mask_bytes_below(unsigned long long bytes)
{
    if (bytes == 0ull)
    {
        return 0ull;
    }
    if (bytes >= SCRIPTURA_WORD_BYTES)
    {
        return SCRIPTURA_ALL;
    }
    return SCRIPTURA_ALL >> ((SCRIPTURA_WORD_BYTES - bytes) * 8u);
}

static inline unsigned long long scriptura_mask_lanes_below(unsigned long long bytes)
{
    return scriptura_mask_bytes_below(bytes) & SCRIPTURA_HIGH;
}

static inline unsigned long long scriptura_mask_lanes_before(unsigned long long mask)
{
    return (mask - 1ull) & ~mask & SCRIPTURA_HIGH;
}

static inline unsigned long long scriptura_mask_tail(unsigned long long bytes, unsigned long long words_done)
{
    const unsigned long long done = words_done * SCRIPTURA_WORD_BYTES;
    return (done >= bytes) ? 0ull : scriptura_mask_lanes_below(bytes - done);
}

static inline unsigned long long scriptura_mask_run(unsigned long long mask, unsigned long long bytes)
{
    if (bytes > SCRIPTURA_WORD_BYTES)
    {
        return 0ull;
    }
    unsigned long long starts = mask;
    unsigned long long have = 1ull;
    while (have < bytes)
    {
        const unsigned long long step = (have < (bytes - have)) ? have : (bytes - have);
        starts &= starts >> (step * 8u);
        have += step;
    }
    return starts;
}

static inline unsigned long long scriptura_mask_run_edge(unsigned long long bytes)
{
    if ((bytes <= 1ull) || (bytes > SCRIPTURA_WORD_BYTES))
    {
        return 0ull;
    }
    return SCRIPTURA_HIGH & ~scriptura_mask_lanes_below(SCRIPTURA_WORD_BYTES - bytes + 1ull);
}

static inline unsigned long long scriptura_word_fold_lower(unsigned long long word)
{
    return word | (scriptura_lane_letter(word) >> 2u);
}

#ifdef __cplusplus
}
#endif

#endif
