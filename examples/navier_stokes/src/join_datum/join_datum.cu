// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// join_datum.cu: the right side of Duraiswami's pressure datum at one eta, an exact form in atoms
#include "run_cfg.h"

#include "report.h"

#include "blend.h"
#include "record.h"
#include "core_series.h"
#include "decay_integral.h"
#include "ode_series.h"

// His join fixes the axis value of the pressure by
//     Pi_0(eta) = -int_0^{X_b} F_blend^2 dX + Pi_ext(X_b, eta),
//     F_blend = chi F_core + (1 - chi) F_ext,   chi = 1 - psi(s),   s = (X - X_a) / (X_b - X_a),
// and F_blend = F_core + psi (F_ext - F_core) on the annulus and F_core inside it. On [0, X_a] the integral is of the
// core polynomial's square, exact. On the annulus, in s, it is
//     (X_b - X_a) int_0^1 (G_0 + psi G_1 + psi^2 G_2) ds,
//     G_0 = F_core^2, G_1 = 2 F_core (F_ext - F_core), G_2 = (F_ext - F_core)^2,
// each by blend.h. The exterior swirl is F_ext = (c / sqrt 2) (2d)^(-1-h) w(X / (2d)), w = U(1 + h, 2, z), about each
// center its atoms w(z_c) and w'(z_c), with 2^(-1/2) and (2d)^(-h) atoms of their own, 2^(-1/2) squared reduced to
// 1/2. Past the join, Pi_ext(X_b, eta) = -(c^2 / 2) (2d)^(-1-2h) int_{z_b}^inf w^2 dz, z_b = X_b / (2d), the integral
// an atom. The value returned is the right side for the cfg's axis data and datum Pi_0, every atom held.
// Checks:
// 1. Every exact value is held in the build's width.
// 2. The two-term decay integral's derivative is b^k e^(-n/b) exactly, for every k the pieces use.
// 3. Every form is written whole to the record the cfg names.
// The request: join_datum <cfg>.
//     bash examples/navier_stokes/run.sh join_datum examples/navier_stokes/cfg/join_datum.cfg

typedef struct
{
    EtaShape shape;
    SimRational h;
    SimRational eta;
    SimRational amplitude;
    SimRational inner;
    SimRational outer;
    std::vector<SimRational> core;
    unsigned int root;
    unsigned int spread;
} JoinContext;

// F_core about X_c in s, the core polynomial moved and stretched by X_b - X_a
static TaylorSeries join_core(const JoinContext *context, SimRational center, unsigned int terms)
{
    const SimRational width = sim_rational_difference(context->outer, context->inner);
    const SimRational place = sim_rational_sum(context->inner, sim_rational_product(width, center));
    TaylorSeries series = taylor_stretched(taylor_polynomial(context->core, place, terms), width);
    series.center = center;
    return series;
}

// F_ext about X_c in s: (c / sqrt 2) (2d)^(-1-h) w(X / (2d)), w about z_c = X_c / (2d) stretched by (X_b - X_a) / (2d)
static TaylorSeries join_exterior(const JoinContext *context, SimRational center, unsigned int terms, AtomBook *book)
{
    const SimRational width = sim_rational_difference(context->outer, context->inner);
    const SimRational place = sim_rational_sum(context->inner, sim_rational_product(width, center));
    const SimRational twice = sim_rational_product(
        sim_rational(2ll, 1ll), sim_rational_difference(sim_rational(1ll, 1ll),
                                                        sim_rational_product(context->eta, context->eta)));
    const SimRational point = sim_rational_product(place, sim_rational_reciprocal(twice));
    const std::string name = atom_book_rational(point);
    const unsigned int value = atom_book_id(book, "w(" + name + ")");
    const unsigned int slope = atom_book_id(book, "w'(" + name + ")");
    TaylorSeries series = taylor_stretched(ode_series_kummer(point, context->h, terms, value, slope),
                                           sim_rational_product(width, sim_rational_reciprocal(twice)));
    series.center = center;
    const AtomForm factor = atom_form_product(
        atom_form_scaled(atom_form_atom(context->root),
                         sim_rational_product(context->amplitude, sim_rational_reciprocal(twice))),
        atom_form_atom(context->spread));
    return taylor_form_scaled(series, factor);
}

static TaylorSeries join_reduced(TaylorSeries series, const JoinContext *context)
{
    for (AtomForm &form : series.coefficient)
    {
        form = atom_form_square_reduced(form, context->root, sim_rational(1ll, 2ll));
    }
    return series;
}

