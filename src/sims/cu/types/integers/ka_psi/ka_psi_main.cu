// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ka_psi_main.cu: products, the cover and main
#include "ka_psi_internal.h"

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
// the ramps take rho = gamma^-(beta(k+1)+2) on each side. The supports U_k are disjoint when
// gamma^-n beta(k) - sum_(p>=2) eps_(k,p) - (gamma - 2) eps_(k,2) sum_p alpha_p - 2 rho > 0, every sum an upper bound
static void psi_separate_all_scales(SimResults *results, const PsiCase *psi_case)
{
    ScripturaLine *const line = &results->line;
    static PsiValue tails;
    static PsiValue alphas;
    static PsiValue remainder;
    static PsiValue width;
    static PsiValue slack;
    const unsigned long long base = psi_case->base;
    const unsigned int last = psi_case->depth - 3u;
    psi_value_zero(&alphas);
    psi_value_add_term(&alphas, sim_rational(1ll, 1ll), 0ull);
    for (unsigned long long coordinate = 1ull; coordinate < psi_case->dimension; coordinate += 1ull)
    {
        psi_series_upper(&alphas, psi_case, coordinate, 1u);
    }
    unsigned int narrow_ok = 0u;
    unsigned int wide_ok = 0u;
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
        psi_value_zero(&slack);
        psi_value_add_term(&slack, sim_rational(1ll, 1ll), psi_case->dimension * psi_case->weight[level]);
        psi_value_add(&slack, &tails, sim_rational(-1ll, 1ll));
        // the base is a small integer, far inside a word
        psi_value_add(&slack, &width, sim_rational(2ll - (long long)base, 1ll));
        psi_value_add_term(&slack, sim_rational(-2ll, 1ll), psi_case->weight[level + 1u] + 2ull);
        narrow_ok += (psi_value_sign(&slack, base) > 0) ? 1u : 0u;
        // the paper's ramp, gamma^-beta(k+1)
        psi_value_add_term(&slack, sim_rational(2ll, 1ll), psi_case->weight[level + 1u] + 2ull);
        psi_value_add_term(&slack, sim_rational(-2ll, 1ll), psi_case->weight[level + 1u]);
        wide_ok += (psi_value_sign(&slack, base) > 0) ? 1u : 0u;
    }
    sim_check(results, narrow_ok == last,
              "the corrected bound keeps the supports apart with the narrow ramp at every k to depth");
    sim_check(results, wide_ok == 0u, "the corrected bound does not cover the paper's ramp at any k");
    scriptura_text(line, "     every scale, k = 1 to ");
    scriptura_decimal(line, last, 1u);
    scriptura_text(line,
                   ": |mu_k| >= g^-n beta(k) - sum eps_(k,p) keeps the supports apart with ramp g^-(beta(k+1)+2) on ");
    scriptura_decimal(line, narrow_ok, 1u);
    scriptura_text(line, ", with the paper's ramp g^-beta(k+1) on ");
    scriptura_decimal(line, wide_ok, 1u);
    scriptura_character(line, '\n');
    sim_flush(results);
}

// the m + 1 shifts: x + q a sits in a level-k gap for q where x, in units of s = gamma^-k / (gamma - 1) modulo
// (gamma - 1) s, lies in ((gamma - 2 - q) s, (gamma - 1 - q) s); every half unit is tried
static unsigned long long psi_gaps_shared(unsigned long long base, unsigned long long shifts)
{
    const long long period = 2ll * ((long long)base - 1ll);
    unsigned long long maximum = 0ull;
    for (long long place = 0ll; place < period; place += 1ll)
    {
        unsigned long long inside = 0ull;
        for (long long shift = 0ll; shift < (long long)shifts; shift += 1ll)
        {
            const long long start = ((((2ll * ((long long)base - 2ll - shift)) % period) + period) % period);
            const long long offset = (((place - start) % period) + period) % period;
            inside += ((offset > 0ll) && (offset < 2ll)) ? 1ull : 0ull;
        }
        maximum = (inside > maximum) ? inside : maximum;
    }
    return maximum;
}

static void psi_cover(SimResults *results, const PsiCase *psi_case)
{
    ScripturaLine *const line = &results->line;
    const unsigned long long shifts = (2ull * psi_case->dimension) + 1ull;
    const unsigned long long allowed = psi_gaps_shared(psi_case->base, shifts);
    const unsigned long long crowded = psi_gaps_shared(psi_case->base, psi_case->base);
    sim_check(results, allowed == 1ull, "with m = 2n shifts no point sits in two gaps of one coordinate");
    sim_check(results, crowded == 2ull, "with m = gamma - 1 two shifts share a gap: gamma >= m + 2 is needed");
    scriptura_text(line, "     the shifts: with m + 1 = ");
    scriptura_decimal(line, shifts, 1u);
    scriptura_text(line, " a point sits in at most ");
    scriptura_decimal(line, allowed, 1u);
    scriptura_text(line, " gap per coordinate, so at least m - n + 1 = ");
    scriptura_decimal(line, shifts - psi_case->dimension, 1u);
    scriptura_text(line, " of the shifts land it in a cube; with m + 1 = gamma, ");
    scriptura_decimal(line, crowded, 1u);
    scriptura_text(line, " shifts share a gap\n");
    sim_flush(results);
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    ScripturaLine *const line = &results.line;
    scriptura_text(line, "  Kolmogorov's inner function psi, exactly (Braun and Griebel 2009, section 2)\n");
    scriptura_text(
        line,
        "  grids in exact integers; depth in sparse sums of c g^-beta(L), the exponent an integer never expanded\n");
    sim_flush(&results);

    PsiCase planar;
    PsiCase spatial;
    const int opened = psi_case_open(&planar, 2ull, 10ull, 60u) && psi_case_open(&spatial, 3ull, 10ull, 38u);
    sim_check(&results, opened, "the weights beta(L) fit the word to the chosen depths");
    if (opened == 0)
    {
        return sim_close(&results, "ka psi");
    }
    psi_sprecher(&results, &planar);

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
        sim_flush(&results);
        for (unsigned long long tilt = psi_case->base - 2ull; tilt <= (psi_case->base - 1ull); tilt += 1ull)
        {
            psi_exhaustive(&results, psi_case, &scale, tilt, measured_widest);
            psi_all_scales(&results, psi_case, &scale, tilt, measured_widest);
        }
        scriptura_text(line, "\n  3. Separation, n = ");
        scriptura_decimal(line, psi_case->dimension, 1u);
        scriptura_text(line, ": xi = sum_p alpha_p psi(x_p) on every point of D_k^n (Lemmas 3.4, 3.7, 3.8)\n");
        sim_flush(&results);
        const unsigned int levels = (psi_case->dimension == 2ull) ? 3u : 2u;
        for (unsigned int level = 1u; level <= levels; level += 1u)
        {
            psi_separate(&results, psi_case, &scale, level);
        }
        psi_separate_all_scales(&results, psi_case);
        psi_cover(&results, psi_case);
    }
    sim_check(&results, s_sim_rational_wide == 0, "every value fit the exact integer and every sign was decided");
    return sim_close(&results, "ka psi");
}
