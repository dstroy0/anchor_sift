// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// axis_heat.cu: the least temperature on the axis of a turning column, by Proposition 21 of the millennium research
// paper, every value an exact form in e^(-s_b) and E1(s_b)
#include "run_cfg.h"

#include "report.h"

#include "ode_series.h"
#include "record.h"

// The column turns with the potential vortex v r = C outside X = X_b, where X = r^2 / (2 nu tau) and tau is the time
// left to the singular time T*. At the time t = T* - tau its axis stands above the temperature it started at by at
// least
//     A (K(s_b) / tau - J(s_b) / t),   A = C^2 Pr^2 / (4 nu c),   s_b = Pr X_b / 2,
//     K(s) = (1 + 1/s) E1(s) - e^(-s) / s,   J(s) = e^(-s) / s - E1(s),
// with Pr = mu c / k and nu = mu / rho. Every quantity is an exact rational read from the cfg's decimals, and K and J
// are each two terms: rational multiples of e^(-s_b) and of the atom E1(s_b). While tau <= T* / 2 the time t is at
// least T* / 2, and the axis has risen by the cfg's rise once tau <= A K / (rise + 2 A J / T*), a ratio of two forms.
// K' = -E1 / s^2 and J' = -e^(-s) / s^2 with K and J 0 at infinity: K = int_s^inf E1(t) / t^2 dt and
// J = int_s^inf e^(-t) / t^2 dt, both above 0, the sign Proposition 21 proves.
// Checks, every series about s_b with the cfg's terms, E1 = E1(s_b) - int_(s_b)^s e^(-t) / t dt:
// 1. K' + E1 / s^2 is 0 in every held coefficient.
// 2. J' + e^(-s) / s^2 is 0 in every held coefficient.
// 3. Every exact value is held in the build's width.
// 4. Every form is written whole to the record the cfg names.
// The request: axis_heat <cfg>.
//     bash examples/navier_stokes/run.sh axis_heat examples/navier_stokes/cfg/water_20c.cfg

typedef struct
{
    SimRational viscosity;
    SimRational density;
    SimRational conductivity;
    SimRational heat_capacity;
    SimRational circulation;
    SimRational join;
    SimRational singular_time;
    SimRational rise;
    unsigned long long terms;
    unsigned long long places;
} AxisHeatRequest;

// K(s) and J(s) as forms in e^(-s) and the atom `integral`
static AtomForm axis_heat_kept(SimRational s, unsigned int integral)
{
    const SimRational over = sim_rational_reciprocal(s);
    const AtomForm decay = atom_form_e(sim_rational_negative(s));
    return atom_form_difference(atom_form_scaled(atom_form_atom(integral), sim_rational_sum(sim_rational(1ll, 1ll), over)),
                                atom_form_scaled(decay, over));
}

static AtomForm axis_heat_before_start(SimRational s, unsigned int integral)
{
    const SimRational over = sim_rational_reciprocal(s);
    return atom_form_difference(atom_form_scaled(atom_form_e(sim_rational_negative(s)), over),
                                atom_form_atom(integral));
}

// 1 where every coefficient the series holds is 0
static int axis_heat_zero(const TaylorSeries &series)
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

