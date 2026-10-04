// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ode_series.h: the Taylor coefficients of solutions of linear equations with polynomial coefficients, about a
// rational center, every coefficient rational; the solution's value at the center is the atom held beside them
#ifndef ODE_SERIES_H
#define ODE_SERIES_H

// First order, P(x) f' = Q(x) f, f(c) = 1: with P(c + t) = sum p_j t^j and Q(c + t) = sum q_j t^j,
//     p_0 (n + 1) a_(n+1) = sum_j q_j a_(n-j) - sum_(j >= 1) p_j (n - j + 1) a_(n-j+1).
// Each function below is such a solution times its value at c, a power of e or an atom:
//     e^(-1/x):          x^2 f' = f,                       e^(-1/c)
//     e^(-1/(1-x)):      (1 - x)^2 f' = -f,                e^(-1/(1-c))
//     e^(4 - 1/(x(1-x))): x^2 (1 - x)^2 f' = (1 - 2x) f,    e^(4 - 1/(c(1-c)))
//     x^h:               x f' = h f,                       atom c^h
// Kummer's equation for w = U(1 + h, 2, z), z w'' + (2 - z) w' - (1 + h) w = 0, about z_c:
//     a_(k+2) = ((k + 1 + h) a_k - (k + 1) (k + 2 - z_c) a_(k+1)) / (z_c (k + 1) (k + 2)),
// from the starts (1, 0) and (0, 1); w = w(z_c) first + w'(z_c) second, the two values its atoms.

#include "taylor.h"

// the first-order solution with f(center) = 1, `terms` coefficients, P and Q as coefficients in x
std::vector<SimRational> ode_series_first(const std::vector<SimRational> &p, const std::vector<SimRational> &q,
                                          SimRational center, unsigned int terms);

// e^(-1/x) about `center`
TaylorSeries ode_series_decay(SimRational center, unsigned int terms);

// e^(-1/(1-x)) about `center`
TaylorSeries ode_series_decay_reflected(SimRational center, unsigned int terms);

// e^(4 - 1/(x(1-x))) about `center`
TaylorSeries ode_series_bump(SimRational center, unsigned int terms);

// x^h about `center`, times the atom
TaylorSeries ode_series_power(SimRational center, SimRational h, unsigned int terms, unsigned int atom);

// w = U(1 + h, 2, z) about `center`, w(center) the atom `value` and w'(center) the atom `slope`
TaylorSeries ode_series_kummer(SimRational center, SimRational h, unsigned int terms, unsigned int value,
                               unsigned int slope);

// the residual series P f' - Q f of a series, for the checks: every coefficient held is 0 for a solution
TaylorSeries ode_series_first_residual(const TaylorSeries &series, const std::vector<SimRational> &p,
                                       const std::vector<SimRational> &q);

// the residual series z w'' + (2 - z) w' - (1 + h) w
TaylorSeries ode_series_kummer_residual(const TaylorSeries &series, SimRational h);

// 1 where a value in this module outgrew the build's width
int ode_series_short(void);

#endif
