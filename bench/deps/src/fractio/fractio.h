/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file fractio.h
 * @brief The binary64 field layout and scale bounds, the assertions that pin them, the six entry points
 *        and the fract table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Everything here is written for binary64. The assertions below are what hold the target to it,
 *       and they are EMBED_STATIC_ASSERT, so a target whose double is another shape fails the build
 *       rather than reading the wrong bits.
 * @note FractioCfg carries no pointer, so no call here follows one into a caller's buffer. The whole
 *       module is field arithmetic on the one value it is handed.
 * @warning args is the one pointer the six entry points take, and none of them tests it. The bodies
 *          EMBED_ENTRY writes read its members straight through, so a null args is dereferenced.
 */
#ifndef MMGR_FRACTIO_H
#define MMGR_FRACTIO_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief The binary64 field layout: three masks, the sign shift, the two field widths, the two whole
 *        field values and the exponent bias.
 *
 * @note The masks, the shift and the widths give each field's position and extent. MMGR_DBL_SIGN_ONE
 *       and MMGR_DBL_EXP_ALL are values a field can hold rather than positions, and MMGR_DBL_BIAS is
 *       an amount.
 * @note The assertions below check the masks tile the word without gap or overlap.
 * @note The masks, MMGR_DBL_SIGN_ONE and MMGR_DBL_EXP_ALL carry a ull suffix, matching the embed_u64 the
 *       fields are read from. The shifts and widths carry u. MMGR_DBL_BIAS carries neither, since it is
 *       subtracted in the signed scale arithmetic below.
 */
#define MMGR_DBL_SIGN_MASK 0x8000000000000000ull /**< The sign bit. */
#define MMGR_DBL_EXP_MASK 0x7FF0000000000000ull  /**< The eleven exponent bits. */
#define MMGR_DBL_MANT_MASK 0x000FFFFFFFFFFFFFull /**< The fifty-two stored mantissa bits. */
#define MMGR_DBL_SIGN_SHIFT 63u                  /**< Bit position of the sign. */
#define MMGR_DBL_MANT_BITS 52u                   /**< Stored mantissa width, and the exponent's shift. */
#define MMGR_DBL_EXP_BITS 11u                    /**< Exponent width. */
#define MMGR_DBL_SIGN_ONE 0x1ull                 /**< A sign of one, and merge's mask for args->sign. */
#define MMGR_DBL_EXP_ALL 0x7FFull                /**< All ones in the exponent, and merge's mask for args->exp. */
#define MMGR_DBL_BIAS 1023                       /**< Amount added to the true exponent when stored. */

/**
 * @brief The width of a double in bits, bytes and embed_word units.
 *
 * @note MMGR_DBL_BITS is declared, not measured. The assertion below compares it against sizeof(double)
 *       and fails the build when the target disagrees.
 * @note The 8u in MMGR_DBL_BYTES is bits per byte. That same assertion holds a target to it, since a
 *       byte of another width would leave sizeof(double) * 8u short of MMGR_DBL_BITS.
 * @note MMGR_DBL_WORDS rounds up, and the assertion below requires it to come out exact.
 */
#define MMGR_DBL_BITS 64u                   /**< Bits in a double. */
#define MMGR_DBL_BYTES (MMGR_DBL_BITS / 8u) /**< Bytes in a double. */
#define MMGR_DBL_WORDS                                                                                                 \
    ((MMGR_DBL_BITS + (EMBED_WORD_BITS - 1u)) / EMBED_WORD_BITS) /**< embed_word units per double.                     \
                                                                  */

/**
 * @brief Pins the target's double to the width and storage this file assumes.
 *
 * @note Checks the bit width, that a double is a whole number of embed_word units, and that embed_u64 holds it.
 */
EMBED_STATIC_ASSERT(sizeof(double) * 8u == MMGR_DBL_BITS,
                    "double is not 64 bits on this target, so every field position in this file is wrong "
                    "- a build where double means float cannot use it");
EMBED_STATIC_ASSERT(MMGR_DBL_WORDS *EMBED_WORD_BITS == MMGR_DBL_BITS,
                    "a double is not a whole number of words on this target");
