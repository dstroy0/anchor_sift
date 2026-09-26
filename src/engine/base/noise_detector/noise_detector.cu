// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "noise_detector.h"

#include "exact_integer.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define NOISE_DETECTOR_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__, \
                        (const void *)(evacaddr_), (error_))

#define NOISE_DETECTOR_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__, \
                       (const void *)(evacaddr_), (error_))

#define NOISE_DETECTOR_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                    (error_))

#define NOISE_DETECTOR_THREADS 256u

#define NOISE_FLICKER_CELLS (NOISE_FLICKER_LAGS * NOISE_LEVEL_BINS * NOISE_FLICKER_SUMS)

static_assert((NOISE_FLICKER_CELLS * sizeof(unsigned long long)) <= 49152u,
              "noise_detector: the flicker sums fit one block's shared memory");

// the widest squared difference less its neighbour's: each frame difference lies in [-65535, 65535]
#define NOISE_WIDEST_SQUARE (131070ull * 131070ull)

// the lane's top: a value past it was held there
#define NOISE_LANE_TOP 65535u

#define NOISE_VALUES 65536u

// the summary reads means 40 to 199, the range compression_table.md fits the transfer curve over, bins 5 to 24
#define NOISE_SUMMARY_FIRST_BIN 5u

#define NOISE_SUMMARY_LAST_BIN 24u

static_assert(((NOISE_SUMMARY_FIRST_BIN << (NOISE_LEVEL_BIN_SHIFT - 1u)) == 40u)
                  && (((NOISE_SUMMARY_LAST_BIN + 1u) << (NOISE_LEVEL_BIN_SHIFT - 1u)) == 200u),
              "noise_detector: the summary's bins are the means 40 to 199");

__device__ static void noise_flicker_flush(unsigned long long *cells, unsigned int lag, unsigned int level_bin,
                                           unsigned long long run[NOISE_FLICKER_SUMS])
{
    unsigned long long *const cell = &cells[((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS];
    for (unsigned int sum = 0u; sum < NOISE_FLICKER_SUMS; sum += 1u)
    {
        if (run[sum] != 0ull)
        {
            atomicAdd(&cell[sum], run[sum]);
        }
        run[sum] = 0ull;
    }
}

// One thread a voxel. Consecutive pairs of a voxel mostly fall in one level bin, so a pair adds to the thread's run
// and the run goes to the block's sums only when the bin changes.
__global__ static void noise_flicker_kernel(const unsigned short *lanes, unsigned long long frames,
                                            unsigned long long voxels, unsigned long long width,
                                            unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_FLICKER_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_FLICKER_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        const int beside = ((voxel % width) + 1ull) < width;
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            const unsigned long long apart = 1ull << lag;
            unsigned long long run[NOISE_FLICKER_SUMS] = {0ull, 0ull, 0ull, 0ull};
            unsigned int held_bin = 0u;
            for (unsigned long long frame = 0ull; (frame + apart) < frames; frame += 1ull)
            {
                const unsigned long long early = (frame * voxels) + voxel;
                const unsigned long long late = ((frame + apart) * voxels) + voxel;
                const unsigned int before = lanes[early];
                const unsigned int after = lanes[late];
                const unsigned int summed_bin = (before + after) >> NOISE_LEVEL_BIN_SHIFT;
                const unsigned int level_bin = (summed_bin < NOISE_LEVEL_BINS) ? summed_bin : (NOISE_LEVEL_BINS - 1u);
                if ((level_bin != held_bin) && (run[NOISE_FLICKER_PAIRS] != 0ull))
                {
                    noise_flicker_flush(cells, lag, held_bin, run);
                }
                held_bin = level_bin;
                const long long moved = (long long)after - (long long)before;
                run[NOISE_FLICKER_PAIRS] += 1ull;
                // a square is never negative, so it re-signs to unsigned long long exactly
                run[NOISE_FLICKER_SQUARES] += (unsigned long long)(moved * moved);
                if (beside)
                {
                    const long long neighbour_moved = (long long)lanes[late + 1ull] - (long long)lanes[early + 1ull];
                    const long long against_neighbour = moved - neighbour_moved;
                    run[NOISE_FLICKER_NEIGHBOUR_PAIRS] += 1ull;
                    run[NOISE_FLICKER_NEIGHBOUR_SQUARES] += (unsigned long long)(against_neighbour * against_neighbour);
                }
            }
            if (run[NOISE_FLICKER_PAIRS] != 0ull)
            {
                noise_flicker_flush(cells, lag, held_bin, run);
            }
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_FLICKER_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

static long noise_flicker_sample(const unsigned short *volume, const unsigned long long extent[4],
                                 unsigned long long sums[NOISE_FLICKER_CELLS], EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long width = extent[3];
    // every sum is at most one sample's pairs times the widest square, and so is every total the summary forms
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (width != 0ull) && (frames <= (~0ull / voxels))
                     && ((frames * voxels) <= (~0ull / NOISE_WIDEST_SQUARE));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_FLICKER_CELLS * sizeof(unsigned long long);
    unsigned short *device_lanes = NULL;
    unsigned long long *device_sums = NULL;
    int good = NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_sums, sum_bytes), &device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_sums, 0, sum_bytes), device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice), device_lanes,
                                   error);
    if (good != 0)
    {
        const unsigned long long needed = (voxels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_flicker_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, voxels, width, device_sums);
        good = NOISE_DETECTOR_TOOK(cudaGetLastError(), device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static void noise_exact_word(AnchorExactInteger *value, unsigned long long word)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(word & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(word >> 32u);
    value->sign = (word != 0ull) ? 1 : 0;
}

// (squares / pairs) against (first_squares / first_pairs), in thousandths rounded down: the four words multiplied
// across, so no mean is ever rounded. 0 where either mean is undefined or the quotient passes 2^64.
static int noise_per_mille(unsigned long long squares, unsigned long long pairs, unsigned long long first_squares,
                           unsigned long long first_pairs, unsigned long long *per_mille)
{
    if ((pairs == 0ull) || (first_pairs == 0ull) || (first_squares == 0ull))
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&numerator, squares);
    noise_exact_word(&factor, first_pairs);
    int good = anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK;
    noise_exact_word(&factor, 1000ull);
    good = good && (anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK);
    noise_exact_word(&denominator, first_squares);
    noise_exact_word(&factor, pairs);
    good = good && (anchor_exact_multiply(&denominator, &factor, &denominator) == ANCHOR_EXACT_OK)
        && (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; good && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        good = quotient.limb[limb] == 0u;
    }
    *per_mille = good ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0]) : 0ull;
    return good;
}

// every lag's sums pooled over the summary's level bins, means 40 to 199
static void noise_flicker_pooled(const unsigned long long sums[NOISE_FLICKER_CELLS],
                                 unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS])
{
    memset(pooled, 0, (size_t)NOISE_FLICKER_LAGS * NOISE_FLICKER_SUMS * sizeof(unsigned long long));
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            for (unsigned int sum = 0u; sum < NOISE_FLICKER_SUMS; sum += 1u)
            {
                pooled[lag][sum] += sums[(((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS) + sum];
            }
        }
    }
}

static void noise_flicker_summary(const char *name, const unsigned long long extent[4],
                                  const unsigned long long sums[NOISE_FLICKER_CELLS])
{
    unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS];
    noise_flicker_pooled(sums, pooled);
    printf("  %-24s %llu frames of %llux%llux%llu; means 40 to 199, %llu pairs at lag 1\n", name, extent[0], extent[1],
           extent[2], extent[3], pooled[0][NOISE_FLICKER_PAIRS]);
    const unsigned int kinds[2][2] = {{NOISE_FLICKER_SQUARES, NOISE_FLICKER_PAIRS},
                                      {NOISE_FLICKER_NEIGHBOUR_SQUARES, NOISE_FLICKER_NEIGHBOUR_PAIRS}};
    const char *const said[2] = {"the frame difference         ", "less its x neighbour's       "};
    for (unsigned int kind = 0u; kind < 2u; kind += 1u)
    {
        printf("    %s", said[kind]);
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            unsigned long long per_mille = 0ull;
            if (noise_per_mille(pooled[lag][kinds[kind][0]], pooled[lag][kinds[kind][1]], pooled[0][kinds[kind][0]],
                                pooled[0][kinds[kind][1]], &per_mille))
            {
                printf(" %6llu", per_mille);
            }
            else
            {
                printf(" %6s", "-");
            }
        }
        printf("\n");
    }
    fflush(stdout);
}

static int noise_flicker_rows(FILE *table, const char *name, const unsigned long long sums[NOISE_FLICKER_CELLS])
{
    int good = 1;
    for (unsigned int lag = 0u; good && (lag < NOISE_FLICKER_LAGS); lag += 1u)
    {
        for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const unsigned long long *const cell = &sums[((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS];
            if ((cell[NOISE_FLICKER_PAIRS] == 0ull) && (cell[NOISE_FLICKER_NEIGHBOUR_PAIRS] == 0ull))
            {
                continue;
            }
            const unsigned int lowest = level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u);
            good = fprintf(table, "%s\t%u\t%u\t%llu\t%llu\t%llu\t%llu\n", name, 1u << lag, lowest,
                           cell[NOISE_FLICKER_PAIRS], cell[NOISE_FLICKER_SQUARES], cell[NOISE_FLICKER_NEIGHBOUR_PAIRS],
                           cell[NOISE_FLICKER_NEIGHBOUR_SQUARES])
                 > 0;
        }
    }
    return good;
}

extern "C" long noise_flicker_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_ROOM];
    const int written = (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_flicker.tsv", request->set)
                                               : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    int good = NOISE_DETECTOR_HELD(named && (request->samples != NULL) && (request->load != NULL), request, error,
                                   ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_IO(table != NULL, path, error)
            && NOISE_DETECTOR_IO(fprintf(table, "sample\tlag\tlowest_mean\tpairs\tsquares\tneighbour_pairs"
                                                "\tneighbour_squares\n")
                                     > 0,
                                 table, error);
    printf("  flicker: the structure function D(k), the mean square of I(t + k) - I(t), at lags 1 to 64, in bins of 8"
           " by the pair's mean\n");
    printf("  each lag's mean square against lag 1's, per mille (white noise holds 1000 at every lag):\n");
    printf("    %-29s", "lag");
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        printf(" %6u", 1u << lag);
    }
    printf("\n");
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)NOISE_FLICKER_CELLS
                                                                  * sizeof(unsigned long long));
    good = good && NOISE_DETECTOR_HELD(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST)
            && (noise_flicker_sample(volume, extent, sums, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_flicker_rows(table, name, sums) != 0, table, error);
        if (good != 0)
        {
            noise_flicker_summary(name, extent, sums);
        }
    }
    free(sums);
    if (table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && good;
    }
    if (good != 0)
    {
        printf("  flicker: %u samples in %llu ms; every sum is in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static_assert(ANCHOR_EXACT_LIMBS >= 8u, "noise_detector: a 128 bit sum times 1000 fits the exact integer");

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} NoiseWide;

static void noise_wide_add(NoiseWide *sum, unsigned long long low, unsigned long long high)
{
    const unsigned long long before = sum->low;
    sum->low += low;
    sum->high += high + ((sum->low < before) ? 1ull : 0ull);
}

// magnitude squared as (upper 2^32 + lower)^2 = upper^2 2^64 + upper lower 2^33 + lower^2, each part below 2^64
static void noise_wide_add_square(NoiseWide *sum, unsigned long long magnitude)
{
    const unsigned long long upper = magnitude >> 32u;
    const unsigned long long lower = magnitude & 0xFFFFFFFFull;
    const unsigned long long cross = upper * lower;
    noise_wide_add(sum, lower * lower, upper * upper);
    noise_wide_add(sum, cross << 33u, cross >> 31u);
}

typedef struct
{
    unsigned long long lines;
    unsigned long long members;
    unsigned long long member_squares;
    NoiseWide line_squares;
} NoiseLineCell;

#define NOISE_LINE_CELLS (NOISE_LINE_KINDS * NOISE_LEVEL_BINS)

static const char *const NOISE_LINE_NAMES[NOISE_LINE_KINDS] = {"row", "column", "plane"};

// One frame pair's z plane: its frame differences summed and their squares summed, the squares of its row sums (along
// x) and of its column sums (along y) each summed, and its values summed, which is its level; then its static voxels'
// count, their frame differences summed and squared, and their values summed, which is their level
typedef struct
{
    long long summed;
    unsigned long long squared;
    unsigned long long row_squares;
    unsigned long long column_squares;
    unsigned long long level;
    unsigned long long static_members;
    long long static_summed;
    unsigned long long static_squared;
    unsigned long long static_level;
} NoisePlane;

// A sample's planes pooled as the two-way layout each plane is, rows by columns (noise_vector_integration_table.md,
// rows 8 to 10). With N voxels a plane, H rows and W columns, a plane's sum P, its squares summed Q, and its row and
// column sums squared and summed A and B, each plane adds N Q - P^2 to spread, H A - P^2 to rows, W B - P^2 to columns
// and P^2 to plane_squares. Independent noise summing to Σs over a plane gives spread - rows - columns its expectation
// (H - 1)(W - 1) Σs, whatever the rows, the columns and the plane share.
typedef struct
{
    unsigned long long planes;
    unsigned long long height;
    unsigned long long width;
    AnchorExactInteger spread;
    AnchorExactInteger rows;
    AnchorExactInteger columns;
    AnchorExactInteger plane_squares;
} NoisePlanePool;

// the static voxels are the dimmest 1 / NOISE_STATIC_SHARE, by their mean over the frames, of those that change and
// never touch either end of the lane
#define NOISE_STATIC_SHARE 4ull

// A sample's static voxels as an unbalanced layout, each line holding only its static members. For a line of n of
// them with frame differences summed to R and squared to S, E[R^2 - S] = (n^2 - n)(var_row + var_plane) along a row
// and (n^2 - n)(var_column + var_plane) along a column. A plane's static sum P over N members, squared to Q, gives
// E[P^2 - Q] = K_row var_row + K_column var_column + (N^2 - N) var_plane, K summing n^2 - n over its rows or columns.
// Pooled here: the ceiling (the highest voxel mean kept), the members M and their squares T, each kind's n^2 - n
// summed, and each kind's squared sums summed.
typedef struct
{
    unsigned long long ceiling;
    unsigned long long members;
    unsigned long long squares;
    unsigned long long row_pairs;
    unsigned long long column_pairs;
    unsigned long long plane_pairs;
    NoiseWide row_squares;
    NoiseWide column_squares;
    NoiseWide plane_squares;
} NoiseStaticPool;

// One thread a line of one frame pair: its frame, its z plane, and its row (along x) or column (along y). The line's
// frame differences are summed, their squares are summed, and so are its values, which place it in a level bin; its
// static members are counted, and their frame differences summed and squared and their values summed apart.
__global__ static void noise_lines_kernel(const unsigned short *lanes, const unsigned char *mask,
                                          unsigned long long frame_pairs, unsigned long long depth,
                                          unsigned long long height, unsigned long long width, unsigned int along_x,
                                          long long *line_sums, unsigned long long *line_squares,
                                          unsigned long long *line_levels, long long *static_sums,
                                          unsigned long long *static_squares, unsigned long long *static_members,
                                          unsigned long long *static_levels)
{
    const unsigned long long across = (along_x != 0u) ? height : width;
    const unsigned long long length = (along_x != 0u) ? width : height;
    const unsigned long long step = (along_x != 0u) ? 1ull : width;
    const unsigned long long voxels = depth * height * width;
    const unsigned long long lines = frame_pairs * depth * across;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long line = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; line < lines;
         line += jump)
    {
        const unsigned long long frame = line / (depth * across);
        const unsigned long long plane = (line / across) % depth;
        const unsigned long long place = line % across;
        const unsigned long long first = (plane * height * width) + ((along_x != 0u) ? (place * width) : place);
        long long summed = 0ll;
        unsigned long long squared = 0ull;
        unsigned long long level = 0ull;
        long long static_summed = 0ll;
        unsigned long long static_squared = 0ull;
        unsigned long long static_counted = 0ull;
        unsigned long long static_level = 0ull;
        for (unsigned long long at = 0ull; at < length; at += 1ull)
        {
            const unsigned long long voxel = first + (at * step);
            const unsigned int before = lanes[(frame * voxels) + voxel];
            const unsigned int after = lanes[((frame + 1ull) * voxels) + voxel];
            const long long moved = (long long)after - (long long)before;
            // a square is never negative, so it re-signs to unsigned long long exactly
            const unsigned long long square = (unsigned long long)(moved * moved);
            summed += moved;
            squared += square;
            level += (unsigned long long)before + after;
            if (mask[voxel] != 0u)
            {
                static_summed += moved;
                static_squared += square;
                static_counted += 1ull;
                static_level += (unsigned long long)before + after;
            }
        }
        line_sums[line] = summed;
        line_squares[line] = squared;
        line_levels[line] = level;
        static_sums[line] = static_summed;
        static_squares[line] = static_squared;
        static_members[line] = static_counted;
        static_levels[line] = static_level;
    }
}

