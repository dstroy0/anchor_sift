// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// join_series.cu: the pieces of the join as Taylor series about rational centers, each coefficient exact, each
// transcendental value an atom held apart
#include "run_cfg.h"

#include "report.h"

#include "blend.h"
#include "ode_series.h"

// The pieces: e^(-1/s) and e^(-1/(1-s)) for the blend weight, the annulus bump e^(4 - 1/(s(1-s))), x^h, and Kummer's
// w = U(1 + h, 2, z), whose two atoms carry the heat exterior H(Z) = Z^(-1-h) w(1/Z). Each comes from its equation's
// recursion, and each is checked against that equation: the residual of the series it gives has every held
// coefficient exactly 0. The blend weight psi = e^(-1/s) / (e^(-1/s) + e^(-1/(1-s))) is 1 / (1 + r g) with
// r = e^(-1/(1-c)) / e^(-1/c) = e^(1/c - 1/(1-c)) and g the ratio of the two unit series; with rho = 1 / (1 + r) it
// is rho alpha / (1 + rho (alpha - 1 + r (beta - 1))), alpha and beta the unit series, held as forms in e and rho, by
// blend.h. Its check: psi times (alpha + r beta) is alpha in every held coefficient once each is reduced by
// rho (1 + r) = 1. e is held at a rational power: the product of the two decay series is checked to be one series at
// the sum of the two powers, e^(-1/c) e^(-1/(1-c)) = e^(-1/(c(1-c))).
// The request: join_series <cfg>.
//     bash examples/navier_stokes/run.sh join_series examples/navier_stokes/cfg/join_series.cfg


typedef struct
{
    SimRational h;
    SimRational blend_center;
    SimRational power_center;
    SimRational kummer_center;
    unsigned long long terms;
    unsigned long long places;
} JoinRequest;

// 1 where every coefficient the series holds is 0
static int join_zero(const TaylorSeries &series)
{
    for (const AtomForm &form : series.coefficient)
    {
        if (!atom_form_zero(form))
        {
            return 0;
        }
    }
    return 1;
}

static void join_report(SimResults *results, int passed, const char *what)
{
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, what);
    scriptura_text(&results->line, passed ? ": every held coefficient of its residual is 0\n"
                                          : ": a held coefficient of its residual is not 0\n");
    sim_check(results, passed, what);
}

