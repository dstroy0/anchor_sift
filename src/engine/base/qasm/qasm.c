// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include "exact_integer.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// OpenQASM 2.0 read into gates the record machine runs. Every parameter is held exactly as a + b pi with a and b
// exact rationals. A rounded gate's entries are computed at QASM_GUARD_BITS in exact integers, with every
// truncation counted, then rounded once to QASM_FRACTION_BITS: each component lands within one unit.

#define QASM_HELD(held, evac, error) \
    engine_error_check((held) ? 1 : 0, ENGINE_ERROR_REQUEST, ENGINE_MODULE_QASM, __LINE__, (evac), (error))

// the fixed point the entries are computed at before their one rounding
#define QASM_GUARD_BITS 124u

// terms of each Taylor series over |r| <= pi/4: (pi/4)^60 / 60! is below 2^-280
#define QASM_SERIES_TERMS 30u

// the counted error of an entry at QASM_GUARD_BITS, in units, past which the one rounding could miss by a unit
#define QASM_SLACK_MOST (1ull << (QASM_GUARD_BITS - QASM_FRACTION_BITS - 2u))

#define QASM_NAME_ROOM 64u
#define QASM_GATE_PARAMS_MOST 16u
#define QASM_GATE_ARGS_MOST 16u
#define QASM_EXPAND_DEPTH_MOST 64u
#define QASM_REGISTERS_MOST 64u

// pi to 110 places; its error, below 10^-110, is far under one unit at QASM_GUARD_BITS
static const char QASM_PI_TEXT[] = "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862"
                                   "803482534211706798214808651";

typedef struct
{
    AnchorExactInteger num;
    AnchorExactInteger den;
} QasmRational;

// a + b pi
typedef struct
{
    QasmRational a;
    QasmRational b;
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
    char name[QASM_NAME_ROOM];
    unsigned int offset;
    unsigned int size;
} QasmRegister;

typedef struct
{
    char name[QASM_NAME_ROOM];
    unsigned int params;
    unsigned int param_token[QASM_GATE_PARAMS_MOST];
    unsigned int args;
    unsigned int arg_token[QASM_GATE_ARGS_MOST];
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
    QasmRegister qregs[QASM_REGISTERS_MOST];
    unsigned int qreg_count;
    QasmRegister cregs[QASM_REGISTERS_MOST];
    unsigned int creg_count;
    QasmDefinition *definitions;
    unsigned int definition_count;
    unsigned int definition_room;
    unsigned int measured_qubit[QASM_QUBITS_MOST];
    unsigned int clbit_written[QASM_CLBITS_MOST];
    unsigned int depth;
    char *reason;
    size_t reason_room;
    EngineError *error;
    int failed;
    // the fixed-point constants, made once
    AnchorExactInteger pi_fixed;
    AnchorExactInteger one_fixed;
} QasmParser;

static void qasm_refuse(QasmParser *parser, const QasmToken *token, const char *format, ...)
{
    if (parser->failed != 0)
    {
        return;
    }
    parser->failed = 1;
    char message[QASM_REASON_ROOM];
    va_list list;
    va_start(list, format);
    vsnprintf(message, sizeof(message), format, list);
    va_end(list);
    if ((parser->reason != NULL) && (parser->reason_room != 0u))
    {
        snprintf(parser->reason, parser->reason_room, "%s:%u:%u: %s", parser->path,
                 (token != NULL) ? token->line : 0u, (token != NULL) ? token->column : 0u, message);
    }
    QASM_HELD(0, token, parser->error);
}

// ---------------------------------------------------------------------------------------------------------------
// exact integers, rationals and angles

static int qasm_exact_ok(QasmParser *parser, AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        qasm_refuse(parser, (parser->at < parser->token_count) ? &parser->tokens[parser->at] : NULL,
                    "a value outgrew the exact integer's width");
        return 0;
    }
    return 1;
}

static void qasm_exact_set(AnchorExactInteger *value, unsigned long long magnitude, int negative)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(magnitude & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(magnitude >> 32u);
    value->sign = (magnitude == 0ull) ? 0 : ((negative != 0) ? -1 : 1);
}

static void qasm_exact_power_of_two(AnchorExactInteger *value, unsigned int bits)
{
    anchor_exact_zero(value);
    value->limb[bits >> 5u] = 1u << (bits & 31u);
    value->sign = 1;
}

static int qasm_exact_is_zero(const AnchorExactInteger *value)
{
    return value->sign == 0;
}

static void qasm_rational_integer(QasmRational *value, long long integer)
{
    qasm_exact_set(&value->num, (integer < 0) ? (unsigned long long)(-integer) : (unsigned long long)integer,
                   integer < 0);
    qasm_exact_set(&value->den, 1ull, 0);
}

static int qasm_rational_reduce(QasmParser *parser, QasmRational *value)
{
    if (qasm_exact_is_zero(&value->num))
    {
        qasm_exact_set(&value->den, 1ull, 0);
        return 1;
    }
    AnchorExactInteger divisor;
    AnchorExactInteger remainder;
    if (!qasm_exact_ok(parser, anchor_exact_gcd(&value->num, &value->den, &divisor))
     || !qasm_exact_ok(parser, anchor_exact_divide(&value->num, &divisor, &value->num, &remainder))
     || !qasm_exact_ok(parser, anchor_exact_divide(&value->den, &divisor, &value->den, &remainder)))
    {
        return 0;
    }
    if (value->den.sign < 0)
    {
        value->den.sign = 1;
        value->num.sign = -value->num.sign;
    }
    return 1;
}

static int qasm_rational_add(QasmParser *parser, const QasmRational *left, const QasmRational *right, int subtract,
                             QasmRational *result)
{
    AnchorExactInteger one;
    AnchorExactInteger two;
    AnchorExactInteger den;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->den, &one))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&right->num, &left->den, &two))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->den, &den)))
    {
        return 0;
    }
    const AnchorExactStatus status = (subtract != 0) ? anchor_exact_subtract(&one, &two, &result->num)
                                                     : anchor_exact_add(&one, &two, &result->num);
    if (!qasm_exact_ok(parser, status))
    {
        return 0;
    }
    result->den = den;
    return qasm_rational_reduce(parser, result);
}

static int qasm_rational_multiply(QasmParser *parser, const QasmRational *left, const QasmRational *right,
                                  QasmRational *result)
{
    QasmRational made;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->num, &made.num))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->den, &made.den)))
    {
        return 0;
    }
    *result = made;
    return qasm_rational_reduce(parser, result);
}

static int qasm_rational_divide(QasmParser *parser, const QasmRational *left, const QasmRational *right,
                                QasmRational *result)
{
    QasmRational made;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->den, &made.num))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->num, &made.den)))
    {
        return 0;
    }
    *result = made;
    return qasm_rational_reduce(parser, result);
}

static void qasm_angle_rational(QasmAngle *angle, long long a_num, long long a_den, long long b_num, long long b_den)
{
    qasm_rational_integer(&angle->a, a_num);
    qasm_exact_set(&angle->a.den, (unsigned long long)a_den, 0);
    qasm_rational_integer(&angle->b, b_num);
    qasm_exact_set(&angle->b.den, (unsigned long long)b_den, 0);
}

static int qasm_angle_add(QasmParser *parser, const QasmAngle *left, const QasmAngle *right, int subtract,
                          QasmAngle *result)
{
    return qasm_rational_add(parser, &left->a, &right->a, subtract, &result->a)
        && qasm_rational_add(parser, &left->b, &right->b, subtract, &result->b);
}

static int qasm_angle_scale(QasmParser *parser, const QasmAngle *angle, long long num, long long den, QasmAngle *result)
{
    QasmRational factor;
    qasm_rational_integer(&factor, num);
    qasm_exact_set(&factor.den, (unsigned long long)den, 0);
    return qasm_rational_multiply(parser, &angle->a, &factor, &result->a)
        && qasm_rational_multiply(parser, &angle->b, &factor, &result->b);
}

// ---------------------------------------------------------------------------------------------------------------
// fixed point at QASM_GUARD_BITS: value * 2^QASM_GUARD_BITS as an exact integer

// (left * right) / 2^QASM_GUARD_BITS, toward zero: at most one unit lost
static int qasm_fixed_multiply(QasmParser *parser, const AnchorExactInteger *left, const AnchorExactInteger *right,
                               AnchorExactInteger *result)
{
    AnchorExactInteger product;
    AnchorExactInteger scale;
    AnchorExactInteger remainder;
    qasm_exact_power_of_two(&scale, QASM_GUARD_BITS);
    return qasm_exact_ok(parser, anchor_exact_multiply(left, right, &product))
        && qasm_exact_ok(parser, anchor_exact_divide(&product, &scale, result, &remainder));
}

// value / divisor for a small positive divisor, toward zero: at most one unit lost
static int qasm_fixed_divide_small(QasmParser *parser, const AnchorExactInteger *value, unsigned long long divisor,
                                   AnchorExactInteger *result)
{
    AnchorExactInteger by;
    AnchorExactInteger remainder;
    qasm_exact_set(&by, divisor, 0);
    return qasm_exact_ok(parser, anchor_exact_divide(value, &by, result, &remainder));
}

// the rational times 2^QASM_GUARD_BITS times `with` (or 2^QASM_GUARD_BITS alone when with is NULL), toward zero
static int qasm_fixed_rational(QasmParser *parser, const QasmRational *value, const AnchorExactInteger *with,
                               AnchorExactInteger *result)
{
    AnchorExactInteger scaled;
    AnchorExactInteger remainder;
    if (with == NULL)
    {
        AnchorExactInteger scale;
        qasm_exact_power_of_two(&scale, QASM_GUARD_BITS);
        if (!qasm_exact_ok(parser, anchor_exact_multiply(&value->num, &scale, &scaled)))
        {
            return 0;
        }
    }
    else if (!qasm_exact_ok(parser, anchor_exact_multiply(&value->num, with, &scaled)))
    {
        return 0;
    }
    return qasm_exact_ok(parser, anchor_exact_divide(&scaled, &value->den, result, &remainder));
}

