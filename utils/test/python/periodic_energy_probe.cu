// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Calls the functions of src/engine/sims/art/periodic_energy.h on the sequences a file holds and prints each result
// in full, every exact integer in hexadecimal with its sign. It is the engine's side of
// utils/test/python/periodic_energy_test.py, which writes the file and reads these lines against measure/periodic_energy.py.
//
//   periodic_energy_probe <requests file>
//
// The file holds records one after another, every field little endian:
//   u32 magic 0x314E4550, u32 has_target, u64 length, u64 reach, u64 draws, u64 key, u64 period, u64 places,
//   i64 values[length], and i64 target[length] when has_target is 1.
//
// For each record it prints, in this order: energy_recover over the reach, energy_ratio at every period the recover
// scanned (from the recover's phase sums), energy_reduction at the period against the target, energy_welford at the
// period, energy_shuffle keyed by the record's key, energy_band_top over the draws, and energy_above for the recover's
// measurement against the band's top. Each measurement is also printed by energy_print, at `places` decimals where
// the probe calls sim_ratio_print itself. The results' own lines, where a device call failed, start with "results",
// and utils/test/python/periodic_energy_test.py leaves them out of the comparison.
//
// The runtime's last error is cleared before each call that launches. At 1789287 the header checks a launch with
// cudaGetLastError(), which also returns an error an earlier failed call left and sim_status_check already
// reported. Without the clearing, one request's failed allocation is read as the next call's launch failure.
// Each call is graded here on its own.
//
// The probe is a job on the device's tessera daemon (engine/sims/sim_job.cu). It reads the file once to size its
// declaration, submits the job, and then runs the records. Its exit status is the file's and the job's: a device call
// that fails is a "results" line the test grades, as before the probe was a job.

#include "device_pool.h"
#include "periodic_energy.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROBE_MAGIC 0x314E4550u

typedef struct
{
    unsigned int magic;
    unsigned int has_target;
    unsigned long long length;
    unsigned long long reach;
    unsigned long long draws;
    unsigned long long key;
    unsigned long long period;
    unsigned long long places;
} ProbeRecord;

// one byte past the results' capacity holds the end of its text
static char s_results_text[SIM_LINE_CAPACITY + 1ull];

// the record's fixed fields in the file's order; 0 at the end of the file, -1 when they are malformed
static int probe_header(FILE *file, ProbeRecord *record)
{
    memset(record, 0, sizeof(*record));
    if (fread(&record->magic, sizeof(record->magic), 1u, file) != 1u)
    {
        return 0;
    }
    const int ok = (record->magic == PROBE_MAGIC) &&
                   (fread(&record->has_target, sizeof(unsigned int), 1u, file) == 1u) &&
                   (fread(&record->length, sizeof(unsigned long long), 6u, file) == 6u);
    return ok ? 1 : -1;
}

static unsigned long long probe_pages(unsigned long long bytes)
{
    return (bytes + DEVICE_POOL_PAGE_BYTES - 1ull) / DEVICE_POOL_PAGE_BYTES;
}

// The bytes the job declares: the max any one call holds on the device, each of its allocations rounded up to pages.
// energy_phase_sums holds the values and the phase sums, energy_welford the values and two arrays of one entry per
// phase, and each frees them before it returns. 0 when a record is malformed.
static unsigned long long probe_declared(FILE *file)
{
    unsigned long long pages_max = 1ull;
    for (;;)
    {
        ProbeRecord record;
        const int read = probe_header(file, &record);
        if (read == 0)
        {
            break;
        }
        if (read < 0)
        {
            return 0ull;
        }
        const unsigned long long sequences = (record.has_target != 0u) ? 2ull : 1ull;
        for (unsigned long long at = 0ull; at < (record.length * sequences); at += 1ull)
        {
            long long value = 0ll;
            if (fread(&value, sizeof(value), 1u, file) != 1u)
            {
                return 0ull;
            }
        }
        const unsigned long long value_pages = probe_pages(record.length * sizeof(long long));
        // energy_recover's own bound: a range below 2 or fewer than 4 values never reaches the device
        if ((record.length >= 4ull) && (record.reach >= 2ull))
        {
            const unsigned long long top =
                (record.reach < (record.length - 1ull)) ? record.reach : (record.length - 1ull);
            const unsigned long long slots = energy_phase_base(top + 1ull);
            const unsigned long long pages = value_pages + probe_pages(slots * sizeof(long long));
            pages_max = (pages > pages_max) ? pages : pages_max;
        }
        if ((record.period != 0ull) && (record.length != 0ull))
        {
            const unsigned long long pages = value_pages + (2ull * probe_pages(record.period * sizeof(long long)));
            pages_max = (pages > pages_max) ? pages : pages_max;
        }
    }
    return pages_max * DEVICE_POOL_PAGE_BYTES;
}

