// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_lane_test_enumerate.cu: enumeration, scale, edges, indexing and main
#include "record_lane_test_internal.h"

// every lane hits, one in 2^4, 2^8, 2^12 and 2^16, and none
static const unsigned long long s_lane_thresholds[LANE_TEST_THRESHOLDS] = {1ull << 32u, 1ull << 28u, 1ull << 24u,
                                                                           1ull << 20u, 1ull << 16u, 0ull};

// The search over 2^16 lanes of one shared record at each threshold: the host, the interpreter and the compiled
// program word for word, every lane's l, x, hash and hit against the host's arithmetic, and the latch three ways
static void lane_enumerate(LaneResults *results)
{
    const unsigned long long lanes = LANE_TEST_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 1, &search);
    LaneLoaded interpreted;
    LaneLoaded compiled;
    const int interpreted_loads = lane_load(&program, 1, &interpreted);
    const int compiled_loads = interpreted_loads && lane_load(&program, 0, &compiled);
    lane_check(results, interpreted_loads && compiled_loads, "the search program encodes, lays out and loads twice");
    if (compiled_loads == 0)
    {
        if (interpreted_loads != 0)
        {
            lane_free(&interpreted);
        }
        return;
    }
    const int kernel = cycle_record_compiled(compiled.record);
    const int interpreter = (cycle_record_compiled(interpreted.record) == 0) ? 1 : 0;
    const DeviceRecordStep *const steps = compiled.layout.step_table;
    const unsigned int out_limbs = compiled.layout.out_limbs;
    const size_t words = (size_t)lanes * out_limbs;
    unsigned int *const host_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *const interpreted_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *const compiled_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *device_shared = NULL;
    unsigned int *device_interpreted = NULL;
    unsigned int *device_compiled = NULL;
    int ok = (host_out != NULL) && (interpreted_out != NULL) && (compiled_out != NULL) &&
             (cudaMalloc((void **)&device_shared, LANE_TEST_SHARED_LIMBS * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_interpreted, words * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_compiled, words * sizeof(unsigned int)) == cudaSuccess);
    lane_check(results, ok, "the search's records are held on the host and the device");
    int ran_all = ok;
    int words_all = ok;
    unsigned long long lanes_right = 0ull;
    unsigned long long lanes_read = 0ull;
    int latched_all = ok;
    scriptura_text(&results->line, "  enumerate: x = base + l over ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes of one shared record, base 0x");
    scriptura_hex(&results->line, LANE_TEST_BASE, 1u);
    scriptura_text(&results->line, "; the compiled program ran ");
    scriptura_text(&results->line, (kernel != 0) ? "as its own kernel" : "on the interpreter");
    scriptura_text(&results->line, "\n  latch, first lane with hash < T:\n");
    for (unsigned int pick = 0u; ok && (pick < LANE_TEST_THRESHOLDS); pick += 1u)
    {
        const unsigned long long threshold = s_lane_thresholds[pick];
        unsigned int shared[LANE_TEST_SHARED_LIMBS];
        lane_shared(shared, LANE_TEST_BASE, threshold);
        const CycleRecordHostRequest host = {&compiled.layout, {shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes,
                                             host_out,         &compiled.error};
        const int host_ran = cycle_record_run_host(&host) != CYCLE_ERROR;
        int device_ran = (cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess) &&
                         lane_sweep(&interpreted, device_shared, lanes, device_interpreted) &&
                         lane_sweep(&compiled, device_shared, lanes, device_compiled) &&
                         (cudaMemcpy(interpreted_out, device_interpreted, words * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost) == cudaSuccess) &&
                         (cudaMemcpy(compiled_out, device_compiled, words * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost) == cudaSuccess);
        ran_all = ran_all && host_ran && device_ran;
        words_all = words_all && host_ran && device_ran &&
                    (memcmp(host_out, interpreted_out, words * sizeof(unsigned int)) == 0) &&
                    (memcmp(host_out, compiled_out, words * sizeof(unsigned int)) == 0);
        for (unsigned long long lane = 0ull; host_ran && (lane < lanes); lane += 1ull)
        {
            const unsigned int *const record = &host_out[lane * out_limbs];
            int lane_fits = 0;
            int value_fits = 0;
            int hash_fits = 0;
            int hit_fits = 0;
            const unsigned long long read_lane = lane_take(record, &steps[program.outputs[search.lane]], &lane_fits);
            const unsigned long long value = lane_take(record, &steps[program.outputs[search.value]], &value_fits);
            const unsigned long long hash = lane_take(record, &steps[program.outputs[search.hash]], &hash_fits);
            const unsigned long long hit = lane_take(record, &steps[program.outputs[search.hit]], &hit_fits);
            const unsigned long long native = (unsigned long long)lane_hash(LANE_TEST_BASE + lane);
            lanes_read += 1ull;
            lanes_right += (lane_fits && value_fits && hash_fits && hit_fits && (read_lane == lane) &&
                            (value == (LANE_TEST_BASE + lane)) && (hash == native) &&
                            (hit == ((native < threshold) ? 1ull : 0ull)))
                               ? 1ull
                               : 0ull;
        }
        const DeviceRecordStep *const hit_step = &steps[program.outputs[search.hit]];
        unsigned long long interpreted_first = 0ull;
        unsigned long long compiled_first = 0ull;
        unsigned long long host_first = 0ull;
        const int latched =
            device_ran && host_ran &&
            lane_latch_device(&interpreted, hit_step, device_interpreted, lanes, &interpreted_first,
                              &interpreted.error) &&
            lane_latch_device(&compiled, hit_step, device_compiled, lanes, &compiled_first, &compiled.error) &&
            lane_latch_host(&compiled, hit_step, host_out, lanes, &host_first, &compiled.error);
        const unsigned long long native_first = lane_native_first(LANE_TEST_BASE, threshold, lanes);
        latched_all = latched_all && latched && (interpreted_first == native_first) &&
                      (compiled_first == native_first) && (host_first == native_first);
        scriptura_text(&results->line, "    T = ");
        scriptura_decimal(&results->line, threshold, 1u);
        scriptura_text(&results->line, ": device ");
        lane_print(results, compiled_first);
        scriptura_text(&results->line, ", interpreter ");
        lane_print(results, interpreted_first);
        scriptura_text(&results->line, ", host scan ");
        lane_print(results, host_first);
        scriptura_text(&results->line, ", host arithmetic ");
        lane_print(results, native_first);
        scriptura_character(&results->line, '\n');
    }
    scriptura_text(&results->line, "  ");
    scriptura_decimal(&results->line, lanes_right, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes_read, 1u);
    scriptura_text(&results->line, " lane-thresholds read l, base + l, the hash and the hit the host reckons\n");
    lane_check(results, interpreter, "CYCLE_RECORD_INTERPRET=1 keeps the interpreted load on the interpreter");
    lane_check(results, kernel, "the search program compiles to its own kernel (NVRTC and nvJitLink found)");
    lane_check(results, ran_all, "every run of the search, host and device, runs every lane of one shared record");
    lane_check(results, words_all, "the host, the interpreter and the compiled program agree word for word");
    lane_check(results, (lanes_read != 0ull) && (lanes_right == lanes_read),
               "every lane reads its own number, base + l, the hash and the hit the host's arithmetic gives");
    lane_check(results, latched_all,
               "the latch on the device, over the interpreter's and the compiled program's records, returns the lane "
               "the host's serial scan and the host's arithmetic find first, at every threshold");
    cudaFree(device_shared);
    cudaFree(device_interpreted);
    cudaFree(device_compiled);
    free(host_out);
    free(interpreted_out);
    free(compiled_out);
    lane_free(&interpreted);
    lane_free(&compiled);
}