static int qasm_fixed_constants(QasmParser *parser)
{
    // pi * 10^110 exactly as text says, then times 2^G over 10^110: floor within one unit of pi 2^G
    const unsigned int places = 110u;
    AnchorExactInteger pi_text;
    AnchorExactInteger scale;
    AnchorExactInteger ten_power;
    AnchorExactInteger product;
    AnchorExactInteger remainder;
    if (!qasm_exact_ok(parser, anchor_exact_from_decimal(QASM_PI_TEXT, strlen(QASM_PI_TEXT), places, &pi_text)))
    {
        return 0;
    }
    qasm_exact_power_of_two(&scale, QASM_GUARD_BITS);
    qasm_exact_set(&ten_power, 1ull, 0);
    if (!qasm_exact_ok(parser, anchor_exact_scale_by_ten(&ten_power, places))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&pi_text, &scale, &product))
     || !qasm_exact_ok(parser, anchor_exact_divide(&product, &ten_power, &parser->pi_fixed, &remainder)))
    {
        return 0;
    }
    parser->one_fixed = scale;
    return 1;
}

// |value| as an unsigned 64-bit count, or ~0 where it does not fit
static unsigned long long qasm_exact_small(const AnchorExactInteger *value)
{
    for (unsigned int limb = 2u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        if (value->limb[limb] != 0u)
        {
            return ~0ull;
        }
    }
    return ((unsigned long long)value->limb[1] << 32u) | (unsigned long long)value->limb[0];
}

// cos and sin of the angle at QASM_GUARD_BITS; *slack gains the counted error, in units
static int qasm_cos_sin(QasmParser *parser, const QasmAngle *angle, AnchorExactInteger *cosine, AnchorExactInteger *sine,
                        unsigned long long *slack)
{
    // b mod 2, exactly: b - 2 floor(b / 2)
    QasmRational b = angle->b;
    {
        AnchorExactInteger twice_den;
        AnchorExactInteger turns;
        AnchorExactInteger remainder;
        AnchorExactInteger two;
        qasm_exact_set(&two, 2ull, 0);
        if (!qasm_exact_ok(parser, anchor_exact_multiply(&b.den, &two, &twice_den))
         || !qasm_exact_ok(parser, anchor_exact_divide(&b.num, &twice_den, &turns, &remainder)))
        {
            return 0;
        }
        // the remainder keeps b's sign; a negative one is lifted by one whole turn
        if (remainder.sign < 0)
        {
            if (!qasm_exact_ok(parser, anchor_exact_add(&remainder, &twice_den, &remainder)))
            {
                return 0;
            }
        }
        b.num = remainder;
        if (!qasm_rational_reduce(parser, &b))
        {
            return 0;
        }
    }
    // x = a 2^G + b pi 2^G: a's floor loses one unit, b P loses |b| * 1 + 1 <= 3, P itself is within one of pi 2^G
    AnchorExactInteger x;
    AnchorExactInteger b_part;
    if (!qasm_fixed_rational(parser, &angle->a, NULL, &x) || !qasm_fixed_rational(parser, &b, &parser->pi_fixed, &b_part)
     || !qasm_exact_ok(parser, anchor_exact_add(&x, &b_part, &x)))
    {
        return 0;
    }
    unsigned long long error = 6ull;
    // into [-pi, pi] by whole turns: each turn taken carries 2P's error, two units
    AnchorExactInteger turn;
    AnchorExactInteger turns;
    AnchorExactInteger remainder;
    if (!qasm_exact_ok(parser, anchor_exact_add(&parser->pi_fixed, &parser->pi_fixed, &turn))
     || !qasm_exact_ok(parser, anchor_exact_divide(&x, &turn, &turns, &remainder)))
    {
        return 0;
    }
    const unsigned long long whole = qasm_exact_small(&turns);
    if ((whole == ~0ull) || (whole > (1ull << 40u)))
    {
        qasm_refuse(parser, &parser->tokens[parser->at], "an angle past 2^40 turns is not read");
        return 0;
    }
    error += 2ull * (whole + 1ull);
    x = remainder;
    // remainder is in (-2pi, 2pi) with x's sign: one more turn brings it to [-pi, pi]
    if (anchor_exact_compare(&x, &parser->pi_fixed) > 0)
    {
        if (!qasm_exact_ok(parser, anchor_exact_subtract(&x, &turn, &x)))
        {
            return 0;
        }
    }
    AnchorExactInteger negative_pi = parser->pi_fixed;
    negative_pi.sign = -1;
    if (anchor_exact_compare(&x, &negative_pi) < 0)
    {
        if (!qasm_exact_ok(parser, anchor_exact_add(&x, &turn, &x)))
        {
            return 0;
        }
    }
    error += 2ull;
    // a quarter turn h = P / 2, within one unit and a half; x = k h + r with |r| <= pi/4 and k in -2..2
    AnchorExactInteger quarter;
    if (!qasm_fixed_divide_small(parser, &parser->pi_fixed, 2ull, &quarter))
    {
        return 0;
    }
    AnchorExactInteger eighth;
    if (!qasm_fixed_divide_small(parser, &parser->pi_fixed, 4ull, &eighth))
    {
        return 0;
    }
    int k = 0;
    AnchorExactInteger r = x;
    for (unsigned int round = 0u; round < 3u; round += 1u)
    {
        if (anchor_exact_compare(&r, &eighth) > 0)
        {
            if (!qasm_exact_ok(parser, anchor_exact_subtract(&r, &quarter, &r)))
            {
                return 0;
            }
            k += 1;
        }
        AnchorExactInteger negative_eighth = eighth;
        negative_eighth.sign = -1;
        if (anchor_exact_compare(&r, &negative_eighth) < 0)
        {
            if (!qasm_exact_ok(parser, anchor_exact_add(&r, &quarter, &r)))
            {
                return 0;
            }
            k -= 1;
        }
    }
    error += 2ull * 3ull;
    const unsigned long long error_r = error;
    // r^2 at G: with |r| < 0.8, r's error at most doubles, and one unit is lost
    AnchorExactInteger r2;
    if (!qasm_fixed_multiply(parser, &r, &r, &r2))
    {
        return 0;
    }
    const unsigned long long error_r2 = (2ull * error_r) + 1ull;
    // The series, term by term: t_k = t_(k-1) r^2 / ((2k - 1) 2k) for cos, / (2k (2k + 1)) for sin. With |t| <= 1
    // and |r^2| < 0.62, a term's error is at most the last term's plus r^2's, over a divisor of at least 2, plus two
    // units lost: e_k <= e_(k-1) + e_r2 + 2. The tail past QASM_SERIES_TERMS is below one unit.
    AnchorExactInteger term = parser->one_fixed;
    AnchorExactInteger cos_sum = parser->one_fixed;
    AnchorExactInteger sin_term = r;
    AnchorExactInteger sin_sum = r;
    unsigned long long error_cos_term = 0ull;
    unsigned long long error_cos = 0ull;
    unsigned long long error_sin_term = error_r;
    unsigned long long error_sin = error_r;
    for (unsigned int k2 = 1u; k2 <= QASM_SERIES_TERMS; k2 += 1u)
    {
        AnchorExactInteger product;
        if (!qasm_fixed_multiply(parser, &term, &r2, &product)
         || !qasm_fixed_divide_small(parser, &product, (unsigned long long)((2u * k2) - 1u) * (2ull * k2), &term))
        {
            return 0;
        }
        term.sign = (term.sign == 0) ? 0 : -term.sign;
        error_cos_term += error_r2 + 2ull;
        error_cos += error_cos_term;
        if (!qasm_exact_ok(parser, anchor_exact_add(&cos_sum, &term, &cos_sum)))
        {
            return 0;
        }
        if (!qasm_fixed_multiply(parser, &sin_term, &r2, &product)
         || !qasm_fixed_divide_small(parser, &product, (2ull * k2) * ((2ull * k2) + 1ull), &sin_term))
        {
            return 0;
        }
        sin_term.sign = (sin_term.sign == 0) ? 0 : -sin_term.sign;
        error_sin_term += error_r2 + 2ull;
        error_sin += error_sin_term;
        if (!qasm_exact_ok(parser, anchor_exact_add(&sin_sum, &sin_term, &sin_sum)))
        {
            return 0;
        }
    }
    // the tail
    error_cos += 1ull;
    error_sin += 1ull;
    // cos r, sin r to the angle: quarter turns k mod 4
    const int quadrant = ((k % 4) + 4) % 4;
    AnchorExactInteger c = cos_sum;
    AnchorExactInteger s = sin_sum;
    if (quadrant == 1)
    {
        c = sin_sum;
        c.sign = -c.sign;
        s = cos_sum;
    }
    if (quadrant == 2)
    {
        c = cos_sum;
        c.sign = -c.sign;
        s = sin_sum;
        s.sign = -s.sign;
    }
    if (quadrant == 3)
    {
        c = sin_sum;
        s = cos_sum;
        s.sign = -s.sign;
    }
    *cosine = c;
    *sine = s;
    const unsigned long long counted = (error_cos > error_sin) ? error_cos : error_sin;
    *slack = (*slack > counted) ? *slack : counted;
    return 1;
}

