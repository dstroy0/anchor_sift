// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// core_series.h: the axis core of Duraiswami's swirl collapse (arXiv 2609.17642, Section 7) as its Taylor series in X,
// every coefficient an exact function of eta
#ifndef CORE_SERIES_H
#define CORE_SERIES_H

// The leading-order system of OpenAI 2026, eq. (4.13), in Duraiswami's profile variables (his eq. 4, nu = 1), with
// A = 1/2 + h, D = 1/2 - h, d = 1 - eta^2 and L = 1 - 2 h eta^2:
//     T_{-(A+1/2)} F + v0 (X F_X + F) + U Z_{-(A+1/2)} F - 2 (X F)_XX = 0,
//     T_{-A} U + X v0 U_X + U Z_{-A} U + Z_{-2A} Pi - 2 (X U_X)_X = 0,
//     (X v0)_X = L^-1 (2 A eta U - d U_eta + 2 eta X U_X),   Pi_X = F^2,
//     T_b f = L^-1 (-b f + D eta f_eta + X f_X),   Z_b f = L^-1 (2 b eta f + d f_eta - 2 eta X f_X).
// With F = sum F_k X^k and the same for U, v0 and Pi, the viscous terms alone raise the power of X, and order k gives
//     2 (k+1)(k+2) F_{k+1} = L^-1 ((k + 1 + h) F_k + D eta F_k') + sum v_i (k-i+1) F_{k-i} + sum U_i (Z_{-(A+1/2)} F)_{k-i},
//     2 (k+1)^2 U_{k+1} = L^-1 ((k + A) U_k + D eta U_k') + sum v_i (k-i) U_{k-i} + sum U_i (Z_{-A} U)_{k-i}
//                         + (Z_{-2A} Pi)_k,
//     (k+1) v_k = L^-1 (2 A eta U_k - d U_k' + 2 k eta U_k),   k P_k = sum_{i+j=k-1} F_i F_j,
// with (Z_b f)_j = L^-1 (2 b eta f_j + d f_j' - 2 j eta f_j). The free data are F_0, U_0 and P_0 = Pi_0 as functions of
// eta, each coefficient an EtaFunction: no grid in eta, no filter.

#include "eta_function.h"

// the coefficients F, U, v, P to the order asked, v and P one order past the last F and U they need, with the eta
// derivatives of F and U and the Z terms of each order kept
typedef struct
{
    std::vector<EtaFunction> swirl;
    std::vector<EtaFunction> axial;
    std::vector<EtaFunction> inflow;
    std::vector<EtaFunction> pressure;
    std::vector<EtaFunction> swirl_slope;
    std::vector<EtaFunction> axial_slope;
    std::vector<EtaFunction> swirl_z;
    std::vector<EtaFunction> axial_z;
} CoreSeries;

void core_series_recursion(const EtaShape *shape, const EtaFunction *swirl, const EtaFunction *axial,
                           const EtaFunction *pressure, unsigned int order, CoreSeries *series);

// the coefficients of X^k, k = 0..2K+1, of the theta and z residuals of the series cut after X^K: v_k from the cut U
// stops at K, and Pi = Pi_0 + int F^2 of the cut F runs to 2K+1
void core_series_residual(const EtaShape *shape, unsigned int order, const CoreSeries *series,
                          std::vector<EtaFunction> *theta, std::vector<EtaFunction> *axial);

// the coefficients of one field at a rational eta, a polynomial in X
std::vector<SimRational> core_series_at(const EtaShape *shape, const std::vector<EtaFunction> &field, SimRational eta);

// 1 where a value in this module outgrew the build's width
int core_series_short(void);

#endif
