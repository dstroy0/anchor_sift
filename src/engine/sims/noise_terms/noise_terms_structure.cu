// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_terms_structure.cu: structure, halves, spikes, boxes and clips
#include "noise_terms_internal.h"

// C17 read back (build plan item 38). The scale moves a pair's d_k - d_{k,x} by (eps_{t+k} - eps_t) g (S - S_x), and
// L - L_x = g (S - S_x)(1 + mean eps). D_a(k) reads the scale path's mean squared step over (1 + mean eps)^2, from the
// path the camera drew: 10^6 T^2 sum_t (e_{t+k} - e_t)^2 / ((T - k)(2^b T + sum_t e_t)^2) in millionths. The intercept
// reads the pairs' own noise, the mean over the pairs in 40 to 199 and their frame pairs of g^2 times the four
// lights plus 4 R^2. The rounded scale adds to it the roundings' own mean square, about 1/3: with rho a light's
// rounding in units of 2^-b, the rounded light times 2^b less the light before the scale times the scale held,
// g^2 (rho(x, t + k) - rho(x, t) - rho(x + 1, t + k) + rho(x + 1, t))^2 / 2^(2b) over the same pairs and frame pairs,
// and the expected value holds that sum exactly. The cross term, 2 g^2 (S - S_x)(e_{t+k} - e_t) times that rounding
// step over 2^(2b), averages to about 0 over the pairs, the roundings spread evenly over their range and unrelated to
// the step they multiply (Derived), and is not kept. The slope's standard error, estimated from the plant, is under
// 100 millionths at every lag. The slope's tolerance of 500 millionths is at least 5 of them. The intercept's is about
// 0.2, and the tolerance of 1 keeps its full width, about 5 of them.
void terms_structure(SimResults *results, const unsigned short *lanes, const SimScene *scene, const SimCamera *camera)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    // the measurement's 28 exact integers are held off the stack
    NoiseStructureMeasurement *const measurement =
        (NoiseStructureMeasurement *)malloc(sizeof(NoiseStructureMeasurement));
    const int ok = (measurement != NULL) && (noise_structure_volume(lanes, TERMS_EXTENT, measurement, &error) == 0L);
    sim_check(results, ok, "the structure pass read the volume");
    unsigned long long *const light =
        (unsigned long long *)malloc(TERMS_WIDTH * TERMS_FRAMES * sizeof(unsigned long long));
    sim_check(results, light != NULL, "the lights' table");
    long long *const rounding = (long long *)malloc(TERMS_WIDTH * TERMS_FRAMES * sizeof(long long));
    sim_check(results, rounding != NULL, "the roundings' table");
    if ((ok == 0) || (light == NULL) || (rounding == NULL))
    {
        free(measurement);
        free(light);
        free(rounding);
        return;
    }
    // the light at every column and frame, exactly as the camera drew it: the scene has no body. Every z and y of a
    // column holds the same light
    for (unsigned long long x = 0ull; x < TERMS_WIDTH; x += 1ull)
    {
        // a column index is far below 2^63
        const long long place[SIM_AXES] = {0ll, 0ll, (long long)x};
        for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
        {
            light[(x * TERMS_FRAMES) + frame] = sim_light(scene, camera, frame, place);
        }
    }
    long long path[TERMS_FRAMES];
    long long path_total = 0ll;
    long long least = 0ll;
    long long maximum = 0ll;
    for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
    {
        path[frame] = (camera->scale_bits != 0u) ? sim_scale(camera, frame) : 0ll;
        path_total += path[frame];
        least = ((frame == 0ull) || (path[frame] < least)) ? path[frame] : least;
        maximum = ((frame == 0ull) || (path[frame] > maximum)) ? path[frame] : maximum;
    }
    const long long unit = (camera->scale_bits != 0u) ? (1ll << camera->scale_bits) : 1ll;
    // each light's rounding in units of 1 / unit: the rounded light times the unit less the light before the scale
    // times the scale held, as sim_light holds it, an integer of at most unit / 2 in size and 0 without a scale
    SimCamera unscaled = *camera;
    unscaled.scale_bits = 0u;
    for (unsigned long long x = 0ull; x < TERMS_WIDTH; x += 1ull)
    {
        // a column index is far below 2^63
        const long long place[SIM_AXES] = {0ll, 0ll, (long long)x};
        for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
        {
            const long long scale = unit + path[frame];
            const long long factor = (scale < 1ll) ? 1ll : scale;
            // a light of a few hundred electrons times a unit of 2^10 is far below 2^63
            rounding[(x * TERMS_FRAMES) + frame] = ((long long)light[(x * TERMS_FRAMES) + frame] * unit) -
                                                   ((long long)sim_light(scene, &unscaled, frame, place) * factor);
        }
    }
    scriptura_text(&results->line, "    e_t from ");
    scriptura_signed(&results->line, least);
    scriptura_text(&results->line, " to ");
    scriptura_signed(&results->line, maximum);
    scriptura_text(&results->line, ", summing to ");
    scriptura_signed(&results->line, path_total);
    scriptura_text(&results->line, " over the frames\n");
    // the gain, offset and read variance are each far below 2^31
    const unsigned long long gain = camera->gain;
    const char *const said[NOISE_FLICKER_LAGS] = {"lag 1", "lag 2", "lag 4", "lag 8", "lag 16", "lag 32", "lag 64"};
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        const unsigned long long apart = 1ull << lag;
        const unsigned long long frame_pairs = TERMS_FRAMES - apart;
        unsigned long long steps = 0ull;
        for (unsigned long long frame = 0ull; frame < frame_pairs; frame += 1ull)
        {
            const long long step = path[frame + apart] - path[frame];
            // a step of a few hundred squares far below 2^63, and re-signs exactly
            steps += (unsigned long long)(step * step);
        }
        // the pairs in 40 to 199 by their lights' totals, and their own noise over the frame pairs
        unsigned long long included = 0ull;
        unsigned long long own = 0ull;
        // the roundings' own mean square, g^2 (rho(x, t + k) - rho(x, t) - rho(x + 1, t + k) + rho(x + 1, t))^2 summed,
        // in units of 1 / unit^2
        unsigned long long rounded = 0ull;
        for (unsigned long long x = 0ull; (x + 1ull) < TERMS_WIDTH; x += 1ull)
        {
            const unsigned long long *const here = &light[x * TERMS_FRAMES];
            const unsigned long long *const beside = &light[(x + 1ull) * TERMS_FRAMES];
            const long long *const here_rounding = &rounding[x * TERMS_FRAMES];
            const long long *const beside_rounding = &rounding[(x + 1ull) * TERMS_FRAMES];
            unsigned long long totals = 0ull;
            for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
            {
                totals += (2ull * camera->offset) + (gain * (here[frame] + beside[frame]));
            }
            const unsigned long long level_bin = totals / (16ull * TERMS_FRAMES);
            if ((level_bin < 5ull) || (level_bin > 24ull))
            {
                continue;
            }
            included += 1ull;
            for (unsigned long long frame = 0ull; frame < frame_pairs; frame += 1ull)
            {
                own += (gain * gain * (here[frame] + here[frame + apart] + beside[frame] + beside[frame + apart])) +
                       (4ull * camera->read_square);
                // four roundings of at most unit / 2 each: the step is at most 2 unit, its square far below 2^63
                const long long step = here_rounding[frame + apart] - here_rounding[frame] -
                                       beside_rounding[frame + apart] + beside_rounding[frame];
                rounded += gain * gain * (unsigned long long)(step * step);
            }
        }
        scriptura_text(&results->line, "    ");
        scriptura_text(&results->line, said[lag]);
        scriptura_text(&results->line, ", over ");
        scriptura_decimal(&results->line, measurement->pairs[lag], 1u);
        scriptura_text(&results->line, " frame pairs\n");
        sim_check(results, measurement->read[lag] != 0, "some bin's q spans two values, so the line reads");
        if (measurement->read[lag] == 0)
        {
            continue;
        }
        // the unit times the frames, and the path's total, are each far below 2^31
        const long long level = (unit * (long long)TERMS_FRAMES) + path_total;
        // each factor is small here: the product stays far below 2^63, the denominator below 2^64
        const long long expected = (long long)(1000000ull * TERMS_FRAMES * TERMS_FRAMES * steps);
        const unsigned long long expected_denominator = frame_pairs * (unsigned long long)(level * level);
        AnchorExactInteger millionths;
        const int scaled = sim_exact_scaled(&measurement->slope[lag], 1000000ull, &millionths);
        sim_check(results, scaled, "the slope in millionths");
        if (scaled)
        {
            terms_ratio_within(results, "  D_a(k), millionths", &millionths, &measurement->slope_denominator[lag],
                               expected, expected_denominator, 500ull, 1ull);
        }
        // the own noise summed, below 2^24, times unit^2 = 2^20, plus the roundings' sum, below 2^36, is far below
        // 2^63, and the pairs' count times unit^2 below 2^34
        const unsigned long long square_unit = (unsigned long long)(unit * unit);
        terms_ratio_within(results, "  2 D(k), the pairs' own noise", &measurement->intercept[lag],
                           &measurement->intercept_denominator[lag], (long long)((own * square_unit) + rounded),
                           included * frame_pairs * square_unit, 1ull, 1ull);
    }
    free(measurement);
    free(light);
    free(rounding);
}

