// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The worked example of engine/prg_sch/README.md, run as written: a two-member program that moves each body by its
// velocity over a shared time step, x' = x + v . dt, and says which side of the origin it lands on. The program is
// encoded, laid out and loaded by the three calls engine_record_encode makes, swept on the device with an index that
// pairs every body with the one time-step record, run again on the host, and each record decoded and checked
// against the arithmetic done directly. The test is one job on the device's tessera daemon, submitted before the
// program is loaded onto the device.
#include "cycle.h"
#include "exact_integer.h"
#include "key_schedule.h"
#include "keymath.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define GUIDE_TEST_LINE 4096ull

#define GUIDE_TEST_BODIES 1000u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} GuideResults;

static void guide_check(GuideResults *results, int passed, const char *what)
{
    results->checks += 1ull;
    if (passed == 0)
    {
        results->failures += 1ull;
        scriptura_text(&results->line, "  FAILED: ");
        scriptura_text(&results->line, what);
        scriptura_character(&results->line, '\n');
    }
}

// `bits` of a value into a record at `offset`, two's complement when negative
static void guide_put(unsigned int *record, unsigned int offset, unsigned int bits, long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int to = offset + bit;
        record[to / 32u] |= (unsigned int)(((unsigned long long)value >> bit) & 1ull) << (to % 32u);
    }
}

// `bits` of a record at `offset` as two's complement
static long long guide_take(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        word |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if (((word >> (bits - 1u)) & 1ull) != 0ull)
    {
        word |= ~0ull << bits;
    }
    return (long long)word;
}

