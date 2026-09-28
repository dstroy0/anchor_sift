// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_trig.c: cosine and sine, and fixed-point rounding
#include "qasm_internal.h"

// cos and sin of the angle at QASM_GUARD_BITS; *slack gains the counted error, in units
int qasm_cos_sin(QasmParser *parser, const QasmAngle *angle, AnchorExactInteger *cosine, AnchorExactInteger *sine,
                 unsigned long long *slack)
{
    // b mod 2, exactly: b - 2 floor(b / 2)
    QasmFraction b = angle->b;
    {
        AnchorExactInteger twice_den;
        AnchorExactInteger turns;
        AnchorExactInteger remainder;
        AnchorExactInteger two;
        qasm_exact_set(&two, 2ull, 0);
        if (!qasm_exact_ok(parser, anchor_exact_multiply(&b.den, &two, &twice_den)) ||
            !qasm_exact_ok(parser, anchor_exact_divide(&b.num, &twice_den, &turns, &remainder)))
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
        if (!qasm_fraction_reduce(parser, &b))
        {
            return 0;
        }
    }
    // x = a 2^G + b pi 2^G: a's floor loses one unit, b P loses |b| * 1 + 1 <= 3, P itself is within one of pi 2^G
    AnchorExactInteger x;
    AnchorExactInteger b_part;
    if (!qasm_fixed_rational(parser, &angle->a, NULL, &x) ||
        !qasm_fixed_rational(parser, &b, &parser->pi_fixed, &b_part) ||
        !qasm_exact_ok(parser, anchor_exact_add(&x, &b_part, &x)))
    {
        return 0;
    }
    unsigned long long error = 6ull;
    // into [-pi, pi] by whole turns: each turn taken carries 2P's error, two units
    AnchorExactInteger turn;
    AnchorExactInteger turns;
    AnchorExactInteger remainder;
    if (!qasm_exact_ok(parser, anchor_exact_add(&parser->pi_fixed, &parser->pi_fixed, &turn)) ||
        !qasm_exact_ok(parser, anchor_exact_divide(&x, &turn, &turns, &remainder)))
    {
        return 0;
    }
    const unsigned long long turns_count = qasm_exact_small(&turns);
    if ((turns_count == ~0ull) || (turns_count > (1ull << 40u)))
    {
        qasm_refuse(parser, &parser->tokens[parser->at], "an angle past 2^40 turns is not read");
        return 0;
    }
    error += 2ull * (turns_count + 1ull);
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
        if (!qasm_fixed_multiply(parser, &term, &r2, &product) ||
            !qasm_fixed_divide_small(parser, &product, (unsigned long long)((2u * k2) - 1u) * (2ull * k2), &term))
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
        if (!qasm_fixed_multiply(parser, &sin_term, &r2, &product) ||
            !qasm_fixed_divide_small(parser, &product, (2ull * k2) * ((2ull * k2) + 1ull), &sin_term))
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
int qasm_fixed_round(QasmParser *parser, const AnchorExactInteger *value, long long *rounded)
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
