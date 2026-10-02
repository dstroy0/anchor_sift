// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the knf_identity_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef KNF_IDENTITY_INTERNAL_H
#define KNF_IDENTITY_INTERNAL_H

#include "sim_camera.h"

#include "../../../../../c/engine/analysis/entropy_history/entropy_history.h"

#define KNF_KEY 0x4E424F4459ull

#define KNF_WINDOWS 16ull

#define KNF_FRAMES (1ull + ((unsigned long long)ENGINE_HISTORY_WINDOW * KNF_WINDOWS))

#define KNF_SIDE 64ull

#define KNF_FOUNDERS 10u

#define KNF_DIVISIONS 3u

#define KNF_BODIES (KNF_FOUNDERS + (2u * KNF_DIVISIONS))

#define KNF_MOTIONS 48u

#define KNF_DRAWS 19u

#define KNF_SCALES 7u

#define KNF_CONTROLS 64u

#define KNF_CONTROL_SIDE 32ull

#define KNF_FLIPS 8192u

// the controls' identified count over n volumes at 1/(draws + 1) each may exceed n p by 5 sqrt(n p), this squared over
// n p: the binomial's spread is sqrt(n p (1 - p)). At 19 draws the tolerance is 5.13 of it
#define KNF_RANGE_SQUARED 25ull

#define KNF_BOX_FIELDS 6u

#define KNF_MOTION_PURPOSE 0x4D4F5645ull

#define KNF_NULL_PURPOSE 0x4E554C4Cull

#define KNF_FLIP_PURPOSE 0x464C4950ull

#define KNF_CONTROL_PURPOSE 0x434F4E54ull

static_assert(KNF_WINDOWS <= ENGINE_HISTORY_WINDOWS_MAX, "knf_identity: the run's windows fit the history");
static_assert(KNF_BODIES <= 16u, "knf_identity: a voxel's boxes are one bit a body in 16 bits");
static_assert((1ull << (KNF_SCALES - 1u)) == KNF_SIDE, "knf_identity: the tile sizes run 1 to the side by doubling");

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} KnfWide;

typedef struct
{
    KnfWide inside;
    KnfWide seam;
    KnfWide body[KNF_BODIES];
} KnfEntangled;

typedef struct
{
    unsigned long long side;
    unsigned long long voxels;
    unsigned long long *history;
    unsigned long long *cloud;
    long long *centerd;
} KnfRecord;

typedef struct
{
    int filled;
    long long box[KNF_BOX_FIELDS];
} KnfBox;

void knf_wide_add(KnfWide *sum, long long term);

int knf_wide_equal(const KnfWide *left, const KnfWide *right);

void knf_wide_exact(const KnfWide *wide, AnchorExactInteger *value);

void knf_exact_total(const KnfEntangled *entangled, AnchorExactInteger *total);

void knf_departure_of(const AnchorExactInteger *truth, const AnchorExactInteger *drawn_sum,
                      AnchorExactInteger *departure);

void knf_scene(SimScene *scene, SimBody *body, int with_bodies);

void knf_camera(SimCamera *camera, unsigned long long key, unsigned long long pattern_range);

void knf_boxes(const SimScene *scene, KnfBox *box, unsigned short *boxes);

int knf_project(SimResults *results, const unsigned short *lanes, KnfRecord *record);

long long knf_pair(const long long *one, const long long *other);

void knf_entangle(const KnfRecord *record, const unsigned int *map, unsigned long long tile,
                  const unsigned short *boxes, KnfEntangled *result);

void knf_inside_draw(unsigned int *map, unsigned int *slot, unsigned long long side, unsigned long long tile,
                     unsigned long long key);

void knf_between_draw(unsigned int *map, unsigned int *slot, unsigned long long side, unsigned long long tile,
                      unsigned long long key);

int knf_identified(const KnfRecord *record, unsigned int *map, unsigned int *slot, unsigned long long key_base);

void knf_one_bit(SimResults *results, const unsigned short *lanes, const KnfRecord *record);

void knf_motions(SimResults *results, const unsigned short *lanes, unsigned short *moved, const KnfRecord *record,
                 KnfRecord *moved_record, unsigned int *target);

#endif
