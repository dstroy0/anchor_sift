// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sim_camera_render.h: thinning, gain, offsets, the render kernel and truth (sim_camera.h includes the parts in order)
#ifndef SIM_CAMERA_RENDER_H
#define SIM_CAMERA_RENDER_H

#include "sim_camera_scene.h"

// each of count electrons kept with chance numerator / 2^bits, bits 1 to 16: a word holds 64 / bits electrons' draws.
// A counter's SIM_COUNTER_STRIDE words hold that many each
static inline __host__ __device__ unsigned long long sim_thinned(unsigned long long key, unsigned long long counter,
                                                                 unsigned long long count, unsigned long long numerator,
                                                                 unsigned int bits)
{
    const unsigned long long per_word = 64ull / bits;
    const unsigned long long mask = (1ull << bits) - 1ull;
    unsigned long long kept = 0ull;
    unsigned long long word = 0ull;
    for (unsigned long long done = 0ull; done < count; done += per_word)
    {
        unsigned long long draw = sim_counter_draw(key, counter, word);
        const unsigned long long left = count - done;
        const unsigned long long taken = (left < per_word) ? left : per_word;
        for (unsigned long long electron = 0ull; electron < taken; electron += 1ull)
        {
            kept += ((draw & mask) < numerator) ? 1ull : 0ull;
            draw >>= bits;
        }
        word += 1ull;
    }
    return kept;
}

// a camera pixel's p, its gain's departure in units of 2^-gain_pattern_bits, 0 where the camera has no gain pattern
static inline __host__ __device__ long long sim_gain_spread(const SimCamera *camera, unsigned long long pixel)
{
    if (camera->gain_pattern_bits == 0u)
    {
        return 0ll;
    }
    // the range is below 2^32 in every camera here. The draw and the difference fit a long long
    return (long long)sim_draw_below(camera->key ^ SIM_GAIN_PATTERN_PURPOSE, pixel,
                                     (2ull * camera->gain_pattern_range) + 1ull) -
           (long long)camera->gain_pattern_range;
}

// a camera pixel's fixed offset, 0 where the camera has no offset pattern
static inline __host__ __device__ unsigned long long sim_offset_pattern(const SimCamera *camera,
                                                                        unsigned long long pixel)
{
    if (camera->offset_pattern_range == 0ull)
    {
        return 0ull;
    }
    return sim_draw_below(camera->key ^ SIM_OFFSET_PATTERN_PURPOSE, pixel, camera->offset_pattern_range + 1ull);
}

static inline __host__ __device__ long long sim_value(const SimCamera *camera, unsigned long long counter,
                                                      unsigned long long voxel, unsigned long long pixel,
                                                      unsigned long long electrons)
{
    // the light's electrons and the dark's are drawn together, before the gain
    const unsigned long long charge = electrons + camera->dark;
    // an electron count is far below 2^62, the signal's bound in every scene here
    long long collected = (long long)charge;
    if (camera->shot == SIM_SHOT_SYMMETRIC)
    {
        // a head count of at most 4 S is far below 2^62
        collected = (long long)sim_binomial_half(camera->key ^ SIM_SHOT_PURPOSE, counter, 4ull * charge) - collected;
    }
    else
    {
        unsigned long long count = charge;
        if (camera->shot == SIM_SHOT_POISSON)
        {
            count = sim_poisson_four_cumulants(camera->key ^ SIM_SHOT_PURPOSE, counter, charge);
        }
        else if (camera->shot == SIM_SHOT_HALF)
        {
            count = sim_binomial_half(camera->key ^ SIM_SHOT_PURPOSE, counter, 2ull * charge);
        }
        else if (camera->shot == SIM_SHOT_PAIRED)
        {
            count = 2ull * sim_poisson_four_cumulants(camera->key ^ SIM_SHOT_PURPOSE, counter, charge / 2ull);
        }
        if (camera->keep_bits != 0u)
        {
            count =
                sim_thinned(camera->key ^ SIM_THIN_PURPOSE, counter, count, camera->keep_numerator, camera->keep_bits);
        }
        if (camera->excess != 0u)
        {
            count = 2ull * sim_binomial_half(camera->key ^ SIM_EXCESS_PURPOSE, counter, count);
        }
        // a count of at most 4 S, doubled, is far below 2^62
        collected = (long long)count;
    }
    long long read = 0ll;
    if (camera->read_square != 0ull)
    {
        // a head count of at most 4 r^2 is far below 2^62
        read = (long long)sim_binomial_half(camera->key ^ SIM_READ_PURPOSE, counter, 4ull * camera->read_square) -
               (2ll * (long long)camera->read_square);
    }
    if (camera->reset_square != 0ull)
    {
        // a head count of at most 4 kTC is far below 2^62
        read += (long long)sim_binomial_half(camera->key ^ SIM_RESET_PURPOSE, counter, 4ull * camera->reset_square) -
                (2ll * (long long)camera->reset_square);
    }
    // the offset, pattern and gain are each far below 2^31 in every camera here
    long long gained = (long long)camera->gain * collected;
    if (camera->gain_pattern_bits != 0u)
    {
        const long long unit = 1ll << camera->gain_pattern_bits;
        const long long scaled = gained * (unit + sim_gain_spread(camera, pixel));
        // the quotient toward minus infinity, then up by one with the chance of the remainder over the unit. The
        // gained count's mean is exact
        const long long below = (scaled / unit) - ((((scaled % unit) != 0ll) && (scaled < 0ll)) ? 1ll : 0ll);
        // the remainder lies in [0, unit). It re-signs exactly
        const unsigned long long remainder = (unsigned long long)(scaled - (below * unit));
        const unsigned long long chance =
            sim_draw_below(camera->key ^ SIM_GAIN_ROUND_PURPOSE, counter, (unsigned long long)unit);
        gained = below + ((chance < remainder) ? 1ll : 0ll);
    }
    return (long long)camera->offset + (long long)sim_pattern(camera, voxel) +
           (long long)sim_offset_pattern(camera, pixel) + gained + read;
}

