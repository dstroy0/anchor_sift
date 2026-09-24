/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_integer.h
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
 *       SIMD widths this tree builds for and onto a CUDA lane. One representation serves every
 *       arm.
 * @note The reference implementation is portable C11. Every vectorized arm is checked against it
 *       and is wrong where it disagrees, whatever it measures.
 * @note Division is integer division: a quotient and a remainder, an exact quotient that refuses a
 *       remainder, and a greatest common divisor. A constant that is no integer quotient, such as h
 *       over 2 pi, is still computed in arbitrary precision outside this type and read in as finished
 *       decimal text.
 * @note Multiplication climbs a ladder: long multiplication, then Karatsuba from
 *       ANCHOR_EXACT_KARATSUBA_LIMBS, then the Schonhage-Strassen transform from
 *       ANCHOR_EXACT_TRANSFORM_LIMBS. Division is Knuth's long division, then Newton's reciprocal on
 *       that ladder from ANCHOR_EXACT_NEWTON_LIMBS. Every rung is measured by
 *       test/exact_transform_test and gives the product or quotient the rung below it gives.
 * @note A width-sized working copy sits on the stack up to ANCHOR_EXACT_STACK_LIMBS and is held
 *       from the heap past it; no width is bounded by a stack. Where the heap cannot hold a
 *       copy, the call refuses with ANCHOR_EXACT_WILL_NOT_FIT. A caller holding many integers at a
 *       wide width keeps them in static or allocated storage. A main thread stack defaults to 1 MiB
 *       under the MSVC linker and 8 MiB under a stock Linux.
 */
#ifndef ANCHOR_EXACT_LIMBS_H
#define ANCHOR_EXACT_LIMBS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
/* The GPU arm is compiled as C++ by nvcc and calls straight into these, which are compiled as C.
 * Without this the C++ side would look for mangled names that no C translation unit ever emits. */
