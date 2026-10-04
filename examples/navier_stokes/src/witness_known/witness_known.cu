// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// witness_known.cu: the witness cube on subjects whose components are known, before it measures anything unknown
#include "run_cfg.h"

#include "report.h"

#include "ode_series.h"
#include "record.h"
#include "witness_cube.h"

// Three subjects, each a cube from the cfg:
// - The product e^(-1/x) y^h w(z), each factor its series about the cube's center on its axis, w = U(1 + h, 2, z).
//   With a factor's series sum a_k t^k, its even part at the half-edge d is sum over even k of a_k d^k and its odd
//   part the sum over odd k. Component S is the product over the axes of the odd part where the axis is in S and the
//   even part where it is not.
// - A trilinear form, sum over S of q_S k_S times the product over a in S of (x_a - center_a) / half_a, with q_S from
//   the cfg and k_S an atom. Component S is q_S k_S.
// - The axis heat's A K(s_b) and A J(s_b) over (C, X_b, Pr), A = C^2 Pr^2 / (4 nu c) and s_b = Pr X_b / 2, the atom
//   E1(s_b) at each corner its own. Nothing is known of its components; they are recorded.
// Checks:
// 1. The product's 8 components are the products of the parts, exactly.
// 2. The trilinear form's 8 components are q_S k_S, exactly.
// 3. Every cube's components rebuild its 8 corners exactly.
// 4. Every exact value is held in the build's width.
// 5. Every cube is written whole to the record the cfg names.
// The request: witness_known <cfg>.
//     bash examples/navier_stokes/run.sh witness_known examples/navier_stokes/cfg/witness_known.cfg

typedef struct
{
    SimRational h;
    unsigned int terms;
    unsigned int value;
    unsigned int slope;
    unsigned int power;
    SimRational center[3];
} WitnessProduct;

typedef struct
{
    SimRational center[3];
    SimRational half[3];
    std::vector<SimRational> coefficients;
    unsigned int atom[8];
} WitnessTrilinear;

typedef struct
{
    SimRational diffusion;
    SimRational heat_capacity;
    int start;
} WitnessHeat;

// the three factors' series about the product's center
static TaylorSeries witness_known_factor(const WitnessProduct *product, unsigned int axis)
{
    if (axis == 0u)
    {
        return ode_series_decay(product->center[0], product->terms);
    }
    if (axis == 1u)
    {
        return ode_series_power(product->center[1], product->h, product->terms, product->power);
    }
    return ode_series_kummer(product->center[2], product->h, product->terms, product->value, product->slope);
}

static AtomForm witness_known_product(const void *context, const SimRational *point, AtomBook *book)
{
    const WitnessProduct *const product = (const WitnessProduct *)context;
    (void)book;
    AtomForm value = atom_form_rational(sim_rational(1ll, 1ll));
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        value = atom_form_product(value, taylor_value(witness_known_factor(product, axis), point[axis]));
    }
    return value;
}

// the even (odd = 0) or odd (odd = 1) part of a series at the offset `half`
static AtomForm witness_known_part(const TaylorSeries &series, SimRational half, unsigned int odd)
{
    AtomForm sum;
    SimRational power = sim_rational(1ll, 1ll);
    for (size_t index = 0u; index < series.coefficient.size(); index += 1u)
    {
        if ((index & 1u) == odd)
        {
            sum = atom_form_sum(sum, atom_form_scaled(series.coefficient[index], power));
        }
        power = sim_rational_product(power, half);
    }
    return sum;
}

static AtomForm witness_known_trilinear(const void *context, const SimRational *point, AtomBook *book)
{
    const WitnessTrilinear *const form = (const WitnessTrilinear *)context;
    (void)book;
    AtomForm value;
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        SimRational weight = form->coefficients[component];
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            if ((component >> axis) & 1u)
            {
                weight = sim_rational_product(
                    weight, sim_rational_product(sim_rational_difference(point[axis], form->center[axis]),
                                                 sim_rational_reciprocal(form->half[axis])));
            }
        }
        value = atom_form_sum(value, atom_form_scaled(atom_form_atom(form->atom[component]), weight));
    }
    return value;
}

