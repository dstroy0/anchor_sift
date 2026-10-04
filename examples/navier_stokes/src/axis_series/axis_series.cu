// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// axis_series.cu: the axis core's Taylor series in X (core_series.h) on Duraiswami's test data, checked against what his
// paper reports of it
#include "run_cfg.h"

#include "report.h"

#include "core_series.h"

// The data come as Chebyshev coefficients in eta and h as a decimal. The size of a coefficient is its largest
// magnitude at the nodes eta = j / n, j = -n..n, which is no more than its largest magnitude on [-1, 1]. The radius
// of convergence in X is read from those sizes by the ratio test and the root test.
// Checks:
// 1. Every exact value is held in the build's width.
// 2. Data even in eta for F_0 and Pi_0 and odd for U_0 give every F_k even and every U_k odd.
// 3. The ratio estimate and the root estimate of the radius from F at the last order lie in the cfg's radius.
// 4. The theta and z residuals of the series cut after X^K have exactly 0 as each coefficient of X^k, k < K.
// 5. Those residuals, at the nodes and at X = reach i / 4, i = 1..4, are no more than the cfg's residual.
// The request: axis_series <cfg>.
//     bash examples/navier_stokes/run.sh axis_series examples/navier_stokes/cfg/axis_series_duraiswami.cfg

// what the cfg gives
typedef struct
{
    EtaShape shape;
    EtaFunction swirl;
    EtaFunction axial;
    EtaFunction pressure;
    SimRational radius_low;
    SimRational radius_high;
    SimRational reach;
    SimRational residual;
    unsigned int order;
    unsigned int nodes;
    unsigned int shown;
    unsigned int root_bits;
    unsigned int places;
} AxisSeriesRequest;

// the largest magnitude at eta = j / nodes, j = -nodes..nodes
static SimRational axis_series_size(const EtaShape *shape, const EtaFunction *function, unsigned int nodes)
{
    SimRational largest = sim_rational(0ll, 1ll);
    for (long long step = -(long long)nodes; step <= (long long)nodes; step += 1ll)
    {
        const SimRational value = sim_rational_absolute(eta_function_value(shape, function, step, (long long)nodes));
        if (sim_rational_sign(sim_rational_difference(value, largest)) > 0)
        {
            largest = value;
        }
    }
    return largest;
}

// the largest magnitude of sum_k terms[k](eta) X^k over eta = j / nodes, j = -nodes..nodes, and X = reach i / 4,
// i = 1..4
static SimRational axis_series_residual_size(const EtaShape *shape, const std::vector<EtaFunction> *terms,
                                             SimRational reach, unsigned int nodes)
{
    SimRational largest = sim_rational(0ll, 1ll);
    for (long long step = -(long long)nodes; step <= (long long)nodes; step += 1ll)
    {
        std::vector<SimRational> values;
        for (const EtaFunction &term : *terms)
        {
            values.push_back(eta_function_value(shape, &term, step, (long long)nodes));
        }
        for (long long quarter = 1ll; quarter <= 4ll; quarter += 1ll)
        {
            const SimRational radius = sim_rational_product(reach, sim_rational(quarter, 4ll));
            SimRational sum = sim_rational(0ll, 1ll);
            for (size_t index = values.size(); index > 0u; index -= 1u)
            {
                sum = sim_rational_sum(sim_rational_product(sum, radius), values[index - 1u]);
            }
            sum = sim_rational_absolute(sum);
            if (sim_rational_sign(sim_rational_difference(sum, largest)) > 0)
            {
                largest = sum;
            }
        }
    }
    return largest;
}

