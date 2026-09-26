// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef NOISE_DETECTOR_H
#define NOISE_DETECTOR_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NOISE_DETECTOR_REFUSED (-1L)

// the structure function's lags, frames apart: 1, 2, 4 and on to 64 (noise_vector_integration_table.md, row 7)
#define NOISE_FLICKER_LAGS 7u

// a pair's level bin is the sum of its two values shifted down 4, its mean in bins of 8 lane units; the last bin
// holds every mean from 1024 up
#define NOISE_LEVEL_BIN_SHIFT 4u

#define NOISE_LEVEL_BINS 129u

// the four sums each lag and level bin holds
#define NOISE_FLICKER_PAIRS 0u

#define NOISE_FLICKER_SQUARES 1u

#define NOISE_FLICKER_NEIGHBOUR_PAIRS 2u

#define NOISE_FLICKER_NEIGHBOUR_SQUARES 3u

#define NOISE_FLICKER_SUMS 4u

// Loads one sample of a set: its extent (frames, depth, height, width) and its volume, frame by frame, z, y and x
// within; the volume is the caller's to free. Returns 0, or a negative value with the error filled. The driver passes
// the engine's crystal loader, so the detector reaches no module but its own.
typedef long (*NoiseLoad)(const char *set, const char *sample, unsigned long long extent[4], unsigned short **volume,
                          EngineError *error);

typedef struct
{
    const char *set;
    char *const *samples;
    unsigned int count;
    EngineError *error;
    NoiseLoad load;
} NoiseSetRequest;

// every sample's structure function, written to <set>/noise_flicker.tsv and summarized on stdout
long noise_flicker_set(const NoiseSetRequest *request);

// the lines a frame difference is summed along (noise_vector_integration_table.md, rows 8 to 10): a row runs along
// x, a column along y, and a plane is one whole z plane
#define NOISE_LINE_ROWS 0u

#define NOISE_LINE_COLUMNS 1u

#define NOISE_LINE_PLANES 2u

#define NOISE_LINE_KINDS 3u

// every sample's line sums, written to <set>/noise_lines.tsv, and every frame pair's z plane with its row and column
// sums squared, written to <set>/noise_planes.tsv; both summarized on stdout
long noise_lines_set(const NoiseSetRequest *request);

// the five sums each axis and level bin of the neighbour pass holds (noise_vector_integration_table.md, rows 17 and
// 25): the pairs, the squared frame difference, the next voxel's, and their products raised and lowered apart
#define NOISE_NEIGHBOURS_PAIRS 0u

#define NOISE_NEIGHBOURS_SQUARES 1u

#define NOISE_NEIGHBOURS_OTHER_SQUARES 2u

#define NOISE_NEIGHBOURS_RAISED 3u

#define NOISE_NEIGHBOURS_LOWERED 4u

#define NOISE_NEIGHBOURS_SUMS 5u

// the neighbour pass's reaches: the next voxel along z, y and x, then the voxel 2, 4, 8, 16 and 32 planes on along z.
// An interpolation between neighbouring planes leaves every reach past the first uncorrelated; a blur along z fades
// over its reach; a term every plane of a pixel shares holds at every reach.
#define NOISE_NEIGHBOUR_REACHES 8u

// every sample's neighbour correlation at each reach, written to <set>/noise_neighbours.tsv and summarized
long noise_neighbours_set(const NoiseSetRequest *request);

// the clip pass (noise_vector_integration_table.md, rows 11, 12, 23 and 24): a spike is a frame above both frames
// beside it by a threshold, a dip one below both, at thresholds of 16, 32, 64 and 128 lane units
#define NOISE_SPIKE_THRESHOLDS 4u

#define NOISE_SPIKE_LEAST 16u

// each level bin holds the triples, then the spikes and the dips at each threshold
#define NOISE_SPIKE_TRIPLES 0u

#define NOISE_SPIKE_SUMS (1u + (2u * NOISE_SPIKE_THRESHOLDS))