// the hit alone over 2^24 lanes on the device, and the latch brings back only the lane
static void lane_scale(LaneResults *results)
{
    const unsigned long long lanes = LANE_TEST_SCALE_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 0, &search);
    LaneLoaded loaded;
    if (lane_load(&program, 0, &loaded) == 0)
    {
        lane_check(results, 0, "the scale program encodes, lays out and loads");
        return;
    }
    const DeviceRecordStep *const hit_step = &loaded.layout.step_table[program.outputs[search.hit]];
    unsigned int shared[LANE_TEST_SHARED_LIMBS];
    lane_shared(shared, LANE_TEST_SCALE_BASE, LANE_TEST_SCALE_THRESHOLD);
    unsigned int *device_shared = NULL;
    unsigned int *device_out = NULL;
    unsigned long long first = 0ull;
    const int ran = (cudaMalloc((void **)&device_shared, sizeof(shared)) == cudaSuccess) &&
                    (cudaMalloc((void **)&device_out, (size_t)lanes * loaded.layout.out_limbs * sizeof(unsigned int)) ==
                     cudaSuccess) &&
                    (cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess) &&
                    lane_sweep(&loaded, device_shared, lanes, device_out) &&
                    lane_latch_device(&loaded, hit_step, device_out, lanes, &first, &loaded.error);
    const unsigned long long native_first = lane_native_first(LANE_TEST_SCALE_BASE, LANE_TEST_SCALE_THRESHOLD, lanes);
    scriptura_text(&results->line, "  scale: ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes, base 0x");
    scriptura_hex(&results->line, LANE_TEST_SCALE_BASE, 1u);
    scriptura_text(&results->line, ", T = ");
    scriptura_decimal(&results->line, LANE_TEST_SCALE_THRESHOLD, 1u);
    scriptura_text(&results->line, ", ");
    scriptura_decimal(&results->line, loaded.layout.out_limbs, 1u);
    scriptura_text(&results->line, " limb a record ");
    scriptura_text(&results->line, (cycle_record_compiled(loaded.record) != 0) ? "compiled" : "interpreted");
    scriptura_text(&results->line, ": the device latches ");
    lane_print(results, first);
    scriptura_text(&results->line, ", the host's arithmetic finds ");
    lane_print(results, native_first);
    scriptura_character(&results->line, '\n');
    lane_check(results, ran, "the scale search runs and latches on the device");
    lane_check(results, ran && (first == native_first), "over 2^24 lanes the device's latch is the host's first lane");
    cudaFree(device_shared);
    cudaFree(device_out);
    lane_free(&loaded);
}

