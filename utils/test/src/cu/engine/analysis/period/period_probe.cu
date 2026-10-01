// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// Calls period_read and period_draw (src/engine/analysis/period/) on the requests a file holds and prints
// each measurement in full, every count and every ratio as its exact numerator and denominator. It is the engine's side
// of utils/test/python/period_test.py, which writes the file and reads these lines against measure/period.py.
//
//   period_probe <requests file>
//
// The file holds records one after another, every field little endian:
//   u32 magic 0x31445250, u32 mode (0 period_read, 1 period_draw), u32 rank, u32 has_null_top,
//   u64 extent[8], u64 draws (period_draw's draw number in mode 1), u8 content[32],
//   u64 null_top[8][2] (numerator, denominator), u64 lane count, u16 lanes[lane count].
// A lane count of 0 still hands the engine one device lane, since a request in error reads none.
//
// The probe is a job on the device's tessera daemon (sims/cu/sim_job.cu). It reads the file once to size its
// declaration, submits the job, and then runs the records.
//
// Each record prints "case <n> mode <read|draw> status <s>", the measurement's lines when the status is 0, and "end".

#include "device_pool.h"
#include "period.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROBE_MAGIC 0x31445250u
#define PROBE_BAND_MAX (1ull << 24u)

typedef struct
{
    unsigned int magic;
    unsigned int mode;
    unsigned int rank;
    unsigned int has_null_top;
    unsigned long long extent[ENGINE_ARRAY_RANK];
    unsigned long long draws;
    unsigned char content[ENGINE_SIGNUM_BYTES];
    PeriodMargin null_top[ENGINE_ARRAY_RANK];
    unsigned long long lane_count;
} ProbeRecord;

static int probe_take(FILE *file, void *into, size_t bytes)
{
    return fread(into, 1u, bytes, file) == bytes;
}

// the record's fixed fields in the file's order; 0 at the end of the file
static int probe_record(FILE *file, ProbeRecord *record)
{
    memset(record, 0, sizeof(*record));
    if (!probe_take(file, &record->magic, sizeof(record->magic)))
    {
        return 0;
    }
    int ok = (record->magic == PROBE_MAGIC) && probe_take(file, &record->mode, sizeof(record->mode)) &&
             probe_take(file, &record->rank, sizeof(record->rank)) &&
             probe_take(file, &record->has_null_top, sizeof(record->has_null_top));
    for (unsigned int axis = 0u; ok && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        ok = probe_take(file, &record->extent[axis], sizeof(record->extent[axis]));
    }
    ok = ok && probe_take(file, &record->draws, sizeof(record->draws)) &&
         probe_take(file, record->content, sizeof(record->content));
    for (unsigned int axis = 0u; ok && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        ok = probe_take(file, &record->null_top[axis].numerator, sizeof(unsigned long long)) &&
             probe_take(file, &record->null_top[axis].denominator, sizeof(unsigned long long));
    }
    ok = ok && probe_take(file, &record->lane_count, sizeof(record->lane_count));
    return ok ? 1 : -1;
}

static int probe_skip(FILE *file, unsigned long long bytes)
{
    unsigned char discard[4096];
    while (bytes != 0ull)
    {
        const size_t step = (bytes < sizeof(discard)) ? (size_t)bytes : sizeof(discard);
        if (!probe_take(file, discard, step))
        {
            return 0;
        }
        bytes -= step;
    }
    return 1;
}