// the value at G rounded once to QASM_FRACTION_BITS, half away from zero
static int qasm_fixed_round(QasmParser *parser, const AnchorExactInteger *value, long long *rounded)
{
    AnchorExactInteger scale;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    qasm_exact_power_of_two(&scale, QASM_GUARD_BITS - QASM_FRACTION_BITS);
    if (!qasm_exact_ok(parser, anchor_exact_divide(value, &scale, &quotient, &remainder)))
    {
        return 0;
    }
    unsigned long long magnitude = qasm_exact_small(&quotient);
    AnchorExactInteger twice;
    if (!qasm_exact_ok(parser, anchor_exact_add(&remainder, &remainder, &twice)))
    {
        return 0;
    }
    twice.sign = (twice.sign < 0) ? 1 : twice.sign;
    if (anchor_exact_compare(&twice, &scale) >= 0)
    {
        magnitude += 1ull;
    }
    if (magnitude > ((1ull << QASM_FRACTION_BITS) + 1ull))
    {
        qasm_refuse(parser, &parser->tokens[parser->at], "an entry left the unit disc");
        return 0;
    }
    const int negative = (value->sign < 0);
    *rounded = (negative != 0) ? -(long long)magnitude : (long long)magnitude;
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------
// the lexer

static int qasm_is_letter(char c)
{
    return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')) || (c == '_');
}

static int qasm_is_digit(char c)
{
    return (c >= '0') && (c <= '9');
}

static int qasm_lex(QasmParser *parser)
{
    const char *const text = parser->text;
    const size_t length = parser->length;
    size_t room = 1024u;
    parser->tokens = (QasmToken *)malloc(room * sizeof(QasmToken));
    if (!QASM_HELD(parser->tokens != NULL, parser, parser->error))
    {
        parser->failed = 1;
        return 0;
    }
    unsigned int line = 1u;
    unsigned int column = 1u;
    size_t at = 0u;
    while (1)
    {
        // spaces and comments
        while (at < length)
        {
            const char c = text[at];
            if (c == '\n')
            {
                line += 1u;
                column = 1u;
                at += 1u;
            }
            else if ((c == ' ') || (c == '\t') || (c == '\r'))
            {
                column += 1u;
                at += 1u;
            }
            else if ((c == '/') && ((at + 1u) < length) && (text[at + 1u] == '/'))
            {
                while ((at < length) && (text[at] != '\n'))
                {
                    at += 1u;
                }
            }
            else if ((c == '/') && ((at + 1u) < length) && (text[at + 1u] == '*'))
            {
                at += 2u;
                column += 2u;
                while ((at < length) && !((text[at] == '*') && ((at + 1u) < length) && (text[at + 1u] == '/')))
                {
                    if (text[at] == '\n')
                    {
                        line += 1u;
                        column = 1u;
                    }
                    else
                    {
                        column += 1u;
                    }
                    at += 1u;
                }
                at += 2u;
                column += 2u;
            }
            else
            {
                break;
            }
        }
        if (parser->token_count + 1u >= room)
        {
            room *= 2u;
            QasmToken *const grown = (QasmToken *)realloc(parser->tokens, room * sizeof(QasmToken));
            if (!QASM_HELD(grown != NULL, parser, parser->error))
            {
                parser->failed = 1;
                return 0;
            }
            parser->tokens = grown;
        }
        QasmToken *const token = &parser->tokens[parser->token_count];
        token->start = (unsigned int)at;
        token->line = line;
        token->column = column;
        if (at >= length)
        {
            token->kind = QASM_TOKEN_END;
            token->length = 0u;
            parser->token_count += 1u;
            return 1;
        }
        const char c = text[at];
        size_t end = at + 1u;
        if (qasm_is_letter(c))
        {
            while ((end < length) && (qasm_is_letter(text[end]) || qasm_is_digit(text[end])))
            {
                end += 1u;
            }
            token->kind = QASM_TOKEN_IDENT;
        }
        else if (qasm_is_digit(c) || ((c == '.') && ((at + 1u) < length) && qasm_is_digit(text[at + 1u])))
        {
            end = at;
            while ((end < length) && qasm_is_digit(text[end]))
            {
                end += 1u;
            }
            if ((end < length) && (text[end] == '.'))
            {
                end += 1u;
                while ((end < length) && qasm_is_digit(text[end]))
                {
                    end += 1u;
                }
            }
            if ((end < length) && ((text[end] == 'e') || (text[end] == 'E')))
            {
                size_t exponent = end + 1u;
                if ((exponent < length) && ((text[exponent] == '+') || (text[exponent] == '-')))
                {
                    exponent += 1u;
                }
                if ((exponent < length) && qasm_is_digit(text[exponent]))
                {
                    end = exponent;
                    while ((end < length) && qasm_is_digit(text[end]))
                    {
                        end += 1u;
                    }
                }
            }
            token->kind = QASM_TOKEN_NUMBER;
        }
        else if (c == '"')
        {
            while ((end < length) && (text[end] != '"') && (text[end] != '\n'))
            {
                end += 1u;
            }
            if ((end >= length) || (text[end] != '"'))
            {
                token->kind = QASM_TOKEN_SYMBOL;
                token->length = 1u;
                parser->token_count += 1u;
                qasm_refuse(parser, token, "a string is not closed on its line");
                return 0;
            }
            end += 1u;
            token->kind = QASM_TOKEN_STRING;
        }
        else if ((c == '-') && ((at + 1u) < length) && (text[at + 1u] == '>'))
        {
            end = at + 2u;
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else if ((c == '=') && ((at + 1u) < length) && (text[at + 1u] == '='))
        {
            end = at + 2u;
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else if (strchr(";,()[]{}+-*/^", c) != NULL)
        {
            token->kind = QASM_TOKEN_SYMBOL;
        }
        else
        {
            token->kind = QASM_TOKEN_SYMBOL;
            token->length = 1u;
            parser->token_count += 1u;
            qasm_refuse(parser, token, "'%c' is not part of OpenQASM 2.0", c);
            return 0;
        }
        token->length = (unsigned int)(end - at);
        column += token->length;
        at = end;
        parser->token_count += 1u;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// the parser's reading of tokens

static const QasmToken *qasm_peek(const QasmParser *parser)
{
    return &parser->tokens[parser->at];
}

static int qasm_token_is(const QasmParser *parser, const QasmToken *token, const char *text)
{
    const size_t length = strlen(text);
    return (token->length == length) && (strncmp(parser->text + token->start, text, length) == 0);
}

static int qasm_tokens_equal(const QasmParser *parser, const QasmToken *left, const QasmToken *right)
{
    return (left->length == right->length)
        && (strncmp(parser->text + left->start, parser->text + right->start, left->length) == 0);
}

static int qasm_accept(QasmParser *parser, const char *text)
{
    const QasmToken *const token = qasm_peek(parser);
    if ((token->kind != QASM_TOKEN_END) && (token->kind != QASM_TOKEN_STRING) && qasm_token_is(parser, token, text))
    {
        parser->at += 1u;
        return 1;
    }
    return 0;
}

static int qasm_expect(QasmParser *parser, const char *text)
{
    if (qasm_accept(parser, text))
    {
        return 1;
    }
    qasm_refuse(parser, qasm_peek(parser), "'%s' was expected here", text);
    return 0;
}

static void qasm_token_name(const QasmParser *parser, const QasmToken *token, char *name)
{
    const unsigned int length = (token->length < (QASM_NAME_ROOM - 1u)) ? token->length : (QASM_NAME_ROOM - 1u);
    memcpy(name, parser->text + token->start, length);
    name[length] = '\0';
}

static int qasm_expect_ident(QasmParser *parser, char *name, unsigned int *token_at)
{
    const QasmToken *const token = qasm_peek(parser);
    if (token->kind != QASM_TOKEN_IDENT)
    {
        qasm_refuse(parser, token, "a name was expected here");
        return 0;
    }
    if (token->length >= QASM_NAME_ROOM)
    {
        qasm_refuse(parser, token, "a name past %u characters is not read", QASM_NAME_ROOM - 1u);
        return 0;
    }
    if (name != NULL)
    {
        qasm_token_name(parser, token, name);
    }
    if (token_at != NULL)
    {
        *token_at = parser->at;
    }
    parser->at += 1u;
    return 1;
}

static int qasm_expect_count(QasmParser *parser, unsigned int *count)
{
    const QasmToken *const token = qasm_peek(parser);
    unsigned long long value = 0ull;
    int digits = (token->kind == QASM_TOKEN_NUMBER);
    for (unsigned int at = 0u; digits && (at < token->length); at += 1u)
    {
        const char c = parser->text[token->start + at];
        digits = qasm_is_digit(c) && (value < 100000000ull);
        value = (value * 10ull) + (unsigned long long)(c - '0');
    }
    if (!digits)
    {
        qasm_refuse(parser, token, "a whole number was expected here");
        return 0;
    }
    *count = (unsigned int)value;
    parser->at += 1u;
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------
// expressions: + - * / unary minus, parentheses, pi, numbers and the gate's parameters

static int qasm_number(QasmParser *parser, const QasmToken *token, QasmAngle *value)
{
    const char *const text = parser->text + token->start;
    unsigned int mantissa_end = 0u;
    while ((mantissa_end < token->length) && (text[mantissa_end] != 'e') && (text[mantissa_end] != 'E'))
    {
        mantissa_end += 1u;
    }
    unsigned int places = 0u;
    int seen_point = 0;
    for (unsigned int at = 0u; at < mantissa_end; at += 1u)
    {
        if (text[at] == '.')
        {
            seen_point = 1;
        }
        else if (seen_point != 0)
        {
            places += 1u;
        }
    }
    if (places > 200u)
    {
        qasm_refuse(parser, token, "a number past 200 places is not read");
        return 0;
    }
    long long exponent = 0;
    if (mantissa_end < token->length)
    {
        exponent = strtoll(text + mantissa_end + 1u, NULL, 10);
        if ((exponent > 300) || (exponent < -300))
        {
            qasm_refuse(parser, token, "an exponent past 300 is not read");
            return 0;
        }
    }
    QasmRational number;
    if (!qasm_exact_ok(parser, anchor_exact_from_decimal(text, mantissa_end, places, &number.num)))
    {
        return 0;
    }
    qasm_exact_set(&number.den, 1ull, 0);
    if (!qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.den, places)))
    {
        return 0;
    }
    if ((exponent > 0) && !qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.num, (uint32_t)exponent)))
    {
        return 0;
    }
    if ((exponent < 0) && !qasm_exact_ok(parser, anchor_exact_scale_by_ten(&number.den, (uint32_t)(-exponent))))
    {
        return 0;
    }
    if (!qasm_rational_reduce(parser, &number))
    {
        return 0;
    }
    value->a = number;
    qasm_rational_integer(&value->b, 0);
    return 1;
}

static int qasm_expression(QasmParser *parser, const QasmScope *scope, QasmAngle *value);

static int qasm_primary(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    const QasmToken *const token = qasm_peek(parser);
    if (token->kind == QASM_TOKEN_NUMBER)
    {
        parser->at += 1u;
        return qasm_number(parser, token, value);
    }
    if (qasm_accept(parser, "("))
    {
        return qasm_expression(parser, scope, value) && qasm_expect(parser, ")");
    }
    if (token->kind == QASM_TOKEN_IDENT)
    {
        if (qasm_token_is(parser, token, "pi"))
        {
            parser->at += 1u;
            qasm_angle_rational(value, 0, 1, 1, 1);
            return 1;
        }
        if ((scope != NULL) && (scope->definition != NULL))
        {
            for (unsigned int param = 0u; param < scope->definition->params; param += 1u)
            {
                if (qasm_tokens_equal(parser, token, &parser->tokens[scope->definition->param_token[param]]))
                {
                    parser->at += 1u;
                    *value = scope->values[param];
                    return 1;
                }
            }
        }
        static const char *const functions[] = {"sin", "cos", "tan", "exp", "ln", "sqrt"};
        for (unsigned int at = 0u; at < (sizeof(functions) / sizeof(functions[0])); at += 1u)
        {
            if (qasm_token_is(parser, token, functions[at]))
            {
                qasm_refuse(parser, token, "%s() in a parameter is not read: a parameter is + - * / over numbers and pi",
                            functions[at]);
                return 0;
            }
        }
        char name[QASM_NAME_ROOM];
        qasm_token_name(parser, token, name);
        qasm_refuse(parser, token, "'%s' is not a parameter here", name);
        return 0;
    }
    qasm_refuse(parser, token, "a number, pi, a parameter or '(' was expected here");
    return 0;
}

static int qasm_unary(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (qasm_accept(parser, "-"))
    {
        if (!qasm_unary(parser, scope, value))
        {
            return 0;
        }
        value->a.num.sign = -value->a.num.sign;
        value->b.num.sign = -value->b.num.sign;
        return 1;
    }
    if (qasm_accept(parser, "+"))
    {
        return qasm_unary(parser, scope, value);
    }
    if (!qasm_primary(parser, scope, value))
    {
        return 0;
    }
    if (qasm_token_is(parser, qasm_peek(parser), "^") && (qasm_peek(parser)->kind == QASM_TOKEN_SYMBOL))
    {
        qasm_refuse(parser, qasm_peek(parser), "'^' in a parameter is not read: a parameter is + - * / over numbers and pi");
        return 0;
    }
    return 1;
}

static int qasm_term(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (!qasm_unary(parser, scope, value))
    {
        return 0;
    }
    while (1)
    {
        const QasmToken *const token = qasm_peek(parser);
        const int multiply = qasm_accept(parser, "*");
        const int divide = (multiply == 0) && qasm_accept(parser, "/");
        if ((multiply == 0) && (divide == 0))
        {
            return 1;
        }
        QasmAngle right;
        if (!qasm_unary(parser, scope, &right))
        {
            return 0;
        }
        const int left_pi = !qasm_exact_is_zero(&value->b.num);
        const int right_pi = !qasm_exact_is_zero(&right.b.num);
        if (divide != 0)
        {
            if (right_pi || qasm_exact_is_zero(&right.a.num))
            {
                qasm_refuse(parser, token, right_pi ? "a division by a multiple of pi is not read"
                                                    : "a parameter divides by zero");
                return 0;
            }
            if (!qasm_rational_divide(parser, &value->a, &right.a, &value->a)
             || !qasm_rational_divide(parser, &value->b, &right.a, &value->b))
            {
                return 0;
            }
            continue;
        }
        if (left_pi && right_pi)
        {
            qasm_refuse(parser, token, "pi times pi is not read: an angle is a + b pi");
            return 0;
        }
        // (a1 + b1 pi)(a2 + b2 pi) with b1 b2 = 0
        QasmAngle made;
        QasmRational cross;
        if (!qasm_rational_multiply(parser, &value->a, &right.a, &made.a)
         || !qasm_rational_multiply(parser, &value->a, &right.b, &made.b)
         || !qasm_rational_multiply(parser, &value->b, &right.a, &cross)
         || !qasm_rational_add(parser, &made.b, &cross, 0, &made.b))
        {
            return 0;
        }
        *value = made;
    }
}

static int qasm_expression(QasmParser *parser, const QasmScope *scope, QasmAngle *value)
{
    if (!qasm_term(parser, scope, value))
    {
        return 0;
    }
    while (1)
    {
        const int add = qasm_accept(parser, "+");
        const int subtract = (add == 0) && qasm_accept(parser, "-");
        if ((add == 0) && (subtract == 0))
        {
            return 1;
        }
        QasmAngle right;
        if (!qasm_term(parser, scope, &right) || !qasm_angle_add(parser, value, &right, subtract, value))
        {
            return 0;
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------
// the bound

static void qasm_wide_to_exact(const unsigned int wide[QASM_WIDE_LIMBS], AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    int any = 0;
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        value->limb[limb] = wide[limb];
        any |= (wide[limb] != 0u);
    }
    value->sign = any ? 1 : 0;
}

static int qasm_exact_to_wide(const AnchorExactInteger *value, unsigned int wide[QASM_WIDE_LIMBS])
{
    for (unsigned int limb = QASM_WIDE_LIMBS; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        if (value->limb[limb] != 0u)
        {
            return 0;
        }
    }
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        wide[limb] = (value->sign > 0) ? value->limb[limb] : 0u;
    }
    return 1;
}

// E' = E' + ceil(delta E' / 2^F) + (delta + T) 2^F, in units of 2^-2F. delta bounds ||M' - M|| in units of 2^-F;
// T bounds the truncations' 2-norm, sqrt(2 N_on) <= 2^ceil((m + 1) / 2) with N_on = 2^m lanes dividing.
static int qasm_bound_gate(QasmParser *parser, const QasmGate *gate)
{
    const unsigned int divides = (gate->kind == QASM_GATE_PAIR) || (gate->kind == QASM_GATE_DIAGONAL);
    if (divides == 0u)
    {
        parser->circuit->exact_gates += 1u;
        return 1;
    }
    parser->circuit->rounded_gates += 1u;
    // a 2x2 whose components are each within one unit: ||.||_2 <= ||.||_F <= sqrt(8) < 3; a diagonal: sqrt(2) < 2
    const unsigned long long delta = (gate->exact_entries != 0u) ? 0ull : ((gate->kind == QASM_GATE_PAIR) ? 3ull : 2ull);
    const unsigned int m = parser->circuit->qubits - gate->control_count;
    const unsigned int t_bits = (m + 2u) / 2u;
    AnchorExactInteger bound;
    AnchorExactInteger grown;
    AnchorExactInteger scale;
    AnchorExactInteger remainder;
    AnchorExactInteger local;
    AnchorExactInteger by;
    qasm_wide_to_exact(parser->circuit->bound, &bound);
    qasm_exact_power_of_two(&scale, QASM_FRACTION_BITS);
    qasm_exact_set(&by, delta, 0);
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&bound, &by, &grown))
     || !qasm_exact_ok(parser, anchor_exact_divide(&grown, &scale, &grown, &remainder)))
    {
        return 0;
    }
    if (!qasm_exact_is_zero(&remainder))
    {
        AnchorExactInteger one;
        qasm_exact_set(&one, 1ull, 0);
        if (!qasm_exact_ok(parser, anchor_exact_add(&grown, &one, &grown)))
        {
            return 0;
        }
    }
    AnchorExactInteger t;
    qasm_exact_power_of_two(&t, t_bits);
    AnchorExactInteger delta_exact;
    qasm_exact_set(&delta_exact, delta, 0);
    if (!qasm_exact_ok(parser, anchor_exact_add(&t, &delta_exact, &local))
     || !qasm_exact_ok(parser, anchor_exact_multiply(&local, &scale, &local))
     || !qasm_exact_ok(parser, anchor_exact_add(&bound, &grown, &bound))
     || !qasm_exact_ok(parser, anchor_exact_add(&bound, &local, &bound)))
    {
        return 0;
    }
    // E past 1/2: nothing can be proved, and an amplitude could outgrow its 62-bit field
    AnchorExactInteger half;
    qasm_exact_power_of_two(&half, (2u * QASM_FRACTION_BITS) - 1u);
    if ((anchor_exact_compare(&bound, &half) >= 0) || !qasm_exact_to_wide(&bound, parser->circuit->bound))
    {
        qasm_refuse(parser, &parser->tokens[parser->at],
                    "the proved error bound reaches 1/2 at this gate (%u rounded gates at F = %u): no bitstring could "
                    "be proved",
                    parser->circuit->rounded_gates, QASM_FRACTION_BITS);
        return 0;
    }
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------
// gates

static int qasm_push_gate(QasmParser *parser, const QasmGate *gate)
{
    QasmCircuit *const circuit = parser->circuit;
    if (circuit->gate_count == circuit->gate_room)
    {
        const unsigned int room = (circuit->gate_room == 0u) ? 256u : (circuit->gate_room * 2u);
        QasmGate *const grown = (QasmGate *)realloc(circuit->gates, (size_t)room * sizeof(QasmGate));
        if (!QASM_HELD(grown != NULL, circuit, parser->error))
        {
            parser->failed = 1;
            return 0;
        }
        circuit->gates = grown;
        circuit->gate_room = room;
    }
    circuit->gates[circuit->gate_count] = *gate;
    circuit->gate_count += 1u;
    return qasm_bound_gate(parser, gate);
}

static void qasm_gate_start(QasmGate *gate, unsigned int kind, unsigned int shape, const QasmToken *token)
{
    memset(gate, 0, sizeof(*gate));
    gate->kind = kind;
    gate->shape = shape;
    gate->line = token->line;
    gate->column = token->column;
}

static void qasm_gate_controls(QasmGate *gate, const unsigned int *qubits, unsigned int count)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        gate->controls |= 1ull << qubits[at];
    }
    gate->control_count = count;
}

