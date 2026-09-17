/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_integer.c
 * @brief The portable C11 reference for the limb transform, which every other arm is checked on.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Nothing here uses an intrinsic, a compiler extension or a 128 bit type. A target with a
 *       C11 compiler builds this and gets the right answer, and the vectorized arms exist only to
 *       get the same answer sooner.
 */

#include "exact_integer.h"

#include <stdlib.h>
#include <string.h>

/** @brief Bits per limb. */
#define LIMB_BITS 32u

/** @brief The base a limb counts in, held as 64 bit, wide enough that two limbs multiply cleanly. */
#define LIMB_BASE ((uint64_t)1u << LIMB_BITS)

/** @brief Everything below the limb boundary, for taking the low half of a 64 bit accumulator. */
#define LIMB_MASK ((uint64_t)0xFFFFFFFFu)

void anchor_exact_zero(AnchorExactInteger *value)
{
    memset(value->limb, 0, sizeof(value->limb));
    value->sign = 0;
}

/**
 * @brief Orders two magnitudes, ignoring sign.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1, 0 or 1.
 * @note Walks from the top limb down, since the first limb that differs settles the order and the
 *       high limbs of a value narrower than the width are zero on both sides.
 */
static int magnitude_compare(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at > 0u)
    {
        at--;
        if (left[at] != right[at])
        {
            return (left[at] < right[at]) ? -1 : 1;
        }
    }
    return 0;
}

/**
 * @brief Whether a magnitude is entirely zero.
 *
 * @param[in] value Magnitude [BORROWS].
 * @return          1 where every limb is zero, 0 otherwise.
 */
static int magnitude_is_zero(const uint32_t *value)
{
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        if (value[at] != 0u)
        {
            return 0;
        }
    }
    return 1;
}

/**
 * @brief Adds two magnitudes.
 *
 * @param[in]  left   First magnitude [BORROWS].
 * @param[in]  right  Second magnitude [BORROWS].
 * @param[out] result Sum [BORROWS].
 * @return            1 where a carry ran off the top limb, 0 otherwise.
 */
