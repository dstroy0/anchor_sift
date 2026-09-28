// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim_camera.h"

#include "noise_detector.h"

#define TERMS_KEY 0x5445524D53ull

// 96 frames of 32 x 128 x 128: the structure function's lag 64 keeps 32 pairs a voxel
#define TERMS_FRAMES 96ull

#define TERMS_DEPTH 32ull

#define TERMS_HEIGHT 128ull

#define TERMS_WIDTH 128ull

// every reading pools at one level: an offset of 20 and 100 electrons at gain 1, inside the means 40 to 199
#define TERMS_OFFSET 20ull

#define TERMS_BACKGROUND 100ull

#define TERMS_READ_SQUARE 4ull

#define TERMS_PATTERN_REACH 8ull

// a value's independent variance: the shot's S g^2 and the read's r^2, 104 lane units squared
#define TERMS_VALUE_SQUARE (TERMS_BACKGROUND + TERMS_READ_SQUARE)

// the shared offsets planted, each of variance 4 a frame
#define TERMS_SHARED_SQUARE 4ull

// flicker: octaves 0 to 5, each of variance 16, held 1 to 32 frames
#define TERMS_FLICKER_SQUARE 16ull

#define TERMS_FLICKER_OCTAVES 6u

// spikes of 256 electrons at one voxel-frame in 1024
#define TERMS_SPIKE_DENOMINATOR 1024ull

#define TERMS_SPIKE_ELECTRONS 256ull

// z mixing: each plane but the first takes 1/8 of the plane before it, the way an interpolation along z would
#define TERMS_MIX_EIGHTHS 1ull

// the constant boxes: one held at 0 and one at the lane's top
#define TERMS_ZERO_BOX_VOXELS (3ull * 20ull * 40ull)

#define TERMS_TOP_BOX_VOXELS (1ull * 4ull * 4ull)

// the reaches: the whole-plane ratios within 2.5% (rows, columns) and 15% (the plane) of what the plant predicts. Each
// frame difference shares a frame with the next, so a ratio read over K lines spreads by about sqrt(3/K) of itself:
// the rows and columns at about 9.6 standard errors planted and 12.6 in the null, the plane at 5.7 in the null and
// 4.8 planted, over its 3040 planes
#define TERMS_LINE_PARTS 25ll

#define TERMS_PLANE_PARTS 150ll

// the shot laws are read at 16 electrons, where the moment pass holds a block's fourth cumulant to about 1.4 lane units
// to the fourth over the static blocks, and third to about 0.1
#define TERMS_SHOT_BACKGROUND 16ull

// the ladder's scene: 1 electron plus 1 a column along x, read at gain 2
#define TERMS_LADDER_BACKGROUND 1ull

#define TERMS_LADDER_RAMP 1ull

#define TERMS_LADDER_GAIN 2ll

// the noise detector's static mask, copied to count its voxels by column: the quiet test's slope and floor
// (noise_detector.cu:557-559), the dimmest share (:403), the lane's top (:38) and values (:40), and the moment pass's
// block of frames (:2071)
#define TERMS_QUIET_SLOPE 4ull

#define TERMS_QUIET_FLOOR 32ull

#define TERMS_STATIC_SHARE 4ull

#define TERMS_LANE_TOP 65535u

#define TERMS_LANE_VALUES 65536ull

#define TERMS_MOMENT_BLOCK 5ull

// crosstalk along x: 1/8 of each neighbour's value after the draw
#define TERMS_CROSSTALK_EIGHTHS 1ull

// charge before the gain: no light, gain 2, a reset variance of 4 beside the read's 4, and 16 dark electrons a frame
// at the first exposure, 32 at the second, twice as long
#define TERMS_CHARGE_GAIN 2ull

#define TERMS_RESET_SQUARE 4ull

#define TERMS_DARK 16ull

#define TERMS_EXPOSURES 2ull

// thinning: 64 electrons of light, each counted electron kept with chance a / 4 for a from 1 to 4
#define TERMS_THIN_LIGHT 64ull

#define TERMS_THIN_BITS 2u

#define TERMS_THIN_STEPS 4ull

// optical crosstalk: (1, 2, 1) / 4 along x over a plant along x of period 16 and amplitude 64
#define TERMS_BLUR_EIGHTHS 2ull

#define TERMS_BLUR_PERIOD 16ull

#define TERMS_BLUR_AMPLITUDE 64ull

#define TERMS_BLUR_KEY 0x424C5552ull

// the structure function against the shared scale: a plant along x over the whole width, 60 to 180 electrons, and a
// scale of 4 octaves of variance 1024 over 2^10, about 1 +- 6%
#define TERMS_STRUCTURE_BACKGROUND 60ull

#define TERMS_STRUCTURE_AMPLITUDE 120ull

#define TERMS_STRUCTURE_KEY 0x5354525543ull

#define TERMS_SCALE_SQUARE 1024ull

#define TERMS_SCALE_OCTAVES 4u

#define TERMS_SCALE_BITS 10u

// the gain pattern: flat lights of 100, 200 and 400 electrons, each pixel's gain (1024 + p) / 1024, p in [-32, 32]
#define TERMS_GAIN_PATTERN_REACH 32ull

#define TERMS_GAIN_PATTERN_BITS 10u

#define TERMS_FLAT_LIGHTS 3u

static const unsigned long long TERMS_FLAT_LIGHT[TERMS_FLAT_LIGHTS] = {100ull, 200ull, 400ull};

// the offset pattern (DSNU): each pixel's offset in [0, 12], var(o) about 14 lane units squared
#define TERMS_OFFSET_PATTERN_REACH 12ull

#define TERMS_MILLION 1000000ull

// the halves' four cameras: the null, the gain pattern, the offset pattern, and both
#define TERMS_HALVES_CAMERAS 4u

// the halves' covariance's reaches at each light for each camera, in lane units squared
static const unsigned long long TERMS_FLAT_REACH[TERMS_HALVES_CAMERAS][TERMS_FLAT_LIGHTS][2] = {
    {{1ull, 30ull}, {1ull, 30ull}, {1ull, 30ull}},
    {{1ull, 10ull}, {1ull, 5ull}, {2ull, 5ull}},
    {{1ull, 5ull}, {1ull, 5ull}, {1ull, 5ull}},
    {{1ull, 5ull}, {1ull, 4ull}, {1ull, 2ull}}};

static const unsigned long long TERMS_EXTENT[4] = {TERMS_FRAMES, TERMS_DEPTH, TERMS_HEIGHT, TERMS_WIDTH};

static void terms_within(SimTally *tally, const char *what, long long read, long long expected, long long reach)
{
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "    ");
    scriptura_text(line, what);
    scriptura_text(line, ": read ");
    scriptura_signed(line, read);
    scriptura_text(line, ", the plant predicts ");
    scriptura_signed(line, expected);
    scriptura_text(line, " within ");
    scriptura_signed(line, reach);
    scriptura_character(line, '\n');
    const long long apart = (read > expected) ? (read - expected) : (expected - read);
    sim_check(tally, apart <= reach, what);
}

static void terms_camera(SimCamera *camera)
{
    memset(camera, 0, sizeof(*camera));
    camera->key = TERMS_KEY;
    camera->offset = TERMS_OFFSET;
    camera->gain = 1ull;
    camera->read_square = TERMS_READ_SQUARE;
    camera->pattern_reach = TERMS_PATTERN_REACH;
    camera->shot = SIM_SHOT_POISSON;
}

static int terms_render(SimTally *tally, const SimScene *scene, const SimCamera *camera, unsigned short *device_lanes,
                        unsigned short *lanes, unsigned long long count)
{
    unsigned long long clipped = 0ull;
    const int good = sim_render(tally, scene, camera, device_lanes, NULL, NULL, &clipped)
                  && sim_took(tally, cudaMemcpy(lanes, device_lanes, count * sizeof(unsigned short),
                                                cudaMemcpyDeviceToHost),
                              "lanes read");
    sim_check(tally, good && (clipped == 0ull), "the scene rendered with no lane clipped");
    return good && (clipped == 0ull);
}