// the entry r e^{i phase} at G: (r cos, r sin), with r and the phase's cos and sin at G; slack grows by the product's
static int qasm_entry(QasmParser *parser, const AnchorExactInteger *radius, const QasmAngle *phase, int negate,
                      long long *re, long long *im, unsigned long long *slack)
{
    AnchorExactInteger c;
    AnchorExactInteger s;
    unsigned long long phase_slack = 0ull;
    if (!qasm_cos_sin(parser, phase, &c, &s, &phase_slack))
    {
        return 0;
    }
    AnchorExactInteger x;
    AnchorExactInteger y;
    if (!qasm_fixed_multiply(parser, radius, &c, &x) || !qasm_fixed_multiply(parser, radius, &s, &y))
    {
        return 0;
    }
    // |radius|, |cos|, |sin| <= 1 within a few units: the product's error is the two errors, their product's
    // share below one unit, and one unit truncated
    const unsigned long long counted = *slack + phase_slack + 2ull;
    if (counted >= QASM_SLACK_MOST)
    {
        qasm_refuse(parser, &parser->tokens[parser->at], "an entry's counted error passed its room");
        return 0;
    }
    if (negate != 0)
    {
        x.sign = -x.sign;
        y.sign = -y.sign;
    }
    return qasm_fixed_round(parser, &x, re) && qasm_fixed_round(parser, &y, im);
}

