/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_limbs.c
 * @brief The portable C11 reference for the limb transform, which every other arm is checked on.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Nothing here uses an intrinsic, a compiler extension or a 128 bit type. A target with a
 *       C11 compiler builds this and gets the right answer, and the vectorized arms exist only to
 *       get the same answer sooner.
 */

#include "exact_limbs.h"

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

AnchorExactStatus anchor_exact_scale_by_ten(AnchorExactInteger *value, uint32_t power)
{
    // Nine powers of ten at a time, the most that fits a limb without overflowing it.
    static const uint32_t TEN_TO[10] = {1u, 10u, 100u, 1000u, 10000u,
                                        100000u, 1000000u, 10000000u, 100000000u, 1000000000u};
    while (power > 0u)
    {
        const uint32_t step = (power > 9u) ? 9u : power;
        if (magnitude_multiply_small(value->limb, TEN_TO[step]) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        power -= step;
    }
    settle_sign(value, value->sign);
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits,
                                            AnchorExactInteger *value)
{
    size_t at = 0u;
    int32_t sign = 1;

    anchor_exact_zero(value);

    while ((at < length) && ((text[at] == ' ') || (text[at] == '\t')))
    {
        at++;
    }
    if ((at < length) && ((text[at] == '+') || (text[at] == '-')))
    {
        sign = (text[at] == '-') ? -1 : 1;
        at++;
    }

    // Where the number ends, found before anything is accumulated. Trailing zeros in the fraction
    // are dropped here instead of counted as places: 1.2300 and 1.23 are the same number and a
    // scale of two places holds both exactly, so counting the zeros made the first refuse at a
    // scale the second passed. That is a refusal to represent a value needing no rounding at all.
    // Trimming has to happen before accumulation because this representation cannot divide the
    // zeros back out afterward.
    size_t ends = at;
    size_t point_at = length;
    for (size_t scan = at; scan < length; scan++)
    {
        const char one = text[scan];
        if ((one == '(') || (one == ' ') || (one == '\t') || (one == '\n') || (one == '\r'))
        {
            break;
        }
        if (one == '.')
        {
            if (point_at != length)
            {
                return ANCHOR_EXACT_NOT_DECIMAL;
            }
            point_at = scan;
        }
        ends = scan + 1u;
    }
    if (point_at != length)
    {
        while ((ends > (point_at + 1u)) && (text[ends - 1u] == '0'))
        {
            ends--;
        }
        // Every fractional digit was a zero, so the point itself carries nothing either.
        if (ends == (point_at + 1u))
        {
            ends = point_at;
        }
    }

    uint32_t places = 0u;
    int seen_point = 0;
    int seen_digit = 0;
    for (; at < ends; at++)
    {
        const char one = text[at];
        if (one == '(')
        {
            // The bracketed uncertainty is not part of the number. Everything from here is dropped.
            break;
        }
        if (one == '.')
        {
            if (seen_point != 0)
            {
                return ANCHOR_EXACT_NOT_DECIMAL;
            }
            seen_point = 1;
            continue;
        }
        if ((one == ' ') || (one == '\t') || (one == '\n') || (one == '\r'))
        {
            break;
        }
        if ((one < '0') || (one > '9'))
        {
            // An exponent, a slash or anything else. Accepting one would put a rounding into the
            // path this whole representation exists to keep clear of it.
            return ANCHOR_EXACT_NOT_DECIMAL;
        }
        if (magnitude_multiply_small(value->limb, 10u) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        if (magnitude_add_small(value->limb, (uint32_t)(one - '0')) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        seen_digit = 1;
        if (seen_point != 0)
        {
            places++;
        }
    }

    if (seen_digit == 0)
    {
        return ANCHOR_EXACT_NOT_DECIMAL;
    }
    if (places > digits)
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }

    settle_sign(value, sign);
    return anchor_exact_scale_by_ten(value, digits - places);
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
 * @brief Finds a position in an ascending run.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] count     How many.
 * @param[in] wanted    The position to find [BORROWS].
 * @return              Its index, or count where it is absent.
 * @note Kept because it needs no allocation and answers where a caller holds only the run. The
 *       measure below does not use it: an ordering is not a property the set has, and asking for
 *       one costs a comparison per step of the search.
 */
static size_t find_position(const AnchorExactInteger *positions, size_t count,
                            const AnchorExactInteger *wanted)
{
    size_t low = 0u;
    size_t high = count;
    while (low < high)
    {
        const size_t middle = low + ((high - low) / 2u);
        const int order = anchor_exact_compare(&positions[middle], wanted);
        if (order == 0)
        {
            return middle;
        }
        if (order < 0)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }
    return count;
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
    // This is what the python side has always done. Its `placed` is a dict, and the two arms were
    // running different algorithms for one operation.
    if (count == 0u)
    {
        return 0u;
    }

    size_t slots = 1u;
    while (slots < (count * 2u))
    {
        slots <<= 1u;
    }

    size_t *table = (size_t *)malloc(slots * sizeof(size_t));
    if (table == NULL)
    {
        // No table, so the ordered search answers instead. Slower and correct beats absent.
        size_t agreed = 0u;
        for (size_t at = 0u; at < count; at++)
        {
            AnchorExactInteger moved;
            if (anchor_exact_add(&positions[at], lag, &moved) != ANCHOR_EXACT_OK)
            {
                continue;
            }
            const size_t found = find_position(positions, count, &moved);
            if ((found < count) && (values[found] == values[at]))
            {
                agreed++;
            }
        }
        return agreed;
    }

    for (size_t at = 0u; at < slots; at++)
    {
        table[at] = count;
    }

    const size_t mask = slots - 1u;
    for (size_t at = 0u; at < count; at++)
    {
        size_t slot = (size_t)(anchor_exact_hash(&positions[at]) & (uint64_t)mask);
        while (table[slot] != count)
        {
            // A position landing twice keeps the first, matching a dict built by insertion where
            // the reader never writes the same key twice.
            if (equal(&positions[table[slot]], &positions[at]) != 0)
            {
                break;
            }
            slot = (slot + 1u) & mask;
        }
        if (table[slot] == count)
        {
            table[slot] = at;
        }
    }

    size_t agreed = 0u;
    for (size_t at = 0u; at < count; at++)
    {
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