static void noise_line_add(NoiseLineCell *cells, unsigned int kind, unsigned long long length, long long summed,
                           unsigned long long squared, unsigned long long level)
{
    // the line's mean pair level, in bins of 8: the level sum holds 2 values a member
    const unsigned long long level_bin = level / (length * 16ull);
    NoiseLineCell *const cell = &cells[(kind * NOISE_LEVEL_BINS)
                                       + ((level_bin < NOISE_LEVEL_BINS) ? level_bin : (NOISE_LEVEL_BINS - 1u))];
    cell->lines += 1ull;
    cell->members += length;
    cell->member_squares += squared;
    // a line's sum is far from the most negative long long, so its negation is exact
    noise_wide_add_square(&cell->line_squares, (unsigned long long)((summed < 0ll) ? -summed : summed));
}

// sum gains left times right, less square, exactly
static int noise_exact_add_centred(AnchorExactInteger *sum, unsigned long long left, unsigned long long right,
                                   const AnchorExactInteger *square)
{
    AnchorExactInteger term;
    AnchorExactInteger factor;
    noise_exact_word(&term, left);
    noise_exact_word(&factor, right);
    return (anchor_exact_multiply(&term, &factor, &term) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&term, square, &term) == ANCHOR_EXACT_OK)
        && (anchor_exact_add(sum, &term, sum) == ANCHOR_EXACT_OK);
}

static int noise_planes_pool(const NoisePlane *planes, unsigned long long count, unsigned long long height,
                             unsigned long long width, NoisePlanePool *pool)
{
    pool->planes = count;
    pool->height = height;
    pool->width = width;
    anchor_exact_zero(&pool->spread);
    anchor_exact_zero(&pool->rows);
    anchor_exact_zero(&pool->columns);
    anchor_exact_zero(&pool->plane_squares);
    int good = 1;
    for (unsigned long long plane = 0ull; good && (plane < count); plane += 1ull)
    {
        const NoisePlane *const one = &planes[plane];
        AnchorExactInteger square;
        // a plane's sum is far from the most negative long long, so its negation is exact
        noise_exact_word(&square, (unsigned long long)((one->summed < 0ll) ? -one->summed : one->summed));
        good = (anchor_exact_multiply(&square, &square, &square) == ANCHOR_EXACT_OK)
            && noise_exact_add_centred(&pool->spread, height * width, one->squared, &square)
            && noise_exact_add_centred(&pool->rows, height, one->row_squares, &square)
            && noise_exact_add_centred(&pool->columns, width, one->column_squares, &square)
            && (anchor_exact_add(&pool->plane_squares, &square, &pool->plane_squares) == ANCHOR_EXACT_OK);
    }
    return good;
}

static int noise_planes_rows(FILE *table, const char *name, const NoisePlane *planes, unsigned long long count,
                             unsigned long long depth, unsigned long long members)
{
    int good = 1;
    for (unsigned long long plane = 0ull; good && (plane < count); plane += 1ull)
    {
        const NoisePlane *const one = &planes[plane];
        good = fprintf(table, "%s\t%llu\t%llu\t%llu\t%llu\t%lld\t%llu\t%llu\t%llu\t%llu\t%lld\t%llu\t%llu\n", name,
                       plane / depth, plane % depth, members, one->level, one->summed, one->squared, one->row_squares,
                       one->column_squares, one->static_members, one->static_summed, one->static_squared,
                       one->static_level)
             > 0;
    }
    return good;
}

// A quiet voxel's frame differences have a mean square of at most NOISE_QUIET_SLOPE times its mean plus
// NOISE_QUIET_FLOOR. A still voxel's is 2 (g L + R^2), and the set's transfer curves (compression_table.md) hold g at
// most 1.162 and the read variance near 2.5, at most 0.6 of this bound at every level; a voxel that structure moves
// through reads far past it.
#define NOISE_QUIET_SLOPE 4ull

#define NOISE_QUIET_FLOOR 32ull

// Marks the static voxels: among those that change and never touch either end of the lane, and where quiet is set
// that pass the spread test above, the dimmest 1 / NOISE_STATIC_SHARE by their mean over the frames, rounded down.
// The ceiling is the highest mean kept. The pixel maps leave quiet unset: a hot pixel is loud and is what they seek.
static int noise_static_mask(const unsigned short *volume, unsigned long long frames, unsigned long long voxels,
                             unsigned int quiet, unsigned char *mask, unsigned long long *ceiling)
{
    unsigned long long *const totals = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned short *const least = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    unsigned short *const most = (unsigned short *)calloc((size_t)voxels, sizeof(unsigned short));
    unsigned long long *const counted = (unsigned long long *)calloc(NOISE_VALUES, sizeof(unsigned long long));
    unsigned long long *const squares = (quiet != 0u)
                                          ? (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long))
                                          : NULL;
    // a voxel's squares times the frames is at most the frames squared times 65535 squared, a word to 65536 frames
    const int good = (totals != NULL) && (least != NULL) && (most != NULL) && (counted != NULL)
                  && ((quiet == 0u) || ((squares != NULL) && (frames <= 65536ull)));
    *ceiling = 0ull;
    if (good != 0)
    {
        memset(least, 0xFF, (size_t)voxels * sizeof(unsigned short));
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            const unsigned short *const lanes = &volume[frame * voxels];
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                totals[voxel] += lanes[voxel];
                least[voxel] = (lanes[voxel] < least[voxel]) ? lanes[voxel] : least[voxel];
                most[voxel] = (lanes[voxel] > most[voxel]) ? lanes[voxel] : most[voxel];
            }
            for (unsigned long long voxel = 0ull; (quiet != 0u) && (frame != 0ull) && (voxel < voxels); voxel += 1ull)
            {
                // the same voxel one frame earlier sits a volume's voxels before it, inside the volume from frame 1
                const long long moved = (long long)lanes[voxel] - (long long)volume[((frame - 1ull) * voxels) + voxel];
                // a square is never negative, so it re-signs to unsigned long long exactly
                squares[voxel] += (unsigned long long)(moved * moved);
            }
        }
        unsigned long long eligible = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            const unsigned long long bound = (NOISE_QUIET_SLOPE * totals[voxel]) + (NOISE_QUIET_FLOOR * frames);
            const int still = (quiet == 0u) || ((squares[voxel] * frames) <= ((frames - 1ull) * bound));
            mask[voxel] = ((least[voxel] != 0u) && (most[voxel] != NOISE_LANE_TOP) && (least[voxel] != most[voxel])
                           && still)
                            ? 1u
                            : 0u;
            if (mask[voxel] != 0u)
            {
                // a mean of values that are each below 2^16 is below 2^16
                counted[totals[voxel] / frames] += 1ull;
                eligible += 1ull;
            }
        }
        const unsigned long long wanted = (eligible + NOISE_STATIC_SHARE - 1ull) / NOISE_STATIC_SHARE;
        unsigned long long running = 0ull;
        for (unsigned long long mean = 0ull; (mean < NOISE_VALUES) && (running < wanted); mean += 1ull)
        {
            running += counted[mean];
            *ceiling = mean;
        }
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            mask[voxel] = ((mask[voxel] != 0u) && ((totals[voxel] / frames) <= *ceiling)) ? 1u : 0u;
        }
    }
    free(totals);
    free(least);
    free(most);
    free(counted);
    free(squares);
    return good;
}

// a static line's squared sum and its n^2 - n, pooled
static void noise_static_line_add(NoiseWide *line_squares, unsigned long long *pairs, long long summed,
                                  unsigned long long members)
{
    // a line's sum is far from the most negative long long, so its negation is exact
    noise_wide_add_square(line_squares, (unsigned long long)((summed < 0ll) ? -summed : summed));
    // n^2 - n is 0 for no member, where the unsigned n - 1 wraps and the product is still 0
    *pairs += members * (members - 1ull);
}

