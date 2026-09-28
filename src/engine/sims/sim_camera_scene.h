// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sim_camera_scene.h: the scene, draws, bodies and light (sim_camera.h includes the parts in order)
#ifndef SIM_CAMERA_SCENE_H
#define SIM_CAMERA_SCENE_H

#include "sim.h"

#define SIM_AXES 3u

#define SIM_TRUTH_FIELDS 4u

#define SIM_LANE_MAX 65535ll

#define SIM_RENDER_THREADS 256ull

#define SIM_SHOT_PURPOSE 0x53484F54ull

#define SIM_READ_PURPOSE 0x52454144ull

#define SIM_PATTERN_PURPOSE 0x50415454ull

#define SIM_ROW_PURPOSE 0x524F57ull

#define SIM_COLUMN_PURPOSE 0x434F4C554D4Eull

#define SIM_PLANE_PURPOSE 0x504C414E45ull

#define SIM_FLICKER_PURPOSE 0x464C49434B4552ull

#define SIM_SPIKE_PURPOSE 0x5350494B45ull

#define SIM_RESET_PURPOSE 0x5245534554ull

#define SIM_THIN_PURPOSE 0x5448494Eull

#define SIM_EXCESS_PURPOSE 0x455843455353ull

#define SIM_SCALE_PURPOSE 0x5343414C45ull

#define SIM_GAIN_PATTERN_PURPOSE 0x50524E55ull

#define SIM_GAIN_ROUND_PURPOSE 0x524F554E44ull

#define SIM_OFFSET_PATTERN_PURPOSE 0x44534E55ull

// the camera's shot laws, 0 for none: sim_poisson_four_cumulants, the camera's own, whose first four cumulants are
// each S, a Poisson count's; and Binomial(4S, 1/2) - S, of mean and variance S but symmetric (third cumulant 0,
// fourth -S/2), kept for a sim to read beside it
#define SIM_SHOT_POISSON 1ull

#define SIM_SHOT_SYMMETRIC 2ull

// two more counts for a sim to thin (rows 13 and 14): Binomial(2S, 1/2), of mean S and variance S / 2, Fano factor
// 1/2, a sub-Poisson source; and twice the camera's Poisson count of S / 2 pairs, S even, of mean S and variance 2 S,
// Fano factor 2, a bunched source
#define SIM_SHOT_HALF 3ull

#define SIM_SHOT_PAIRED 4ull

typedef struct
{
    long long center[SIM_AXES];
    long long velocity[SIM_AXES];
    long long range[SIM_AXES];
    unsigned long long brightness;
    unsigned long long born;
    unsigned long long ended;
    long long parent;
} SimBody;

typedef struct
{
    unsigned long long frames;
    unsigned long long extent[SIM_AXES];
    unsigned long long background;
    unsigned long long ramp;
    unsigned int plant_axis;
    unsigned long long plant_period;
    unsigned long long plant_amplitude;
    unsigned long long plant_key;
    unsigned int bodies;
    const SimBody *body;
} SimScene;

