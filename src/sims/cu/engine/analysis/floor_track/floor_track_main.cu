// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// floor_track_main.cu: the scene and main
#include "floor_track_internal.h"

// the tolerances d, and the patch sizes: the body's own cell, then its 27
static const unsigned int s_track_deltas[TRACK_DELTAS] = {0u, 4u, 8u, 16u, 32u, 64u};

static const unsigned int s_track_patch_cells[TRACK_PATCHES] = {1u, TRACK_PATCH_MAX};

// one scene: render its frames, take every frame's floor 2 from the engine and hold it to the host, lay out the planes,
// build a query for every body, step of `stride` frames, patch and tolerance, run them, and grade them by the
// bodies' paths
static int track_scene(SimResults *results, const char *name, const SimScene *scene, const SimCamera *camera,
                       unsigned long long stride, TrackHost *host, TrackDevice *device,
                       TrackSetting settings[TRACK_PATCHES][TRACK_DELTAS], unsigned int deltas)
{
    const unsigned long long frames = scene->frames;
    unsigned long long clipped = 0ull;
    int ok = sim_render(results, scene, camera, device->lanes, NULL, NULL, &clipped);
    sim_check(results, ok && (clipped == 0ull), "the scene's frames render with nothing clipped");
    const size_t frame_bytes = (size_t)(frames * TRACK_SAMPLES) * sizeof(unsigned short);
    ok = ok && (clipped == 0ull) &&
         sim_status_check(results, cudaMemcpy(host->lanes, device->lanes, frame_bytes, cudaMemcpyDeviceToHost),
                          "frames read");
    int lowered = ok;
    unsigned long long equal = 0ull;
    for (unsigned long long frame = 0ull; ok && (frame < frames); frame += 1ull)
    {
        unsigned short *const floor_values = &host->floors[frame * TRACK_FLOOR_VALUES];
        lowered = lowered &&
                  track_floor_engine(&device->lanes[frame * TRACK_SAMPLES], host->crystal, host->corner, floor_values);
        track_floor_host(&host->lanes[frame * TRACK_SAMPLES], host->work, host->before, host->floor_host);
        for (unsigned long long at = 0ull; lowered && (at < TRACK_FLOOR_VALUES); at += 1ull)
        {
            equal += (host->floor_host[at] == (long long)floor_values[at]) ? 1ull : 0ull;
        }
    }
    sim_check(results, ok && lowered, "the engine's tower lifts every frame and its corner lowers inside the lane");
    ok = ok && lowered;
    sim_check(results, ok && (equal == (frames * TRACK_FLOOR_VALUES)),
              "every frame's floor 2 equals the host's two-level lifting at every coefficient");

    // the planes of every frame, laid out once
    ok = ok && sim_status_check(results,
                                cudaMemcpy(device->floors, host->floors,
                                           (size_t)(frames * TRACK_FLOOR_VALUES) * sizeof(unsigned short),
                                           cudaMemcpyHostToDevice),
                                "floors write");
    for (unsigned long long frame = 0ull; ok && (frame < frames); frame += 1ull)
    {
        // floor 2's values fill whole blocks, far fewer than 2^31
        track_planes_kernel<<<(unsigned int)(TRACK_FLOOR_VALUES / TRACK_THREADS), (unsigned int)TRACK_THREADS>>>(
            &device->floors[frame * TRACK_FLOOR_VALUES], &device->planes[frame * TRACK_BITS * TRACK_WORDS]);
        ok = sim_status_check(results, cudaGetLastError(), "planes launch");
    }
    ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "planes run") &&
         sim_status_check(results,
                          cudaMemcpy(host->planes, device->planes,
                                     (size_t)(frames * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost),
                          "planes read");
    unsigned long long bits_matched = 0ull;
    for (unsigned long long frame = 0ull; ok && (frame < frames); frame += 1ull)
    {
        for (unsigned long long at = 0ull; at < TRACK_FLOOR_VALUES; at += 1ull)
        {
            const unsigned int value = host->floors[(frame * TRACK_FLOOR_VALUES) + at];
            for (unsigned int bit = 0u; bit < TRACK_BITS; bit += 1u)
            {
                const unsigned long long word = (((frame * TRACK_BITS) + bit) * TRACK_WORDS) + (at / TRACK_WORD_BITS);
                const unsigned int plane_bit = (host->planes[word] >> (at % TRACK_WORD_BITS)) & 1u;
                bits_matched += (plane_bit == ((value >> bit) & 1u)) ? 1ull : 0ull;
            }
        }
    }
    sim_check(results, ok && (bits_matched == (frames * TRACK_FLOOR_VALUES * TRACK_BITS)),
              "every frame's 16 planes hold every bit of its floor 2");

    // the queries: a body's patch at frame t, its values' ranges, searched in frame t + stride
    unsigned int count = 0u;
    for (unsigned int index = 0u; ok && (index < scene->bodies); index += 1u)
    {
        const SimBody *const body = &scene->body[index];
        for (unsigned long long frame = 0ull; (frame + stride) < frames; frame += 1ull)
        {
            const unsigned long long from = track_body_cell(body, frame);
            const unsigned long long truth = track_body_cell(body, frame + stride);
            const int clear = track_clear(scene, index, frame, stride, from, truth);
            // the cell's coordinates on floor 2, each below 16
            const long long center[SIM_AXES] = {(long long)(from / (TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE)),
                                                (long long)((from / TRACK_FLOOR_SIDE) % TRACK_FLOOR_SIDE),
                                                (long long)(from % TRACK_FLOOR_SIDE)};
            for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
            {
                for (unsigned int delta = 0u; delta < deltas; delta += 1u)
                {
                    TrackQuery *const query = &host->queries[count];
                    memset(query, 0, sizeof(*query));
                    // frame t + stride is below the scene's frame count, far under 2^32
                    query->frame = (unsigned int)(frame + stride);
                    for (unsigned int cell = 0u; cell < TRACK_PATCH_MAX; cell += 1u)
                    {
                        // the center first, then the other 26 in order; each digit of the order is 0, 1 or 2:
                        // every step is -1, 0 or 1 once the digit is taken signed
                        const unsigned int order = (cell == 0u) ? 13u : ((cell <= 13u) ? (cell - 1u) : cell);
                        const int step[SIM_AXES] = {(int)(order / 9u) - 1, (int)((order / 3u) % 3u) - 1,
                                                    (int)(order % 3u) - 1};
                        const long long at[SIM_AXES] = {center[0] + step[0], center[1] + step[1], center[2] + step[2]};
                        const long long side = (long long)TRACK_FLOOR_SIDE;
                        const int inside = (at[0] >= 0ll) && (at[0] < side) && (at[1] >= 0ll) && (at[1] < side) &&
                                           (at[2] >= 0ll) && (at[2] < side);
                        if ((inside == 0) || (query->count >= s_track_patch_cells[patch]))
                        {
                            continue;
                        }
                        // the cell is inside floor 2 just above. Its position is non-negative and below 2^12
                        const unsigned long long place =
                            (unsigned long long)((((at[0] * side) + at[1]) * side) + at[2]);
                        const unsigned int value = host->floors[(frame * TRACK_FLOOR_VALUES) + place];
                        const unsigned int range = s_track_deltas[delta];
                        memcpy(query->step[query->count], step, sizeof(step));
                        query->low[query->count] = (value > range) ? (value - range) : 0u;
                        query->high[query->count] =
                            ((TRACK_VALUE_MAX - value) > range) ? (value + range) : TRACK_VALUE_MAX;
                        query->count += 1u;
                    }
                    host->truths[count].patch = patch;
                    host->truths[count].delta = delta;
                    host->truths[count].from = from;
                    host->truths[count].truth = truth;
                    host->truths[count].clear = clear;
                    count += 1u;
                }
            }
        }
    }
    ok = ok && sim_status_check(results,
                                cudaMemcpy(device->queries, host->queries, (size_t)count * sizeof(TrackQuery),
                                           cudaMemcpyHostToDevice),
                                "queries write");
    if (ok && (count != 0u))
    {
        track_query_kernel<<<count, (unsigned int)TRACK_WORDS>>>(device->planes, device->queries, device->candidates,
                                                                 device->reads);
        ok = sim_status_check(results, cudaGetLastError(), "query launch") &&
             sim_status_check(results, cudaDeviceSynchronize(), "query run") &&
             sim_status_check(results,
                              cudaMemcpy(host->candidates, device->candidates,
                                         (size_t)count * TRACK_WORDS * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                              "candidates read") &&
             sim_status_check(results,
                              cudaMemcpy(host->reads, device->reads, (size_t)count * TRACK_WORDS * sizeof(unsigned int),
                                         cudaMemcpyDeviceToHost),
                              "reads read");
    }

    // every candidate set against the host's scan, then graded by the body's path
    unsigned long long scanned = 0ull;
    for (unsigned int index = 0u; ok && (index < count); index += 1u)
    {
        const TrackQuery *const query = &host->queries[index];
        const TrackTruth *const truth = &host->truths[index];
        TrackSetting *const setting = &settings[truth->patch][truth->delta];
        track_scan(query, &host->floors[(unsigned long long)query->frame * TRACK_FLOOR_VALUES], host->expected);
        const unsigned int *const found = &host->candidates[(unsigned long long)index * TRACK_WORDS];
        int same = 1;
        unsigned long long candidates = 0ull;
        unsigned long long gated = 0ull;
        unsigned long long taken = 0ull;
        for (unsigned long long word = 0ull; word < TRACK_WORDS; word += 1ull)
        {
            same = same && (found[word] == host->expected[word]);
            candidates += sim_bits_set((unsigned long long)found[word]);
            taken += host->reads[((unsigned long long)index * TRACK_WORDS) + word];
            for (unsigned int bit = 0u; bit < TRACK_WORD_BITS; bit += 1u)
            {
                if (((found[word] >> bit) & 1u) != 0u)
                {
                    gated += (track_gated(truth->from, (word * TRACK_WORD_BITS) + bit) != 0) ? 1ull : 0ull;
                }
            }
        }
        const int hit = ((found[truth->truth / TRACK_WORD_BITS] >> (truth->truth % TRACK_WORD_BITS)) & 1u) != 0u;
        scanned += (same != 0) ? 1ull : 0ull;
        setting->queries += 1ull;
        setting->hits += (hit != 0) ? 1ull : 0ull;
        setting->candidates += candidates;
        setting->candidates_max = (candidates > setting->candidates_max) ? candidates : setting->candidates_max;
        setting->gated += gated;
        setting->alone += ((hit != 0) && (gated == 1ull)) ? 1ull : 0ull;
        setting->reads += taken;
        setting->reads_max = (taken > setting->reads_max) ? taken : setting->reads_max;
        setting->clear += (truth->clear != 0) ? 1ull : 0ull;
        setting->clear_hits += ((truth->clear != 0) && (hit != 0)) ? 1ull : 0ull;
    }
    sim_check(results, ok && (scanned == count),
              "every candidate set equals the host's scan of the later frame's floor 2");

    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, ": ");
    scriptura_decimal(line, scene->bodies, 1u);
    scriptura_text(line, " bodies over ");
    scriptura_decimal(line, frames, 1u);
    scriptura_text(line, " frames, frame t to t + ");
    scriptura_decimal(line, stride, 1u);
    scriptura_text(line, ", ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " queries; half of a frame is ");
    scriptura_decimal(line, TRACK_SAMPLES / 2ull, 1u);
    scriptura_text(line, " samples, ");
    scriptura_decimal(line, TRACK_SAMPLES, 1u);
    scriptura_text(line, " bytes\n");
    for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
    {
        for (unsigned int delta = 0u; delta < deltas; delta += 1u)
        {
            const TrackSetting *const setting = &settings[patch][delta];
            scriptura_text(line, "    patch ");
            scriptura_decimal_columns(line, s_track_patch_cells[patch], 2u);
            scriptura_text(line, ", d ");
            scriptura_decimal_columns(line, s_track_deltas[delta], 2u);
            scriptura_text(line, ": found ");
            scriptura_decimal(line, setting->hits, 1u);
            scriptura_text(line, " of ");
            scriptura_decimal(line, setting->queries, 1u);
            scriptura_text(line, " (clear steps ");
            scriptura_decimal(line, setting->clear_hits, 1u);
            scriptura_text(line, " of ");
            scriptura_decimal(line, setting->clear, 1u);
            scriptura_text(line, "), alone in the gate on ");
            scriptura_decimal(line, setting->alone, 1u);
            scriptura_text(line, "; candidates a query ");
            sim_fraction_print(line, setting->candidates, setting->queries, 2u);
            scriptura_text(line, " (most ");
            scriptura_decimal(line, setting->candidates_max, 1u);
            scriptura_text(line, "), in the gate ");
            sim_fraction_print(line, setting->gated, setting->queries, 2u);
            scriptura_text(line, "; plane words read ");
            sim_fraction_print(line, setting->reads, setting->queries, 1u);
            scriptura_text(line, " (most ");
            scriptura_decimal(line, setting->reads_max, 1u);
            scriptura_text(line, ", ");
            scriptura_decimal(line, 4ull * setting->reads_max, 1u);
            scriptura_text(line, " bytes)\n");
        }
    }
    sim_flush(results);
    return ok;
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    TrackHost host;
    host.lanes = (unsigned short *)malloc((size_t)(TRACK_FRAMES_MAX * TRACK_SAMPLES) * sizeof(unsigned short));
    host.crystal = (int *)malloc((size_t)TRACK_SAMPLES * sizeof(int));
    host.corner = (int *)malloc((size_t)TRACK_FLOOR_VALUES * sizeof(int));
    host.floors = (unsigned short *)malloc((size_t)(TRACK_FRAMES_MAX * TRACK_FLOOR_VALUES) * sizeof(unsigned short));
    host.work = (long long *)malloc((size_t)TRACK_SAMPLES * sizeof(long long));
    host.before = (long long *)malloc((size_t)TRACK_SAMPLES * sizeof(long long));
    host.floor_host = (long long *)malloc((size_t)TRACK_FLOOR_VALUES * sizeof(long long));
    host.planes = (unsigned int *)malloc((size_t)(TRACK_FRAMES_MAX * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int));
    host.queries = (TrackQuery *)malloc((size_t)TRACK_QUERIES_MAX * sizeof(TrackQuery));
    host.truths = (TrackTruth *)malloc((size_t)TRACK_QUERIES_MAX * sizeof(TrackTruth));
    host.candidates = (unsigned int *)malloc((size_t)(TRACK_QUERIES_MAX * TRACK_WORDS) * sizeof(unsigned int));
    host.reads = (unsigned int *)malloc((size_t)(TRACK_QUERIES_MAX * TRACK_WORDS) * sizeof(unsigned int));
    host.expected = (unsigned int *)malloc((size_t)TRACK_WORDS * sizeof(unsigned int));
    int ok = (host.lanes != NULL) && (host.crystal != NULL) && (host.corner != NULL) && (host.floors != NULL) &&
             (host.work != NULL) && (host.before != NULL) && (host.floor_host != NULL) && (host.planes != NULL) &&
             (host.queries != NULL) && (host.truths != NULL) && (host.candidates != NULL) && (host.reads != NULL) &&
             (host.expected != NULL);
    sim_check(&results, ok, "the host buffers are held");
    ok = ok && sim_job_submit(&results, "floor_track", count, arguments, TRACK_DECLARED);
    TrackDevice device;
    memset(&device, 0, sizeof(device));
    ok =
        ok &&
        sim_status_check(
            &results,
            cudaMalloc((void **)&device.lanes, (size_t)(TRACK_FRAMES_MAX * TRACK_SAMPLES) * sizeof(unsigned short)),
            "device frames") &&
        sim_status_check(&results,
                         cudaMalloc((void **)&device.floors,
                                    (size_t)(TRACK_FRAMES_MAX * TRACK_FLOOR_VALUES) * sizeof(unsigned short)),
                         "device floors") &&
        sim_status_check(&results,
                         cudaMalloc((void **)&device.planes,
                                    (size_t)(TRACK_FRAMES_MAX * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int)),
                         "device planes") &&
        sim_status_check(&results, cudaMalloc((void **)&device.queries, (size_t)TRACK_QUERIES_MAX * sizeof(TrackQuery)),
                         "device queries") &&
        sim_status_check(
            &results,
            cudaMalloc((void **)&device.candidates, (size_t)(TRACK_QUERIES_MAX * TRACK_WORDS) * sizeof(unsigned int)),
            "device candidates") &&
        sim_status_check(
            &results,
            cudaMalloc((void **)&device.reads, (size_t)(TRACK_QUERIES_MAX * TRACK_WORDS) * sizeof(unsigned int)),
            "device reads");

    // the control: every body a floor-2 cell a frame, no noise, no ramp, no pattern. Floor 2 translates exactly
    SimBody control_body[TRACK_CONTROL_BODIES];
    SimScene control;
    memset(&control, 0, sizeof(control));
    control.frames = TRACK_CONTROL_FRAMES;
    control.extent[0] = TRACK_SIDE;
    control.extent[1] = TRACK_SIDE;
    control.extent[2] = TRACK_SIDE;
    control.background = 200ull;
    control.bodies = TRACK_CONTROL_BODIES;
    track_control_bodies(control_body, TRACK_CONTROL_FRAMES);
    control.body = control_body;
    SimCamera still;
    memset(&still, 0, sizeof(still));
    still.key = TRACK_KEY;
    still.offset = 100ull;
    still.gain = 1ull;
    TrackSetting control_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(control_settings, 0, sizeof(control_settings));
    ok = ok && track_scene(&results, "control, a cell a frame, no noise", &control, &still, 1ull, &host, &device,
                           control_settings, 1u);
    sim_check(&results,
              ok && (control_settings[0][0].hits == control_settings[0][0].queries) &&
                  (control_settings[1][0].hits == control_settings[1][0].queries),
              "the control finds every body at its true next cell at d = 0, by its own cell and by its 27");

    // the camera law: bodies a voxel a frame, shot and read noise, the ramp and the fixed pattern
    SimBody camera_body[TRACK_CAMERA_BODIES];
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = TRACK_CAMERA_FRAMES;
    scene.extent[0] = TRACK_SIDE;
    scene.extent[1] = TRACK_SIDE;
    scene.extent[2] = TRACK_SIDE;
    scene.background = 200ull;
    scene.ramp = 1ull;
    scene.bodies = TRACK_CAMERA_BODIES;
    SimDraws draws;
    draws.key = TRACK_KEY ^ TRACK_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, camera_body, TRACK_CAMERA_BODIES);
    scene.body = camera_body;
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = TRACK_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_range = 8ull;
    camera.shot = 1ull;
    TrackSetting camera_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(camera_settings, 0, sizeof(camera_settings));
    ok = ok && track_scene(&results, "camera law, a voxel a frame", &scene, &camera, 1ull, &host, &device,
                           camera_settings, TRACK_DELTAS);
    // the floor's own time step: over 2^2 frames a body moving a whole voxel a frame moves whole floor-2 cells
    TrackSetting floor_step_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(floor_step_settings, 0, sizeof(floor_step_settings));
    ok = ok && track_scene(&results, "camera law, a voxel a frame", &scene, &camera, (unsigned long long)TRACK_CELL,
                           &host, &device, floor_step_settings, TRACK_DELTAS);
    // the same bodies with no noise, no ramp and no pattern: what the floor's time step leaves once the noise is gone
    SimScene quiet = scene;
    quiet.ramp = 0ull;
    TrackSetting quiet_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(quiet_settings, 0, sizeof(quiet_settings));
    ok = ok && track_scene(&results, "the camera law's bodies, no noise", &quiet, &still,
                           (unsigned long long)TRACK_CELL, &host, &device, quiet_settings, TRACK_DELTAS);

    // the first three of those bodies spread along z. No body reaches another's footprint, with the camera's noise
    // and without it
    SimBody sparse_body[TRACK_SPARSE_BODIES];
    memcpy(sparse_body, camera_body, sizeof(sparse_body));
    for (unsigned int index = 0u; index < TRACK_SPARSE_BODIES; index += 1u)
    {
        sparse_body[index].center[0] = TRACK_SPARSE_FIRST_Z + ((long long)index * TRACK_SPARSE_Z_STEP);
    }
    SimScene sparse = scene;
    sparse.bodies = TRACK_SPARSE_BODIES;
    sparse.body = sparse_body;
    TrackSetting sparse_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(sparse_settings, 0, sizeof(sparse_settings));
    ok = ok && track_scene(&results, "three bodies apart, camera law", &sparse, &camera, (unsigned long long)TRACK_CELL,
                           &host, &device, sparse_settings, TRACK_DELTAS);
    SimScene sparse_quiet = sparse;
    sparse_quiet.ramp = 0ull;
    TrackSetting sparse_quiet_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(sparse_quiet_settings, 0, sizeof(sparse_quiet_settings));
    ok = ok && track_scene(&results, "three bodies apart, no noise", &sparse_quiet, &still,
                           (unsigned long long)TRACK_CELL, &host, &device, sparse_quiet_settings, TRACK_DELTAS);
    scriptura_text(&results.line, "  clear steps among the three, no noise: ");
    scriptura_decimal(&results.line, sparse_quiet_settings[1][0].clear, 1u);
    scriptura_text(&results.line, " of ");
    scriptura_decimal(&results.line, sparse_quiet_settings[1][0].queries, 1u);
    scriptura_text(&results.line, "\n");
    sim_check(&results,
              ok && (sparse_quiet_settings[1][0].clear != 0ull) &&
                  (sparse_quiet_settings[0][0].clear_hits == sparse_quiet_settings[0][0].clear) &&
                  (sparse_quiet_settings[1][0].clear_hits == sparse_quiet_settings[1][0].clear),
              "at floor 2's time step every clear step is found at d = 0, by its own cell and by its 27");
    unsigned long long maximum = 0ull;
    for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
    {
        for (unsigned int delta = 0u; delta < TRACK_DELTAS; delta += 1u)
        {
            maximum =
                (camera_settings[patch][delta].reads_max > maximum) ? camera_settings[patch][delta].reads_max : maximum;
            maximum = (floor_step_settings[patch][delta].reads_max > maximum)
                          ? floor_step_settings[patch][delta].reads_max
                          : maximum;
            maximum =
                (quiet_settings[patch][delta].reads_max > maximum) ? quiet_settings[patch][delta].reads_max : maximum;
            maximum =
                (sparse_settings[patch][delta].reads_max > maximum) ? sparse_settings[patch][delta].reads_max : maximum;
            const unsigned long long quiet_max = sparse_quiet_settings[patch][delta].reads_max;
            maximum = (quiet_max > maximum) ? quiet_max : maximum;
        }
    }
    maximum = (control_settings[1][0].reads_max > maximum) ? control_settings[1][0].reads_max : maximum;
    scriptura_text(&results.line, "  the most plane words any query read: ");
    scriptura_decimal(&results.line, maximum, 1u);
    scriptura_text(&results.line, ", ");
    scriptura_decimal(&results.line, 4ull * maximum, 1u);
    scriptura_text(&results.line, " bytes, against half of a frame, ");
    scriptura_decimal(&results.line, TRACK_SAMPLES, 1u);
    scriptura_text(&results.line, " bytes\n");
    // a plane word is 4 bytes and a sample 2. Half of a frame's samples is TRACK_SAMPLES bytes
    sim_check(&results, ok && ((4ull * maximum) < TRACK_SAMPLES),
              "no query reads as many bytes of planes as half of a frame holds");

    cudaFree(device.reads);
    cudaFree(device.candidates);
    cudaFree(device.queries);
    cudaFree(device.planes);
    cudaFree(device.floors);
    cudaFree(device.lanes);
    free(host.expected);
    free(host.reads);
    free(host.candidates);
    free(host.truths);
    free(host.queries);
    free(host.planes);
    free(host.floor_host);
    free(host.before);
    free(host.work);
    free(host.floors);
    free(host.corner);
    free(host.crystal);
    free(host.lanes);
    return sim_close(&results, "floor track");
}
