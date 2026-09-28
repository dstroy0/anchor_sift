// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_symbolic_function.c: rational functions
#include "qasm_symbolic_internal.h"

// the coefficient the field's zero and one point at; nothing writes it, and nothing releases it
static QasmNumber qasm_symbolic_unit = QASM_NUMBER_ONE_INITIALIZER;

static const QasmRationalFunction qasm_symbolic_zero = {{0, 0u, NULL}, {0, 1u, &qasm_symbolic_unit}};

static const QasmRationalFunction qasm_symbolic_one = {{0, 1u, &qasm_symbolic_unit}, {0, 1u, &qasm_symbolic_unit}};

// the result replaces what the slot held, or is dropped on a refusal
static long qasm_function_install(long status, QasmRationalFunction *result, QasmRationalFunction *slot)
{
    if (status == 0L)
    {
        qasm_function_release_parts(slot);
        *slot = *result;
    }
    else
    {
        qasm_function_release_parts(result);
    }
    return status;
}

// rat_make: both shifted so neither holds a negative power, reduced by their monic gcd, and the denominator made
// monic. `made` is empty on entry.
static long qasm_function_make(const QasmPolynomial *numerator, const QasmPolynomial *denominator,
                               QasmRationalFunction *made, EngineError *error)
{
    if (numerator->count == 0u)
    {
        const long status = qasm_polynomial_alloc(0, 0ull, &made->numerator, error);
        return (status == 0L) ? qasm_polynomial_copy(&qasm_symbolic_zero.denominator, &made->denominator, error)
                              : status;
    }
    if (QASM_CHECK(denominator->count > 0u, denominator, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    const long long low = (numerator->low < denominator->low) ? numerator->low : denominator->low;
    QasmPolynomial top = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial bottom = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial common = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial reduced_top = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial reduced_bottom = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial top_remainder = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial bottom_remainder = QASM_POLYNOMIAL_EMPTY;
    // the lows widen from int to long long exactly; the allocation checks the shifted power against the bound
    long status = qasm_polynomial_alloc((long long)numerator->low - low, numerator->count, &top, error);
    status = (status == 0L)
                 ? qasm_polynomial_alloc((long long)denominator->low - low, denominator->count, &bottom, error)
                 : status;
    for (unsigned int index = 0u; (status == 0L) && (index < numerator->count); index += 1u)
    {
        top.coefficients[index] = numerator->coefficients[index];
    }
    for (unsigned int index = 0u; (status == 0L) && (index < denominator->count); index += 1u)
    {
        bottom.coefficients[index] = denominator->coefficients[index];
    }
    status = (status == 0L) ? qasm_polynomial_gcd(&top, &bottom, &common, error) : status;
    status = (status == 0L) ? qasm_polynomial_divide(&top, &common, &reduced_top, &top_remainder, error) : status;
    status =
        (status == 0L) ? qasm_polynomial_divide(&bottom, &common, &reduced_bottom, &bottom_remainder, error) : status;
    QasmNumber leading_inverse;
    status = (status == 0L)
                 ? qasm_number_invert(&reduced_bottom.coefficients[reduced_bottom.count - 1u], &leading_inverse, error)
                 : status;
    status = (status == 0L) ? qasm_polynomial_scale(&reduced_top, &leading_inverse, &made->numerator, error) : status;
    status =
        (status == 0L) ? qasm_polynomial_scale(&reduced_bottom, &leading_inverse, &made->denominator, error) : status;
    qasm_polynomial_release(&top);
    qasm_polynomial_release(&bottom);
    qasm_polynomial_release(&common);
    qasm_polynomial_release(&reduced_top);
    qasm_polynomial_release(&reduced_bottom);
    qasm_polynomial_release(&top_remainder);
    qasm_polynomial_release(&bottom_remainder);
    return status;
}

long qasm_rational_function_set(QasmRationalFunction *value, const QasmNumber *coefficient, int exponent,
                                EngineError *error)
{
    QasmPolynomial numerator = QASM_POLYNOMIAL_EMPTY;
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_alloc(exponent, 1ull, &numerator, error);
    if (status == 0L)
    {
        numerator.coefficients[0] = *coefficient;
        qasm_polynomial_trim(&numerator);
    }
    status = (status == 0L) ? qasm_function_make(&numerator, &qasm_symbolic_one.denominator, &result, error) : status;
    qasm_polynomial_release(&numerator);
    return qasm_function_install(status, &result, value);
}

long qasm_rational_function_copy(const QasmRationalFunction *from, QasmRationalFunction *to, EngineError *error)
{
    if (from == to)
    {
        return 0L;
    }
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_copy(&from->numerator, &result.numerator, error);
    status = (status == 0L) ? qasm_polynomial_copy(&from->denominator, &result.denominator, error) : status;
    return qasm_function_install(status, &result, to);
}

void qasm_rational_function_release(QasmRationalFunction *value)
{
    qasm_function_release_parts(value);
}

long qasm_rational_function_add(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                QasmRationalFunction *sum, EngineError *error)
{
    QasmPolynomial left_cross = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial right_cross = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial numerator = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial denominator = QASM_POLYNOMIAL_EMPTY;
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_multiply(&left->numerator, &right->denominator, &left_cross, error);
    status =
        (status == 0L) ? qasm_polynomial_multiply(&right->numerator, &left->denominator, &right_cross, error) : status;
    status = (status == 0L) ? qasm_polynomial_add(&left_cross, &right_cross, &numerator, error) : status;
    status = (status == 0L) ? qasm_polynomial_multiply(&left->denominator, &right->denominator, &denominator, error)
                            : status;
    status = (status == 0L) ? qasm_function_make(&numerator, &denominator, &result, error) : status;
    qasm_polynomial_release(&left_cross);
    qasm_polynomial_release(&right_cross);
    qasm_polynomial_release(&numerator);
    qasm_polynomial_release(&denominator);
    return qasm_function_install(status, &result, sum);
}

long qasm_rational_function_subtract(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                     QasmRationalFunction *difference, EngineError *error)
{
    QasmRationalFunction negated = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_negate(&right->numerator, &negated.numerator, error);
    status = (status == 0L) ? qasm_polynomial_copy(&right->denominator, &negated.denominator, error) : status;
    status = (status == 0L) ? qasm_rational_function_add(left, &negated, difference, error) : status;
    qasm_function_release_parts(&negated);
    return status;
}

long qasm_rational_function_multiply(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                     QasmRationalFunction *product, EngineError *error)
{
    QasmPolynomial numerator = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial denominator = QASM_POLYNOMIAL_EMPTY;
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_multiply(&left->numerator, &right->numerator, &numerator, error);
    status = (status == 0L) ? qasm_polynomial_multiply(&left->denominator, &right->denominator, &denominator, error)
                            : status;
    status = (status == 0L) ? qasm_function_make(&numerator, &denominator, &result, error) : status;
    qasm_polynomial_release(&numerator);
    qasm_polynomial_release(&denominator);
    return qasm_function_install(status, &result, product);
}

long qasm_rational_function_invert(const QasmRationalFunction *value, QasmRationalFunction *inverse, EngineError *error)
{
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    const long status = qasm_function_make(&value->denominator, &value->numerator, &result, error);
    return qasm_function_install(status, &result, inverse);
}

// w^e goes to w^-e: the coefficients reversed, each conjugated, the lowest power the negated highest
static long qasm_polynomial_conjugate(const QasmPolynomial *value, QasmPolynomial *conjugate, EngineError *error)
{
    const long long low = (value->count > 0u) ? -qasm_polynomial_high(value) : 0ll;
    const long status = qasm_polynomial_alloc(low, value->count, conjugate, error);
    for (unsigned int index = 0u; (status == 0L) && (index < value->count); index += 1u)
    {
        qasm_number_conjugate(&value->coefficients[value->count - 1u - index], &conjugate->coefficients[index]);
    }
    return status;
}

long qasm_rational_function_conjugate(const QasmRationalFunction *value, QasmRationalFunction *conjugate,
                                      EngineError *error)
{
    QasmPolynomial numerator = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial denominator = QASM_POLYNOMIAL_EMPTY;
    QasmRationalFunction result = QASM_FUNCTION_EMPTY;
    long status = qasm_polynomial_conjugate(&value->numerator, &numerator, error);
    status = (status == 0L) ? qasm_polynomial_conjugate(&value->denominator, &denominator, error) : status;
    status = (status == 0L) ? qasm_function_make(&numerator, &denominator, &result, error) : status;
    qasm_polynomial_release(&numerator);
    qasm_polynomial_release(&denominator);
    return qasm_function_install(status, &result, conjugate);
}

static int qasm_polynomial_equal(const QasmPolynomial *left, const QasmPolynomial *right)
{
    if (left->count != right->count)
    {
        return 0;
    }
    int equal = (left->count == 0u) || (left->low == right->low);
    for (unsigned int index = 0u; (equal != 0) && (index < left->count); index += 1u)
    {
        equal = qasm_number_equal(&left->coefficients[index], &right->coefficients[index]);
    }
    return equal;
}

int qasm_rational_function_equal(const QasmRationalFunction *left, const QasmRationalFunction *right)
{
    return qasm_polynomial_equal(&left->numerator, &right->numerator) &&
           qasm_polynomial_equal(&left->denominator, &right->denominator);
}

int qasm_rational_function_is_zero(const QasmRationalFunction *value)
{
    return value->numerator.count == 0u;
}

// the polynomial at w = omega: the sum of c_j omega^(low + j), the powers built up from one
static long qasm_polynomial_evaluate(const QasmPolynomial *polynomial, const QasmNumber *omega, QasmNumber *result,
                                     EngineError *error)
{
    if (QASM_CHECK((polynomial->count == 0u) || (polynomial->low >= 0), polynomial, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    QasmNumber power = qasm_number_one;
    QasmNumber sum = qasm_number_zero;
    long status = 0L;
    for (int step = 0; (status == 0L) && (step < polynomial->low); step += 1)
    {
        status = qasm_number_multiply(&power, omega, &power, error);
    }
    // no power past the highest is formed: rat_eval never forms one, and it could pass the width where the value fits
    for (unsigned int index = 0u; (status == 0L) && (index < polynomial->count); index += 1u)
    {
        QasmNumber term;
        status = (index > 0u) ? qasm_number_multiply(&power, omega, &power, error) : 0L;
        status = (status == 0L) ? qasm_number_multiply(&polynomial->coefficients[index], &power, &term, error) : status;
        status = (status == 0L) ? qasm_number_add(&sum, &term, &sum, error) : status;
    }
    if (status == 0L)
    {
        *result = sum;
    }
    return status;
}

long qasm_rational_function_evaluate(const QasmRationalFunction *value, const QasmNumber *omega, QasmNumber *result,
                                     EngineError *error)
{
    QasmNumber numerator;
    QasmNumber denominator;
    QasmNumber inverse;
    long status = qasm_polynomial_evaluate(&value->numerator, omega, &numerator, error);
    status = (status == 0L) ? qasm_polynomial_evaluate(&value->denominator, omega, &denominator, error) : status;
    status = (status == 0L) ? qasm_number_invert(&denominator, &inverse, error) : status;
    status = (status == 0L) ? qasm_number_multiply(&numerator, &inverse, result, error) : status;
    return status;
}

// p_str: each nonzero term by ascending power, "c", "w", "(c)w", "w^e" or "(c)w^e", joined by " + "
static long qasm_polynomial_text(const QasmPolynomial *polynomial, QasmText *builder, EngineError *error)
{
    if (polynomial->count == 0u)
    {
        return (qasm_symbolic_text_put(builder, "0") != 0) ? 0L : QASM_ERROR;
    }
    char piece[QASM_NUMBER_TEXT_CAPACITY];
    int first = 1;
    int ok = 1;
    for (unsigned int index = 0u; (ok != 0) && (index < polynomial->count); index += 1u)
    {
        if (!qasm_number_is_zero(&polynomial->coefficients[index]))
        {
            // index is below the count, and low + index is within the exponent bound the allocation checked
            const int exponent = polynomial->low + (int)index;
            ok = (qasm_number_short_text(&polynomial->coefficients[index], piece, sizeof(piece), error) == 0L) &&
                 ((first != 0) || qasm_symbolic_text_put(builder, " + "));
            first = 0;
            const int unit = (strcmp(piece, "1") == 0);
            if ((ok != 0) && (exponent == 0))
            {
                ok = qasm_symbolic_text_put(builder, piece);
            }
            else if (ok != 0)
            {
                ok = (unit || (qasm_symbolic_text_put(builder, "(") && qasm_symbolic_text_put(builder, piece) &&
                               qasm_symbolic_text_put(builder, ")"))) &&
                     qasm_symbolic_text_put(builder, "w") &&
                     ((exponent == 1) ||
                      (qasm_symbolic_text_put(builder, "^") && qasm_text_exponent(builder, exponent)));
            }
        }
    }
    return (ok != 0) ? 0L : QASM_ERROR;
}

long qasm_rational_function_text(const QasmRationalFunction *value, char *text, size_t capacity, EngineError *error)
{
    if (QASM_CHECK((value != NULL) && (text != NULL) && (capacity > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    text[0] = '\0';
    QasmText builder = {text, capacity, 0u, 1};
    const int is_polynomial = qasm_polynomial_equal(&value->denominator, &qasm_symbolic_one.denominator);
    int ok = 1;
    if (is_polynomial != 0)
    {
        ok = (qasm_polynomial_text(&value->numerator, &builder, error) == 0L);
    }
    else
    {
        ok =
            qasm_symbolic_text_put(&builder, "(") && (qasm_polynomial_text(&value->numerator, &builder, error) == 0L) &&
            qasm_symbolic_text_put(&builder, ") / (") &&
            (qasm_polynomial_text(&value->denominator, &builder, error) == 0L) && qasm_symbolic_text_put(&builder, ")");
    }
    return (QASM_CHECK(ok && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_ERROR;
}

static long qasm_function_field_copy(const void *from, void *to, EngineError *error)
{
    return qasm_rational_function_copy((const QasmRationalFunction *)from, (QasmRationalFunction *)to, error);
}

static void qasm_function_field_release(void *element)
{
    qasm_function_release_parts((QasmRationalFunction *)element);
}

static long qasm_function_field_add(const void *left, const void *right, void *sum, EngineError *error)
{
    return qasm_rational_function_add((const QasmRationalFunction *)left, (const QasmRationalFunction *)right,
                                      (QasmRationalFunction *)sum, error);
}

static long qasm_function_field_subtract(const void *left, const void *right, void *difference, EngineError *error)
{
    return qasm_rational_function_subtract((const QasmRationalFunction *)left, (const QasmRationalFunction *)right,
                                           (QasmRationalFunction *)difference, error);
}

static long qasm_function_field_multiply(const void *left, const void *right, void *product, EngineError *error)
{
    return qasm_rational_function_multiply((const QasmRationalFunction *)left, (const QasmRationalFunction *)right,
                                           (QasmRationalFunction *)product, error);
}

static long qasm_function_field_invert(const void *value, void *inverse, EngineError *error)
{
    return qasm_rational_function_invert((const QasmRationalFunction *)value, (QasmRationalFunction *)inverse, error);
}

static long qasm_function_field_conjugate(const void *value, void *conjugate, EngineError *error)
{
    return qasm_rational_function_conjugate((const QasmRationalFunction *)value, (QasmRationalFunction *)conjugate,
                                            error);
}

static int qasm_function_field_is_zero(const void *value)
{
    return qasm_rational_function_is_zero((const QasmRationalFunction *)value);
}

const QasmField qasm_rational_function_field = {
    sizeof(QasmRationalFunction),  &qasm_symbolic_zero,          &qasm_symbolic_one,
    qasm_function_field_copy,      qasm_function_field_release,  qasm_function_field_add,
    qasm_function_field_subtract,  qasm_function_field_multiply, qasm_function_field_invert,
    qasm_function_field_conjugate, qasm_function_field_is_zero};