// the counts a sample's clip pass keeps: voxel-frames at 0 and at the top, voxels whose every frame holds one value,
// and those held at 0 or at the top
#define NOISE_CLIPS_AT_ZERO 0u

#define NOISE_CLIPS_AT_TOP 1u

#define NOISE_CLIPS_CONSTANT 2u

#define NOISE_CLIPS_CONSTANT_ZERO 3u

#define NOISE_CLIPS_CONSTANT_TOP 4u

#define NOISE_CLIPS_COUNTS 5u

// the constant voxels' box: least and most z, then y, then x
#define NOISE_CLIPS_BOX (2u * ENGINE_AXES)

// every sample's value counts, the voxel-frames at either end of the lane, the voxels that never change and the
// spikes and dips, written to <set>/noise_clips.tsv, <set>/noise_values.tsv and <set>/noise_spikes.tsv, and
// summarized on stdout
long noise_clips_set(const NoiseSetRequest *request);

// every sample's camera pixels (noise_vector_integration_table.md, rows 18 to 21): at each (y, x), the static voxels
// of the z planes below the middle and of those from it up, counted, their values summed and their frame differences
// squared and summed, written to <set>/noise_pixels.tsv
long noise_pixels_set(const NoiseSetRequest *request);

// every sample's cumulant sums (noise_vector_integration_table.md, rows 1, 11 and 12): each quiet static voxel's
// frames in short blocks, a block's values less its own mean rounded raised to the powers 1 to 4 and summed (S1 to
// S4), then per level bin by the block's mean those sums and their products summed over the blocks, from which the
// unbiased k-statistics of the second, third and fourth cumulants follow exactly; written to <set>/noise_moments.tsv
long noise_moments_set(const NoiseSetRequest *request);

// One volume's readings, the numbers each set call prints for a sample, so a sim can plant a term and read it back.
// The volume and extent are laid out as NoiseLoad gives them. Each returns 0, or NOISE_DETECTOR_REFUSED with the error
// filled; a reading the volume cannot give is 0.

// each lag's mean square against lag 1's, per mille over means 40 to 199: the frame difference, then it less its x
// neighbour's
long noise_flicker_volume(const unsigned short *volume, const unsigned long long extent[4],
                          unsigned long long per_mille[NOISE_FLICKER_LAGS],
                          unsigned long long neighbour_per_mille[NOISE_FLICKER_LAGS], EngineError *error);

// the two-way layout over every plane: rows, columns and the plane per mille, each 1000 where nothing is shared,
// then the independent variance of a voxel's frame difference in lane units squared
#define NOISE_PLANE_ROWS 0u

#define NOISE_PLANE_COLUMNS 1u

#define NOISE_PLANE_PLANE 2u

#define NOISE_PLANE_INDEPENDENT 3u

// then the static voxels' unbalanced layout: var_row, var_col and var_plane against the independent part s, signed
// per mille, each 0 where nothing is shared, then s in thousandths of a lane unit squared
#define NOISE_STATIC_ROWS 4u

#define NOISE_STATIC_COLUMNS 5u

#define NOISE_STATIC_PLANE 6u

#define NOISE_STATIC_INDEPENDENT 7u

#define NOISE_PLANE_READINGS 8u

long noise_lines_volume(const unsigned short *volume, const unsigned long long extent[4],
                        long long readings[NOISE_PLANE_READINGS], EngineError *error);

// the neighbour correlation at each reach over means 40 to 199, signed per mille
long noise_neighbours_volume(const unsigned short *volume, const unsigned long long extent[4],
                             long long per_mille[NOISE_NEIGHBOUR_REACHES], EngineError *error);

// the clip pass's counts and box, and its triples, spikes and dips over means 40 to 199
long noise_clips_volume(const unsigned short *volume, const unsigned long long extent[4],
                        unsigned long long counts[NOISE_CLIPS_COUNTS], unsigned int box[NOISE_CLIPS_BOX],
                        unsigned long long spikes[NOISE_SPIKE_SUMS], EngineError *error);

