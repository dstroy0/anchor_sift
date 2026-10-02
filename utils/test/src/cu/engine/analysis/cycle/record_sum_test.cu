// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The sum across lanes. cycle_record_sum reads a field of every record in device memory and returns, for each run of
// consecutive records, their exact sum as two's complement: each 32-bit limb summed into 64 bits by the records of a
// thread and one atomic add a run, the negative fields counted beside, and the carries and the sign taken on the host.
// cycle_record_sum_host adds the same records in order, each sign-extended. The two must agree word for word, and both
// must equal closed forms:
// - a record program's lane number l over 2^22 lanes: sum l = L(L - 1) / 2, sum -l, sum l^2 = (L - 1) L (2L - 1) / 6,
//   which passes 2^64, and sum -l^2, over all the lanes and over runs of 2^16, each run its own closed form;
// - random records of nine limbs, fields one bit wide, across two limbs, a whole limb, two hundred bits and the whole
//   record, over runs of 1, 3, 1024 and every record;
// - every field at its most negative and at its most positive, the sums' two ends.
// A request whose sums cannot hold the run's total, whose count is not a whole number of runs, or whose run passes
// 2^32 records errors on both routes before a record is read. The test is one job on the device's tessera daemon.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SUM_TEST_LINE 8192ull

#define SUM_TEST_STEPS 8u

#define SUM_TEST_OUTPUTS 4u

// the lanes of the record program: l^2 summed over them passes 2^64
#define SUM_TEST_LANES (1ull << 22u)

// the runs the program's lanes are cut into
#define SUM_TEST_RUN (1ull << 16u)

// the random records: three times 2^14, so that runs of 3 divide them
#define SUM_TEST_RECORDS (3ull * (1ull << 14u))

#define SUM_TEST_RECORD_LIMBS 9u

// the sums' limbs: 9 limbs of field and the bits of 2^32 records beside them
#define SUM_TEST_SUM_LIMBS 11u

#define SUM_TEST_FIELDS 6u

#define SUM_TEST_GROUPS 4u

// the most the test puts on the device at once: the program's records, with room beside for the small allocations
#define SUM_TEST_DECLARED ((SUM_TEST_LANES * 8ull * sizeof(unsigned int)) + (16ull << 20u))

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} SumResults;

static unsigned long long s_sum_state = 0x5EED5A1E5C0FFEE1ull;

static unsigned long long sum_random(void)
{
    s_sum_state ^= s_sum_state << 13u;
    s_sum_state ^= s_sum_state >> 7u;
    s_sum_state ^= s_sum_state << 17u;
    return s_sum_state;
}

static void sum_check(SumResults *results, int passed, const char *what)
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

// ---- small exact arithmetic on limbs, for the closed forms ----

static void limbs_set(unsigned int *value, unsigned int limbs, unsigned long long low)
{
    memset(value, 0, limbs * sizeof(unsigned int));
    value[0] = (unsigned int)low;
    value[1] = (unsigned int)(low >> 32u);
}

static void limbs_multiply(unsigned int *value, unsigned int limbs, unsigned int factor)
{
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        carry += (unsigned long long)value[limb] * factor;
        value[limb] = (unsigned int)carry;
        carry >>= 32u;
    }
}

static void limbs_divide(unsigned int *value, unsigned int limbs, unsigned int divisor)
{
    unsigned long long remainder = 0ull;
    for (unsigned int limb = limbs; limb > 0u; limb -= 1u)
    {
        const unsigned long long part = (remainder << 32u) | value[limb - 1u];
        value[limb - 1u] = (unsigned int)(part / divisor);
        remainder = part % divisor;
    }
}

static void limbs_add(unsigned int *value, unsigned int limbs, const unsigned int *other)
{
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        carry += (unsigned long long)value[limb] + other[limb];
        value[limb] = (unsigned int)carry;
        carry >>= 32u;
    }
}

static void limbs_negate(unsigned int *value, unsigned int limbs)
{
    unsigned long long carry = 1ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        carry += (unsigned long long)(~value[limb]);
        value[limb] = (unsigned int)carry;
        carry >>= 32u;
    }
}

