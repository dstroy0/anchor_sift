/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file climb_machine.cu
 * @brief The frame store and the self-running climb of climb_machine.h.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-17
 *
 * Sign words and runs are one device array per kind with a slot per frame; labels are a ring of two, because a
 * frame's labels are read only while its runs are cut and while the overlap engine reads the pair it belongs
 * to. Runs are cut on the device from the labels in the ring, one thread per row, counted and then written in
 * row order; only each run's leaf comes to the host, which orders the runs by leaf, and the device gathers them
 * into the slot in that order, writing back where each run in row order landed. A landing looks a voxel up in
 * those runs, halving over its row, in place of reading a label. A leaf's runs are bundled a few at a time, so
 * every thread of a tick does work of like size.
 *
 * A run lays every pending pair out as two sides, forward and backward; every leaf of a side is a climber;
 * every bundle a climber walks, its own and, where the climb is sticky, its contacts', is an entry. A tick is
 * two launches: the score kernel, one thread per entry, and the decide kernel, one thread per climber. Nothing
 * crosses to the host inside a tick. After each block of ticks one cell, set wherever any climber moved, is
 * copied without waiting into pinned memory, and the host reads it once that block has run; while two blocks
 * are queued the host waits on the older one, so the queue never outgrows the device. A block in which nothing
 * moved is past every fixed point.
 */

#include "climb_machine.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define CLIMB_MACHINE_BLOCK 256u

/** @brief Most runs one entry thread walks, so no thread waits long on another beside it. */
#define CLIMB_MACHINE_BUNDLE 32u

/** @brief Candidate lags per tick: the climber's lag, at index 13, and its 26 neighbours in z y x order. */
#define CLIMB_MACHINE_CANDIDATES 27u

/** @brief Ticks queued between two looks at whether anything moved. */
#define CLIMB_MACHINE_TICKS 8u

/** @brief A slot holding no frame. */
#define CLIMB_MACHINE_EMPTY 0xFFFFFFFFu

/** @brief A landing outside the view. */
#define CLIMB_MACHINE_OUTSIDE 0xFFFFFFFFu

static_assert(sizeof(unsigned int) == 4u, "climb_machine: unsigned int must be 32 bits, a label");
static_assert(sizeof(unsigned long long) == 8u, "climb_machine: unsigned long long must be 64 bits, a sign word");

/** @brief Extents and strides a kernel reads, passed by value. */
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
    // The labels of a frame are held only while its runs are cut and while the overlap engine reads the pair it
    // belongs to, so two frames' labels are kept in a ring and every stored frame is its runs.
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
    // A frame's runs in row order, as places in its own leaf-ordered runs, and where each row's runs begin: what a
    // landing reads in place of a label at every voxel.
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
};

/**
 * @brief 64 sign bits of one slot starting at a bit; bits past the slot's last word read as zero.
 *
 * @param[in] positive  Every slot's sign words [BORROWS].
 * @param[in] base_word The slot's first word.
 * @param[in] words     Words per slot.
 * @param[in] bit       The first bit, counted within the slot.
 * @return              The bits, the first in the lowest place.
 */
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

/**
 * @brief The set bits of a word, by adding them in pairs, nibbles and bytes.
 *
 * @param[in] value The word.
 * @return          Its population count.
 */
__device__ static unsigned int machine_ones(unsigned long long value)
{
    const unsigned long long pairs = value - ((value >> 1u) & 0x5555555555555555ull);
    const unsigned long long nibbles = (pairs & 0x3333333333333333ull) + ((pairs >> 2u) & 0x3333333333333333ull);
    const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0Full;
    // Narrowing is safe: the count is at most 64.
    return (unsigned int)((bytes * 0x0101010101010101ull) >> 56u);
}

/**
 * @brief How many of count consecutive bits of one row equal the bits of another, a word at a time.
 *
 * @param[in] positive   Every slot's sign words [BORROWS].
 * @param[in] words      Words per slot.
 * @param[in] own_word   The first slot's first word.
 * @param[in] own_bit    The first bit compared there.
 * @param[in] other_word The second slot's first word.
 * @param[in] other_bit  The first bit compared there.
 * @param[in] count      Bits compared.
 * @return               Equal bits.
 */
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

