// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_root.cu: the root pattern
#include "noise_detector_internal.h"

// the box's voxels, 0 where an axis is empty or the count passes NOISE_ROOT_VOXELS_MAX
static unsigned long long noise_root_voxels(const unsigned long long box[4])
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        const int fits = (box[axis] != 0ull) && (box[axis] <= (NOISE_ROOT_VOXELS_MAX / voxels));
        voxels = (fits != 0) ? (voxels * box[axis]) : 0ull;
        if (voxels == 0ull)
        {
            return 0ull;
        }
    }
    return voxels;
}

// the next place in the box, x fastest, as the voxels are laid out
static void noise_root_next(unsigned long long place[4], const unsigned long long box[4])
{
    for (unsigned int axis = 4u; axis > 0u; axis -= 1u)
    {
        place[axis - 1u] += 1ull;
        if (place[axis - 1u] < box[axis - 1u])
        {
            return;
        }
        place[axis - 1u] = 0ull;
    }
}

// a box voxel's place in a term's pattern: its own along the axes the term keeps, 0 along those it shares
static unsigned long long noise_root_pattern_place(const unsigned long long place[4],
                                                   const unsigned long long pattern[4])
{
    unsigned long long index = 0ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        index = (index * pattern[axis]) + ((pattern[axis] == 1ull) ? 0ull : place[axis]);
    }
    return index;
}

// the box's voxels read from the volume into ints, frames, z, y and x
static void noise_root_take(const NoiseRootRequest *request, const unsigned long long box[4], int *values)
{
    const unsigned long long *const low = request->low;
    const unsigned long long *const extent = request->extent;
    unsigned long long at = 0ull;
    for (unsigned long long frame = 0ull; frame < box[0]; frame += 1ull)
    {
        for (unsigned long long z = 0ull; z < box[1]; z += 1ull)
        {
            for (unsigned long long y = 0ull; y < box[2]; y += 1ull)
            {
                // the volume is held. Its voxel count, and every place inside it, fits a word
                const unsigned long long plane = (((low[0] + frame) * extent[1]) + low[1] + z) * extent[2];
                const unsigned short *const row = &request->volume[((plane + low[2] + y) * extent[3]) + low[3]];
                for (unsigned long long x = 0ull; x < box[3]; x += 1ull)
                {
                    values[at] = row[x];
                    at += 1ull;
                }
            }
        }
    }
}

// A term's pattern over the box: each pattern value the mean of the box's voxels that share it, rounded down. Every
// pattern value shares the same count of voxels, the box's voxels over the pattern's.
static void noise_root_pattern(const int *values, const unsigned long long box[4], unsigned long long voxels,
                               unsigned int term, unsigned long long *sums, int *pattern)
{
    unsigned long long extent[4];
    noise_root_extent(term, box, extent);
    const unsigned long long cells = extent[0] * extent[1] * extent[2] * extent[3];
    memset(sums, 0, (size_t)cells * sizeof(unsigned long long));
    unsigned long long place[4] = {0ull, 0ull, 0ull, 0ull};
    for (unsigned long long at = 0ull; at < voxels; at += 1ull)
    {
        // a box value is a lane, never negative
        sums[noise_root_pattern_place(place, extent)] += (unsigned long long)values[at];
        noise_root_next(place, box);
    }
    const unsigned long long shared = voxels / cells;
    for (unsigned long long cell = 0ull; cell < cells; cell += 1ull)
    {
        // a mean of lanes, rounded down, is a lane, which an int holds
        pattern[cell] = (int)(sums[cell] / shared);
    }
}

// each voxel of `from` plus `sign` times its pattern value: -1 leaves the residual, 1 returns the box
static void noise_root_spread(const int *from, const unsigned long long box[4], unsigned long long voxels,
                              unsigned int term, const int *pattern, int sign, int *to)
{
    unsigned long long extent[4];
    noise_root_extent(term, box, extent);
    unsigned long long place[4] = {0ull, 0ull, 0ull, 0ull};
    for (unsigned long long at = 0ull; at < voxels; at += 1ull)
    {
        to[at] = from[at] + (sign * pattern[noise_root_pattern_place(place, extent)]);
        noise_root_next(place, box);
    }
}

