// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The worked example of engine/prg_sch/README.md, run as written: a two-member program that moves each body by its
// velocity over a shared time step, x' = x + v . dt, and says which side of the origin it lands on. The program is
// imprinted, laid and loaded by the three calls engine_record_imprint makes, swept on the device with an index that
// pairs every body with the one time-step record, run again on the host, and each record decoded and checked
// against the arithmetic done directly.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "exact_integer.h"

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
} GuideTally;

static void guide_check(GuideTally *tally, int held, const char *what)
{
    tally->checks += 1ull;
    if (held == 0)
    {
        tally->failures += 1ull;
        scriptura_text(&tally->line, "  FAILED: ");
        scriptura_text(&tally->line, what);
        scriptura_character(&tally->line, '\n');
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

int main(void)
{
    GuideTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = GUIDE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)GUIDE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }

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

    // a step that reads itself or a later step is refused at imprint
    EngineRecordKey key;
    KeymathRecordRequest imprint = {program, 6u, field_bits, 3u, 2u, outputs, 2u, NULL, 0u, &key, &error};
    guide_check(&tally, keymath_record_imprint(&imprint) == KEYMATH_REFUSED,
                "a step reading itself is refused at imprint");

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
    imprint.steps = full;
    imprint.count = 7u;
    imprint.outputs = full_outputs;
    int good = keymath_record_imprint(&imprint) != KEYMATH_REFUSED;
    guide_check(&tally, good, "the example program imprints");
    // the widths the imprint derived: 16 + 16 bits for the product, one more for the sum, 1 for the comparison
    guide_check(&tally, good && (key.term[3].bits == 32u) && (key.term[4].bits == 33u) && (key.term[6].bits == 1u),
                "the imprint derives 32 bits for v . dt, 33 for x + v . dt and 1 for the comparison");
    EngineRecordLayout layout;
    memset(&layout, 0, sizeof(layout));
    const KeyScheduleRecordRequest lay = {&key, field_offset, 3u, in_limbs, 1, &layout, &error};
    good = good && (key_schedule_record_lay(&lay) != KEY_SCHEDULE_REFUSED);
    guide_check(&tally, good, "the example program lays out");
    // outputs are packed in the order named, each one bit wider than its register for the sign
    guide_check(&tally, good && (layout.step_table[4].out_offset == 0u) && (layout.step_table[4].out_bits == 34u)
                            && (layout.step_table[6].out_offset == 34u) && (layout.step_table[6].out_bits == 2u)
                            && (layout.out_limbs == 2u),
                "the outputs pack as x' in bits 0..33 and the side in bits 34..35 of a 2-limb record");
    CycleRecord *record = NULL;
    good = good && (cycle_record_load(&layout, &record, &error) != CYCLE_REFUSED);
    guide_check(&tally, good, "the example program loads");

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
    good = good && (bodies != NULL) && (index != NULL) && (host_out != NULL) && (device_out != NULL)
        && (cudaMalloc((void **)&device_bodies, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess)
        && (cudaMalloc((void **)&device_step, sizeof(unsigned int)) == cudaSuccess)
        && (cudaMalloc((void **)&device_index, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess)
        && (cudaMalloc((void **)&device_record, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == cudaSuccess)
        && (cudaMemcpy(device_bodies, bodies, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                       cudaMemcpyHostToDevice) == cudaSuccess)
        && (cudaMemcpy(device_step, step_record, sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess)
        && (cudaMemcpy(device_index, index, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                       cudaMemcpyHostToDevice) == cudaSuccess);
    if (good != 0)
    {
        const CycleRecordRunRequest run = {record, {device_bodies, device_step, NULL}, {GUIDE_TEST_BODIES, 1ull, 0ull},
                                           device_index, GUIDE_TEST_BODIES, device_record, &error};
        good = (cycle_record_run(&run) == (long)GUIDE_TEST_BODIES)
            && (cudaMemcpy(device_out, device_record, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    guide_check(&tally, good, "the example sweeps on the device");
    const CycleRecordHostRequest host = {&layout, {bodies, step_record, NULL}, {GUIDE_TEST_BODIES, 1ull, 0ull}, index,
                                         GUIDE_TEST_BODIES, host_out};
    const int host_ran = (good != 0) && (cycle_record_run_host(&host) == (long)GUIDE_TEST_BODIES);
    guide_check(&tally, host_ran, "the example runs on the host");
    guide_check(&tally, host_ran && (memcmp(host_out, device_out, (size_t)GUIDE_TEST_BODIES * 2u * sizeof(unsigned int)) == 0),
                "the device's records equal the host's word for word");
    int right = host_ran;
    for (unsigned int body = 0u; (right != 0) && (body < GUIDE_TEST_BODIES); body += 1u)
    {
        const long long x = ((long long)body * 7919ll) - 4000000ll;
        const long long v = ((long long)(body % 200u) * 311ll) - 30000ll;
        const long long moved = x + (v * dt);
        const long long side = (moved > 0ll) ? 1ll : ((moved < 0ll) ? -1ll : 0ll);
        right = (guide_take(&device_out[body * 2u], 0u, 34u) == moved)
             && (guide_take(&device_out[body * 2u], 34u, 2u) == side);
    }
    guide_check(&tally, right, "every body's x + v . dt and its side of the origin decode exactly");

    // a lane whose index names a record past its member refuses the sweep
    index[0] = GUIDE_TEST_BODIES;
    const CycleRecordHostRequest past = {&layout, {bodies, step_record, NULL}, {GUIDE_TEST_BODIES, 1ull, 0ull}, index,
                                         GUIDE_TEST_BODIES, host_out};
    guide_check(&tally, cycle_record_run_host(&past) == CYCLE_REFUSED,
                "an index past its member's records refuses the sweep");

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
    scriptura_text(&tally.line, "  record guide test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
