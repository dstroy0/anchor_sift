// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "period.h"

#include "scriptura.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define TEST_LOW_HALF 0xFFFFFFFFull

#define TEST_LINE_ROOM 4096ull

#define TEST_RANDOM_VOLUMES 64u

#define TEST_DRAWS 8ull

#define TEST_SMOOTH_VOLUMES 16u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} TestTally;

typedef struct
{
    unsigned long long high;
    unsigned long long low;
} TestWide;

static unsigned long long s_test_state = 0x9E3779B97F4A7C15ull;

static unsigned long long test_next(void)
{
    s_test_state ^= s_test_state << 13u;
    s_test_state ^= s_test_state >> 7u;
    s_test_state ^= s_test_state << 17u;
    return s_test_state;
}

static TestWide test_wide_product(unsigned long long left, unsigned long long right)
{
    const unsigned long long cross_one = (left >> 32u) * (right & TEST_LOW_HALF);
    const unsigned long long cross_other = (left & TEST_LOW_HALF) * (right >> 32u);
    const unsigned long long bottom = (left & TEST_LOW_HALF) * (right & TEST_LOW_HALF);
    const unsigned long long carry = ((bottom >> 32u) + (cross_one & TEST_LOW_HALF) + (cross_other & TEST_LOW_HALF)) >> 32u;
    TestWide product;
    product.low = left * right;
    product.high = ((left >> 32u) * (right >> 32u)) + (cross_one >> 32u) + (cross_other >> 32u) + carry;
    return product;
}

static int test_wide_above(TestWide one, TestWide other, int or_equal)
{
    if (one.high != other.high)
    {
        return one.high > other.high;
    }
    return or_equal ? (one.low >= other.low) : (one.low > other.low);
}

static void test_check(TestTally *tally, int held, const char *what)
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

static void test_flush(TestTally *tally)
{
    scriptura_write(&tally->line, stdout);
    tally->line.at = 0ull;
}

static unsigned long long test_reference_counts(const unsigned short *volume, unsigned int rank,
                                                const unsigned long long *shape, unsigned long long *counts)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= shape[axis];
    }
    unsigned long long entry = 0ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        unsigned long long stride = 1ull;
        for (unsigned int later = axis + 1u; later < rank; later += 1u)
        {
            stride *= shape[later];
        }
        const unsigned long long lags = shape[axis] / 2ull;
        const unsigned long long usable = shape[axis] - lags;
        for (unsigned long long lag = 1ull; lag <= lags; lag += 1ull)
        {
            unsigned long long same = 0ull;
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                const unsigned long long along = (voxel / stride) % shape[axis];
                if (along < usable)
                {
                    same += (volume[voxel] == volume[voxel + (lag * stride)]) ? 1ull : 0ull;
                }
            }
            counts[entry] = same;
            entry += 1ull;
        }
    }
    return entry;
}

static int test_margin_above(const PeriodMargin *one, const PeriodMargin *other, int or_equal);

static int test_reference_peak(const unsigned long long *same, unsigned long long candidate, unsigned long long lags,
                               unsigned long long *height)
{
    if (((2ull * candidate) + 1ull) > lags)
    {
        return 0;
    }
    unsigned long long least = 0ull;
    for (unsigned long long multiple = 1ull; multiple <= 2ull; multiple += 1ull)
    {
        const unsigned long long lag = multiple * candidate;
        const unsigned long long here = same[lag - 1ull];
        const unsigned long long left = same[lag - 2ull];
        const unsigned long long right = same[lag];
        if ((here <= left) || (here <= right))
        {
            return 0;
        }
        const unsigned long long rise = here - ((left > right) ? left : right);
        least = (multiple == 1ull) ? rise : ((rise < least) ? rise : least);
    }
    *height = least;
    return 1;
}

// Mirrors period_select: the smallest candidate whose height clears the top, else the strongest peak
// with no period.
static unsigned long long test_reference_select(const unsigned long long *same, unsigned long long lags,
                                                unsigned long long pairs, const PeriodMargin *top,
                                                unsigned long long *candidate_out, PeriodMargin *margin)
{
    unsigned long long strongest = 0ull;
    unsigned long long strongest_height = 0ull;
    for (unsigned long long candidate = 2ull; ((2ull * candidate) + 1ull) <= lags; candidate += 1ull)
    {
        unsigned long long height = 0ull;
        if (test_reference_peak(same, candidate, lags, &height) == 0)
        {
            continue;
        }
        const PeriodMargin here = {height, pairs};
        if (test_margin_above(&here, top, 0))
        {
            *candidate_out = candidate;
            margin->numerator = height;
            margin->denominator = pairs;
            return candidate;
        }
        if ((strongest == 0ull) || (height > strongest_height))
        {
            strongest = candidate;
            strongest_height = height;
        }
    }
    *candidate_out = strongest;
    margin->numerator = (strongest != 0ull) ? strongest_height : 0ull;
    margin->denominator = (strongest != 0ull) ? pairs : 0ull;
    return 0ull;
}

