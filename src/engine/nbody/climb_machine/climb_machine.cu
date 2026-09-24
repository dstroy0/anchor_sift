// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "climb_machine.h"
#include "engine_config.h"
#include "spiral_table.h"

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
    unsigned int peak_room;
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
    unsigned int **slot_bundle_past;
    unsigned int **slot_contact_start;
    unsigned int **slot_contacts;
    size_t run_room;
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
    size_t cut_room;
    unsigned int *device_cut_start;
    unsigned int *device_cut_length;
    unsigned int *device_cut_leaf;
    unsigned int *cut_leaf;
    unsigned int *order;
    unsigned int *device_order;
    unsigned int *leaf_counts;
    ClimbMachinePair *pending;
    unsigned int pending_count;
    unsigned int pending_room;
    size_t side_room;
    unsigned int *side_slots;
    unsigned int *device_side_slots;
    size_t climber_room;
    unsigned int *climber_side;
    unsigned int *climber_peak;
    unsigned int *climber_entry_start;
    int *centers;
    unsigned int *active;
    unsigned int *landed;
    unsigned int *held;
    unsigned int *device_held;
    unsigned int *device_climber_side;
    unsigned int *device_climber_peak;
    unsigned int *device_climber_entry_start;
    int *device_centers;
    unsigned int *device_active;
    unsigned int *device_landed;
    size_t entry_room;
    unsigned int *entry_first;
    unsigned int *entry_past;
    unsigned int *entry_climber;
    unsigned int *device_entry_first;
    unsigned int *device_entry_past;
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
    unsigned int *refused;
};

__device__ static unsigned long long machine_bits(const unsigned long long *positive, unsigned long long base_word,
                                                  unsigned long long words, unsigned long long bit)
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

__device__ static unsigned int machine_ones(unsigned long long value)
{
    const unsigned long long pairs = value - ((value >> 1u) & 0x5555555555555555ull);
    const unsigned long long nibbles = (pairs & 0x3333333333333333ull) + ((pairs >> 2u) & 0x3333333333333333ull);
    const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0Full;
    return (unsigned int)((bytes * 0x0101010101010101ull) >> 56u);
}

__device__ static unsigned int machine_agreeing(const unsigned long long *positive, unsigned long long words,
                                                unsigned long long own_word, unsigned long long own_bit,
                                                unsigned long long other_word, unsigned long long other_bit,
                                                unsigned int count)
{
    unsigned int agreeing = 0u;
    for (unsigned int done = 0u; done < count; done += 64u)
    {
        const unsigned int take = ((count - done) < 64u) ? (count - done) : 64u;
        const unsigned long long mask = (take == 64u) ? 0xFFFFFFFFFFFFFFFFull : ((1ull << take) - 1ull);
        const unsigned long long differing = (machine_bits(positive, own_word, words, own_bit + done)
                                              ^ machine_bits(positive, other_word, words, other_bit + done)) & mask;
        agreeing += take - machine_ones(differing);
    }
    return agreeing;
}

__global__ static void machine_score_kernel(const unsigned int *run_start, const unsigned int *run_length,
                                            const unsigned int *entry_first, const unsigned int *entry_past,
                                            const unsigned int *entry_climber, unsigned int entries,
                                            const unsigned int *climber_side, const unsigned int *side_slots,
                                            const int *centers, const unsigned int *active,
                                            const unsigned long long *positive, MachineGeometry geometry,
                                            unsigned int *scores)
{
    const unsigned int entry = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (entry >= entries)
    {
        return;
    }
    const unsigned int climber = entry_climber[entry];
    if (active[climber] == 0u)
    {
        return;
    }
    const unsigned int side = climber_side[climber];
    const unsigned long long own_word = (unsigned long long)side_slots[2u * side] * geometry.words;
    const unsigned long long other_word = (unsigned long long)side_slots[(2u * side) + 1u] * geometry.words;
    const int *const center = &centers[3u * climber];
    const unsigned int plane = geometry.height * geometry.width;
    unsigned int counts[CLIMB_MACHINE_CANDIDATES];
    for (unsigned int candidate = 0u; candidate < CLIMB_MACHINE_CANDIDATES; candidate += 1u)
    {
        counts[candidate] = 0u;
    }
    for (unsigned int run = entry_first[entry]; run < entry_past[entry]; run += 1u)
    {
        const unsigned int start = run_start[run];
        const long long length = (long long)run_length[run];
        const unsigned int rest = start % plane;
        const long long base_z = (long long)(start / plane) + (long long)center[0];
        const long long base_y = (long long)(rest / geometry.width) + (long long)center[1];
        const long long base_x = (long long)(rest % geometry.width) + (long long)center[2];
        unsigned int candidate = 0u;
        for (long long step_z = -1ll; step_z <= 1ll; step_z += 1ll)
        {
            const long long z = base_z + step_z;
            const int inside_z = (z >= 0ll) && (z < (long long)geometry.depth);
            for (long long step_y = -1ll; step_y <= 1ll; step_y += 1ll)
            {
                const long long y = base_y + step_y;
                const int inside_y = (y >= 0ll) && (y < (long long)geometry.height);
                for (long long step_x = -1ll; step_x <= 1ll; step_x += 1ll)
                {
                    const long long x = base_x + step_x;
                    const long long first = (x < 0ll) ? -x : 0ll;
                    const long long width_left = (long long)geometry.width - x;
                    const long long past = (width_left < length) ? width_left : length;
                    if ((inside_z != 0) && (inside_y != 0) && (first < past))
                    {
                        const unsigned long long row = (unsigned long long)((z * (long long)geometry.height + y)
                                                                            * (long long)geometry.width);
                        counts[candidate] += machine_agreeing(positive, geometry.words, own_word,
                                                              (unsigned long long)start + (unsigned long long)first,
                                                              other_word, row + (unsigned long long)(x + first),
                                                              (unsigned int)(past - first));
                    }
                    candidate += 1u;
                }
            }
        }
    }
    for (unsigned int candidate = 0u; candidate < CLIMB_MACHINE_CANDIDATES; candidate += 1u)
    {
        scores[((unsigned long long)entry * CLIMB_MACHINE_CANDIDATES) + candidate] = counts[candidate];
    }
}

__global__ static void machine_decide_kernel(const unsigned int *climber_entry_start, const unsigned int *scores,
                                             unsigned int climbers, MachineGeometry geometry, int *centers,
                                             unsigned int *active, unsigned int *moved, unsigned int *held)
{
    const unsigned int climber = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((climber >= climbers) || (active[climber] == 0u))
    {
        return;
    }
    long long sums[CLIMB_MACHINE_CANDIDATES];
    for (unsigned int candidate = 0u; candidate < CLIMB_MACHINE_CANDIDATES; candidate += 1u)
    {
        sums[candidate] = 0ll;
    }
    for (unsigned int entry = climber_entry_start[climber]; entry < climber_entry_start[climber + 1u]; entry += 1u)
    {
        for (unsigned int candidate = 0u; candidate < CLIMB_MACHINE_CANDIDATES; candidate += 1u)
        {
            sums[candidate] += (long long)scores[((unsigned long long)entry * CLIMB_MACHINE_CANDIDATES) + candidate];
        }
    }
    int *const center = &centers[3u * climber];
    const long long here[3] = {(long long)center[0], (long long)center[1], (long long)center[2]};
    long long best[3] = {here[0], here[1], here[2]};
    long long best_score = sums[13];
    unsigned long long best_length = 0ull;
    int stepped = 0;
    unsigned int candidate = 0u;
    for (long long step_z = -1ll; step_z <= 1ll; step_z += 1ll)
    {
        for (long long step_y = -1ll; step_y <= 1ll; step_y += 1ll)
        {
            for (long long step_x = -1ll; step_x <= 1ll; step_x += 1ll)
            {
                const long long lag[3] = {here[0] + step_z, here[1] + step_y, here[2] + step_x};
                const unsigned long long length = (unsigned long long)geometry.weight_z * (unsigned long long)(lag[0] * lag[0])
                                                + (unsigned long long)(lag[1] * lag[1])
                                                + (unsigned long long)(lag[2] * lag[2]);
                if ((candidate != 13u)
                 && ((sums[candidate] > best_score)
                     || ((stepped != 0) && (sums[candidate] == best_score) && (length < best_length))))
                {
                    best_score = sums[candidate];
                    best_length = length;
                    best[0] = lag[0];
                    best[1] = lag[1];
                    best[2] = lag[2];
                    stepped = 1;
                }
                candidate += 1u;
            }
        }
    }
    if (stepped != 0)
    {
        center[0] = (int)best[0];
        center[1] = (int)best[1];
        center[2] = (int)best[2];
        moved[0] = 1u;
    }
    else
    {
        active[climber] = 0u;
        held[climber] = (unsigned int)sums[13];
    }
}

__device__ static unsigned int machine_leaf_at(unsigned long long voxel, unsigned long long slot,
                                               const unsigned int *row_first, const unsigned int *run_at_row,
                                               const unsigned int *run_start, const unsigned int *run_length,
                                               const unsigned int *run_leaf, unsigned int run_room,
                                               MachineGeometry geometry)
{
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long row = voxel / geometry.width;
    const unsigned long long base = slot * (unsigned long long)run_room;
    const unsigned long long offsets = slot * (rows + 1ull);
    const unsigned int first = row_first[offsets + row];
    const unsigned int past = row_first[offsets + row + 1ull];
    const unsigned int empty = (unsigned int)(past <= first);
    unsigned int low = (empty != 0u) ? 0u : first;
    unsigned int high = (empty != 0u) ? 1u : past;
    while ((high - low) > 1u)
    {
        const unsigned int middle = low + ((high - low) / 2u);
        const unsigned int at = run_at_row[base + middle];
        low = (run_start[base + at] <= (unsigned int)voxel) ? middle : low;
        high = (run_start[base + at] <= (unsigned int)voxel) ? high : middle;
    }
    const unsigned int at = run_at_row[base + low];
    const unsigned int start = run_start[base + at];
    const unsigned int covers = (unsigned int)((empty == 0u) && (start <= (unsigned int)voxel)
                                               && ((unsigned int)voxel < (start + run_length[base + at])));
    return (covers != 0u) ? run_leaf[base + at] : CLIMB_MACHINE_OUTSIDE;
}

__global__ static void machine_land_mass_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                                const unsigned int *climber_entry_start,
                                                const unsigned int *entry_first, const unsigned int *entry_past,
                                                const int *centers, const unsigned int *row_first,
                                                const unsigned int *run_at_row, const unsigned int *run_start,
                                                const unsigned int *run_length, const unsigned int *run_leaf,
                                                unsigned int run_room, unsigned int climbers,
                                                const int *spiral, unsigned int tries,
                                                MachineGeometry geometry, unsigned int *landed)
{
    const unsigned int climber = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (climber >= climbers)
    {
        return;
    }
    const unsigned int side = climber_side[climber];
    const unsigned long long other = (unsigned long long)side_slots[(2u * side) + 1u];
    const int *const center = &centers[3u * climber];
    const unsigned int plane = geometry.height * geometry.width;
    unsigned int best_leaf = CLIMB_MACHINE_OUTSIDE;
    unsigned int best_agreed = 0u;
    for (unsigned int attempt = 0u; attempt < tries; attempt += 1u)
    {
        const int lag_z = center[0] + ((attempt == 0u) ? 0 : spiral[3u * (attempt - 1u)]);
        const int lag_y = center[1] + ((attempt == 0u) ? 0 : spiral[(3u * (attempt - 1u)) + 1u]);
        const int lag_x = center[2] + ((attempt == 0u) ? 0 : spiral[(3u * (attempt - 1u)) + 2u]);
        unsigned int candidate = CLIMB_MACHINE_OUTSIDE;
        unsigned int count = 0u;
        unsigned int agreed = 0u;
        for (unsigned int walk = 0u; walk < 2u; walk += 1u)
        {
            for (unsigned int entry = climber_entry_start[climber];
                 entry < climber_entry_start[climber + 1u]; entry += 1u)
            {
                for (unsigned int run = entry_first[entry]; run < entry_past[entry]; run += 1u)
                {
                    const unsigned int start = run_start[run];
                    const unsigned int length = run_length[run];
                    const unsigned int rest = start % plane;
                    const long long z = (long long)(start / plane) + (long long)lag_z;
                    const long long y = (long long)(rest / geometry.width) + (long long)lag_y;
                    const long long base_x = (long long)(rest % geometry.width) + (long long)lag_x;
                    const int inside = (z >= 0ll) && (z < (long long)geometry.depth)
                                    && (y >= 0ll) && (y < (long long)geometry.height);
                    for (unsigned int step = 0u; (inside != 0) && (step < length); step += 1u)
                    {
                        const long long x = base_x + (long long)step;
                        if ((x < 0ll) || (x >= (long long)geometry.width))
                        {
                            continue;
                        }
                        const unsigned long long voxel =
                            (unsigned long long)((z * (long long)geometry.height + y)
                                                 * (long long)geometry.width + x);
                        const unsigned int reached = machine_leaf_at(voxel, other, row_first, run_at_row,
                                                                      run_start, run_length, run_leaf,
                                                                      run_room, geometry);
                        const unsigned int votes = (unsigned int)(reached != CLIMB_MACHINE_OUTSIDE);
                        const unsigned int empty = (unsigned int)(count == 0u);
                        const unsigned int agrees = (unsigned int)(reached == candidate);
                        candidate = ((walk == 0u) && (votes != 0u) && (empty != 0u)) ? reached : candidate;
                        count = ((walk != 0u) || (votes == 0u))
                              ? count
                              : (((empty != 0u) || (agrees != 0u)) ? (count + 1u) : (count - 1u));
                        agreed += (unsigned int)((walk != 0u) && (votes != 0u) && (agrees != 0u));
                    }
                }
            }
        }
        const unsigned int ahead = (unsigned int)((candidate != CLIMB_MACHINE_OUTSIDE)
                                                  && (agreed > best_agreed));
        best_leaf = (ahead != 0u) ? candidate : best_leaf;
        best_agreed = (ahead != 0u) ? agreed : best_agreed;
    }
    landed[climber] = best_leaf;
}

