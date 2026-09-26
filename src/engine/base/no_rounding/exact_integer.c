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

/** @brief Most decimal digits one limb takes in a single multiply, since 10^9 is below 2^32. */
#define LIMB_DECIMAL_DIGITS 9u

#define EXACT_LIMBS ((size_t)ANCHOR_EXACT_LIMBS)

// A call's width-sized working copies are one room, placed at compile time: on the stack while the width is at most
// ANCHOR_EXACT_STACK_LIMBS, from the heap beyond it, so no width is bounded by a stack. A room from the heap that
// cannot be held is refused as ANCHOR_EXACT_WILL_NOT_FIT.
#if (ANCHOR_EXACT_LIMBS) <= (ANCHOR_EXACT_STACK_LIMBS)
#define EXACT_ROOM(name_, count_)                                                                                      \
    uint32_t name_##_on_stack[count_];                                                                                 \
    uint32_t *const name_ = name_##_on_stack
#define EXACT_ROOM_HELD(name_) (1)
#define EXACT_ROOM_RELEASE(name_) ((void)(name_))
#define EXACT_VALUE(name_)                                                                                             \
    AnchorExactInteger name_##_on_stack;                                                                               \
    AnchorExactInteger *const name_ = &name_##_on_stack
#define EXACT_VALUE_RELEASE(name_) ((void)(name_))
#else
#define EXACT_ROOM(name_, count_) uint32_t *const name_ = (uint32_t *)malloc((size_t)(count_) * sizeof(uint32_t))
#define EXACT_ROOM_HELD(name_) ((name_) != NULL)
#define EXACT_ROOM_RELEASE(name_) free(name_)
#define EXACT_VALUE(name_) AnchorExactInteger *const name_ = (AnchorExactInteger *)malloc(sizeof(AnchorExactInteger))
#define EXACT_VALUE_RELEASE(name_) free(name_)
#endif

/** @brief Ten raised to each power a single limb multiply can apply, 10^0 to 10^9. */
static const uint32_t TEN_TO[LIMB_DECIMAL_DIGITS + 1u] = {
    1u, 10u, 100u, 1000u, 10000u, 100000u, 1000000u, 10000000u, 100000000u, 1000000000u,
};

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
 * @brief How many limbs a magnitude uses.
 *
 * @param[in] value Magnitude [BORROWS].
 * @return          One past the index of the highest nonzero limb, and 0 for zero.
 */
