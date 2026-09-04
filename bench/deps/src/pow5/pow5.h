/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file pow5.h
 * @brief Powers of five as 128-bit significands, for scaling a decimal mantissa into a binary one.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note transformo walks the bits of the decimal exponent and multiplies in one entry per set bit, so nine
 *       entries reach 511.
 * @note Declares no function. Both tables are static const data that outlive every call, so a pointer into
 *       one stays good for the whole program [BORROWS].
 */
#ifndef MMGR_POW5_H
#define MMGR_POW5_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Expands to 9, the number of entries in each table.
 *
 * @note Entry i holds five raised to two to the i, so the nine entries run from 5^1 to 5^256.
 * @note Carries no suffix: it sizes both tables and bounds the walk, where it converts to the signed
 *       embed_iword the loop counts in.
 */
#define MMGR_POW5_STEPS 9

/**
 * @brief Expands to ((1 << 9) - 1), which is 511, the largest decimal exponent the tables reach.
 *
 * @note Every one of the nine entries multiplied together gives 5^511.
 * @note The expansion is a plain int constant expression, which widens to the embed_iword an exponent is
 *       carried in wherever the two are compared.
 * @warning muto_scale bounds against this and returns infinity above it and zero below its negative;
 *          muto_scale_to_u64 does not. What keeps either off the end of the tables is the walk itself,
 *          which takes only MMGR_POW5_STEPS steps, so an exponent past this loses its higher bits.
 */
#define MMGR_POW5_MAX ((1 << MMGR_POW5_STEPS) - 1)

/**
 * @brief One power of five, as a 128-bit significand with a binary exponent.
 *
 * @note The value is (hi * 2^64 + lo) * 2^e2, and hi always has its top bit set.
 */
typedef struct
{
    embed_u64 hi;   /**< High 64 bits of the significand, with its top bit set. */
    embed_u64 lo;   /**< Low 64 bits of the significand. */
    embed_iword e2; /**< Binary exponent the significand is scaled by; -722 at the widest fits a 16-bit embed_iword. */
} MmgrPow5;

/**
 * @brief Five raised to each power of two, from 5^1 at index 0 to 5^256 at index 8.
 *
 * @note Entry i is the multiplier for bit i of the exponent magnitude, and the walk in muto_apply_pow10
 *       takes this table over mmgr_pow5_down whenever the decimal exponent is not negative.
 * @note Index 0 through 5 are exact. 5^64 and up need more than 128 bits, so the last three entries are
 *       truncated toward zero and read a little low.
 * @note Every significand literal carries ULL to match the embed_u64 it is stored in. Each e2 is a bare int
 *       that converts to embed_iword.
 * @note static const at header scope, so each translation unit gets its own copy, EMBED_UNUSED keeps a unit
 *       that never reads it quiet, and an entry's address stays good for the whole program [BORROWS].
 * @warning transformo settles a positive exponent from its exact powers of ten and returns before the walk,
 *          so the only exponent reaching this table there is zero, which sets no bit.
 */
static const MmgrPow5 mmgr_pow5_up[MMGR_POW5_STEPS] EMBED_UNUSED = {
    {0xA000000000000000ULL, 0x0000000000000000ULL, -125}, {0xC800000000000000ULL, 0x0000000000000000ULL, -123},
    {0x9C40000000000000ULL, 0x0000000000000000ULL, -118}, {0xBEBC200000000000ULL, 0x0000000000000000ULL, -109},
    {0x8E1BC9BF04000000ULL, 0x0000000000000000ULL, -90},  {0x9DC5ADA82B70B59DULL, 0xF020000000000000ULL, -53},
    {0xC2781F49FFCFA6D5ULL, 0x3CBF6B71C76B25FBULL, 21},   {0x93BA47C980E98CDFULL, 0xC66F336C36B10137ULL, 170},
    {0xAA7EEBFB9DF9DE8DULL, 0xDDBB901B98FEEAB7ULL, 467},
};

/**
 * @brief The reciprocal of each mmgr_pow5_up entry, from 5^-1 at index 0 to 5^-256 at index 8.
 *
 * @note Entry i is the multiplier for bit i of the exponent magnitude, and the walk in muto_apply_pow10
 *       takes this table when the decimal exponent is negative.
 * @note No negative power of five ends in binary, so all nine are the exact value truncated toward zero.
 *       Every entry reads a little low and none of them round up: 5^-1 is the repeating 0xCCCC..., not the
 *       0xCCCD... that rounding to nearest would give.
 * @note Every significand literal carries ULL to match the embed_u64 it is stored in. Each e2 is a bare int
 *       that converts to embed_iword.
 * @note static const at header scope, so each translation unit gets its own copy, EMBED_UNUSED keeps a unit
 *       that never reads it quiet, and an entry's address stays good for the whole program [BORROWS].
 */
static const MmgrPow5 mmgr_pow5_down[MMGR_POW5_STEPS] EMBED_UNUSED = {
    {0xCCCCCCCCCCCCCCCCULL, 0xCCCCCCCCCCCCCCCCULL, -130}, {0xA3D70A3D70A3D70AULL, 0x3D70A3D70A3D70A3ULL, -132},
    {0xD1B71758E219652BULL, 0xD3C36113404EA4A8ULL, -137}, {0xABCC77118461CEFCULL, 0xFDC20D2B36BA7C3DULL, -146},
    {0xE69594BEC44DE15BULL, 0x4C2EBE687989A9B3ULL, -165}, {0xCFB11EAD453994BAULL, 0x67DE18EDA5814AF2ULL, -202},
    {0xA87FEA27A539E9A5ULL, 0x3F2398D747B36224ULL, -276}, {0xDDD0467C64BCE4A0ULL, 0xAC7CB3F6D05DDBDEULL, -425},
    {0xC0314325637A1939ULL, 0xFA911155FEFB5308ULL, -722},
};

/**
 * @brief Asserts MMGR_POW5_MAX is at least 511.
 *
 * @note A double's decimal exponent stays well inside 511, so nine steps cover every value one can hold.
 */
EMBED_STATIC_ASSERT(MMGR_POW5_MAX >= 511, "the tables do not reach the exponents a double can carry");

EMBED_END_DECLS

#endif
