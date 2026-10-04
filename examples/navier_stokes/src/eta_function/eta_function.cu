// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// eta_function.cu: functions of eta held exactly (eta_function.h)
#include "eta_function.h"

AnchorExactInteger eta_function_whole(long long number)
{
    AnchorExactInteger value;
    sim_exact_signed(&value, number);
    return value;
}

AnchorExactInteger eta_function_product(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    AnchorExactInteger value;
    sim_rational_status_check(sim_exact_product(left, right, &value));
    return value;
}

AnchorExactInteger eta_function_sum(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    AnchorExactInteger value;
    sim_rational_status_check(sim_exact_sum(left, right, &value));
    return value;
}

AnchorExactInteger eta_function_difference(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    AnchorExactInteger value;
    sim_rational_status_check(sim_exact_less(left, right, &value));
    return value;
}

AnchorExactInteger eta_function_divided(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor)
{
    AnchorExactInteger value;
    sim_rational_status_check(anchor_exact_divide_exact(numerator, divisor, &value) == ANCHOR_EXACT_OK);
    return value;
}

AnchorExactInteger eta_function_common(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    AnchorExactInteger value;
    sim_rational_status_check(anchor_exact_gcd(left, right, &value) == ANCHOR_EXACT_OK);
    value.sign = (value.sign != 0) ? 1 : 0;
    return value;
}

// the function 0
void eta_function_zero(EtaFunction *function)
{
    function->coefficient.clear();
    sim_exact_unsigned(&function->scale, 1ull);
    function->power = 0u;
}

// the coefficients and the scale divided by their common factor, the trailing zeros dropped
void eta_function_settle(EtaFunction *function)
{
    while (!function->coefficient.empty() && (function->coefficient.back().sign == 0))
    {
        function->coefficient.pop_back();
    }
    if (function->coefficient.empty())
    {
        eta_function_zero(function);
        return;
    }
    AnchorExactInteger common = function->scale;
    const AnchorExactInteger one = eta_function_whole(1ll);
    for (const AnchorExactInteger &value : function->coefficient)
    {
        if ((value.sign != 0) && (anchor_exact_compare(&common, &one) > 0))
        {
            common = eta_function_common(&common, &value);
        }
    }
    if (anchor_exact_compare(&common, &one) > 0)
    {
        for (AnchorExactInteger &value : function->coefficient)
        {
            if (value.sign != 0)
            {
                value = eta_function_divided(&value, &common);
            }
        }
        function->scale = eta_function_divided(&function->scale, &common);
    }
}

// the numerator times M, the power one higher: the same function
void eta_function_raise(const EtaShape *shape, EtaFunction *function)
{
    const size_t size = function->coefficient.size();
    std::vector<AnchorExactInteger> raised(size + 2u);
    const AnchorExactInteger twice = eta_function_sum(&shape->part, &shape->part);
    for (size_t index = 0u; index < size + 2u; index += 1u)
    {
        anchor_exact_zero(&raised[index]);
        if (index < size)
        {
            raised[index] = eta_function_product(&shape->whole, &function->coefficient[index]);
        }
        if (index >= 2u)
        {
            const AnchorExactInteger lowered = eta_function_product(&twice, &function->coefficient[index - 2u]);
            raised[index] = eta_function_difference(&raised[index], &lowered);
        }
    }
    function->coefficient.swap(raised);
    function->power += 1u;
}