// the root estimate size^(-1/k), floored to 2^-bits, by bisection on m with (m 2^-bits)^k size <= 1
static SimRational axis_series_root(SimRational size, unsigned int k, unsigned int bits)
{
    unsigned long long low = 0ull;
    unsigned long long high = 1ull << (bits + 8u);
    AnchorExactInteger unit;
    sim_rational_status_check(sim_exact_power(1ull << bits, k, &unit));
    AnchorExactInteger limit;
    sim_rational_status_check(sim_exact_product(&unit, &size.denominator, &limit));
    while (high - low > 1ull)
    {
        const unsigned long long middle = low + (high - low) / 2ull;
        AnchorExactInteger power;
        AnchorExactInteger reach;
        sim_rational_status_check(sim_exact_power(middle, k, &power));
        sim_rational_status_check(sim_exact_product(&power, &size.numerator, &reach));
        if (anchor_exact_compare(&reach, &limit) <= 0)
        {
            low = middle;
        }
        else
        {
            high = middle;
        }
    }
    return sim_rational((long long)low, (long long)(1ull << bits));
}

// the cfg at `path` read into `request`: 1, or 0 with the reason written to `line`
static int axis_series_read(const char *path, AxisSeriesRequest *request, ScripturaLine *line)
{
    static RunCfg cfg;
    if (run_cfg_open(path, &cfg, line) == 0)
    {
        return 0;
    }
    SimRational h;
    std::vector<SimRational> swirl;
    std::vector<SimRational> axial;
    std::vector<SimRational> pressure;
    std::vector<SimRational> radius;
    unsigned long long order = 0ull;
    unsigned long long nodes = 0ull;
    unsigned long long shown = 0ull;
    unsigned long long root_bits = 0ull;
    unsigned long long places = 0ull;
    const int read =
        run_cfg_rational(&cfg, "core.anisotropy", &h) && (sim_rational_sign(h) > 0) &&
        run_cfg_rationals(&cfg, "core.axis.swirl", &swirl) && run_cfg_rationals(&cfg, "core.axis.axial", &axial) &&
        run_cfg_rationals(&cfg, "core.axis.pressure", &pressure) && run_cfg_rationals(&cfg, "core.radius", &radius) &&
        (radius.size() == 2u) && run_cfg_rational(&cfg, "core.reach", &request->reach) &&
        (sim_rational_sign(request->reach) > 0) && run_cfg_rational(&cfg, "core.residual", &request->residual) &&
        run_cfg_count(&cfg, "core.order", &order) && (order > 0ull) && (order < (1ull << 20u)) &&
        run_cfg_count(&cfg, "core.nodes", &nodes) && (nodes > 0ull) && (nodes < (1ull << 20u)) &&
        run_cfg_count(&cfg, "report.shown", &shown) && run_cfg_count(&cfg, "report.root_bits", &root_bits) &&
        (root_bits > 0ull) && (root_bits < 48ull) && run_cfg_count(&cfg, "report.places", &places) &&
        (places <= 18ull);
    if (!read)
    {
        run_cfg_missing(line, "core anisotropy, reach and residual as decimal strings, core axis swirl, axial and "
                              "pressure as arrays of decimal Chebyshev coefficients, core radius as two decimal "
                              "strings, core order and nodes, and report shown, root_bits and places as whole numbers");
        return 0;
    }
    request->shape.part = h.numerator;
    request->shape.whole = h.denominator;
    eta_function_chebyshev(swirl, &request->swirl);
    eta_function_chebyshev(axial, &request->axial);
    eta_function_chebyshev(pressure, &request->pressure);
    request->radius_low = radius[0];
    request->radius_high = radius[1];
    // each below 2^20 or its own limit, checked above
    request->order = (unsigned int)order;
    request->nodes = (unsigned int)nodes;
    request->shown = (unsigned int)((shown < order) ? shown : order);
    request->root_bits = (unsigned int)root_bits;
    request->places = (unsigned int)places;
    return 1;
}

// 1 where every coefficient of every power of eta of the given parity is zero
static int axis_series_parity(const std::vector<EtaFunction> *functions, size_t parity)
{
    for (const EtaFunction &function : *functions)
    {
        for (size_t index = parity; index < function.coefficient.size(); index += 2u)
        {
            if (function.coefficient[index].sign != 0)
            {
                return 0;
            }
        }
    }
    return 1;
}

