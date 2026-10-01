// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the max_tree_device_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef MAX_TREE_DEVICE_INTERNAL_H
#define MAX_TREE_DEVICE_INTERNAL_H

#include "../../../../c/engine/nbody/max_tree/max_tree.h"

#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TREE_BLOCK 256u

#define MAX_TREE_TICKS 8u

#define MAX_TREE_JUMPS 2u

#define MAX_TREE_KEY_WORDS ((MAX_TREE_KEY_LIMBS + 1u) / 2u)

#define MAX_TREE_BUCKETS 256u

#define MAX_TREE_KEY_BYTES (ENGINE_RESIDUAL_LIMBS * 4u)

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define MAX_TREE_STATUS_CHECK(call_, evacaddr_, error_)                                                                \
    engine_status_check((int)(call_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__, (const void *)(evacaddr_),       \
                        (error_))

#define MAX_TREE_CHECK(condition_, evacaddr_, error_, kind_)                                                           \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__,                          \
                       (const void *)(evacaddr_), (error_))

__device__ static inline unsigned int max_tree_selected(const unsigned int *residual, unsigned int voxel)
{
    const unsigned int *const limbs = &residual[(size_t)voxel * ENGINE_RESIDUAL_LIMBS];
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        any |= limbs[limb];
    }
    return (unsigned int)(((limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) == 0u) && (any != 0u));
}

__device__ static inline unsigned int max_tree_below(const unsigned int *residual, unsigned int left,
                                                     unsigned int right)
{
    const unsigned int *const one = &residual[(size_t)left * ENGINE_RESIDUAL_LIMBS];
    const unsigned int *const other = &residual[(size_t)right * ENGINE_RESIDUAL_LIMBS];
    unsigned int decided = 0u;
    unsigned int below = 0u;
    for (unsigned int limb = ENGINE_RESIDUAL_LIMBS; limb > 0u; limb -= 1u)
    {
        const unsigned int differs = (unsigned int)(one[limb - 1u] != other[limb - 1u]) & (decided ^ 1u);
        below |= differs & (unsigned int)(one[limb - 1u] < other[limb - 1u]);
        decided |= differs;
    }
    return below;
}

__device__ static inline unsigned int max_tree_key_limb(const unsigned int *residual, unsigned int weaker,
                                                        unsigned int name, unsigned int limb)
{
    const unsigned int above = (unsigned int)((limb >= 1u) && (limb <= ENGINE_RESIDUAL_LIMBS));
    const unsigned int value = residual[((size_t)weaker * ENGINE_RESIDUAL_LIMBS) + ((limb - 1u) * above)];
    return (limb == 0u) ? ~name : (value * above);
}

__device__ static inline unsigned long long max_tree_key_word(const unsigned int *residual, unsigned int weaker,
                                                              unsigned int name, unsigned int word)
{
    const unsigned long long low = max_tree_key_limb(residual, weaker, name, word * 2u);
    const unsigned long long high = max_tree_key_limb(residual, weaker, name, (word * 2u) + 1u);
    return (high << 32u) | low;
}

__device__ static inline unsigned int max_tree_leads(const unsigned int *residual, unsigned int weaker,
                                                     unsigned int name, unsigned int word,
                                                     const unsigned long long *best)
{
    unsigned int ties = 1u;
    for (unsigned int above = word + 1u; above < MAX_TREE_KEY_WORDS; above += 1u)
    {
        ties &= (unsigned int)(best[above] == max_tree_key_word(residual, weaker, name, above));
    }
    return ties;
}

__global__ void max_tree_jump_kernel(unsigned int voxels, unsigned int *belongs);

__global__ void max_tree_flatten_kernel(unsigned int voxels, unsigned int *belongs);

int max_tree_contract(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                      unsigned char *faces, unsigned int *belongs, unsigned long long *strongest, unsigned int *partner,
                      unsigned char *bound, unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                      EngineError *error);

#define MAX_TREE_CHUNK 256u

__global__ void max_tree_iota_kernel(unsigned int voxels, unsigned int *order);