// left + right into `result`
void eta_function_add(const EtaShape *shape, const EtaFunction *left,
                            const EtaFunction *right, EtaFunction *result)
{
    if (left->coefficient.empty())
    {
        *result = *right;
        return;
    }
    if (right->coefficient.empty())
    {
        *result = *left;
        return;
    }
    EtaFunction first = *left;
    EtaFunction second = *right;
    while (first.power < second.power)
    {
        eta_function_raise(shape, &first);
    }
    while (second.power < first.power)
    {
        eta_function_raise(shape, &second);
    }
    const AnchorExactInteger common = eta_function_common(&first.scale, &second.scale);
    const AnchorExactInteger first_factor = eta_function_divided(&second.scale, &common);
    const AnchorExactInteger second_factor = eta_function_divided(&first.scale, &common);
    const size_t size = (first.coefficient.size() > second.coefficient.size()) ? first.coefficient.size()
                                                                                : second.coefficient.size();
    EtaFunction sum;
    sum.coefficient.resize(size);
    for (size_t index = 0u; index < size; index += 1u)
    {
        anchor_exact_zero(&sum.coefficient[index]);
        if (index < first.coefficient.size())
        {
            sum.coefficient[index] = eta_function_product(&first.coefficient[index], &first_factor);
        }
        if (index < second.coefficient.size())
        {
            const AnchorExactInteger other = eta_function_product(&second.coefficient[index], &second_factor);
            sum.coefficient[index] = eta_function_sum(&sum.coefficient[index], &other);
        }
    }
    sum.scale = eta_function_product(&first.scale, &first_factor);
    sum.power = first.power;
    eta_function_settle(&sum);
    *result = sum;
}

// left times right into `result`
void eta_function_multiply(const EtaFunction *left, const EtaFunction *right,
                                 EtaFunction *result)
{
    EtaFunction product;
    if (left->coefficient.empty() || right->coefficient.empty())
    {
        eta_function_zero(&product);
        *result = product;
        return;
    }
    product.coefficient.resize(left->coefficient.size() + right->coefficient.size() - 1u);
    for (AnchorExactInteger &value : product.coefficient)
    {
        anchor_exact_zero(&value);
    }
    for (size_t first = 0u; first < left->coefficient.size(); first += 1u)
    {
        if (left->coefficient[first].sign == 0)
        {
            continue;
        }
        for (size_t second = 0u; second < right->coefficient.size(); second += 1u)
        {
            if (right->coefficient[second].sign == 0)
            {
                continue;
            }
            const AnchorExactInteger term = eta_function_product(&left->coefficient[first], &right->coefficient[second]);
            product.coefficient[first + second] = eta_function_sum(&product.coefficient[first + second], &term);
        }
    }
    product.scale = eta_function_product(&left->scale, &right->scale);
    product.power = left->power + right->power;
    eta_function_settle(&product);
    *result = product;
}

// the function times numerator / denominator, the denominator positive
void eta_function_scale(EtaFunction *function, const AnchorExactInteger *numerator,
                              const AnchorExactInteger *denominator)
{
    for (AnchorExactInteger &value : function->coefficient)
    {
        value = eta_function_product(&value, numerator);
    }
    function->scale = eta_function_product(&function->scale, denominator);
    eta_function_settle(function);
}

void eta_function_scale_word(EtaFunction *function, long long numerator, long long denominator)
{
    const AnchorExactInteger top = eta_function_whole(numerator);
    const AnchorExactInteger bottom = eta_function_whole(denominator);
    eta_function_scale(function, &top, &bottom);
}

// the function times eta
void eta_function_eta(EtaFunction *function)
{
    if (!function->coefficient.empty())
    {
        function->coefficient.insert(function->coefficient.begin(), eta_function_whole(0ll));
    }
}

// the function times d = 1 - eta^2
void eta_function_end_factor(EtaFunction *function)
{
    const size_t size = function->coefficient.size();
    if (size == 0u)
    {
        return;
    }
    std::vector<AnchorExactInteger> product(size + 2u);
    for (size_t index = 0u; index < size + 2u; index += 1u)
    {
        anchor_exact_zero(&product[index]);
        if (index < size)
        {
            product[index] = function->coefficient[index];
        }
        if (index >= 2u)
        {
            product[index] = eta_function_difference(&product[index], &function->coefficient[index - 2u]);
        }
    }
    function->coefficient.swap(product);
    eta_function_settle(function);
}

