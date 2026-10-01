// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ka_psi_separate.cu: wide arithmetic, the grid and separation
#include "ka_psi_internal.h"

void psi_all_scales(SimResults *results, const PsiCase *psi_case, const PsiScale *scale, unsigned long long tilt,
                    const AnchorExactInteger *measured_widest)
{
    ScripturaLine *const line = &results->line;
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
    sim_check(results, monotone_steps == (depth - 1u), "the step keeps psi increasing at every level to depth");
    sim_check(results, least_steps == (depth - 1u),
              "the step keeps the least gap at gamma^-beta(L) at every level to depth");

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
    const SimRational constant =
        sim_rational_sum(sim_rational(1ll, 2ll * signed_base),
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
    sim_check(results, above_least == (depth - 1u), "the widest gap stays above the least at every level to depth");
    sim_check(results, under_halving == (depth - 1u),
              "the widest gap stays at or below 2^-(L-1) / gamma: psi is continuous");
    sim_check(results, under_lemma == (depth - 1u), "the widest gap stays within the paper's Lemma 2.3 bound");
    sim_check(results, expanded_equal == (PSI_EXHAUSTIVE - 1u),
              "the symbolic widest gap equals the gap measured on D_2 to D_5");

    unsigned char digit[PSI_LEVELS_MAX];
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
    sim_check(results, deep_above && deep_below, "a keyed point at depth has its gap between the least and the widest");

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
    sim_flush(results);
}

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
    AnchorExactInteger integer_part;
    AnchorExactInteger low;
    sim_exact_unsigned(&high, wide.high);
    sim_exact_unsigned(&shift, 1ull << 32u);
    psi_multiply(&high, &shift, &half);
    psi_multiply(&half, &shift, &integer_part);
    sim_exact_unsigned(&low, wide.low);
    psi_add(&integer_part, &low, result);
}

static int psi_image_order(const void *left, const void *right)
{
    return psi_wide_compare(((const PsiImage *)left)->value, ((const PsiImage *)right)->value);
}

static unsigned long long psi_integer_power(unsigned long long base, unsigned long long power)
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
    sim_rational_status_check(sim_exact_power(base, power, &bottom));
    return psi_rational_exact(&top, &bottom);
}

// psi on every point of D_level and at 1, as numerators over 2^level . gamma^beta(level), in the form the proofs use
static int psi_grid(const PsiCase *psi_case, const PsiScale *scale, unsigned int level, unsigned long long *grid)
{
    const unsigned long long base = psi_case->base;
    const unsigned long long points = psi_integer_power(base, level);
    AnchorExactInteger *below = (AnchorExactInteger *)malloc((size_t)(points + 1ull) * sizeof(AnchorExactInteger));
    AnchorExactInteger *table = (AnchorExactInteger *)malloc((size_t)(points + 1ull) * sizeof(AnchorExactInteger));
    int ok = (below != NULL) && (table != NULL);
    if (ok)
    {
        for (unsigned long long index = 0ull; index <= base; index += 1ull)
        {
            sim_exact_unsigned(&table[index], 2ull * index);
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
                ok = ok && (table[index].limb[limb] == 0u);
            }
            grid[index] = ((unsigned long long)table[index].limb[1] << 32u) | (unsigned long long)table[index].limb[0];
        }
    }
    free(below);
    free(table);
    return ok;
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

