// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// eta_function.h: a function of eta held exactly as a polynomial over a power of M = whole - 2 part eta^2, h = part /
// whole, so that M / whole = L = 1 - 2 h eta^2
#ifndef ETA_FUNCTION_H
#define ETA_FUNCTION_H

#include "sim_rational.h"

#include <vector>

// (sum coefficient[i] eta^i) / (scale M^power)
typedef struct
{
    std::vector<AnchorExactInteger> coefficient;
    AnchorExactInteger scale;
    unsigned int power;
} EtaFunction;

// h = part / whole
typedef struct
{
    AnchorExactInteger part;
    AnchorExactInteger whole;
} EtaShape;

AnchorExactInteger eta_function_whole(long long number);
AnchorExactInteger eta_function_product(const AnchorExactInteger *left, const AnchorExactInteger *right);
AnchorExactInteger eta_function_sum(const AnchorExactInteger *left, const AnchorExactInteger *right);
AnchorExactInteger eta_function_difference(const AnchorExactInteger *left, const AnchorExactInteger *right);
AnchorExactInteger eta_function_divided(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor);
AnchorExactInteger eta_function_common(const AnchorExactInteger *left, const AnchorExactInteger *right);

// the function 0
void eta_function_zero(EtaFunction *function);

// the coefficients and the scale divided by their common factor, the trailing zeros dropped
void eta_function_settle(EtaFunction *function);

// the numerator times M, the power one higher: the same function
void eta_function_raise(const EtaShape *shape, EtaFunction *function);

void eta_function_add(const EtaShape *shape, const EtaFunction *left, const EtaFunction *right, EtaFunction *result);
void eta_function_multiply(const EtaFunction *left, const EtaFunction *right, EtaFunction *result);

// the function times numerator / denominator, the denominator positive
void eta_function_scale(EtaFunction *function, const AnchorExactInteger *numerator,
                        const AnchorExactInteger *denominator);
void eta_function_scale_word(EtaFunction *function, long long numerator, long long denominator);

// the function times eta, times d = 1 - eta^2, and times L^-1
void eta_function_eta(EtaFunction *function);
void eta_function_end_factor(EtaFunction *function);
void eta_function_over_l(const EtaShape *shape, EtaFunction *function);

// the derivative in eta
void eta_function_derivative(const EtaShape *shape, const EtaFunction *function, EtaFunction *result);

// result = result + function * numerator / (denominator whole)
void eta_function_gather(const EtaShape *shape, EtaFunction *result, const EtaFunction *function,
                         const AnchorExactInteger *numerator, long long denominator);

// part_count part + whole_count whole
AnchorExactInteger eta_function_mixed(const EtaShape *shape, long long part_count, long long whole_count);

// L^-1 ((2 b - 2 j) eta f + d f'), 2 b - 2 j = numerator / whole, f' the derivative given as `slope`
void eta_function_z(const EtaShape *shape, const EtaFunction *function, const EtaFunction *slope,
                    const AnchorExactInteger *numerator, EtaFunction *result);

// the value at eta = top / bottom, bottom > 0
SimRational eta_function_value(const EtaShape *shape, const EtaFunction *function, long long top, long long bottom);

// the value at a rational eta
SimRational eta_function_value_at(const EtaShape *shape, const EtaFunction *function, SimRational eta);

// the polynomial sum weights[m] T_m(eta), T_m Chebyshev's
void eta_function_chebyshev(const std::vector<SimRational> &weights, EtaFunction *function);

// 1 where an operation since the module's start outgrew the build's exact width
int eta_function_short(void);

#endif