// e^{i gamma} U3(theta, phi, lambda): [[c, -e^{i lambda} s], [e^{i phi} s, e^{i (phi + lambda)} c]] times e^{i gamma}
static int qasm_u3_entries(QasmParser *parser, const QasmAngle *theta, const QasmAngle *phi, const QasmAngle *lambda,
                           const QasmAngle *gamma, QasmGate *gate)
{
    QasmAngle half;
    AnchorExactInteger c;
    AnchorExactInteger s;
    unsigned long long slack = 0ull;
    if (!qasm_angle_scale(parser, theta, 1, 2, &half) || !qasm_cos_sin(parser, &half, &c, &s, &slack))
    {
        return 0;
    }
    QasmAngle gamma_lambda;
    QasmAngle gamma_phi;
    QasmAngle gamma_phi_lambda;
    if (!qasm_angle_add(parser, gamma, lambda, 0, &gamma_lambda) || !qasm_angle_add(parser, gamma, phi, 0, &gamma_phi)
     || !qasm_angle_add(parser, &gamma_phi, lambda, 0, &gamma_phi_lambda))
    {
        return 0;
    }
    return qasm_entry(parser, &c, gamma, 0, &gate->entries[0], &gate->entries[1], &slack)
        && qasm_entry(parser, &s, &gamma_lambda, 1, &gate->entries[2], &gate->entries[3], &slack)
        && qasm_entry(parser, &s, &gamma_phi, 0, &gate->entries[4], &gate->entries[5], &slack)
        && qasm_entry(parser, &c, &gamma_phi_lambda, 0, &gate->entries[6], &gate->entries[7], &slack);
}

// diag(e^{i zero}, e^{i one})
static int qasm_diagonal_entries(QasmParser *parser, const QasmAngle *zero, const QasmAngle *one, QasmGate *gate)
{
    unsigned long long slack = 0ull;
    return qasm_entry(parser, &parser->one_fixed, zero, 0, &gate->entries[0], &gate->entries[1], &slack)
        && qasm_entry(parser, &parser->one_fixed, one, 0, &gate->entries[2], &gate->entries[3], &slack);
}

// the angle is a whole number of quarter turns (a = 0 and 2b whole): its count mod 4, else -1
static int qasm_quarter_turns(QasmParser *parser, const QasmAngle *angle)
{
    if (!qasm_exact_is_zero(&angle->a.num))
    {
        return -1;
    }
    QasmRational twice;
    QasmRational two;
    qasm_rational_integer(&two, 2);
    if (!qasm_rational_multiply(parser, &angle->b, &two, &twice))
    {
        return -1;
    }
    AnchorExactInteger one;
    qasm_exact_set(&one, 1ull, 0);
    if (!anchor_exact_equal(&twice.den, &one))
    {
        return -1;
    }
    AnchorExactInteger four;
    AnchorExactInteger turns;
    AnchorExactInteger remainder;
    qasm_exact_set(&four, 4ull, 0);
    if (anchor_exact_divide(&twice.num, &four, &turns, &remainder) != ANCHOR_EXACT_OK)
    {
        return -1;
    }
    long long quarter = (long long)qasm_exact_small(&remainder);
    quarter = (remainder.sign < 0) ? (4 - quarter) % 4 : quarter;
    return (int)quarter;
}

typedef struct
{
    const char *name;
    unsigned int params;
    unsigned int qubits;
} QasmBuiltin;

static const QasmBuiltin QASM_BUILTINS[] = {
    {"U", 3u, 1u},     {"u3", 3u, 1u},    {"u", 3u, 1u},     {"u2", 2u, 1u},   {"u1", 1u, 1u},    {"p", 1u, 1u},
    {"CX", 0u, 2u},    {"cx", 0u, 2u},    {"id", 0u, 1u},    {"u0", 1u, 1u},   {"x", 0u, 1u},     {"y", 0u, 1u},
    {"z", 0u, 1u},     {"h", 0u, 1u},     {"s", 0u, 1u},     {"sdg", 0u, 1u},  {"t", 0u, 1u},     {"tdg", 0u, 1u},
    {"rx", 1u, 1u},    {"ry", 1u, 1u},    {"rz", 1u, 1u},    {"sx", 0u, 1u},   {"sxdg", 0u, 1u},  {"cz", 0u, 2u},
    {"cy", 0u, 2u},    {"swap", 0u, 2u},  {"ch", 0u, 2u},    {"ccx", 0u, 3u},  {"cswap", 0u, 3u}, {"crx", 1u, 2u},
    {"cry", 1u, 2u},   {"crz", 1u, 2u},   {"cu1", 1u, 2u},   {"cp", 1u, 2u},   {"cu3", 3u, 2u},   {"cu", 4u, 2u},
    {"csx", 0u, 2u},   {"rzz", 1u, 2u},   {"rxx", 1u, 2u},   {"ryy", 1u, 2u},  {"c3x", 0u, 4u},   {"c4x", 0u, 5u},
    {"iden", 0u, 1u},
};

static const QasmBuiltin *qasm_builtin(const char *name)
{
    for (unsigned int at = 0u; at < (sizeof(QASM_BUILTINS) / sizeof(QASM_BUILTINS[0])); at += 1u)
    {
        if (strcmp(QASM_BUILTINS[at].name, name) == 0)
        {
            return &QASM_BUILTINS[at];
        }
    }
    return NULL;
}

static int qasm_emit(QasmParser *parser, const char *name, const QasmAngle *angles, const unsigned int *qubits,
                     const QasmToken *token);

// a pair gate with its entries computed from U3 plus a phase, under the given controls
static int qasm_emit_u3(QasmParser *parser, const QasmAngle *theta, const QasmAngle *phi, const QasmAngle *lambda,
                        const QasmAngle *gamma, const unsigned int *controls, unsigned int control_count,
                        unsigned int target, const QasmToken *token)
{
    QasmGate gate;
    qasm_gate_start(&gate, QASM_GATE_PAIR, 0u, token);
    gate.target = target;
    qasm_gate_controls(&gate, controls, control_count);
    return qasm_u3_entries(parser, theta, phi, lambda, gamma, &gate) && qasm_push_gate(parser, &gate);
}

// diag(1, e^{i lambda}) under controls: exact where lambda is whole quarter turns
static int qasm_emit_phase(QasmParser *parser, const QasmAngle *lambda, const unsigned int *controls,
                           unsigned int control_count, unsigned int target, const QasmToken *token)
{
    QasmGate gate;
    const int quarters = qasm_quarter_turns(parser, lambda);
    if (parser->failed != 0)
    {
        return 0;
    }
    if (quarters >= 0)
    {
        if (quarters == 0)
        {
            return 1;
        }
        qasm_gate_start(&gate, QASM_GATE_PERMUTE, QASM_PERMUTE_PHASE, token);
        gate.target = target;
        gate.phase = (unsigned int)quarters;
        qasm_gate_controls(&gate, controls, control_count);
        return qasm_push_gate(parser, &gate);
    }
    QasmAngle zero;
    qasm_angle_rational(&zero, 0, 1, 0, 1);
    qasm_gate_start(&gate, QASM_GATE_DIAGONAL, QASM_DIAGONAL_BIT, token);
    gate.target = target;
    qasm_gate_controls(&gate, controls, control_count);
    return qasm_diagonal_entries(parser, &zero, lambda, &gate) && qasm_push_gate(parser, &gate);
}

// a gate whose entries are exact multiples of 2^-(F+1): sx and sxdg, (1 +- i) / 2
static int qasm_emit_sx(QasmParser *parser, int dagger, const unsigned int *controls, unsigned int control_count,
                        unsigned int target, const QasmToken *token)
{
    QasmGate gate;
    qasm_gate_start(&gate, QASM_GATE_PAIR, 0u, token);
    gate.target = target;
    qasm_gate_controls(&gate, controls, control_count);
    const long long half = 1ll << (QASM_FRACTION_BITS - 1u);
    const long long sign = (dagger != 0) ? -1 : 1;
    const long long entries[8] = {half, sign * half, half, -sign * half, half, -sign * half, half, sign * half};
    memcpy(gate.entries, entries, sizeof(entries));
    gate.exact_entries = 1u;
    return qasm_push_gate(parser, &gate);
}

static int qasm_emit_permute(QasmParser *parser, unsigned int shape, unsigned int phase, const unsigned int *controls,
                             unsigned int control_count, unsigned int target, unsigned int second,
                             const QasmToken *token)
{
    QasmGate gate;
    qasm_gate_start(&gate, QASM_GATE_PERMUTE, shape, token);
    gate.target = target;
    gate.second = second;
    gate.phase = phase;
    qasm_gate_controls(&gate, controls, control_count);
    return qasm_push_gate(parser, &gate);
}

