// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_bitwise_test_lifting.cu: the stack, lifting and main
#include "record_bitwise_test_internal.h"

// a stack of BITWISE_TEST_FLOORS floors over four 32-bit words (w0, w1, w2, w3). Each floor's round is
// n = wrap32(((w2 and (w0 xor w1)) + w3) xor constant), and the words move down one: (w1, w2, w3, n). One program,
// register reuse on, far past a thousand steps; the oracle runs the same rounds on long long.
static void bitwise_stack(BitwiseResults *results)
{
    const unsigned int count = BITWISE_TEST_STACK_WORDS + (BITWISE_TEST_FLOORS * BITWISE_TEST_FLOOR_STEPS);
    EngineRecordStep *const steps = (EngineRecordStep *)calloc(count, sizeof(EngineRecordStep));
    long long *const oracle = (long long *)malloc((size_t)count * sizeof(long long));
    if ((steps == NULL) || (oracle == NULL))
    {
        bitwise_check(results, 0, "the stack is held");
        free(steps);
        free(oracle);
        return;
    }
    unsigned int field_bits[BITWISE_TEST_STACK_WORDS];
    unsigned int field_offset[BITWISE_TEST_STACK_WORDS];
    unsigned int word[BITWISE_TEST_STACK_WORDS];
    for (unsigned int at = 0u; at < BITWISE_TEST_STACK_WORDS; at += 1u)
    {
        field_bits[at] = 32u;
        field_offset[at] = 32u * at;
        steps[at].operation = ENGINE_RECORD_FIELD_SIGNED;
        steps[at].left = at;
        word[at] = at;
    }
    unsigned int outputs[BITWISE_TEST_STACK_TAPS];
    unsigned int output_count = 0u;
    unsigned int at = BITWISE_TEST_STACK_WORDS;
    for (unsigned int floor = 0u; floor < BITWISE_TEST_FLOORS; floor += 1u)
    {
        const unsigned int mixed = at;
        steps[at] = EngineRecordStep{ENGINE_RECORD_XOR, word[0], word[1], 0u};
        steps[at + 1u] = EngineRecordStep{ENGINE_RECORD_AND, word[2], mixed, 0u};
        steps[at + 2u] = EngineRecordStep{ENGINE_RECORD_SUM, at + 1u, word[3], 0u};
        steps[at + 3u] = EngineRecordStep{ENGINE_RECORD_CONSTANT, bitwise_floor_constant(floor), 0u, 0u};
        steps[at + 4u] = EngineRecordStep{ENGINE_RECORD_XOR, at + 2u, at + 3u, 0u};
        steps[at + 5u] = EngineRecordStep{ENGINE_RECORD_WRAP, at + 4u, 32u, 0u};
        word[0] = word[1];
        word[1] = word[2];
        word[2] = word[3];
        word[3] = at + 5u;
        if ((floor == 0u) || (floor == (BITWISE_TEST_FLOORS / 2u)) || ((floor + 4u) >= BITWISE_TEST_FLOORS))
        {
            outputs[output_count] = at + 5u;
            output_count += 1u;
        }
        at += BITWISE_TEST_FLOOR_STEPS;
    }
    BitwiseLoaded loaded;
    memset(&loaded, 0, sizeof(loaded));
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {BITWISE_TEST_STACK_WORDS, 0u, 0u};
    const KeymathRecordRequest encode_request = {steps, count,       field_bits,   BITWISE_TEST_STACK_WORDS,
                                                 1u,    outputs,     output_count, NULL,
                                                 0u,    &loaded.key, &loaded.error};
    const KeyScheduleRecordRequest layout_request = {
        &loaded.key, field_offset, BITWISE_TEST_STACK_WORDS, in_limbs, 1, &loaded.layout, &loaded.error};
    int loads = keymath_record_encode(&encode_request) != KEYMATH_ERROR;
    loads = loads && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
    loads = loads && (cycle_record_load(&loaded.layout, &loaded.record, &loaded.error) != CYCLE_ERROR);
    bitwise_check(results, loads, "a stack of 4204 steps encodes, lays out with reuse and loads");
    if (loads == 0)
    {
        free(steps);
        free(oracle);
        return;
    }
    const unsigned int lanes = BITWISE_TEST_STACK_LANES;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * BITWISE_TEST_STACK_WORDS, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    int host_ran = 0;
    int device_ran = 0;
    unsigned int lanes_equal = 0u;
    if ((atoms != NULL) && (host_out != NULL) && (device_out != NULL))
    {
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            const unsigned int pattern = bitwise_random();
            for (unsigned int field = 0u; field < BITWISE_TEST_STACK_WORDS; field += 1u)
            {
                bitwise_field_fill(&atoms[lane * BITWISE_TEST_STACK_WORDS], field_offset[field], 32u,
                                   pattern >> (3u * field));
            }
        }
        bitwise_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
        for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
        {
            const unsigned int *const atom = &atoms[lane * BITWISE_TEST_STACK_WORDS];
            for (unsigned int step = 0u; step < count; step += 1u)
            {
                const EngineRecordStep *const doing = &steps[step];
                if (doing->operation == ENGINE_RECORD_FIELD_SIGNED)
                {
                    // a 32-bit field read signed: 2^32 comes off where its top bit is set
                    const unsigned int raw = atom[doing->left];
                    oracle[step] = ((raw & 0x80000000u) != 0u) ? ((long long)raw - 4294967296ll) : (long long)raw;
                }
                else if (doing->operation == ENGINE_RECORD_XOR)
                {
                    oracle[step] = oracle[doing->left] ^ oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_AND)
                {
                    oracle[step] = oracle[doing->left] & oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_SUM)
                {
                    oracle[step] = oracle[doing->left] + oracle[doing->right];
                }
                else if (doing->operation == ENGINE_RECORD_CONSTANT)
                {
                    oracle[step] = (long long)doing->left;
                }
                else
                {
                    oracle[step] = bitwise_wrap_native(oracle[doing->left], doing->right);
                }
            }
            int lane_ok = 1;
            for (unsigned int output = 0u; output < output_count; output += 1u)
            {
                const DeviceRecordStep *const tapped = &loaded.layout.step_table[outputs[output]];
                AnchorExactInteger value;
                bitwise_take(&host_out[lane * out_limbs], tapped->out_offset, tapped->out_bits, &value);
                // a floor's word lies in [-2^31, 2^31), one limb of magnitude
                const long long read = (long long)value.sign * (long long)value.limb[0];
                lane_ok = lane_ok && (read == oracle[outputs[output]]);
            }
            lanes_equal += (lane_ok != 0) ? 1u : 0u;
        }
    }
    scriptura_text(&results->line, "  stack: ");
    scriptura_decimal(&results->line, BITWISE_TEST_FLOORS, 1u);
    scriptura_text(&results->line, " floors, ");
    scriptura_decimal(&results->line, count, 1u);
    scriptura_text(&results->line, " steps, file ");
    scriptura_decimal(&results->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs, ");
    scriptura_decimal(&results->line, lanes_equal, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes equal the CPU's rounds at every tapped floor\n");
    bitwise_check(results, (host_ran != 0) && (device_ran != 0), "the stack runs on the host and the device");
    bitwise_check(results,
                  (host_ran != 0) && (device_ran != 0) &&
                      (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                  "the stack's device records equal the host's word for word");
    bitwise_check(results, lanes_equal == lanes, "every lane's tapped floors equal the CPU's rounds");
    free(atoms);
    free(host_out);
    free(device_out);
    free(steps);
    free(oracle);
    bitwise_free(&loaded);
}

#define BITWISE_TEST_LIFT_SAMPLES 8u

#define BITWISE_TEST_LIFT_LANES 4096u

// the lifting's outputs: 4 lows, 4 highs and the 8 rebuilt samples
#define BITWISE_TEST_LIFT_OUTPUTS 16u

static unsigned int bitwise_lift_append(BitwiseLift *lift, EngineRecordOperation operation, unsigned int left,
                                        unsigned int right)
{
    lift->steps[lift->count] = EngineRecordStep{operation, left, right, 0u};
    lift->count += 1u;
    return lift->count - 1u;
}

// floor(v / 2^k), toward minus infinity, from record steps: the and with 2^k - 1 is v's residue, never negative, and
// v less it divides exactly
static unsigned int bitwise_floor_shift(BitwiseLift *lift, unsigned int value, unsigned int shift)
{
    const unsigned int mask = bitwise_lift_append(lift, ENGINE_RECORD_CONSTANT, (1u << shift) - 1u, 0u);
    const unsigned int residue = bitwise_lift_append(lift, ENGINE_RECORD_AND, value, mask);
    const unsigned int difference = bitwise_lift_append(lift, ENGINE_RECORD_DIFFERENCE, value, residue);
    const unsigned int power = bitwise_lift_append(lift, ENGINE_RECORD_CONSTANT, 1u << shift, 0u);
    return bitwise_lift_append(lift, ENGINE_RECORD_EXACT_QUOTIENT, difference, power);
}

// the tower's own floor shift, as tower_*.cu computes it on the device
static long long bitwise_tower_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// one level of the tower's 5/3 lifting over 8 samples, forward then inverse, stacked in one program of record steps.
// The forward floor's coefficients must equal tower_*.cu's formulas on the CPU, and the inverse floor must return the
// samples exactly: the lifting and its inverse are record floors, and T^-1 . T is the identity on the machine.
static void bitwise_lifting(BitwiseResults *results)
{
    const unsigned int count = BITWISE_TEST_LIFT_SAMPLES;
    const unsigned int lows = (count + 1u) / 2u;
    const unsigned int highs = count / 2u;
    BitwiseLift *const steps = (BitwiseLift *)calloc(1u, sizeof(BitwiseLift));
    if (steps == NULL)
    {
        bitwise_check(results, 0, "the lifting is held");
        return;
    }
    unsigned int sample[BITWISE_TEST_LIFT_SAMPLES];
    unsigned int field_bits[BITWISE_TEST_LIFT_SAMPLES];
    unsigned int field_offset[BITWISE_TEST_LIFT_SAMPLES];
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        sample[at] = bitwise_lift_append(steps, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
        field_bits[at] = 16u;
        field_offset[at] = 16u * at;
    }
    // forward: the high d_j = x_(2j+1) - floor((x_2j + x_(2j+2)) / 2), the edge repeating x_2j
    unsigned int high[BITWISE_TEST_LIFT_SAMPLES];
    for (unsigned int j = 0u; j < highs; j += 1u)
    {
        const unsigned int left = sample[2u * j];
        const unsigned int right = ((2u * j) + 2u < count) ? sample[(2u * j) + 2u] : left;
        const unsigned int pair = bitwise_lift_append(steps, ENGINE_RECORD_SUM, left, right);
        high[j] = bitwise_lift_append(steps, ENGINE_RECORD_DIFFERENCE, sample[(2u * j) + 1u],
                                      bitwise_floor_shift(steps, pair, 1u));
    }
    // the low s_i = x_2i + floor((d_(i-1) + d_i + 2) / 4), the edges repeating their neighbor
    const unsigned int two = bitwise_lift_append(steps, ENGINE_RECORD_CONSTANT, 2u, 0u);
    unsigned int low[BITWISE_TEST_LIFT_SAMPLES];
    for (unsigned int i = 0u; i < lows; i += 1u)
    {
        const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
        const unsigned int after = (i < highs) ? high[i] : before;
        const unsigned int pair = bitwise_lift_append(steps, ENGINE_RECORD_SUM, before, after);
        const unsigned int rounded = bitwise_lift_append(steps, ENGINE_RECORD_SUM, pair, two);
        low[i] = bitwise_lift_append(steps, ENGINE_RECORD_SUM, sample[2u * i], bitwise_floor_shift(steps, rounded, 2u));
    }
    // inverse, read from the forward floor only: x_2i = s_i - floor((d_(i-1) + d_i + 2) / 4), then
    // x_(2j+1) = d_j + floor((x_2j + x_(2j+2)) / 2)
    unsigned int even[BITWISE_TEST_LIFT_SAMPLES];
    for (unsigned int i = 0u; i < lows; i += 1u)
    {
        const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
        const unsigned int after = (i < highs) ? high[i] : before;
        const unsigned int pair = bitwise_lift_append(steps, ENGINE_RECORD_SUM, before, after);
        const unsigned int rounded = bitwise_lift_append(steps, ENGINE_RECORD_SUM, pair, two);
        even[i] = bitwise_lift_append(steps, ENGINE_RECORD_DIFFERENCE, low[i], bitwise_floor_shift(steps, rounded, 2u));
    }
    unsigned int rebuilt[BITWISE_TEST_LIFT_SAMPLES];
    for (unsigned int j = 0u; j < highs; j += 1u)
    {
        const unsigned int left = even[j];
        const unsigned int right = (j + 1u < lows) ? even[j + 1u] : left;
        const unsigned int pair = bitwise_lift_append(steps, ENGINE_RECORD_SUM, left, right);
        rebuilt[(2u * j) + 1u] =
            bitwise_lift_append(steps, ENGINE_RECORD_SUM, high[j], bitwise_floor_shift(steps, pair, 1u));
        rebuilt[2u * j] = even[j];
    }
    // the outputs: s_0..s_3, d_0..d_3, then the rebuilt x_0..x_7
    unsigned int outputs[BITWISE_TEST_LIFT_OUTPUTS];
    unsigned int output_count = 0u;
    for (unsigned int i = 0u; i < lows; i += 1u)
    {
        outputs[output_count] = low[i];
        output_count += 1u;
    }
    for (unsigned int j = 0u; j < highs; j += 1u)
    {
        outputs[output_count] = high[j];
        output_count += 1u;
    }
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        outputs[output_count] = rebuilt[at];
        output_count += 1u;
    }
    BitwiseLoaded loaded;
    memset(&loaded, 0, sizeof(loaded));
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {(16u * count) / 32u, 0u, 0u};
    const KeymathRecordRequest encode_request = {
        steps->steps, steps->count, field_bits, count, 1u, outputs, output_count, NULL, 0u, &loaded.key, &loaded.error};
    const KeyScheduleRecordRequest layout_request = {&loaded.key, field_offset,   count,        in_limbs,
                                                     1,           &loaded.layout, &loaded.error};
    int loads = keymath_record_encode(&encode_request) != KEYMATH_ERROR;
    loads = loads && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
    loads = loads && (cycle_record_load(&loaded.layout, &loaded.record, &loaded.error) != CYCLE_ERROR);
    bitwise_check(results, loads, "one 5/3 lifting level and its inverse encode as one stack");
    if (loads == 0)
    {
        free(steps);
        return;
    }
    const unsigned int lanes = BITWISE_TEST_LIFT_LANES;
    const unsigned int record_limbs = in_limbs[0];
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * record_limbs, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int pattern = bitwise_random();
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            bitwise_field_fill(&atoms[(size_t)lane * record_limbs], field_offset[at], 16u, pattern >> (3u * (at % 8u)));
        }
    }
    int host_ran = 0;
    int device_ran = 0;
    if (buffers != 0)
    {
        bitwise_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    }
    unsigned int coefficients_ok = 0u;
    unsigned int rebuilt_ok = 0u;
    for (unsigned int lane = 0u; (host_ran != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const atom = &atoms[(size_t)lane * record_limbs];
        long long x[BITWISE_TEST_LIFT_SAMPLES];
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            // a 16-bit field read signed: 2^16 comes off where its top bit is set
            const unsigned int raw = (atom[(16u * at) / 32u] >> ((16u * at) % 32u)) & 0xFFFFu;
            x[at] = ((raw & 0x8000u) != 0u) ? ((long long)raw - 65536ll) : (long long)raw;
        }
        long long d[BITWISE_TEST_LIFT_SAMPLES];
        for (unsigned int j = 0u; j < highs; j += 1u)
        {
            const long long left = x[2u * j];
            const long long right = ((2u * j) + 2u < count) ? x[(2u * j) + 2u] : left;
            d[j] = x[(2u * j) + 1u] - bitwise_tower_shift(left + right, 1u);
        }
        long long expected[2u * BITWISE_TEST_LIFT_SAMPLES];
        for (unsigned int i = 0u; i < lows; i += 1u)
        {
            const long long before = (i > 0u) ? d[i - 1u] : d[0];
            const long long after = (i < highs) ? d[i] : before;
            expected[i] = x[2u * i] + bitwise_tower_shift(before + after + 2ll, 2u);
        }
        for (unsigned int j = 0u; j < highs; j += 1u)
        {
            expected[lows + j] = d[j];
        }
        int coefficients = 1;
        int samples = 1;
        for (unsigned int output = 0u; output < output_count; output += 1u)
        {
            const DeviceRecordStep *const step = &loaded.layout.step_table[outputs[output]];
            AnchorExactInteger value;
            bitwise_take(&device_out[(size_t)lane * out_limbs], step->out_offset, step->out_bits, &value);
            // every coefficient and sample lies below 2^20 in magnitude, one limb
            const long long read = (long long)value.sign * (long long)value.limb[0];
            if (output < count)
            {
                coefficients = coefficients && (read == expected[output]);
            }
            else
            {
                samples = samples && (read == x[output - count]);
            }
        }
        coefficients_ok += (coefficients != 0) ? 1u : 0u;
        rebuilt_ok += (samples != 0) ? 1u : 0u;
    }
    scriptura_text(&results->line, "  lifting: one 5/3 level and its inverse, ");
    scriptura_decimal(&results->line, steps->count, 1u);
    scriptura_text(&results->line, " steps, file ");
    scriptura_decimal(&results->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs; ");
    scriptura_decimal(&results->line, coefficients_ok, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes equal tower_*.cu's coefficients, ");
    scriptura_decimal(&results->line, rebuilt_ok, 1u);
    scriptura_text(&results->line, " rebuilt exactly\n");
    bitwise_check(results,
                  (host_ran != 0) && (device_ran != 0) &&
                      (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                  "the lifting's device records equal the host's word for word");
    bitwise_check(results, coefficients_ok == lanes, "the record floor's coefficients equal tower_*.cu's 5/3 lifting");
    bitwise_check(results, rebuilt_ok == lanes, "the inverse floor returns every sample exactly");
    free(atoms);
    free(host_out);
    free(device_out);
    free(steps);
    bitwise_free(&loaded);
}

int main(int count, char **arguments)
{
    BitwiseResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = BITWISE_TEST_LINE;
    results.line.out = (char *)malloc((size_t)BITWISE_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_bitwise_test", count, arguments, BITWISE_TEST_DECLARED);
    if (admitted != 0)
    {
        bitwise_known(&results);
        bitwise_narrow(&results);
        bitwise_narrowed(&results);
        bitwise_wide(&results);
        bitwise_refused(&results);
        bitwise_stack(&results);
        bitwise_lifting(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    bitwise_check(&results, (admitted != 0) && (job.failures == 0ull),
                  "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record bitwise test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