static TaylorSeries join_first(const void *given, SimRational center, unsigned int terms, AtomBook *book)
{
    const JoinContext *const context = (const JoinContext *)given;
    (void)book;
    const TaylorSeries core = join_core(context, center, terms);
    return taylor_product(core, core);
}

static TaylorSeries join_second(const void *given, SimRational center, unsigned int terms, AtomBook *book)
{
    const JoinContext *const context = (const JoinContext *)given;
    const TaylorSeries core = join_core(context, center, terms);
    const TaylorSeries gap = taylor_difference(join_exterior(context, center, terms, book), core);
    return join_reduced(taylor_scaled(taylor_product(core, gap), sim_rational(2ll, 1ll)), context);
}

static TaylorSeries join_third(const void *given, SimRational center, unsigned int terms, AtomBook *book)
{
    const JoinContext *const context = (const JoinContext *)given;
    const TaylorSeries core = join_core(context, center, terms);
    const TaylorSeries gap = taylor_difference(join_exterior(context, center, terms, book), core);
    return join_reduced(taylor_product(gap, gap), context);
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    static RunCfg cfg;
    SimRational h;
    std::vector<SimRational> swirl;
    std::vector<SimRational> axial;
    std::vector<SimRational> pressure;
    static JoinContext context;
    BlendPieces pieces;
    unsigned long long order = 0ull;
    unsigned long long terms = 0ull;
    unsigned long long orders = 0ull;
    unsigned long long places = 0ull;
    const int read =
        (count == 2) && run_cfg_open(arguments[1], &cfg, &results.line) &&
        run_cfg_rational(&cfg, "core.anisotropy", &h) && (sim_rational_sign(h) > 0) &&
        run_cfg_rationals(&cfg, "core.axis.swirl", &swirl) && run_cfg_rationals(&cfg, "core.axis.axial", &axial) &&
        run_cfg_rationals(&cfg, "core.axis.pressure", &pressure) && run_cfg_count(&cfg, "core.order", &order) &&
        (order > 0ull) && (order < (1ull << 20u)) && run_cfg_rational(&cfg, "join.eta", &context.eta) &&
        run_cfg_rational(&cfg, "join.amplitude", &context.amplitude) &&
        run_cfg_rational(&cfg, "join.inner", &context.inner) && run_cfg_rational(&cfg, "join.outer", &context.outer) &&
        (sim_rational_sign(sim_rational_difference(context.outer, context.inner)) > 0) &&
        (sim_rational_sign(context.inner) > 0) && run_cfg_rationals(&cfg, "blend.cuts", &pieces.cuts) &&
        (pieces.cuts.size() >= 3u) && run_cfg_count(&cfg, "blend.terms", &terms) && (terms > 1ull) &&
        run_cfg_count(&cfg, "blend.orders", &orders) && run_cfg_count(&cfg, "report.places", &places) &&
        (places <= 18ull) &&
        (sim_rational_sign(sim_rational_difference(sim_rational(1ll, 1ll),
                                                   sim_rational_product(context.eta, context.eta))) > 0);
    if (!read)
    {
        if (count == 2)
        {
            run_cfg_missing(&results.line, "core anisotropy, axis swirl, axial and pressure, core order, join eta "
                                           "inside (-1, 1), amplitude, inner and outer with 0 < inner < outer, blend "
                                           "cuts (three or more), blend terms and orders, report places");
        }
        sim_flush(&results);
        fprintf(stderr, "join_datum <cfg>\n");
        return 2;
    }
    pieces.terms = (unsigned int)terms;
    pieces.orders = (unsigned int)orders;
    context.h = h;
    context.shape.part = h.numerator;
    context.shape.whole = h.denominator;
    EtaFunction swirl_data;
    EtaFunction axial_data;
    EtaFunction pressure_data;
    eta_function_chebyshev(swirl, &swirl_data);
    eta_function_chebyshev(axial, &axial_data);
    eta_function_chebyshev(pressure, &pressure_data);
    static CoreSeries series;
    core_series_recursion(&context.shape, &swirl_data, &axial_data, &pressure_data, (unsigned int)order, &series);
    context.core = core_series_at(&context.shape, series.swirl, context.eta);
    static AtomBook book;
    context.root = atom_book_id(&book, "2^(-1/2)");
    const SimRational twice = sim_rational_product(
        sim_rational(2ll, 1ll),
        sim_rational_difference(sim_rational(1ll, 1ll), sim_rational_product(context.eta, context.eta)));
    context.spread = atom_book_id(&book, "(" + atom_book_rational(twice) + ")^(-h)");

    // the core inside X_a: int_0^{X_a} P^2 dX, P held with room for its square
    const unsigned int square_terms = 2u * (unsigned int)context.core.size();
    const TaylorSeries whole = taylor_polynomial(context.core, sim_rational(0ll, 1ll), square_terms);
    const AtomForm inside = taylor_integral(taylor_product(whole, whole), sim_rational(0ll, 1ll), context.inner);
    // the annulus
    const SimRational width = sim_rational_difference(context.outer, context.inner);
    AtomForm annulus = blend_integral(&pieces, 0u, join_first, &context, &book);
    annulus = atom_form_sum(annulus, blend_integral(&pieces, 1u, join_second, &context, &book));
    annulus = atom_form_sum(annulus, blend_integral(&pieces, 2u, join_third, &context, &book));
    annulus = atom_form_scaled(annulus, width);
    // past the join
    const SimRational end = sim_rational_product(context.outer, sim_rational_reciprocal(twice));
    const unsigned int tail = atom_book_id(&book, "int_(" + atom_book_rational(end) + ")^inf w^2");
    const AtomForm beyond = atom_form_product(
        atom_form_scaled(atom_form_atom(tail),
                         sim_rational_negative(sim_rational_product(
                             sim_rational_product(context.amplitude, context.amplitude),
                             sim_rational_reciprocal(sim_rational_product(sim_rational(2ll, 1ll), twice))))),
        atom_form_product(atom_form_atom(context.spread), atom_form_atom(context.spread)));
    const AtomForm datum = atom_form_sum(atom_form_scaled(atom_form_sum(inside, annulus), sim_rational(-1ll, 1ll)),
                                         beyond);

    scriptura_text(&results.line, "  join datum at eta = ");
    report_value(&results.line, context.eta, (unsigned int)places);
    scriptura_text(&results.line, ": ");
    scriptura_decimal(&results.line, atom_form_terms(datum), 1u);
    scriptura_text(&results.line, " terms over ");
    scriptura_decimal(&results.line, book.names.size(), 1u);
    scriptura_text(&results.line, " atoms and ");
    scriptura_decimal(&results.line, atom_form_e_count(datum), 1u);
    scriptura_text(&results.line, " powers of e, held as ");
    scriptura_decimal(&results.line, atom_form_entries(datum), 1u);
    scriptura_text(&results.line, " entries of at most ");
    scriptura_decimal(&results.line, atom_form_bits(datum), 1u);
    scriptura_text(&results.line, " bits over one denominator\n  the core inside X_a, -int_0^{X_a} F_core^2 dX = ");
    report_value(&results.line, sim_rational_negative(atom_form_constant(inside)), (unsigned int)places);
    scriptura_text(&results.line, "\n  the atoms:");
    for (const std::string &name : book.names)
    {
        scriptura_text(&results.line, " ");
        scriptura_text(&results.line, name.c_str());
    }
    scriptura_character(&results.line, '\n');
    // the record: every form whole
    FILE *const record = record_open(arguments[1], &cfg, "report.record");
    int recorded = 0;
    if (record != NULL)
    {
        record_form(record, "core_inside", inside, &book);
        record_form(record, "annulus", annulus, &book);
        record_form(record, "beyond", beyond, &book);
        record_form(record, "datum", datum, &book);
        recorded = record_close(record);
    }
    // 2. the decay integral, every k the pieces use
    int derivative = 1;
    for (unsigned int k = 0u; k < pieces.terms; k += 1u)
    {
        std::vector<SimRational> first;
        std::vector<SimRational> second;
        decay_integral_residual(k, &first, &second);
        derivative = derivative && first.empty() && second.empty();
    }
    // 1. the width
    const int held = (s_sim_rational_wide == 0) && (run_cfg_short() == 0) && (report_short() == 0) &&
                     (atom_form_short() == 0) && (taylor_short() == 0) && (ode_series_short() == 0) &&
                     (eta_function_short() == 0) && (core_series_short() == 0) && (decay_integral_short() == 0) &&
                     (blend_short() == 0);
    scriptura_text(&results.line, held ? "  every exact value is held in the build's width\n"
                                       : "  a value outgrew the build's width: run with a larger SIM_EXACT_LIMBS\n");
    sim_check(&results, held, "every exact value held");
    scriptura_text(&results.line, derivative ? "  d/db of each decay integral is b^k e^(-n/b) exactly\n"
                                             : "  a decay integral's derivative is not b^k e^(-n/b)\n");
    sim_check(&results, derivative, "decay integral derivative");
    scriptura_text(&results.line, recorded ? "  every form is written whole to the cfg's record\n"
                                           : "  the record is not written: the cfg names none, or it does not open\n");
    sim_check(&results, recorded, "record written");
    return sim_close(&results, "join datum");
}
