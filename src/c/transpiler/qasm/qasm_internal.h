// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_{exact,trig,lexer,expression,gates,statements,read}.c pieces share: its includes, types and the
// functions one piece calls in another
#ifndef QASM_INTERNAL_H
#define QASM_INTERNAL_H

#include "qasm.h"

#include "../../types/integers/exact_integer.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// OpenQASM 2.0 read into gates the record machine runs. Every parameter is held exactly as a + b pi with a and b
// exact rationals. A rounded gate's entries are computed at QASM_GUARD_BITS in exact integers, with every
// truncation counted, then rounded once to QASM_FRACTION_BITS: each component lands within one unit.

#define QASM_CHECK(condition_, evacaddr_, error_)                                                                      \
    engine_error_check((condition_) ? 1 : 0, ENGINE_ERROR_REQUEST, ENGINE_MODULE_QASM, __LINE__, (evacaddr_), (error_))

// the fixed point the entries are computed at before their one rounding
#define QASM_GUARD_BITS 124u

// terms of each Taylor series over |r| <= pi/4: (pi/4)^60 / 60! is below 2^-280
#define QASM_SERIES_TERMS 30u

// the counted error of an entry at QASM_GUARD_BITS, in units, past which the one rounding could miss by a unit
#define QASM_SLACK_MAX (1ull << (QASM_GUARD_BITS - QASM_FRACTION_BITS - 2u))

#define QASM_NAME_CAPACITY 64u
#define QASM_GATE_PARAMS_MAX 16u
#define QASM_GATE_ARGS_MAX 16u
#define QASM_EXPAND_DEPTH_MAX 64u
#define QASM_REGISTERS_MAX 64u

typedef struct
{
    AnchorExactInteger num;
    AnchorExactInteger den;
} QasmFraction;

// a + b pi
typedef struct
{
    QasmFraction a;
    QasmFraction b;
} QasmAngle;

typedef enum
{
    QASM_TOKEN_END = 0,
    QASM_TOKEN_IDENT = 1,
    QASM_TOKEN_NUMBER = 2,
    QASM_TOKEN_STRING = 3,
    QASM_TOKEN_SYMBOL = 4
} QasmTokenKind;

typedef struct
{
    unsigned int kind;
    unsigned int start;
    unsigned int length;
    unsigned int line;
    unsigned int column;
} QasmToken;

typedef struct
{
    char name[QASM_NAME_CAPACITY];
    unsigned int offset;
    unsigned int size;
} QasmRegister;

typedef struct
{
    char name[QASM_NAME_CAPACITY];
    unsigned int params;
    unsigned int param_token[QASM_GATE_PARAMS_MAX];
    unsigned int args;
    unsigned int arg_token[QASM_GATE_ARGS_MAX];
    unsigned int body_start;
    unsigned int body_end;
} QasmDefinition;

typedef struct
{
    const QasmDefinition *definition;
    const QasmAngle *values;
    const unsigned int *qubits;
} QasmScope;

typedef struct
{
    const char *path;
    const char *text;
    size_t length;
    QasmToken *tokens;
    unsigned int token_count;
    unsigned int at;
    QasmCircuit *circuit;
    QasmRegister qregs[QASM_REGISTERS_MAX];
    unsigned int qreg_count;
    QasmRegister cregs[QASM_REGISTERS_MAX];
    unsigned int creg_count;
    QasmDefinition *definitions;
    unsigned int definition_count;
    unsigned int definition_capacity;
    unsigned int measured_qubit[QASM_QUBITS_MAX];
    unsigned int clbit_written[QASM_CLBITS_MAX];
    unsigned int depth;
    char *reason;
    size_t reason_capacity;
    EngineError *error;
    int failed;
    // the fixed-point constants, made once
    AnchorExactInteger pi_fixed;
    AnchorExactInteger one_fixed;
} QasmParser;

void qasm_error(QasmParser *parser, const QasmToken *token, const char *format, ...);

int qasm_exact_ok(QasmParser *parser, AnchorExactStatus status);