static void probe_exact(const AnchorExactInteger *value)
{
    if (value->sign == 0)
    {
        printf("0");
        return;
    }
    unsigned int top = ANCHOR_EXACT_LIMBS;
    while ((top > 1u) && (value->limb[top - 1u] == 0u))
    {
        top -= 1u;
    }
    printf("%s%x", (value->sign < 0) ? "-" : "", (unsigned int)value->limb[top - 1u]);
    for (unsigned int limb = top - 1u; limb > 0u; limb -= 1u)
    {
        printf("%08x", (unsigned int)value->limb[limb - 1u]);
    }
}

static void probe_ratio(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator)
{
    probe_exact(numerator);
    printf("/");
    probe_exact(denominator);
}

static void probe_measurement(const char *name, int status, const EnergyMeasurement *measurement, unsigned int places)
{
    printf("%s status %d found %d", name, status, (status != 0) ? measurement->found : 0);
    if ((status != 0) && (measurement->found != 0))
    {
        printf(" period %llu ratio ", measurement->period);
        probe_ratio(&measurement->numerator, &measurement->denominator);
        char text[256];
        ScripturaLine line;
        line.out = text;
        line.capacity = sizeof(text) - 1u;
        line.at = 0ull;
        energy_print(&line, measurement);
        text[line.at] = '\0';
        printf(" print %s", text);
        line.at = 0ull;
        sim_ratio_print(&line, &measurement->numerator, &measurement->denominator, places);
        text[line.at] = '\0';
        printf(" places %s", text);
    }
    printf("\n");
}

static void probe_results(SimResults *results)
{
    // the results' failed checks, one "results" line each
    results->line.out[results->line.at] = '\0';
    char *at = results->line.out;
    while (*at != '\0')
    {
        char *end = strchr(at, '\n');
        if (end != NULL)
        {
            *end = '\0';
        }
        printf("results %s\n", at);
        if (end == NULL)
        {
            break;
        }
        at = end + 1;
    }
    results->line.at = 0ull;
}

