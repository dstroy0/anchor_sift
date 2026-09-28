// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_exact_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_EXACT_TEST_INTERNAL_H
#define QASM_EXACT_TEST_INTERNAL_H

// The four Python models' demonstrations, run on the port, each result checked against the value the Python printed
// (exact_qubits.py, mps_qubits.py, symbolic_qubits.py and boundary_lens.py 13 13 8 6 2024 1 16 30).
#include "qasm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} QasmResults;

void qasm_test_check(QasmResults *results, int passed, const char *claim);

int qasm_test_short_is(const QasmNumber *value, const char *expected, EngineError *error);

int qasm_test_function_is(const QasmRationalFunction *value, const char *expected, EngineError *error);

int qasm_test_clean(const EngineError *error);

int qasm_test_error_here(long status, const EngineError *error);

extern QasmNumber qasm_test_hadamard[4];

extern QasmNumber qasm_test_cnot[16];

extern QasmNumber qasm_test_controlled_t[16];

extern QasmNumber qasm_test_controlled_t_back[16];

void qasm_test_gates(void);

// one build runs on the chain or on the dense state. The two can be compared amplitude for amplitude
typedef struct
{
    QasmChain *chain;
    QasmDense *dense;
} QasmTestTarget;

long qasm_test_one(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error);

long qasm_test_two(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error);

long qasm_test_ghz(const QasmTestTarget *target, unsigned int sites, EngineError *error);

long qasm_test_ghz_t(const QasmTestTarget *target, unsigned int sites, EngineError *error);

long qasm_test_scrambler(const QasmTestTarget *target, unsigned int sites, unsigned int depth, EngineError *error);

long qasm_test_scrambler_six(const QasmTestTarget *target, unsigned int sites, EngineError *error);

int qasm_test_bonds_are(const QasmChain *chain, const unsigned int *bonds);

void qasm_test_bits(unsigned long long index, unsigned int sites, unsigned char *bits);

int qasm_test_amplitude_is(const QasmChain *chain, unsigned int value, const char *expected, EngineError *error);

int qasm_test_norm_is_one(const QasmChain *chain, EngineError *error);

void qasm_test_exact_qubits(QasmResults *results);

typedef long (*QasmTestBuild)(const QasmTestTarget *target, unsigned int sites, EngineError *error);

int qasm_test_cross(QasmTestBuild build, EngineError *error);

// the symbolic gates and observables, as symbolic_qubits.py builds them over a field
typedef struct
{
    QasmRationalFunction hadamard[4];
    QasmRationalFunction cnot[16];
    QasmRationalFunction cphase[16];
    QasmRationalFunction identity[4];
    QasmRationalFunction pauli_x[4];
    QasmRationalFunction pauli_z[4];
    QasmRationalFunction local_phase[4];
    QasmRationalFunction omega;
} QasmTestSymbols;

#endif
