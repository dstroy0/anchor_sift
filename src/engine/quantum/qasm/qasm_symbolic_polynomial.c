// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_symbolic_polynomial.c: polynomials
#include "qasm_symbolic_internal.h"

int qasm_symbolic_text_put(QasmText *builder, const char *piece)
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

int qasm_text_exponent(QasmText *builder, int exponent)
{
    char digits[16];
    unsigned int length = 0u;
    // the magnitude is taken in unsigned arithmetic, where negating INT_MIN is defined
    unsigned int left = (exponent < 0) ? (0u - (unsigned int)exponent) : (unsigned int)exponent;
    digits[15] = '\0';
    do
    {
        // a digit is 0 to 9. '0' plus it is an ASCII digit, which a char holds
        digits[14u - length] = (char)('0' + (int)(left % 10u));
        left /= 10u;
        length += 1u;
    } while (left != 0u);
    if (exponent < 0)
    {
        digits[14u - length] = '-';
        length += 1u;
    }
    return qasm_symbolic_text_put(builder, &digits[15u - length]);
}

void qasm_polynomial_release(QasmPolynomial *polynomial)
{
    free(polynomial->coefficients);
    polynomial->coefficients = NULL;
    polynomial->count = 0u;
    polynomial->low = 0;
}

// the powers low .. low + count - 1, every coefficient zero; the polynomial is empty on a refusal
long qasm_polynomial_alloc(long long low, unsigned long long count, QasmPolynomial *polynomial, EngineError *error)
{
    polynomial->low = 0;
    polynomial->count = 0u;
    polynomial->coefficients = NULL;
    // the bound is a positive int. It widens to long long exactly and re-signs to unsigned long long exactly
    const long long maximum = (long long)QASM_EXPONENT_MAX;
    const int count_ok = (count <= (unsigned long long)maximum);
    // read only once the count is within the bound, below 2^31. It re-signs to long long exactly
    const long long high = count_ok ? (low + (long long)((count > 0ull) ? (count - 1ull) : 0ull)) : 0ll;
    const int ok = count_ok && (low >= -maximum) && (high <= maximum);
    if (QASM_CHECK(ok, polynomial, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_ERROR;
    }
    if (count == 0ull)
    {
        return 0L;
    }
    // the count is within the exponent bound, below 2^31. It fits in a size_t
    QasmNumber *const coefficients = (QasmNumber *)malloc((size_t)count * sizeof(QasmNumber));
    if (QASM_CHECK(coefficients != NULL, polynomial, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_ERROR;
    }
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        coefficients[index] = qasm_number_zero;
    }
    // low and count are within the exponent bound, checked above. Each fits its narrower type
    polynomial->low = (int)low;
    polynomial->count = (unsigned int)count;
    polynomial->coefficients = coefficients;
    return 0L;
}

// the zero coefficients at both ends dropped; none left is the zero polynomial
void qasm_polynomial_trim(QasmPolynomial *polynomial)
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

long qasm_polynomial_copy(const QasmPolynomial *from, QasmPolynomial *to, EngineError *error)
{
    const long status = qasm_polynomial_alloc(from->low, from->count, to, error);
    for (unsigned int index = 0u; (status == 0L) && (index < from->count); index += 1u)
    {
        to->coefficients[index] = from->coefficients[index];
    }
    return status;
}

long long qasm_polynomial_high(const QasmPolynomial *polynomial)
{
    // an int widens to long long exactly, and the count, below 2^31 by the exponent bound, re-signs to it exactly
    return (long long)polynomial->low + (long long)polynomial->count - 1ll;
}

long qasm_polynomial_add(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *sum,
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
    // high is at least low. The count is positive
    long status = qasm_polynomial_alloc(low, (unsigned long long)((high - low) + 1ll), sum, error);
    for (unsigned int index = 0u; (status == 0L) && (index < left->count); index += 1u)
    {
        // the offset is the difference of two exponents, low the smaller. It is non-negative and below the count
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

long qasm_polynomial_negate(const QasmPolynomial *value, QasmPolynomial *negated, EngineError *error)
{
    const long status = qasm_polynomial_copy(value, negated, error);
    for (unsigned int index = 0u; (status == 0L) && (index < negated->count); index += 1u)
    {
        qasm_number_negate(&negated->coefficients[index], &negated->coefficients[index]);
    }
    return status;
}

long qasm_polynomial_multiply(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *product,
                              EngineError *error)
{
    if ((left->count == 0u) || (right->count == 0u))
    {
        return qasm_polynomial_alloc(0, 0ull, product, error);
    }
    // unsigned int counts widen to unsigned long long exactly, and int lows to long long. Neither sum wraps
    const unsigned long long count = (unsigned long long)left->count + (unsigned long long)right->count - 1ull;
    long status = qasm_polynomial_alloc((long long)left->low + (long long)right->low, count, product, error);
    for (unsigned int outer = 0u; (status == 0L) && (outer < left->count); outer += 1u)
    {
        for (unsigned int inner = 0u; (status == 0L) && (inner < right->count); inner += 1u)
        {
            QasmNumber term;
            // outer widens to size_t exactly. The sum of the two indices cannot wrap an unsigned int
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

long qasm_polynomial_scale(const QasmPolynomial *value, const QasmNumber *scalar, QasmPolynomial *scaled,
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
long qasm_polynomial_divide(const QasmPolynomial *numerator, const QasmPolynomial *divisor, QasmPolynomial *quotient,
                            QasmPolynomial *remainder, EngineError *error)
{
    const int ok = (divisor->count > 0u) && (divisor->low >= 0) && ((numerator->count == 0u) || (numerator->low >= 0));
    if (QASM_CHECK(ok, numerator, error, ENGINE_ERROR_LOGIC) == 0)
    {
        return QASM_ERROR;
    }
    if (numerator->count == 0u)
    {
        const long status = qasm_polynomial_alloc(0, 0ull, quotient, error);
        return (status == 0L) ? qasm_polynomial_alloc(0, 0ull, remainder, error) : status;
    }
    const long long numerator_degree = qasm_polynomial_high(numerator);
    const long long divisor_degree = qasm_polynomial_high(divisor);
    // the difference is taken only where the numerator's degree is at least the divisor's. It re-signs exactly
    const unsigned long long quotient_count =
        (numerator_degree >= divisor_degree) ? (unsigned long long)((numerator_degree - divisor_degree) + 1ll) : 0ull;
    // the degree is non-negative here. The power count is positive
    long status = qasm_polynomial_alloc(0, (unsigned long long)numerator_degree + 1ull, remainder, error);
    status = (status == 0L) ? qasm_polynomial_alloc(0, quotient_count, quotient, error) : status;
    for (unsigned int index = 0u; (status == 0L) && (index < numerator->count); index += 1u)
    {
        // the numerator's lowest power is non-negative, held above. It re-signs to size_t exactly
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
            // the loop keeps the degree at or above the divisor's. The shift is non-negative
            const size_t shift = (size_t)(degree - divisor_degree);
            status = qasm_number_multiply(&remainder->coefficients[at], &leading_inverse, &coefficient, error);
            status = (status == 0L) ? qasm_number_add(&quotient->coefficients[shift], &coefficient,
                                                      &quotient->coefficients[shift], error)
                                    : status;
            for (unsigned int index = 0u; (status == 0L) && (index < divisor->count); index += 1u)
            {
                QasmNumber term;
                // the divisor's lowest power is non-negative, held above. It re-signs to size_t exactly
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
long qasm_polynomial_gcd(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *divisor,
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

void qasm_function_release_parts(QasmRationalFunction *value)
{
    qasm_polynomial_release(&value->numerator);
    qasm_polynomial_release(&value->denominator);
}