// The lines' eight readings against what the planted row, column and plane variances predict. Each offset of
// variance v a frame puts 2 v into the frame difference, whose independent variance is 2 V: the whole-plane ratios
// read 1000 + 1000 L v / V, L the voxels sharing it, and the static readings 1000 v / V.
static void terms_lines(SimTally *tally, const unsigned short *lanes, unsigned long long row_square,
                        unsigned long long column_square, unsigned long long plane_square)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long readings[NOISE_PLANE_READINGS];
    const int good = noise_lines_volume(lanes, TERMS_EXTENT, readings, &error) == 0L;
    sim_check(tally, good, "the lines read the volume");
    if (good == 0)
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
    const long long reach[NOISE_PLANE_READINGS] = {10ll + ((rows * TERMS_LINE_PARTS) / 1000ll),
                                                   10ll + ((columns * TERMS_LINE_PARTS) / 1000ll),
                                                   30ll + ((plane * TERMS_PLANE_PARTS) / 1000ll),
                                                   2ll,
                                                   3ll,
                                                   3ll,
                                                   6ll,
                                                   1000ll};
    const char *const said[NOISE_PLANE_READINGS] = {
        "whole planes, rows per mille",       "whole planes, columns per mille",
        "whole planes, the plane per mille",  "whole planes, the independent part",
        "static, var_row / s per mille",      "static, var_col / s per mille",
        "static, var_plane / s per mille",    "static, s in thousandths"};
    for (unsigned int reading = 0u; reading < NOISE_PLANE_READINGS; reading += 1u)
    {
        terms_within(tally, said[reading], readings[reading], expected[reading], reach[reading]);
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

// The structure function's readings against the plant. At lag k over n_k pairs, the frame difference's mean square
// is 2 V plus, for each octave, 2 f times the share of pairs whose block changes; so D(k) n_k is proportional to
// V n_k + f C(k), C(k) counting the pairs that cross a block over every octave. Both routes read the same ratio.
static void terms_flicker(SimTally *tally, const unsigned short *lanes, unsigned long long flicker_square,
                          unsigned int octaves)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long per_mille[NOISE_FLICKER_LAGS];
    unsigned long long neighbour_per_mille[NOISE_FLICKER_LAGS];
    const int good = noise_flicker_volume(lanes, TERMS_EXTENT, per_mille, neighbour_per_mille, &error) == 0L;
    sim_check(tally, good, "the flicker pass read the volume");
    if (good == 0)
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
        // each factor is below 2^20 here, so the product is far under 2^63
        const long long expected = (long long)((1000ull * weight[lag] * pairs[0]) / (weight[0] * pairs[lag]));
        scriptura_text(&tally->line, "    ");
        scriptura_text(&tally->line, said[lag]);
        scriptura_character(&tally->line, '\n');
        // a mean square per mille is far below 2^63
        terms_within(tally, "  the frame difference", (long long)per_mille[lag], expected, 10ll);
        terms_within(tally, "  less its x neighbour's", (long long)neighbour_per_mille[lag], expected, 10ll);
    }
}

// The neighbour pass against the plant. A mix of neighbouring planes shares no draw between planes two or more apart,
// so every reach past the first along z reads 0 in the null and in the mix alike.
static void terms_neighbours(SimTally *tally, const unsigned short *lanes, long long expected_z)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long per_mille[NOISE_NEIGHBOUR_REACHES];
    const int good = noise_neighbours_volume(lanes, TERMS_EXTENT, per_mille, &error) == 0L;
    sim_check(tally, good, "the neighbour pass read the volume");
    if (good == 0)
    {
        return;
    }
    terms_within(tally, "z neighbour, per mille", per_mille[0], expected_z, 6ll);
    terms_within(tally, "y neighbour, per mille", per_mille[1], 0ll, 5ll);
    terms_within(tally, "x neighbour, per mille", per_mille[2], 0ll, 5ll);
    const char *const said[NOISE_NEIGHBOUR_REACHES - ENGINE_AXES] = {
        "2 planes on along z, per mille", "4 planes on along z, per mille", "8 planes on along z, per mille",
        "16 planes on along z, per mille", "32 planes on along z, per mille"};
    for (unsigned int reach = ENGINE_AXES; reach < NOISE_NEIGHBOUR_REACHES; reach += 1u)
    {
        terms_within(tally, said[reach - ENGINE_AXES], per_mille[reach], 0ll, 5ll);
    }
}

// The shot law read back by the moment pass. At S electrons with the read draw's variance r^2 (symmetric: third
// cumulant 0, fourth -r^2/2), a Poisson shot gives k2 = S + r^2, k3 = S and k4 = S - r^2/2, and the symmetric shot
// gives k2 = S + r^2, k3 = 0 and k4 = -S/2 - r^2/2. Each reach is about 5 standard errors of the mean over the static
// blocks of 5 frames.
static void terms_shot_law(SimTally *tally, const unsigned short *lanes, unsigned long long law)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    long long cumulants[NOISE_MOMENT_CUMULANTS];
    const int good = noise_moments_volume(lanes, TERMS_EXTENT, cumulants, &error) == 0L;
    sim_check(tally, good, "the moment pass read the volume");
    if (good == 0)
    {
        return;
    }
    // the scene's electrons and the read variance are each far below 2^31
    const long long shot = (long long)TERMS_SHOT_BACKGROUND;
    const long long read = (long long)TERMS_READ_SQUARE;
    const int poisson = law == SIM_SHOT_POISSON;
    const long long expected[NOISE_MOMENT_CUMULANTS] = {
        1000ll * (shot + read), poisson ? (1000ll * shot) : 0ll,
        poisson ? ((1000ll * shot) - (500ll * read)) : ((-500ll * shot) - (500ll * read))};
    const long long reach[NOISE_MOMENT_CUMULANTS] = {100ll, 500ll, 7000ll};
    const char *const said[NOISE_MOMENT_CUMULANTS] = {"the second cumulant, thousandths",
                                                      "the third cumulant, thousandths",
                                                      "the fourth cumulant, thousandths"};
    for (unsigned int order = 0u; order < NOISE_MOMENT_CUMULANTS; order += 1u)
    {
        terms_within(tally, said[order], cumulants[order], expected[order], reach[order]);
    }
}

// numerator / denominator, the denominator positive, within reach_numerator / reach_denominator of expected_numerator
// / expected_denominator: the difference cross-multiplied, |numerator ed rd - en denominator rd| against rn
// denominator ed
static void terms_ratio_within(SimTally *tally, const char *what, const AnchorExactInteger *numerator,
                               const AnchorExactInteger *denominator, long long expected_numerator,
                               unsigned long long expected_denominator, unsigned long long reach_numerator,
                               unsigned long long reach_denominator)
{
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "    ");
    scriptura_text(line, what);
    scriptura_text(line, ": read ");
    sim_ratio_print(line, numerator, denominator, 4u);
    scriptura_text(line, ", the plant predicts ");
    // printed in lowest terms: a magnitude below 2^63 re-signs exactly
    unsigned long long common = (expected_numerator < 0ll) ? (unsigned long long)(-expected_numerator)
                                                          : (unsigned long long)expected_numerator;
    unsigned long long other = expected_denominator;
    while (other != 0ull)
    {
        const unsigned long long rest = common % other;
        common = other;
        other = rest;
    }
    common = (common == 0ull) ? 1ull : common;
    // the common factor divides the numerator's magnitude, so the quotient keeps its sign and range
    scriptura_signed(line, expected_numerator / (long long)common);
    if ((expected_denominator / common) != 1ull)
    {
        scriptura_character(line, '/');
        scriptura_decimal(line, expected_denominator / common, 1u);
    }
    scriptura_text(line, " within ");
    scriptura_decimal(line, reach_numerator, 1u);
    if (reach_denominator != 1ull)
    {
        scriptura_character(line, '/');
        scriptura_decimal(line, reach_denominator, 1u);
    }
    scriptura_character(line, '\n');
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger term;
    sim_exact_signed(&term, expected_numerator);
    int good = sim_exact_scaled(numerator, expected_denominator, &left)
            && sim_exact_scaled(&left, reach_denominator, &left) && sim_exact_product(&term, denominator, &right)
            && sim_exact_scaled(&right, reach_denominator, &right) && sim_exact_less(&left, &right, &left);
    left.sign = (left.sign < 0) ? 1 : left.sign;
    good = good && sim_exact_scaled(denominator, reach_numerator, &right)
        && sim_exact_scaled(&right, expected_denominator, &right) && (anchor_exact_compare(&left, &right) <= 0);
    sim_check(tally, good, what);
}