__global__ void max_tree_code_gather_kernel(const unsigned int *residual, const unsigned int *order,
                                            unsigned int voxels, unsigned int limb, unsigned int *keys);

__global__ void max_tree_code_flags_kernel(const unsigned int *residual, const unsigned int *order, unsigned int voxels,
                                           unsigned int *flags);

__global__ void max_tree_code_scatter_kernel(const unsigned int *residual, const unsigned int *order,
                                             const unsigned int *ranks, unsigned int voxels, unsigned int *code);

int max_tree_code_contract(const unsigned int *code, unsigned int depth, unsigned int height, unsigned int width,
                           unsigned char *faces, unsigned int *belongs, unsigned long long *best, unsigned int *partner,
                           unsigned char *bound, unsigned int *moved, unsigned int *pinned_moved,
                           cudaEvent_t *blocks_done, EngineError *error);

__global__ void max_tree_faces_differ_kernel(const unsigned char *one, const unsigned char *other, unsigned int faces,
                                             unsigned int *differ);

__global__ void max_tree_code_levels_kernel(const unsigned int *code, const unsigned char *bound, unsigned int depth,
                                            unsigned int height, unsigned int width, int *change);

__global__ void max_tree_reverse_kernel(const int *change, unsigned int top, int *reversed);

__global__ void max_tree_level_pick_kernel(const int *counts, unsigned int top, const int *maximum,
                                           unsigned int *level);

__global__ void max_tree_cc_start_kernel(const unsigned int *code, unsigned int voxels, unsigned int level,
                                         unsigned char *ranges, unsigned int *parent);

__global__ void max_tree_cc_hook_kernel(const unsigned char *ranges, unsigned int depth, unsigned int height,
                                        unsigned int width, unsigned int *parent, unsigned int *moved);

__global__ void max_tree_cc_jump_kernel(const unsigned char *ranges, unsigned int voxels, unsigned int *parent);

__global__ void max_tree_cc_flatten_kernel(const unsigned char *ranges, unsigned int voxels, unsigned int *parent);

int max_tree_cc(const unsigned char *ranges, unsigned int depth, unsigned int height, unsigned int width,
                unsigned int *parent, unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                EngineError *error);

__global__ void max_tree_roots_kernel(const unsigned char *ranges, const unsigned int *label, unsigned int voxels,
                                      unsigned int *roots);

__global__ void max_tree_peak_kernel(const unsigned int *code, const unsigned char *ranges, const unsigned int *label,
                                     unsigned int voxels, unsigned long long *best);

__global__ void max_tree_mark_kernel(const unsigned int *residual, const unsigned int *code,
                                     const unsigned char *ranges, const unsigned int *label,
                                     const unsigned long long *best, unsigned int voxels, unsigned int writing,
                                     unsigned int *at_chunk, unsigned int *slot_at, EngineBody *bodies);

__global__ void max_tree_object_census_kernel(const unsigned char *ranges, const unsigned int *label,
                                              const unsigned long long *best, const unsigned int *slot_at,
                                              unsigned int depth, unsigned int height, unsigned int width,
                                              EngineBody *bodies, unsigned int *labels);

__global__ void max_tree_pack_kernel(const unsigned int *residual, unsigned int voxels, unsigned int words,
                                     unsigned long long *packed);

__global__ void max_tree_code_values_kernel(const unsigned int *residual, const unsigned int *order,
                                            const unsigned int *flags, const unsigned int *code, unsigned int voxels,
                                            unsigned int *values);