// Rows 18 and 19 read back. Under a flat light S a pixel holds f = o + p g S / 2^b in both halves, its offset o and
// its gain's departure p, and the halves' covariance is var(f) over the pixels' drawn f,
// (P sum F^2 - (sum F)^2) / (P^2 2^(2b)) with F = o 2^b + p g S: the fixed pattern is drawn per voxel. No two planes
// share it, and the null reads 0. The pattern and the draws, independent between the halves with variance h^2 in a
// half's mean, spread the measurement by sqrt((2 var(f) h^2 + h^4) / P): about 1/70, 1/33 and 1/15 lane units squared
// at the three lights with the gain pattern, 1/260 to 1/190 in the null, about 1/35 to 1/30 with the offset pattern
// alone (var(o) about 14), and about 1/32, 1/24 and 1/14 with both. Each tolerance is at least 6 of them.
int terms_halves(SimResults *results, const unsigned short *lanes, const SimCamera *camera, unsigned long long light,
                 unsigned long long range_numerator, unsigned long long range_denominator,
                 NoiseHalvesMeasurement *measurement)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int ok = noise_halves_volume(lanes, TERMS_EXTENT, measurement, &error) == 0L;
    sim_check(results, ok, "the halves pass read the volume");
    if (ok == 0)
    {
        return 0;
    }
    const unsigned long long pixels = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long unit = (camera->gain_pattern_bits != 0u) ? (1ull << camera->gain_pattern_bits) : 1ull;
    // g S is below 2^10 here. The gained light re-signs exactly
    const long long gained = (long long)(camera->gain * light);
    long long fixed = 0ll;
    long long fixed_square = 0ll;
    for (unsigned long long pixel = 0ull; pixel < pixels; pixel += 1ull)
    {
        // o is at most 12 and p at most 32 in magnitude. F is below 2^15 and its square below 2^30
        const long long own = ((long long)sim_offset_pattern(camera, pixel) * (long long)unit) +
                              (sim_gain_spread(camera, pixel) * gained);
        fixed += own;
        fixed_square += own * own;
    }
    // P sum F^2 and (sum F)^2 are each below 2^59 over 2^14 pixels
    const long long varied = ((long long)pixels * fixed_square) - (fixed * fixed);
    scriptura_text(&results->line, "    the level: ");
    sim_ratio_print(&results->line, &measurement->level, &measurement->level_denominator, 4u);
    scriptura_character(&results->line, '\n');
    terms_ratio_within(results, "  the halves' covariance", &measurement->covariance,
                       &measurement->covariance_denominator, varied, pixels * pixels * unit * unit, range_numerator,
                       range_denominator);
    return 1;
}

