// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define QASM_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// Every exponent a polynomial holds stays within this bound, so a sum of two, or a shift by one, fits an int.
#define QASM_EXPONENT_MOST (INT_MAX / 4)

#define QASM_POLYNOMIAL_EMPTY {0, 0u, NULL}

#define QASM_FUNCTION_EMPTY {QASM_POLYNOMIAL_EMPTY, QASM_POLYNOMIAL_EMPTY}

// the coefficient the field's zero and one point at; nothing writes it, and nothing releases it
static QasmNumber qasm_symbolic_unit = QASM_NUMBER_ONE_INITIALIZER;

static const QasmRationalFunction qasm_symbolic_zero = {{0, 0u, NULL}, {0, 1u, &qasm_symbolic_unit}};

static const QasmRationalFunction qasm_symbolic_one = {{0, 1u, &qasm_symbolic_unit}, {0, 1u, &qasm_symbolic_unit}};

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

static int qasm_text_exponent(QasmText *builder, int exponent)
{
    char digits[16];
    unsigned int length = 0u;
    // the magnitude is taken in unsigned arithmetic, where negating INT_MIN is defined
    unsigned int left = (exponent < 0) ? (0u - (unsigned int)exponent) : (unsigned int)exponent;
    digits[15] = '\0';
    do
    {
        // a digit is 0 to 9, so '0' plus it is an ASCII digit, which a char holds
        digits[14u - length] = (char)('0' + (int)(left % 10u));
        left /= 10u;
        length += 1u;
    } while (left != 0u);
    if (exponent < 0)
    {
        digits[14u - length] = '-';
        length += 1u;
    }
    return qasm_text_put(builder, &digits[15u - length]);
}

static void qasm_polynomial_release(QasmPolynomial *polynomial)
{
    free(polynomial->coefficients);
    polynomial->coefficients = NULL;
    polynomial->count = 0u;
    polynomial->low = 0;
}

