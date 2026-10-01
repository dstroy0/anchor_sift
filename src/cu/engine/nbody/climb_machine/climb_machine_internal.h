// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the climb_machine_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef CLIMB_MACHINE_INTERNAL_H
#define CLIMB_MACHINE_INTERNAL_H

#include "../../../../engine/nbody/climb_machine/climb_machine.h"
#include "engine_config.h"
#include "../../../../engine/nbody/climb_machine/spiral_table.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define CLIMB_MACHINE_BLOCK 256u

#define CLIMB_MACHINE_BUNDLE 32u

#define CLIMB_MACHINE_CANDIDATES 27u

#define CLIMB_MACHINE_TICKS 8u

#define CLIMB_MACHINE_EMPTY 0xFFFFFFFFu

#define CLIMB_MACHINE_OUTSIDE 0xFFFFFFFFu

static_assert(sizeof(unsigned int) == 4u, "climb_machine: unsigned int must be 32 bits, a label");
static_assert(sizeof(unsigned long long) == 8u, "climb_machine: unsigned long long must be 64 bits, a sign word");

struct MachineGeometry
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int weight_z;
    unsigned long long voxels;
    unsigned long long words;
};

struct ClimbMachine
{
    MachineGeometry geometry;
    unsigned int peak_capacity;
    unsigned int capacity;
    unsigned int newest;
    unsigned int land_by_mass;
    unsigned int spiral_tries;
    int *device_spiral;
    unsigned int *scratch_labels;
    unsigned int scratch_frame[2];
    unsigned int scratch_next;
    unsigned long long *positive;
    unsigned int *slot_frame;
    unsigned int *slot_leaves;
    unsigned int *slot_runs;
    unsigned int **slot_leaf_bundles;
    unsigned int **slot_bundle_first;
    unsigned int **slot_bundle_end;
    unsigned int **slot_contact_start;
    unsigned int **slot_contacts;
    size_t run_capacity;
    unsigned int *run_start;
    unsigned int *run_length;
    unsigned int *run_leaf;
    unsigned int *run_at_row;
    unsigned int *row_first;
    int *device_map;
    unsigned int *device_peaks;
    unsigned int *row_counts;
    unsigned int *device_row_counts;
    unsigned int *device_row_offsets;
    size_t unsorted_capacity;
    unsigned int *device_unsorted_start;
    unsigned int *device_unsorted_length;
    unsigned int *device_unsorted_leaf;
    unsigned int *unsorted_leaf;
    unsigned int *order;
    unsigned int *device_order;
    unsigned int *leaf_counts;
    ClimbMachinePair *pending;
    unsigned int pending_count;
    unsigned int pending_capacity;
    size_t side_capacity;
    unsigned int *side_slots;
    unsigned int *device_side_slots;
    size_t climber_capacity;
    unsigned int *climber_side;
    unsigned int *climber_peak;
    unsigned int *climber_entry_start;
    int *centers;
    unsigned int *active;
    unsigned int *landed;
    unsigned int *final_score;
    unsigned int *device_final_score;
    unsigned int *device_climber_side;
    unsigned int *device_climber_peak;
    unsigned int *device_climber_entry_start;
    int *device_centers;
    unsigned int *device_active;
    unsigned int *device_landed;
    size_t entry_capacity;
    unsigned int *entry_first;
    unsigned int *entry_end;
    unsigned int *entry_climber;
    unsigned int *device_entry_first;
    unsigned int *device_entry_end;
    unsigned int *device_entry_climber;
    unsigned int *device_scores;
    unsigned int *device_moved;
    unsigned int *pinned_moved;
    unsigned int *pinned_zero;
    cudaEvent_t blocks_done[2];
    unsigned int ran_count;
    unsigned int *box_earlier;
    unsigned int *box_later;
    unsigned int *box_leaf;
    unsigned int *box_cell_first;
    int *box_cell_shift;
    unsigned int *box_entry_first;
    unsigned int *box_target;
    unsigned int *box_count;
    unsigned int *core_earlier;
    unsigned int *core_later;
    unsigned int *core_side;
    unsigned int *core_leaf;
    unsigned int *core_match;
    int *core_lag;
    unsigned int *core_width_first;
    unsigned long long *core_fields;
};

struct MachineBoxCells
{
    const unsigned int *cell_climber;
    const unsigned int *climber_of_box;
    const int *cell_shift;
    const unsigned int *entry_first;
    unsigned int *cell_entries;
    unsigned int *cell_total;
    unsigned int *cell_raw;
    unsigned int *target;
    unsigned int *count;
    unsigned int *error;
};

__device__ static inline unsigned long long machine_bits(const unsigned long long *positive,
                                                         unsigned long long base_word, unsigned long long words,
                                                         unsigned long long bit)
{
    const unsigned long long word = bit >> 6u;
    const unsigned int shift = (unsigned int)(bit & 63ull);
    unsigned long long value = positive[base_word + word] >> shift;
    if ((shift != 0u) && ((word + 1ull) < words))
    {
        value |= positive[base_word + word + 1ull] << (64u - shift);
    }
    return value;
}

__device__ static inline unsigned int machine_ones(unsigned long long value)
{
    const unsigned long long pairs = value - ((value >> 1u) & 0x5555555555555555ull);
    const unsigned long long nibbles = (pairs & 0x3333333333333333ull) + ((pairs >> 2u) & 0x3333333333333333ull);
    const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0Full;
    return (unsigned int)((bytes * 0x0101010101010101ull) >> 56u);
}

