// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the noise_detector_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef NOISE_DETECTOR_INTERNAL_H
#define NOISE_DETECTOR_INTERNAL_H

#include "noise_detector.h"

#include "exact_integer.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define NOISE_DETECTOR_STATUS_CHECK(call_, evacaddr_, error_)                                                          \
    engine_status_check((int)(call_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define NOISE_DETECTOR_CHECK(condition_, evacaddr_, error_, kind_)                                                     \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__,                    \
                       (const void *)(evacaddr_), (error_))

#define NOISE_DETECTOR_IO(condition_, evacaddr_, error_)                                                               \
    engine_io_check((condition_), ENGINE_MODULE_NOISE_DETECTOR, (unsigned int)__LINE__, (const void *)(evacaddr_),     \
                    (error_))

#define NOISE_DETECTOR_THREADS 256u

#define NOISE_FLICKER_CELLS (NOISE_FLICKER_LAGS * NOISE_LEVEL_BINS * NOISE_FLICKER_SUMS)

static_assert((NOISE_FLICKER_CELLS * sizeof(unsigned long long)) <= 49152u,
              "noise_detector: the flicker sums fit one block's shared memory");

// the widest squared difference less its neighbor's: each frame difference lies in [-65535, 65535]
#define NOISE_WIDEST_SQUARE (131070ull * 131070ull)

// the lane's top: a value past it was held there
#define NOISE_LANE_TOP 65535u

#define NOISE_VALUES 65536u

// the summary reads means 40 to 199, the range compression_table.md fits the transfer curve over, bins 5 to 24
#define NOISE_SUMMARY_FIRST_BIN 5u

#define NOISE_SUMMARY_LAST_BIN 24u

static_assert(((NOISE_SUMMARY_FIRST_BIN << (NOISE_LEVEL_BIN_SHIFT - 1u)) == 40u) &&
                  (((NOISE_SUMMARY_LAST_BIN + 1u) << (NOISE_LEVEL_BIN_SHIFT - 1u)) == 200u),
              "noise_detector: the summary's bins are the means 40 to 199");

long noise_flicker_sample(const unsigned short *volume, const unsigned long long extent[4],
                          unsigned long long sums[NOISE_FLICKER_CELLS], EngineError *error);

void noise_exact_word(AnchorExactInteger *value, unsigned long long word);

int noise_per_mille(unsigned long long squares, unsigned long long pairs, unsigned long long first_squares,
                    unsigned long long first_pairs, unsigned long long *per_mille);

void noise_flicker_pooled(const unsigned long long sums[NOISE_FLICKER_CELLS],
                          unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS]);

static_assert(ANCHOR_EXACT_LIMBS >= 8u, "noise_detector: a 128 bit sum times 1000 fits the exact integer");

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} NoiseWide;

void noise_wide_add(NoiseWide *sum, unsigned long long low, unsigned long long high);

void noise_wide_add_square(NoiseWide *sum, unsigned long long magnitude);

typedef struct
{
    unsigned long long lines;
    unsigned long long members;
    unsigned long long member_squares;
    NoiseWide line_squares;
} NoiseLineCell;

#define NOISE_LINE_CELLS (NOISE_LINE_KINDS * NOISE_LEVEL_BINS)

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
// and P^2 to plane_squares. Independent noise summing to sums over a plane gives spread - rows - columns its
// expectation (H - 1)(W - 1) sums, whatever the rows, the columns and the plane share.
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

int noise_static_mask(const unsigned short *volume, unsigned long long frames, unsigned long long voxels,
                      unsigned int quiet, unsigned char *mask, unsigned long long *ceiling);

long noise_lines_sample(const unsigned short *volume, const unsigned long long extent[4],
                        NoiseLineCell cells[NOISE_LINE_CELLS], NoisePlanePool *pool, NoiseStaticPool *still,
                        FILE *plane_table, const char *name, EngineError *error);

void noise_exact_wide(AnchorExactInteger *value, const NoiseWide *wide);

// The pooled planes as three ratios against the independent part s, the variance of one voxel's frame difference
// that nothing shares: rows 1 + W var_row / s, columns 1 + H var_col / s and the plane 1 + N var_plane / s, per mille,
// each 1000 where nothing is shared; then s itself in lane units squared, rounded toward zero. With D = spread - rows -
// columns, the row ratio is rows (W - 1) / D, the column ratio columns (H - 1) / D, and the plane ratio
// (plane_squares (H - 1)(W - 1) - rows (W - 1) - columns (H - 1) + 2 D) / D.
#define NOISE_TWO_WAY_READINGS 4u

