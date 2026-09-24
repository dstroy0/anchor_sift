// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "decimal_double.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#define DECIMAL_DOUBLE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_DECIMAL_DOUBLE, (unsigned int)__LINE__, \
                       (const void *)(evacaddr_), (error_))

#define DECIMAL_DOUBLE_LIMB_BITS 32ull

#define DECIMAL_DOUBLE_DIGIT_BITS 4ull

#define DECIMAL_DOUBLE_FIVE_BITS 3ull

#define DECIMAL_DOUBLE_SLACK_LIMBS 3ull

_Static_assert(sizeof(uint32_t) * 8u == DECIMAL_DOUBLE_LIMB_BITS, "a work limb is the 32 bits an exact limb holds");
_Static_assert(10ull <= (1ull << DECIMAL_DOUBLE_DIGIT_BITS), "a decimal digit multiplies a value by at most 2^4");
_Static_assert(5ull < (1ull << DECIMAL_DOUBLE_FIVE_BITS), "a five multiplies a value by less than 2^3");

typedef struct
{
    uint32_t *limb;
    size_t room;
    size_t used;
} DecimalDoubleWork;

typedef struct
{
    uint32_t factor;
    unsigned long long power;
} DecimalDoubleFive;

static inline DecimalDoubleFive decimal_double_five_widest(void)
{
    DecimalDoubleFive five = {.factor = 1u, .power = 0ull};
    while (five.factor <= (UINT32_MAX / 5u))
    {
        five.factor *= 5u;
        five.power += 1ull;
    }
    return five;
}

static inline uint32_t decimal_double_five_power(unsigned long long power)
{
    uint32_t factor = 1u;
    for (unsigned long long step = 0ull; step < power; step += 1ull)
    {
        factor *= 5u;
    }
    return factor;
}

static inline void decimal_double_trim(DecimalDoubleWork *work)
{
    while ((work->used > 0u) && (work->limb[work->used - 1u] == 0u))
    {
        work->used -= 1u;
    }
}

static inline int decimal_double_multiply(DecimalDoubleWork *work, uint32_t factor, uint32_t addend)
{
    uint64_t carry = addend;
    for (size_t index = 0u; index < work->used; index += 1u)
    {
        // the limb widens to 64 bits; a 32 by 32 product plus a 32-bit carry stays below 2^64
        const uint64_t product = ((uint64_t)work->limb[index] * factor) + carry;
        // the low 32 bits of the product are this limb, and the high 32 carry upward
        work->limb[index] = (uint32_t)product;
        carry = product >> DECIMAL_DOUBLE_LIMB_BITS;
    }
    if (carry == 0u)
    {
        return 1;
    }
    if (work->used == work->room)
    {
        return 0;
    }
    // the carry is below 2^32 since the product is below 2^64; it narrows to one limb exactly
    work->limb[work->used] = (uint32_t)carry;
    work->used += 1u;
    return 1;
}

static inline uint32_t decimal_double_remainder(const DecimalDoubleWork *work, uint32_t divisor)
{
    uint64_t remainder = 0u;
    for (size_t index = work->used; index > 0u; index -= 1u)
    {
        remainder = ((remainder << DECIMAL_DOUBLE_LIMB_BITS) | work->limb[index - 1u]) % divisor;
    }
    // the remainder is below the 32-bit divisor; it narrows exactly
    return (uint32_t)remainder;
}

static inline void decimal_double_divide(DecimalDoubleWork *work, uint32_t divisor)
{
    uint64_t remainder = 0u;
    for (size_t index = work->used; index > 0u; index -= 1u)
    {
        const uint64_t dividend = (remainder << DECIMAL_DOUBLE_LIMB_BITS) | work->limb[index - 1u];
        // the remainder is below the divisor; the quotient is below 2^32 and narrows to one limb exactly
        work->limb[index - 1u] = (uint32_t)(dividend / divisor);
        remainder = dividend % divisor;
    }
    decimal_double_trim(work);
}

static inline unsigned long long decimal_double_bits(const DecimalDoubleWork *work)
{
    if (work->used == 0u)
    {
        return 0ull;
    }
    uint32_t top = work->limb[work->used - 1u];
    // the used limb count widens to the unsigned long long the bit count is kept in
    unsigned long long bits = (unsigned long long)(work->used - 1u) * DECIMAL_DOUBLE_LIMB_BITS;
    while (top != 0u)
    {
        bits += 1ull;
        top >>= 1u;
    }
    return bits;
}