extern "C"
{
#endif

/**
 * @brief Limbs per exact integer, at 32 bits each, a power of two for a power-of-two width.
 *
 * @note Given as limbs here or as bits in ANCHOR_EXACT_BITS. The one not given follows from the
 *       other, and both given must agree. The widths are written without casts so #if can weigh
 *       them.
 * @note 128 limbs is 4096 bits, which holds 1024 decimal digits with room over. That is the scale
 *       representation/exact.py ingests at, and the two forms have to agree on the same values or
 *       a cross check between them means nothing.
 * @note The value a limb array carries is the expansion sum(limb[i] * (2^32)^i), whose top
 *       coefficient is the width 2^ANCHOR_EXACT_BITS. A power of two limb count makes that width a
 *       power of two. The top magnitude bit then lands at a fixed position, and the width scales by
 *       doubling, 4096 to 8192 to 16384 bits, with the position fixed at each. The guard below
 *       refuses a width that is not a power of two.
 * @note A build selects any power of two from 1 limb up, 32 bits up, with no ceiling. Every arm is
 *       graded from 1 limb to 32768 by maint/engine/check_exact_widths.sh, and the portable
 *       reference to 4194304 bits by test/exact_transform_test.
 * @note A width below 4096 bits cannot hold the 1024 digit floor. A build selecting one declares
 *       its own ANCHOR_EXACT_DIGITS, and the floor assert below refuses it by name where it does not.
 * @note Defined on both arms so #if always has a value and an unset build is never a silent false.
 */
#if defined(ANCHOR_EXACT_BITS) && !defined(ANCHOR_EXACT_LIMBS)
#define ANCHOR_EXACT_LIMBS ((ANCHOR_EXACT_BITS) / 32ull)
#endif

#ifndef ANCHOR_EXACT_LIMBS
#define ANCHOR_EXACT_LIMBS 128u
#endif

/**
 * @brief Bits the fixed width actually carries. Every size is taken from this or from the limbs.
 */
#ifndef ANCHOR_EXACT_BITS
#define ANCHOR_EXACT_BITS ((ANCHOR_EXACT_LIMBS) * 32ull)
#endif

/**
 * @brief Decimal digits the fixed width is guaranteed to hold, matching representation.exact.
 *
 * @note A declared floor and never the capacity. 128 limbs is 4096 bits, which actually holds 1232
 *       decimal digits. 208 of them are headroom this constant does not promise.
 * @note The floor counts every digit of the stored integer, the integer part of the value included.
 *       A value carried at d decimal places is stored as value times 10^d. At d = 1024 the width
 *       holds a magnitude below 2^4096 / 10^1024, about 1e209, and refuses anything larger. The
 *       CODATA 2022 kilogram-hertz relationship, 1.35639248965e50, needs 3569 bits at 1024 places,
 *       which this width holds and the earlier 3456-bit width refused.
 * @warning Never size a buffer from this. A width computed from digits is short the moment anybody
 *          raises the floor toward the real capacity, and a device allocation sized that way would
 *          be short by exactly the amount nobody was watching. Size from ANCHOR_EXACT_LIMBS or from
 *          sizeof(AnchorExactInteger), which cannot drift apart from the array they describe.
 * @note Defined on both arms, like the limb count. A build can then raise the floor and the assert
 *       below decides whether the width holds it. A knob the build cannot set is a knob whose guard
 *       has never been exercised.
 */
#ifndef ANCHOR_EXACT_DIGITS
#define ANCHOR_EXACT_DIGITS 1024u
#endif

/* The width is a power of two of at least one limb. The expansion's top coefficient
 * 2^ANCHOR_EXACT_BITS is then a power of two and the top magnitude bit sits at a fixed position at
 * every size the build selects. Scaling is by doubling the limb count, 128 to 256 to 512, holding
 * 4096, 8192, 16384 bits. A width that is not a power of two, an override such as the earlier 108
 * limbs, fails compilation here. The power of two test alone passes a width of zero, because
 * 0 & (0 - 1) is 0; the bottom of the range is tested with it. */
/* The declared floor has to fit the width, and the build can decide that. A decimal digit needs
 * log2(10) bits, which is 3.3219, carried here as 3322 parts in a thousand and rounded up so the
 * test is never optimistic. A floor raised past the width fails compilation with this line. */
/* Three arms and every one defined, keyed on what the LANGUAGE offers and not on which
 * compiler is driving. C++ spells it static_assert, C11 spells it _Static_assert, and a C compiler
 * older than C11 has neither, where a negative array width fails at compile time on any of them.
 * Naming a vendor here would only move the hole to the next toolchain that is not that vendor.
 * Unguarded, this header once failed to compile under nvcc, the GPU arm was never built, and a stale
 * bench binary carrying no CUDA symbols went on reporting a "cuda" arm that agreed with the portable
 * one. It agreed because it WAS the portable one. */
#if defined(__cplusplus)
    static_assert(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull)
                      && (((unsigned long long)(ANCHOR_EXACT_BITS) & ((unsigned long long)(ANCHOR_EXACT_BITS) - 1ull)) == 0ull),
                  "ANCHOR_EXACT_BITS must be a power of two of at least 32, so the width scales by doubling");
    static_assert((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull),
                  "ANCHOR_EXACT_BITS and ANCHOR_EXACT_LIMBS must name the same width");
    static_assert(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) + 1ull) <= (unsigned long long)(ANCHOR_EXACT_BITS),
                  "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull)
                   && (((unsigned long long)(ANCHOR_EXACT_BITS) & ((unsigned long long)(ANCHOR_EXACT_BITS) - 1ull)) == 0ull),
               "ANCHOR_EXACT_BITS must be a power of two of at least 32, so the width scales by doubling");
_Static_assert((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull),
               "ANCHOR_EXACT_BITS and ANCHOR_EXACT_LIMBS must name the same width");
_Static_assert(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) + 1ull) <= (unsigned long long)(ANCHOR_EXACT_BITS),
               "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#else
typedef char anchor_exact_bits_are_a_power_of_two[(((unsigned long long)(ANCHOR_EXACT_BITS) >= 32ull)
                                                   && (((unsigned long long)(ANCHOR_EXACT_BITS) & ((unsigned long long)(ANCHOR_EXACT_BITS) - 1ull)) == 0ull))
                                                      ? 1
                                                      : -1];
