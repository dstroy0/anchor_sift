// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_chain_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_CHAIN_INTERNAL_H
#define QASM_CHAIN_INTERNAL_H

#include "../../engine/runtime/obsignatio/obsignatio.h"
#include "qasm.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define QASM_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_),   \
                       (error_))

#define QASM_MATRIX_EMPTY {NULL, 0u, 0u, NULL}

// room for one element of either field, for a temporary
typedef union {
    QasmNumber number;
    QasmRationalFunction function;
} QasmSlot;

unsigned char *qasm_matrix_at(const QasmMatrix *matrix, unsigned int row, unsigned int column);

const void *qasm_element_at(const QasmField *field, const void *elements, size_t index);

void qasm_matrix_release(QasmMatrix *matrix);

long qasm_matrix_alloc(const QasmField *field, unsigned int rows, unsigned int columns, QasmMatrix *matrix,
                       EngineError *error);

long qasm_matrix_copy(const QasmMatrix *from, QasmMatrix *to, EngineError *error);

long qasm_matrix_multiply(const QasmMatrix *left, const QasmMatrix *right, QasmMatrix *product, EngineError *error);

long qasm_matrix_conjugate_transpose(const QasmMatrix *matrix, QasmMatrix *dagger, EngineError *error);

long qasm_matrix_factor(const QasmMatrix *matrix, QasmMatrix *pivot_columns, QasmMatrix *reduced_rows,
                        EngineError *error);

#endif
