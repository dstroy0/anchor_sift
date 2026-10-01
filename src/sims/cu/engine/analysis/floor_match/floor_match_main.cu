// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// floor_match_main.cu: main
#include "floor_match_internal.h"

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)MATCH_SAMPLES * sizeof(unsigned short));
    int *const crystal = (int *)malloc((size_t)MATCH_SAMPLES * sizeof(int));
    int *const corner = (int *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(int));
    unsigned short *const floor_values = (unsigned short *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short));
    long long *const work = (long long *)malloc((size_t)MATCH_SAMPLES * sizeof(long long));
    long long *const before = (long long *)malloc((size_t)MATCH_SAMPLES * sizeof(long long));
    long long *const floor_host = (long long *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(long long));
    unsigned int *const planes = (unsigned int *)malloc((size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int));
    unsigned int *const queries = (unsigned int *)malloc((size_t)MATCH_QUERIES * sizeof(unsigned int));
    unsigned int *const matches = (unsigned int *)malloc((size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int));
    unsigned char *const reads = (unsigned char *)malloc((size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char));
    unsigned char *const present = (unsigned char *)calloc((size_t)MATCH_VALUES_MAX, sizeof(unsigned char));
    unsigned int *const expected = (unsigned int *)malloc((size_t)MATCH_WORDS * sizeof(unsigned int));
    int ok = (lanes != NULL) && (crystal != NULL) && (corner != NULL) && (floor_values != NULL) && (work != NULL) &&
             (before != NULL) && (floor_host != NULL) && (planes != NULL) && (queries != NULL) && (matches != NULL) &&
             (reads != NULL) && (present != NULL) && (expected != NULL);
    sim_check(&results, ok, "the host buffers are held");
    ok = ok && sim_job_submit(&results, "floor_match", count, arguments, MATCH_DECLARED);

    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = 1ull;
    scene.extent[0] = MATCH_SIDE;
    scene.extent[1] = MATCH_SIDE;
    scene.extent[2] = MATCH_SIDE;
    scene.background = 200ull;
    scene.ramp = 1ull;
    scene.bodies = MATCH_FOUNDERS;
    SimBody body[MATCH_FOUNDERS];
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = MATCH_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_range = 8ull;
    camera.shot = 1ull;
    SimDraws draws;
    draws.key = MATCH_KEY ^ MATCH_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, body, MATCH_FOUNDERS);
    scene.body = body;

    unsigned short *device_lanes = NULL;
    unsigned short *device_floor = NULL;
    unsigned int *device_planes = NULL;
    unsigned int *device_queries = NULL;
    unsigned int *device_matches = NULL;
    unsigned char *device_reads = NULL;
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_lanes, (size_t)MATCH_SAMPLES * sizeof(unsigned short)),
                          "device frame");
    unsigned long long clipped = 0ull;
    ok = ok && sim_render(&results, &scene, &camera, device_lanes, NULL, NULL, &clipped);
    sim_check(&results, ok && (clipped == 0ull), "the frame renders with nothing clipped");
    ok = ok && (clipped == 0ull) &&
         sim_status_check(
             &results,
             cudaMemcpy(lanes, device_lanes, (size_t)MATCH_SAMPLES * sizeof(unsigned short), cudaMemcpyDeviceToHost),
             "frame read");

    // floor 2 from the engine, checked against the host's own lifting at every coefficient
    ok = ok && match_floor_engine(&results, device_lanes, crystal, corner, floor_values);
    unsigned long long equal = 0ull;
    if (ok)
    {
        match_floor_host(lanes, work, before, floor_host);
        for (unsigned long long at = 0ull; at < MATCH_FLOOR_VALUES; at += 1ull)
        {
            equal += (floor_host[at] == (long long)floor_values[at]) ? 1ull : 0ull;
        }
    }
    sim_check(&results, ok && (equal == MATCH_FLOOR_VALUES),
              "the engine's floor 2 equals the host's two-level lifting of the frame at every coefficient");

    // the planes, laid out once on the device from floor 2's values
    ok = ok &&
         sim_status_check(&results,
                          cudaMalloc((void **)&device_floor, (size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short)),
                          "device floor") &&
         sim_status_check(
             &results, cudaMalloc((void **)&device_planes, (size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int)),
             "device planes") &&
         sim_status_check(&results,
                          cudaMemcpy(device_floor, floor_values, (size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short),
                                     cudaMemcpyHostToDevice),
                          "floor write");
    if (ok)
    {
        // floor 2's values fill whole blocks, far fewer than 2^31
        match_planes_kernel<<<(unsigned int)(MATCH_FLOOR_VALUES / MATCH_THREADS), (unsigned int)MATCH_THREADS>>>(
            device_floor, device_planes);
        ok = sim_status_check(&results, cudaGetLastError(), "planes launch") &&
             sim_status_check(&results, cudaDeviceSynchronize(), "planes run") &&
             sim_status_check(&results,
                              cudaMemcpy(planes, device_planes,
                                         (size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int),
                                         cudaMemcpyDeviceToHost),
                              "planes read");
    }
    unsigned long long bits_matched = 0ull;
    for (unsigned long long at = 0ull; ok && (at < MATCH_FLOOR_VALUES); at += 1ull)
    {
        present[floor_values[at]] = 1u;
        for (unsigned int bit = 0u; bit < MATCH_BITS; bit += 1u)
        {
            const unsigned int plane_bit =
                (planes[((unsigned long long)bit * MATCH_WORDS) + (at / MATCH_WORD_BITS)] >> (at % MATCH_WORD_BITS)) &
                1u;
            bits_matched += (plane_bit == ((floor_values[at] >> bit) & 1u)) ? 1ull : 0ull;
        }
    }
    sim_check(&results, ok && (bits_matched == (MATCH_FLOOR_VALUES * MATCH_BITS)),
              "the 16 planes hold every bit of every floor-2 value");

    // the queries: values drawn at keyed positions of floor 2, then values drawn over the lane that floor 2 lacks
    unsigned long long distinct = 0ull;
    for (unsigned long long value = 0ull; value < MATCH_VALUES_MAX; value += 1ull)
    {
        distinct += present[value];
    }
    for (unsigned int query = 0u; ok && (query < MATCH_QUERIES_EACH); query += 1u)
    {
        // the drawn position is below floor 2's count
        queries[query] = floor_values[sim_draw_below(MATCH_KEY ^ MATCH_PRESENT_PURPOSE, query, MATCH_FLOOR_VALUES)];
    }
    unsigned long long absent_counter = 0ull;
    for (unsigned int query = 0u; ok && (query < MATCH_QUERIES_EACH); query += 1u)
    {
        unsigned int value = 0u;
        do
        {
            // the draw is below the lane's 2^16 values
            value = (unsigned int)sim_draw_below(MATCH_KEY ^ MATCH_ABSENT_PURPOSE, absent_counter, MATCH_VALUES_MAX);
            absent_counter += 1ull;
        } while (present[value] != 0u);
        queries[MATCH_QUERIES_EACH + query] = value;
    }
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_queries, (size_t)MATCH_QUERIES * sizeof(unsigned int)),
                          "device queries") &&
         sim_status_check(
             &results, cudaMalloc((void **)&device_matches, (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int)),
             "device matches") &&
         sim_status_check(
             &results, cudaMalloc((void **)&device_reads, (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char)),
             "device reads") &&
         sim_status_check(
             &results,
             cudaMemcpy(device_queries, queries, (size_t)MATCH_QUERIES * sizeof(unsigned int), cudaMemcpyHostToDevice),
             "queries write");
    if (ok)
    {
        const unsigned long long threads = (unsigned long long)MATCH_QUERIES * MATCH_WORDS;
        // the grid is far below 2^31 blocks
        match_query_kernel<<<(unsigned int)sim_launch_blocks(threads, MATCH_THREADS), (unsigned int)MATCH_THREADS>>>(
            device_planes, device_queries, device_matches, device_reads);
        ok = sim_status_check(&results, cudaGetLastError(), "query launch") &&
             sim_status_check(&results, cudaDeviceSynchronize(), "query run") &&
             sim_status_check(&results,
                              cudaMemcpy(matches, device_matches,
                                         (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int),
                                         cudaMemcpyDeviceToHost),
                              "matches read") &&
             sim_status_check(&results,
                              cudaMemcpy(reads, device_reads,
                                         (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char),
                                         cudaMemcpyDeviceToHost),
                              "reads read");
    }

    // each query's match set against the host's scan of floor 2, and its reads
    MatchSide sides[2];
    memset(sides, 0, sizeof(sides));
    unsigned long long first_query_cell = MATCH_FLOOR_VALUES;
    for (unsigned int query = 0u; ok && (query < MATCH_QUERIES); query += 1u)
    {
        MatchSide *const side = &sides[query / MATCH_QUERIES_EACH];
        memset(expected, 0, (size_t)MATCH_WORDS * sizeof(unsigned int));
        for (unsigned long long at = 0ull; at < MATCH_FLOOR_VALUES; at += 1ull)
        {
            if ((unsigned int)floor_values[at] == queries[query])
            {
                expected[at / MATCH_WORD_BITS] |= 1u << (at % MATCH_WORD_BITS);
            }
        }
        int same = 1;
        unsigned long long found = 0ull;
        unsigned long long taken = 0ull;
        for (unsigned long long word = 0ull; word < MATCH_WORDS; word += 1ull)
        {
            const unsigned int got = matches[((unsigned long long)query * MATCH_WORDS) + word];
            same = same && (got == expected[word]);
            found += sim_bits_set((unsigned long long)got);
            taken += reads[((unsigned long long)query * MATCH_WORDS) + word];
            if ((query == 0u) && (got != 0u) && (first_query_cell == MATCH_FLOOR_VALUES))
            {
                // the lowest set bit of a nonzero word, counted up from bit 0
                unsigned int low = 0u;
                while (((got >> low) & 1u) == 0u)
                {
                    low += 1u;
                }
                first_query_cell = (word * MATCH_WORD_BITS) + low;
            }
        }
        side->matched += (same != 0) ? 1ull : 0ull;
        side->found += found;
        side->found_max = (found > side->found_max) ? found : side->found_max;
        side->total += taken;
        side->maximum = (taken > side->maximum) ? taken : side->maximum;
    }

    const unsigned long long half = MATCH_SAMPLES / 2ull;
    const unsigned long long full = MATCH_BITS * MATCH_WORDS;
    ScripturaLine *const line = &results.line;
    scriptura_text(line, "  a: one 64^3 camera frame, n = ");
    scriptura_decimal(line, MATCH_SAMPLES, 1u);
    scriptura_text(line, " samples; floor 2, its 16^3 corner after two levels, m = ");
    scriptura_decimal(line, MATCH_FLOOR_VALUES, 1u);
    scriptura_text(line, " = n / 64 values, ");
    scriptura_decimal(line, distinct, 1u);
    scriptura_text(line, " distinct; equal to the host's lifting at ");
    scriptura_decimal(line, equal, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, MATCH_FLOOR_VALUES, 1u);
    scriptura_text(line, "\n  the index, built once: the lift read a's n samples and the planes floor 2's m values; ");
    scriptura_decimal(line, MATCH_BITS, 1u);
    scriptura_text(line, " planes of ");
    scriptura_decimal(line, MATCH_WORDS, 1u);
    scriptura_text(line, " words\n  a query reads no value: the and over the planes takes at most ");
    scriptura_decimal(line, full, 1u);
    scriptura_text(line, " plane words, and half of a is ");
    scriptura_decimal(line, half, 1u);
    scriptura_text(line, " samples\n");
    match_print_side(line, "on floor 2", &sides[0]);
    match_print_side(line, "not on floor 2", &sides[1]);
    if (first_query_cell < MATCH_FLOOR_VALUES)
    {
        const unsigned long long z = first_query_cell / (MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE);
        const unsigned long long y = (first_query_cell / MATCH_FLOOR_SIDE) % MATCH_FLOOR_SIDE;
        const unsigned long long x = first_query_cell % MATCH_FLOOR_SIDE;
        scriptura_text(line, "    the first query, x = ");
        scriptura_decimal(line, queries[0], 1u);
        scriptura_text(line, ": its first cell on floor 2 is (");
        scriptura_decimal(line, z, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, y, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, x, 1u);
        scriptura_text(line, "), centerd on a's (");
        scriptura_decimal(line, 4ull * z, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, 4ull * y, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, 4ull * x, 1u);
        scriptura_text(line, ")\n");
    }
    sim_check(&results, ok && (sides[0].matched == MATCH_QUERIES_EACH),
              "every value on floor 2 is found at exactly the positions the host's scan finds");
    sim_check(&results, ok && (sides[1].matched == MATCH_QUERIES_EACH) && (sides[1].found == 0ull),
              "every value not on floor 2 is found nowhere");
    // the query kernel stops at the 16th plane. The reads hold by construction; the check records that the bound,
    // 16 m / 32 plane words, sits below n / 2
    sim_check(&results, ok && (sides[0].maximum <= full) && (sides[1].maximum <= full) && (full < half),
              "no query reads more than 16 m / 32 plane words, below half of a");

    cudaFree(device_reads);
    cudaFree(device_matches);
    cudaFree(device_queries);
    cudaFree(device_planes);
    cudaFree(device_floor);
    cudaFree(device_lanes);
    free(expected);
    free(present);
    free(reads);
    free(matches);
    free(queries);
    free(planes);
    free(floor_host);
    free(before);
    free(work);
    free(floor_values);
    free(corner);
    free(crystal);
    free(lanes);
    return sim_close(&results, "floor match");
}
