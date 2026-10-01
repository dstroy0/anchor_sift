// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The record programs' speed. Three programs of the kinds the engine runs, each over 2^22 lanes, each timed on the
// host around cycle_record_run, which launches the program and waits for it: the best of five runs. The same binary
// run with CYCLE_RECORD_INTERPRET=1 times the interpreter, and each program says which ran. Every program's first
// 65,536 lanes are checked word for word against the host's records.
// - chain: the Gaussian step's eight floors, a DIFFERENCE and a SUM a floor, over two 24-bit signed fields
// - powers: x to x^8 by products, then their sum, over one 32-bit field: the products reach 8 limbs
// - mix: six rounds of a xor, a product by a constant, a sum and a 32-bit wrap over two 32-bit fields, then the golden
//   ladder of the last pair
// The test is one job on the device's tessera daemon, submitted before the first program is loaded onto the device.
#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"
#include "sim.h"

#include <chrono>

#define SPEED_TEST_LANES (1u << 22u)

#define SPEED_TEST_CHECKED 65536u

#define SPEED_TEST_RUNS 5u

#define SPEED_TEST_PROGRAMS 3u

#define SPEED_TEST_STEPS_MAX 64u

#define SPEED_TEST_FLOORS 8u

#define SPEED_TEST_POWERS 8u

#define SPEED_TEST_ROUNDS 6u

#define SPEED_TEST_KEY 0x5EEDC0DE5EEDC0DEull

typedef struct
{
    const char *name;
    EngineRecordStep steps[SPEED_TEST_STEPS_MAX];
    unsigned int step_count;
    unsigned int outputs[SPEED_TEST_STEPS_MAX];
    unsigned int output_count;
    unsigned int field_bits[2];
    unsigned int field_offset[2];
    unsigned int fields;
    unsigned int in_limbs;
} SpeedProgram;

// z = a + b i in fields 0 and 1; floor k writes a - b at step 2k and a + b at step 2k + 1; the last floor is read out
static void speed_chain(SpeedProgram *program)
{
    program->name = "chain";
    program->steps[0] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u};
    program->steps[1] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u};
    for (unsigned int level = 1u; level <= SPEED_TEST_FLOORS; level += 1u)
    {
        const unsigned int real_before = 2u * (level - 1u);
        program->steps[2u * level] = EngineRecordStep{ENGINE_RECORD_DIFFERENCE, real_before, real_before + 1u, 0u};
        program->steps[(2u * level) + 1u] = EngineRecordStep{ENGINE_RECORD_SUM, real_before, real_before + 1u, 0u};
    }
    program->step_count = 2u + (2u * SPEED_TEST_FLOORS);
    program->outputs[0] = 2u * SPEED_TEST_FLOORS;
    program->outputs[1] = (2u * SPEED_TEST_FLOORS) + 1u;
    program->output_count = 2u;
    program->field_bits[0] = 24u;
    program->field_bits[1] = 24u;
    program->field_offset[0] = 0u;
    program->field_offset[1] = 32u;
    program->fields = 2u;
    program->in_limbs = 2u;
}

// steps 0 to 7 are x to x^8, each power the one before times x; steps 8 to 14 sum them, and the sum is read out
static void speed_powers(SpeedProgram *program)
{
    program->name = "powers";
    program->steps[0] = EngineRecordStep{ENGINE_RECORD_FIELD, 0u, 0u, 0u};
    for (unsigned int power = 1u; power < SPEED_TEST_POWERS; power += 1u)
    {
        program->steps[power] = EngineRecordStep{ENGINE_RECORD_PRODUCT, power - 1u, 0u, 0u};
    }
    program->steps[SPEED_TEST_POWERS] = EngineRecordStep{ENGINE_RECORD_SUM, 0u, 1u, 0u};
    for (unsigned int power = 2u; power < SPEED_TEST_POWERS; power += 1u)
    {
        const unsigned int at = SPEED_TEST_POWERS + power - 1u;
        program->steps[at] = EngineRecordStep{ENGINE_RECORD_SUM, at - 1u, power, 0u};
    }
    program->step_count = (2u * SPEED_TEST_POWERS) - 1u;
    program->outputs[0] = program->step_count - 1u;
    program->output_count = 1u;
    program->field_bits[0] = 32u;
    program->field_offset[0] = 0u;
    program->fields = 1u;
    program->in_limbs = 1u;
}

