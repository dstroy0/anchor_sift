
// exact_integer_decimal.c: small scaling and decimal reading
#include "exact_integer_internal.h"

/** @brief Ten raised to each power a single limb multiply can apply, 10^0 to 10^9. */
static const uint32_t TEN_TO[LIMB_DECIMAL_DIGITS + 1u] = {
    1u, 10u, 100u, 1000u, 10000u, 100000u, 1000000u, 10000000u, 100000000u, 1000000000u,
};

/**
 * @brief Multiplies a magnitude by a single limb sized value in place, over the limbs it uses.
 *
 * @param[in,out] value  Magnitude [BORROWS].
 * @param[in,out] used   A count of limbs at or above which every limb of `value` is zero, raised
 *                       where the product reaches further [BORROWS].
 * @param[in]     factor What to multiply by.
 * @return               1 where the product needs a limb past the width, 0 otherwise.
 * @note Walks `used` limbs and never the width. An earlier form walked the whole width once per
 *       decimal digit read, which made reading 315000 digits at 32768 limbs cost ten billion limb
 *       steps.
 * @warning On a return of 1 `value` holds the low limbs of the product. Callers run this on a copy
 *          they discard on error.
 */
static int magnitude_multiply_small(uint32_t *value, size_t *used, uint32_t factor)
{
    uint64_t carry = 0u;
    for (size_t at = 0u; at < *used; at++)
    {
        const uint64_t total = ((uint64_t)value[at] * (uint64_t)factor) + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    if (carry == 0u)
    {
        return 0;
    }
    if (*used == (size_t)ANCHOR_EXACT_LIMBS)
    {
        return 1;
    }
    // The carry is the high half of a 64 bit total and fits one limb.
    value[*used] = (uint32_t)carry;
    *used += 1u;
    return 0;
}

/**
 * @brief Adds a single limb sized value to a magnitude in place.
 *
 * @param[in,out] value What to add to [BORROWS].
 * @param[in,out] used  A count of limbs at or above which every limb of `value` is zero, raised
 *                      where the sum reaches further [BORROWS].
 * @param[in]     added What to add.
 * @return              1 where a carry ran off the top limb, 0 otherwise.
 * @warning On a carry out of the top limb `value` holds the wrapped sum. Callers run this on a copy
 *          they discard on error.
 */
static int magnitude_add_small(uint32_t *value, size_t *used, uint32_t added)
{
    uint64_t carry = (uint64_t)added;
    size_t at = 0u;
    while ((at < (size_t)ANCHOR_EXACT_LIMBS) && (carry != 0u))
    {
        const uint64_t total = (uint64_t)value[at] + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
        at++;
    }
    if (carry != 0u)
    {
        return 1;
    }
    if (at > *used)
    {
        *used = at;
    }
    return 0;
}

/**
 * @brief Multiplies a magnitude by ten raised to a power, in place.
 *
 * @param[in,out] value Magnitude [BORROWS].
 * @param[in,out] used  A count of limbs at or above which every limb of `value` is zero [BORROWS].
 * @param[in]     power How many powers of ten to apply.
 * @return              1 where the product ran off the top limb, 0 otherwise.
 * @warning On a return of 1 `value` holds a wrapped product. Callers run this on a copy they
 *          discard on error.
 */
static int magnitude_scale_by_ten(uint32_t *value, size_t *used, uint32_t power)
{
    // Nine powers of ten at a time, the most that fits a limb without overflowing it.
    while (power > 0u)
    {
        const uint32_t step = (power > LIMB_DECIMAL_DIGITS) ? LIMB_DECIMAL_DIGITS : power;
        if (magnitude_multiply_small(value, used, TEN_TO[step]) != 0)
        {
            return 1;
        }
        power -= step;
    }
    return 0;
}

AnchorExactStatus anchor_exact_scale_by_ten(AnchorExactInteger *value, uint32_t power)
{
    // Scaled on a copy. An error leaves the caller's value as it was.
    EXACT_SCRATCH(scaled, EXACT_LIMBS);
    if (!EXACT_SCRATCH_VALID(scaled))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    memcpy(scaled, value->limb, EXACT_LIMBS * sizeof(uint32_t));
    size_t used = magnitude_used(scaled);
    AnchorExactStatus status = ANCHOR_EXACT_WILL_NOT_FIT;
    if (magnitude_scale_by_ten(scaled, &used, power) == 0)
    {
        memcpy(value->limb, scaled, EXACT_LIMBS * sizeof(uint32_t));
        settle_sign(value, value->sign);
        status = ANCHOR_EXACT_OK;
    }
    EXACT_SCRATCH_RELEASE(scaled);
    return status;
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

    layout->integer_from = at;
    while ((at < length) && (decimal_is_digit(text[at]) != 0))
    {
        at++;
    }
    layout->integer_to = at;

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

    if ((layout->integer_to == layout->integer_from) && (layout->fraction_to == layout->fraction_from))
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
        if ((layout->uncertainty_to == layout->uncertainty_from) || (at >= length) || (text[at] != ')'))
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
 * @param[in,out] used  A count of limbs at or above which every limb of `value` is zero [BORROWS].
 * @param[in]     text  Decimal text [BORROWS].
 * @param[in]     from  First digit.
 * @param[in]     to    One past the last digit.
 * @return              1 where the magnitude ran off the top limb, 0 otherwise.
 * @note Takes nine digits a step. The magnitude is multiplied by 10^9 and the nine digits are added
 *       as one limb. A text overruns the width in nine digit steps exactly where it overruns one
 *       digit at a time, because every partial value is at most the finished one.
 * @warning On a return of 1 `value` holds a wrapped magnitude. Callers run this on a copy they
 *          discard on error.
 */
static int magnitude_accumulate_digits(uint32_t *value, size_t *used, const char *text, size_t from, size_t to)
{
    size_t at = from;
    while (at < to)
    {
        const size_t remaining = to - at;
        const size_t step = (remaining > (size_t)LIMB_DECIMAL_DIGITS) ? (size_t)LIMB_DECIMAL_DIGITS : remaining;
        uint32_t digits = 0u;
        for (size_t within = 0u; within < step; within++)
        {
            // decimal_layout checked that the byte is an ASCII digit, and the difference is 0 to 9.
            // Nine of them fold to at most 999999999, below 2^32.
            digits = (digits * 10u) + (uint32_t)(text[at + within] - '0');
        }
        if (magnitude_multiply_small(value, used, TEN_TO[step]) != 0)
        {
            return 1;
        }
        if (magnitude_add_small(value, used, digits) != 0)
        {
            return 1;
        }
        at += step;
    }
    return 0;
}

/**
 * @brief Reads decimal text into a value and an uncertainty at `digits` places, in staging integers
 *        the caller discards on an error.
 *
 * @param[in]  text        Decimal text [BORROWS].
 * @param[in]  length      How many bytes of text.
 * @param[in]  digits      Decimal places to carry both results at.
 * @param[out] value       Staging integer the value is read into [BORROWS].
 * @param[out] uncertainty Staging integer the uncertainty is read into [BORROWS].
 * @param[out] carried     Where 1 or 0 is written for a bracketed uncertainty [BORROWS].
 * @return                 ANCHOR_EXACT_OK, ANCHOR_EXACT_NOT_DECIMAL or ANCHOR_EXACT_WILL_NOT_FIT.
 * @note The shared body of anchor_exact_from_decimal and anchor_exact_from_measured. One reading of
 *       the grammar serves both, and the two entries cannot accept different text.
 * @warning On an error `value` and `uncertainty` hold partial limbs. Both entries pass integers of
 *          their own and copy out only on ANCHOR_EXACT_OK. An error leaves a caller's untouched.
 *          An earlier form read into two limb arrays of its own and then copied, which put a third
 *          and fourth width-sized array on the stack beside the entry's two.
 */
static AnchorExactStatus decimal_read(const char *text, size_t length, uint32_t digits, AnchorExactInteger *value,
                                      AnchorExactInteger *uncertainty, int *carried)
{
    DecimalLayout layout;
    const AnchorExactStatus layout_status = decimal_layout(text, length, &layout);
    if (layout_status != ANCHOR_EXACT_OK)
    {
        return layout_status;
    }

    // Trailing zeros after the point are not places. 1.2300 and 1.23 are one number, and ".000" is
    // zero at no places. Counting the zeros errored 1.2300 at a scale that accepted 1.23, and
    // dropping every digit of ".000" with no digit left behind errored on a zero outright.
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

    anchor_exact_zero(value);
    size_t value_used = 0u;
    if ((magnitude_accumulate_digits(value->limb, &value_used, text, layout.integer_from, layout.integer_to) != 0) ||
        (magnitude_accumulate_digits(value->limb, &value_used, text, layout.fraction_from, trimmed_to) != 0))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    // places is at most digits, checked above. The difference fits the uint32_t it is passed as.
    if (magnitude_scale_by_ten(value->limb, &value_used, digits - (uint32_t)places) != 0)
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }

    anchor_exact_zero(uncertainty);
    if (layout.carried != 0)
    {
        // The bracketed digits count units of the last place printed, trailing zeros included.
        const size_t printed = layout.fraction_to - layout.fraction_from;
        if (printed > (size_t)digits)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        size_t spread_used = 0u;
        if (magnitude_accumulate_digits(uncertainty->limb, &spread_used, text, layout.uncertainty_from,
                                        layout.uncertainty_to) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        // printed is at most digits, checked above. The difference fits the uint32_t.
        if (magnitude_scale_by_ten(uncertainty->limb, &spread_used, digits - (uint32_t)printed) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
    }

    settle_sign(value, layout.sign);
    settle_sign(uncertainty, 1);
    *carried = layout.carried;
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits, AnchorExactInteger *value)
{
    // Read into a local value. An error leaves the caller's value as it was. This entry reads the
    // uncertainty and drops it, as its declaration documents.
    EXACT_VALUE(read);
    EXACT_VALUE(spread);
    AnchorExactStatus status = ANCHOR_EXACT_WILL_NOT_FIT;
    if (EXACT_SCRATCH_VALID(read) && EXACT_SCRATCH_VALID(spread))
    {
        int carried = 0;
        status = decimal_read(text, length, digits, read, spread, &carried);
        if (status == ANCHOR_EXACT_OK)
        {
            *value = *read;
        }
    }
    EXACT_VALUE_RELEASE(read);
    EXACT_VALUE_RELEASE(spread);
    return status;
}

AnchorExactStatus anchor_exact_from_measured(const char *text, size_t length, uint32_t digits,
                                             AnchorExactInteger *value, AnchorExactInteger *uncertainty, int *carried)
{
    EXACT_VALUE(read);
    EXACT_VALUE(spread);
    AnchorExactStatus status = ANCHOR_EXACT_WILL_NOT_FIT;
    if (EXACT_SCRATCH_VALID(read) && EXACT_SCRATCH_VALID(spread))
    {
        int bracket = 0;
        status = decimal_read(text, length, digits, read, spread, &bracket);
        if (status == ANCHOR_EXACT_OK)
        {
            *value = *read;
            *uncertainty = *spread;
            *carried = bracket;
        }
    }
    EXACT_VALUE_RELEASE(read);
    EXACT_VALUE_RELEASE(spread);
    return status;
}