typedef char anchor_exact_bits_and_limbs_agree[((unsigned long long)(ANCHOR_EXACT_BITS) == ((unsigned long long)(ANCHOR_EXACT_LIMBS) * 32ull)) ? 1 : -1];
typedef char anchor_exact_digits_fit_the_width[(((((unsigned long long)(ANCHOR_EXACT_DIGITS) * 3322ull) / 1000ull) + 1ull) <= (unsigned long long)(ANCHOR_EXACT_BITS)) ? 1 : -1];
#endif

/**
 * @brief The widest width whose working copies are held on the stack, in limbs.
 *
 * @note Past it every width-sized working copy is held from the heap. 4096 limbs is 16 KiB a copy,
 *       and the widest call, the gcd, holds nine of them.
 */
#ifndef ANCHOR_EXACT_STACK_LIMBS
#define ANCHOR_EXACT_STACK_LIMBS 4096u
#endif

/**
 * @brief The shorter factor's limbs from which a product is taken by Karatsuba instead of long
 *        multiplication.
 *
 * @note Karatsuba splits each factor in halves and recurses into three half products; its cost
 *       grows as n^1.585 against the long multiplication's n^2.
 */
#ifndef ANCHOR_EXACT_KARATSUBA_LIMBS
#define ANCHOR_EXACT_KARATSUBA_LIMBS 32u
#endif

/**
 * @brief The shorter factor's limbs from which a product is taken by the Schonhage-Strassen
 *        transform.
 *
 * @note The transform works in the ring of integers modulo 2^n + 1, where a power of two is a root
 *       of unity and every twiddle is a shift, and weights by the square root of that root for a
 *       negacyclic product. Its depth is chosen by an integer cost model.
 * @note Measured on an RTX 3070 host (x86-64, MSVC -O2): Karatsuba and the transform meet near 8192
 *       limbs, and the transform is 1.44x ahead at 16384, 1.55x at 32768 and 1.85x at 65536.
 * @note Those ratios are one reading. Repeated readings of the same code on the same host differ by up
 *       to about 1.3x, and 16384 has read 1.02x and 1.32x. The crossover at 8192 held on every run.
 */
#ifndef ANCHOR_EXACT_TRANSFORM_LIMBS
#define ANCHOR_EXACT_TRANSFORM_LIMBS 8192u
#endif

/**
 * @brief The limbs the divisor and the quotient must both reach before a division is taken by
 *        Newton's reciprocal instead of long division.
 *
 * @note Newton's reciprocal is grown at half precision recursively, taken one Newton step, and
 *       corrected exactly. The quotient is then one product on the ladder.
 * @note Measured on the same host, a 2n-limb numerator by an n-limb divisor on the Karatsuba ladder
 *       alone: long division leads to 4096 limbs, and Newton is 1.21x ahead at 8192, 1.06x at 16384,
 *       1.81x at 32768 and 2.44x at 65536.
 * @note One reading as well. Another run read 1.09x at 8192 and 1.45x at 16384. Ratios within about
 *       1.3x are not settled by one reading, and the crossover at 8192 held on every run.
 */
#ifndef ANCHOR_EXACT_NEWTON_LIMBS
#define ANCHOR_EXACT_NEWTON_LIMBS 8192u
#endif

