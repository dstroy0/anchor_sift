// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// decay_integral.h: int_0^b s^k e^(-n/s) ds as two terms, e^(-n/b) and E1(n/b), each times an exact rational
#ifndef DECAY_INTEGRAL_H
#define DECAY_INTEGRAL_H

// With y = n / s, int_0^b s^k e^(-n/s) ds = b^(k+1) E_(k+2)(x), x = n / b, and the generalized exponential integrals
// reduce to two terms, E_m(x) = A_m(x) e^(-x) + B_m(x) E1(x), by m E_(m+1) = e^(-x) - x E_m:
//     A_1 = 0, B_1 = 1,   A_(m+1) = (1 - x A_m) / m,   B_(m+1) = -x B_m / m,
// A and B polynomials in x with rational coefficients. With I(b) = b^(k+1) (A e^(-x) + B E1(x)) and m = k + 2,
// dI/db = b^k e^(-n/b) holds exactly where (k + 1) B - x B' = 0 and (k + 1) A - x A' + x A + B = 1, the check.

#include "atom_form.h"

// A_m and B_m as coefficients in x
void decay_integral_reduction(unsigned int m, std::vector<SimRational> *a, std::vector<SimRational> *b);

// the two polynomials the check asks to be 0, for m = k + 2
void decay_integral_residual(unsigned int k, std::vector<SimRational> *first, std::vector<SimRational> *second);

// int_0^b s^k e^(-n/s) ds, n > 0 and b > 0, a form in e^(-n/b) and the book's atom E1(n/b)
AtomForm decay_integral_from_zero(unsigned int k, SimRational n, SimRational b, AtomBook *book);

// 1 where a value in this module outgrew the build's width
int decay_integral_short(void);

#endif