// The terms a camera shares across voxels or carries across frames: an offset drawn per frame for each row, column
// and plane, flicker octaves each held for 2^o frames, and spikes at a rational rate. Each is 0 unless its field is
// set. With none of them set, a camera draws what it drew before they existed.
static inline __host__ __device__ long long sim_shared(const SimCamera *camera, const SimScene *scene,
                                                       unsigned long long frame, const long long *place,
                                                       unsigned long long voxel, unsigned long long counter)
{
    // each coordinate is inside the view, non-negative and below its extent
    const unsigned long long plane = (frame * scene->extent[0]) + (unsigned long long)place[0];
    const unsigned long long row = (plane * scene->extent[1]) + (unsigned long long)place[1];
    const unsigned long long column = (plane * scene->extent[2]) + (unsigned long long)place[2];
    long long shared = 0ll;
    if (camera->row_square != 0ull)
    {
        shared += sim_centerd(camera->key ^ SIM_ROW_PURPOSE, row, camera->row_square);
    }
    if (camera->column_square != 0ull)
    {
        shared += sim_centerd(camera->key ^ SIM_COLUMN_PURPOSE, column, camera->column_square);
    }
    if (camera->plane_square != 0ull)
    {
        shared += sim_centerd(camera->key ^ SIM_PLANE_PURPOSE, plane, camera->plane_square);
    }
    for (unsigned int octave = 0u; (camera->flicker_square != 0ull) && (octave < camera->flicker_octaves); octave += 1u)
    {
        // octave o's draw is held for 2^o frames: its counter changes only when frame >> o does
        const unsigned long long index =
            ((((voxel * camera->flicker_octaves) + octave) * scene->frames) + (frame >> octave));
        shared += sim_centerd(camera->key ^ SIM_FLICKER_PURPOSE, index, camera->flicker_square);
    }
    if ((camera->spike_denominator != 0ull) &&
        (sim_draw_below(camera->key ^ SIM_SPIKE_PURPOSE, counter, camera->spike_denominator) < camera->spike_numerator))
    {
        // a spike's electrons times the gain, like the signal's, are far below 2^62
        shared += (long long)(camera->gain * camera->spike_electrons);
    }
    return shared;
}

static __global__ void sim_render_kernel(SimScene scene, SimCamera camera, unsigned short *lanes, unsigned int *signal,
                                         unsigned long long *truth, unsigned long long *clipped)
{
    const unsigned long long voxels = sim_scene_voxels(&scene);
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= (scene.frames * voxels))
    {
        return;
    }
    const unsigned long long frame = index / voxels;
    const unsigned long long voxel = index % voxels;
    long long place[SIM_AXES];
    // each coordinate is below its extent, far under 2^63
    place[0] = (long long)(voxel / (scene.extent[1] * scene.extent[2]));
    place[1] = (long long)((voxel / scene.extent[2]) % scene.extent[1]);
    place[2] = (long long)(voxel % scene.extent[2]);
    const unsigned long long electrons = sim_light(&scene, &camera, frame, place);
    if (signal != NULL)
    {
        // the signal of every scene here is far below 2^32
        signal[index] = (unsigned int)electrons;
    }
    // a camera pixel is a (y, x), the same in every plane
    const unsigned long long pixel = voxel % (scene.extent[1] * scene.extent[2]);
    const long long value =
        sim_value(&camera, index, voxel, pixel, electrons) + sim_shared(&camera, &scene, frame, place, voxel, index);
    if ((value < 0ll) || (value > SIM_LANE_MAX))
    {
        atomicAdd(clipped, 1ull);
    }
    const long long clamped = (value < 0ll) ? 0ll : ((value > SIM_LANE_MAX) ? SIM_LANE_MAX : value);
    // held is clamped to the u16 lane's range just above
    lanes[index] = (unsigned short)clamped;
    if (truth == NULL)
    {
        return;
    }
    for (unsigned int body = 0u; body < scene.bodies; body += 1u)
    {
        if (sim_body_inside(&scene.body[body], frame, place) != 0)
        {
            unsigned long long *const field = &truth[((frame * scene.bodies) + body) * SIM_TRUTH_FIELDS];
            atomicAdd(&field[0], 1ull);
            // each coordinate is non-negative inside the view
            atomicAdd(&field[1], (unsigned long long)place[0]);
            atomicAdd(&field[2], (unsigned long long)place[1]);
            atomicAdd(&field[3], (unsigned long long)place[2]);
        }
    }
}

