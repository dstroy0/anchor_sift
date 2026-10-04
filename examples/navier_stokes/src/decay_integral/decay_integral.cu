// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// decay_integral.cu: the two-term decay integral (decay_integral.h)
#include "decay_integral.h"

static void decay_integral_trim(std::vector<SimRational> *values)
{
    while (!values->empty() && (sim_rational_sign(values->back()) == 0))
    {
        values->pop_back();
    }
}

void decay_integral_reduction(unsigned int m, std::vector<SimRational> *a, std::vector<SimRational> *b)
{
    a->clear();
    b->assign(1u, sim_rational(1ll, 1ll));
    for (unsigned int order = 1u; order < m; order += 1u)
    {
        const SimRational over = sim_rational(1ll, (long long)order);
        // (1 - x A) / order
        std::vector<SimRational> next_a(a->size() + 1u, sim_rational(0ll, 1ll));
        next_a[0] = over;
        for (size_t index = 0u; index < a->size(); index += 1u)
        {
            next_a[index + 1u] = sim_rational_negative(sim_rational_product((*a)[index], over));
        }
        // -x B / order
        std::vector<SimRational> next_b(b->size() + 1u, sim_rational(0ll, 1ll));
        for (size_t index = 0u; index < b->size(); index += 1u)
        {
            next_b[index + 1u] = sim_rational_negative(sim_rational_product((*b)[index], over));
        }
        decay_integral_trim(&next_a);
        decay_integral_trim(&next_b);
        a->swap(next_a);
        b->swap(next_b);
    }
}

void decay_integral_residual(unsigned int k, std::vector<SimRational> *first, std::vector<SimRational> *second)
{
    std::vector<SimRational> a;
    std::vector<SimRational> b;
    decay_integral_reduction(k + 2u, &a, &b);
    const SimRational rise = sim_rational((long long)k + 1ll, 1ll);
    const size_t size = ((a.size() > b.size()) ? a.size() : b.size()) + 1u;
    first->assign(size, sim_rational(0ll, 1ll));
    second->assign(size, sim_rational(0ll, 1ll));
    // (k + 1) B - x B': the coefficient of x^j is (k + 1 - j) B_j
    for (size_t index = 0u; index < b.size(); index += 1u)
    {
        (*first)[index] = sim_rational_product(sim_rational_difference(rise, sim_rational((long long)index, 1ll)),
                                               b[index]);
    }
    // (k + 1) A - x A' + x A + B - 1
    for (size_t index = 0u; index < a.size(); index += 1u)
    {
        (*second)[index] = sim_rational_sum(
            (*second)[index],
            sim_rational_product(sim_rational_difference(rise, sim_rational((long long)index, 1ll)), a[index]));
        (*second)[index + 1u] = sim_rational_sum((*second)[index + 1u], a[index]);
    }
    for (size_t index = 0u; index < b.size(); index += 1u)
    {
        (*second)[index] = sim_rational_sum((*second)[index], b[index]);
    }
    (*second)[0] = sim_rational_difference((*second)[0], sim_rational(1ll, 1ll));
    decay_integral_trim(first);
    decay_integral_trim(second);
}

static SimRational decay_integral_polynomial(const std::vector<SimRational> &values, SimRational x)
{
    SimRational sum = sim_rational(0ll, 1ll);
    for (size_t index = values.size(); index > 0u; index -= 1u)
    {
        sum = sim_rational_sum(sim_rational_product(sum, x), values[index - 1u]);
    }
    return sum;
}

AtomForm decay_integral_from_zero(unsigned int k, SimRational n, SimRational b, AtomBook *book)
{
    const SimRational x = sim_rational_product(n, sim_rational_reciprocal(b));
    std::vector<SimRational> a;
    std::vector<SimRational> bb;
    decay_integral_reduction(k + 2u, &a, &bb);
    SimRational lift = b;
    for (unsigned int step = 0u; step < k; step += 1u)
    {
        lift = sim_rational_product(lift, b);
    }
    const std::string name = atom_book_rational(x);
    const unsigned int integral = atom_book_id(book, "E1(" + name + ")");
    const AtomForm decay_part = atom_form_scaled(atom_form_e(sim_rational_negative(x)),
                                                 sim_rational_product(lift, decay_integral_polynomial(a, x)));
    const AtomForm integral_part = atom_form_scaled(atom_form_atom(integral),
                                                    sim_rational_product(lift, decay_integral_polynomial(bb, x)));
    return atom_form_sum(decay_part, integral_part);
}

int decay_integral_short(void)
{
    return s_sim_rational_wide != 0;
}
