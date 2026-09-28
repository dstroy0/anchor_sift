// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_symbolic_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_SYMBOLIC_INTERNAL_H
#define QASM_SYMBOLIC_INTERNAL_H

#include "qasm.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define QASM_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_),   \
                       (error_))

// Every exponent a polynomial holds stays within this bound. A sum of two, or a shift by one, fits an int.
#define QASM_EXPONENT_MAX (INT_MAX / 4)

#define QASM_POLYNOMIAL_EMPTY {0, 0u, NULL}

#define QASM_FUNCTION_EMPTY {QASM_POLYNOMIAL_EMPTY, QASM_POLYNOMIAL_EMPTY}

typedef struct
{
    char *text;
    size_t capacity;
    size_t length;
    int fits;
} QasmText;

int qasm_symbolic_text_put(QasmText *builder, const char *piece);

int qasm_text_exponent(QasmText *builder, int exponent);

void qasm_polynomial_release(QasmPolynomial *polynomial);

long qasm_polynomial_alloc(long long low, unsigned long long count, QasmPolynomial *polynomial, EngineError *error);

void qasm_polynomial_trim(QasmPolynomial *polynomial);

long qasm_polynomial_copy(const QasmPolynomial *from, QasmPolynomial *to, EngineError *error);

long long qasm_polynomial_high(const QasmPolynomial *polynomial);

long qasm_polynomial_add(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *sum,
                         EngineError *error);

long qasm_polynomial_negate(const QasmPolynomial *value, QasmPolynomial *negated, EngineError *error);

long qasm_polynomial_multiply(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *product,
                              EngineError *error);

long qasm_polynomial_scale(const QasmPolynomial *value, const QasmNumber *scalar, QasmPolynomial *scaled,
                           EngineError *error);

long qasm_polynomial_divide(const QasmPolynomial *numerator, const QasmPolynomial *divisor, QasmPolynomial *quotient,
                            QasmPolynomial *remainder, EngineError *error);

long qasm_polynomial_gcd(const QasmPolynomial *left, const QasmPolynomial *right, QasmPolynomial *divisor,
                         EngineError *error);

void qasm_function_release_parts(QasmRationalFunction *value);

#endif