// sum over l from first to first + count - 1 of l, and of l^2, each into `limbs` limbs
static void sum_closed(unsigned long long first, unsigned long long count, unsigned int *linear, unsigned int *square,
                       unsigned int limbs)
{
    unsigned int upper[SUM_TEST_SUM_LIMBS];
    unsigned int lower[SUM_TEST_SUM_LIMBS];
    // sum l below n is n (n - 1) / 2, and sum l^2 below n is (n - 1) n (2n - 1) / 6
    const unsigned long long ends[2] = {first + count, first};
    unsigned int *const parts[2] = {upper, lower};
    for (unsigned int side = 0u; side < 2u; side += 1u)
    {
        const unsigned long long n = ends[side];
        unsigned int *const target = parts[side];
        limbs_set(target, limbs, n);
        limbs_multiply(target, limbs, (unsigned int)((n == 0ull) ? 0ull : (n - 1ull)));
        limbs_divide(target, limbs, 2u);
        if (side == 0u)
        {
            memcpy(linear, target, limbs * sizeof(unsigned int));
        }
        else
        {
            limbs_negate(target, limbs);
            limbs_add(linear, limbs, target);
        }
        limbs_set(target, limbs, n);
        limbs_multiply(target, limbs, (unsigned int)((n == 0ull) ? 0ull : (n - 1ull)));
        limbs_multiply(target, limbs, (unsigned int)((n == 0ull) ? 0ull : ((2ull * n) - 1ull)));
        limbs_divide(target, limbs, 6u);
        if (side == 0u)
        {
            memcpy(square, target, limbs * sizeof(unsigned int));
        }
        else
        {
            limbs_negate(target, limbs);
            limbs_add(square, limbs, target);
        }
    }
}

// ---- the two routes ----

static long sum_run(int device, const unsigned int *records, unsigned long long count, unsigned long long group,
                    unsigned int out_limbs, unsigned int offset, unsigned int bits, unsigned int sum_limbs,
                    unsigned int *sums, EngineError *error)
{
    const CycleRecordSumRequest request = {records, count, group, out_limbs, offset, bits, sum_limbs, sums, error};
    return (device != 0) ? cycle_record_sum(&request) : cycle_record_sum_host(&request);
}

// ---- a record program's lane number, its negative, its square and its square's negative ----

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} SumLoaded;