// The static voxels the ladder reads, counted by column along x, where the ladder's scene sets the level: the
// detector's rule (noise_detector.cu:553-632) run again on the host. A voxel that changes, never touches either end of
// the lane and passes the quiet test is eligible; the dimmest quarter of those by their mean over the frames, rounded
// down, is kept, every voxel at or below the highest mean the quarter reaches. The ceiling is that mean.
static int terms_static_columns(const unsigned short *lanes, unsigned long long columns[TERMS_WIDTH],
                                unsigned long long *ceiling)
{
    const unsigned long long voxels = TERMS_DEPTH * TERMS_HEIGHT * TERMS_WIDTH;
    unsigned long long *const totals = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned long long *const squares = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned short *const least = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    unsigned short *const most = (unsigned short *)calloc((size_t)voxels, sizeof(unsigned short));
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    unsigned long long *const counted = (unsigned long long *)calloc((size_t)TERMS_LANE_VALUES,
                                                                     sizeof(unsigned long long));
    const int good = (totals != NULL) && (squares != NULL) && (least != NULL) && (most != NULL) && (mask != NULL)
                  && (counted != NULL);
    memset(columns, 0, (size_t)TERMS_WIDTH * sizeof(unsigned long long));
    *ceiling = 0ull;
    if (good != 0)
    {
        memset(least, 0xFF, (size_t)voxels * sizeof(unsigned short));
        for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
        {
            const unsigned short *const lane = &lanes[frame * voxels];
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                totals[voxel] += lane[voxel];
                least[voxel] = (lane[voxel] < least[voxel]) ? lane[voxel] : least[voxel];
                most[voxel] = (lane[voxel] > most[voxel]) ? lane[voxel] : most[voxel];
                if (frame != 0ull)
                {
                    const unsigned short before = lanes[((frame - 1ull) * voxels) + voxel];
                    const long long moved = (long long)lane[voxel] - (long long)before;
                    // a square is never negative, so it re-signs to unsigned long long exactly
                    squares[voxel] += (unsigned long long)(moved * moved);
                }
            }
        }
        unsigned long long eligible = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            const unsigned long long bound = (TERMS_QUIET_SLOPE * totals[voxel]) + (TERMS_QUIET_FLOOR * TERMS_FRAMES);
            const int still = (squares[voxel] * TERMS_FRAMES) <= ((TERMS_FRAMES - 1ull) * bound);
            mask[voxel] = ((least[voxel] != 0u) && (most[voxel] != TERMS_LANE_TOP) && (least[voxel] != most[voxel])
                           && still)
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
    free(most);
    free(mask);
    free(counted);
    return good;
}

// C15 and C19 read back (build plan item 38). A Poisson shot at gain g over a ramp of levels, offset O and read
// variance r^2, no fixed pattern: at a level L = O + g S the cumulants are k2 = g (L - O) + r^2, k3 = g^2 (L - O) and
// k4 = g^3 (L - O) - r^2 / 2, so the ladder's slopes are g, g^2 and g^3, the k3 line crosses 0 at O, and the k2 line
// reads r^2 there. A Poisson count holds both checks with equality, so the sim prints them and checks neither. The
// reaches are each the smallest fraction of the kind the check uses, fiftieths for s2, quarters for s3, tenths for
// R^2 and whole units for s4 and O, at or above 5 standard errors of the reading over the static blocks here, the
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
// printed counts SE(s2) = 0.00225 and the reach, 1 / 50, is 8.90 of them; SE(s3) = 0.0526 and 2 / 4 is 9.51;
// SE(s4) = 1.93 and 10 is 5.18; SE(O) = 0.248 and 2 is 8.05; SE(R^2) = 0.487 and 25 / 10 is 5.13. 0 sits 4 / 0.487,
// about 8.2 of them, from r^2 = 4, and a reading of 0 falls 3.08 of them past the reach's edge: the check shows the
// read noise present at that strength, short of 5, and no reach gives 5 on both sides with 8.2 between them. s2
// reads 6.6 of its SE below g: x's noise, var k2 / 90, attenuates the slopes by 0.9974, Derived, 2.3 SE of it, and
// the remaining 4.3 SE has the sign of the quiet test's cut; the reach of 1/50 holds it. Neglected: x taken as
// fixed, the place noise one voxel's blocks share, and the quiet test and the cut by mean, in columns 15 to 30, taken
// as unrelated to the blocks they keep.
static void terms_ladder(SimTally *tally, const unsigned short *lanes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseLadderReading reading;
    const int good = noise_ladder_volume(lanes, TERMS_EXTENT, &reading, &error) == 0L;
    sim_check(tally, good, "the ladder read the volume");
    if (good == 0)
    {
        return;
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "    ");
    scriptura_decimal(line, reading.blocks, 1u);
    scriptura_text(line, " blocks kept, ");
    scriptura_decimal(line, reading.left_out, 1u);
    scriptura_text(line, " left out; s3 >= s2^2 ");
    scriptura_text(line, (reading.rising != 0) ? "holds" : "fails");
    scriptura_text(line, ", s2 s4 >= s3^2 ");
    scriptura_text(line, (reading.convex != 0) ? "holds" : "fails");
    scriptura_character(line, '\n');
    unsigned long long columns[TERMS_WIDTH];
    unsigned long long ceiling = 0ull;
    const int copied = terms_static_columns(lanes, columns, &ceiling);
    sim_check(tally, copied, "the static mask's copy");
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
    sim_check(tally, copied && ((members * (TERMS_FRAMES / TERMS_MOMENT_BLOCK)) == (reading.blocks + reading.left_out)),
              "the copied mask's voxels hold the ladder's blocks, kept and left out");
    const long long gain = TERMS_LADDER_GAIN;
    terms_ratio_within(tally, "s2, the k2 line's slope", &reading.cumulant[0].slope, &reading.cumulant[0].denominator,
                       gain, 1ull, 1ull, 50ull);
    terms_ratio_within(tally, "s3, the k3 line's slope", &reading.cumulant[1].slope, &reading.cumulant[1].denominator,
                       gain * gain, 1ull, 2ull, 4ull);
    terms_ratio_within(tally, "s4, the k4 line's slope", &reading.cumulant[2].slope, &reading.cumulant[2].denominator,
                       gain * gain * gain, 1ull, 10ull, 1ull);
    sim_check(tally, reading.tail != 0, "the k3 line has a slope, so the tail reads");
    if (reading.tail == 0)
    {
        return;
    }
    // the offset and the read variance are each far below 2^31
    terms_ratio_within(tally, "O, where the k3 line crosses 0", &reading.offset, &reading.offset_denominator,
                       (long long)TERMS_OFFSET, 1ull, 2ull, 1ull);
    terms_ratio_within(tally, "R^2, the k2 line at O", &reading.read_square, &reading.read_square_denominator,
                       (long long)TERMS_READ_SQUARE, 1ull, 25ull, 10ull);
}

// crosstalk along x: every voxel takes alpha = TERMS_CROSSTALK_EIGHTHS / 8 of each x neighbour's value after the
// draw, rounded to the nearest, read from a copy so each mixes unmixed values; the first and last columns take their
// one neighbour
static void terms_crosstalk_mix(unsigned short *lanes, const unsigned short *drawn)
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
            // the scene's lanes are near 120, so a lane plus a quarter of two more stays far below 65536
            into[x] = (unsigned short)mixed;
        }
    }
}