// the latch's edges over records laid out by hand: bits outside the field set in every record, and the field set at the
// lanes the case names; the device and the host must both return the case's lane
static void lane_edges(LaneResults *results)
{
    const unsigned long long lanes = LANE_TEST_EDGE_LANES;
    const size_t words = (size_t)lanes * LANE_TEST_EDGE_LIMBS;
    unsigned int *const records = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *device_records = NULL;
    const int passed =
        (records != NULL) && (cudaMalloc((void **)&device_records, words * sizeof(unsigned int)) == cudaSuccess);
    lane_check(results, passed, "the edge records are held");
    // each case: its field, and the lanes it sets in that field
    const unsigned int offsets[6] = {30u, 30u, 30u, 30u, 30u, 32u};
    const unsigned int widths[6] = {5u, 5u, 5u, 5u, 5u, 32u};
    const char *const names[6] = {"outside the field only",
                                  "lane 0 and others",
                                  "the last lane alone",
                                  "the least of many",
                                  "the field's bit in the second limb",
                                  "a field of a whole limb"};
    unsigned int matched = 0u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    scriptura_text(&results->line, "  latch edges over ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " records of two limbs:\n");
    for (unsigned int edge = 0u; passed && (edge < 6u); edge += 1u)
    {
        const unsigned int offset = offsets[edge];
        const unsigned int bits = widths[edge];
        // every bit outside the field set, in every record
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            records[lane * LANE_TEST_EDGE_LIMBS] = 0xFFFFFFFFu;
            records[(lane * LANE_TEST_EDGE_LIMBS) + 1u] = 0xFFFFFFFFu;
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 0ull);
        }
        unsigned long long expected = CYCLE_LATCH_NONE;
        if (edge == 1u)
        {
            lane_put(&records[0], offset, bits, 1ull);
            lane_put(&records[777ull * LANE_TEST_EDGE_LIMBS], offset, bits, 3ull);
            lane_put(&records[(lanes - 1ull) * LANE_TEST_EDGE_LIMBS], offset, bits, 31ull);
            expected = 0ull;
        }
        else if (edge == 2u)
        {
            lane_put(&records[(lanes - 1ull) * LANE_TEST_EDGE_LIMBS], offset, bits, 16ull);
            expected = lanes - 1ull;
        }
        else if (edge == 3u)
        {
            for (unsigned int many = 0u; many < 64u; many += 1u)
            {
                const unsigned long long lane = lane_random() % lanes;
                lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 1ull + (lane_random() % 31ull));
                expected = (lane < expected) ? lane : expected;
            }
        }
        else if (edge == 4u)
        {
            // bit 33 of the record, the field's fourth, lies in the second limb
            const unsigned long long lane = 1ull + (lane_random() % (lanes - 1ull));
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 8ull);
            expected = lane;
        }
        else if (edge == 5u)
        {
            const unsigned long long lane = lanes / 2ull;
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 0x80000000ull);
            expected = lane;
        }
        const CycleRecordLatchRequest device = {device_records, lanes, LANE_TEST_EDGE_LIMBS, offset, bits,
                                                NULL,           &error};
        unsigned long long device_first = 0ull;
        unsigned long long host_first = 0ull;
        CycleRecordLatchRequest device_latch = device;
        device_latch.first = &device_first;
        CycleRecordLatchRequest host_latch = device;
        host_latch.records = records;
        host_latch.first = &host_first;
        const int ran = (cudaMemcpy(device_records, records, words * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
                         cudaSuccess) &&
                        (cycle_record_latch(&device_latch) != CYCLE_ERROR) &&
                        (cycle_record_latch_host(&host_latch) != CYCLE_ERROR);
        const int right = ran && (device_first == expected) && (host_first == expected);
        matched += (right != 0) ? 1u : 0u;
        scriptura_text(&results->line, "    ");
        scriptura_text(&results->line, names[edge]);
        scriptura_text(&results->line, ", field at bit ");
        scriptura_decimal(&results->line, offset, 1u);
        scriptura_text(&results->line, ", ");
        scriptura_decimal(&results->line, bits, 1u);
        scriptura_text(&results->line, " bits: device ");
        lane_print(results, device_first);
        scriptura_text(&results->line, ", host ");
        lane_print(results, host_first);
        scriptura_text(&results->line, ", laid out ");
        lane_print(results, expected);
        scriptura_character(&results->line, '\n');
    }
    lane_check(results, passed && (matched == 6u),
               "the latch returns the laid-out lane on the device and the host at every edge, and none where only bits "
               "outside the field are set");
    // a field past the record, and no lanes, are refused
    unsigned long long refused_first = 0ull;
    const CycleRecordLatchRequest over_limit = {device_records, lanes, LANE_TEST_EDGE_LIMBS, 60u, 5u,
                                                &refused_first, &error};
    CycleRecordLatchRequest over_limit_host = over_limit;
    over_limit_host.records = records;
    const CycleRecordLatchRequest empty = {device_records, 0ull, LANE_TEST_EDGE_LIMBS, 0u, 1u, &refused_first, &error};
    lane_check(results,
               passed && (cycle_record_latch(&over_limit) == CYCLE_ERROR) &&
                   (cycle_record_latch_host(&over_limit_host) == CYCLE_ERROR) &&
                   (cycle_record_latch(&empty) == CYCLE_ERROR),
               "the latch refuses a field past its record and a count of no lanes");
    cudaFree(device_records);
    free(records);
}

