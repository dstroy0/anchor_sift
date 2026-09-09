/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_limbs.h
 * @brief An exact integer held as a fixed width array of limbs, and the operations a measure needs.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note A limb array is a transform of an integer, the same way decimal text is one. The value is
 *       identical in every form. What changes is which machine can work on it.
 *       Python carries the arbitrary precision form, this carries the fixed width form, and a GPU
 *       carries the same fixed width form one warp to a number. No arm is allowed its own
 *       arithmetic doctrine.
 * @note The width is fixed at compile time because a GPU register file cannot grow at run time.
 *       That is the only bound this representation has, and it is declared instead of discovered.
 *       Every entry point refuses a value that will not fit instead of truncating it.
 * @note Base 2^32 with a 64 bit accumulator. Wider limbs would need 128 bit products, which are a
 *       compiler extension on some targets and absent on others. 32 bit limbs also map onto both
 *       SIMD widths this tree builds for and onto a CUDA lane, so one representation serves every
 *       arm.
 * @note The reference implementation is portable C11. Every vectorized arm is checked against it
 *       and is wrong where it disagrees, whatever it measures.
 */
#ifndef ANCHOR_EXACT_LIMBS_H
#define ANCHOR_EXACT_LIMBS_H

#include <stddef.h>
#include <stdint.h>

/**
 * @brief Limbs per exact integer, at 32 bits each.
 *
 * @note 108 limbs is 3456 bits, which holds 1024 decimal digits with room over. That is the scale
 *       representation/exact.py ingests at, and the two forms have to agree on the same values or
 *       a cross check between them means nothing.
 * @note Defined on both arms so #if always has a value and an unset build is never a silent false.
 */
#ifndef ANCHOR_EXACT_LIMBS
#define ANCHOR_EXACT_LIMBS 108u
#endif

/** @brief Decimal digits the fixed width is guaranteed to hold, matching representation.exact. */
#define ANCHOR_EXACT_DIGITS 1024u

/**
 * @brief An exact integer, magnitude in limbs and sign held apart from it.
 *
 * @note Least significant limb first. A carry then walks upward through increasing indices and a
 *       vectorized arm reads the array in the order memory hands it over.
 * @note Sign is held separately instead of as two's complement across the whole array, because a
 *       comparison is the hot operation and comparing magnitudes is a scan from the top limb down.
 *       Zero always carries sign 0, which keeps two zeros from comparing unequal.
 */
typedef struct
{
    uint32_t limb[ANCHOR_EXACT_LIMBS];  /**< Magnitude, least significant limb at index 0. */
    int32_t sign;                       /**< -1, 0 or 1. Zero is the only value carrying 0. */
} AnchorExactInteger;

/** @brief Every entry point returning a status returns one of these. */
typedef enum
{
    ANCHOR_EXACT_OK = 0,          /**< The operation completed and the result is exact. */
    ANCHOR_EXACT_WILL_NOT_FIT,    /**< The value needs more limbs than the width holds. */
    ANCHOR_EXACT_NOT_DECIMAL      /**< The text was not plain decimal, exponent notation included. */
} AnchorExactStatus;

/**
 * @brief Sets an integer to zero.
 *
 * @param[out] value Integer to clear [BORROWS].
 */
void anchor_exact_zero(AnchorExactInteger *value);

/**
 * @brief Whether two integers hold the same value.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 * @note The hot operation. A shift measure asks nothing else of a coordinate, and it asks it once
 *       per point per lag, so this is the call every vectorized arm exists to widen.
 */
int anchor_exact_equal(const AnchorExactInteger *left, const AnchorExactInteger *right);

/**
 * @brief Orders two integers.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1 where left is smaller, 1 where it is larger, 0 where they are equal.
 */
int anchor_exact_compare(const AnchorExactInteger *left, const AnchorExactInteger *right);