static int magnitude_add(const uint32_t *left, const uint32_t *right, uint32_t *result)
{
    uint64_t carry = 0u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        const uint64_t total = (uint64_t)left[at] + (uint64_t)right[at] + carry;
        // Explicit narrowing to a limb. The high half is the carry and is kept, not discarded.
        result[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    return (carry != 0u) ? 1 : 0;
}

/**
 * @brief Subtracts the smaller magnitude from the larger, which the caller has already ordered.
 *
 * @param[in]  left   Magnitude to subtract from, no smaller than right [BORROWS].
 * @param[in]  right  Magnitude to subtract [BORROWS].
 * @param[out] result Difference [BORROWS].
 */
static void magnitude_subtract(const uint32_t *left, const uint32_t *right, uint32_t *result)
{
    uint64_t borrow = 0u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        // LIMB_BASE keeps the arithmetic non negative before the narrowing below, so no unsigned
        // wrap has to be reasoned about at the point the limb is stored.
        const uint64_t total = LIMB_BASE + (uint64_t)left[at] - (uint64_t)right[at] - borrow;
        result[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
}

int anchor_exact_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return (magnitude_compare(left->limb, right->limb) == 0) ? 1 : 0;
}

int anchor_exact_compare(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Writes a signed result from a magnitude and the sign it should carry.
 *
 * @param[in,out] result Integer whose limbs are already set [BORROWS].
 * @param[in]     sign   Sign to apply where the magnitude is not zero.
 * @note Zero always ends up carrying sign 0, which keeps a negative zero from ever existing and
 *       keeps two zeros comparing equal.
 */
static void settle_sign(AnchorExactInteger *result, int32_t sign)
{
    result->sign = magnitude_is_zero(result->limb) ? 0 : sign;
}

AnchorExactStatus anchor_exact_add(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                   AnchorExactInteger *result)
{
    if (left->sign == 0)
    {
        *result = *right;
        return ANCHOR_EXACT_OK;
    }
    if (right->sign == 0)
    {
        *result = *left;
        return ANCHOR_EXACT_OK;
    }

    if (left->sign == right->sign)
    {
        uint32_t sum[ANCHOR_EXACT_LIMBS];
        if (magnitude_add(left->limb, right->limb, sum) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        memcpy(result->limb, sum, sizeof(sum));
        settle_sign(result, left->sign);
        return ANCHOR_EXACT_OK;
    }

    const int order = magnitude_compare(left->limb, right->limb);
    if (order == 0)
    {
        anchor_exact_zero(result);
        return ANCHOR_EXACT_OK;
    }

    uint32_t difference[ANCHOR_EXACT_LIMBS];
    if (order > 0)
    {
        magnitude_subtract(left->limb, right->limb, difference);
        memcpy(result->limb, difference, sizeof(difference));
        settle_sign(result, left->sign);
    }
    else
    {
        magnitude_subtract(right->limb, left->limb, difference);
        memcpy(result->limb, difference, sizeof(difference));
        settle_sign(result, right->sign);
    }
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_subtract(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    AnchorExactInteger negated = *right;
    negated.sign = -negated.sign;
    return anchor_exact_add(left, &negated, result);
}

AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    if ((left->sign == 0) || (right->sign == 0))
    {
        anchor_exact_zero(result);
        return ANCHOR_EXACT_OK;
    }

    // Twice the width, so an overrun is detected in the top half instead of being wrapped away.
    uint32_t wide[2u * ANCHOR_EXACT_LIMBS];
    memset(wide, 0, sizeof(wide));

    for (size_t low = 0u; low < (size_t)ANCHOR_EXACT_LIMBS; low++)
    {
        if (left->limb[low] == 0u)
        {
            continue;
        }
        uint64_t carry = 0u;
        for (size_t high = 0u; high < (size_t)ANCHOR_EXACT_LIMBS; high++)
        {
            const uint64_t total = ((uint64_t)left->limb[low] * (uint64_t)right->limb[high])
                                   + (uint64_t)wide[low + high] + carry;
            wide[low + high] = (uint32_t)(total & LIMB_MASK);
            carry = total >> LIMB_BITS;
        }
        // The carry out of the inner loop lands above both factors and cannot itself carry further,
        // because the widest product of two n limb values occupies 2n limbs.
        size_t spill = low + (size_t)ANCHOR_EXACT_LIMBS;
        while ((carry != 0u) && (spill < (2u * (size_t)ANCHOR_EXACT_LIMBS)))
        {
            const uint64_t total = (uint64_t)wide[spill] + carry;
            wide[spill] = (uint32_t)(total & LIMB_MASK);
            carry = total >> LIMB_BITS;
            spill++;
        }
    }

    for (size_t at = (size_t)ANCHOR_EXACT_LIMBS; at < (2u * (size_t)ANCHOR_EXACT_LIMBS); at++)
    {
        if (wide[at] != 0u)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
    }

    memcpy(result->limb, wide, sizeof(result->limb));
    settle_sign(result, (left->sign == right->sign) ? 1 : -1);
    return ANCHOR_EXACT_OK;
}

/**
 * @brief Multiplies a magnitude by a single limb sized value in place.
 *
 * @param[in,out] value  Magnitude [BORROWS].
 * @param[in]     factor What to multiply by.
 * @return               1 where a carry ran off the top limb, 0 otherwise.
 * @warning On a carry out of the top limb `value` holds the low limbs of the product. Callers run
 *          this on a copy they discard on refusal.
 */
static int magnitude_multiply_small(uint32_t *value, uint32_t factor)
{
    uint64_t carry = 0u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        const uint64_t total = ((uint64_t)value[at] * (uint64_t)factor) + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    return (carry != 0u) ? 1 : 0;
}

/**
 * @brief Adds a single limb sized value to a magnitude in place.
 *
 * @param[in,out] value What to add to [BORROWS].
 * @param[in]     added What to add.
 * @return              1 where a carry ran off the top limb, 0 otherwise.
 * @warning On a carry out of the top limb `value` holds the wrapped sum. Callers run this on a copy
 *          they discard on refusal.
 */
static int magnitude_add_small(uint32_t *value, uint32_t added)
{
    uint64_t carry = (uint64_t)added;
    for (size_t at = 0u; (at < (size_t)ANCHOR_EXACT_LIMBS) && (carry != 0u); at++)
    {
        const uint64_t total = (uint64_t)value[at] + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    return (carry != 0u) ? 1 : 0;
}

/**
 * @brief Multiplies a magnitude by ten raised to a power, in place.
 *
 * @param[in,out] value Magnitude [BORROWS].
 * @param[in]     power How many powers of ten to apply.
 * @return              1 where the product ran off the top limb, 0 otherwise.
 * @warning On a return of 1 `value` holds a wrapped product. Callers run this on a copy they
 *          discard on refusal.
 */
static int magnitude_scale_by_ten(uint32_t *value, uint32_t power)
{
    // Nine powers of ten at a time, the most that fits a limb without overflowing it.
    static const uint32_t TEN_TO[10] = {1u, 10u, 100u, 1000u, 10000u,
                                        100000u, 1000000u, 10000000u, 100000000u, 1000000000u};
    while (power > 0u)
    {
        const uint32_t step = (power > 9u) ? 9u : power;
        if (magnitude_multiply_small(value, TEN_TO[step]) != 0)
        {
            return 1;
        }
        power -= step;
    }
    return 0;
}

AnchorExactStatus anchor_exact_scale_by_ten(AnchorExactInteger *value, uint32_t power)
{
    // Scaled on a copy. A refusal leaves the caller's value as it was.
    uint32_t scaled[ANCHOR_EXACT_LIMBS];
    memcpy(scaled, value->limb, sizeof(scaled));
    if (magnitude_scale_by_ten(scaled, power) != 0)
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    memcpy(value->limb, scaled, sizeof(scaled));
    settle_sign(value, value->sign);
    return ANCHOR_EXACT_OK;
}

/**
 * @brief Whether a byte is one of the four whitespace characters decimal text may be padded with.
 *
 * @param[in] one The byte.
 * @return        1 for a space, tab, carriage return or line feed, 0 otherwise.
 * @note ASCII only, matching representation.exact. A locale dependent isspace would let the two
 *       arms accept different text on different machines.
 */
static int decimal_is_space(char one)
{
    return ((one == ' ') || (one == '\t') || (one == '\r') || (one == '\n')) ? 1 : 0;
}

/**
 * @brief Whether a byte is an ASCII decimal digit.
 *
 * @param[in] one The byte.
 * @return        1 for '0' through '9', 0 otherwise.
 */
static int decimal_is_digit(char one)
{
    return ((one >= '0') && (one <= '9')) ? 1 : 0;
}

/**
 * @brief Where each part of a decimal text sits, found before any arithmetic is done.
 *
 * @note Every range is a pair of byte offsets into the text, the second one past the last byte. An
 *       empty range has both offsets equal.
 */
typedef struct
{
    int32_t sign;              /**< -1 where the text opened with '-', 1 otherwise. */
    size_t whole_from;         /**< First digit before the point. */
    size_t whole_to;           /**< One past the last digit before the point. */
    size_t fraction_from;      /**< First digit after the point. */
    size_t fraction_to;        /**< One past the last digit after the point. */
    size_t uncertainty_from;   /**< First digit inside the brackets. */
    size_t uncertainty_to;     /**< One past the last digit inside the brackets. */
    int carried;               /**< 1 where the text carried a bracketed uncertainty, else 0. */
} DecimalLayout;

/**
 * @brief Checks a text against the decimal grammar and records where its parts sit.
 *
 * @param[in]  text   Decimal text [BORROWS].
 * @param[in]  length How many bytes of text.
 * @param[out] layout Where the parts sit [BORROWS].
 * @return            ANCHOR_EXACT_OK, or ANCHOR_EXACT_NOT_DECIMAL where the text breaks the grammar
 *                    anchor_exact_from_decimal documents.
 * @note Runs to the end of the text before any digit is accumulated. A malformed text is therefore
 *       ANCHOR_EXACT_NOT_DECIMAL even where its digits would also overrun the width.
 */
static AnchorExactStatus decimal_layout(const char *text, size_t length, DecimalLayout *layout)
{
    size_t at = 0u;
    while ((at < length) && (decimal_is_space(text[at]) != 0))
    {
        at++;
    }

    layout->sign = 1;
    if ((at < length) && ((text[at] == '+') || (text[at] == '-')))
    {
        layout->sign = (text[at] == '-') ? -1 : 1;
        at++;
    }

    layout->whole_from = at;
    while ((at < length) && (decimal_is_digit(text[at]) != 0))
    {
        at++;
    }
    layout->whole_to = at;

    layout->fraction_from = at;
    layout->fraction_to = at;
    if ((at < length) && (text[at] == '.'))
    {
        at++;
        layout->fraction_from = at;
        while ((at < length) && (decimal_is_digit(text[at]) != 0))
        {
            at++;
        }
        layout->fraction_to = at;
    }

    if ((layout->whole_to == layout->whole_from) && (layout->fraction_to == layout->fraction_from))
    {
        return ANCHOR_EXACT_NOT_DECIMAL;
    }

    layout->uncertainty_from = at;
    layout->uncertainty_to = at;
    layout->carried = 0;
    if ((at < length) && (text[at] == '('))
    {
        at++;
        layout->uncertainty_from = at;
        while ((at < length) && (decimal_is_digit(text[at]) != 0))
        {
            at++;
        }
        layout->uncertainty_to = at;
        if ((layout->uncertainty_to == layout->uncertainty_from) || (at >= length)
            || (text[at] != ')'))
        {
            return ANCHOR_EXACT_NOT_DECIMAL;
        }
        at++;
        layout->carried = 1;
    }

    while ((at < length) && (decimal_is_space(text[at]) != 0))
    {
        at++;
    }
    return (at == length) ? ANCHOR_EXACT_OK : ANCHOR_EXACT_NOT_DECIMAL;
}

/**
 * @brief Accumulates a run of ASCII digits onto a magnitude, most significant first.
 *
 * @param[in,out] value Magnitude to accumulate onto [BORROWS].
 * @param[in]     text  Decimal text [BORROWS].
 * @param[in]     from  First digit.
 * @param[in]     to    One past the last digit.
 * @return              1 where the magnitude ran off the top limb, 0 otherwise.
 * @warning On a return of 1 `value` holds a wrapped magnitude. Callers run this on a copy they
 *          discard on refusal.
 */
static int magnitude_accumulate_digits(uint32_t *value, const char *text, size_t from, size_t to)
{
    for (size_t at = from; at < to; at++)
    {
        if (magnitude_multiply_small(value, 10u) != 0)
        {
            return 1;
        }
        // The byte is an ASCII digit, checked by decimal_layout, so the difference is 0 to 9.
        if (magnitude_add_small(value, (uint32_t)(text[at] - '0')) != 0)
        {
            return 1;
        }
    }
    return 0;
}

/**
 * @brief Reads decimal text into a value and an uncertainty at `digits` places, writing only on
 *        success.
 *
 * @param[in]  text        Decimal text [BORROWS].
 * @param[in]  length      How many bytes of text.
 * @param[in]  digits      Decimal places to carry both results at.
 * @param[out] value       Where the value is written [BORROWS].
 * @param[out] uncertainty Where the uncertainty is written [BORROWS].
 * @param[out] carried     Where 1 or 0 is written for a bracketed uncertainty [BORROWS].
 * @return                 ANCHOR_EXACT_OK, ANCHOR_EXACT_NOT_DECIMAL or ANCHOR_EXACT_WILL_NOT_FIT.
 * @note The shared body of anchor_exact_from_decimal and anchor_exact_from_measured. One reading of
 *       the grammar serves both, and the two entries cannot accept different text.
 */
static AnchorExactStatus decimal_read(const char *text, size_t length, uint32_t digits,
                                      AnchorExactInteger *value, AnchorExactInteger *uncertainty,
                                      int *carried)
{
    DecimalLayout layout;
    const AnchorExactStatus shape = decimal_layout(text, length, &layout);
    if (shape != ANCHOR_EXACT_OK)
    {
        return shape;
    }

    // Trailing zeros after the point are not places. 1.2300 and 1.23 are one number, and ".000" is
    // zero at no places. Counting the zeros refused 1.2300 at a scale that accepted 1.23, and
    // dropping every digit of ".000" with no digit left behind refused a zero outright.
    size_t trimmed_to = layout.fraction_to;
    while ((trimmed_to > layout.fraction_from) && (text[trimmed_to - 1u] == '0'))
    {
        trimmed_to--;
    }
    const size_t places = trimmed_to - layout.fraction_from;
    if (places > (size_t)digits)
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }

    uint32_t magnitude[ANCHOR_EXACT_LIMBS];
    memset(magnitude, 0, sizeof(magnitude));
    if ((magnitude_accumulate_digits(magnitude, text, layout.whole_from, layout.whole_to) != 0)
        || (magnitude_accumulate_digits(magnitude, text, layout.fraction_from, trimmed_to) != 0))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    // places is at most digits, checked above, so the difference fits the uint32_t it is passed as.
    if (magnitude_scale_by_ten(magnitude, digits - (uint32_t)places) != 0)
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }

    uint32_t spread[ANCHOR_EXACT_LIMBS];
    memset(spread, 0, sizeof(spread));
    if (layout.carried != 0)
    {
        // The bracketed digits count units of the last place printed, trailing zeros included.
        const size_t printed = layout.fraction_to - layout.fraction_from;
        if (printed > (size_t)digits)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        if (magnitude_accumulate_digits(spread, text, layout.uncertainty_from,
                                        layout.uncertainty_to) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        // printed is at most digits, checked above, so the difference fits the uint32_t.
        if (magnitude_scale_by_ten(spread, digits - (uint32_t)printed) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
    }

    memcpy(value->limb, magnitude, sizeof(magnitude));
    settle_sign(value, layout.sign);
    memcpy(uncertainty->limb, spread, sizeof(spread));
    settle_sign(uncertainty, 1);
    *carried = layout.carried;
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits,
                                            AnchorExactInteger *value)
{
    // Read into a local value. A refusal leaves the caller's value as it was. This entry reads the
    // uncertainty and drops it, as its declaration documents.
    AnchorExactInteger read;
    AnchorExactInteger spread;
    int carried = 0;
    const AnchorExactStatus status =
        decimal_read(text, length, digits, &read, &spread, &carried);
    if (status == ANCHOR_EXACT_OK)
    {
        *value = read;
    }
    return status;
}

AnchorExactStatus anchor_exact_from_measured(const char *text, size_t length, uint32_t digits,
                                             AnchorExactInteger *value,
                                             AnchorExactInteger *uncertainty, int *carried)
{
    AnchorExactInteger read;
    AnchorExactInteger spread;
    int bracket = 0;
    const AnchorExactStatus status = decimal_read(text, length, digits, &read, &spread, &bracket);
    if (status == ANCHOR_EXACT_OK)
    {
        *value = read;
        *uncertainty = spread;
        *carried = bracket;
    }
    return status;
}

uint64_t anchor_exact_hash(const AnchorExactInteger *value)
{
    // FNV-1a over the limbs, with the sign folded in last so two magnitudes that differ only in
    // sign do not land on one bucket.
    uint64_t held = 0xCBF29CE484222325u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        held ^= (uint64_t)value->limb[at];
        held *= 0x100000001B3u;
    }
    held ^= (uint64_t)(uint32_t)value->sign;
    held *= 0x100000001B3u;
    return held;
}

/**
 * @brief The agreement count without a table, for when the table cannot be allocated.
 *
 * @param[in] equal     Whether two integers hold the same value [BORROWS].
 * @param[in] positions Positions carrying values, in any order [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              The count anchor_exact_agreement_using returns with a table.
 * @note Quadratic in `count` and needs no memory. A position is counted at its last entry only, and
 *       a displaced position is matched to the last entry equal to it, which keeps the last value
 *       at a repeated position. An earlier version ran a binary search here, which needed the
 *       positions sorted when the table path did not.
 */
static size_t agreement_without_table(int (*equal)(const AnchorExactInteger *left,
                                                   const AnchorExactInteger *right),
                                      const AnchorExactInteger *positions, const uint64_t *values,
                                      size_t count, const AnchorExactInteger *lag)
{
    size_t agreed = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        int repeated_later = 0;
        for (size_t later = at + 1u; later < count; later++)
        {
            if (equal(&positions[later], &positions[at]) != 0)
            {
                repeated_later = 1;
                break;
            }
        }
        if (repeated_later != 0)
        {
            continue;
        }

        AnchorExactInteger moved;
        if (anchor_exact_add(&positions[at], lag, &moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t found = count;
        for (size_t other = 0u; other < count; other++)
        {
            if (equal(&positions[other], &moved) != 0)
            {
                found = other;
            }
        }
        if ((found < count) && (values[found] == values[at]))
        {
            agreed++;
        }
    }
    return agreed;
}

size_t anchor_exact_agreement(const AnchorExactInteger *positions, const uint64_t *values,
                              size_t count, const AnchorExactInteger *lag)
{
    return anchor_exact_agreement_using(anchor_exact_equal, positions, values, count, lag);
}

size_t anchor_exact_agreement_using(int (*equal)(const AnchorExactInteger *left,
                                                 const AnchorExactInteger *right),
                                    const AnchorExactInteger *positions, const uint64_t *values,
                                    size_t count, const AnchorExactInteger *lag)
{
    // What the measure asks of the set is membership: is there a point exactly one lag away, and
    // does it carry the same value. A set has no ordering, and a search that walks one imposes a
    // structure the domain never had and pays a full limb comparison at every step of it.
    //
    // An open addressed table keyed on the hash answers the same question in one probe on average.
    // The hash is not trusted on its own: a hit is confirmed with a full comparison, since two
    // distinct coordinates reading as equal is the error this whole path exists to prevent.
    //
    // This is what the python side has always done. Its `placed` is a dict built by overwriting,
    // which keeps the last value at a repeated position and holds each position once. The table
    // below keeps the last entry and the count walks the table, which gives the same count.
    if (count == 0u)
    {
        return 0u;
    }

    // The slot count is the power of two at or above twice `count`, which is below four times
    // `count`. Past this bound that product or its size in bytes wraps size_t, and the scan below
    // needs no allocation to answer.
    const size_t widest = SIZE_MAX / (4u * sizeof(size_t));
    if (count > widest)
    {
        return agreement_without_table(equal, positions, values, count, lag);
    }

    size_t slots = 1u;
    while (slots < (count * 2u))
    {
        slots <<= 1u;
    }

    size_t *table = (size_t *)malloc(slots * sizeof(size_t));
    if (table == NULL)
    {
        // No table, so the scan answers instead. Slower and correct beats absent.
        return agreement_without_table(equal, positions, values, count, lag);
    }

    for (size_t at = 0u; at < slots; at++)
    {
        table[at] = count;
    }

    const size_t mask = slots - 1u;
    for (size_t at = 0u; at < count; at++)
    {
        size_t slot = (size_t)(anchor_exact_hash(&positions[at]) & (uint64_t)mask);
        while ((table[slot] != count) && (equal(&positions[table[slot]], &positions[at]) == 0))
        {
            slot = (slot + 1u) & mask;
        }
        // An empty slot takes the entry. A slot already holding this position takes it too, so the
        // table ends up holding the last entry for every position.
        table[slot] = at;
    }

    size_t agreed = 0u;
    for (size_t held = 0u; held < slots; held++)
    {
        const size_t at = table[held];
        if (at == count)
        {
            continue;
        }
        AnchorExactInteger moved;
        if (anchor_exact_add(&positions[at], lag, &moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t slot = (size_t)(anchor_exact_hash(&moved) & (uint64_t)mask);
        while (table[slot] != count)
        {
            if (equal(&positions[table[slot]], &moved) != 0)
            {
                if (values[table[slot]] == values[at])
                {
                    agreed++;
                }
                break;
            }
            slot = (slot + 1u) & mask;
        }
    }

    free(table);
    return agreed;
}
