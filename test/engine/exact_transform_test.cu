// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Proves the exact integer's multiplication ladder at the width it is built at: the ladder (long multiplication,
// Karatsuba, the Schonhage-Strassen transform) and the transform alone both equal a long multiplication kept here, on
// keyed and edge-shaped limbs, balanced and unbalanced, across every rung boundary up to half the width; division
// and gcd hold at the same width; and each rung is timed, so the crossovers are measured, not assumed. Every value
// is held from the heap, so the test runs at any width the header accepts.

#include "no_rounding/exact_integer.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#define LADDER_KEY 0x4C4144ull
#define LADDER_TRIALS 3u

static int s_checks = 0;
static int s_failed = 0;

static void check(const char *name, int ok)
{
    s_checks += 1;
    if (ok == 0)
    {
        s_failed += 1;
        printf("  FAIL %s\n", name);
    }
    else
    {
        printf("  ok   %s\n", name);
    }
}

static unsigned long long ladder_mix(unsigned long long value)
{
    value ^= value >> 33u;
    value *= 0xFF51AFD7ED558CCDull;
    value ^= value >> 33u;
    value *= 0xC4CEB9FE1A85EC53ull;
    value ^= value >> 33u;
    return value;
}

static unsigned long long s_counter = 0ull;

static unsigned int ladder_draw(void)
{
    s_counter += 1ull;
    // the low word of the mixed counter
    return (unsigned int)ladder_mix(LADDER_KEY ^ ladder_mix(s_counter));
}

static AnchorExactInteger *ladder_value(void)
{
    AnchorExactInteger *const value = (AnchorExactInteger *)malloc(sizeof(AnchorExactInteger));
    if (value == NULL)
    {
        printf("  no room for a value at this width\n");
        exit(1);
    }
    anchor_exact_zero(value);
    return value;
}

// all ones half the time: every coefficient of the transform at its largest
static void ladder_fill(AnchorExactInteger *value, size_t limbs, int shaped)
{
    anchor_exact_zero(value);
    for (size_t at = 0u; at < limbs; at++)
    {
        value->limb[at] = (shaped != 0) ? 0xFFFFFFFFu : ladder_draw();
    }
    value->limb[limbs - 1u] |= 1u;
    value->sign = ((ladder_draw() & 1u) != 0u) ? -1 : 1;
}

static size_t ladder_used(const AnchorExactInteger *value)
{
    size_t used = (size_t)ANCHOR_EXACT_LIMBS;
    while ((used > 0u) && (value->limb[used - 1u] == 0u))
    {
        used--;
    }
    return used;
}

// the reference: long multiplication, the sign apart
static int ladder_matches(const AnchorExactInteger *left, const AnchorExactInteger *right,
                          const AnchorExactInteger *product)
{
    const size_t left_used = ladder_used(left);
    const size_t right_used = ladder_used(right);
    uint32_t *const wide = (uint32_t *)calloc(left_used + right_used + 1u, sizeof(uint32_t));
    if (wide == NULL)
    {
        return 0;
    }
    for (size_t low = 0u; low < left_used; low++)
    {
        unsigned long long carry = 0ull;
        for (size_t high = 0u; high < right_used; high++)
        {
            const unsigned long long total = ((unsigned long long)left->limb[low] * right->limb[high]) + wide[low + high] + carry;
            // the low word; the high word carries on
            wide[low + high] = (uint32_t)total;
            carry = total >> 32u;
        }
        // the carry is below 2^32
        wide[low + right_used] = (uint32_t)carry;
    }
    int same = (product->sign == ((left->sign == right->sign) ? 1 : -1));
    for (size_t at = 0u; (at < (size_t)ANCHOR_EXACT_LIMBS) && (same != 0); at++)
    {
        const uint32_t expected = (at < (left_used + right_used)) ? wide[at] : 0u;
        same = (product->limb[at] == expected);
    }
    free(wide);
    return same;
}

static double ladder_seconds(AnchorExactStatus (*multiply)(const AnchorExactInteger *, const AnchorExactInteger *,
                                                           AnchorExactInteger *),
                             const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *product)
{
    unsigned int repeats = 1u;
    for (;;)
    {
        const auto start = std::chrono::steady_clock::now();
        for (unsigned int at = 0u; at < repeats; at++)
        {
            (void)multiply(left, right, product);
        }
        const double spent = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        if ((spent > 0.2) || (repeats >= (1u << 20u)))
        {
            return spent / repeats;
        }
        repeats *= 4u;
    }
}

