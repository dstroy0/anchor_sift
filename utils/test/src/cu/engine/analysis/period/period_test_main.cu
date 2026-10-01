// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// period_test_main.cu: volumes, errors and main
#include "period_test_internal.h"

static void test_volume(SimResults *results, const char *name, const unsigned short *volume, unsigned int rank,
                        const unsigned long long *extent, const unsigned long long *expected, int print)
{
    const unsigned long long entries = period_agreement_entries(rank, extent);
    const size_t slots = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned long long *const counts = (unsigned long long *)calloc(slots, sizeof(unsigned long long));
    unsigned long long *const reference = (unsigned long long *)calloc(slots, sizeof(unsigned long long));
    PeriodMargin *const band = (PeriodMargin *)calloc((size_t)(TEST_DRAWS * rank), sizeof(PeriodMargin));
    PeriodMargin *const band_again = (PeriodMargin *)calloc((size_t)(TEST_DRAWS * rank), sizeof(PeriodMargin));
    PeriodMeasurement measurement;
    PeriodMeasurement measurement_again;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int read = (counts != NULL) && (reference != NULL) && (band != NULL) && (band_again != NULL) &&
                     test_read(volume, rank, extent, &measurement, counts, entries, band, &error) &&
                     test_read(volume, rank, extent, &measurement_again, NULL, 0ull, band_again, &error);
    sim_check(results, read, name);
    sim_check(results,
              read && (memcmp(&measurement, &measurement_again, sizeof(measurement)) == 0) &&
                  (memcmp(band, band_again, (size_t)(TEST_DRAWS * rank) * sizeof(PeriodMargin)) == 0),
              name);
    sim_check(results, read && test_draws_and_given_top(volume, rank, extent, &measurement, band), name);
    if (read != 0)
    {
        test_reference_counts(volume, rank, extent, reference);
        unsigned long long differ = 0ull;
        for (unsigned long long entry = 0ull; entry < entries; entry += 1ull)
        {
            differ += (counts[entry] != reference[entry]) ? 1ull : 0ull;
        }
        sim_check(results, differ == 0ull, name);
        unsigned long long voxels = 1ull;
        unsigned long long histogram_check = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            voxels *= extent[axis];
        }
        unsigned int *const histogram = (unsigned int *)calloc(65536u, sizeof(unsigned int));
        for (unsigned long long voxel = 0ull; (histogram != NULL) && (voxel < voxels); voxel += 1ull)
        {
            histogram[volume[voxel]] += 1u;
        }
        for (unsigned int value = 0u; (histogram != NULL) && (value < 65536u); value += 1u)
        {
            histogram_check += (unsigned long long)histogram[value] * histogram[value];
        }
        free(histogram);
        sim_check(results, (measurement.voxels == voxels) && (measurement.collisions == histogram_check), name);
        unsigned long long first = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            const unsigned long long lags = extent[axis] / 2ull;
            const unsigned long long pairs = (extent[axis] - lags) * (voxels / extent[axis]);
            PeriodMargin top;
            if (measurement.axis[axis].band_count != 0ull)
            {
                top = measurement.axis[axis].band_top;
            }
            else
            {
                top.numerator = 0ull;
                top.denominator = pairs;
            }
            PeriodMargin margin;
            unsigned long long candidate = 0ull;
            const unsigned long long period =
                test_reference_select(&reference[first], lags, pairs, &top, &candidate, &margin);
            sim_check(results,
                      (measurement.axis[axis].pairs_per_lag == pairs) && (measurement.axis[axis].lags == lags) &&
                          (measurement.axis[axis].candidate == candidate) &&
                          (measurement.axis[axis].period == period) &&
                          (memcmp(&measurement.axis[axis].margin, &margin, sizeof(margin)) == 0) &&
                          test_band_valid(&measurement.axis[axis], &band[axis * TEST_DRAWS]),
                      name);
            if (expected != NULL)
            {
                sim_check(results, measurement.axis[axis].period == expected[axis], name);
            }
            first += lags;
        }
        if (print != 0)
        {
            scriptura_text(&results->line, "  ");
            scriptura_text(&results->line, name);
            scriptura_character(&results->line, '\n');
            sim_flush(results);
            period_print(&measurement, stdout);
        }
    }
    free(counts);
    free(reference);
    free(band);
    free(band_again);
}

