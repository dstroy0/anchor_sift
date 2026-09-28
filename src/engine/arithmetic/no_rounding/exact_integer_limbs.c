
// exact_integer_limbs.c: limb arithmetic, products, Karatsuba and the Fermat ring
#include "exact_integer_internal.h"

uint32_t limbs_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
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

uint32_t limbs_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
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
uint32_t limbs_accumulate(uint32_t *value, size_t count, const uint32_t *added, size_t added_count)
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
uint32_t limbs_deduct(uint32_t *value, size_t count, const uint32_t *taken, size_t taken_count)
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

void limbs_long_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
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

// Karatsuba on two equal lengths: with a = a1 B + a0 and b = b1 B + b0, the three products a0 b0, a1 b1 and
// (a0 + a1)(b0 + b1) give the middle term as the third less the first two
static int limbs_karatsuba(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t count)
{
    const size_t low = count / 2u;
    const size_t high = count - low;
    if ((limbs_product(result, left, low, right, low) == 0) ||
        (limbs_product(&result[2u * low], &left[low], high, &right[low], high) == 0))
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
    const size_t remaining = (2u * count) - low;
    const size_t middle_count = (2u * (high + 1u) < remaining) ? (2u * (high + 1u)) : remaining;
    (void)limbs_accumulate(&result[low], remaining, middle, middle_count);
    free(work);
    return 1;
}

// result[0, left_count + right_count) = left . right by the rung that fits: long multiplication below the Karatsuba
// width, Karatsuba on equal lengths, and slices of the longer operand otherwise; 0 when workspace cannot be held
int limbs_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right, size_t right_count)
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

unsigned int bits_ceiling_log(size_t value)
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

void fermat_add(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    (void)limbs_add(result, left, right, limbs + 1u);
    fermat_settle(result, limbs);
}

// a wrapped difference comes back by adding 2^n + 1, the wrap of the words canceling
static void fermat_mend(uint32_t *value, size_t limbs)
{
    uint32_t one = 1u;
    (void)limbs_accumulate(value, limbs + 1u, &one, 1u);
    value[limbs] += 1u;
}

void fermat_subtract(uint32_t *result, const uint32_t *left, const uint32_t *right, size_t limbs)
{
    if (limbs_subtract(result, left, right, limbs + 1u) != 0u)
    {
        fermat_mend(result, limbs);
    }
}

void fermat_negate(uint32_t *value, size_t limbs)
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
void fermat_shift(uint32_t *result, const uint32_t *value, size_t shift, size_t limbs, uint32_t *scratch)
{
    const size_t bits = limbs * LIMB_BITS;
    shift %= 2u * bits;
    const int negated = (shift >= bits);
    shift = negated ? (shift - bits) : shift;
    const size_t limb_shift = shift / LIMB_BITS;
    const unsigned int part = (unsigned int)(shift % LIMB_BITS);
    memset(scratch, 0, ((2u * limbs) + 2u) * sizeof(uint32_t));
    for (size_t at = 0u; at <= limbs; at++)
    {
        scratch[at + limb_shift] |= value[at] << part;
        if (part != 0u)
        {
            scratch[at + limb_shift + 1u] |= value[at] >> (LIMB_BITS - part);
        }
    }
    // value . 2^shift < 2^(2n). The part above n is below 2^n and its top word is zero
    memcpy(result, scratch, limbs * sizeof(uint32_t));
    result[limbs] = 0u;
    fermat_subtract(result, result, &scratch[limbs], limbs);
    if (negated)
    {
        fermat_negate(result, limbs);
    }
}
