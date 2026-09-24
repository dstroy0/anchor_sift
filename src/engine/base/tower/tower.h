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
// the high bits pass through; the map is a bijection on the coefficient word and tower_lower replays
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

typedef struct
{
    const unsigned short *device_lanes;
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

#ifdef __cplusplus
}
#endif

#endif