#if defined(__cplusplus)
    static_assert((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u, "Newton's division needs a divisor of at least one limb");
    static_assert((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u, "Karatsuba splits in halves of at least two limbs");
    static_assert((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS),
                  "the transform's rung sits at or above Karatsuba's");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u, "Newton's division needs a divisor of at least one limb");
_Static_assert((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u, "Karatsuba splits in halves of at least two limbs");
_Static_assert((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS),
               "the transform's rung sits at or above Karatsuba's");
#else
typedef char anchor_exact_newton_has_a_divisor[((ANCHOR_EXACT_NEWTON_LIMBS) >= 1u) ? 1 : -1];
typedef char anchor_exact_karatsuba_splits[((ANCHOR_EXACT_KARATSUBA_LIMBS) >= 4u) ? 1 : -1];
typedef char anchor_exact_rungs_in_order[((ANCHOR_EXACT_TRANSFORM_LIMBS) >= (ANCHOR_EXACT_KARATSUBA_LIMBS)) ? 1 : -1];
#endif

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
        uint32_t limb[ANCHOR_EXACT_LIMBS]; /**< Magnitude, least significant limb at index 0. */
        int32_t sign;                      /**< -1, 0 or 1. Zero is the only value carrying 0. */
    } AnchorExactInteger;

    /** @brief Every entry point returning a status returns one of these. */
    typedef enum
    {
        ANCHOR_EXACT_OK = 0,       /**< The operation completed and the result is exact. */
        ANCHOR_EXACT_WILL_NOT_FIT, /**< The value needs more limbs than the width holds, or a working
                                        copy past the stack could not be held. */
        ANCHOR_EXACT_NOT_DECIMAL,  /**< The text was not plain decimal, exponent notation included. */
        ANCHOR_EXACT_BY_ZERO,      /**< The divisor was zero. */
        ANCHOR_EXACT_NOT_EXACT     /**< An exact quotient was asked of a division leaving a remainder. */
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
     *       per point per lag. This is the call every vectorized arm exists to widen.
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
     * @note On a refusal `result` is left unchanged.
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
     * @note On a refusal `result` is left unchanged.
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
     * @note Taken on the ladder over the limbs each factor uses. The arithmetic grows with the used
     *       lengths and the width adds one pass writing the result, the cost of a product of a few
     *       limbs at a wide width: 8e-5 s at 131072 limbs. A rung whose workspace cannot be held
     *       steps down to the rung below it, and long multiplication needs none.
     * @note Factors whose used lengths sum past the width by more than one limb are refused before any
     *       arithmetic. Their product is at least 2^(32 * (sum - 2)), which already overruns.
     * @note On a refusal `result` is left unchanged.
     * @warning A product overruns the fixed width far sooner than a sum does. Ingesting a coordinate
     *          multiplies a fraction by a cell edge exactly once for that reason.
     */
    AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left,
                                            const AnchorExactInteger *right,
                                            AnchorExactInteger *result);

    /**
     * @brief Multiplies two integers by the Schonhage-Strassen transform at any size.
     *
     * @param[in]  left   First factor [BORROWS].
     * @param[in]  right  Second factor [BORROWS].
     * @param[out] result Product [BORROWS]. May alias either input.
     * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where the product needs more
     *                    limbs or the transform's workspace cannot be held.
     * @note The transform anchor_exact_multiply takes from ANCHOR_EXACT_TRANSFORM_LIMBS up, exposed so
     *       the rung can be graded and timed below its threshold.
     * @note On a refusal `result` is left unchanged.
     */
    AnchorExactStatus anchor_exact_multiply_transform(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                                      AnchorExactInteger *result);

    /**
     * @brief Divides one integer by another, into a quotient and a remainder.
     *
     * @param[in]  numerator Dividend [BORROWS].
     * @param[in]  divisor   Divisor [BORROWS].
     * @param[out] quotient  Quotient, rounded toward zero [BORROWS]. May alias either input.
     * @param[out] remainder Remainder, carrying the numerator's sign [BORROWS]. May alias either input,
     *                       and never `quotient`.
     * @return               ANCHOR_EXACT_OK, ANCHOR_EXACT_BY_ZERO for a zero divisor, or
     *                       ANCHOR_EXACT_WILL_NOT_FIT where a working copy past the stack cannot be
     *                       held.
     * @note numerator = quotient * divisor + remainder, with |remainder| below |divisor|. That is C's
     *       own division; a caller moving between the two meets no sign rule of a third kind.
     * @note Knuth's Algorithm D, and Newton's reciprocal once the divisor and the quotient both reach
     *       ANCHOR_EXACT_NEWTON_LIMBS.
     * @note On a refusal `quotient` and `remainder` are left unchanged.
     */
    AnchorExactStatus anchor_exact_divide(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                          AnchorExactInteger *quotient, AnchorExactInteger *remainder);

    /**
     * @brief The same division by Newton's reciprocal at any size.
     *
     * @param[in]  numerator Dividend [BORROWS].
     * @param[in]  divisor   Divisor [BORROWS].
     * @param[out] quotient  Quotient, rounded toward zero [BORROWS]. May alias either input.
     * @param[out] remainder Remainder, carrying the numerator's sign [BORROWS]. May alias either input,
     *                       and never `quotient`.
     * @return               As anchor_exact_divide.
     * @note The division anchor_exact_divide takes from ANCHOR_EXACT_NEWTON_LIMBS up, exposed so the
     *       rung can be graded and timed below its threshold.
     */
    AnchorExactStatus anchor_exact_divide_newton(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                                 AnchorExactInteger *quotient, AnchorExactInteger *remainder);

    /**
     * @brief The quotient of a division known to leave no remainder.
     *
     * @param[in]  numerator Dividend [BORROWS].
     * @param[in]  divisor   Divisor [BORROWS].
     * @param[out] quotient  Quotient [BORROWS]. May alias either input.
     * @return               ANCHOR_EXACT_OK, ANCHOR_EXACT_BY_ZERO for a zero divisor,
     *                       ANCHOR_EXACT_NOT_EXACT where the division leaves a remainder, or
     *                       ANCHOR_EXACT_WILL_NOT_FIT where a working copy past the stack cannot be
     *                       held.
     * @note A multiply and a mask, with no division in it: both are shifted past the divisor's low
     *       zero bits, the odd divisor's inverse modulo 2^(32 limbs) is grown by Newton's x(2 - dx) from
     *       d itself, which is its own inverse to 3 bits, and the quotient is the low limbs of the
     *       numerator times that inverse. Multiplying the quotient back proves it, and a remainder is
     *       found there and refused instead of returned as a wrong quotient.
     * @note On a refusal `quotient` is left unchanged.
     */
    AnchorExactStatus anchor_exact_divide_exact(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                                AnchorExactInteger *quotient);

    /**
     * @brief The greatest common divisor of two integers' magnitudes.
     *
     * @param[in]  left   First integer [BORROWS].
     * @param[in]  right  Second integer [BORROWS].
     * @param[out] result The gcd, never negative, and 0 only where both are 0 [BORROWS]. May alias
     *                    either input.
     * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where a working copy past the
     *                    stack cannot be held.
     * @note Lehmer's gcd, Knuth's Algorithm L: the leading 32 bits of the pair run Euclid's steps in
     *       words while each quotient is certain, and the steps' cofactors then advance the whole pair
     *       in one pass. It replaced a binary gcd, whose bit-at-a-time shifts cost the square of the
     *       bits and stalled the 4194304-bit test.
     * @note On a refusal `result` is left unchanged.
     */
    AnchorExactStatus anchor_exact_gcd(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                       AnchorExactInteger *result);

    /**
     * @brief Multiplies an integer by ten raised to a power, applying a scale.
     *
     * @param[in,out] value Integer to scale [BORROWS].
     * @param[in]     power How many powers of ten to apply.
     * @return              ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT.
     * @note On a refusal `value` is left unchanged. An earlier version wrote the low limbs of an
     *       overrun product into `value` before refusing, which left a wrapped magnitude behind.
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
     * @note The accepted text is, in order: any spaces, tabs, carriage returns or line feeds; an
     *       optional + or -; one or more ASCII digits with at most one decimal point among them, where
     *       either side of the point may be empty but not both; an optional uncertainty of one or more
     *       ASCII digits between ( and ); any spaces, tabs, carriage returns or line feeds; the end of
     *       the text. Anything else is ANCHOR_EXACT_NOT_DECIMAL, and that is decided before any
     *       ANCHOR_EXACT_WILL_NOT_FIT. representation.exact.units accepts exactly the same text.
     * @note Trailing zeros after the point are not counted as places. ".000" reads as zero and
     *       "1.2300" reads at two places.
     * @note The uncertainty is dropped and the call still returns ANCHOR_EXACT_OK. A reading of
     *       deposited coordinates wants only the value. anchor_exact_from_measured returns both.
     * @note The result equals the value of the text. Text carrying fewer places than `digits` is
     *       padded with zeros, which is exact for the text. Where the text is a truncated expansion of
     *       a longer number, such as a constant printed to 1000 places and read at 1024, the padded
     *       places are zeros and not the digits of that number. Supply text carrying at least `digits`
     *       places for such a number.
     * @note Refusing a value with too many places is the same refusal representation.exact makes, and
     *       for the same reason: a scale that rounds is a quantum this end imposed, and it has to be an
     *       error and never a quiet loss.
     * @note On a refusal `value` is left unchanged.
     */
    AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits,
                                                AnchorExactInteger *value);

    /**
     * @brief Reads decimal text into an exact value and an exact uncertainty, both at one scale.
     *
     * @param[in]  text        Decimal text in the grammar anchor_exact_from_decimal accepts [BORROWS].
     * @param[in]  length      How many bytes of text.
     * @param[in]  digits      Decimal places to carry both results at.
     * @param[out] value       Where the value is written [BORROWS].
     * @param[out] uncertainty Where the uncertainty is written, as a non-negative integer [BORROWS].
     * @param[out] carried     Set to 1 where the text carried a bracketed uncertainty and 0 where it
     *                         carried none [BORROWS].
     * @return                 ANCHOR_EXACT_OK, ANCHOR_EXACT_NOT_DECIMAL, or ANCHOR_EXACT_WILL_NOT_FIT
     *                         where the value or the uncertainty needs more places than `digits` or
     *                         more limbs than the width holds.
     * @note Exists for measured constants. The CODATA 2022 fine-structure constant is published as
     *       7.2973525643e-3 with a standard uncertainty of 0.0000000011e-3. Read at 1024 places without
     *       that uncertainty, the stored integer has 1024 places and no record that 11 are measured.
     * @note The bracketed digits count units of the last place PRINTED in the value, trailing zeros
     *       included. "1.2300(5)" is 1.23 with an uncertainty of 0.0005, and "137(2)" is 137 with an
     *       uncertainty of 2. That place count can exceed the value's own after its trailing zeros are
     *       dropped. The uncertainty can refuse at a scale the value fits.
     * @note A text with no bracket returns a zero uncertainty with `carried` at 0. A text of "(0)"
     *       returns a zero uncertainty with `carried` at 1, a value stated as exact by its source.
     * @note On a refusal `value`, `uncertainty` and `carried` are left unchanged.
     */
    AnchorExactStatus anchor_exact_from_measured(const char *text, size_t length, uint32_t digits,
                                                 AnchorExactInteger *value,
                                                 AnchorExactInteger *uncertainty, int *carried);

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
     * @brief Counts positions whose value equals the value one lag away.
     *
     * @param[in] positions Positions, in any order, each carrying an index into `values` [BORROWS].
     * @param[in] values    The value standing at each position [BORROWS].
     * @param[in] count     How many positions.
     * @param[in] lag       The offset to test, as an exact integer [BORROWS].
     * @return              How many distinct positions have a position exactly `lag` above them
     *                      carrying an equal value.
     * @note This is the measure itself, and the reason every arm below exists. The portable form keys
     *       a table on the hash. A vectorized form compares many limbs at once and a GPU form compares
     *       many positions at once, and all three return the same count or one of them has a defect.
     * @note A position listed more than once keeps the value of its last entry and is counted once.
     *       representation.exact.placed builds its lookup the same way, and the two arms return one
     *       count on the same list.
     */
    size_t anchor_exact_agreement(const AnchorExactInteger *positions, const uint64_t *values,
                                  size_t count, const AnchorExactInteger *lag);

    /**
     * @brief The same count, with the equality test supplied by the caller.
     *
     * @param[in] equal     Whether two integers hold the same value [BORROWS].
     * @param[in] positions Positions carrying values, in any order [BORROWS].
     * @param[in] values    The value standing at each position [BORROWS].
     * @param[in] count     How many positions.
     * @param[in] lag       The offset to test [BORROWS].
     * @return              How many distinct positions agree with the place one lag above them.
     * @note Every arm runs this one function and supplies only its own equality test. An arm that
     *       carried its own search would be a different algorithm, and timing it against the portable
     *       arm would measure the algorithm instead of the instruction set. The AVX2 arm did carry its
     *       own, and its advantage read 3.44x against an ordered search and 1.75x against this one.
     * @note A repeated position is handled as anchor_exact_agreement documents. Where the table cannot
     *       be allocated, a quadratic scan answers with the same count and needs no ordering.
     */
    size_t anchor_exact_agreement_using(int (*equal)(const AnchorExactInteger *left,
                                                     const AnchorExactInteger *right),
                                        const AnchorExactInteger *positions, const uint64_t *values,
                                        size_t count, const AnchorExactInteger *lag);

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_EXACT_LIMBS_H */