// C20 read back (build plan item 38): along x, a draw shared by alpha with each neighbour gives alpha = C1 / (2 V),
// alpha^2 = C2 / V and C3 / V = 0; along y nothing is shared, so all three read 0. Over M products of frame
// differences, each difference sharing a frame with the next, the null's C1 / (2 V) has a standard error of
// sqrt(3/2) / (2 sqrt(M)) and C2 / V and C3 / V twice that: at M = 95 x 32 x 128 x 125, about 1/11000 and 1/5700, so
// each reach is about 11 of them, room for the mix's larger ones.
static void terms_crosstalk(SimTally *tally, const unsigned short *lanes, unsigned long long along_x_eighths)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseCrosstalkReading reading;
    const int good = noise_crosstalk_volume(lanes, TERMS_EXTENT, &reading, &error) == 0L;
    sim_check(tally, good, "the crosstalk pass read the volume");
    if (good == 0)
    {
        return;
    }
    const char *const axis_names[NOISE_CROSSTALK_AXES] = {"along y", "along x"};
    for (unsigned int axis = 0u; axis < NOISE_CROSSTALK_AXES; axis += 1u)
    {
        // the planted share is a few eighths, far below 2^31
        const long long eighths = (axis == 1u) ? (long long)along_x_eighths : 0ll;
        scriptura_text(&tally->line, "    ");
        scriptura_text(&tally->line, axis_names[axis]);
        scriptura_text(&tally->line, ", over ");
        scriptura_decimal(&tally->line, reading.pairs[axis], 1u);
        scriptura_text(&tally->line, " frame differences\n");
        AnchorExactInteger twice;
        const int doubled = sim_exact_scaled(&reading.spread[axis], 2ull, &twice);
        sim_check(tally, doubled && (reading.spread[axis].sign > 0), "V is positive");
        if ((doubled == 0) || (reading.spread[axis].sign <= 0))
        {
            continue;
        }
        // no share reads as 0, not 0/8
        const unsigned long long eighth = (eighths != 0ll) ? 8ull : 1ull;
        terms_ratio_within(tally, "  alpha, C1 / (2 V)", &reading.steps[axis][0], &twice, eighths, eighth, 1ull,
                           1000ull);
        terms_ratio_within(tally, "  alpha^2, C2 / V", &reading.steps[axis][1], &reading.spread[axis],
                           eighths * eighths, eighth * eighth, 1ull, 500ull);
        terms_ratio_within(tally, "  C3 / V", &reading.steps[axis][2], &reading.spread[axis], 0ll, 1ull, 1ull, 500ull);
    }
}

// C14 read back (build plan item 38). A bias series and a dark series, no light: the bias mean is O, the bias
// E[d^2] / 2 is R^2 + kTC, the dark mean less the bias's is g D Δt, the dark E[d^2] / 2 less the bias's is g^2 D Δt,
// and their ratio is g. Over 96 frames of 32 x 128 x 128, with a Poisson dark shot, the standard errors at 16 dark
// electrons are about 1/2500 (O), 1/500 (R^2 + kTC), 1/800 (g D Δt), 1/55 (g^2 D Δt) and 1/1700 (g), and at 32 about
// 1/600, 1/30 and 1/1900 for the last three, so each reach is at least 5 of them.
static void terms_charge(SimTally *tally, const unsigned short *bias, const unsigned short *dark,
                         const SimCamera *camera)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseChargeReading reading;
    const int good = noise_charge_series(bias, dark, TERMS_EXTENT, &reading, &error) == 0L;
    sim_check(tally, good, "the charge pass read the series");
    if (good == 0)
    {
        return;
    }
    // the offset, variances, gain and dark electrons are each far below 2^31
    const long long gain = (long long)camera->gain;
    const long long dark_electrons = (long long)camera->dark;
    terms_ratio_within(tally, "O, the bias mean", &reading.offset, &reading.offset_denominator,
                       (long long)camera->offset, 1ull, 1ull, 500ull);
    terms_ratio_within(tally, "R^2 + kTC, the bias E[d^2] / 2", &reading.level_free, &reading.level_free_denominator,
                       (long long)(camera->read_square + camera->reset_square), 1ull, 1ull, 100ull);
    terms_ratio_within(tally, "g D dt, the dark mean less the bias's", &reading.dark_level,
                       &reading.dark_level_denominator, gain * dark_electrons, 1ull, 1ull, 100ull);
    terms_ratio_within(tally, "g^2 D dt, the dark E[d^2] / 2 less the bias's", &reading.dark_square,
                       &reading.dark_square_denominator, gain * gain * dark_electrons, 1ull, 1ull, 5ull);
    sim_check(tally, reading.gain_read != 0, "the dark mean differs from the bias's, so g reads");
    if (reading.gain_read != 0)
    {
        terms_ratio_within(tally, "g, their ratio", &reading.gain, &reading.gain_denominator, gain, 1ull, 1ull, 300ull);
    }
}

// C16 read back (build plan item 38). A lit series against the bias, as C14 reads a dark one: the lit mean less the
// bias's is g q S and the lit E[d^2] / 2 less the bias's is g^2 f' q S, so their ratio is g f'. A count of Fano factor
// f thinned by q holds f' - 1 = q (f - 1), and where the excess follows the thinning, f' = F^2 f at every q. The
// standard error of the ratio is under 1/1000 in every run here, so a reach of 1/200 is at least 5 of them.
static void terms_thinned(SimTally *tally, const unsigned short *bias, const unsigned short *lit, long long expected,
                          unsigned long long expected_denominator)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    NoiseChargeReading reading;
    const int good = noise_charge_series(bias, lit, TERMS_EXTENT, &reading, &error) == 0L;
    sim_check(tally, good && (reading.gain_read != 0), "the charge pass read the lit series against the bias");
    if ((good == 0) || (reading.gain_read == 0))
    {
        return;
    }
    terms_ratio_within(tally, "  g f', the lit ratio", &reading.gain, &reading.gain_denominator, expected,
                       expected_denominator, 1ull, 200ull);
}

// Row 16 read back: the light is blurred before the draw, so every column's mean over the frames, z and y is the
// offset, the pattern's column mean and g times the blurred light, within 1/8 of a lane unit, 6 to 8 standard errors
// over its 393,216 voxel-frames at levels 120 to 184; and the kernel moves the planted light by more than 1
// somewhere.
static void terms_blur(SimTally *tally, const unsigned short *lanes, const SimScene *scene, const SimCamera *camera)
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
        const unsigned long long expected = (samples * (camera->offset + (camera->gain * light)))
                                          + (TERMS_FRAMES * pattern);
        const unsigned long long apart = (total > expected) ? (total - expected) : (expected - total);
        worst = (apart > worst) ? apart : worst;
    }
    scriptura_text(&tally->line, "    the worst column's mean less the blurred light's: ");
    sim_fraction_print(&tally->line, worst, samples, 4u);
    scriptura_text(&tally->line, " lane units; the kernel moves the planted light by up to ");
    scriptura_decimal(&tally->line, moved, 1u);
    scriptura_text(&tally->line, " electrons\n");
    sim_check(tally, (8ull * worst) <= samples, "every column's mean is the blurred light's within 1/8");
    sim_check(tally, moved > 1ull, "the kernel moves the planted light by more than 1 somewhere");
}