// A K(s_b), or A J(s_b) where `start` is set, at (C, X_b, Pr)
static AtomForm witness_known_heat(const void *context, const SimRational *point, AtomBook *book)
{
    const WitnessHeat *const heat = (const WitnessHeat *)context;
    const SimRational s = sim_rational_product(sim_rational_product(point[2], point[1]), sim_rational(1ll, 2ll));
    const SimRational scale = sim_rational_product(
        sim_rational_product(sim_rational_product(point[0], point[0]), sim_rational_product(point[2], point[2])),
        sim_rational_reciprocal(sim_rational_product(sim_rational(4ll, 1ll),
                                                     sim_rational_product(heat->diffusion, heat->heat_capacity))));
    const unsigned int integral = atom_book_id(book, "E1(" + atom_book_rational(s) + ")");
    const SimRational over = sim_rational_reciprocal(s);
    const AtomForm decay = atom_form_scaled(atom_form_e(sim_rational_negative(s)), over);
    const AtomForm value =
        heat->start ? atom_form_difference(decay, atom_form_atom(integral))
                    : atom_form_difference(atom_form_scaled(atom_form_atom(integral),
                                                            sim_rational_sum(sim_rational(1ll, 1ll), over)),
                                           decay);
    return atom_form_scaled(value, scale);
}

static int witness_known_cube(const RunCfg *cfg, const char *name, SimRational *center, SimRational *half)
{
    std::vector<SimRational> centers;
    std::vector<SimRational> halves;
    const std::string at = name;
    if (!run_cfg_rationals(cfg, (at + ".center").c_str(), &centers) ||
        !run_cfg_rationals(cfg, (at + ".half").c_str(), &halves) || (centers.size() != 3u) || (halves.size() != 3u))
    {
        return 0;
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        center[axis] = centers[axis];
        half[axis] = halves[axis];
        if (sim_rational_sign(half[axis]) <= 0)
        {
            return 0;
        }
    }
    return 1;
}