static_assert(
    NOISE_TWO_WAY_READINGS == NOISE_STATIC_ROWS,
    "noise_detector: the two-way measurements come first in a volume's measurements, the static ones after them");

void noise_planes_readings(const NoisePlanePool *pool, long long readings[NOISE_TWO_WAY_READINGS],
                           int valid[NOISE_TWO_WAY_READINGS]);

// the static layout's measurements: rows, columns, the plane, and the independent part
#define NOISE_STATIC_READINGS 4u

static_assert((NOISE_TWO_WAY_READINGS + NOISE_STATIC_READINGS) == NOISE_PLANE_READINGS,
              "noise_detector: a volume's line measurements are the two-way ones, then the static ones");

void noise_static_readings(const NoiseStaticPool *still, long long readings[NOISE_STATIC_READINGS],
                           int valid[NOISE_STATIC_READINGS]);

#define NOISE_NEIGHBORS_CELLS (NOISE_NEIGHBOR_RADII * NOISE_LEVEL_BINS * NOISE_NEIGHBORS_SUMS)

static_assert((NOISE_NEIGHBORS_CELLS * sizeof(unsigned long long)) <= 49152u,
              "noise_detector: the neighbor sums fit one block's shared memory");

static_assert(NOISE_NEIGHBOR_RADII == (ENGINE_AXES + 5u),
              "noise_detector: the radii are one voxel along each axis, then 2 to 32 planes along z");

// the summary's level bins: means 24, 40, 72, 104 and 200, where compression_table.md reads its correlations
#define NOISE_NEIGHBORS_SHOWN 5u

long noise_neighbors_sample(const unsigned short *volume, const unsigned long long extent[4],
                            unsigned long long sums[NOISE_NEIGHBORS_CELLS], EngineError *error);

int noise_neighbors_per_mille(const unsigned long long cell[NOISE_NEIGHBORS_SUMS], long long *per_mille);

#define NOISE_SPIKE_CELLS (NOISE_LEVEL_BINS * NOISE_SPIKE_SUMS)

// values below this are counted in the block's shared memory first; the rest go to the sample's counts directly
#define NOISE_SHARED_VALUES 8192u