// C17 read back (build plan item 38). The scale moves a pair's d_k - d_{k,x} by (ε_{t+k} - ε_t) g (S - S_x), and
// L - L_x = g (S - S_x)(1 + mean ε), so D_a(k) reads the scale path's mean squared step over (1 + mean ε)^2, from the
// path the camera drew: 10^6 T^2 Σ_t (e_{t+k} - e_t)^2 / ((T - k)(2^b T + Σ_t e_t)^2) in millionths. The intercept
// reads the pairs' own noise, the mean over the pairs in 40 to 199 and their frame pairs of g^2 times the four
// lights plus 4 R^2. The rounded scale adds to it the roundings' own mean square, about 1/3: with rho a light's
// rounding in units of 2^-b, the rounded light times 2^b less the light before the scale times the scale held,
// g^2 (rho(x, t + k) - rho(x, t) - rho(x + 1, t + k) + rho(x + 1, t))^2 / 2^(2b) over the same pairs and frame pairs,
// and the expected value holds that sum exactly. The cross term, 2 g^2 (S - S_x)(e_{t+k} - e_t) times that rounding
// step over 2^(2b), averages to about 0 over the pairs, the roundings spread evenly over their range and unrelated to
// the step they multiply (Derived), and is not held. The slope's standard error, estimated from the plant, is under
// 100 millionths at every lag, so the slope's reach of 500 millionths is at least 5 of them. The intercept's is about
// 0.2, and the reach of 1 keeps its full width, about 5 of them.
static void terms_structure(SimTally *tally, const unsigned short *lanes, const SimScene *scene,
                            const SimCamera *camera)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    // the reading's 28 exact integers are held off the stack
    NoiseStructureReading *const reading = (NoiseStructureReading *)malloc(sizeof(NoiseStructureReading));
    const int good = (reading != NULL) && (noise_structure_volume(lanes, TERMS_EXTENT, reading, &error) == 0L);
    sim_check(tally, good, "the structure pass read the volume");
    unsigned long long *const light = (unsigned long long *)malloc(TERMS_WIDTH * TERMS_FRAMES
                                                                   * sizeof(unsigned long long));
    sim_check(tally, light != NULL, "the lights' table");
    long long *const rounding = (long long *)malloc(TERMS_WIDTH * TERMS_FRAMES * sizeof(long long));
    sim_check(tally, rounding != NULL, "the roundings' table");
    if ((good == 0) || (light == NULL) || (rounding == NULL))
    {
        free(reading);
        free(light);
        free(rounding);
        return;
    }
    // the light at every column and frame, exactly as the camera drew it: the scene has no body, so every z and y of a
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
    long long most = 0ll;
    for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
    {
        path[frame] = (camera->scale_bits != 0u) ? sim_scale(camera, frame) : 0ll;
        path_total += path[frame];
        least = ((frame == 0ull) || (path[frame] < least)) ? path[frame] : least;
        most = ((frame == 0ull) || (path[frame] > most)) ? path[frame] : most;
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
            const long long held = (scale < 1ll) ? 1ll : scale;
            // a light of a few hundred electrons times a unit of 2^10 is far below 2^63
            rounding[(x * TERMS_FRAMES) + frame] = ((long long)light[(x * TERMS_FRAMES) + frame] * unit)
                                                 - ((long long)sim_light(scene, &unscaled, frame, place) * held);
        }
    }
    scriptura_text(&tally->line, "    e_t from ");
    scriptura_signed(&tally->line, least);
    scriptura_text(&tally->line, " to ");
    scriptura_signed(&tally->line, most);
    scriptura_text(&tally->line, ", summing to ");
    scriptura_signed(&tally->line, path_total);
    scriptura_text(&tally->line, " over the frames\n");
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
                own += (gain * gain * (here[frame] + here[frame + apart] + beside[frame] + beside[frame + apart]))
                     + (4ull * camera->read_square);
                // four roundings of at most unit / 2 each: the step is at most 2 unit, its square far below 2^63
                const long long step = here_rounding[frame + apart] - here_rounding[frame]
                                     - beside_rounding[frame + apart] + beside_rounding[frame];
                rounded += gain * gain * (unsigned long long)(step * step);
            }
        }
        scriptura_text(&tally->line, "    ");
        scriptura_text(&tally->line, said[lag]);
        scriptura_text(&tally->line, ", over ");
        scriptura_decimal(&tally->line, reading->pairs[lag], 1u);
        scriptura_text(&tally->line, " frame pairs\n");
        sim_check(tally, reading->read[lag] != 0, "some bin's q spans two values, so the line reads");
        if (reading->read[lag] == 0)
        {
            continue;
        }
        // the unit times the frames, and the path's total, are each far below 2^31
        const long long level = (unit * (long long)TERMS_FRAMES) + path_total;
        // each factor is small here: the product stays far below 2^63, the denominator below 2^64
        const long long expected = (long long)(1000000ull * TERMS_FRAMES * TERMS_FRAMES * steps);
        const unsigned long long expected_denominator = frame_pairs * (unsigned long long)(level * level);
        AnchorExactInteger millionths;
        const int scaled = sim_exact_scaled(&reading->slope[lag], 1000000ull, &millionths);
        sim_check(tally, scaled, "the slope in millionths");
        if (scaled)
        {
            terms_ratio_within(tally, "  D_a(k), millionths", &millionths, &reading->slope_denominator[lag], expected,
                               expected_denominator, 500ull, 1ull);
        }
        // the own noise summed, below 2^24, times unit^2 = 2^20, plus the roundings' sum, below 2^36, is far below
        // 2^63, and the pairs' count times unit^2 below 2^34
        const unsigned long long square_unit = (unsigned long long)(unit * unit);
        terms_ratio_within(tally, "  2 D(k), the pairs' own noise", &reading->intercept[lag],
                           &reading->intercept_denominator[lag], (long long)((own * square_unit) + rounded),
                           included * frame_pairs * square_unit, 1ull, 1ull);
    }
    free(reading);
    free(light);
    free(rounding);
}

// Rows 18 and 19 read back. Under a flat light S a pixel holds f = o + p g S / 2^b in both halves, its offset o and
// its gain's departure p, and the halves' covariance is var(f) over the pixels' drawn f,
// (P Σ F^2 - (Σ F)^2) / (P^2 2^(2b)) with F = o 2^b + p g S: the fixed pattern is drawn per voxel, so no two planes
// share it, and the null reads 0. The pattern and the draws, independent between the halves with variance h^2 in a
// half's mean, spread the reading by sqrt((2 var(f) h^2 + h^4) / P): about 1/70, 1/33 and 1/15 lane units squared at
// the three lights with the gain pattern, 1/260 to 1/190 in the null, about 1/35 to 1/30 with the offset pattern
// alone (var(o) about 14), and about 1/32, 1/24 and 1/14 with both, so each reach is at least 6 of them.
static int terms_halves(SimTally *tally, const unsigned short *lanes, const SimCamera *camera, unsigned long long light,
                        unsigned long long reach_numerator, unsigned long long reach_denominator,
                        NoiseHalvesReading *reading)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int good = noise_halves_volume(lanes, TERMS_EXTENT, reading, &error) == 0L;
    sim_check(tally, good, "the halves pass read the volume");
    if (good == 0)
    {
        return 0;
    }
    const unsigned long long pixels = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long unit = (camera->gain_pattern_bits != 0u) ? (1ull << camera->gain_pattern_bits) : 1ull;
    // g S is below 2^10 here, so the gained light re-signs exactly
    const long long gained = (long long)(camera->gain * light);
    long long fixed = 0ll;
    long long fixed_square = 0ll;
    for (unsigned long long pixel = 0ull; pixel < pixels; pixel += 1ull)
    {
        // o is at most 12 and p at most 32 in magnitude, so F is below 2^15 and its square below 2^30
        const long long own = ((long long)sim_offset_pattern(camera, pixel) * (long long)unit)
                            + (sim_gain_spread(camera, pixel) * gained);
        fixed += own;
        fixed_square += own * own;
    }
    // P Σ F^2 and (Σ F)^2 are each below 2^59 over 2^14 pixels
    const long long varied = ((long long)pixels * fixed_square) - (fixed * fixed);
    scriptura_text(&tally->line, "    the level: ");
    sim_ratio_print(&tally->line, &reading->level, &reading->level_denominator, 4u);
    scriptura_character(&tally->line, '\n');
    terms_ratio_within(tally, "  the halves' covariance", &reading->covariance, &reading->covariance_denominator,
                       varied, pixels * pixels * unit * unit, reach_numerator, reach_denominator);
    return 1;
}

