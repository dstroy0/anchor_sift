// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_field_rational.c: text and rationals
#include "qasm_field_internal.h"

const QasmNumber qasm_number_minus_one = {{QASM_RATIONAL_MINUS_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                          {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_i = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                  {QASM_RATIONAL_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_half_sqrt2 = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
                                           {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_eighth_turn = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
                                            {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER}};

const QasmNumber qasm_number_eighth_turn_back = {
    {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
    {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_MINUS_HALF_INITIALIZER}};

static const QasmRational qasm_rational_zero = QASM_RATIONAL_ZERO_INITIALIZER;

int qasm_text_put(QasmText *builder, const char *piece)
{
    const size_t count = strlen(piece);
    if ((builder->fits != 0) && (count < (builder->capacity - builder->length)))
    {
        memcpy(&builder->text[builder->length], piece, count);
        builder->length += count;
        builder->text[builder->length] = '\0';
    }
    else
    {
        builder->fits = 0;
    }
    return builder->fits;
}

// one chunk's digits, padded with zeros to `width` digits
static int qasm_text_chunk(QasmText *builder, unsigned int chunk, unsigned int width)
{
    char digits[QASM_TEXT_CHUNK_DIGITS + 1u];
    unsigned int length = 0u;
    unsigned int left = chunk;
    digits[QASM_TEXT_CHUNK_DIGITS] = '\0';
    do
    {
        // a digit is 0 to 9. '0' plus it is an ASCII digit, which a char holds
        digits[QASM_TEXT_CHUNK_DIGITS - 1u - length] = (char)('0' + (int)(left % 10u));
        left /= 10u;
        length += 1u;
    } while ((left != 0u) || (length < width));
    return qasm_text_put(builder, &digits[QASM_TEXT_CHUNK_DIGITS - length]);
}

static long qasm_integer_text(const AnchorExactInteger *value, QasmText *builder, EngineError *error)
{
    if (value->sign == 0)
    {
        return (qasm_text_put(builder, "0") != 0) ? 0L : QASM_ERROR;
    }
    AnchorExactInteger chunk_divisor;
    anchor_exact_zero(&chunk_divisor);
    chunk_divisor.limb[0] = QASM_TEXT_CHUNK;
    chunk_divisor.sign = 1;
    AnchorExactInteger remaining = *value;
    remaining.sign = 1;
    unsigned int chunks[QASM_TEXT_CHUNKS];
    unsigned int count = 0u;
    int ok = 1;
    while ((ok != 0) && (remaining.sign != 0))
    {
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        ok = QASM_CHECK(count < QASM_TEXT_CHUNKS, value, error, ENGINE_ERROR_LOGIC) &&
             QASM_STATUS_CHECK(anchor_exact_divide(&remaining, &chunk_divisor, &quotient, &remainder), value, error);
        if (ok != 0)
        {
            chunks[count] = remainder.limb[0];
            count += 1u;
            remaining = quotient;
        }
    }
    if (ok == 0)
    {
        return QASM_ERROR;
    }
    int fits = (value->sign < 0) ? qasm_text_put(builder, "-") : 1;
    fits = fits && qasm_text_chunk(builder, chunks[count - 1u], 0u);
    for (unsigned int at = count - 1u; (fits != 0) && (at > 0u); at -= 1u)
    {
        fits = qasm_text_chunk(builder, chunks[at - 1u], QASM_TEXT_CHUNK_DIGITS);
    }
    return (fits != 0) ? 0L : QASM_ERROR;
}

long qasm_rational_put_text(const QasmRational *value, QasmText *builder, EngineError *error)
{
    if (qasm_integer_text(&value->numerator, builder, error) != 0L)
    {
        return QASM_ERROR;
    }
    if (anchor_exact_equal(&value->denominator, &qasm_rational_one.denominator) != 0)
    {
        return 0L;
    }
    const int ok = qasm_text_put(builder, "/") && (qasm_integer_text(&value->denominator, builder, error) == 0L);
    return (ok != 0) ? 0L : QASM_ERROR;
}

// numerator / denominator with no common factor and the denominator positive; a zero denominator refuses
static long qasm_rational_reduce(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                                 QasmRational *value, EngineError *error)
{
    if (QASM_CHECK(denominator->sign != 0, denominator, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    AnchorExactInteger common;
    AnchorExactInteger reduced_numerator;
    AnchorExactInteger reduced_denominator;
    const int ok =
        QASM_STATUS_CHECK(anchor_exact_gcd(numerator, denominator, &common), numerator, error) &&
        QASM_STATUS_CHECK(anchor_exact_divide_exact(numerator, &common, &reduced_numerator), numerator, error) &&
        QASM_STATUS_CHECK(anchor_exact_divide_exact(denominator, &common, &reduced_denominator), denominator, error);
    if (ok == 0)
    {
        return QASM_ERROR;
    }
    // a negative denominator hands its sign to the numerator
    reduced_numerator.sign *= reduced_denominator.sign;
    reduced_denominator.sign = 1;
    value->numerator = reduced_numerator;
    value->denominator = reduced_denominator;
    return 0L;
}

static void qasm_integer_set(AnchorExactInteger *value, long long signed_value)
{
    anchor_exact_zero(value);
    // the magnitude is taken in unsigned arithmetic, where negating LLONG_MIN is defined
    const unsigned long long magnitude =
        (signed_value < 0LL) ? (0ull - (unsigned long long)signed_value) : (unsigned long long)signed_value;
    // each limb takes 32 bits of the magnitude
    value->limb[0] = (uint32_t)(magnitude & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(magnitude >> 32u);
    value->sign = (signed_value < 0LL) ? -1 : ((signed_value > 0LL) ? 1 : 0);
}

long qasm_rational_set(QasmRational *value, long long numerator, long long denominator, EngineError *error)
{
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    qasm_integer_set(&top, numerator);
    qasm_integer_set(&bottom, denominator);
    return qasm_rational_reduce(&top, &bottom, value, error);
}

long qasm_rational_add(const QasmRational *left, const QasmRational *right, QasmRational *sum, EngineError *error)
{
    if (left->numerator.sign == 0)
    {
        *sum = *right;
        return 0L;
    }
    if (right->numerator.sign == 0)
    {
        *sum = *left;
        return 0L;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger cross;
    AnchorExactInteger denominator;
    const int ok =
        QASM_STATUS_CHECK(anchor_exact_multiply(&left->numerator, &right->denominator, &numerator), left, error) &&
        QASM_STATUS_CHECK(anchor_exact_multiply(&right->numerator, &left->denominator, &cross), right, error) &&
        QASM_STATUS_CHECK(anchor_exact_add(&numerator, &cross, &numerator), left, error) &&
        QASM_STATUS_CHECK(anchor_exact_multiply(&left->denominator, &right->denominator, &denominator), left, error);
    return (ok != 0) ? qasm_rational_reduce(&numerator, &denominator, sum, error) : QASM_ERROR;
}

long qasm_rational_subtract(const QasmRational *left, const QasmRational *right, QasmRational *difference,
                            EngineError *error)
{
    QasmRational negated;
    qasm_rational_negate(right, &negated);
    return qasm_rational_add(left, &negated, difference, error);
}

long qasm_rational_multiply(const QasmRational *left, const QasmRational *right, QasmRational *product,
                            EngineError *error)
{
    if ((left->numerator.sign == 0) || (right->numerator.sign == 0))
    {
        *product = qasm_rational_zero;
        return 0L;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    const int ok =
        QASM_STATUS_CHECK(anchor_exact_multiply(&left->numerator, &right->numerator, &numerator), left, error) &&
        QASM_STATUS_CHECK(anchor_exact_multiply(&left->denominator, &right->denominator, &denominator), right, error);
    return (ok != 0) ? qasm_rational_reduce(&numerator, &denominator, product, error) : QASM_ERROR;
}

long qasm_rational_divide(const QasmRational *numerator, const QasmRational *divisor, QasmRational *quotient,
                          EngineError *error)
{
    if (QASM_CHECK(divisor->numerator.sign != 0, divisor, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    const int ok =
        QASM_STATUS_CHECK(anchor_exact_multiply(&numerator->numerator, &divisor->denominator, &top), numerator,
                          error) &&
        QASM_STATUS_CHECK(anchor_exact_multiply(&numerator->denominator, &divisor->numerator, &bottom), divisor, error);
    return (ok != 0) ? qasm_rational_reduce(&top, &bottom, quotient, error) : QASM_ERROR;
}

void qasm_rational_negate(const QasmRational *value, QasmRational *negated)
{
    *negated = *value;
    negated->numerator.sign = -negated->numerator.sign;
}

int qasm_rational_equal(const QasmRational *left, const QasmRational *right)
{
    return anchor_exact_equal(&left->numerator, &right->numerator) &&
           anchor_exact_equal(&left->denominator, &right->denominator);
}

int qasm_rational_is_zero(const QasmRational *value)
{
    return value->numerator.sign == 0;
}

long qasm_rational_text(const QasmRational *value, char *text, size_t capacity, EngineError *error)
{
    if (QASM_CHECK((value != NULL) && (text != NULL) && (capacity > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    text[0] = '\0';
    QasmText builder = {text, capacity, 0u, 1};
    const int ok = (qasm_rational_put_text(value, &builder, error) == 0L);
    return (QASM_CHECK(ok && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_ERROR;
}

long qasm_real_add(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *sum, EngineError *error)
{
    QasmRealNumber result;
    const int ok = (qasm_rational_add(&left->rational, &right->rational, &result.rational, error) == 0L) &&
                   (qasm_rational_add(&left->sqrt2, &right->sqrt2, &result.sqrt2, error) == 0L);
    if (ok != 0)
    {
        *sum = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

void qasm_real_negate(const QasmRealNumber *value, QasmRealNumber *negated)
{
    qasm_rational_negate(&value->rational, &negated->rational);
    qasm_rational_negate(&value->sqrt2, &negated->sqrt2);
}

long qasm_real_subtract(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *difference,
                        EngineError *error)
{
    QasmRealNumber negated;
    qasm_real_negate(right, &negated);
    return qasm_real_add(left, &negated, difference, error);
}

// (a + b sqrt2)(c + d sqrt2) = (ac + 2bd) + (ad + bc) sqrt2
long qasm_real_multiply(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *product,
                        EngineError *error)
{
    QasmRational rational_rational;
    QasmRational sqrt2_sqrt2;
    QasmRational rational_sqrt2;
    QasmRational sqrt2_rational;
    QasmRealNumber result;
    const int ok = (qasm_rational_multiply(&left->rational, &right->rational, &rational_rational, error) == 0L) &&
                   (qasm_rational_multiply(&left->sqrt2, &right->sqrt2, &sqrt2_sqrt2, error) == 0L) &&
                   (qasm_rational_add(&sqrt2_sqrt2, &sqrt2_sqrt2, &sqrt2_sqrt2, error) == 0L) &&
                   (qasm_rational_add(&rational_rational, &sqrt2_sqrt2, &result.rational, error) == 0L) &&
                   (qasm_rational_multiply(&left->rational, &right->sqrt2, &rational_sqrt2, error) == 0L) &&
                   (qasm_rational_multiply(&left->sqrt2, &right->rational, &sqrt2_rational, error) == 0L) &&
                   (qasm_rational_add(&rational_sqrt2, &sqrt2_rational, &result.sqrt2, error) == 0L);
    if (ok != 0)
    {
        *product = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}
