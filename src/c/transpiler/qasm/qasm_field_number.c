// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_field_number.c: numbers of the field and their bytes
#include "qasm_field_internal.h"

const QasmNumber qasm_number_zero = {{QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},
                                     {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}};

const QasmNumber qasm_number_one = QASM_NUMBER_ONE_INITIALIZER;

static const QasmRational qasm_rational_half = QASM_RATIONAL_HALF_INITIALIZER;

// 1/(a + b sqrt2) = (a - b sqrt2)/(a^2 - 2 b^2); sqrt2 is irrational. Only zero has a zero denominator
static long qasm_real_invert(const QasmRealNumber *value, QasmRealNumber *inverse, EngineError *error)
{
    QasmRational rational_squared;
    QasmRational sqrt2_squared;
    QasmRational denominator;
    QasmRational negated_sqrt2;
    QasmRealNumber result;
    qasm_rational_negate(&value->sqrt2, &negated_sqrt2);
    const int ok = (qasm_rational_multiply(&value->rational, &value->rational, &rational_squared, error) == 0L) &&
                   (qasm_rational_multiply(&value->sqrt2, &value->sqrt2, &sqrt2_squared, error) == 0L) &&
                   (qasm_rational_add(&sqrt2_squared, &sqrt2_squared, &sqrt2_squared, error) == 0L) &&
                   (qasm_rational_subtract(&rational_squared, &sqrt2_squared, &denominator, error) == 0L) &&
                   (qasm_rational_divide(&value->rational, &denominator, &result.rational, error) == 0L) &&
                   (qasm_rational_divide(&negated_sqrt2, &denominator, &result.sqrt2, error) == 0L);
    if (ok != 0)
    {
        *inverse = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_number_add(const QasmNumber *left, const QasmNumber *right, QasmNumber *sum, EngineError *error)
{
    QasmNumber result;
    const int ok = (qasm_real_add(&left->real, &right->real, &result.real, error) == 0L) &&
                   (qasm_real_add(&left->imaginary, &right->imaginary, &result.imaginary, error) == 0L);
    if (ok != 0)
    {
        *sum = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_number_subtract(const QasmNumber *left, const QasmNumber *right, QasmNumber *difference, EngineError *error)
{
    QasmNumber result;
    const int ok = (qasm_real_subtract(&left->real, &right->real, &result.real, error) == 0L) &&
                   (qasm_real_subtract(&left->imaginary, &right->imaginary, &result.imaginary, error) == 0L);
    if (ok != 0)
    {
        *difference = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
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
    const int ok = (qasm_real_multiply(&left->real, &right->real, &real_real, error) == 0L) &&
                   (qasm_real_multiply(&left->imaginary, &right->imaginary, &imaginary_imaginary, error) == 0L) &&
                   (qasm_real_subtract(&real_real, &imaginary_imaginary, &result.real, error) == 0L) &&
                   (qasm_real_multiply(&left->real, &right->imaginary, &real_imaginary, error) == 0L) &&
                   (qasm_real_multiply(&left->imaginary, &right->real, &imaginary_real, error) == 0L) &&
                   (qasm_real_add(&real_imaginary, &imaginary_real, &result.imaginary, error) == 0L);
    if (ok != 0)
    {
        *product = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
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
    const int ok = (qasm_real_multiply(&value->real, &value->real, &real_squared, error) == 0L) &&
                   (qasm_real_multiply(&value->imaginary, &value->imaginary, &imaginary_squared, error) == 0L) &&
                   (qasm_real_add(&real_squared, &imaginary_squared, &magnitude, error) == 0L) &&
                   (qasm_real_invert(&magnitude, &magnitude_inverse, error) == 0L) &&
                   (qasm_real_multiply(&value->real, &magnitude_inverse, &result.real, error) == 0L) &&
                   (qasm_real_multiply(&negated_imaginary, &magnitude_inverse, &result.imaginary, error) == 0L);
    if (ok != 0)
    {
        *inverse = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_number_half_sqrt2_times(const QasmNumber *value, QasmNumber *product, EngineError *error)
{
    QasmNumber result;
    result.real.rational = value->real.sqrt2;
    result.imaginary.rational = value->imaginary.sqrt2;
    const int ok =
        (qasm_rational_multiply(&value->real.rational, &qasm_rational_half, &result.real.sqrt2, error) == 0L) &&
        (qasm_rational_multiply(&value->imaginary.rational, &qasm_rational_half, &result.imaginary.sqrt2, error) == 0L);
    if (ok != 0)
    {
        *product = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_number_norm(const QasmNumber *value, QasmNumber *norm, EngineError *error)
{
    QasmRealNumber real_squared;
    QasmRealNumber imaginary_squared;
    QasmNumber result = qasm_number_zero;
    const int ok = (qasm_real_multiply(&value->real, &value->real, &real_squared, error) == 0L) &&
                   (qasm_real_multiply(&value->imaginary, &value->imaginary, &imaginary_squared, error) == 0L) &&
                   (qasm_real_add(&real_squared, &imaginary_squared, &result.real, error) == 0L);
    if (ok != 0)
    {
        *norm = result;
    }
    return (ok != 0) ? 0L : QASM_ERROR;
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
    return qasm_rational_equal(&left->real.rational, &right->real.rational) &&
           qasm_rational_equal(&left->real.sqrt2, &right->real.sqrt2) &&
           qasm_rational_equal(&left->imaginary.rational, &right->imaginary.rational) &&
           qasm_rational_equal(&left->imaginary.sqrt2, &right->imaginary.sqrt2);
}

int qasm_number_is_zero(const QasmNumber *value)
{
    return qasm_rational_is_zero(&value->real.rational) && qasm_rational_is_zero(&value->real.sqrt2) &&
           qasm_rational_is_zero(&value->imaginary.rational) && qasm_rational_is_zero(&value->imaginary.sqrt2);
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
    // the limb count fits in 32 bits, as the assert at the top of this file requires
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
    // the used count widens to size_t exactly. Four bytes a limb cannot wrap 32 bits
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
        const int ok =
            (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L) && qasm_text_put(builder, "*sqrt2");
        return (ok != 0) ? 0L : QASM_ERROR;
    }
    const int ok = qasm_text_put(builder, "(") && (qasm_rational_put_text(&value->rational, builder, error) == 0L) &&
                   qasm_text_put(builder, " + ") && (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L) &&
                   qasm_text_put(builder, "*sqrt2)");
    return (ok != 0) ? 0L : QASM_ERROR;
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
            return (qasm_text_put(builder, "sqrt2") != 0) ? 0L : QASM_ERROR;
        }
        const int ok = (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L) && qasm_text_put(builder, "sqrt2");
        return (ok != 0) ? 0L : QASM_ERROR;
    }
    const int ok = qasm_text_put(builder, "(") && (qasm_rational_put_text(&value->rational, builder, error) == 0L) &&
                   qasm_text_put(builder, "+") && (qasm_rational_put_text(&value->sqrt2, builder, error) == 0L) &&
                   qasm_text_put(builder, "sqrt2)");
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_number_text(const QasmNumber *value, char *text, size_t capacity, EngineError *error)
{
    if (QASM_CHECK((value != NULL) && (text != NULL) && (capacity > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    text[0] = '\0';
    QasmText builder = {text, capacity, 0u, 1};
    const int ok = (qasm_real_text(&value->real, &builder, error) == 0L) && qasm_text_put(&builder, " + ") &&
                   (qasm_real_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    return (QASM_CHECK(ok && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_ERROR;
}

long qasm_number_short_text(const QasmNumber *value, char *text, size_t capacity, EngineError *error)
{
    if (QASM_CHECK((value != NULL) && (text != NULL) && (capacity > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    text[0] = '\0';
    QasmText builder = {text, capacity, 0u, 1};
    const int imaginary_zero =
        qasm_rational_is_zero(&value->imaginary.rational) && qasm_rational_is_zero(&value->imaginary.sqrt2);
    const int real_zero = qasm_rational_is_zero(&value->real.rational) && qasm_rational_is_zero(&value->real.sqrt2);
    int ok = 1;
    if (imaginary_zero != 0)
    {
        ok = (qasm_real_short_text(&value->real, &builder, error) == 0L);
    }
    else if (real_zero != 0)
    {
        ok = (qasm_real_short_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    }
    else
    {
        ok = (qasm_real_short_text(&value->real, &builder, error) == 0L) && qasm_text_put(&builder, " + ") &&
             (qasm_real_short_text(&value->imaginary, &builder, error) == 0L) && qasm_text_put(&builder, " i");
    }
    return (QASM_CHECK(ok && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_ERROR;
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
    return qasm_number_subtract((const QasmNumber *)left, (const QasmNumber *)right, (QasmNumber *)difference, error);
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

const QasmField qasm_number_field = {sizeof(QasmNumber),          &qasm_number_zero,          &qasm_number_one,
                                     qasm_number_field_copy,      qasm_number_field_release,  qasm_number_field_add,
                                     qasm_number_field_subtract,  qasm_number_field_multiply, qasm_number_field_invert,
                                     qasm_number_field_conjugate, qasm_number_field_is_zero};
