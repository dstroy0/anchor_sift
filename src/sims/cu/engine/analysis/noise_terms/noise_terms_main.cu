// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_terms_main.cu: the mix and main
#include "noise_terms_internal.h"

static const unsigned long long TERMS_FLAT_LIGHT[TERMS_FLAT_LIGHTS] = {100ull, 200ull, 400ull};

// the halves' covariance's tolerances at each light for each camera, in lane units squared
static const unsigned long long TERMS_FLAT_RANGE[TERMS_HALVES_CAMERAS][TERMS_FLAT_LIGHTS][2] = {
    {{1ull, 30ull}, {1ull, 30ull}, {1ull, 30ull}},
    {{1ull, 10ull}, {1ull, 5ull}, {2ull, 5ull}},
    {{1ull, 5ull}, {1ull, 5ull}, {1ull, 5ull}},
    {{1ull, 5ull}, {1ull, 4ull}, {1ull, 2ull}}};

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
                const unsigned long long mixed =
                    (((8ull - TERMS_MIX_EIGHTHS) * lanes[here]) + (TERMS_MIX_EIGHTHS * lanes[here - plane]) + 4ull) /
                    8ull;
                // an eighths-weighted mean of two lanes is itself a lane
                lanes[here] = (unsigned short)mixed;
            }
        }
    }
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    scriptura_text(&results.line,
                   "  the noise terms, each planted in the camera law and read back by the noise detector"
                   "\n");
    const unsigned long long count = TERMS_FRAMES * TERMS_DEPTH * TERMS_HEIGHT * TERMS_WIDTH;
    const unsigned long long lane_bytes = count * sizeof(unsigned short);
    // the sim's lanes, the detector's copy of them, and the detector's line sums and mask
    int ok = sim_job_submit(&results, "noise_terms", 0, NULL, (2ull * lane_bytes) + (64ull << 20u));
    unsigned short *const lanes = (unsigned short *)malloc((size_t)lane_bytes);
    unsigned short *device_lanes = NULL;
    ok = ok && (lanes != NULL) &&
         sim_status_check(&results, cudaMalloc((void **)&device_lanes, (size_t)lane_bytes), "lanes");
    sim_check(&results, ok, "the scene's buffers");
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = TERMS_FRAMES;
    scene.extent[0] = TERMS_DEPTH;
    scene.extent[1] = TERMS_HEIGHT;
    scene.extent[2] = TERMS_WIDTH;
    scene.background = TERMS_BACKGROUND;
    SimCamera camera;

    if (ok)
    {
        scriptura_text(&results.line, "  the null: shot and read noise and the fixed pattern only\n");
        terms_camera(&camera);
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_lines(&results, lanes, 0ull, 0ull, 0ull);
            terms_flicker(&results, lanes, 0ull, 0u);
            terms_neighbors(&results, lanes, 0ll);
            terms_spikes(&results, lanes, 0ull, camera.shot);
            sim_flush(&results);
            scriptura_text(&results.line, "  the null mixed along z, 1/8 of the plane before (an interpolation's"
                                          " weights): (1/8)(7/8) / ((7/8)^2 + (1/8)^2) = 7/50\n");
            terms_mix(lanes);
            terms_neighbors(&results, lanes, 140ll);
        }
        sim_flush(&results);
        scriptura_text(&results.line, "  the null with a box held at 0 and a box held at the top\n");
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_boxes(lanes);
            terms_clips(&results, lanes);
        }
        sim_flush(&results);
    }
    const char *const shared_names[3] = {"  a row offset of variance 4 a frame\n",
                                         "  a column offset of variance 4 a frame\n",
                                         "  a plane offset of variance 4 a frame\n"};
    for (unsigned int shared = 0u; ok && (shared < 3u); shared += 1u)
    {
        scriptura_text(&results.line, shared_names[shared]);
        terms_camera(&camera);
        camera.row_square = (shared == 0u) ? TERMS_SHARED_SQUARE : 0ull;
        camera.column_square = (shared == 1u) ? TERMS_SHARED_SQUARE : 0ull;
        camera.plane_square = (shared == 2u) ? TERMS_SHARED_SQUARE : 0ull;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_lines(&results, lanes, camera.row_square, camera.column_square, camera.plane_square);
        }
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line, "  flicker: octaves 0 to 5, each of variance 16, held 2^o frames at a voxel\n");
        terms_camera(&camera);
        camera.flicker_square = TERMS_FLICKER_SQUARE;
        camera.flicker_octaves = TERMS_FLICKER_OCTAVES;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_flicker(&results, lanes, TERMS_FLICKER_SQUARE, TERMS_FLICKER_OCTAVES);
        }
        sim_flush(&results);
        scriptura_text(&results.line, "  spikes of 256 electrons at one voxel-frame in 1024\n");
        terms_camera(&camera);
        camera.spike_numerator = 1ull;
        camera.spike_denominator = TERMS_SPIKE_DENOMINATOR;
        camera.spike_electrons = TERMS_SPIKE_ELECTRONS;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_spikes(&results, lanes, TERMS_SPIKE_DENOMINATOR, camera.shot);
        }
        sim_flush(&results);
    }
    // each shot law read at 16 electrons by the moment pass, then its null's tails at the scene's 100, and the render's
    // time there, where the laws' draws differ most
    const unsigned long long laws[2] = {SIM_SHOT_SYMMETRIC, SIM_SHOT_POISSON};
    const char *const law_names[2] = {
        "  the symmetric shot, Binomial(4S, 1/2) - S\n",
        "  the Poisson shot: each electron 0, 1, 2 or 4 with chances 9, 8, 6 and 1 in 24, Poisson's first four"
        " cumulants\n"};
    for (unsigned int each = 0u; ok && (each < 2u); each += 1u)
    {
        scriptura_text(&results.line, law_names[each]);
        terms_camera(&camera);
        camera.shot = laws[each];
        scene.background = TERMS_SHOT_BACKGROUND;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_shot_law(&results, lanes, laws[each]);
        }
        scene.background = TERMS_BACKGROUND;
        unsigned long long clipped = 0ull;
        const unsigned long long began = engine_clock_microseconds();
        const int rendered = sim_render(&results, &scene, &camera, device_lanes, NULL, NULL, &clipped);
        const unsigned long long spent = engine_clock_microseconds() - began;
        const int copied =
            rendered &&
            sim_status_check(&results, cudaMemcpy(lanes, device_lanes, (size_t)lane_bytes, cudaMemcpyDeviceToHost),
                             "lanes read");
        if (copied)
        {
            scriptura_text(&results.line, "    rendered at 100 electrons in ");
            scriptura_decimal(&results.line, spent, 1u);
            scriptura_text(&results.line, " microseconds\n");
            terms_spikes(&results, lanes, 0ull, laws[each]);
        }
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line,
                       "  the ladder and the tail: a Poisson shot at gain 2 over 1 to 128 electrons along x,"
                       " offset 20, read variance 4, no fixed pattern\n");
        terms_camera(&camera);
        // the gain is a small positive constant
        camera.gain = (unsigned long long)TERMS_LADDER_GAIN;
        camera.pattern_range = 0ull;
        scene.background = TERMS_LADDER_BACKGROUND;
        scene.ramp = TERMS_LADDER_RAMP;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_ladder(&results, lanes);
        }
        scene.background = TERMS_BACKGROUND;
        scene.ramp = 0ull;
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line, "  crosstalk read in the null\n");
        terms_camera(&camera);
        unsigned short *const drawn = (unsigned short *)malloc((size_t)lane_bytes);
        sim_check(&results, drawn != NULL, "the crosstalk copy");
        if ((drawn != NULL) && terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_crosstalk(&results, lanes, 0ull);
            sim_flush(&results);
            scriptura_text(&results.line,
                           "  the null with each voxel taking 1/8 of each x neighbor's value after the draw"
                           "\n");
            memcpy(drawn, lanes, (size_t)lane_bytes);
            terms_crosstalk_mix(lanes, drawn);
            terms_crosstalk(&results, lanes, TERMS_CROSSTALK_EIGHTHS);
        }
        free(drawn);
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line,
                       "  charge before the gain: no light, offset 20, gain 2, read variance 4, reset variance"
                       " 4, a Poisson dark shot; a bias series, then a dark series at 16 and at 32 dark"
                       " electrons a frame\n");
        // no fixed pattern. Each series draws on its own key as a second series of one camera would
        terms_camera(&camera);
        camera.gain = TERMS_CHARGE_GAIN;
        camera.pattern_range = 0ull;
        camera.reset_square = TERMS_RESET_SQUARE;
        scene.background = 0ull;
        unsigned short *const bias = (unsigned short *)malloc((size_t)lane_bytes);
        sim_check(&results, bias != NULL, "the bias series");
        if ((bias != NULL) && terms_render(&results, &scene, &camera, device_lanes, bias, count))
        {
            for (unsigned long long exposure = 1ull; exposure <= TERMS_EXPOSURES; exposure += 1ull)
            {
                camera.key = TERMS_KEY + exposure;
                camera.dark = exposure * TERMS_DARK;
                scriptura_text(&results.line, "    ");
                scriptura_decimal(&results.line, camera.dark, 1u);
                scriptura_text(&results.line, " dark electrons a frame\n");
                if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
                {
                    terms_charge(&results, bias, lanes, &camera);
                }
            }
            sim_flush(&results);
            scriptura_text(&results.line,
                           "  thinning: 64 electrons of light against the same bias, each counted electron"
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
                scriptura_text(&results.line, thin_names[law]);
                camera.shot = thin_laws[law];
                camera.keep_bits = TERMS_THIN_BITS;
                for (unsigned long long keep = 1ull; keep <= TERMS_THIN_STEPS; keep += 1ull)
                {
                    camera.key = TERMS_KEY + (16ull * (law + 1ull)) + keep;
                    camera.keep_numerator = keep;
                    scriptura_text(&results.line, "    q = ");
                    scriptura_decimal(&results.line, keep, 1u);
                    scriptura_text(&results.line, "/4\n");
                    if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
                    {
                        // g (4 d + a (n - d)) / (4 d), each term a few units
                        const long long denominator = 4ll * fano_denominator[law];
                        const long long numerator =
                            (long long)camera.gain *
                            (denominator + ((long long)keep * (fano_numerator[law] - fano_denominator[law])));
                        terms_thinned(&results, bias, lanes, numerator, (unsigned long long)denominator);
                    }
                }
                sim_flush(&results);
            }
            scriptura_text(&results.line,
                           "    the Poisson count thinned, then the excess, F^2 = 2: g f' = 2 g at every q\n");
            camera.shot = SIM_SHOT_POISSON;
            camera.excess = 1u;
            for (unsigned long long keep = 1ull; keep <= TERMS_THIN_STEPS; keep += 3ull)
            {
                camera.key = TERMS_KEY + 128ull + keep;
                camera.keep_numerator = keep;
                scriptura_text(&results.line, "    q = ");
                scriptura_decimal(&results.line, keep, 1u);
                scriptura_text(&results.line, "/4\n");
                if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
                {
                    // the gain is a small positive constant
                    terms_thinned(&results, bias, lanes, 2ll * (long long)camera.gain, 1ull);
                }
            }
        }
        free(bias);
        scene.background = TERMS_BACKGROUND;
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line,
                       "  optical crosstalk: a plant along x of period 16 and amplitude 64 over 100 electrons,"
                       " blurred by (1, 2, 1)/4 along x before the draw\n");
        terms_camera(&camera);
        camera.blur_eighths = TERMS_BLUR_EIGHTHS;
        scene.plant_axis = 2u;
        scene.plant_period = TERMS_BLUR_PERIOD;
        scene.plant_amplitude = TERMS_BLUR_AMPLITUDE;
        scene.plant_key = TERMS_BLUR_KEY;
        if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
        {
            terms_blur(&results, lanes, &scene, &camera);
            terms_neighbors(&results, lanes, 0ll);
            terms_crosstalk(&results, lanes, 0ull);
        }
        scene.plant_period = 0ull;
        scene.plant_amplitude = 0ull;
        sim_flush(&results);
    }
    if (ok)
    {
        scriptura_text(&results.line,
                       "  the structure function against the shared scale: a plant along x of 60 to 180"
                       " electrons, no fixed pattern; the null, then a light scale of 4 octaves of variance"
                       " 1024 over 2^10, octave o held 2^o frames\n");
        terms_camera(&camera);
        camera.pattern_range = 0ull;
        scene.background = TERMS_STRUCTURE_BACKGROUND;
        scene.plant_axis = 2u;
        scene.plant_period = TERMS_WIDTH;
        scene.plant_amplitude = TERMS_STRUCTURE_AMPLITUDE;
        scene.plant_key = TERMS_STRUCTURE_KEY;
        for (unsigned int scaled = 0u; scaled < 2u; scaled += 1u)
        {
            scriptura_text(&results.line, (scaled != 0u) ? "    the scale\n" : "    the null\n");
            camera.scale_square = (scaled != 0u) ? TERMS_SCALE_SQUARE : 0ull;
            camera.scale_octaves = (scaled != 0u) ? TERMS_SCALE_OCTAVES : 0u;
            camera.scale_bits = (scaled != 0u) ? TERMS_SCALE_BITS : 0u;
            if (terms_render(&results, &scene, &camera, device_lanes, lanes, count))
            {
                terms_structure(&results, lanes, &scene, &camera);
            }
            sim_flush(&results);
        }
        scene.background = TERMS_BACKGROUND;
        scene.plant_period = 0ull;
        scene.plant_amplitude = 0ull;
    }
    if (ok)
    {
        scriptura_text(&results.line,
                       "  the gain and offset patterns: flat lights of 100, 200 and 400 electrons, the fixed"
                       " pattern per voxel; the null, each pixel's gain (1024 + p)/1024, p in [-32, 32],"
                       " each pixel's offset o in [0, 12], and both\n");
        terms_camera(&camera);
        static const char *const cameras[TERMS_HALVES_CAMERAS] = {"    the null\n", "    the gain pattern\n",
                                                                  "    the offset pattern\n",
                                                                  "    the gain and offset patterns\n"};
        for (unsigned int patterned = 0u; patterned < TERMS_HALVES_CAMERAS; patterned += 1u)
        {
            scriptura_text(&results.line, cameras[patterned]);
            const int gained = (patterned & 1u) != 0u;
            const int offset = (patterned & 2u) != 0u;
            camera.gain_pattern_range = gained ? TERMS_GAIN_PATTERN_RANGE : 0ull;
            camera.gain_pattern_bits = gained ? TERMS_GAIN_PATTERN_BITS : 0u;
            camera.offset_pattern_range = offset ? TERMS_OFFSET_PATTERN_RANGE : 0ull;
            NoiseHalvesMeasurement readings[TERMS_FLAT_LIGHTS];
            int read = 1;
            for (unsigned int flat = 0u; flat < TERMS_FLAT_LIGHTS; flat += 1u)
            {
                scene.background = TERMS_FLAT_LIGHT[flat];
                read =
                    read && terms_render(&results, &scene, &camera, device_lanes, lanes, count) &&
                    terms_halves(&results, lanes, &camera, TERMS_FLAT_LIGHT[flat], TERMS_FLAT_RANGE[patterned][flat][0],
                                 TERMS_FLAT_RANGE[patterned][flat][1], &readings[flat]);
            }
            if (read && (patterned == (TERMS_HALVES_CAMERAS - 1u)))
            {
                terms_halves_line(&results, &camera, &readings[0], TERMS_FLAT_LIGHT[0],
                                  &readings[TERMS_FLAT_LIGHTS - 1u], TERMS_FLAT_LIGHT[TERMS_FLAT_LIGHTS - 1u]);
            }
            sim_flush(&results);
        }
        camera.offset_pattern_range = 0ull;
        scene.background = TERMS_BACKGROUND;
    }
    cudaFree(device_lanes);
    free(lanes);
    return sim_close(&results, "noise terms");
}