// a and b in fields 0 and 1, the golden ratio's word a constant; a round is x = a xor b, then the wrap of x times the
// constant plus b to 32 bits, the next a, and x is the next b. The last pair is read out, then the ladder of
// |a| over |b| + 1, whose denominator is never 0
static void speed_mix(SpeedProgram *program)
{
    program->name = "mix";
    program->steps[0] = EngineRecordStep{ENGINE_RECORD_FIELD, 0u, 0u, 0u};
    program->steps[1] = EngineRecordStep{ENGINE_RECORD_FIELD, 1u, 0u, 0u};
    program->steps[2] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 0x9E3779B9u, 0u, 0u};
    unsigned int left = 0u;
    unsigned int right = 1u;
    for (unsigned int round = 0u; round < SPEED_TEST_ROUNDS; round += 1u)
    {
        const unsigned int mixed = 3u + (4u * round);
        program->steps[mixed] = EngineRecordStep{ENGINE_RECORD_XOR, left, right, 0u};
        program->steps[mixed + 1u] = EngineRecordStep{ENGINE_RECORD_PRODUCT, mixed, 2u, 0u};
        program->steps[mixed + 2u] = EngineRecordStep{ENGINE_RECORD_SUM, mixed + 1u, right, 0u};
        program->steps[mixed + 3u] = EngineRecordStep{ENGINE_RECORD_WRAP, mixed + 2u, 32u, 0u};
        left = mixed + 3u;
        right = mixed;
    }
    const unsigned int after = 3u + (4u * SPEED_TEST_ROUNDS);
    program->steps[after] = EngineRecordStep{ENGINE_RECORD_ABSOLUTE, right, 0u, 0u};
    program->steps[after + 1u] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 1u, 0u, 0u};
    program->steps[after + 2u] = EngineRecordStep{ENGINE_RECORD_SUM, after, after + 1u, 0u};
    program->steps[after + 3u] = EngineRecordStep{ENGINE_RECORD_ABSOLUTE, left, 0u, 0u};
    program->steps[after + 4u] = EngineRecordStep{ENGINE_RECORD_LADDER, after + 3u, after + 2u, 0u};
    program->step_count = after + 5u;
    program->outputs[0] = left;
    program->outputs[1] = right;
    program->outputs[2] = after + 4u;
    program->output_count = 3u;
    program->field_bits[0] = 32u;
    program->field_bits[1] = 32u;
    program->field_offset[0] = 0u;
    program->field_offset[1] = 32u;
    program->fields = 2u;
    program->in_limbs = 2u;
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);

    static SpeedProgram programs[SPEED_TEST_PROGRAMS];
    speed_chain(&programs[0]);
    speed_powers(&programs[1]);
    speed_mix(&programs[2]);
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineRecordKey keys[SPEED_TEST_PROGRAMS];
    EngineRecordLayout layouts[SPEED_TEST_PROGRAMS];
    memset(keys, 0, sizeof(keys));
    memset(layouts, 0, sizeof(layouts));
    int ok = 1;
    unsigned int in_limbs_max = 0u;
    unsigned int out_limbs_max = 0u;
    for (unsigned int at = 0u; (ok != 0) && (at < SPEED_TEST_PROGRAMS); at += 1u)
    {
        const SpeedProgram *const program = &programs[at];
        const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {program->in_limbs, 0u, 0u};
        const KeymathRecordRequest encode_request = {program->steps,
                                                     program->step_count,
                                                     program->field_bits,
                                                     program->fields,
                                                     1u,
                                                     program->outputs,
                                                     program->output_count,
                                                     NULL,
                                                     0u,
                                                     &keys[at],
                                                     &error};
        ok = keymath_record_encode(&encode_request) != KEYMATH_ERROR;
        const KeyScheduleRecordRequest layout_request = {&keys[at], program->field_offset, program->fields, in_limbs,
                                                         1,         &layouts[at],          &error};
        ok = ok && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
        in_limbs_max = (program->in_limbs > in_limbs_max) ? program->in_limbs : in_limbs_max;
        out_limbs_max = ((ok != 0) && (layouts[at].out_limbs > out_limbs_max)) ? layouts[at].out_limbs : out_limbs_max;
    }
    sim_check(&results, ok, "the three programs encode and lay out");

    // the job declares what the test puts on the device at once: one program's lanes, its records and its steps
    const unsigned long long declared = ((unsigned long long)SPEED_TEST_LANES * in_limbs_max * sizeof(unsigned int)) +
                                        ((unsigned long long)SPEED_TEST_LANES * out_limbs_max * sizeof(unsigned int)) +
                                        ((unsigned long long)SPEED_TEST_STEPS_MAX * sizeof(DeviceRecordStep));
    ok = ok && sim_job_submit(&results, "record_speed_test", count, arguments, declared);

    unsigned int *const atoms =
        (unsigned int *)calloc((size_t)SPEED_TEST_LANES * in_limbs_max + 1u, sizeof(unsigned int));
    unsigned int *const host_out =
        (unsigned int *)calloc((size_t)SPEED_TEST_CHECKED * out_limbs_max + 1u, sizeof(unsigned int));
    unsigned int *const device_out =
        (unsigned int *)calloc((size_t)SPEED_TEST_CHECKED * out_limbs_max + 1u, sizeof(unsigned int));
    ok = ok && (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned long long word = 0ull; (ok != 0) && (word < ((unsigned long long)SPEED_TEST_LANES * in_limbs_max));
         word += 1ull)
    {
        // a draw's low half is a whole word
        atoms[word] = (unsigned int)(sim_draw(SPEED_TEST_KEY, word) & 0xFFFFFFFFull);
    }
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    ok = ok &&
         sim_status_check(
             &results,
             cudaMalloc((void **)&device_atoms, (size_t)SPEED_TEST_LANES * in_limbs_max * sizeof(unsigned int)),
             "the lanes' fields on the device") &&
         sim_status_check(
             &results,
             cudaMalloc((void **)&device_record, (size_t)SPEED_TEST_LANES * out_limbs_max * sizeof(unsigned int)),
             "the lanes' records on the device");

    for (unsigned int at = 0u; (ok != 0) && (at < SPEED_TEST_PROGRAMS); at += 1u)
    {
        const SpeedProgram *const program = &programs[at];
        const EngineRecordLayout *const layout = &layouts[at];
        const size_t in_words = (size_t)SPEED_TEST_LANES * program->in_limbs;
        CycleRecord *record = NULL;
        int loaded =
            sim_status_check(&results,
                             cudaMemcpy(device_atoms, atoms, in_words * sizeof(unsigned int), cudaMemcpyHostToDevice),
                             "the fields copied to the device") &&
            (cycle_record_load(layout, &record, &error) != CYCLE_ERROR);
        sim_check(&results, loaded, program->name);
        unsigned long long best = ~0ull;
        int ran = loaded;
        const CycleRecordRunRequest run = {record, {device_atoms, NULL, NULL}, {SPEED_TEST_LANES, 0ull, 0ull},
                                           NULL,   SPEED_TEST_LANES,           device_record,
                                           &error};
        for (unsigned int each = 0u; (ran != 0) && (each < SPEED_TEST_RUNS); each += 1u)
        {
            const auto began = std::chrono::steady_clock::now();
            ran = cycle_record_run(&run) == (long)SPEED_TEST_LANES;
            const auto ended = std::chrono::steady_clock::now();
            // a run's microseconds are a count of ticks, never negative
            const unsigned long long elapsed =
                (unsigned long long)std::chrono::duration_cast<std::chrono::microseconds>(ended - began).count();
            best = (elapsed < best) ? elapsed : best;
        }
        sim_check(&results, ran, "every run takes every lane, none errored");
        const size_t checked_words = (size_t)SPEED_TEST_CHECKED * layout->out_limbs;
        const CycleRecordHostRequest host = {
            layout, {atoms, NULL, NULL}, {SPEED_TEST_LANES, 0ull, 0ull}, NULL, SPEED_TEST_CHECKED, host_out, &error};
        const int same = (ran != 0) &&
                         sim_status_check(&results,
                                          cudaMemcpy(device_out, device_record, checked_words * sizeof(unsigned int),
                                                     cudaMemcpyDeviceToHost),
                                          "the records copied back") &&
                         (cycle_record_run_host(&host) == (long)SPEED_TEST_CHECKED) &&
                         (memcmp(host_out, device_out, checked_words * sizeof(unsigned int)) == 0);
        sim_check(&results, same, "the device's first 65,536 records equal the host's word for word");
        if ((ran != 0) && (best != 0ull))
        {
            scriptura_text(&results.line, "  ");
            scriptura_text(&results.line, program->name);
            scriptura_text(&results.line, ": ");
            scriptura_decimal(&results.line, program->step_count, 1u);
            scriptura_text(&results.line, " steps, ");
            scriptura_decimal(&results.line, layout->file_limbs, 1u);
            scriptura_text(&results.line, " file limbs, ");
            scriptura_decimal(&results.line, layout->out_limbs, 1u);
            scriptura_text(&results.line, " record limbs; ");
            scriptura_text(&results.line, (cycle_record_compiled(record) != 0) ? "compiled" : "interpreted");
            scriptura_text(&results.line, ", the best of 5 runs over ");
            scriptura_decimal(&results.line, SPEED_TEST_LANES, 1u);
            scriptura_text(&results.line, " lanes: ");
            sim_fraction_print(&results.line, best, 1000ull, 3u);
            scriptura_text(&results.line, " ms, ");
            sim_fraction_print(&results.line, SPEED_TEST_LANES, best, 1u);
            scriptura_text(&results.line, " million lanes a second\n");
        }
        if (record != NULL)
        {
            cycle_record_release(record);
        }
        ok = loaded;
    }

    cudaFree(device_atoms);
    cudaFree(device_record);
    free(atoms);
    free(host_out);
    free(device_out);
    for (unsigned int at = 0u; at < SPEED_TEST_PROGRAMS; at += 1u)
    {
        key_schedule_record_release(&layouts[at]);
        keymath_record_release(&keys[at]);
    }
    return sim_close(&results, "record speed test");
}