static void test_error(SimResults *results, const char *name, const unsigned short *device_lanes, unsigned int rank,
                         const unsigned long long *extent, unsigned long long draws, unsigned long long *counts,
                         unsigned long long capacity, PeriodMargin *band, unsigned long long band_capacity)
{
    PeriodMeasurement measurement;
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    for (unsigned int axis = 0u; (axis < rank) && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        request.extent[axis] = extent[axis];
    }
    request.draws = draws;
    request.agreement = counts;
    request.agreement_capacity = capacity;
    request.band = band;
    request.band_capacity = band_capacity;
    request.measurement = &measurement;
    request.error = &error;
    const long result = period_read(&request);
    sim_check(results,
              (result == PERIOD_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                  (error.module == ENGINE_MODULE_PERIOD),
              name);
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    // the most the test holds on the device at once: one volume's lanes, an allocation under a page, beside the period
    // pool grown for the largest volume and the most agreement entries
    const unsigned long long declared =
        DEVICE_POOL_PAGE_BYTES + period_reserve_bytes(TEST_VOXELS_MAX, TEST_ENTRIES_MAX);
    const int admitted = sim_job_submit(&results, "period_test", count, arguments, declared);
    if (admitted == 0)
    {
        return sim_close(&results, "period test");
    }

    static unsigned short line_volume[4096];
    for (unsigned int at = 0u; at < 4096u; at += 1u)
    {
        line_volume[at] = (unsigned short)(at % 7u);
    }
    const unsigned long long line_extent[1] = {4096ull};
    const unsigned long long line_expected[1] = {7ull};
    test_volume(&results, "one axis, period 7", line_volume, 1u, line_extent, line_expected, 1);

    static unsigned short block_volume[24u * 48u * 60u];
    for (unsigned int z = 0u; z < 24u; z += 1u)
    {
        for (unsigned int y = 0u; y < 48u; y += 1u)
        {
            for (unsigned int x = 0u; x < 60u; x += 1u)
            {
                // at most 11 + 12 * 4 + 60 * 47, below 65536
                block_volume[(((z * 48u) + y) * 60u) + x] = (unsigned short)((x % 12u) + (12u * (z % 5u)) + (60u * y));
            }
        }
    }
    const unsigned long long block_extent[3] = {24ull, 48ull, 60ull};
    const unsigned long long block_expected[3] = {5ull, 0ull, 12ull};
    test_volume(&results, "three axes, periods 5 in z and 12 in x, none in y", block_volume, 3u, block_extent,
                block_expected, 1);

    static unsigned short smooth_volume[24u * 64u * 64u];
    const unsigned long long smooth_extent[3] = {24ull, 64ull, 64ull};
    unsigned long long smooth_axes = 0ull;
    unsigned long long smooth_periods = 0ull;
    for (unsigned int volume = 0u; volume < TEST_SMOOTH_VOLUMES; volume += 1u)
    {
        for (unsigned int z = 0u; z < 24u; z += 1u)
        {
            for (unsigned int y = 0u; y < 64u; y += 1u)
            {
                for (unsigned int x = 0u; x < 64u; x += 1u)
                {
                    // at most 64 + 64 + 2 * 24 + 63, below 65536
                    smooth_volume[(((z * 64u) + y) * 64u) + x] =
                        (unsigned short)(x + y + (2u * z) + (unsigned int)(test_next() % 64ull));
                }
            }
        }
        const unsigned long long before = results.failures;
        PeriodMeasurement measurement;
        EngineError error;
        memset(&error, 0, sizeof(error));
        test_volume(&results, "a smooth ramp and noise", smooth_volume, 3u, smooth_extent, NULL,
                    (volume == 0u) ? 1 : 0);
        if ((results.failures == before) &&
            test_read(smooth_volume, 3u, smooth_extent, &measurement, NULL, 0ull, NULL, &error))
        {
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                smooth_axes += 1ull;
                smooth_periods += (measurement.axis[axis].period != 0ull) ? 1ull : 0ull;
            }
        }
    }
    scriptura_text(&results.line,
                   "  a smooth ramp and noise, 16 volumes of 24 x 64 x 64, 8 shuffles each: a period found on ");
    scriptura_decimal(&results.line, smooth_periods, 1u);
    scriptura_text(&results.line, " of ");
    scriptura_decimal(&results.line, smooth_axes, 1u);
    scriptura_text(&results.line, " axes\n");

    static unsigned short flat_volume[16u * 16u * 16u];
    for (unsigned int at = 0u; at < (16u * 16u * 16u); at += 1u)
    {
        flat_volume[at] = 4321u;
    }
    const unsigned long long flat_extent[3] = {16ull, 16ull, 16ull};
    const unsigned long long flat_expected[3] = {0ull, 0ull, 0ull};
    test_volume(&results, "a constant volume", flat_volume, 3u, flat_extent, flat_expected, 0);

    static unsigned short odd_volume[1u * 7u * 33u];
    for (unsigned int at = 0u; at < (7u * 33u); at += 1u)
    {
        // the draw is reduced below 65536 first
        odd_volume[at] = (unsigned short)(test_next() % 5ull);
    }
    const unsigned long long odd_extent[3] = {1ull, 7ull, 33ull};
    test_volume(&results, "extents 1, 7 and 33", odd_volume, 3u, odd_extent, NULL, 0);

    static unsigned short rank_volume[2u * 3u * 2u * 3u * 2u * 3u * 4u * 5u];
    for (unsigned int at = 0u; at < (2u * 3u * 2u * 3u * 2u * 3u * 4u * 5u); at += 1u)
    {
        // the draw is reduced below 65536 first
        rank_volume[at] = (unsigned short)(test_next() % 3ull);
    }
    const unsigned long long rank_extent[8] = {2ull, 3ull, 2ull, 3ull, 2ull, 3ull, 4ull, 5ull};
    test_volume(&results, "rank 8", rank_volume, 8u, rank_extent, NULL, 0);

    static unsigned short random_volume[32u * 64u * 64u];
    const unsigned long long random_extent[3] = {32ull, 64ull, 64ull};
    unsigned long long random_axes = 0ull;
    unsigned long long random_periods = 0ull;
    for (unsigned int volume = 0u; volume < TEST_RANDOM_VOLUMES; volume += 1u)
    {
        for (unsigned int at = 0u; at < (32u * 64u * 64u); at += 1u)
        {
            // the low 16 bits of the draw, exactly
            random_volume[at] = (unsigned short)(test_next() & 0xFFFFull);
        }
        const unsigned long long before = results.failures;
        test_volume(&results, "uniform random", random_volume, 3u, random_extent, NULL, 0);
        if (results.failures == before)
        {
            PeriodMeasurement measurement;
            EngineError error;
            memset(&error, 0, sizeof(error));
            if (test_read(random_volume, 3u, random_extent, &measurement, NULL, 0ull, NULL, &error))
            {
                for (unsigned int axis = 0u; axis < 3u; axis += 1u)
                {
                    random_axes += 1ull;
                    random_periods += (measurement.axis[axis].period != 0ull) ? 1ull : 0ull;
                }
            }
        }
    }
    scriptura_text(&results.line,
                   "  uniform random u16, 64 volumes of 32 x 64 x 64, 8 shuffles each: a period found on ");
    scriptura_decimal(&results.line, random_periods, 1u);
    scriptura_text(&results.line, " of ");
    scriptura_decimal(&results.line, random_axes, 1u);
    scriptura_text(&results.line, " axes\n");

    unsigned short *device_lanes = NULL;
    const int allocated = cudaMalloc((void **)&device_lanes, 64u * sizeof(unsigned short)) == cudaSuccess;
    sim_check(&results, allocated, "device allocation for the errors");
    if (allocated != 0)
    {
        const unsigned long long small[2] = {8ull, 8ull};
        const unsigned long long empty[2] = {8ull, 0ull};
        const unsigned long long huge[2] = {65536ull, 65536ull};
        const unsigned long long nine[9] = {1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull};
        unsigned long long counts[8];
        PeriodMargin band[16];
        test_error(&results, "no lanes", NULL, 2u, small, 8ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "rank 0", device_lanes, 0u, small, 8ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "rank 9", device_lanes, 9u, nine, 8ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "an extent of 0", device_lanes, 2u, empty, 8ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "2^32 voxels", device_lanes, 2u, huge, 8ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "agreement capacity short by one", device_lanes, 2u, small, 8ull, counts, 7ull, NULL,
                     0ull);
        test_error(&results, "no draws", device_lanes, 2u, small, 0ull, NULL, 0ull, NULL, 0ull);
        test_error(&results, "band capacity short by one", device_lanes, 2u, small, 8ull, NULL, 0ull, band, 15ull);
        PeriodMargin tops[2] = {{1ull, 32ull}, {1ull, 32ull}};
        PeriodMeasurement measurement;
        EngineError error;
        memset(&error, 0, sizeof(error));
        PeriodRequest request;
        memset(&request, 0, sizeof(request));
        request.device_lanes = device_lanes;
        request.rank = 2u;
        request.extent[0] = 8ull;
        request.extent[1] = 8ull;
        request.draws = 8ull;
        request.null_top = tops;
        request.measurement = &measurement;
        request.error = &error;
        sim_check(&results,
                  (period_read(&request) == PERIOD_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                      (error.module == ENGINE_MODULE_PERIOD),
                  "a given band with draws of its own");
        cudaFree(device_lanes);
    }

    sim_check(&results, period_reserve_bytes(0ull, 1ull) == 0ull, "a pool for no voxels is 0 bytes");
    sim_check(&results, period_reserve_bytes(0x100000000ull, 1ull) == 0ull,
              "a pool for 2^32 voxels, which the calls error, is 0 bytes");
    sim_check(&results, period_reserve_bytes(TEST_VOXELS_MAX, TEST_ENTRIES_MAX) == DEVICE_POOL_PAGE_BYTES,
              "the test's largest pool, 528 KiB of slices, is one page");
    return sim_close(&results, "period test");
}
