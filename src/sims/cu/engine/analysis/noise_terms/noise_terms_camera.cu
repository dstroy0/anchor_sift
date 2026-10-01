// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_terms_camera.cu: the camera, lines, flicker and neighbors
#include "noise_terms_internal.h"

static void terms_within(SimResults *results, const char *what, long long read, long long expected, long long tolerance)
{
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "    ");
    scriptura_text(line, what);
    scriptura_text(line, ": read ");
    scriptura_signed(line, read);
    scriptura_text(line, ", the plant predicts ");
    scriptura_signed(line, expected);
    scriptura_text(line, " within ");
    scriptura_signed(line, tolerance);
    scriptura_character(line, '\n');
    const long long apart = (read > expected) ? (read - expected) : (expected - read);
    sim_check(results, apart <= tolerance, what);
}

void terms_camera(SimCamera *camera)
{
    memset(camera, 0, sizeof(*camera));
    camera->key = TERMS_KEY;
    camera->offset = TERMS_OFFSET;
    camera->gain = 1ull;
    camera->read_square = TERMS_READ_SQUARE;
    camera->pattern_range = TERMS_PATTERN_RANGE;
    camera->shot = SIM_SHOT_POISSON;
}

int terms_render(SimResults *results, const SimScene *scene, const SimCamera *camera, unsigned short *device_lanes,
                 unsigned short *lanes, unsigned long long count)
{
    unsigned long long clipped = 0ull;
    const int ok = sim_render(results, scene, camera, device_lanes, NULL, NULL, &clipped) &&
                   sim_status_check(
                       results, cudaMemcpy(lanes, device_lanes, count * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                       "lanes read");
    sim_check(results, ok && (clipped == 0ull), "the scene rendered with no lane clipped");
    return ok && (clipped == 0ull);
}

// The lines' eight measurements against what the planted row, column and plane variances predict. Each offset of
// variance v a frame puts 2 v into the frame difference, whose independent variance is 2 V: the whole-plane ratios
// read 1000 + 1000 L v / V, L the voxels sharing it, and the static measurements 1000 v / V.
void terms_lines(SimResults *results, const unsigned short *lanes, unsigned long long row_square,
                 unsigned long long column_square, unsigned long long plane_square)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long readings[NOISE_PLANE_READINGS];
    const int ok = noise_lines_volume(lanes, TERMS_EXTENT, readings, &error) == 0L;
    sim_check(results, ok, "the lines read the volume");
    if (ok == 0)
    {
        return;
    }
    // every product below is far under 2^63 at these sizes
    const long long square = (long long)TERMS_VALUE_SQUARE;
    const long long rows = 1000ll + ((1000ll * (long long)(TERMS_WIDTH * row_square)) / square);
    const long long columns = 1000ll + ((1000ll * (long long)(TERMS_HEIGHT * column_square)) / square);
    const long long plane = 1000ll + ((1000ll * (long long)(TERMS_HEIGHT * TERMS_WIDTH * plane_square)) / square);
    const long long expected[NOISE_PLANE_READINGS] = {rows,
                                                      columns,
                                                      plane,
                                                      2ll * square,
                                                      (1000ll * (long long)row_square) / square,
                                                      (1000ll * (long long)column_square) / square,
                                                      (1000ll * (long long)plane_square) / square,
                                                      2000ll * square};
    const long long tolerance[NOISE_PLANE_READINGS] = {10ll + ((rows * TERMS_LINE_PARTS) / 1000ll),
                                                       10ll + ((columns * TERMS_LINE_PARTS) / 1000ll),
                                                       30ll + ((plane * TERMS_PLANE_PARTS) / 1000ll),
                                                       2ll,
                                                       3ll,
                                                       3ll,
                                                       6ll,
                                                       1000ll};
    const char *const said[NOISE_PLANE_READINGS] = {
        "whole planes, rows per mille",       "whole planes, columns per mille", "whole planes, the plane per mille",
        "whole planes, the independent part", "static, var_row / s per mille",   "static, var_col / s per mille",
        "static, var_plane / s per mille",    "static, s in thousandths"};
    for (unsigned int measurement = 0u; measurement < NOISE_PLANE_READINGS; measurement += 1u)
    {
        terms_within(results, said[measurement], readings[measurement], expected[measurement], tolerance[measurement]);
    }
}

