// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// period_test_reference.cu: the reference counts, peaks and margins
#include "period_test_internal.h"

static unsigned long long s_test_state = 0x9E3779B97F4A7C15ull;

unsigned long long test_next(void)
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
    const unsigned long long carry =
        ((bottom >> 32u) + (cross_one & TEST_LOW_HALF) + (cross_other & TEST_LOW_HALF)) >> 32u;
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

unsigned long long test_reference_counts(const unsigned short *volume, unsigned int rank,
                                         const unsigned long long *extent, unsigned long long *counts)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= extent[axis];
    }
    unsigned long long entry = 0ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        unsigned long long stride = 1ull;
        for (unsigned int later = axis + 1u; later < rank; later += 1u)
        {
            stride *= extent[later];
        }
        const unsigned long long lags = extent[axis] / 2ull;
        const unsigned long long usable = extent[axis] - lags;
        for (unsigned long long lag = 1ull; lag <= lags; lag += 1ull)
        {
            unsigned long long same = 0ull;
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                const unsigned long long along = (voxel / stride) % extent[axis];
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
unsigned long long test_reference_select(const unsigned long long *same, unsigned long long lags,
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

int test_read(const unsigned short *volume, unsigned int rank, const unsigned long long *extent,
              PeriodMeasurement *measurement, unsigned long long *counts, unsigned long long capacity,
              PeriodMargin *band, EngineError *error)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= extent[axis];
    }
    unsigned short *device_lanes = NULL;
    if (cudaMalloc((void **)&device_lanes, (size_t)voxels * sizeof(unsigned short)) != cudaSuccess)
    {
        return 0;
    }
    int ok = cudaMemcpy(device_lanes, volume, (size_t)voxels * sizeof(unsigned short), cudaMemcpyHostToDevice) ==
             cudaSuccess;
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    memcpy(request.extent, extent, rank * sizeof(unsigned long long));
    request.draws = TEST_DRAWS;
    request.content = test_content(volume, voxels);
    request.agreement = counts;
    request.agreement_capacity = capacity;
    request.band = band;
    request.band_capacity = (band != NULL) ? (TEST_DRAWS * rank) : 0ull;
    request.measurement = measurement;
    request.error = error;
    ok = ok && (period_read(&request) == 0L);
    cudaFree(device_lanes);
    return ok;
}

static int test_margin_above(const PeriodMargin *one, const PeriodMargin *other, int or_equal)
{
    return test_wide_above(test_wide_product(one->numerator, other->denominator),
                           test_wide_product(other->numerator, one->denominator), or_equal);
}

int test_band_valid(const PeriodAxis *axis, const PeriodMargin *band)
{
    int ok = axis->band_count <= TEST_DRAWS;
    for (unsigned long long at = 1ull; ok && (at < axis->band_count); at += 1ull)
    {
        ok = test_margin_above(&band[at], &band[at - 1ull], 1);
    }
    if (ok && (axis->band_count != 0ull))
    {
        ok = (memcmp(&axis->band_bottom, &band[0], sizeof(PeriodMargin)) == 0) &&
             (memcmp(&axis->band_top, &band[axis->band_count - 1ull], sizeof(PeriodMargin)) == 0);
    }
    return ok;
}

static int test_margin_before(const void *one, const void *other)
{
    const PeriodMargin *const left = (const PeriodMargin *)one;
    const PeriodMargin *const right = (const PeriodMargin *)other;
    return test_margin_above(left, right, 0) ? 1 : (test_margin_above(right, left, 0) ? -1 : 0);
}

int test_draws_and_given_top(const unsigned short *volume, unsigned int rank, const unsigned long long *extent,
                             const PeriodMeasurement *measurement, const PeriodMargin *band)
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        voxels *= extent[axis];
    }
    unsigned short *device_lanes = NULL;
    if (cudaMalloc((void **)&device_lanes, (size_t)voxels * sizeof(unsigned short)) != cudaSuccess)
    {
        return 0;
    }
    int ok = cudaMemcpy(device_lanes, volume, (size_t)voxels * sizeof(unsigned short), cudaMemcpyHostToDevice) ==
             cudaSuccess;
    EngineError error;
    memset(&error, 0, sizeof(error));
    PeriodRequest request;
    memset(&request, 0, sizeof(request));
    request.device_lanes = device_lanes;
    request.rank = rank;
    memcpy(request.extent, extent, rank * sizeof(unsigned long long));
    request.content = test_content(volume, voxels);
    request.error = &error;
    PeriodMargin drawn[TEST_DRAWS * ENGINE_ARRAY_RANK];
    unsigned long long kept[ENGINE_ARRAY_RANK] = {0ull};
    for (unsigned long long draw = 0ull; ok && (draw < TEST_DRAWS); draw += 1ull)
    {
        PeriodMargin heights[ENGINE_ARRAY_RANK];
        ok = period_draw(&request, draw, heights) == 0L;
        for (unsigned int axis = 0u; ok && (axis < rank); axis += 1u)
        {
            if (heights[axis].numerator != 0ull)
            {
                drawn[(axis * TEST_DRAWS) + kept[axis]] = heights[axis];
                kept[axis] += 1ull;
            }
        }
    }
    PeriodMargin tops[ENGINE_ARRAY_RANK];
    for (unsigned int axis = 0u; ok && (axis < rank); axis += 1u)
    {
        qsort(&drawn[axis * TEST_DRAWS], (size_t)kept[axis], sizeof(PeriodMargin), test_margin_before);
        ok = (kept[axis] == measurement->axis[axis].band_count) &&
             ((kept[axis] == 0ull) || (memcmp(&drawn[axis * TEST_DRAWS], &band[axis * TEST_DRAWS],
                                              (size_t)kept[axis] * sizeof(PeriodMargin)) == 0));
        tops[axis] = (kept[axis] != 0ull) ? measurement->axis[axis].band_top : drawn[axis * TEST_DRAWS];
        tops[axis].numerator = (kept[axis] != 0ull) ? tops[axis].numerator : 0ull;
        tops[axis].denominator = measurement->axis[axis].pairs_per_lag;
    }
    PeriodMeasurement judged;
    request.null_top = tops;
    request.measurement = &judged;
    ok = ok && (period_read(&request) == 0L);
    for (unsigned int axis = 0u; ok && (axis < rank); axis += 1u)
    {
        ok = (judged.axis[axis].period == measurement->axis[axis].period) &&
             (judged.axis[axis].candidate == measurement->axis[axis].candidate);
    }
    cudaFree(device_lanes);
    return ok;
}
