// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// core_series.cu: the recursion and the residual of the cut series (core_series.h)
#include "core_series.h"

void core_series_recursion(const EtaShape *shape, const EtaFunction *swirl, const EtaFunction *axial,
                           const EtaFunction *pressure, unsigned int cut, CoreSeries *series)
{
    std::vector<EtaFunction> &swirl_slope = series->swirl_slope;
    std::vector<EtaFunction> &axial_slope = series->axial_slope;
    std::vector<EtaFunction> &swirl_z = series->swirl_z;
    std::vector<EtaFunction> &axial_z = series->axial_z;
    series->swirl.push_back(*swirl);
    series->axial.push_back(*axial);
    series->pressure.push_back(*pressure);
    for (unsigned int k = 0u; k <= cut; k += 1u)
    {
        const long long order = (long long)k;
        EtaFunction slope;
        eta_function_derivative(shape, &series->swirl[k], &slope);
        swirl_slope.push_back(slope);
        eta_function_derivative(shape, &series->axial[k], &slope);
        axial_slope.push_back(slope);
        // (Z_{-(A+1/2)} F)_k: 2 b - 2 k = -(2 part + (2 + 2k) whole) / whole
        EtaFunction turned;
        AnchorExactInteger factor = eta_function_mixed(shape, -2ll, -(2ll + 2ll * order));
        eta_function_z(shape, &series->swirl[k], &swirl_slope[k], &factor, &turned);
        swirl_z.push_back(turned);
        // (Z_{-A} U)_k: 2 b - 2 k = -(2 part + (1 + 2k) whole) / whole
        factor = eta_function_mixed(shape, -2ll, -(1ll + 2ll * order));
        eta_function_z(shape, &series->axial[k], &axial_slope[k], &factor, &turned);
        axial_z.push_back(turned);
        // (k+1) v_k = L^-1 (((1 + 2k) whole + 2 part) / whole eta U_k - d U_k')
        EtaFunction inflow;
        eta_function_zero(&inflow);
        EtaFunction tilted = series->axial[k];
        eta_function_eta(&tilted);
        factor = eta_function_mixed(shape, 2ll, 1ll + 2ll * order);
        eta_function_gather(shape, &inflow, &tilted, &factor, 1ll);
        EtaFunction ended = axial_slope[k];
        eta_function_end_factor(&ended);
        eta_function_scale_word(&ended, -1ll, 1ll);
        eta_function_add(shape, &inflow, &ended, &inflow);
        eta_function_over_l(shape, &inflow);
        eta_function_scale_word(&inflow, 1ll, order + 1ll);
        series->inflow.push_back(inflow);
        // k P_k = sum_{i+j=k-1} F_i F_j
        if (k >= 1u)
        {
            EtaFunction pressure;
            eta_function_zero(&pressure);
            for (unsigned int index = 0u; index < k; index += 1u)
            {
                EtaFunction term;
                eta_function_multiply(&series->swirl[index], &series->swirl[k - 1u - index], &term);
                eta_function_add(shape, &pressure, &term, &pressure);
            }
            eta_function_scale_word(&pressure, 1ll, order);
            series->pressure.push_back(pressure);
        }
        if (k == cut)
        {
            break;
        }
        // the theta equation at order k
        EtaFunction next;
        eta_function_zero(&next);
        factor = eta_function_mixed(shape, 1ll, order + 1ll);
        eta_function_gather(shape, &next, &series->swirl[k], &factor, 1ll);
        tilted = swirl_slope[k];
        eta_function_eta(&tilted);
        factor = eta_function_mixed(shape, -2ll, 1ll);
        eta_function_gather(shape, &next, &tilted, &factor, 2ll);
        eta_function_over_l(shape, &next);
        for (unsigned int index = 0u; index <= k; index += 1u)
        {
            EtaFunction term;
            eta_function_multiply(&series->inflow[index], &series->swirl[k - index], &term);
            eta_function_scale_word(&term, order - (long long)index + 1ll, 1ll);
            eta_function_add(shape, &next, &term, &next);
            eta_function_multiply(&series->axial[index], &swirl_z[k - index], &term);
            eta_function_add(shape, &next, &term, &next);
        }
        eta_function_scale_word(&next, 1ll, 2ll * (order + 1ll) * (order + 2ll));
        series->swirl.push_back(next);
        // the z equation at order k
        eta_function_zero(&next);
        factor = eta_function_mixed(shape, 2ll, 1ll + 2ll * order);
        eta_function_gather(shape, &next, &series->axial[k], &factor, 2ll);
        tilted = axial_slope[k];
        eta_function_eta(&tilted);
        factor = eta_function_mixed(shape, -2ll, 1ll);
        eta_function_gather(shape, &next, &tilted, &factor, 2ll);
        eta_function_over_l(shape, &next);
        for (unsigned int index = 0u; index <= k; index += 1u)
        {
            EtaFunction term;
            eta_function_multiply(&series->inflow[index], &series->axial[k - index], &term);
            eta_function_scale_word(&term, order - (long long)index, 1ll);
            eta_function_add(shape, &next, &term, &next);
            eta_function_multiply(&series->axial[index], &axial_z[k - index], &term);
            eta_function_add(shape, &next, &term, &next);
        }
        // (Z_{-2A} Pi)_k: 2 b - 2 k = -(4 part + (2 + 2k) whole) / whole
        EtaFunction pressure_slope;
        eta_function_derivative(shape, &series->pressure[k], &pressure_slope);
        factor = eta_function_mixed(shape, -4ll, -(2ll + 2ll * order));
        eta_function_z(shape, &series->pressure[k], &pressure_slope, &factor, &turned);
        eta_function_add(shape, &next, &turned, &next);
        eta_function_scale_word(&next, 1ll, 2ll * (order + 1ll) * (order + 1ll));
        series->axial.push_back(next);
    }
}