__device__ static inline unsigned int machine_agreeing(const unsigned long long *positive, unsigned long long words,
                                                       unsigned long long own_word, unsigned long long own_bit,
                                                       unsigned long long other_word, unsigned long long other_bit,
                                                       unsigned int count)
{
    unsigned int agreeing = 0u;
    for (unsigned int done = 0u; done < count; done += 64u)
    {
        const unsigned int take = ((count - done) < 64u) ? (count - done) : 64u;
        const unsigned long long mask = (take == 64u) ? 0xFFFFFFFFFFFFFFFFull : ((1ull << take) - 1ull);
        const unsigned long long differing = (machine_bits(positive, own_word, words, own_bit + done) ^
                                              machine_bits(positive, other_word, words, other_bit + done)) &
                                             mask;
        agreeing += take - machine_ones(differing);
    }
    return agreeing;
}

__global__ void machine_score_kernel(const unsigned int *run_start, const unsigned int *run_length,
                                     const unsigned int *entry_first, const unsigned int *entry_end,
                                     const unsigned int *entry_climber, unsigned int entries,
                                     const unsigned int *climber_side, const unsigned int *side_slots,
                                     const int *centers, const unsigned int *active, const unsigned long long *positive,
                                     MachineGeometry geometry, unsigned int *scores);

__global__ void machine_decide_kernel(const unsigned int *climber_entry_start, const unsigned int *scores,
                                      unsigned int climbers, MachineGeometry geometry, int *centers,
                                      unsigned int *active, unsigned int *moved, unsigned int *final_score);

__device__ static inline unsigned int machine_leaf_at(unsigned long long voxel, unsigned long long slot,
                                                      const unsigned int *row_first, const unsigned int *run_at_row,
                                                      const unsigned int *run_start, const unsigned int *run_length,
                                                      const unsigned int *run_leaf, unsigned int run_capacity,
                                                      MachineGeometry geometry)
{
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long row = voxel / geometry.width;
    const unsigned long long base = slot * (unsigned long long)run_capacity;
    const unsigned long long offsets = slot * (rows + 1ull);
    const unsigned int first = row_first[offsets + row];
    const unsigned int end = row_first[offsets + row + 1ull];
    const unsigned int empty = (unsigned int)(end <= first);
    unsigned int low = (empty != 0u) ? 0u : first;
    unsigned int high = (empty != 0u) ? 1u : end;
    while ((high - low) > 1u)
    {
        const unsigned int middle = low + ((high - low) / 2u);
        const unsigned int at = run_at_row[base + middle];
        low = (run_start[base + at] <= (unsigned int)voxel) ? middle : low;
        high = (run_start[base + at] <= (unsigned int)voxel) ? high : middle;
    }
    const unsigned int at = run_at_row[base + low];
    const unsigned int start = run_start[base + at];
    const unsigned int covers = (unsigned int)((empty == 0u) && (start <= (unsigned int)voxel) &&
                                               ((unsigned int)voxel < (start + run_length[base + at])));
    return (covers != 0u) ? run_leaf[base + at] : CLIMB_MACHINE_OUTSIDE;
}

__global__ void machine_land_mass_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                         const unsigned int *climber_entry_start, const unsigned int *entry_first,
                                         const unsigned int *entry_end, const int *centers,
                                         const unsigned int *row_first, const unsigned int *run_at_row,
                                         const unsigned int *run_start, const unsigned int *run_length,
                                         const unsigned int *run_leaf, unsigned int run_capacity, unsigned int climbers,
                                         const int *spiral, unsigned int tries, MachineGeometry geometry,
                                         unsigned int *landed);

__global__ void machine_land_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                    const unsigned int *climber_peak, const int *centers, const unsigned int *row_first,
                                    const unsigned int *run_at_row, const unsigned int *run_start,
                                    const unsigned int *run_length, const unsigned int *run_leaf,
                                    unsigned int run_capacity, unsigned int climbers, MachineGeometry geometry,
                                    unsigned int *landed);

__global__ void machine_box_kernel(unsigned int cells, unsigned int writing, MachineBoxCells box,
                                   const unsigned int *climber_side, const unsigned int *side_slots,
                                   const unsigned int *climber_entry_start, const unsigned int *entry_first,
                                   const unsigned int *entry_end, const unsigned int *row_first,
                                   const unsigned int *run_at_row, const unsigned int *run_start,
                                   const unsigned int *run_length, const unsigned int *run_leaf,
                                   unsigned int run_capacity, const unsigned long long *positive,
                                   MachineGeometry geometry);

__global__ void machine_map_kernel(const unsigned int *peaks, unsigned int leaves, unsigned int clear, int *map);

__global__ void machine_row_kernel(const unsigned int *labels, const int *map, unsigned int rows,
                                   MachineGeometry geometry, const unsigned int *offsets, unsigned int *counts,
                                   unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf);

__global__ void machine_gather_kernel(const unsigned int *order, unsigned int runs, const unsigned int *unsorted_start,
                                      const unsigned int *unsorted_length, const unsigned int *unsorted_leaf,
                                      unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf,
                                      unsigned int *run_at_row);

int machine_launched(void);

unsigned int machine_slot_of(const ClimbMachine *machine, unsigned int frame);

int machine_grow(void **host, void **device, size_t bytes);

extern "C" int climb_machine_run(ClimbMachine *machine);

void machine_box_release(ClimbMachine *machine);

typedef struct
{
    unsigned int target;
    unsigned int count;
} MachineBoxPiece;

void machine_core_release(ClimbMachine *machine);

extern "C" void climb_machine_close(ClimbMachine *machine);

#endif
