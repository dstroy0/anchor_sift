// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_exact.c: exact fractions, angles and fixed point
#include "qasm_internal.h"

// pi to 110 places; its error, below 10^-110, is far under one unit at QASM_GUARD_BITS
static const char QASM_PI_TEXT[] =
    "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862"
    "803482534211706798214808651";

void qasm_refuse(QasmParser *parser, const QasmToken *token, const char *format, ...)
{
    if (parser->failed != 0)
    {
        return;
    }
    parser->failed = 1;
    char message[QASM_REASON_CAPACITY];
    va_list list;
    va_start(list, format);
    vsnprintf(message, sizeof(message), format, list);
    va_end(list);
    if ((parser->reason != NULL) && (parser->reason_capacity != 0u))
    {
        snprintf(parser->reason, parser->reason_capacity, "%s:%u:%u: %s", parser->path,
                 (token != NULL) ? token->line : 0u, (token != NULL) ? token->column : 0u, message);
    }
    QASM_CHECK(0, token, parser->error);
}

// ---------------------------------------------------------------------------------------------------------------
// exact integers, rationals and angles

int qasm_exact_ok(QasmParser *parser, AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        qasm_refuse(parser, (parser->at < parser->token_count) ? &parser->tokens[parser->at] : NULL,
                    "a value outgrew the exact integer's width");
        return 0;
    }
    return 1;
}

void qasm_exact_set(AnchorExactInteger *value, unsigned long long magnitude, int negative)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(magnitude & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(magnitude >> 32u);
    value->sign = (magnitude == 0ull) ? 0 : ((negative != 0) ? -1 : 1);
}

void qasm_exact_power_of_two(AnchorExactInteger *value, unsigned int bits)
{
    anchor_exact_zero(value);
    value->limb[bits >> 5u] = 1u << (bits & 31u);
    value->sign = 1;
}

int qasm_exact_is_zero(const AnchorExactInteger *value)
{
    return value->sign == 0;
}

void qasm_fraction_integer(QasmFraction *value, long long integer)
{
    qasm_exact_set(&value->num, (integer < 0) ? (unsigned long long)(-integer) : (unsigned long long)integer,
                   integer < 0);
    qasm_exact_set(&value->den, 1ull, 0);
}

int qasm_fraction_reduce(QasmParser *parser, QasmFraction *value)
{
    if (qasm_exact_is_zero(&value->num))
    {
        qasm_exact_set(&value->den, 1ull, 0);
        return 1;
    }
    AnchorExactInteger divisor;
    AnchorExactInteger remainder;
    if (!qasm_exact_ok(parser, anchor_exact_gcd(&value->num, &value->den, &divisor)) ||
        !qasm_exact_ok(parser, anchor_exact_divide(&value->num, &divisor, &value->num, &remainder)) ||
        !qasm_exact_ok(parser, anchor_exact_divide(&value->den, &divisor, &value->den, &remainder)))
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

int qasm_fraction_add(QasmParser *parser, const QasmFraction *left, const QasmFraction *right, int subtract,
                      QasmFraction *result)
{
    AnchorExactInteger one;
    AnchorExactInteger two;
    AnchorExactInteger den;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->den, &one)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&right->num, &left->den, &two)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->den, &den)))
    {
        return 0;
    }
    const AnchorExactStatus status =
        (subtract != 0) ? anchor_exact_subtract(&one, &two, &result->num) : anchor_exact_add(&one, &two, &result->num);
    if (!qasm_exact_ok(parser, status))
    {
        return 0;
    }
    result->den = den;
    return qasm_fraction_reduce(parser, result);
}

int qasm_fraction_multiply(QasmParser *parser, const QasmFraction *left, const QasmFraction *right,
                           QasmFraction *result)
{
    QasmFraction made;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->num, &made.num)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->den, &made.den)))
    {
        return 0;
    }
    *result = made;
    return qasm_fraction_reduce(parser, result);
}

int qasm_fraction_divide(QasmParser *parser, const QasmFraction *left, const QasmFraction *right, QasmFraction *result)
{
    QasmFraction made;
    if (!qasm_exact_ok(parser, anchor_exact_multiply(&left->num, &right->den, &made.num)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&left->den, &right->num, &made.den)))
    {
        return 0;
    }
    *result = made;
    return qasm_fraction_reduce(parser, result);
}

void qasm_angle_rational(QasmAngle *angle, long long a_num, long long a_den, long long b_num, long long b_den)
{
    qasm_fraction_integer(&angle->a, a_num);
    qasm_exact_set(&angle->a.den, (unsigned long long)a_den, 0);
    qasm_fraction_integer(&angle->b, b_num);
    qasm_exact_set(&angle->b.den, (unsigned long long)b_den, 0);
}

int qasm_angle_add(QasmParser *parser, const QasmAngle *left, const QasmAngle *right, int subtract, QasmAngle *result)
{
    return qasm_fraction_add(parser, &left->a, &right->a, subtract, &result->a) &&
           qasm_fraction_add(parser, &left->b, &right->b, subtract, &result->b);
}

int qasm_angle_scale(QasmParser *parser, const QasmAngle *angle, long long num, long long den, QasmAngle *result)
{
    QasmFraction factor;
    qasm_fraction_integer(&factor, num);
    qasm_exact_set(&factor.den, (unsigned long long)den, 0);
    return qasm_fraction_multiply(parser, &angle->a, &factor, &result->a) &&
           qasm_fraction_multiply(parser, &angle->b, &factor, &result->b);
}

// ---------------------------------------------------------------------------------------------------------------
// fixed point at QASM_GUARD_BITS: value * 2^QASM_GUARD_BITS as an exact integer

// (left * right) / 2^QASM_GUARD_BITS, toward zero: at most one unit lost
int qasm_fixed_multiply(QasmParser *parser, const AnchorExactInteger *left, const AnchorExactInteger *right,
                        AnchorExactInteger *result)
{
    AnchorExactInteger product;
    AnchorExactInteger scale;
    AnchorExactInteger remainder;
    qasm_exact_power_of_two(&scale, QASM_GUARD_BITS);
    return qasm_exact_ok(parser, anchor_exact_multiply(left, right, &product)) &&
           qasm_exact_ok(parser, anchor_exact_divide(&product, &scale, result, &remainder));
}

// value / divisor for a small positive divisor, toward zero: at most one unit lost
int qasm_fixed_divide_small(QasmParser *parser, const AnchorExactInteger *value, unsigned long long divisor,
                            AnchorExactInteger *result)
{
    AnchorExactInteger by;
    AnchorExactInteger remainder;
    qasm_exact_set(&by, divisor, 0);
    return qasm_exact_ok(parser, anchor_exact_divide(value, &by, result, &remainder));
}

// the rational times 2^QASM_GUARD_BITS times `with` (or 2^QASM_GUARD_BITS alone when with is NULL), toward zero
int qasm_fixed_rational(QasmParser *parser, const QasmFraction *value, const AnchorExactInteger *with,
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

int qasm_fixed_constants(QasmParser *parser)
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
    if (!qasm_exact_ok(parser, anchor_exact_scale_by_ten(&ten_power, places)) ||
        !qasm_exact_ok(parser, anchor_exact_multiply(&pi_text, &scale, &product)) ||
        !qasm_exact_ok(parser, anchor_exact_divide(&product, &ten_power, &parser->pi_fixed, &remainder)))
    {
        return 0;
    }
    parser->one_fixed = scale;
    return 1;
}

// |value| as an unsigned 64-bit count, or ~0 where it does not fit
unsigned long long qasm_exact_small(const AnchorExactInteger *value)
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