// the function times L^-1 = whole / M
void eta_function_over_l(const EtaShape *shape, EtaFunction *function)
{
    for (AnchorExactInteger &value : function->coefficient)
    {
        value = eta_function_product(&value, &shape->whole);
    }
    function->power += 1u;
    eta_function_settle(function);
}

// the derivative in eta: (p' M + 4 n part eta p) / (scale M^(n+1)) for p / (scale M^n)
void eta_function_derivative(const EtaShape *shape, const EtaFunction *function,
                                   EtaFunction *result)
{
    EtaFunction slope;
    slope.scale = function->scale;
    slope.power = function->power;
    const size_t size = function->coefficient.size();
    for (size_t index = 1u; index < size; index += 1u)
    {
        const AnchorExactInteger order = eta_function_whole((long long)index);
        slope.coefficient.push_back(eta_function_product(&function->coefficient[index], &order));
    }
    eta_function_raise(shape, &slope);
    EtaFunction tilt = *function;
    const AnchorExactInteger factor = eta_function_whole(4ll * (long long)function->power);
    const AnchorExactInteger step = eta_function_product(&factor, &shape->part);
    for (AnchorExactInteger &value : tilt.coefficient)
    {
        value = eta_function_product(&value, &step);
    }
    eta_function_eta(&tilt);
    tilt.power += 1u;
    slope.power = tilt.power;
    eta_function_settle(&slope);
    eta_function_settle(&tilt);
    eta_function_add(shape, &slope, &tilt, result);
}

// result = result + function * numerator / (denominator whole), the rational a whole-number ratio over h's whole
void eta_function_gather(const EtaShape *shape, EtaFunction *result,
                               const EtaFunction *function, const AnchorExactInteger *numerator,
                               long long denominator)
{
    EtaFunction term = *function;
    const AnchorExactInteger bottom = eta_function_whole(denominator);
    const AnchorExactInteger below = eta_function_product(&bottom, &shape->whole);
    eta_function_scale(&term, numerator, &below);
    eta_function_add(shape, result, &term, result);
}

// a + b part + c whole, each a word
AnchorExactInteger eta_function_mixed(const EtaShape *shape, long long part_count, long long whole_count)
{
    const AnchorExactInteger part_factor = eta_function_whole(part_count);
    const AnchorExactInteger whole_factor = eta_function_whole(whole_count);
    const AnchorExactInteger parts = eta_function_product(&part_factor, &shape->part);
    const AnchorExactInteger wholes = eta_function_product(&whole_factor, &shape->whole);
    return eta_function_sum(&parts, &wholes);
}

// (Z_b f)_j = L^-1 ((2 b - 2 j) eta f_j + d f_j'), 2 b - 2 j = numerator / whole
void eta_function_z(const EtaShape *shape, const EtaFunction *function,
                          const EtaFunction *slope, const AnchorExactInteger *numerator,
                          EtaFunction *result)
{
    EtaFunction tilted = *function;
    eta_function_eta(&tilted);
    EtaFunction sum;
    eta_function_zero(&sum);
    eta_function_gather(shape, &sum, &tilted, numerator, 1ll);
    EtaFunction ended = *slope;
    eta_function_end_factor(&ended);
    eta_function_add(shape, &sum, &ended, &sum);
    eta_function_over_l(shape, &sum);
    *result = sum;
}


