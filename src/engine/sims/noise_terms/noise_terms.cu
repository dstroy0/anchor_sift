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

// the reaches: the whole-plane ratios within 2.5% (rows, columns) and 15% (the plane) of what the plant predicts,
// each at least 5 standard errors of its reading at these sizes
#define TERMS_LINE_PARTS 25ll

#define TERMS_PLANE_PARTS 150ll

// the shot laws are read at 16 electrons, where the moment pass holds a block's fourth cumulant to about 1.4 lane units
// to the fourth over the static blocks, and third to about 0.1
#define TERMS_SHOT_BACKGROUND 16ull

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
    cudaFree(device_lanes);
    free(lanes);
    return sim_close(&tally, "noise terms");
}