static_assert(((NOISE_SPIKE_CELLS * sizeof(unsigned long long)) + (NOISE_SHARED_VALUES * sizeof(unsigned int))) <=
                  49152u,
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

long noise_clips_sample(const unsigned short *volume, const unsigned long long extent[4], NoiseClips *clips,
                        EngineError *error);

void noise_spikes_pooled(const NoiseClips *clips, unsigned long long pooled[NOISE_SPIKE_SUMS]);

void noise_clips_summary(const char *name, const NoiseClips *clips);

int noise_clips_rows(FILE *const tables[NOISE_CLIPS_TABLES], const char *name, const NoiseClips *clips);

int noise_table_open(const char *set, const char *file, const char *header, char path[ENGINE_PATH_CAPACITY],
                     FILE **table, EngineError *error);

// The moment pass reads each voxel's frames in blocks of this many, each block about its own mean rounded. A level
// that moves over the frames then adds to a block only what it moves within one: the set's static level moves at most
// about one lane unit a frame, which adds about 2 lane units squared to a block's variance, under 2% of the shot's
// there, and nothing to its third cumulant.
#define NOISE_MOMENT_BLOCK 5ull

// a block's values stay within this many lane units of its rounded mean, or the block is left out and counted
#define NOISE_MOMENT_RANGE 255ull

#define NOISE_MOMENT_POWERS 4u

#define NOISE_SIGNED_TOP 0x7FFFFFFFFFFFFFFFull

// One level bin of the moment pass, over its blocks: their count, their values summed, and S1, S1^2, S1^3, S1^4, S2,
// S1 S2, S1^2 S2, S3, S1 S3 and S4 summed, S2^2 summed 128 bits wide, S1 to S4 being a block's values less its mean
// rounded raised to the powers 1 to 4 and summed. With n frames a block and V blocks the k-statistics, each the mean
// over the blocks of that block's unbiased estimate, are
//   k2 = (n sumS2 - sumS1^2) / (V n (n - 1))
//   k3 = (2 sumS1^3 - 3 n sumS1 S2 + n^2 sumS3) / (V n (n - 1)(n - 2))
//   k4 = (n^2 (n + 1) sumS4 - 4 n (n + 1) sumS1 S3 - 3 n (n - 1) sumS2^2 + 12 n sumS1^2 S2 - 6 sumS1^4)
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

extern "C" void noise_line_sums_zero(NoiseLineSums *sums);

int noise_exact_add_product(AnchorExactInteger *sum, const AnchorExactInteger *left, const AnchorExactInteger *right);

extern "C" long noise_line_fit(const NoiseLineSums *sums, unsigned long long level_scale,
                               unsigned long long measurement_scale, NoiseLine *line, EngineError *error);

// A signed sum 128 bits wide, held as its raised and lowered parts
typedef struct
{
    NoiseWide raised;
    NoiseWide lowered;
} NoiseSignedWide;

void noise_signed_wide_add(NoiseSignedWide *sum, unsigned long long place, long long measurement);

int noise_exact_signed_wide(AnchorExactInteger *value, const NoiseSignedWide *wide);

// The ladder's sums over the kept blocks: a block's place x is its voxel's frames summed over the voxel's other whole
// blocks, and its measurements e2, e3 and e4 are its k-statistics' numerators, each k_j being e_j over n (n - 1) down
// to n - j + 1 (the formulas at NoiseMomentCell, with V = 1). By the bounds noise_ladder_sample holds, x is below 2^32,
// every |e_j| below 2^46 and the blocks below 2^31. Sum x^2 stays below 2^95 and every sum x e_j below 2^109.
typedef struct
{
    unsigned long long blocks;
    NoiseWide along;
    NoiseWide along_square;
    NoiseSignedWide measured[NOISE_LADDER_ORDERS];
    NoiseSignedWide cross[NOISE_LADDER_ORDERS];
} NoiseLadderSums;

// the crosstalk pass's sums along each axis: the pairs, sum d'^2, then each step's raised and lowered products
#define NOISE_CROSSTALK_SUMS (2u + (2u * NOISE_CROSSTALK_STEPS))

#define NOISE_CROSSTALK_CELLS (NOISE_CROSSTALK_AXES * NOISE_CROSSTALK_SUMS)

// the structure pass's level bins: the pair's mean level over the frames, in bins of 8, over the summary's 40 to 199
#define NOISE_STRUCTURE_BINS (NOISE_SUMMARY_LAST_BIN - NOISE_SUMMARY_FIRST_BIN + 1u)

// the words each lag and bin holds: the pairs, then the sums of M, M^2, q, q^2, M q, y, M y and q y, each 128 bits as
// its low word then its high word
#define NOISE_STRUCTURE_PAIRS 0u

#define NOISE_STRUCTURE_LEVEL 1u

#define NOISE_STRUCTURE_LEVEL_SQUARE 3u

#define NOISE_STRUCTURE_ALONG 5u

#define NOISE_STRUCTURE_ALONG_SQUARE 7u

#define NOISE_STRUCTURE_LEVEL_ALONG 9u

#define NOISE_STRUCTURE_MEASURED 11u

#define NOISE_STRUCTURE_LEVEL_MEASURED 13u

#define NOISE_STRUCTURE_CROSS 15u

#define NOISE_STRUCTURE_WORDS 17u

// the five centerd sums a bin gives the fit: M against M, q against q, M against q, M against y and q against y
#define NOISE_STRUCTURE_CENTERD 5u

#define NOISE_STRUCTURE_CELLS (NOISE_FLICKER_LAGS * NOISE_STRUCTURE_BINS * NOISE_STRUCTURE_WORDS)

static_assert((NOISE_STRUCTURE_CELLS * sizeof(unsigned long long)) <= 49152u,
              "noise_detector: the structure sums fit one block's shared memory");

// A 128 bit sum held at cell[0] (its low word) and cell[1] (its high word) gains high 2^64 + low. The low word's carry
// is read from the value the atomic add found there. Each carry is counted once, whatever the order.
__device__ static inline void noise_wide_atomic_add(unsigned long long *cell, unsigned long long low,
                                                    unsigned long long high)
{
    const unsigned long long before = atomicAdd(&cell[0], low);
    const unsigned long long carried = high + (((before + low) < before) ? 1ull : 0ull);
    if (carried != 0ull)
    {
        atomicAdd(&cell[1], carried);
    }
}

void noise_exact_words(AnchorExactInteger *value, const unsigned long long *words);

// the halves pass's sums: sum lo and sum hi, then sum lo hi as 128 bits, its low word then its high word
#define NOISE_HALVES_LOWER 0u

#define NOISE_HALVES_UPPER 1u

#define NOISE_HALVES_PRODUCT 2u

#define NOISE_HALVES_SUMS 4u

// a box holds at most 2^31 voxels. A pattern value's sum of at most that many lanes fits a word
#define NOISE_ROOT_VOXELS_MAX (1ull << 31u)

// a price past 2^61 bits is refused. The box's less a residual's and a pattern's is a long long
#define NOISE_ROOT_BITS_MAX (1ull << 61u)

extern "C" void noise_root_extent(unsigned int term, const unsigned long long box[4], unsigned long long pattern[4]);

#endif
