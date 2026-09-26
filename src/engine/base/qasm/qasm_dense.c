// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"
#include "obsignatio.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define QASM_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

long qasm_dense_alloc(QasmDense *state, unsigned int qubits, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    if (QASM_HELD((state != NULL) && (qubits <= QASM_DENSE_QUBITS_MOST), state, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    const unsigned long long count = 1ull << qubits;
    // the count is at most 2^30, so it is held whole in a size_t on every target the room test admits
    const int room = (count <= (SIZE_MAX / sizeof(QasmNumber)));
    QasmNumber *const amplitudes = room ? (QasmNumber *)malloc((size_t)count * sizeof(QasmNumber)) : NULL;
    if (QASM_HELD(amplitudes != NULL, state, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_REFUSED;
    }
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        amplitudes[index] = qasm_number_zero;
    }
    amplitudes[0] = qasm_number_one;
    state->qubits = qubits;
    state->amplitudes = amplitudes;
    return 0L;
}

void qasm_dense_release(QasmDense *state)
{
    if (state != NULL)
    {
        free(state->amplitudes);
        state->amplitudes = NULL;
        state->qubits = 0u;
    }
}

static void qasm_dense_swap(QasmNumber *first, QasmNumber *second)
{
    const QasmNumber held = *first;
    *first = *second;
    *second = held;
}

static void qasm_dense_x(QasmDense *state, unsigned long long bit)
{
    const unsigned long long count = 1ull << state->qubits;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        if ((index & bit) == 0ull)
        {
            qasm_dense_swap(&state->amplitudes[index], &state->amplitudes[index | bit]);
        }
    }
}

static void qasm_dense_z(QasmDense *state, unsigned long long bits)
{
    const unsigned long long count = 1ull << state->qubits;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        if ((index & bits) == bits)
        {
            qasm_number_negate(&state->amplitudes[index], &state->amplitudes[index]);
        }
    }
}

static void qasm_dense_s(QasmDense *state, unsigned long long bit)
{
    const unsigned long long count = 1ull << state->qubits;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        if ((index & bit) != 0ull)
        {
            qasm_number_i_times(&state->amplitudes[index], &state->amplitudes[index]);
        }
    }
}

static long qasm_dense_h(QasmDense *state, unsigned long long bit, EngineError *error)
{
    const unsigned long long count = 1ull << state->qubits;
    long status = 0L;
    for (unsigned long long index = 0ull; (status == 0L) && (index < count); index += 1ull)
    {
        if ((index & bit) == 0ull)
        {
            QasmNumber *const low = &state->amplitudes[index];
            QasmNumber *const high = &state->amplitudes[index | bit];
            QasmNumber sum;
            QasmNumber difference;
            const int held = (qasm_number_add(low, high, &sum, error) == 0L)
                          && (qasm_number_subtract(low, high, &difference, error) == 0L)
                          && (qasm_number_half_sqrt2_times(&sum, low, error) == 0L)
                          && (qasm_number_half_sqrt2_times(&difference, high, error) == 0L);
            status = (held != 0) ? 0L : QASM_REFUSED;
        }
    }
    return status;
}

static long qasm_dense_cnot(QasmDense *state, unsigned long long control, unsigned long long target)
{
    const unsigned long long count = 1ull << state->qubits;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        if (((index & control) != 0ull) && ((index & target) == 0ull))
        {
            qasm_dense_swap(&state->amplitudes[index], &state->amplitudes[index | target]);
        }
    }
    return 0L;
}

static long qasm_dense_phase(QasmDense *state, unsigned long long bits, const QasmNumber *phase, EngineError *error)
{
    const unsigned long long count = 1ull << state->qubits;
    long status = 0L;
    for (unsigned long long index = 0ull; (status == 0L) && (index < count); index += 1ull)
    {
        if ((index & bits) == bits)
        {
            status = qasm_number_multiply(&state->amplitudes[index], phase, &state->amplitudes[index], error);
        }
    }
    return status;
}

// out = row . in over `width` entries: the sum of matrix[row][column] in[column], from zero upward
static long qasm_dense_row(const QasmNumber *matrix, unsigned int width, unsigned int row, const QasmNumber *in,
                           QasmNumber *out, EngineError *error)
{
    QasmNumber sum = qasm_number_zero;
    long status = 0L;
    for (unsigned int column = 0u; (status == 0L) && (column < width); column += 1u)
    {
        QasmNumber term;
        status = qasm_number_multiply(&matrix[(row * width) + column], &in[column], &term, error);
        status = (status == 0L) ? qasm_number_add(&sum, &term, &sum, error) : status;
    }
    if (status == 0L)
    {
        *out = sum;
    }
    return status;
}

static long qasm_dense_one_qubit(QasmDense *state, unsigned long long bit, const QasmNumber *matrix,
                                 EngineError *error)
{
    const unsigned long long count = 1ull << state->qubits;
    long status = 0L;
    for (unsigned long long index = 0ull; (status == 0L) && (index < count); index += 1ull)
    {
        if ((index & bit) == 0ull)
        {
            const QasmNumber in[2] = {state->amplitudes[index], state->amplitudes[index | bit]};
            status = qasm_dense_row(matrix, 2u, 0u, in, &state->amplitudes[index], error);
            status = (status == 0L) ? qasm_dense_row(matrix, 2u, 1u, in, &state->amplitudes[index | bit], error)
                                    : status;
        }
    }
    return status;
}

