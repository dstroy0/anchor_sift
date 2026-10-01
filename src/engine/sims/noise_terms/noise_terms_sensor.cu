// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_terms_sensor.cu: static columns, ladder, crosstalk, charge and blur
#include "noise_terms_internal.h"

// The static voxels the ladder reads, counted by column along x, where the ladder's scene sets the level: the
// detector's rule (noise_detector_lines.cu:155-234) run again on the host. A voxel that changes, never touches either
// end of the lane and passes the quiet test is eligible; the dimmest quarter of those by their mean over the frames,
// rounded down, is kept, every voxel at or below the highest mean the quarter reaches. The ceiling is that mean.
static int terms_static_columns(const unsigned short *lanes, unsigned long long columns[TERMS_WIDTH],
                                unsigned long long *ceiling)
{
    const unsigned long long voxels = TERMS_DEPTH * TERMS_HEIGHT * TERMS_WIDTH;
    unsigned long long *const totals = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned long long *const squares = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned short *const least = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    unsigned short *const maximum = (unsigned short *)calloc((size_t)voxels, sizeof(unsigned short));
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    unsigned long long *const counted =
        (unsigned long long *)calloc((size_t)TERMS_LANE_VALUES, sizeof(unsigned long long));
    const int ok = (totals != NULL) && (squares != NULL) && (least != NULL) && (maximum != NULL) && (mask != NULL) &&
                   (counted != NULL);
    memset(columns, 0, (size_t)TERMS_WIDTH * sizeof(unsigned long long));
    *ceiling = 0ull;
    if (ok != 0)
    {
        memset(least, 0xFF, (size_t)voxels * sizeof(unsigned short));
        for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
        {
            const unsigned short *const lane = &lanes[frame * voxels];
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                totals[voxel] += lane[voxel];
                least[voxel] = (lane[voxel] < least[voxel]) ? lane[voxel] : least[voxel];
                maximum[voxel] = (lane[voxel] > maximum[voxel]) ? lane[voxel] : maximum[voxel];
                if (frame != 0ull)
                {
                    const unsigned short before = lanes[((frame - 1ull) * voxels) + voxel];
                    const long long moved = (long long)lane[voxel] - (long long)before;
                    // a square is never negative. It re-signs to unsigned long long exactly
                    squares[voxel] += (unsigned long long)(moved * moved);
                }
            }
        }
        unsigned long long eligible = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            const unsigned long long bound = (TERMS_QUIET_SLOPE * totals[voxel]) + (TERMS_QUIET_FLOOR * TERMS_FRAMES);
            const int still = (squares[voxel] * TERMS_FRAMES) <= ((TERMS_FRAMES - 1ull) * bound);
            mask[voxel] = ((least[voxel] != 0u) && (maximum[voxel] != TERMS_LANE_TOP) &&
                           (least[voxel] != maximum[voxel]) && still)
                              ? 1u
                              : 0u;
            if (mask[voxel] != 0u)
            {
                // a mean of values that are each below 2^16 is below 2^16
                counted[totals[voxel] / TERMS_FRAMES] += 1ull;
                eligible += 1ull;
            }
        }
        const unsigned long long wanted = (eligible + TERMS_STATIC_SHARE - 1ull) / TERMS_STATIC_SHARE;
        unsigned long long running = 0ull;
        for (unsigned long long mean = 0ull; (mean < TERMS_LANE_VALUES) && (running < wanted); mean += 1ull)
        {
            running += counted[mean];
            *ceiling = mean;
        }
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            if ((mask[voxel] != 0u) && ((totals[voxel] / TERMS_FRAMES) <= *ceiling))
            {
                columns[voxel % TERMS_WIDTH] += 1ull;
            }
        }
    }
    free(totals);
    free(squares);
    free(least);
    free(maximum);
    free(mask);
    free(counted);
    return ok;
}