/**
 * @brief One entry's runs, counted true at all 27 candidates around its climber's lag.
 *
 * @param[in]  run_start     Every stored run's first voxel [BORROWS].
 * @param[in]  run_length    Every stored run's voxels [BORROWS].
 * @param[in]  entry_first   Per entry, its first run in the arena [BORROWS].
 * @param[in]  entry_past    Per entry, the run past its last [BORROWS].
 * @param[in]  entry_climber Per entry, the climber [BORROWS].
 * @param[in]  entries       Entries.
 * @param[in]  climber_side  Per climber, its side [BORROWS].
 * @param[in]  side_slots    Two per side: the climbing slot, then the slot landed in [BORROWS].
 * @param[in]  centers       Three per climber: its lag [BORROWS].
 * @param[in]  active        Per climber, 1 while it has not reached its fixed point [BORROWS].
 * @param[in]  positive      Every slot's sign words [BORROWS].
 * @param[in]  geometry      Extents and strides.
 * @param[out] scores        CLIMB_MACHINE_CANDIDATES true counts per entry [BORROWS].
 */
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
    // Widening each slot to unsigned long long keeps every stride product exact.
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
        // Widening to long long keeps a negative landing representable before the bounds test.
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
                    // The run's voxel i lands at x + i of one row; a landing outside the view is false, so only
                    // the voxels landing inside it are compared.
                    const long long x = base_x + step_x;
                    const long long first = (x < 0ll) ? -x : 0ll;
                    const long long width_left = (long long)geometry.width - x;
                    const long long past = (width_left < length) ? width_left : length;
                    if ((inside_z != 0) && (inside_y != 0) && (first < past))
                    {
                        // Widening is safe: the row and every compared landing lie inside the view.
                        const unsigned long long row = (unsigned long long)((z * (long long)geometry.height + y)
                                                                            * (long long)geometry.width);
                        // Narrowing is safe: a run lies within one row, so its length fits an unsigned int.
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

/**
 * @brief One climber's step: its entries' counts summed per candidate, then the most coherent neighbour taken
 *        where it is strictly more coherent than staying, the shorter weighted lag first among equals, then the
 *        first in z y x order. A climber that stays has reached its fixed point.
 *
 * @param[in]     climber_entry_start Per climber, the offset of its entries; climbers + 1 of them [BORROWS].
 * @param[in]     scores              The score kernel's counts [BORROWS].
 * @param[in]     climbers            Climbers.
 * @param[in]     geometry            The weight of z.
 * @param[in,out] centers             Three per climber: its lag [BORROWS].
 * @param[in,out] active              Per climber, cleared where it stays [BORROWS].
 * @param[out]    moved               Set to 1 where any climber moves [BORROWS].
 * @param[out]    held                Per climber, its coherence at its fixed point, written where it stays [BORROWS].
 */
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
            // Widening an entry's count to long long is exact.
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
                // Widening: each squared lag component is nonnegative.
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
        // Narrowing is safe: a lag one step from an int lag inside any view fits an int.
        center[0] = (int)best[0];
        center[1] = (int)best[1];
        center[2] = (int)best[2];
        // Every thread that writes here writes the same 1.
        moved[0] = 1u;
    }
    else
    {
        active[climber] = 0u;
        // Narrowing is safe: a coherence counts voxels, below 2^32.
        held[climber] = (unsigned int)sums[13];
    }
}

/**
 * @brief Each climber's peak carried by its lag into the other frame, and the label it lands on.
 *
 * @param[in]  climber_side Per climber, its side [BORROWS].
 * @param[in]  side_slots   Two per side [BORROWS].
 * @param[in]  climber_peak Per climber, its peak's raster index [BORROWS].
 * @param[in]  centers      Three per climber: its lag [BORROWS].
 * @param[in]  row_first    Every slot's rows + 1 offsets into its runs in row order [BORROWS].
 * @param[in]  run_at_row   Every slot's runs in row order, as places in its leaf-ordered runs [BORROWS].
 * @param[in]  run_start    Every slot's runs' first voxels, leaf order [BORROWS].
 * @param[in]  run_length   Every slot's runs' voxels, leaf order [BORROWS].
 * @param[in]  run_leaf     Every slot's runs' leaves, leaf order [BORROWS].
 * @param[in]  run_room     Runs one slot holds.
 * @param[in]  climbers     Climbers.
 * @param[in]  geometry     Extents and strides.
 * @param[out] landed       Per climber, the leaf landed in, or CLIMB_MACHINE_OUTSIDE [BORROWS].
 */
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
    // Widening to long long keeps a negative landing representable before the bounds test.
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
    // Widening is safe: the landing lies inside the view, so it is nonnegative.
    const unsigned long long voxel = (unsigned long long)((z * (long long)geometry.height + y) * (long long)geometry.width + x);
    // The leaf holding the voxel: the run of its row that covers it, by halving over that row's runs, which are in
    // voxel order. A row of a frame holds no two runs of one leaf next to each other and none overlap, so the run
    // whose first voxel is the last one at or before the landing is the only run that can cover it.
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long row = voxel / geometry.width;
    const unsigned long long base = other * (unsigned long long)run_room;
    const unsigned long long offsets = other * (rows + 1ull);
    const unsigned int first = row_first[offsets + row];
    const unsigned int past = row_first[offsets + row + 1ull];
    // A row with no runs holds no leaf, and its one read is kept inside the slot's runs.
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