__global__ static void machine_land_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                           const unsigned int *climber_peak, const int *centers,
                                           const unsigned int *row_first, const unsigned int *run_at_row,
                                           const unsigned int *run_start, const unsigned int *run_length,
                                           const unsigned int *run_leaf, unsigned int run_room, unsigned int climbers,
                                           MachineGeometry geometry, unsigned int *landed)
{
    const unsigned int climber = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (climber >= climbers)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int peak = climber_peak[climber];
    const unsigned int rest = peak % plane;
    const int *const center = &centers[3u * climber];
    const long long z = (long long)(peak / plane) + (long long)center[0];
    const long long y = (long long)(rest / geometry.width) + (long long)center[1];
    const long long x = (long long)(rest % geometry.width) + (long long)center[2];
    if ((z < 0ll) || (z >= (long long)geometry.depth) || (y < 0ll) || (y >= (long long)geometry.height) || (x < 0ll)
     || (x >= (long long)geometry.width))
    {
        landed[climber] = CLIMB_MACHINE_OUTSIDE;
        return;
    }
    const unsigned long long other = (unsigned long long)side_slots[(2u * climber_side[climber]) + 1u];
    const unsigned long long voxel = (unsigned long long)((z * (long long)geometry.height + y) * (long long)geometry.width + x);
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long row = voxel / geometry.width;
    const unsigned long long base = other * (unsigned long long)run_room;
    const unsigned long long offsets = other * (rows + 1ull);
    const unsigned int first = row_first[offsets + row];
    const unsigned int past = row_first[offsets + row + 1ull];
    const unsigned int empty = (unsigned int)(past <= first);
    unsigned int low = (empty != 0u) ? 0u : first;
    unsigned int high = (empty != 0u) ? 1u : past;
    while ((high - low) > 1u)
    {
        const unsigned int middle = low + ((high - low) / 2u);
        const unsigned int at = run_at_row[base + middle];
        low = (run_start[base + at] <= (unsigned int)voxel) ? middle : low;
        high = (run_start[base + at] <= (unsigned int)voxel) ? high : middle;
    }
    const unsigned int at = run_at_row[base + low];
    const unsigned int start = run_start[base + at];
    const unsigned int covers = (unsigned int)((empty == 0u) && (start <= (unsigned int)voxel)
                                               && ((unsigned int)voxel < (start + run_length[base + at])));
    landed[climber] = (covers != 0u) ? run_leaf[base + at] : CLIMB_MACHINE_OUTSIDE;
}

__global__ static void machine_box_kernel(unsigned int cells, unsigned int writing, MachineBoxCells box,
                                          const unsigned int *climber_side, const unsigned int *side_slots,
                                          const unsigned int *climber_entry_start, const unsigned int *entry_first,
                                          const unsigned int *entry_past, const unsigned int *row_first,
                                          const unsigned int *run_at_row, const unsigned int *run_start,
                                          const unsigned int *run_length, const unsigned int *run_leaf,
                                          unsigned int run_room, const unsigned long long *positive,
                                          MachineGeometry geometry)
{
    const unsigned int cell = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (cell >= cells)
    {
        return;
    }
    const unsigned int boxed = box.cell_climber[cell];
    const unsigned int climber = box.climber_of_box[boxed];
    const long long shift_z = (long long)box.cell_shift[3u * cell];
    const long long shift_y = (long long)box.cell_shift[(3u * cell) + 1u];
    const long long shift_x = (long long)box.cell_shift[(3u * cell) + 2u];
    const unsigned int raw = (writing != 0u) ? box.cell_raw[cell] : 0u;
    const unsigned int write_at = (writing != 0u) ? box.entry_first[cell] : 0u;
    unsigned int pieces = 0u;
    const unsigned int side = climber_side[climber];
    const unsigned long long own_word = (unsigned long long)side_slots[2u * side] * geometry.words;
    const unsigned long long other = (unsigned long long)side_slots[(2u * side) + 1u];
    const unsigned long long other_word = other * geometry.words;
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long base = other * (unsigned long long)run_room;
    const unsigned long long offsets = other * (rows + 1ull);
    const unsigned int plane = geometry.height * geometry.width;
    unsigned int targets[CLIMB_MACHINE_BOX_TARGETS];
    unsigned int counts[CLIMB_MACHINE_BOX_TARGETS];
    unsigned int held = 0u;
    unsigned int total = 0u;
    unsigned int labeled = 0u;
    unsigned int overflow = 0u;
    for (unsigned int entry = climber_entry_start[climber]; entry < climber_entry_start[climber + 1u]; entry += 1u)
    {
        for (unsigned int run = entry_first[entry]; run < entry_past[entry]; run += 1u)
        {
            const unsigned int start = run_start[run];
            const long long length = (long long)run_length[run];
            const unsigned int rest = start % plane;
            const long long z = (long long)(start / plane) + shift_z;
            const long long y = (long long)(rest / geometry.width) + shift_y;
            const long long x = (long long)(rest % geometry.width) + shift_x;
            const long long first = (x < 0ll) ? -x : 0ll;
            const long long width_left = (long long)geometry.width - x;
            const long long past = (width_left < length) ? width_left : length;
            if ((z < 0ll) || (z >= (long long)geometry.depth) || (y < 0ll) || (y >= (long long)geometry.height)
             || (first >= past))
            {
                continue;
            }
            const unsigned long long row = (unsigned long long)(z * (long long)geometry.height + y);
            const unsigned int from = (unsigned int)(row * geometry.width + (unsigned long long)(x + first));
            const unsigned int to = from + (unsigned int)(past - first);
            total += machine_agreeing(positive, geometry.words, own_word, (unsigned long long)start
                                      + (unsigned long long)first, other_word, (unsigned long long)from,
                                      (unsigned int)(past - first));
            const unsigned int row_start = row_first[offsets + row];
            const unsigned int row_past = row_first[offsets + row + 1ull];
            for (unsigned int place = row_start; place < row_past; place += 1u)
            {
                const unsigned int at = run_at_row[base + place];
                const unsigned int there = run_start[base + at];
                const unsigned int there_past = there + run_length[base + at];
                const unsigned int meet = (there > from) ? there : from;
                const unsigned int leave = (there_past < to) ? there_past : to;
                if (meet >= leave)
                {
                    continue;
                }
                const unsigned int leaf = run_leaf[base + at];
                const unsigned int shared = leave - meet;
                labeled += shared;
                if (raw != 0u)
                {
                    box.target[write_at + pieces] = leaf;
                    box.count[write_at + pieces] = shared;
                }
                pieces += 1u;
                unsigned int slot = held;
                for (unsigned int seen = 0u; seen < held; seen += 1u)
                {
                    slot = (targets[seen] == leaf) ? seen : slot;
                }
                if ((slot == held) && (held == CLIMB_MACHINE_BOX_TARGETS))
                {
                    overflow = 1u;
                    continue;
                }
                targets[slot] = leaf;
                counts[slot] = (slot == held) ? shared : (counts[slot] + shared);
                held += (slot == held) ? 1u : 0u;
            }
        }
    }
    const unsigned int outside = (total >= labeled) ? (total - labeled) : 0u;
    const unsigned int listed = (overflow != 0u) ? pieces : held;
    const unsigned int written = listed + ((outside != 0u) ? 1u : 0u);
    if (total < labeled)
    {
        atomicAdd(&box.refused[1], 1u);
    }
    if (writing == 0u)
    {
        atomicAdd(&box.refused[0], overflow);
        box.cell_entries[cell] = written;
        box.cell_total[cell] = total;
        box.cell_raw[cell] = overflow;
        return;
    }
    for (unsigned int slot = 0u; (raw == 0u) && (slot < held); slot += 1u)
    {
        box.target[write_at + slot] = targets[slot];
        box.count[write_at + slot] = counts[slot];
    }
    const unsigned int last = (raw != 0u) ? pieces : held;
    if (outside != 0u)
    {
        box.target[write_at + last] = CLIMB_MACHINE_BOX_NONE;
        box.count[write_at + last] = outside;
    }
}

__global__ static void machine_map_kernel(const unsigned int *peaks, unsigned int leaves, unsigned int clear, int *map)
{
    const unsigned int leaf = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (leaf >= leaves)
    {
        return;
    }
    map[peaks[leaf]] = (clear != 0u) ? -1 : (int)leaf;
}

__global__ static void machine_row_kernel(const unsigned int *labels, const int *map, unsigned int rows,
                                          MachineGeometry geometry, const unsigned int *offsets, unsigned int *counts,
                                          unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf)
{
    const unsigned int row = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (row >= rows)
    {
        return;
    }
    const unsigned int first = row * geometry.width;
    const unsigned int past = first + geometry.width;
    unsigned int slot = (offsets != NULL) ? offsets[row] : 0u;
    unsigned int runs = 0u;
    unsigned int voxel = first;
    while (voxel < past)
    {
        const unsigned int label = labels[voxel];
        const unsigned int start = voxel;
        voxel += 1u;
        while ((voxel < past) && (labels[voxel] == label))
        {
            voxel += 1u;
        }
        const int leaf = map[label];
        if (leaf < 0)
        {
            continue;
        }
        if (offsets != NULL)
        {
            run_start[slot] = start;
            run_length[slot] = voxel - start;
            run_leaf[slot] = (unsigned int)leaf;
            slot += 1u;
        }
        runs += 1u;
    }
    if (offsets == NULL)
    {
        counts[row] = runs;
    }
}

__global__ static void machine_gather_kernel(const unsigned int *order, unsigned int runs, const unsigned int *cut_start,
                                             const unsigned int *cut_length, const unsigned int *cut_leaf,
                                             unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf,
                                             unsigned int *run_at_row)
{
    const unsigned int run = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (run >= runs)
    {
        return;
    }
    const unsigned int at = order[run];
    run_start[run] = cut_start[at];
    run_length[run] = cut_length[at];
    run_leaf[run] = cut_leaf[at];
    run_at_row[at] = run;
}

