// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ka_psi_value.cu: exact values
#include "ka_psi_internal.h"

// beta(L) = 1 + n + ... + n^(L - 1), errored if it would outgrow the word
int psi_case_open(PsiCase *psi_case, unsigned long long dimension, unsigned long long base, unsigned int depth)
{
    psi_case->dimension = dimension;
    psi_case->base = base;
    psi_case->depth = depth;
    psi_case->weight[0] = 0ull;
    unsigned long long power = 1ull;
    for (unsigned int level = 1u; level <= depth; level += 1u)
    {
        if ((psi_case->weight[level - 1u] > (0xFFFFFFFFFFFFFFFFull - power)) || (level > PSI_LEVELS_MAX))
        {
            return 0;
        }
        psi_case->weight[level] = psi_case->weight[level - 1u] + power;
        if ((level < depth) && (power > (0xFFFFFFFFFFFFFFFFull / dimension)))
        {
            return 0;
        }
        power *= dimension;
    }
    return 1;
}

void psi_times_integer(const AnchorExactInteger *value, unsigned long long factor, AnchorExactInteger *result)
{
    AnchorExactInteger integer_part;
    sim_exact_unsigned(&integer_part, factor);
    sim_rational_status_check(sim_exact_product(value, &integer_part, result));
}

void psi_add(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result)
{
    sim_rational_status_check(sim_exact_sum(left, right, result));
}

void psi_multiply(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result)
{
    sim_rational_status_check(sim_exact_product(left, right, result));
}

SimRational psi_rational_exact(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator)
{
    SimRational value;
    value.numerator = *numerator;
    value.denominator = *denominator;
    sim_rational_settle(&value);
    return value;
}

void psi_value_zero(PsiValue *value)
{
    value->count = 0u;
}

void psi_value_add_term(PsiValue *value, SimRational coefficient, unsigned long long exponent)
{
    if (sim_rational_sign(coefficient) == 0)
    {
        return;
    }
    unsigned int at = 0u;
    while ((at < value->count) && (value->exponent[at] < exponent))
    {
        at += 1u;
    }
    if ((at < value->count) && (value->exponent[at] == exponent))
    {
        value->coefficient[at] = sim_rational_sum(value->coefficient[at], coefficient);
        if (sim_rational_sign(value->coefficient[at]) == 0)
        {
            for (unsigned int move = at; (move + 1u) < value->count; move += 1u)
            {
                value->coefficient[move] = value->coefficient[move + 1u];
                value->exponent[move] = value->exponent[move + 1u];
            }
            value->count -= 1u;
        }
        return;
    }
    if (value->count == PSI_TERMS)
    {
        s_sim_rational_wide = 1;
        return;
    }
    for (unsigned int move = value->count; move > at; move -= 1u)
    {
        value->coefficient[move] = value->coefficient[move - 1u];
        value->exponent[move] = value->exponent[move - 1u];
    }
    value->coefficient[at] = coefficient;
    value->exponent[at] = exponent;
    value->count += 1u;
}

// into += scale . from; into and from are distinct
void psi_value_add(PsiValue *into, const PsiValue *from, SimRational scale)
{
    for (unsigned int at = 0u; at < from->count; at += 1u)
    {
        psi_value_add_term(into, sim_rational_product(scale, from->coefficient[at]), from->exponent[at]);
    }
}

void psi_value_scale(PsiValue *value, SimRational scale)
{
    for (unsigned int at = 0u; at < value->count; at += 1u)
    {
        value->coefficient[at] = sim_rational_product(value->coefficient[at], scale);
    }
}

// |head| . base^gap > tail, decided by bit lengths when the gap is wide and by an exact power otherwise
static int psi_dominates(SimRational head, SimRational tail, unsigned long long gap, unsigned long long base,
                         int *decided)
{
    *decided = 1;
    head = sim_rational_absolute(head);
    if (sim_rational_sign(tail) == 0)
    {
        return 1;
    }
    // tail / |head| < 2^(top - bottom + 2), and base^gap >= 2^gap
    const unsigned long long top = sim_exact_bits(&tail.numerator) + sim_exact_bits(&head.denominator);
    const unsigned long long bottom = sim_exact_bits(&tail.denominator) + sim_exact_bits(&head.numerator);
    const unsigned long long need = (top > bottom) ? ((top - bottom) + 2ull) : 2ull;
    if (gap >= need)
    {
        return 1;
    }
    if (gap > PSI_EXPAND_MAX)
    {
        *decided = 0;
        return 0;
    }
    AnchorExactInteger power;
    AnchorExactInteger scaled;
    AnchorExactInteger left;
    AnchorExactInteger right;
    sim_rational_status_check(sim_exact_power(base, gap, &power));
    psi_multiply(&head.numerator, &power, &scaled);
    psi_multiply(&scaled, &tail.denominator, &left);
    psi_multiply(&tail.numerator, &head.denominator, &right);
    return anchor_exact_compare(&left, &right) > 0;
}