/**
 * @brief Marks or clears each leaf's peak in the peak map: the map holds the leaf at every peak of the frame
 *        being cut and -1 everywhere else.
 *
 * @param[in]     peaks  The frame's peaks, ascending [BORROWS].
 * @param[in]     leaves Leaves.
 * @param[in]     clear  1 to clear, 0 to mark.
 * @param[in,out] map    The peak map, one entry per voxel [BORROWS].
 */
__global__ static void machine_map_kernel(const unsigned int *peaks, unsigned int leaves, unsigned int clear, int *map)
{
    const unsigned int leaf = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (leaf >= leaves)
    {
        return;
    }
    // Narrowing is safe: a leaf count is below 2^31.
    map[peaks[leaf]] = (clear != 0u) ? -1 : (int)leaf;
}

/**
 * @brief One row's runs: counted, or written where the row's offset is given. A run is the voxels next to each
 *        other along the row carrying one label, where that label is a leaf's peak.
 *
 * @param[in]  labels     The frame's labels [BORROWS].
 * @param[in]  map        The peak map [BORROWS].
 * @param[in]  rows       Rows of the view.
 * @param[in]  geometry   Extents.
 * @param[in]  offsets    Per row, where its runs are written, or NULL to count [BORROWS].
 * @param[out] counts     Per row, its runs, written when counting [BORROWS].
 * @param[out] run_start  Per run, its first voxel, written when writing [BORROWS].
 * @param[out] run_length Per run, its voxels [BORROWS].
 * @param[out] run_leaf   Per run, its leaf [BORROWS].
 */
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
            // Narrowing is safe: the leaf was found, so it is nonnegative.
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

/**
 * @brief Gathers the runs, in row order, into a slot's run arrays in leaf order, and writes back where each run
 *        in row order landed, which is what a landing halves over.
 *
 * @param[in]  order      Per run in leaf order, its place in row order [BORROWS].
 * @param[in]  runs       Runs.
 * @param[in]  cut_start  First voxels in row order [BORROWS].
 * @param[in]  cut_length Lengths in row order [BORROWS].
 * @param[in]  cut_leaf   Leaves in row order [BORROWS].
 * @param[out] run_start  The slot's first voxels [BORROWS].
 * @param[out] run_length The slot's lengths [BORROWS].
 * @param[out] run_leaf   The slot's leaves [BORROWS].
 * @param[out] run_at_row Per run in row order, its place in leaf order [BORROWS].
 */
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
    // The order is a permutation, so every run in row order is written exactly once.
    run_at_row[at] = run;
}

/**
 * @brief Whether the kernel just launched was accepted.
 *
 * @return 1 where it was, 0 otherwise.
 */