static inline unsigned long long decimal_double_trailing_zeros(const DecimalDoubleWork *work)
{
    size_t index = 0u;
    while (work->limb[index] == 0u)
    {
        index += 1u;
    }
    uint32_t low = work->limb[index];
    // the limb index widens to the unsigned long long the bit count is kept in
    unsigned long long zeros = (unsigned long long)index * DECIMAL_DOUBLE_LIMB_BITS;
    while ((low & 1u) == 0u)
    {
        zeros += 1ull;
        low >>= 1u;
    }
    return zeros;
}

static inline void decimal_double_shift_right(DecimalDoubleWork *work, unsigned long long bits)
{
    // the shift is at most the bits the work holds, whose limb count is a size_t; the quotient narrows exactly
    const size_t limbs = (size_t)(bits / DECIMAL_DOUBLE_LIMB_BITS);
    // the remainder is below 32; it narrows to unsigned int exactly
    const unsigned int part = (unsigned int)(bits % DECIMAL_DOUBLE_LIMB_BITS);
    if (limbs >= work->used)
    {
        work->used = 0u;
        return;
    }
    for (size_t index = 0u; (index + limbs) < work->used; index += 1u)
    {
        uint64_t window = work->limb[index + limbs];
        if ((index + limbs + 1u) < work->used)
        {
            // the next limb widens to 64 bits so it can sit above this one in the window
            window |= (uint64_t)work->limb[index + limbs + 1u] << DECIMAL_DOUBLE_LIMB_BITS;
        }
        // the window shifted by less than 32 keeps this limb in its low 32 bits
        work->limb[index] = (uint32_t)(window >> part);
    }
    work->used -= limbs;
    decimal_double_trim(work);
}

static inline int decimal_double_shift_left(DecimalDoubleWork *work, unsigned long long bits)
{
    // the shift was bounded against the work room, a size_t, before the work was allocated; it narrows exactly
    const size_t limbs = (size_t)(bits / DECIMAL_DOUBLE_LIMB_BITS);
    // the remainder is below 32; it narrows to unsigned int exactly
    const unsigned int part = (unsigned int)(bits % DECIMAL_DOUBLE_LIMB_BITS);
    if ((work->used + limbs + 1u) > work->room)
    {
        return 0;
    }
    for (size_t source = work->used + 1u; source > 0u; source -= 1u)
    {
        const size_t high = source - 1u;
        // the high limb widens to 64 bits so the limb below it can sit under it in the window
        uint64_t window = (high < work->used) ? ((uint64_t)work->limb[high] << DECIMAL_DOUBLE_LIMB_BITS) : 0u;
        if (high > 0u)
        {
            window |= work->limb[high - 1u];
        }
        // the window shifted right by 32 less the part leaves this limb in its low 32 bits
        work->limb[high + limbs] = (uint32_t)(window >> (DECIMAL_DOUBLE_LIMB_BITS - part));
    }
    for (size_t index = 0u; index < limbs; index += 1u)
    {
        work->limb[index] = 0u;
    }
    work->used += limbs + 1u;
    decimal_double_trim(work);
    return 1;
}

static inline int decimal_double_multiply_five(DecimalDoubleWork *work, const DecimalDoubleFive *five,
                                               unsigned long long count)
{
    unsigned long long left = count;
    int held = 1;
    while (held && (left >= five->power))
    {
        held = decimal_double_multiply(work, five->factor, 0u);
        left -= five->power;
    }
    return held && decimal_double_multiply(work, decimal_double_five_power(left), 0u);
}

static inline void decimal_double_divide_five(DecimalDoubleWork *work, const DecimalDoubleFive *five,
                                              unsigned long long count)
{
    unsigned long long left = count;
    while (left >= five->power)
    {
        decimal_double_divide(work, five->factor);
        left -= five->power;
    }
    decimal_double_divide(work, decimal_double_five_power(left));
}

static inline unsigned long long decimal_double_strip_five(DecimalDoubleWork *work, const DecimalDoubleFive *five,
                                                           unsigned long long most)
{
    unsigned long long stripped = 0ull;
    while (((most - stripped) >= five->power) && (decimal_double_remainder(work, five->factor) == 0u))
    {
        decimal_double_divide(work, five->factor);
        stripped += five->power;
    }
    while ((stripped < most) && (decimal_double_remainder(work, 5u) == 0u))
    {
        decimal_double_divide(work, 5u);
        stripped += 1ull;
    }
    return stripped;
}

