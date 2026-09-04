/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file transformo.h
 * @brief Decimal to binary conversion, the limits, the arguments, and the muto dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note take builds a mantissa one digit at a time.
 * @note scale turns one into a double, and scale_to_u64 turns one into an integer.
 */
#ifndef MMGR_TRANSFORMO_H
#define MMGR_TRANSFORMO_H

#include "fractio/fractio.h"
#include "mmgr.h"
#include "pow5/pow5.h"

EMBED_BEGIN_DECLS

/**
 * @brief Expands to the largest mantissa mmgr_muto_take will extend, which is (~0 - 9) / 10.
 *
 * @note Chosen so multiplying by ten and adding a digit of nine both stay inside an embed_u64.
 * @note mmgr_muto_take returns EMBED_FALSE rather than appending once the mantissa passes this.
 * @note Explicit casts hold both the complement and the result at embed_u64, and the 9u and 10u are
 *       suffixed to match, so the subtraction and the divide are done at the mantissa's own width
 *       rather than at int's.
 */
#define MMGR_MUTO_MANT_MAX ((embed_u64)((~(embed_u64)0 - 9u) / 10u))

/**
 * @brief Expands to 400, the count at which a parsed decimal exponent stops accumulating.
 *
 * @note cellul_expo tests its running exponent against this before each multiply and add, so a long run
 *       of digits cannot run the count away with the embed_iword it is kept in.
 * @note 400 is past the 308 a double reaches, so anything the clamp holds back has already gone to a
 *       signed infinity or a signed zero, and stopping the count early cannot change the result.
 * @note The literal is untyped, matching the embed_iword exponent it is compared against.
 */
#define MMGR_MUTO_EXP_LIMIT 400

/**
 * @brief Arguments for the three muto calls.
 *
 * @note take reads mant and digit.
 * @note scale reads mant, ex, rest and neg.
 * @note scale_to_u64 reads mant, e2 and ex.
 * @warning mant is written through by take, so the caller's mantissa changes [BORROWS].
 */
typedef struct
{
    embed_u64 *const mant;  /**< The mantissa, extended by take and read by both scaling calls [BORROWS]. */
    const char digit;       /**< ASCII decimal digit take appends. */
    const embed_iword e2;   /**< Binary exponent the mantissa already carries, read by scale_to_u64. */
    const embed_iword ex;   /**< Decimal exponent to apply. */
    const embed_iword rest; /**< Non-zero when the caller already dropped bits, so rounding can see them. */
    const embed_bool neg;   /**< Sign scale gives its result. */
} TransformoCfg;

/**
 * @brief Type of the muto dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the three members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    embed_bool (*take)(const TransformoCfg *args);        /**< Appends one decimal digit to a mantissa. */
    double (*scale)(const TransformoCfg *args);           /**< Turns a mantissa and decimal exponent into a double. */
    embed_u64 (*scale_to_u64)(const TransformoCfg *args); /**< Turns the same plus e2 into a rounded 64-bit integer. */
} TransformoNs;
EMBED_TABLE_LAYOUT(TransformoNs, take, scale, scale_to_u64);

/**
 * @brief Appends args->digit to *args->mant as one more decimal digit.
 *
 * @param[in] args The mantissa to extend and the digit to append [BORROWS].
 * @return         EMBED_TRUE when the digit was appended, EMBED_FALSE when *args->mant already passed
 *                 MMGR_MUTO_MANT_MAX.
 * @note On EMBED_FALSE the mantissa is left as it was, so a caller can count the digits it had to drop.
 * @warning args->digit must be an ASCII decimal digit, since the value added is args->digit minus '0'.
 * @warning Writes through args->mant [BORROWS].
 */
embed_bool mmgr_muto_take(const TransformoCfg *args);

/**
 * @brief Turns *args->mant times ten raised to args->ex into a double, signed by args->neg.
 *
 * @param[in] args The mantissa, the decimal exponent, the dropped bits and the sign [BORROWS].
 * @return         The nearest double, with ties going to even.
 * @note Set args->rest when digits were dropped from the mantissa, so the rounding still accounts for them.
 * @note Takes a plain double path when nothing was dropped, the mantissa is under 2^53 and args->ex is within 22.
 * @note Does not read args->e2, so the mantissa is taken as a plain integer.
 * @warning Returns a signed infinity for an args->ex above MMGR_POW5_MAX and a signed zero below its negative.
 */
double mmgr_muto_scale(const TransformoCfg *args);

/**
 * @brief Turns *args->mant times two raised to args->e2 times ten raised to args->ex into a rounded 64-bit integer.
 *
 * @param[in] args The mantissa, its binary exponent and the decimal exponent [BORROWS].
 * @return         The nearest integer with a half going up, 0 when the value rounds below one, or all
 *                 ones when too large.
 * @note Reads args->e2, which mmgr_muto_scale leaves alone, so the mantissa may carry a binary exponent here.
 * @note A half is taken up whatever lies below it, so the result is the magnitude rounded away from
 *       zero. mmgr_muto_scale rounds its own halves to even, which is what a double wants and what
 *       this deliberately does not do.
 * @note Reads neither args->rest, args->above nor args->neg, so the result is always unsigned.
 * @warning Does not bound args->ex against MMGR_POW5_MAX the way mmgr_muto_scale does. Only
 *          MMGR_POW5_STEPS bits of the magnitude are walked, so a larger exponent loses its high
 *          bits and the value scaled is not the one asked for.
 */
embed_u64 mmgr_muto_scale_to_u64(const TransformoCfg *args);

/**
 * @brief Dispatch table instance named muto, with each member set to its mmgr_muto_ function.
 */
EMBED_TABLE_STORAGE TransformoNs muto EMBED_UNUSED = {
    .take = mmgr_muto_take,
    .scale = mmgr_muto_scale,
    .scale_to_u64 = mmgr_muto_scale_to_u64,
};

EMBED_END_DECLS

#endif
