
// exact_integer_divide.c: long and Newton division
#include "exact_integer_internal.h"

unsigned int limb_leading_zeros(uint32_t word)
{
    unsigned int zeros = 0u;
    while ((word & 0x80000000u) == 0u)
    {
        zeros++;
        word <<= 1u;
    }
    return zeros;
}

size_t limbs_used(const uint32_t *value, size_t count)
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
            // current is below divisor . 2^32. The quotient limb fits 32 bits
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
        const uint64_t head =
            ((uint64_t)running[at + bottom_used] << LIMB_BITS) | (uint64_t)running[at + bottom_used - 1u];
        uint64_t estimate = head / leading;
        uint64_t left_over = head % leading;
        while ((estimate >= LIMB_BASE) ||
               ((estimate * second) > ((left_over << LIMB_BITS) | (uint64_t)running[at + bottom_used - 2u])))
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

// the precision below which the reciprocal is taken by long division outright
#define NEWTON_BASE_LIMBS 32u

// x = floor(beta^t / d), beta = 2^32, for d of used limbs with its top limb nonzero and t >= used; x takes
// t - used + 2 limbs. Each level halves the quotient's precision p: the top p/2 + 2 limbs of d give a reciprocal good
// to half the limbs, shifted back up; one Newton step x + x (beta^t - d x) / beta^t squares its relative error; and
// multiplying back fixes the last units exactly. Every product is on the ladder. The reciprocal costs a few
// products. 0 when workspace cannot be held
static int limbs_reciprocal(uint32_t *x, const uint32_t *d, size_t used, size_t t)
{
    const size_t precision = t - used;
    const size_t count = precision + 2u;
    memset(x, 0, count * sizeof(uint32_t));
    if ((precision <= (size_t)NEWTON_BASE_LIMBS) || (used <= (size_t)NEWTON_BASE_LIMBS))
    {
        uint32_t *const workspace = (uint32_t *)calloc((t + 1u) + (t + 2u) + used + (t + used + 2u), sizeof(uint32_t));
        if (workspace == NULL)
        {
            return 0;
        }
        uint32_t *const power = workspace;
        uint32_t *const quotient = &power[t + 1u];
        uint32_t *const rest = &quotient[t + 2u];
        uint32_t *const work = &rest[used];
        power[t] = 1u;
        limbs_divide(power, t + 1u, d, used, quotient, rest, work);
        memcpy(x, quotient, count * sizeof(uint32_t));
        free(workspace);
        return 1;
    }
    const size_t half = precision / 2u;
    const size_t inner_precision = precision - half;
    const size_t keep = (used < (inner_precision + 2u)) ? used : (inner_precision + 2u);
    const size_t dropped = used - keep;
    // products run to t + 4 limbs; the Newton step's error term to t + 2
    const size_t span = t + precision + 8u;
    uint32_t *const workspace = (uint32_t *)calloc((5u * span) + count, sizeof(uint32_t));
    if (workspace == NULL)
    {
        return 0;
    }
    uint32_t *const guess = workspace;
    uint32_t *const product = &guess[span];
    uint32_t *const error = &product[span];
    uint32_t *const step = &error[span];
    uint32_t *const correction = &step[span];
    uint32_t *const inner = &correction[span];
    if (limbs_reciprocal(inner, &d[dropped], keep, keep + inner_precision) == 0)
    {
        free(workspace);
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
    free(workspace);
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
    uint32_t *const workspace = (uint32_t *)calloc((precision + 2u) + (2u * span), sizeof(uint32_t));
    if (workspace == NULL)
    {
        return 0;
    }
    uint32_t *const reciprocal = workspace;
    uint32_t *const product = &reciprocal[precision + 2u];
    uint32_t *const estimate = &product[span];
    if (limbs_reciprocal(reciprocal, bottom, bottom_used, top_used) == 0)
    {
        free(workspace);
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
    free(workspace);
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
    const int by_newton = (newton_only != 0) || ((bottom_used >= (size_t)ANCHOR_EXACT_NEWTON_LIMBS) &&
                                                 (quotient_limbs >= (size_t)ANCHOR_EXACT_NEWTON_LIMBS));
    if ((quotient_limbs != 0u) && (by_newton != 0))
    {
        // the quotient's limbs past the width are zero, the quotient being no larger than the top
        uint32_t *const full_quotient = (uint32_t *)calloc(quotient_limbs + 1u, sizeof(uint32_t));
        if ((full_quotient != NULL) &&
            (limbs_divide_newton(top, top_used, bottom, bottom_used, full_quotient, rest) != 0))
        {
            memcpy(quotient, full_quotient,
                   ((quotient_limbs < EXACT_LIMBS) ? quotient_limbs : EXACT_LIMBS) * sizeof(uint32_t));
            free(full_quotient);
            return;
        }
        free(full_quotient);
    }
    if (quotient_limbs == 0u)
    {
        memcpy(rest, top, top_used * sizeof(uint32_t));
        return;
    }
    limbs_divide(top, top_used, bottom, bottom_used, quotient, rest, work);
}

void magnitude_divide(const uint32_t *top, const uint32_t *bottom, uint32_t *quotient, uint32_t *rest, uint32_t *work)
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
    EXACT_SCRATCH(work, (4u * EXACT_LIMBS) + 1u);
    if (!EXACT_SCRATCH_VALID(work))
    {
        return ANCHOR_EXACT_WILL_NOT_FIT;
    }
    uint32_t *const full_quotient = work;
    uint32_t *const rest = &work[EXACT_LIMBS];
    magnitude_divide_by(numerator->limb, divisor->limb, full_quotient, rest, &work[2u * EXACT_LIMBS], newton_only);
    // the signs are read before an output that shares an input is written
    const int32_t quotient_sign = numerator->sign * divisor->sign;
    const int32_t rest_sign = numerator->sign;
    memcpy(quotient->limb, full_quotient, EXACT_LIMBS * sizeof(uint32_t));
    settle_sign(quotient, quotient_sign);
    memcpy(remainder->limb, rest, EXACT_LIMBS * sizeof(uint32_t));
    settle_sign(remainder, rest_sign);
    EXACT_SCRATCH_RELEASE(work);
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
