// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the root_universal_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef ROOT_UNIVERSAL_INTERNAL_H
#define ROOT_UNIVERSAL_INTERNAL_H

// The root universal: the tower with reversible lookup edges sandwiched between its floors, run on
// camera-law volumes. Three measurements: the root stays exact (random edge programs rebuild every lane
// through the full crystal path of lift, code, wipe, decode, lower); edges fold in order (two edges on
// one floor produce the same crystal as the single table that composes them, and a floor between them blocks
// the fold); and the price (what an unfitted edge costs the magnitude coder, by table width and floor).

#include "sim_camera.h"

#include "../../../../../c/engine/analysis/compression/compression.h"
#include "../../../../../c/engine/analysis/tower/tower.h"

#define ROOT_KEY 0x524F4F54ull

#define ROOT_FOUNDER_PURPOSE 0x464F554Eull

#define ROOT_PROGRAM_PURPOSE 0x50524F47ull

#define ROOT_FOLD_PURPOSE 0x464F4C44ull

#define ROOT_COST_PURPOSE 0x434F5354ull

#define ROOT_FOUNDERS 6u

#define ROOT_EXTENTS 2u

#define ROOT_EXACT_VOLUMES 24u

#define ROOT_FOLD_VOLUMES 8u

#define ROOT_COST_VOLUMES 8u

#define ROOT_EDGES_MAX 8u

#define ROOT_EDGES_DRAWN_MAX 6u

#define ROOT_BITS_DRAWN_MAX 12u

#define ROOT_COST_WIDTHS 4u

#define ROOT_PLACES 4u

#define ROOT_FOLD_BITS 8u

#define ROOT_FOLD_FLOOR 1u

#define ROOT_TABLE_CAPACITY (1u << TOWER_EDGE_INDEX_BITS_MAX)

typedef struct
{
    SimScene scene;
    SimBody body[ROOT_FOUNDERS];
    unsigned long long extent[4];
    unsigned long long lanes;
    unsigned int floors;
    unsigned short *host;
    unsigned short *device;
    unsigned short *rebuilt;
} RootVolume;

typedef struct
{
    unsigned int *table[ROOT_EDGES_MAX];
    TowerEdge edge[ROOT_EDGES_MAX];
    unsigned int count;
} RootProgram;

unsigned long long root_region(const unsigned long long extent[4], unsigned int floor);

void root_permutation(unsigned int *table, unsigned int bits, unsigned long long key);

void root_program_draw(RootProgram *program, unsigned int floors, unsigned long long key, int range_widest);

void root_program_place(RootProgram *program, unsigned int bits, unsigned int first, unsigned int last,
                        unsigned long long key);

int root_volume_open(SimResults *results, RootVolume *volume, const unsigned long long extent[4]);

void root_volume_close(RootVolume *volume);

int root_volume_render(SimResults *results, RootVolume *volume, const SimCamera *camera);

int root_lift_crystal(SimResults *results, const RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
                      int *crystal);

int root_crystal_trip(SimResults *results, RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
                      int *crystal, unsigned long long *bits, int *exact);

#endif
