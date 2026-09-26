// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include <string.h>

_Static_assert(ANCHOR_EXACT_LIMBS >= 2u, "qasm: a rational set from a long long needs two limbs");
_Static_assert(ANCHOR_EXACT_LIMBS <= 0xFFFFFFFFull, "qasm: a number's bytes count its used limbs in 32 bits");

// an exact status enumerates small non-negative codes, so it converts to int exactly
#define QASM_TOOK(status_, evacaddr_, error_) \
    engine_status_check((int)(status_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define QASM_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// 10^9 exceeds 2^29, so each decimal chunk takes at least 29 of the width's bits
#define QASM_TEXT_CHUNKS (((unsigned long long)(ANCHOR_EXACT_BITS) / 29ull) + 2ull)

#define QASM_TEXT_CHUNK 1000000000u

#define QASM_TEXT_CHUNK_DIGITS 9u

#define QASM_RATIONAL_MINUS_ONE_INITIALIZER {{{1u}, -1}, {{1u}, 1}}

#define QASM_RATIONAL_HALF_INITIALIZER {{{1u}, 1}, {{2u}, 1}}

#define QASM_RATIONAL_MINUS_HALF_INITIALIZER {{{1u}, -1}, {{2u}, 1}}

const QasmNumber qasm_number_zero = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                     {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_one = QASM_NUMBER_ONE_INITIALIZER;

const QasmNumber qasm_number_minus_one = {{QASM_RATIONAL_MINUS_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                          {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_i = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                  {QASM_RATIONAL_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_half_sqrt2 = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
                                           {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_eighth_turn = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
                                            {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER}};

const QasmNumber qasm_number_eighth_turn_back = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_HALF_INITIALIZER},
                                                 {QASM_RATIONAL_ZERO_INITIALIZER,
                                                  QASM_RATIONAL_MINUS_HALF_INITIALIZER}};

static const QasmRational qasm_rational_half = QASM_RATIONAL_HALF_INITIALIZER;

static const QasmRational qasm_rational_one = QASM_RATIONAL_ONE_INITIALIZER;

static const QasmRational qasm_rational_zero = QASM_RATIONAL_ZERO_INITIALIZER;

typedef struct
{
    char *text;
    size_t room;
    size_t length;
    int fits;
} QasmText;

static int qasm_text_put(QasmText *builder, const char *piece)
{
    const size_t count = strlen(piece);
    if ((builder->fits != 0) && (count < (builder->room - builder->length)))
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
        // a digit is 0 to 9, so '0' plus it is an ASCII digit, which a char holds
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
        return (qasm_text_put(builder, "0") != 0) ? 0L : QASM_REFUSED;
    }
    AnchorExactInteger chunk_divisor;
    anchor_exact_zero(&chunk_divisor);
    chunk_divisor.limb[0] = QASM_TEXT_CHUNK;
    chunk_divisor.sign = 1;
    AnchorExactInteger remaining = *value;
    remaining.sign = 1;
    unsigned int chunks[QASM_TEXT_CHUNKS];
    unsigned int count = 0u;
    int held = 1;
    while ((held != 0) && (remaining.sign != 0))
    {
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        held = QASM_HELD(count < QASM_TEXT_CHUNKS, value, error, ENGINE_ERROR_LOGIC)
            && QASM_TOOK(anchor_exact_divide(&remaining, &chunk_divisor, &quotient, &remainder), value, error);
        if (held != 0)
        {
            chunks[count] = remainder.limb[0];
            count += 1u;
            remaining = quotient;
        }
    }
    if (held == 0)
    {
        return QASM_REFUSED;
    }
    int fits = (value->sign < 0) ? qasm_text_put(builder, "-") : 1;
    fits = fits && qasm_text_chunk(builder, chunks[count - 1u], 0u);
    for (unsigned int at = count - 1u; (fits != 0) && (at > 0u); at -= 1u)
    {
        fits = qasm_text_chunk(builder, chunks[at - 1u], QASM_TEXT_CHUNK_DIGITS);
    }
    return (fits != 0) ? 0L : QASM_REFUSED;
}

static long qasm_rational_put_text(const QasmRational *value, QasmText *builder, EngineError *error)
{
    if (qasm_integer_text(&value->numerator, builder, error) != 0L)
    {
        return QASM_REFUSED;
    }
    if (anchor_exact_equal(&value->denominator, &qasm_rational_one.denominator) != 0)
    {
        return 0L;
    }
    const int held = qasm_text_put(builder, "/") && (qasm_integer_text(&value->denominator, builder, error) == 0L);
    return (held != 0) ? 0L : QASM_REFUSED;
}

// numerator / denominator with no common factor and the denominator positive; a zero denominator refuses
static long qasm_rational_reduce(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                                 QasmRational *value, EngineError *error)
{
    if (QASM_HELD(denominator->sign != 0, denominator, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    AnchorExactInteger common;
    AnchorExactInteger reduced_numerator;
    AnchorExactInteger reduced_denominator;
    const int held = QASM_TOOK(anchor_exact_gcd(numerator, denominator, &common), numerator, error)
                  && QASM_TOOK(anchor_exact_divide_exact(numerator, &common, &reduced_numerator), numerator, error)
                  && QASM_TOOK(anchor_exact_divide_exact(denominator, &common, &reduced_denominator), denominator,
                               error);
    if (held == 0)
    {
        return QASM_REFUSED;
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
    const unsigned long long magnitude = (signed_value < 0LL) ? (0ull - (unsigned long long)signed_value)
                                                               : (unsigned long long)signed_value;
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
    const int held = QASM_TOOK(anchor_exact_multiply(&left->numerator, &right->denominator, &numerator), left, error)
                  && QASM_TOOK(anchor_exact_multiply(&right->numerator, &left->denominator, &cross), right, error)
                  && QASM_TOOK(anchor_exact_add(&numerator, &cross, &numerator), left, error)
                  && QASM_TOOK(anchor_exact_multiply(&left->denominator, &right->denominator, &denominator), left,
                               error);
    return (held != 0) ? qasm_rational_reduce(&numerator, &denominator, sum, error) : QASM_REFUSED;
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
    const int held = QASM_TOOK(anchor_exact_multiply(&left->numerator, &right->numerator, &numerator), left, error)
                  && QASM_TOOK(anchor_exact_multiply(&left->denominator, &right->denominator, &denominator), right,
                               error);
    return (held != 0) ? qasm_rational_reduce(&numerator, &denominator, product, error) : QASM_REFUSED;
}

long qasm_rational_divide(const QasmRational *numerator, const QasmRational *divisor, QasmRational *quotient,
                          EngineError *error)
{
    if (QASM_HELD(divisor->numerator.sign != 0, divisor, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    const int held = QASM_TOOK(anchor_exact_multiply(&numerator->numerator, &divisor->denominator, &top), numerator,
                               error)
                  && QASM_TOOK(anchor_exact_multiply(&numerator->denominator, &divisor->numerator, &bottom), divisor,
                               error);
    return (held != 0) ? qasm_rational_reduce(&top, &bottom, quotient, error) : QASM_REFUSED;
}

void qasm_rational_negate(const QasmRational *value, QasmRational *negated)
{
    *negated = *value;
    negated->numerator.sign = -negated->numerator.sign;
}

int qasm_rational_equal(const QasmRational *left, const QasmRational *right)
{
    return anchor_exact_equal(&left->numerator, &right->numerator)
        && anchor_exact_equal(&left->denominator, &right->denominator);
}

int qasm_rational_is_zero(const QasmRational *value)
{
    return value->numerator.sign == 0;
}

long qasm_rational_text(const QasmRational *value, char *text, size_t room, EngineError *error)
{
    if (QASM_HELD((value != NULL) && (text != NULL) && (room > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    text[0] = '\0';
    QasmText builder = {text, room, 0u, 1};
    const int held = (qasm_rational_put_text(value, &builder, error) == 0L);
    return (QASM_HELD(held && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_REFUSED;
}

static long qasm_real_add(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *sum,
                          EngineError *error)
{
    QasmRealNumber result;
    const int held = (qasm_rational_add(&left->rational, &right->rational, &result.rational, error) == 0L)
                  && (qasm_rational_add(&left->sqrt2, &right->sqrt2, &result.sqrt2, error) == 0L);
    if (held != 0)
    {
        *sum = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

static void qasm_real_negate(const QasmRealNumber *value, QasmRealNumber *negated)
{
    qasm_rational_negate(&value->rational, &negated->rational);
    qasm_rational_negate(&value->sqrt2, &negated->sqrt2);
}

static long qasm_real_subtract(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *difference,
                               EngineError *error)
{
    QasmRealNumber negated;
    qasm_real_negate(right, &negated);
    return qasm_real_add(left, &negated, difference, error);
}

// (a + b sqrt2)(c + d sqrt2) = (ac + 2bd) + (ad + bc) sqrt2
static long qasm_real_multiply(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *product,
                               EngineError *error)
{
    QasmRational rational_rational;
    QasmRational sqrt2_sqrt2;
    QasmRational rational_sqrt2;
    QasmRational sqrt2_rational;
    QasmRealNumber result;
    const int held = (qasm_rational_multiply(&left->rational, &right->rational, &rational_rational, error) == 0L)
                  && (qasm_rational_multiply(&left->sqrt2, &right->sqrt2, &sqrt2_sqrt2, error) == 0L)
                  && (qasm_rational_add(&sqrt2_sqrt2, &sqrt2_sqrt2, &sqrt2_sqrt2, error) == 0L)
                  && (qasm_rational_add(&rational_rational, &sqrt2_sqrt2, &result.rational, error) == 0L)
                  && (qasm_rational_multiply(&left->rational, &right->sqrt2, &rational_sqrt2, error) == 0L)
                  && (qasm_rational_multiply(&left->sqrt2, &right->rational, &sqrt2_rational, error) == 0L)
                  && (qasm_rational_add(&rational_sqrt2, &sqrt2_rational, &result.sqrt2, error) == 0L);
    if (held != 0)
    {
        *product = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

// 1/(a + b sqrt2) = (a - b sqrt2)/(a^2 - 2 b^2); sqrt2 is irrational, so only zero has a zero denominator
static long qasm_real_invert(const QasmRealNumber *value, QasmRealNumber *inverse, EngineError *error)
{
    QasmRational rational_squared;
    QasmRational sqrt2_squared;
    QasmRational denominator;
    QasmRational negated_sqrt2;
    QasmRealNumber result;
    qasm_rational_negate(&value->sqrt2, &negated_sqrt2);
    const int held = (qasm_rational_multiply(&value->rational, &value->rational, &rational_squared, error) == 0L)
                  && (qasm_rational_multiply(&value->sqrt2, &value->sqrt2, &sqrt2_squared, error) == 0L)
                  && (qasm_rational_add(&sqrt2_squared, &sqrt2_squared, &sqrt2_squared, error) == 0L)
                  && (qasm_rational_subtract(&rational_squared, &sqrt2_squared, &denominator, error) == 0L)
                  && (qasm_rational_divide(&value->rational, &denominator, &result.rational, error) == 0L)
                  && (qasm_rational_divide(&negated_sqrt2, &denominator, &result.sqrt2, error) == 0L);
    if (held != 0)
    {
        *inverse = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_add(const QasmNumber *left, const QasmNumber *right, QasmNumber *sum, EngineError *error)
{
    QasmNumber result;
    const int held = (qasm_real_add(&left->real, &right->real, &result.real, error) == 0L)
                  && (qasm_real_add(&left->imaginary, &right->imaginary, &result.imaginary, error) == 0L);
    if (held != 0)
    {
        *sum = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_subtract(const QasmNumber *left, const QasmNumber *right, QasmNumber *difference, EngineError *error)
{
    QasmNumber result;
    const int held = (qasm_real_subtract(&left->real, &right->real, &result.real, error) == 0L)
                  && (qasm_real_subtract(&left->imaginary, &right->imaginary, &result.imaginary, error) == 0L);
    if (held != 0)
    {
        *difference = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

// (xr + i xi)(yr + i yi) = (xr yr - xi yi) + i (xr yi + xi yr)
long qasm_number_multiply(const QasmNumber *left, const QasmNumber *right, QasmNumber *product, EngineError *error)
{
    if (qasm_number_is_zero(left) || qasm_number_is_zero(right))
    {
        *product = qasm_number_zero;
        return 0L;
    }
    QasmRealNumber real_real;
    QasmRealNumber imaginary_imaginary;
    QasmRealNumber real_imaginary;
    QasmRealNumber imaginary_real;
    QasmNumber result;
    const int held = (qasm_real_multiply(&left->real, &right->real, &real_real, error) == 0L)
                  && (qasm_real_multiply(&left->imaginary, &right->imaginary, &imaginary_imaginary, error) == 0L)
                  && (qasm_real_subtract(&real_real, &imaginary_imaginary, &result.real, error) == 0L)
                  && (qasm_real_multiply(&left->real, &right->imaginary, &real_imaginary, error) == 0L)
                  && (qasm_real_multiply(&left->imaginary, &right->real, &imaginary_real, error) == 0L)
                  && (qasm_real_add(&real_imaginary, &imaginary_real, &result.imaginary, error) == 0L);
    if (held != 0)
    {
        *product = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_invert(const QasmNumber *value, QasmNumber *inverse, EngineError *error)
{
    QasmRealNumber real_squared;
    QasmRealNumber imaginary_squared;
    QasmRealNumber magnitude;
    QasmRealNumber magnitude_inverse;
    QasmRealNumber negated_imaginary;
    QasmNumber result;
    qasm_real_negate(&value->imaginary, &negated_imaginary);
    const int held = (qasm_real_multiply(&value->real, &value->real, &real_squared, error) == 0L)
                  && (qasm_real_multiply(&value->imaginary, &value->imaginary, &imaginary_squared, error) == 0L)
                  && (qasm_real_add(&real_squared, &imaginary_squared, &magnitude, error) == 0L)
                  && (qasm_real_invert(&magnitude, &magnitude_inverse, error) == 0L)
                  && (qasm_real_multiply(&value->real, &magnitude_inverse, &result.real, error) == 0L)
                  && (qasm_real_multiply(&negated_imaginary, &magnitude_inverse, &result.imaginary, error) == 0L);
    if (held != 0)
    {
        *inverse = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_half_sqrt2_times(const QasmNumber *value, QasmNumber *product, EngineError *error)
{
    QasmNumber result;
    result.real.rational = value->real.sqrt2;
    result.imaginary.rational = value->imaginary.sqrt2;
    const int held = (qasm_rational_multiply(&value->real.rational, &qasm_rational_half, &result.real.sqrt2, error)
                      == 0L)
                  && (qasm_rational_multiply(&value->imaginary.rational, &qasm_rational_half,
                                             &result.imaginary.sqrt2, error)
                      == 0L);
    if (held != 0)
    {
        *product = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_norm(const QasmNumber *value, QasmNumber *norm, EngineError *error)
{
    QasmRealNumber real_squared;
    QasmRealNumber imaginary_squared;
    QasmNumber result = qasm_number_zero;
    const int held = (qasm_real_multiply(&value->real, &value->real, &real_squared, error) == 0L)
                  && (qasm_real_multiply(&value->imaginary, &value->imaginary, &imaginary_squared, error) == 0L)
                  && (qasm_real_add(&real_squared, &imaginary_squared, &result.real, error) == 0L);
    if (held != 0)
    {
        *norm = result;
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

void qasm_number_negate(const QasmNumber *value, QasmNumber *negated)
{
    qasm_real_negate(&value->real, &negated->real);
    qasm_real_negate(&value->imaginary, &negated->imaginary);
}

// i (xr + i xi) = -xi + i xr
void qasm_number_i_times(const QasmNumber *value, QasmNumber *product)
{
    const QasmRealNumber real = value->real;
    qasm_real_negate(&value->imaginary, &product->real);
    product->imaginary = real;
}

void qasm_number_conjugate(const QasmNumber *value, QasmNumber *conjugate)
{
    conjugate->real = value->real;
    qasm_real_negate(&value->imaginary, &conjugate->imaginary);
}

int qasm_number_equal(const QasmNumber *left, const QasmNumber *right)
{
    return qasm_rational_equal(&left->real.rational, &right->real.rational)
        && qasm_rational_equal(&left->real.sqrt2, &right->real.sqrt2)
        && qasm_rational_equal(&left->imaginary.rational, &right->imaginary.rational)
        && qasm_rational_equal(&left->imaginary.sqrt2, &right->imaginary.sqrt2);
}

int qasm_number_is_zero(const QasmNumber *value)
{
    return qasm_rational_is_zero(&value->real.rational) && qasm_rational_is_zero(&value->real.sqrt2)
        && qasm_rational_is_zero(&value->imaginary.rational) && qasm_rational_is_zero(&value->imaginary.sqrt2);
}

static void qasm_word_bytes(uint32_t word, unsigned char *bytes)
{
    for (unsigned int byte = 0u; byte < 4u; byte += 1u)
    {
        // one byte of the word, masked to 8 bits
        bytes[byte] = (unsigned char)((word >> (8u * byte)) & 0xFFu);
    }
}

static size_t qasm_integer_bytes(const AnchorExactInteger *value, unsigned char *bytes)
{
    // the limb count is held whole in 32 bits, as the assert at the top of this file requires
    uint32_t used = (uint32_t)ANCHOR_EXACT_LIMBS;
    while ((used > 0u) && (value->limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    if (bytes != NULL)
    {
        // the sign is -1, 0 or 1; its two's complement bits are what the seal takes
        qasm_word_bytes((uint32_t)value->sign, &bytes[0]);
        qasm_word_bytes(used, &bytes[4]);
        for (uint32_t limb = 0u; limb < used; limb += 1u)
        {
            // a 32-bit limb index widens to size_t exactly
            qasm_word_bytes(value->limb[limb], &bytes[8u + (4u * (size_t)limb)]);
        }
    }
    // the used count widens to size_t exactly, so four bytes a limb cannot wrap 32 bits
    return 8u + (4u * (size_t)used);
}

static size_t qasm_rational_bytes(const QasmRational *value, unsigned char *bytes)
{
    const size_t numerator = qasm_integer_bytes(&value->numerator, bytes);
    return numerator + qasm_integer_bytes(&value->denominator, (bytes != NULL) ? &bytes[numerator] : NULL);
}

size_t qasm_number_bytes(const QasmNumber *value, unsigned char *bytes)
{
    const QasmRational *const parts[4] = {&value->real.rational, &value->real.sqrt2, &value->imaginary.rational,
                                          &value->imaginary.sqrt2};
    size_t count = 0u;
    for (unsigned int part = 0u; part < 4u; part += 1u)
    {
        count += qasm_rational_bytes(parts[part], (bytes != NULL) ? &bytes[count] : NULL);
    }
    return count;
}

// f_str's q2: "p" where the sqrt2 part is 0, "q*sqrt2" where the rational part is, "(p + q*sqrt2)" otherwise
static long qasm_real_text(const QasmRealNumber *value, QasmText *builder, EngineError *error)
{
    if (qasm_rational_is_zero(&value->sqrt2))
    {
        return qasm_rational_put_text(&value->rational, builder, error);
    }
    if (qasm_rational_is_zero(&value->rational))
    {
        const int held = (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L)
                      && qasm_text_put(builder, "*sqrt2");
        return (held != 0) ? 0L : QASM_REFUSED;
    }
    const int held = qasm_text_put(builder, "(") && (qasm_rational_put_text(&value->rational, builder, error) == 0L)
                  && qasm_text_put(builder, " + ") && (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L)
                  && qasm_text_put(builder, "*sqrt2)");
    return (held != 0) ? 0L : QASM_REFUSED;
}

// k_short's real: "x" where the sqrt2 part is 0; "sqrt2" or "ysqrt2" where the rational part is; "(x+ysqrt2)"
static long qasm_real_short_text(const QasmRealNumber *value, QasmText *builder, EngineError *error)
{
    if (qasm_rational_is_zero(&value->sqrt2))
    {
        return qasm_rational_put_text(&value->rational, builder, error);
    }
    if (qasm_rational_is_zero(&value->rational))
    {
        if (qasm_rational_equal(&value->sqrt2, &qasm_rational_one))
        {
            return (qasm_text_put(builder, "sqrt2") != 0) ? 0L : QASM_REFUSED;
        }
        const int held = (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L)
                      && qasm_text_put(builder, "sqrt2");
        return (held != 0) ? 0L : QASM_REFUSED;
    }
    const int held = qasm_text_put(builder, "(") && (qasm_rational_put_text(&value->rational, builder, error) == 0L)
                  && qasm_text_put(builder, "+") && (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L)
                  && qasm_text_put(builder, "sqrt2)");
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_text(const QasmNumber *value, char *text, size_t room, EngineError *error)
{
    if (QASM_HELD((value != NULL) && (text != NULL) && (room > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    text[0] = '\0';
    QasmText builder = {text, room, 0u, 1};
    const int held = (qasm_real_text(&value->real, &builder, error) == 0L) && qasm_text_put(&builder, " + ")
                  && (qasm_real_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    return (QASM_HELD(held && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_REFUSED;
}

long qasm_number_short_text(const QasmNumber *value, char *text, size_t room, EngineError *error)
{
    if (QASM_HELD((value != NULL) && (text != NULL) && (room > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    text[0] = '\0';
    QasmText builder = {text, room, 0u, 1};
    const int imaginary_zero = qasm_rational_is_zero(&value->imaginary.rational)
                            && qasm_rational_is_zero(&value->imaginary.sqrt2);
    const int real_zero = qasm_rational_is_zero(&value->real.rational) && qasm_rational_is_zero(&value->real.sqrt2);
    int held = 1;
    if (imaginary_zero != 0)
    {
        held = (qasm_real_short_text(&value->real, &builder, error) == 0L);
    }
    else if (real_zero != 0)
    {
        held = (qasm_real_short_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    }
    else
    {
        held = (qasm_real_short_text(&value->real, &builder, error) == 0L) && qasm_text_put(&builder, " + ")
            && (qasm_real_short_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    }
    return (QASM_HELD(held && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_REFUSED;
}

static long qasm_number_field_copy(const void *from, void *to, EngineError *error)
{
    (void)error;
    *(QasmNumber *)to = *(const QasmNumber *)from;
    return 0L;
}

static void qasm_number_field_release(void *element)
{
    memset(element, 0, sizeof(QasmNumber));
}

static long qasm_number_field_add(const void *left, const void *right, void *sum, EngineError *error)
{
    return qasm_number_add((const QasmNumber *)left, (const QasmNumber *)right, (QasmNumber *)sum, error);
}

static long qasm_number_field_subtract(const void *left, const void *right, void *difference, EngineError *error)
{
    return qasm_number_subtract((const QasmNumber *)left, (const QasmNumber *)right, (QasmNumber *)difference,
                                error);
}

static long qasm_number_field_multiply(const void *left, const void *right, void *product, EngineError *error)
{
    return qasm_number_multiply((const QasmNumber *)left, (const QasmNumber *)right, (QasmNumber *)product, error);
}

static long qasm_number_field_invert(const void *value, void *inverse, EngineError *error)
{
    return qasm_number_invert((const QasmNumber *)value, (QasmNumber *)inverse, error);
}

static long qasm_number_field_conjugate(const void *value, void *conjugate, EngineError *error)
{
    (void)error;
    qasm_number_conjugate((const QasmNumber *)value, (QasmNumber *)conjugate);
    return 0L;
}

static int qasm_number_field_is_zero(const void *value)
{
    return qasm_number_is_zero((const QasmNumber *)value);
}

const QasmField qasm_number_field = {sizeof(QasmNumber),         &qasm_number_zero,          &qasm_number_one,
                                     qasm_number_field_copy,     qasm_number_field_release,  qasm_number_field_add,
                                     qasm_number_field_subtract, qasm_number_field_multiply, qasm_number_field_invert,
                                     qasm_number_field_conjugate, qasm_number_field_is_zero};