// pairs t in [0, frames - lag) whose octave's block, t >> octave, differs from that of t + lag
static unsigned long long terms_crossings(unsigned long long lag, unsigned int octave)
{
    unsigned long long crossed = 0ull;
    for (unsigned long long frame = 0ull; (frame + lag) < TERMS_FRAMES; frame += 1ull)
    {
        crossed += ((frame >> octave) != ((frame + lag) >> octave)) ? 1ull : 0ull;
    }
    return crossed;
}

// The structure function's measurements against the plant. At lag k over n_k pairs, the frame difference's mean square
// is 2 V plus, for each octave, 2 f times the share of pairs whose block changes; so D(k) n_k is proportional to
// V n_k + f C(k), C(k) counting the pairs that cross a block over every octave. Both routes read the same ratio.
void terms_flicker(SimResults *results, const unsigned short *lanes, unsigned long long flicker_square,
                   unsigned int octaves)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long per_mille[NOISE_FLICKER_LAGS];
    unsigned long long neighbor_per_mille[NOISE_FLICKER_LAGS];
    const int ok = noise_flicker_volume(lanes, TERMS_EXTENT, per_mille, neighbor_per_mille, &error) == 0L;
    sim_check(results, ok, "the flicker pass read the volume");
    if (ok == 0)
    {
        return;
    }
    unsigned long long weight[NOISE_FLICKER_LAGS];
    unsigned long long pairs[NOISE_FLICKER_LAGS];
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        pairs[lag] = TERMS_FRAMES - (1ull << lag);
        weight[lag] = TERMS_VALUE_SQUARE * pairs[lag];
        for (unsigned int octave = 0u; octave < octaves; octave += 1u)
        {
            weight[lag] += flicker_square * terms_crossings(1ull << lag, octave);
        }
    }
    const char *const said[NOISE_FLICKER_LAGS] = {"lag 1", "lag 2", "lag 4", "lag 8", "lag 16", "lag 32", "lag 64"};
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        // each factor is below 2^20 here. The product is far under 2^63
        const long long expected = (long long)((1000ull * weight[lag] * pairs[0]) / (weight[0] * pairs[lag]));
        scriptura_text(&results->line, "    ");
        scriptura_text(&results->line, said[lag]);
        scriptura_character(&results->line, '\n');
        // a mean square per mille is far below 2^63
        terms_within(results, "  the frame difference", (long long)per_mille[lag], expected, 10ll);
        terms_within(results, "  less its x neighbor's", (long long)neighbor_per_mille[lag], expected, 10ll);
    }
}

// The neighbor pass against the plant. A mix of neighboring planes shares no draw between planes two or more apart.
// Every radius past the first along z reads 0 in the null and in the mix alike.
void terms_neighbors(SimResults *results, const unsigned short *lanes, long long expected_z)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long per_mille[NOISE_NEIGHBOR_RADII];
    const int ok = noise_neighbors_volume(lanes, TERMS_EXTENT, per_mille, &error) == 0L;
    sim_check(results, ok, "the neighbor pass read the volume");
    if (ok == 0)
    {
        return;
    }
    terms_within(results, "z neighbor, per mille", per_mille[0], expected_z, 6ll);
    terms_within(results, "y neighbor, per mille", per_mille[1], 0ll, 5ll);
    terms_within(results, "x neighbor, per mille", per_mille[2], 0ll, 5ll);
    const char *const said[NOISE_NEIGHBOR_RADII - ENGINE_AXES] = {
        "2 planes on along z, per mille", "4 planes on along z, per mille", "8 planes on along z, per mille",
        "16 planes on along z, per mille", "32 planes on along z, per mille"};
    for (unsigned int radius = ENGINE_AXES; radius < NOISE_NEIGHBOR_RADII; radius += 1u)
    {
        terms_within(results, said[radius - ENGINE_AXES], per_mille[radius], 0ll, 5ll);
    }
}