/**
 * @brief Adds two integers.
 *
 * @param[in]  left   First addend [BORROWS].
 * @param[in]  right  Second addend [BORROWS].
 * @param[out] result Sum [BORROWS]. May alias either input.
 * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where the sum needs more limbs.
 */
AnchorExactStatus anchor_exact_add(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                   AnchorExactInteger *result);

/**
 * @brief Subtracts the second integer from the first.
 *
 * @param[in]  left   Minuend [BORROWS].
 * @param[in]  right  Subtrahend [BORROWS].
 * @param[out] result Difference [BORROWS]. May alias either input.
 * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where the result needs more
 *                    limbs.
 * @note The difference set a period is read from is built entirely out of this call.
 */
AnchorExactStatus anchor_exact_subtract(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result);

/**
 * @brief Multiplies two integers.
 *
 * @param[in]  left   First factor [BORROWS].
 * @param[in]  right  Second factor [BORROWS].
 * @param[out] result Product [BORROWS]. May alias either input.
 * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where the product needs more
 *                    limbs than the width holds.
 * @note Schoolbook, the right choice at this width. Karatsuba crosses over in the
 *       thousands of limbs and this is a hundred, so the recursion would cost more than it saves.
 * @warning A product overruns the fixed width far sooner than a sum does. Ingesting a coordinate
 *          multiplies a fraction by a cell edge exactly once for that reason.
 */
AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result);

/**
 * @brief Multiplies an integer by ten raised to a power, applying a scale.
 *
 * @param[in,out] value Integer to scale [BORROWS].
 * @param[in]     power How many powers of ten to apply.
 * @return              ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT.
 */
AnchorExactStatus anchor_exact_scale_by_ten(AnchorExactInteger *value, uint32_t power);

/**
 * @brief Reads plain decimal text into an exact integer at a given number of decimal places.
 *
 * @param[in]  text   Decimal text, optionally signed, with an optional bracketed uncertainty that
 *                    is dropped [BORROWS].
 * @param[in]  length How many bytes of text.
 * @param[in]  digits Decimal places to carry the value at.
 * @param[out] value  Where the result is written [BORROWS].
 * @return            ANCHOR_EXACT_OK, ANCHOR_EXACT_NOT_DECIMAL where the text is not plain decimal,
 *                    or ANCHOR_EXACT_WILL_NOT_FIT where the value carries more decimal places than
 *                    `digits` holds or needs more limbs than the width holds.
 * @note Refusing a value with too many places is the same refusal representation.exact makes, and
 *       for the same reason: a scale that rounds is a quantum this end imposed, and it has to be an
 *       error and never a quiet loss.
 */
AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits,
                                            AnchorExactInteger *value);

/**
 * @brief A 64 bit hash of an exact value, for keying a lookup by position.
 *
 * @param[in] value Integer to hash [BORROWS].
 * @return          The hash.
 * @note Two equal values hash the same and that is all this promises. A collision is possible, and
 *       a caller keying a table on it compares the values on a hit instead of trusting the hash.
 *       Trusting it would let two distinct coordinates read as agreeing. The exact path exists to
 *       make that impossible.
 */
uint64_t anchor_exact_hash(const AnchorExactInteger *value);

/**
 * @brief Counts places whose value equals the value one lag away, over a sorted run of positions.
 *
 * @param[in] positions Positions, ascending, each carrying an index into `values` [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test, as an exact integer [BORROWS].
 * @return              How many positions have a position exactly `lag` above them carrying an
 *                      equal value.
 * @note This is the measure itself, and the reason every arm below exists. The portable form walks
 *       the run with a binary search per position. A vectorized form compares many limbs at once
 *       and a GPU form compares many positions at once, and all three return the same count or one
 *       of them has a defect.
 */
size_t anchor_exact_agreement(const AnchorExactInteger *positions, const uint64_t *values,
                              size_t count, const AnchorExactInteger *lag);

#endif /* ANCHOR_EXACT_LIMBS_H */