// the coefficients of X^k, k = 0..2K+1, of the theta and z residuals of the series cut after X^K: v_k from the cut U
// stops at K, and Pi = Pi_0 + int F^2 of the cut F runs to 2K+1
void core_series_residual(const EtaShape *shape, unsigned int order, const CoreSeries *series,
                                 std::vector<EtaFunction> *theta, std::vector<EtaFunction> *axial)
{
    const unsigned int last = order;
    const unsigned int most = 2u * last + 1u;
    std::vector<EtaFunction> pressure = series->pressure;
    for (unsigned int k = last + 1u; k <= most; k += 1u)
    {
        EtaFunction sum;
        eta_function_zero(&sum);
        for (unsigned int index = (k - 1u > last) ? k - 1u - last : 0u; (index < k) && (index <= last); index += 1u)
        {
            EtaFunction term;
            eta_function_multiply(&series->swirl[index], &series->swirl[k - 1u - index], &term);
            eta_function_add(shape, &sum, &term, &sum);
        }
        eta_function_scale_word(&sum, 1ll, (long long)k);
        pressure.push_back(sum);
    }
    theta->assign(most + 1u, EtaFunction());
    axial->assign(most + 1u, EtaFunction());
    for (unsigned int k = 0u; k <= most; k += 1u)
    {
        const long long order = (long long)k;
        EtaFunction swirl_sum;
        EtaFunction axial_sum;
        eta_function_zero(&swirl_sum);
        eta_function_zero(&axial_sum);
        if (k <= last)
        {
            AnchorExactInteger factor = eta_function_mixed(shape, 1ll, order + 1ll);
            eta_function_gather(shape, &swirl_sum, &series->swirl[k], &factor, 1ll);
            EtaFunction tilted = series->swirl_slope[k];
            eta_function_eta(&tilted);
            factor = eta_function_mixed(shape, -2ll, 1ll);
            eta_function_gather(shape, &swirl_sum, &tilted, &factor, 2ll);
            eta_function_over_l(shape, &swirl_sum);
            factor = eta_function_mixed(shape, 2ll, 1ll + 2ll * order);
            eta_function_gather(shape, &axial_sum, &series->axial[k], &factor, 2ll);
            tilted = series->axial_slope[k];
            eta_function_eta(&tilted);
            factor = eta_function_mixed(shape, -2ll, 1ll);
            eta_function_gather(shape, &axial_sum, &tilted, &factor, 2ll);
            eta_function_over_l(shape, &axial_sum);
        }
        if (k < last)
        {
            EtaFunction viscous = series->swirl[k + 1u];
            eta_function_scale_word(&viscous, -2ll * (order + 1ll) * (order + 2ll), 1ll);
            eta_function_add(shape, &swirl_sum, &viscous, &swirl_sum);
            viscous = series->axial[k + 1u];
            eta_function_scale_word(&viscous, -2ll * (order + 1ll) * (order + 1ll), 1ll);
            eta_function_add(shape, &axial_sum, &viscous, &axial_sum);
        }
        for (unsigned int index = (k > last) ? k - last : 0u; (index <= k) && (index <= last); index += 1u)
        {
            const unsigned int other = k - index;
            EtaFunction term;
            eta_function_multiply(&series->inflow[index], &series->swirl[other], &term);
            eta_function_scale_word(&term, (long long)other + 1ll, 1ll);
            eta_function_add(shape, &swirl_sum, &term, &swirl_sum);
            eta_function_multiply(&series->axial[index], &series->swirl_z[other], &term);
            eta_function_add(shape, &swirl_sum, &term, &swirl_sum);
            eta_function_multiply(&series->inflow[index], &series->axial[other], &term);
            eta_function_scale_word(&term, (long long)other, 1ll);
            eta_function_add(shape, &axial_sum, &term, &axial_sum);
            eta_function_multiply(&series->axial[index], &series->axial_z[other], &term);
            eta_function_add(shape, &axial_sum, &term, &axial_sum);
        }
        EtaFunction pressure_slope;
        eta_function_derivative(shape, &pressure[k], &pressure_slope);
        const AnchorExactInteger factor = eta_function_mixed(shape, -4ll, -(2ll + 2ll * order));
        EtaFunction turned;
        eta_function_z(shape, &pressure[k], &pressure_slope, &factor, &turned);
        eta_function_add(shape, &axial_sum, &turned, &axial_sum);
        (*theta)[k] = swirl_sum;
        (*axial)[k] = axial_sum;
    }
}


std::vector<SimRational> core_series_at(const EtaShape *shape, const std::vector<EtaFunction> &field, SimRational eta)
{
    std::vector<SimRational> values;
    for (const EtaFunction &function : field)
    {
        values.push_back(eta_function_value_at(shape, &function, eta));
    }
    return values;
}

int core_series_short(void)
{
    return s_sim_rational_wide != 0;
}