int main(int count, char **arguments)
{
    GuideResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = GUIDE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)GUIDE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);

    // the program, as the README writes it
    const EngineRecordStep steps[6] = {
        {ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u}, // 0 x, field 0 of member 0
        {ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u}, // 1 v, field 1 of member 0
        {ENGINE_RECORD_FIELD, 2u, 0u, 1u},        // 2 dt, field 2 of member 1
        {ENGINE_RECORD_PRODUCT, 1u, 2u, 0u},      // 3 v . dt
        {ENGINE_RECORD_SUM, 0u, 3u, 0u},          // 4 x + v . dt
        {ENGINE_RECORD_COMPARE, 4u, 5u, 0u},      // 5 refused: reads itself
    };
    EngineRecordStep program[6];
    memcpy(program, steps, sizeof(steps));
    const unsigned int field_bits[3] = {32u, 16u, 16u};
    const unsigned int field_offset[3] = {0u, 32u, 0u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {2u, 1u, 0u};
    const unsigned int outputs[2] = {4u, 5u};
    EngineError error;
    memset(&error, 0, sizeof(error));

    // a step that reads itself or a later step is refused at encode
    EngineRecordKey key;
    KeymathRecordRequest encode_request = {program, 6u, field_bits, 3u, 2u, outputs, 2u, NULL, 0u, &key, &error};
    guide_check(&results, keymath_record_encode(&encode_request) == KEYMATH_ERROR,
                "a step reading itself is refused at encode");

    // the side of the origin: compare x' against the constant 0
    program[5].operation = ENGINE_RECORD_CONSTANT;
    program[5].left = 0u;
    program[5].right = 0u;
    EngineRecordStep full[7];
    memcpy(full, program, sizeof(program));
    full[6].operation = ENGINE_RECORD_COMPARE;
    full[6].left = 4u;
    full[6].right = 5u;
    full[6].member = 0u;
    const unsigned int full_outputs[2] = {4u, 6u};
    encode_request.steps = full;
    encode_request.count = 7u;
    encode_request.outputs = full_outputs;
    int ok = keymath_record_encode(&encode_request) != KEYMATH_ERROR;
    guide_check(&results, ok, "the example program encodes");
    // the widths the encoding derived: 16 + 16 bits for the product, one more for the sum, 1 for the comparison
    guide_check(&results, ok && (key.term[3].bits == 32u) && (key.term[4].bits == 33u) && (key.term[6].bits == 1u),
                "the encoding derives 32 bits for v . dt, 33 for x + v . dt and 1 for the comparison");
    EngineRecordLayout layout;
    memset(&layout, 0, sizeof(layout));
    const KeyScheduleRecordRequest layout_request = {&key, field_offset, 3u, in_limbs, 1, &layout, &error};
    ok = ok && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
    guide_check(&results, ok, "the example program lays out");
    // outputs are packed in the order named, each one bit wider than its register for the sign
    guide_check(&results,
                ok && (layout.step_table[4].out_offset == 0u) && (layout.step_table[4].out_bits == 34u) &&
                    (layout.step_table[6].out_offset == 34u) && (layout.step_table[6].out_bits == 2u) &&
                    (layout.out_limbs == 2u),
                "the outputs pack as x' in bits 0..33 and the side in bits 34..35 of a 2-limb record");
    CycleRecord *record = NULL;
    // the job declares what the test puts on the device: the bodies, the time step, the index and the records
    const unsigned long long declared = ((unsigned long long)GUIDE_TEST_BODIES * 6ull * sizeof(unsigned int)) +
                                        sizeof(unsigned int) + (7ull * sizeof(DeviceRecordStep));
    ok = ok && sim_job_submit(&job, "record_guide_test", count, arguments, declared);
    ok = ok && (cycle_record_load(&layout, &record, &error) != CYCLE_ERROR);
    guide_check(&results, ok, "the example program loads");

    // the bodies (member 0) and the one time step (member 1), paired by the index
    unsigned int *const bodies = (unsigned int *)calloc((size_t)GUIDE_TEST_BODIES * 2u, sizeof(unsigned int));
    unsigned int step_record[1] = {0u};
    unsigned int *const index = (unsigned int *)malloc((size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)GUIDE_TEST_BODIES * 2u, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)GUIDE_TEST_BODIES * 2u, sizeof(unsigned int));
    const long long dt = 37;
    guide_put(step_record, 0u, 16u, dt);
    for (unsigned int body = 0u; body < GUIDE_TEST_BODIES; body += 1u)
    {
        const long long x = ((long long)body * 7919ll) - 4000000ll;
        const long long v = ((long long)(body % 200u) * 311ll) - 30000ll;
        guide_put(&bodies[body * 2u], 0u, 32u, x);
        guide_put(&bodies[body * 2u], 32u, 16u, v);
        index[2u * body] = body;
        index[(2u * body) + 1u] = 0u;
    }
    unsigned int *device_bodies = NULL;
    unsigned int *device_step = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_record = NULL;
    ok = ok && (bodies != NULL) && (index != NULL) && (host_out != NULL) && (device_out != NULL) &&
         (cudaMalloc((void **)&device_bodies, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_step, sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_index, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_record, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_bodies, bodies, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_step, step_record, sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_index, index, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {record,
                                           {device_bodies, device_step, NULL},
                                           {GUIDE_TEST_BODIES, 1ull, 0ull},
                                           device_index,
                                           GUIDE_TEST_BODIES,
                                           device_record,
                                           &error};
        ok = (cycle_record_run(&run) == (long)GUIDE_TEST_BODIES) &&
             (cudaMemcpy(device_out, device_record, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    guide_check(&results, ok, "the example sweeps on the device");
    const CycleRecordHostRequest host = {&layout, {bodies, step_record, NULL}, {GUIDE_TEST_BODIES, 1ull, 0ull},
                                         index,   GUIDE_TEST_BODIES,           host_out,
                                         &error};
    const int host_ran = (ok != 0) && (cycle_record_run_host(&host) == (long)GUIDE_TEST_BODIES);
    guide_check(&results, host_ran, "the example runs on the host");
    guide_check(&results,
                host_ran && (memcmp(host_out, device_out, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == 0),
                "the device's records equal the host's word for word");
    int right = host_ran;
    for (unsigned int body = 0u; (right != 0) && (body < GUIDE_TEST_BODIES); body += 1u)
    {
        const long long x = ((long long)body * 7919ll) - 4000000ll;
        const long long v = ((long long)(body % 200u) * 311ll) - 30000ll;
        const long long moved = x + (v * dt);
        const long long side = (moved > 0ll) ? 1ll : ((moved < 0ll) ? -1ll : 0ll);
        right = (guide_take(&device_out[body * 2u], 0u, 34u) == moved) &&
                (guide_take(&device_out[body * 2u], 34u, 2u) == side);
    }
    guide_check(&results, right, "every body's x + v . dt and its side of the origin decode exactly");

    // a lane whose index names a record past its member refuses the sweep, and the record machine names it a request
    // error in an error of its own, since `error` already holds the encoding's refusal above
    index[0] = GUIDE_TEST_BODIES;
    EngineError over_limit_error;
    memset(&over_limit_error, 0, sizeof(over_limit_error));
    const CycleRecordHostRequest over_limit = {&layout,
                                               {bodies, step_record, NULL},
                                               {GUIDE_TEST_BODIES, 1ull, 0ull},
                                               index,
                                               GUIDE_TEST_BODIES,
                                               host_out,
                                               &over_limit_error};
    guide_check(&results,
                (cycle_record_run_host(&over_limit) == CYCLE_ERROR) &&
                    (over_limit_error.kind == ENGINE_ERROR_REQUEST) && (over_limit_error.module == ENGINE_MODULE_CYCLE),
                "an index past its member's records refuses the sweep, a request error from the record machine");

    cudaFree(device_bodies);
    cudaFree(device_step);
    cudaFree(device_index);
    cudaFree(device_record);
    free(bodies);
    free(index);
    free(host_out);
    free(device_out);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    key_schedule_record_release(&layout);
    keymath_record_release(&key);
    sim_job_release(&job);
    sim_flush(&job);
    guide_check(&results, (job.checks == 2ull) && (job.failures == 0ull),
                "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record guide test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
