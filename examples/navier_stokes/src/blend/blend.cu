// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// blend.cu: the blend weight's integrals (blend.h)
#include "blend.h"

#include "decay_integral.h"
#include "ode_series.h"

static std::vector<SimRational> blend_words(std::initializer_list<long long> words)
{
    std::vector<SimRational> values;
    for (long long word : words)
    {
        values.push_back(sim_rational(word, 1ll));
    }
    return values;
}

TaylorSeries blend_weight(SimRational center, unsigned int terms, AtomBook *book, SimRational *ratio,
                          unsigned int *share)
{
    const std::string name = atom_book_rational(center);
    *ratio = sim_rational_difference(sim_rational_reciprocal(center),
                                     sim_rational_reciprocal(sim_rational_difference(sim_rational(1ll, 1ll), center)));
    // at c = 1/2, r = 1 and rho = 1/2: no atom
    const int even = sim_rational_sign(*ratio) == 0;
    *share = even ? 0u : atom_book_id(book, "rho(" + name + ")");
    const AtomForm rho = even ? atom_form_rational(sim_rational(1ll, 2ll)) : atom_form_atom(*share);
    const TaylorSeries alpha =
        taylor_rational(center, ode_series_first(blend_words({0ll, 0ll, 1ll}), blend_words({1ll}), center, terms));
    const TaylorSeries beta =
        taylor_rational(center, ode_series_first(blend_words({1ll, -2ll, 1ll}), blend_words({-1ll}), center, terms));
    std::vector<SimRational> unit(terms, sim_rational(0ll, 1ll));
    unit[0] = sim_rational(1ll, 1ll);
    const TaylorSeries one = taylor_rational(center, unit);
    const TaylorSeries lean = taylor_sum(taylor_difference(alpha, one),
                                         taylor_form_scaled(taylor_difference(beta, one), atom_form_e(*ratio)));
    const TaylorSeries unit_part = taylor_sum(one, taylor_form_scaled(lean, rho));
    TaylorSeries weight =
        taylor_form_scaled(taylor_product(alpha, taylor_unit_inverse(unit_part)), rho);
    for (AtomForm &form : weight.coefficient)
    {
        form = atom_form_unit_reduced(form, *ratio, *share);
    }
    return weight;
}

// int_0^b psi^power G, power 1 or 2, G about 0 in s
static AtomForm blend_end(const TaylorSeries &integrand, unsigned int power, SimRational end,
                          const BlendPieces *pieces, AtomBook *book)
{
    AtomForm sum;
    for (unsigned int order = 1u; order <= pieces->orders; order += 1u)
    {
        if ((power == 2u) && (order < 2u))
        {
            continue;
        }
        // (-1)^(N+1) for psi, (-1)^N (N - 1) for psi^2
        const long long sign = ((order & 1u) != 0u) ? 1ll : -1ll;
        const SimRational weight =
            (power == 1u) ? sim_rational(sign, 1ll) : sim_rational(-sign * ((long long)order - 1ll), 1ll);
        const SimRational count = sim_rational((long long)order, 1ll);
        std::vector<SimRational> fall(1u, count);
        const TaylorSeries rise = taylor_rational(
            sim_rational(0ll, 1ll),
            ode_series_first(blend_words({1ll, -2ll, 1ll}), fall, sim_rational(0ll, 1ll), pieces->terms));
        const TaylorSeries product = taylor_product(rise, integrand);
        AtomForm part;
        for (unsigned int k = 0u; k < product.coefficient.size(); k += 1u)
        {
            part = atom_form_sum(part, atom_form_product(product.coefficient[k],
                                                         decay_integral_from_zero(k, count, end, book)));
        }
        sum = atom_form_sum(sum, atom_form_scaled(atom_form_product(part, atom_form_e(count)), weight));
    }
    return sum;
}

// the series in t = 1 - s about t = 0 of a series about s = 1
static TaylorSeries blend_reflected(const TaylorSeries &series)
{
    TaylorSeries reflected = taylor_stretched(series, sim_rational(-1ll, 1ll));
    reflected.center = sim_rational(0ll, 1ll);
    return reflected;
}

static TaylorSeries blend_power(const TaylorSeries &weight, unsigned int power, SimRational ratio, unsigned int share)
{
    if (power == 1u)
    {
        return weight;
    }
    TaylorSeries square = taylor_product(weight, weight);
    for (AtomForm &form : square.coefficient)
    {
        form = atom_form_unit_reduced(form, ratio, share);
    }
    return square;
}

AtomForm blend_integral(const BlendPieces *pieces, unsigned int power, BlendIntegrand integrand, const void *context,
                        AtomBook *book)
{
    const size_t count = pieces->cuts.size();
    const SimRational zero = sim_rational(0ll, 1ll);
    const SimRational one = sim_rational(1ll, 1ll);
    AtomForm sum;
    for (size_t piece = 0u; piece + 1u < count; piece += 1u)
    {
        const SimRational low = pieces->cuts[piece];
        const SimRational high = pieces->cuts[piece + 1u];
        if (piece == 0u)
        {
            const TaylorSeries g = integrand(context, zero, pieces->terms, book);
            sum = atom_form_sum(sum, taylor_integral(g, zero, high));
            if (power > 0u)
            {
                sum = atom_form_sum(sum, blend_end(g, power, high, pieces, book));
            }
            continue;
        }
        if (piece + 2u == count)
        {
            // psi(s) = 1 - psi(t): psi = 1 - psi_t, psi^2 = 1 - 2 psi_t + psi_t^2, t from 0 to 1 - low
            const TaylorSeries g = blend_reflected(integrand(context, one, pieces->terms, book));
            const SimRational end = sim_rational_difference(one, low);
            if (power == 0u)
            {
                sum = atom_form_sum(sum, taylor_integral(g, zero, end));
                continue;
            }
            const AtomForm plain = taylor_integral(g, zero, end);
            const AtomForm first = blend_end(g, 1u, end, pieces, book);
            if (power == 1u)
            {
                sum = atom_form_sum(sum, atom_form_difference(plain, first));
                continue;
            }
            const AtomForm second = blend_end(g, 2u, end, pieces, book);
            sum = atom_form_sum(sum, atom_form_sum(atom_form_difference(plain, atom_form_scaled(first, sim_rational(2ll, 1ll))),
                                                   second));
            continue;
        }
        const SimRational center = sim_rational_product(sim_rational_sum(low, high), sim_rational(1ll, 2ll));
        const TaylorSeries g = integrand(context, center, pieces->terms, book);
        if (power == 0u)
        {
            sum = atom_form_sum(sum, taylor_integral(g, low, high));
            continue;
        }
        SimRational ratio = sim_rational(0ll, 1ll);
        unsigned int share = 0u;
        const TaylorSeries weight = blend_weight(center, pieces->terms, book, &ratio, &share);
        TaylorSeries product = taylor_product(blend_power(weight, power, ratio, share), g);
        AtomForm part = taylor_integral(product, low, high);
        sum = atom_form_sum(sum, atom_form_unit_reduced(part, ratio, share));
    }
    return sum;
}

int blend_short(void)
{
    return s_sim_rational_wide != 0;
}
