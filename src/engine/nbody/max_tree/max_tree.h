// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef MAX_TREE_H
#define MAX_TREE_H

#include "engine_config.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_TREE_REFUSED (-1)

#define MAX_TREE_ABSENT 0xFFFFFFFFu

#define MAX_TREE_KEY_LIMBS (ENGINE_RESIDUAL_LIMBS + 1u)

typedef struct
{
    unsigned int voxels;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int admitted;
    unsigned int *parent;
    unsigned int *order;
} MaxTree;

typedef struct
{
    const unsigned int *residual;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    const unsigned int *levels;
    unsigned int level_count;
    unsigned char *bound;
    unsigned int *rounds;
    unsigned int *levels_held;
    unsigned long long *bound_microseconds;
    unsigned long long *proved_microseconds;
    EngineError *error;
} MaxTreeBindRequest;

long max_tree_build(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                    MaxTree *tree);

void max_tree_release(MaxTree *tree);

int max_tree_holds(const unsigned int *residual, const MaxTree *tree, unsigned int levels);

long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width, const unsigned char *bound, MaxTree *tree);

int max_tree_equal(const MaxTree *left, const MaxTree *right);

int max_tree_poc(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                 unsigned char *bound, unsigned int *rounds);

int max_tree_order_agrees(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width, EngineError *error);

long max_tree_bind(const MaxTreeBindRequest *request);

typedef struct
{
    const unsigned int *device_residual;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int room;
    EngineBody *bodies;
    unsigned int *labels;
    unsigned long long *positive_words;
    unsigned int grade;
    unsigned int *faces_differ;
    unsigned int *level_code;
    unsigned int *proof_held;
    EngineError *error;
} MaxTreeObjectsRequest;

long max_tree_objects(const MaxTreeObjectsRequest *request);

#define MAX_TREE_FIELD_MOMENT_ZZ 0u
#define MAX_TREE_FIELD_MOMENT_YY 1u
#define MAX_TREE_FIELD_MOMENT_XX 2u
#define MAX_TREE_FIELD_MOMENT_ZY 3u
#define MAX_TREE_FIELD_MOMENT_ZX 4u
#define MAX_TREE_FIELD_MOMENT_YX 5u
#define MAX_TREE_FIELD_SUM_Z 6u
#define MAX_TREE_FIELD_SUM_Y 7u
#define MAX_TREE_FIELD_SUM_X 8u
#define MAX_TREE_FIELD_PEAK 9u
#define MAX_TREE_FIELD_TOUCHES 10u
#define MAX_TREE_FIELD_MASS 11u
#define MAX_TREE_FIELD_LEVEL 12u
#define MAX_TREE_FIELD_FRAME 13u
#define MAX_TREE_FIELD_SAMPLE 14u
#define MAX_TREE_FIELDS 15u

typedef struct
{
    unsigned int bits[MAX_TREE_FIELDS];
    unsigned int offset[MAX_TREE_FIELDS];
    unsigned int total_bits;
    unsigned int limbs;
} MaxTreeLayout;

void max_tree_layout(unsigned int depth, unsigned int height, unsigned int width, unsigned int frames,
                     unsigned int samples, MaxTreeLayout *layout);

typedef struct
{
    const MaxTreeLayout *layout;
    unsigned int sample;
    unsigned int frame;
    unsigned int *device_magnitudes;
    unsigned long long *mismatches;
    EngineError *error;
} MaxTreePackRequest;

long max_tree_pack(const MaxTreePackRequest *request);

typedef struct
{
    unsigned int level;
    unsigned int components;
} MaxTreeSlideStep;

typedef struct
{
    const unsigned int *probe_voxels;
    unsigned int probe_count;
    MaxTreeSlideStep *steps;
    unsigned int *partitions;
    unsigned int step_room;
    unsigned int *step_count;
    unsigned int *top_level;
    unsigned int *cut_level;
    unsigned int *labelings;
    EngineError *error;
} MaxTreeSlideRequest;

long max_tree_slide(const MaxTreeSlideRequest *request);

int max_tree_keep_frames(void);

typedef struct
{
    unsigned int origin;
    unsigned int level;
    unsigned int earlier_code;
    unsigned int later_code;
    unsigned int earlier_components;
    unsigned int later_components;
    unsigned int earlier_one;
    unsigned int later_one;
    unsigned int earlier_unpaired;
    unsigned int earlier_mutual;
    unsigned int earlier_forked;
    unsigned int later_unpaired;
    unsigned int later_mutual;
    unsigned int later_forked;
} MaxTreeOverlapStep;

typedef struct
{
    unsigned int root;
    unsigned int degree;
    unsigned int backs;
} MaxTreeOverlapProbe;

typedef struct
{
    int lag[3];
    const unsigned int *earlier_levels;
    unsigned int earlier_level_count;
    const unsigned int *later_levels;
    unsigned int later_level_count;
    const unsigned int *probe_voxels[2];
    unsigned int probe_counts[2];
    const unsigned int *probe_links;
    unsigned int link_count;
    MaxTreeOverlapProbe *probes;
    unsigned char *links_held;
    MaxTreeOverlapStep *steps;
    unsigned int step_room;
    unsigned int *step_count;
    EngineError *error;
} MaxTreeOverlapRequest;

long max_tree_overlap(const MaxTreeOverlapRequest *request);

void max_tree_profile_report(void);

#ifdef __cplusplus
}
#endif

#endif
