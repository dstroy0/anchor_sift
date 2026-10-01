// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// double_fields' ribosome held 1:1 against double_fields.c. The record program double_fields_record fills is encoded,
// laid out and loaded by the calls engine_record_encode makes, swept on the device and run on the host, and every
// lane's four answers are checked against double_fields_sign, double_fields_exp, double_fields_mant and
// double_fields_merge on the same words. The lanes are the edges of a double, every field at its least and most,
// and drawn words; a merge's request carries words past every mask: the masking is asked as well. The test is
// one job on the device's tessera daemon.
#include "codegen_device.h"
#include "cycle.h"
#include "double_fields.h"
#include "key_schedule.h"
#include "keymath.h"
#include "scriptura.h"
#include "sim.h"
#include <cuda_runtime.h>
#include <stdlib.h>
#include <string.h>

#define DOUBLE_FIELDS_TEST_LINE 4096ull
#define DOUBLE_FIELDS_TEST_DRAWN 4096u
#define DOUBLE_FIELDS_TEST_EDGES 14u
#define DOUBLE_FIELDS_TEST_LANES (DOUBLE_FIELDS_TEST_EDGES + DOUBLE_FIELDS_TEST_DRAWN)

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} DoubleFieldsTestResults;

static void double_fields_test_check(DoubleFieldsTestResults *results, int passed, const char *what)
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

// `bits` bits of a record at `offset`, which the program never makes negative: the low 64 bits, and in `above`
// whether any bit past the 64th is set
static unsigned long long double_fields_test_take(const unsigned int *record, unsigned int offset, unsigned int bits,
                                                  int *above)
{
    unsigned long long word = 0ull;
    *above = 0;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        const unsigned int set = (record[from / 32u] >> (from % 32u)) & 1u;
        if (bit < 64u)
        {
            word |= (unsigned long long)set << bit;
        }
        else if (set != 0u)
        {
            *above = 1;
        }
    }
    return word;
}

// xorshift64: the drawn words, the same on every run
static unsigned long long double_fields_test_draw(unsigned long long *state)
{
    unsigned long long value = *state;
    value ^= value << 13u;
    value ^= value >> 7u;
    value ^= value << 17u;
    *state = value;
    return value;
}

// double_fields.c's answer for one request, the request laid out as the header lays it: the bits, then the sign, the
// exponent and the mantissa
static void double_fields_test_reference(unsigned long long bits, unsigned long long sign, unsigned long long exp,
                                         unsigned long long mant, unsigned long long answer[DOUBLE_FIELDS_RECORD_OUTPUTS])
{
    unsigned long long laid[4] = {bits, sign, exp, mant};
    static_assert(sizeof(DoubleFieldsRequest) == sizeof(laid), "DoubleFieldsRequest is not four words");
    const DoubleFieldsRequest *const request = (const DoubleFieldsRequest *)laid;
    answer[0] = double_fields_sign(request);
    answer[1] = double_fields_exp(request);
    answer[2] = double_fields_mant(request);
    answer[3] = double_fields_merge(request);
}