typedef struct
{
    unsigned long long key;
    unsigned long long offset;
    unsigned long long gain;
    unsigned long long read_square;
    unsigned long long pattern_range;
    // the shot law, SIM_SHOT_POISSON, SIM_SHOT_SYMMETRIC, SIM_SHOT_HALF or SIM_SHOT_PAIRED, or 0 for none
    unsigned long long shot;
    // the terms noise_vector_integration_table.md rows 7 to 11 plant, each 0 unless set: an offset of this variance
    // drawn per frame for each row, each column and each plane
    unsigned long long row_square;
    unsigned long long column_square;
    unsigned long long plane_square;
    // flicker octaves 0 up to this count, each a draw of flicker_square held for 2^o frames at a voxel
    unsigned long long flicker_square;
    unsigned int flicker_octaves;
    // a spike of spike_electrons at a voxel-frame, at the rate numerator over denominator
    unsigned long long spike_numerator;
    unsigned long long spike_denominator;
    unsigned long long spike_electrons;
    // charge before and beside the gain (rows 2, 3 and 6), each 0 unless set: the dark electrons a voxel collects a
    // frame at the camera's exposure, D dt, drawn with the light by the shot law; and a reset offset of this variance
    // drawn per voxel-frame (kTC), level-free like the read
    unsigned long long dark;
    unsigned long long reset_square;
    // a count law's stages after the draw, each off unless set (rows 12 to 14): every counted electron kept with
    // chance keep_numerator / 2^keep_bits, keep_bits 1 to 16 (quantum efficiency, a binomial thinning); then, where
    // excess is set, every electron left doubled or lost with chance 1/2, F^2 = 2 (an electron-multiplying register)
    unsigned long long keep_numerator;
    unsigned int keep_bits;
    unsigned int excess;
    // optical crosstalk (row 16), 0 unless set, 1 to 4: the light takes blur_eighths / 8 of each x neighbor's before
    // the draw and keeps (8 - 2 blur_eighths) / 8 of its own, rounded to the nearest; an edge voxel's missing
    // neighbor is itself
    unsigned long long blur_eighths;
    // a light scale shared by the whole volume, with memory (row 10), off unless scale_bits is set, 1 to 32: frame t's
    // light times (2^scale_bits + e_t) / 2^scale_bits before the draw, rounded to the nearest, e_t the sum of
    // scale_octaves draws of variance scale_square, octave o's held for 2^o frames
    unsigned long long scale_square;
    unsigned int scale_octaves;
    unsigned int scale_bits;
    // a gain per camera pixel (PRNU, row 19), off unless gain_pattern_bits is set, 1 to 32: the pixel (y, x)'s gain is
    // gain (2^gain_pattern_bits + p) / 2^gain_pattern_bits in every plane, p drawn once in [-range, range] with
    // gain_pattern_range below 2^gain_pattern_bits, and the gained count rounded by chance so its mean is exact
    unsigned long long gain_pattern_range;
    unsigned int gain_pattern_bits;
    // an offset per camera pixel (DSNU, row 18), 0 unless set: the pixel (y, x)'s offset, drawn once in [0, range], is
    // added in every plane, where pattern_range's is drawn anew at each voxel
    unsigned long long offset_pattern_range;
} SimCamera;

typedef struct
{
    unsigned long long key;
    unsigned long long counter;
} SimDraws;

static inline __host__ __device__ unsigned long long sim_scene_voxels(const SimScene *scene)
{
    return scene->extent[0] * scene->extent[1] * scene->extent[2];
}

static inline unsigned long long sim_draws_between(SimDraws *draws, unsigned long long low, unsigned long long high)
{
    const unsigned long long value = low + sim_draw_below(draws->key, draws->counter, (high - low) + 1ull);
    draws->counter += 1ull;
    return value;
}

static inline long long sim_draws_signed(SimDraws *draws, long long range)
{
    // the range is a small positive speed. 2 range + 1 and the draw below it fit both types
    return (long long)sim_draws_between(draws, 0ull, 2ull * (unsigned long long)range) - range;
}

static inline void sim_founders_draw(SimDraws *draws, const SimScene *scene, SimBody *body, unsigned int founders)
{
    for (unsigned int index = 0u; index < founders; index += 1u)
    {
        SimBody *const founder = &body[index];
        // each extent is far below 2^63, and the margins keep a founder inside at birth
        founder->center[0] = (long long)sim_draws_between(draws, 4ull, scene->extent[0] - 5ull);
        founder->center[1] = (long long)sim_draws_between(draws, 16ull, scene->extent[1] - 17ull);
        founder->center[2] = (long long)sim_draws_between(draws, 16ull, scene->extent[2] - 17ull);
        founder->velocity[0] = 0ll;
        founder->velocity[1] = sim_draws_signed(draws, 1ll);
        founder->velocity[2] = sim_draws_signed(draws, 1ll);
        // semi-axes of a few voxels, drawn small and positive
        founder->range[0] = (long long)sim_draws_between(draws, 2ull, 3ull);
        founder->range[1] = (long long)sim_draws_between(draws, 4ull, 7ull);
        founder->range[2] = (long long)sim_draws_between(draws, 4ull, 7ull);
        founder->brightness = sim_draws_between(draws, 150ull, 400ull);
        founder->born = 0ull;
        founder->ended = scene->frames;
        founder->parent = -1ll;
    }
}

static inline __host__ __device__ long long sim_body_at(const SimBody *body, unsigned long long frame,
                                                        unsigned int axis)
{
    // frames since birth are below the frame count, which the scene keeps far under 2^63
    return body->center[axis] + (body->velocity[axis] * (long long)(frame - body->born));
}

