// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef NOISE_DETECTOR_H
#define NOISE_DETECTOR_H

#include "engine_config.h"
#include "exact_integer.h"

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
// the engine's crystal loader, and the detector reaches no module but its own.
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

// the five sums each axis and level bin of the neighbor pass holds (noise_vector_integration_table.md, rows 17 and
// 25): the pairs, the squared frame difference, the next voxel's, and their products raised and lowered apart
#define NOISE_NEIGHBOURS_PAIRS 0u

#define NOISE_NEIGHBOURS_SQUARES 1u

#define NOISE_NEIGHBOURS_OTHER_SQUARES 2u

#define NOISE_NEIGHBOURS_RAISED 3u

#define NOISE_NEIGHBOURS_LOWERED 4u

#define NOISE_NEIGHBOURS_SUMS 5u

// the neighbor pass's reaches: the next voxel along z, y and x, then the voxel 2, 4, 8, 16 and 32 planes on along z.
// An interpolation between neighboring planes leaves every reach past the first uncorrelated; a blur along z fades
// over its reach; a term every plane of a pixel shares holds at every reach.
#define NOISE_NEIGHBOUR_REACHES 8u

// every sample's neighbor correlation at each reach, written to <set>/noise_neighbours.tsv and summarized
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

// One volume's readings, the numbers each set call prints for a sample. A sim plants a term and reads it back through these.
// The volume and extent are laid out as NoiseLoad gives them. Each returns 0, or NOISE_DETECTOR_REFUSED with the error
// filled; a reading the volume cannot give is 0.

// each lag's mean square against lag 1's, per mille over means 40 to 199: the frame difference, then it less its x
// neighbor's
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

// the neighbor correlation at each reach over means 40 to 199, signed per mille
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

// The line over the level (build plan item 38): the least-squares line through points each weighted by a count, held
// as three exact integers over one denominator. count points sit at an integer place, and their readings sum to total.
// A level is a place over level_scale and a reading a total's share over reading_scale, so with N = sum of counts,
// A = sum of count place, B = sum of count place^2, T = sum of totals and C = sum of place total, the line is
//   slope = level_scale (N C - A T) / D,  intercept = (T B - A C) / D,  D = reading_scale (N B - A^2)
// in readings per level and in readings at level 0.
typedef struct
{
    AnchorExactInteger samples;
    AnchorExactInteger along;
    AnchorExactInteger along_square;
    AnchorExactInteger measured;
    AnchorExactInteger cross;
} NoiseLineSums;

typedef struct
{
    AnchorExactInteger slope;
    AnchorExactInteger intercept;
    AnchorExactInteger denominator;
} NoiseLine;

void noise_line_sums_zero(NoiseLineSums *sums);

// count points at place whose readings sum to total; on a refusal the sums are unchanged
long noise_line_sums_add(NoiseLineSums *sums, unsigned long long count, unsigned long long place,
                         const AnchorExactInteger *total, EngineError *error);

// refuses where the places do not span two levels (D would be 0), a scale is 0, or a product passes the exact
// integer's width; on a refusal the line is unchanged
long noise_line_fit(const NoiseLineSums *sums, unsigned long long level_scale, unsigned long long reading_scale,
                    NoiseLine *line, EngineError *error);

// C15, the cumulant ladder, and C19, the single-electron tail (build plan item 38). The moment pass's quiet static
// blocks, each block's k-statistics read against its voxel's level over the frames of the voxel's other blocks, so a
// block's own values never set the level it is read at; then each cumulant's line over that level in lane units.
#define NOISE_LADDER_ORDERS 3u

typedef struct
{
    // the lines of k2, k3 and k4 against the level
    NoiseLine cumulant[NOISE_LADDER_ORDERS];
    unsigned long long blocks;
    unsigned long long left_out;
    // s3 >= s2^2 and s2 s4 >= s3^2, each cross-multiplied over the slopes' positive denominators
    int rising;
    int convex;
    // C19 from the k2 and k3 lines, set where s3 is not 0: O = -c3 / s3 and R^2 = (c2 s3 - c3 s2) / s3, each a
    // numerator over a positive denominator. O is the offset only where rising and convex both hold.
    int tail;
    AnchorExactInteger offset;
    AnchorExactInteger offset_denominator;
    AnchorExactInteger read_square;
    AnchorExactInteger read_square_denominator;
} NoiseLadderReading;

// refuses a volume with fewer than two whole blocks of frames, or whose blocks' levels do not span two values
long noise_ladder_volume(const unsigned short *volume, const unsigned long long extent[4], NoiseLadderReading *reading,
                         EngineError *error);

// C20, crosstalk in the neighbour correlation (build plan item 38). Along y and along x, over the same voxels (those
// whose voxel three steps on is inside the view), every frame pair's difference d': the pairs, Σ d'^2, and the
// products Σ d'(v) d'(v + s δ) for the steps s = 1, 2 and 3, C1, C2 and C3. A draw shared with each neighbour by α after
// it is made leaves V = Σ d'^2 - 2 C2, α = C1 / (2 V) and α^2 = C2 / V, which agree where C1^2 = 4 C2 V, and C3 = 0.
// The detector reads the sums exactly; how near to agreement and to 0 a reading must come is not set here.
#define NOISE_CROSSTALK_AXES 2u