// the moment pass's second, third and fourth k-statistics pooled over every level bin, each in signed thousandths of
// a lane unit to its power, rounded toward zero; each 0 where no block was kept
#define NOISE_MOMENT_CUMULANTS 3u

long noise_moments_volume(const unsigned short *volume, const unsigned long long extent[4],
                          long long cumulants[NOISE_MOMENT_CUMULANTS], EngineError *error);

// The root noise of a box: a span of frames and a place the caller names, an object's in the cell book. Each term the
// noise vector table names as shared is a pattern in fewer dimensions than the box, one value for every place along
// the axes it is kept on and the same along the axes it is shared along. A term's pattern over a box is the box's mean
// along its shared axes, rounded down, exactly; its residual is the box less the pattern spread back along them. The
// crystal's own coder prices the box, each residual and each pattern in bits (NoiseCost), and a term saves what the
// box costs less what its residual and its pattern cost together. The root noise is the term that saves the most, the
// first of them where two save alike, and none where no term saves. Yanking it keeps its residual and its pattern,
// from which the box returns exactly (noise_root_return).
// rows (table row 8): shared along x, a value for each frame, z and y
#define NOISE_ROOT_ROWS 0u

// columns (row 9): shared along y, a value for each frame, z and x
#define NOISE_ROOT_COLUMNS 1u

// planes (row 10): shared along y and x, a value for each frame and z
#define NOISE_ROOT_PLANES 2u

// the fixed pattern (row 18): shared along the frames and z, a value for each camera pixel, y and x
#define NOISE_ROOT_PIXELS 3u

// the term every plane of a stack shares (row 25): shared along z, a value for each frame, y and x
#define NOISE_ROOT_STACKS 4u

#define NOISE_ROOT_TERMS 5u

// Prices a lattice of ints laid as NoiseLoad lays a volume, frames, z, y and x: the bits the crystal spends on it.
// Returns 0, or a negative value with the error filled. The driver passes the engine's, so the detector reaches no
// module but its own.
typedef long (*NoiseCost)(const int *values, const unsigned long long extent[4], unsigned long long *bits,
                          EngineError *error);

// `saved` is the box's bits less the term's residual's and pattern's, signed; `root` is NOISE_ROOT_TERMS where none
// saves
typedef struct
{
    unsigned long long box_bits;
    unsigned long long residual_bits[NOISE_ROOT_TERMS];
    unsigned long long pattern_bits[NOISE_ROOT_TERMS];
    long long saved[NOISE_ROOT_TERMS];
    unsigned int root;
} NoiseRootReading;

// The box runs from `low` to below `high` on every axis, frames, z, y and x, inside the volume's extent, and holds at
// most 2^31 voxels. Where `residual` is set, the root's residual is left in it, the box's voxels as ints, or the box
// itself where there is no root; where `pattern` is set, the root's pattern is left in it (noise_root_extent sizes it,
// never more than the box's voxels), and nothing where there is no root. A price the cost gives past 2^61 bits is
// refused.
typedef struct
{
    const unsigned short *volume;
    unsigned long long extent[4];
    unsigned long long low[4];
    unsigned long long high[4];
    NoiseCost cost;
    NoiseRootReading *reading;
    int *residual;
    int *pattern;
    EngineError *error;
} NoiseRootRequest;

long noise_root_box(const NoiseRootRequest *request);

// a term's pattern extent over a box's: the box's own along the term's kept axes, 1 along its shared axes and for a
// term past the last
void noise_root_extent(unsigned int term, const unsigned long long box[4], unsigned long long pattern[4]);

// The box's values back from a term's residual and pattern, each residual plus its pattern value. For the residual
// and pattern noise_root_box leaves, the sum is the box's value exactly; any other pair must keep every sum within an
// int, which is not checked.
typedef struct
{
    const int *residual;
    const int *pattern;
    unsigned int term;
    unsigned long long box[4];
    int *values;
    EngineError *error;
} NoiseReturnRequest;

long noise_root_return(const NoiseReturnRequest *request);

#ifdef __cplusplus
}
#endif

#endif