// Row 18's intercept and row 19's slope, read as the kcr set is read: the halves' covariance C over the level squared,
// through the two lights S1 and S2, is a line of slope (C2 - C1) / (S2^2 - S1^2) and intercept
// (C1 S2^2 - C2 S1^2) / (S2^2 - S1^2). The plant predicts var(o) and var(p) g^2 / 2^(2b) over the drawn o and p. The
// intercept is 16/15 C1 less 1/15 C2 at lights of 100 and 400, spread about 1/30 with both patterns, so its reach of
// 1/5 is 6 of that; the slope's spread is about 5/10^7, so its reach of 1/300000 is 6 of that.
static void terms_halves_line(SimTally *tally, const SimCamera *camera, const NoiseHalvesReading *low,
                              unsigned long long low_light, const NoiseHalvesReading *high,
                              unsigned long long high_light)
{
    const unsigned long long pixels = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long unit = (camera->gain_pattern_bits != 0u) ? (1ull << camera->gain_pattern_bits) : 1ull;
    long long offset = 0ll;
    long long offset_square = 0ll;
    long long spread = 0ll;
    long long spread_square = 0ll;
    for (unsigned long long pixel = 0ull; pixel < pixels; pixel += 1ull)
    {
        // o is at most 12 and p at most 32 in magnitude, so each re-signs and squares exactly
        const long long own_offset = (long long)sim_offset_pattern(camera, pixel);
        const long long own_spread = sim_gain_spread(camera, pixel);
        offset += own_offset;
        offset_square += own_offset * own_offset;
        spread += own_spread;
        spread_square += own_spread * own_spread;
    }
    const long long offset_varied = ((long long)pixels * offset_square) - (offset * offset);
    // g is 1 here, so g^2 times P Σ p^2 - (Σ p)^2 stays below 2^40, and a million times it below 2^60
    const long long spread_varied = (((long long)pixels * spread_square) - (spread * spread))
                                  * (long long)(camera->gain * camera->gain);
    // S2^2 - S1^2 is positive, the high light above the low
    const unsigned long long low_square = low_light * low_light;
    const unsigned long long high_square = high_light * high_light;
    AnchorExactInteger cross_low;
    AnchorExactInteger cross_high;
    AnchorExactInteger denominator;
    AnchorExactInteger intercept;
    AnchorExactInteger slope;
    int good = sim_exact_product(&low->covariance, &high->covariance_denominator, &cross_low)
            && sim_exact_product(&high->covariance, &low->covariance_denominator, &cross_high)
            && sim_exact_product(&low->covariance_denominator, &high->covariance_denominator, &denominator)
            && sim_exact_scaled(&denominator, high_square - low_square, &denominator);
    AnchorExactInteger low_part;
    AnchorExactInteger high_part;
    good = good && sim_exact_scaled(&cross_low, high_square, &low_part)
        && sim_exact_scaled(&cross_high, low_square, &high_part) && sim_exact_less(&low_part, &high_part, &intercept)
        && sim_exact_less(&cross_high, &cross_low, &slope);
    sim_check(tally, good, "the halves' line through the two lights");
    if (good == 0)
    {
        return;
    }
    terms_ratio_within(tally, "  the halves' intercept, var(o)", &intercept, &denominator, offset_varied,
                       pixels * pixels, 1ull, 5ull);
    // the slope is printed in millionths, where four places show it; its reach of 1/300000 is 10/3 millionths
    good = sim_exact_scaled(&slope, TERMS_MILLION, &slope);
    sim_check(tally, good, "the halves' slope in millionths");
    terms_ratio_within(tally, "  the halves' slope in millionths, var(p) g^2 / 2^2b", &slope, &denominator,
                       spread_varied * (long long)TERMS_MILLION, pixels * pixels * unit * unit, 10ull, 3ull);
}

// The clip pass against the plant: spikes at 128 in one voxel-frame of 1024, dips never. At 16 and 32 a symmetric
// shot's null holds its spikes and dips equal within 5 standard errors; a Poisson shot's upper tail is longer than its
// lower, so its null's spikes outnumber its dips by more than 5.
static void terms_spikes(SimTally *tally, const unsigned short *lanes, unsigned long long spike_denominator,
                         unsigned long long law)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long counts[NOISE_CLIPS_COUNTS];
    unsigned int box[NOISE_CLIPS_BOX];
    unsigned long long spikes[NOISE_SPIKE_SUMS];
    const int good = noise_clips_volume(lanes, TERMS_EXTENT, counts, box, spikes, &error) == 0L;
    sim_check(tally, good, "the clip pass read the volume");
    if (good == 0)
    {
        return;
    }
    ScripturaLine *const line = &tally->line;
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
    sim_check(tally, top_dips == 0ull, "no dip clears 128 at a level of 120");
    if (spike_denominator == 0ull)
    {
        sim_check(tally, top_spikes == 0ull, "the null holds no spike of 128");
        for (unsigned int threshold = 0u; threshold < 2u; threshold += 1u)
        {
            const unsigned long long raised = spikes[1u + (2u * threshold)];
            const unsigned long long lowered = spikes[2u + (2u * threshold)];
            const unsigned long long apart = (raised > lowered) ? (raised - lowered) : (lowered - raised);
            // counts of a few million: their squares are far below 2^64
            if (law == SIM_SHOT_POISSON)
            {
                sim_check(tally, (raised > lowered) && ((apart * apart) > (25ull * (raised + lowered))),
                          "the Poisson null's spikes outnumber its dips by more than 5 standard errors");
            }
            else
            {
                sim_check(tally, (apart * apart) <= (25ull * (raised + lowered)),
                          "the null's spikes and dips agree within 5 standard errors");
            }
        }
        return;
    }
    // the spikes at 128 are the planted ones: triples over the denominator, within 5 standard errors
    const unsigned long long scaled = top_spikes * spike_denominator;
    const unsigned long long apart = (scaled > triples) ? (scaled - triples) : (triples - scaled);
    // the difference is below 2^32 and the bound below 2^50 at these sizes
    sim_check(tally, (apart * apart) <= (25ull * spike_denominator * triples),
              "the spikes of 128 are the planted rate within 5 standard errors");
}

// the constant boxes: z 3 to 5, y 10 to 29, x 40 to 79 held at 0, and z 7, y 0 to 3, x 0 to 3 held at the top
static void terms_boxes(unsigned short *lanes)
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

static void terms_clips(SimTally *tally, const unsigned short *lanes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned long long counts[NOISE_CLIPS_COUNTS];
    unsigned int box[NOISE_CLIPS_BOX];
    unsigned long long spikes[NOISE_SPIKE_SUMS];
    const int good = noise_clips_volume(lanes, TERMS_EXTENT, counts, box, spikes, &error) == 0L;
    sim_check(tally, good, "the clip pass read the volume");
    if (good == 0)
    {
        return;
    }
    ScripturaLine *const line = &tally->line;
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
    sim_check(tally, counts[NOISE_CLIPS_AT_ZERO] == (TERMS_ZERO_BOX_VOXELS * TERMS_FRAMES),
              "every voxel-frame at 0 is the zero box's");
    sim_check(tally, counts[NOISE_CLIPS_AT_TOP] == (TERMS_TOP_BOX_VOXELS * TERMS_FRAMES),
              "every voxel-frame at the top is the top box's");
    sim_check(tally, counts[NOISE_CLIPS_CONSTANT] == (TERMS_ZERO_BOX_VOXELS + TERMS_TOP_BOX_VOXELS),
              "the constant voxels are the two boxes'");
    sim_check(tally, counts[NOISE_CLIPS_CONSTANT_ZERO] == TERMS_ZERO_BOX_VOXELS, "the zero box is held at 0");
    sim_check(tally, counts[NOISE_CLIPS_CONSTANT_TOP] == TERMS_TOP_BOX_VOXELS, "the top box is held at the top");
    sim_check(tally,
              (box[0] == 3u) && (box[1] == 7u) && (box[2] == 0u) && (box[3] == 29u) && (box[4] == 0u)
                  && (box[5] == 79u),
              "the constant voxels' box spans both boxes");
}

