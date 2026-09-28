
// exact_integer_gcd.c: exact division by an odd divisor and the gcd
#include "exact_integer_internal.h"

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
    const size_t limb_shift = bits / LIMB_BITS;
    const unsigned int part = (unsigned int)(bits % LIMB_BITS);
    for (size_t at = 0u; at < (size_t)ANCHOR_EXACT_LIMBS; at++)
    {
        const size_t from = at + limb_shift;
        const uint32_t low = (from < (size_t)ANCHOR_EXACT_LIMBS) ? value[from] : 0u;
        const uint32_t high = ((from + 1u) < (size_t)ANCHOR_EXACT_LIMBS) ? value[from + 1u] : 0u;
        value[at] = (part == 0u) ? low : ((low >> part) | (high << (LIMB_BITS - part)));
    }
}

// result[0, left_count + right_count) = left . right on the ladder: the transform once both reach its rung, Karatsuba
// or long multiplication below it, each stepping down when its workspace cannot be held
void limbs_ladder_product(uint32_t *result, const uint32_t *left, size_t left_count, const uint32_t *right,
                          size_t right_count)
{
    const size_t shorter = (left_count < right_count) ? left_count : right_count;
    if ((shorter >= (size_t)ANCHOR_EXACT_TRANSFORM_LIMBS) &&
        (transform_product(result, left, left_count, right, right_count) != 0))
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
// right. Each step works only to the doubled precision; 2 - t is the two's complement negation of t plus two;
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
        const size_t range = (doubled + LIMB_BITS - 1u) / LIMB_BITS;
        magnitude_low_product(odd, guess, range, step, product);
        uint64_t carry = 2u;
        for (size_t at = 0u; at < range; at++)
        {
            // ~t + 1 + 2 in the first limb, the carry thereafter
            const uint64_t total = (uint64_t)(uint32_t)(~step[at]) + carry + ((at == 0u) ? 1u : 0u);
            step[at] = (uint32_t)(total & LIMB_MASK);
            carry = total >> LIMB_BITS;
        }
        magnitude_low_product(guess, step, range, guess, product);
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
    EXACT_SCRATCH(work, 10u * EXACT_LIMBS);
    if (!EXACT_SCRATCH_VALID(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    uint32_t *const odd = work;
    uint32_t *const top = &work[EXACT_LIMBS];
    uint32_t *const low_product = &work[2u * EXACT_LIMBS];
    uint32_t *const back = &work[3u * EXACT_LIMBS];
    uint32_t *const inverse_work = &work[5u * EXACT_LIMBS];
    uint32_t *const inverse = &work[9u * EXACT_LIMBS];
    const size_t twos = magnitude_trailing_zeros(divisor->limb);
    memcpy(odd, divisor->limb, EXACT_LIMBS * sizeof(uint32_t));
    memcpy(top, numerator->limb, EXACT_LIMBS * sizeof(uint32_t));
    magnitude_shift_down(odd, twos);
    magnitude_shift_down(top, twos);
    const size_t limbs = magnitude_used(top);
    memset(low_product, 0, EXACT_LIMBS * sizeof(uint32_t));
    if (limbs != 0u)
    {
        magnitude_odd_inverse(odd, limbs, inverse, inverse_work);
        magnitude_low_product(top, inverse, limbs, low_product, inverse_work);
    }
    // multiplied back, the quotient must give the numerator's magnitude
    const size_t low_product_used = magnitude_used(low_product);
    const size_t divisor_used = magnitude_used(divisor->limb);
    AnchorExactStatus status = ANCHOR_EXACT_NOT_EXACT;
    if ((low_product_used != 0u) && ((low_product_used + divisor_used) <= (2u * EXACT_LIMBS)))
    {
        limbs_ladder_product(back, low_product, low_product_used, divisor->limb, divisor_used);
        memset(&back[low_product_used + divisor_used], 0,
               ((2u * EXACT_LIMBS) - low_product_used - divisor_used) * sizeof(uint32_t));
        if ((magnitude_compare(back, numerator->limb) == 0) && (magnitude_is_zero(&back[EXACT_LIMBS]) != 0))
        {
            const int32_t sign = numerator->sign * divisor->sign;
            memcpy(quotient->limb, low_product, EXACT_LIMBS * sizeof(uint32_t));
            settle_sign(quotient, sign);
            status = ANCHOR_EXACT_OK;
        }
    }
    EXACT_SCRATCH_RELEASE(work);
    return status;
}

// the 32 bits of value starting at bit from, the bits past the top reading as zero
static uint64_t limbs_window(const uint32_t *value, size_t used, size_t from)
{
    const size_t limb_shift = from / LIMB_BITS;
    const unsigned int part = (unsigned int)(from % LIMB_BITS);
    const uint64_t low = (limb_shift < used) ? (uint64_t)value[limb_shift] : 0u;
    const uint64_t high = ((limb_shift + 1u) < used) ? (uint64_t)value[limb_shift + 1u] : 0u;
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
    EXACT_SCRATCH(work, (9u * EXACT_LIMBS) + 8u);
    if (!EXACT_SCRATCH_VALID(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    const size_t width = EXACT_LIMBS + 1u;
    uint32_t *buffer[4] = {work, &work[width], &work[2u * width], &work[3u * width]};
    size_t range[4] = {width, width, width, width};
    uint32_t *const other = &work[4u * width];
    uint32_t *const quotient = &work[5u * width];
    uint32_t *const divide_work = &work[(5u * width) + EXACT_LIMBS];
    memset(work, 0, 4u * width * sizeof(uint32_t));
    const int left_larger = (magnitude_compare(left->limb, right->limb) >= 0);
    memcpy(buffer[0], left_larger ? left->limb : right->limb, EXACT_LIMBS * sizeof(uint32_t));
    memcpy(buffer[1], left_larger ? right->limb : left->limb, EXACT_LIMBS * sizeof(uint32_t));
    // u in buffer[held], v in buffer[held + 1], the next pair in the other two
    unsigned int current = 0u;
    size_t larger_used = limbs_used(buffer[0], width);
    size_t smaller_used = limbs_used(buffer[1], width);
    while (smaller_used > 2u)
    {
        uint32_t *const larger = buffer[current];
        uint32_t *const smaller = buffer[current + 1u];
        const size_t top =
            ((larger_used - 1u) * LIMB_BITS) + (LIMB_BITS - limb_leading_zeros(larger[larger_used - 1u]));
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
        const unsigned int into = (current == 0u) ? 2u : 0u;
        if (second_u == 0)
        {
            // no word step was certain: one long division, u, v -> v, u mod v
            magnitude_divide(larger, smaller, quotient, buffer[into + 1u], divide_work);
            memcpy(buffer[into], smaller, width * sizeof(uint32_t));
            range[into] = width;
            range[into + 1u] = width;
        }
        else
        {
            const size_t count = larger_used;
            limbs_combine(buffer[into], larger, first_u, smaller, second_u, count, other);
            limbs_combine(buffer[into + 1u], larger, first_v, smaller, second_v, count, other);
            for (unsigned int side = 0u; side < 2u; side++)
            {
                if (range[into + side] > (count + 1u))
                {
                    memset(&buffer[into + side][count + 1u], 0, (range[into + side] - count - 1u) * sizeof(uint32_t));
                }
                range[into + side] = count + 1u;
            }
        }
        current = into;
        larger_used = limbs_used(buffer[current], width);
        smaller_used = limbs_used(buffer[current + 1u], width);
    }
    // two words or fewer remain in v: one long division, then Euclid in words
    uint64_t larger_word = 0u;
    uint64_t smaller_word = ((uint64_t)buffer[current + 1u][1] << LIMB_BITS) | (uint64_t)buffer[current + 1u][0];
    if (smaller_word != 0u)
    {
        uint32_t *const rest = buffer[(current == 0u) ? 2u : 0u];
        memset(rest, 0, width * sizeof(uint32_t));
        magnitude_divide(buffer[current], buffer[current + 1u], quotient, rest, divide_work);
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
        memcpy(result->limb, buffer[current], EXACT_LIMBS * sizeof(uint32_t));
    }
    settle_sign(result, 1);
    EXACT_SCRATCH_RELEASE(work);
    return ANCHOR_EXACT_OK;
}