// the exact sign of sum c_j . base^-e_j: the leading terms are folded in until they outweigh any tail the rest can make
int psi_value_sign(const PsiValue *value, unsigned long long base)
{
    unsigned int lead = 0u;
    while (lead < value->count)
    {
        SimRational head = value->coefficient[lead];
        const unsigned long long origin = value->exponent[lead];
        SimRational tail = sim_rational(0ll, 1ll);
        for (unsigned int at = lead + 1u; at < value->count; at += 1u)
        {
            tail = sim_rational_sum(tail, sim_rational_absolute(value->coefficient[at]));
        }
        unsigned int next = lead + 1u;
        int restart = 0;
        while (restart == 0)
        {
            if (next == value->count)
            {
                return sim_rational_sign(head);
            }
            const unsigned long long gap = value->exponent[next] - origin;
            int decided = 1;
            if (psi_dominates(head, tail, gap, base, &decided))
            {
                return sim_rational_sign(head);
            }
            if ((decided == 0) || (gap > PSI_EXPAND_MAX))
            {
                s_sim_rational_wide = 1;
                return sim_rational_sign(head);
            }
            AnchorExactInteger power;
            AnchorExactInteger one;
            sim_rational_status_check(sim_exact_power(base, gap, &power));
            sim_exact_unsigned(&one, 1ull);
            const SimRational shrink = psi_rational_exact(&one, &power);
            head = sim_rational_sum(head, sim_rational_product(value->coefficient[next], shrink));
            tail = sim_rational_difference(tail, sim_rational_absolute(value->coefficient[next]));
            next += 1u;
            if (sim_rational_sign(head) == 0)
            {
                lead = next;
                restart = 1;
            }
        }
    }
    return 0;
}

int psi_value_compare(const PsiValue *left, const PsiValue *right, unsigned long long base)
{
    static PsiValue difference;
    difference = *left;
    psi_value_add(&difference, right, sim_rational(-1ll, 1ll));
    return psi_value_sign(&difference, base);
}

// the exact rational a sparse value stands for, when every exponent is small enough to expand
SimRational psi_value_expand(const PsiValue *value, unsigned long long base)
{
    SimRational total = sim_rational(0ll, 1ll);
    for (unsigned int at = 0u; at < value->count; at += 1u)
    {
        AnchorExactInteger power;
        AnchorExactInteger one;
        sim_rational_status_check(sim_exact_power(base, value->exponent[at], &power));
        sim_exact_unsigned(&one, 1ull);
        total = sim_rational_sum(total, sim_rational_product(value->coefficient[at], psi_rational_exact(&one, &power)));
    }
    return total;
}

void psi_value_print(ScripturaLine *line, const PsiValue *value)
{
    scriptura_decimal(line, value->count, 1u);
    scriptura_text(line, " terms, from ");
    for (unsigned int at = 0u; (at < value->count) && (at < 2u); at += 1u)
    {
        if (at != 0u)
        {
            scriptura_text(line, " + ");
        }
        sim_rational_print(line, value->coefficient[at]);
        scriptura_text(line, " g^-");
        scriptura_decimal(line, value->exponent[at], 1u);
    }
    if (value->count != 0u)
    {
        scriptura_text(line, " to exponent ");
        scriptura_decimal(line, value->exponent[value->count - 1u], 1u);
    }
}

// Sprecher's psi (2.4) on D_5 at n = 2, gamma = 10, as a numerator over 2^5 . gamma^beta(5)
void psi_sprecher_numerator(const PsiCase *psi_case, const unsigned char *digit, AnchorExactInteger *numerator)
{
    const unsigned long long base = psi_case->base;
    sim_exact_unsigned(numerator, 0ull);
    for (unsigned int level = 1u; level <= PSI_EXHAUSTIVE; level += 1u)
    {
        const unsigned long long place = digit[level - 1u];
        const unsigned long long carried = ((level >= 2u) && (place == (base - 1ull))) ? 1ull : 0ull;
        // tilde i_r = i_r - (gamma - 2) <i_r>
        const unsigned long long reduced = place - ((base - 2ull) * carried);
        if (reduced == 0ull)
        {
            continue;
        }
        // m_r = <i_r> (1 + sum over s < r of [i_s] ... [i_(r-1)])
        unsigned long long shifts = 0ull;
        if (carried != 0ull)
        {
            shifts = 1ull;
            for (unsigned int start = 1u; start < level; start += 1u)
            {
                unsigned long long run = 1ull;
                for (unsigned int at = start; at < level; at += 1u)
                {
                    const unsigned long long step = digit[at - 1u];
                    run *= ((at >= 2u) && (step >= (base - 2ull))) ? 1ull : 0ull;
                }
                shifts += run;
            }
        }
        AnchorExactInteger power;
        AnchorExactInteger term;
        AnchorExactInteger total;
        sim_rational_status_check(
            sim_exact_power(base, psi_case->weight[PSI_EXHAUSTIVE] - psi_case->weight[level - shifts], &power));
        // the level's term, over 2^5 . gamma^beta(5): reduced . 2^(5 - m_r) . gamma^(beta(5) - beta(r - m_r))
        psi_times_integer(&power, reduced * (1ull << (PSI_EXHAUSTIVE - shifts)), &term);
        psi_add(numerator, &term, &total);
        *numerator = total;
    }
}
