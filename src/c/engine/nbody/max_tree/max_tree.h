// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef MAX_TREE_H
#define MAX_TREE_H

#include "../../engine_config.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define MAX_TREE_ERROR (-1)

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
        unsigned int *levels_equal;
        unsigned long long *bound_microseconds;
        unsigned long long *proved_microseconds;
        EngineError *error;
    } MaxTreeBindRequest;

    long max_tree_build(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                        MaxTree *tree);

    void max_tree_release(MaxTree *tree);

    int max_tree_valid(const unsigned int *residual, const MaxTree *tree, unsigned int levels);

    long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                              const unsigned char *bound, MaxTree *tree);

    int max_tree_equal(const MaxTree *left, const MaxTree *right);

    int max_tree_poc(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                     unsigned char *bound, unsigned int *rounds);

    int max_tree_order_agrees(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                              EngineError *error);

    long max_tree_bind(const MaxTreeBindRequest *request);

    // The tree as nodes (A2). A node is one component of one upper level set, the nodes of a tree built by
    // max_tree_build. A node's level is the dense rank of its value among the admitted values, 1 the least, and
    // `levels` is the most. Nodes are numbered in DFS order: a node's subtree is a single range [node,
    // subtree_end[node]), its parent is the node of the next lower level that holds it, a root is its own parent, and
    // `root` names each node's root. A child's level is above its parent's. `own` names each voxel's own node, the node
    // at its own level that holds it, and is MAX_TREE_ABSENT for a voxel that is not admitted. The component at level r
    // holding voxel x is the ancestor a of own[x] with level[a] >= r > level[parent[a]]: max_tree_node_at.
    typedef struct
    {
        unsigned int count;
        unsigned int levels;
        unsigned int voxels;
        unsigned int depth;
        unsigned int height;
        unsigned int width;
        unsigned int *voxel;
        unsigned int *parent;
        unsigned int *level;
        unsigned int *subtree_end;
        unsigned int *root;
        unsigned int *own;
    } MaxTreeNodes;

    typedef struct
    {
        const unsigned int *residual;
        const MaxTree *tree;
        MaxTreeNodes *nodes;
        EngineError *error;
    } MaxTreeNodesRequest;

    // the nodes of `tree`, built over `residual`; returns the node count, or MAX_TREE_ERROR with the error filled and
    // `nodes` left empty
    long max_tree_nodes(const MaxTreeNodesRequest *request);

    void max_tree_nodes_release(MaxTreeNodes *nodes);

    // the component at `level` that holds `node`'s voxels: `node` itself or its ancestor, or MAX_TREE_ABSENT where the
    // node's level is below `level`
    unsigned int max_tree_node_at(const MaxTreeNodes *nodes, unsigned int node, unsigned int level);

    // The probe partition at every level at once (A2). `sorted` lists the probes by their own nodes' DFS order, a probe
    // whose voxel is not admitted last. `own_level` is each probe's own level, 0 where its voxel is not admitted.
    // `joined[i]` is the level of the LCA of sorted probes i and i + 1, 0 where no level holds both. At level r a probe
    // is present where its own level is r or more, and two present probes are in one component exactly where every
    // joined level between them in the order is r or more. Each joined level is read in one scan of the DFS order: for
    // u before v in one tree, the LCA's level is the least level among the parents of the nodes in (u, v], since each
    // of those nodes lies under the LCA and the LCA's child toward v is one of them.
    typedef struct
    {
        const MaxTreeNodes *nodes;
        const unsigned int *probe_voxels;
        unsigned int probe_count;
        unsigned int *sorted;
        unsigned int *own_level;
        unsigned int *joined;
        EngineError *error;
    } MaxTreeProbeRequest;

    // returns the probe count, or MAX_TREE_ERROR with the error filled
    long max_tree_probe_levels(const MaxTreeProbeRequest *request);

    // one level's partition from max_tree_probe_levels: each probe's part, numbered from 0 in the sorted order, or
    // MAX_TREE_ABSENT where the probe is not present at `level`; returns the number of parts
    unsigned int max_tree_probe_partition(const unsigned int *sorted, const unsigned int *own_level,
                                          const unsigned int *joined, unsigned int probe_count, unsigned int level,
                                          unsigned int *part);

    // The own-node pair table (A2). For an earlier and a later frame's nodes over one extent and a lag v (z, y, x),
    // entry i counts the voxels x whose own node in the earlier frame is earlier[i] and whose x + v is admitted in the
    // later frame with own node later[i]. Entries are sorted by the earlier node, then the later one, each pair once.
    typedef struct
    {
        unsigned int count;
        unsigned int *earlier;
        unsigned int *later;
        unsigned long long *voxels;
    } MaxTreePairs;

    typedef struct
    {
        const MaxTreeNodes *earlier;
        const MaxTreeNodes *later;
        int lag[3];
        MaxTreePairs *pairs;
        EngineError *error;
    } MaxTreePairsRequest;

    // returns the entry count, or MAX_TREE_ERROR with the error filled and `pairs` left empty
    long max_tree_pairs(const MaxTreePairsRequest *request);

    void max_tree_pairs_release(MaxTreePairs *pairs);

    // The overlap at every pair of levels from the single table (A2). For each asked pair of nodes, a of the earlier
    // frame and b of the later, `sums` is the table summed over a's subtree and b's subtree: C_{r,r'}[A, B](v) for the
    // components A and B those nodes are, at any level each is a component at. The sums are answered together in one
    // sweep of the table.
    typedef struct
    {
        const MaxTreeNodes *earlier;
        const MaxTreeNodes *later;
        const MaxTreePairs *pairs;
        const unsigned int *earlier_nodes;
        const unsigned int *later_nodes;
        unsigned int asked;
        unsigned long long *sums;
        EngineError *error;
    } MaxTreeOverlapSumsRequest;

    // returns the number of sums, or MAX_TREE_ERROR with the error filled
    long max_tree_overlap_sums(const MaxTreeOverlapSumsRequest *request);

    typedef struct
    {
        const unsigned int *device_residual;
        unsigned int depth;
        unsigned int height;
        unsigned int width;
        unsigned int capacity;
        EngineBody *bodies;
        unsigned int *labels;
        unsigned long long *positive_words;
        unsigned int grade;
        unsigned int *faces_differ;
        unsigned int *level_code;
        unsigned int *proof_count;
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
        unsigned int step_capacity;
        unsigned int *step_count;
        unsigned int *top_level;
        unsigned int *threshold;
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
        unsigned char *links_present;
        MaxTreeOverlapStep *steps;
        unsigned int step_capacity;
        unsigned int *step_count;
        EngineError *error;
    } MaxTreeOverlapRequest;

    long max_tree_overlap(const MaxTreeOverlapRequest *request);

    void max_tree_profile_report(void);

#ifdef __cplusplus
}
#endif

#endif
