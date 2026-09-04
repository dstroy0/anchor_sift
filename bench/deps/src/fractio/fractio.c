/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file fractio.c
 * @brief Field access on the bit pattern of a binary64 double: the three field reads, the merge back,
 *        and the two reinterpretations of the same storage.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 */
#include "fractio/fractio.h"

/**
 * @brief Arguments for every fract backend, grouped by the calls that read them.
 *
 * @note Mirrors FractioCfg without its const qualifiers, union included.
 * @note val and bits share storage, so writing one and reading the other reinterprets the same bytes.
 */
typedef struct
{
    union {
        double val;     /**< The value, when the caller supplies a double. */
        embed_u64 bits; /**< The same storage read as a bit pattern. */
    };
    embed_u64 sign; /**< Sign for merge, 0 or 1. */
    embed_u64 exp;  /**< Biased exponent for merge. */
    embed_u64 mant; /**< Stored mantissa for merge. */
} FractioCtx;

/**
 * @brief Returns the sign bit of args->bits, as 0 or 1.
 *
 * @param[in] args Bit pattern to read [BORROWS].
 * @return         0 for a positive value, 1 for a negative one.
 */
EMBED_INLINE embed_u64 fract_sign(const FractioCtx *args)
{
    return (args->bits & MMGR_DBL_SIGN_MASK) >> MMGR_DBL_SIGN_SHIFT;
}

/**
 * @brief Returns the raw exponent field of args->bits, still biased.
 *
 * @param[in] args Bit pattern to read [BORROWS].
 * @return         The stored exponent, with MMGR_DBL_BIAS not yet removed.
 * @note 0 marks a zero or subnormal. MMGR_DBL_EXP_ALL marks an infinity or NaN.
 */
EMBED_INLINE embed_u64 fract_exp(const FractioCtx *args)
{
    return (args->bits & MMGR_DBL_EXP_MASK) >> MMGR_DBL_MANT_BITS;
}

/**
 * @brief Returns the stored mantissa field of args->bits, without the implicit leading bit.
 *
 * @param[in] args Bit pattern to read [BORROWS].
 * @return         The stored mantissa alone.
 */
EMBED_INLINE embed_u64 fract_mant(const FractioCtx *args)
{
    return args->bits & MMGR_DBL_MANT_MASK;
}

/**
 * @brief Packs args->sign, args->exp and args->mant back into one bit pattern.
 *
 * @param[in] args The three fields to pack [BORROWS].
 * @return         The assembled bit pattern.
 * @note Each field is masked to its own width first, so a wide input cannot reach a neighbor.
 */
EMBED_INLINE embed_u64 fract_merge(const FractioCtx *args)
{
    return ((args->sign & MMGR_DBL_SIGN_ONE) << MMGR_DBL_SIGN_SHIFT) |
           ((args->exp & MMGR_DBL_EXP_ALL) << MMGR_DBL_MANT_BITS) | (args->mant & MMGR_DBL_MANT_MASK);
}

/**
 * @brief Reads the union as a double after the caller filled its bits member.
 *
 * @param[in] args Union holding the pattern [BORROWS].
 * @return         The same storage read as a double.
 */
EMBED_INLINE double fract_from_bits(const FractioCtx *args)
{
    return args->val;
}

/**
 * @brief Reads the union as a bit pattern after the caller filled its val member.
 *
 * @param[in] args Union holding the value [BORROWS].
 * @return         The same storage read as a bit pattern.
 */
EMBED_INLINE embed_u64 fract_to_bits(const FractioCtx *args)
{
    return args->bits;
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_fract_ and fract_ prefixes, which the two share.
 * @param[in] ...         Initializers for the FractioCtx literal, written in terms of args.
 * @note The six entries differ only in what they forward, so the prefixes and the two structure types
 *       are named once here and the table below states only what each entry reads.
 */
#define FRACT_ENTRY(ReturnType_, name_, ...)                                                                           \
    EMBED_ENTRY(mmgr_fract_, fract_, FractioCtx, FractioCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in fractio.h.
 * @note The five union lines forward the member the caller filled. merge forwards its three fields
 *       instead. from_bits is given bits and reads val, to_bits is given val and reads bits, which is
 *       the reinterpretation both exist for.
 */
FRACT_ENTRY(embed_u64, sign, .bits = args->bits)
FRACT_ENTRY(embed_u64, exp, .bits = args->bits)
FRACT_ENTRY(embed_u64, mant, .bits = args->bits)
FRACT_ENTRY(embed_u64, merge, .sign = args->sign, .exp = args->exp, .mant = args->mant)
FRACT_ENTRY(double, from_bits, .bits = args->bits)
FRACT_ENTRY(embed_u64, to_bits, .val = args->val)