static inline __host__ __device__ int sim_body_inside(const SimBody *body, unsigned long long frame,
                                                      const long long *place)
{
    if ((frame < body->born) || (frame >= body->ended))
    {
        return 0;
    }
    long long offset[SIM_AXES];
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        offset[axis] = place[axis] - sim_body_at(body, frame, axis);
        if ((offset[axis] > body->range[axis]) || (offset[axis] < -body->range[axis]))
        {
            return 0;
        }
    }
    const long long square_z = body->range[0] * body->range[0];
    const long long square_y = body->range[1] * body->range[1];
    const long long square_x = body->range[2] * body->range[2];
    const long long spread = (offset[0] * offset[0] * square_y * square_x) +
                             (offset[1] * offset[1] * square_z * square_x) +
                             (offset[2] * offset[2] * square_z * square_y);
    return spread <= (square_z * square_y * square_x);
}

static inline __host__ __device__ unsigned long long sim_signal(const SimScene *scene, unsigned long long frame,
                                                                const long long *place)
{
    // a column index inside the view is non-negative and below the extent
    unsigned long long electrons = scene->background + (scene->ramp * (unsigned long long)place[2]);
    if (scene->plant_period != 0ull)
    {
        // a coordinate inside the view is non-negative and below the extent
        const unsigned long long phase = (unsigned long long)place[scene->plant_axis] % scene->plant_period;
        electrons += sim_draw_below(scene->plant_key, phase, scene->plant_amplitude + 1ull);
    }
    for (unsigned int index = 0u; index < scene->bodies; index += 1u)
    {
        if (sim_body_inside(&scene->body[index], frame, place) != 0)
        {
            electrons += scene->body[index].brightness;
        }
    }
    return electrons;
}

// a draw of variance square about 0: Binomial(4 square, 1/2) - 2 square
static inline __host__ __device__ long long sim_centerd(unsigned long long key, unsigned long long counter,
                                                        unsigned long long square)
{
    // a head count of at most 4 square is far below 2^62
    return (long long)sim_binomial_half(key, counter, 4ull * square) - (2ll * (long long)square);
}

// the shared scale's e_t in frame t: scale_octaves draws of variance scale_square, octave o's held for 2^o frames
static inline __host__ __device__ long long sim_scale(const SimCamera *camera, unsigned long long frame)
{
    long long shared = 0ll;
    for (unsigned int octave = 0u; octave < camera->scale_octaves; octave += 1u)
    {
        // octave o's draw changes only when frame >> o does
        const unsigned long long index = ((frame >> octave) * camera->scale_octaves) + octave;
        shared += sim_centerd(camera->key ^ SIM_SCALE_PURPOSE, index, camera->scale_square);
    }
    return shared;
}

// The light a voxel's draw is made from: the scene's signal, blurred along x before the draw, then scaled by the
// shared scale, each where the camera says so.
static inline __host__ __device__ unsigned long long sim_light(const SimScene *scene, const SimCamera *camera,
                                                               unsigned long long frame, const long long *place)
{
    unsigned long long light = sim_signal(scene, frame, place);
    if (camera->blur_eighths != 0ull)
    {
        long long beside[SIM_AXES] = {place[0], place[1], place[2] - 1ll};
        const unsigned long long left = (place[2] > 0ll) ? sim_signal(scene, frame, beside) : light;
        beside[2] = place[2] + 1ll;
        // a column index inside the view is non-negative and below the extent
        const unsigned long long right =
            (((unsigned long long)place[2] + 1ull) < scene->extent[2]) ? sim_signal(scene, frame, beside) : light;
        light =
            (((8ull - (2ull * camera->blur_eighths)) * light) + (camera->blur_eighths * (left + right)) + 4ull) / 8ull;
    }
    if (camera->scale_bits != 0u)
    {
        // the unit is far below 2^62, and the scale is held at 1 at least
        const long long unit = 1ll << camera->scale_bits;
        const long long scale = unit + sim_scale(camera, frame);
        const unsigned long long factor = (scale < 1ll) ? 1ull : (unsigned long long)scale;
        light = ((light * factor) + (1ull << (camera->scale_bits - 1u))) >> camera->scale_bits;
    }
    return light;
}

static inline __host__ __device__ unsigned long long sim_pattern(const SimCamera *camera, unsigned long long voxel)
{
    if (camera->pattern_range == 0ull)
    {
        return 0ull;
    }
    return sim_draw_below(camera->key ^ SIM_PATTERN_PURPOSE, voxel, camera->pattern_range + 1ull);
}

#endif