void qasm_exact_set(AnchorExactInteger *value, unsigned long long magnitude, int negative);

void qasm_exact_power_of_two(AnchorExactInteger *value, unsigned int bits);

int qasm_exact_is_zero(const AnchorExactInteger *value);

void qasm_fraction_integer(QasmFraction *value, long long integer);

int qasm_fraction_reduce(QasmParser *parser, QasmFraction *value);

int qasm_fraction_add(QasmParser *parser, const QasmFraction *left, const QasmFraction *right, int subtract,
                      QasmFraction *result);

int qasm_fraction_multiply(QasmParser *parser, const QasmFraction *left, const QasmFraction *right,
                           QasmFraction *result);

int qasm_fraction_divide(QasmParser *parser, const QasmFraction *left, const QasmFraction *right, QasmFraction *result);

void qasm_angle_rational(QasmAngle *angle, long long a_num, long long a_den, long long b_num, long long b_den);

int qasm_angle_add(QasmParser *parser, const QasmAngle *left, const QasmAngle *right, int subtract, QasmAngle *result);

int qasm_angle_scale(QasmParser *parser, const QasmAngle *angle, long long num, long long den, QasmAngle *result);

int qasm_fixed_multiply(QasmParser *parser, const AnchorExactInteger *left, const AnchorExactInteger *right,
                        AnchorExactInteger *result);

int qasm_fixed_divide_small(QasmParser *parser, const AnchorExactInteger *value, unsigned long long divisor,
                            AnchorExactInteger *result);

int qasm_fixed_rational(QasmParser *parser, const QasmFraction *value, const AnchorExactInteger *with,
                        AnchorExactInteger *result);

int qasm_fixed_constants(QasmParser *parser);

unsigned long long qasm_exact_small(const AnchorExactInteger *value);

int qasm_cos_sin(QasmParser *parser, const QasmAngle *angle, AnchorExactInteger *cosine, AnchorExactInteger *sine,
                 unsigned long long *slack);

int qasm_fixed_round(QasmParser *parser, const AnchorExactInteger *value, long long *rounded);

int qasm_lex(QasmParser *parser);

const QasmToken *qasm_peek(const QasmParser *parser);

int qasm_token_is(const QasmParser *parser, const QasmToken *token, const char *text);

int qasm_tokens_equal(const QasmParser *parser, const QasmToken *left, const QasmToken *right);

int qasm_accept(QasmParser *parser, const char *text);

int qasm_expect(QasmParser *parser, const char *text);

void qasm_token_name(const QasmParser *parser, const QasmToken *token, char *name);

int qasm_expect_ident(QasmParser *parser, char *name, unsigned int *token_at);

int qasm_expect_count(QasmParser *parser, unsigned int *count);

int qasm_number(QasmParser *parser, const QasmToken *token, QasmAngle *value);

int qasm_expression(QasmParser *parser, const QasmScope *scope, QasmAngle *value);

void qasm_wide_to_exact(const unsigned int wide[QASM_WIDE_LIMBS], AnchorExactInteger *value);

int qasm_push_gate(QasmParser *parser, const QasmGate *gate);

typedef struct
{
    const char *name;
    unsigned int params;
    unsigned int qubits;
} QasmBuiltin;

const QasmBuiltin *qasm_builtin(const char *name);

int qasm_lower_gate(QasmParser *parser, const char *name, const QasmAngle *angles, const unsigned int *qubits,
                    const QasmToken *token);

const QasmDefinition *qasm_definition(const QasmParser *parser, const char *name);

const QasmRegister *qasm_register(const QasmRegister *registers, unsigned int count, const char *name);

// a register argument: a whole register (index -1) or one of its bits
typedef struct
{
    const QasmRegister *reg;
    long long index;
} QasmArgument;

int qasm_application(QasmParser *parser, const QasmScope *scope);

int qasm_measure(QasmParser *parser);

int qasm_statements(QasmParser *parser, const QasmScope *scope, unsigned int end);

#endif