int main(int count, char **arguments)
{
    DoubleFieldsTestResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = DOUBLE_FIELDS_TEST_LINE;
    results.line.out = (char *)malloc((size_t)DOUBLE_FIELDS_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);

    EngineRecordRequest program;
    memset(&program, 0, sizeof(program));
    double_fields_test_check(&results, double_fields_record(&program) == 0L, "double_fields_record fills its program");
    double_fields_test_check(&results, double_fields_record(NULL) != 0L, "double_fields_record refuses no request");
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineRecordKey math;
    const KeymathRecordRequest encode_request = {program.steps,   program.count,        program.field_bits,
                                                 program.fields,  program.members,      program.outputs,
                                                 program.output_count, program.tables,  program.table_count,
                                                 &math,           &error};
    int ok = (keymath_record_encode(&encode_request) != KEYMATH_ERROR);
    double_fields_test_check(&results, ok, "the program encodes");
    EngineRecordLayout layout;
    memset(&layout, 0, sizeof(layout));
    const KeyScheduleRecordRequest layout_request = {&math, program.field_offset, program.fields, program.in_limbs,
                                                     program.reuse, &layout, &error};
    ok = ok && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
    keymath_record_release(&math);
    double_fields_test_check(&results, ok, "the program lays out");
    const LayoutRequest device_request = {program.steps,   program.count,   program.field_bits, program.field_offset,
                                          program.fields,  program.members, program.in_limbs,   program.outputs,
                                          program.output_count, program.tables, program.table_count, program.reuse};
    ok = ok && (layout_device_held(&device_request, &layout, 0) != 0);
    double_fields_test_check(&results, ok, "the program laid out on the device is the host's layout, word for word");
    unsigned int out_offset[DOUBLE_FIELDS_RECORD_OUTPUTS] = {0u, 0u, 0u, 0u};
    unsigned int out_bits[DOUBLE_FIELDS_RECORD_OUTPUTS] = {0u, 0u, 0u, 0u};
    for (unsigned int output = 0u; ok && (output < DOUBLE_FIELDS_RECORD_OUTPUTS); output += 1u)
    {
        out_offset[output] = layout.step_table[program.outputs[output]].out_offset;
        out_bits[output] = layout.step_table[program.outputs[output]].out_bits;
    }
    CycleRecord *record = NULL;
    ok = ok && (cycle_record_load(&layout, &record, &error) != CYCLE_ERROR);
    double_fields_test_check(&results, ok, "the program loads");
    ok = ok && (sim_job_submit(&job, "double_fields_test", count, arguments,
                               (unsigned long long)DOUBLE_FIELDS_TEST_LANES * 6ull * sizeof(unsigned int)) != 0);

    // the lanes: member 0 a double's low and high words, member 1 a merge's sign, exponent and mantissa words
    static const unsigned long long s_edges[DOUBLE_FIELDS_TEST_EDGES] = {
        0x0000000000000000ull, 0x8000000000000000ull, 0x3FF0000000000000ull, 0xC004000000000000ull,
        0x7FF0000000000000ull, 0xFFF0000000000000ull, 0x7FF8000000000000ull, 0x7FF0000000000001ull,
        0x0000000000000001ull, 0x000FFFFFFFFFFFFFull, 0x0010000000000000ull, 0x7FEFFFFFFFFFFFFFull,
        0xFFFFFFFFFFFFFFFFull, 0x00000000FFFFFFFFull};
    const unsigned int out_limbs = layout.out_limbs;
    unsigned int *const bits = (unsigned int *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * 2u, sizeof(unsigned int));
    unsigned int *const merges = (unsigned int *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * 4u, sizeof(unsigned int));
    unsigned int *const index = (unsigned int *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * 2u, sizeof(unsigned int));
    unsigned int *const host_out =
        (unsigned int *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * (out_limbs + 1u), sizeof(unsigned int));
    unsigned int *const device_answer =
        (unsigned int *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * (out_limbs + 1u), sizeof(unsigned int));
    unsigned long long *const words = (unsigned long long *)calloc((size_t)DOUBLE_FIELDS_TEST_LANES * 4u,
                                                                   sizeof(unsigned long long));
    ok = ok && (bits != NULL) && (merges != NULL) && (index != NULL) && (host_out != NULL) && (device_answer != NULL) &&
         (words != NULL);
    unsigned long long state = 0x9E3779B97F4A7C15ull;
    for (unsigned int lane = 0u; ok && (lane < DOUBLE_FIELDS_TEST_LANES); lane += 1u)
    {
        const unsigned long long value = (lane < DOUBLE_FIELDS_TEST_EDGES) ? s_edges[lane]
                                                                           : double_fields_test_draw(&state);
        const unsigned long long sign = (lane < DOUBLE_FIELDS_TEST_EDGES) ? (unsigned long long)lane
                                                                          : (double_fields_test_draw(&state) >> 32u);
        const unsigned long long exp = (lane < DOUBLE_FIELDS_TEST_EDGES) ? (0x7FEull + lane)
                                                                         : (double_fields_test_draw(&state) >> 32u);
        const unsigned long long mant = (lane < DOUBLE_FIELDS_TEST_EDGES) ? ~s_edges[lane]
                                                                          : double_fields_test_draw(&state);
        words[lane * 4u] = value;
        words[lane * 4u + 1u] = sign;
        words[lane * 4u + 2u] = exp;
        words[lane * 4u + 3u] = mant;
        bits[lane * 2u] = (unsigned int)(value & 0xFFFFFFFFull);
        bits[lane * 2u + 1u] = (unsigned int)(value >> 32u);
        merges[lane * 4u] = (unsigned int)sign;
        merges[lane * 4u + 1u] = (unsigned int)exp;
        merges[lane * 4u + 2u] = (unsigned int)(mant & 0xFFFFFFFFull);
        merges[lane * 4u + 3u] = (unsigned int)(mant >> 32u);
        index[lane * 2u] = lane;
        index[lane * 2u + 1u] = lane;
    }

    unsigned int *device_bits = NULL;
    unsigned int *device_merges = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    const size_t out_bytes = (size_t)DOUBLE_FIELDS_TEST_LANES * out_limbs * sizeof(unsigned int);
    ok = ok && (cudaMalloc((void **)&device_bits, (size_t)DOUBLE_FIELDS_TEST_LANES * 2u * sizeof(unsigned int)) ==
                cudaSuccess) &&
         (cudaMalloc((void **)&device_merges, (size_t)DOUBLE_FIELDS_TEST_LANES * 4u * sizeof(unsigned int)) ==
          cudaSuccess) &&
         (cudaMalloc((void **)&device_index, (size_t)DOUBLE_FIELDS_TEST_LANES * 2u * sizeof(unsigned int)) ==
          cudaSuccess) &&
         (cudaMalloc((void **)&device_out, out_bytes) == cudaSuccess) &&
         (cudaMemcpy(device_bits, bits, (size_t)DOUBLE_FIELDS_TEST_LANES * 2u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_merges, merges, (size_t)DOUBLE_FIELDS_TEST_LANES * 4u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_index, index, (size_t)DOUBLE_FIELDS_TEST_LANES * 2u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok)
    {
        const CycleRecordRunRequest run = {record,
                                           {device_bits, device_merges, NULL},
                                           {DOUBLE_FIELDS_TEST_LANES, DOUBLE_FIELDS_TEST_LANES, 0ull},
                                           device_index,
                                           DOUBLE_FIELDS_TEST_LANES,
                                           device_out,
                                           &error};
        ok = (cycle_record_run(&run) == (long)DOUBLE_FIELDS_TEST_LANES) &&
             (cudaMemcpy(device_answer, device_out, out_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    double_fields_test_check(&results, ok, "the ribosome sweeps on the device");
    const CycleRecordHostRequest host = {&layout,
                                         {bits, merges, NULL},
                                         {DOUBLE_FIELDS_TEST_LANES, DOUBLE_FIELDS_TEST_LANES, 0ull},
                                         index,
                                         DOUBLE_FIELDS_TEST_LANES,
                                         host_out,
                                         &error};
    const int host_ran = ok && (cycle_record_run_host(&host) == (long)DOUBLE_FIELDS_TEST_LANES);
    double_fields_test_check(&results, host_ran, "the ribosome runs on the host");
    double_fields_test_check(&results, host_ran && (memcmp(host_out, device_answer, out_bytes) == 0),
                             "the device's answers equal the host's word for word");

    static const char *const s_names[DOUBLE_FIELDS_RECORD_OUTPUTS] = {"double_fields_sign", "double_fields_exp",
                                                                      "double_fields_mant", "double_fields_merge"};
    unsigned long long wrong[DOUBLE_FIELDS_RECORD_OUTPUTS] = {0ull, 0ull, 0ull, 0ull};
    for (unsigned int lane = 0u; host_ran && (lane < DOUBLE_FIELDS_TEST_LANES); lane += 1u)
    {
        unsigned long long answer[DOUBLE_FIELDS_RECORD_OUTPUTS];
        double_fields_test_reference(words[lane * 4u], words[lane * 4u + 1u], words[lane * 4u + 2u],
                                     words[lane * 4u + 3u], answer);
        for (unsigned int output = 0u; output < DOUBLE_FIELDS_RECORD_OUTPUTS; output += 1u)
        {
            int above = 0;
            const unsigned long long ribosome = double_fields_test_take(&device_answer[(size_t)lane * out_limbs],
                                                                        out_offset[output], out_bits[output], &above);
            if ((ribosome != answer[output]) || (above != 0))
            {
                wrong[output] += 1ull;
            }
        }
    }
    for (unsigned int output = 0u; output < DOUBLE_FIELDS_RECORD_OUTPUTS; output += 1u)
    {
        char what[160];
        snprintf(what, sizeof(what), "%s: the ribosome answers what double_fields.c answers on every lane (%llu wrong)",
                 s_names[output], wrong[output]);
        double_fields_test_check(&results, host_ran && (wrong[output] == 0ull), what);
    }

    cudaFree(device_bits);
    cudaFree(device_merges);
    cudaFree(device_index);
    cudaFree(device_out);
    free(bits);
    free(merges);
    free(index);
    free(host_out);
    free(device_answer);
    free(words);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    key_schedule_record_release(&layout);
    sim_job_release(&job);
    sim_flush(&job);
    double_fields_test_check(&results, (job.checks == 2ull) && (job.failures == 0ull),
                             "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  double fields test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