static int qasm_emit(QasmParser *parser, const char *name, const QasmAngle *angles, const unsigned int *qubits,
                     const QasmToken *token)
{
    QasmAngle zero;
    QasmAngle half_pi;
    QasmAngle negative_half_pi;
    qasm_angle_rational(&zero, 0, 1, 0, 1);
    qasm_angle_rational(&half_pi, 0, 1, 1, 2);
    qasm_angle_rational(&negative_half_pi, 0, 1, -1, 2);
    const unsigned int q0 = qubits[0];
    if ((strcmp(name, "U") == 0) || (strcmp(name, "u3") == 0) || (strcmp(name, "u") == 0))
    {
        return qasm_emit_u3(parser, &angles[0], &angles[1], &angles[2], &zero, NULL, 0u, q0, token);
    }
    if (strcmp(name, "u2") == 0)
    {
        return qasm_emit_u3(parser, &half_pi, &angles[0], &angles[1], &zero, NULL, 0u, q0, token);
    }
    if ((strcmp(name, "u1") == 0) || (strcmp(name, "p") == 0))
    {
        return qasm_emit_phase(parser, &angles[0], NULL, 0u, q0, token);
    }
    if ((strcmp(name, "id") == 0) || (strcmp(name, "u0") == 0) || (strcmp(name, "iden") == 0))
    {
        return 1;
    }
    if ((strcmp(name, "CX") == 0) || (strcmp(name, "cx") == 0))
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_FLIP, 0u, &qubits[0], 1u, qubits[1], 0u, token);
    }
    if (strcmp(name, "ccx") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_FLIP, 0u, &qubits[0], 2u, qubits[2], 0u, token);
    }
    if (strcmp(name, "c3x") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_FLIP, 0u, &qubits[0], 3u, qubits[3], 0u, token);
    }
    if (strcmp(name, "c4x") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_FLIP, 0u, &qubits[0], 4u, qubits[4], 0u, token);
    }
    if (strcmp(name, "x") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_FLIP, 0u, NULL, 0u, q0, 0u, token);
    }
    if (strcmp(name, "y") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_Y, 0u, NULL, 0u, q0, 0u, token);
    }
    if (strcmp(name, "cy") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_Y, 0u, &qubits[0], 1u, qubits[1], 0u, token);
    }
    if (strcmp(name, "z") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_PHASE, 2u, NULL, 0u, q0, 0u, token);
    }
    if (strcmp(name, "cz") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_PHASE, 2u, &qubits[0], 1u, qubits[1], 0u, token);
    }
    if (strcmp(name, "s") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_PHASE, 1u, NULL, 0u, q0, 0u, token);
    }
    if (strcmp(name, "sdg") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_PHASE, 3u, NULL, 0u, q0, 0u, token);
    }
    if (strcmp(name, "swap") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_SWAP, 0u, NULL, 0u, qubits[0], qubits[1], token);
    }
    if (strcmp(name, "cswap") == 0)
    {
        return qasm_emit_permute(parser, QASM_PERMUTE_SWAP, 0u, &qubits[0], 1u, qubits[1], qubits[2], token);
    }
    if ((strcmp(name, "t") == 0) || (strcmp(name, "tdg") == 0))
    {
        QasmAngle eighth;
        qasm_angle_rational(&eighth, 0, 1, (strcmp(name, "t") == 0) ? 1 : -1, 4);
        return qasm_emit_phase(parser, &eighth, NULL, 0u, q0, token);
    }
    if ((strcmp(name, "cu1") == 0) || (strcmp(name, "cp") == 0))
    {
        return qasm_emit_phase(parser, &angles[0], &qubits[0], 1u, qubits[1], token);
    }
    if ((strcmp(name, "h") == 0) || (strcmp(name, "ch") == 0))
    {
        // H = U3(pi/2, 0, pi)
        QasmAngle pi;
        qasm_angle_rational(&pi, 0, 1, 1, 1);
        const unsigned int controlled = (strcmp(name, "ch") == 0);
        return qasm_emit_u3(parser, &half_pi, &zero, &pi, &zero, &qubits[0], controlled, qubits[controlled], token);
    }
    if ((strcmp(name, "rx") == 0) || (strcmp(name, "crx") == 0))
    {
        // RX(theta) = U3(theta, -pi/2, pi/2)
        const unsigned int controlled = (strcmp(name, "crx") == 0);
        return qasm_emit_u3(parser, &angles[0], &negative_half_pi, &half_pi, &zero, &qubits[0], controlled,
                            qubits[controlled], token);
    }
    if ((strcmp(name, "ry") == 0) || (strcmp(name, "cry") == 0))
    {
        // RY(theta) = U3(theta, 0, 0)
        const unsigned int controlled = (strcmp(name, "cry") == 0);
        return qasm_emit_u3(parser, &angles[0], &zero, &zero, &zero, &qubits[0], controlled, qubits[controlled], token);
    }
    if ((strcmp(name, "rz") == 0) || (strcmp(name, "crz") == 0))
    {
        // RZ(theta) = diag(e^{-i theta/2}, e^{i theta/2})
        const unsigned int controlled = (strcmp(name, "crz") == 0);
        QasmAngle half;
        QasmAngle negative_half;
        if (!qasm_angle_scale(parser, &angles[0], 1, 2, &half) || !qasm_angle_scale(parser, &angles[0], -1, 2, &negative_half))
        {
            return 0;
        }
        QasmGate gate;
        qasm_gate_start(&gate, QASM_GATE_DIAGONAL, QASM_DIAGONAL_BIT, token);
        gate.target = qubits[controlled];
        qasm_gate_controls(&gate, &qubits[0], controlled);
        return qasm_diagonal_entries(parser, &negative_half, &half, &gate) && qasm_push_gate(parser, &gate);
    }
    if (strcmp(name, "rzz") == 0)
    {
        // exp(-i theta/2 Z Z): e^{-i theta/2} at even parity, e^{i theta/2} at odd
        QasmAngle half;
        QasmAngle negative_half;
        if (!qasm_angle_scale(parser, &angles[0], 1, 2, &half) || !qasm_angle_scale(parser, &angles[0], -1, 2, &negative_half))
        {
            return 0;
        }
        QasmGate gate;
        qasm_gate_start(&gate, QASM_GATE_DIAGONAL, QASM_DIAGONAL_PARITY, token);
        gate.target = qubits[0];
        gate.second = qubits[1];
        return qasm_diagonal_entries(parser, &negative_half, &half, &gate) && qasm_push_gate(parser, &gate);
    }
    if (strcmp(name, "rxx") == 0)
    {
        // X = H Z H: RXX = (H x H) RZZ (H x H)
        const unsigned int a[1] = {qubits[0]};
        const unsigned int b[1] = {qubits[1]};
        return qasm_emit(parser, "h", NULL, a, token) && qasm_emit(parser, "h", NULL, b, token)
            && qasm_emit(parser, "rzz", angles, qubits, token) && qasm_emit(parser, "h", NULL, a, token)
            && qasm_emit(parser, "h", NULL, b, token);
    }
    if (strcmp(name, "ryy") == 0)
    {
        // Y = S X Sdg: RYY = (S x S) RXX (Sdg x Sdg)
        const unsigned int a[1] = {qubits[0]};
        const unsigned int b[1] = {qubits[1]};
        return qasm_emit(parser, "sdg", NULL, a, token) && qasm_emit(parser, "sdg", NULL, b, token)
            && qasm_emit(parser, "rxx", angles, qubits, token) && qasm_emit(parser, "s", NULL, a, token)
            && qasm_emit(parser, "s", NULL, b, token);
    }
    if ((strcmp(name, "sx") == 0) || (strcmp(name, "sxdg") == 0))
    {
        return qasm_emit_sx(parser, strcmp(name, "sxdg") == 0, NULL, 0u, q0, token);
    }
    if (strcmp(name, "csx") == 0)
    {
        return qasm_emit_sx(parser, 0, &qubits[0], 1u, qubits[1], token);
    }
    if (strcmp(name, "cu3") == 0)
    {
        return qasm_emit_u3(parser, &angles[0], &angles[1], &angles[2], &zero, &qubits[0], 1u, qubits[1], token);
    }
    if (strcmp(name, "cu") == 0)
    {
        return qasm_emit_u3(parser, &angles[0], &angles[1], &angles[2], &angles[3], &qubits[0], 1u, qubits[1], token);
    }
    qasm_refuse(parser, token, "the gate '%s' has no built-in form", name);
    return 0;
}

// ---------------------------------------------------------------------------------------------------------------
// statements

static const QasmDefinition *qasm_definition(const QasmParser *parser, const char *name)
{
    for (unsigned int at = 0u; at < parser->definition_count; at += 1u)
    {
        if (strcmp(parser->definitions[at].name, name) == 0)
        {
            return &parser->definitions[at];
        }
    }
    return NULL;
}

static const QasmRegister *qasm_register(const QasmRegister *registers, unsigned int count, const char *name)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        if (strcmp(registers[at].name, name) == 0)
        {
            return &registers[at];
        }
    }
    return NULL;
}

static int qasm_statements(QasmParser *parser, const QasmScope *scope, unsigned int end);

// one gate on resolved qubits: a definition's body, or a built-in
static int qasm_apply(QasmParser *parser, const char *name, const QasmToken *token, const QasmAngle *angles,
                      unsigned int angle_count, const unsigned int *qubits, unsigned int qubit_count)
{
    for (unsigned int one = 0u; one < qubit_count; one += 1u)
    {
        if (parser->measured_qubit[qubits[one]] != 0u)
        {
            qasm_refuse(parser, token, "a gate follows the measure of qubit %u: only a final measure is read", qubits[one]);
            return 0;
        }
        for (unsigned int two = one + 1u; two < qubit_count; two += 1u)
        {
            if (qubits[one] == qubits[two])
            {
                qasm_refuse(parser, token, "the gate '%s' names qubit %u twice", name, qubits[one]);
                return 0;
            }
        }
    }
    const QasmDefinition *const definition = qasm_definition(parser, name);
    if (definition != NULL)
    {
        if ((angle_count != definition->params) || (qubit_count != definition->args))
        {
            qasm_refuse(parser, token, "the gate '%s' takes %u parameters and %u qubits", name, definition->params,
                        definition->args);
            return 0;
        }
        if (parser->depth >= QASM_EXPAND_DEPTH_MOST)
        {
            qasm_refuse(parser, token, "gate definitions nest past %u", QASM_EXPAND_DEPTH_MOST);
            return 0;
        }
        const QasmScope inner = {definition, angles, qubits};
        const unsigned int resume = parser->at;
        parser->at = definition->body_start;
        parser->depth += 1u;
        const int good = qasm_statements(parser, &inner, definition->body_end);
        parser->depth -= 1u;
        parser->at = resume;
        return good;
    }
    const QasmBuiltin *const builtin = qasm_builtin(name);
    if (builtin == NULL)
    {
        qasm_refuse(parser, token, "the gate '%s' is not defined", name);
        return 0;
    }
    if ((angle_count != builtin->params) || (qubit_count != builtin->qubits))
    {
        qasm_refuse(parser, token, "the gate '%s' takes %u parameters and %u qubits", name, builtin->params,
                    builtin->qubits);
        return 0;
    }
    return qasm_emit(parser, name, angles, qubits, token);
}

