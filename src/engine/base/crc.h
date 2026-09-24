// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CRC_H
#define CRC_H

#include "crc_key.h"

#ifdef __CUDACC__
#define CRC_FUNCTION __host__ __device__ static inline
#else
#define CRC_FUNCTION static inline
#endif

#define CRC_SEGMENT_PIXELS 64ull

#define CRC_SEGMENT_POWER 7u

#define CRC_CHECK 0x995DC9BBDF1939FAull

static constexpr unsigned long long CRC_TABLE[256] = CRC_KEY_TABLE;

static constexpr unsigned long long CRC_ADVANCE[CRC_KEY_POWERS][64] = CRC_KEY_ADVANCE;

#ifdef __CUDACC__
__device__ static const unsigned long long CRC_TABLE_DEVICE[256] = CRC_KEY_TABLE;

__device__ static const unsigned long long CRC_ADVANCE_DEVICE[CRC_KEY_POWERS][64] = CRC_KEY_ADVANCE;
#endif

CRC_FUNCTION unsigned long long crc_step(const unsigned long long *table, unsigned long long crc, unsigned int byte)
{
    return table[(crc ^ byte) & 0xFFull] ^ (crc >> 8u);
}

CRC_FUNCTION unsigned long long crc_pixel(const unsigned long long *table, unsigned long long crc, unsigned int pixel)
{
    return crc_step(table, crc_step(table, crc, pixel & 0xFFu), (pixel >> 8u) & 0xFFu);
}

CRC_FUNCTION unsigned long long crc_words(const unsigned long long *table, const unsigned long long *words,
                                          unsigned long long count)
{
    unsigned long long crc = ~0ull;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        for (unsigned int place = 0u; place < 8u; place += 1u)
        {
            crc = crc_step(table, crc, (unsigned int)((words[at] >> (8u * place)) & 0xFFull));
        }
    }
    return ~crc;
}

CRC_FUNCTION unsigned long long crc_apply(const unsigned long long *columns, unsigned long long crc)
{
    unsigned long long carried = 0ull;
    for (unsigned int column = 0u; column < 64u; column += 1u)
    {
        carried ^= (((crc >> column) & 1ull) != 0ull) ? columns[column] : 0ull;
    }
    return carried;
}

CRC_FUNCTION unsigned long long crc_finish(const unsigned long long (*advance)[64], unsigned long long from_zero,
                                           unsigned long long bytes)
{
    unsigned long long start = ~0ull;
    for (unsigned int power = 0u; (power < CRC_KEY_POWERS) && ((bytes >> power) != 0ull); power += 1u)
    {
        start = (((bytes >> power) & 1ull) != 0ull) ? crc_apply(advance[power], start) : start;
    }
    return ~(from_zero ^ start);
}

static constexpr unsigned long long crc_check_carry(unsigned long long crc, const char *bytes, unsigned int count)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        crc = CRC_TABLE[(crc ^ (unsigned long long)(unsigned char)bytes[at]) & 0xFFull] ^ (crc >> 8u);
    }
    return crc;
}

static constexpr unsigned long long crc_check_apply(unsigned int power, unsigned long long crc)
{
    unsigned long long carried = 0ull;
    for (unsigned int column = 0u; column < 64u; column += 1u)
    {
        carried ^= (((crc >> column) & 1ull) != 0ull) ? CRC_ADVANCE[power][column] : 0ull;
    }
    return carried;
}

static_assert((crc_check_carry(~0ull, "123456789", 9u) ^ ~0ull) == CRC_CHECK,
              "the CRC key must give CRC-64/XZ's published check value for 123456789");
static_assert(crc_check_carry(0ull, "123456789", 9u)
                  == (crc_check_apply(2u, crc_check_apply(0u, crc_check_carry(0ull, "1234", 4u)))
                      ^ crc_check_carry(0ull, "56789", 5u)),
              "a fold of the CRC key must equal the message taken in order");

#endif
