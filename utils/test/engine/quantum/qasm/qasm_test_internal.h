// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_TEST_INTERNAL_H
#define QASM_TEST_INTERNAL_H

#include "qasm.h"

#include "exact_integer.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// qasm_test <fixture directory>: errors by line and column, known answers on the device and the host, the
// bound's formula, the probabilities within the proved slack of their true values, and the device against the
// host word for word.

#define TEXT_CAPACITY (1u << 20u)

extern unsigned int g_passed;

extern unsigned int g_failed;

void check(int passed, const char *format, ...);

static const char HEADER[] = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\n";

typedef struct
{
    char *text;
    size_t length;
} Text;

void text_add(Text *text, const char *format, ...);

int read_text(const char *name, const char *text, QasmCircuit *circuit, char *reason, size_t capacity);

int run(const QasmCircuit *circuit, int on_host, QasmOutcome *outcome, unsigned int *state);

int within(const unsigned int units[QASM_WIDE_LIMBS], unsigned int num, unsigned int shift,
           const unsigned int slack_units[QASM_WIDE_LIMBS]);

int units_are_power(const unsigned int units[QASM_WIDE_LIMBS], unsigned int shift);

// ---------------------------------------------------------------------------------------------------------------

typedef struct
{
    const char *body;
    unsigned int qubits;
    const char *expected;
} KnownAnswer;

void known_answers(void);

// ---------------------------------------------------------------------------------------------------------------

typedef struct
{
    const char *body;
    const char *prefix;
    const char *fragment;
} Error;

void errors(void);

void ties(void);

void bound_formula(void);

#endif