// C15 and C19 read back (build plan item 38). A Poisson shot at gain g over a ramp of levels, offset O and read
// variance r^2, no fixed pattern: at a level L = O + g S the cumulants are k2 = g (L - O) + r^2, k3 = g^2 (L - O) and
// k4 = g^3 (L - O) - r^2 / 2. The ladder's slopes are g, g^2 and g^3, the k3 line crosses 0 at O, and the k2 line
// reads r^2 there. A Poisson count holds both checks with equality. The sim prints them and checks neither. The
// reaches are each the smallest fraction of the kind the check uses, fiftieths for s2, quarters for s3, tenths for
// R^2 and whole units for s4 and O, at or above 5 standard errors of the measurement over the static blocks here, the
// quiet static quarter of the view, 19 blocks of 5 frames a voxel, worked over levels 22 to 84; the mask keeps 22 to
// 82. The standard errors, Derived, first order. A frame's shot cumulants 2 to 8 are g^2 S, g^3 S, g^4 S, 0,
// -9 g^6 S, -49 g^7 S and -104 g^8 S (S electrons, each adding 0, 1, 2 or 4 at chances 9, 8, 6 and 1 in 24), the
// read's r^2, 0, -r^2 / 2, 0, r^2, 0 and -17 r^2 / 4. A block of n spreads its k-statistics by var k2 = k4 / n +
// 2 k2^2 / (n - 1), cov(k2, k3) = k5 / n + 6 k2 k3 / (n - 1), var k3 = k6 / n + 9 k2 k4 / (n - 1) + 9 k3^2 / (n - 1)
// + 6 n k2^3 / ((n - 1)(n - 2)) and var k4 = k8 / n + (16 k2 k6 + 48 k3 k5 + 34 k4^2) / (n - 1) + (72 k2^2 k4 +
// 144 k2 k3^2) n / ((n - 1)(n - 2)) + 24 n (n + 1) k2^4 / ((n - 1)(n - 2)(n - 3)) (R. A. Fisher, "Moments and
// product moments of sampling distributions", Proc. London Math. Soc. 30, 1929; M. G. Kendall and A. Stuart, The
// Advanced Theory of Statistics, vol. 1). The static mask keeps the dimmest quarter of the eligible voxels by their
// mean over the frames, and the quiet test leaves out part of the bright columns: the quarter ends at a mean of 77,
// inside column 28 (level 78). The sim prints n_c, the voxels kept in column c, for c = 0 to 30, 116456 in all, and
// checks that their 19 blocks each are the ladder's. Column c holds N_c = 19 n_c blocks at L_c = 22 + 2 c, S = c + 1;
// N = sum N_c, and the blocks' mean level Lbar = 49.46. A slope's variance is sum N_c (L_c - Lbar)^2 var k_j(S_c) /
// (sum N_c (L_c - Lbar)^2)^2. The least-squares weight at O on a block of column c is w_c = 1 / N +
// (O - Lbar)(L_c - Lbar) / sum N_c (L_c - Lbar)^2, O's error is the k3 line's at O over g^2, var O = sum N_c w_c^2
// var k3(S_c) / g^4, and R^2 - r^2 is about e2(O) - e3(O) / g, the two lines' errors at O, a block's share v(S) =
// var k2 - 2 cov(k2, k3) / g + var k3 / g^2, 40 (S + 1)^3 + 32 S^2 - 26.1 S + 3.3 at g = 2 and r^2 = 4. Over the
// printed counts SE(s2) = 0.00225 and the tolerance, 1 / 50, is 8.90 of them; SE(s3) = 0.0526 and 2 / 4 is 9.51;
// SE(s4) = 1.93 and 10 is 5.18; SE(O) = 0.248 and 2 is 8.05; SE(R^2) = 0.487 and 25 / 10 is 5.13. 0 sits 4 / 0.487,
// about 8.2 of them, from r^2 = 4, and a measurement of 0 falls 3.08 of them past the tolerance's edge: the check shows
// the read noise present at that strength, short of 5, and no tolerance gives 5 on both sides with 8.2 between them. s2
// reads 6.6 of its SE below g: x's noise, var k2 / 90, attenuates the slopes by 0.9974, Derived, 2.3 SE of it, and
// the remaining 4.3 SE has the sign of the quiet test's cut; the tolerance of 1/50 holds it. Neglected: x taken as
// fixed, the place noise one voxel's blocks share, and the quiet test and the cut by mean, in columns 15 to 30, taken
// as unrelated to the blocks they keep.
void terms_ladder(SimResults *results, const unsigned short *lanes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseLadderMeasurement measurement;
    const int ok = noise_ladder_volume(lanes, TERMS_EXTENT, &measurement, &error) == 0L;
    sim_check(results, ok, "the ladder read the volume");
    if (ok == 0)
    {
        return;
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "    ");
    scriptura_decimal(line, measurement.blocks, 1u);
    scriptura_text(line, " blocks kept, ");
    scriptura_decimal(line, measurement.left_out, 1u);
    scriptura_text(line, " left out; s3 >= s2^2 ");
    scriptura_text(line, (measurement.rising != 0) ? "holds" : "fails");
    scriptura_text(line, ", s2 s4 >= s3^2 ");
    scriptura_text(line, (measurement.convex != 0) ? "holds" : "fails");
    scriptura_character(line, '\n');
    unsigned long long columns[TERMS_WIDTH];
    unsigned long long ceiling = 0ull;
    const int copied = terms_static_columns(lanes, columns, &ceiling);
    sim_check(results, copied, "the static mask's copy");
    unsigned long long members = 0ull;
    unsigned long long last = 0ull;
    for (unsigned long long x = 0ull; copied && (x < TERMS_WIDTH); x += 1ull)
    {
        members += columns[x];
        last = (columns[x] != 0ull) ? x : last;
    }
    scriptura_text(line, "    the static voxels by column along x from column 0, every mean kept at most ");
    scriptura_decimal(line, ceiling, 1u);
    scriptura_character(line, ':');
    for (unsigned long long x = 0ull; copied && (x <= last); x += 1ull)
    {
        scriptura_character(line, ' ');
        scriptura_decimal(line, columns[x], 1u);
    }
    scriptura_character(line, '\n');
    sim_check(results,
              copied &&
                  ((members * (TERMS_FRAMES / TERMS_MOMENT_BLOCK)) == (measurement.blocks + measurement.left_out)),
              "the copied mask's voxels hold the ladder's blocks, kept and left out");
    const long long gain = TERMS_LADDER_GAIN;
    terms_ratio_within(results, "s2, the k2 line's slope", &measurement.cumulant[0].slope,
                       &measurement.cumulant[0].denominator, gain, 1ull, 1ull, 50ull);
    terms_ratio_within(results, "s3, the k3 line's slope", &measurement.cumulant[1].slope,
                       &measurement.cumulant[1].denominator, gain * gain, 1ull, 2ull, 4ull);
    terms_ratio_within(results, "s4, the k4 line's slope", &measurement.cumulant[2].slope,
                       &measurement.cumulant[2].denominator, gain * gain * gain, 1ull, 10ull, 1ull);
    sim_check(results, measurement.tail != 0, "the k3 line has a slope, so the tail reads");
    if (measurement.tail == 0)
    {
        return;
    }
    // the offset and the read variance are each far below 2^31
    terms_ratio_within(results, "O, where the k3 line crosses 0", &measurement.offset, &measurement.offset_denominator,
                       (long long)TERMS_OFFSET, 1ull, 2ull, 1ull);
    terms_ratio_within(results, "R^2, the k2 line at O", &measurement.read_square, &measurement.read_square_denominator,
                       (long long)TERMS_READ_SQUARE, 1ull, 25ull, 10ull);
}

