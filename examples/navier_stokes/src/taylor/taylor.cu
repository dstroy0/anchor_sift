// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// taylor.cu: Taylor series (taylor.h)
#include "taylor.h"

TaylorSeries taylor_rational(SimRational center, const std::vector<SimRational> &values)
{
    TaylorSeries series;
    series.center = center;
    for (const SimRational &value : values)
    {
        series.coefficient.push_back(atom_form_rational(value));
    }
    return series;
}

TaylorSeries taylor_form_scaled(const TaylorSeries &series, const AtomForm &form)
{
    TaylorSeries scaled;
    scaled.center = series.center;
    for (const AtomForm &coefficient : series.coefficient)
    {
        scaled.coefficient.push_back(atom_form_product(coefficient, form));
    }
    return scaled;
}

TaylorSeries taylor_scaled(const TaylorSeries &series, SimRational factor)
{
    TaylorSeries scaled;
    scaled.center = series.center;
    for (const AtomForm &coefficient : series.coefficient)
    {
        scaled.coefficient.push_back(atom_form_scaled(coefficient, factor));
    }
    return scaled;
}

static size_t taylor_fewer(const TaylorSeries &left, const TaylorSeries &right)
{
    return (left.coefficient.size() < right.coefficient.size()) ? left.coefficient.size() : right.coefficient.size();
}

TaylorSeries taylor_sum(const TaylorSeries &left, const TaylorSeries &right)
{
    TaylorSeries sum;
    sum.center = left.center;
    for (size_t index = 0u; index < taylor_fewer(left, right); index += 1u)
    {
        sum.coefficient.push_back(atom_form_sum(left.coefficient[index], right.coefficient[index]));
    }
    return sum;
}

TaylorSeries taylor_difference(const TaylorSeries &left, const TaylorSeries &right)
{
    TaylorSeries difference;
    difference.center = left.center;
    for (size_t index = 0u; index < taylor_fewer(left, right); index += 1u)
    {
        difference.coefficient.push_back(atom_form_difference(left.coefficient[index], right.coefficient[index]));
    }
    return difference;
}

TaylorSeries taylor_product(const TaylorSeries &left, const TaylorSeries &right)
{
    TaylorSeries product;
    product.center = left.center;
    const size_t terms = taylor_fewer(left, right);
    for (size_t index = 0u; index < terms; index += 1u)
    {
        AtomForm sum;
        for (size_t first = 0u; first <= index; first += 1u)
        {
            sum = atom_form_sum(sum, atom_form_product(left.coefficient[first], right.coefficient[index - first]));
        }
        product.coefficient.push_back(sum);
    }
    return product;
}

TaylorSeries taylor_derivative(const TaylorSeries &series)
{
    TaylorSeries slope;
    slope.center = series.center;
    for (size_t index = 1u; index < series.coefficient.size(); index += 1u)
    {
        slope.coefficient.push_back(atom_form_scaled(series.coefficient[index], sim_rational((long long)index, 1ll)));
    }
    return slope;
}

// b_0 = 1, b_n = -sum over k = 1 .. n of a_k b_(n - k)
TaylorSeries taylor_unit_inverse(const TaylorSeries &series)
{
    TaylorSeries inverse;
    inverse.center = series.center;
    if (series.coefficient.empty())
    {
        return inverse;
    }
    inverse.coefficient.push_back(atom_form_rational(sim_rational(1ll, 1ll)));
    for (size_t index = 1u; index < series.coefficient.size(); index += 1u)
    {
        AtomForm sum;
        for (size_t first = 1u; first <= index; first += 1u)
        {
            sum = atom_form_sum(sum, atom_form_product(series.coefficient[first], inverse.coefficient[index - first]));
        }
        inverse.coefficient.push_back(atom_form_scaled(sum, sim_rational(-1ll, 1ll)));
    }
    return inverse;
}

TaylorSeries taylor_stretched(const TaylorSeries &series, SimRational stretch)
{
    TaylorSeries stretched;
    stretched.center = series.center;
    SimRational power = sim_rational(1ll, 1ll);
    for (const AtomForm &coefficient : series.coefficient)
    {
        stretched.coefficient.push_back(atom_form_scaled(coefficient, power));
        power = sim_rational_product(power, stretch);
    }
    return stretched;
}

// the coefficient of (x - c)^j in x^k is binom(k, j) c^(k - j)
TaylorSeries taylor_polynomial(const std::vector<SimRational> &values, SimRational center, unsigned int terms)
{
    std::vector<SimRational> moved(terms, sim_rational(0ll, 1ll));
    std::vector<SimRational> row(1u, sim_rational(1ll, 1ll));
    for (size_t degree = 0u; degree < values.size(); degree += 1u)
    {
        // row[j] is the coefficient of (x - c)^j in x^degree
        for (size_t index = 0u; (index < row.size()) && (index < terms); index += 1u)
        {
            moved[index] = sim_rational_sum(moved[index], sim_rational_product(values[degree], row[index]));
        }
        // x^(degree + 1) = (x - c) x^degree + c x^degree
        std::vector<SimRational> next(row.size() + 1u, sim_rational(0ll, 1ll));
        for (size_t index = 0u; index < row.size(); index += 1u)
        {
            next[index + 1u] = sim_rational_sum(next[index + 1u], row[index]);
            next[index] = sim_rational_sum(next[index], sim_rational_product(center, row[index]));
        }
        row.swap(next);
    }
    return taylor_rational(center, moved);
}

AtomForm taylor_value(const TaylorSeries &series, SimRational x)
{
    const SimRational offset = sim_rational_difference(x, series.center);
    AtomForm sum;
    for (size_t index = series.coefficient.size(); index > 0u; index -= 1u)
    {
        sum = atom_form_sum(atom_form_scaled(sum, offset), series.coefficient[index - 1u]);
    }
    return sum;
}

AtomForm taylor_integral(const TaylorSeries &series, SimRational low, SimRational high)
{
    const SimRational upper = sim_rational_difference(high, series.center);
    const SimRational lower = sim_rational_difference(low, series.center);
    SimRational upper_power = upper;
    SimRational lower_power = lower;
    AtomForm sum;
    for (size_t index = 0u; index < series.coefficient.size(); index += 1u)
    {
        const SimRational weight = sim_rational_product(sim_rational_difference(upper_power, lower_power),
                                                        sim_rational(1ll, (long long)index + 1ll));
        sum = atom_form_sum(sum, atom_form_scaled(series.coefficient[index], weight));
        upper_power = sim_rational_product(upper_power, upper);
        lower_power = sim_rational_product(lower_power, lower);
    }
    return sum;
}

TaylorSeries taylor_integral_from_center(const TaylorSeries &series, const AtomForm &start)
{
    TaylorSeries integral;
    integral.center = series.center;
    integral.coefficient.push_back(start);
    for (size_t index = 0u; index < series.coefficient.size(); index += 1u)
    {
        integral.coefficient.push_back(
            atom_form_scaled(series.coefficient[index], sim_rational(1ll, (long long)index + 1ll)));
    }
    return integral;
}

int taylor_short(void)
{
    return s_sim_rational_wide != 0;
}