static double ladder_divide_seconds(AnchorExactStatus (*divide)(const AnchorExactInteger *, const AnchorExactInteger *,
                                                                  AnchorExactInteger *, AnchorExactInteger *),
                                    const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                                    AnchorExactInteger *quotient, AnchorExactInteger *remainder)
{
    unsigned int repeats = 1u;
    for (;;)
    {
        const auto start = std::chrono::steady_clock::now();
        for (unsigned int at = 0u; at < repeats; at++)
        {
            (void)divide(numerator, divisor, quotient, remainder);
        }
        const double spent = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        if ((spent > 0.2) || (repeats >= (1u << 20u)))
        {
            return spent / repeats;
        }
        repeats *= 4u;
    }
}

// the long multiplication, for timing, through the same signature
static AnchorExactInteger *s_long_room = NULL;

static AnchorExactStatus ladder_long(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                     AnchorExactInteger *result)
{
    (void)s_long_room;
    const size_t left_used = ladder_used(left);
    const size_t right_used = ladder_used(right);
    memset(result->limb, 0, sizeof(result->limb));
    for (size_t low = 0u; low < left_used; low++)
    {
        unsigned long long carry = 0ull;
        for (size_t high = 0u; high < right_used; high++)
        {
            const unsigned long long total = ((unsigned long long)left->limb[low] * right->limb[high]) + result->limb[low + high] + carry;
            // the low word; the high word carries on
            result->limb[low + high] = (uint32_t)total;
            carry = total >> 32u;
        }
        // the carry is below 2^32
        result->limb[low + right_used] = (uint32_t)carry;
    }
    result->sign = 1;
    return ANCHOR_EXACT_OK;
}

