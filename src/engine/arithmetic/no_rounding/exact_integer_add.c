
// exact_integer_add.c: magnitudes, comparison, addition and subtraction
#include "exact_integer_internal.h"

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
int magnitude_compare(const uint32_t *left, const uint32_t *right)
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
int magnitude_is_zero(const uint32_t *value)
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
 * @brief How many limbs a magnitude uses.
 *
 * @param[in] value Magnitude [BORROWS].
 * @return          One past the index of the highest nonzero limb, and 0 for zero.
 */
size_t magnitude_used(const uint32_t *value)
{
    size_t used = (size_t)ANCHOR_EXACT_LIMBS;
    while ((used > 0u) && (value[used - 1u] == 0u))
    {
        used--;
    }
    return used;
}

/**
 * @brief Whether the sum of two magnitudes carries off the top limb, found before any limb is
 *        written.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where the sum needs more limbs than the width holds, 0 otherwise.
 * @note left + right reaches 2^ANCHOR_EXACT_BITS exactly where left exceeds 2^ANCHOR_EXACT_BITS - 1
 *       - right, and that bound is ~right limb by limb. The test is then a comparison from the top
 *       limb down, which settles at the first limb that differs. For two values well inside the
 *       width that is the top limb.
 */
static int magnitude_add_overflows(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at > 0u)
    {
        at--;
        const uint32_t headroom = ~right[at];
        if (left[at] != headroom)
        {
            return (left[at] > headroom) ? 1 : 0;
        }
    }
    return 0;
}

/**
 * @brief Adds two magnitudes whose sum the caller has already found fits the width.
 *
 * @param[in]  left   First magnitude [BORROWS].
 * @param[in]  right  Second magnitude [BORROWS].
 * @param[out] result Sum [BORROWS]. May alias either input, since each limb is read before the
 *                    limb at the same index is written.
 */
static void magnitude_add(const uint32_t *left, const uint32_t *right, uint32_t *result)
{
    uint64_t carry = 0u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        const uint64_t total = (uint64_t)left[at] + (uint64_t)right[at] + carry;
        // Explicit narrowing to a limb. The high half is the carry and is kept, not discarded.
        result[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
}

/**
 * @brief Subtracts the smaller magnitude from the larger, which the caller has already ordered.
 *
 * @param[in]  left   Magnitude to subtract from, no smaller than right [BORROWS].
 * @param[in]  right  Magnitude to subtract [BORROWS].
 * @param[out] result Difference [BORROWS]. May alias either input, since each limb is read before
 *                    the limb at the same index is written.
 */
static void magnitude_subtract(const uint32_t *left, const uint32_t *right, uint32_t *result)
{
    uint64_t borrow = 0u;
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        // LIMB_BASE keeps the arithmetic non negative before the narrowing below. No unsigned
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
        // Both negative. The larger magnitude is the smaller value.
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
void settle_sign(AnchorExactInteger *result, int32_t sign)
{
    result->sign = magnitude_is_zero(result->limb) ? 0 : sign;
}

/**
 * @brief Adds two integers, with the sign of the second supplied apart from it.
 *
 * @param[in]  left       First addend [BORROWS].
 * @param[in]  right      Second addend, whose magnitude is read and whose sign is not [BORROWS].
 * @param[in]  right_sign Sign the second addend is taken to carry.
 * @param[out] result     Sum [BORROWS]. May alias either input.
 * @return                ANCHOR_EXACT_OK, or ANCHOR_EXACT_WILL_NOT_FIT where the sum needs more
 *                        limbs.
 * @note The two signs are the flag for which operation is legal on this pair. Equal signs add the
 *       magnitudes, which alone can overrun and is tested before a limb is written. Opposite signs
 *       subtract the smaller magnitude from the larger and take the larger one's sign. Equal
 *       magnitudes of opposite sign are zero.
 * @note Subtraction is this call with the sign turned over. An earlier form copied the whole
 *       integer to negate it, which at 32768 limbs put 128 KiB on the stack to change four bytes.
 */
static AnchorExactStatus exact_add_signed(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                          int32_t right_sign, AnchorExactInteger *result)
{
    if (left->sign == 0)
    {
        *result = *right;
        result->sign = right_sign;
        return ANCHOR_EXACT_OK;
    }
    if (right_sign == 0)
    {
        *result = *left;
        return ANCHOR_EXACT_OK;
    }

    if (left->sign == right_sign)
    {
        if (magnitude_add_overflows(left->limb, right->limb) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        const int32_t sign = left->sign;
        magnitude_add(left->limb, right->limb, result->limb);
        settle_sign(result, sign);
        return ANCHOR_EXACT_OK;
    }

    const int order = magnitude_compare(left->limb, right->limb);
    if (order == 0)
    {
        anchor_exact_zero(result);
        return ANCHOR_EXACT_OK;
    }

    // The sign is taken before the limbs are written, since `result` may be either input.
    if (order > 0)
    {
        const int32_t sign = left->sign;
        magnitude_subtract(left->limb, right->limb, result->limb);
        settle_sign(result, sign);
    }
    else
    {
        magnitude_subtract(right->limb, left->limb, result->limb);
        settle_sign(result, right_sign);
    }
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_add(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                   AnchorExactInteger *result)
{
    return exact_add_signed(left, right, right->sign, result);
}

AnchorExactStatus anchor_exact_subtract(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    return exact_add_signed(left, right, -right->sign, result);
}
