// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TOWER_H
#define TOWER_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TOWER_REFUSED (-1L)

// A reversible lookup edge stands between two tower floors. It permutes the low `index_bits` of every
// approximation coefficient at floor `floor` through `forward`, a permutation of [0, 1 << index_bits);
// the high bits pass through, so the map is a bijection on the coefficient word and tower_lower replays
// its inverse in reverse order. This is the engine's nonlinear edge (kolmogorov_arnold.md) folded into
// the reversible tower: the tower keeps the crystal exactly invertible, the edge makes it universal over
// the coefficient alphabet. `floor` runs 0..floors: floor k acts on the approximation just before level
// k's lifting, and floor == floors acts on the fully collapsed floor.
#define TOWER_EDGE_INDEX_BITS_MOST 20u

typedef struct
{
    unsigned int floor;
    unsigned int index_bits;
    const unsigned int *forward;
} TowerEdge;

// The lattice lifted is `device_lanes`, 16-bit samples, or, where `device_values` is set, a lattice of ints read
// instead, such as a residual left below zero; its values past ENGINE_COEFFICIENT_LIMIT refuse the lift as the
// coefficients' do.
typedef struct
{
    const unsigned short *device_lanes;
    const int *device_values;
    unsigned long long extent[4];
    const int **coefficients;
    unsigned int **scratch;
    unsigned int *floors;
    const TowerEdge *edges;
    unsigned int edge_count;
    EngineError *error;
} TowerLiftRequest;

long tower_lift(const TowerLiftRequest *request);

long tower_room(const unsigned long long extent[4], int **coefficients, EngineError *error);

// the device bytes the tower holds for a lattice of `lanes` values: its one pool, the coefficients and the scratch
// as ints beside the flag and the mismatch count, rounded to the page; 0 for no lanes or a count no pool could hold.
// The pool is kept at the most lanes asked, so a job that lifts or lowers several lattices holds it for the largest.
unsigned long long tower_hold_bytes(unsigned long long lanes);

typedef struct
{
    const unsigned short *device_lanes;
    unsigned long long extent[4];
    unsigned long long *mismatches;
    const unsigned short **device_rebuilt;
    unsigned short *rebuilt;
    const TowerEdge *edges;
    unsigned int edge_count;
    EngineError *error;
} TowerLowerRequest;

long tower_lower(const TowerLowerRequest *request);

// The wave transform's ruleset. A line of values splits into two bands, the lows (its even values) and the highs (its
// odd), and a lifting step moves one band by a rounded sum over the other:
//     target[a] += sign * floor((rounding + sum_k weight_k * other[a + offset_k]) / 2^shift),
// an index past either end of `other` taken at that end. A ruleset is its lifting steps in order; the transform runs
// them along every line of every level, and its inverse runs them last first with each sign turned, so every ruleset
// is invertible exactly. The kernels' 5/3 is two steps: the highs less floor((x_2j + x_(2j+2)) / 2), then the lows
// plus floor((d_(j-1) + d_j + 2) / 4).
#define TOWER_BAND_LOW 0u

#define TOWER_BAND_HIGH 1u

#define TOWER_RULE_TAPS_MOST 8u

#define TOWER_RULE_SHIFT_MOST 30u

typedef struct
{
    unsigned int target;
    int sign;
    unsigned int taps;
    int offset[TOWER_RULE_TAPS_MOST];
    int weight[TOWER_RULE_TAPS_MOST];
    unsigned int rounding;
    unsigned int shift;
} TowerLiftingStep;

// T and T^-1 as record floors (engine_table.md item 8, A13): the ruleset passed through the extent, one record step
// at a time, into a caller's program, so a program runs T, T^-1, or an operation read through T^-1, as one stack on
// the record machine, one block of the lattice to a lane. `rules` and `rule_count` are the ruleset; left zero, it is
// the 5/3 tower_lift and tower_lower run as kernels. `extent` is the block's, t, z, y and x, and every position's
// register is named in that order: `in_registers` the register holding each value going in, any earlier step, and
// `out_registers` the register holding each value coming out. tower_record_lift leaves the crystal where tower_lift
// leaves its coefficients, each level's lows first along every axis and its highs after them; tower_record_lower
// leaves the samples. A weight other than 1 is a product by a constant, and a floor v / 2^k is
// EXACT_QUOTIENT(v - AND(v, 2^k - 1), 2^k), toward minus infinity as the kernels' shift; each constant is one step,
// laid where it is first read. No edge is laid. The steps go in at `*count`, which is left past them. With `steps`
// NULL nothing is written but the count and the out registers, which sizes a program before it is held; with `steps`
// set, a program past `step_room` is refused and the count left where it was.
typedef struct
{
    unsigned long long extent[4];
    const TowerLiftingStep *rules;
    unsigned int rule_count;
    const unsigned int *in_registers;
    unsigned int *out_registers;
    EngineRecordStep *steps;
    unsigned int step_room;
    unsigned int *count;
    EngineError *error;
} TowerRecordRequest;

long tower_record_lift(const TowerRecordRequest *request);

long tower_record_lower(const TowerRecordRequest *request);

#ifdef __cplusplus
}
#endif

#endif