// the largest coefficient's bits over every function
static unsigned long long axis_series_bits(const std::vector<EtaFunction> *functions)
{
    unsigned long long most = 0ull;
    for (const EtaFunction &function : *functions)
    {
        for (const AnchorExactInteger &value : function.coefficient)
        {
            const unsigned long long bits = sim_exact_bits(&value);
            most = (bits > most) ? bits : most;
        }
        const unsigned long long bits = sim_exact_bits(&function.scale);
        most = (bits > most) ? bits : most;
    }
    return most;
}

// the sizes, the ratio estimates and the root estimates of one field over the last orders, printed; the ratio and
// root estimates at the last order returned
static void axis_series_radius(ScripturaLine *line, const AxisSeriesRequest *request,
                               const std::vector<EtaFunction> *functions, const char *name, SimRational *ratio_last,
                               SimRational *root_last)
{
    const unsigned int last = (unsigned int)functions->size() - 1u;
    const unsigned int first = (last > request->shown) ? last - request->shown + 1u : 1u;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, ": k, size, ratio estimate, root estimate\n");
    SimRational previous = axis_series_size(&request->shape, &(*functions)[first - 1u], request->nodes);
    *ratio_last = sim_rational(0ll, 1ll);
    *root_last = sim_rational(0ll, 1ll);
    for (unsigned int k = first; k <= last; k += 1u)
    {
        const SimRational size = axis_series_size(&request->shape, &(*functions)[k], request->nodes);
        scriptura_text(line, "    ");
        scriptura_decimal(line, k, 1u);
        scriptura_text(line, "  ");
        report_value(line, size, request->places);
        if (sim_rational_sign(size) > 0)
        {
            *ratio_last = sim_rational_product(previous, sim_rational_reciprocal(size));
            *root_last = axis_series_root(size, k, request->root_bits);
            scriptura_text(line, "  ");
            report_value(line, *ratio_last, request->places);
            scriptura_text(line, "  ");
            report_value(line, *root_last, request->places);
        }
        scriptura_character(line, '\n');
        previous = size;
    }
}