EMBED_STATIC_ASSERT(sizeof(embed_u64) == sizeof(double), "the bit pattern of a double does not fit embed_u64");

/**
 * @brief Pins the field constants above against each other.
 *
 * @note Checks the widths sum to 64, the masks tile the word, and no two masks overlap.
 * @note Also checks each mask against the shift or width for the same field, that MMGR_DBL_EXP_ALL fills
 *       MMGR_DBL_EXP_BITS, and that MMGR_DBL_BIAS is half the exponent range less one.
 */
EMBED_STATIC_ASSERT(1u + MMGR_DBL_EXP_BITS + MMGR_DBL_MANT_BITS == MMGR_DBL_BITS,
                    "the three fields do not add up to the width of the value");
EMBED_STATIC_ASSERT((MMGR_DBL_SIGN_MASK | MMGR_DBL_EXP_MASK | MMGR_DBL_MANT_MASK) == 0xFFFFFFFFFFFFFFFFull,
                    "the three field masks leave a gap");
EMBED_STATIC_ASSERT((MMGR_DBL_SIGN_MASK & MMGR_DBL_EXP_MASK) == 0u && (MMGR_DBL_EXP_MASK & MMGR_DBL_MANT_MASK) == 0u &&
                        (MMGR_DBL_SIGN_MASK & MMGR_DBL_MANT_MASK) == 0u,
                    "the three field masks overlap");
EMBED_STATIC_ASSERT(MMGR_DBL_SIGN_MASK == (MMGR_DBL_SIGN_ONE << MMGR_DBL_SIGN_SHIFT),
                    "the sign mask and the sign shift disagree about where the sign is");
EMBED_STATIC_ASSERT(MMGR_DBL_EXP_MASK == (MMGR_DBL_EXP_ALL << MMGR_DBL_MANT_BITS),
                    "the exponent mask and the exponent width disagree");
EMBED_STATIC_ASSERT(MMGR_DBL_EXP_ALL == ((1u << MMGR_DBL_EXP_BITS) - 1u), "the exponent does not fill its field");
EMBED_STATIC_ASSERT(MMGR_DBL_BIAS == ((1 << (MMGR_DBL_EXP_BITS - 1u)) - 1), "the bias is not the one binary64 uses");

/**
 * @brief The range of powers of two a double can carry once the mantissa is treated as an integer.
 *
 * @note MMGR_DBL_SCALE_MAX takes the largest finite exponent, removes the bias, and drops the mantissa width.
 * @note MMGR_DBL_SCALE_MIN starts from an exponent field of 1, which is the smallest normal.
 * @note Explicit casts hold both expressions in embed_iword, since MMGR_DBL_EXP_ALL and MMGR_DBL_MANT_BITS
 *       are unsigned. MMGR_DBL_SCALE_MIN is negative, and without its cast the subtraction would wrap.
 */
#define MMGR_DBL_SCALE_MAX ((embed_iword)(MMGR_DBL_EXP_ALL - 1u) - MMGR_DBL_BIAS - (embed_iword)MMGR_DBL_MANT_BITS)
#define MMGR_DBL_SCALE_MIN (1 - MMGR_DBL_BIAS - (embed_iword)MMGR_DBL_MANT_BITS)

/**
 * @brief Pins the two scale bounds to the values binary64 gives.
 */
EMBED_STATIC_ASSERT(MMGR_DBL_SCALE_MAX == 971, "the largest scale a finite double can carry is not what it was");
EMBED_STATIC_ASSERT(MMGR_DBL_SCALE_MIN == -1074, "the smallest scale a subnormal can carry is not what it was");

/**
 * @brief Arguments for the fract calls, where each call reads only the members it needs.
 *
 * @note val and bits share storage, so writing one and reading the other reinterprets the same bytes.
 * @note sign, exp and mant are read by merge alone. The other five calls read the union.
 */
typedef struct
{
    union {
        const double val;     /**< The value, when the caller supplies a double. */
        const embed_u64 bits; /**< The same storage read as a bit pattern. */
    };
    const embed_u64 sign; /**< Sign for merge, 0 or 1. */
    const embed_u64 exp;  /**< Biased exponent for merge. */
    const embed_u64 mant; /**< Stored mantissa for merge. */
} FractioCfg;