// a register argument: a whole register (index -1) or one of its bits
typedef struct
{
    const QasmRegister *reg;
    long long index;
} QasmArgument;

static int qasm_argument(QasmParser *parser, const QasmRegister *registers, unsigned int count, QasmArgument *argument)
{
    char name[QASM_NAME_ROOM];
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_expect_ident(parser, name, NULL))
    {
        return 0;
    }
    argument->reg = qasm_register(registers, count, name);
    if (argument->reg == NULL)
    {
        qasm_refuse(parser, token, "'%s' is not a register of this kind", name);
        return 0;
    }
    argument->index = -1;
    if (qasm_accept(parser, "["))
    {
        unsigned int index = 0u;
        const QasmToken *const at = qasm_peek(parser);
        if (!qasm_expect_count(parser, &index) || !qasm_expect(parser, "]"))
        {
            return 0;
        }
        if (index >= argument->reg->size)
        {
            qasm_refuse(parser, at, "%s[%u] is past the register's %u", name, index, argument->reg->size);
            return 0;
        }
        argument->index = (long long)index;
    }
    return 1;
}

static int qasm_application(QasmParser *parser, const QasmScope *scope)
{
    const QasmToken *const token = qasm_peek(parser);
    char name[QASM_NAME_ROOM];
    if (!qasm_expect_ident(parser, name, NULL))
    {
        return 0;
    }
    QasmAngle *const angles = (QasmAngle *)malloc(QASM_GATE_PARAMS_MOST * sizeof(QasmAngle));
    if (!QASM_HELD(angles != NULL, parser, parser->error))
    {
        parser->failed = 1;
        return 0;
    }
    unsigned int angle_count = 0u;
    int good = 1;
    if (qasm_accept(parser, "("))
    {
        if (!qasm_accept(parser, ")"))
        {
            do
            {
                if (angle_count == QASM_GATE_PARAMS_MOST)
                {
                    qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u parameters", QASM_GATE_PARAMS_MOST);
                    good = 0;
                    break;
                }
                good = qasm_expression(parser, scope, &angles[angle_count]);
                angle_count += 1u;
            } while (good && qasm_accept(parser, ","));
            good = good && qasm_expect(parser, ")");
        }
    }
    unsigned int qubits[QASM_GATE_ARGS_MOST];
    unsigned int qubit_count = 0u;
    if (good && (scope != NULL) && (scope->definition != NULL))
    {
        // inside a definition: plain argument names
        do
        {
            unsigned int at = 0u;
            const QasmToken *const argument = qasm_peek(parser);
            if (!qasm_expect_ident(parser, NULL, &at))
            {
                good = 0;
                break;
            }
            unsigned int found = QASM_GATE_ARGS_MOST;
            for (unsigned int arg = 0u; arg < scope->definition->args; arg += 1u)
            {
                if (qasm_tokens_equal(parser, argument, &parser->tokens[scope->definition->arg_token[arg]]))
                {
                    found = arg;
                }
            }
            if ((found == QASM_GATE_ARGS_MOST) || (qubit_count == QASM_GATE_ARGS_MOST))
            {
                qasm_refuse(parser, argument, "not an argument of this gate");
                good = 0;
                break;
            }
            qubits[qubit_count] = scope->qubits[found];
            qubit_count += 1u;
        } while (qasm_accept(parser, ","));
        good = good && qasm_expect(parser, ";") && qasm_apply(parser, name, token, angles, angle_count, qubits, qubit_count);
        free(angles);
        return good;
    }
    // at the top: register bits, or whole registers broadcast over their common size
    QasmArgument arguments[QASM_GATE_ARGS_MOST];
    unsigned int argument_count = 0u;
    unsigned int broadcast = 0u;
    if (good)
    {
        do
        {
            if (argument_count == QASM_GATE_ARGS_MOST)
            {
                qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u qubits", QASM_GATE_ARGS_MOST);
                good = 0;
                break;
            }
            const QasmToken *const at = qasm_peek(parser);
            if (!qasm_argument(parser, parser->qregs, parser->qreg_count, &arguments[argument_count]))
            {
                good = 0;
                break;
            }
            if (arguments[argument_count].index < 0)
            {
                if ((broadcast != 0u) && (broadcast != arguments[argument_count].reg->size))
                {
                    qasm_refuse(parser, at, "registers of different sizes are applied together");
                    good = 0;
                    break;
                }
                broadcast = arguments[argument_count].reg->size;
            }
            argument_count += 1u;
        } while (qasm_accept(parser, ","));
        good = good && qasm_expect(parser, ";");
    }
    const unsigned int times = (broadcast != 0u) ? broadcast : 1u;
    for (unsigned int time = 0u; good && (time < times); time += 1u)
    {
        for (unsigned int argument = 0u; argument < argument_count; argument += 1u)
        {
            const long long index = (arguments[argument].index < 0) ? (long long)time : arguments[argument].index;
            qubits[argument] = arguments[argument].reg->offset + (unsigned int)index;
        }
        good = qasm_apply(parser, name, token, angles, angle_count, qubits, argument_count);
    }
    free(angles);
    return good;
}

static int qasm_measure(QasmParser *parser)
{
    const QasmToken *const token = qasm_peek(parser);
    QasmArgument from;
    QasmArgument into;
    if (!qasm_argument(parser, parser->qregs, parser->qreg_count, &from) || !qasm_expect(parser, "->")
     || !qasm_argument(parser, parser->cregs, parser->creg_count, &into) || !qasm_expect(parser, ";"))
    {
        return 0;
    }
    if ((from.index < 0) != (into.index < 0))
    {
        qasm_refuse(parser, token, "a measure takes a register into a register, or a bit into a bit");
        return 0;
    }
    if ((from.index < 0) && (from.reg->size != into.reg->size))
    {
        qasm_refuse(parser, token, "a measure takes registers of one size");
        return 0;
    }
    const unsigned int times = (from.index < 0) ? from.reg->size : 1u;
    for (unsigned int time = 0u; time < times; time += 1u)
    {
        const unsigned int qubit = from.reg->offset + ((from.index < 0) ? time : (unsigned int)from.index);
        const unsigned int clbit = into.reg->offset + ((into.index < 0) ? time : (unsigned int)into.index);
        if (parser->measured_qubit[qubit] != 0u)
        {
            qasm_refuse(parser, token, "qubit %u is measured twice", qubit);
            return 0;
        }
        if (parser->clbit_written[clbit] != 0u)
        {
            qasm_refuse(parser, token, "clbit %u is written twice", clbit);
            return 0;
        }
        parser->measured_qubit[qubit] = 1u;
        parser->clbit_written[clbit] = 1u;
        parser->circuit->measure[qubit] = clbit + 1u;
        parser->circuit->measured += 1u;
    }
    return 1;
}

static int qasm_declare(QasmParser *parser, int quantum)
{
    char name[QASM_NAME_ROOM];
    const QasmToken *const token = qasm_peek(parser);
    unsigned int size = 0u;
    if (!qasm_expect_ident(parser, name, NULL) || !qasm_expect(parser, "[") || !qasm_expect_count(parser, &size)
     || !qasm_expect(parser, "]") || !qasm_expect(parser, ";"))
    {
        return 0;
    }
    QasmRegister *const registers = (quantum != 0) ? parser->qregs : parser->cregs;
    unsigned int *const count = (quantum != 0) ? &parser->qreg_count : &parser->creg_count;
    unsigned int *const total = (quantum != 0) ? &parser->circuit->qubits : &parser->circuit->clbits;
    const unsigned int most = (quantum != 0) ? QASM_QUBITS_MOST : QASM_CLBITS_MOST;
    if ((qasm_register(parser->qregs, parser->qreg_count, name) != NULL)
     || (qasm_register(parser->cregs, parser->creg_count, name) != NULL))
    {
        qasm_refuse(parser, token, "the register '%s' is declared twice", name);
        return 0;
    }
    if ((size == 0u) || (*count == QASM_REGISTERS_MOST) || ((*total + size) > most))
    {
        qasm_refuse(parser, token, (quantum != 0) ? "past %u qubits: the index names a record by 32 bits"
                                                  : "past %u clbits: an outcome is one 64-bit word",
                    most);
        return 0;
    }
    snprintf(registers[*count].name, QASM_NAME_ROOM, "%s", name);
    registers[*count].offset = *total;
    registers[*count].size = size;
    *count += 1u;
    *total += size;
    return 1;
}