// sum c_i (top / bottom)^i / (scale M^n): the numerator by Horner in whole numbers over bottom^degree, and
// M(top / bottom) bottom^2 = whole bottom^2 - 2 part top^2
SimRational eta_function_value_at(const EtaShape *shape, const EtaFunction *function, SimRational eta)
{
    if (function->coefficient.empty())
    {
        return sim_rational(0ll, 1ll);
    }
    const AnchorExactInteger &above = eta.numerator;
    const AnchorExactInteger &below = eta.denominator;
    const size_t degree = function->coefficient.size() - 1u;
    AnchorExactInteger sum = function->coefficient[degree];
    AnchorExactInteger lower = below;
    AnchorExactInteger spread = eta_function_whole(1ll);
    for (size_t index = degree; index > 0u; index -= 1u)
    {
        sum = eta_function_product(&sum, &above);
        const AnchorExactInteger term = eta_function_product(&function->coefficient[index - 1u], &lower);
        sum = eta_function_sum(&sum, &term);
        lower = eta_function_product(&lower, &below);
        spread = eta_function_product(&spread, &below);
    }
    const AnchorExactInteger squared_below = eta_function_product(&below, &below);
    const AnchorExactInteger squared_above = eta_function_product(&above, &above);
    const AnchorExactInteger twice = eta_function_sum(&shape->part, &shape->part);
    const AnchorExactInteger first = eta_function_product(&shape->whole, &squared_below);
    const AnchorExactInteger second = eta_function_product(&twice, &squared_above);
    const AnchorExactInteger factor = eta_function_difference(&first, &second);
    SimRational value;
    value.numerator = sum;
    sim_exact_unsigned(&value.denominator, 1ull);
    for (unsigned int step = 0u; step < function->power; step += 1u)
    {
        value.numerator = eta_function_product(&value.numerator, &squared_below);
        value.denominator = eta_function_product(&value.denominator, &factor);
    }
    value.denominator = eta_function_product(&value.denominator, &spread);
    value.denominator = eta_function_product(&value.denominator, &function->scale);
    if (value.denominator.sign < 0)
    {
        value.denominator.sign = 1;
        value.numerator.sign = -value.numerator.sign;
    }
    sim_rational_settle(&value);
    return value;
}

SimRational eta_function_value(const EtaShape *shape, const EtaFunction *function, long long top, long long bottom)
{
    return eta_function_value_at(shape, function, sim_rational(top, bottom));
}

// T_0 = 1, T_1 = eta, T_(m+1) = 2 eta T_m - T_(m-1), every coefficient whole; the weights brought over one scale
void eta_function_chebyshev(const std::vector<SimRational> &weights, EtaFunction *function)
{
    const size_t count = weights.size();
    std::vector<std::vector<long long>> chebyshev(count);
    if (count > 0u)
    {
        chebyshev[0] = std::vector<long long>(1u, 1ll);
    }
    if (count > 1u)
    {
        chebyshev[1] = std::vector<long long>{0ll, 1ll};
    }
    for (size_t degree = 2u; degree < count; degree += 1u)
    {
        chebyshev[degree] = std::vector<long long>(degree + 1u, 0ll);
        for (size_t index = 0u; index < degree; index += 1u)
        {
            chebyshev[degree][index + 1u] += 2ll * chebyshev[degree - 1u][index];
        }
        for (size_t index = 0u; index + 1u < degree; index += 1u)
        {
            chebyshev[degree][index] -= chebyshev[degree - 2u][index];
        }
    }
    AnchorExactInteger scale = eta_function_whole(1ll);
    for (const SimRational &value : weights)
    {
        const AnchorExactInteger common = eta_function_common(&scale, &value.denominator);
        const AnchorExactInteger factor = eta_function_divided(&value.denominator, &common);
        scale = eta_function_product(&scale, &factor);
    }
    function->coefficient.assign(count, eta_function_whole(0ll));
    for (size_t degree = 0u; degree < count; degree += 1u)
    {
        const AnchorExactInteger factor = eta_function_divided(&scale, &weights[degree].denominator);
        const AnchorExactInteger lifted = eta_function_product(&weights[degree].numerator, &factor);
        for (size_t index = 0u; index <= degree; index += 1u)
        {
            const AnchorExactInteger entry = eta_function_whole(chebyshev[degree][index]);
            const AnchorExactInteger term = eta_function_product(&lifted, &entry);
            function->coefficient[index] = eta_function_sum(&function->coefficient[index], &term);
        }
    }
    function->scale = scale;
    function->power = 0u;
    eta_function_settle(function);
}

int eta_function_short(void)
{
    return s_sim_rational_wide != 0;
}