// the local index is 2 s0 + s1, s0 the bit of the first qubit and s1 the bit of the next
static long qasm_dense_two_qubit(QasmDense *state, unsigned int first, const QasmNumber *matrix, EngineError *error)
{
    const unsigned long long count = 1ull << state->qubits;
    const unsigned long long low_bit = 1ull << first;
    const unsigned long long high_bit = 1ull << (first + 1u);
    long status = 0L;
    for (unsigned long long base = 0ull; (status == 0L) && (base < count); base += 1ull)
    {
        if ((base & (low_bit | high_bit)) == 0ull)
        {
            const unsigned long long at[4] = {base, base | high_bit, base | low_bit, base | low_bit | high_bit};
            const QasmNumber in[4] = {state->amplitudes[at[0]], state->amplitudes[at[1]], state->amplitudes[at[2]],
                                      state->amplitudes[at[3]]};
            for (unsigned int row = 0u; (status == 0L) && (row < 4u); row += 1u)
            {
                status = qasm_dense_row(matrix, 4u, row, in, &state->amplitudes[at[row]], error);
            }
        }
    }
    return status;
}

long qasm_dense_apply(QasmDense *state, const QasmGate *gate, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    const int present = (state != NULL) && (state->amplitudes != NULL) && (gate != NULL);
    const int pair = present
                  && ((gate->kind == QASM_GATE_CNOT) || (gate->kind == QASM_GATE_CZ)
                      || (gate->kind == QASM_GATE_CONTROLLED_PHASE));
    const int numbered = present
                      && ((gate->kind == QASM_GATE_CONTROLLED_PHASE) || (gate->kind == QASM_GATE_ONE_QUBIT)
                          || (gate->kind == QASM_GATE_TWO_QUBIT));
    const int held = present && (gate->kind >= QASM_GATE_X) && (gate->kind <= QASM_GATE_TWO_QUBIT)
                  && (gate->first < state->qubits) && (!pair || (gate->second < state->qubits))
                  && (!numbered || (gate->numbers != NULL))
                  && ((gate->kind != QASM_GATE_TWO_QUBIT) || ((gate->first + 1u) < state->qubits));
    if (QASM_HELD(held, gate, error, ENGINE_ERROR_REQUEST) == 0)
    {
        return QASM_REFUSED;
    }
    const unsigned long long first = 1ull << gate->first;
    const unsigned long long second = pair ? (1ull << gate->second) : 0ull;
    long status = 0L;
    switch (gate->kind)
    {
        case QASM_GATE_X:
            qasm_dense_x(state, first);
            break;
        case QASM_GATE_Y:
            qasm_dense_z(state, first);
            qasm_dense_x(state, first);
            qasm_dense_s(state, first);
            break;
        case QASM_GATE_Z:
            qasm_dense_z(state, first);
            break;
        case QASM_GATE_S:
            qasm_dense_s(state, first);
            break;
        case QASM_GATE_H:
            status = qasm_dense_h(state, first, error);
            break;
        case QASM_GATE_CNOT:
            status = qasm_dense_cnot(state, first, second);
            break;
        case QASM_GATE_CZ:
            qasm_dense_z(state, first | second);
            break;
        case QASM_GATE_CONTROLLED_PHASE:
            status = qasm_dense_phase(state, first | second, gate->numbers, error);
            break;
        case QASM_GATE_ONE_QUBIT:
            status = qasm_dense_one_qubit(state, first, gate->numbers, error);
            break;
        default:
            status = qasm_dense_two_qubit(state, gate->first, gate->numbers, error);
            break;
    }
    return status;
}

long qasm_dense_norm(const QasmDense *state, QasmNumber *norm, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    if (QASM_HELD((state != NULL) && (state->amplitudes != NULL) && (norm != NULL), state, error,
                  ENGINE_ERROR_REQUEST)
        == 0)
    {
        return QASM_REFUSED;
    }
    const unsigned long long count = 1ull << state->qubits;
    QasmNumber total = qasm_number_zero;
    long status = 0L;
    for (unsigned long long index = 0ull; (status == 0L) && (index < count); index += 1ull)
    {
        QasmNumber square;
        status = qasm_number_norm(&state->amplitudes[index], &square, error);
        status = (status == 0L) ? qasm_number_add(&total, &square, &total, error) : status;
    }
    if (status == 0L)
    {
        *norm = total;
    }
    return status;
}

int qasm_dense_equal(const QasmDense *left, const QasmDense *right)
{
    if ((left->qubits != right->qubits) || (left->amplitudes == NULL) || (right->amplitudes == NULL))
    {
        return 0;
    }
    const unsigned long long count = 1ull << left->qubits;
    int equal = 1;
    for (unsigned long long index = 0ull; (equal != 0) && (index < count); index += 1ull)
    {
        equal = qasm_number_equal(&left->amplitudes[index], &right->amplitudes[index]);
    }
    return equal;
}

long qasm_dense_seal(const QasmDense *state, unsigned char *signum, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    if (QASM_HELD((state != NULL) && (state->amplitudes != NULL) && (signum != NULL), state, error,
                  ENGINE_ERROR_REQUEST)
        == 0)
    {
        return QASM_REFUSED;
    }
    const unsigned long long count = 1ull << state->qubits;
    size_t total = 0u;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        total += qasm_number_bytes(&state->amplitudes[index], NULL);
    }
    unsigned char *const bytes = (unsigned char *)malloc(total);
    if (QASM_HELD(bytes != NULL, state, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return QASM_REFUSED;
    }
    size_t at = 0u;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        at += qasm_number_bytes(&state->amplitudes[index], &bytes[at]);
    }
    const ObsignatioSealRequest request = {bytes, total, signum, error};
    const long sealed = obsignatio_seal(&request);
    free(bytes);
    return (sealed == 0L) ? 0L : QASM_REFUSED;
}