static EngineSignum test_content(const unsigned short *volume, unsigned long long voxels)
{
    EngineSignum content;
    unsigned long long running = 0xCBF29CE484222325ull;
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        for (unsigned long long voxel = byte; voxel < voxels; voxel += ENGINE_SIGNUM_BYTES)
        {
            running = (running ^ volume[voxel]) * 0x100000001B3ull;
        }
        // the byte is the top 8 bits of the running hash
        content.bytes[byte] = (unsigned char)(running >> 56u);
    }
    return content;
}

static int test_read(const unsigned short *volume, unsigned int rank, const unsigned long long *shape,
                     PeriodReading *reading, unsigned long long *counts, unsigned long long room, PeriodMargin *band,
                     EngineError *error)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= shape[axis];
    }
    unsigned short *device_lanes = NULL;
    if (cudaMalloc((void **)&device_lanes, (size_t)voxels * sizeof(unsigned short)) != cudaSuccess)
    {
        return 0;
    }
    int good = cudaMemcpy(device_lanes, volume, (size_t)voxels * sizeof(unsigned short), cudaMemcpyHostToDevice)
            == cudaSuccess;
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    memcpy(request.shape, shape, rank * sizeof(unsigned long long));
    request.draws = TEST_DRAWS;
    request.content = test_content(volume, voxels);
    request.agreement = counts;
    request.agreement_room = room;
    request.band = band;
    request.band_room = (band != NULL) ? (TEST_DRAWS * rank) : 0ull;
    request.reading = reading;
    request.error = error;
    good = good && (period_read(&request) == 0L);
    cudaFree(device_lanes);
    return good;
}

static int test_margin_above(const PeriodMargin *one, const PeriodMargin *other, int or_equal)
{
    return test_wide_above(test_wide_product(one->numerator, other->denominator),
                           test_wide_product(other->numerator, one->denominator), or_equal);
}

static int test_band_holds(const PeriodAxis *axis, const PeriodMargin *band)
{
    int held = axis->band_count <= TEST_DRAWS;
    for (unsigned long long at = 1ull; held && (at < axis->band_count); at += 1ull)
    {
        held = test_margin_above(&band[at], &band[at - 1ull], 1);
    }
    if (held && (axis->band_count != 0ull))
    {
        held = (memcmp(&axis->band_bottom, &band[0], sizeof(PeriodMargin)) == 0)
            && (memcmp(&axis->band_top, &band[axis->band_count - 1ull], sizeof(PeriodMargin)) == 0);
    }
    return held;
}

static int test_margin_before(const void *one, const void *other)
{
    const PeriodMargin *const left = (const PeriodMargin *)one;
    const PeriodMargin *const right = (const PeriodMargin *)other;
    return test_margin_above(left, right, 0) ? 1 : (test_margin_above(right, left, 0) ? -1 : 0);
}