// The bytes the job declares: the device lanes the largest record copies, rounded up to pages, beside
// period_reserve_bytes for the max voxels and the max agreement entries of the records it can hold (a job over several
// extents declares the pool for the max of each). 0 when a record is malformed.
static unsigned long long probe_declared(FILE *file)
{
    unsigned long long lane_bytes_max = sizeof(unsigned short);
    unsigned long long voxels_max = 0ull;
    unsigned long long entries_max = 0ull;
    for (;;)
    {
        ProbeRecord record;
        const int read = probe_record(file, &record);
        if (read == 0)
        {
            break;
        }
        const unsigned long long lane_bytes = record.lane_count * sizeof(unsigned short);
        if ((read < 0) || !probe_skip(file, lane_bytes))
        {
            return 0ull;
        }
        lane_bytes_max = (lane_bytes > lane_bytes_max) ? lane_bytes : lane_bytes_max;
        const unsigned int bounded_rank = (record.rank < ENGINE_ARRAY_RANK) ? record.rank : ENGINE_ARRAY_RANK;
        unsigned long long voxels = (bounded_rank != 0u) ? 1ull : 0ull;
        for (unsigned int axis = 0u; axis < bounded_rank; axis += 1u)
        {
            const unsigned long long extent = record.extent[axis];
            // saturates at 2^64 - 1, which period_reserve_bytes takes as more voxels than the calls hold
            voxels = ((extent != 0ull) && (voxels > (~0ull / extent))) ? ~0ull : (voxels * extent);
        }
        const unsigned long long entries = period_agreement_entries(bounded_rank, record.extent);
        if (period_reserve_bytes(voxels, entries) != 0ull)
        {
            voxels_max = (voxels > voxels_max) ? voxels : voxels_max;
            entries_max = (entries > entries_max) ? entries : entries_max;
        }
    }
    const unsigned long long lane_pages = (lane_bytes_max + DEVICE_POOL_PAGE_BYTES - 1ull) / DEVICE_POOL_PAGE_BYTES;
    return (lane_pages * DEVICE_POOL_PAGE_BYTES) + period_reserve_bytes(voxels_max, entries_max);
}

static void probe_margin(const char *name, const PeriodMargin *margin)
{
    printf(" %s %llu/%llu", name, margin->numerator, margin->denominator);
}

static void probe_measurement(const PeriodMeasurement *measurement, const unsigned long long *agreement,
                              unsigned long long entries, const PeriodMargin *band, unsigned long long band_entries)
{
    printf("measurement rank %u voxels %llu collisions %llu draws %llu\n", measurement->rank, measurement->voxels,
           measurement->collisions, measurement->draws);
    for (unsigned int axis = 0u; axis < measurement->rank; axis += 1u)
    {
        const PeriodAxis *const measured = &measurement->axis[axis];
        printf("axis %u extent %llu period %llu candidate %llu lags %llu pairs %llu at %llu beside %llu doubled %llu "
               "beside_double %llu",
               axis, measured->extent, measured->period, measured->candidate, measured->lags, measured->pairs_per_lag,
               measured->agreement_at_candidate, measured->agreement_beside_candidate, measured->agreement_at_double,
               measured->agreement_beside_double);
        probe_margin("margin", &measured->margin);
        printf(" band_count %llu", measured->band_count);
        probe_margin("bottom", &measured->band_bottom);
        probe_margin("top", &measured->band_top);
        printf("\n");
    }
    printf("agreement %llu", entries);
    for (unsigned long long entry = 0ull; entry < entries; entry += 1ull)
    {
        printf(" %llu", agreement[entry]);
    }
    printf("\nband %llu", band_entries);
    for (unsigned long long entry = 0ull; entry < band_entries; entry += 1ull)
    {
        printf(" %llu/%llu", band[entry].numerator, band[entry].denominator);
    }
    printf("\n");
}