static void join_first_terms(ScripturaLine *line, const char *name, const TaylorSeries &series, unsigned int shown,
                             const AtomBook *book, unsigned int places)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " about ");
    report_value(line, series.center, places);
    scriptura_text(line, ":\n");
    for (unsigned int index = 0u; (index < shown) && (index < series.coefficient.size()); index += 1u)
    {
        scriptura_text(line, "    t^");
        scriptura_decimal(line, index, 1u);
        scriptura_text(line, ": ");
        atom_form_print(line, series.coefficient[index], book->names, places);
        scriptura_character(line, '\n');
    }
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    static RunCfg cfg;
    JoinRequest request;
    if ((count != 2) || (run_cfg_open(arguments[1], &cfg, &results.line) == 0) ||
        !run_cfg_rational(&cfg, "anisotropy", &request.h) ||
        !run_cfg_rational(&cfg, "centers.blend", &request.blend_center) ||
        !run_cfg_rational(&cfg, "centers.power", &request.power_center) ||
        !run_cfg_rational(&cfg, "centers.kummer", &request.kummer_center) ||
        !run_cfg_count(&cfg, "terms", &request.terms) || (request.terms < 3ull) ||
        !run_cfg_count(&cfg, "places", &request.places))
    {
        if (count == 2)
        {
            run_cfg_missing(&results.line, "anisotropy, centers.blend, centers.power and centers.kummer as decimal "
                                           "strings, terms at least 3 and places as whole numbers");
        }
        sim_flush(&results);
        fprintf(stderr, "join_series <cfg>\n");
        return 2;
    }
    const unsigned int terms = (unsigned int)request.terms;
    const unsigned int places = (unsigned int)request.places;
    const SimRational one = sim_rational(1ll, 1ll);
    std::vector<SimRational> square(3u, sim_rational(0ll, 1ll));
    square[2] = one;
    const std::vector<SimRational> unit(1u, one);
    std::vector<SimRational> reflected_square(3u, one);
    reflected_square[1] = sim_rational(-2ll, 1ll);
    const std::vector<SimRational> negative_unit(1u, sim_rational(-1ll, 1ll));
    std::vector<SimRational> bump_p(5u, sim_rational(0ll, 1ll));
    bump_p[2] = one;
    bump_p[3] = sim_rational(-2ll, 1ll);
    bump_p[4] = one;
    std::vector<SimRational> bump_q(2u, one);
    bump_q[1] = sim_rational(-2ll, 1ll);
    std::vector<SimRational> line_p(2u, sim_rational(0ll, 1ll));
    line_p[1] = one;
    const std::vector<SimRational> power_q(1u, request.h);

    static AtomBook book;
    const unsigned int power_atom = atom_book_id(&book, "c^h");
    const unsigned int value_atom = atom_book_id(&book, "w(z_c)");
    const unsigned int slope_atom = atom_book_id(&book, "w'(z_c)");
    const TaylorSeries decay = ode_series_decay(request.blend_center, terms);
    const TaylorSeries reflected = ode_series_decay_reflected(request.blend_center, terms);
    const TaylorSeries bump = ode_series_bump(request.blend_center, terms);
    const TaylorSeries power = ode_series_power(request.power_center, request.h, terms, power_atom);
    const TaylorSeries kummer = ode_series_kummer(request.kummer_center, request.h, terms, value_atom, slope_atom);

    // psi = alpha / (alpha + r beta), alpha and beta the unit series
    const TaylorSeries alpha =
        taylor_rational(request.blend_center, ode_series_first(square, unit, request.blend_center, terms));
    const TaylorSeries beta = taylor_rational(
        request.blend_center, ode_series_first(reflected_square, negative_unit, request.blend_center, terms));
    SimRational ratio = sim_rational(0ll, 1ll);
    unsigned int share = 0u;
    const TaylorSeries weight = blend_weight(request.blend_center, terms, &book, &ratio, &share);

    join_first_terms(&results.line, "e^(-1/s)", decay, 3u, &book, places);
    join_first_terms(&results.line, "w = U(1+h, 2, z)", kummer, 3u, &book, places);
    join_first_terms(&results.line, "psi", weight, 2u, &book, places);

    join_report(&results, join_zero(ode_series_first_residual(decay, square, unit)), "e^(-1/s): s^2 f' - f");
    join_report(&results, join_zero(ode_series_first_residual(reflected, reflected_square, negative_unit)),
                "e^(-1/(1-s)): (1-s)^2 f' + f");
    join_report(&results, join_zero(ode_series_first_residual(bump, bump_p, bump_q)),
                "e^(4-1/(s(1-s))): s^2 (1-s)^2 f' - (1-2s) f");
    join_report(&results, join_zero(ode_series_first_residual(power, line_p, power_q)), "x^h: x f' - h f");
    join_report(&results, join_zero(ode_series_kummer_residual(kummer, request.h)),
                "w: z w'' + (2-z) w' - (1+h) w");
    // psi (alpha + r beta) - alpha, every coefficient reduced under rho (1 + r) = 1
    const TaylorSeries whole = taylor_sum(alpha, taylor_form_scaled(beta, atom_form_e(ratio)));
    TaylorSeries back = taylor_difference(taylor_product(weight, whole), alpha);
    for (AtomForm &form : back.coefficient)
    {
        form = atom_form_unit_reduced(form, ratio, share);
    }
    join_report(&results, join_zero(back), "psi: psi (alpha + r beta) - alpha, reduced by rho (1 + r) = 1");
    // e^(-1/s) e^(-1/(1-s)) = e^(-1/(s(1-s))), the bump at e^(-4)
    const TaylorSeries joined = taylor_difference(taylor_product(decay, reflected),
                                                  taylor_form_scaled(bump, atom_form_e(sim_rational(-4ll, 1ll))));
    join_report(&results, join_zero(joined), "e: e^(-1/s) e^(-1/(1-s)) - e^(-4) e^(4-1/(s(1-s)))");
    const int held = (s_sim_rational_wide == 0) && (run_cfg_short() == 0) && (report_short() == 0) &&
                     (atom_form_short() == 0) && (taylor_short() == 0) && (ode_series_short() == 0) &&
                     (blend_short() == 0);
    scriptura_text(&results.line, held ? "  every exact value is held in the build's width\n"
                                       : "  a value outgrew the build's width: run with a larger SIM_EXACT_LIMBS\n");
    sim_check(&results, held, "every exact value held");
    return sim_close(&results, "join series");
}