// The sample's lines binned into cells, and every plane's sums written to the plane table under the sample's name and
// pooled for the two-way layout; the static voxels' lines pooled apart.
static long noise_lines_sample(const unsigned short *volume, const unsigned long long extent[4],
                               NoiseLineCell cells[NOISE_LINE_CELLS], NoisePlanePool *pool, NoiseStaticPool *still,
                               FILE *plane_table, const char *name, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long height = extent[2];
    const unsigned long long width = extent[3];
    const unsigned long long voxels = depth * height * width;
    const unsigned long long plane_voxels = height * width;
    const unsigned long long longer = (height > width) ? height : width;
    // every member square sum fits a word, and a plane's sum and level sum fit theirs; a plane's squared row sums
    // total at most its voxels times its width times 65535 squared, its columns' at most its voxels times its height
    // times that, and the longer side bounds both; every n^2 - n pooled totals at most the sample's voxel-frames times
    // a plane's voxels, which a plane of at most 65535 squared voxels holds in a word
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels))
                     && ((frames * voxels) <= (~0ull / (65535ull * 65535ull)))
                     && (plane_voxels <= (0x7FFFFFFFFFFFFFFFull / 131070ull))
                     && (longer <= ((~0ull / (65535ull * 65535ull)) / plane_voxels))
                     && (plane_voxels <= (65535ull * 65535ull));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    memset(cells, 0, (size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    memset(still, 0, sizeof(*still));
    const unsigned long long frame_pairs = frames - 1ull;
    const unsigned long long row_lines = frame_pairs * depth * height;
    const unsigned long long column_lines = frame_pairs * depth * width;
    const unsigned long long most_lines = (row_lines > column_lines) ? row_lines : column_lines;
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t line_bytes = (size_t)most_lines * sizeof(unsigned long long);
    unsigned short *device_lanes = NULL;
    unsigned char *device_mask = NULL;
    long long *device_sums = NULL;
    unsigned long long *device_squares = NULL;
    unsigned long long *device_levels = NULL;
    long long *device_static_sums = NULL;
    unsigned long long *device_static_squares = NULL;
    unsigned long long *device_static_members = NULL;
    unsigned long long *device_static_levels = NULL;
    long long *const sums = (long long *)malloc(line_bytes);
    unsigned long long *const squares = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const levels = (unsigned long long *)malloc(line_bytes);
    long long *const static_sums = (long long *)malloc(line_bytes);
    unsigned long long *const static_squares = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const static_members = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const static_levels = (unsigned long long *)malloc(line_bytes);
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    const unsigned long long plane_count = frame_pairs * depth;
    NoisePlane *const planes = (NoisePlane *)malloc((size_t)plane_count * sizeof(NoisePlane));
    int good = NOISE_DETECTOR_HELD((sums != NULL) && (squares != NULL) && (levels != NULL) && (static_sums != NULL)
                                       && (static_squares != NULL) && (static_members != NULL)
                                       && (static_levels != NULL) && (mask != NULL) && (planes != NULL),
                                   &sums, error, ENGINE_ERROR_RESOURCE)
            && NOISE_DETECTOR_HELD(noise_static_mask(volume, frames, voxels, 1u, mask, &still->ceiling) != 0, mask,
                                   error, ENGINE_ERROR_RESOURCE)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_mask, (size_t)voxels), &device_mask, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_sums, line_bytes), &device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_squares, line_bytes), &device_squares, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_levels, line_bytes), &device_levels, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_static_sums, line_bytes), &device_static_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_static_squares, line_bytes), &device_static_squares,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_static_members, line_bytes), &device_static_members,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_static_levels, line_bytes), &device_static_levels,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice), device_lanes,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_mask, mask, (size_t)voxels, cudaMemcpyHostToDevice), device_mask,
                                   error);
    for (unsigned int kind = NOISE_LINE_ROWS; good && (kind <= NOISE_LINE_COLUMNS); kind += 1u)
    {
        const unsigned int along_x = (kind == NOISE_LINE_ROWS) ? 1u : 0u;
        const unsigned long long lines = (along_x != 0u) ? row_lines : column_lines;
        const unsigned long long length = (along_x != 0u) ? width : height;
        const unsigned long long needed = (lines + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_lines_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, device_mask, frame_pairs, depth, height,
                                                                width, along_x, device_sums, device_squares,
                                                                device_levels, device_static_sums,
                                                                device_static_squares, device_static_members,
                                                                device_static_levels);
        const size_t taken = (size_t)lines * sizeof(unsigned long long);
        good = NOISE_DETECTOR_TOOK(cudaGetLastError(), device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(sums, device_sums, taken, cudaMemcpyDeviceToHost), sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(squares, device_squares, taken, cudaMemcpyDeviceToHost), squares, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(levels, device_levels, taken, cudaMemcpyDeviceToHost), levels, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(static_sums, device_static_sums, taken, cudaMemcpyDeviceToHost),
                                   static_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(static_squares, device_static_squares, taken, cudaMemcpyDeviceToHost),
                                   static_squares, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(static_members, device_static_members, taken, cudaMemcpyDeviceToHost),
                                   static_members, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(static_levels, device_static_levels, taken, cudaMemcpyDeviceToHost),
                                   static_levels, error);
        NoiseWide *const static_lines = (along_x != 0u) ? &still->row_squares : &still->column_squares;
        unsigned long long *const static_pairs = (along_x != 0u) ? &still->row_pairs : &still->column_pairs;
        for (unsigned long long line = 0ull; good && (line < lines); line += 1ull)
        {
            noise_line_add(cells, kind, length, sums[line], squares[line], levels[line]);
            noise_static_line_add(static_lines, static_pairs, static_sums[line], static_members[line]);
        }
        // the rows of one frame pair and one z plane sit together, height of them, and together they are the plane
        for (unsigned long long plane = 0ull; good && (along_x != 0u) && (plane < plane_count); plane += 1ull)
        {
            long long summed = 0ll;
            unsigned long long squared = 0ull;
            unsigned long long level = 0ull;
            unsigned long long row_squares = 0ull;
            long long static_summed = 0ll;
            unsigned long long static_squared = 0ull;
            unsigned long long static_counted = 0ull;
            unsigned long long static_level = 0ull;
            for (unsigned long long row = plane * height; row < ((plane + 1ull) * height); row += 1ull)
            {
                summed += sums[row];
                squared += squares[row];
                level += levels[row];
                // a row's sum is far from the most negative long long, so its negation is exact
                const unsigned long long magnitude = (unsigned long long)((sums[row] < 0ll) ? -sums[row] : sums[row]);
                row_squares += magnitude * magnitude;
                static_summed += static_sums[row];
                static_squared += static_squares[row];
                static_counted += static_members[row];
                static_level += static_levels[row];
            }
            noise_line_add(cells, NOISE_LINE_PLANES, plane_voxels, summed, squared, level);
            noise_static_line_add(&still->plane_squares, &still->plane_pairs, static_summed, static_counted);
            still->members += static_counted;
            still->squares += static_squared;
            planes[plane].summed = summed;
            planes[plane].squared = squared;
            planes[plane].row_squares = row_squares;
            planes[plane].level = level;
            planes[plane].static_members = static_counted;
            planes[plane].static_summed = static_summed;
            planes[plane].static_squared = static_squared;
            planes[plane].static_level = static_level;
        }
        // a plane's columns sit together in the same order, width of them
        for (unsigned long long plane = 0ull; good && (along_x == 0u) && (plane < plane_count); plane += 1ull)
        {
            unsigned long long column_squares = 0ull;
            for (unsigned long long column = plane * width; column < ((plane + 1ull) * width); column += 1ull)
            {
                // a column's sum is far from the most negative long long, so its negation is exact
                const unsigned long long magnitude = (unsigned long long)((sums[column] < 0ll) ? -sums[column]
                                                                                               : sums[column]);
                column_squares += magnitude * magnitude;
            }
            planes[plane].column_squares = column_squares;
        }
    }
    // a sim reading one volume passes no plane table
    good = good
        && NOISE_DETECTOR_HELD(noise_planes_pool(planes, plane_count, height, width, pool) != 0, pool, error,
                               ENGINE_ERROR_RESOURCE)
        && ((plane_table == NULL)
            || NOISE_DETECTOR_IO(noise_planes_rows(plane_table, name, planes, plane_count, depth, plane_voxels) != 0,
                                 plane_table, error));
    cudaFree(device_lanes);
    cudaFree(device_mask);
    cudaFree(device_sums);
    cudaFree(device_squares);
    cudaFree(device_levels);
    cudaFree(device_static_sums);
    cudaFree(device_static_squares);
    cudaFree(device_static_members);
    cudaFree(device_static_levels);
    free(sums);
    free(squares);
    free(levels);
    free(static_sums);
    free(static_squares);
    free(static_members);
    free(static_levels);
    free(mask);
    free(planes);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static void noise_exact_wide(AnchorExactInteger *value, const NoiseWide *wide)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(wide->low & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(wide->low >> 32u);
    value->limb[2] = (uint32_t)(wide->high & 0xFFFFFFFFull);
    value->limb[3] = (uint32_t)(wide->high >> 32u);
    value->sign = ((wide->low | wide->high) != 0ull) ? 1 : 0;
}

// the lines' summed squares against their members' squares, in thousandths rounded down; 0 where nothing was summed
static int noise_line_per_mille(const NoiseWide *line_squares, unsigned long long member_squares,
                                unsigned long long *per_mille)
{
    if (member_squares == 0ull)
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_wide(&numerator, line_squares);
    noise_exact_word(&factor, 1000ull);
    noise_exact_word(&denominator, member_squares);
    int good = (anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK)
            && (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; good && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        good = quotient.limb[limb] == 0u;
    }
    *per_mille = good ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0]) : 0ull;
    return good;
}

static void noise_lines_summary(const char *name, const NoiseLineCell cells[NOISE_LINE_CELLS])
{
    printf("  %-24s", name);
    unsigned long long counted[NOISE_LINE_KINDS];
    for (unsigned int kind = 0u; kind < NOISE_LINE_KINDS; kind += 1u)
    {
        NoiseLineCell pooled;
        memset(&pooled, 0, sizeof(pooled));
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            const NoiseLineCell *const cell = &cells[(kind * NOISE_LEVEL_BINS) + level_bin];
            pooled.lines += cell->lines;
            pooled.member_squares += cell->member_squares;
            noise_wide_add(&pooled.line_squares, cell->line_squares.low, cell->line_squares.high);
        }
        counted[kind] = pooled.lines;
        unsigned long long per_mille = 0ull;
        if (noise_line_per_mille(&pooled.line_squares, pooled.member_squares, &per_mille))
        {
            printf(" %9llu", per_mille);
        }
        else
        {
            printf(" %9s", "-");
        }
    }
    printf("   lines: %llu, %llu, %llu\n", counted[NOISE_LINE_ROWS], counted[NOISE_LINE_COLUMNS],
           counted[NOISE_LINE_PLANES]);
    fflush(stdout);
}

// scale times numerator over denominator, signed and rounded toward zero; 0 where the denominator is 0 or the
// quotient's magnitude reaches 2^63
static int noise_exact_ratio(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                             unsigned long long scale, long long *ratio)
{
    if (denominator->sign == 0)
    {
        return 0;
    }
    AnchorExactInteger scaled;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&factor, scale);
    int good = (anchor_exact_multiply(numerator, &factor, &scaled) == ANCHOR_EXACT_OK)
            && (anchor_exact_divide(&scaled, denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; good && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        good = quotient.limb[limb] == 0u;
    }
    const unsigned long long magnitude = good ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0])
                                              : 0ull;
    good = good && (magnitude <= 0x7FFFFFFFFFFFFFFFull);
    // the magnitude is below 2^63, so it converts to long long exactly; the sign is held apart
    *ratio = good ? ((long long)magnitude * (long long)quotient.sign) : 0ll;
    return good;
}

// The pooled planes as three ratios against the independent part s, the variance of one voxel's frame difference
// that nothing shares: rows 1 + W var_row / s, columns 1 + H var_col / s and the plane 1 + N var_plane / s, per mille,
// each 1000 where nothing is shared; then s itself in lane units squared, rounded toward zero. With D = spread - rows -
// columns, the row ratio is rows (W - 1) / D, the column ratio columns (H - 1) / D, and the plane ratio
// (plane_squares (H - 1)(W - 1) - rows (W - 1) - columns (H - 1) + 2 D) / D.
#define NOISE_TWO_WAY_READINGS 4u

static_assert(NOISE_TWO_WAY_READINGS == NOISE_STATIC_ROWS,
              "noise_detector: the two-way readings come first in a volume's readings, the static ones after them");

static void noise_planes_readings(const NoisePlanePool *pool, long long readings[NOISE_TWO_WAY_READINGS],
                                  int held[NOISE_TWO_WAY_READINGS])
{
    const unsigned long long height = pool->height;
    const unsigned long long width = pool->width;
    AnchorExactInteger residual;
    AnchorExactInteger factor;
    AnchorExactInteger row_part;
    AnchorExactInteger column_part;
    AnchorExactInteger plane_part;
    AnchorExactInteger counted;
    noise_exact_word(&factor, width - 1ull);
    int good = (anchor_exact_subtract(&pool->spread, &pool->rows, &residual) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&residual, &pool->columns, &residual) == ANCHOR_EXACT_OK)
            && (anchor_exact_multiply(&pool->rows, &factor, &row_part) == ANCHOR_EXACT_OK);
    noise_exact_word(&factor, height - 1ull);
    good = good && (anchor_exact_multiply(&pool->columns, &factor, &column_part) == ANCHOR_EXACT_OK);
    noise_exact_word(&factor, (height - 1ull) * (width - 1ull));
    good = good && (anchor_exact_multiply(&pool->plane_squares, &factor, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&plane_part, &row_part, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&plane_part, &column_part, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_add(&plane_part, &residual, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_add(&plane_part, &residual, &plane_part) == ANCHOR_EXACT_OK);
    // the planes' voxels are the sample's frame pairs times its voxels, which the sample's bound holds in a word
    noise_exact_word(&counted, height * width * pool->planes);
    good = good && (anchor_exact_multiply(&counted, &factor, &counted) == ANCHOR_EXACT_OK);
    const AnchorExactInteger *const numerators[NOISE_TWO_WAY_READINGS] = {&row_part, &column_part, &plane_part,
                                                                          &residual};
    const AnchorExactInteger *const denominators[NOISE_TWO_WAY_READINGS] = {&residual, &residual, &residual,
                                                                            &counted};
    const unsigned long long scales[NOISE_TWO_WAY_READINGS] = {1000ull, 1000ull, 1000ull, 1ull};
    for (unsigned int ratio = 0u; ratio < NOISE_TWO_WAY_READINGS; ratio += 1u)
    {
        readings[ratio] = 0ll;
        held[ratio] = good
                   && noise_exact_ratio(numerators[ratio], denominators[ratio], scales[ratio], &readings[ratio]);
    }
}

static void noise_planes_summary(const NoisePlanePool *pool)
{
    long long readings[NOISE_TWO_WAY_READINGS];
    int held[NOISE_TWO_WAY_READINGS];
    noise_planes_readings(pool, readings, held);
    const char *const said[NOISE_TWO_WAY_READINGS] = {"within each plane: rows", "columns", "plane", "independent"};
    printf("  %-24s", "");
    for (unsigned int ratio = 0u; ratio < NOISE_TWO_WAY_READINGS; ratio += 1u)
    {
        if (held[ratio] != 0)
        {
            printf(" %s %lld", said[ratio], readings[ratio]);
        }
        else
        {
            printf(" %s -", said[ratio]);
        }
    }
    printf("\n");
    fflush(stdout);
}

// the static layout's readings: rows, columns, the plane, and the independent part
#define NOISE_STATIC_READINGS 4u

static_assert((NOISE_TWO_WAY_READINGS + NOISE_STATIC_READINGS) == NOISE_PLANE_READINGS,
              "noise_detector: a volume's line readings are the two-way ones, then the static ones");

// The static layout's three shared variances against the independent part s, per mille and signed (each 0 where
// nothing is shared), then s in thousandths of a lane unit squared. With each kind's excess A its squared sums less T,
// D_plane = K_plane - K_row - K_column: var_plane = (A_plane - A_row - A_column) / D_plane, var_row = A_row / K_row -
// var_plane, var_column = A_column / K_column - var_plane, and s = T / M - var_row - var_column - var_plane, each
// carried over the common denominator L = M K_row K_column D_plane so nothing is rounded before the last division.
static void noise_static_readings(const NoiseStaticPool *still, long long readings[NOISE_STATIC_READINGS],
                                  int held[NOISE_STATIC_READINGS])
{
    AnchorExactInteger squares;
    AnchorExactInteger members;
    AnchorExactInteger row_pairs;
    AnchorExactInteger column_pairs;
    AnchorExactInteger plane_pairs;
    AnchorExactInteger row_excess;
    AnchorExactInteger column_excess;
    AnchorExactInteger plane_excess;
    noise_exact_word(&squares, still->squares);
    noise_exact_word(&members, still->members);
    noise_exact_word(&row_pairs, still->row_pairs);
    noise_exact_word(&column_pairs, still->column_pairs);
    noise_exact_word(&plane_pairs, still->plane_pairs);
    noise_exact_wide(&row_excess, &still->row_squares);
    noise_exact_wide(&column_excess, &still->column_squares);
    noise_exact_wide(&plane_excess, &still->plane_squares);
    // plane_pairs becomes D_plane, and plane_excess the plane's excess less the rows' and the columns'
    int good = (anchor_exact_subtract(&row_excess, &squares, &row_excess) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&column_excess, &squares, &column_excess) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&plane_excess, &squares, &plane_excess) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&plane_excess, &row_excess, &plane_excess) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&plane_excess, &column_excess, &plane_excess) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&plane_pairs, &row_pairs, &plane_pairs) == ANCHOR_EXACT_OK)
            && (anchor_exact_subtract(&plane_pairs, &column_pairs, &plane_pairs) == ANCHOR_EXACT_OK);
    // var_plane L, then A_row M K_column D_plane and A_column M K_row D_plane, then s L and L
    AnchorExactInteger plane_part;
    AnchorExactInteger row_part;
    AnchorExactInteger column_part;
    AnchorExactInteger independent;
    AnchorExactInteger common;
    good = good && (anchor_exact_multiply(&plane_excess, &members, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&plane_part, &row_pairs, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&plane_part, &column_pairs, &plane_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&row_excess, &members, &row_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&row_part, &column_pairs, &row_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&row_part, &plane_pairs, &row_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&column_excess, &members, &column_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&column_part, &row_pairs, &column_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&column_part, &plane_pairs, &column_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&row_pairs, &column_pairs, &common) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&common, &plane_pairs, &common) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&common, &squares, &independent) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&independent, &row_part, &independent) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&independent, &column_part, &independent) == ANCHOR_EXACT_OK)
        && (anchor_exact_add(&independent, &plane_part, &independent) == ANCHOR_EXACT_OK)
        && (anchor_exact_multiply(&common, &members, &common) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&row_part, &plane_part, &row_part) == ANCHOR_EXACT_OK)
        && (anchor_exact_subtract(&column_part, &plane_part, &column_part) == ANCHOR_EXACT_OK);
    const AnchorExactInteger *const numerators[NOISE_STATIC_READINGS] = {&row_part, &column_part, &plane_part,
                                                                         &independent};
    const AnchorExactInteger *const denominators[NOISE_STATIC_READINGS] = {&independent, &independent, &independent,
                                                                           &common};
    for (unsigned int reading = 0u; reading < NOISE_STATIC_READINGS; reading += 1u)
    {
        readings[reading] = 0ll;
        held[reading] = good && noise_exact_ratio(numerators[reading], denominators[reading], 1000ull,
                                                  &readings[reading]);
    }
}