static int machine_launched(void)
{
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

static unsigned int machine_slot_of(const ClimbMachine *machine, unsigned int frame)
{
    for (unsigned int slot = 0u; slot < machine->capacity; slot += 1u)
    {
        if (machine->slot_frame[slot] == frame)
        {
            return slot;
        }
    }
    return CLIMB_MACHINE_EMPTY;
}

static int machine_grow(void **host, void **device, size_t bytes)
{
    free(*host);
    cudaFree(*device);
    *device = NULL;
    *host = malloc(bytes);
    return ((*host != NULL) && (cudaMalloc(device, bytes) == cudaSuccess)) ? 1 : 0;
}

static int machine_cut_runs(ClimbMachine *machine, unsigned int slot, const unsigned int *labels,
                            const ClimbMachineFrame *frame)
{
    const MachineGeometry geometry = machine->geometry;
    const unsigned int rows = geometry.depth * geometry.height;
    const unsigned int leaves = frame->leaf_count;
    const unsigned int row_blocks = (rows + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    const unsigned int leaf_blocks = (leaves + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    int ok = (leaves == 0u) || (cudaMemcpy(machine->device_peaks, frame->peaks, (size_t)leaves * sizeof(unsigned int),
                                           cudaMemcpyHostToDevice) == cudaSuccess);
    if ((ok != 0) && (leaves != 0u))
    {
        machine_map_kernel<<<leaf_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_peaks, leaves, 0u, machine->device_map);
        ok = machine_launched();
    }
    if (ok != 0)
    {
        machine_row_kernel<<<row_blocks, CLIMB_MACHINE_BLOCK>>>(labels, machine->device_map, rows, geometry, NULL,
                                                                machine->device_row_counts, NULL, NULL, NULL);
        ok = machine_launched();
    }
    ok = ok && (cudaMemcpy(machine->row_counts, machine->device_row_counts, (size_t)rows * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    size_t runs = 0u;
    for (unsigned int row = 0u; (ok != 0) && (row < rows); row += 1u)
    {
        const unsigned int count = machine->row_counts[row];
        machine->row_counts[row] = (unsigned int)runs;
        runs += (size_t)count;
    }
    if ((ok != 0) && (runs + 1u > machine->cut_room))
    {
        const size_t room = runs + (runs / 2u) + 1u;
        cudaFree(machine->device_cut_start);
        cudaFree(machine->device_cut_length);
        cudaFree(machine->device_cut_leaf);
        machine->device_cut_start = NULL;
        machine->device_cut_length = NULL;
        machine->device_cut_leaf = NULL;
        ok = ok && (cudaMalloc((void **)&machine->device_cut_start, room * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&machine->device_cut_length, room * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&machine->device_cut_leaf, room * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && machine_grow((void **)&machine->order, (void **)&machine->device_order, room * sizeof(unsigned int));
        free(machine->cut_leaf);
        machine->cut_leaf = (unsigned int *)malloc(room * sizeof(unsigned int));
        ok = ok && (machine->cut_leaf != NULL);
        machine->cut_room = (ok != 0) ? room : 0u;
    }
    ok = ok && (cudaMemcpy(machine->device_row_offsets, machine->row_counts, (size_t)rows * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        machine_row_kernel<<<row_blocks, CLIMB_MACHINE_BLOCK>>>(labels, machine->device_map, rows, geometry,
                                                                machine->device_row_offsets, machine->device_row_counts,
                                                                machine->device_cut_start, machine->device_cut_length,
                                                                machine->device_cut_leaf);
        ok = machine_launched();
    }
    if ((ok != 0) && (leaves != 0u))
    {
        machine_map_kernel<<<leaf_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_peaks, leaves, 1u, machine->device_map);
        ok = machine_launched();
    }
    ok = ok && ((runs == 0u) || (cudaMemcpy(machine->cut_leaf, machine->device_cut_leaf, runs * sizeof(unsigned int),
                                            cudaMemcpyDeviceToHost) == cudaSuccess));
    if (ok == 0)
    {
        return 0;
    }

    unsigned int *const counts = machine->leaf_counts;
    memset(counts, 0, ((size_t)leaves + 1u) * sizeof(unsigned int));
    for (size_t run = 0u; run < runs; run += 1u)
    {
        counts[machine->cut_leaf[run] + 1u] += 1u;
    }
    for (unsigned int leaf = 0u; leaf < leaves; leaf += 1u)
    {
        counts[leaf + 1u] += counts[leaf];
    }
    for (size_t run = 0u; run < runs; run += 1u)
    {
        const unsigned int leaf = machine->cut_leaf[run];
        machine->order[counts[leaf]] = (unsigned int)run;
        counts[leaf] += 1u;
    }

    if (runs > machine->run_room)
    {
        const size_t room = runs + (runs / 4u) + 1u;
        const size_t slots = (size_t)machine->capacity;
        unsigned int *grown[4] = {NULL, NULL, NULL, NULL};
        unsigned int *const kept[4] = {machine->run_start, machine->run_length, machine->run_leaf, machine->run_at_row};
        ok = ok && ((slots * room) <= 0xFFFFFFFFull);
        for (unsigned int which = 0u; (ok != 0) && (which < 4u); which += 1u)
        {
            ok = (cudaMalloc((void **)&grown[which], slots * room * sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
        }
        for (unsigned int held = 0u; (ok != 0) && (held < machine->capacity); held += 1u)
        {
            const size_t count = (size_t)machine->slot_runs[held];
            if ((held == slot) || (machine->slot_frame[held] == CLIMB_MACHINE_EMPTY) || (count == 0u))
            {
                continue;
            }
            for (unsigned int which = 0u; (ok != 0) && (which < 4u); which += 1u)
            {
                ok = (cudaMemcpy(&grown[which][(size_t)held * room], &kept[which][(size_t)held * machine->run_room],
                                 count * sizeof(unsigned int), cudaMemcpyDeviceToDevice) == cudaSuccess) ? 1 : 0;
            }
        }
        for (unsigned int which = 0u; which < 4u; which += 1u)
        {
            cudaFree(kept[which]);
        }
        machine->run_start = grown[0];
        machine->run_length = grown[1];
        machine->run_leaf = grown[2];
        machine->run_at_row = grown[3];
        machine->run_room = (ok != 0) ? room : 0u;
    }
    ok = ok && ((runs == 0u) || (cudaMemcpy(machine->device_order, machine->order, runs * sizeof(unsigned int),
                                            cudaMemcpyHostToDevice) == cudaSuccess));
    if ((ok != 0) && (runs != 0u))
    {
        const size_t base = (size_t)slot * machine->run_room;
        const unsigned int run_blocks = (unsigned int)((runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK);
        machine_gather_kernel<<<run_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_order, (unsigned int)runs,
                                                                   machine->device_cut_start, machine->device_cut_length,
                                                                   machine->device_cut_leaf, &machine->run_start[base],
                                                                   &machine->run_length[base], &machine->run_leaf[base],
                                                                   &machine->run_at_row[base]);
        ok = machine_launched();
    }
    if (ok != 0)
    {
        const size_t offsets = (size_t)slot * ((size_t)rows + 1u);
        const unsigned int total = (unsigned int)runs;
        ok = (cudaMemcpy(&machine->row_first[offsets], machine->row_counts, (size_t)rows * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess) ? 1 : 0;
        ok = ok && (cudaMemcpy(&machine->row_first[offsets + rows], &total, sizeof(unsigned int),
                               cudaMemcpyHostToDevice) == cudaSuccess);
    }

    free(machine->slot_leaf_bundles[slot]);
    free(machine->slot_bundle_first[slot]);
    free(machine->slot_bundle_past[slot]);
    machine->slot_leaf_bundles[slot] = (unsigned int *)malloc(((size_t)leaves + 1u) * sizeof(unsigned int));
    const size_t bundle_room = (runs / CLIMB_MACHINE_BUNDLE) + (size_t)leaves + 1u;
    machine->slot_bundle_first[slot] = (unsigned int *)malloc(bundle_room * sizeof(unsigned int));
    machine->slot_bundle_past[slot] = (unsigned int *)malloc(bundle_room * sizeof(unsigned int));
    ok = ok && (machine->slot_leaf_bundles[slot] != NULL) && (machine->slot_bundle_first[slot] != NULL)
      && (machine->slot_bundle_past[slot] != NULL);
    unsigned int bundles = 0u;
    unsigned int leaf_first = 0u;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < leaves); leaf += 1u)
    {
        const unsigned int leaf_past = counts[leaf];
        machine->slot_leaf_bundles[slot][leaf] = bundles;
        for (unsigned int first = leaf_first; first < leaf_past; first += CLIMB_MACHINE_BUNDLE)
        {
            machine->slot_bundle_first[slot][bundles] = first;
            machine->slot_bundle_past[slot][bundles] = ((leaf_past - first) < CLIMB_MACHINE_BUNDLE)
                                                     ? leaf_past : (first + CLIMB_MACHINE_BUNDLE);
            bundles += 1u;
        }
        leaf_first = leaf_past;
    }
    if (ok != 0)
    {
        machine->slot_leaf_bundles[slot][leaves] = bundles;
        machine->slot_runs[slot] = (unsigned int)runs;
    }
    return ok;
}

extern "C" ClimbMachine *climb_machine_open(const ClimbMachineShape *shape)
{
    if ((shape == NULL) || (shape->depth == 0u) || (shape->height == 0u) || (shape->width == 0u))
    {
        return NULL;
    }
    ClimbMachine *const machine = (ClimbMachine *)calloc(1u, sizeof(ClimbMachine));
    if (machine == NULL)
    {
        return NULL;
    }
    MachineGeometry *const geometry = &machine->geometry;
    geometry->depth = shape->depth;
    geometry->height = shape->height;
    geometry->width = shape->width;
    geometry->weight_z = shape->weight_z;
    geometry->voxels = (unsigned long long)shape->depth * shape->height * shape->width;
    geometry->words = (geometry->voxels + 63ull) / 64ull;
    machine->peak_room = shape->peak_room;
    machine->capacity = (shape->frames < 2u) ? 2u : shape->frames;
    const size_t slots = (size_t)machine->capacity;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&machine->scratch_labels, 2u * (size_t)geometry->voxels * sizeof(unsigned int))
                == cudaSuccess);
    machine->scratch_frame[0] = CLIMB_MACHINE_EMPTY;
    machine->scratch_frame[1] = CLIMB_MACHINE_EMPTY;
    ok = ok && (cudaMalloc((void **)&machine->positive, slots * (size_t)geometry->words * sizeof(unsigned long long))
                == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&machine->row_first,
                           slots * (((size_t)shape->depth * shape->height) + 1u) * sizeof(unsigned int)) == cudaSuccess);
    machine->slot_frame = (unsigned int *)malloc(slots * sizeof(unsigned int));
    machine->slot_leaves = (unsigned int *)calloc(slots, sizeof(unsigned int));
    machine->slot_runs = (unsigned int *)calloc(slots, sizeof(unsigned int));
    machine->slot_leaf_bundles = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_bundle_first = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_bundle_past = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_contact_start = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_contacts = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    ok = ok && (machine->slot_frame != NULL) && (machine->slot_leaves != NULL) && (machine->slot_runs != NULL)
      && (machine->slot_leaf_bundles != NULL) && (machine->slot_bundle_first != NULL)
      && (machine->slot_bundle_past != NULL) && (machine->slot_contact_start != NULL) && (machine->slot_contacts != NULL);
    for (size_t slot = 0u; (ok != 0) && (slot < slots); slot += 1u)
    {
        machine->slot_frame[slot] = CLIMB_MACHINE_EMPTY;
    }
    const size_t rows = (size_t)shape->depth * shape->height;
    ok = ok && (cudaMalloc((void **)&machine->device_map, (size_t)geometry->voxels * sizeof(int)) == cudaSuccess);
    ok = ok && (cudaMemset(machine->device_map, 0xFF, (size_t)geometry->voxels * sizeof(int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&machine->device_peaks, ((size_t)shape->peak_room + 1u) * sizeof(unsigned int))
                == cudaSuccess);
    ok = ok && machine_grow((void **)&machine->row_counts, (void **)&machine->device_row_counts, rows * sizeof(unsigned int));
    ok = ok && (cudaMalloc((void **)&machine->device_row_offsets, rows * sizeof(unsigned int)) == cudaSuccess);
    machine->leaf_counts = (unsigned int *)malloc(((size_t)shape->peak_room + 2u) * sizeof(unsigned int));
    ok = ok && (machine->leaf_counts != NULL);
    ok = ok && (cudaMalloc((void **)&machine->device_moved, 2u * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMallocHost((void **)&machine->pinned_moved, 2u * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMallocHost((void **)&machine->pinned_zero, sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaEventCreate(&machine->blocks_done[0]) == cudaSuccess);
    ok = ok && (cudaEventCreate(&machine->blocks_done[1]) == cudaSuccess);
    if (ok == 0)
    {
        climb_machine_close(machine);
        return NULL;
    }
    machine->pinned_zero[0] = 0u;
    machine->newest = CLIMB_MACHINE_EMPTY;
    return machine;
}

extern "C" int climb_machine_store(ClimbMachine *machine, const ClimbMachineFrame *frame)
{
    if ((machine == NULL) || (frame == NULL) || (frame->labels == NULL) || (frame->positive == NULL)
     || (frame->leaf_count > machine->peak_room))
    {
        return 0;
    }
    unsigned int slot = machine_slot_of(machine, CLIMB_MACHINE_EMPTY);
    int ok = 1;
    if (slot == CLIMB_MACHINE_EMPTY)
    {
        ok = climb_machine_run(machine);
        for (unsigned int held = 0u; (ok != 0) && (held < machine->capacity); held += 1u)
        {
            if (held != machine->newest)
            {
                machine->slot_frame[held] = CLIMB_MACHINE_EMPTY;
            }
        }
        slot = machine_slot_of(machine, CLIMB_MACHINE_EMPTY);
        ok = ok && (slot != CLIMB_MACHINE_EMPTY);
    }
    if (ok == 0)
    {
        return 0;
    }
    const MachineGeometry *const geometry = &machine->geometry;
    const size_t at = (size_t)slot;
    const unsigned int half = machine->scratch_next;
    unsigned int *const labels = &machine->scratch_labels[(size_t)half * (size_t)geometry->voxels];
    machine->scratch_frame[half] = CLIMB_MACHINE_EMPTY;
    ok = ok && (cudaMemcpy(labels, frame->labels, (size_t)geometry->voxels * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    machine->scratch_frame[half] = (ok != 0) ? frame->frame : CLIMB_MACHINE_EMPTY;
    machine->scratch_next = 1u - half;
    ok = ok && (cudaMemcpy(&machine->positive[at * (size_t)geometry->words], frame->positive,
                           (size_t)geometry->words * sizeof(unsigned long long), cudaMemcpyHostToDevice) == cudaSuccess);
    free(machine->slot_contact_start[slot]);
    free(machine->slot_contacts[slot]);
    machine->slot_contact_start[slot] = NULL;
    machine->slot_contacts[slot] = NULL;
    machine->slot_leaves[slot] = frame->leaf_count;
    machine->slot_runs[slot] = 0u;
    free(machine->slot_leaf_bundles[slot]);
    machine->slot_leaf_bundles[slot] = NULL;
    if ((ok != 0) && (frame->peaks != NULL))
    {
        ok = machine_cut_runs(machine, slot, labels, frame);
    }
    if ((ok != 0) && (frame->contact_start != NULL) && (frame->contacts != NULL))
    {
        const size_t contacts = (size_t)frame->contact_start[frame->leaf_count];
        machine->slot_contact_start[slot] = (unsigned int *)malloc(((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
        machine->slot_contacts[slot] = (unsigned int *)malloc((contacts + 1u) * sizeof(unsigned int));
        ok = (machine->slot_contact_start[slot] != NULL) && (machine->slot_contacts[slot] != NULL);
        if (ok != 0)
        {
            memcpy(machine->slot_contact_start[slot], frame->contact_start, ((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
            memcpy(machine->slot_contacts[slot], frame->contacts, contacts * sizeof(unsigned int));
        }
    }
    machine->slot_frame[slot] = (ok != 0) ? frame->frame : CLIMB_MACHINE_EMPTY;
    machine->newest = (ok != 0) ? slot : machine->newest;
    return ok;
}

extern "C" void climb_machine_land_by_mass(ClimbMachine *machine, unsigned int by_mass)
{
    if (machine != NULL)
    {
        machine->land_by_mass = (by_mass != 0u) ? 1u : 0u;
    }
}

extern "C" int climb_machine_spiral(ClimbMachine *machine, unsigned int tries)
{
    if (machine == NULL)
    {
        return 0;
    }
    const unsigned int held = (tries > SPIRAL_STEPS) ? SPIRAL_STEPS : tries;
    machine->spiral_tries = held + 1u;
    if ((machine->device_spiral != NULL) || (held == 0u))
    {
        return 1;
    }
    const int ok = (cudaMalloc((void **)&machine->device_spiral, (size_t)SPIRAL_STEPS * 3u * sizeof(int))
                    == cudaSuccess)
                && (cudaMemcpy(machine->device_spiral, SPIRAL_OFFSETS,
                               (size_t)SPIRAL_STEPS * 3u * sizeof(int), cudaMemcpyHostToDevice) == cudaSuccess);
    return ok ? 1 : 0;
}

extern "C" const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame)
{
    if (machine == NULL)
    {
        return NULL;
    }
    const unsigned int held = (unsigned int)(machine->scratch_frame[1] == frame);
    const unsigned int has = (unsigned int)((frame != CLIMB_MACHINE_EMPTY)
                                            && ((machine->scratch_frame[0] == frame) || (machine->scratch_frame[1] == frame)));
    return (has != 0u) ? &machine->scratch_labels[(size_t)held * (size_t)machine->geometry.voxels] : NULL;
}

extern "C" const unsigned long long *climb_machine_positive(const ClimbMachine *machine, unsigned int frame)
{
    const unsigned int slot = (machine != NULL) ? machine_slot_of(machine, frame) : CLIMB_MACHINE_EMPTY;
    return (slot == CLIMB_MACHINE_EMPTY) ? NULL : &machine->positive[(size_t)slot * (size_t)machine->geometry.words];
}

extern "C" int climb_machine_pend(ClimbMachine *machine, const ClimbMachinePair *pair)
{
    if ((machine == NULL) || (pair == NULL) || (machine_slot_of(machine, pair->earlier) == CLIMB_MACHINE_EMPTY)
     || (machine_slot_of(machine, pair->later) == CLIMB_MACHINE_EMPTY))
    {
        return 0;
    }
    if (machine->pending_count == machine->pending_room)
    {
        const unsigned int room = (machine->pending_room * 2u) + 8u;
        ClimbMachinePair *const grown = (ClimbMachinePair *)realloc(machine->pending, (size_t)room * sizeof(ClimbMachinePair));
        if (grown == NULL)
        {
            return 0;
        }
        machine->pending = grown;
        machine->pending_room = room;
    }
    machine->pending[machine->pending_count] = *pair;
    machine->pending_count += 1u;
    return 1;
}

extern "C" int climb_machine_run(ClimbMachine *machine)
{
    if (machine == NULL)
    {
        return 0;
    }
    if (machine->pending_count == 0u)
    {
        return 1;
    }
    const MachineGeometry geometry = machine->geometry;
    const size_t sides = 2u * (size_t)machine->pending_count;
    size_t climbers = 0u;
    size_t entries = 0u;
    for (unsigned int pair = 0u; pair < machine->pending_count; pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        const unsigned int slots[2] = {machine_slot_of(machine, pending->earlier), machine_slot_of(machine, pending->later)};
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int slot = slots[side];
            const unsigned int *const leaf_bundles = machine->slot_leaf_bundles[slot];
            const unsigned int *const contact_start = machine->slot_contact_start[slot];
            if (leaf_bundles == NULL)
            {
                return 0;
            }
            climbers += (size_t)machine->slot_leaves[slot];
            entries += (size_t)leaf_bundles[machine->slot_leaves[slot]];
            for (unsigned int leaf = 0u; (contact_start != NULL) && (leaf < machine->slot_leaves[slot]); leaf += 1u)
            {
                for (unsigned int contact = contact_start[leaf]; contact < contact_start[leaf + 1u]; contact += 1u)
                {
                    const unsigned int near = machine->slot_contacts[slot][contact];
                    entries += (size_t)(leaf_bundles[near + 1u] - leaf_bundles[near]);
                }
            }
        }
    }
    int ok = 1;
    if (sides > machine->side_room)
    {
        ok = ok && machine_grow((void **)&machine->side_slots, (void **)&machine->device_side_slots, sides * 2u * sizeof(unsigned int));
        machine->side_room = (ok != 0) ? sides : 0u;
    }
    if ((ok != 0) && (climbers + 1u > machine->climber_room))
    {
        const size_t room = climbers + (climbers / 2u) + 1u;
        ok = ok && machine_grow((void **)&machine->climber_side, (void **)&machine->device_climber_side, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->climber_peak, (void **)&machine->device_climber_peak, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->climber_entry_start, (void **)&machine->device_climber_entry_start,
                                (room + 1u) * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->centers, (void **)&machine->device_centers, room * 3u * sizeof(int));
        ok = ok && machine_grow((void **)&machine->active, (void **)&machine->device_active, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->landed, (void **)&machine->device_landed, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->held, (void **)&machine->device_held, room * sizeof(unsigned int));
        machine->climber_room = (ok != 0) ? room : 0u;
    }
    if ((ok != 0) && (entries + 1u > machine->entry_room))
    {
        const size_t room = entries + (entries / 2u) + 1u;
        ok = ok && machine_grow((void **)&machine->entry_first, (void **)&machine->device_entry_first, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->entry_past, (void **)&machine->device_entry_past, room * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->entry_climber, (void **)&machine->device_entry_climber,
                                room * sizeof(unsigned int));
        cudaFree(machine->device_scores);
        machine->device_scores = NULL;
        ok = ok && (cudaMalloc((void **)&machine->device_scores, room * CLIMB_MACHINE_CANDIDATES * sizeof(unsigned int))
                    == cudaSuccess);
        machine->entry_room = (ok != 0) ? room : 0u;
    }
    if (ok == 0)
    {
        return 0;
    }

    unsigned int climber = 0u;
    unsigned int entry = 0u;
    for (unsigned int pair = 0u; pair < machine->pending_count; pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        const unsigned int earlier = machine_slot_of(machine, pending->earlier);
        const unsigned int later = machine_slot_of(machine, pending->later);
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int index = (2u * pair) + side;
            const unsigned int own = (side == 0u) ? earlier : later;
            const int sign = (side == 0u) ? 1 : -1;
            const unsigned int *const peaks = (side == 0u) ? pending->earlier_peaks : pending->later_peaks;
            const unsigned int *const leaf_bundles = machine->slot_leaf_bundles[own];
            const unsigned int *const contact_start = machine->slot_contact_start[own];
            const unsigned int run_base = (unsigned int)((size_t)own * machine->run_room);
            machine->side_slots[2u * index] = own;
            machine->side_slots[(2u * index) + 1u] = (side == 0u) ? later : earlier;
            for (unsigned int leaf = 0u; leaf < machine->slot_leaves[own]; leaf += 1u)
            {
                machine->climber_side[climber] = index;
                machine->climber_peak[climber] = peaks[leaf];
                machine->climber_entry_start[climber] = entry;
                machine->centers[3u * climber] = sign * pending->lag[0];
                machine->centers[(3u * climber) + 1u] = sign * pending->lag[1];
                machine->centers[(3u * climber) + 2u] = sign * pending->lag[2];
                machine->active[climber] = 1u;
                unsigned int part = leaf;
                unsigned int next_contact = (contact_start != NULL) ? contact_start[leaf] : 0u;
                const unsigned int last_contact = (contact_start != NULL) ? contact_start[leaf + 1u] : 0u;
                for (;;)
                {
                    for (unsigned int bundle = leaf_bundles[part]; bundle < leaf_bundles[part + 1u]; bundle += 1u)
                    {
                        machine->entry_first[entry] = run_base + machine->slot_bundle_first[own][bundle];
                        machine->entry_past[entry] = run_base + machine->slot_bundle_past[own][bundle];
                        machine->entry_climber[entry] = climber;
                        entry += 1u;
                    }
                    if (next_contact >= last_contact)
                    {
                        break;
                    }
                    part = machine->slot_contacts[own][next_contact];
                    next_contact += 1u;
                }
                climber += 1u;
            }
        }
    }
    machine->climber_entry_start[climber] = entry;
    ok = ok && (cudaMemcpy(machine->device_side_slots, machine->side_slots, sides * 2u * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_climber_side, machine->climber_side, climbers * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_climber_peak, machine->climber_peak, climbers * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_climber_entry_start, machine->climber_entry_start,
                           (climbers + 1u) * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_centers, machine->centers, climbers * 3u * sizeof(int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_active, machine->active, climbers * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && ((entries == 0u)
                || ((cudaMemcpy(machine->device_entry_first, machine->entry_first, entries * sizeof(unsigned int),
                                cudaMemcpyHostToDevice) == cudaSuccess)
                    && (cudaMemcpy(machine->device_entry_past, machine->entry_past, entries * sizeof(unsigned int),
                                   cudaMemcpyHostToDevice) == cudaSuccess)
                    && (cudaMemcpy(machine->device_entry_climber, machine->entry_climber, entries * sizeof(unsigned int),
                                   cudaMemcpyHostToDevice) == cudaSuccess)));

    const unsigned int entry_blocks = (entry + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    const unsigned int climber_blocks = (climber + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    int settled = (climber == 0u) ? 1 : 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = (cudaMemcpyAsync(&machine->device_moved[parity], machine->pinned_zero, sizeof(unsigned int),
                              cudaMemcpyHostToDevice, 0) == cudaSuccess) ? 1 : 0;
        for (unsigned int tick = 0u; (ok != 0) && (tick < CLIMB_MACHINE_TICKS); tick += 1u)
        {
            if (entry != 0u)
            {
                machine_score_kernel<<<entry_blocks, CLIMB_MACHINE_BLOCK>>>(
                    machine->run_start, machine->run_length, machine->device_entry_first, machine->device_entry_past,
                    machine->device_entry_climber, entry, machine->device_climber_side, machine->device_side_slots,
                    machine->device_centers, machine->device_active, machine->positive, geometry, machine->device_scores);
                ok = machine_launched();
            }
            if (ok != 0)
            {
                machine_decide_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
                    machine->device_climber_entry_start, machine->device_scores, climber, geometry,
                    machine->device_centers, machine->device_active, &machine->device_moved[parity], machine->device_held);
                ok = machine_launched();
            }
        }
        ok = ok && (cudaMemcpyAsync(&machine->pinned_moved[parity], &machine->device_moved[parity], sizeof(unsigned int),
                                    cudaMemcpyDeviceToHost, 0) == cudaSuccess);
        ok = ok && (cudaEventRecord(machine->blocks_done[parity], 0) == cudaSuccess);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = (cudaEventSynchronize(machine->blocks_done[previous]) == cudaSuccess) ? 1 : 0;
            settled = ((ok != 0) && (machine->pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }

    if ((ok != 0) && (climber != 0u))
    {
        if (machine->land_by_mass != 0u)
        {
            machine_land_mass_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
                machine->device_climber_side, machine->device_side_slots, machine->device_climber_entry_start,
                machine->device_entry_first, machine->device_entry_past, machine->device_centers,
                machine->row_first, machine->run_at_row, machine->run_start, machine->run_length,
                machine->run_leaf, (unsigned int)machine->run_room, climber,
                machine->device_spiral, (machine->spiral_tries != 0u) ? machine->spiral_tries : 1u,
                geometry, machine->device_landed);
        }
        else
        {
            machine_land_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
                machine->device_climber_side, machine->device_side_slots, machine->device_climber_peak,
                machine->device_centers, machine->row_first, machine->run_at_row, machine->run_start,
                machine->run_length, machine->run_leaf, (unsigned int)machine->run_room, climber, geometry,
                machine->device_landed);
        }
        ok = machine_launched();
    }
    ok = ok && (cudaMemcpy(machine->centers, machine->device_centers, climbers * 3u * sizeof(int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->landed, machine->device_landed, climbers * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->held, machine->device_held, climbers * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);

    climber = 0u;
    for (unsigned int pair = 0u; (ok != 0) && (pair < machine->pending_count); pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int leaves = (side == 0u) ? pending->earlier_leaves : pending->later_leaves;
            int *const lag_out = (side == 0u) ? pending->forward_lags : pending->backward_lags;
            int *const landing_out = (side == 0u) ? pending->forward : pending->backward;
            unsigned int *const held_out = (side == 0u) ? pending->forward_held : pending->backward_held;
            for (unsigned int leaf = 0u; leaf < leaves; leaf += 1u)
            {
                if (held_out != NULL)
                {
                    held_out[leaf] = machine->held[climber];
                }
                lag_out[3u * leaf] = machine->centers[3u * climber];
                lag_out[(3u * leaf) + 1u] = machine->centers[(3u * climber) + 1u];
                lag_out[(3u * leaf) + 2u] = machine->centers[(3u * climber) + 2u];
                landing_out[leaf] = (machine->landed[climber] == CLIMB_MACHINE_OUTSIDE)
                                  ? CLIMB_MACHINE_NO_LEAF : (int)machine->landed[climber];
                climber += 1u;
            }
        }
    }
    machine->ran_count = (ok != 0) ? machine->pending_count : 0u;
    machine->pending_count = 0u;
    return ok;
}

static void machine_box_release(ClimbMachine *machine)
{
    free(machine->box_earlier);
    free(machine->box_later);
    free(machine->box_leaf);
    free(machine->box_cell_first);
    free(machine->box_cell_shift);
    free(machine->box_entry_first);
    free(machine->box_target);
    free(machine->box_count);
    machine->box_earlier = NULL;
    machine->box_later = NULL;
    machine->box_leaf = NULL;
    machine->box_cell_first = NULL;
    machine->box_cell_shift = NULL;
    machine->box_entry_first = NULL;
    machine->box_target = NULL;
    machine->box_count = NULL;
}

typedef struct
{
    unsigned int target;
    unsigned int count;
} MachineBoxPiece;

static int machine_box_piece_order(const void *left, const void *right)
{
    const unsigned int one = ((const MachineBoxPiece *)left)->target;
    const unsigned int other = ((const MachineBoxPiece *)right)->target;
    return (one < other) ? -1 : ((one > other) ? 1 : 0);
}

static int machine_box_merge(ClimbMachine *machine, const unsigned int *cell_raw, size_t cell_count)
{
    size_t kept = 0u;
    size_t widest = 0u;
    for (size_t cell = 0u; cell < cell_count; cell += 1u)
    {
        const size_t size = (size_t)(machine->box_entry_first[cell + 1u] - machine->box_entry_first[cell]);
        widest = (size > widest) ? size : widest;
    }
    MachineBoxPiece *const pieces = (MachineBoxPiece *)malloc((widest + 1u) * sizeof(MachineBoxPiece));
    if (pieces == NULL)
    {
        return 0;
    }
    unsigned int from = 0u;
    for (size_t cell = 0u; cell < cell_count; cell += 1u)
    {
        const unsigned int past = machine->box_entry_first[cell + 1u];
        machine->box_entry_first[cell] = (unsigned int)kept;
        if (cell_raw[cell] == 0u)
        {
            for (unsigned int entry = from; entry < past; entry += 1u)
            {
                machine->box_target[kept] = machine->box_target[entry];
                machine->box_count[kept] = machine->box_count[entry];
                kept += 1u;
            }
            from = past;
            continue;
        }
        size_t held = 0u;
        unsigned int outside = 0u;
        for (unsigned int entry = from; entry < past; entry += 1u)
        {
            const unsigned int none = (unsigned int)(machine->box_target[entry] == CLIMB_MACHINE_BOX_NONE);
            outside = (none != 0u) ? machine->box_count[entry] : outside;
            pieces[held].target = machine->box_target[entry];
            pieces[held].count = machine->box_count[entry];
            held += (none != 0u) ? 0u : 1u;
        }
        qsort(pieces, held, sizeof(MachineBoxPiece), machine_box_piece_order);
        for (size_t piece = 0u; piece < held; piece += 1u)
        {
            const int same = (piece != 0u) && (pieces[piece].target == pieces[piece - 1u].target);
            machine->box_target[kept - (same ? 1u : 0u)] = pieces[piece].target;
            machine->box_count[kept - (same ? 1u : 0u)] = same ? (machine->box_count[kept - 1u] + pieces[piece].count)
                                                               : pieces[piece].count;
            kept += same ? 0u : 1u;
        }
        if (outside != 0u)
        {
            machine->box_target[kept] = CLIMB_MACHINE_BOX_NONE;
            machine->box_count[kept] = outside;
            kept += 1u;
        }
        from = past;
    }
    machine->box_entry_first[cell_count] = (unsigned int)kept;
    free(pieces);
    return 1;
}

extern "C" int climb_machine_box(ClimbMachine *machine, ClimbMachineBox *box)
{
    if ((machine == NULL) || (box == NULL))
    {
        return 0;
    }
    memset(box, 0, sizeof(*box));
    machine_box_release(machine);
    const unsigned long long started = engine_clock_microseconds();
    unsigned int boxed = 0u;
    for (unsigned int pair = 0u; pair < machine->ran_count; pair += 1u)
    {
        boxed += machine->pending[pair].earlier_leaves;
    }
    const size_t room = (size_t)boxed + 1u;
    const unsigned long long cells = (unsigned long long)boxed * CLIMB_MACHINE_BOX_CELLS;
    const size_t cell_count = (cells <= 0x7FFFFFFFull) ? (size_t)cells : 0u;
    machine->box_earlier = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->box_later = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->box_leaf = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->box_cell_first = (unsigned int *)malloc((room + 1u) * sizeof(unsigned int));
    machine->box_cell_shift = (int *)malloc((cell_count + 1u) * 3u * sizeof(int));
    machine->box_entry_first = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const climber_of_box = (unsigned int *)malloc(room * sizeof(unsigned int));
    unsigned int *const cell_climber = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const cell_total = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const cell_raw = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    int ok = (cells <= 0x7FFFFFFFull) && (machine->box_earlier != NULL) && (machine->box_later != NULL)
          && (machine->box_leaf != NULL) && (machine->box_cell_first != NULL) && (machine->box_cell_shift != NULL)
          && (machine->box_entry_first != NULL) && (climber_of_box != NULL) && (cell_climber != NULL)
          && (cell_total != NULL) && (cell_raw != NULL);
    unsigned int climber = 0u;
    unsigned int at = 0u;
    for (unsigned int pair = 0u; ok && (pair < machine->ran_count); pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        for (unsigned int leaf = 0u; leaf < pending->earlier_leaves; leaf += 1u)
        {
            const int *const center = &machine->centers[3u * (climber + leaf)];
            machine->box_earlier[at] = pending->earlier;
            machine->box_later[at] = pending->later;
            machine->box_leaf[at] = leaf;
            climber_of_box[at] = climber + leaf;
            machine->box_cell_first[at] = at * CLIMB_MACHINE_BOX_CELLS;
            unsigned int cell = at * CLIMB_MACHINE_BOX_CELLS;
            for (int step_z = -1; step_z <= 1; step_z += 1)
            {
                for (int step_y = -1; step_y <= 1; step_y += 1)
                {
                    for (int step_x = -1; step_x <= 1; step_x += 1)
                    {
                        machine->box_cell_shift[3u * cell] = center[0] + step_z;
                        machine->box_cell_shift[(3u * cell) + 1u] = center[1] + step_y;
                        machine->box_cell_shift[(3u * cell) + 2u] = center[2] + step_x;
                        cell_climber[cell] = at;
                        cell += 1u;
                    }
                }
            }
            machine->box_cell_shift[3u * cell] = pending->lag[0];
            machine->box_cell_shift[(3u * cell) + 1u] = pending->lag[1];
            machine->box_cell_shift[(3u * cell) + 2u] = pending->lag[2];
            cell_climber[cell] = at;
            at += 1u;
        }
        climber += pending->earlier_leaves + pending->later_leaves;
    }
    if (ok)
    {
        machine->box_cell_first[boxed] = (unsigned int)cell_count;
    }
    MachineBoxCells device;
    memset(&device, 0, sizeof(device));
    unsigned int *device_cell_climber = NULL;
    unsigned int *device_climber_of_box = NULL;
    int *device_cell_shift = NULL;
    unsigned int *device_entry_first = NULL;
    unsigned int *device_cell_entries = NULL;
    unsigned int *device_cell_total = NULL;
    unsigned int *device_cell_raw = NULL;
    unsigned int *device_target = NULL;
    unsigned int *device_count = NULL;
    unsigned int *device_refused = NULL;
    ok = ok && (cudaMalloc((void **)&device_cell_climber, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_climber_of_box, room * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_cell_shift, (cell_count + 1u) * 3u * sizeof(int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_entry_first, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_cell_entries, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_cell_total, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_cell_raw, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_refused, 2u * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMemset(device_refused, 0, 2u * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMemcpy(device_cell_climber, cell_climber, cell_count * sizeof(unsigned int), cudaMemcpyHostToDevice)
          == cudaSuccess)
      && (cudaMemcpy(device_climber_of_box, climber_of_box, (size_t)boxed * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess)
      && (cudaMemcpy(device_cell_shift, machine->box_cell_shift, cell_count * 3u * sizeof(int), cudaMemcpyHostToDevice)
          == cudaSuccess);
    device.cell_climber = device_cell_climber;
    device.climber_of_box = device_climber_of_box;
    device.cell_shift = device_cell_shift;
    device.entry_first = device_entry_first;
    device.cell_entries = device_cell_entries;
    device.cell_total = device_cell_total;
    device.cell_raw = device_cell_raw;
    device.refused = device_refused;
    const unsigned int cell_blocks = (unsigned int)((cell_count + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK);
    if (ok && (cell_count != 0u))
    {
        machine_box_kernel<<<cell_blocks, CLIMB_MACHINE_BLOCK>>>(
            (unsigned int)cell_count, 0u, device, machine->device_climber_side, machine->device_side_slots,
            machine->device_climber_entry_start, machine->device_entry_first, machine->device_entry_past,
            machine->row_first, machine->run_at_row, machine->run_start, machine->run_length, machine->run_leaf,
            (unsigned int)machine->run_room, machine->positive, machine->geometry);
        ok = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
    }
    ok = ok && ((cell_count == 0u)
                || ((cudaMemcpy(machine->box_entry_first, device_cell_entries, cell_count * sizeof(unsigned int),
                                cudaMemcpyDeviceToHost) == cudaSuccess)
                    && (cudaMemcpy(cell_total, device_cell_total, cell_count * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost) == cudaSuccess)
                    && (cudaMemcpy(cell_raw, device_cell_raw, cell_count * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost) == cudaSuccess)));
    unsigned long long entries = 0ull;
    for (size_t cell = 0u; ok && (cell < cell_count); cell += 1u)
    {
        const unsigned int here = machine->box_entry_first[cell];
        machine->box_entry_first[cell] = (unsigned int)entries;
        entries += (unsigned long long)here;
    }
    ok = ok && (entries <= 0x7FFFFFFFull);
    if (ok)
    {
        machine->box_entry_first[cell_count] = (unsigned int)entries;
    }
    const size_t entry_count = ok ? (size_t)entries : 0u;
    machine->box_target = ok ? (unsigned int *)malloc((entry_count + 1u) * sizeof(unsigned int)) : NULL;
    machine->box_count = ok ? (unsigned int *)malloc((entry_count + 1u) * sizeof(unsigned int)) : NULL;
    ok = ok && (machine->box_target != NULL) && (machine->box_count != NULL)
      && (cudaMalloc((void **)&device_target, (entry_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMalloc((void **)&device_count, (entry_count + 1u) * sizeof(unsigned int)) == cudaSuccess)
      && (cudaMemcpy(device_entry_first, machine->box_entry_first, (cell_count + 1u) * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    device.target = device_target;
    device.count = device_count;
    if (ok && (cell_count != 0u))
    {
        machine_box_kernel<<<cell_blocks, CLIMB_MACHINE_BLOCK>>>(
            (unsigned int)cell_count, 1u, device, machine->device_climber_side, machine->device_side_slots,
            machine->device_climber_entry_start, machine->device_entry_first, machine->device_entry_past,
            machine->row_first, machine->run_at_row, machine->run_start, machine->run_length, machine->run_leaf,
            (unsigned int)machine->run_room, machine->positive, machine->geometry);
        ok = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
    }
    unsigned int refused[2] = {0u, 0u};
    ok = ok && ((entry_count == 0u)
                || ((cudaMemcpy(machine->box_target, device_target, entry_count * sizeof(unsigned int),
                                cudaMemcpyDeviceToHost) == cudaSuccess)
                    && (cudaMemcpy(machine->box_count, device_count, entry_count * sizeof(unsigned int),
                                   cudaMemcpyDeviceToHost) == cudaSuccess)));
    const int counted = (device_refused != NULL)
                     && (cudaMemcpy(refused, device_refused, 2u * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                         == cudaSuccess);
    box->climbers = boxed;
    box->cells = (unsigned int)((cells <= 0xFFFFFFFFull) ? cells : 0xFFFFFFFFull);
    box->crowded = counted ? refused[0] : 0u;
    box->broken = counted ? refused[1] : 0u;
    ok = ok && counted && (refused[1] == 0u) && machine_box_merge(machine, cell_raw, cell_count);
    unsigned int held_differ = 0u;
    unsigned int not_highest = 0u;
    for (unsigned int one = 0u; ok && (one < boxed); one += 1u)
    {
        const unsigned int first = machine->box_cell_first[one];
        const unsigned int top = cell_total[first + CLIMB_MACHINE_BOX_CENTRE];
        held_differ += (top != machine->held[climber_of_box[one]]) ? 1u : 0u;
        unsigned int higher = 0u;
        for (unsigned int near = 0u; near < CLIMB_MACHINE_BOX_NEIGHBOURS; near += 1u)
        {
            higher += (cell_total[first + near] > top) ? 1u : 0u;
        }
        not_highest += (higher != 0u) ? 1u : 0u;
    }
    cudaFree(device_cell_climber);
    cudaFree(device_climber_of_box);
    cudaFree(device_cell_shift);
    cudaFree(device_entry_first);
    cudaFree(device_cell_entries);
    cudaFree(device_cell_total);
    cudaFree(device_cell_raw);
    cudaFree(device_target);
    cudaFree(device_count);
    cudaFree(device_refused);
    free(cell_climber);
    free(cell_total);
    free(cell_raw);
    free(climber_of_box);
    if (ok == 0)
    {
        machine_box_release(machine);
        return 0;
    }
    box->earlier = machine->box_earlier;
    box->later = machine->box_later;
    box->leaf = machine->box_leaf;
    box->cell_first = machine->box_cell_first;
    box->cell_shift = machine->box_cell_shift;
    box->entry_first = machine->box_entry_first;
    box->target = machine->box_target;
    box->count = machine->box_count;
    box->cells = (unsigned int)cell_count;
    box->entries = machine->box_entry_first[cell_count];
    box->held_differ = held_differ;
    box->not_highest = not_highest;
    box->microseconds = engine_clock_microseconds() - started;
    return 1;
}

__global__ static void machine_paint_kernel(const unsigned int *run_start, const unsigned int *run_length,
                                            const unsigned int *run_leaf, unsigned int runs, unsigned int *painted)
{
    const unsigned int run = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (run >= runs)
    {
        return;
    }
    const unsigned int start = run_start[run];
    for (unsigned int step = 0u; step < run_length[run]; step += 1u)
    {
        painted[start + step] = run_leaf[run];
    }
}

__global__ static void machine_reach_row_kernel(const unsigned int *painted, MachineGeometry geometry,
                                                unsigned int *reach)
{
    const unsigned int row = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (row >= (geometry.depth * geometry.height))
    {
        return;
    }
    const unsigned int row_first = row * geometry.width;
    unsigned int edge_distance = 0u;
    for (unsigned int width_place = 0u; width_place < geometry.width; width_place += 1u)
    {
        const unsigned int voxel = row_first + width_place;
        const unsigned int label_boundary = ((width_place == 0u) || (painted[voxel] != painted[voxel - 1u])) ? 1u : 0u;
        edge_distance = (label_boundary != 0u) ? 1u : (edge_distance + 1u);
        reach[voxel] = edge_distance;
    }
    edge_distance = 0u;
    for (unsigned int width_past = geometry.width; width_past > 0u; width_past -= 1u)
    {
        const unsigned int voxel = row_first + width_past - 1u;
        const unsigned int label_boundary =
            ((width_past == geometry.width) || (painted[voxel] != painted[voxel + 1u])) ? 1u : 0u;
        edge_distance = (label_boundary != 0u) ? 1u : (edge_distance + 1u);
        reach[voxel] = (edge_distance < reach[voxel]) ? edge_distance : reach[voxel];
    }
}

__global__ static void machine_reach_column_kernel(const unsigned int *painted, MachineGeometry geometry,
                                                   unsigned int axis, const unsigned int *reach_in,
                                                   unsigned int *reach_out)
{
    const unsigned int column = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int extent = (axis == 0u) ? geometry.depth : geometry.height;
    const unsigned int stride = (axis == 0u) ? plane : geometry.width;
    const unsigned int columns = (axis == 0u) ? plane : (geometry.depth * geometry.width);
    if (column >= columns)
    {
        return;
    }
    const unsigned int base = (axis == 0u) ? column
                                           : (((column / geometry.width) * plane) + (column % geometry.width));
    for (unsigned int place = 0u; place < extent; place += 1u)
    {
        const unsigned int voxel = base + (place * stride);
        const unsigned int label = painted[voxel];
        unsigned int least_reach = reach_in[voxel];
        for (unsigned int radius = 1u; (label != CLIMB_MACHINE_OUTSIDE) && (radius < least_reach); radius += 1u)
        {
            for (unsigned int direction = 0u; direction < 2u; direction += 1u)
            {
                const unsigned int neighbour_inside = (direction == 0u) ? ((radius <= place) ? 1u : 0u)
                                                                        : (((place + radius) < extent) ? 1u : 0u);
                const unsigned int neighbour_place = (direction == 0u) ? (place - radius) : (place + radius);
                const unsigned int neighbour = (neighbour_inside != 0u) ? (base + (neighbour_place * stride)) : 0u;
                const unsigned int neighbour_reach =
                    ((neighbour_inside != 0u) && (painted[neighbour] == label)) ? reach_in[neighbour] : 0u;
                const unsigned int candidate_reach = (neighbour_reach > radius) ? neighbour_reach : radius;
                least_reach = (candidate_reach < least_reach) ? candidate_reach : least_reach;
            }
        }
        reach_out[voxel] = (label != CLIMB_MACHINE_OUTSIDE) ? least_reach : 0u;
    }
}

__global__ static void machine_core_kernel(unsigned int items, const unsigned int *item_run_first,
                                           const unsigned int *item_run_past, const int *item_center,
                                           const unsigned int *item_match, const unsigned int *run_start,
                                           const unsigned int *run_length, const unsigned int *painted,
                                           const unsigned int *reach, MachineGeometry geometry, unsigned int widest,
                                           unsigned long long *fields, unsigned int *refused)
{
    const unsigned int item = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (item >= items)
    {
        return;
    }
    const unsigned int match = item_match[item];
    const long long shift_depth = item_center[3u * item];
    const long long shift_height = item_center[(3u * item) + 1u];
    const long long shift_width = item_center[(3u * item) + 2u];
    const unsigned int plane = geometry.height * geometry.width;
    // item widens from unsigned int to unsigned long long before the multiply, so item * widest * 10 cannot wrap in 32 bits
    unsigned long long *const item_bins = &fields[(unsigned long long)item * widest * CLIMB_MACHINE_CORE_FIELDS];
    for (unsigned int run = item_run_first[item]; run < item_run_past[item]; run += 1u)
    {
        const unsigned int start = run_start[run];
        const unsigned int rest = start % plane;
        const unsigned long long depth_place = start / plane;
        const unsigned long long height_place = rest / geometry.width;
        // depth_place is below geometry.depth, a 32-bit count, so it re-signs to long long exactly
        const long long lagged_depth = (long long)depth_place + shift_depth;
        // height_place is below geometry.height, a 32-bit count, so it re-signs to long long exactly
        const long long lagged_height = (long long)height_place + shift_height;
        if ((lagged_depth < 0ll) || (lagged_depth >= geometry.depth) || (lagged_height < 0ll)
         || (lagged_height >= geometry.height))
        {
            continue;
        }
        const long long lagged_row = ((lagged_depth * geometry.height) + lagged_height) * geometry.width;
        for (unsigned int step = 0u; step < run_length[run]; step += 1u)
        {
            const unsigned long long width_place = (rest % geometry.width) + step;
            // width_place is below geometry.width, a 32-bit count, so it re-signs to long long exactly
            const long long lagged_width = (long long)width_place + shift_width;
            if ((lagged_width < 0ll) || (lagged_width >= geometry.width)
             || (painted[lagged_row + lagged_width] != match))
            {
                continue;
            }
            const unsigned int core_width = reach[lagged_row + lagged_width] - 1u;
            if (core_width >= widest)
            {
                atomicAdd(refused, 1u);
                continue;
            }
            // core_width widens from unsigned int to unsigned long long, matching the 64-bit offset item_bins is indexed by
            unsigned long long *const bin = &item_bins[(unsigned long long)core_width * CLIMB_MACHINE_CORE_FIELDS];
            bin[0] += 1ull;
            bin[1] += depth_place;
            bin[2] += height_place;
            bin[3] += width_place;
            bin[4] += depth_place * depth_place;
            bin[5] += height_place * height_place;
            bin[6] += width_place * width_place;
            bin[7] += depth_place * height_place;
            bin[8] += depth_place * width_place;
            bin[9] += height_place * width_place;
        }
    }
}

static void machine_core_release(ClimbMachine *machine)
{
    free(machine->core_earlier);
    free(machine->core_later);
    free(machine->core_side);
    free(machine->core_leaf);
    free(machine->core_match);
    free(machine->core_lag);
    free(machine->core_width_first);
    free(machine->core_fields);
    machine->core_earlier = NULL;
    machine->core_later = NULL;
    machine->core_side = NULL;
    machine->core_leaf = NULL;
    machine->core_match = NULL;
    machine->core_lag = NULL;
    machine->core_width_first = NULL;
    machine->core_fields = NULL;
}

extern "C" int climb_machine_core(ClimbMachine *machine, ClimbMachineCore *core)
{
    if ((machine == NULL) || (core == NULL))
    {
        return 0;
    }
    memset(core, 0, sizeof(*core));
    machine_core_release(machine);
    const unsigned long long started = engine_clock_microseconds();
    const MachineGeometry geometry = machine->geometry;
    const unsigned int least_plane_side = (geometry.height < geometry.width) ? geometry.height : geometry.width;
    const unsigned int least_side = (geometry.depth < least_plane_side) ? geometry.depth : least_plane_side;
    const unsigned int widest = (least_side + 1u) / 2u;
    unsigned int listed_count = 0u;
    for (unsigned int pair = 0u; pair < machine->ran_count; pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        listed_count += (pending->later == (pending->earlier + 1u)) ? (pending->earlier_leaves + pending->later_leaves)
                                                                    : 0u;
    }
    // listed_count widens from unsigned int to size_t, so listed_count + 1 cannot wrap in 32 bits
    const size_t room = (size_t)listed_count + 1u;
    const size_t slots = machine->capacity;
    machine->core_earlier = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->core_later = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->core_side = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->core_leaf = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->core_match = (unsigned int *)malloc(room * sizeof(unsigned int));
    machine->core_lag = (int *)malloc(room * 3u * sizeof(int));
    machine->core_width_first = (unsigned int *)malloc((room + 1u) * sizeof(unsigned int));
    unsigned int *const listed_slot = (unsigned int *)malloc(room * sizeof(unsigned int));
    unsigned int *const listed_run_first = (unsigned int *)malloc(room * sizeof(unsigned int));
    unsigned int *const listed_run_past = (unsigned int *)malloc(room * sizeof(unsigned int));
    int *const listed_center = (int *)malloc(room * 3u * sizeof(int));
    unsigned int *const widths = (unsigned int *)calloc(room, sizeof(unsigned int));
    size_t *const staged_at = (size_t *)calloc(room, sizeof(size_t));
    unsigned int *const slot_first = (unsigned int *)calloc(slots + 1u, sizeof(unsigned int));
    unsigned int *const slot_order = (unsigned int *)malloc(room * sizeof(unsigned int));
    int steps_succeeded = (widest != 0u) && (machine->core_earlier != NULL) && (machine->core_later != NULL)
                       && (machine->core_side != NULL) && (machine->core_leaf != NULL) && (machine->core_match != NULL)
                       && (machine->core_lag != NULL) && (machine->core_width_first != NULL) && (listed_slot != NULL)
                       && (listed_run_first != NULL) && (listed_run_past != NULL) && (listed_center != NULL)
                       && (widths != NULL) && (staged_at != NULL) && (slot_first != NULL) && (slot_order != NULL);
    unsigned int climber_first = 0u;
    unsigned int listed_written = 0u;
    for (unsigned int pair = 0u; steps_succeeded && (pair < machine->ran_count); pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        const unsigned int adjacent = (pending->later == (pending->earlier + 1u)) ? 1u : 0u;
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int leaves = (side == 0u) ? pending->earlier_leaves : pending->later_leaves;
            for (unsigned int leaf = 0u; (adjacent != 0u) && (leaf < leaves); leaf += 1u)
            {
                const unsigned int climber = climber_first + leaf;
                const unsigned int index = machine->climber_side[climber];
                const unsigned int own_slot = machine->side_slots[2u * index];
                const unsigned int *const leaf_bundles = machine->slot_leaf_bundles[own_slot];
                const unsigned int bundle_first = leaf_bundles[leaf];
                const unsigned int bundle_past = leaf_bundles[leaf + 1u];
                // own_slot * run_room narrows from size_t to unsigned int exactly, as machine_cut_runs holds capacity * run_room within 32 bits
                const unsigned int run_base = (unsigned int)(own_slot * machine->run_room);
                const unsigned int empty = (bundle_past <= bundle_first) ? 1u : 0u;
                machine->core_earlier[listed_written] = pending->earlier;
                machine->core_later[listed_written] = pending->later;
                machine->core_side[listed_written] = side;
                machine->core_leaf[listed_written] = leaf;
                machine->core_match[listed_written] = machine->landed[climber];
                listed_slot[listed_written] = machine->side_slots[(2u * index) + 1u];
                listed_run_first[listed_written] =
                    (empty != 0u) ? 0u : (run_base + machine->slot_bundle_first[own_slot][bundle_first]);
                listed_run_past[listed_written] =
                    (empty != 0u) ? 0u : (run_base + machine->slot_bundle_past[own_slot][bundle_past - 1u]);
                listed_center[3u * listed_written] = machine->centers[3u * climber];
                listed_center[(3u * listed_written) + 1u] = machine->centers[(3u * climber) + 1u];
                listed_center[(3u * listed_written) + 2u] = machine->centers[(3u * climber) + 2u];
                machine->core_lag[3u * listed_written] = listed_center[3u * listed_written];
                machine->core_lag[(3u * listed_written) + 1u] = listed_center[(3u * listed_written) + 1u];
                machine->core_lag[(3u * listed_written) + 2u] = listed_center[(3u * listed_written) + 2u];
                slot_first[listed_slot[listed_written] + 1u] +=
                    (machine->landed[climber] != CLIMB_MACHINE_OUTSIDE) ? 1u : 0u;
                listed_written += 1u;
            }
            climber_first += leaves;
        }
    }
    for (size_t slot = 0u; steps_succeeded && (slot < slots); slot += 1u)
    {
        slot_first[slot + 1u] += slot_first[slot];
    }
    unsigned int *const slot_fill =
        steps_succeeded ? (unsigned int *)malloc((slots + 1u) * sizeof(unsigned int)) : NULL;
    steps_succeeded = steps_succeeded && (slot_fill != NULL);
    if (steps_succeeded)
    {
        memcpy(slot_fill, slot_first, (slots + 1u) * sizeof(unsigned int));
    }
    for (unsigned int listed_place = 0u; steps_succeeded && (listed_place < listed_count); listed_place += 1u)
    {
        if (machine->core_match[listed_place] == CLIMB_MACHINE_OUTSIDE)
        {
            continue;
        }
        slot_order[slot_fill[listed_slot[listed_place]]] = listed_place;
        slot_fill[listed_slot[listed_place]] += 1u;
    }
    unsigned int most_slot_items = 0u;
    for (size_t slot = 0u; steps_succeeded && (slot < slots); slot += 1u)
    {
        const unsigned int slot_items = slot_first[slot + 1u] - slot_first[slot];
        most_slot_items = (slot_items > most_slot_items) ? slot_items : most_slot_items;
    }
    // voxels narrows from unsigned long long to size_t exactly, as climb_machine_open already allocated this many labels
    const size_t voxels = (size_t)geometry.voxels;
    // most_slot_items widens from unsigned int to size_t before the multiply, so items * widest * 10 cannot wrap in 32 bits
    const size_t bins = (size_t)most_slot_items * widest * CLIMB_MACHINE_CORE_FIELDS;
    // most_slot_items widens from unsigned int to size_t, so most_slot_items + 1 cannot wrap in 32 bits
    const size_t item_room = (size_t)most_slot_items + 1u;
    unsigned int *painted = NULL;
    unsigned int *reach_first = NULL;
    unsigned int *reach_second = NULL;
    unsigned int *device_run_first = NULL;
    unsigned int *device_run_past = NULL;
    int *device_center = NULL;
    unsigned int *device_match = NULL;
    unsigned long long *device_bins = NULL;
    unsigned int *device_refused = NULL;
    unsigned int *const item_run_first = steps_succeeded ? (unsigned int *)malloc(item_room * sizeof(unsigned int)) : NULL;
    unsigned int *const item_run_past = steps_succeeded ? (unsigned int *)malloc(item_room * sizeof(unsigned int)) : NULL;
    int *const item_center = steps_succeeded ? (int *)malloc(item_room * 3u * sizeof(int)) : NULL;
    unsigned int *const item_match = steps_succeeded ? (unsigned int *)malloc(item_room * sizeof(unsigned int)) : NULL;
    unsigned long long *const host_bins =
        steps_succeeded ? (unsigned long long *)malloc((bins + 1u) * sizeof(unsigned long long)) : NULL;
    steps_succeeded = steps_succeeded && (item_run_first != NULL) && (item_run_past != NULL) && (item_center != NULL)
                   && (item_match != NULL) && (host_bins != NULL)
                   && (cudaMalloc((void **)&painted, voxels * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&reach_first, voxels * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&reach_second, voxels * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_run_first, item_room * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_run_past, item_room * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_center, item_room * 3u * sizeof(int)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_match, item_room * sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_bins, (bins + 1u) * sizeof(unsigned long long)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_refused, sizeof(unsigned int)) == cudaSuccess)
                   && (cudaMemset(device_refused, 0, sizeof(unsigned int)) == cudaSuccess);
    unsigned long long *staged = NULL;
    size_t staged_room = 0u;
    size_t staged_count = 0u;
    const unsigned int rows = geometry.depth * geometry.height;
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int height_columns = geometry.depth * geometry.width;
    for (unsigned int slot = 0u; steps_succeeded && (slot < machine->capacity); slot += 1u)
    {
        const unsigned int slot_item_first = slot_first[slot];
        const unsigned int slot_items = slot_first[slot + 1u] - slot_item_first;
        if (slot_items == 0u)
        {
            continue;
        }
        for (unsigned int item = 0u; item < slot_items; item += 1u)
        {
            const unsigned int listed_place = slot_order[slot_item_first + item];
            item_run_first[item] = listed_run_first[listed_place];
            item_run_past[item] = listed_run_past[listed_place];
            item_center[3u * item] = listed_center[3u * listed_place];
            item_center[(3u * item) + 1u] = listed_center[(3u * listed_place) + 1u];
            item_center[(3u * item) + 2u] = listed_center[(3u * listed_place) + 2u];
            item_match[item] = machine->core_match[listed_place];
        }
        const size_t base = slot * machine->run_room;
        const unsigned int runs = machine->slot_runs[slot];
        // slot_items widens from unsigned int to size_t before the multiply, so items * widest * 10 cannot wrap in 32 bits
        const size_t slot_bins = (size_t)slot_items * widest * CLIMB_MACHINE_CORE_FIELDS;
        steps_succeeded =
            (cudaMemset(painted, 0xFF, voxels * sizeof(unsigned int)) == cudaSuccess)
         && (cudaMemset(device_bins, 0, slot_bins * sizeof(unsigned long long)) == cudaSuccess)
         && (cudaMemcpy(device_run_first, item_run_first, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice)
             == cudaSuccess)
         && (cudaMemcpy(device_run_past, item_run_past, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice)
             == cudaSuccess)
         && (cudaMemcpy(device_center, item_center, slot_items * sizeof(int) * 3u, cudaMemcpyHostToDevice)
             == cudaSuccess)
         && (cudaMemcpy(device_match, item_match, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice)
             == cudaSuccess);
        if (steps_succeeded && (runs != 0u))
        {
            machine_paint_kernel<<<(runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                &machine->run_start[base], &machine->run_length[base], &machine->run_leaf[base], runs, painted);
            steps_succeeded = machine_launched();
        }
        if (steps_succeeded)
        {
            machine_reach_row_kernel<<<(rows + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                painted, geometry, reach_first);
            machine_reach_column_kernel<<<(height_columns + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK,
                                          CLIMB_MACHINE_BLOCK>>>(painted, geometry, 1u, reach_first, reach_second);
            machine_reach_column_kernel<<<(plane + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK,
                                          CLIMB_MACHINE_BLOCK>>>(painted, geometry, 0u, reach_second, reach_first);
            machine_core_kernel<<<(slot_items + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                slot_items, device_run_first, device_run_past, device_center, device_match, machine->run_start,
                machine->run_length, painted, reach_first, geometry, widest, device_bins, device_refused);
            steps_succeeded = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
        }
        steps_succeeded = steps_succeeded
                       && (cudaMemcpy(host_bins, device_bins, slot_bins * sizeof(unsigned long long),
                                      cudaMemcpyDeviceToHost) == cudaSuccess);
        for (unsigned int item = 0u; steps_succeeded && (item < slot_items); item += 1u)
        {
            const unsigned int listed_place = slot_order[slot_item_first + item];
            // item widens from unsigned int to size_t before the multiply, so item * widest * 10 cannot wrap in 32 bits
            const unsigned long long *const item_bins = &host_bins[(size_t)item * widest * CLIMB_MACHINE_CORE_FIELDS];
            unsigned int top_width = 0u;
            for (unsigned int width = 0u; width < widest; width += 1u)
            {
                // width widens from unsigned int to size_t, matching the size_t offset item_bins is indexed by
                top_width = (item_bins[(size_t)width * CLIMB_MACHINE_CORE_FIELDS] != 0ull) ? (width + 1u) : top_width;
            }
            if ((staged_count + top_width) > staged_room)
            {
                const size_t grown_room = ((staged_count + top_width) * 2u) + 1u;
                unsigned long long *const grown = (unsigned long long *)realloc(
                    staged, grown_room * CLIMB_MACHINE_CORE_FIELDS * sizeof(unsigned long long));
                steps_succeeded = (grown != NULL);
                staged = steps_succeeded ? grown : staged;
                staged_room = steps_succeeded ? grown_room : staged_room;
            }
            for (unsigned int width = top_width; steps_succeeded && (width > 0u); width -= 1u)
            {
                // width - 1 widens from unsigned int to size_t, matching the size_t offset item_bins is indexed by
                const size_t item_offset = (size_t)(width - 1u) * CLIMB_MACHINE_CORE_FIELDS;
                const size_t staged_offset = (staged_count + width - 1u) * CLIMB_MACHINE_CORE_FIELDS;
                for (unsigned int field = 0u; field < CLIMB_MACHINE_CORE_FIELDS; field += 1u)
                {
                    const unsigned long long wider_sum =
                        (width == top_width) ? 0ull : staged[staged_offset + CLIMB_MACHINE_CORE_FIELDS + field];
                    staged[staged_offset + field] = item_bins[item_offset + field] + wider_sum;
                }
            }
            staged_at[listed_place] = staged_count;
            widths[listed_place] = top_width;
            staged_count += steps_succeeded ? top_width : 0u;
        }
    }
    unsigned int refused = 0u;
    steps_succeeded = steps_succeeded
                   && (cudaMemcpy(&refused, device_refused, sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess)
                   && (refused == 0u) && (staged_count <= 0xFFFFFFFFull);
    machine->core_fields = steps_succeeded ? (unsigned long long *)malloc((staged_count + 1u) * CLIMB_MACHINE_CORE_FIELDS
                                                                          * sizeof(unsigned long long))
                                           : NULL;
    steps_succeeded = steps_succeeded && (machine->core_fields != NULL);
    size_t widths_written = 0u;
    for (unsigned int listed_place = 0u; steps_succeeded && (listed_place < listed_count); listed_place += 1u)
    {
        // widths_written is at most staged_count, held within 32 bits above, so it narrows from size_t to unsigned int exactly
        machine->core_width_first[listed_place] = (unsigned int)widths_written;
        memcpy(&machine->core_fields[widths_written * CLIMB_MACHINE_CORE_FIELDS],
               &staged[staged_at[listed_place] * CLIMB_MACHINE_CORE_FIELDS],
               widths[listed_place] * sizeof(unsigned long long) * CLIMB_MACHINE_CORE_FIELDS);
        widths_written += widths[listed_place];
    }
    if (steps_succeeded)
    {
        // widths_written equals staged_count, held within 32 bits above, so it narrows from size_t to unsigned int exactly
        machine->core_width_first[listed_count] = (unsigned int)widths_written;
    }
    cudaFree(painted);
    cudaFree(reach_first);
    cudaFree(reach_second);
    cudaFree(device_run_first);
    cudaFree(device_run_past);
    cudaFree(device_center);
    cudaFree(device_match);
    cudaFree(device_bins);
    cudaFree(device_refused);
    free(item_run_first);
    free(item_run_past);
    free(item_center);
    free(item_match);
    free(host_bins);
    free(staged);
    free(slot_fill);
    free(slot_order);
    free(slot_first);
    free(staged_at);
    free(widths);
    free(listed_center);
    free(listed_run_past);
    free(listed_run_first);
    free(listed_slot);
    if (steps_succeeded == 0)
    {
        machine_core_release(machine);
        return 0;
    }
    core->climbers = listed_count;
    core->earlier = machine->core_earlier;
    core->later = machine->core_later;
    core->side = machine->core_side;
    core->leaf = machine->core_leaf;
    core->match = machine->core_match;
    core->lag = machine->core_lag;
    core->width_first = machine->core_width_first;
    core->fields = machine->core_fields;
    // widths_written equals staged_count, held within 32 bits above, so it narrows from size_t to unsigned int exactly
    core->widths = (unsigned int)widths_written;
    core->microseconds = engine_clock_microseconds() - started;
    return 1;
}

__global__ static void machine_extent_kernel(const unsigned int *run_start, const unsigned int *run_length,
                                             const unsigned int *run_leaf, unsigned int runs, MachineGeometry geometry,
                                             unsigned int *extents)
{
    const unsigned int run = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (run >= runs)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int start = run_start[run];
    const unsigned int rest = start % plane;
    const unsigned int depth_place = start / plane;
    const unsigned int height_place = rest / geometry.width;
    const unsigned int width_place = rest % geometry.width;
    unsigned int *const extent = &extents[CLIMB_MACHINE_EXTENT_FIELDS * run_leaf[run]];
    atomicMin(&extent[0], depth_place);
    atomicMin(&extent[1], height_place);
    atomicMin(&extent[2], width_place);
    atomicMax(&extent[3], depth_place);
    atomicMax(&extent[4], height_place);
    atomicMax(&extent[5], width_place + run_length[run] - 1u);
}

extern "C" int climb_machine_extents(ClimbMachine *machine, const ClimbMachineExtentsRequest *request)
{
    const unsigned int slot = ((machine != NULL) && (request != NULL) && (request->extents != NULL))
                            ? machine_slot_of(machine, request->frame)
                            : CLIMB_MACHINE_EMPTY;
    if (slot == CLIMB_MACHINE_EMPTY)
    {
        return 0;
    }
    const unsigned int leaves = machine->slot_leaves[slot];
    const unsigned int runs = machine->slot_runs[slot];
    const unsigned int axes = CLIMB_MACHINE_EXTENT_FIELDS / 2u;
    // leaves widens from unsigned int to size_t before the multiply, so leaves * 6 cannot wrap in 32 bits
    const size_t fields = (size_t)leaves * CLIMB_MACHINE_EXTENT_FIELDS;
    unsigned int *const initial_extents = (unsigned int *)malloc((fields + 1u) * sizeof(unsigned int));
    for (unsigned int leaf = 0u; (initial_extents != NULL) && (leaf < leaves); leaf += 1u)
    {
        for (unsigned int axis = 0u; axis < axes; axis += 1u)
        {
            initial_extents[(CLIMB_MACHINE_EXTENT_FIELDS * leaf) + axis] = 0xFFFFFFFFu;
            initial_extents[(CLIMB_MACHINE_EXTENT_FIELDS * leaf) + axes + axis] = 0u;
        }
    }
    unsigned int *device_extents = NULL;
    int steps_succeeded =
        (initial_extents != NULL)
     && (cudaMalloc((void **)&device_extents, (fields + 1u) * sizeof(unsigned int)) == cudaSuccess)
     && (cudaMemcpy(device_extents, initial_extents, fields * sizeof(unsigned int), cudaMemcpyHostToDevice)
         == cudaSuccess);
    if (steps_succeeded && (runs != 0u))
    {
        const size_t base = slot * machine->run_room;
        machine_extent_kernel<<<(runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
            &machine->run_start[base], &machine->run_length[base], &machine->run_leaf[base], runs, machine->geometry,
            device_extents);
        steps_succeeded = machine_launched();
    }
    steps_succeeded = steps_succeeded
                   && (cudaMemcpy(request->extents, device_extents, fields * sizeof(unsigned int),
                                  cudaMemcpyDeviceToHost) == cudaSuccess);
    cudaFree(device_extents);
    free(initial_extents);
    return steps_succeeded ? 1 : 0;
}

extern "C" void climb_machine_close(ClimbMachine *machine)
{
    if (machine == NULL)
    {
        return;
    }
    cudaFree(machine->scratch_labels);
    cudaFree(machine->positive);
    cudaFree(machine->row_first);
    for (unsigned int slot = 0u; (machine->slot_leaf_bundles != NULL) && (slot < machine->capacity); slot += 1u)
    {
        free(machine->slot_leaf_bundles[slot]);
        free(machine->slot_bundle_first[slot]);
        free(machine->slot_bundle_past[slot]);
        free(machine->slot_contact_start[slot]);
        free(machine->slot_contacts[slot]);
    }
    free(machine->slot_frame);
    free(machine->slot_leaves);
    free(machine->slot_runs);
    free(machine->slot_leaf_bundles);
    free(machine->slot_bundle_first);
    free(machine->slot_bundle_past);
    free(machine->slot_contact_start);
    free(machine->slot_contacts);
    cudaFree(machine->run_start);
    cudaFree(machine->run_length);
    cudaFree(machine->run_leaf);
    cudaFree(machine->run_at_row);
    cudaFree(machine->device_map);
    cudaFree(machine->device_peaks);
    free(machine->row_counts);
    cudaFree(machine->device_row_counts);
    cudaFree(machine->device_row_offsets);
    cudaFree(machine->device_cut_start);
    cudaFree(machine->device_cut_length);
    cudaFree(machine->device_cut_leaf);
    free(machine->cut_leaf);
    free(machine->order);
    cudaFree(machine->device_order);
    free(machine->leaf_counts);
    free(machine->pending);
    free(machine->side_slots);
    cudaFree(machine->device_side_slots);
    free(machine->climber_side);
    free(machine->climber_peak);
    free(machine->climber_entry_start);
    free(machine->centers);
    free(machine->active);
    free(machine->landed);
    free(machine->held);
    cudaFree(machine->device_held);
    cudaFree(machine->device_climber_side);
    cudaFree(machine->device_climber_peak);
    cudaFree(machine->device_climber_entry_start);
    cudaFree(machine->device_centers);
    cudaFree(machine->device_active);
    cudaFree(machine->device_landed);
    free(machine->entry_first);
    free(machine->entry_past);
    free(machine->entry_climber);
    cudaFree(machine->device_entry_first);
    cudaFree(machine->device_entry_past);
    cudaFree(machine->device_entry_climber);
    cudaFree(machine->device_scores);
    cudaFree(machine->device_moved);
    cudaFreeHost(machine->pinned_moved);
    cudaFreeHost(machine->pinned_zero);
    if (machine->blocks_done[0] != NULL)
    {
        cudaEventDestroy(machine->blocks_done[0]);
    }
    if (machine->blocks_done[1] != NULL)
    {
        cudaEventDestroy(machine->blocks_done[1]);
    }
    machine_box_release(machine);
    machine_core_release(machine);
    free(machine);
}