/**
 * @brief Type of the fract dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the six members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    embed_u64 (*sign)(const FractioCfg *args);    /**< Sign bit of bits, as 0 or 1. */
    embed_u64 (*exp)(const FractioCfg *args);     /**< Biased exponent field of bits. */
    embed_u64 (*mant)(const FractioCfg *args);    /**< Stored mantissa field of bits. */
    embed_u64 (*merge)(const FractioCfg *args);   /**< Packs sign, exp and mant into one pattern. */
    double (*from_bits)(const FractioCfg *args);  /**< Reads the union as a double. */
    embed_u64 (*to_bits)(const FractioCfg *args); /**< Reads the union as a bit pattern. */
} FractioNs;
EMBED_TABLE_LAYOUT(FractioNs, sign, exp, mant, merge, from_bits, to_bits);

/**
 * @brief Returns the sign bit of args->bits.
 *
 * @param[in] args Bit pattern in the union [BORROWS].
 * @return         0 for a positive sign, 1 for a negative one.
 * @note The bit is read as stored and nothing else is examined, so a negative zero answers 1, and so
 *       does a NaN carrying the sign.
 */
embed_u64 mmgr_fract_sign(const FractioCfg *args);

/**
 * @brief Returns the exponent field of args->bits.
 *
 * @param[in] args Bit pattern in the union [BORROWS].
 * @return         The stored exponent, still carrying MMGR_DBL_BIAS.
 * @note 0 marks a zero or subnormal. MMGR_DBL_EXP_ALL marks an infinity or NaN.
 */
embed_u64 mmgr_fract_exp(const FractioCfg *args);

/**
 * @brief Returns the mantissa field of args->bits.
 *
 * @param[in] args Bit pattern in the union [BORROWS].
 * @return         The fifty-two stored bits, without the implicit leading one.
 * @note The leading one is implicit only where the exponent field is nonzero. A zero or a subnormal
 *       has none, and there these fifty-two bits are the whole mantissa.
 */
embed_u64 mmgr_fract_mant(const FractioCfg *args);

/**
 * @brief Packs args->sign, args->exp and args->mant into one bit pattern.
 *
 * @param[in] args The three fields [BORROWS].
 * @return         The assembled pattern.
 * @note Each field is masked to its own width, so a wide input cannot reach a neighboring field.
 * @warning What the mask drops is gone and nothing reports it. A sign above MMGR_DBL_SIGN_ONE, an
 *          exponent above MMGR_DBL_EXP_ALL or a mantissa above MMGR_DBL_MANT_MASK keeps only its low
 *          bits.
 */
embed_u64 mmgr_fract_merge(const FractioCfg *args);

/**
 * @brief Reads the union as a double.
 *
 * @param[in] args Union with its bits member filled [BORROWS].
 * @return         The same storage interpreted as a double.
 */
double mmgr_fract_from_bits(const FractioCfg *args);

/**
 * @brief Reads the union as a bit pattern.
 *
 * @param[in] args Union with its val member filled [BORROWS].
 * @return         The same storage interpreted as embed_u64.
 */
embed_u64 mmgr_fract_to_bits(const FractioCfg *args);

/**
 * @brief Dispatch table instance named fract, whose members are the mmgr_fract_ entries.
 *
 * @note EMBED_TABLE_STORAGE is static const, so every translation unit including this header holds a copy of its
 *       own and the addresses differ between them. The six functions it points at are the one shared
 *       definition.
 * @note EMBED_UNUSED keeps a translation unit that includes the header without calling through the
 *       table from warning about it. It expands to nothing where the unused attribute is unavailable.
 */
EMBED_TABLE_STORAGE FractioNs fract EMBED_UNUSED = {
    .sign = mmgr_fract_sign,
    .exp = mmgr_fract_exp,
    .mant = mmgr_fract_mant,
    .merge = mmgr_fract_merge,
    .from_bits = mmgr_fract_from_bits,
    .to_bits = mmgr_fract_to_bits,
};

EMBED_END_DECLS

#endif