// the powers low .. low + count - 1, every coefficient zero; the polynomial is empty on a refusal
static long qasm_polynomial_alloc(long long low, unsigned long long count, QasmPolynomial *polynomial,
                                  EngineError *error)
{
    polynomial->low = 0;
    polynomial->count = 0u;
    polynomial->coefficients = NULL;
    // the bound is a positive int, so it widens to long long exactly and re-signs to unsigned long long exactly
    const long long most = (long long)QASM_EXPONENT_MOST;
    const int count_held = (count <= (unsigned long long)most);
    // read only once the count is within the bound, below 2^31, so it re-signs to long long exactly
    const long long high = count_held ? (low + (long long)((count > 0ull) ? (count - 1ull) : 0ull)) : 0ll;
    const int held = count_held && (low >= -most) && (high <= most);
    if (QASM_HELD(held, polynomial, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    if (count == 0ull)
    {
        return 0L;
    }
    // the count is within the exponent bound, below 2^31, so it is held whole in a size_t
    QasmNumber *const coefficients = (QasmNumber *)malloc((size_t)count * sizeof(QasmNumber));
    if (QASM_HELD(coefficients != NULL, polynomial, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_REFUSED;
    }
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        coefficients[index] = qasm_number_zero;
    }
    // low and count are within the exponent bound, checked above, so each fits its narrower type
    polynomial->low = (int)low;
    polynomial->count = (unsigned int)count;
    polynomial->coefficients = coefficients;
    return 0L;
}

// the zero coefficients at both ends dropped; none left is the zero polynomial
static void qasm_polynomial_trim(QasmPolynomial *polynomial)
{
    unsigned int first = 0u;
    while ((first < polynomial->count) && qasm_number_is_zero(&polynomial->coefficients[first]))
    {
        first += 1u;
    }
    if (first == polynomial->count)
    {
        qasm_polynomial_release(polynomial);
        return;
    }
    unsigned int last = polynomial->count - 1u;
    while (qasm_number_is_zero(&polynomial->coefficients[last]))
    {
        last -= 1u;
    }
    const unsigned int kept = (last - first) + 1u;
    if (first > 0u)
    {
        // an unsigned int count widens to size_t exactly
        memmove(&polynomial->coefficients[0], &polynomial->coefficients[first], (size_t)kept * sizeof(QasmNumber));
    }
    // first is below the count, and low + first stays within the exponent bound the allocation checked
    polynomial->low += (int)first;
    polynomial->count = kept;
}

static long qasm_polynomial_copy(const QasmPolynomial *from, QasmPolynomial *to, EngineError *error)
{
    const long status = qasm_polynomial_alloc(from->low, from->count, to, error);
    for (unsigned int index = 0u; (status == 0L) && (index < from->count); index += 1u)
    {
        to->coefficients[index] = from->coefficients[index];
    }
    return status;
}

static long long qasm_polynomial_high(const QasmPolynomial *polynomial)
{
    // an int widens to long long exactly, and the count, below 2^31 by the exponent bound, re-signs to it exactly
    return (long long)polynomial->low + (long long)polynomial->count - 1ll;
}

static long qasm_polynomial_add(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *sum,
                                EngineError *error)
{
    if (left->count == 0u)
    {
        return qasm_polynomial_copy(right, sum, error);
    }
    if (right->count == 0u)
    {
        return qasm_polynomial_copy(left, sum, error);
    }
    const long long low = (left->low < right->low) ? left->low : right->low;
    const long long left_high = qasm_polynomial_high(left);
    const long long right_high = qasm_polynomial_high(right);
    const long long high = (left_high > right_high) ? left_high : right_high;
    // high is at least low, so the count is positive
    long status = qasm_polynomial_alloc(low, (unsigned long long)((high - low) + 1ll), sum, error);
    for (unsigned int index = 0u; (status == 0L) && (index < left->count); index += 1u)
    {
        // the offset is the difference of two exponents, low the smaller, so it is non-negative and below the count
        QasmNumber *const at = &sum->coefficients[(size_t)((left->low - low) + index)];
        status = qasm_number_add(at, &left->coefficients[index], at, error);
    }
    for (unsigned int index = 0u; (status == 0L) && (index < right->count); index += 1u)
    {
        // as above
        QasmNumber *const at = &sum->coefficients[(size_t)((right->low - low) + index)];
        status = qasm_number_add(at, &right->coefficients[index], at, error);
    }
    if (status == 0L)
    {
        qasm_polynomial_trim(sum);
    }
    return status;
}

static long qasm_polynomial_negate(const QasmPolynomial *value, QasmPolynomial *negated, EngineError *error)
{
    const long status = qasm_polynomial_copy(value, negated, error);
    for (unsigned int index = 0u; (status == 0L) && (index < negated->count); index += 1u)
    {
        qasm_number_negate(&negated->coefficients[index], &negated->coefficients[index]);
    }
    return status;
}

static long qasm_polynomial_multiply(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *product,
                                     EngineError *error)
{
    if ((left->count == 0u) || (right->count == 0u))
    {
        return qasm_polynomial_alloc(0, 0ull, product, error);
    }
    // unsigned int counts widen to unsigned long long exactly, and int lows to long long, so neither sum wraps
    const unsigned long long count = (unsigned long long)left->count + (unsigned long long)right->count - 1ull;
    long status = qasm_polynomial_alloc((long long)left->low + (long long)right->low, count, product, error);
    for (unsigned int outer = 0u; (status == 0L) && (outer < left->count); outer += 1u)
    {
        for (unsigned int inner = 0u; (status == 0L) && (inner < right->count); inner += 1u)
        {
            QasmNumber term;
            // outer widens to size_t exactly, so the sum of the two indices cannot wrap an unsigned int
            QasmNumber *const at = &product->coefficients[(size_t)outer + inner];
            status = qasm_number_multiply(&left->coefficients[outer], &right->coefficients[inner], &term, error);
            status = (status == 0L) ? qasm_number_add(at, &term, at, error) : status;
        }
    }
    if (status == 0L)
    {
        qasm_polynomial_trim(product);
    }
    return status;
}

static long qasm_polynomial_scale(const QasmPolynomial *value, const QasmNumber *scalar, QasmPolynomial *scaled,
                                  EngineError *error)
{
    long status = qasm_polynomial_copy(value, scaled, error);
    for (unsigned int index = 0u; (status == 0L) && (index < scaled->count); index += 1u)
    {
        status = qasm_number_multiply(&scaled->coefficients[index], scalar, &scaled->coefficients[index], error);
    }
    if (status == 0L)
    {
        qasm_polynomial_trim(scaled);
    }
    return status;
}

// p_divmod: ordinary polynomials, no negative power in either, the divisor nonzero
static long qasm_polynomial_divide(const QasmPolynomial *numerator, const QasmPolynomial *divisor,
                                   QasmPolynomial *quotient, QasmPolynomial *remainder, EngineError *error)
{
    const int held = (divisor->count > 0u) && (divisor->low >= 0) && ((numerator->count == 0u) || (numerator->low >= 0));
    if (QASM_HELD(held, numerator, error, ENGINE_ERROR_LOGIC) == 0)
    {
        return QASM_REFUSED;
    }
    if (numerator->count == 0u)
    {
        const long status = qasm_polynomial_alloc(0, 0ull, quotient, error);
        return (status == 0L) ? qasm_polynomial_alloc(0, 0ull, remainder, error) : status;
    }
    const long long numerator_degree = qasm_polynomial_high(numerator);
    const long long divisor_degree = qasm_polynomial_high(divisor);
    // the difference is taken only where the numerator's degree is at least the divisor's, so it re-signs exactly
    const unsigned long long quotient_count = (numerator_degree >= divisor_degree)
                                                  ? (unsigned long long)((numerator_degree - divisor_degree) + 1ll)
                                                  : 0ull;
    // the degree is non-negative here, so the power count is positive
    long status = qasm_polynomial_alloc(0, (unsigned long long)numerator_degree + 1ull, remainder, error);
    status = (status == 0L) ? qasm_polynomial_alloc(0, quotient_count, quotient, error) : status;
    for (unsigned int index = 0u; (status == 0L) && (index < numerator->count); index += 1u)
    {
        // the numerator's lowest power is non-negative, held above, so it re-signs to size_t exactly
        remainder->coefficients[(size_t)numerator->low + index] = numerator->coefficients[index];
    }
    QasmNumber leading_inverse;
    status = (status == 0L) ? qasm_number_invert(&divisor->coefficients[divisor->count - 1u], &leading_inverse, error)
                            : status;
    for (long long degree = numerator_degree; (status == 0L) && (degree >= divisor_degree); degree -= 1ll)
    {
        // a degree here is between the divisor's and the numerator's, both within the remainder's count
        const size_t at = (size_t)degree;
        if (!qasm_number_is_zero(&remainder->coefficients[at]))
        {
            QasmNumber coefficient;
            // the loop keeps the degree at or above the divisor's, so the shift is non-negative
            const size_t shift = (size_t)(degree - divisor_degree);
            status = qasm_number_multiply(&remainder->coefficients[at], &leading_inverse, &coefficient, error);
            status = (status == 0L)
                         ? qasm_number_add(&quotient->coefficients[shift], &coefficient, &quotient->coefficients[shift],
                                           error)
                         : status;
            for (unsigned int index = 0u; (status == 0L) && (index < divisor->count); index += 1u)
            {
                QasmNumber term;
                // the divisor's lowest power is non-negative, held above, so it re-signs to size_t exactly
                QasmNumber *const target = &remainder->coefficients[(size_t)divisor->low + index + shift];
                status = qasm_number_multiply(&coefficient, &divisor->coefficients[index], &term, error);
                status = (status == 0L) ? qasm_number_subtract(target, &term, target, error) : status;
            }
        }
    }
    if (status == 0L)
    {
        qasm_polynomial_trim(quotient);
        qasm_polynomial_trim(remainder);
    }
    return status;
}

// p_gcd: Euclid's, made monic; zero where both are zero
static long qasm_polynomial_gcd(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *divisor,
                                EngineError *error)
{
    QasmPolynomial first = QASM_POLYNOMIAL_EMPTY;
    QasmPolynomial second = QASM_POLYNOMIAL_EMPTY;
    long status = qasm_polynomial_copy(left, &first, error);
    status = (status == 0L) ? qasm_polynomial_copy(right, &second, error) : status;
    while ((status == 0L) && (second.count > 0u))
    {
        QasmPolynomial quotient = QASM_POLYNOMIAL_EMPTY;
        QasmPolynomial remainder = QASM_POLYNOMIAL_EMPTY;
        status = qasm_polynomial_divide(&first, &second, &quotient, &remainder, error);
        qasm_polynomial_release(&quotient);
        qasm_polynomial_release(&first);
        first = second;
        second = remainder;
    }
    if ((status == 0L) && (first.count == 0u))
    {
        status = qasm_polynomial_alloc(0, 0ull, divisor, error);
    }
    else if (status == 0L)
    {
        QasmNumber leading_inverse;
        status = qasm_number_invert(&first.coefficients[first.count - 1u], &leading_inverse, error);
        status = (status == 0L) ? qasm_polynomial_scale(&first, &leading_inverse, divisor, error) : status;
    }
    qasm_polynomial_release(&first);
    qasm_polynomial_release(&second);
    return status;
}

static void qasm_function_release_parts(QasmRationalFunction *value)
{
    qasm_polynomial_release(&value->numerator);
    qasm_polynomial_release(&value->denominator);
}

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
    if (QASM_HELD(denominator->count > 0u, denominator, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
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
    status = (status == 0L) ? qasm_polynomial_alloc((long long)denominator->low - low, denominator->count, &bottom,
                                                    error)
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
    status = (status == 0L) ? qasm_polynomial_divide(&bottom, &common, &reduced_bottom, &bottom_remainder, error)
                            : status;
    QasmNumber leading_inverse;
    status = (status == 0L) ? qasm_number_invert(&reduced_bottom.coefficients[reduced_bottom.count - 1u],
                                                 &leading_inverse, error)
                            : status;
    status = (status == 0L) ? qasm_polynomial_scale(&reduced_top, &leading_inverse, &made->numerator, error) : status;
    status = (status == 0L) ? qasm_polynomial_scale(&reduced_bottom, &leading_inverse, &made->denominator, error)
                            : status;
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
    status = (status == 0L) ? qasm_polynomial_multiply(&right->numerator, &left->denominator, &right_cross, error)
                            : status;
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

long qasm_rational_function_invert(const QasmRationalFunction *value, QasmRationalFunction *inverse,
                                   EngineError *error)
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
    return qasm_polynomial_equal(&left->numerator, &right->numerator)
        && qasm_polynomial_equal(&left->denominator, &right->denominator);
}

int qasm_rational_function_is_zero(const QasmRationalFunction *value)
{
    return value->numerator.count == 0u;
}

// the polynomial at w = omega: the sum of c_j omega^(low + j), the powers built up from one
static long qasm_polynomial_evaluate(const QasmPolynomial *polynomial, const QasmNumber *omega, QasmNumber *result,
                                     EngineError *error)
{
    if (QASM_HELD((polynomial->count == 0u) || (polynomial->low >= 0), polynomial, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
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
        return (qasm_text_put(builder, "0") != 0) ? 0L : QASM_REFUSED;
    }
    char piece[QASM_NUMBER_TEXT_ROOM];
    int first = 1;
    int held = 1;
    for (unsigned int index = 0u; (held != 0) && (index < polynomial->count); index += 1u)
    {
        if (!qasm_number_is_zero(&polynomial->coefficients[index]))
        {
            // index is below the count, and low + index is within the exponent bound the allocation checked
            const int exponent = polynomial->low + (int)index;
            held = (qasm_number_short_text(&polynomial->coefficients[index], piece, sizeof(piece), error) == 0L)
                && ((first != 0) || qasm_text_put(builder, " + "));
            first = 0;
            const int unit = (strcmp(piece, "1") == 0);
            if ((held != 0) && (exponent == 0))
            {
                held = qasm_text_put(builder, piece);
            }
            else if (held != 0)
            {
                held = (unit || (qasm_text_put(builder, "(") && qasm_text_put(builder, piece)
                                 && qasm_text_put(builder, ")")))
                    && qasm_text_put(builder, "w")
                    && ((exponent == 1) || (qasm_text_put(builder, "^") && qasm_text_exponent(builder, exponent)));
            }
        }
    }
    return (held != 0) ? 0L : QASM_REFUSED;
}

long qasm_rational_function_text(const QasmRationalFunction *value, char *text, size_t room, EngineError *error)
{
    if (QASM_HELD((value != NULL) && (text != NULL) && (room > 0u), value, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    text[0] = '\0';
    QasmText builder = {text, room, 0u, 1};
    const int whole = qasm_polynomial_equal(&value->denominator, &qasm_symbolic_one.denominator);
    int held = 1;
    if (whole != 0)
    {
        held = (qasm_polynomial_text(&value->numerator, &builder, error) == 0L);
    }
    else
    {
        held = qasm_text_put(&builder, "(") && (qasm_polynomial_text(&value->numerator, &builder, error) == 0L)
            && qasm_text_put(&builder, ") / (") && (qasm_polynomial_text(&value->denominator, &builder, error) == 0L)
            && qasm_text_put(&builder, ")");
    }
    return (QASM_HELD(held && builder.fits, text, error, ENGINE_ERROR_REQUEST) != 0) ? 0L : QASM_REFUSED;
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
    sizeof(QasmRationalFunction), &qasm_symbolic_zero,         &qasm_symbolic_one,
    qasm_function_field_copy,     qasm_function_field_release, qasm_function_field_add,
    qasm_function_field_subtract, qasm_function_field_multiply, qasm_function_field_invert,
    qasm_function_field_conjugate, qasm_function_field_is_zero};
