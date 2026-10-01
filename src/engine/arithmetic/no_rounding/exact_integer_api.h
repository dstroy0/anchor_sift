
// exact_integer_api.h: the exact integer and its operations (exact_integer.h includes the parts in order)
#ifndef EXACT_INTEGER_API_H
#define EXACT_INTEGER_API_H

#include "exact_integer_widths.h"

#ifdef __cplusplus
/* The GPU arm is compiled as C++ by nvcc and calls straight into these, which are compiled as C.
 * Without this the C++ side would look for mangled names that no C translation unit ever emits. */
extern "C"
{
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
     * @note On an error `result` is left unchanged.
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
     * @note On an error `result` is left unchanged.
     */
    AnchorExactStatus anchor_exact_subtract(const AnchorExactInteger *left, const AnchorExactInteger *right,
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
     *       lengths and the width adds one pass writing the result. That pass is the cost of a product of
     *       a few limbs at a wide width: 8e-5 s at 131072 limbs. A rung whose workspace cannot be held
     *       steps down to the rung below it, and long multiplication needs none.
     * @note Factors whose used lengths sum past the width by more than one limb error before any
     *       arithmetic. Their product is at least 2^(32 * (sum - 2)), which already overruns.
     * @note On an error `result` is left unchanged.
     * @warning A product overruns the fixed width far sooner than a sum does. Ingesting a coordinate
     *          multiplies a fraction by a cell edge exactly once for that reason.
     */
    AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left, const AnchorExactInteger *right,
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
     * @note On an error `result` is left unchanged.
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
     *       own division. A caller moving between the two meets no sign rule of a third kind.
     * @note Knuth's Algorithm D, and Newton's reciprocal once the divisor and the quotient both reach
     *       ANCHOR_EXACT_NEWTON_LIMBS.
     * @note On an error `quotient` and `remainder` are left unchanged.
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
     *       found there and errored instead of returned as a wrong quotient.
     * @note On an error `quotient` is left unchanged.
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
     * @note On an error `result` is left unchanged.
     */
    AnchorExactStatus anchor_exact_gcd(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                       AnchorExactInteger *result);

    /**
     * @brief Multiplies an integer by ten raised to a power, applying a scale.
     *
     * @param[in,out] value Integer to scale [BORROWS].
     * @param[in]     power How many powers of ten to apply.
     * @return              ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT.
     * @note On an error `value` is left unchanged.
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
     *                    or ANCHOR_EXACT_WILL_NOT_FIT where the value, or its uncertainty, carries more
     *                    decimal places than `digits` holds, or the value needs more limbs than the width
     *                    holds.
     * @note The accepted text is, in order: any spaces, tabs, carriage returns or line feeds; an
     *       optional + or -; one or more ASCII digits with at most one decimal point among them, where
     *       either side of the point may be empty but not both; an optional uncertainty of one or more
     *       ASCII digits between ( and ); any spaces, tabs, carriage returns or line feeds; the end of
     *       the text. Anything else is ANCHOR_EXACT_NOT_DECIMAL, and that is decided before any
     *       ANCHOR_EXACT_WILL_NOT_FIT. representation.exact.units accepts exactly the same text.
     * @note Trailing zeros after the point are not counted as places. ".000" reads as zero and
     *       "1.2300" reads at two places.
     * @note The uncertainty is dropped from the result, and it is still sized as
     *       anchor_exact_from_measured sizes it: an uncertainty printed past `digits` places is
     *       ANCHOR_EXACT_WILL_NOT_FIT, "1.00000000000000000000000000(1)" at 24 among them. A reading of
     *       deposited coordinates wants only the value. anchor_exact_from_measured returns both.
     * @note The result equals the value of the text. Text carrying fewer places than `digits` is
     *       padded with zeros, which is exact for the text. Where the text is a truncated expansion of
     *       a longer number, such as a constant printed to 1000 places and read at 1024, the padded
     *       places are zeros and not the digits of that number. Supply text carrying at least `digits`
     *       places for such a number.
     * @note Erroring on a value with too many places is the same error representation.exact makes, and
     *       for the same reason: a scale that rounds is a quantum this end imposed, and it has to be an
     *       error and never a quiet loss.
     * @note On an error `value` is left unchanged.
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
     *       dropped. The uncertainty can error at a scale the value fits.
     * @note A text with no bracket returns a zero uncertainty with `carried` at 0. A text of "(0)"
     *       returns a zero uncertainty with `carried` at 1, a value stated as exact by its source.
     * @note On an error `value`, `uncertainty` and `carried` are left unchanged.
     */
    AnchorExactStatus anchor_exact_from_measured(const char *text, size_t length, uint32_t digits,
                                                 AnchorExactInteger *value, AnchorExactInteger *uncertainty,
                                                 int *carried);

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
    size_t anchor_exact_agreement(const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                                  const AnchorExactInteger *lag);

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
    size_t anchor_exact_agreement_using(int (*equal)(const AnchorExactInteger *left, const AnchorExactInteger *right),
                                        const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                                        const AnchorExactInteger *lag);

#ifdef __cplusplus
}
#endif

#endif
