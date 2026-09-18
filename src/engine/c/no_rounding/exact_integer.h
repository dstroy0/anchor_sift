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
 *       SIMD widths this tree builds for and onto a CUDA lane, so one representation serves every
 *       arm.
 * @note The reference implementation is portable C11. Every vectorized arm is checked against it
 *       and is wrong where it disagrees, whatever it measures.
 * @note There is no division. A product of two values at a scale of 10^d sits at 10^2d and needs a
 *       division to return to 10^d, and its intermediate needs twice the width. A constant derived
 *       by division, such as h over 2 pi, is computed in arbitrary precision outside this type and
 *       read in as finished decimal text. The multiply refuses a product that overruns the width.
 * @note No call holds more than two width-sized integers on the stack, which is 256 KiB at 32768
 *       limbs. A caller holding many integers at a wide width keeps them in static or allocated
 *       storage. A main thread stack defaults to 1 MiB under the MSVC linker and 8 MiB under a
 *       stock Linux, and eight integers at 32768 limbs fill the first.
 */
#ifndef ANCHOR_EXACT_LIMBS_H
#define ANCHOR_EXACT_LIMBS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
/* The GPU arm is compiled as C++ by nvcc and calls straight into these, which are compiled as C.
 * Without this the C++ side would look for mangled names that no C translation unit ever emits. */