static void witness_known_report(SimResults *results, const char *name, const WitnessCube *cube)
{
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, ": ");
    scriptura_decimal(&results->line, cube->slot.size(), 1u);
    scriptura_text(&results->line, " terms; by character 1..8:");
    for (unsigned int count = 1u; count <= 8u; count += 1u)
    {
        scriptura_character(&results->line, ' ');
        scriptura_decimal(&results->line, witness_cube_characters(cube, count), 1u);
    }
    scriptura_character(&results->line, '\n');
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    static RunCfg cfg;
    static WitnessProduct product;
    static WitnessTrilinear trilinear;
    WitnessHeat heat;
    SimRational product_half[3];
    SimRational heat_center[3];
    SimRational heat_half[3];
    SimRational viscosity;
    SimRational density;
    unsigned long long terms = 0ull;
    unsigned long long places = 0ull;
    const int read =
        (count == 2) && run_cfg_open(arguments[1], &cfg, &results.line) &&
        run_cfg_rational(&cfg, "anisotropy", &product.h) && run_cfg_count(&cfg, "terms", &terms) && (terms > 1ull) &&
        (terms < (1ull << 16u)) && witness_known_cube(&cfg, "product", product.center, product_half) &&
        (sim_rational_sign(sim_rational_difference(product.center[0], product_half[0])) > 0) &&
        (sim_rational_sign(sim_rational_difference(product.center[2], product_half[2])) > 0) &&
        witness_known_cube(&cfg, "trilinear", trilinear.center, trilinear.half) &&
        run_cfg_rationals(&cfg, "trilinear.coefficients", &trilinear.coefficients) &&
        (trilinear.coefficients.size() == 8u) && witness_known_cube(&cfg, "heat", heat_center, heat_half) &&
        (sim_rational_sign(sim_rational_difference(heat_center[1], heat_half[1])) > 0) &&
        (sim_rational_sign(sim_rational_difference(heat_center[2], heat_half[2])) > 0) &&
        run_cfg_rational(&cfg, "fluid.viscosity", &viscosity) && (sim_rational_sign(viscosity) > 0) &&
        run_cfg_rational(&cfg, "fluid.density", &density) && (sim_rational_sign(density) > 0) &&
        run_cfg_rational(&cfg, "fluid.heat_capacity", &heat.heat_capacity) &&
        (sim_rational_sign(heat.heat_capacity) > 0) && run_cfg_count(&cfg, "places", &places) && (places <= 18ull);
    if (!read)
    {
        if (count == 2)
        {
            run_cfg_missing(&results.line, "anisotropy, terms above 1, product, trilinear and heat each with three "
                                           "centers and three half-edges above 0 (product x and z and heat X_b and Pr "
                                           "above their half-edges), eight trilinear coefficients, fluid viscosity, "
                                           "density and heat_capacity above 0, places");
        }
        sim_flush(&results);
        fprintf(stderr, "witness_known <cfg>\n");
        return 2;
    }
    product.terms = (unsigned int)terms;
    heat.diffusion = sim_rational_product(viscosity, sim_rational_reciprocal(density));
    static AtomBook book;
    product.power = atom_book_id(&book, "(" + atom_book_rational(product.center[1]) + ")^h");
    product.value = atom_book_id(&book, "w(" + atom_book_rational(product.center[2]) + ")");
    product.slope = atom_book_id(&book, "w'(" + atom_book_rational(product.center[2]) + ")");
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        trilinear.atom[component] = atom_book_id(&book, "k_" + std::to_string(component));
    }

    static WitnessCube product_cube;
    static WitnessCube trilinear_cube;
    static WitnessCube kept_cube;
    static WitnessCube start_cube;
    witness_cube_measure(witness_known_product, &product, product.center, product_half, &book, &product_cube);
    witness_cube_measure(witness_known_trilinear, &trilinear, trilinear.center, trilinear.half, &book,
                         &trilinear_cube);
    heat.start = 0;
    witness_cube_measure(witness_known_heat, &heat, heat_center, heat_half, &book, &kept_cube);
    heat.start = 1;
    witness_cube_measure(witness_known_heat, &heat, heat_center, heat_half, &book, &start_cube);
    witness_known_report(&results, "e^(-1/x) y^h w(z)", &product_cube);
    witness_known_report(&results, "trilinear", &trilinear_cube);
    witness_known_report(&results, "A K(s_b) over (C, X_b, Pr)", &kept_cube);
    witness_known_report(&results, "A J(s_b) over (C, X_b, Pr)", &start_cube);

    // 1. the product's components
    int parts = 1;
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        AtomForm expected = atom_form_rational(sim_rational(1ll, 1ll));
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            expected = atom_form_product(expected, witness_known_part(witness_known_factor(&product, axis),
                                                                      product_half[axis], (component >> axis) & 1u));
        }
        parts = parts && atom_form_zero(atom_form_difference(expected, product_cube.component[component]));
    }
    scriptura_text(&results.line, parts ? "  the product's 8 components are the products of its factors' parts\n"
                                        : "  a component of the product is not the product of its factors' parts\n");
    sim_check(&results, parts, "product components");
    // 2. the trilinear form's components
    int coefficients = 1;
    for (unsigned int component = 0u; component < 8u; component += 1u)
    {
        const AtomForm expected =
            atom_form_scaled(atom_form_atom(trilinear.atom[component]), trilinear.coefficients[component]);
        coefficients = coefficients && atom_form_zero(atom_form_difference(expected, trilinear_cube.component[component]));
    }
    scriptura_text(&results.line, coefficients ? "  the trilinear form's 8 components are its coefficients\n"
                                               : "  a component of the trilinear form is not its coefficient\n");
    sim_check(&results, coefficients, "trilinear components");
    // 3. every cube rebuilt
    const int whole = witness_cube_whole(&product_cube) && witness_cube_whole(&trilinear_cube) &&
                      witness_cube_whole(&kept_cube) && witness_cube_whole(&start_cube);
    scriptura_text(&results.line, whole ? "  every cube's components rebuild its 8 corners exactly\n"
                                        : "  a cube's components do not rebuild a corner\n");
    sim_check(&results, whole, "corners rebuilt");
    // 5. the record, before the width: a number too wide to write marks the width
    FILE *const record = record_open(arguments[1], &cfg, "record");
    int recorded = 0;
    if (record != NULL)
    {
        witness_cube_record(record, "product", &product_cube, &book);
        witness_cube_record(record, "trilinear", &trilinear_cube, &book);
        witness_cube_record(record, "A_K", &kept_cube, &book);
        witness_cube_record(record, "A_J", &start_cube, &book);
        recorded = record_close(record);
    }
    // 4. the width
    const int held = (s_sim_rational_wide == 0) && (run_cfg_short() == 0) && (report_short() == 0) &&
                     (atom_form_short() == 0) && (taylor_short() == 0) && (ode_series_short() == 0) &&
                     (record_short() == 0) && (witness_cube_short() == 0);
    scriptura_text(&results.line, held ? "  every exact value is held in the build's width\n"
                                       : "  a value outgrew the build's width: run with a larger SIM_EXACT_LIMBS\n");
    sim_check(&results, held, "every exact value held");
    scriptura_text(&results.line, recorded ? "  every cube is written whole to the cfg's record\n"
                                           : "  the record is not written: the cfg names none, or it does not open\n");
    sim_check(&results, recorded, "record written");
    return sim_close(&results, "witness known");
}