static int noise_root_price(const NoiseRootRequest *request, const int *values, const unsigned long long extent[4],
                            unsigned long long *bits)
{
    *bits = 0ull;
    return NOISE_DETECTOR_CHECK((request->cost(values, extent, bits, request->error) == 0L) &&
                                    (*bits <= NOISE_ROOT_BITS_MAX),
                                values, request->error, ENGINE_ERROR_REQUEST);
}

extern "C" long noise_root_box(const NoiseRootRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    unsigned long long box[4] = {0ull, 0ull, 0ull, 0ull};
    int inside = (request->volume != NULL) && (request->cost != NULL) && (request->measurement != NULL);
    for (unsigned int axis = 0u; inside && (axis < 4u); axis += 1u)
    {
        inside = (request->low[axis] < request->high[axis]) && (request->high[axis] <= request->extent[axis]);
        box[axis] = (inside != 0) ? (request->high[axis] - request->low[axis]) : 0ull;
    }
    const unsigned long long voxels = (inside != 0) ? noise_root_voxels(box) : 0ull;
    if (!NOISE_DETECTOR_CHECK(voxels != 0ull, request, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseRootMeasurement *const measurement = request->measurement;
    memset(measurement, 0, sizeof(*measurement));
    measurement->root = NOISE_ROOT_TERMS;
    int *const values = (int *)malloc((size_t)voxels * sizeof(int));
    int *const residual = (int *)malloc((size_t)voxels * sizeof(int));
    int *const pattern = (int *)malloc((size_t)voxels * sizeof(int));
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)voxels * sizeof(unsigned long long));
    int ok = NOISE_DETECTOR_CHECK((values != NULL) && (residual != NULL) && (pattern != NULL) && (sums != NULL),
                                  &values, error, ENGINE_ERROR_RESOURCE);
    if (ok != 0)
    {
        noise_root_take(request, box, values);
    }
    ok = ok && noise_root_price(request, values, box, &measurement->box_bits);
    long long maximum = 0ll;
    for (unsigned int term = 0u; ok && (term < NOISE_ROOT_TERMS); term += 1u)
    {
        unsigned long long extent[4];
        noise_root_extent(term, box, extent);
        noise_root_pattern(values, box, voxels, term, sums, pattern);
        noise_root_spread(values, box, voxels, term, pattern, -1, residual);
        ok = noise_root_price(request, residual, box, &measurement->residual_bits[term]) &&
             noise_root_price(request, pattern, extent, &measurement->pattern_bits[term]);
        // each price is at most 2^61. Each converts to long long exactly and the difference cannot wrap
        measurement->saved[term] = (long long)measurement->box_bits - (long long)measurement->residual_bits[term] -
                                   (long long)measurement->pattern_bits[term];
        if (ok && (measurement->saved[term] > maximum))
        {
            maximum = measurement->saved[term];
            measurement->root = term;
        }
    }
    const unsigned int root = measurement->root;
    if (ok && (root < NOISE_ROOT_TERMS))
    {
        noise_root_pattern(values, box, voxels, root, sums, pattern);
        noise_root_spread(values, box, voxels, root, pattern, -1, residual);
    }
    if (ok && (request->residual != NULL))
    {
        memcpy(request->residual, (root < NOISE_ROOT_TERMS) ? residual : values, (size_t)voxels * sizeof(int));
    }
    if (ok && (request->pattern != NULL) && (root < NOISE_ROOT_TERMS))
    {
        unsigned long long extent[4];
        noise_root_extent(root, box, extent);
        memcpy(request->pattern, pattern, (size_t)(extent[0] * extent[1] * extent[2] * extent[3]) * sizeof(int));
    }
    free(values);
    free(residual);
    free(pattern);
    free(sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_root_return(const NoiseReturnRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const unsigned long long voxels = noise_root_voxels(request->box);
    if (!NOISE_DETECTOR_CHECK((request->residual != NULL) && (request->pattern != NULL) && (request->values != NULL) &&
                                  (request->term < NOISE_ROOT_TERMS) && (voxels != 0ull),
                              request, request->error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    noise_root_spread(request->residual, request->box, voxels, request->term, request->pattern, 1, request->values);
    return 0L;
}