struct MaxTreeResident
{
    size_t voxels;
    unsigned int *code;
    unsigned int *order[2];
    unsigned int *keys[2];
    void *scratch;
    size_t scratch_bytes;
    unsigned char *faces;
    unsigned int *belongs;
    unsigned long long *best;
    unsigned int *partner;
    unsigned char *bound;
    unsigned char *ranges;
    unsigned int *label;
    int *change;
    int *counts;
    int *maximum;
    unsigned int *level;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    unsigned int *roots;
    unsigned int *at_chunk;
    unsigned int *host_chunks;
    unsigned long long *packed;
    size_t body_capacity;
    EngineBody *bodies;
    size_t last_bodies;
    unsigned int top;
    unsigned int threshold;
    unsigned int last_depth;
    unsigned int last_height;
    unsigned int last_width;
    int keeping;
    unsigned int kept_current;
    unsigned int *kept_code[2];
    unsigned int *kept_values[2];
    unsigned int kept_top[2];
    unsigned int kept_ready[2];
};

extern MaxTreeResident g_max_tree_resident;

void max_tree_release_resident(MaxTreeResident *resident);

int max_tree_reserve(size_t voxels, EngineError *error);

int max_tree_grow_bodies(size_t bodies, EngineError *error);

extern int g_max_tree_profile;

void max_tree_stage(unsigned int stage, unsigned long long *mark);

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int top;
    unsigned int probes;
    const unsigned int *device_probes;
    unsigned char *ranges;
    unsigned int *label;
    unsigned int *probe_labels;
    unsigned int *roots;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    unsigned int *raw;
    MaxTreeSlideStep *steps;
    unsigned int *partitions;
    unsigned int step_capacity;
    unsigned int step_count;
    unsigned int labelings;
    EngineError *error;
} MaxTreeSlide;

#define MAX_TREE_OVERLAP_TALLIES 10u

__global__ void max_tree_overlap_threshold_kernel(const unsigned int *values, unsigned int top,
                                                  const unsigned int *value, unsigned int *threshold);

__global__ void max_tree_overlap_pairs_kernel(const unsigned char *earlier_ranges, const unsigned int *earlier_label,
                                              const unsigned char *later_ranges, const unsigned int *later_label,
                                              unsigned int depth, unsigned int height, unsigned int width, int lag_z,
                                              int lag_y, int lag_x, unsigned long long *pairs);

__global__ void max_tree_overlap_partners_kernel(const unsigned long long *sorted, unsigned int count,
                                                 unsigned int *earlier_partners, unsigned int *later_partners);

__global__ void max_tree_overlap_one_kernel(const unsigned char *ranges, const unsigned int *label,
                                            const unsigned int *partners, unsigned int voxels, unsigned int *ones);

__global__ void max_tree_overlap_backs_kernel(const unsigned long long *sorted, unsigned int count,
                                              const unsigned int *earlier_partners, const unsigned int *later_partners,
                                              unsigned int *earlier_backs, unsigned int *later_backs);

__global__ void max_tree_overlap_census_kernel(const unsigned char *ranges, const unsigned int *label,
                                               const unsigned int *partners, const unsigned int *backs,
                                               unsigned int voxels, unsigned int *census);

__global__ void max_tree_overlap_probe_kernel(const unsigned int *probe_voxels, unsigned int probes,
                                              const unsigned char *ranges, const unsigned int *label,
                                              const unsigned int *partners, const unsigned int *backs,
                                              MaxTreeOverlapProbe *out);

__global__ void max_tree_overlap_link_kernel(const unsigned int *probe_links, unsigned int links,
                                             const MaxTreeOverlapProbe *earlier, const MaxTreeOverlapProbe *later,
                                             const unsigned long long *sorted, unsigned int count,
                                             unsigned char *links_present);

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    int lag[3];
    unsigned int probe_counts[2];
    const unsigned int *probe_voxels[2];
    MaxTreeOverlapProbe *probes[2];
    const unsigned int *probe_links;
    unsigned int link_count;
    unsigned char *links_present;
    unsigned int slot[2];
    unsigned char *ranges[2];
    unsigned int *label[2];
    unsigned int *partners[2];
    unsigned int *backs[2];
    unsigned long long *pairs[2];
    void *scratch;
    size_t scratch_bytes;
    unsigned int *thresholds;
    unsigned int *tallies;
    unsigned int *moved;
    unsigned int *pinned_moved;
    cudaEvent_t blocks_done[2];
    EngineError *error;
} MaxTreeOverlap;

#endif