static int test_draws_and_given_top(const unsigned short *volume, unsigned int rank, const unsigned long long *shape,
                                    const PeriodReading *reading, const PeriodMargin *band)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= shape[axis];
    }
    unsigned short *device_lanes = NULL;
    if (cudaMalloc((void **)&device_lanes, (size_t)voxels * sizeof(unsigned short)) != cudaSuccess)
    {
        return 0;
    }
    int good = cudaMemcpy(device_lanes, volume, (size_t)voxels * sizeof(unsigned short), cudaMemcpyHostToDevice)
            == cudaSuccess;
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    memcpy(request.shape, shape, rank * sizeof(unsigned long long));
    request.content = test_content(volume, voxels);
    request.error = &error;
    PeriodMargin drawn[TEST_DRAWS * ENGINE_ARRAY_RANK];
    unsigned long long kept[ENGINE_ARRAY_RANK] = {0ull};
    for (unsigned long long draw = 0ull; good && (draw < TEST_DRAWS); draw += 1ull)
    {
        PeriodMargin heights[ENGINE_ARRAY_RANK];
        good = period_draw(&request, draw, heights) == 0L;
        for (unsigned int axis = 0u; good && (axis < rank); axis += 1u)
        {
            if (heights[axis].numerator != 0ull)
            {
                drawn[(axis * TEST_DRAWS) + kept[axis]] = heights[axis];
                kept[axis] += 1ull;
            }
        }
    }
    PeriodMargin tops[ENGINE_ARRAY_RANK];
    for (unsigned int axis = 0u; good && (axis < rank); axis += 1u)
    {
        qsort(&drawn[axis * TEST_DRAWS], (size_t)kept[axis], sizeof(PeriodMargin), test_margin_before);
        good = (kept[axis] == reading->axis[axis].band_count)
            && ((kept[axis] == 0ull)
                || (memcmp(&drawn[axis * TEST_DRAWS], &band[axis * TEST_DRAWS], (size_t)kept[axis] * sizeof(PeriodMargin))
                    == 0));
        tops[axis] = (kept[axis] != 0ull) ? reading->axis[axis].band_top : drawn[axis * TEST_DRAWS];
        tops[axis].numerator = (kept[axis] != 0ull) ? tops[axis].numerator : 0ull;
        tops[axis].denominator = reading->axis[axis].pairs_per_lag;
    }
    PeriodReading judged;
    request.null_top = tops;
    request.reading = &judged;
    good = good && (period_read(&request) == 0L);
    for (unsigned int axis = 0u; good && (axis < rank); axis += 1u)
    {
        good = (judged.axis[axis].period == reading->axis[axis].period)
            && (judged.axis[axis].candidate == reading->axis[axis].candidate);
    }
    cudaFree(device_lanes);
    return good;
}

static void test_volume(TestTally *tally, const char *name, const unsigned short *volume, unsigned int rank,
                        const unsigned long long *shape, const unsigned long long *expected, int print)
{
    const unsigned long long entries = period_agreement_entries(rank, shape);
    const size_t held = (size_t)((entries != 0ull) ? entries : 1ull);
    unsigned long long *const counts = (unsigned long long *)calloc(held, sizeof(unsigned long long));
    unsigned long long *const reference = (unsigned long long *)calloc(held, sizeof(unsigned long long));
    PeriodMargin *const band = (PeriodMargin *)calloc((size_t)(TEST_DRAWS * rank), sizeof(PeriodMargin));
    PeriodMargin *const band_again = (PeriodMargin *)calloc((size_t)(TEST_DRAWS * rank), sizeof(PeriodMargin));
    PeriodReading reading;
    PeriodReading reading_again;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int read = (counts != NULL) && (reference != NULL) && (band != NULL) && (band_again != NULL)
                  && test_read(volume, rank, shape, &reading, counts, entries, band, &error)
                  && test_read(volume, rank, shape, &reading_again, NULL, 0ull, band_again, &error);
    test_check(tally, read, name);
    test_check(tally, read && (memcmp(&reading, &reading_again, sizeof(reading)) == 0)
                          && (memcmp(band, band_again, (size_t)(TEST_DRAWS * rank) * sizeof(PeriodMargin)) == 0),
               name);
    test_check(tally, read && test_draws_and_given_top(volume, rank, shape, &reading, band), name);
    if (read != 0)
    {
        test_reference_counts(volume, rank, shape, reference);
        unsigned long long differ = 0ull;
        for (unsigned long long entry = 0ull; entry < entries; entry += 1ull)
        {
            differ += (counts[entry] != reference[entry]) ? 1ull : 0ull;
        }
        test_check(tally, differ == 0ull, name);
        unsigned long long voxels = 1ull;
        unsigned long long histogram_check = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            voxels *= shape[axis];
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
        test_check(tally, (reading.voxels == voxels) && (reading.collisions == histogram_check), name);
        unsigned long long first = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            const unsigned long long lags = shape[axis] / 2ull;
            const unsigned long long pairs = (shape[axis] - lags) * (voxels / shape[axis]);
            PeriodMargin top;
            if (reading.axis[axis].band_count != 0ull)
            {
                top = reading.axis[axis].band_top;
            }
            else
            {
                top.numerator = 0ull;
                top.denominator = pairs;
            }
            PeriodMargin margin;
            unsigned long long candidate = 0ull;
            const unsigned long long period = test_reference_select(&reference[first], lags, pairs, &top, &candidate,
                                                                   &margin);
            test_check(tally, (reading.axis[axis].pairs_per_lag == pairs) && (reading.axis[axis].lags == lags)
                                  && (reading.axis[axis].candidate == candidate)
                                  && (reading.axis[axis].period == period)
                                  && (memcmp(&reading.axis[axis].margin, &margin, sizeof(margin)) == 0)
                                  && test_band_holds(&reading.axis[axis], &band[axis * TEST_DRAWS]),
                       name);
            if (expected != NULL)
            {
                test_check(tally, reading.axis[axis].period == expected[axis], name);
            }
            first += lags;
        }
        if (print != 0)
        {
            scriptura_text(&tally->line, "  ");
            scriptura_text(&tally->line, name);
            scriptura_character(&tally->line, '\n');
            test_flush(tally);
            period_print(&reading, stdout);
        }
    }
    free(counts);
    free(reference);
    free(band);
    free(band_again);
}