static int qasm_define(QasmParser *parser)
{
    if (parser->definition_count == parser->definition_room)
    {
        const unsigned int room = (parser->definition_room == 0u) ? 32u : (parser->definition_room * 2u);
        QasmDefinition *const grown = (QasmDefinition *)realloc(parser->definitions, (size_t)room * sizeof(QasmDefinition));
        if (!QASM_HELD(grown != NULL, parser, parser->error))
        {
            parser->failed = 1;
            return 0;
        }
        parser->definitions = grown;
        parser->definition_room = room;
    }
    QasmDefinition *const definition = &parser->definitions[parser->definition_count];
    memset(definition, 0, sizeof(*definition));
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_expect_ident(parser, definition->name, NULL))
    {
        return 0;
    }
    if (qasm_definition(parser, definition->name) != NULL)
    {
        qasm_refuse(parser, token, "the gate '%s' is defined twice", definition->name);
        return 0;
    }
    if (qasm_accept(parser, "(") && !qasm_accept(parser, ")"))
    {
        do
        {
            if (definition->params == QASM_GATE_PARAMS_MOST)
            {
                qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u parameters", QASM_GATE_PARAMS_MOST);
                return 0;
            }
            if (!qasm_expect_ident(parser, NULL, &definition->param_token[definition->params]))
            {
                return 0;
            }
            definition->params += 1u;
        } while (qasm_accept(parser, ","));
        if (!qasm_expect(parser, ")"))
        {
            return 0;
        }
    }
    do
    {
        if (definition->args == QASM_GATE_ARGS_MOST)
        {
            qasm_refuse(parser, qasm_peek(parser), "a gate takes at most %u qubits", QASM_GATE_ARGS_MOST);
            return 0;
        }
        if (!qasm_expect_ident(parser, NULL, &definition->arg_token[definition->args]))
        {
            return 0;
        }
        definition->args += 1u;
    } while (qasm_accept(parser, ","));
    if (!qasm_expect(parser, "{"))
    {
        return 0;
    }
    definition->body_start = parser->at;
    while ((qasm_peek(parser)->kind != QASM_TOKEN_END) && !qasm_token_is(parser, qasm_peek(parser), "}"))
    {
        parser->at += 1u;
    }
    definition->body_end = parser->at;
    if (!qasm_expect(parser, "}"))
    {
        return 0;
    }
    parser->definition_count += 1u;
    return 1;
}

// statements up to the token `end`: inside a definition (scope set) only gates and barriers
static int qasm_statements(QasmParser *parser, const QasmScope *scope, unsigned int end)
{
    const int top = (scope == NULL) || (scope->definition == NULL);
    while ((parser->failed == 0) && (parser->at < end) && (qasm_peek(parser)->kind != QASM_TOKEN_END))
    {
        const QasmToken *const token = qasm_peek(parser);
        if (token->kind != QASM_TOKEN_IDENT)
        {
            qasm_refuse(parser, token, "a statement was expected here");
            return 0;
        }
        if (qasm_token_is(parser, token, "barrier"))
        {
            parser->at += 1u;
            while ((qasm_peek(parser)->kind != QASM_TOKEN_END) && !qasm_accept(parser, ";"))
            {
                parser->at += 1u;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "include"))
        {
            parser->at += 1u;
            const QasmToken *const file = qasm_peek(parser);
            if ((file->kind != QASM_TOKEN_STRING) || !qasm_token_is(parser, file, "\"qelib1.inc\""))
            {
                qasm_refuse(parser, file, "only \"qelib1.inc\" is included: its gates are built in");
                return 0;
            }
            parser->at += 1u;
            if (!qasm_expect(parser, ";"))
            {
                return 0;
            }
            continue;
        }
        if (top && (qasm_token_is(parser, token, "qreg") || qasm_token_is(parser, token, "creg")))
        {
            parser->at += 1u;
            if (!qasm_declare(parser, qasm_token_is(parser, token, "qreg")))
            {
                return 0;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "gate"))
        {
            parser->at += 1u;
            if (!qasm_define(parser))
            {
                return 0;
            }
            continue;
        }
        if (top && qasm_token_is(parser, token, "measure"))
        {
            parser->at += 1u;
            if (!qasm_measure(parser))
            {
                return 0;
            }
            continue;
        }
        if (qasm_token_is(parser, token, "opaque") || qasm_token_is(parser, token, "reset")
         || qasm_token_is(parser, token, "if") || qasm_token_is(parser, token, "measure")
         || qasm_token_is(parser, token, "OPENQASM") || qasm_token_is(parser, token, "include")
         || qasm_token_is(parser, token, "gate") || qasm_token_is(parser, token, "qreg")
         || qasm_token_is(parser, token, "creg"))
        {
            char name[QASM_NAME_ROOM];
            qasm_token_name(parser, token, name);
            qasm_refuse(parser, token, top ? "'%s' is not read: only unitary gates and a final measure are"
                                           : "'%s' is not read inside a gate definition",
                        name);
            return 0;
        }
        if (!qasm_application(parser, scope))
        {
            return 0;
        }
    }
    return parser->failed == 0;
}

static int qasm_header(QasmParser *parser)
{
    const QasmToken *const token = qasm_peek(parser);
    if (!qasm_token_is(parser, token, "OPENQASM"))
    {
        qasm_refuse(parser, token, "a program opens with OPENQASM 2.0;");
        return 0;
    }
    parser->at += 1u;
    const QasmToken *const version = qasm_peek(parser);
    if ((version->kind != QASM_TOKEN_NUMBER)
     || !(qasm_token_is(parser, version, "2.0") || qasm_token_is(parser, version, "2")))
    {
        qasm_refuse(parser, version, "only OpenQASM 2.0 is read");
        return 0;
    }
    parser->at += 1u;
    return qasm_expect(parser, ";");
}

long qasm_read(const QasmReadRequest *request, QasmCircuit *circuit)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_REFUSED;
    }
    EngineError *const error = request->error;
    if (!QASM_HELD((circuit != NULL) && ((request->text != NULL) || (request->path != NULL)), request, error))
    {
        return QASM_REFUSED;
    }
    memset(circuit, 0, sizeof(*circuit));
    char *owned = NULL;
    const char *text = request->text;
    size_t length = request->length;
    if (text == NULL)
    {
        FILE *const file = fopen(request->path, "rb");
        if (!engine_io_check(file != NULL, ENGINE_MODULE_QASM, __LINE__, request->path, error))
        {
            if (request->reason != NULL)
            {
                snprintf(request->reason, request->reason_room, "%s: could not be opened", request->path);
            }
            return QASM_REFUSED;
        }
        size_t room = 65536u;
        owned = (char *)malloc(room);
        length = 0u;
        while (owned != NULL)
        {
            const size_t got = fread(owned + length, 1u, room - length, file);
            length += got;
            if (length < room)
            {
                break;
            }
            room *= 2u;
            char *const grown = (char *)realloc(owned, room);
            if (grown == NULL)
            {
                free(owned);
                owned = NULL;
            }
            owned = grown;
        }
        fclose(file);
        if (!QASM_HELD(owned != NULL, request, error))
        {
            return QASM_REFUSED;
        }
        text = owned;
    }
    QasmParser *const parser = (QasmParser *)calloc(1u, sizeof(QasmParser));
    if (!QASM_HELD(parser != NULL, request, error))
    {
        free(owned);
        return QASM_REFUSED;
    }
    parser->path = (request->path != NULL) ? request->path : "<text>";
    parser->text = text;
    parser->length = length;
    parser->circuit = circuit;
    parser->reason = request->reason;
    parser->reason_room = request->reason_room;
    parser->error = error;
    int good = qasm_fixed_constants(parser) && qasm_lex(parser) && qasm_header(parser)
            && qasm_statements(parser, NULL, 0xFFFFFFFFu);
    if (good && (circuit->qubits == 0u))
    {
        qasm_refuse(parser, qasm_peek(parser), "no qreg is declared");
        good = 0;
    }
    if (good && (circuit->measured == 0u))
    {
        // no measure: every qubit is read, qubit i into clbit i
        if (circuit->qubits > QASM_CLBITS_MOST)
        {
            qasm_refuse(parser, qasm_peek(parser), "no measure, and more qubits than an outcome holds");
            good = 0;
        }
        for (unsigned int qubit = 0u; good && (qubit < circuit->qubits); qubit += 1u)
        {
            circuit->measure[qubit] = qubit + 1u;
        }
        if (good)
        {
            circuit->measured = circuit->qubits;
            circuit->clbits = (circuit->clbits > circuit->qubits) ? circuit->clbits : circuit->qubits;
            circuit->measured_all_by_default = 1u;
        }
    }
    free(parser->tokens);
    free(parser->definitions);
    free(parser);
    free(owned);
    if (!good)
    {
        qasm_release(circuit);
        return QASM_REFUSED;
    }
    return 0L;
}

void qasm_release(QasmCircuit *circuit)
{
    if (circuit == NULL)
    {
        return;
    }
    free(circuit->gates);
    circuit->gates = NULL;
    circuit->gate_count = 0u;
    circuit->gate_room = 0u;
}

void qasm_bitstring(const QasmCircuit *circuit, unsigned long long outcome, char *text, size_t room)
{
    size_t at = 0u;
    for (unsigned int clbit = circuit->clbits; (clbit > 0u) && ((at + 1u) < room); clbit -= 1u)
    {
        text[at] = (((outcome >> (clbit - 1u)) & 1ull) != 0ull) ? '1' : '0';
        at += 1u;
    }
    if (room != 0u)
    {
        text[at] = '\0';
    }
}

void qasm_units_decimal(const unsigned int units[QASM_WIDE_LIMBS], unsigned int places, char *text, size_t room)
{
    AnchorExactInteger value;
    AnchorExactInteger scale;
    AnchorExactInteger whole;
    AnchorExactInteger part;
    qasm_wide_to_exact(units, &value);
    qasm_exact_power_of_two(&scale, 2u * QASM_FRACTION_BITS);
    if ((anchor_exact_divide(&value, &scale, &whole, &part) != ANCHOR_EXACT_OK)
     || (anchor_exact_scale_by_ten(&part, places) != ANCHOR_EXACT_OK)
     || (anchor_exact_divide(&part, &scale, &part, &value) != ANCHOR_EXACT_OK))
    {
        snprintf(text, room, "?");
        return;
    }
    char digits[64];
    unsigned long long fraction = qasm_exact_small(&part);
    for (unsigned int at = places; at > 0u; at -= 1u)
    {
        digits[at - 1u] = (char)('0' + (fraction % 10ull));
        fraction /= 10ull;
    }
    digits[(places < 63u) ? places : 63u] = '\0';
    snprintf(text, room, "%llu.%s", qasm_exact_small(&whole), digits);
}