static inline int sim_render(SimResults *results, const SimScene *scene, const SimCamera *camera,
                             unsigned short *device_lanes, unsigned int *device_signal, unsigned long long *host_truth,
                             unsigned long long *clipped)
{
    const unsigned long long lanes = scene->frames * sim_scene_voxels(scene);
    const unsigned long long truth_words = scene->frames * scene->bodies * SIM_TRUTH_FIELDS;
    SimScene launch = *scene;
    SimBody *device_body = NULL;
    unsigned long long *device_truth = NULL;
    unsigned long long *device_clipped = NULL;
    int ok = sim_status_check(results, cudaMalloc((void **)&device_clipped, sizeof(unsigned long long)),
                              "render: clip count");
    ok =
        ok && sim_status_check(results, cudaMemset(device_clipped, 0, sizeof(unsigned long long)), "render: clip zero");
    if (ok && (scene->bodies != 0u))
    {
        ok = sim_status_check(results, cudaMalloc((void **)&device_body, scene->bodies * sizeof(SimBody)),
                              "render: bodies");
        ok = ok &&
             sim_status_check(
                 results, cudaMemcpy(device_body, scene->body, scene->bodies * sizeof(SimBody), cudaMemcpyHostToDevice),
                 "render: bodies copy");
        launch.body = device_body;
    }
    if (ok && (host_truth != NULL) && (truth_words != 0ull))
    {
        ok = sim_status_check(results, cudaMalloc((void **)&device_truth, truth_words * sizeof(unsigned long long)),
                              "render: truth");
        ok = ok && sim_status_check(results, cudaMemset(device_truth, 0, truth_words * sizeof(unsigned long long)),
                                    "render: truth zero");
    }
    if (ok)
    {
        const unsigned long long blocks = sim_launch_blocks(lanes, SIM_RENDER_THREADS);
        // the grid is below 2^31 blocks for every scene here
        sim_render_kernel<<<(unsigned int)blocks, (unsigned int)SIM_RENDER_THREADS>>>(
            launch, *camera, device_lanes, device_signal, device_truth, device_clipped);
        ok = sim_status_check(results, cudaGetLastError(), "render: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "render: run");
    }
    if (ok)
    {
        ok = sim_status_check(results,
                              cudaMemcpy(clipped, device_clipped, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                              "render: clip read");
    }
    if (ok && (device_truth != NULL))
    {
        ok = sim_status_check(
            results,
            cudaMemcpy(host_truth, device_truth, truth_words * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
            "render: truth read");
    }
    cudaFree(device_truth);
    cudaFree(device_body);
    cudaFree(device_clipped);
    return ok;
}

static inline void sim_truth_host(const SimScene *scene, unsigned long long *truth)
{
    memset(truth, 0, scene->frames * scene->bodies * SIM_TRUTH_FIELDS * sizeof(unsigned long long));
    for (unsigned long long frame = 0ull; frame < scene->frames; frame += 1ull)
    {
        for (unsigned int index = 0u; index < scene->bodies; index += 1u)
        {
            const SimBody *const body = &scene->body[index];
            unsigned long long *const field = &truth[((frame * scene->bodies) + index) * SIM_TRUTH_FIELDS];
            long long low[SIM_AXES];
            long long high[SIM_AXES];
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const long long center = sim_body_at(body, frame, axis);
                low[axis] = ((center - body->range[axis]) < 0ll) ? 0ll : (center - body->range[axis]);
                // the extent is far below 2^63
                const long long last = (long long)scene->extent[axis] - 1ll;
                high[axis] = ((center + body->range[axis]) > last) ? last : (center + body->range[axis]);
            }
            long long place[SIM_AXES];
            for (place[0] = low[0]; place[0] <= high[0]; place[0] += 1ll)
            {
                for (place[1] = low[1]; place[1] <= high[1]; place[1] += 1ll)
                {
                    for (place[2] = low[2]; place[2] <= high[2]; place[2] += 1ll)
                    {
                        if (sim_body_inside(body, frame, place) != 0)
                        {
                            field[0] += 1ull;
                            // each coordinate is non-negative, clipped to the view above
                            field[1] += (unsigned long long)place[0];
                            field[2] += (unsigned long long)place[1];
                            field[3] += (unsigned long long)place[2];
                        }
                    }
                }
            }
        }
    }
}

#endif
