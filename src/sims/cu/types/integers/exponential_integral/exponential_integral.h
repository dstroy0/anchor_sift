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

// The heat exterior and its pressure, each read as the functions above are (exponential_integral_heat.cu), h = p / q
// with 0 <= h < 1 wherever it enters H:
// - x^h = e^(h ln x), e^y read at both ends of y's bracket.
// - Gamma(1 + h) = T^h e^(-T) (T sum over k >= 0 of T^k / (1 + h)_(k + 1) + theta), theta in [1, 1 + h / T], for a
//   whole T near W ln 2: the sum is gamma(1 + h, T), and the rest is Gamma(1 + h, T) held between T^h e^(-T) and
//   T^h e^(-T) (1 + h / T) by the concavity of t^h.
// - H(Z) = Gamma(1 + h)^(-1) int_0^inf e^(-v) v^h (1 + Z v)^(-h) dv = Z^(-1 - h) U(1 + h, 2, 1 / Z), U Tricomi's. As
//   (1 + u)^(-h) is completely monotone, H(Z) lies between any two consecutive partial sums of
//   sum over k of binom(-h, k) (1 + h)_k Z^k, and that sum is read where 1 / Z >= z0, z0 a whole number near W ln 2,
//   which holds its least term below one unit. Past it, w = U(1 + h, 2, z) is carried down from z0 to 1 / Z by its
//   Taylor series under z w'' + (2 - z) w' - (1 + h) w = 0, every step at most a quarter of z, and each truncated
//   series bounded by Cauchy's estimate with |w| <= 1 / (Gamma(1 + h) Re z) on the right half-plane.
// - Pi_ext(X, eta) = -int_X^inf c^2 x^(-2 - 2h) H(2 d / x)^2 / 2 dx, d = 1 - eta^2. With z = x / (2 d) it is
//   -(c^2 / 2) (2 d)^(-1 - 2h) int_(X / (2 d))^inf U(1 + h, 2, z)^2 dz: the Taylor steps integrate w^2 down to z0, and
//   past z0 the integral is z0^(-1 - 2h) int_0^1 u^(2h) H(u / z0)^2 du, between the integrals of the two partial sums'
//   squares. Where X / (2 d) >= z0 the integral is X^(-1 - 2h) int_0^1 u^(2h) H(2 d u / X)^2 du times (2 d)^(1 + 2h).

// x^h for x > 0 and h of either sign
int power_floor(const SimRational *x, const SimRational *h, unsigned int bits, ExponentialIntegralBracket *bracket);

// Gamma(1 + h) for 0 <= h < 1
int gamma_floor(const SimRational *h, unsigned int bits, ExponentialIntegralBracket *bracket);

// H(Z) for Z >= 0 and 0 <= h < 1
int heat_exterior_floor(const SimRational *z, const SimRational *h, unsigned int bits,
                        ExponentialIntegralBracket *bracket);

// Pi_ext(X, eta) for X > 0, -1 <= eta <= 1, any c, and 0 <= h < 1
int exterior_pressure_floor(const SimRational *x, const SimRational *eta, const SimRational *c, const SimRational *h,
                            unsigned int bits, ExponentialIntegralBracket *bracket);

// the bits the build's exact width holds
unsigned int exponential_integral_width(void);

#endif