static size_t magnitude_used(const uint32_t *value)
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
        const uint32_t room = ~right[at];
        if (left[at] != room)
        {
            return (left[at] > room) ? 1 : 0;
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
static void settle_sign(AnchorExactInteger *result, int32_t sign)
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
static AnchorExactStatus exact_add_signed(const AnchorExactInteger *left,
                                          const AnchorExactInteger *right, int32_t right_sign,
                                          AnchorExactInteger *result)
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

AnchorExactStatus anchor_exact_subtract(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    return exact_add_signed(left, right, -right->sign, result);
}

static uint32_t limbs_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
{
    uint64_t carry = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        const uint64_t total = (uint64_t)left[at] + (uint64_t)right[at] + carry;
        result[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    // the carry out of the top limb is 0 or 1
    return (uint32_t)carry;
}

static uint32_t limbs_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
{
    uint64_t borrow = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        const uint64_t total = LIMB_BASE + (uint64_t)left[at] - (uint64_t)right[at] - borrow;
        result[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
    // the borrow out of the top limb is 0 or 1
    return (uint32_t)borrow;
}

// value += added, the carry run up through the rest of value; returns the carry out of value's top
static uint32_t limbs_accumulate(uint32_t *value, size_t count, const uint32_t *added, size_t added_count)
{
    uint64_t carry = 0u;
    size_t at = 0u;
    for (; at < added_count; at++)
    {
        const uint64_t total = (uint64_t)value[at] + (uint64_t)added[at] + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    for (; (at < count) && (carry != 0u); at++)
    {
        const uint64_t total = (uint64_t)value[at] + carry;
        value[at] = (uint32_t)(total & LIMB_MASK);
        carry = total >> LIMB_BITS;
    }
    // the carry out of the top limb is 0 or 1
    return (uint32_t)carry;
}

// value -= taken, the borrow run up through the rest of value; returns the borrow out of value's top
static uint32_t limbs_deduct(uint32_t *value, size_t count, const uint32_t *taken, size_t taken_count)
{
    uint64_t borrow = 0u;
    size_t at = 0u;
    for (; at < taken_count; at++)
    {
        const uint64_t total = LIMB_BASE + (uint64_t)value[at] - (uint64_t)taken[at] - borrow;
        value[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
    for (; (at < count) && (borrow != 0u); at++)
    {
        const uint64_t total = LIMB_BASE + (uint64_t)value[at] - borrow;
        value[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
    // the borrow out of the top limb is 0 or 1
    return (uint32_t)borrow;
}

static void limbs_long_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                               size_t right_count)
{
    memset(result, 0, (left_count + right_count) * sizeof(result[0]));
    for (size_t low = 0u; low < left_count; low++)
    {
        if (left[low] == 0u)
        {
            continue;
        }
        uint64_t carry = 0u;
        for (size_t high = 0u; high < right_count; high++)
        {
            const uint64_t total = ((uint64_t)left[low] * (uint64_t)right[high]) + (uint64_t)result[low + high] + carry;
            result[low + high] = (uint32_t)(total & LIMB_MASK);
            carry = total >> LIMB_BITS;
        }
        // The row's carry lands on the limb just above it, which no earlier row reached: row
        // low - 1 wrote up to index low - 1 + right_count and no further. The largest total above is
        // (2^32 - 1)^2 + 2 * (2^32 - 1), exactly 2^64 - 1, and its high half fits one limb.
        result[low + right_count] = (uint32_t)carry;
    }
}

static int limbs_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                         size_t right_count);

// Karatsuba on two equal lengths: with a = a1 B + a0 and b = b1 B + b0, the three products a0 b0, a1 b1 and
// (a0 + a1)(b0 + b1) give the middle term as the third less the first two
static int limbs_karatsuba(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
{
    const size_t low = count / 2u;
    const size_t high = count - low;
    if ((limbs_product(result, left, low, right, low) == 0)
        || (limbs_product(&result[2u * low], &left[low], high, &right[low], high) == 0))
    {
        return 0;
    }
    uint32_t *const work = (uint32_t *)malloc(4u * (high + 1u) * sizeof(uint32_t));
    if (work == NULL)
    {
        return 0;
    }
    uint32_t *const left_sum = work;
    uint32_t *const right_sum = &work[high + 1u];
    uint32_t *const middle = &work[2u * (high + 1u)];
    memcpy(left_sum, &left[low], high * sizeof(uint32_t));
    memcpy(right_sum, &right[low], high * sizeof(uint32_t));
    left_sum[high] = limbs_accumulate(left_sum, high, left, low);
    right_sum[high] = limbs_accumulate(right_sum, high, right, low);
    if (limbs_product(middle, left_sum, high + 1u, right_sum, high + 1u) == 0)
    {
        free(work);
        return 0;
    }
    (void)limbs_deduct(middle, 2u * (high + 1u), result, 2u * low);
    (void)limbs_deduct(middle, 2u * (high + 1u), &result[2u * low], 2u * high);
    // a0 b1 + a1 b0 sits inside the product's limbs above low; the middle's limbs past them are zero
    const size_t room = (2u * count) - low;
    const size_t middle_count = (2u * (high + 1u) < room) ? (2u * (high + 1u)) : room;
    (void)limbs_accumulate(&result[low], room, middle, middle_count);
    free(work);
    return 1;
}

// result[0, left_count + right_count) = left . right by the rung that fits: long multiplication below the Karatsuba
// width, Karatsuba on equal lengths, and slices of the longer operand otherwise; 0 when workspace cannot be held
static int limbs_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                         size_t right_count)
{
    if (left_count < right_count)
    {
        const uint32_t *const swap = left;
        left = right;
        right = swap;
        const size_t count_swap = left_count;
        left_count = right_count;
        right_count = count_swap;
    }
    if (right_count < (size_t)ANCHOR_EXACT_KARATSUBA_LIMBS)
    {
        limbs_long_product(result, left, left_count, right, right_count);
        return 1;
    }
    if (left_count == right_count)
    {
        return limbs_karatsuba(result, left, right, left_count);
    }
    uint32_t *const slice = (uint32_t *)malloc(2u * right_count * sizeof(uint32_t));
    if (slice == NULL)
    {
        return 0;
    }
    memset(result, 0, (left_count + right_count) * sizeof(uint32_t));
    for (size_t start = 0u; start < left_count; start += right_count)
    {
        const size_t piece = ((left_count - start) < right_count) ? (left_count - start) : right_count;
        if (limbs_product(slice, &left[start], piece, right, right_count) == 0)
        {
            free(slice);
            return 0;
        }
        (void)limbs_accumulate(&result[start], (left_count + right_count) - start, slice, piece + right_count);
    }
    free(slice);
    return 1;
}

// A ring element modulo 2^n + 1, n = 32 limbs, is limbs + 1 words holding a value from 0 to 2^n. In this ring 2 is a
// root of unity (2^(2n) = 1), so every twiddle of the transform is a shift, and nothing is rounded.
#define TRANSFORM_BASE_LIMBS 64u

static unsigned int bits_ceiling_log(size_t value)
{
    unsigned int power = 0u;
    while (((size_t)1u << power) < value)
    {
        power++;
    }
    return power;
}

// the top word folded back: 2^n = -1
static void fermat_settle(uint32_t *value, size_t limbs)
{
    const uint32_t top = value[limbs];
    value[limbs] = 0u;
    uint64_t borrow = top;
    for (size_t at = 0u; (at < limbs) && (borrow != 0u); at++)
    {
        const uint64_t total = LIMB_BASE + (uint64_t)value[at] - borrow;
        value[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
    if (borrow != 0u)
    {
        // below zero by less than 2^n: adding 2^n + 1 is adding one to the wrapped words, the carry out giving 2^n
        uint32_t one = 1u;
        value[limbs] = limbs_accumulate(value, limbs, &one, 1u);
    }
}

static void fermat_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    (void)limbs_add(result, left, right, limbs + 1u);
    fermat_settle(result, limbs);
}

// a wrapped difference comes back by adding 2^n + 1, the wrap of the words cancelling
static void fermat_mend(uint32_t *value, size_t limbs)
{
    uint32_t one = 1u;
    (void)limbs_accumulate(value, limbs + 1u, &one, 1u);
    value[limbs] += 1u;
}

static void fermat_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    if (limbs_subtract(result, left, right, limbs + 1u) != 0u)
    {
        fermat_mend(result, limbs);
    }
}

static void fermat_negate(uint32_t *value, size_t limbs)
{
    uint64_t borrow = 0u;
    for (size_t at = 0u; at <= limbs; at++)
    {
        const uint64_t total = LIMB_BASE - (uint64_t)value[at] - borrow;
        value[at] = (uint32_t)(total & LIMB_MASK);
        borrow = (total < LIMB_BASE) ? 1u : 0u;
    }
    if (borrow != 0u)
    {
        fermat_mend(value, limbs);
    }
}

// result = value . 2^shift modulo 2^n + 1, by a shift and a fold; scratch holds 2 limbs + 2 words
static void fermat_shift(uint32_t *result, const uint32_t *value, size_t shift, size_t limbs, uint32_t *scratch)
{
    const size_t bits = limbs * LIMB_BITS;
    shift %= 2u * bits;
    const int negated = (shift >= bits);
    shift = negated ? (shift - bits) : shift;
    const size_t whole = shift / LIMB_BITS;
    const unsigned int part = (unsigned int)(shift % LIMB_BITS);
    memset(scratch, 0, ((2u * limbs) + 2u) * sizeof(uint32_t));
    for (size_t at = 0u; at <= limbs; at++)
    {
        scratch[at + whole] |= value[at] << part;
        if (part != 0u)
        {
            scratch[at + whole + 1u] |= value[at] >> (LIMB_BITS - part);
        }
    }
    // value . 2^shift < 2^(2n), so the part above n is below 2^n and its top word is zero
    memcpy(result, scratch, limbs * sizeof(uint32_t));
    result[limbs] = 0u;
    fermat_subtract(result, result, &scratch[limbs], limbs);
    if (negated)
    {
        fermat_negate(result, limbs);
    }
}

static int fermat_multiply(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs);

// the cyclic transform of count = 2^depth ring elements in place, root 2^root_bits: bit-reversed order, then
// butterflies (u, v) -> (u + w v, u - w v) with w a power of the root, every product by w a shift
static void fermat_fourier(uint32_t *elements, size_t count, unsigned int depth, size_t limbs, size_t root_bits,
                           uint32_t *scratch, uint32_t *turned)
{
    const size_t width = limbs + 1u;
    const size_t cycle = 2u * limbs * LIMB_BITS;
    for (size_t at = 0u; at < count; at++)
    {
        size_t reversed = 0u;
        for (unsigned int bit = 0u; bit < depth; bit++)
        {
            reversed |= ((at >> bit) & 1u) << (depth - 1u - bit);
        }
        if (reversed > at)
        {
            memcpy(turned, &elements[at * width], width * sizeof(uint32_t));
            memcpy(&elements[at * width], &elements[reversed * width], width * sizeof(uint32_t));
            memcpy(&elements[reversed * width], turned, width * sizeof(uint32_t));
        }
    }
    for (size_t span = 2u; span <= count; span <<= 1u)
    {
        const size_t half = span / 2u;
        const size_t stage_bits = (root_bits * (count / span)) % cycle;
        for (size_t start = 0u; start < count; start += span)
        {
            for (size_t step = 0u; step < half; step++)
            {
                uint32_t *const upper = &elements[(start + step) * width];
                uint32_t *const lower = &elements[(start + step + half) * width];
                fermat_shift(turned, lower, (step * stage_bits) % cycle, limbs, scratch);
                fermat_subtract(lower, upper, turned, limbs);
                fermat_add(upper, upper, turned, limbs);
            }
        }
    }
}

// the inner ring for pieces of piece_bits in 2^depth parts: at least 2 piece_bits + depth + 2 bits, so a signed
// coefficient of the negacyclic product fits, and a multiple of the part count and of a limb; a ring past the base
// case also leaves room to split in turn
static size_t fermat_inner_bits(size_t piece_bits, unsigned int depth)
{
    const size_t least = (2u * piece_bits) + depth + 2u;
    const size_t parts = (size_t)1u << depth;
    const size_t tight_step = (parts > (size_t)LIMB_BITS) ? parts : (size_t)LIMB_BITS;
    const size_t tight = ((least + tight_step - 1u) / tight_step) * tight_step;
    if ((tight / LIMB_BITS) <= (size_t)TRANSFORM_BASE_LIMBS)
    {
        return tight;
    }
    size_t step = (size_t)LIMB_BITS << ((bits_ceiling_log(least) + 1u) / 2u);
    step = (step < parts) ? parts : step;
    return ((least + step - 1u) / step) * step;
}

// the modeled word operations of a product on the ladder below the transform: long multiplication's square, and
// Karatsuba's three half products and linear passes
static unsigned long long fermat_ladder_cost(size_t limbs)
{
    if (limbs < (size_t)ANCHOR_EXACT_KARATSUBA_LIMBS)
    {
        return (unsigned long long)limbs * limbs;
    }
    return (3ull * fermat_ladder_cost((limbs + 1u) / 2u)) + (8ull * limbs);
}

static unsigned long long fermat_cost(size_t limbs, unsigned int *depth);

// the modeled word operations of the transform at a depth: three transforms of 2^depth depth / 2 butterflies over
// the inner ring's words, a few passes each, and the pointwise products at their own best; a split whose inner ring
// is no smaller than the ring is never taken
static unsigned long long fermat_cost_at(size_t limbs, unsigned int depth)
{
    const size_t parts = (size_t)1u << depth;
    const size_t inner = fermat_inner_bits((limbs / parts) * LIMB_BITS, depth) / LIMB_BITS;
    if (inner >= limbs)
    {
        return ~0ull;
    }
    unsigned int inner_depth = 0u;
    const unsigned long long point = fermat_cost(inner, &inner_depth);
    return (6ull * parts * depth * (inner + 1u)) + (4ull * parts * (inner + 1u)) + (parts * point);
}

// the cheapest way to multiply in the ring of the given limbs: the depth of the transform, or 0 for the ladder
// below; depths are tried near the balanced split of sqrt(n) pieces, where the inner ring is near sqrt(n) bits, so
// the model's own recursion is a few levels deep
static unsigned long long fermat_cost(size_t limbs, unsigned int *depth)
{
    unsigned long long best = fermat_ladder_cost(limbs) + (2ull * limbs);
    *depth = 0u;
    if (limbs <= (size_t)TRANSFORM_BASE_LIMBS)
    {
        return best;
    }
    const unsigned int balanced = (bits_ceiling_log(limbs * LIMB_BITS) + 1u) / 2u;
    const unsigned int lowest = (balanced > 4u) ? (balanced - 2u) : 2u;
    for (unsigned int trial = lowest; (trial <= (balanced + 1u)) && (((limbs >> trial) << trial) == limbs); trial++)
    {
        const unsigned long long cost = fermat_cost_at(limbs, trial);
        if (cost < best)
        {
            best = cost;
            *depth = trial;
        }
    }
    return best;
}

// the number of pieces a ring of the given limbs splits into, 2^depth pieces of whole limbs, chosen by the cost
// model; 0 is the ladder below the transform
static unsigned int fermat_depth(size_t limbs)
{
    unsigned int depth = 0u;
    (void)fermat_cost(limbs, &depth);
    return depth;
}

// Schonhage-Strassen modulo 2^n + 1: the value is cut into 2^depth pieces; the pieces are weighted by powers of
// psi = 2^(n' / 2^depth), whose 2^depth-th power is -1 in the inner ring 2^n' + 1, which turns the cyclic transform
// into the negacyclic product the outer ring needs; the transforms multiply point by point, recursively, and the
// inverse transform, the division by 2^depth and the unweighting are shifts
static int fermat_transform(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs,
                            unsigned int depth)
{
    const size_t count = (size_t)1u << depth;
    const size_t piece = limbs / count;
    const size_t inner_bits = fermat_inner_bits(piece * LIMB_BITS, depth);
    const size_t inner = inner_bits / LIMB_BITS;
    const size_t width = inner + 1u;
    const size_t cycle = 2u * inner_bits;
    const size_t total = limbs + width + 1u;
    uint32_t *const held = (uint32_t *)calloc((2u * count * width) + (4u * width) + (2u * total) + 2u, sizeof(uint32_t));
    if (held == NULL)
    {
        return 0;
    }
    uint32_t *const first = held;
    uint32_t *const second = &held[count * width];
    uint32_t *const scratch = &held[2u * count * width];
    uint32_t *const turned = &scratch[(2u * inner) + 2u];
    uint32_t *const product = &turned[width];
    uint32_t *const positive = &product[width];
    uint32_t *const negative = &positive[total];
    for (size_t at = 0u; at < count; at++)
    {
        memcpy(&first[at * width], &left[at * piece], piece * sizeof(uint32_t));
        memcpy(&second[at * width], &right[at * piece], piece * sizeof(uint32_t));
        fermat_shift(&first[at * width], &first[at * width], at * (inner_bits / count), inner, scratch);
        fermat_shift(&second[at * width], &second[at * width], at * (inner_bits / count), inner, scratch);
    }
    fermat_fourier(first, count, depth, inner, (2u * inner_bits) / count, scratch, turned);
    fermat_fourier(second, count, depth, inner, (2u * inner_bits) / count, scratch, turned);
    for (size_t at = 0u; at < count; at++)
    {
        if (fermat_multiply(product, &first[at * width], &second[at * width], inner) == 0)
        {
            free(held);
            return 0;
        }
        memcpy(&first[at * width], product, width * sizeof(uint32_t));
    }
    fermat_fourier(first, count, depth, inner, cycle - ((2u * inner_bits) / count), scratch, turned);
    for (size_t at = 0u; at < count; at++)
    {
        uint32_t *const coefficient = &first[at * width];
        // divide by 2^depth and unweight by psi^-at in one shift
        const size_t back = ((2u * cycle) - depth - (at * (inner_bits / count))) % cycle;
        fermat_shift(coefficient, coefficient, back, inner, scratch);
        // above half the ring is a negative coefficient
        const int below_zero = (coefficient[inner] != 0u) || ((coefficient[inner - 1u] >> (LIMB_BITS - 1u)) != 0u);
        if (below_zero)
        {
            fermat_negate(coefficient, inner);
        }
        (void)limbs_accumulate(&(below_zero ? negative : positive)[at * piece], total - (at * piece), coefficient, width);
    }
    // each sum folds into the ring, n bits at a time with alternating signs, 2^n being -1
    uint32_t *const folded = product;
    memset(result, 0, (limbs + 1u) * sizeof(uint32_t));
    uint32_t *const chunk = (uint32_t *)calloc(limbs + 1u, sizeof(uint32_t));
    if (chunk == NULL)
    {
        free(held);
        return 0;
    }
    for (unsigned int sign = 0u; sign < 2u; sign++)
    {
        const uint32_t *const sum = (sign == 0u) ? positive : negative;
        uint32_t *const into = (uint32_t *)calloc(limbs + 1u, sizeof(uint32_t));
        if (into == NULL)
        {
            free(chunk);
            free(held);
            return 0;
        }
        for (size_t start = 0u, index = 0u; start < total; start += limbs, index++)
        {
            const size_t taken = ((total - start) < limbs) ? (total - start) : limbs;
            memset(chunk, 0, (limbs + 1u) * sizeof(uint32_t));
            memcpy(chunk, &sum[start], taken * sizeof(uint32_t));
            if ((index & 1u) == 0u)
            {
                fermat_add(into, into, chunk, limbs);
            }
            else
            {
                fermat_subtract(into, into, chunk, limbs);
            }
        }
        if (sign == 0u)
        {
            memcpy(result, into, (limbs + 1u) * sizeof(uint32_t));
        }
        else
        {
            fermat_subtract(result, result, into, limbs);
        }
        free(into);
    }
    (void)folded;
    free(chunk);
    free(held);
    return 1;
}

// result = left . right modulo 2^n + 1; result is distinct from both
static int fermat_multiply(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    if ((left[limbs] != 0u) || (right[limbs] != 0u))
    {
        // 2^n is -1
        memcpy(result, (left[limbs] != 0u) ? right : left, (limbs + 1u) * sizeof(uint32_t));
        if ((left[limbs] != 0u) && (right[limbs] != 0u))
        {
            memset(result, 0, (limbs + 1u) * sizeof(uint32_t));
            result[0] = 1u;
            return 1;
        }
        fermat_negate(result, limbs);
        return 1;
    }
    const unsigned int depth = fermat_depth(limbs);
    if (depth < 2u)
    {
        uint32_t *const product = (uint32_t *)calloc((2u * limbs) + 1u, sizeof(uint32_t));
        if ((product == NULL) || (limbs_product(product, left, limbs, right, limbs) == 0))
        {
            free(product);
            return 0;
        }
        memcpy(result, product, limbs * sizeof(uint32_t));
        result[limbs] = 0u;
        fermat_subtract(result, result, &product[limbs], limbs);
        free(product);
        return 1;
    }
    return fermat_transform(result, left, right, limbs, depth);
}

// the product of used limbs by the transform, into wide (left_used + right_used limbs); 0 when workspace cannot be held
static int transform_product(uint32_t *wide, const uint32_t *left, size_t left_used, const uint32_t *right,
                             size_t right_used)
{
    const size_t bits = (left_used + right_used) * LIMB_BITS;
    const size_t step = (size_t)LIMB_BITS << ((bits_ceiling_log(bits) + 1u) / 2u);
    const size_t limbs = (((bits + step - 1u) / step) * step) / LIMB_BITS;
    uint32_t *const held = (uint32_t *)calloc(3u * (limbs + 1u), sizeof(uint32_t));
    if (held == NULL)
    {
        return 0;
    }
    uint32_t *const first = held;
    uint32_t *const second = &held[limbs + 1u];
    uint32_t *const product = &held[2u * (limbs + 1u)];
    memcpy(first, left, left_used * sizeof(uint32_t));
    memcpy(second, right, right_used * sizeof(uint32_t));
    // the product is below 2^bits <= 2^n, so the ring leaves it whole
    const int held_product = fermat_multiply(product, first, second, limbs);
    if (held_product != 0)
    {
        memcpy(wide, product, (left_used + right_used) * sizeof(uint32_t));
    }
    free(held);
    return held_product;
}

// the product by the rung of the ladder the operands reach, or by the transform alone when it is asked for; a rung
// that cannot hold its workspace steps down to the one below, and long multiplication needs none
static AnchorExactStatus exact_multiply_by(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                           AnchorExactInteger *result, int transform_only)
{
    if ((left->sign == 0) || (right->sign == 0))
    {
        anchor_exact_zero(result);
        return ANCHOR_EXACT_OK;
    }

    // A factor using n limbs is at least 2^(32 * (n - 1)). The product of factors using n and m limbs
    // is at least 2^(32 * (n + m - 2)). Where n + m passes the width by more than one limb, that
    // product already overruns and nothing is multiplied.
    const size_t left_used = magnitude_used(left->limb);
    const size_t right_used = magnitude_used(right->limb);
    const size_t reach = left_used + right_used;
    if (reach > (EXACT_LIMBS + 1u))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    // The product is below 2^(32 * reach) and occupies at most `reach` limbs, at most one past the
    // width. An overrun shows in that extra limb, and the accumulator keeps it instead of wrapping
    // it away.
    EXACT_ROOM(wide, EXACT_LIMBS + 1u);
    if (!EXACT_ROOM_HELD(wide))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    const size_t shorter = (left_used < right_used) ? left_used : right_used;
    int held = 0;
    if ((transform_only != 0) || (shorter >= (size_t)ANCHOR_EXACT_TRANSFORM_LIMBS))
    {
        held = transform_product(wide, left->limb, left_used, right->limb, right_used);
    }
    if ((held == 0) && (transform_only == 0))
    {
        held = limbs_product(wide, left->limb, left_used, right->limb, right_used);
        if (held == 0)
        {
            limbs_long_product(wide, left->limb, left_used, right->limb, right_used);
            held = 1;
        }
    }
    AnchorExactStatus status = ANCHOR_EXACT_OK;
    if ((held == 0) || ((reach > EXACT_LIMBS) && (wide[EXACT_LIMBS] != 0u)))
    {
        status = ANCHOR_EXACT_WILL_NOT_FIT;
    }
    else
    {
        // Written only now, and the sign taken first, since `result` may be either factor.
        const int32_t sign = (left->sign == right->sign) ? 1 : -1;
        const size_t kept = (reach < EXACT_LIMBS) ? reach : EXACT_LIMBS;
        memcpy(result->limb, wide, kept * sizeof(uint32_t));
        memset(&result->limb[kept], 0, (EXACT_LIMBS - kept) * sizeof(uint32_t));
        settle_sign(result, sign);
    }
    EXACT_ROOM_RELEASE(wide);
    return status;
}

AnchorExactStatus anchor_exact_multiply_transform(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                                  AnchorExactInteger *result)
{
    return exact_multiply_by(left, right, result, 1);
}

AnchorExactStatus anchor_exact_multiply(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right,
                                        AnchorExactInteger *result)
{
    return exact_multiply_by(left, right, result, 0);
}

static unsigned int limb_leading_zeros(uint32_t word)
{
    unsigned int zeros = 0u;
    while ((word & 0x80000000u) == 0u)
    {
        zeros++;
        word <<= 1u;
    }
    return zeros;
}

static size_t limbs_used(const uint32_t *value, size_t count)
{
    while ((count > 0u) && (value[count - 1u] == 0u))
    {
        count--;
    }
    return count;
}

// the order of two magnitudes of the given used lengths, their top limbs nonzero
static int limbs_compare(const uint32_t *left, size_t left_used, const uint32_t *right, size_t right_used)
{
    if (left_used != right_used)
    {
        return (left_used < right_used) ? -1 : 1;
    }
    for (size_t at = left_used; at > 0u; at--)
    {
        if (left[at - 1u] != right[at - 1u])
        {
            return (left[at - 1u] < right[at - 1u]) ? -1 : 1;
        }
    }
    return 0;
}

// Knuth's algorithm D in base 2^32 on operands of any length: the top two limbs of the running remainder over the
// divisor's normalized top limb estimate each quotient limb, the estimate is at most two high, and the
// multiply-subtract's borrow says when to add the divisor back. top has top_used limbs and bottom bottom_used, its
// top limb nonzero; quotient takes top_used - bottom_used + 1 limbs and rest bottom_used, both written in full;
// work holds top_used + bottom_used + 1 words
static void limbs_divide(const uint32_t *top, size_t top_used, const uint32_t *bottom, size_t bottom_used,
                         uint32_t *quotient, uint32_t *rest, uint32_t *work)
{
    top_used = limbs_used(top, top_used);
    if (limbs_compare(top, top_used, bottom, bottom_used) < 0)
    {
        if (top_used >= bottom_used)
        {
            memset(quotient, 0, ((top_used - bottom_used) + 1u) * sizeof(uint32_t));
        }
        memset(rest, 0, bottom_used * sizeof(uint32_t));
        memcpy(rest, top, top_used * sizeof(uint32_t));
        return;
    }
    memset(quotient, 0, ((top_used - bottom_used) + 1u) * sizeof(uint32_t));
    memset(rest, 0, bottom_used * sizeof(uint32_t));
    if (bottom_used == 1u)
    {
        const uint64_t divisor = (uint64_t)bottom[0];
        uint64_t carried = 0u;
        for (size_t at = top_used; at > 0u; at--)
        {
            const uint64_t current = (carried << LIMB_BITS) | (uint64_t)top[at - 1u];
            // current is below divisor . 2^32, so the quotient limb fits 32 bits
            quotient[at - 1u] = (uint32_t)(current / divisor);
            carried = current % divisor;
        }
        rest[0] = (uint32_t)carried;
        return;
    }
    const unsigned int shift = limb_leading_zeros(bottom[bottom_used - 1u]);
    uint32_t *const divisor = work;
    uint32_t *const running = &work[bottom_used];
    for (size_t at = bottom_used; at > 0u; at--)
    {
        const uint32_t below = ((at > 1u) && (shift != 0u)) ? (bottom[at - 2u] >> (LIMB_BITS - shift)) : 0u;
        divisor[at - 1u] = (bottom[at - 1u] << shift) | below;
    }
    running[top_used] = (shift != 0u) ? (top[top_used - 1u] >> (LIMB_BITS - shift)) : 0u;
    for (size_t at = top_used; at > 0u; at--)
    {
        const uint32_t below = ((at > 1u) && (shift != 0u)) ? (top[at - 2u] >> (LIMB_BITS - shift)) : 0u;
        running[at - 1u] = (top[at - 1u] << shift) | below;
    }
    const uint64_t leading = (uint64_t)divisor[bottom_used - 1u];
    const uint64_t second = (uint64_t)divisor[bottom_used - 2u];
    for (size_t place = (top_used - bottom_used) + 1u; place > 0u; place--)
    {
        const size_t at = place - 1u;
        const uint64_t head = ((uint64_t)running[at + bottom_used] << LIMB_BITS) | (uint64_t)running[at + bottom_used - 1u];
        uint64_t estimate = head / leading;
        uint64_t left_over = head % leading;
        while ((estimate >= LIMB_BASE)
               || ((estimate * second) > ((left_over << LIMB_BITS) | (uint64_t)running[at + bottom_used - 2u])))
        {
            estimate--;
            left_over += leading;
            if (left_over >= LIMB_BASE)
            {
                break;
            }
        }
        uint64_t carry = 0u;
        uint64_t borrow = 0u;
        for (size_t limb = 0u; limb < bottom_used; limb++)
        {
            const uint64_t product = (estimate * (uint64_t)divisor[limb]) + carry;
            carry = product >> LIMB_BITS;
            const uint64_t difference = (uint64_t)running[at + limb] - (product & LIMB_MASK) - borrow;
            running[at + limb] = (uint32_t)(difference & LIMB_MASK);
            // a wrapped difference has its top bit set, both parts being below 2^33
            borrow = difference >> 63u;
        }
        const uint64_t difference = (uint64_t)running[at + bottom_used] - carry - borrow;
        running[at + bottom_used] = (uint32_t)(difference & LIMB_MASK);
        if ((difference >> 63u) != 0u)
        {
            estimate--;
            uint64_t sum_carry = 0u;
            for (size_t limb = 0u; limb < bottom_used; limb++)
            {
                const uint64_t sum = (uint64_t)running[at + limb] + (uint64_t)divisor[limb] + sum_carry;
                running[at + limb] = (uint32_t)(sum & LIMB_MASK);
                sum_carry = sum >> LIMB_BITS;
            }
            running[at + bottom_used] = (uint32_t)(((uint64_t)running[at + bottom_used] + sum_carry) & LIMB_MASK);
        }
        // the estimate was brought below 2^32 above
        quotient[at] = (uint32_t)estimate;
    }
    for (size_t at = 0u; at < bottom_used; at++)
    {
        const uint32_t above = (shift != 0u) ? (running[at + 1u] << (LIMB_BITS - shift)) : 0u;
        rest[at] = (running[at] >> shift) | above;
    }
}

static void limbs_ladder_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                                 size_t right_count);

// the precision below which the reciprocal is taken by long division outright
#define NEWTON_BASE_LIMBS 32u

// x = floor(beta^t / d), beta = 2^32, for d of used limbs with its top limb nonzero and t >= used; x takes
// t - used + 2 limbs. Each level halves the quotient's precision p: the top p/2 + 2 limbs of d give a reciprocal good
// to half the limbs, shifted back up; one Newton step x + x (beta^t - d x) / beta^t squares its relative error; and
// multiplying back fixes the last units exactly. Every product is on the ladder, so the reciprocal costs a few
// products. 0 when workspace cannot be held
static int limbs_reciprocal(uint32_t *x, const uint32_t *d, size_t used, size_t t)
{
    const size_t precision = t - used;
    const size_t count = precision + 2u;
    memset(x, 0, count * sizeof(uint32_t));
    if ((precision <= (size_t)NEWTON_BASE_LIMBS) || (used <= (size_t)NEWTON_BASE_LIMBS))
    {
        uint32_t *const held = (uint32_t *)calloc((t + 1u) + (t + 2u) + used + (t + used + 2u), sizeof(uint32_t));
        if (held == NULL)
        {
            return 0;
        }
        uint32_t *const power = held;
        uint32_t *const quotient = &power[t + 1u];
        uint32_t *const rest = &quotient[t + 2u];
        uint32_t *const work = &rest[used];
        power[t] = 1u;
        limbs_divide(power, t + 1u, d, used, quotient, rest, work);
        memcpy(x, quotient, count * sizeof(uint32_t));
        free(held);
        return 1;
    }
    const size_t half = precision / 2u;
    const size_t inner_precision = precision - half;
    const size_t keep = (used < (inner_precision + 2u)) ? used : (inner_precision + 2u);
    const size_t dropped = used - keep;
    // products run to t + 4 limbs; the Newton step's error term to t + 2
    const size_t span = t + precision + 8u;
    uint32_t *const held = (uint32_t *)calloc((5u * span) + count, sizeof(uint32_t));
    if (held == NULL)
    {
        return 0;
    }
    uint32_t *const guess = held;
    uint32_t *const product = &guess[span];
    uint32_t *const error = &product[span];
    uint32_t *const step = &error[span];
    uint32_t *const correction = &step[span];
    uint32_t *const inner = &correction[span];
    if (limbs_reciprocal(inner, &d[dropped], keep, keep + inner_precision) == 0)
    {
        free(held);
        return 0;
    }
    // the half-precision reciprocal, shifted up by the limbs of precision it lacks
    memcpy(&guess[half], inner, (inner_precision + 2u) * sizeof(uint32_t));
    size_t guess_used = limbs_used(guess, count);
    // the error beta^t - d x, and its sign
    limbs_ladder_product(product, d, used, guess, guess_used);
    size_t product_used = limbs_used(product, used + guess_used);
    memset(error, 0, span * sizeof(uint32_t));
    error[t] = 1u;
    const int over = (limbs_compare(product, product_used, error, t + 1u) > 0);
    if (over)
    {
        (void)limbs_subtract(error, product, error, product_used);
    }
    else
    {
        (void)limbs_subtract(error, error, product, t + 1u);
    }
    const size_t error_used = limbs_used(error, (product_used > (t + 1u)) ? product_used : (t + 1u));
    if (error_used != 0u)
    {
        // the step x . |e| / beta^t, taken down by t limbs
        memset(step, 0, span * sizeof(uint32_t));
        limbs_ladder_product(step, guess, guess_used, error, error_used);
        const size_t step_used = limbs_used(step, guess_used + error_used);
        memset(correction, 0, span * sizeof(uint32_t));
        // the step is below the guess; the cap only keeps a far guess inside its limbs, the exact pass below fixing it
        const size_t correction_used = (step_used > t) ? (((step_used - t) < count) ? (step_used - t) : count) : 0u;
        memcpy(correction, &step[t], correction_used * sizeof(uint32_t));
        if (over)
        {
            (void)limbs_deduct(guess, count, correction, correction_used);
        }
        else
        {
            (void)limbs_accumulate(guess, count, correction, correction_used);
        }
    }
    // exact: step back while d x > beta^t, then up while beta^t - d x >= d
    guess_used = limbs_used(guess, count);
    memset(product, 0, span * sizeof(uint32_t));
    limbs_ladder_product(product, d, used, guess, guess_used);
    product_used = limbs_used(product, used + guess_used);
    memset(error, 0, span * sizeof(uint32_t));
    error[t] = 1u;
    uint32_t one = 1u;
    while (limbs_compare(product, product_used, error, t + 1u) > 0)
    {
        (void)limbs_deduct(guess, count, &one, 1u);
        (void)limbs_deduct(product, product_used, d, used);
        product_used = limbs_used(product, product_used);
    }
    (void)limbs_subtract(error, error, product, t + 1u);
    size_t rest_used = limbs_used(error, t + 1u);
    while (limbs_compare(error, rest_used, d, used) >= 0)
    {
        (void)limbs_accumulate(guess, count, &one, 1u);
        (void)limbs_deduct(error, rest_used, d, used);
        rest_used = limbs_used(error, rest_used);
    }
    memcpy(x, guess, count * sizeof(uint32_t));
    free(held);
    return 1;
}

// division by the reciprocal: with x = floor(beta^n / d) for a top of n limbs, q = floor(top x / beta^n) is the
// quotient or at most two below it, and the remainder settles it; quotient takes n - used + 1 limbs and rest used.
// 0 when workspace cannot be held
static int limbs_divide_newton(const uint32_t *top, size_t top_used, const uint32_t *bottom, size_t bottom_used,
                               uint32_t *quotient, uint32_t *rest)
{
    top_used = limbs_used(top, top_used);
    if (limbs_compare(top, top_used, bottom, bottom_used) < 0)
    {
        if (top_used >= bottom_used)
        {
            memset(quotient, 0, ((top_used - bottom_used) + 1u) * sizeof(uint32_t));
        }
        memset(rest, 0, bottom_used * sizeof(uint32_t));
        memcpy(rest, top, top_used * sizeof(uint32_t));
        return 1;
    }
    const size_t precision = top_used - bottom_used;
    const size_t span = (2u * top_used) + 8u;
    uint32_t *const held = (uint32_t *)calloc((precision + 2u) + (2u * span), sizeof(uint32_t));
    if (held == NULL)
    {
        return 0;
    }
    uint32_t *const reciprocal = held;
    uint32_t *const product = &reciprocal[precision + 2u];
    uint32_t *const estimate = &product[span];
    if (limbs_reciprocal(reciprocal, bottom, bottom_used, top_used) == 0)
    {
        free(held);
        return 0;
    }
    const size_t reciprocal_used = limbs_used(reciprocal, precision + 2u);
    limbs_ladder_product(product, top, top_used, reciprocal, reciprocal_used);
    const size_t product_used = limbs_used(product, top_used + reciprocal_used);
    const size_t estimate_used = (product_used > top_used) ? (product_used - top_used) : 0u;
    memcpy(estimate, &product[top_used], estimate_used * sizeof(uint32_t));
    // the remainder top - q d, then up while it is at least d
    memset(product, 0, span * sizeof(uint32_t));
    if (estimate_used != 0u)
    {
        limbs_ladder_product(product, estimate, estimate_used, bottom, bottom_used);
    }
    uint32_t *const remainder = &product[span / 2u];
    memset(remainder, 0, (span / 2u) * sizeof(uint32_t));
    memcpy(remainder, top, top_used * sizeof(uint32_t));
    (void)limbs_deduct(remainder, top_used, product, limbs_used(product, estimate_used + bottom_used));
    size_t remainder_used = limbs_used(remainder, top_used);
    uint32_t one = 1u;
    while (limbs_compare(remainder, remainder_used, bottom, bottom_used) >= 0)
    {
        (void)limbs_accumulate(estimate, precision + 2u, &one, 1u);
        (void)limbs_deduct(remainder, remainder_used, bottom, bottom_used);
        remainder_used = limbs_used(remainder, remainder_used);
    }
    memcpy(quotient, estimate, (precision + 1u) * sizeof(uint32_t));
    memset(rest, 0, bottom_used * sizeof(uint32_t));
    memcpy(rest, remainder, remainder_used * sizeof(uint32_t));
    free(held);
    return 1;
}

// the full-width division: Newton's once the divisor and the quotient both reach ANCHOR_EXACT_NEWTON_LIMBS (or
// always, when asked), long division below it or when Newton's workspace cannot be held; work holds 2 limbs + 1 words
static void magnitude_divide_by(const uint32_t *top, const uint32_t *bottom, uint32_t *quotient, uint32_t *rest,
                                uint32_t *work, int newton_only)
{
    const size_t top_used = magnitude_used(top);
    const size_t bottom_used = magnitude_used(bottom);
    memset(quotient, 0, EXACT_LIMBS * sizeof(uint32_t));
    memset(rest, 0, EXACT_LIMBS * sizeof(uint32_t));
    const size_t quotient_limbs = (top_used >= bottom_used) ? ((top_used - bottom_used) + 1u) : 0u;
    const int by_newton = (newton_only != 0)
                       || ((bottom_used >= (size_t)ANCHOR_EXACT_NEWTON_LIMBS) && (quotient_limbs >= (size_t)ANCHOR_EXACT_NEWTON_LIMBS));
    if ((quotient_limbs != 0u) && (by_newton != 0))
    {
        // the quotient's limbs past the width are zero, the quotient being no larger than the top
        uint32_t *const whole = (uint32_t *)calloc(quotient_limbs + 1u, sizeof(uint32_t));
        if ((whole != NULL) && (limbs_divide_newton(top, top_used, bottom, bottom_used, whole, rest) != 0))
        {
            memcpy(quotient, whole, ((quotient_limbs < EXACT_LIMBS) ? quotient_limbs : EXACT_LIMBS) * sizeof(uint32_t));
            free(whole);
            return;
        }
        free(whole);
    }
    if (quotient_limbs == 0u)
    {
        memcpy(rest, top, top_used * sizeof(uint32_t));
        return;
    }
    limbs_divide(top, top_used, bottom, bottom_used, quotient, rest, work);
}

static void magnitude_divide(const uint32_t *top, const uint32_t *bottom, uint32_t *quotient, uint32_t *rest,
                             uint32_t *work)
{
    magnitude_divide_by(top, bottom, quotient, rest, work, 0);
}

static AnchorExactStatus exact_divide_by(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                         AnchorExactInteger *quotient, AnchorExactInteger *remainder, int newton_only)
{
    if (divisor->sign == 0)
    {
        return ANCHOR_EXACT_BY_ZERO;
    }
    EXACT_ROOM(work, (4u * EXACT_LIMBS) + 1u);
    if (!EXACT_ROOM_HELD(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    uint32_t *const whole = work;
    uint32_t *const rest = &work[EXACT_LIMBS];
    magnitude_divide_by(numerator->limb, divisor->limb, whole, rest, &work[2u * EXACT_LIMBS], newton_only);
    // the signs are read before an output that shares an input is written
    const int32_t whole_sign = numerator->sign * divisor->sign;
    const int32_t rest_sign = numerator->sign;
    memcpy(quotient->limb, whole, EXACT_LIMBS * sizeof(uint32_t));
    settle_sign(quotient, whole_sign);
    memcpy(remainder->limb, rest, EXACT_LIMBS * sizeof(uint32_t));
    settle_sign(remainder, rest_sign);
    EXACT_ROOM_RELEASE(work);
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_divide(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                      AnchorExactInteger *quotient, AnchorExactInteger *remainder)
{
    return exact_divide_by(numerator, divisor, quotient, remainder, 0);
}

AnchorExactStatus anchor_exact_divide_newton(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                             AnchorExactInteger *quotient, AnchorExactInteger *remainder)
{
    return exact_divide_by(numerator, divisor, quotient, remainder, 1);
}

static size_t magnitude_trailing_zeros(const uint32_t *value)
{
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        uint32_t word = value[at];
        if (word != 0u)
        {
            size_t zeros = at * LIMB_BITS;
            while ((word & 1u) == 0u)
            {
                zeros++;
                word >>= 1u;
            }
            return zeros;
        }
    }
    return 0u;
}

static void magnitude_shift_down(uint32_t *value, size_t bits)
{
    const size_t whole = bits / LIMB_BITS;
    const unsigned int part = (unsigned int)(bits % LIMB_BITS);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        const size_t from = at + whole;
        const uint32_t low = (from < (size_t)ANCHOR_EXACT_LIMBS) ? value[from] : 0u;
        const uint32_t high = ((from + 1u) < (size_t)ANCHOR_EXACT_LIMBS) ? value[from + 1u] : 0u;
        value[at] = (part == 0u) ? low : ((low >> part) | (high << (LIMB_BITS - part)));
    }
}

// the caller keeps the shifted value inside the width
static void magnitude_shift_up(uint32_t *value, size_t bits)
{
    const size_t whole = bits / LIMB_BITS;
    const unsigned int part = (unsigned int)(bits % LIMB_BITS);
    for (size_t at = (size_t)ANCHOR_EXACT_LIMBS; at > 0u; at--)
    {
        const size_t to = at - 1u;
        const uint32_t low = (to >= whole) ? value[to - whole] : 0u;
        const uint32_t below = ((to >= (whole + 1u)) && (part != 0u)) ? value[to - whole - 1u] : 0u;
        value[to] = (part == 0u) ? low : ((low << part) | (below >> (LIMB_BITS - part)));
    }
}

// result[0, left_count + right_count) = left . right on the ladder: the transform once both reach its rung, Karatsuba
// or long multiplication below it, each stepping down when its workspace cannot be held
static void limbs_ladder_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                                 size_t right_count)
{
    const size_t shorter = (left_count < right_count) ? left_count : right_count;
    if ((shorter >= (size_t)ANCHOR_EXACT_TRANSFORM_LIMBS) && (transform_product(result, left, left_count, right, right_count) != 0))
    {
        return;
    }
    if (limbs_product(result, left, left_count, right, right_count) == 0)
    {
        limbs_long_product(result, left, left_count, right, right_count);
    }
}

// left . right modulo 2^(32 limbs) into result's low limbs, the rest of result zeroed: the multiply on the ladder and
// the mask; work holds 2 limbs words
static void magnitude_low_product(const uint32_t *left, const uint32_t *right, size_t limbs, uint32_t *result,
                                  uint32_t *work)
{
    limbs_ladder_product(work, left, limbs, right, limbs);
    memcpy(result, work, limbs * sizeof(uint32_t));
    memset(&result[limbs], 0, (EXACT_LIMBS - limbs) * sizeof(uint32_t));
}

// the inverse of an odd magnitude modulo 2^(32 limbs) by Newton's step x (2 - d x), which doubles the bits that are
// right, so each step works only to the doubled precision; 2 - t is the two's complement negation of t plus two;
// work holds four widths
static void magnitude_odd_inverse(const uint32_t *odd, size_t limbs, uint32_t *inverse, uint32_t *work)
{
    uint32_t *const guess = work;
    uint32_t *const step = &work[EXACT_LIMBS];
    uint32_t *const product = &work[2u * EXACT_LIMBS];
    memset(guess, 0, EXACT_LIMBS * sizeof(uint32_t));
    guess[0] = odd[0];
    // d . d = 1 modulo 8 for every odd d
    size_t right_bits = 3u;
    while (right_bits < (limbs * LIMB_BITS))
    {
        const size_t doubled = ((2u * right_bits) < (limbs * LIMB_BITS)) ? (2u * right_bits) : (limbs * LIMB_BITS);
        const size_t reach = (doubled + LIMB_BITS - 1u) / LIMB_BITS;
        magnitude_low_product(odd, guess, reach, step, product);
        uint64_t carry = 2u;
        for (size_t at = 0u; at < reach; at++)
        {
            // ~t + 1 + 2 in the first limb, the carry thereafter
            const uint64_t total = (uint64_t)(uint32_t)(~step[at]) + carry + ((at == 0u) ? 1u : 0u);
            step[at] = (uint32_t)(total & LIMB_MASK);
            carry = total >> LIMB_BITS;
        }
        magnitude_low_product(guess, step, reach, guess, product);
        right_bits = doubled;
    }
    memcpy(inverse, guess, EXACT_LIMBS * sizeof(uint32_t));
}

AnchorExactStatus anchor_exact_divide_exact(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                            AnchorExactInteger *quotient)
{
    if (divisor->sign == 0)
    {
        return ANCHOR_EXACT_BY_ZERO;
    }
    if (numerator->sign == 0)
    {
        anchor_exact_zero(quotient);
        return ANCHOR_EXACT_OK;
    }
    EXACT_ROOM(work, 10u * EXACT_LIMBS);
    if (!EXACT_ROOM_HELD(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    uint32_t *const odd = work;
    uint32_t *const top = &work[EXACT_LIMBS];
    uint32_t *const whole = &work[2u * EXACT_LIMBS];
    uint32_t *const back = &work[3u * EXACT_LIMBS];
    uint32_t *const inverse_work = &work[5u * EXACT_LIMBS];
    uint32_t *const inverse = &work[9u * EXACT_LIMBS];
    const size_t twos = magnitude_trailing_zeros(divisor->limb);
    memcpy(odd, divisor->limb, EXACT_LIMBS * sizeof(uint32_t));
    memcpy(top, numerator->limb, EXACT_LIMBS * sizeof(uint32_t));
    magnitude_shift_down(odd, twos);
    magnitude_shift_down(top, twos);
    const size_t limbs = magnitude_used(top);
    memset(whole, 0, EXACT_LIMBS * sizeof(uint32_t));
    if (limbs != 0u)
    {
        magnitude_odd_inverse(odd, limbs, inverse, inverse_work);
        magnitude_low_product(top, inverse, limbs, whole, inverse_work);
    }
    // multiplied back, the quotient must give the numerator's magnitude
    const size_t whole_used = magnitude_used(whole);
    const size_t divisor_used = magnitude_used(divisor->limb);
    AnchorExactStatus status = ANCHOR_EXACT_NOT_EXACT;
    if ((whole_used != 0u) && ((whole_used + divisor_used) <= (2u * EXACT_LIMBS)))
    {
        limbs_ladder_product(back, whole, whole_used, divisor->limb, divisor_used);
        memset(&back[whole_used + divisor_used], 0, ((2u * EXACT_LIMBS) - whole_used - divisor_used) * sizeof(uint32_t));
        if ((magnitude_compare(back, numerator->limb) == 0) && (magnitude_is_zero(&back[EXACT_LIMBS]) != 0))
        {
            const int32_t sign = numerator->sign * divisor->sign;
            memcpy(quotient->limb, whole, EXACT_LIMBS * sizeof(uint32_t));
            settle_sign(quotient, sign);
            status = ANCHOR_EXACT_OK;
        }
    }
    EXACT_ROOM_RELEASE(work);
    return status;
}

// the 32 bits of value starting at bit from, the bits past the top reading as zero
static uint64_t limbs_window(const uint32_t *value, size_t used, size_t from)
{
    const size_t whole = from / LIMB_BITS;
    const unsigned int part = (unsigned int)(from % LIMB_BITS);
    const uint64_t low = (whole < used) ? (uint64_t)value[whole] : 0u;
    const uint64_t high = ((whole + 1u) < used) ? (uint64_t)value[whole + 1u] : 0u;
    return ((low | (high << LIMB_BITS)) >> part) & LIMB_MASK;
}

// result = first . |first_factor| + or - second . |second_factor| over count limbs and one above, the factors below
// 2^32 in magnitude and of opposite signs or zero, the combination known to be non-negative; other holds count + 1
static void limbs_combine(uint32_t *result, const uint32_t *first, int64_t first_factor, const uint32_t *second,
                          int64_t second_factor, size_t count, uint32_t *other)
{
    // the magnitudes are below 2^32
    const uint64_t first_size = (uint64_t)((first_factor < 0) ? -first_factor : first_factor);
    const uint64_t second_size = (uint64_t)((second_factor < 0) ? -second_factor : second_factor);
    uint64_t first_carry = 0u;
    uint64_t second_carry = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        const uint64_t first_total = (first_size * (uint64_t)first[at]) + first_carry;
        const uint64_t second_total = (second_size * (uint64_t)second[at]) + second_carry;
        result[at] = (uint32_t)(first_total & LIMB_MASK);
        other[at] = (uint32_t)(second_total & LIMB_MASK);
        first_carry = first_total >> LIMB_BITS;
        second_carry = second_total >> LIMB_BITS;
    }
    result[count] = (uint32_t)first_carry;
    other[count] = (uint32_t)second_carry;
    if ((first_factor >= 0) && (second_factor >= 0))
    {
        (void)limbs_add(result, result, other, count + 1u);
    }
    else if (first_factor >= 0)
    {
        (void)limbs_subtract(result, result, other, count + 1u);
    }
    else
    {
        (void)limbs_subtract(result, other, result, count + 1u);
    }
}

// Lehmer's gcd (Knuth's algorithm L): the leading 32 bits of u and the same bits of v run Euclid's steps in words
// while the quotient is certain, and the steps' cofactors then advance u and v in one pass, about thirty bits at a
// time; where no step is certain one long division advances them; the last two words finish in a word
AnchorExactStatus anchor_exact_gcd(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                   AnchorExactInteger *result)
{
    if (left->sign == 0)
    {
        *result = *right;
        result->sign = (right->sign == 0) ? 0 : 1;
        return ANCHOR_EXACT_OK;
    }
    if (right->sign == 0)
    {
        *result = *left;
        result->sign = 1;
        return ANCHOR_EXACT_OK;
    }
    EXACT_ROOM(work, (9u * EXACT_LIMBS) + 8u);
    if (!EXACT_ROOM_HELD(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    const size_t width = EXACT_LIMBS + 1u;
    uint32_t *buffer[4] = {work, &work[width], &work[2u * width], &work[3u * width]};
    size_t reach[4] = {width, width, width, width};
    uint32_t *const other = &work[4u * width];
    uint32_t *const quotient = &work[5u * width];
    uint32_t *const divide_work = &work[(5u * width) + EXACT_LIMBS];
    memset(work, 0, 4u * width * sizeof(uint32_t));
    const int left_larger = (magnitude_compare(left->limb, right->limb) >= 0);
    memcpy(buffer[0], left_larger ? left->limb : right->limb, EXACT_LIMBS * sizeof(uint32_t));
    memcpy(buffer[1], left_larger ? right->limb : left->limb, EXACT_LIMBS * sizeof(uint32_t));
    // u in buffer[held], v in buffer[held + 1], the next pair in the other two
    unsigned int held = 0u;
    size_t larger_used = limbs_used(buffer[0], width);
    size_t smaller_used = limbs_used(buffer[1], width);
    while (smaller_used > 2u)
    {
        uint32_t *const larger = buffer[held];
        uint32_t *const smaller = buffer[held + 1u];
        const size_t top = ((larger_used - 1u) * LIMB_BITS) + (LIMB_BITS - limb_leading_zeros(larger[larger_used - 1u]));
        int64_t larger_head = (int64_t)limbs_window(larger, larger_used, top - LIMB_BITS);
        int64_t smaller_head = (int64_t)limbs_window(smaller, smaller_used, top - LIMB_BITS);
        int64_t first_u = 1;
        int64_t second_u = 0;
        int64_t first_v = 0;
        int64_t second_v = 1;
        while (((smaller_head + first_v) != 0) && ((smaller_head + second_v) != 0))
        {
            const int64_t quotient_low = (larger_head + first_u) / (smaller_head + first_v);
            if (quotient_low != ((larger_head + second_u) / (smaller_head + second_v)))
            {
                break;
            }
            const int64_t next_first = first_u - (quotient_low * first_v);
            first_u = first_v;
            first_v = next_first;
            const int64_t next_second = second_u - (quotient_low * second_v);
            second_u = second_v;
            second_v = next_second;
            const int64_t next_head = larger_head - (quotient_low * smaller_head);
            larger_head = smaller_head;
            smaller_head = next_head;
        }
        const unsigned int into = (held == 0u) ? 2u : 0u;
        if (second_u == 0)
        {
            // no word step was certain: one long division, u, v -> v, u mod v
            magnitude_divide(larger, smaller, quotient, buffer[into + 1u], divide_work);
            memcpy(buffer[into], smaller, width * sizeof(uint32_t));
            reach[into] = width;
            reach[into + 1u] = width;
        }
        else
        {
            const size_t count = larger_used;
            limbs_combine(buffer[into], larger, first_u, smaller, second_u, count, other);
            limbs_combine(buffer[into + 1u], larger, first_v, smaller, second_v, count, other);
            for (unsigned int side = 0u; side < 2u; side++)
            {
                if (reach[into + side] > (count + 1u))
                {
                    memset(&buffer[into + side][count + 1u], 0, (reach[into + side] - count - 1u) * sizeof(uint32_t));
                }
                reach[into + side] = count + 1u;
            }
        }
        held = into;
        larger_used = limbs_used(buffer[held], width);
        smaller_used = limbs_used(buffer[held + 1u], width);
    }
    // two words or fewer remain in v: one long division, then Euclid in words
    uint64_t larger_word = 0u;
    uint64_t smaller_word = ((uint64_t)buffer[held + 1u][1] << LIMB_BITS) | (uint64_t)buffer[held + 1u][0];
    if (smaller_word != 0u)
    {
        uint32_t *const rest = buffer[(held == 0u) ? 2u : 0u];
        memset(rest, 0, width * sizeof(uint32_t));
        magnitude_divide(buffer[held], buffer[held + 1u], quotient, rest, divide_work);
        larger_word = smaller_word;
        smaller_word = ((uint64_t)rest[1] << LIMB_BITS) | (uint64_t)rest[0];
        while (smaller_word != 0u)
        {
            const uint64_t next = larger_word % smaller_word;
            larger_word = smaller_word;
            smaller_word = next;
        }
        anchor_exact_zero(result);
        result->limb[0] = (uint32_t)(larger_word & LIMB_MASK);
        if (EXACT_LIMBS > 1u)
        {
            result->limb[1] = (uint32_t)(larger_word >> LIMB_BITS);
        }
    }
    else
    {
        memcpy(result->limb, buffer[held], EXACT_LIMBS * sizeof(uint32_t));
    }
    settle_sign(result, 1);
    EXACT_ROOM_RELEASE(work);
    return ANCHOR_EXACT_OK;
}

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
 *          they discard on refusal.
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
 *          they discard on refusal.
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
 *          discard on refusal.
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
    // Scaled on a copy. A refusal leaves the caller's value as it was.
    EXACT_ROOM(scaled, EXACT_LIMBS);
    if (!EXACT_ROOM_HELD(scaled))
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
    EXACT_ROOM_RELEASE(scaled);
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
 * @param[in,out] used  A count of limbs at or above which every limb of `value` is zero [BORROWS].
 * @param[in]     text  Decimal text [BORROWS].
 * @param[in]     from  First digit.
 * @param[in]     to    One past the last digit.
 * @return              1 where the magnitude ran off the top limb, 0 otherwise.
 * @note Takes nine digits a step. The magnitude is multiplied by 10^9 and the nine digits are added
 *       as one limb. A text overruns the width in nine digit steps exactly where it overruns one
 *       digit at a time, because every partial value is at most the finished one.
 * @warning On a return of 1 `value` holds a wrapped magnitude. Callers run this on a copy they
 *          discard on refusal.
 */
static int magnitude_accumulate_digits(uint32_t *value, size_t *used, const char *text,
                                       size_t from, size_t to)
{
    size_t at = from;
    while (at < to)
    {
        const size_t remaining = to - at;
        const size_t step = (remaining > (size_t)LIMB_DECIMAL_DIGITS)
                            ? (size_t)LIMB_DECIMAL_DIGITS : remaining;
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
 *        the caller discards on a refusal.
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
 * @warning On a refusal `value` and `uncertainty` hold partial limbs. Both entries pass integers of
 *          their own and copy out only on ANCHOR_EXACT_OK. A refusal leaves a caller's untouched.
 *          An earlier form read into two limb arrays of its own and then copied, which put a third
 *          and fourth width-sized array on the stack beside the entry's two.
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

    anchor_exact_zero(value);
    size_t value_used = 0u;
    if ((magnitude_accumulate_digits(value->limb, &value_used, text, layout.whole_from,
                                     layout.whole_to) != 0)
        || (magnitude_accumulate_digits(value->limb, &value_used, text, layout.fraction_from,
                                        trimmed_to) != 0))
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
        if (magnitude_accumulate_digits(uncertainty->limb, &spread_used, text,
                                        layout.uncertainty_from, layout.uncertainty_to) != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
        // printed is at most digits, checked above. The difference fits the uint32_t.
        if (magnitude_scale_by_ten(uncertainty->limb, &spread_used, digits - (uint32_t)printed)
            != 0)
        {
            return ANCHOR_EXACT_WILL_NOT_FIT;
        }
    }

    settle_sign(value, layout.sign);
    settle_sign(uncertainty, 1);
    *carried = layout.carried;
    return ANCHOR_EXACT_OK;
}

AnchorExactStatus anchor_exact_from_decimal(const char *text, size_t length, uint32_t digits,
                                            AnchorExactInteger *value)
{
    // Read into a local value. A refusal leaves the caller's value as it was. This entry reads the
    // uncertainty and drops it, as its declaration documents.
    EXACT_VALUE(read);
    EXACT_VALUE(spread);
    AnchorExactStatus status = ANCHOR_EXACT_WILL_NOT_FIT;
    if (EXACT_ROOM_HELD(read) && EXACT_ROOM_HELD(spread))
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
                                             AnchorExactInteger *value,
                                             AnchorExactInteger *uncertainty, int *carried)
{
    EXACT_VALUE(read);
    EXACT_VALUE(spread);
    AnchorExactStatus status = ANCHOR_EXACT_WILL_NOT_FIT;
    if (EXACT_ROOM_HELD(read) && EXACT_ROOM_HELD(spread))
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
    EXACT_VALUE(moved);
    if (!EXACT_ROOM_HELD(moved))
    {
        return 0u;
    }
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

        if (anchor_exact_add(&positions[at], lag, moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t found = count;
        for (size_t other = 0u; other < count; other++)
        {
            if (equal(&positions[other], moved) != 0)
            {
                found = other;
            }
        }
        if ((found < count) && (values[found] == values[at]))
        {
            agreed++;
        }
    }
    EXACT_VALUE_RELEASE(moved);
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
        // No table. The scan answers instead. Slower and correct beats absent.
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
        // An empty slot takes the entry. A slot already holding this position takes it too. The
        // table ends up holding the last entry for every position.
        table[slot] = at;
    }

    EXACT_VALUE(moved);
    if (!EXACT_ROOM_HELD(moved))
    {
        free(table);
        return agreement_without_table(equal, positions, values, count, lag);
    }
    size_t agreed = 0u;
    for (size_t held = 0u; held < slots; held++)
    {
        const size_t at = table[held];
        if (at == count)
        {
            continue;
        }
        if (anchor_exact_add(&positions[at], lag, moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t slot = (size_t)(anchor_exact_hash(moved) & (uint64_t)mask);
        while (table[slot] != count)
        {
            if (equal(&positions[table[slot]], moved) != 0)
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

    EXACT_VALUE_RELEASE(moved);
    free(table);
    return agreed;
}