static void axis_heat_form(ScripturaLine *line, const char *name, const AtomForm &form, const AtomBook *book,
                           unsigned int places)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " = ");
    atom_form_print(line, form, book->names, places);
    scriptura_character(line, '\n');
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    static RunCfg cfg;
    AxisHeatRequest request;
    const int read =
        (count == 2) && run_cfg_open(arguments[1], &cfg, &results.line) &&
        run_cfg_rational(&cfg, "fluid.viscosity", &request.viscosity) &&
        run_cfg_rational(&cfg, "fluid.density", &request.density) &&
        run_cfg_rational(&cfg, "fluid.conductivity", &request.conductivity) &&
        run_cfg_rational(&cfg, "fluid.heat_capacity", &request.heat_capacity) &&
        run_cfg_rational(&cfg, "column.circulation", &request.circulation) &&
        run_cfg_rational(&cfg, "column.join", &request.join) && (sim_rational_sign(request.join) > 0) &&
        run_cfg_rational(&cfg, "column.singular_time", &request.singular_time) &&
        run_cfg_rational(&cfg, "column.rise", &request.rise) && run_cfg_count(&cfg, "terms", &request.terms) &&
        (request.terms > 2ull) && (request.terms < (1ull << 20u)) && run_cfg_count(&cfg, "places", &request.places) &&
        (request.places <= 18ull) && (sim_rational_sign(request.viscosity) > 0) &&
        (sim_rational_sign(request.density) > 0) && (sim_rational_sign(request.conductivity) > 0) &&
        (sim_rational_sign(request.heat_capacity) > 0);
    if (!read)
    {
        if (count == 2)
        {
            run_cfg_missing(&results.line, "fluid viscosity, density, conductivity and heat_capacity above 0, column "
                                           "circulation, join above 0, singular_time and rise as decimal strings, "
                                           "terms above 2 and places as whole numbers");
        }
        sim_flush(&results);
        fprintf(stderr, "axis_heat <cfg>\n");
        return 2;
    }
    const unsigned int terms = (unsigned int)request.terms;
    const unsigned int places = (unsigned int)request.places;
    const SimRational two = sim_rational(2ll, 1ll);
    const SimRational four = sim_rational(4ll, 1ll);
    const SimRational diffusion = sim_rational_product(request.viscosity, sim_rational_reciprocal(request.density));
    const SimRational prandtl = sim_rational_product(sim_rational_product(request.viscosity, request.heat_capacity),
                                                     sim_rational_reciprocal(request.conductivity));
    const SimRational s = sim_rational_product(sim_rational_product(prandtl, request.join), sim_rational_reciprocal(two));
    const SimRational squared = sim_rational_product(sim_rational_product(request.circulation, request.circulation),
                                                     sim_rational_product(prandtl, prandtl));
    const SimRational scale = sim_rational_product(
        squared, sim_rational_reciprocal(sim_rational_product(four, sim_rational_product(diffusion, request.heat_capacity))));
    scriptura_text(&results.line, "  axis heat: the potential vortex outside X_b\n");
    report_line(&results.line, "nu", diffusion, " m^2/s", places);
    report_line(&results.line, "Pr", prandtl, "", places);
    report_line(&results.line, "s_b = Pr X_b / 2", s, "", places);
    report_line(&results.line, "A = C^2 Pr^2 / (4 nu c)", scale, " K s", places);

    static AtomBook book;
    const unsigned int integral = atom_book_id(&book, "E1(" + atom_book_rational(s) + ")");
    const AtomForm kept = axis_heat_kept(s, integral);
    const AtomForm before_start = axis_heat_before_start(s, integral);
    axis_heat_form(&results.line, "K(s_b)", kept, &book, places);
    axis_heat_form(&results.line, "J(s_b)", before_start, &book, places);
    const AtomForm lowest = atom_form_scaled(kept, scale);
    const AtomForm start = atom_form_scaled(before_start, scale);
    axis_heat_form(&results.line, "A K(s_b), the coefficient of 1 / tau, K s", lowest, &book, places);
    axis_heat_form(&results.line, "A J(s_b), the coefficient of 1 / t, K s", start, &book, places);
    // tau <= A K / (rise + 2 A J / T*), and no later than T* / 2
    const AtomForm below = atom_form_sum(
        atom_form_rational(request.rise),
        atom_form_scaled(start, sim_rational_product(two, sim_rational_reciprocal(request.singular_time))));
    scriptura_text(&results.line, "  the latest tau by which the axis has risen by the cfg's rise, the lesser of T* / 2 = ");
    report_value(&results.line, sim_rational_product(request.singular_time, sim_rational_reciprocal(two)), places);
    scriptura_text(&results.line, " s and (");
    atom_form_print(&results.line, lowest, book.names, places);
    scriptura_text(&results.line, ") / (");
    atom_form_print(&results.line, below, book.names, places);
    scriptura_text(&results.line, ") s\n");

    // the series about s_b: e^(-s), 1/s and E1
    const std::vector<SimRational> unit(1u, sim_rational(1ll, 1ll));
    const std::vector<SimRational> negative_unit(1u, sim_rational(-1ll, 1ll));
    std::vector<SimRational> line_p(2u, sim_rational(0ll, 1ll));
    line_p[1] = sim_rational(1ll, 1ll);
    const TaylorSeries decay = taylor_form_scaled(taylor_rational(s, ode_series_first(unit, negative_unit, s, terms)),
                                                  atom_form_e(sim_rational_negative(s)));
    // s f' = -f, f(s_b) = 1: f = s_b / s
    const TaylorSeries over = taylor_scaled(taylor_rational(s, ode_series_first(line_p, negative_unit, s, terms)),
                                            sim_rational_reciprocal(s));
    const TaylorSeries falling = taylor_scaled(taylor_product(decay, over), sim_rational(-1ll, 1ll));
    const TaylorSeries exponential_integral = taylor_integral_from_center(falling, atom_form_atom(integral));
    std::vector<SimRational> one_values(terms, sim_rational(0ll, 1ll));
    one_values[0] = sim_rational(1ll, 1ll);
    const TaylorSeries one = taylor_rational(s, one_values);
    const TaylorSeries kept_series = taylor_difference(taylor_product(taylor_sum(one, over), exponential_integral),
                                                       taylor_product(over, decay));
    const TaylorSeries start_series = taylor_difference(taylor_product(over, decay), exponential_integral);
    const TaylorSeries square = taylor_product(over, over);
    // 1. K' = -E1 / s^2
    const TaylorSeries kept_residual =
        taylor_sum(taylor_derivative(kept_series), taylor_product(exponential_integral, square));
    const int kept_zero = axis_heat_zero(kept_residual);
    scriptura_text(&results.line, kept_zero ? "  K' + E1 / s^2: every held coefficient is 0\n"
                                            : "  K' + E1 / s^2: a held coefficient is not 0\n");
    sim_check(&results, kept_zero, "K' = -E1 / s^2");
    // 2. J' = -e^(-s) / s^2
    const TaylorSeries start_residual = taylor_sum(taylor_derivative(start_series), taylor_product(decay, square));
    const int start_zero = axis_heat_zero(start_residual);
    scriptura_text(&results.line, start_zero ? "  J' + e^(-s) / s^2: every held coefficient is 0\n"
                                             : "  J' + e^(-s) / s^2: a held coefficient is not 0\n");
    sim_check(&results, start_zero, "J' = -e^(-s) / s^2");
    // 3. the width
    const int held = (s_sim_rational_wide == 0) && (run_cfg_short() == 0) && (report_short() == 0) &&
                     (atom_form_short() == 0) && (taylor_short() == 0) && (ode_series_short() == 0);
    scriptura_text(&results.line, held ? "  every exact value is held in the build's width\n"
                                       : "  a value outgrew the build's width: run with a larger SIM_EXACT_LIMBS\n");
    sim_check(&results, held, "every exact value held");
    // 4. the record
    FILE *const record = record_open(arguments[1], &cfg, "record");
    int recorded = 0;
    if (record != NULL)
    {
        record_form(record, "K", kept, &book);
        record_form(record, "J", before_start, &book);
        record_form(record, "A_K", lowest, &book);
        record_form(record, "A_J", start, &book);
        record_form(record, "latest_tau_over", below, &book);
        // a number wider than the decimal buffer marks atom_form short and leaves the record not whole
        recorded = record_close(record) && (atom_form_short() == 0);
    }
    scriptura_text(&results.line, recorded ? "  every form is written whole to the cfg's record\n"
                                           : "  the record is not written: the cfg names none, or it does not open\n");
    sim_check(&results, recorded, "record written");
    return sim_close(&results, "axis heat");
}
