// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ode_series.cu: series of solutions of linear equations (ode_series.h)
#include "ode_series.h"

// the polynomial sum values[k] x^k moved to `center`, all its coefficients
static std::vector<SimRational> ode_series_moved(const std::vector<SimRational> &values, SimRational center)
{
    const TaylorSeries moved = taylor_polynomial(values, center, (unsigned int)values.size());
    std::vector<SimRational> coefficients;
    for (const AtomForm &form : moved.coefficient)
    {
        coefficients.push_back(atom_form_constant(form));
    }
    return coefficients;
}

std::vector<SimRational> ode_series_first(const std::vector<SimRational> &p, const std::vector<SimRational> &q,
                                          SimRational center, unsigned int terms)
{
    const std::vector<SimRational> p_moved = ode_series_moved(p, center);
    const std::vector<SimRational> q_moved = ode_series_moved(q, center);
    std::vector<SimRational> a(1u, sim_rational(1ll, 1ll));
    for (unsigned int n = 0u; n + 1u < terms; n += 1u)
    {
        SimRational sum = sim_rational(0ll, 1ll);
        for (size_t j = 0u; (j < q_moved.size()) && (j <= n); j += 1u)
        {
            sum = sim_rational_sum(sum, sim_rational_product(q_moved[j], a[n - j]));
        }
        for (size_t j = 1u; (j < p_moved.size()) && (j <= n); j += 1u)
        {
            const SimRational weight = sim_rational((long long)(n - j + 1u), 1ll);
            sum = sim_rational_difference(sum, sim_rational_product(sim_rational_product(p_moved[j], weight),
                                                                    a[n - j + 1u]));
        }
        a.push_back(sim_rational_product(sum, sim_rational_reciprocal(sim_rational_product(
                                                  p_moved[0], sim_rational((long long)n + 1ll, 1ll)))));
    }
    return a;
}

static TaylorSeries ode_series_atom(SimRational center, const std::vector<SimRational> &values, unsigned int atom)
{
    return taylor_form_scaled(taylor_rational(center, values), atom_form_atom(atom));
}

static std::vector<SimRational> ode_series_words(std::initializer_list<long long> words)
{
    std::vector<SimRational> values;
    for (long long word : words)
    {
        values.push_back(sim_rational(word, 1ll));
    }
    return values;
}

static TaylorSeries ode_series_e(SimRational center, const std::vector<SimRational> &values, SimRational power)
{
    return taylor_form_scaled(taylor_rational(center, values), atom_form_e(power));
}

TaylorSeries ode_series_decay(SimRational center, unsigned int terms)
{
    const std::vector<SimRational> p = ode_series_words({0ll, 0ll, 1ll});
    const std::vector<SimRational> q = ode_series_words({1ll});
    return ode_series_e(center, ode_series_first(p, q, center, terms),
                        sim_rational_negative(sim_rational_reciprocal(center)));
}

TaylorSeries ode_series_decay_reflected(SimRational center, unsigned int terms)
{
    const std::vector<SimRational> p = ode_series_words({1ll, -2ll, 1ll});
    const std::vector<SimRational> q = ode_series_words({-1ll});
    const SimRational rest = sim_rational_difference(sim_rational(1ll, 1ll), center);
    return ode_series_e(center, ode_series_first(p, q, center, terms),
                        sim_rational_negative(sim_rational_reciprocal(rest)));
}

TaylorSeries ode_series_bump(SimRational center, unsigned int terms)
{
    // x^2 (1 - x)^2 = x^2 - 2 x^3 + x^4
    const std::vector<SimRational> p = ode_series_words({0ll, 0ll, 1ll, -2ll, 1ll});
    const std::vector<SimRational> q = ode_series_words({1ll, -2ll});
    const SimRational rest = sim_rational_difference(sim_rational(1ll, 1ll), center);
    const SimRational power = sim_rational_difference(
        sim_rational(4ll, 1ll), sim_rational_reciprocal(sim_rational_product(center, rest)));
    return ode_series_e(center, ode_series_first(p, q, center, terms), power);
}

TaylorSeries ode_series_power(SimRational center, SimRational h, unsigned int terms, unsigned int atom)
{
    const std::vector<SimRational> p = ode_series_words({0ll, 1ll});
    const std::vector<SimRational> q(1u, h);
    return ode_series_atom(center, ode_series_first(p, q, center, terms), atom);
}

TaylorSeries ode_series_kummer(SimRational center, SimRational h, unsigned int terms, unsigned int value,
                               unsigned int slope)
{
    std::vector<SimRational> first(terms, sim_rational(0ll, 1ll));
    std::vector<SimRational> second(terms, sim_rational(0ll, 1ll));
    if (terms > 0u)
    {
        first[0] = sim_rational(1ll, 1ll);
    }
    if (terms > 1u)
    {
        second[1] = sim_rational(1ll, 1ll);
    }
    for (unsigned int k = 0u; k + 2u < terms; k += 1u)
    {
        const SimRational rise = sim_rational_sum(h, sim_rational((long long)k + 1ll, 1ll));
        const SimRational fall = sim_rational_product(
            sim_rational((long long)k + 1ll, 1ll),
            sim_rational_difference(sim_rational((long long)k + 2ll, 1ll), center));
        const SimRational below = sim_rational_reciprocal(sim_rational_product(
            center, sim_rational(((long long)k + 1ll) * ((long long)k + 2ll), 1ll)));
        first[k + 2u] = sim_rational_product(
            sim_rational_difference(sim_rational_product(rise, first[k]), sim_rational_product(fall, first[k + 1u])),
            below);
        second[k + 2u] = sim_rational_product(
            sim_rational_difference(sim_rational_product(rise, second[k]), sim_rational_product(fall, second[k + 1u])),
            below);
    }
    return taylor_sum(ode_series_atom(center, first, value), ode_series_atom(center, second, slope));
}

TaylorSeries ode_series_first_residual(const TaylorSeries &series, const std::vector<SimRational> &p,
                                       const std::vector<SimRational> &q)
{
    const unsigned int terms = (unsigned int)series.coefficient.size();
    const TaylorSeries p_series = taylor_polynomial(p, series.center, terms);
    const TaylorSeries q_series = taylor_polynomial(q, series.center, terms);
    return taylor_difference(taylor_product(p_series, taylor_derivative(series)), taylor_product(q_series, series));
}

TaylorSeries ode_series_kummer_residual(const TaylorSeries &series, SimRational h)
{
    const unsigned int terms = (unsigned int)series.coefficient.size();
    std::vector<SimRational> z(2u, sim_rational(0ll, 1ll));
    z[1] = sim_rational(1ll, 1ll);
    std::vector<SimRational> two_less(2u, sim_rational(2ll, 1ll));
    two_less[1] = sim_rational(-1ll, 1ll);
    const TaylorSeries slope = taylor_derivative(series);
    const TaylorSeries bend = taylor_derivative(slope);
    const TaylorSeries first = taylor_product(taylor_polynomial(z, series.center, terms), bend);
    const TaylorSeries second = taylor_product(taylor_polynomial(two_less, series.center, terms), slope);
    const TaylorSeries third = taylor_scaled(series, sim_rational_sum(h, sim_rational(1ll, 1ll)));
    return taylor_difference(taylor_sum(first, second), third);
}

int ode_series_short(void)
{
    return s_sim_rational_wide != 0;
}