int main(void)
{
    // unbuffered, so a long run shows where it is
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("  exact integer multiplication ladder at %llu bits (%llu limbs; Karatsuba from %u, transform from %u)\n",
           (unsigned long long)ANCHOR_EXACT_BITS, (unsigned long long)ANCHOR_EXACT_LIMBS,
           (unsigned int)ANCHOR_EXACT_KARATSUBA_LIMBS, (unsigned int)ANCHOR_EXACT_TRANSFORM_LIMBS);
    AnchorExactInteger *const left = ladder_value();
    AnchorExactInteger *const right = ladder_value();
    AnchorExactInteger *const product = ladder_value();
    AnchorExactInteger *const quotient = ladder_value();
    AnchorExactInteger *const remainder = ladder_value();
    AnchorExactInteger *const common = ladder_value();

    const size_t half = (size_t)ANCHOR_EXACT_LIMBS / 2u;
    size_t sizes[64];
    unsigned int size_count = 0u;
    const size_t marks[] = {1u, 2u, 3u, 31u, 32u, 33u, 63u, 64u, 65u, 100u, 127u, 128u, 129u, 500u, 1023u, 1024u, 1025u, 3000u};
    for (unsigned int at = 0u; at < (sizeof(marks) / sizeof(marks[0])); at++)
    {
        if (marks[at] <= half)
        {
            sizes[size_count] = marks[at];
            size_count++;
        }
    }
    for (size_t size = 4096u; size <= half; size *= 4u)
    {
        sizes[size_count] = size;
        size_count++;
    }
    if (sizes[size_count - 1u] != half)
    {
        sizes[size_count] = half;
        size_count++;
    }

    unsigned int ladder_held = 0u;
    unsigned int transform_held = 0u;
    unsigned int tried = 0u;
    unsigned int divided = 0u;
    for (unsigned int at = 0u; at < size_count; at++)
    {
        for (unsigned int trial = 0u; trial < LADDER_TRIALS; trial++)
        {
            const size_t left_limbs = sizes[at];
            // balanced, then shorter on the right
            const size_t right_limbs = (trial == 0u) ? left_limbs : (1u + (ladder_draw() % left_limbs));
            ladder_fill(left, left_limbs, (int)(trial == 1u));
            ladder_fill(right, right_limbs, (int)(trial == 1u));
            tried++;
            ladder_held += ((anchor_exact_multiply(left, right, product) == ANCHOR_EXACT_OK)
                            && ladder_matches(left, right, product))
                         ? 1u
                         : 0u;
            transform_held += ((anchor_exact_multiply_transform(left, right, product) == ANCHOR_EXACT_OK)
                               && ladder_matches(left, right, product))
                            ? 1u
                            : 0u;
            // the product divides back to its factors, and the gcd holds the shorter one
            int back = (anchor_exact_divide(product, right, quotient, remainder) == ANCHOR_EXACT_OK)
                    && (remainder->sign == 0) && anchor_exact_equal(quotient, left);
            back = back && (anchor_exact_divide_exact(product, left, quotient) == ANCHOR_EXACT_OK)
                && anchor_exact_equal(quotient, right);
            back = back && (anchor_exact_gcd(product, right, common) == ANCHOR_EXACT_OK)
                && (anchor_exact_divide(common, right, quotient, remainder) == ANCHOR_EXACT_OK) && (remainder->sign == 0);
            divided += back ? 1u : 0u;
        }
    }
    printf("  %u products, operands to %llu limbs\n", tried, (unsigned long long)half);
    check("the ladder equals long multiplication at every size, balanced and not, edge-shaped and keyed",
          ladder_held == tried);
    check("the transform alone equals long multiplication at every size", transform_held == tried);
    check("each product divides back to its factors, exactly and with remainder, and the gcd holds a factor",
          divided == tried);

    // division of values that are not multiples: numerator = quotient . divisor + remainder, 0 <= |remainder| <
    // |divisor|, the definition of the division whatever computes it; Newton's and the dispatched division agree
    AnchorExactInteger *const newton_quotient = ladder_value();
    AnchorExactInteger *const newton_remainder = ladder_value();
    AnchorExactInteger *const rebuilt = ladder_value();
    unsigned int division_held = 0u;
    unsigned int division_tried = 0u;
    for (unsigned int at = 0u; at < size_count; at++)
    {
        for (unsigned int trial = 0u; trial < LADDER_TRIALS; trial++)
        {
            const size_t divisor_limbs = sizes[at];
            // the numerator twice the divisor, a limb more, or the width, whichever is least
            const size_t twice = (2u * divisor_limbs) + (size_t)(trial & 1u);
            const size_t numerator_limbs = (twice < (size_t)ANCHOR_EXACT_LIMBS) ? twice : (size_t)ANCHOR_EXACT_LIMBS;
            ladder_fill(left, numerator_limbs, (int)(trial == 1u));
            ladder_fill(right, divisor_limbs, (int)(trial == 2u));
            division_tried++;
            int held = (anchor_exact_divide(left, right, quotient, remainder) == ANCHOR_EXACT_OK)
                    && (anchor_exact_divide_newton(left, right, newton_quotient, newton_remainder) == ANCHOR_EXACT_OK)
                    && anchor_exact_equal(quotient, newton_quotient) && anchor_exact_equal(remainder, newton_remainder);
            held = held && (anchor_exact_multiply(newton_quotient, right, product) == ANCHOR_EXACT_OK)
                && (anchor_exact_add(product, newton_remainder, rebuilt) == ANCHOR_EXACT_OK) && anchor_exact_equal(rebuilt, left);
            AnchorExactInteger *const magnitude = common;
            *magnitude = *newton_remainder;
            magnitude->sign = (magnitude->sign == 0) ? 0 : 1;
            *product = *right;
            product->sign = 1;
            held = held && (anchor_exact_compare(magnitude, product) < 0)
                && ((newton_remainder->sign == 0) || (newton_remainder->sign == left->sign));
            division_held += held ? 1u : 0u;
        }
    }
    printf("  %u divisions, divisors to %llu limbs\n", division_tried, (unsigned long long)half);
    check("Newton's division meets numerator = quotient . divisor + remainder, the remainder below the divisor, and "
          "equals the dispatched division",
          division_held == division_tried);

    printf("  seconds per product, balanced operands:\n  limbs        long         ladder       transform\n");
    for (size_t size = 8u; size <= half; size *= 2u)
    {
        ladder_fill(left, size, 0);
        ladder_fill(right, size, 0);
        const double long_seconds = (size <= 8192u) ? ladder_seconds(ladder_long, left, right, product) : 0.0;
        const double ladder_time = ladder_seconds(anchor_exact_multiply, left, right, product);
        const double transform_time = ladder_seconds(anchor_exact_multiply_transform, left, right, product);
        printf("  %7llu  %11.3e  %11.3e  %11.3e\n", (unsigned long long)size, long_seconds, ladder_time, transform_time);
    }

    printf("  seconds per division, a 2n-limb numerator by an n-limb divisor:\n  limbs        divide       newton\n");
    for (size_t size = 8u; (2u * size) <= (size_t)ANCHOR_EXACT_LIMBS; size *= 2u)
    {
        ladder_fill(left, 2u * size, 0);
        ladder_fill(right, size, 0);
        const double divide_time = ladder_divide_seconds(anchor_exact_divide, left, right, quotient, remainder);
        const double newton_time = ladder_divide_seconds(anchor_exact_divide_newton, left, right, quotient, remainder);
        printf("  %7llu  %11.3e  %11.3e\n", (unsigned long long)size, divide_time, newton_time);
    }

    free(newton_quotient);
    free(newton_remainder);
    free(rebuilt);
    free(left);
    free(right);
    free(product);
    free(quotient);
    free(remainder);
    free(common);
    printf("  exact transform test: %d checks, %d failed\n", s_checks, s_failed);
    return (s_failed == 0) ? 0 : 1;
}