static int machine_launched(void)
{
    // No synchronise: the machine's launches queue in order and run without the host.
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

/**
 * @brief The slot a frame is stored in.
 *
 * @param[in] machine The machine [BORROWS].
 * @param[in] frame   The frame's index.
 * @return            The slot, or CLIMB_MACHINE_EMPTY.
 */
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

/**
 * @brief Grows a host and a device array pair to hold a count of bytes; they never shrink and keep nothing.
 *
 * @param[in,out] host   The host array [BORROWS].
 * @param[in,out] device The device array [BORROWS].
 * @param[in]     bytes  Bytes needed.
 * @return               1 on success, 0 on a failure.
 */
static int machine_grow(void **host, void **device, size_t bytes)
{
    free(*host);
    cudaFree(*device);
    *device = NULL;
    *host = malloc(bytes);
    return ((*host != NULL) && (cudaMalloc(device, bytes) == cudaSuccess)) ? 1 : 0;
}

/**
 * @brief Cuts a stored frame's leaves into runs along its rows on the device, orders them by leaf, and bundles
 *        them. Each leaf's runs keep row order.
 *
 * @param[in,out] machine The machine, the frame's labels already in the scratch ring [BORROWS].
 * @param[in]     slot    The slot.
 * @param[in]     labels  The frame's labels on the device [BORROWS].
 * @param[in]     frame   The frame, with its peaks [BORROWS].
 * @return                1 on success, 0 on a failure.
 */
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
        // Narrowing is safe: the runs so far never exceed the voxels, which fit an unsigned int.
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
        // The map goes back to -1 at this frame's peaks, ready for the next frame's.
        machine_map_kernel<<<leaf_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_peaks, leaves, 1u, machine->device_map);
        ok = machine_launched();
    }
    ok = ok && ((runs == 0u) || (cudaMemcpy(machine->cut_leaf, machine->device_cut_leaf, runs * sizeof(unsigned int),
                                            cudaMemcpyDeviceToHost) == cudaSuccess));
    if (ok == 0)
    {
        return 0;
    }

    // Counted by leaf and placed in row order, so each leaf's runs stay in row order; each count ends as the
    // place past its leaf's last run.
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
        // Narrowing is safe: runs never exceed the voxels.
        machine->order[counts[leaf]] = (unsigned int)run;
        counts[leaf] += 1u;
    }

    // Where this frame has more runs than a slot holds, every slot grows and every stored frame's runs move. The
    // four arrays are one frame's whole representation, so they grow together.
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
        // Narrowing is safe: runs never exceed the voxels.
        const unsigned int run_blocks = (unsigned int)((runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK);
        machine_gather_kernel<<<run_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_order, (unsigned int)runs,
                                                                   machine->device_cut_start, machine->device_cut_length,
                                                                   machine->device_cut_leaf, &machine->run_start[base],
                                                                   &machine->run_length[base], &machine->run_leaf[base],
                                                                   &machine->run_at_row[base]);
        ok = machine_launched();
    }
    // Where each row's runs begin, and the total past the last row: what a landing halves inside.
    if (ok != 0)
    {
        const size_t offsets = (size_t)slot * ((size_t)rows + 1u);
        // Narrowing is safe: runs never exceed the voxels.
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
    // Every leaf's runs make at most one bundle more than its runs fill.
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
        // Narrowing is safe: runs never exceed the voxels.
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
    // Every frame asked for is held, because a frame held is its runs and its sign words, which is small. Nothing
    // here is sized from the free memory: what is stored is what the frames contain.
    machine->capacity = (shape->frames < 2u) ? 2u : shape->frames;
    const size_t slots = (size_t)machine->capacity;
    int ok = 1;
    // Two frames' labels, and no more: a frame's labels are read while its runs are cut and while the overlap
    // engine reads the pair it belongs to, which is the frame before it and itself.
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
    // The peak map starts -1 everywhere: every byte of every entry set.
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
        // Every slot is taken: the pairs waiting on these frames run now, and all but the newest frame are let go.
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
    // Widening each slot to size_t keeps every stride product exact.
    const size_t at = (size_t)slot;
    // The labels take the older half of the ring; the frame stored before this one keeps the other half.
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
        // The labels are in the ring now, so the runs are cut from them and the slot keeps the runs.
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

extern "C" const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame)
{
    if (machine == NULL)
    {
        return NULL;
    }
    // Only the two frames in the ring have labels; a frame stored earlier than that is its runs.
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
    // Two sides per pair: forward, the earlier frame's leaves against the later, and backward.
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

    // Lay every side out: its slots, its climbers from the start lag, and each climber's entries.
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
            // Narrowing is safe: the run arrays were held to 2^32 entries when they grew.
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
                // The basin's own bundles, then each contact's where the climb is sticky, as climb_lag sums them.
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

    // The machine runs itself: blocks of ticks queue one after another, and the host only watches for a block
    // that moved nothing.
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
            // The block before this one: once it has run, whether it moved anything is known.
            const unsigned int previous = 1u - parity;
            ok = (cudaEventSynchronize(machine->blocks_done[previous]) == cudaSuccess) ? 1 : 0;
            settled = ((ok != 0) && (machine->pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }

    if ((ok != 0) && (climber != 0u))
    {
        // Narrowing is safe: the run arrays were held to 2^32 entries when they grew.
        machine_land_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
            machine->device_climber_side, machine->device_side_slots, machine->device_climber_peak,
            machine->device_centers, machine->row_first, machine->run_at_row, machine->run_start, machine->run_length,
            machine->run_leaf, (unsigned int)machine->run_room, climber, geometry, machine->device_landed);
        ok = machine_launched();
    }
    ok = ok && (cudaMemcpy(machine->centers, machine->device_centers, climbers * 3u * sizeof(int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->landed, machine->device_landed, climbers * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->held, machine->device_held, climbers * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);

    // Every output goes back to the pair it was pended with.
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
                // The landing is already the other frame's leaf: the run it fell in carries it.
                // Narrowing is safe: a leaf count is below 2^31.
                landing_out[leaf] = (machine->landed[climber] == CLIMB_MACHINE_OUTSIDE)
                                  ? CLIMB_MACHINE_NO_LEAF : (int)machine->landed[climber];
                climber += 1u;
            }
        }
    }
    machine->pending_count = 0u;
    return ok;
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
    free(machine);
}