static void noise_static_summary(const NoiseStaticPool *still)
{
    long long readings[NOISE_STATIC_READINGS];
    int held[NOISE_STATIC_READINGS];
    noise_static_readings(still, readings, held);
    const char *const said[NOISE_STATIC_READINGS] = {"rows", "columns", "plane", "independent"};
    printf("  %-24s static, means up to %llu, %llu voxel-frame pairs:", "", still->ceiling, still->members);
    for (unsigned int reading = 0u; reading < NOISE_STATIC_READINGS; reading += 1u)
    {
        if (held[reading] != 0)
        {
            printf(" %s %lld", said[reading], readings[reading]);
        }
        else
        {
            printf(" %s -", said[reading]);
        }
    }
    printf("\n");
    fflush(stdout);
}

static int noise_lines_rows(FILE *table, const char *name, const NoiseLineCell cells[NOISE_LINE_CELLS])
{
    int good = 1;
    for (unsigned int kind = 0u; good && (kind < NOISE_LINE_KINDS); kind += 1u)
    {
        for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const NoiseLineCell *const cell = &cells[(kind * NOISE_LEVEL_BINS) + level_bin];
            if (cell->lines == 0ull)
            {
                continue;
            }
            good = fprintf(table, "%s\t%s\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, NOISE_LINE_NAMES[kind],
                           level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u), cell->lines, cell->members, cell->member_squares,
                           cell->line_squares.high, cell->line_squares.low)
                 > 0;
        }
    }
    return good;
}

