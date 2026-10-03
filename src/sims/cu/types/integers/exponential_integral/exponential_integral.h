// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The exponential integral E1(x), e^(-x), ln x and Euler's gamma, each read exactly at a rational argument
#ifndef EXPONENTIAL_INTEGRAL_H
#define EXPONENTIAL_INTEGRAL_H

// Each function gives floor(f(x) 2^bits) for x = numerator / denominator, bits from the caller. The value is
// bracketed in integers at 2^(bits + guard): every term is floored for the low end and ceiled for the high end, and a
// tail past the last term is bounded and added to the high end. The guard grows until both ends floor to one integer
// at 2^bits, and that integer is the answer. No term count is written in: a series runs until its next term's high
// end is at most one unit at 2^(bits + guard), and a continued fraction deepens until its two convergents agree.
// - e^x by its series of positive terms, the tail past term N at most term N x / (N + 1 - x) once N + 1 > x;
//   e^(-x) is 1 / e^x, its ends swapped.
// - ln n for a whole n as e ln 2 + 2 artanh((n - 2^e) / (n + 2^e)), 2^e the power of two nearest n, and ln 2 as
//   2 artanh(1/3). artanh y is the series of y^(2k + 1) / (2k + 1), the tail past term N at most
//   y^(2N + 1) y^2 / ((2N + 3) (1 - y^2)). ln(p / q) is ln p - ln q.
// - e^x E1(x) by the continued fraction 1 / (x + 1 / (1 + 1 / (x + 2 / (1 + 2 / (x + ...))))). Its elements are
//   positive, and its value lies between any two consecutive convergents. Each convergent is evaluated from its
//   deepest level up, every level rounded outward. E1(x) is that bracket times e^(-x)'s; both are positive.
// - gamma = S(1) - E1(1), S(x) = sum over k >= 1 of (-1)^(k + 1) x^k / (k k!), ln 1 being 0. S's terms fall from
//   k >= x on, and S lies between two consecutive partial sums taken past that point.
// x is positive for E1, e^(-x) and ln. Every value is an AnchorExactInteger of the build's width (SIM_EXACT_LIMBS sets
// it).

#include "sim_rational.h"

// how a reading ended: its floor is held, or the build's exact width cannot hold the bracket, or the argument is outside
// the function's domain
#define EXPONENTIAL_INTEGRAL_HELD 0
#define EXPONENTIAL_INTEGRAL_WIDTH 1
#define EXPONENTIAL_INTEGRAL_DOMAIN 2

// A bracket at 2^bits: low <= f(x) 2^bits <= high, and the floor both ends give
typedef struct
{
    AnchorExactInteger low;
    AnchorExactInteger high;
    AnchorExactInteger floor_value;
    unsigned int bits;
} ExponentialIntegralBracket;

// E1(x) for x > 0
int exponential_integral_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket);

// E1(x) for x > 0 by the series -gamma - ln x + S(x), the continued fraction's check
int exponential_integral_series_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket);

// e^(-x) for x >= 0
int exponential_negative_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket);

// ln x for x > 0
int logarithm_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket);

// Euler's gamma
int euler_gamma_floor(unsigned int bits, ExponentialIntegralBracket *bracket);

// the bits the build's exact width holds
unsigned int exponential_integral_width(void);

#endif