static int decimal_double_expand_work(const DecimalDoubleRequest *request, DecimalDoubleWork *work)
{
    EngineError *const error = request->error;
    for (size_t index = 0u; index < request->digit_count; index += 1u)
    {
        const char digit = request->digits[index];
        if (!DECIMAL_DOUBLE_HELD((digit >= '0') && (digit <= '9'), &request->digits[index], error,
                                 ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        // the digit is 0 to 9 after the test above; it converts to uint32_t exactly
        if (!DECIMAL_DOUBLE_HELD(decimal_double_multiply(work, 10u, (uint32_t)(digit - '0')), work->limb, error,
                                 ENGINE_ERROR_LOGIC))
        {
            return 0;
        }
    }

    DecimalDoubleHeld held = {.e2 = 0, .fits = 1, .terminates = 1, .needed_bits = 0ull};
    if (work->used != 0u)
    {
        const DecimalDoubleFive five = decimal_double_five_widest();
        if (request->ex >= 0)
        {
            // ex is non-negative here; it widens to unsigned long long exactly
            if (!DECIMAL_DOUBLE_HELD(decimal_double_multiply_five(work, &five, (unsigned long long)request->ex),
                                     work->limb, error, ENGINE_ERROR_LOGIC))
            {
                return 0;
            }
            held.e2 = request->ex;
        }
        else
        {
            // ex is negative here, and its negation in long long holds INT_MIN's; it widens exactly
            const unsigned long long places = (unsigned long long)(-(long long)request->ex);
            const unsigned long long left = places - decimal_double_strip_five(work, &five, places);
            held.e2 = request->ex;
            if (left != 0ull)
            {
                const unsigned long long shift = ANCHOR_EXACT_BITS + 1ull + (DECIMAL_DOUBLE_FIVE_BITS * left);
                if (!DECIMAL_DOUBLE_HELD(decimal_double_shift_left(work, shift), work->limb, error,
                                         ENGINE_ERROR_LOGIC))
                {
                    return 0;
                }
                decimal_double_divide_five(work, &five, left);
                // the shift is bounded by the work room checked before allocation; it converts to long long exactly
                held.e2 -= (long long)shift;
                held.terminates = 0;
                held.fits = 0;
            }
        }
        if (held.terminates)
        {
            const unsigned long long zeros = decimal_double_trailing_zeros(work);
            decimal_double_shift_right(work, zeros);
            // the zeros are counted within the work; they convert to long long exactly
            held.e2 += (long long)zeros;
            held.needed_bits = decimal_double_bits(work);
        }
        const unsigned long long bits = decimal_double_bits(work);
        if (bits > ANCHOR_EXACT_BITS)
        {
            const unsigned long long excess = bits - ANCHOR_EXACT_BITS;
            decimal_double_shift_right(work, excess);
            // the excess is counted within the work; it converts to long long exactly
            held.e2 += (long long)excess;
            held.fits = 0;
        }
    }

    AnchorExactInteger *const candidate = request->candidate;
    anchor_exact_zero(candidate);
    for (size_t index = 0u; index < work->used; index += 1u)
    {
        candidate->limb[index] = work->limb[index];
    }
    candidate->sign = (work->used == 0u) ? 0 : (request->neg ? -1 : 1);
    *request->held = held;
    return 1;
}

int decimal_double_expand(const DecimalDoubleRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    if (!DECIMAL_DOUBLE_HELD((request->digits != NULL) && (request->digit_count > 0u) && (request->candidate != NULL)
                                 && (request->held != NULL),
                             request, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // the exponent's magnitude in long long holds INT_MIN's; it widens to unsigned long long exactly
    const unsigned long long places = (unsigned long long)((request->ex < 0) ? -(long long)request->ex : request->ex);
    const unsigned long long tail_bits = (DECIMAL_DOUBLE_FIVE_BITS * places) + ANCHOR_EXACT_BITS + 1ull
                                       + (DECIMAL_DOUBLE_SLACK_LIMBS * DECIMAL_DOUBLE_LIMB_BITS);
    if (!DECIMAL_DOUBLE_HELD(request->digit_count <= ((ULLONG_MAX - tail_bits) / DECIMAL_DOUBLE_DIGIT_BITS),
                             request->digits, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // the digit count widens to the unsigned long long the bound is kept in
    const unsigned long long room_bits = (DECIMAL_DOUBLE_DIGIT_BITS * (unsigned long long)request->digit_count)
                                       + tail_bits;
    const unsigned long long room_limbs = room_bits / DECIMAL_DOUBLE_LIMB_BITS;
    if (!DECIMAL_DOUBLE_HELD(room_limbs <= (SIZE_MAX / sizeof(uint32_t)), request, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // the room was held below SIZE_MAX over the limb size above; it narrows to size_t exactly
    DecimalDoubleWork work = {.limb = (uint32_t *)malloc((size_t)room_limbs * sizeof(uint32_t)),
                              .room = (size_t)room_limbs,
                              .used = 0u};
    if (!DECIMAL_DOUBLE_HELD(work.limb != NULL, &work, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    const int expanded = decimal_double_expand_work(request, &work);
    free(work.limb);
    return expanded;
}