extern "C" long noise_lines_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_ROOM];
    const int written = (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_lines.tsv", request->set)
                                               : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    char plane_path[ENGINE_PATH_ROOM];
    const int plane_written = (request->set != NULL)
                                ? snprintf(plane_path, sizeof(plane_path), "%s/noise_planes.tsv", request->set)
                                : -1;
    const int plane_named = (plane_written > 0) && ((size_t)plane_written < sizeof(plane_path));
    FILE *const plane_table = plane_named ? fopen(plane_path, "wb") : NULL;
    int good = NOISE_DETECTOR_HELD(named && plane_named && (request->samples != NULL) && (request->load != NULL),
                                   request, error, ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_IO(table != NULL, path, error)
            && NOISE_DETECTOR_IO(fprintf(table, "sample\tline\tlowest_mean\tlines\tmembers\tmember_squares"
                                                "\tline_squares_high\tline_squares_low\n")
                                     > 0,
                                 table, error)
            && NOISE_DETECTOR_IO(plane_table != NULL, plane_path, error)
            && NOISE_DETECTOR_IO(fprintf(plane_table, "sample\tframe\tz\tmembers\tlevel\tplane_sum\tplane_squares"
                                                      "\trow_squares\tcolumn_squares\tstatic_members\tstatic_sum"
                                                      "\tstatic_squares\tstatic_level\n")
                                     > 0,
                                 plane_table, error);
    printf("  lines: each frame difference summed along a row (x), a column (y) and a whole z plane, the sum squared,"
           " in bins of 8 by the line's mean\n");
    printf("  the lines' squared sums against their members' squares summed, per mille, means 40 to 199 (independent"
           " noise holds 1000; an offset shared along the line raises it):\n");
    printf("  then every plane as a two-way layout, rows by columns: rows 1 + W var_row / s, columns 1 + H var_col / s"
           " and the plane 1 + N var_plane / s, per mille (1000 where nothing is shared), and s, the independent"
           " variance of a voxel's frame difference, in lane units squared\n");
    printf("  then the static voxels alone (the dimmest quarter by mean of those that change, never touch either end"
           " of the lane, and hold a mean square frame difference within 4 times their mean plus 32) as an unbalanced"
           " layout: var_row, var_col and var_plane against s, per mille (0 where nothing is shared), and s in"
           " thousandths of a lane unit squared\n");
    printf("  %-24s %9s %9s %9s\n", "", "rows", "columns", "planes");
    NoiseLineCell *const cells = (NoiseLineCell *)malloc((size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    good = good && NOISE_DETECTOR_HELD(cells != NULL, &cells, error, ENGINE_ERROR_RESOURCE);
    // four exact integers, held apart from the stack
    NoisePlanePool *const pool = (NoisePlanePool *)malloc(sizeof(NoisePlanePool));
    good = good && NOISE_DETECTOR_HELD(pool != NULL, &pool, error, ENGINE_ERROR_RESOURCE);
    NoiseStaticPool still;
    memset(&still, 0, sizeof(still));
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST)
            && (noise_lines_sample(volume, extent, cells, pool, &still, plane_table, name, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_lines_rows(table, name, cells) != 0, table, error);
        if (good != 0)
        {
            noise_lines_summary(name, cells);
            noise_planes_summary(pool);
            noise_static_summary(&still);
        }
    }
    free(cells);
    free(pool);
    if (table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && good;
    }
    if (plane_table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(plane_table) == 0, plane_path, error) && good;
    }
    if (good != 0)
    {
        printf("  lines: %u samples in %llu ms; every sum is in %s, and every plane's in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path, plane_path);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

#define NOISE_NEIGHBOURS_CELLS (NOISE_NEIGHBOUR_REACHES * NOISE_LEVEL_BINS * NOISE_NEIGHBOURS_SUMS)

static_assert((NOISE_NEIGHBOURS_CELLS * sizeof(unsigned long long)) <= 49152u,
              "noise_detector: the neighbour sums fit one block's shared memory");

static_assert(NOISE_NEIGHBOUR_REACHES == (ENGINE_AXES + 5u),
              "noise_detector: the reaches are one voxel along each axis, then 2 to 32 planes along z");

static const char *const NOISE_REACH_NAMES[NOISE_NEIGHBOUR_REACHES] = {"z", "y", "x", "z2", "z4", "z8", "z16", "z32"};

// the summary's level bins: means 24, 40, 72, 104 and 200, where compression_table.md reads its correlations
#define NOISE_NEIGHBOURS_SHOWN 5u

static const unsigned int NOISE_NEIGHBOURS_SHOWN_BINS[NOISE_NEIGHBOURS_SHOWN] = {3u, 5u, 9u, 13u, 25u};

__device__ static void noise_neighbours_flush(unsigned long long *cells, unsigned int reach, unsigned int level_bin,
                                              unsigned long long run[NOISE_NEIGHBOURS_SUMS])
{
    unsigned long long *const cell = &cells[((reach * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBOURS_SUMS];
    for (unsigned int sum = 0u; sum < NOISE_NEIGHBOURS_SUMS; sum += 1u)
    {
        if (run[sum] != 0ull)
        {
            atomicAdd(&cell[sum], run[sum]);
        }
        run[sum] = 0ull;
    }
}

// One thread a voxel. At each reach whose voxel is inside the view, every frame pair's difference is multiplied by
// that voxel's, the product's sign kept by summing the raised and lowered products apart.
__global__ static void noise_neighbours_kernel(const unsigned short *lanes, unsigned long long frames,
                                               unsigned long long depth, unsigned long long height,
                                               unsigned long long width, unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_NEIGHBOURS_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_NEIGHBOURS_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long voxels = depth * height * width;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        const unsigned long long place[ENGINE_AXES] = {voxel / (height * width), (voxel / width) % height,
                                                       voxel % width};
        const unsigned long long extent[ENGINE_AXES] = {depth, height, width};
        const unsigned long long stride[ENGINE_AXES] = {height * width, width, 1ull};
        for (unsigned int reach = 0u; reach < NOISE_NEIGHBOUR_REACHES; reach += 1u)
        {
            // one voxel along each axis, then 2^(reach - 2) planes along z
            const unsigned int axis = (reach < ENGINE_AXES) ? reach : 0u;
            const unsigned long long apart = (reach < ENGINE_AXES) ? 1ull : (1ull << (reach - 2u));
            if ((place[axis] + apart) >= extent[axis])
            {
                continue;
            }
            const unsigned long long next = voxel + (apart * stride[axis]);
            unsigned long long run[NOISE_NEIGHBOURS_SUMS] = {0ull, 0ull, 0ull, 0ull, 0ull};
            unsigned int held_bin = 0u;
            for (unsigned long long frame = 0ull; (frame + 1ull) < frames; frame += 1ull)
            {
                const unsigned int before = lanes[(frame * voxels) + voxel];
                const unsigned int after = lanes[((frame + 1ull) * voxels) + voxel];
                const unsigned int summed_bin = (before + after) >> NOISE_LEVEL_BIN_SHIFT;
                const unsigned int level_bin = (summed_bin < NOISE_LEVEL_BINS) ? summed_bin : (NOISE_LEVEL_BINS - 1u);
                if ((level_bin != held_bin) && (run[NOISE_NEIGHBOURS_PAIRS] != 0ull))
                {
                    noise_neighbours_flush(cells, reach, held_bin, run);
                }
                held_bin = level_bin;
                const long long moved = (long long)after - (long long)before;
                const long long next_moved = (long long)lanes[((frame + 1ull) * voxels) + next]
                                           - (long long)lanes[(frame * voxels) + next];
                const long long product = moved * next_moved;
                run[NOISE_NEIGHBOURS_PAIRS] += 1ull;
                // a square is never negative, and a product's magnitude re-signs to unsigned long long exactly
                run[NOISE_NEIGHBOURS_SQUARES] += (unsigned long long)(moved * moved);
                run[NOISE_NEIGHBOURS_OTHER_SQUARES] += (unsigned long long)(next_moved * next_moved);
                run[NOISE_NEIGHBOURS_RAISED] += (product > 0ll) ? (unsigned long long)product : 0ull;
                run[NOISE_NEIGHBOURS_LOWERED] += (product < 0ll) ? (unsigned long long)(-product) : 0ull;
            }
            if (run[NOISE_NEIGHBOURS_PAIRS] != 0ull)
            {
                noise_neighbours_flush(cells, reach, held_bin, run);
            }
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_NEIGHBOURS_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

static long noise_neighbours_sample(const unsigned short *volume, const unsigned long long extent[4],
                                    unsigned long long sums[NOISE_NEIGHBOURS_CELLS], EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    // every sum is at most one sample's pairs times the widest product, 65535 squared
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels))
                     && ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_NEIGHBOURS_CELLS * sizeof(unsigned long long);
    unsigned short *device_lanes = NULL;
    unsigned long long *device_sums = NULL;
    int good = NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_sums, sum_bytes), &device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_sums, 0, sum_bytes), device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice), device_lanes,
                                   error);
    if (good != 0)
    {
        const unsigned long long needed = (voxels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_neighbours_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, extent[1], extent[2],
                                                                     extent[3], device_sums);
        good = NOISE_DETECTOR_TOOK(cudaGetLastError(), device_sums, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

// Σ d d' against the mean of Σ d² and Σ d'², in signed thousandths rounded toward zero: 2000 (raised - lowered) /
// (squares + other squares). For equal spreads it is the correlation. 0 where nothing was summed.
static int noise_neighbours_per_mille(const unsigned long long cell[NOISE_NEIGHBOURS_SUMS], long long *per_mille)
{
    if ((cell[NOISE_NEIGHBOURS_SQUARES] == 0ull) && (cell[NOISE_NEIGHBOURS_OTHER_SQUARES] == 0ull))
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger part;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&numerator, cell[NOISE_NEIGHBOURS_RAISED]);
    noise_exact_word(&part, cell[NOISE_NEIGHBOURS_LOWERED]);
    int good = anchor_exact_subtract(&numerator, &part, &numerator) == ANCHOR_EXACT_OK;
    noise_exact_word(&part, 2000ull);
    good = good && (anchor_exact_multiply(&numerator, &part, &numerator) == ANCHOR_EXACT_OK);
    noise_exact_word(&denominator, cell[NOISE_NEIGHBOURS_SQUARES]);
    noise_exact_word(&part, cell[NOISE_NEIGHBOURS_OTHER_SQUARES]);
    good = good && (anchor_exact_add(&denominator, &part, &denominator) == ANCHOR_EXACT_OK)
        && (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 1u; good && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        good = quotient.limb[limb] == 0u;
    }
    // the magnitude is at most 2000, one limb; the sign is held apart
    *per_mille = good ? ((long long)quotient.limb[0] * (long long)quotient.sign) : 0ll;
    return good;
}

static void noise_neighbours_summary(const char *name, const unsigned long long sums[NOISE_NEIGHBOURS_CELLS])
{
    for (unsigned int reach = 0u; reach < NOISE_NEIGHBOUR_REACHES; reach += 1u)
    {
        if (reach == 0u)
        {
            printf("  %-24s %-3s", name, NOISE_REACH_NAMES[reach]);
        }
        else
        {
            printf("  %-24s %-3s", "", NOISE_REACH_NAMES[reach]);
        }
        for (unsigned int shown = 0u; shown < NOISE_NEIGHBOURS_SHOWN; shown += 1u)
        {
            const unsigned int level_bin = NOISE_NEIGHBOURS_SHOWN_BINS[shown];
            long long per_mille = 0ll;
            if (noise_neighbours_per_mille(&sums[((reach * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBOURS_SUMS],
                                           &per_mille))
            {
                printf(" %7lld", per_mille);
            }
            else
            {
                printf(" %7s", "-");
            }
        }
        printf("\n");
    }
    fflush(stdout);
}

static int noise_neighbours_rows(FILE *table, const char *name, const unsigned long long sums[NOISE_NEIGHBOURS_CELLS])
{
    int good = 1;
    for (unsigned int reach = 0u; good && (reach < NOISE_NEIGHBOUR_REACHES); reach += 1u)
    {
        for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const unsigned long long *const cell = &sums[((reach * NOISE_LEVEL_BINS) + level_bin)
                                                         * NOISE_NEIGHBOURS_SUMS];
            if (cell[NOISE_NEIGHBOURS_PAIRS] == 0ull)
            {
                continue;
            }
            good = fprintf(table, "%s\t%s\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, NOISE_REACH_NAMES[reach],
                           level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u), cell[NOISE_NEIGHBOURS_PAIRS],
                           cell[NOISE_NEIGHBOURS_SQUARES], cell[NOISE_NEIGHBOURS_OTHER_SQUARES],
                           cell[NOISE_NEIGHBOURS_RAISED], cell[NOISE_NEIGHBOURS_LOWERED])
                 > 0;
        }
    }
    return good;
}

extern "C" long noise_neighbours_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_ROOM];
    const int written = (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_neighbours.tsv", request->set)
                                               : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    int good = NOISE_DETECTOR_HELD(named && (request->samples != NULL) && (request->load != NULL), request, error,
                                   ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_IO(table != NULL, path, error)
            && NOISE_DETECTOR_IO(fprintf(table, "sample\taxis\tlowest_mean\tpairs\tsquares\tnext_squares\traised"
                                                "\tlowered\n")
                                     > 0,
                                 table, error);
    printf("  neighbours: each frame difference times the next voxel's along z, y and x, and the voxel's 2 to 32 planes"
           " on along z (z2 to z32), in bins of 8 by the pair's mean\n");
    printf("  2000 (raised - lowered) / (squares + next squares), signed per mille (independent noise holds 0):\n");
    printf("  %-24s  ", "mean");
    for (unsigned int shown = 0u; shown < NOISE_NEIGHBOURS_SHOWN; shown += 1u)
    {
        printf(" %7u", NOISE_NEIGHBOURS_SHOWN_BINS[shown] << (NOISE_LEVEL_BIN_SHIFT - 1u));
    }
    printf("\n");
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)NOISE_NEIGHBOURS_CELLS
                                                                  * sizeof(unsigned long long));
    good = good && NOISE_DETECTOR_HELD(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST)
            && (noise_neighbours_sample(volume, extent, sums, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_neighbours_rows(table, name, sums) != 0, table, error);
        if (good != 0)
        {
            noise_neighbours_summary(name, sums);
        }
    }
    free(sums);
    if (table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && good;
    }
    if (good != 0)
    {
        printf("  neighbours: %u samples in %llu ms; every sum is in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

#define NOISE_SPIKE_CELLS (NOISE_LEVEL_BINS * NOISE_SPIKE_SUMS)

// values below this are counted in the block's shared memory first; the rest go to the sample's counts directly
#define NOISE_SHARED_VALUES 8192u

static_assert(((NOISE_SPIKE_CELLS * sizeof(unsigned long long)) + (NOISE_SHARED_VALUES * sizeof(unsigned int)))
                  <= 49152u,
              "noise_detector: the spike sums and the shared value counts fit one block's shared memory");

static_assert((NOISE_SPIKE_LEAST << (NOISE_SPIKE_THRESHOLDS - 1u)) == 128u,
              "noise_detector: the spike thresholds are 16, 32, 64 and 128, as the spike table's header names them");

// the clip pass writes three tables
#define NOISE_TABLE_CLIPS 0u

#define NOISE_TABLE_VALUES 1u

#define NOISE_TABLE_SPIKES 2u

#define NOISE_CLIPS_TABLES 3u

typedef struct
{
    unsigned long long counts[NOISE_CLIPS_COUNTS];
    unsigned int box[NOISE_CLIPS_BOX];
    unsigned long long values[NOISE_VALUES];
    unsigned long long constant_values[NOISE_VALUES];
    unsigned long long spikes[NOISE_SPIKE_CELLS];
} NoiseClips;

__device__ static void noise_spikes_flush(unsigned long long *cells, unsigned int level_bin,
                                          unsigned long long run[NOISE_SPIKE_SUMS])
{
    unsigned long long *const cell = &cells[level_bin * NOISE_SPIKE_SUMS];
    for (unsigned int sum = 0u; sum < NOISE_SPIKE_SUMS; sum += 1u)
    {
        if (run[sum] != 0ull)
        {
            atomicAdd(&cell[sum], run[sum]);
        }
        run[sum] = 0ull;
    }
}

// One thread a voxel. Every frame's value is counted. A frame with a frame on either side is a triple, binned by the
// mean of the two beside it, and a spike or a dip where it clears both by a threshold. A voxel whose least and most
// values agree is constant: counted, its value counted apart, and its place taken into the box.
__global__ static void noise_clips_kernel(const unsigned short *lanes, unsigned long long frames,
                                          unsigned long long depth, unsigned long long height,
                                          unsigned long long width, unsigned long long *counts, unsigned int *box,
                                          unsigned long long *values, unsigned long long *constant_values,
                                          unsigned long long *spikes)
{
    __shared__ unsigned long long cells[NOISE_SPIKE_CELLS];
    __shared__ unsigned int shared_values[NOISE_SHARED_VALUES];
    for (unsigned int entry = threadIdx.x; entry < NOISE_SPIKE_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    for (unsigned int entry = threadIdx.x; entry < NOISE_SHARED_VALUES; entry += blockDim.x)
    {
        shared_values[entry] = 0u;
    }
    __syncthreads();
    const unsigned long long voxels = depth * height * width;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    unsigned long long at_zero = 0ull;
    unsigned long long at_top = 0ull;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        unsigned int least = NOISE_LANE_TOP;
        unsigned int most = 0u;
        unsigned long long run[NOISE_SPIKE_SUMS];
        for (unsigned int sum = 0u; sum < NOISE_SPIKE_SUMS; sum += 1u)
        {
            run[sum] = 0ull;
        }
        unsigned int held_bin = 0u;
        unsigned int earlier = 0u;
        unsigned int middle = 0u;
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            const unsigned int value = lanes[(frame * voxels) + voxel];
            least = (value < least) ? value : least;
            most = (value > most) ? value : most;
            at_zero += (value == 0u) ? 1ull : 0ull;
            at_top += (value == NOISE_LANE_TOP) ? 1ull : 0ull;
            if (value < NOISE_SHARED_VALUES)
            {
                atomicAdd(&shared_values[value], 1u);
            }
            else
            {
                atomicAdd(&values[value], 1ull);
            }
            if (frame >= 2ull)
            {
                // the middle frame against the frames either side of it, binned by their mean
                const unsigned int summed_bin = (earlier + value) >> NOISE_LEVEL_BIN_SHIFT;
                const unsigned int level_bin = (summed_bin < NOISE_LEVEL_BINS) ? summed_bin : (NOISE_LEVEL_BINS - 1u);
                if ((level_bin != held_bin) && (run[NOISE_SPIKE_TRIPLES] != 0ull))
                {
                    noise_spikes_flush(cells, held_bin, run);
                }
                held_bin = level_bin;
                const unsigned int higher = (earlier > value) ? earlier : value;
                const unsigned int lower = (earlier < value) ? earlier : value;
                run[NOISE_SPIKE_TRIPLES] += 1ull;
                for (unsigned int threshold = 0u; threshold < NOISE_SPIKE_THRESHOLDS; threshold += 1u)
                {
                    const unsigned int apart = NOISE_SPIKE_LEAST << threshold;
                    run[1u + (2u * threshold)] += (middle >= (higher + apart)) ? 1ull : 0ull;
                    run[2u + (2u * threshold)] += ((middle + apart) <= lower) ? 1ull : 0ull;
                }
            }
            earlier = middle;
            middle = value;
        }
        if (run[NOISE_SPIKE_TRIPLES] != 0ull)
        {
            noise_spikes_flush(cells, held_bin, run);
        }
        if (least != most)
        {
            continue;
        }
        atomicAdd(&counts[NOISE_CLIPS_CONSTANT], 1ull);
        if (least == 0u)
        {
            atomicAdd(&counts[NOISE_CLIPS_CONSTANT_ZERO], 1ull);
        }
        if (least == NOISE_LANE_TOP)
        {
            atomicAdd(&counts[NOISE_CLIPS_CONSTANT_TOP], 1ull);
        }
        atomicAdd(&constant_values[least], 1ull);
        // each coordinate is below its extent, which the host holds under 2^32
        const unsigned int place[ENGINE_AXES] = {(unsigned int)(voxel / (height * width)),
                                                 (unsigned int)((voxel / width) % height),
                                                 (unsigned int)(voxel % width)};
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            atomicMin(&box[2u * axis], place[axis]);
            atomicMax(&box[(2u * axis) + 1u], place[axis]);
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_SPIKE_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&spikes[entry], cells[entry]);
        }
    }
    for (unsigned int entry = threadIdx.x; entry < NOISE_SHARED_VALUES; entry += blockDim.x)
    {
        if (shared_values[entry] != 0u)
        {
            atomicAdd(&values[entry], (unsigned long long)shared_values[entry]);
        }
    }
    if (at_zero != 0ull)
    {
        atomicAdd(&counts[NOISE_CLIPS_AT_ZERO], at_zero);
    }
    if (at_top != 0ull)
    {
        atomicAdd(&counts[NOISE_CLIPS_AT_TOP], at_top);
    }
}

static long noise_clips_sample(const unsigned short *volume, const unsigned long long extent[4], NoiseClips *clips,
                               EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long height = extent[2];
    const unsigned long long width = extent[3];
    const unsigned long long voxels = depth * height * width;
    const unsigned long long needed = (voxels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
    const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
    // the voxels each thread takes in turn
    const unsigned long long rounds = (blocks != 0u) ? ((needed + blocks - 1ull) / blocks) : 0ull;
    // every count is at most the sample's voxel-frames; a block's shared counts are at most its threads' voxel-frames,
    // which an unsigned int holds; every coordinate fits an unsigned int
    const int bounded = (frames >= 1ull) && (voxels != 0ull) && (frames <= (~0ull / voxels))
                     && (depth <= 0xFFFFFFFFull) && (height <= 0xFFFFFFFFull) && (width <= 0xFFFFFFFFull)
                     && (rounds <= ((0xFFFFFFFFull / NOISE_DETECTOR_THREADS) / frames));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t count_bytes = (size_t)NOISE_CLIPS_COUNTS * sizeof(unsigned long long);
    const size_t box_bytes = (size_t)NOISE_CLIPS_BOX * sizeof(unsigned int);
    const size_t value_bytes = (size_t)NOISE_VALUES * sizeof(unsigned long long);
    const size_t spike_bytes = (size_t)NOISE_SPIKE_CELLS * sizeof(unsigned long long);
    // an empty box: every least at the widest coordinate and every most at 0
    const unsigned int empty_box[NOISE_CLIPS_BOX] = {0xFFFFFFFFu, 0u, 0xFFFFFFFFu, 0u, 0xFFFFFFFFu, 0u};
    unsigned short *device_lanes = NULL;
    unsigned long long *device_counts = NULL;
    unsigned int *device_box = NULL;
    unsigned long long *device_values = NULL;
    unsigned long long *device_constant_values = NULL;
    unsigned long long *device_spikes = NULL;
    int good = NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_counts, count_bytes), &device_counts, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_box, box_bytes), &device_box, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_values, value_bytes), &device_values, error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_constant_values, value_bytes), &device_constant_values,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMalloc((void **)&device_spikes, spike_bytes), &device_spikes, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_counts, 0, count_bytes), device_counts, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_values, 0, value_bytes), device_values, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_constant_values, 0, value_bytes), device_constant_values, error)
            && NOISE_DETECTOR_TOOK(cudaMemset(device_spikes, 0, spike_bytes), device_spikes, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_box, empty_box, box_bytes, cudaMemcpyHostToDevice), device_box,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice), device_lanes,
                                   error);
    if (good != 0)
    {
        noise_clips_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, depth, height, width,
                                                                device_counts, device_box, device_values,
                                                                device_constant_values, device_spikes);
        good = NOISE_DETECTOR_TOOK(cudaGetLastError(), device_counts, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(clips->counts, device_counts, count_bytes, cudaMemcpyDeviceToHost),
                                   clips->counts, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(clips->box, device_box, box_bytes, cudaMemcpyDeviceToHost), clips->box,
                                   error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(clips->values, device_values, value_bytes, cudaMemcpyDeviceToHost),
                                   clips->values, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(clips->constant_values, device_constant_values, value_bytes,
                                              cudaMemcpyDeviceToHost),
                                   clips->constant_values, error)
            && NOISE_DETECTOR_TOOK(cudaMemcpy(clips->spikes, device_spikes, spike_bytes, cudaMemcpyDeviceToHost),
                                   clips->spikes, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_counts);
    cudaFree(device_box);
    cudaFree(device_values);
    cudaFree(device_constant_values);
    cudaFree(device_spikes);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

// the least and most values the sample holds, and how many values between them it never holds
static void noise_clips_range(const NoiseClips *clips, unsigned int *least, unsigned int *most,
                              unsigned long long *empty)
{
    int found = 0;
    *least = 0u;
    *most = 0u;
    for (unsigned int value = 0u; value < NOISE_VALUES; value += 1u)
    {
        if (clips->values[value] == 0ull)
        {
            continue;
        }
        *least = (found != 0) ? *least : value;
        *most = value;
        found = 1;
    }
    *empty = 0ull;
    for (unsigned int value = *least; (found != 0) && (value <= *most); value += 1u)
    {
        *empty += (clips->values[value] == 0ull) ? 1ull : 0ull;
    }
}