static int sum_load(SumLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    EngineRecordStep steps[SUM_TEST_STEPS];
    unsigned int count = 0u;
    steps[count++] = EngineRecordStep{ENGINE_RECORD_LANE, 0u, 0u, 0u};
    steps[count++] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 0u, 0u, 0u};
    steps[count++] = EngineRecordStep{ENGINE_RECORD_DIFFERENCE, 1u, 0u, 0u};
    steps[count++] = EngineRecordStep{ENGINE_RECORD_PRODUCT, 0u, 0u, 0u};
    steps[count++] = EngineRecordStep{ENGINE_RECORD_DIFFERENCE, 1u, 3u, 0u};
    const unsigned int outputs[SUM_TEST_OUTPUTS] = {0u, 2u, 3u, 4u};
    const unsigned int field_bits[1] = {32u};
    const unsigned int field_offset[1] = {0u};
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {1u, 0u, 0u};
    const KeymathRecordRequest encode = {steps,   count,           field_bits, 1u,   1u, outputs, SUM_TEST_OUTPUTS,
                                         NULL,    0u,              &loaded->key, &loaded->error};
    if (keymath_record_encode(&encode) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout = {&loaded->key, field_offset, 1u, in_limbs, 1, &loaded->layout,
                                             &loaded->error};
    if (key_schedule_record_layout(&layout) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    if (cycle_record_load(&loaded->layout, &loaded->record, &loaded->error) == CYCLE_ERROR)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

static void sum_free(SumLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// the four outputs over 2^22 lanes, summed on the device and on the host, over all lanes and over runs of 2^16,
// against the closed forms
static void sum_program(SumResults *results)
{
    SumLoaded loaded;
    const int loaded_ok = sum_load(&loaded);
    sum_check(results, loaded_ok, "the lane program is encoded, laid out and loaded");
    if (loaded_ok == 0)
    {
        return;
    }
    const unsigned int out_limbs = loaded.layout.out_limbs;
    const size_t words = (size_t)SUM_TEST_LANES * out_limbs;
    unsigned int *const out = (unsigned int *)malloc(words * sizeof(unsigned int));
    const unsigned long long runs = SUM_TEST_LANES / SUM_TEST_RUN;
    unsigned int *const device_sums = (unsigned int *)malloc((size_t)runs * SUM_TEST_SUM_LIMBS * sizeof(unsigned int));
    unsigned int *const host_sums = (unsigned int *)malloc((size_t)runs * SUM_TEST_SUM_LIMBS * sizeof(unsigned int));
    unsigned int shared[1] = {0u};
    unsigned int *device_shared = NULL;
    unsigned int *device_out = NULL;
    const CycleRecordRunRequest run = {loaded.record, {NULL, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, SUM_TEST_LANES,
                                       NULL,          &loaded.error};
    CycleRecordRunRequest sweep = run;
    int ok = (out != NULL) && (device_sums != NULL) && (host_sums != NULL) &&
             (cudaMalloc((void **)&device_shared, sizeof(shared)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_out, words * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess);
    sweep.device_in[0] = device_shared;
    sweep.device_out = device_out;
    ok = ok && (cycle_record_run(&sweep) != CYCLE_ERROR) &&
         (cudaMemcpy(out, device_out, words * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);
    sum_check(results, ok, "the lane program sweeps 2^22 lanes on the device");
    const char *const names[SUM_TEST_OUTPUTS] = {"l", "-l", "l^2", "-l^2"};
    const unsigned int output_steps[SUM_TEST_OUTPUTS] = {0u, 2u, 3u, 4u};
    unsigned int linear[SUM_TEST_SUM_LIMBS];
    unsigned int square[SUM_TEST_SUM_LIMBS];
    for (unsigned int output = 0u; (ok != 0) && (output < SUM_TEST_OUTPUTS); output += 1u)
    {
        const DeviceRecordStep *const step = &loaded.layout.step_table[output_steps[output]];
        for (unsigned int cut = 0u; cut < 2u; cut += 1u)
        {
            const unsigned long long group = (cut == 0u) ? SUM_TEST_LANES : SUM_TEST_RUN;
            const unsigned long long cut_runs = SUM_TEST_LANES / group;
            EngineError error;
            memset(&error, 0, sizeof(error));
            const int both =
                (sum_run(1, device_out, SUM_TEST_LANES, group, out_limbs, step->out_offset, step->out_bits,
                         SUM_TEST_SUM_LIMBS, device_sums, &error) != CYCLE_ERROR) &&
                (sum_run(0, out, SUM_TEST_LANES, group, out_limbs, step->out_offset, step->out_bits,
                         SUM_TEST_SUM_LIMBS, host_sums, &error) != CYCLE_ERROR);
            int same = both;
            int closed = both;
            for (unsigned long long r = 0ull; (both != 0) && (r < cut_runs); r += 1ull)
            {
                sum_closed(r * group, group, linear, square, SUM_TEST_SUM_LIMBS);
                unsigned int *const expected = (output < 2u) ? linear : square;
                if ((output % 2u) == 1u)
                {
                    limbs_negate(expected, SUM_TEST_SUM_LIMBS);
                }
                same = same && (memcmp(&device_sums[r * SUM_TEST_SUM_LIMBS], &host_sums[r * SUM_TEST_SUM_LIMBS],
                                       SUM_TEST_SUM_LIMBS * sizeof(unsigned int)) == 0);
                closed = closed && (memcmp(&device_sums[r * SUM_TEST_SUM_LIMBS], expected,
                                           SUM_TEST_SUM_LIMBS * sizeof(unsigned int)) == 0);
            }
            char what[160];
            snprintf(what, sizeof(what), "sum of %s over %s: the device equals the host word for word", names[output],
                     (cut == 0u) ? "all 2^22 lanes" : "each run of 2^16");
            sum_check(results, same, what);
            snprintf(what, sizeof(what), "sum of %s over %s equals its closed form", names[output],
                     (cut == 0u) ? "all 2^22 lanes" : "each run of 2^16");
            sum_check(results, closed, what);
        }
    }
    cudaFree(device_shared);
    cudaFree(device_out);
    free(out);
    free(device_sums);
    free(host_sums);
    sum_free(&loaded);
}

// random records of nine limbs, and the sums' two ends
static void sum_records(SumResults *results)
{
    const size_t words = (size_t)SUM_TEST_RECORDS * SUM_TEST_RECORD_LIMBS;
    unsigned int *const records = (unsigned int *)malloc(words * sizeof(unsigned int));
    unsigned int *const device_sums =
        (unsigned int *)malloc((size_t)SUM_TEST_RECORDS * SUM_TEST_SUM_LIMBS * sizeof(unsigned int));
    unsigned int *const host_sums =
        (unsigned int *)malloc((size_t)SUM_TEST_RECORDS * SUM_TEST_SUM_LIMBS * sizeof(unsigned int));
    unsigned int *device_records = NULL;
    int ok = (records != NULL) && (device_sums != NULL) && (host_sums != NULL) &&
             (cudaMalloc((void **)&device_records, words * sizeof(unsigned int)) == cudaSuccess);
    sum_check(results, ok, "the random records are held on the host and the device");
    const unsigned int offsets[SUM_TEST_FIELDS] = {0u, 5u, 30u, 32u, 7u, 0u};
    const unsigned int bits[SUM_TEST_FIELDS] = {1u, 31u, 34u, 32u, 200u, 32u * SUM_TEST_RECORD_LIMBS};
    const unsigned long long groups[SUM_TEST_GROUPS] = {1ull, 3ull, 1024ull, SUM_TEST_RECORDS};
    // the fill: random, every field at its most negative (only the sign bit set), and at its most positive
    const char *const fills[3] = {"random", "most negative", "most positive"};
    for (unsigned int fill = 0u; (ok != 0) && (fill < 3u); fill += 1u)
    {
        for (unsigned int field = 0u; field < SUM_TEST_FIELDS; field += 1u)
        {
            for (size_t word = 0u; word < words; word += 1u)
            {
                records[word] = (unsigned int)sum_random();
            }
            for (unsigned long long lane = 0ull; (fill != 0u) && (lane < SUM_TEST_RECORDS); lane += 1ull)
            {
                unsigned int *const record = &records[lane * SUM_TEST_RECORD_LIMBS];
                for (unsigned int bit = 0u; bit < bits[field]; bit += 1u)
                {
                    const unsigned int at = offsets[field] + bit;
                    const unsigned int set = (fill == 1u) ? ((bit + 1u) == bits[field]) : ((bit + 1u) != bits[field]);
                    record[at / 32u] = (record[at / 32u] & ~(1u << (at % 32u))) | ((set ? 1u : 0u) << (at % 32u));
                }
            }
            ok = ok && (cudaMemcpy(device_records, records, words * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
                        cudaSuccess);
            for (unsigned int g = 0u; (ok != 0) && (g < SUM_TEST_GROUPS); g += 1u)
            {
                EngineError error;
                memset(&error, 0, sizeof(error));
                const unsigned long long runs = SUM_TEST_RECORDS / groups[g];
                const int both = (sum_run(1, device_records, SUM_TEST_RECORDS, groups[g], SUM_TEST_RECORD_LIMBS,
                                          offsets[field], bits[field], SUM_TEST_SUM_LIMBS, device_sums,
                                          &error) != CYCLE_ERROR) &&
                                 (sum_run(0, records, SUM_TEST_RECORDS, groups[g], SUM_TEST_RECORD_LIMBS,
                                          offsets[field], bits[field], SUM_TEST_SUM_LIMBS, host_sums,
                                          &error) != CYCLE_ERROR);
                const int same = both && (memcmp(device_sums, host_sums,
                                                 (size_t)runs * SUM_TEST_SUM_LIMBS * sizeof(unsigned int)) == 0);
                char what[200];
                snprintf(what, sizeof(what),
                         "%s fields of %u bits at bit %u, runs of %llu: the device equals the host word for word",
                         fills[fill], bits[field], offsets[field], groups[g]);
                sum_check(results, same, what);
            }
        }
    }
    // the refusals, on both routes
    for (int device = 0; (ok != 0) && (device < 2); device += 1)
    {
        EngineError error;
        memset(&error, 0, sizeof(error));
        const void *const from = (device != 0) ? (const void *)device_records : (const void *)records;
        const unsigned int *const source = (const unsigned int *)from;
        sum_check(results,
                  sum_run(device, source, SUM_TEST_RECORDS, SUM_TEST_RECORDS, SUM_TEST_RECORD_LIMBS, 0u,
                          32u * SUM_TEST_RECORD_LIMBS, SUM_TEST_RECORD_LIMBS, host_sums, &error) == CYCLE_ERROR,
                  (device != 0) ? "the device refuses sums too narrow for the run's total"
                                : "the host refuses sums too narrow for the run's total");
        sum_check(results,
                  sum_run(device, source, SUM_TEST_RECORDS, 1000ull, SUM_TEST_RECORD_LIMBS, 0u, 32u, SUM_TEST_SUM_LIMBS,
                          host_sums, &error) == CYCLE_ERROR,
                  (device != 0) ? "the device refuses a count that is not a whole number of runs"
                                : "the host refuses a count that is not a whole number of runs");
        sum_check(results,
                  sum_run(device, source, SUM_TEST_RECORDS, (1ull << 33u), SUM_TEST_RECORD_LIMBS, 0u, 32u,
                          SUM_TEST_SUM_LIMBS, host_sums, &error) == CYCLE_ERROR,
                  (device != 0) ? "the device refuses a run past 2^32 records"
                                : "the host refuses a run past 2^32 records");
    }
    cudaFree(device_records);
    free(records);
    free(device_sums);
    free(host_sums);
}

int main(int count, char **arguments)
{
    SumResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = SUM_TEST_LINE;
    results.line.out = (char *)malloc((size_t)SUM_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_sum_test", count, arguments, SUM_TEST_DECLARED);
    if (admitted != 0)
    {
        sum_program(&results);
        sum_records(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    sum_check(&results, (admitted != 0) && (job.failures == 0ull),
              "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record sum test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