// Lemmas 3.4, 3.7 and 3.8: xi(d) = sum_p alpha_p psi(d_p) over every d in D_k^n, sorted, its least neighboring gap
// exact up to the alpha tails, which are bounded; the gap is weighed against the margin the paper proves, the width of
// the image intervals T_k, and the width the supports U_k of the outer function's bumps need
void psi_separate(SimResults *results, const PsiCase *psi_case, const PsiScale *scale, unsigned int level)
{
    ScripturaLine *const line = &results->line;
    const unsigned long long base = psi_case->base;
    // the dimension is 2 or 3 here
    const unsigned int dimension = (unsigned int)psi_case->dimension;
    const unsigned long long side = psi_integer_power(base, level);
    const unsigned long long count = psi_integer_power(side, dimension);
    const unsigned long long exponent = psi_case->weight[level + 1u] + 3ull;
    const unsigned long long grid_denominator = (1ull << level) * psi_integer_power(base, psi_case->weight[level]);
    // alpha_p truncated to the terms at or above gamma^-exponent, over gamma^exponent; beyond is the first dropped
    unsigned long long alpha[3];
    unsigned long long beyond[3];
    alpha[0] = psi_integer_power(base, exponent);
    beyond[0] = 0ull;
    for (unsigned int coordinate = 1u; coordinate < dimension; coordinate += 1u)
    {
        alpha[coordinate] = 0ull;
        unsigned int term = 1u;
        while ((coordinate * psi_case->weight[term]) <= exponent)
        {
            alpha[coordinate] += psi_integer_power(base, exponent - (coordinate * psi_case->weight[term]));
            term += 1u;
        }
        beyond[coordinate] = coordinate * psi_case->weight[term];
    }
    unsigned long long *grid = (unsigned long long *)malloc((size_t)(side + 1ull) * sizeof(unsigned long long));
    PsiImage *images = (PsiImage *)malloc((size_t)count * sizeof(PsiImage));
    if ((grid == NULL) || (images == NULL) || (psi_grid(psi_case, scale, level, grid) == 0))
    {
        sim_check(results, 0, "the grid and its images were held");
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
        const unsigned long long power = (shift < 19ull) ? psi_integer_power(base, shift) : 0xFFFFFFFFFFFFFFFFull;
        tail += ((2ull * grid_denominator) + power - 1ull) / power;
    }
    AnchorExactInteger denominator;
    AnchorExactInteger power;
    AnchorExactInteger gap;
    AnchorExactInteger slack;
    AnchorExactInteger low;
    AnchorExactInteger high;
    sim_rational_status_check(sim_exact_power(base, exponent, &power));
    psi_times_integer(&power, grid_denominator, &denominator);
    psi_wide_exact(least, &gap);
    sim_exact_unsigned(&slack, tail);
    sim_rational_status_check(sim_exact_less(&gap, &slack, &low));
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
    const SimRational remainder_high =
        sim_rational_sum(remainder_low, psi_rational_power(2ll, base, psi_case->weight[level + 4u]));
    SimRational alphas_low = sim_rational(0ll, 1ll);
    SimRational alphas_high = sim_rational(0ll, 1ll);
    for (unsigned int coordinate = 0u; coordinate < dimension; coordinate += 1u)
    {
        AnchorExactInteger integer_part;
        sim_exact_unsigned(&integer_part, alpha[coordinate]);
        alphas_low = sim_rational_sum(alphas_low, psi_rational_exact(&integer_part, &power));
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
    const int margin_ok = sim_rational_sign(sim_rational_difference(gap_low, margin)) >= 0;
    const int images_apart = sim_rational_sign(sim_rational_difference(gap_low, width_high)) > 0;
    const int supports_apart = sim_rational_sign(sim_rational_difference(gap_low, support_high)) >= 0;
    const int supports_meet = sim_rational_sign(sim_rational_difference(gap_high, support_low)) < 0;
    // a ramp of gamma^-beta(k+1) / gamma^2 instead of gamma^-beta(k+1); the base is far inside a word
    const SimRational narrow =
        sim_rational_sum(width_high, sim_rational_product(pad, sim_rational(1ll, (long long)(base * base))));
    const int narrow_apart = sim_rational_sign(sim_rational_difference(gap_low, narrow)) >= 0;
    const int margin_below = sim_rational_sign(sim_rational_difference(gap_high, margin)) < 0;
    sim_check(results, injective, "xi is one to one on D_k^n, the alpha tails included");
    sim_check(results, (level >= 2u) ? margin_ok : margin_below,
              "the least gap meets gamma^-n beta(k) from k = 2 and falls below it at k = 1 (Lemma 3.4)");
    sim_check(results, images_apart, "the image intervals T_k are pairwise disjoint (Lemma 3.7)");
    sim_check(results, (level >= 2u) ? supports_apart : supports_meet,
              "the supports U_k are disjoint from k = 2 and overlap at k = 1 (Lemma 3.8)");
    sim_check(results, narrow_apart, "with a ramp narrower by gamma the supports are disjoint at every k");
    // everything in units of gamma^-beta(k+1)
    SimRational scale_up;
    sim_rational_status_check(sim_exact_power(base, psi_case->weight[level + 1u], &scale_up.numerator));
    sim_exact_unsigned(&scale_up.denominator, 1ull);
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
    scriptura_text(line, margin_ok ? "; Lemma 3.4 holds" : "; Lemma 3.4 FAILS");
    scriptura_text(line, supports_apart ? ", the supports are disjoint"
                                        : (supports_meet ? ", the supports OVERLAP" : ", the supports are undecided"));
    scriptura_text(line,
                   narrow_apart ? ", disjoint with the narrow ramp\n" : ", overlapping even with the narrow ramp\n");
    sim_flush(results);

    // (3.11): the alphas cut at r <= k, sum_(r<=k) gamma^-(p-1) beta(r), exact over gamma^((n-1) beta(k))
    const unsigned long long top_exponent = (dimension - 1u) * psi_case->weight[level];
    alpha[0] = psi_integer_power(base, top_exponent);
    for (unsigned int coordinate = 1u; coordinate < dimension; coordinate += 1u)
    {
        alpha[coordinate] = 0ull;
        for (unsigned int term = 1u; term <= level; term += 1u)
        {
            alpha[coordinate] += psi_integer_power(base, top_exponent - (coordinate * psi_case->weight[term]));
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
    AnchorExactInteger base_power;
    AnchorExactInteger power_denominator;
    psi_wide_exact(truncated, &truncated_gap);
    sim_rational_status_check(sim_exact_power(base, top_exponent, &base_power));
    psi_times_integer(&base_power, grid_denominator, &power_denominator);
    const SimRational truncated_least = psi_rational_exact(&truncated_gap, &power_denominator);
    const int truncated_ok = sim_rational_sign(sim_rational_difference(truncated_least, margin)) >= 0;
    sim_check(results, truncated_ok, "with the alphas cut at r <= k the least gap is at least gamma^-n beta(k) (3.11)");
    scriptura_text(line, "       the alphas cut at r <= k (3.11): least gap ");
    sim_rational_print(line, sim_rational_product(truncated_least, scale_up));
    scriptura_text(line, " units, at least the margin: ");
    scriptura_text(line, truncated_ok ? "yes\n" : "NO\n");
    sim_flush(results);
    free(grid);
    free(images);
}