// the triples, spikes and dips pooled over the summary's level bins, means 40 to 199
static void noise_spikes_pooled(const NoiseClips *clips, unsigned long long pooled[NOISE_SPIKE_SUMS])
{
    memset(pooled, 0, (size_t)NOISE_SPIKE_SUMS * sizeof(unsigned long long));
    for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
    {
        for (unsigned int sum = 0u; sum < NOISE_SPIKE_SUMS; sum += 1u)
        {
            pooled[sum] += clips->spikes[(level_bin * NOISE_SPIKE_SUMS) + sum];
        }
    }
}

static void noise_clips_summary(const char *name, const NoiseClips *clips)
{
    unsigned int least = 0u;
    unsigned int most = 0u;
    unsigned long long empty = 0ull;
    noise_clips_range(clips, &least, &most, &empty);
    printf("  %-24s values %u to %u, %llu never held between; at 0: %llu, at the top: %llu; constant voxels: %llu"
           " (at 0: %llu, at the top: %llu)",
           name, least, most, empty, clips->counts[NOISE_CLIPS_AT_ZERO], clips->counts[NOISE_CLIPS_AT_TOP],
           clips->counts[NOISE_CLIPS_CONSTANT], clips->counts[NOISE_CLIPS_CONSTANT_ZERO],
           clips->counts[NOISE_CLIPS_CONSTANT_TOP]);
    if (clips->counts[NOISE_CLIPS_CONSTANT] != 0ull)
    {
        printf(", within z %u to %u, y %u to %u, x %u to %u", clips->box[0], clips->box[1], clips->box[2],
               clips->box[3], clips->box[4], clips->box[5]);
    }
    printf("\n");
    unsigned long long pooled[NOISE_SPIKE_SUMS];
    noise_spikes_pooled(clips, pooled);
    printf("  %-24s %llu triples at means 40 to 199; spikes against dips at", "", pooled[NOISE_SPIKE_TRIPLES]);
    for (unsigned int threshold = 0u; threshold < NOISE_SPIKE_THRESHOLDS; threshold += 1u)
    {
        printf(" %u: %llu, %llu;", NOISE_SPIKE_LEAST << threshold, pooled[1u + (2u * threshold)],
               pooled[2u + (2u * threshold)]);
    }
    printf("\n");
    fflush(stdout);
}

static int noise_clips_rows(FILE *const tables[NOISE_CLIPS_TABLES], const char *name, const NoiseClips *clips)
{
    unsigned int least = 0u;
    unsigned int most = 0u;
    unsigned long long empty = 0ull;
    noise_clips_range(clips, &least, &most, &empty);
    int good = fprintf(tables[NOISE_TABLE_CLIPS],
                       "%s\t%u\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%u\t%u\t%u\t%u\t%u\t%u\n", name, least, most,
                       empty, clips->counts[NOISE_CLIPS_AT_ZERO], clips->counts[NOISE_CLIPS_AT_TOP],
                       clips->counts[NOISE_CLIPS_CONSTANT], clips->counts[NOISE_CLIPS_CONSTANT_ZERO],
                       clips->counts[NOISE_CLIPS_CONSTANT_TOP], clips->box[0], clips->box[1], clips->box[2],
                       clips->box[3], clips->box[4], clips->box[5])
             > 0;
    for (unsigned int value = 0u; good && (value < NOISE_VALUES); value += 1u)
    {
        if (clips->values[value] == 0ull)
        {
            continue;
        }
        good = fprintf(tables[NOISE_TABLE_VALUES], "%s\t%u\t%llu\t%llu\n", name, value, clips->values[value],
                       clips->constant_values[value])
             > 0;
    }
    for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
    {
        const unsigned long long *const cell = &clips->spikes[level_bin * NOISE_SPIKE_SUMS];
        if (cell[NOISE_SPIKE_TRIPLES] == 0ull)
        {
            continue;
        }
        good = fprintf(tables[NOISE_TABLE_SPIKES], "%s\t%u\t%llu", name, level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u),
                       cell[NOISE_SPIKE_TRIPLES])
             > 0;
        for (unsigned int sum = 1u; good && (sum < NOISE_SPIKE_SUMS); sum += 1u)
        {
            good = fprintf(tables[NOISE_TABLE_SPIKES], "\t%llu", cell[sum]) > 0;
        }
        good = good && (fprintf(tables[NOISE_TABLE_SPIKES], "\n") > 0);
    }
    return good;
}

// opens <set>/<file> for writing and writes its header
static int noise_table_open(const char *set, const char *file, const char *header, char path[ENGINE_PATH_ROOM],
                            FILE **table, EngineError *error)
{
    const int written = snprintf(path, ENGINE_PATH_ROOM, "%s/%s", set, file);
    const int named = (written > 0) && ((size_t)written < ENGINE_PATH_ROOM);
    *table = named ? fopen(path, "wb") : NULL;
    return NOISE_DETECTOR_HELD(named, set, error, ENGINE_ERROR_REQUEST)
        && NOISE_DETECTOR_IO(*table != NULL, path, error)
        && NOISE_DETECTOR_IO(fputs(header, *table) >= 0, *table, error);
}

extern "C" long noise_clips_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    static const char *const files[NOISE_CLIPS_TABLES] = {"noise_clips.tsv", "noise_values.tsv", "noise_spikes.tsv"};
    static const char *const headers[NOISE_CLIPS_TABLES] = {
        "sample\tleast\tmost\tnever_held_between\tat_zero\tat_top\tconstant\tconstant_zero\tconstant_top\tz_least"
        "\tz_most\ty_least\ty_most\tx_least\tx_most\n",
        "sample\tvalue\tcount\tconstant_voxels\n",
        "sample\tlowest_mean\ttriples\tspikes_16\tdips_16\tspikes_32\tdips_32\tspikes_64\tdips_64\tspikes_128"
        "\tdips_128\n"};
    char paths[NOISE_CLIPS_TABLES][ENGINE_PATH_ROOM];
    FILE *tables[NOISE_CLIPS_TABLES] = {NULL, NULL, NULL};
    int good = NOISE_DETECTOR_HELD((request->set != NULL) && (request->samples != NULL) && (request->load != NULL),
                                   request, error, ENGINE_ERROR_REQUEST);
    for (unsigned int kind = 0u; good && (kind < NOISE_CLIPS_TABLES); kind += 1u)
    {
        good = noise_table_open(request->set, files[kind], headers[kind], paths[kind], &tables[kind], error);
    }
    printf("  clips: every value counted; the voxel-frames at 0 and at the lane's top, 65535; the voxels whose every"
           " frame holds one value, and the box they sit in\n");
    printf("  and each frame against the frames beside it: a spike clears both from above by 16, 32, 64 or 128, a dip"
           " from below (symmetric noise holds them equal)\n");
    NoiseClips *const clips = (NoiseClips *)malloc(sizeof(NoiseClips));
    good = good && NOISE_DETECTOR_HELD(clips != NULL, &clips, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST)
            && (noise_clips_sample(volume, extent, clips, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_clips_rows(tables, name, clips) != 0, tables[NOISE_TABLE_CLIPS], error);
        if (good != 0)
        {
            noise_clips_summary(name, clips);
        }
    }
    free(clips);
    for (unsigned int kind = 0u; kind < NOISE_CLIPS_TABLES; kind += 1u)
    {
        if (tables[kind] != NULL)
        {
            good = NOISE_DETECTOR_IO(fclose(tables[kind]) == 0, paths[kind], error) && good;
        }
    }
    if (good != 0)
    {
        printf("  clips: %u samples in %llu ms; the counts are in %s, %s and %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, paths[NOISE_TABLE_CLIPS], paths[NOISE_TABLE_VALUES],
               paths[NOISE_TABLE_SPIKES]);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

// the pixel maps' halves: the z planes below the middle, then those from it up
#define NOISE_PIXEL_HALVES 2u

// each pixel and half holds its static voxels, their values summed over the frames, and their frame differences
// squared and summed
#define NOISE_PIXEL_VOXELS 0u

#define NOISE_PIXEL_VALUES 1u

#define NOISE_PIXEL_SQUARES 2u

#define NOISE_PIXEL_SUMS 3u

#define NOISE_PIXEL_CELLS(plane_voxels_) ((plane_voxels_) * NOISE_PIXEL_HALVES * NOISE_PIXEL_SUMS)

// Every camera pixel's static voxels in each half of the z planes: counted, their values summed over the frames, and
// their frame differences squared and summed. A voxel's pixel is its (y, x); every z plane of a light sheet stack is
// one exposure of the same pixels, so a fixed pattern, a hot pixel or a dust shadow repeats in both halves, and the
// cells, which differ between the halves, do not.
static long noise_pixels_sample(const unsigned short *volume, const unsigned long long extent[4],
                                unsigned long long *maps, unsigned long long *ceiling, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long plane_voxels = extent[2] * extent[3];
    const unsigned long long voxels = depth * plane_voxels;
    // a pixel's squares total at most the sample's voxel-frames times 65535 squared
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels))
                     && ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    int good = NOISE_DETECTOR_HELD(mask != NULL, &mask, error, ENGINE_ERROR_RESOURCE)
            && NOISE_DETECTOR_HELD(noise_static_mask(volume, frames, voxels, 0u, mask, ceiling) != 0, mask, error,
                                   ENGINE_ERROR_RESOURCE);
    if (good != 0)
    {
        memset(maps, 0, (size_t)NOISE_PIXEL_CELLS(plane_voxels) * sizeof(unsigned long long));
        const unsigned long long middle = depth / 2ull;
        // frame by frame and plane by plane, so the volume is read in order; the first frame also counts the voxels
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            for (unsigned long long z = 0ull; z < depth; z += 1ull)
            {
                const unsigned long long half = (z < middle) ? 0ull : 1ull;
                const unsigned char *const kept = &mask[z * plane_voxels];
                const unsigned short *const lanes = &volume[(frame * voxels) + (z * plane_voxels)];
                // the same plane one frame earlier; the first frame has none and reads itself
                const unsigned short *const earlier = (frame != 0ull)
                                                        ? &volume[((frame - 1ull) * voxels) + (z * plane_voxels)]
                                                        : lanes;
                for (unsigned long long pixel = 0ull; pixel < plane_voxels; pixel += 1ull)
                {
                    if (kept[pixel] == 0u)
                    {
                        continue;
                    }
                    unsigned long long *const cell = &maps[((pixel * NOISE_PIXEL_HALVES) + half) * NOISE_PIXEL_SUMS];
                    cell[NOISE_PIXEL_VOXELS] += (frame == 0ull) ? 1ull : 0ull;
                    cell[NOISE_PIXEL_VALUES] += lanes[pixel];
                    if (frame != 0ull)
                    {
                        const long long moved = (long long)lanes[pixel] - (long long)earlier[pixel];
                        // a square is never negative, so it re-signs to unsigned long long exactly
                        cell[NOISE_PIXEL_SQUARES] += (unsigned long long)(moved * moved);
                    }
                }
            }
        }
    }
    free(mask);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static int noise_pixels_rows(FILE *table, const char *name, const unsigned long long extent[4],
                             const unsigned long long *maps)
{
    const unsigned long long width = extent[3];
    const unsigned long long plane_voxels = extent[2] * width;
    int good = 1;
    for (unsigned long long pixel = 0ull; good && (pixel < plane_voxels); pixel += 1ull)
    {
        const unsigned long long *const lower = &maps[(pixel * NOISE_PIXEL_HALVES) * NOISE_PIXEL_SUMS];
        const unsigned long long *const upper = &lower[NOISE_PIXEL_SUMS];
        if ((lower[NOISE_PIXEL_VOXELS] == 0ull) && (upper[NOISE_PIXEL_VOXELS] == 0ull))
        {
            continue;
        }
        good = fprintf(table, "%s\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, pixel / width,
                       pixel % width, lower[NOISE_PIXEL_VOXELS], lower[NOISE_PIXEL_VALUES],
                       lower[NOISE_PIXEL_SQUARES], upper[NOISE_PIXEL_VOXELS], upper[NOISE_PIXEL_VALUES],
                       upper[NOISE_PIXEL_SQUARES])
             > 0;
    }
    return good;
}