// crosstalk along x: every voxel takes alpha = TERMS_CROSSTALK_EIGHTHS / 8 of each x neighbor's value after the
// draw, rounded to the nearest, read from a copy so each mixes unmixed values; the first and last columns take their
// one neighbor
void terms_crosstalk_mix(unsigned short *lanes, const unsigned short *drawn)
{
    const unsigned long long rows = TERMS_FRAMES * TERMS_DEPTH * TERMS_HEIGHT;
    for (unsigned long long row = 0ull; row < rows; row += 1ull)
    {
        const unsigned short *const from = &drawn[row * TERMS_WIDTH];
        unsigned short *const into = &lanes[row * TERMS_WIDTH];
        for (unsigned long long x = 0ull; x < TERMS_WIDTH; x += 1ull)
        {
            const unsigned long long left = (x != 0ull) ? from[x - 1ull] : 0ull;
            const unsigned long long right = ((x + 1ull) < TERMS_WIDTH) ? from[x + 1ull] : 0ull;
            const unsigned long long mixed = from[x] + (((TERMS_CROSSTALK_EIGHTHS * (left + right)) + 4ull) / 8ull);
            // the scene's lanes are near 120. A lane plus a quarter of two more stays far below 65536
            into[x] = (unsigned short)mixed;
        }
    }
}

