// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TRACK_H
#define TRACK_H

#include "climb_machine.h"
#include "engine.h"

#include <stdio.h>

static const unsigned int SMOOTH_ORDERS[3] = {2u, 34u, 34u};

static const unsigned int BACKGROUND_ORDERS[3] = {6u, 96u, 96u};

static const unsigned int AXIS_WEIGHTS[3] = {16u, 1u, 1u};

#define LINK_SWEEP_STEPS 12u

#define LINK_MAGNITUDE_BITS 40u

#define LINK_MAGNITUDE_MASK ((1ull << LINK_MAGNITUDE_BITS) - 1ull)

static_assert(((unsigned long long)LINK_SWEEP_STEPS << LINK_MAGNITUDE_BITS) != 0ull,
              "track_driver: the swept step must stay inside an unsigned long long");

typedef struct
{
    int pick;
    int share;
    int agree;
    int unbound;
    int cast;
    int parallax;
    int arc;
    int settle;
    int focus;
    int web;
    int damp;
    int dish;
    int vote;
    int mutual;
    int tower;
    int mass;
    int forest;
    int cohere;
    int accrue;
    int merge_split;
    int merge_target;
    int forward_only;
    int resolve;
    int keep_view;
    int climb;
    int sticky;
    int motion_check;
    unsigned int null_draws;
    int floor_entropy;
    unsigned int arms;
    unsigned int spiral;
    int print_match;
    const CycleRecord *print_pair;
    const unsigned int *prints;
    unsigned int print_limbs;
    int velocity;
    const CycleRecord *velocity_record;
    const EngineRecordRequest *velocity_imprint;
    int mass_band;
    int division;
    const CycleRecord *division_record;
    const EngineRecordRequest *division_imprint;
    int marginal;
    int box;
    int core;
    int box_history;
    unsigned int unit_sweep;
    int contact_side;
    const CycleRecord *contact_difference_record;
    const EngineRecordRequest *contact_difference_imprint;
    const CycleRecord *contact_kept_record;
    const EngineRecordRequest *contact_kept_imprint;
    const unsigned int *flattened;
    unsigned int flattened_limbs;
    unsigned int flattened_samples;
    char *const *flattened_names;
    const unsigned long long *flattened_start;
    FILE *coherence;
    FILE *edges;
    FILE *pool;
    FILE *nodes;
    const char *export_directory;
    bool object;
    const char *object_directory;
    const char *vis_directory;
    FILE *vis_index;
    const char *cfg_text;
    size_t cfg_length;
} TreeRules;

typedef struct
{
    unsigned int node_count;
    unsigned int edge_count;
    long long *node_identity;
    int *node_coordinates;
    long long *edge_ends;
} AnswerKey;

typedef struct
{
    unsigned int time;
    unsigned int leaf_count;
    unsigned int *peaks;
    unsigned int *sizes;
    unsigned long long *sums;
    unsigned long long *moments;
    unsigned int *exposed;
    unsigned int *touches;
    unsigned int *body_id;
    unsigned int *body_parent;
    unsigned int *body_state;
    unsigned int *contact_faces;
    unsigned int *extents;
    unsigned int joined_count;
    unsigned int *joined;
    int lag_to_next[3];
    unsigned int step_back;
    unsigned int step_next;
    int *forward;
    int *backward;
    int *forward_lag;
    int *backward_lag;
    int *check_forward_lag;
    int *check_backward_lag;
    unsigned int *forward_held;
    unsigned int null_count;
    unsigned int arm_count;
    int *arm_forward;
    unsigned int *null_held;
    unsigned int triple_count;
    unsigned int *triple_start;
    unsigned int *triple_after;
    unsigned int *triple_shared;
    unsigned int *triple_still;
    unsigned int object_count;
    unsigned int *held_target;
    unsigned int *held_count;
    unsigned int *held_rounds;
    unsigned int *object_of;
    unsigned int *member_start;
    unsigned int *members;
    unsigned int *link_start;
    unsigned int *link_target;
    unsigned int *pool_start;
    unsigned int *pool_target;
    unsigned int *pool_weight;
    unsigned long long *pool_cost;
} TreeFrame;

typedef struct
{
    unsigned long long correct;
    unsigned long long branched;
    unsigned long long wrong;
    unsigned long long unlinked;
    unsigned long long missed;
} EdgeTally;

typedef struct
{
    unsigned long long read;
    unsigned long long bodies;
    unsigned long long ties;
    unsigned long long motion;
    unsigned long long landing;
    unsigned long long store;
    unsigned long long climb;
    unsigned long long overlap;
} StageClock;

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int peak_room;
    unsigned short *volume;
    unsigned int *peak_indices;
    unsigned int *sizes;
    unsigned long long *sums;
    unsigned int *peak_limbs;
    EngineBody *bodies;
    unsigned int pair_room;
    unsigned int *adjacency;
    unsigned int *joined;
    unsigned int *labels[2];
    unsigned long long *positive[2];
    unsigned int overlap_room;
    unsigned int *overlap_before;
    unsigned int *overlap_after;
    unsigned int *overlap_shared;
    int *leaf_at_peak[2];
    unsigned int *leaf_start[2];
    unsigned int *leaf_voxels[2];
    ClimbMachine *machine;
    unsigned int unit_sweep;
} EngineBuffers;

void track_error_report(const char *what, const EngineError *error);

int track_frame_bodies(EngineBuffers *buffers, unsigned int slot, TreeFrame *frame);

void track_group_voxels(EngineBuffers *buffers, unsigned int slot, const unsigned int *labels, const TreeFrame *frame);

#define WEB_MEMBERS 24u

#define DAMP_DEVIATIONS 3ull

typedef struct
{
    unsigned int frame_count;
    TreeFrame *frames;
    unsigned int node_count;
    unsigned int *node_offset;
    unsigned int *node_frame;
} NodeIndex;

static const char *const EDGE_STATUS_NAMES[5] = {"correct", "branched", "wrong", "nolink", "missed"};

typedef struct
{
    const char *sample;
    const unsigned short *volume;
    const AnswerKey *key;
    const TreeFrame *frames;
    unsigned int frame_count;
    const unsigned int *node_offset;
    const unsigned int *unified_of;
    unsigned int unified_count;
    const int *node_leaf;
    const int *tree_index_of_time;
    unsigned int volume_frames;
    const signed char *edge_status;
    const unsigned int *unified_start;
    const unsigned long long *unified_link;
    const char *vis_directory;
    FILE *vis_index;
    const unsigned int *unified_first;
} CoherenceInputs;

#define BODY_NONE 0xFFFFFFFFu

#define BODY_ENTERED 0x001u

#define BODY_PRESENT 0x002u

#define BODY_APPEARED 0x004u

#define BODY_SPLIT 0x008u

#define BODY_MERGED 0x010u

#define BODY_LEFT 0x020u

#define BODY_ENDED 0x040u

#define BODY_VANISHED 0x080u

#define BODY_ABSORBED 0x100u

#endif