extern "C" {
#endif

/**
 * @brief Limbs per exact integer, at 32 bits each, a power of two for a power-of-two width.
 *
 * @note 128 limbs is 4096 bits, which holds 1024 decimal digits with room over. That is the scale
 *       representation/exact.py ingests at, and the two forms have to agree on the same values or
 *       a cross check between them means nothing.
 * @note The value a limb array carries is the expansion sum(limb[i] * (2^32)^i), whose top
 *       coefficient is the width 2^ANCHOR_EXACT_BITS. A power of two limb count makes that width a
 *       power of two. The top magnitude bit then lands at a fixed position, and the width scales by
 *       doubling, 4096 to 8192 to 16384 bits, with the position fixed at each. The guard below
 *       refuses a width that is not a power of two.
 * @note A build selects any power of two from 1 limb to 32768, which is 32 bits to 1048576 bits,
 *       and the guard below refuses anything outside that range. Every arm is graded at every one
 *       of those widths by maint/engine/check_exact_widths.sh.
 * @note A width below 4096 bits cannot hold the 1024 digit floor. A build selecting one declares
 *       its own ANCHOR_EXACT_DIGITS, and the floor assert below refuses it by name where it does not.
 * @note Defined on both arms so #if always has a value and an unset build is never a silent false.
 */
#ifndef ANCHOR_EXACT_LIMBS
#define ANCHOR_EXACT_LIMBS 128u
#endif

/**
 * @brief Decimal digits the fixed width is guaranteed to hold, matching representation.exact.
 *
 * @note A declared floor and never the capacity. 128 limbs is 4096 bits, which actually holds 1232
 *       decimal digits, so 208 of them are headroom this constant does not promise.
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

/**
 * @brief Bits the fixed width actually carries. Every size is taken from this or from the limbs.
 */
#define ANCHOR_EXACT_BITS (ANCHOR_EXACT_LIMBS * 32u)

/* The declared floor has to fit the width, and the build can decide that. A decimal digit needs
 * log2(10) bits, which is 3.3219, carried here as 3322 parts in a thousand and rounded up so the
 * test is never optimistic. A floor raised past the width fails compilation with this line. */
/* Spelled per language and both arms defined, because nvcc compiles a .cu as C++ where
 * _Static_assert does not exist. Unguarded, this header failed to compile under nvcc, the GPU arm
 * was never built, and a stale bench binary carrying no CUDA symbols went on reporting a "cuda" arm
 * that agreed with the portable one. It agreed because it WAS the portable one. */
/* Three arms and every one defined, keyed on what the LANGUAGE offers rather than on which
 * compiler is driving. C++ spells it static_assert, C11 spells it _Static_assert, and a C compiler
 * older than C11 has neither, where a negative array width fails at compile time on any of them.
 * Naming a vendor here would only move the hole to the next toolchain that is not that vendor. */
#if defined(__cplusplus)
static_assert((((ANCHOR_EXACT_DIGITS * 3322u) / 1000u) + 1u) <= ANCHOR_EXACT_BITS,
              "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert((((ANCHOR_EXACT_DIGITS * 3322u) / 1000u) + 1u) <= ANCHOR_EXACT_BITS,
               "ANCHOR_EXACT_DIGITS declares more decimal digits than ANCHOR_EXACT_LIMBS holds");
#else
typedef char anchor_exact_digits_fit_the_width[
    ((((ANCHOR_EXACT_DIGITS * 3322u) / 1000u) + 1u) <= ANCHOR_EXACT_BITS) ? 1 : -1];
#endif

/* The width is a power of two. The expansion's top coefficient 2^ANCHOR_EXACT_BITS is then a power
 * of two and the top magnitude bit sits at a fixed position at every size the build selects. Scaling is
 * by doubling the limb count, 128 to 256 to 512, holding 4096, 8192, 16384 bits. A width that is not
 * a power of two, an override such as the earlier 108 limbs, fails compilation here. Both arms
 * defined, for the same reason as the floor above: nvcc compiles a .cu as C++, where _Static_assert
 * does not exist. */
#if defined(__cplusplus)
static_assert((ANCHOR_EXACT_BITS & (ANCHOR_EXACT_BITS - 1u)) == 0u,
              "ANCHOR_EXACT_BITS must be a power of two so the expansion width scales by doubling");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert((ANCHOR_EXACT_BITS & (ANCHOR_EXACT_BITS - 1u)) == 0u,
               "ANCHOR_EXACT_BITS must be a power of two so the expansion width scales by doubling");
#else
typedef char anchor_exact_bits_are_a_power_of_two[
    ((ANCHOR_EXACT_BITS & (ANCHOR_EXACT_BITS - 1u)) == 0u) ? 1 : -1];
#endif

/**
 * @brief The widest width a build may select, 32768 limbs.
 *
 * @note The ceiling is the widest width check_exact_widths.sh grades. No arm has run a width past
 *       it. The assert below refuses one at compile time.
 */
#define ANCHOR_EXACT_WIDEST_BITS 1048576u

/* One limb at the bottom and ANCHOR_EXACT_WIDEST_BITS at the top. The power of two test above passes
 * a width of zero, because 0 & (0 - 1) is 0. The bottom of the range is its own test here. */
#if defined(__cplusplus)
static_assert((ANCHOR_EXACT_LIMBS >= 1u) && (ANCHOR_EXACT_BITS <= ANCHOR_EXACT_WIDEST_BITS),
              "ANCHOR_EXACT_LIMBS must be from 1 to 32768, 32 bits to 1048576 bits");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert((ANCHOR_EXACT_LIMBS >= 1u) && (ANCHOR_EXACT_BITS <= ANCHOR_EXACT_WIDEST_BITS),
               "ANCHOR_EXACT_LIMBS must be from 1 to 32768, 32 bits to 1048576 bits");
#else
typedef char anchor_exact_limbs_are_in_range[
    ((ANCHOR_EXACT_LIMBS >= 1u) && (ANCHOR_EXACT_BITS <= ANCHOR_EXACT_WIDEST_BITS)) ? 1 : -1];
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
 * @note Schoolbook over the limbs each factor uses. Its cost grows with the two used lengths
 *       multiplied together, and the width sets only the ceiling. A value of a few limbs multiplies
 *       in the same time at 32768 limbs as at 128.
 * @note Factors whose used lengths sum past the width by more than one limb are refused before any
 *       arithmetic. Their product is at least 2^(32 * (sum - 2)), which already overruns.
 * @note Holds one accumulator of ANCHOR_EXACT_LIMBS + 1 limbs on the stack, 128 KiB at 32768 limbs.
 * @note On a refusal `result` is left unchanged.
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
 *       dropped, so the uncertainty can refuse at a scale the value fits.
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