static void probe_run(SimResults *results, const ProbeRecord *record, const long long *values, const long long *target,
                      unsigned long long number)
{
    const unsigned long long length = record->length;
    printf("case %llu length %llu reach %llu draws %llu period %llu\n", number, length, record->reach, record->draws,
           record->period);
    const unsigned long long top =
        (length >= 1ull) ? ((record->reach < (length - 1ull)) ? record->reach : (length - 1ull)) : 0ull;
    const unsigned long long slots = (top >= 2ull) ? energy_phase_base(top + 1ull) : 1ull;
    long long *const sums = (long long *)calloc((size_t)slots, sizeof(long long));
    long long *const shuffled = (long long *)calloc((size_t)(length + 1ull), sizeof(long long));
    const unsigned long long phases = (record->period != 0ull) ? record->period : 1ull;
    long long *const welford_numerator = (long long *)calloc((size_t)phases, sizeof(long long));
    unsigned long long *const welford_denominator =
        (unsigned long long *)calloc((size_t)phases, sizeof(unsigned long long));
    if ((sums == NULL) || (shuffled == NULL) || (welford_numerator == NULL) || (welford_denominator == NULL))
    {
        printf("host memory not allocated\nend\n");
        free(sums);
        free(shuffled);
        free(welford_numerator);
        free(welford_denominator);
        return;
    }
    const unsigned int places = (unsigned int)record->places;

    EnergyMeasurement live;
    memset(&live, 0, sizeof(live));
    (void)cudaGetLastError();
    const int recovered = energy_recover(results, values, length, record->reach, sums, &live);
    probe_measurement("recover", recovered, &live, places);
    probe_results(results);

    for (unsigned long long period = 2ull; (recovered != 0) && (period <= top); period += 1ull)
    {
        AnchorExactInteger numerator;
        AnchorExactInteger denominator;
        printf("ratio %llu ", period);
        if (energy_ratio(values, length, sums, period, &numerator, &denominator) != 0)
        {
            probe_ratio(&numerator, &denominator);
        }
        else
        {
            printf("none");
        }
        printf("\n");
    }

    if ((record->has_target != 0u) && (recovered != 0) && (record->period >= 2ull) && (record->period <= top))
    {
        AnchorExactInteger numerator;
        AnchorExactInteger denominator;
        const int reduced = energy_reduction(values, target, length, record->period,
                                             &sums[energy_phase_base(record->period)], &numerator, &denominator);
        printf("reduction status %d ", reduced);
        probe_ratio(&numerator, &denominator);
        printf("\n");
    }

    if ((record->period != 0ull) && (length != 0ull))
    {
        (void)cudaGetLastError();
        const int averaged =
            energy_welford(results, values, length, record->period, welford_numerator, welford_denominator);
        printf("welford status %d", averaged);
        for (unsigned long long phase = 0ull; (averaged != 0) && (phase < record->period); phase += 1ull)
        {
            printf(" %lld/%llu", welford_numerator[phase], welford_denominator[phase]);
        }
        printf("\n");
        probe_results(results);
    }

    if (length != 0ull)
    {
        energy_shuffle(values, shuffled, length, record->key);
        printf("shuffle");
        for (unsigned long long at = 0ull; at < length; at += 1ull)
        {
            printf(" %lld", shuffled[at]);
        }
        printf("\n");

        EnergyMeasurement band;
        memset(&band, 0, sizeof(band));
        unsigned long long reached = 0ull;
        (void)cudaGetLastError();
        const int banded = energy_band_top(results, values, length, record->reach, record->draws, record->key, shuffled,
                                           sums, &band, &reached);
        printf("reached %llu\n", (banded != 0) ? reached : 0ull);
        probe_measurement("band", banded, &band, places);
        probe_results(results);
        if ((recovered != 0) && (banded != 0))
        {
            printf("above %d\n", energy_above(&live, &band));
        }
    }
    printf("end\n");
    free(sums);
    free(shuffled);
    free(welford_numerator);
    free(welford_denominator);
}

int main(int count, char **arguments)
{
    if (count != 2)
    {
        printf("usage: periodic_energy_probe <requests file>\n");
        return 2;
    }
    FILE *const file = fopen(arguments[1], "rb");
    if (file == NULL)
    {
        printf("periodic_energy_probe: %s not opened\n", arguments[1]);
        return 2;
    }
    const unsigned long long declared = probe_declared(file);
    rewind(file);
    if (declared == 0ull)
    {
        printf("periodic_energy_probe: a record in %s is malformed\n", arguments[1]);
        fclose(file);
        return 2;
    }
    SimResults results;
    sim_open(&results, s_results_text);
    if (sim_job_submit(&results, "periodic_energy_probe", count, arguments, declared) == 0)
    {
        fclose(file);
        return sim_close(&results, "periodic energy probe");
    }
    int ok = 1;
    unsigned long long number = 0ull;
    for (;;)
    {
        ProbeRecord record;
        const int header = probe_header(file, &record);
        if (header == 0)
        {
            break;
        }
        long long *const values =
            (header > 0) ? (long long *)calloc((size_t)(record.length + 1ull), sizeof(long long)) : NULL;
        long long *const target =
            (header > 0) ? (long long *)calloc((size_t)(record.length + 1ull), sizeof(long long)) : NULL;
        const int body = (values != NULL) && (target != NULL) &&
                         (fread(values, sizeof(long long), (size_t)record.length, file) == (size_t)record.length) &&
                         ((record.has_target == 0u) ||
                          (fread(target, sizeof(long long), (size_t)record.length, file) == (size_t)record.length));
        if (!body)
        {
            printf("periodic_energy_probe: record %llu is malformed\n", number);
            free(values);
            free(target);
            ok = 0;
            break;
        }
        probe_run(&results, &record, values, target, number);
        free(values);
        free(target);
        number += 1ull;
        fflush(stdout);
    }
    fclose(file);
    printf("records %llu\n", number);
    const unsigned long long failures = results.failures;
    sim_job_release(&results);
    const int released = results.failures == failures;
    probe_results(&results);
    return (ok && released) ? 0 : 1;
}