// The shot law read back by the moment pass. At S electrons with the read draw's variance r^2 (symmetric: third
// cumulant 0, fourth -r^2/2), a Poisson shot gives k2 = S + r^2, k3 = S and k4 = S - r^2/2, and the symmetric shot
// gives k2 = S + r^2, k3 = 0 and k4 = -S/2 - r^2/2. Each tolerance is about 5 standard errors of the mean over the
// static blocks of 5 frames.
void terms_shot_law(SimResults *results, const unsigned short *lanes, unsigned long long law)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long cumulants[NOISE_MOMENT_CUMULANTS];
    const int ok = noise_moments_volume(lanes, TERMS_EXTENT, cumulants, &error) == 0L;
    sim_check(results, ok, "the moment pass read the volume");
    if (ok == 0)
    {
        return;
    }
    // the scene's electrons and the read variance are each far below 2^31
    const long long shot = (long long)TERMS_SHOT_BACKGROUND;
    const long long read = (long long)TERMS_READ_SQUARE;
    const int poisson = law == SIM_SHOT_POISSON;
    const long long expected[NOISE_MOMENT_CUMULANTS] = {1000ll * (shot + read), poisson ? (1000ll * shot) : 0ll,
                                                        poisson ? ((1000ll * shot) - (500ll * read))
                                                                : ((-500ll * shot) - (500ll * read))};
    const long long range[NOISE_MOMENT_CUMULANTS] = {100ll, 500ll, 7000ll};
    const char *const said[NOISE_MOMENT_CUMULANTS] = {
        "the second cumulant, thousandths", "the third cumulant, thousandths", "the fourth cumulant, thousandths"};
    for (unsigned int order = 0u; order < NOISE_MOMENT_CUMULANTS; order += 1u)
    {
        terms_within(results, said[order], cumulants[order], expected[order], range[order]);
    }
}

// numerator / denominator, the denominator positive, within range_numerator / range_denominator of expected_numerator
// / expected_denominator: the difference cross-multiplied, |numerator ed rd - en denominator rd| against rn
// denominator ed
void terms_ratio_within(SimResults *results, const char *what, const AnchorExactInteger *numerator,
                        const AnchorExactInteger *denominator, long long expected_numerator,
                        unsigned long long expected_denominator, unsigned long long range_numerator,
                        unsigned long long range_denominator)
{
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "    ");
    scriptura_text(line, what);
    scriptura_text(line, ": read ");
    sim_ratio_print(line, numerator, denominator, 4u);
    scriptura_text(line, ", the plant predicts ");
    // printed in lowest terms: a magnitude below 2^63 re-signs exactly
    unsigned long long common =
        (expected_numerator < 0ll) ? (unsigned long long)(-expected_numerator) : (unsigned long long)expected_numerator;
    unsigned long long other = expected_denominator;
    while (other != 0ull)
    {
        const unsigned long long rest = common % other;
        common = other;
        other = rest;
    }
    common = (common == 0ull) ? 1ull : common;
    // the common factor divides the numerator's magnitude. The quotient keeps its sign and range
    scriptura_signed(line, expected_numerator / (long long)common);
    if ((expected_denominator / common) != 1ull)
    {
        scriptura_character(line, '/');
        scriptura_decimal(line, expected_denominator / common, 1u);
    }
    scriptura_text(line, " within ");
    scriptura_decimal(line, range_numerator, 1u);
    if (range_denominator != 1ull)
    {
        scriptura_character(line, '/');
        scriptura_decimal(line, range_denominator, 1u);
    }
    scriptura_character(line, '\n');
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger term;
    sim_exact_signed(&term, expected_numerator);
    int ok = sim_exact_scaled(numerator, expected_denominator, &left) &&
             sim_exact_scaled(&left, range_denominator, &left) && sim_exact_product(&term, denominator, &right) &&
             sim_exact_scaled(&right, range_denominator, &right) && sim_exact_less(&left, &right, &left);
    left.sign = (left.sign < 0) ? 1 : left.sign;
    ok = ok && sim_exact_scaled(denominator, range_numerator, &right) &&
         sim_exact_scaled(&right, expected_denominator, &right) && (anchor_exact_compare(&left, &right) <= 0);
    sim_check(results, ok, what);
}
