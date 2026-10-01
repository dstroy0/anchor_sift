// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_floor_fit.cu: fits, bins, spreads and main
#include "noise_floor_internal.h"

// the line over the level through the noise detector's fit (build plan item 38), each level a place and its squares a
// total, at scale 1 on both
static int floor_fit(const unsigned long long *count, const unsigned long long *total, FloorLine *fit)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseLineSums sums;
    noise_line_sums_zero(&sums);
    fit->samples = 0ull;
    int ok = 1;
    for (unsigned long long level = 0ull; ok && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        fit->samples += count[level];
        AnchorExactInteger measured;
        sim_exact_unsigned(&measured, total[level]);
        ok = noise_line_sums_add(&sums, count[level], level, &measured, &error) == 0L;
    }
    NoiseLine line;
    ok = ok && (noise_line_fit(&sums, 1ull, 1ull, &line, &error) == 0L);
    if (ok != 0)
    {
        fit->slope = line.slope;
        fit->intercept = line.intercept;
        fit->denominator = line.denominator;
    }
    return ok;
}

static void floor_print_fit(ScripturaLine *line, const char *name, const FloorLine *fit)
{
    scriptura_text(line, name);
    scriptura_text(line, "slope ");
    sim_ratio_print(line, &fit->slope, &fit->denominator, 4u);
    scriptura_text(line, ", intercept ");
    sim_ratio_print(line, &fit->intercept, &fit->denominator, 3u);
    scriptura_text(line, ", over ");
    scriptura_decimal(line, fit->samples, 1u);
    scriptura_text(line, " pairs\n");
}

static int floor_bins_open(SimResults *results, FloorBins *bins)
{
    bins->count = NULL;
    bins->total = NULL;
    int ok =
        sim_status_check(results, cudaMalloc((void **)&bins->count, FLOOR_LEVELS * sizeof(unsigned long long)), "bins");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&bins->total, FLOOR_LEVELS * sizeof(unsigned long long)),
                                "bins");
    ok = ok &&
         sim_status_check(results, cudaMemset(bins->count, 0, FLOOR_LEVELS * sizeof(unsigned long long)), "bins zero");
    ok = ok &&
         sim_status_check(results, cudaMemset(bins->total, 0, FLOOR_LEVELS * sizeof(unsigned long long)), "bins zero");
    return ok;
}

