// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Kolmogorov's inner function, exactly (Braun and Griebel, Constructive Approximation 30(3) (2009) 653-675, the
// preprint's section 2). Every value is exact: on the grids by exact integers over a common denominator, and at
// depth by a sparse sum of c . gamma^-e whose exponent e = beta(L) = (n^L - 1)/(n - 1) is carried as an integer and
// never expanded (Doug, 23 September: "the exp is symbolic").
// 1. Sprecher's psi (2.4) reproduces the paper's counterexample exactly and its descents are counted.
// 2. Koppen's psi, in two readings the paper gives: (2.9)/(2.10), which its proofs use, where the carried midpoint
//    adds (gamma - 2)/2 units; and (2.7) as printed, which adds (gamma - 1)/2. On every point of D_1 to D_5 the
//    pair recursion (the scale step) equals the level-by-level recursion, psi is strictly increasing, its smallest
//    gap is exactly gamma^-beta(L), and its largest gap is what the gap recursion predicts.
// 3. Every scale, by the chained step: the smallest gap stays gamma^-beta(L) and the step stays monotone because
//    gamma^(n^(L-1)) > gamma + 1, checked symbolically to depth; the largest gap stays below 2^-(L-1)/gamma and below
//    the paper's Lemma 2.3 bound, so psi extends to a continuous strictly increasing function; a keyed point at
//    depth lands its gap between the two.

#include "sim_rational.h"

#define PSI_TERMS 64u

#define PSI_LEVELS_MOST 61u

#define PSI_EXHAUSTIVE 5u

// the widest relative exponent the sign test expands into an exact power
#define PSI_EXPAND_MOST 1024ull

#define PSI_KEY 0x505349ull

typedef struct
{
    unsigned int count;
    SimRational coefficient[PSI_TERMS];
    unsigned long long exponent[PSI_TERMS];
} PsiValue;

typedef struct
{
    unsigned long long dimension;
    unsigned long long base;
    unsigned int depth;
    unsigned long long weight[PSI_LEVELS_MOST + 1u];
} PsiCase;