static void test_refusal(TestTally *tally, const char *name, const unsigned short *device_lanes, unsigned int rank,
                         const unsigned long long *shape, unsigned long long draws, unsigned long long *counts,
                         unsigned long long room, PeriodMargin *band, unsigned long long band_room)
{
    PeriodReading reading;
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    for (unsigned int axis = 0u; (axis < rank) && (axis < ENGINE_ARRAY_RANK); axis += 1u)
    {
        request.shape[axis] = shape[axis];
    }
    request.draws = draws;
    request.agreement = counts;
    request.agreement_room = room;
    request.band = band;
    request.band_room = band_room;
    request.reading = &reading;
    request.error = &error;
    const long result = period_read(&request);
    test_check(tally, (result == PERIOD_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
                          && (error.module == ENGINE_MODULE_PERIOD),
               name);
}

int main(void)
{
    TestTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = TEST_LINE_ROOM;
    tally.line.out = (char *)malloc((size_t)TEST_LINE_ROOM);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }

    static unsigned short line_volume[4096];
    for (unsigned int at = 0u; at < 4096u; at += 1u)
    {
        line_volume[at] = (unsigned short)(at % 7u);
    }
    const unsigned long long line_shape[1] = {4096ull};
    const unsigned long long line_expected[1] = {7ull};
    test_volume(&tally, "one axis, period 7", line_volume, 1u, line_shape, line_expected, 1);

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
    const unsigned long long block_shape[3] = {24ull, 48ull, 60ull};
    const unsigned long long block_expected[3] = {5ull, 0ull, 12ull};
    test_volume(&tally, "three axes, periods 5 in z and 12 in x, none in y", block_volume, 3u, block_shape,
                block_expected, 1);

    static unsigned short smooth_volume[24u * 64u * 64u];
    const unsigned long long smooth_shape[3] = {24ull, 64ull, 64ull};
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
        const unsigned long long before = tally.failures;
        PeriodReading reading;
        EngineError error;
        memset(&error, 0, sizeof(error));
        test_volume(&tally, "a smooth ramp and noise", smooth_volume, 3u, smooth_shape, NULL, (volume == 0u) ? 1 : 0);
        if ((tally.failures == before) && test_read(smooth_volume, 3u, smooth_shape, &reading, NULL, 0ull, NULL, &error))
        {
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                smooth_axes += 1ull;
                smooth_periods += (reading.axis[axis].period != 0ull) ? 1ull : 0ull;
            }
        }
    }
    scriptura_text(&tally.line, "  a smooth ramp and noise, 16 volumes of 24 x 64 x 64, 8 shuffles each: a period found on ");
    scriptura_decimal(&tally.line, smooth_periods, 1u);
    scriptura_text(&tally.line, " of ");
    scriptura_decimal(&tally.line, smooth_axes, 1u);
    scriptura_text(&tally.line, " axes\n");

    static unsigned short flat_volume[16u * 16u * 16u];
    for (unsigned int at = 0u; at < (16u * 16u * 16u); at += 1u)
    {
        flat_volume[at] = 4321u;
    }
    const unsigned long long flat_shape[3] = {16ull, 16ull, 16ull};
    const unsigned long long flat_expected[3] = {0ull, 0ull, 0ull};
    test_volume(&tally, "a constant volume", flat_volume, 3u, flat_shape, flat_expected, 0);

    static unsigned short odd_volume[1u * 7u * 33u];
    for (unsigned int at = 0u; at < (7u * 33u); at += 1u)
    {
        // the draw is reduced below 65536 first
        odd_volume[at] = (unsigned short)(test_next() % 5ull);
    }
    const unsigned long long odd_shape[3] = {1ull, 7ull, 33ull};
    test_volume(&tally, "extents 1, 7 and 33", odd_volume, 3u, odd_shape, NULL, 0);

    static unsigned short rank_volume[2u * 3u * 2u * 3u * 2u * 3u * 4u * 5u];
    for (unsigned int at = 0u; at < (2u * 3u * 2u * 3u * 2u * 3u * 4u * 5u); at += 1u)
    {
        // the draw is reduced below 65536 first
        rank_volume[at] = (unsigned short)(test_next() % 3ull);
    }
    const unsigned long long rank_shape[8] = {2ull, 3ull, 2ull, 3ull, 2ull, 3ull, 4ull, 5ull};
    test_volume(&tally, "rank 8", rank_volume, 8u, rank_shape, NULL, 0);

    static unsigned short random_volume[32u * 64u * 64u];
    const unsigned long long random_shape[3] = {32ull, 64ull, 64ull};
    unsigned long long random_axes = 0ull;
    unsigned long long random_periods = 0ull;
    for (unsigned int volume = 0u; volume < TEST_RANDOM_VOLUMES; volume += 1u)
    {
        for (unsigned int at = 0u; at < (32u * 64u * 64u); at += 1u)
        {
            // the low 16 bits of the draw, exactly
            random_volume[at] = (unsigned short)(test_next() & 0xFFFFull);
        }
        const unsigned long long before = tally.failures;
        test_volume(&tally, "uniform random", random_volume, 3u, random_shape, NULL, 0);
        if (tally.failures == before)
        {
            PeriodReading reading;
            EngineError error;
            memset(&error, 0, sizeof(error));
            if (test_read(random_volume, 3u, random_shape, &reading, NULL, 0ull, NULL, &error))
            {
                for (unsigned int axis = 0u; axis < 3u; axis += 1u)
                {
                    random_axes += 1ull;
                    random_periods += (reading.axis[axis].period != 0ull) ? 1ull : 0ull;
                }
            }
        }
    }
    scriptura_text(&tally.line, "  uniform random u16, 64 volumes of 32 x 64 x 64, 8 shuffles each: a period found on ");
    scriptura_decimal(&tally.line, random_periods, 1u);
    scriptura_text(&tally.line, " of ");
    scriptura_decimal(&tally.line, random_axes, 1u);
    scriptura_text(&tally.line, " axes\n");

    unsigned short *device_lanes = NULL;
    const int allocated = cudaMalloc((void **)&device_lanes, 64u * sizeof(unsigned short)) == cudaSuccess;
    test_check(&tally, allocated, "device allocation for the refusals");
    if (allocated != 0)
    {
        const unsigned long long small[2] = {8ull, 8ull};
        const unsigned long long empty[2] = {8ull, 0ull};
        const unsigned long long huge[2] = {65536ull, 65536ull};
        const unsigned long long nine[9] = {1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull, 1ull};
        unsigned long long counts[8];
        PeriodMargin band[16];
        test_refusal(&tally, "no lanes", NULL, 2u, small, 8ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "rank 0", device_lanes, 0u, small, 8ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "rank 9", device_lanes, 9u, nine, 8ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "an extent of 0", device_lanes, 2u, empty, 8ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "2^32 voxels", device_lanes, 2u, huge, 8ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "agreement room short by one", device_lanes, 2u, small, 8ull, counts, 7ull, NULL, 0ull);
        test_refusal(&tally, "no draws", device_lanes, 2u, small, 0ull, NULL, 0ull, NULL, 0ull);
        test_refusal(&tally, "band room short by one", device_lanes, 2u, small, 8ull, NULL, 0ull, band, 15ull);
        PeriodMargin tops[2] = {{1ull, 32ull}, {1ull, 32ull}};
        PeriodReading reading;
        EngineError error;
        memset(&error, 0, sizeof(error));
        PeriodRequest request;
        memset(&request, 0, sizeof(request));
        request.device_lanes = device_lanes;
        request.rank = 2u;
        request.shape[0] = 8ull;
        request.shape[1] = 8ull;
        request.draws = 8ull;
        request.null_top = tops;
        request.reading = &reading;
        request.error = &error;
        test_check(&tally, (period_read(&request) == PERIOD_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
                               && (error.module == ENGINE_MODULE_PERIOD),
                   "a given band with draws of its own");
        cudaFree(device_lanes);
    }

    scriptura_text(&tally.line, "  period test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    test_flush(&tally);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