// Row 18's intercept and row 19's slope, read as the kcr set is read: the halves' covariance C over the level squared,
// through the two lights S1 and S2, is a line of slope (C2 - C1) / (S2^2 - S1^2) and intercept
// (C1 S2^2 - C2 S1^2) / (S2^2 - S1^2). The plant predicts var(o) and var(p) g^2 / 2^(2b) over the drawn o and p. The
// intercept is 16/15 C1 less 1/15 C2 at lights of 100 and 400, spread about 1/30 with both patterns. Its tolerance of
// 1/5 is 6 of that; the slope's spread is about 5/10^7. Its tolerance of 1/300000 is 6 of that.
void terms_halves_line(SimResults *results, const SimCamera *camera, const NoiseHalvesMeasurement *low,
                       unsigned long long low_light, const NoiseHalvesMeasurement *high, unsigned long long high_light)
{
    const unsigned long long pixels = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long unit = (camera->gain_pattern_bits != 0u) ? (1ull << camera->gain_pattern_bits) : 1ull;
    long long offset = 0ll;
    long long offset_square = 0ll;
    long long spread = 0ll;
    long long spread_square = 0ll;
    for (unsigned long long pixel = 0ull; pixel < pixels; pixel += 1ull)
    {
        // o is at most 12 and p at most 32 in magnitude. Each re-signs and squares exactly
        const long long own_offset = (long long)sim_offset_pattern(camera, pixel);
        const long long own_spread = sim_gain_spread(camera, pixel);
        offset += own_offset;
        offset_square += own_offset * own_offset;
        spread += own_spread;
        spread_square += own_spread * own_spread;
    }
    const long long offset_varied = ((long long)pixels * offset_square) - (offset * offset);
    // g is 1 here. G^2 times P sum p^2 - (sum p)^2 stays below 2^40, and a million times it below 2^60
    const long long spread_varied =
        (((long long)pixels * spread_square) - (spread * spread)) * (long long)(camera->gain * camera->gain);
    // S2^2 - S1^2 is positive, the high light above the low
    const unsigned long long low_square = low_light * low_light;
    const unsigned long long high_square = high_light * high_light;
    AnchorExactInteger cross_low;
    AnchorExactInteger cross_high;
    AnchorExactInteger denominator;
    AnchorExactInteger intercept;
    AnchorExactInteger slope;
    int ok = sim_exact_product(&low->covariance, &high->covariance_denominator, &cross_low) &&
             sim_exact_product(&high->covariance, &low->covariance_denominator, &cross_high) &&
             sim_exact_product(&low->covariance_denominator, &high->covariance_denominator, &denominator) &&
             sim_exact_scaled(&denominator, high_square - low_square, &denominator);
    AnchorExactInteger low_part;
    AnchorExactInteger high_part;
    ok = ok && sim_exact_scaled(&cross_low, high_square, &low_part) &&
         sim_exact_scaled(&cross_high, low_square, &high_part) && sim_exact_less(&low_part, &high_part, &intercept) &&
         sim_exact_less(&cross_high, &cross_low, &slope);
    sim_check(results, ok, "the halves' line through the two lights");
    if (ok == 0)
    {
        return;
    }
    terms_ratio_within(results, "  the halves' intercept, var(o)", &intercept, &denominator, offset_varied,
                       pixels * pixels, 1ull, 5ull);
    // the slope is printed in millionths, where four places show it; its tolerance of 1/300000 is 10/3 millionths
    ok = sim_exact_scaled(&slope, TERMS_MILLION, &slope);
    sim_check(results, ok, "the halves' slope in millionths");
    terms_ratio_within(results, "  the halves' slope in millionths, var(p) g^2 / 2^2b", &slope, &denominator,
                       spread_varied * (long long)TERMS_MILLION, pixels * pixels * unit * unit, 10ull, 3ull);
}