static int floor_bins_fit(SimResults *results, const FloorBins *bins, unsigned long long *count,
                          unsigned long long *total, FloorLine *fit)
{
    int ok = sim_status_check(
        results, cudaMemcpy(count, bins->count, FLOOR_LEVELS * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
        "bins read");
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(total, bins->total, FLOOR_LEVELS * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
             "bins read");
    return ok && floor_fit(count, total, fit);
}

static void floor_bins_close(FloorBins *bins)
{
    cudaFree(bins->total);
    cudaFree(bins->count);
}

// The truth route's spreads, D^2 times a bound on its intercept's and its slope's variance (Derived). A pair whose
// signal holds at S reads y = d^2, d = X' - X, X = offset + pattern + g Poisson(S) + read, the read
// Binomial(4 r^2, 1/2) - 2 r^2 with kappa4 = -r^2 / 2. The pattern cancels in d, sigma^2 = g^2 S + r^2,
// k4 = kappa4(X) = g^4 S - r^2 / 2, kappa4(d) = 2 k4, and var(y) = v = 8 sigma^4 + 2 k4. Two pairs sharing a frame
// have cov(y, y') = c = mu4 - sigma^4 = 2 sigma^4 + k4 >= 0, and pairs sharing none are independent. The bound
// assumes pairs correlate only within one voxel's run of held pairs, and a run holds one level: each run carries one
// weight, and a run of m pairs has variance m v + 2 (m - 1) c = m (v + 2 c) - 2 c <= m u, with
// u = v + 2 c = 12 sigma^4 + 4 k4 = 12 (g^2 S + r^2)^2 + 4 g^4 S - 2 r^2. With N, A and B the counts' sums of 1, S
// and S^2 and D = N B - A^2, the fit's intercept is a D = sum y (B - A S) and its slope b D = sum y (N S - A), and
// Va = sum_S count(S) (B - A S)^2 u(S) >= D^2 var(a), Vb = sum_S count(S) (N S - A)^2 u(S) >= D^2 var(b).
static int floor_spreads(const unsigned long long *count, const SimCamera *camera, AnchorExactInteger *intercept_spread,
                         AnchorExactInteger *slope_spread)
{
    AnchorExactInteger samples;
    AnchorExactInteger along;
    AnchorExactInteger along_square;
    anchor_exact_zero(&samples);
    anchor_exact_zero(&along);
    anchor_exact_zero(&along_square);
    anchor_exact_zero(intercept_spread);
    anchor_exact_zero(slope_spread);
    int ok = 1;
    for (unsigned long long level = 0ull; ok && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        AnchorExactInteger number;
        AnchorExactInteger weighted;
        AnchorExactInteger squared;
        sim_exact_unsigned(&number, count[level]);
        ok = sim_exact_sum(&samples, &number, &samples) && sim_exact_scaled(&number, level, &weighted) &&
             sim_exact_sum(&along, &weighted, &along) && sim_exact_scaled(&weighted, level, &squared) &&
             sim_exact_sum(&along_square, &squared, &along_square);
    }
    AnchorExactInteger gain;
    AnchorExactInteger gain_square;
    AnchorExactInteger gain_fourth;
    AnchorExactInteger read;
    AnchorExactInteger read_twice;
    sim_exact_unsigned(&gain, camera->gain);
    sim_exact_unsigned(&read, camera->read_square);
    ok = ok && sim_exact_product(&gain, &gain, &gain_square) &&
         sim_exact_product(&gain_square, &gain_square, &gain_fourth) && sim_exact_scaled(&read, 2ull, &read_twice);
    for (unsigned long long level = 0ull; ok && (level < FLOOR_LEVELS); level += 1ull)
    {
        if (count[level] == 0ull)
        {
            continue;
        }
        // u(S) = 12 (g^2 S + r^2)^2 + 4 g^4 S - 2 r^2, non-negative for a whole r^2
        AnchorExactInteger shot;
        AnchorExactInteger variance;
        AnchorExactInteger fourth;
        AnchorExactInteger fourth_twelve;
        AnchorExactInteger shot_fourth;
        AnchorExactInteger spread;
        AnchorExactInteger unit;
        // a level is below 2^18. 4 S fits a word
        ok = sim_exact_scaled(&gain_square, level, &shot) && sim_exact_sum(&shot, &read, &variance) &&
             sim_exact_product(&variance, &variance, &fourth) && sim_exact_scaled(&fourth, 12ull, &fourth_twelve) &&
             sim_exact_scaled(&gain_fourth, 4ull * level, &shot_fourth) &&
             sim_exact_sum(&fourth_twelve, &shot_fourth, &spread) && sim_exact_less(&spread, &read_twice, &unit);
        // the intercept's weight B - A S and the slope's N S - A, each squared, times count(S) u(S)
        AnchorExactInteger product;
        AnchorExactInteger weight;
        AnchorExactInteger weight_square;
        AnchorExactInteger counted;
        AnchorExactInteger term;
        ok = ok && sim_exact_scaled(&along, level, &product) && sim_exact_less(&along_square, &product, &weight) &&
             sim_exact_product(&weight, &weight, &weight_square) &&
             sim_exact_scaled(&weight_square, count[level], &counted) && sim_exact_product(&counted, &unit, &term) &&
             sim_exact_sum(intercept_spread, &term, intercept_spread);
        ok = ok && sim_exact_scaled(&samples, level, &product) && sim_exact_less(&product, &along, &weight) &&
             sim_exact_product(&weight, &weight, &weight_square) &&
             sim_exact_scaled(&weight_square, count[level], &counted) && sim_exact_product(&counted, &unit, &term) &&
             sim_exact_sum(slope_spread, &term, slope_spread);
    }
    return ok;
}

static void floor_print_correlation(ScripturaLine *line, const char *name, unsigned long long product,
                                    unsigned long long here)
{
    // the product total was accumulated modulo 2^64 and its magnitude is below 2^63
    const long long signed_product = (long long)product;
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    sim_exact_signed(&top, signed_product);
    sim_exact_unsigned(&bottom, here);
    scriptura_text(line, name);
    scriptura_text(line, "sum d d' ");
    scriptura_signed(line, signed_product);
    scriptura_text(line, ", over sum d^2 ");
    scriptura_decimal(line, here, 1u);
    scriptura_text(line, ": ");
    sim_ratio_print(line, &top, &bottom, 4u);
    scriptura_character(line, '\n');
}

static void floor_transfer(SimResults *results, const SimScene *scene, const SimCamera *camera,
                           unsigned short *device_lanes, unsigned int *device_signal)
{
    const unsigned long long voxels = sim_scene_voxels(scene);
    FloorBins bins[FLOOR_ROUTES];
    FloorCoherence *device_coherence = NULL;
    int ok = 1;
    for (unsigned int route = 0u; route < FLOOR_ROUTES; route += 1u)
    {
        ok = floor_bins_open(results, &bins[route]) && ok;
    }
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_coherence, sizeof(FloorCoherence)), "coherence");
    ok = ok && sim_status_check(results, cudaMemset(device_coherence, 0, sizeof(FloorCoherence)), "coherence zero");
    if (ok)
    {
        const unsigned long long blocks = sim_launch_blocks((scene->frames - 1ull) * voxels, SIM_RENDER_THREADS);
        // the grid is below 2^31 blocks here
        floor_transfer_kernel<<<(unsigned int)blocks, (unsigned int)SIM_RENDER_THREADS>>>(
            device_lanes, device_signal, scene->frames, voxels, scene->extent[2], bins[0], bins[1], bins[2],
            device_coherence);
        ok = sim_status_check(results, cudaGetLastError(), "transfer: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "transfer: run");
    }
    unsigned long long *const count = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    unsigned long long *const total = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    // the truth route's counts, kept for its spreads after the other routes reuse count
    unsigned long long *const truth_count = (unsigned long long *)malloc(FLOOR_LEVELS * sizeof(unsigned long long));
    ok = ok && (count != NULL) && (total != NULL) && (truth_count != NULL);
    FloorLine fit[FLOOR_ROUTES];
    for (unsigned int route = 0u; ok && (route < FLOOR_ROUTES); route += 1u)
    {
        ok = floor_bins_fit(results, &bins[route], count, total, &fit[route]);
        if (ok && (route == 0u))
        {
            memcpy(truth_count, count, FLOOR_LEVELS * sizeof(unsigned long long));
        }
    }
    FloorCoherence coherence;
    ok = ok && sim_status_check(
                   results, cudaMemcpy(&coherence, device_coherence, sizeof(FloorCoherence), cudaMemcpyDeviceToHost),
                   "coherence read");
    sim_check(results, ok, "the transfer curve's three routes were measured");
    // the truth route's D = N B - A^2, checked positive before any ratio over it
    const int spanned = ok && (fit[0].denominator.sign > 0);
    sim_check(results, spanned, "the truth route's levels span two: D = N B - A^2 > 0");
    if (ok)
    {
        ScripturaLine *const line = &results->line;
        scriptura_text(line, "  the photon transfer curve, frame differences d = I(t+1) - I(t) over ");
        scriptura_decimal(line, coherence.pairs, 1u);
        scriptura_text(line, " pairs; planted gain ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_text(line, ", read variance ");
        scriptura_decimal(line, camera->read_square, 1u);
        scriptura_character(line, '\n');
        scriptura_text(line, "    truth, motion removed exactly (signal unchanged), d^2 on S: law slope 2 g^2 = ");
        scriptura_decimal(line, 2ull * camera->gain * camera->gain, 1u);
        scriptura_text(line, ", intercept 2 r^2 = ");
        scriptura_decimal(line, 2ull * camera->read_square, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[0]);
        scriptura_text(line, "    data only, every pair, d^2 on I(t) + I(t+1): law slope g = ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[1]);
        scriptura_text(line, "    data only, neighbor coherence, (d - d')^2 on the four lanes' sum: law slope g = ");
        scriptura_decimal(line, camera->gain, 1u);
        scriptura_character(line, '\n');
        floor_print_fit(line, "      ", &fit[2]);

        // the truth route's standard errors squared, SE^2 = V / D^2, from floor_spreads' bounds (Derived); every check
        // squares both sides against 25 V, exact
        AnchorExactInteger intercept_spread;
        AnchorExactInteger slope_spread;
        AnchorExactInteger denominator_square;
        const int spread = spanned && floor_spreads(truth_count, camera, &intercept_spread, &slope_spread) &&
                           sim_exact_product(&fit[0].denominator, &fit[0].denominator, &denominator_square);
        sim_check(results, spread, "the truth route's spreads were formed");
        if (spread != 0)
        {
            scriptura_text(line, "      SE^2 bounded above: intercept ");
            sim_ratio_print(line, &intercept_spread, &denominator_square, 8u);
            scriptura_text(line, ", slope ");
            sim_ratio_print(line, &slope_spread, &denominator_square, 8u);
            scriptura_character(line, '\n');
        }
        AnchorExactInteger law;
        AnchorExactInteger scaled;
        AnchorExactInteger apart;
        AnchorExactInteger apart_square;
        AnchorExactInteger bound;
        sim_exact_unsigned(&law, 2ull * camera->gain * camera->gain);
        ok = spread && sim_exact_product(&law, &fit[0].denominator, &scaled) &&
             sim_exact_less(&fit[0].slope, &scaled, &apart) && sim_exact_product(&apart, &apart, &apart_square) &&
             sim_exact_scaled(&slope_spread, FLOOR_ERROR_RANGE_SQUARED, &bound) &&
             (anchor_exact_compare(&apart_square, &bound) <= 0);
        sim_check(results, ok, "the truth route's slope lies within 5 SE_b of 2 g^2");
        sim_exact_unsigned(&law, 2ull * camera->read_square);
        ok = spread && sim_exact_product(&law, &fit[0].denominator, &scaled) &&
             sim_exact_less(&fit[0].intercept, &scaled, &apart) && sim_exact_product(&apart, &apart, &apart_square) &&
             sim_exact_scaled(&intercept_spread, FLOOR_ERROR_RANGE_SQUARED, &bound) &&
             (anchor_exact_compare(&apart_square, &bound) <= 0);
        sim_check(results, ok, "the truth route's intercept lies within 5 SE_a of 2 r^2");
        ok = spread && (fit[0].intercept.sign > 0) &&
             sim_exact_product(&fit[0].intercept, &fit[0].intercept, &apart_square) &&
             sim_exact_scaled(&intercept_spread, FLOOR_ERROR_RANGE_SQUARED, &bound) &&
             (anchor_exact_compare(&apart_square, &bound) >= 0);
        sim_check(results, ok, "the truth route's intercept stands at least 5 SE_a above 0: the read noise is there");

        scriptura_text(line, "  the neighbor coherence of d (x against x + 1)\n");
        floor_print_correlation(line, "    truth-static pairs: ", coherence.neighbor_product, coherence.square_here);
        floor_print_correlation(line, "    every pair:         ", coherence.neighbor_product_all,
                                coherence.square_here_all);
        // the product total's magnitude is below 2^63. It is read back signed
        const long long product = (long long)coherence.neighbor_product;
        AnchorExactInteger left;
        AnchorExactInteger right;
        AnchorExactInteger term;
        sim_exact_signed(&term, product);
        ok = sim_exact_product(&term, &term, &left);
        sim_exact_unsigned(&term, coherence.square_here);
        sim_exact_unsigned(&right, coherence.square_beside);
        ok = ok && sim_exact_product(&term, &right, &right);
        // twenty-five, the tolerance squared, is a small positive constant
        ok = ok && sim_exact_scaled(&right, (unsigned long long)FLOOR_CORRELATION_RANGE_SQUARED, &right);
        sim_exact_unsigned(&term, coherence.both_static);
        ok = ok && sim_exact_product(&left, &term, &left) && (anchor_exact_compare(&left, &right) <= 0);
        sim_check(results, ok, "static pairs' neighbor correlation lies within 5 / sqrt(N) of 0, about 4.1 sigma");
    }
    free(truth_count);
    free(total);
    free(count);
    cudaFree(device_coherence);
    for (unsigned int route = 0u; route < FLOOR_ROUTES; route += 1u)
    {
        floor_bins_close(&bins[route]);
    }
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    scriptura_text(&results.line, "  the noise floor, measured on the camera law with the answer known\n");

    FloorStream *const streams = (FloorStream *)malloc(FLOOR_STREAMS * sizeof(FloorStream));
    unsigned int *const lengths = (unsigned int *)malloc(FLOOR_STREAMS * sizeof(unsigned int));
    unsigned int *const regenerated = (unsigned int *)malloc(FLOOR_STREAMS * sizeof(unsigned int));
    int ok = (streams != NULL) && (lengths != NULL) && (regenerated != NULL);
    sim_check(&results, ok, "stream buffers");
    // the streams on the device, and the camera-law scene below: 24 frames of 20 x 96 x 96 lanes
    ok = ok && sim_job_submit(&results, "noise_floor", 0, NULL,
                              (FLOOR_STREAMS * (sizeof(FloorStream) + (2u * sizeof(unsigned int)))) +
                                  (24ull * 20ull * 96ull * 96ull * sizeof(unsigned short)));
    if (ok)
    {
        floor_mock(&results, streams, lengths, regenerated);
        floor_random(&results, streams, lengths, regenerated);
    }
    sim_flush(&results);

    SimBody body[FLOOR_FOUNDERS];
    memset(body, 0, sizeof(body));
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = 24ull;
    scene.extent[0] = 20ull;
    scene.extent[1] = 96ull;
    scene.extent[2] = 96ull;
    scene.background = 40ull;
    scene.ramp = 2ull;
    scene.bodies = FLOOR_FOUNDERS;
    scene.body = body;
    SimDraws draws;
    draws.key = FLOOR_KEY;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, body, FLOOR_FOUNDERS);
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = FLOOR_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_range = 8ull;
    camera.shot = 1ull;

    const unsigned long long lanes_count = scene.frames * sim_scene_voxels(&scene);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)lanes_count * sizeof(unsigned short));
    unsigned short *device_lanes = NULL;
    unsigned int *device_signal = NULL;
    unsigned long long clipped = 0ull;
    ok = ok && (lanes != NULL);
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_lanes, lanes_count * sizeof(unsigned short)), "lanes");
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_signal, lanes_count * sizeof(unsigned int)), "signal");
    ok = ok && sim_render(&results, &scene, &camera, device_lanes, device_signal, NULL, &clipped);
    ok = ok &&
         sim_status_check(&results,
                          cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                          "lanes read");
    sim_check(&results, ok && (clipped == 0ull), "the lattice rendered with no lane clipped");
    if (ok)
    {
        floor_planes(&results, lanes, lanes_count);
        sim_flush(&results);
        floor_transfer(&results, &scene, &camera, device_lanes, device_signal);
    }

    cudaFree(device_signal);
    cudaFree(device_lanes);
    free(lanes);
    free(regenerated);
    free(lengths);
    free(streams);
    return sim_close(&results, "noise floor");
}