#define NOISE_CROSSTALK_STEPS 3u

typedef struct
{
    unsigned long long pairs[NOISE_CROSSTALK_AXES];
    AnchorExactInteger squares[NOISE_CROSSTALK_AXES];
    AnchorExactInteger steps[NOISE_CROSSTALK_AXES][NOISE_CROSSTALK_STEPS];
    // V = Σ d'^2 - 2 C2
    AnchorExactInteger spread[NOISE_CROSSTALK_AXES];
} NoiseCrosstalkReading;

// refuses a volume of fewer than two frames or one whose products could pass 64 bits a sum
long noise_crosstalk_volume(const unsigned short *volume, const unsigned long long extent[4],
                            NoiseCrosstalkReading *reading, EngineError *error);

// C14, charge before the gain (build plan item 38). A bias series (no light, no exposure) and a dark series (no light,
// exposed for a named Δt) of one extent: over each, Σ I over every voxel-frame and Σ d^2 over every frame difference.
// With M voxel-frames and P frame differences a series, the bias mean A_b / M is O (with the fixed pattern's mean),
// and the bias E[d^2] / 2 = Q_b / (2 P) is the level-free sum R^2 + σ_J^2 + σ_kTC^2. Dark electrons enter before the
// gain, so the dark mean less the bias mean is g D Δt and the dark E[d^2] / 2 less the bias's is g^2 D Δt; g is their
// ratio. Each reading is a numerator over a positive denominator.
typedef struct
{
    AnchorExactInteger offset;
    AnchorExactInteger offset_denominator;
    AnchorExactInteger level_free;
    AnchorExactInteger level_free_denominator;
    AnchorExactInteger dark_level;
    AnchorExactInteger dark_level_denominator;
    AnchorExactInteger dark_square;
    AnchorExactInteger dark_square_denominator;
    // set where the dark mean differs from the bias mean
    int gain_read;
    AnchorExactInteger gain;
    AnchorExactInteger gain_denominator;
} NoiseChargeReading;

// refuses series of fewer than two frames, or whose squares could pass 64 bits a sum
long noise_charge_series(const unsigned short *bias, const unsigned short *dark, const unsigned long long extent[4],
                         NoiseChargeReading *reading, EngineError *error);

// C17, the structure function against the shared scale (build plan item 38). Over each voxel and its x neighbour whose
// mean level over the frames lies in 40 to 199, at each lag k of the flicker pass, every frame pair's
// y = (d_k - d_{k,x})^2 against q = (Σ_t I - Σ_t I_x)^2 = (T (L - L_x))^2 and the pair's total M = Σ_t I + Σ_t I_x:
// per lag and level bin of 8, the pairs N and the sums of M, M^2, q, q^2, M q, y, M y and q y. A scale 1 + ε_t shared
// by the whole volume moves d_k - d_{k,x} by (ε_{t+k} - ε_t) times the pair's light apart, so y rises over
// (L - L_x)^2 with slope D_a(k) = E[(ε_{t+k} - ε_t)^2], the scale's structure function, above 2 D(k), the pair's own
// noise. The own noise grows with the level, and a bin of 8 still holds a spread of it, so y is fitted against M and q
// together within each bin, the least squares of the line above over two places, pooled over the bins: with each bin's
// centred sums N Σ u v - Σ u Σ v summed over the bins as MM, QQ, MQ, MY and QY,
// D_a(k) = T^2 (MM QY - MQ MY) / (MM QQ - MQ^2), and the intercept is the pairs' mean y less D_a(k) times their mean
// (L - L_x)^2. Each reading is a numerator over a positive denominator.
typedef struct
{
    unsigned long long pairs[NOISE_FLICKER_LAGS];
    // set where q is not a line in M within every bin, so MM QQ - MQ^2 is positive
    int read[NOISE_FLICKER_LAGS];
    AnchorExactInteger slope[NOISE_FLICKER_LAGS];
    AnchorExactInteger slope_denominator[NOISE_FLICKER_LAGS];
    AnchorExactInteger intercept[NOISE_FLICKER_LAGS];
    AnchorExactInteger intercept_denominator[NOISE_FLICKER_LAGS];
} NoiseStructureReading;

// refuses a volume of fewer than two frames or two columns, of more than 65536 frames, or whose sums could pass 128
// bits
long noise_structure_volume(const unsigned short *volume, const unsigned long long extent[4],
                            NoiseStructureReading *reading, EngineError *error);

// The root noise of a box: a span of frames and a place the caller names, an object's in the cell workbook. Each term the
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
// Returns 0, or a negative value with the error filled. The driver passes the engine's, and the detector reaches no
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
