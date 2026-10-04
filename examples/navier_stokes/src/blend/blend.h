// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// blend.h: integrals over 0 <= s <= 1 of psi(s)^j G(s), j = 0, 1, 2, psi = e^(-1/s) / (e^(-1/s) + e^(-1/(1-s))) the
// weight Duraiswami blends with, every value a form in atoms
#ifndef BLEND_H
#define BLEND_H

// psi is flat at both ends, where no Taylor series reaches it, and the interval is cut at the cfg's points into an end
// piece at each end and middle pieces between.
// - End at s = 0: psi = u / (1 + u), u = e^(-1/s) e^(1/(1-s)); psi = sum over N >= 1 of (-1)^(N+1) u^N and
//   psi^2 = sum over N >= 2 of (-1)^N (N - 1) u^N. u^N = e^N e^(-N/s) g_N(s), g_N = e^(N s / (1-s)) from
//   (1 - s)^2 g' = N g, and int_0^b s^k e^(-N/s) ds is the two-term decay integral: e^(N - N/b) and the atom E1(N/b).
// - End at s = 1: with t = 1 - s, psi(s) = 1 - psi(t), and the end at 0 is taken in t with G moved to s = 1.
// - Middle piece about c: psi = rho alpha / (1 + rho (alpha - 1 + r (beta - 1))), alpha and beta the unit series of
//   e^(-1/s) and e^(-1/(1-s)) about c, r = e^(-1/(1-c)) / e^(-1/c) = e^(1/c - 1/(1-c)) a power of e, rho = 1 / (1 + r)
//   its atom, every form reduced by rho (1 + r) = 1.
// G is given about any center the pieces ask for, by the caller, in s.

#include "taylor.h"

// G about `center` in s with `terms` terms, its atoms named in `book`
typedef TaylorSeries (*BlendIntegrand)(const void *context, SimRational center, unsigned int terms, AtomBook *book);

typedef struct
{
    std::vector<SimRational> cuts;
    unsigned int terms;
    unsigned int orders;
} BlendPieces;

// int_0^1 psi^j G ds, j = 0, 1 or 2, over the pieces
AtomForm blend_integral(const BlendPieces *pieces, unsigned int power, BlendIntegrand integrand, const void *context,
                        AtomBook *book);

// psi about a middle center, r = e^ratio with ratio = 1/c - 1/(1-c), and rho the atom named in `book`; `ratio` takes
// the power and `share` rho's number. At c = 1/2 the power is 0, rho is the rational 1/2, and no atom is named.
TaylorSeries blend_weight(SimRational center, unsigned int terms, AtomBook *book, SimRational *ratio,
                          unsigned int *share);

// 1 where a value in this module outgrew the build's width
int blend_short(void);

#endif