static int probe_run(const ProbeRecord *record, const unsigned short *lanes, unsigned long long number)
{
    const unsigned long long device_lane_count = (record->lane_count != 0ull) ? record->lane_count : 1ull;
    unsigned short *device_lanes = NULL;
    if (cudaMalloc((void **)&device_lanes, (size_t)device_lane_count * sizeof(unsigned short)) != cudaSuccess)
    {
        printf("case %llu device lanes not allocated\n", number);
        return 0;
    }
    int ok = cudaMemset(device_lanes, 0, (size_t)device_lane_count * sizeof(unsigned short)) == cudaSuccess;
    if (ok && (record->lane_count != 0ull))
    {
        ok = cudaMemcpy(device_lanes, lanes, (size_t)record->lane_count * sizeof(unsigned short),
                        cudaMemcpyHostToDevice) == cudaSuccess;
    }
    const unsigned int bounded_rank = (record->rank < ENGINE_ARRAY_RANK) ? record->rank : ENGINE_ARRAY_RANK;
    const unsigned long long entries = period_agreement_entries(bounded_rank, record->extent);
    const unsigned long long band_entries = record->draws * bounded_rank;
    unsigned long long *const agreement =
        (unsigned long long *)calloc((size_t)(entries + 1ull), sizeof(unsigned long long));
    // a band past the max this probe holds is passed as none, which only a request in error asks for
    PeriodMargin *const band = (band_entries <= PROBE_BAND_MAX)
                                   ? (PeriodMargin *)calloc((size_t)(band_entries + 1ull), sizeof(PeriodMargin))
                                   : NULL;
    PeriodMargin heights[ENGINE_ARRAY_RANK];
    memset(heights, 0, sizeof(heights));
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodMeasurement measurement;
    memset(&measurement, 0, sizeof(measurement));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = record->rank;
    memcpy(request.extent, record->extent, sizeof(request.extent));
    request.draws = (record->mode == 0u) ? record->draws : 0ull;
    memcpy(request.content.bytes, record->content, sizeof(request.content.bytes));
    request.null_top = (record->has_null_top != 0u) ? record->null_top : NULL;
    request.agreement = agreement;
    request.agreement_capacity = entries;
    request.band = band;
    request.band_capacity = (band != NULL) ? band_entries : 0ull;
    request.measurement = &measurement;
    request.error = &error;
    long status = -2L;
    if (ok && (agreement != NULL))
    {
        status = (record->mode == 0u) ? period_read(&request) : period_draw(&request, record->draws, heights);
    }
    printf("case %llu mode %s status %ld\n", number, (record->mode == 0u) ? "read" : "draw", status);
    if ((status == 0L) && (record->mode == 0u))
    {
        probe_measurement(&measurement, agreement, entries, band, (band != NULL) ? band_entries : 0ull);
    }
    else if (status == 0L)
    {
        printf("heights %u", bounded_rank);
        for (unsigned int axis = 0u; axis < bounded_rank; axis += 1u)
        {
            printf(" %llu/%llu", heights[axis].numerator, heights[axis].denominator);
        }
        printf("\n");
    }
    else
    {
        printf("error kind %d module %d site %u status %d\n", (int)error.kind, (int)error.module, error.site,
               (int)error.status);
    }
    printf("end\n");
    free(agreement);
    free(band);
    cudaFree(device_lanes);
    return 1;
}

int main(int count, char **arguments)
{
    if (count != 2)
    {
        printf("usage: period_probe <requests file>\n");
        return 2;
    }
    FILE *const file = fopen(arguments[1], "rb");
    if (file == NULL)
    {
        printf("period_probe: %s not opened\n", arguments[1]);
        return 2;
    }
    const unsigned long long declared = probe_declared(file);
    rewind(file);
    if (declared == 0ull)
    {
        printf("period_probe: a record in %s is malformed\n", arguments[1]);
        fclose(file);
        return 2;
    }
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    if (sim_job_submit(&results, "period_probe", count, arguments, declared) == 0)
    {
        fclose(file);
        return sim_close(&results, "period probe");
    }
    int ok = 1;
    unsigned long long number = 0ull;
    for (;;)
    {
        ProbeRecord record;
        const int read = probe_record(file, &record);
        if (read == 0)
        {
            break;
        }
        unsigned short *const lanes =
            (unsigned short *)malloc((size_t)(record.lane_count + 1ull) * sizeof(unsigned short));
        if ((read < 0) || (lanes == NULL) ||
            !probe_take(file, lanes, (size_t)record.lane_count * sizeof(unsigned short)))
        {
            printf("period_probe: record %llu is malformed\n", number);
            free(lanes);
            ok = 0;
            break;
        }
        ok = probe_run(&record, lanes, number) && ok;
        free(lanes);
        number += 1ull;
        fflush(stdout);
    }
    fclose(file);
    printf("records %llu\n", number);
    const int closed = sim_close(&results, "period probe");
    return (ok && (closed == 0)) ? 0 : 1;
}
