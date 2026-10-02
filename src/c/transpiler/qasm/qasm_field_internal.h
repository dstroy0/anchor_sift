// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_field_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_FIELD_INTERNAL_H
#define QASM_FIELD_INTERNAL_H

#include "qasm.h"

#include <string.h>

_Static_assert(ANCHOR_EXACT_LIMBS >= 2u, "qasm: a rational set from a long long needs two limbs");
_Static_assert(ANCHOR_EXACT_LIMBS <= 0xFFFFFFFFull, "qasm: a number's bytes count its used limbs in 32 bits");

// an exact status enumerates small non-negative codes. It converts to int exactly
#define QASM_STATUS_CHECK(status_, evacaddr_, error_)                                                                  \
    engine_status_check((int)(status_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define QASM_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_),   \
                       (error_))

// 10^9 exceeds 2^29. Each decimal chunk takes at least 29 of the width's bits
#define QASM_TEXT_CHUNKS (((unsigned long long)(ANCHOR_EXACT_BITS) / 29ull) + 2ull)

#define QASM_TEXT_CHUNK 1000000000u

#define QASM_TEXT_CHUNK_DIGITS 9u

#define QASM_RATIONAL_MINUS_ONE_INITIALIZER {{{1u}, -1}, {{1u}, 1}}

#define QASM_RATIONAL_HALF_INITIALIZER {{{1u}, 1}, {{2u}, 1}}

#define QASM_RATIONAL_MINUS_HALF_INITIALIZER {{{1u}, -1}, {{2u}, 1}}

static const QasmRational qasm_rational_one = QASM_RATIONAL_ONE_INITIALIZER;

typedef struct
{
    char *text;
    size_t capacity;
    size_t length;
    int fits;
} QasmText;

int qasm_text_put(QasmText *builder, const char *piece);

long qasm_rational_put_text(const QasmRational *value, QasmText *builder, EngineError *error);

long qasm_rational_add(const QasmRational *left, const QasmRational *right, QasmRational *sum, EngineError *error);

long qasm_rational_subtract(const QasmRational *left, const QasmRational *right, QasmRational *difference,
                            EngineError *error);

long qasm_rational_multiply(const QasmRational *left, const QasmRational *right, QasmRational *product,
                            EngineError *error);

long qasm_rational_divide(const QasmRational *numerator, const QasmRational *divisor, QasmRational *quotient,
                          EngineError *error);

void qasm_rational_negate(const QasmRational *value, QasmRational *negated);

int qasm_rational_equal(const QasmRational *left, const QasmRational *right);

int qasm_rational_is_zero(const QasmRational *value);

long qasm_real_add(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *sum, EngineError *error);

void qasm_real_negate(const QasmRealNumber *value, QasmRealNumber *negated);

long qasm_real_subtract(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *difference,
                        EngineError *error);

long qasm_real_multiply(const QasmRealNumber *left, const QasmRealNumber *right, QasmRealNumber *product,
                        EngineError *error);

#endif