// The clip pass against the plant: spikes at 128 in one voxel-frame of 1024, dips never. At 16 and 32 a symmetric
// shot's null holds its spikes and dips equal within 5 standard errors; a Poisson shot's upper tail is longer than its
// lower. Its null's spikes outnumber its dips by more than 5.
void terms_spikes(SimResults *results, const unsigned short *lanes, unsigned long long spike_denominator,
                  unsigned long long law)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long counts[NOISE_CLIPS_COUNTS];
    unsigned int box[NOISE_CLIPS_BOX];
    unsigned long long spikes[NOISE_SPIKE_SUMS];
    const int ok = noise_clips_volume(lanes, TERMS_EXTENT, counts, box, spikes, &error) == 0L;
    sim_check(results, ok, "the clip pass read the volume");
    if (ok == 0)
    {
        return;
    }
    ScripturaLine *const line = &results->line;
    const unsigned long long triples = spikes[NOISE_SPIKE_TRIPLES];
    scriptura_text(line, "    ");
    scriptura_decimal(line, triples, 1u);
    scriptura_text(line, " triples; spikes and dips at 16, 32, 64, 128:");
    for (unsigned int threshold = 0u; threshold < NOISE_SPIKE_THRESHOLDS; threshold += 1u)
    {
        scriptura_character(line, ' ');
        scriptura_decimal(line, spikes[1u + (2u * threshold)], 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, spikes[2u + (2u * threshold)], 1u);
        scriptura_character(line, ';');
    }
    scriptura_character(line, '\n');
    const unsigned long long top_spikes = spikes[1u + (2u * (NOISE_SPIKE_THRESHOLDS - 1u))];
    const unsigned long long top_dips = spikes[2u + (2u * (NOISE_SPIKE_THRESHOLDS - 1u))];
    sim_check(results, top_dips == 0ull, "no dip clears 128 at a level of 120");
    if (spike_denominator == 0ull)
    {
        sim_check(results, top_spikes == 0ull, "the null holds no spike of 128");
        for (unsigned int threshold = 0u; threshold < 2u; threshold += 1u)
        {
            const unsigned long long raised = spikes[1u + (2u * threshold)];
            const unsigned long long lowered = spikes[2u + (2u * threshold)];
            const unsigned long long apart = (raised > lowered) ? (raised - lowered) : (lowered - raised);
            // counts of a few million: their squares are far below 2^64
            if (law == SIM_SHOT_POISSON)
            {
                sim_check(results, (raised > lowered) && ((apart * apart) > (25ull * (raised + lowered))),
                          "the Poisson null's spikes outnumber its dips by more than 5 standard errors");
            }
            else
            {
                sim_check(results, (apart * apart) <= (25ull * (raised + lowered)),
                          "the null's spikes and dips agree within 5 standard errors");
            }
        }
        return;
    }
    // the spikes at 128 are the planted ones: triples over the denominator, within 5 standard errors
    const unsigned long long scaled = top_spikes * spike_denominator;
    const unsigned long long apart = (scaled > triples) ? (scaled - triples) : (triples - scaled);
    // the difference is below 2^32 and the bound below 2^50 at these sizes
    sim_check(results, (apart * apart) <= (25ull * spike_denominator * triples),
              "the spikes of 128 are the planted rate within 5 standard errors");
}