typedef struct
{
    AnchorExactInteger lift[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger up[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger unit[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger half[PSI_EXHAUSTIVE + 1u];
    AnchorExactInteger denominator[PSI_EXHAUSTIVE + 1u];
} PsiScale;

// beta(L) = 1 + n + ... + n^(L - 1), refused if it would outgrow the word
static int psi_case_open(PsiCase *psi_case, unsigned long long dimension, unsigned long long base, unsigned int depth)
{
    psi_case->dimension = dimension;
    psi_case->base = base;
    psi_case->depth = depth;
    psi_case->weight[0] = 0ull;
    unsigned long long power = 1ull;
    for (unsigned int level = 1u; level <= depth; level += 1u)
    {
        if ((psi_case->weight[level - 1u] > (0xFFFFFFFFFFFFFFFFull - power)) || (level > PSI_LEVELS_MOST))
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

static void psi_times_whole(const AnchorExactInteger *value, unsigned long long factor, AnchorExactInteger *result)
{
    AnchorExactInteger whole;
    sim_exact_whole(&whole, factor);
    sim_rational_took(sim_exact_product(value, &whole, result));
}

static void psi_add(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result)
{
    sim_rational_took(sim_exact_sum(left, right, result));
}

static void psi_multiply(const AnchorExactInteger *left, const AnchorExactInteger *right, AnchorExactInteger *result)
{
    sim_rational_took(sim_exact_product(left, right, result));
}

static SimRational psi_rational_exact(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator)
{
    SimRational value;
    value.numerator = *numerator;
    value.denominator = *denominator;
    sim_rational_settle(&value);
    return value;
}

static void psi_value_zero(PsiValue *value)
{
    value->count = 0u;
}

static void psi_value_add_term(PsiValue *value, SimRational coefficient, unsigned long long exponent)
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
static void psi_value_add(PsiValue *into, const PsiValue *from, SimRational scale)
{
    for (unsigned int at = 0u; at < from->count; at += 1u)
    {
        psi_value_add_term(into, sim_rational_product(scale, from->coefficient[at]), from->exponent[at]);
    }
}

static void psi_value_scale(PsiValue *value, SimRational scale)
{
    for (unsigned int at = 0u; at < value->count; at += 1u)
    {
        value->coefficient[at] = sim_rational_product(value->coefficient[at], scale);
    }
}

// |head| . base^gap > tail, decided by bit lengths when the gap is wide and by an exact power otherwise
static int psi_dominates(SimRational head, SimRational tail, unsigned long long gap, unsigned long long base, int *decided)
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
    if (gap > PSI_EXPAND_MOST)
    {
        *decided = 0;
        return 0;
    }
    AnchorExactInteger power;
    AnchorExactInteger scaled;
    AnchorExactInteger left;
    AnchorExactInteger right;
    sim_rational_took(sim_exact_power(base, gap, &power));
    psi_multiply(&head.numerator, &power, &scaled);
    psi_multiply(&scaled, &tail.denominator, &left);
    psi_multiply(&tail.numerator, &head.denominator, &right);
    return anchor_exact_compare(&left, &right) > 0;
}

// the exact sign of sum c_j . base^-e_j: the leading terms are folded in until they outweigh any tail the rest can make
static int psi_value_sign(const PsiValue *value, unsigned long long base)
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
            if ((decided == 0) || (gap > PSI_EXPAND_MOST))
            {
                s_sim_rational_wide = 1;
                return sim_rational_sign(head);
            }
            AnchorExactInteger power;
            AnchorExactInteger one;
            sim_rational_took(sim_exact_power(base, gap, &power));
            sim_exact_whole(&one, 1ull);
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

static int psi_value_compare(const PsiValue *left, const PsiValue *right, unsigned long long base)
{
    static PsiValue difference;
    difference = *left;
    psi_value_add(&difference, right, sim_rational(-1ll, 1ll));
    return psi_value_sign(&difference, base);
}

// the exact rational a sparse value stands for, when every exponent is small enough to expand
static SimRational psi_value_expand(const PsiValue *value, unsigned long long base)
{
    SimRational total = sim_rational(0ll, 1ll);
    for (unsigned int at = 0u; at < value->count; at += 1u)
    {
        AnchorExactInteger power;
        AnchorExactInteger one;
        sim_rational_took(sim_exact_power(base, value->exponent[at], &power));
        sim_exact_whole(&one, 1ull);
        total = sim_rational_sum(total, sim_rational_product(value->coefficient[at], psi_rational_exact(&one, &power)));
    }
    return total;
}

static void psi_value_print(ScripturaLine *line, const PsiValue *value)
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
static void psi_sprecher_numerator(const PsiCase *psi_case, const unsigned char *digit, AnchorExactInteger *numerator)
{
    const unsigned long long base = psi_case->base;
    sim_exact_whole(numerator, 0ull);
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
        sim_rational_took(sim_exact_power(base, psi_case->weight[PSI_EXHAUSTIVE] - psi_case->weight[level - shifts],
                                          &power));
        // the level's term, over 2^5 . gamma^beta(5): reduced . 2^(5 - m_r) . gamma^(beta(5) - beta(r - m_r))
        psi_times_whole(&power, reduced * (1ull << (PSI_EXHAUSTIVE - shifts)), &term);
        psi_add(numerator, &term, &total);
        *numerator = total;
    }
}

static void psi_digits(unsigned long long index, unsigned long long base, unsigned int levels, unsigned char *digit)
{
    for (unsigned int at = levels; at > 0u; at -= 1u)
    {
        // a digit is below the base, which is far below 256
        digit[at - 1u] = (unsigned char)(index % base);
        index /= base;
    }
}

static void psi_sprecher(SimTally *tally, const PsiCase *psi_case)
{
    ScripturaLine *const line = &tally->line;
    AnchorExactInteger denominator;
    AnchorExactInteger power;
    sim_rational_took(sim_exact_power(psi_case->base, psi_case->weight[PSI_EXHAUSTIVE], &power));
    psi_times_whole(&power, 1ull << PSI_EXHAUSTIVE, &denominator);
    const unsigned char before[PSI_EXHAUSTIVE] = {5u, 8u, 9u, 9u, 9u};
    const unsigned char after[PSI_EXHAUSTIVE] = {5u, 9u, 0u, 0u, 0u};
    AnchorExactInteger numerator;
    psi_sprecher_numerator(psi_case, before, &numerator);
    const SimRational low = psi_rational_exact(&numerator, &denominator);
    psi_sprecher_numerator(psi_case, after, &numerator);
    const SimRational high = psi_rational_exact(&numerator, &denominator);
    sim_check(tally, sim_rational_equal(low, sim_rational(2207ll, 4000ll)), "Sprecher's psi(0.58999) is 0.55175 exactly (2.5)");
    sim_check(tally, sim_rational_equal(high, sim_rational(11ll, 20ll)), "Sprecher's psi(0.59) is 0.55 exactly (2.5)");
    sim_check(tally, sim_rational_sign(sim_rational_difference(low, high)) > 0, "so Sprecher's psi is not monotone");
    unsigned long long descents = 0ull;
    unsigned long long first = 0ull;
    AnchorExactInteger previous;
    unsigned char digit[PSI_EXHAUSTIVE];
    const unsigned long long points = 100000ull;
    for (unsigned long long index = 0ull; index < points; index += 1ull)
    {
        psi_digits(index, psi_case->base, PSI_EXHAUSTIVE, digit);
        psi_sprecher_numerator(psi_case, digit, &numerator);
        if ((index != 0ull) && (anchor_exact_compare(&numerator, &previous) < 0))
        {
            first = (descents == 0ull) ? index : first;
            descents += 1ull;
        }
        previous = numerator;
    }
    sim_check(tally, descents != 0ull, "Sprecher's psi descends on D_5");
    scriptura_text(line, "\n  1. Sprecher's psi (2.4), n = 2, gamma = 10: psi(0.58999) = ");
    sim_rational_print(line, low);
    scriptura_text(line, " and psi(0.59) = ");
    sim_rational_print(line, high);
    scriptura_text(line, " (the paper's (2.5), exact)\n     it descends between ");
    scriptura_decimal(line, descents, 1u);
    scriptura_text(line, " of the 99,999 neighbouring pairs of D_5, the first at 0.");
    psi_digits(first, psi_case->base, PSI_EXHAUSTIVE, digit);
    for (unsigned int at = 0u; at < PSI_EXHAUSTIVE; at += 1u)
    {
        scriptura_character(line, (char)('0' + digit[at]));
    }
    scriptura_character(line, '\n');
    sim_flush(tally);
}

static void psi_scale_open(const PsiCase *psi_case, PsiScale *scale)
{
    for (unsigned int level = 1u; level <= PSI_EXHAUSTIVE; level += 1u)
    {
        AnchorExactInteger power;
        sim_rational_took(sim_exact_power(psi_case->base, psi_case->weight[level] - psi_case->weight[level - 1u],
                                          &scale->lift[level]));
        psi_times_whole(&scale->lift[level], 2ull, &scale->up[level]);
        sim_exact_whole(&scale->unit[level], 1ull << level);
        sim_exact_whole(&scale->half[level], 1ull << (level - 1u));
        sim_rational_took(sim_exact_power(psi_case->base, psi_case->weight[level], &power));
        psi_times_whole(&power, 1ull << level, &scale->denominator[level]);
    }
}

// The scale step in numerators over D_L = 2^L . gamma^beta(L): (value, plus) at level L - 1 are raised by
// 2 gamma^(beta(L) - beta(L - 1)); a regular digit adds i units of 2^L; the carried midpoint is
// (value + plus) gamma^(beta(L) - beta(L - 1)) + tilt . 2^(L - 1), tilt being gamma - 2 (2.9) or gamma - 1 (2.7)
static void psi_pair_numerator(const PsiCase *psi_case, const PsiScale *scale, const unsigned char *digit,
                               unsigned int levels, unsigned long long tilt, AnchorExactInteger *value,
                               AnchorExactInteger *plus)
{
    const unsigned long long base = psi_case->base;
    sim_exact_whole(value, 2ull * digit[0]);
    sim_exact_whole(plus, 2ull * (digit[0] + 1ull));
    for (unsigned int level = 2u; level <= levels; level += 1u)
    {
        const unsigned long long place = digit[level - 1u];
        AnchorExactInteger raised;
        AnchorExactInteger shifted;
        AnchorExactInteger both;
        AnchorExactInteger lifted;
        AnchorExactInteger midpoint;
        if (place < (base - 2ull))
        {
            psi_multiply(value, &scale->up[level], &raised);
            psi_times_whole(&scale->unit[level], place + 1ull, &shifted);
            psi_add(&raised, &shifted, plus);
            psi_times_whole(&scale->unit[level], place, &shifted);
            psi_add(&raised, &shifted, value);
            continue;
        }
        psi_add(value, plus, &both);
        psi_multiply(&both, &scale->lift[level], &lifted);
        psi_times_whole(&scale->half[level], tilt, &shifted);
        psi_add(&lifted, &shifted, &midpoint);
        if (place == (base - 2ull))
        {
            psi_multiply(value, &scale->up[level], &raised);
            psi_times_whole(&scale->unit[level], place, &shifted);
            psi_add(&raised, &shifted, value);
            *plus = midpoint;
        }
        else
        {
            psi_multiply(plus, &scale->up[level], &raised);
            *plus = raised;
            *value = midpoint;
        }
    }
}

// level L from level L - 1, point by point, as the paper's recursion reads: a regular digit adds to the prefix's
// value, and the last digit takes the prefix and its successor's average plus the carried units
static void psi_table_next(const PsiCase *psi_case, const PsiScale *scale, unsigned int level, unsigned long long tilt,
                           const AnchorExactInteger *below, unsigned long long below_count, AnchorExactInteger *table)
{
    const unsigned long long base = psi_case->base;
    for (unsigned long long prefix = 0ull; prefix < below_count; prefix += 1ull)
    {
        AnchorExactInteger raised;
        AnchorExactInteger shifted;
        psi_multiply(&below[prefix], &scale->up[level], &raised);
        for (unsigned long long place = 0ull; place < (base - 1ull); place += 1ull)
        {
            psi_times_whole(&scale->unit[level], place, &shifted);
            psi_add(&raised, &shifted, &table[(prefix * base) + place]);
        }
        AnchorExactInteger both;
        AnchorExactInteger lifted;
        psi_add(&below[prefix], &below[prefix + 1ull], &both);
        psi_multiply(&both, &scale->lift[level], &lifted);
        psi_times_whole(&scale->half[level], tilt, &shifted);
        psi_add(&lifted, &shifted, &table[(prefix * base) + base - 1ull]);
    }
    psi_multiply(&below[below_count], &scale->up[level], &table[below_count * base]);
}

static const char *psi_reading(const PsiCase *psi_case, unsigned long long tilt)
{
    return (tilt == (psi_case->base - 2ull)) ? "(2.9)/(2.10), the form the proofs use" : "(2.7) as printed";
}

// the carried midpoint splits a gap D into D/2 - s u/2 on each side, s = tilt and 2(gamma - 2) - tilt
static unsigned long long psi_wide_side(const PsiCase *psi_case, unsigned long long tilt)
{
    const unsigned long long other = (2ull * (psi_case->base - 2ull)) - tilt;
    return (tilt < other) ? tilt : other;
}

static void psi_exhaustive(SimTally *tally, const PsiCase *psi_case, const PsiScale *scale, unsigned long long tilt,
                           AnchorExactInteger *measured_widest)
{
    ScripturaLine *const line = &tally->line;
    const unsigned long long base = psi_case->base;
    unsigned long long most = 1ull;
    for (unsigned int level = 0u; level < PSI_EXHAUSTIVE; level += 1u)
    {
        most *= base;
    }
    AnchorExactInteger *below = (AnchorExactInteger *)malloc((size_t)(most + 1ull) * sizeof(AnchorExactInteger));
    AnchorExactInteger *table = (AnchorExactInteger *)malloc((size_t)(most + 1ull) * sizeof(AnchorExactInteger));
    if ((below == NULL) || (table == NULL))
    {
        sim_check(tally, 0, "the level tables were held");
        free(below);
        free(table);
        return;
    }
    for (unsigned long long index = 0ull; index <= base; index += 1ull)
    {
        sim_exact_whole(&table[index], 2ull * index);
    }
    AnchorExactInteger predicted;
    sim_exact_whole(&predicted, 2ull);
    const unsigned long long side = psi_wide_side(psi_case, tilt);
    unsigned long long points = base;
    scriptura_text(line, "     reading ");
    scriptura_text(line, psi_reading(psi_case, tilt));
    scriptura_text(line, ":\n     level   points   step = recursion   increasing   least gap = g^-beta(L)   widest gap = predicted\n");
    for (unsigned int level = 1u; level <= PSI_EXHAUSTIVE; level += 1u)
    {
        if (level >= 2u)
        {
            AnchorExactInteger *const swap = below;
            below = table;
            table = swap;
            psi_table_next(psi_case, scale, level, tilt, below, points, table);
            points *= base;
            AnchorExactInteger lifted;
            AnchorExactInteger shrink;
            AnchorExactInteger next;
            psi_multiply(&predicted, &scale->lift[level], &lifted);
            psi_times_whole(&scale->half[level], side, &shrink);
            sim_rational_took(sim_exact_less(&lifted, &shrink, &next));
            predicted = next;
        }
        unsigned long long matched = 0ull;
        unsigned long long increasing = 0ull;
        AnchorExactInteger least;
        AnchorExactInteger widest;
        unsigned char digit[PSI_EXHAUSTIVE];
        for (unsigned long long index = 0ull; index < points; index += 1ull)
        {
            AnchorExactInteger value;
            AnchorExactInteger plus;
            AnchorExactInteger gap;
            psi_digits(index, base, level, digit);
            psi_pair_numerator(psi_case, scale, digit, level, tilt, &value, &plus);
            matched += ((anchor_exact_compare(&value, &table[index]) == 0)
                        && (anchor_exact_compare(&plus, &table[index + 1ull]) == 0))
                     ? 1ull
                     : 0ull;
            sim_rational_took(sim_exact_less(&table[index + 1ull], &table[index], &gap));
            increasing += (gap.sign > 0) ? 1ull : 0ull;
            if ((index == 0ull) || (anchor_exact_compare(&gap, &least) < 0))
            {
                least = gap;
            }
            if ((index == 0ull) || (anchor_exact_compare(&gap, &widest) > 0))
            {
                widest = gap;
            }
        }
        const int least_is_unit = (anchor_exact_compare(&least, &scale->unit[level]) == 0);
        const int widest_predicted = (anchor_exact_compare(&widest, &predicted) == 0);
        measured_widest[level] = widest;
        sim_check(tally, matched == points, "the scale step (the pair recursion) equals the level recursion on every point");
        sim_check(tally, increasing == points, "psi is strictly increasing on every neighbouring pair");
        sim_check(tally, least_is_unit, "the least gap at level L is exactly gamma^-beta(L)");
        sim_check(tally, widest_predicted, "the widest gap is the gap recursion's");
        scriptura_decimal_columns(line, level, 10u);
        scriptura_decimal_columns(line, points, 9u);
        scriptura_decimal_columns(line, matched, 19u);
        scriptura_decimal_columns(line, increasing, 13u);
        scriptura_text(line, least_is_unit ? "                      yes" : "                       NO");
        scriptura_text(line, widest_predicted ? "                      yes\n" : "                       NO\n");
    }
    sim_flush(tally);
    free(below);
    free(table);
}

static void psi_pair_symbolic(const PsiCase *psi_case, const unsigned char *digit, unsigned int levels,
                              unsigned long long tilt, PsiValue *value, PsiValue *plus)
{
    static PsiValue held;
    const unsigned long long base = psi_case->base;
    // tilt / 2 is at most (gamma - 1) / 2, far inside a word
    const SimRational carried = sim_rational((long long)tilt, 2ll);
    const SimRational half = sim_rational(1ll, 2ll);
    psi_value_zero(value);
    psi_value_zero(plus);
    psi_value_add_term(value, sim_rational((long long)digit[0], 1ll), psi_case->weight[1]);
    psi_value_add_term(plus, sim_rational((long long)digit[0] + 1ll, 1ll), psi_case->weight[1]);
    for (unsigned int level = 2u; level <= levels; level += 1u)
    {
        const unsigned long long place = digit[level - 1u];
        const unsigned long long exponent = psi_case->weight[level];
        if (place < (base - 2ull))
        {
            *plus = *value;
            // a digit is below the base, far inside a word
            psi_value_add_term(plus, sim_rational((long long)place + 1ll, 1ll), exponent);
            psi_value_add_term(value, sim_rational((long long)place, 1ll), exponent);
        }
        else if (place == (base - 2ull))
        {
            held = *value;
            psi_value_scale(plus, half);
            psi_value_add(plus, &held, half);
            psi_value_add_term(plus, carried, exponent);
            psi_value_add_term(value, sim_rational((long long)place, 1ll), exponent);
        }
        else
        {
            psi_value_scale(value, half);
            psi_value_add(value, plus, half);
            psi_value_add_term(value, carried, exponent);
        }
    }
}

static void psi_all_scales(SimTally *tally, const PsiCase *psi_case, const PsiScale *scale, unsigned long long tilt,
                           const AnchorExactInteger *measured_widest)
{
    ScripturaLine *const line = &tally->line;
    static PsiValue step;
    static PsiValue widest;
    static PsiValue bound;
    static PsiValue value;
    static PsiValue plus;
    static PsiValue gap;
    static PsiValue unit;
    const unsigned long long base = psi_case->base;
    const unsigned int depth = psi_case->depth;
    const long long side = (long long)psi_wide_side(psi_case, tilt);
    // the base is a small integer, far inside a word
    const long long signed_base = (long long)base;
    unsigned int monotone_steps = 0u;
    unsigned int least_steps = 0u;
    for (unsigned int level = 2u; level <= depth; level += 1u)
    {
        // the step keeps the order when u(L-1) > (gamma - 1) u(L)
        psi_value_zero(&step);
        psi_value_add_term(&step, sim_rational(1ll, 1ll), psi_case->weight[level - 1u]);
        psi_value_add_term(&step, sim_rational(1ll - signed_base, 1ll), psi_case->weight[level]);
        monotone_steps += (psi_value_sign(&step, base) > 0) ? 1u : 0u;
        // and the least gap stays u(L) when (u(L-1) - (gamma - 1) u(L)) / 2 > u(L)
        psi_value_zero(&step);
        psi_value_add_term(&step, sim_rational(1ll, 2ll), psi_case->weight[level - 1u]);
        psi_value_add_term(&step, sim_rational(-(signed_base + 1ll), 2ll), psi_case->weight[level]);
        least_steps += (psi_value_sign(&step, base) > 0) ? 1u : 0u;
    }
    sim_check(tally, monotone_steps == (depth - 1u), "the step keeps psi increasing at every level to depth");
    sim_check(tally, least_steps == (depth - 1u), "the step keeps the least gap at gamma^-beta(L) at every level to depth");

    psi_value_zero(&widest);
    psi_value_add_term(&widest, sim_rational(1ll, 1ll), psi_case->weight[1]);
    unsigned int above_least = 0u;
    unsigned int under_halving = 0u;
    unsigned int under_lemma = 0u;
    unsigned int expanded_equal = 0u;
    // Lemma 2.3's constant: 1/(2 gamma) + (gamma - 2) gamma^n / (gamma^n - 2)
    unsigned long long power = 1ull;
    for (unsigned long long at = 0ull; at < psi_case->dimension; at += 1ull)
    {
        power *= base;
    }
    // gamma^n is at most 1000 here, far inside a word
    const SimRational constant = sim_rational_sum(sim_rational(1ll, 2ll * signed_base),
                                                  sim_rational((signed_base - 2ll) * (long long)power, (long long)power - 2ll));
    for (unsigned int level = 2u; level <= depth; level += 1u)
    {
        psi_value_scale(&widest, sim_rational(1ll, 2ll));
        psi_value_add_term(&widest, sim_rational(-side, 2ll), psi_case->weight[level]);
        psi_value_zero(&unit);
        psi_value_add_term(&unit, sim_rational(1ll, 1ll), psi_case->weight[level]);
        above_least += (psi_value_compare(&widest, &unit, base) > 0) ? 1u : 0u;
        // 2^-(L-1) / gamma, a power of two below 2^61 in the denominator
        psi_value_zero(&bound);
        psi_value_add_term(&bound, sim_rational(1ll, 1ll << (level - 1u)), psi_case->weight[1]);
        under_halving += (psi_value_compare(&widest, &bound, base) <= 0) ? 1u : 0u;
        psi_value_zero(&bound);
        psi_value_add_term(&bound, sim_rational_product(constant, sim_rational(1ll, 1ll << (level - 2u))), 0ull);
        under_lemma += (psi_value_compare(&widest, &bound, base) <= 0) ? 1u : 0u;
        if (level <= PSI_EXHAUSTIVE)
        {
            const SimRational measured = psi_rational_exact(&measured_widest[level], &scale->denominator[level]);
            expanded_equal += sim_rational_equal(psi_value_expand(&widest, base), measured) ? 1u : 0u;
        }
    }
    sim_check(tally, above_least == (depth - 1u), "the widest gap stays above the least at every level to depth");
    sim_check(tally, under_halving == (depth - 1u), "the widest gap stays at or below 2^-(L-1) / gamma: psi is continuous");
    sim_check(tally, under_lemma == (depth - 1u), "the widest gap stays within the paper's Lemma 2.3 bound");
    sim_check(tally, expanded_equal == (PSI_EXHAUSTIVE - 1u), "the symbolic widest gap equals the gap measured on D_2 to D_5");

    unsigned char digit[PSI_LEVELS_MOST];
    for (unsigned int at = 0u; at < depth; at += 1u)
    {
        // a draw below the base is below 256
        digit[at] = (unsigned char)sim_draw_below(PSI_KEY ^ base ^ tilt, at, base);
    }
    psi_pair_symbolic(psi_case, digit, depth, tilt, &value, &plus);
    gap = plus;
    psi_value_add(&gap, &value, sim_rational(-1ll, 1ll));
    psi_value_zero(&unit);
    psi_value_add_term(&unit, sim_rational(1ll, 1ll), psi_case->weight[depth]);
    const int deep_above = psi_value_compare(&gap, &unit, base) >= 0;
    const int deep_below = psi_value_compare(&gap, &widest, base) <= 0;
    sim_check(tally, deep_above && deep_below, "a keyed point at depth has its gap between the least and the widest");

    scriptura_text(line, "     every scale, by the chained step, to level ");
    scriptura_decimal(line, depth, 1u);
    scriptura_text(line, " (beta = ");
    scriptura_decimal(line, psi_case->weight[depth], 1u);
    scriptura_text(line, ", never expanded): the step keeps the order on ");
    scriptura_decimal(line, monotone_steps, 1u);
    scriptura_text(line, " and the least gap on ");
    scriptura_decimal(line, least_steps, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, depth - 1u, 1u);
    scriptura_text(line, " levels\n     the widest gap stays above the least on ");
    scriptura_decimal(line, above_least, 1u);
    scriptura_text(line, ", under 2^-(L-1)/gamma on ");
    scriptura_decimal(line, under_halving, 1u);
    scriptura_text(line, ", within Lemma 2.3 on ");
    scriptura_decimal(line, under_lemma, 1u);
    scriptura_text(line, ", equal to the measured gap on ");
    scriptura_decimal(line, expanded_equal, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, PSI_EXHAUSTIVE - 1u, 1u);
    scriptura_text(line, "\n     the widest gap at level ");
    scriptura_decimal(line, depth, 1u);
    scriptura_text(line, ": ");
    psi_value_print(line, &widest);
    scriptura_text(line, "\n     a keyed point at depth ");
    scriptura_decimal(line, depth, 1u);
    scriptura_text(line, ": psi is ");
    psi_value_print(line, &value);
    scriptura_text(line, "; its gap lies between the least and the widest: ");
    scriptura_text(line, (deep_above && deep_below) ? "yes\n" : "NO\n");
    sim_flush(tally);
}

// a value below 2^128, as two words
typedef struct
{
    unsigned long long high;
    unsigned long long low;
} PsiWide;

typedef struct
{
    PsiWide value;
    unsigned int index;
} PsiImage;

static PsiWide psi_wide_product(unsigned long long left, unsigned long long right)
{
    const unsigned long long left_low = left & 0xFFFFFFFFull;
    const unsigned long long left_high = left >> 32u;
    const unsigned long long right_low = right & 0xFFFFFFFFull;
    const unsigned long long right_high = right >> 32u;
    const unsigned long long low_low = left_low * right_low;
    const unsigned long long low_high = left_low * right_high;
    const unsigned long long high_low = left_high * right_low;
    const unsigned long long middle = (low_low >> 32u) + (low_high & 0xFFFFFFFFull) + (high_low & 0xFFFFFFFFull);
    PsiWide wide;
    wide.low = (middle << 32u) | (low_low & 0xFFFFFFFFull);
    wide.high = (left_high * right_high) + (low_high >> 32u) + (high_low >> 32u) + (middle >> 32u);
    return wide;
}

static PsiWide psi_wide_sum(PsiWide left, PsiWide right)
{
    PsiWide wide;
    wide.low = left.low + right.low;
    wide.high = left.high + right.high + ((wide.low < left.low) ? 1ull : 0ull);
    return wide;
}

// left >= right
static PsiWide psi_wide_difference(PsiWide left, PsiWide right)
{
    PsiWide wide;
    wide.low = left.low - right.low;
    wide.high = left.high - right.high - ((left.low < right.low) ? 1ull : 0ull);
    return wide;
}

static int psi_wide_compare(PsiWide left, PsiWide right)
{
    if (left.high != right.high)
    {
        return (left.high < right.high) ? -1 : 1;
    }
    return (left.low < right.low) ? -1 : ((left.low > right.low) ? 1 : 0);
}

static void psi_wide_exact(PsiWide wide, AnchorExactInteger *result)
{
    AnchorExactInteger high;
    AnchorExactInteger shift;
    AnchorExactInteger half;
    AnchorExactInteger whole;
    AnchorExactInteger low;
    sim_exact_whole(&high, wide.high);
    sim_exact_whole(&shift, 1ull << 32u);
    psi_multiply(&high, &shift, &half);
    psi_multiply(&half, &shift, &whole);
    sim_exact_whole(&low, wide.low);
    psi_add(&whole, &low, result);
}

static int psi_image_order(const void *left, const void *right)
{
    return psi_wide_compare(((const PsiImage *)left)->value, ((const PsiImage *)right)->value);
}

static unsigned long long psi_whole_power(unsigned long long base, unsigned long long power)
{
    unsigned long long result = 1ull;
    for (unsigned long long at = 0ull; at < power; at += 1ull)
    {
        result *= base;
    }
    return result;
}

static SimRational psi_rational_power(long long numerator, unsigned long long base, unsigned long long power)
{
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    sim_exact_signed(&top, numerator);
    sim_rational_took(sim_exact_power(base, power, &bottom));
    return psi_rational_exact(&top, &bottom);
}

// psi on every point of D_level and at 1, as numerators over 2^level . gamma^beta(level), in the form the proofs use
static int psi_grid(const PsiCase *psi_case, const PsiScale *scale, unsigned int level, unsigned long long *grid)
{
    const unsigned long long base = psi_case->base;
    const unsigned long long points = psi_whole_power(base, level);
    AnchorExactInteger *below = (AnchorExactInteger *)malloc((size_t)(points + 1ull) * sizeof(AnchorExactInteger));
    AnchorExactInteger *table = (AnchorExactInteger *)malloc((size_t)(points + 1ull) * sizeof(AnchorExactInteger));
    int held = (below != NULL) && (table != NULL);
    if (held)
    {
        for (unsigned long long index = 0ull; index <= base; index += 1ull)
        {
            sim_exact_whole(&table[index], 2ull * index);
        }
        unsigned long long count = base;
        for (unsigned int step = 2u; step <= level; step += 1u)
        {
            AnchorExactInteger *const swap = below;
            below = table;
            table = swap;
            psi_table_next(psi_case, scale, step, base - 2ull, below, count, table);
            count *= base;
        }
        for (unsigned long long index = 0ull; index <= points; index += 1ull)
        {
            for (unsigned int limb = 2u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
            {
                held = held && (table[index].limb[limb] == 0u);
            }
            grid[index] = ((unsigned long long)table[index].limb[1] << 32u) | (unsigned long long)table[index].limb[0];
        }
    }
    free(below);
    free(table);
    return held;
}

static void psi_point_print(ScripturaLine *line, unsigned int index, unsigned long long side, unsigned int level,
                            unsigned int dimension, unsigned long long base)
{
    unsigned long long rest = index;
    unsigned char digit[PSI_EXHAUSTIVE];
    scriptura_character(line, '(');
    for (unsigned int coordinate = 0u; coordinate < dimension; coordinate += 1u)
    {
        psi_digits(rest % side, base, level, digit);
        rest /= side;
        scriptura_text(line, (coordinate == 0u) ? "0." : ", 0.");
        for (unsigned int at = 0u; at < level; at += 1u)
        {
            scriptura_character(line, (char)('0' + digit[at]));
        }
    }
    scriptura_character(line, ')');
}

// Lemmas 3.4, 3.7 and 3.8: xi(d) = sum_p alpha_p psi(d_p) over every d in D_k^n, sorted, its least neighbouring gap
// exact up to the alpha tails, which are bounded; the gap is weighed against the margin the paper proves, the width of
// the image intervals T_k, and the width the supports U_k of the outer function's bumps need
static void psi_separate(SimTally *tally, const PsiCase *psi_case, const PsiScale *scale, unsigned int level)
{
    ScripturaLine *const line = &tally->line;
    const unsigned long long base = psi_case->base;
    // the dimension is 2 or 3 here
    const unsigned int dimension = (unsigned int)psi_case->dimension;
    const unsigned long long side = psi_whole_power(base, level);
    const unsigned long long count = psi_whole_power(side, dimension);
    const unsigned long long exponent = psi_case->weight[level + 1u] + 3ull;
    const unsigned long long grid_denominator = (1ull << level) * psi_whole_power(base, psi_case->weight[level]);
    // alpha_p truncated to the terms at or above gamma^-exponent, over gamma^exponent; beyond is the first dropped
    unsigned long long alpha[3];
    unsigned long long beyond[3];
    alpha[0] = psi_whole_power(base, exponent);
    beyond[0] = 0ull;
    for (unsigned int coordinate = 1u; coordinate < dimension; coordinate += 1u)
    {
        alpha[coordinate] = 0ull;
        unsigned int term = 1u;
        while ((coordinate * psi_case->weight[term]) <= exponent)
        {
            alpha[coordinate] += psi_whole_power(base, exponent - (coordinate * psi_case->weight[term]));
            term += 1u;
        }
        beyond[coordinate] = coordinate * psi_case->weight[term];
    }
    unsigned long long *grid = (unsigned long long *)malloc((size_t)(side + 1ull) * sizeof(unsigned long long));
    PsiImage *images = (PsiImage *)malloc((size_t)count * sizeof(PsiImage));
    if ((grid == NULL) || (images == NULL) || (psi_grid(psi_case, scale, level, grid) == 0))
    {
        sim_check(tally, 0, "the grid and its images were held");
        free(grid);
        free(images);
        return;
    }
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        unsigned long long rest = index;
        PsiWide sum = {0ull, 0ull};
        for (unsigned int coordinate = 0u; coordinate < dimension; coordinate += 1u)
        {
            sum = psi_wide_sum(sum, psi_wide_product(grid[rest % side], alpha[coordinate]));
            rest /= side;
        }
        images[index].value = sum;
        // count is at most 10^6
        images[index].index = (unsigned int)index;
    }
    qsort(images, (size_t)count, sizeof(PsiImage), psi_image_order);
    PsiWide least = psi_wide_difference(images[1].value, images[0].value);
    unsigned long long least_at = 0ull;
    for (unsigned long long at = 1ull; (at + 1ull) < count; at += 1ull)
    {
        const PsiWide gap = psi_wide_difference(images[at + 1ull].value, images[at].value);
        if (psi_wide_compare(gap, least) < 0)
        {
            least = gap;
            least_at = at;
        }
    }
    // the dropped alpha tails move each image up by less than sum_p 2 gamma^-beyond_p, psi being at most 1
    unsigned long long tail = 0ull;
    for (unsigned int coordinate = 1u; coordinate < dimension; coordinate += 1u)
    {
        const unsigned long long shift = beyond[coordinate] - exponent;
        const unsigned long long power = (shift < 19ull) ? psi_whole_power(base, shift) : 0xFFFFFFFFFFFFFFFFull;
        tail += ((2ull * grid_denominator) + power - 1ull) / power;
    }
    AnchorExactInteger denominator;
    AnchorExactInteger power;
    AnchorExactInteger gap;
    AnchorExactInteger slack;
    AnchorExactInteger low;
    AnchorExactInteger high;
    sim_rational_took(sim_exact_power(base, exponent, &power));
    psi_times_whole(&power, grid_denominator, &denominator);
    psi_wide_exact(least, &gap);
    sim_exact_whole(&slack, tail);
    sim_rational_took(sim_exact_less(&gap, &slack, &low));
    psi_add(&gap, &slack, &high);
    const int injective = (low.sign > 0);
    const SimRational gap_low = psi_rational_exact(&low, &denominator);
    const SimRational gap_high = psi_rational_exact(&high, &denominator);
    const SimRational margin = psi_rational_power(1ll, base, dimension * psi_case->weight[level]);
    const SimRational unit = psi_rational_power(1ll, base, psi_case->weight[level + 1u]);
    SimRational remainder_low = sim_rational(0ll, 1ll);
    for (unsigned int term = level + 1u; term <= (level + 3u); term += 1u)
    {
        remainder_low = sim_rational_sum(remainder_low, psi_rational_power(1ll, base, psi_case->weight[term]));
    }
    const SimRational remainder_high = sim_rational_sum(remainder_low, psi_rational_power(2ll, base, psi_case->weight[level + 4u]));
    SimRational alphas_low = sim_rational(0ll, 1ll);
    SimRational alphas_high = sim_rational(0ll, 1ll);
    for (unsigned int coordinate = 0u; coordinate < dimension; coordinate += 1u)
    {
        AnchorExactInteger whole;
        sim_exact_whole(&whole, alpha[coordinate]);
        alphas_low = sim_rational_sum(alphas_low, psi_rational_exact(&whole, &power));
        if (coordinate != 0u)
        {
            alphas_high = sim_rational_sum(alphas_high, psi_rational_power(2ll, base, beyond[coordinate]));
        }
    }
    alphas_high = sim_rational_sum(alphas_high, alphas_low);
    // the image width (gamma - 2) b_k, b_k = (sum over r > k of gamma^-beta(r)) (sum_p alpha_p)
    // the base is a small integer, far inside a word
    const SimRational tilt = sim_rational((long long)base - 2ll, 1ll);
    const SimRational width_low = sim_rational_product(tilt, sim_rational_product(remainder_low, alphas_low));
    const SimRational width_high = sim_rational_product(tilt, sim_rational_product(remainder_high, alphas_high));
    const SimRational pad = sim_rational_product(sim_rational(2ll, 1ll), unit);
    const SimRational support_low = sim_rational_sum(width_low, pad);
    const SimRational support_high = sim_rational_sum(width_high, pad);
    const int margin_held = sim_rational_sign(sim_rational_difference(gap_low, margin)) >= 0;
    const int images_apart = sim_rational_sign(sim_rational_difference(gap_low, width_high)) > 0;
    const int supports_apart = sim_rational_sign(sim_rational_difference(gap_low, support_high)) >= 0;
    const int supports_meet = sim_rational_sign(sim_rational_difference(gap_high, support_low)) < 0;
    // a ramp of gamma^-beta(k+1) / gamma^2 instead of gamma^-beta(k+1); the base is far inside a word
    const SimRational narrow = sim_rational_sum(width_high, sim_rational_product(pad, sim_rational(1ll, (long long)(base * base))));
    const int narrow_apart = sim_rational_sign(sim_rational_difference(gap_low, narrow)) >= 0;
    const int margin_below = sim_rational_sign(sim_rational_difference(gap_high, margin)) < 0;
    sim_check(tally, injective, "xi is one to one on D_k^n, the alpha tails included");
    sim_check(tally, (level >= 2u) ? margin_held : margin_below,
              "the least gap meets gamma^-n beta(k) from k = 2 and falls below it at k = 1 (Lemma 3.4)");
    sim_check(tally, images_apart, "the image intervals T_k are pairwise disjoint (Lemma 3.7)");
    sim_check(tally, (level >= 2u) ? supports_apart : supports_meet,
              "the supports U_k are disjoint from k = 2 and overlap at k = 1 (Lemma 3.8)");
    sim_check(tally, narrow_apart, "with a ramp narrower by gamma the supports are disjoint at every k");
    // everything in units of gamma^-beta(k+1)
    SimRational scale_up;
    sim_rational_took(sim_exact_power(base, psi_case->weight[level + 1u], &scale_up.numerator));
    sim_exact_whole(&scale_up.denominator, 1ull);
    scriptura_text(line, "     k = ");
    scriptura_decimal(line, level, 1u);
    scriptura_text(line, ", ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " points: least gap ");
    sim_rational_print(line, sim_rational_product(gap_low, scale_up));
    scriptura_text(line, " units of g^-beta(k+1); Lemma 3.4's margin ");
    sim_rational_print(line, sim_rational_product(margin, scale_up));
    scriptura_text(line, ", the image width ");
    sim_rational_print(line, sim_rational_product(width_high, scale_up));
    scriptura_text(line, ", the supports need ");
    sim_rational_print(line, sim_rational_product(support_high, scale_up));
    scriptura_text(line, "\n       tightest between ");
    psi_point_print(line, images[least_at].index, side, level, dimension, base);
    scriptura_text(line, " and ");
    psi_point_print(line, images[least_at + 1ull].index, side, level, dimension, base);
    scriptura_text(line, margin_held ? "; Lemma 3.4 holds" : "; Lemma 3.4 FAILS");
    scriptura_text(line, supports_apart ? ", the supports are disjoint"
                                        : (supports_meet ? ", the supports OVERLAP" : ", the supports are undecided"));
    scriptura_text(line, narrow_apart ? ", disjoint with the narrow ramp\n" : ", overlapping even with the narrow ramp\n");
    sim_flush(tally);

    // (3.11): the alphas cut at r <= k, sum_(r<=k) gamma^-(p-1) beta(r), exact over gamma^((n-1) beta(k))
    const unsigned long long cut = (dimension - 1u) * psi_case->weight[level];
    alpha[0] = psi_whole_power(base, cut);
    for (unsigned int coordinate = 1u; coordinate < dimension; coordinate += 1u)
    {
        alpha[coordinate] = 0ull;
        for (unsigned int term = 1u; term <= level; term += 1u)
        {
            alpha[coordinate] += psi_whole_power(base, cut - (coordinate * psi_case->weight[term]));
        }
    }
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        unsigned long long rest = index;
        PsiWide sum = {0ull, 0ull};
        for (unsigned int coordinate = 0u; coordinate < dimension; coordinate += 1u)
        {
            sum = psi_wide_sum(sum, psi_wide_product(grid[rest % side], alpha[coordinate]));
            rest /= side;
        }
        images[index].value = sum;
    }
    qsort(images, (size_t)count, sizeof(PsiImage), psi_image_order);
    PsiWide truncated = psi_wide_difference(images[1].value, images[0].value);
    for (unsigned long long at = 1ull; (at + 1ull) < count; at += 1ull)
    {
        const PsiWide next = psi_wide_difference(images[at + 1ull].value, images[at].value);
        truncated = (psi_wide_compare(next, truncated) < 0) ? next : truncated;
    }
    AnchorExactInteger truncated_gap;
    AnchorExactInteger cut_power;
    AnchorExactInteger cut_denominator;
    psi_wide_exact(truncated, &truncated_gap);
    sim_rational_took(sim_exact_power(base, cut, &cut_power));
    psi_times_whole(&cut_power, grid_denominator, &cut_denominator);
    const SimRational truncated_least = psi_rational_exact(&truncated_gap, &cut_denominator);
    const int truncated_held = sim_rational_sign(sim_rational_difference(truncated_least, margin)) >= 0;
    sim_check(tally, truncated_held, "with the alphas cut at r <= k the least gap is at least gamma^-n beta(k) (3.11)");
    scriptura_text(line, "       the alphas cut at r <= k (3.11): least gap ");
    sim_rational_print(line, sim_rational_product(truncated_least, scale_up));
    scriptura_text(line, " units, at least the margin: ");
    scriptura_text(line, truncated_held ? "yes\n" : "NO\n");
    sim_flush(tally);
    free(grid);
    free(images);
}

// result = left . right; result is distinct from both
static void psi_value_product(const PsiValue *left, const PsiValue *right, PsiValue *result)
{
    psi_value_zero(result);
    for (unsigned int first = 0u; first < left->count; first += 1u)
    {
        for (unsigned int second = 0u; second < right->count; second += 1u)
        {
            psi_value_add_term(result, sim_rational_product(left->coefficient[first], right->coefficient[second]),
                               left->exponent[first] + right->exponent[second]);
        }
    }
}

// an upper bound on sum over r >= first of gamma^-(factor beta(r)): terms to first + 1, then twice the next, since
// the exponents grow by at least one a term and the rest is under a geometric series of ratio 1/gamma
static void psi_series_upper(PsiValue *value, const PsiCase *psi_case, unsigned long long factor, unsigned int first)
{
    psi_value_add_term(value, sim_rational(1ll, 1ll), factor * psi_case->weight[first]);
    psi_value_add_term(value, sim_rational(1ll, 1ll), factor * psi_case->weight[first + 1u]);
    psi_value_add_term(value, sim_rational(2ll, 1ll), factor * psi_case->weight[first + 2u]);
}

// The corrected chain at every scale. (3.11) gives |mu_k| >= gamma^-n beta(k) with the alphas cut at r <= k; the cut
// tails move mu by at most sum_(p>=2) eps_(k,p), psi lying in [0, 1]. The images T_k have width (gamma - 2) b_k and
// the ramps take rho = gamma^-(beta(k+1)+2) on each side, so the supports U_k are disjoint when
// gamma^-n beta(k) - sum_(p>=2) eps_(k,p) - (gamma - 2) eps_(k,2) sum_p alpha_p - 2 rho > 0, every sum an upper bound
static void psi_separate_all_scales(SimTally *tally, const PsiCase *psi_case)
{
    ScripturaLine *const line = &tally->line;
    static PsiValue tails;
    static PsiValue alphas;
    static PsiValue remainder;
    static PsiValue width;
    static PsiValue room;
    const unsigned long long base = psi_case->base;
    const unsigned int last = psi_case->depth - 3u;
    psi_value_zero(&alphas);
    psi_value_add_term(&alphas, sim_rational(1ll, 1ll), 0ull);
    for (unsigned long long coordinate = 1ull; coordinate < psi_case->dimension; coordinate += 1ull)
    {
        psi_series_upper(&alphas, psi_case, coordinate, 1u);
    }
    unsigned int narrow_held = 0u;
    unsigned int wide_held = 0u;
    for (unsigned int level = 1u; level <= last; level += 1u)
    {
        psi_value_zero(&tails);
        for (unsigned long long coordinate = 1ull; coordinate < psi_case->dimension; coordinate += 1ull)
        {
            psi_series_upper(&tails, psi_case, coordinate, level + 1u);
        }
        psi_value_zero(&remainder);
        psi_series_upper(&remainder, psi_case, 1ull, level + 1u);
        psi_value_product(&remainder, &alphas, &width);
        psi_value_zero(&room);
        psi_value_add_term(&room, sim_rational(1ll, 1ll), psi_case->dimension * psi_case->weight[level]);
        psi_value_add(&room, &tails, sim_rational(-1ll, 1ll));
        // the base is a small integer, far inside a word
        psi_value_add(&room, &width, sim_rational(2ll - (long long)base, 1ll));
        psi_value_add_term(&room, sim_rational(-2ll, 1ll), psi_case->weight[level + 1u] + 2ull);
        narrow_held += (psi_value_sign(&room, base) > 0) ? 1u : 0u;
        // the paper's ramp, gamma^-beta(k+1)
        psi_value_add_term(&room, sim_rational(2ll, 1ll), psi_case->weight[level + 1u] + 2ull);
        psi_value_add_term(&room, sim_rational(-2ll, 1ll), psi_case->weight[level + 1u]);
        wide_held += (psi_value_sign(&room, base) > 0) ? 1u : 0u;
    }
    sim_check(tally, narrow_held == last, "the corrected bound keeps the supports apart with the narrow ramp at every k to depth");
    sim_check(tally, wide_held == 0u, "the corrected bound does not cover the paper's ramp at any k");
    scriptura_text(line, "     every scale, k = 1 to ");
    scriptura_decimal(line, last, 1u);
    scriptura_text(line, ": |mu_k| >= g^-n beta(k) - sum eps_(k,p) keeps the supports apart with ramp g^-(beta(k+1)+2) on ");
    scriptura_decimal(line, narrow_held, 1u);
    scriptura_text(line, ", with the paper's ramp g^-beta(k+1) on ");
    scriptura_decimal(line, wide_held, 1u);
    scriptura_character(line, '\n');
    sim_flush(tally);
}

// the m + 1 shifts: x + q a sits in a level-k gap for q where x, in units of s = gamma^-k / (gamma - 1) modulo
// (gamma - 1) s, lies in ((gamma - 2 - q) s, (gamma - 1 - q) s); every half unit is tried
static unsigned long long psi_gaps_shared(unsigned long long base, unsigned long long shifts)
{
    const long long period = 2ll * ((long long)base - 1ll);
    unsigned long long most = 0ull;
    for (long long place = 0ll; place < period; place += 1ll)
    {
        unsigned long long inside = 0ull;
        for (long long shift = 0ll; shift < (long long)shifts; shift += 1ll)
        {
            const long long start = ((((2ll * ((long long)base - 2ll - shift)) % period) + period) % period);
            const long long offset = (((place - start) % period) + period) % period;
            inside += ((offset > 0ll) && (offset < 2ll)) ? 1ull : 0ull;
        }
        most = (inside > most) ? inside : most;
    }
    return most;
}

static void psi_cover(SimTally *tally, const PsiCase *psi_case)
{
    ScripturaLine *const line = &tally->line;
    const unsigned long long shifts = (2ull * psi_case->dimension) + 1ull;
    const unsigned long long allowed = psi_gaps_shared(psi_case->base, shifts);
    const unsigned long long crowded = psi_gaps_shared(psi_case->base, psi_case->base);
    sim_check(tally, allowed == 1ull, "with m = 2n shifts no point sits in two gaps of one coordinate");
    sim_check(tally, crowded == 2ull, "with m = gamma - 1 two shifts share a gap: gamma >= m + 2 is needed");
    scriptura_text(line, "     the shifts: with m + 1 = ");
    scriptura_decimal(line, shifts, 1u);
    scriptura_text(line, " a point sits in at most ");
    scriptura_decimal(line, allowed, 1u);
    scriptura_text(line, " gap per coordinate, so at least m - n + 1 = ");
    scriptura_decimal(line, shifts - psi_case->dimension, 1u);
    scriptura_text(line, " of the shifts land it in a cube; with m + 1 = gamma, ");
    scriptura_decimal(line, crowded, 1u);
    scriptura_text(line, " shifts share a gap\n");
    sim_flush(tally);
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    ScripturaLine *const line = &tally.line;
    scriptura_text(line, "  Kolmogorov's inner function psi, exactly (Braun and Griebel 2009, section 2)\n");
    scriptura_text(line, "  grids in exact integers; depth in sparse sums of c g^-beta(L), the exponent an integer never expanded\n");
    sim_flush(&tally);

    PsiCase planar;
    PsiCase spatial;
    const int opened = psi_case_open(&planar, 2ull, 10ull, 60u) && psi_case_open(&spatial, 3ull, 10ull, 38u);
    sim_check(&tally, opened, "the weights beta(L) fit the word to the chosen depths");
    if (opened == 0)
    {
        return sim_close(&tally, "ka psi");
    }
    psi_sprecher(&tally, &planar);

    static PsiScale scale;
    static AnchorExactInteger measured_widest[PSI_EXHAUSTIVE + 1u];
    const PsiCase *const cases[2] = {&planar, &spatial};
    for (unsigned int shaped = 0u; shaped < 2u; shaped += 1u)
    {
        const PsiCase *const psi_case = cases[shaped];
        psi_scale_open(psi_case, &scale);
        scriptura_text(line, "\n  2. Koppen's psi, n = ");
        scriptura_decimal(line, psi_case->dimension, 1u);
        scriptura_text(line, ", gamma = ");
        scriptura_decimal(line, psi_case->base, 1u);
        scriptura_text(line, " (Theorem 2.1 asks gamma >= 2n + 2)\n");
        sim_flush(&tally);
        for (unsigned long long tilt = psi_case->base - 2ull; tilt <= (psi_case->base - 1ull); tilt += 1ull)
        {
            psi_exhaustive(&tally, psi_case, &scale, tilt, measured_widest);
            psi_all_scales(&tally, psi_case, &scale, tilt, measured_widest);
        }
        scriptura_text(line, "\n  3. Separation, n = ");
        scriptura_decimal(line, psi_case->dimension, 1u);
        scriptura_text(line, ": xi = sum_p alpha_p psi(x_p) on every point of D_k^n (Lemmas 3.4, 3.7, 3.8)\n");
        sim_flush(&tally);
        const unsigned int levels = (psi_case->dimension == 2ull) ? 3u : 2u;
        for (unsigned int level = 1u; level <= levels; level += 1u)
        {
            psi_separate(&tally, psi_case, &scale, level);
        }
        psi_separate_all_scales(&tally, psi_case);
        psi_cover(&tally, psi_case);
    }
    sim_check(&tally, s_sim_rational_wide == 0, "every value fit the exact integer and every sign was decided");
    return sim_close(&tally, "ka psi");
}