// C20 read back (build plan item 38): along x, a draw shared by alpha with each neighbor gives alpha = C1 / (2 V),
// alpha^2 = C2 / V and C3 / V = 0; along y nothing is shared. All three read 0. Over M products of frame
// differences, each difference sharing a frame with the next, the null's C1 / (2 V) has a standard error of
// sqrt(3/2) / (2 sqrt(M)) and C2 / V and C3 / V twice that: at M = 95 x 32 x 128 x 125, about 1/11000 and 1/5700.
// Each tolerance is about 11 of them, room for the mix's larger ones.
void terms_crosstalk(SimResults *results, const unsigned short *lanes, unsigned long long along_x_eighths)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseCrosstalkMeasurement measurement;
    const int ok = noise_crosstalk_volume(lanes, TERMS_EXTENT, &measurement, &error) == 0L;
    sim_check(results, ok, "the crosstalk pass read the volume");
    if (ok == 0)
    {
        return;
    }
    const char *const axis_names[NOISE_CROSSTALK_AXES] = {"along y", "along x"};
    for (unsigned int axis = 0u; axis < NOISE_CROSSTALK_AXES; axis += 1u)
    {
        // the planted share is a few eighths, far below 2^31
        const long long eighths = (axis == 1u) ? (long long)along_x_eighths : 0ll;
        scriptura_text(&results->line, "    ");
        scriptura_text(&results->line, axis_names[axis]);
        scriptura_text(&results->line, ", over ");
        scriptura_decimal(&results->line, measurement.pairs[axis], 1u);
        scriptura_text(&results->line, " frame differences\n");
        AnchorExactInteger twice;
        const int doubled = sim_exact_scaled(&measurement.spread[axis], 2ull, &twice);
        sim_check(results, doubled && (measurement.spread[axis].sign > 0), "V is positive");
        if ((doubled == 0) || (measurement.spread[axis].sign <= 0))
        {
            continue;
        }
        // no share reads as 0, not 0/8
        const unsigned long long eighth = (eighths != 0ll) ? 8ull : 1ull;
        terms_ratio_within(results, "  alpha, C1 / (2 V)", &measurement.steps[axis][0], &twice, eighths, eighth, 1ull,
                           1000ull);
        terms_ratio_within(results, "  alpha^2, C2 / V", &measurement.steps[axis][1], &measurement.spread[axis],
                           eighths * eighths, eighth * eighth, 1ull, 500ull);
        terms_ratio_within(results, "  C3 / V", &measurement.steps[axis][2], &measurement.spread[axis], 0ll, 1ull, 1ull,
                           500ull);
    }
}

// C14 read back (build plan item 38). A bias series and a dark series, no light: the bias mean is O, the bias
// E[d^2] / 2 is R^2 + kTC, the dark mean less the bias's is g D dt, the dark E[d^2] / 2 less the bias's is g^2 D dt,
// and their ratio is g. Over 96 frames of 32 x 128 x 128, with a Poisson dark shot, the standard errors at 16 dark
// electrons are about 1/2500 (O), 1/500 (R^2 + kTC), 1/800 (g D dt), 1/55 (g^2 D dt) and 1/1700 (g), and at 32 about
// 1/600, 1/30 and 1/1900 for the last three. Each tolerance is at least 5 of them.
void terms_charge(SimResults *results, const unsigned short *bias, const unsigned short *dark, const SimCamera *camera)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseChargeMeasurement measurement;
    const int ok = noise_charge_series(bias, dark, TERMS_EXTENT, &measurement, &error) == 0L;
    sim_check(results, ok, "the charge pass read the series");
    if (ok == 0)
    {
        return;
    }
    // the offset, variances, gain and dark electrons are each far below 2^31
    const long long gain = (long long)camera->gain;
    const long long dark_electrons = (long long)camera->dark;
    terms_ratio_within(results, "O, the bias mean", &measurement.offset, &measurement.offset_denominator,
                       (long long)camera->offset, 1ull, 1ull, 500ull);
    terms_ratio_within(results, "R^2 + kTC, the bias E[d^2] / 2", &measurement.level_free,
                       &measurement.level_free_denominator, (long long)(camera->read_square + camera->reset_square),
                       1ull, 1ull, 100ull);
    terms_ratio_within(results, "g D dt, the dark mean less the bias's", &measurement.dark_level,
                       &measurement.dark_level_denominator, gain * dark_electrons, 1ull, 1ull, 100ull);
    terms_ratio_within(results, "g^2 D dt, the dark E[d^2] / 2 less the bias's", &measurement.dark_square,
                       &measurement.dark_square_denominator, gain * gain * dark_electrons, 1ull, 1ull, 5ull);
    sim_check(results, measurement.gain_read != 0, "the dark mean differs from the bias's, so g reads");
    if (measurement.gain_read != 0)
    {
        terms_ratio_within(results, "g, their ratio", &measurement.gain, &measurement.gain_denominator, gain, 1ull,
                           1ull, 300ull);
    }
}

