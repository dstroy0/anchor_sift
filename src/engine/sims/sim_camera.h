// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SIM_CAMERA_H
#define SIM_CAMERA_H

#include "sim.h"

#define SIM_AXES 3u

#define SIM_TRUTH_FIELDS 4u

#define SIM_LANE_MOST 65535ll

#define SIM_RENDER_THREADS 256ull

#define SIM_SHOT_PURPOSE 0x53484F54ull

#define SIM_READ_PURPOSE 0x52454144ull

#define SIM_PATTERN_PURPOSE 0x50415454ull

typedef struct
{
    long long centre[SIM_AXES];
    long long velocity[SIM_AXES];
    long long reach[SIM_AXES];
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
    unsigned long long pattern_reach;
    unsigned long long shot;
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

static inline long long sim_draws_signed(SimDraws *draws, long long reach)
{
    // the reach is a small positive speed; 2 reach + 1 and the draw below it fit both types
    return (long long)sim_draws_between(draws, 0ull, 2ull * (unsigned long long)reach) - reach;
}

static inline void sim_founders_draw(SimDraws *draws, const SimScene *scene, SimBody *body, unsigned int founders)
{
    for (unsigned int index = 0u; index < founders; index += 1u)
    {
        SimBody *const founder = &body[index];
        // each extent is far below 2^63, and the margins keep a founder inside at birth
        founder->centre[0] = (long long)sim_draws_between(draws, 4ull, scene->extent[0] - 5ull);
        founder->centre[1] = (long long)sim_draws_between(draws, 16ull, scene->extent[1] - 17ull);
        founder->centre[2] = (long long)sim_draws_between(draws, 16ull, scene->extent[2] - 17ull);
        founder->velocity[0] = 0ll;
        founder->velocity[1] = sim_draws_signed(draws, 1ll);
        founder->velocity[2] = sim_draws_signed(draws, 1ll);
        // semi-axes of a few voxels, drawn small and positive
        founder->reach[0] = (long long)sim_draws_between(draws, 2ull, 3ull);
        founder->reach[1] = (long long)sim_draws_between(draws, 4ull, 7ull);
        founder->reach[2] = (long long)sim_draws_between(draws, 4ull, 7ull);
        founder->brightness = sim_draws_between(draws, 150ull, 400ull);
        founder->born = 0ull;
        founder->ended = scene->frames;
        founder->parent = -1ll;
    }
}

static inline __host__ __device__ long long sim_body_at(const SimBody *body, unsigned long long frame, unsigned int axis)
{
    // frames since birth are below the frame count, which the scene keeps far under 2^63
    return body->centre[axis] + (body->velocity[axis] * (long long)(frame - body->born));
}

static inline __host__ __device__ int sim_body_inside(const SimBody *body, unsigned long long frame, const long long *place)
{
    if ((frame < body->born) || (frame >= body->ended))
    {
        return 0;
    }
    long long offset[SIM_AXES];
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        offset[axis] = place[axis] - sim_body_at(body, frame, axis);
        if ((offset[axis] > body->reach[axis]) || (offset[axis] < -body->reach[axis]))
        {
            return 0;
        }
    }
    const long long square_z = body->reach[0] * body->reach[0];
    const long long square_y = body->reach[1] * body->reach[1];
    const long long square_x = body->reach[2] * body->reach[2];
    const long long spread = (offset[0] * offset[0] * square_y * square_x) + (offset[1] * offset[1] * square_z * square_x)
                           + (offset[2] * offset[2] * square_z * square_y);
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

static inline __host__ __device__ unsigned long long sim_pattern(const SimCamera *camera, unsigned long long voxel)
{
    if (camera->pattern_reach == 0ull)
    {
        return 0ull;
    }
    return sim_draw_below(camera->key ^ SIM_PATTERN_PURPOSE, voxel, camera->pattern_reach + 1ull);
}

static inline __host__ __device__ long long sim_value(const SimCamera *camera, unsigned long long counter,
                                                      unsigned long long voxel, unsigned long long electrons)
{
    // an electron count is far below 2^62, the signal's bound in every scene here
    long long collected = (long long)electrons;
    if (camera->shot != 0ull)
    {
        // a head count of at most 4 S is far below 2^62
        collected = (long long)sim_binomial_half(camera->key ^ SIM_SHOT_PURPOSE, counter, 4ull * electrons)
                  - collected;
    }
    long long read = 0ll;
    if (camera->read_square != 0ull)
    {
        // a head count of at most 4 r^2 is far below 2^62
        read = (long long)sim_binomial_half(camera->key ^ SIM_READ_PURPOSE, counter, 4ull * camera->read_square)
             - (2ll * (long long)camera->read_square);
    }
    // the offset, pattern and gain are each far below 2^31 in every camera here
    return (long long)camera->offset + (long long)sim_pattern(camera, voxel) + ((long long)camera->gain * collected)
         + read;
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
    const unsigned long long electrons = sim_signal(&scene, frame, place);
    if (signal != NULL)
    {
        // the signal of every scene here is far below 2^32
        signal[index] = (unsigned int)electrons;
    }
    const long long value = sim_value(&camera, index, voxel, electrons);
    if ((value < 0ll) || (value > SIM_LANE_MOST))
    {
        atomicAdd(clipped, 1ull);
    }
    const long long held = (value < 0ll) ? 0ll : ((value > SIM_LANE_MOST) ? SIM_LANE_MOST : value);
    // held is clamped to the u16 lane's range just above
    lanes[index] = (unsigned short)held;
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

static inline int sim_render(SimTally *tally, const SimScene *scene, const SimCamera *camera, unsigned short *device_lanes,
                             unsigned int *device_signal, unsigned long long *host_truth, unsigned long long *clipped)
{
    const unsigned long long lanes = scene->frames * sim_scene_voxels(scene);
    const unsigned long long truth_words = scene->frames * scene->bodies * SIM_TRUTH_FIELDS;
    SimScene launch = *scene;
    SimBody *device_body = NULL;
    unsigned long long *device_truth = NULL;
    unsigned long long *device_clipped = NULL;
    int good = sim_took(tally, cudaMalloc((void **)&device_clipped, sizeof(unsigned long long)), "render: clip count");
    good = good && sim_took(tally, cudaMemset(device_clipped, 0, sizeof(unsigned long long)), "render: clip zero");
    if (good && (scene->bodies != 0u))
    {
        good = sim_took(tally, cudaMalloc((void **)&device_body, scene->bodies * sizeof(SimBody)), "render: bodies");
        good = good && sim_took(tally, cudaMemcpy(device_body, scene->body, scene->bodies * sizeof(SimBody),
                                                  cudaMemcpyHostToDevice), "render: bodies copy");
        launch.body = device_body;
    }
    if (good && (host_truth != NULL) && (truth_words != 0ull))
    {
        good = sim_took(tally, cudaMalloc((void **)&device_truth, truth_words * sizeof(unsigned long long)), "render: truth");
        good = good && sim_took(tally, cudaMemset(device_truth, 0, truth_words * sizeof(unsigned long long)),
                                "render: truth zero");
    }
    if (good)
    {
        const unsigned long long blocks = sim_launch_blocks(lanes, SIM_RENDER_THREADS);
        // the grid is below 2^31 blocks for every scene here
        sim_render_kernel<<<(unsigned int)blocks, (unsigned int)SIM_RENDER_THREADS>>>(launch, *camera, device_lanes,
                                                                                    device_signal, device_truth,
                                                                                    device_clipped);
        good = sim_took(tally, cudaGetLastError(), "render: launch");
        good = good && sim_took(tally, cudaDeviceSynchronize(), "render: run");
    }
    if (good)
    {
        good = sim_took(tally, cudaMemcpy(clipped, device_clipped, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                        "render: clip read");
    }
    if (good && (device_truth != NULL))
    {
        good = sim_took(tally, cudaMemcpy(host_truth, device_truth, truth_words * sizeof(unsigned long long),
                                          cudaMemcpyDeviceToHost), "render: truth read");
    }
    cudaFree(device_truth);
    cudaFree(device_body);
    cudaFree(device_clipped);
    return good;
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
                const long long centre = sim_body_at(body, frame, axis);
                low[axis] = ((centre - body->reach[axis]) < 0ll) ? 0ll : (centre - body->reach[axis]);
                // the extent is far below 2^63
                const long long last = (long long)scene->extent[axis] - 1ll;
                high[axis] = ((centre + body->reach[axis]) > last) ? last : (centre + body->reach[axis]);
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