extern "C" long noise_pixels_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_ROOM];
    FILE *table = NULL;
    int good = NOISE_DETECTOR_HELD((request->set != NULL) && (request->samples != NULL) && (request->load != NULL),
                                   request, error, ENGINE_ERROR_REQUEST)
            && noise_table_open(request->set, "noise_pixels.tsv",
                                "sample\ty\tx\tlower_voxels\tlower_values\tlower_squares\tupper_voxels\tupper_values"
                                "\tupper_squares\n",
                                path, &table, error);
    printf("  pixels: every camera pixel's static voxels (the dimmest quarter by mean of those that change and never"
           " touch either end of the lane), counted, their values summed and their frame differences squared, in the"
           " z planes below the middle and from it up\n");
    const unsigned long long began = engine_clock_microseconds();
    unsigned long long *maps = NULL;
    unsigned long long held = 0ull;
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST);
        const unsigned long long cells = NOISE_PIXEL_CELLS(extent[2] * extent[3]);
        // the maps grow to the widest plane the set holds
        if (good && (cells > held))
        {
            free(maps);
            maps = (unsigned long long *)malloc((size_t)cells * sizeof(unsigned long long));
            held = (maps != NULL) ? cells : 0ull;
            good = NOISE_DETECTOR_HELD(maps != NULL, &maps, error, ENGINE_ERROR_RESOURCE);
        }
        unsigned long long ceiling = 0ull;
        good = good && (noise_pixels_sample(volume, extent, maps, &ceiling, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_pixels_rows(table, name, extent, maps) != 0, table, error);
        if (good != 0)
        {
            printf("  %-24s static means up to %llu\n", name, ceiling);
            fflush(stdout);
        }
    }
    free(maps);
    if (table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && good;
    }
    if (good != 0)
    {
        printf("  pixels: %u samples in %llu ms; every pixel's sums are in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

// The moment pass reads each voxel's frames in blocks of this many, each block about its own mean rounded. A level
// that moves over the frames then adds to a block only what it moves within one: the set's static level moves at most
// about one lane unit a frame, which adds about 2 lane units squared to a block's variance, under 2% of the shot's
// there, and nothing to its third cumulant.
#define NOISE_MOMENT_BLOCK 5ull

// a block's values stay within this many lane units of its rounded mean, or the block is left out and counted
#define NOISE_MOMENT_REACH 255ull

#define NOISE_MOMENT_POWERS 4u

#define NOISE_SIGNED_TOP 0x7FFFFFFFFFFFFFFFull

// One level bin of the moment pass, over its blocks: their count, their values summed, and S1, S1^2, S1^3, S1^4, S2,
// S1 S2, S1^2 S2, S3, S1 S3 and S4 summed, S2^2 summed 128 bits wide, S1 to S4 being a block's values less its mean
// rounded raised to the powers 1 to 4 and summed. With n frames a block and V blocks the k-statistics, each the mean
// over the blocks of that block's unbiased estimate, are
//   k2 = (n ΣS2 - ΣS1^2) / (V n (n - 1))
//   k3 = (2 ΣS1^3 - 3 n ΣS1 S2 + n^2 ΣS3) / (V n (n - 1)(n - 2))
//   k4 = (n^2 (n + 1) ΣS4 - 4 n (n + 1) ΣS1 S3 - 3 n (n - 1) ΣS2^2 + 12 n ΣS1^2 S2 - 6 ΣS1^4)
//        / (V n (n - 1)(n - 2)(n - 3))
typedef struct
{
    unsigned long long blocks;
    unsigned long long values;
    long long s1;
    unsigned long long s1_squared;
    long long s1_cubed;
    unsigned long long s1_fourth;
    unsigned long long s2;
    long long s1_s2;
    unsigned long long s1_squared_s2;
    long long s3;
    long long s1_s3;
    unsigned long long s4;
    NoiseWide s2_squared;
} NoiseMomentCell;

// A sample's quiet static voxels, each one's frames in blocks of NOISE_MOMENT_BLOCK: a block's values less their mean
// rounded to the nearest, raised to the powers 1 to 4 and summed, then binned by that mean. The fixed pattern leaves
// with the mean. A block with a value past NOISE_MOMENT_REACH of its mean is left out and counted, so every power sum
// fits a word; frames past the last whole block are not read.
static long noise_moments_sample(const unsigned short *volume, const unsigned long long extent[4],
                                 NoiseMomentCell cells[NOISE_LEVEL_BINS], unsigned long long *ceiling,
                                 unsigned long long *kept, unsigned long long *left_out, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long blocks = frames / NOISE_MOMENT_BLOCK;
    const unsigned long long square = NOISE_MOMENT_REACH * NOISE_MOMENT_REACH;
    const unsigned long long fourth = square * square;
    const unsigned long long spread = ((voxels != 0ull) && (frames <= (~0ull / voxels))) ? (frames * voxels) : ~0ull;
    // a block's |S1| is at most half its frames and each power at most its frames times the reach to that power, so
    // S4 bounds every product the cells sum but S2^2, which they sum wide; ΣS4 is at most the sample's voxel-frames
    // times the reach to the fourth, and the values at most the voxel-frames times the lane's top; the quiet mask holds
    // to 65536 frames
    const int bounded = (blocks != 0ull) && (frames <= 65536ull) && (voxels != 0ull) && (spread != ~0ull)
                     && (spread <= (NOISE_SIGNED_TOP / fourth)) && (spread <= (NOISE_SIGNED_TOP / NOISE_LANE_TOP));
    if (!NOISE_DETECTOR_HELD(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    memset(cells, 0, (size_t)NOISE_LEVEL_BINS * sizeof(NoiseMomentCell));
    *kept = 0ull;
    *left_out = 0ull;
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    int good = NOISE_DETECTOR_HELD(mask != NULL, &mask, error, ENGINE_ERROR_RESOURCE)
            && NOISE_DETECTOR_HELD(noise_static_mask(volume, frames, voxels, 1u, mask, ceiling) != 0, mask, error,
                                   ENGINE_ERROR_RESOURCE);
    unsigned long long members = 0ull;
    for (unsigned long long voxel = 0ull; good && (voxel < voxels); voxel += 1ull)
    {
        members += mask[voxel];
    }
    // one more than the members, so a sample with none still allocates
    unsigned long long *const places = (unsigned long long *)malloc((size_t)(members + 1ull)
                                                                    * sizeof(unsigned long long));
    good = good && NOISE_DETECTOR_HELD(places != NULL, &places, error, ENGINE_ERROR_RESOURCE);
    if (good != 0)
    {
        unsigned long long member = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            if (mask[voxel] != 0u)
            {
                places[member] = voxel;
                member += 1ull;
            }
        }
    }
    const long long reach = (long long)NOISE_MOMENT_REACH;
    for (unsigned long long block = 0ull; good && (block < blocks); block += 1ull)
    {
        const unsigned short *const first = &volume[block * NOISE_MOMENT_BLOCK * voxels];
        for (unsigned long long each = 0ull; each < members; each += 1ull)
        {
            const unsigned short *const lane = &first[places[each]];
            unsigned long long total = 0ull;
            for (unsigned long long frame = 0ull; frame < NOISE_MOMENT_BLOCK; frame += 1ull)
            {
                total += lane[frame * voxels];
            }
            // a mean of lanes rounded to the nearest is itself a lane
            const long long centre = (long long)((total + (NOISE_MOMENT_BLOCK / 2ull)) / NOISE_MOMENT_BLOCK);
            long long power[NOISE_MOMENT_POWERS] = {0ll, 0ll, 0ll, 0ll};
            int within = 1;
            for (unsigned long long frame = 0ull; within && (frame < NOISE_MOMENT_BLOCK); frame += 1ull)
            {
                const long long apart = (long long)lane[frame * voxels] - centre;
                within = (apart <= reach) && (apart >= -reach);
                if (within != 0)
                {
                    const long long apart_squared = apart * apart;
                    power[0] += apart;
                    power[1] += apart_squared;
                    power[2] += apart_squared * apart;
                    power[3] += apart_squared * apart_squared;
                }
            }
            if (within == 0)
            {
                *left_out += 1ull;
                continue;
            }
            *kept += 1ull;
            // the centre is a lane, so it re-signs to unsigned int exactly
            const unsigned int summed_bin = (unsigned int)centre >> (NOISE_LEVEL_BIN_SHIFT - 1u);
            NoiseMomentCell *const cell = &cells[(summed_bin < NOISE_LEVEL_BINS) ? summed_bin
                                                                                  : (NOISE_LEVEL_BINS - 1u)];
            const long long s1 = power[0];
            // S2 and S4 are sums of squares, never negative, so they re-sign to unsigned long long exactly
            const unsigned long long s2 = (unsigned long long)power[1];
            const unsigned long long s1_squared = (unsigned long long)(s1 * s1);
            cell->blocks += 1ull;
            cell->values += total;
            cell->s1 += s1;
            cell->s1_squared += s1_squared;
            cell->s1_cubed += s1 * s1 * s1;
            cell->s1_fourth += s1_squared * s1_squared;
            cell->s2 += s2;
            // S2 is at most a block's frames times the reach squared, far below 2^63, so it re-signs to long long
            // exactly
            cell->s1_s2 += s1 * (long long)s2;
            cell->s1_squared_s2 += s1_squared * s2;
            cell->s3 += power[2];
            cell->s1_s3 += s1 * power[2];
            cell->s4 += (unsigned long long)power[3];
            noise_wide_add_square(&cell->s2_squared, s2);
        }
    }
    free(mask);
    free(places);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static int noise_moments_rows(FILE *table, const char *name, const NoiseMomentCell cells[NOISE_LEVEL_BINS])
{
    int good = 1;
    for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
    {
        const NoiseMomentCell *const cell = &cells[level_bin];
        if (cell->blocks == 0ull)
        {
            continue;
        }
        good = fprintf(table,
                       "%s\t%u\t%llu\t%llu\t%llu\t%lld\t%llu\t%lld\t%llu\t%llu\t%lld\t%llu\t%llu\t%llu\t%lld\t%lld"
                       "\t%llu\n",
                       name, level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u), NOISE_MOMENT_BLOCK, cell->blocks, cell->values,
                       cell->s1,
                       cell->s1_squared, cell->s1_cubed, cell->s1_fourth, cell->s2, cell->s1_s2, cell->s1_squared_s2,
                       cell->s2_squared.high, cell->s2_squared.low, cell->s3, cell->s1_s3, cell->s4)
             > 0;
    }
    return good;
}

extern "C" long noise_moments_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_ROOM];
    FILE *table = NULL;
    int good = NOISE_DETECTOR_HELD((request->set != NULL) && (request->samples != NULL) && (request->load != NULL),
                                   request, error, ENGINE_ERROR_REQUEST)
            && noise_table_open(request->set, "noise_moments.tsv",
                                "sample\tlowest_mean\tblock_frames\tblocks\tvalues\ts1\ts1_squared\ts1_cubed\ts1_fourth"
                                "\ts2\ts1_s2\ts1_squared_s2\ts2_squared_high\ts2_squared_low\ts3\ts1_s3\ts4\n",
                                path, &table, error);
    printf("  moments: every quiet static voxel's frames in blocks of %llu, each block's values less its mean raised to"
           " the powers 1 to 4 and summed, then binned by the mean in 8s; the second, third and fourth k-statistics"
           " follow exactly from the table\n",
           NOISE_MOMENT_BLOCK);
    NoiseMomentCell *const cells = (NoiseMomentCell *)malloc((size_t)NOISE_LEVEL_BINS * sizeof(NoiseMomentCell));
    good = good && NOISE_DETECTOR_HELD(cells != NULL, &cells, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        unsigned long long ceiling = 0ull;
        unsigned long long kept = 0ull;
        unsigned long long left_out = 0ull;
        good = NOISE_DETECTOR_HELD(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                   ENGINE_ERROR_REQUEST)
            && (noise_moments_sample(volume, extent, cells, &ceiling, &kept, &left_out, error) == 0L);
        free(volume);
        good = good && NOISE_DETECTOR_IO(noise_moments_rows(table, name, cells) != 0, table, error);
        if (good != 0)
        {
            printf("  %-24s static means up to %llu; %llu blocks kept, %llu left out past %llu of their mean\n", name,
                   ceiling, kept, left_out, NOISE_MOMENT_REACH);
            fflush(stdout);
        }
    }
    free(cells);
    if (table != NULL)
    {
        good = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && good;
    }
    if (good != 0)
    {
        printf("  moments: %u samples in %llu ms; every bin's sums are in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

static void noise_exact_signed(AnchorExactInteger *value, long long word)
{
    // the magnitude of a negative word is its two's complement negation, taken unsigned
    const unsigned long long magnitude = (word < 0ll) ? (0ull - (unsigned long long)word) : (unsigned long long)word;
    noise_exact_word(value, magnitude);
    if (word < 0ll)
    {
        value->sign = -1;
    }
}

// sum gains factor times term, exactly
static int noise_exact_add_scaled(AnchorExactInteger *sum, long long factor, const AnchorExactInteger *term)
{
    AnchorExactInteger product;
    noise_exact_signed(&product, factor);
    return (anchor_exact_multiply(&product, term, &product) == ANCHOR_EXACT_OK)
        && (anchor_exact_add(sum, &product, sum) == ANCHOR_EXACT_OK);
}

// The k-statistic of order 2, 3 or 4 over a cell's blocks (the formulas at NoiseMomentCell), in signed thousandths
// rounded toward zero. 0 where the quotient passes a long long.
static int noise_moments_cumulant(const NoiseMomentCell *cell, unsigned int order, long long *thousandths)
{
    // the block's frames, 5, far below 2^31, as are every factor below
    const long long frames = (long long)NOISE_MOMENT_BLOCK;
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger term;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    anchor_exact_zero(&numerator);
    // the denominator: the blocks times n (n - 1) down to n - order + 1
    long long falling = 1ll;
    for (unsigned int step = 0u; step < order; step += 1u)
    {
        falling *= frames - (long long)step;
    }
    noise_exact_word(&denominator, cell->blocks);
    // the falling product of the block's frames is positive, so it re-signs to unsigned long long exactly
    noise_exact_word(&term, (unsigned long long)falling);
    int good = anchor_exact_multiply(&denominator, &term, &denominator) == ANCHOR_EXACT_OK;
    if (order == 2u)
    {
        noise_exact_word(&term, cell->s2);
        good = good && noise_exact_add_scaled(&numerator, frames, &term);
        noise_exact_word(&term, cell->s1_squared);
        good = good && noise_exact_add_scaled(&numerator, -1ll, &term);
    }
    else if (order == 3u)
    {
        noise_exact_signed(&term, cell->s1_cubed);
        good = good && noise_exact_add_scaled(&numerator, 2ll, &term);
        noise_exact_signed(&term, cell->s1_s2);
        good = good && noise_exact_add_scaled(&numerator, -3ll * frames, &term);
        noise_exact_signed(&term, cell->s3);
        good = good && noise_exact_add_scaled(&numerator, frames * frames, &term);
    }
    else
    {
        noise_exact_word(&term, cell->s4);
        good = good && noise_exact_add_scaled(&numerator, frames * frames * (frames + 1ll), &term);
        noise_exact_signed(&term, cell->s1_s3);
        good = good && noise_exact_add_scaled(&numerator, -4ll * frames * (frames + 1ll), &term);
        noise_exact_wide(&term, &cell->s2_squared);
        good = good && noise_exact_add_scaled(&numerator, -3ll * frames * (frames - 1ll), &term);
        noise_exact_word(&term, cell->s1_squared_s2);
        good = good && noise_exact_add_scaled(&numerator, 12ll * frames, &term);
        noise_exact_word(&term, cell->s1_fourth);
        good = good && noise_exact_add_scaled(&numerator, -6ll, &term);
    }
    noise_exact_word(&term, 1000ull);
    good = good && (anchor_exact_multiply(&numerator, &term, &numerator) == ANCHOR_EXACT_OK)
        && (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; good && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        good = quotient.limb[limb] == 0u;
    }
    good = good && (quotient.limb[1] < 0x80000000u);
    // the magnitude is below 2^63 by the test above; the sign is held apart
    *thousandths = good ? ((long long)(((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0])
                           * (long long)quotient.sign)
                        : 0ll;
    return good;
}

extern "C" long noise_moments_volume(const unsigned short *volume, const unsigned long long extent[4],
                                     long long cumulants[NOISE_MOMENT_CUMULANTS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_REFUSED;
    }
    NoiseMomentCell *const cells = (NoiseMomentCell *)malloc((size_t)NOISE_LEVEL_BINS * sizeof(NoiseMomentCell));
    unsigned long long ceiling = 0ull;
    unsigned long long kept = 0ull;
    unsigned long long left_out = 0ull;
    int good = NOISE_DETECTOR_HELD((volume != NULL) && (extent != NULL) && (cumulants != NULL), volume, error,
                                   ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_HELD(cells != NULL, &cells, error, ENGINE_ERROR_RESOURCE)
            && (noise_moments_sample(volume, extent, cells, &ceiling, &kept, &left_out, error) == 0L);
    // every bin pooled: each pooled sum is a sum over the sample's blocks, which the pass's bound already holds
    NoiseMomentCell pooled;
    memset(&pooled, 0, sizeof(pooled));
    for (unsigned int level_bin = 0u; good && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
    {
        const NoiseMomentCell *const cell = &cells[level_bin];
        pooled.blocks += cell->blocks;
        pooled.values += cell->values;
        pooled.s1 += cell->s1;
        pooled.s1_squared += cell->s1_squared;
        pooled.s1_cubed += cell->s1_cubed;
        pooled.s1_fourth += cell->s1_fourth;
        pooled.s2 += cell->s2;
        pooled.s1_s2 += cell->s1_s2;
        pooled.s1_squared_s2 += cell->s1_squared_s2;
        pooled.s3 += cell->s3;
        pooled.s1_s3 += cell->s1_s3;
        pooled.s4 += cell->s4;
        noise_wide_add(&pooled.s2_squared, cell->s2_squared.low, cell->s2_squared.high);
    }
    for (unsigned int order = 0u; good && (order < NOISE_MOMENT_CUMULANTS); order += 1u)
    {
        cumulants[order] = 0ll;
        if (pooled.blocks != 0ull)
        {
            good = NOISE_DETECTOR_HELD(noise_moments_cumulant(&pooled, order + 2u, &cumulants[order]) != 0,
                                       &pooled, error, ENGINE_ERROR_RESOURCE);
        }
    }
    free(cells);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

extern "C" long noise_flicker_volume(const unsigned short *volume, const unsigned long long extent[4],
                                     unsigned long long per_mille[NOISE_FLICKER_LAGS],
                                     unsigned long long neighbour_per_mille[NOISE_FLICKER_LAGS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_REFUSED;
    }
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)NOISE_FLICKER_CELLS
                                                                  * sizeof(unsigned long long));
    int good = NOISE_DETECTOR_HELD((volume != NULL) && (extent != NULL) && (per_mille != NULL)
                                       && (neighbour_per_mille != NULL),
                                   volume, error, ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_HELD(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE)
            && (noise_flicker_sample(volume, extent, sums, error) == 0L);
    if (good != 0)
    {
        unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS];
        noise_flicker_pooled(sums, pooled);
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            if (noise_per_mille(pooled[lag][NOISE_FLICKER_SQUARES], pooled[lag][NOISE_FLICKER_PAIRS],
                                pooled[0][NOISE_FLICKER_SQUARES], pooled[0][NOISE_FLICKER_PAIRS], &per_mille[lag])
                == 0)
            {
                per_mille[lag] = 0ull;
            }
            if (noise_per_mille(pooled[lag][NOISE_FLICKER_NEIGHBOUR_SQUARES],
                                pooled[lag][NOISE_FLICKER_NEIGHBOUR_PAIRS], pooled[0][NOISE_FLICKER_NEIGHBOUR_SQUARES],
                                pooled[0][NOISE_FLICKER_NEIGHBOUR_PAIRS], &neighbour_per_mille[lag])
                == 0)
            {
                neighbour_per_mille[lag] = 0ull;
            }
        }
    }
    free(sums);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

extern "C" long noise_lines_volume(const unsigned short *volume, const unsigned long long extent[4],
                                   long long readings[NOISE_PLANE_READINGS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_REFUSED;
    }
    NoiseLineCell *const cells = (NoiseLineCell *)malloc((size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    // four exact integers, held apart from the stack
    NoisePlanePool *const pool = (NoisePlanePool *)malloc(sizeof(NoisePlanePool));
    NoiseStaticPool still;
    // a volume read alone writes no plane table and so needs no name
    int good = NOISE_DETECTOR_HELD((volume != NULL) && (extent != NULL) && (readings != NULL), volume, error,
                                   ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_HELD((cells != NULL) && (pool != NULL), &cells, error, ENGINE_ERROR_RESOURCE)
            && (noise_lines_sample(volume, extent, cells, pool, &still, NULL, NULL, error) == 0L);
    if (good != 0)
    {
        int held[NOISE_PLANE_READINGS];
        noise_planes_readings(pool, readings, held);
        noise_static_readings(&still, &readings[NOISE_STATIC_ROWS], &held[NOISE_STATIC_ROWS]);
    }
    free(cells);
    free(pool);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

extern "C" long noise_neighbours_volume(const unsigned short *volume, const unsigned long long extent[4],
                                        long long per_mille[NOISE_NEIGHBOUR_REACHES], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_REFUSED;
    }
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)NOISE_NEIGHBOURS_CELLS
                                                                  * sizeof(unsigned long long));
    int good = NOISE_DETECTOR_HELD((volume != NULL) && (extent != NULL) && (per_mille != NULL), volume, error,
                                   ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_HELD(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE)
            && (noise_neighbours_sample(volume, extent, sums, error) == 0L);
    for (unsigned int reach = 0u; good && (reach < NOISE_NEIGHBOUR_REACHES); reach += 1u)
    {
        // each reach's sums pooled over the summary's level bins, means 40 to 199
        unsigned long long pooled[NOISE_NEIGHBOURS_SUMS];
        memset(pooled, 0, sizeof(pooled));
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            for (unsigned int sum = 0u; sum < NOISE_NEIGHBOURS_SUMS; sum += 1u)
            {
                pooled[sum] += sums[(((reach * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBOURS_SUMS) + sum];
            }
        }
        if (noise_neighbours_per_mille(pooled, &per_mille[reach]) == 0)
        {
            per_mille[reach] = 0ll;
        }
    }
    free(sums);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

extern "C" long noise_clips_volume(const unsigned short *volume, const unsigned long long extent[4],
                                   unsigned long long counts[NOISE_CLIPS_COUNTS], unsigned int box[NOISE_CLIPS_BOX],
                                   unsigned long long spikes[NOISE_SPIKE_SUMS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_REFUSED;
    }
    NoiseClips *const clips = (NoiseClips *)malloc(sizeof(NoiseClips));
    int good = NOISE_DETECTOR_HELD((volume != NULL) && (extent != NULL) && (counts != NULL) && (box != NULL)
                                       && (spikes != NULL),
                                   volume, error, ENGINE_ERROR_REQUEST)
            && NOISE_DETECTOR_HELD(clips != NULL, &clips, error, ENGINE_ERROR_RESOURCE)
            && (noise_clips_sample(volume, extent, clips, error) == 0L);
    if (good != 0)
    {
        memcpy(counts, clips->counts, sizeof(clips->counts));
        memcpy(box, clips->box, sizeof(clips->box));
        noise_spikes_pooled(clips, spikes);
    }
    free(clips);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

// one bit an axis of a box, frames (0), z, y and x (3)
#define NOISE_ROOT_AXIS(axis_) (1u << (axis_))

// the axes each term's value is shared along
static const unsigned int NOISE_ROOT_SHARED[NOISE_ROOT_TERMS] = {
    NOISE_ROOT_AXIS(3u), NOISE_ROOT_AXIS(2u), NOISE_ROOT_AXIS(2u) | NOISE_ROOT_AXIS(3u),
    NOISE_ROOT_AXIS(0u) | NOISE_ROOT_AXIS(1u), NOISE_ROOT_AXIS(1u)};

// a box holds at most 2^31 voxels, so a pattern value's sum of at most that many lanes fits a word
#define NOISE_ROOT_VOXELS_MOST (1ull << 31u)

// a price past 2^61 bits is refused, so the box's less a residual's and a pattern's is a long long
#define NOISE_ROOT_BITS_MOST (1ull << 61u)

extern "C" void noise_root_extent(unsigned int term, const unsigned long long box[4], unsigned long long pattern[4])
{
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        const int kept = (term < NOISE_ROOT_TERMS) && ((NOISE_ROOT_SHARED[term] & NOISE_ROOT_AXIS(axis)) == 0u);
        pattern[axis] = (kept != 0) ? box[axis] : 1ull;
    }
}

// the box's voxels, 0 where an axis is empty or the count passes NOISE_ROOT_VOXELS_MOST
static unsigned long long noise_root_voxels(const unsigned long long box[4])
{
    unsigned long long voxels = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        const int fits = (box[axis] != 0ull) && (box[axis] <= (NOISE_ROOT_VOXELS_MOST / voxels));
        voxels = (fits != 0) ? (voxels * box[axis]) : 0ull;
        if (voxels == 0ull)
        {
            return 0ull;
        }
    }
    return voxels;
}

// the next place in the box, x fastest, as the voxels are laid
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
                // the volume is held, so its voxel count, and every place inside it, fits a word
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
    unsigned long long shape[4];
    noise_root_extent(term, box, shape);
    const unsigned long long cells = shape[0] * shape[1] * shape[2] * shape[3];
    memset(sums, 0, (size_t)cells * sizeof(unsigned long long));
    unsigned long long place[4] = {0ull, 0ull, 0ull, 0ull};
    for (unsigned long long at = 0ull; at < voxels; at += 1ull)
    {
        // a box value is a lane, never negative
        sums[noise_root_pattern_place(place, shape)] += (unsigned long long)values[at];
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
    unsigned long long shape[4];
    noise_root_extent(term, box, shape);
    unsigned long long place[4] = {0ull, 0ull, 0ull, 0ull};
    for (unsigned long long at = 0ull; at < voxels; at += 1ull)
    {
        to[at] = from[at] + (sign * pattern[noise_root_pattern_place(place, shape)]);
        noise_root_next(place, box);
    }
}

static int noise_root_price(const NoiseRootRequest *request, const int *values, const unsigned long long shape[4],
                            unsigned long long *bits)
{
    *bits = 0ull;
    return NOISE_DETECTOR_HELD((request->cost(values, shape, bits, request->error) == 0L)
                                   && (*bits <= NOISE_ROOT_BITS_MOST),
                               values, request->error, ENGINE_ERROR_REQUEST);
}

extern "C" long noise_root_box(const NoiseRootRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    EngineError *const error = request->error;
    unsigned long long box[4] = {0ull, 0ull, 0ull, 0ull};
    int inside = (request->volume != NULL) && (request->cost != NULL) && (request->reading != NULL);
    for (unsigned int axis = 0u; inside && (axis < 4u); axis += 1u)
    {
        inside = (request->low[axis] < request->high[axis]) && (request->high[axis] <= request->extent[axis]);
        box[axis] = (inside != 0) ? (request->high[axis] - request->low[axis]) : 0ull;
    }
    const unsigned long long voxels = (inside != 0) ? noise_root_voxels(box) : 0ull;
    if (!NOISE_DETECTOR_HELD(voxels != 0ull, request, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    NoiseRootReading *const reading = request->reading;
    memset(reading, 0, sizeof(*reading));
    reading->root = NOISE_ROOT_TERMS;
    int *const values = (int *)malloc((size_t)voxels * sizeof(int));
    int *const residual = (int *)malloc((size_t)voxels * sizeof(int));
    int *const pattern = (int *)malloc((size_t)voxels * sizeof(int));
    unsigned long long *const sums = (unsigned long long *)malloc((size_t)voxels * sizeof(unsigned long long));
    int good = NOISE_DETECTOR_HELD((values != NULL) && (residual != NULL) && (pattern != NULL) && (sums != NULL),
                                   &values, error, ENGINE_ERROR_RESOURCE);
    if (good != 0)
    {
        noise_root_take(request, box, values);
    }
    good = good && noise_root_price(request, values, box, &reading->box_bits);
    long long most = 0ll;
    for (unsigned int term = 0u; good && (term < NOISE_ROOT_TERMS); term += 1u)
    {
        unsigned long long shape[4];
        noise_root_extent(term, box, shape);
        noise_root_pattern(values, box, voxels, term, sums, pattern);
        noise_root_spread(values, box, voxels, term, pattern, -1, residual);
        good = noise_root_price(request, residual, box, &reading->residual_bits[term])
            && noise_root_price(request, pattern, shape, &reading->pattern_bits[term]);
        // each price is at most 2^61, so each converts to long long exactly and the difference cannot wrap
        reading->saved[term] = (long long)reading->box_bits - (long long)reading->residual_bits[term]
                             - (long long)reading->pattern_bits[term];
        if (good && (reading->saved[term] > most))
        {
            most = reading->saved[term];
            reading->root = term;
        }
    }
    const unsigned int root = reading->root;
    if (good && (root < NOISE_ROOT_TERMS))
    {
        noise_root_pattern(values, box, voxels, root, sums, pattern);
        noise_root_spread(values, box, voxels, root, pattern, -1, residual);
    }
    if (good && (request->residual != NULL))
    {
        memcpy(request->residual, (root < NOISE_ROOT_TERMS) ? residual : values, (size_t)voxels * sizeof(int));
    }
    if (good && (request->pattern != NULL) && (root < NOISE_ROOT_TERMS))
    {
        unsigned long long shape[4];
        noise_root_extent(root, box, shape);
        memcpy(request->pattern, pattern, (size_t)(shape[0] * shape[1] * shape[2] * shape[3]) * sizeof(int));
    }
    free(values);
    free(residual);
    free(pattern);
    free(sums);
    return (good != 0) ? 0L : NOISE_DETECTOR_REFUSED;
}

extern "C" long noise_root_return(const NoiseReturnRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    const unsigned long long voxels = noise_root_voxels(request->box);
    if (!NOISE_DETECTOR_HELD((request->residual != NULL) && (request->pattern != NULL) && (request->values != NULL)
                                 && (request->term < NOISE_ROOT_TERMS) && (voxels != 0ull),
                             request, request->error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_REFUSED;
    }
    noise_root_spread(request->residual, request->box, voxels, request->term, request->pattern, 1, request->values);
    return 0L;
}
