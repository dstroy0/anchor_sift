// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim_camera.h"

#include "period.h"

#define POWER_KEY 0x504F574552ull

#define POWER_VOLUMES 32u

#define POWER_PERIOD 5ull

#define POWER_AMPLITUDES 9u

#define POWER_DRAW_COUNTS 2u

// a count of false periods over n chances at 1/(draws + 1) each may exceed n p by 5 sqrt(n p), this squared over n p:
// the binomial's spread is sqrt(n p (1 - p)). The tolerance is 5.30 of it at 8 draws and 5.13 at 19
#define POWER_RANGE_SQUARED 25ull

typedef struct
{
    unsigned long long found;
    unsigned long long found_multiple;
    unsigned long long found_elsewhere;
    unsigned long long false_other_axes;
} PowerResults;

static int power_read(SimResults *results, const unsigned short *lanes, const unsigned short *device_lanes,
                      const SimScene *scene, unsigned long long draws, PeriodMargin *band,
                      PeriodMeasurement *measurement)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = SIM_AXES;
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        request.extent[axis] = scene->extent[axis];
    }
    request.draws = draws;
    request.content = sim_content(lanes, sim_scene_voxels(scene), POWER_KEY);
    request.band = band;
    request.band_capacity = draws * SIM_AXES;
    request.measurement = measurement;
    request.error = &error;
    const long long status = period_read(&request);
    sim_check(results, (status == 0ll) && (error.kind == ENGINE_ERROR_NONE), "period_read accepted the volume");
    return status == 0ll;
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    const unsigned long long amplitude[POWER_AMPLITUDES] = {0ull,  2ull,   8ull,   16ull,  32ull,
                                                            64ull, 128ull, 256ull, 1024ull};
    const unsigned long long draw_count[POWER_DRAW_COUNTS] = {8ull, 19ull};

    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = 1ull;
    scene.extent[0] = 32ull;
    scene.extent[1] = 64ull;
    scene.extent[2] = 64ull;
    scene.background = 200ull;
    scene.plant_axis = 2u;
    scene.plant_period = POWER_PERIOD;
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_range = 8ull;
    camera.shot = 1ull;

    const unsigned long long voxels = sim_scene_voxels(&scene);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    PeriodMargin band[19ull * SIM_AXES];
    unsigned short *device_lanes = NULL;
    int ok = lanes != NULL;
    ok = ok && sim_job_submit(&results, "period_power", 0, NULL, voxels * sizeof(unsigned short));
    ok = ok && sim_status_check(&results, cudaMalloc((void **)&device_lanes, voxels * sizeof(unsigned short)), "lanes");

    ScripturaLine *const line = &results.line;
    scriptura_text(line, "  the period reading's power: a planted period ");
    scriptura_decimal(line, POWER_PERIOD, 1u);
    scriptura_text(
        line, " along x of 32 x 64 x 64 under the camera law (signal 200 e, read variance 3, fixed pattern 0 to 8)\n");
    scriptura_text(line, "  each column over ");
    scriptura_decimal(line, POWER_VOLUMES, 1u);
    scriptura_text(line, " volumes; the plant adds 0 to the amplitude electrons by phase\n");
    scriptura_text(line,
                   "  draws  amplitude  x reads 5  x reads 10 or 15  x reads another  z or y reads one (of 64)\n");
    for (unsigned int counts = 0u; ok && (counts < POWER_DRAW_COUNTS); counts += 1u)
    {
        const unsigned long long draws = draw_count[counts];
        for (unsigned int level = 0u; ok && (level < POWER_AMPLITUDES); level += 1u)
        {
            PowerResults result;
            memset(&result, 0, sizeof(result));
            scene.plant_amplitude = amplitude[level];
            for (unsigned int volume = 0u; ok && (volume < POWER_VOLUMES); volume += 1u)
            {
                camera.key = sim_draw(POWER_KEY, (((counts * POWER_AMPLITUDES) + level) * POWER_VOLUMES) + volume);
                scene.plant_key = camera.key ^ 0x504C414E54ull;
                unsigned long long clipped = 0ull;
                ok = sim_render(&results, &scene, &camera, device_lanes, NULL, NULL, &clipped);
                ok = ok && (clipped == 0ull);
                ok = ok && sim_status_check(
                               &results,
                               cudaMemcpy(lanes, device_lanes, voxels * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                               "lanes read");
                PeriodMeasurement measurement;
                ok = ok && power_read(&results, lanes, device_lanes, &scene, draws, band, &measurement);
                if (ok)
                {
                    const unsigned long long read_x = measurement.axis[2].period;
                    const int multiple = (read_x > POWER_PERIOD) && ((read_x % POWER_PERIOD) == 0ull);
                    result.found += (read_x == POWER_PERIOD) ? 1ull : 0ull;
                    result.found_multiple += multiple ? 1ull : 0ull;
                    result.found_elsewhere += ((read_x != 0ull) && (read_x % POWER_PERIOD) != 0ull) ? 1ull : 0ull;
                    result.false_other_axes += (measurement.axis[0].period != 0ull) ? 1ull : 0ull;
                    result.false_other_axes += (measurement.axis[1].period != 0ull) ? 1ull : 0ull;
                }
            }
            scriptura_decimal_columns(line, draws, 7u);
            scriptura_decimal_columns(line, amplitude[level], 11u);
            scriptura_decimal_columns(line, result.found, 11u);
            scriptura_decimal_columns(line, result.found_multiple, 16u);
            scriptura_decimal_columns(line, result.found_elsewhere, 17u);
            scriptura_decimal_columns(line, result.false_other_axes, 18u);
            scriptura_character(line, '\n');
            sim_flush(&results);
            const unsigned long long axes = 2ull * POWER_VOLUMES;
            const unsigned long long scaled = (draws + 1ull) * result.false_other_axes;
            const unsigned long long excess = (scaled > axes) ? (scaled - axes) : 0ull;
            sim_check(&results, (excess * excess) <= (POWER_RANGE_SQUARED * axes * (draws + 1ull)),
                      "the unplanted axes' false periods exceed n/(draws + 1) by at most 5 sqrt(n p)");
            if (amplitude[level] == 0ull)
            {
                const unsigned long long scaled_x =
                    (draws + 1ull) * (result.found + result.found_multiple + result.found_elsewhere);
                const unsigned long long excess_x = (scaled_x > POWER_VOLUMES) ? (scaled_x - POWER_VOLUMES) : 0ull;
                sim_check(&results, (excess_x * excess_x) <= (POWER_RANGE_SQUARED * POWER_VOLUMES * (draws + 1ull)),
                          "with nothing planted, x's false periods exceed n/(draws + 1) by at most 5 sqrt(n p)");
            }
            if (level + 1u == POWER_AMPLITUDES)
            {
                sim_check(&results, (result.found + result.found_multiple) == POWER_VOLUMES,
                          "the strongest plant is read as 5 or a multiple of it on every volume");
            }
        }
    }
    sim_check(&results, ok, "every volume rendered and read");
    cudaFree(device_lanes);
    free(lanes);
    return sim_close(&results, "period power");
}