// C16 read back (build plan item 38). A lit series against the bias, as C14 reads a dark one: the lit mean less the
// bias's is g q S and the lit E[d^2] / 2 less the bias's is g^2 f' q S. Their ratio is g f'. A count of Fano factor
// f thinned by q holds f' - 1 = q (f - 1), and where the excess follows the thinning, f' = F^2 f at every q. The
// standard error of the ratio is under 1/1000 in every run here. A tolerance of 1/200 is at least 5 of them.
void terms_thinned(SimResults *results, const unsigned short *bias, const unsigned short *lit, long long expected,
                   unsigned long long expected_denominator)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseChargeMeasurement measurement;
    const int ok = noise_charge_series(bias, lit, TERMS_EXTENT, &measurement, &error) == 0L;
    sim_check(results, ok && (measurement.gain_read != 0), "the charge pass read the lit series against the bias");
    if ((ok == 0) || (measurement.gain_read == 0))
    {
        return;
    }
    terms_ratio_within(results, "  g f', the lit ratio", &measurement.gain, &measurement.gain_denominator, expected,
                       expected_denominator, 1ull, 200ull);
}

// Row 16 read back: the light is blurred before the draw. Every column's mean over the frames, z and y is the
// offset, the pattern's column mean and g times the blurred light, within 1/8 of a lane unit, 6 to 8 standard errors
// over its 393,216 voxel-frames at levels 120 to 184; and the kernel moves the planted light by more than 1
// somewhere.
void terms_blur(SimResults *results, const unsigned short *lanes, const SimScene *scene, const SimCamera *camera)
{
    const unsigned long long plane = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long voxels = TERMS_DEPTH * plane;
    const unsigned long long samples = TERMS_FRAMES * TERMS_DEPTH * TERMS_HEIGHT;
    unsigned long long worst = 0ull;
    unsigned long long moved = 0ull;
    for (unsigned long long x = 0ull; x < TERMS_WIDTH; x += 1ull)
    {
        // a column index is far below 2^63
        const long long place[SIM_AXES] = {0ll, 0ll, (long long)x};
        const unsigned long long light = sim_light(scene, camera, 0ull, place);
        const unsigned long long planted = sim_signal(scene, 0ull, place);
        const unsigned long long shift = (light > planted) ? (light - planted) : (planted - light);
        moved = (shift > moved) ? shift : moved;
        unsigned long long pattern = 0ull;
        unsigned long long total = 0ull;
        for (unsigned long long z = 0ull; z < TERMS_DEPTH; z += 1ull)
        {
            for (unsigned long long y = 0ull; y < TERMS_HEIGHT; y += 1ull)
            {
                const unsigned long long voxel = (((z * TERMS_HEIGHT) + y) * TERMS_WIDTH) + x;
                pattern += sim_pattern(camera, voxel);
                for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
                {
                    total += lanes[(frame * voxels) + voxel];
                }
            }
        }
        const unsigned long long expected =
            (samples * (camera->offset + (camera->gain * light))) + (TERMS_FRAMES * pattern);
        const unsigned long long apart = (total > expected) ? (total - expected) : (expected - total);
        worst = (apart > worst) ? apart : worst;
    }
    scriptura_text(&results->line, "    the worst column's mean less the blurred light's: ");
    sim_fraction_print(&results->line, worst, samples, 4u);
    scriptura_text(&results->line, " lane units; the kernel moves the planted light by up to ");
    scriptura_decimal(&results->line, moved, 1u);
    scriptura_text(&results->line, " electrons\n");
    sim_check(results, (8ull * worst) <= samples, "every column's mean is the blurred light's within 1/8");
    sim_check(results, moved > 1ull, "the kernel moves the planted light by more than 1 somewhere");
}