// the constant boxes: z 3 to 5, y 10 to 29, x 40 to 79 held at 0, and z 7, y 0 to 3, x 0 to 3 held at the top
void terms_boxes(unsigned short *lanes)
{
    const unsigned long long voxels = TERMS_DEPTH * TERMS_HEIGHT * TERMS_WIDTH;
    for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
    {
        for (unsigned long long z = 3ull; z <= 5ull; z += 1ull)
        {
            for (unsigned long long y = 10ull; y <= 29ull; y += 1ull)
            {
                for (unsigned long long x = 40ull; x <= 79ull; x += 1ull)
                {
                    lanes[(frame * voxels) + (((z * TERMS_HEIGHT) + y) * TERMS_WIDTH) + x] = 0u;
                }
            }
        }
        for (unsigned long long y = 0ull; y <= 3ull; y += 1ull)
        {
            for (unsigned long long x = 0ull; x <= 3ull; x += 1ull)
            {
                lanes[(frame * voxels) + (((7ull * TERMS_HEIGHT) + y) * TERMS_WIDTH) + x] = 65535u;
            }
        }
    }
}

void terms_clips(SimResults *results, const unsigned short *lanes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long counts[NOISE_CLIPS_COUNTS];
    unsigned int box[NOISE_CLIPS_BOX];
    unsigned long long spikes[NOISE_SPIKE_SUMS];
    const int ok = noise_clips_volume(lanes, TERMS_EXTENT, counts, box, spikes, &error) == 0L;
    sim_check(results, ok, "the clip pass read the volume");
    if (ok == 0)
    {
        return;
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "    at 0: ");
    scriptura_decimal(line, counts[NOISE_CLIPS_AT_ZERO], 1u);
    scriptura_text(line, ", at the top: ");
    scriptura_decimal(line, counts[NOISE_CLIPS_AT_TOP], 1u);
    scriptura_text(line, "; constant voxels: ");
    scriptura_decimal(line, counts[NOISE_CLIPS_CONSTANT], 1u);
    scriptura_text(line, " (at 0: ");
    scriptura_decimal(line, counts[NOISE_CLIPS_CONSTANT_ZERO], 1u);
    scriptura_text(line, ", at the top: ");
    scriptura_decimal(line, counts[NOISE_CLIPS_CONSTANT_TOP], 1u);
    scriptura_text(line, "), within z ");
    scriptura_decimal(line, box[0], 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, box[1], 1u);
    scriptura_text(line, ", y ");
    scriptura_decimal(line, box[2], 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, box[3], 1u);
    scriptura_text(line, ", x ");
    scriptura_decimal(line, box[4], 1u);
    scriptura_text(line, " to ");
    scriptura_decimal(line, box[5], 1u);
    scriptura_character(line, '\n');
    sim_check(results, counts[NOISE_CLIPS_AT_ZERO] == (TERMS_ZERO_BOX_VOXELS * TERMS_FRAMES),
              "every voxel-frame at 0 is the zero box's");
    sim_check(results, counts[NOISE_CLIPS_AT_TOP] == (TERMS_TOP_BOX_VOXELS * TERMS_FRAMES),
              "every voxel-frame at the top is the top box's");
    sim_check(results, counts[NOISE_CLIPS_CONSTANT] == (TERMS_ZERO_BOX_VOXELS + TERMS_TOP_BOX_VOXELS),
              "the constant voxels are the two boxes'");
    sim_check(results, counts[NOISE_CLIPS_CONSTANT_ZERO] == TERMS_ZERO_BOX_VOXELS, "the zero box is held at 0");
    sim_check(results, counts[NOISE_CLIPS_CONSTANT_TOP] == TERMS_TOP_BOX_VOXELS, "the top box is held at the top");
    sim_check(results,
              (box[0] == 3u) && (box[1] == 7u) && (box[2] == 0u) && (box[3] == 29u) && (box[4] == 0u) &&
                  (box[5] == 79u),
              "the constant voxels' box spans both boxes");
}