// each plane but the first takes 1/8 of the plane before it, rounded to the nearest, from the top plane down so each
// mixes with an unmixed plane
static void terms_mix(unsigned short *lanes)
{
    const unsigned long long plane = TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long voxels = TERMS_DEPTH * plane;
    for (unsigned long long frame = 0ull; frame < TERMS_FRAMES; frame += 1ull)
    {
        for (unsigned long long z = TERMS_DEPTH - 1ull; z >= 1ull; z -= 1ull)
        {
            for (unsigned long long place = 0ull; place < plane; place += 1ull)
            {
                const unsigned long long here = (frame * voxels) + (z * plane) + place;
                const unsigned long long mixed = (((8ull - TERMS_MIX_EIGHTHS) * lanes[here])
                                                  + (TERMS_MIX_EIGHTHS * lanes[here - plane]) + 4ull)
                                               / 8ull;
                // an eighths-weighted mean of two lanes is itself a lane
                lanes[here] = (unsigned short)mixed;
            }
        }
    }
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    scriptura_text(&tally.line, "  the noise terms, each planted in the camera law and read back by the noise detector"
                                "\n");
    const unsigned long long count = TERMS_FRAMES * TERMS_DEPTH * TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long lane_bytes = count * sizeof(unsigned short);
    // the sim's lanes, the detector's copy of them, and the detector's line sums and mask
    int good = sim_job_submit(&tally, "noise_terms", 0, NULL, (2ull * lane_bytes) + (64ull << 20u));
    unsigned short *const lanes = (unsigned short *)malloc((size_t)lane_bytes);
    unsigned short *device_lanes = NULL;
    good = good && (lanes != NULL)
        && sim_took(&tally, cudaMalloc((void **)&device_lanes, (size_t)lane_bytes), "lanes");
    sim_check(&tally, good, "the scene's buffers");
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = TERMS_FRAMES;
    scene.extent[0] = TERMS_DEPTH;
    scene.extent[1] = TERMS_HEIGHT;
    scene.extent[2] = TERMS_WIDTH;
    scene.background = TERMS_BACKGROUND;
    SimCamera camera;

    if (good)
    {
        scriptura_text(&tally.line, "  the null: shot and read noise and the fixed pattern only\n");
        terms_camera(&camera);
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_lines(&tally, lanes, 0ull, 0ull, 0ull);
            terms_flicker(&tally, lanes, 0ull, 0u);
            terms_neighbours(&tally, lanes, 0ll);
            terms_spikes(&tally, lanes, 0ull, camera.shot);
            sim_flush(&tally);
            scriptura_text(&tally.line, "  the null mixed along z, 1/8 of the plane before (an interpolation's"
                                        " weights): (1/8)(7/8) / ((7/8)^2 + (1/8)^2) = 7/50\n");
            terms_mix(lanes);
            terms_neighbours(&tally, lanes, 140ll);
        }
        sim_flush(&tally);
        scriptura_text(&tally.line, "  the null with a box held at 0 and a box held at the top\n");
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_boxes(lanes);
            terms_clips(&tally, lanes);
        }
        sim_flush(&tally);
    }
    const char *const shared_names[3] = {"  a row offset of variance 4 a frame\n",
                                         "  a column offset of variance 4 a frame\n",
                                         "  a plane offset of variance 4 a frame\n"};
    for (unsigned int shared = 0u; good && (shared < 3u); shared += 1u)
    {
        scriptura_text(&tally.line, shared_names[shared]);
        terms_camera(&camera);
        camera.row_square = (shared == 0u) ? TERMS_SHARED_SQUARE : 0ull;
        camera.column_square = (shared == 1u) ? TERMS_SHARED_SQUARE : 0ull;
        camera.plane_square = (shared == 2u) ? TERMS_SHARED_SQUARE : 0ull;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_lines(&tally, lanes, camera.row_square, camera.column_square, camera.plane_square);
        }
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  flicker: octaves 0 to 5, each of variance 16, held 2^o frames at a voxel\n");
        terms_camera(&camera);
        camera.flicker_square = TERMS_FLICKER_SQUARE;
        camera.flicker_octaves = TERMS_FLICKER_OCTAVES;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_flicker(&tally, lanes, TERMS_FLICKER_SQUARE, TERMS_FLICKER_OCTAVES);
        }
        sim_flush(&tally);
        scriptura_text(&tally.line, "  spikes of 256 electrons at one voxel-frame in 1024\n");
        terms_camera(&camera);
        camera.spike_numerator = 1ull;
        camera.spike_denominator = TERMS_SPIKE_DENOMINATOR;
        camera.spike_electrons = TERMS_SPIKE_ELECTRONS;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_spikes(&tally, lanes, TERMS_SPIKE_DENOMINATOR, camera.shot);
        }
        sim_flush(&tally);
    }
    // each shot law read at 16 electrons by the moment pass, then its null's tails at the scene's 100, and the render's
    // time there, where the laws' draws differ most
    const unsigned long long laws[2] = {SIM_SHOT_SYMMETRIC, SIM_SHOT_POISSON};
    const char *const law_names[2] = {
        "  the symmetric shot, Binomial(4S, 1/2) - S\n",
        "  the Poisson shot: each electron 0, 1, 2 or 4 with chances 9, 8, 6 and 1 in 24, Poisson's first four"
        " cumulants\n"};
    for (unsigned int each = 0u; good && (each < 2u); each += 1u)
    {
        scriptura_text(&tally.line, law_names[each]);
        terms_camera(&camera);
        camera.shot = laws[each];
        scene.background = TERMS_SHOT_BACKGROUND;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_shot_law(&tally, lanes, laws[each]);
        }
        scene.background = TERMS_BACKGROUND;
        unsigned long long clipped = 0ull;
        const unsigned long long began = engine_clock_microseconds();
        const int rendered = sim_render(&tally, &scene, &camera, device_lanes, NULL, NULL, &clipped);
        const unsigned long long spent = engine_clock_microseconds() - began;
        const int copied = rendered
                        && sim_took(&tally, cudaMemcpy(lanes, device_lanes, (size_t)lane_bytes, cudaMemcpyDeviceToHost),
                                    "lanes read");
        if (copied)
        {
            scriptura_text(&tally.line, "    rendered at 100 electrons in ");
            scriptura_decimal(&tally.line, spent, 1u);
            scriptura_text(&tally.line, " microseconds\n");
            terms_spikes(&tally, lanes, 0ull, laws[each]);
        }
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  the ladder and the tail: a Poisson shot at gain 2 over 1 to 128 electrons along x,"
                                    " offset 20, read variance 4, no fixed pattern\n");
        terms_camera(&camera);
        // the gain is a small positive constant
        camera.gain = (unsigned long long)TERMS_LADDER_GAIN;
        camera.pattern_reach = 0ull;
        scene.background = TERMS_LADDER_BACKGROUND;
        scene.ramp = TERMS_LADDER_RAMP;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_ladder(&tally, lanes);
        }
        scene.background = TERMS_BACKGROUND;
        scene.ramp = 0ull;
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  crosstalk read in the null\n");
        terms_camera(&camera);
        unsigned short *const drawn = (unsigned short *)malloc((size_t)lane_bytes);
        sim_check(&tally, drawn != NULL, "the crosstalk copy");
        if ((drawn != NULL) && terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_crosstalk(&tally, lanes, 0ull);
            sim_flush(&tally);
            scriptura_text(&tally.line, "  the null with each voxel taking 1/8 of each x neighbour's value after the draw"
                                        "\n");
            memcpy(drawn, lanes, (size_t)lane_bytes);
            terms_crosstalk_mix(lanes, drawn);
            terms_crosstalk(&tally, lanes, TERMS_CROSSTALK_EIGHTHS);
        }
        free(drawn);
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  charge before the gain: no light, offset 20, gain 2, read variance 4, reset variance"
                                    " 4, a Poisson dark shot; a bias series, then a dark series at 16 and at 32 dark"
                                    " electrons a frame\n");
        // no fixed pattern, so each series draws on its own key as a second series of one camera would
        terms_camera(&camera);
        camera.gain = TERMS_CHARGE_GAIN;
        camera.pattern_reach = 0ull;
        camera.reset_square = TERMS_RESET_SQUARE;
        scene.background = 0ull;
        unsigned short *const bias = (unsigned short *)malloc((size_t)lane_bytes);
        sim_check(&tally, bias != NULL, "the bias series");
        if ((bias != NULL) && terms_render(&tally, &scene, &camera, device_lanes, bias, count))
        {
            for (unsigned long long exposure = 1ull; exposure <= TERMS_EXPOSURES; exposure += 1ull)
            {
                camera.key = TERMS_KEY + exposure;
                camera.dark = exposure * TERMS_DARK;
                scriptura_text(&tally.line, "    ");
                scriptura_decimal(&tally.line, camera.dark, 1u);
                scriptura_text(&tally.line, " dark electrons a frame\n");
                if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
                {
                    terms_charge(&tally, bias, lanes, &camera);
                }
            }
            sim_flush(&tally);
            scriptura_text(&tally.line, "  thinning: 64 electrons of light against the same bias, each counted electron"
                                        " kept with chance q = a/4; g f' = g (1 + q (f - 1))\n");
            camera.dark = 0ull;
            scene.background = TERMS_THIN_LIGHT;
            const unsigned long long thin_laws[3] = {SIM_SHOT_POISSON, SIM_SHOT_HALF, SIM_SHOT_PAIRED};
            // each law's Fano factor, a numerator over a denominator
            const long long fano_numerator[3] = {1ll, 1ll, 2ll};
            const long long fano_denominator[3] = {1ll, 2ll, 1ll};
            const char *const thin_names[3] = {"    the Poisson count, f = 1\n", "    Binomial(2S, 1/2), f = 1/2\n",
                                               "    twice a Poisson count of pairs, f = 2\n"};
            for (unsigned int law = 0u; law < 3u; law += 1u)
            {
                scriptura_text(&tally.line, thin_names[law]);
                camera.shot = thin_laws[law];
                camera.keep_bits = TERMS_THIN_BITS;
                for (unsigned long long keep = 1ull; keep <= TERMS_THIN_STEPS; keep += 1ull)
                {
                    camera.key = TERMS_KEY + (16ull * (law + 1ull)) + keep;
                    camera.keep_numerator = keep;
                    scriptura_text(&tally.line, "    q = ");
                    scriptura_decimal(&tally.line, keep, 1u);
                    scriptura_text(&tally.line, "/4\n");
                    if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
                    {
                        // g (4 d + a (n - d)) / (4 d), each term a few units
                        const long long denominator = 4ll * fano_denominator[law];
                        const long long numerator = (long long)camera.gain
                                                  * (denominator + ((long long)keep
                                                                    * (fano_numerator[law] - fano_denominator[law])));
                        terms_thinned(&tally, bias, lanes, numerator, (unsigned long long)denominator);
                    }
                }
                sim_flush(&tally);
            }
            scriptura_text(&tally.line, "    the Poisson count thinned, then the excess, F^2 = 2: g f' = 2 g at every q\n");
            camera.shot = SIM_SHOT_POISSON;
            camera.excess = 1u;
            for (unsigned long long keep = 1ull; keep <= TERMS_THIN_STEPS; keep += 3ull)
            {
                camera.key = TERMS_KEY + 128ull + keep;
                camera.keep_numerator = keep;
                scriptura_text(&tally.line, "    q = ");
                scriptura_decimal(&tally.line, keep, 1u);
                scriptura_text(&tally.line, "/4\n");
                if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
                {
                    // the gain is a small positive constant
                    terms_thinned(&tally, bias, lanes, 2ll * (long long)camera.gain, 1ull);
                }
            }
        }
        free(bias);
        scene.background = TERMS_BACKGROUND;
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  optical crosstalk: a plant along x of period 16 and amplitude 64 over 100 electrons,"
                                    " blurred by (1, 2, 1)/4 along x before the draw\n");
        terms_camera(&camera);
        camera.blur_eighths = TERMS_BLUR_EIGHTHS;
        scene.plant_axis = 2u;
        scene.plant_period = TERMS_BLUR_PERIOD;
        scene.plant_amplitude = TERMS_BLUR_AMPLITUDE;
        scene.plant_key = TERMS_BLUR_KEY;
        if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
        {
            terms_blur(&tally, lanes, &scene, &camera);
            terms_neighbours(&tally, lanes, 0ll);
            terms_crosstalk(&tally, lanes, 0ull);
        }
        scene.plant_period = 0ull;
        scene.plant_amplitude = 0ull;
        sim_flush(&tally);
    }
    if (good)
    {
        scriptura_text(&tally.line, "  the structure function against the shared scale: a plant along x of 60 to 180"
                                    " electrons, no fixed pattern; the null, then a light scale of 4 octaves of variance"
                                    " 1024 over 2^10, octave o held 2^o frames\n");
        terms_camera(&camera);
        camera.pattern_reach = 0ull;
        scene.background = TERMS_STRUCTURE_BACKGROUND;
        scene.plant_axis = 2u;
        scene.plant_period = TERMS_WIDTH;
        scene.plant_amplitude = TERMS_STRUCTURE_AMPLITUDE;
        scene.plant_key = TERMS_STRUCTURE_KEY;
        for (unsigned int scaled = 0u; scaled < 2u; scaled += 1u)
        {
            scriptura_text(&tally.line, (scaled != 0u) ? "    the scale\n" : "    the null\n");
            camera.scale_square = (scaled != 0u) ? TERMS_SCALE_SQUARE : 0ull;
            camera.scale_octaves = (scaled != 0u) ? TERMS_SCALE_OCTAVES : 0u;
            camera.scale_bits = (scaled != 0u) ? TERMS_SCALE_BITS : 0u;
            if (terms_render(&tally, &scene, &camera, device_lanes, lanes, count))
            {
                terms_structure(&tally, lanes, &scene, &camera);
            }
            sim_flush(&tally);
        }
        scene.background = TERMS_BACKGROUND;
        scene.plant_period = 0ull;
        scene.plant_amplitude = 0ull;
    }
    if (good)
    {
        scriptura_text(&tally.line, "  the gain and offset patterns: flat lights of 100, 200 and 400 electrons, the fixed"
                                    " pattern per voxel; the null, each pixel's gain (1024 + p)/1024, p in [-32, 32],"
                                    " each pixel's offset o in [0, 12], and both\n");
        terms_camera(&camera);
        static const char *const cameras[TERMS_HALVES_CAMERAS] = {"    the null\n", "    the gain pattern\n",
                                                                  "    the offset pattern\n",
                                                                  "    the gain and offset patterns\n"};
        for (unsigned int patterned = 0u; patterned < TERMS_HALVES_CAMERAS; patterned += 1u)
        {
            scriptura_text(&tally.line, cameras[patterned]);
            const int gained = (patterned & 1u) != 0u;
            const int offset = (patterned & 2u) != 0u;
            camera.gain_pattern_reach = gained ? TERMS_GAIN_PATTERN_REACH : 0ull;
            camera.gain_pattern_bits = gained ? TERMS_GAIN_PATTERN_BITS : 0u;
            camera.offset_pattern_reach = offset ? TERMS_OFFSET_PATTERN_REACH : 0ull;
            NoiseHalvesReading readings[TERMS_FLAT_LIGHTS];
            int read = 1;
            for (unsigned int flat = 0u; flat < TERMS_FLAT_LIGHTS; flat += 1u)
            {
                scene.background = TERMS_FLAT_LIGHT[flat];
                read = read && terms_render(&tally, &scene, &camera, device_lanes, lanes, count)
                    && terms_halves(&tally, lanes, &camera, TERMS_FLAT_LIGHT[flat], TERMS_FLAT_REACH[patterned][flat][0],
                                    TERMS_FLAT_REACH[patterned][flat][1], &readings[flat]);
            }
            if (read && (patterned == (TERMS_HALVES_CAMERAS - 1u)))
            {
                terms_halves_line(&tally, &camera, &readings[0], TERMS_FLAT_LIGHT[0],
                                  &readings[TERMS_FLAT_LIGHTS - 1u], TERMS_FLAT_LIGHT[TERMS_FLAT_LIGHTS - 1u]);
            }
            sim_flush(&tally);
        }
        camera.offset_pattern_reach = 0ull;
        scene.background = TERMS_BACKGROUND;
    }
    cudaFree(device_lanes);
    free(lanes);
    return sim_close(&tally, "noise terms");
}