// 1 where low <= value <= high
static int axis_series_within(SimRational value, SimRational low, SimRational high)
{
    return (sim_rational_sign(sim_rational_difference(value, low)) >= 0) &&
           (sim_rational_sign(sim_rational_difference(high, value)) >= 0);
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    static AxisSeriesRequest request;
    if ((count != 2) || (axis_series_read(arguments[1], &request, &results.line) == 0))
    {
        sim_flush(&results);
        fprintf(stderr, "axis_series <cfg>\n");
        return 2;
    }
    scriptura_text(&results.line, "  axis series: the Taylor coefficients in X of the axis core, exact, to order ");
    scriptura_decimal(&results.line, request.order, 1u);
    scriptura_character(&results.line, '\n');
    static CoreSeries series;
    core_series_recursion(&request.shape, &request.swirl, &request.axial, &request.pressure, request.order, &series);
    scriptura_text(&results.line, "  the largest whole number held: ");
    const unsigned long long swirl_bits = axis_series_bits(&series.swirl);
    const unsigned long long axial_bits = axis_series_bits(&series.axial);
    scriptura_decimal(&results.line, (swirl_bits > axial_bits) ? swirl_bits : axial_bits, 1u);
    scriptura_text(&results.line, " bits; the last F over M^");
    scriptura_decimal(&results.line, series.swirl.back().power, 1u);
    scriptura_text(&results.line, " with degree ");
    scriptura_decimal(&results.line, series.swirl.back().coefficient.size() - 1u, 1u);
    scriptura_character(&results.line, '\n');
    SimRational swirl_ratio;
    SimRational swirl_root;
    SimRational axial_ratio;
    SimRational axial_root;
    axis_series_radius(&results.line, &request, &series.swirl, "F", &swirl_ratio, &swirl_root);
    axis_series_radius(&results.line, &request, &series.axial, "U", &axial_ratio, &axial_root);
    std::vector<EtaFunction> theta_residual;
    std::vector<EtaFunction> axial_residual;
    core_series_residual(&request.shape, request.order, &series, &theta_residual, &axial_residual);
    int below = 1;
    for (unsigned int k = 0u; k < request.order; k += 1u)
    {
        below = below && theta_residual[k].coefficient.empty() && axial_residual[k].coefficient.empty();
    }
    const SimRational theta_size =
        axis_series_residual_size(&request.shape, &theta_residual, request.reach, request.nodes);
    const SimRational axial_size =
        axis_series_residual_size(&request.shape, &axial_residual, request.reach, request.nodes);
    scriptura_text(&results.line, "  the residuals of the series cut after X^");
    scriptura_decimal(&results.line, request.order, 1u);
    scriptura_text(&results.line, ", largest over X = reach i / 4, i = 1..4, reach ");
    report_value(&results.line, request.reach, request.places);
    scriptura_text(&results.line, ": theta ");
    report_value(&results.line, theta_size, request.places);
    scriptura_text(&results.line, ", z ");
    report_value(&results.line, axial_size, request.places);
    scriptura_character(&results.line, '\n');
    // 1. the width
    const int held = (s_sim_rational_wide == 0) && (run_cfg_short() == 0) && (report_short() == 0) &&
                     (eta_function_short() == 0) && (core_series_short() == 0);
    scriptura_text(&results.line, held ? "  every exact value is held in the build's width\n"
                                       : "  a value outgrew the build's width: run with a larger SIM_EXACT_LIMBS\n");
    sim_check(&results, held, "every exact value held");
    // 2. parity, where the data have it
    std::vector<EtaFunction> data_even{request.swirl, request.pressure};
    std::vector<EtaFunction> data_odd{request.axial};
    if (axis_series_parity(&data_even, 1u) && axis_series_parity(&data_odd, 0u))
    {
        const int parity = axis_series_parity(&series.swirl, 1u) && axis_series_parity(&series.axial, 0u);
        scriptura_text(&results.line, parity ? "  every F_k is even in eta and every U_k odd\n"
                                             : "  an F_k is not even in eta or a U_k is not odd\n");
        sim_check(&results, parity, "F_k even and U_k odd");
    }
    // 3. the radius
    const int inside = axis_series_within(swirl_ratio, request.radius_low, request.radius_high) &&
                       axis_series_within(swirl_root, request.radius_low, request.radius_high);
    scriptura_text(&results.line, "  the ratio and root estimates from F at the last order ");
    scriptura_text(&results.line, inside ? "lie in " : "do not both lie in ");
    report_value(&results.line, request.radius_low, request.places);
    scriptura_text(&results.line, " to ");
    report_value(&results.line, request.radius_high, request.places);
    scriptura_character(&results.line, '\n');
    sim_check(&results, inside, "radius estimates in the cfg's radius");
    // 4. the residual below the cut
    scriptura_text(&results.line, below ? "  the residual coefficients of X^k, k < K, are exactly 0\n"
                                        : "  a residual coefficient of X^k, k < K, is not 0\n");
    sim_check(&results, below, "residual below the cut exactly 0");
    // 5. the residual at the reach
    const int small = (sim_rational_sign(sim_rational_difference(request.residual, theta_size)) >= 0) &&
                      (sim_rational_sign(sim_rational_difference(request.residual, axial_size)) >= 0);
    scriptura_text(&results.line, small ? "  both residuals are no more than " : "  a residual is more than ");
    report_value(&results.line, request.residual, request.places);
    scriptura_character(&results.line, '\n');
    sim_check(&results, small, "residuals within the cfg's residual");
    return sim_close(&results, "axis series");
}