// Under an index the lane register is the lane: lane l reads record 4095 - l, whose base is (4095 - l) 2^20, and
// writes l and (4095 - l) 2^20 + l. A member of two records, with no index, still refuses three lanes
static void lane_indexed(LaneResults *results)
{
    const unsigned int lanes = LANE_TEST_INDEXED_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 1, &search);
    LaneLoaded loaded;
    if (lane_load(&program, 0, &loaded) == 0)
    {
        lane_check(results, 0, "the indexed program encodes, lays out and loads");
        return;
    }
    const DeviceRecordStep *const steps = loaded.layout.step_table;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const records = (unsigned int *)calloc((size_t)lanes * LANE_TEST_SHARED_LIMBS, sizeof(unsigned int));
    unsigned int *const index = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_copy = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *device_records = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    int ran = (records != NULL) && (index != NULL) && (host_out != NULL) && (device_copy != NULL);
    for (unsigned int lane = 0u; ran && (lane < lanes); lane += 1u)
    {
        lane_shared(&records[lane * LANE_TEST_SHARED_LIMBS], (unsigned long long)lane << 20u, 0ull);
        index[lane] = lanes - 1u - lane;
    }
    const CycleRecordHostRequest host = {&loaded.layout, {records, NULL, NULL}, {lanes, 0ull, 0ull}, index, lanes,
                                         host_out,       &loaded.error};
    ran =
        ran && (cycle_record_run_host(&host) != CYCLE_ERROR) &&
        (cudaMalloc((void **)&device_records, (size_t)lanes * LANE_TEST_SHARED_LIMBS * sizeof(unsigned int)) ==
         cudaSuccess) &&
        (cudaMalloc((void **)&device_index, (size_t)lanes * sizeof(unsigned int)) == cudaSuccess) &&
        (cudaMalloc((void **)&device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
        (cudaMemcpy(device_records, records, (size_t)lanes * LANE_TEST_SHARED_LIMBS * sizeof(unsigned int),
                    cudaMemcpyHostToDevice) == cudaSuccess) &&
        (cudaMemcpy(device_index, index, (size_t)lanes * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    if (ran)
    {
        const CycleRecordRunRequest run = {
            loaded.record, {device_records, NULL, NULL}, {lanes, 0ull, 0ull}, device_index, lanes, device_out,
            &loaded.error};
        ran = (cycle_record_run(&run) != CYCLE_ERROR) &&
              (cudaMemcpy(device_copy, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int),
                          cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    unsigned int right = 0u;
    for (unsigned int lane = 0u; ran && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &host_out[(size_t)lane * out_limbs];
        int lane_fits = 0;
        int value_fits = 0;
        const unsigned long long read_lane = lane_take(record, &steps[program.outputs[search.lane]], &lane_fits);
        const unsigned long long value = lane_take(record, &steps[program.outputs[search.value]], &value_fits);
        const unsigned long long body = (unsigned long long)(lanes - 1u - lane);
        right += (lane_fits && value_fits && (read_lane == lane) && (value == ((body << 20u) + lane))) ? 1u : 0u;
    }
    const int words = ran && (memcmp(host_out, device_copy, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
    // a member of two records and no index: three lanes are refused on the host and on the device
    const CycleRecordHostRequest short_host = {&loaded.layout, {records, NULL, NULL}, {2ull, 0ull, 0ull}, NULL, 3ull,
                                               host_out,       &loaded.error};
    const CycleRecordRunRequest short_run = {
        loaded.record, {device_records, NULL, NULL}, {2ull, 0ull, 0ull}, NULL, 3ull, device_out, &loaded.error};
    const int refused =
        ran && (cycle_record_run_host(&short_host) == CYCLE_ERROR) && (cycle_record_run(&short_run) == CYCLE_ERROR);
    scriptura_text(&results->line, "  indexed: ");
    scriptura_decimal(&results->line, right, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes reading record 4095 - l write l and its record's base + l\n");
    lane_check(results, words, "the indexed program's device records equal the host's word for word");
    lane_check(results, right == lanes, "under an index the lane register is the lane, not the record it reads");
    lane_check(results, refused, "a member of two records with no index refuses three lanes, host and device");
    cudaFree(device_records);
    cudaFree(device_index);
    cudaFree(device_out);
    free(records);
    free(index);
    free(host_out);
    free(device_copy);
    lane_free(&loaded);
}

int main(int count, char **arguments)
{
    LaneResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = LANE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)LANE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_lane_test", count, arguments, LANE_TEST_DECLARED);
    if (admitted != 0)
    {
        lane_enumerate(&results);
        lane_scale(&results);
        lane_edges(&results);
        lane_indexed(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    lane_check(&results, (admitted != 0) && (job.failures == 0ull),
               "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record lane test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
