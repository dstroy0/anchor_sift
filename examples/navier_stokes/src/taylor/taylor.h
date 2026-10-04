// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// taylor.h: a Taylor series about a rational center, its coefficients forms in atoms, and its integral term by term
#ifndef TAYLOR_H
#define TAYLOR_H

// sum over k of coefficient[k] (x - center)^k, as many terms as the request holds. The integral over [low, high] is
// sum over k of coefficient[k] ((high - center)^(k+1) - (low - center)^(k+1)) / (k + 1), every term exact.

#include "atom_form.h"

typedef struct
{
    SimRational center;
    std::vector<AtomForm> coefficient;
} TaylorSeries;

// the series of rational coefficients `values` about `center`, each a form with no atom
TaylorSeries taylor_rational(SimRational center, const std::vector<SimRational> &values);

// the series times a form
TaylorSeries taylor_form_scaled(const TaylorSeries &series, const AtomForm &form);

TaylorSeries taylor_scaled(const TaylorSeries &series, SimRational factor);

// two series about one center; the result holds the fewer terms of the two
TaylorSeries taylor_sum(const TaylorSeries &left, const TaylorSeries &right);
TaylorSeries taylor_difference(const TaylorSeries &left, const TaylorSeries &right);
TaylorSeries taylor_product(const TaylorSeries &left, const TaylorSeries &right);

// d/dx, one term fewer
TaylorSeries taylor_derivative(const TaylorSeries &series);

// 1 / series for a series whose first coefficient is the rational 1
TaylorSeries taylor_unit_inverse(const TaylorSeries &series);

// the series in y = (x - center) / stretch: coefficient k times stretch^k, the center unchanged
TaylorSeries taylor_stretched(const TaylorSeries &series, SimRational stretch);

// a polynomial sum values[k] x^k moved to the center, `terms` terms held
TaylorSeries taylor_polynomial(const std::vector<SimRational> &values, SimRational center, unsigned int terms);

AtomForm taylor_value(const TaylorSeries &series, SimRational x);

AtomForm taylor_integral(const TaylorSeries &series, SimRational low, SimRational high);

// the series of start + int_center^x series, one term more
TaylorSeries taylor_integral_from_center(const TaylorSeries &series, const AtomForm &start);

// 1 where a value in this module outgrew the build's width
int taylor_short(void);

#endif
