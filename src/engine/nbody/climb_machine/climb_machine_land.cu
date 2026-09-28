// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_land.cu: land, boxes, maps and rows
#include "climb_machine_internal.h"

__global__ void machine_land_mass_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                         const unsigned int *climber_entry_start, const unsigned int *entry_first,
                                         const unsigned int *entry_end, const int *centers,
                                         const unsigned int *row_first, const unsigned int *run_at_row,
                                         const unsigned int *run_start, const unsigned int *run_length,
                                         const unsigned int *run_leaf, unsigned int run_capacity, unsigned int climbers,
                                         const int *spiral, unsigned int tries, MachineGeometry geometry,
                                         unsigned int *landed)
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
            for (unsigned int entry = climber_entry_start[climber]; entry < climber_entry_start[climber + 1u];
                 entry += 1u)
            {
                for (unsigned int run = entry_first[entry]; run < entry_end[entry]; run += 1u)
                {
                    const unsigned int start = run_start[run];
                    const unsigned int length = run_length[run];
                    const unsigned int rest = start % plane;
                    const long long z = (long long)(start / plane) + (long long)lag_z;
                    const long long y = (long long)(rest / geometry.width) + (long long)lag_y;
                    const long long base_x = (long long)(rest % geometry.width) + (long long)lag_x;
                    const int inside =
                        (z >= 0ll) && (z < (long long)geometry.depth) && (y >= 0ll) && (y < (long long)geometry.height);
                    for (unsigned int step = 0u; (inside != 0) && (step < length); step += 1u)
                    {
                        const long long x = base_x + (long long)step;
                        if ((x < 0ll) || (x >= (long long)geometry.width))
                        {
                            continue;
                        }
                        const unsigned long long voxel =
                            (unsigned long long)((z * (long long)geometry.height + y) * (long long)geometry.width + x);
                        const unsigned int reached = machine_leaf_at(voxel, other, row_first, run_at_row, run_start,
                                                                     run_length, run_leaf, run_capacity, geometry);
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
        const unsigned int ahead = (unsigned int)((candidate != CLIMB_MACHINE_OUTSIDE) && (agreed > best_agreed));
        best_leaf = (ahead != 0u) ? candidate : best_leaf;
        best_agreed = (ahead != 0u) ? agreed : best_agreed;
    }
    landed[climber] = best_leaf;
}

__global__ void machine_land_kernel(const unsigned int *climber_side, const unsigned int *side_slots,
                                    const unsigned int *climber_peak, const int *centers, const unsigned int *row_first,
                                    const unsigned int *run_at_row, const unsigned int *run_start,
                                    const unsigned int *run_length, const unsigned int *run_leaf,
                                    unsigned int run_capacity, unsigned int climbers, MachineGeometry geometry,
                                    unsigned int *landed)
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
    if ((z < 0ll) || (z >= (long long)geometry.depth) || (y < 0ll) || (y >= (long long)geometry.height) || (x < 0ll) ||
        (x >= (long long)geometry.width))
    {
        landed[climber] = CLIMB_MACHINE_OUTSIDE;
        return;
    }
    const unsigned long long other = (unsigned long long)side_slots[(2u * climber_side[climber]) + 1u];
    const unsigned long long voxel =
        (unsigned long long)((z * (long long)geometry.height + y) * (long long)geometry.width + x);
    const unsigned long long rows = (unsigned long long)geometry.depth * geometry.height;
    const unsigned long long row = voxel / geometry.width;
    const unsigned long long base = other * (unsigned long long)run_capacity;
    const unsigned long long offsets = other * (rows + 1ull);
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
    landed[climber] = (covers != 0u) ? run_leaf[base + at] : CLIMB_MACHINE_OUTSIDE;
}

__global__ void machine_box_kernel(unsigned int cells, unsigned int writing, MachineBoxCells box,
                                   const unsigned int *climber_side, const unsigned int *side_slots,
                                   const unsigned int *climber_entry_start, const unsigned int *entry_first,
                                   const unsigned int *entry_end, const unsigned int *row_first,
                                   const unsigned int *run_at_row, const unsigned int *run_start,
                                   const unsigned int *run_length, const unsigned int *run_leaf,
                                   unsigned int run_capacity, const unsigned long long *positive,
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
    const unsigned long long base = other * (unsigned long long)run_capacity;
    const unsigned long long offsets = other * (rows + 1ull);
    const unsigned int plane = geometry.height * geometry.width;
    unsigned int targets[CLIMB_MACHINE_BOX_TARGETS];
    unsigned int counts[CLIMB_MACHINE_BOX_TARGETS];
    unsigned int used = 0u;
    unsigned int total = 0u;
    unsigned int labeled = 0u;
    unsigned int overflow = 0u;
    for (unsigned int entry = climber_entry_start[climber]; entry < climber_entry_start[climber + 1u]; entry += 1u)
    {
        for (unsigned int run = entry_first[entry]; run < entry_end[entry]; run += 1u)
        {
            const unsigned int start = run_start[run];
            const long long length = (long long)run_length[run];
            const unsigned int rest = start % plane;
            const long long z = (long long)(start / plane) + shift_z;
            const long long y = (long long)(rest / geometry.width) + shift_y;
            const long long x = (long long)(rest % geometry.width) + shift_x;
            const long long first = (x < 0ll) ? -x : 0ll;
            const long long width_left = (long long)geometry.width - x;
            const long long end = (width_left < length) ? width_left : length;
            if ((z < 0ll) || (z >= (long long)geometry.depth) || (y < 0ll) || (y >= (long long)geometry.height) ||
                (first >= end))
            {
                continue;
            }
            const unsigned long long row = (unsigned long long)(z * (long long)geometry.height + y);
            const unsigned int from = (unsigned int)(row * geometry.width + (unsigned long long)(x + first));
            const unsigned int to = from + (unsigned int)(end - first);
            total += machine_agreeing(positive, geometry.words, own_word,
                                      (unsigned long long)start + (unsigned long long)first, other_word,
                                      (unsigned long long)from, (unsigned int)(end - first));
            const unsigned int row_start = row_first[offsets + row];
            const unsigned int row_end = row_first[offsets + row + 1ull];
            for (unsigned int place = row_start; place < row_end; place += 1u)
            {
                const unsigned int at = run_at_row[base + place];
                const unsigned int there = run_start[base + at];
                const unsigned int there_end = there + run_length[base + at];
                const unsigned int meet = (there > from) ? there : from;
                const unsigned int leave = (there_end < to) ? there_end : to;
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
                unsigned int slot = used;
                for (unsigned int seen = 0u; seen < used; seen += 1u)
                {
                    slot = (targets[seen] == leaf) ? seen : slot;
                }
                if ((slot == used) && (used == CLIMB_MACHINE_BOX_TARGETS))
                {
                    overflow = 1u;
                    continue;
                }
                targets[slot] = leaf;
                counts[slot] = (slot == used) ? shared : (counts[slot] + shared);
                used += (slot == used) ? 1u : 0u;
            }
        }
    }
    const unsigned int outside = (total >= labeled) ? (total - labeled) : 0u;
    const unsigned int listed = (overflow != 0u) ? pieces : used;
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
    for (unsigned int slot = 0u; (raw == 0u) && (slot < used); slot += 1u)
    {
        box.target[write_at + slot] = targets[slot];
        box.count[write_at + slot] = counts[slot];
    }
    const unsigned int last = (raw != 0u) ? pieces : used;
    if (outside != 0u)
    {
        box.target[write_at + last] = CLIMB_MACHINE_BOX_NONE;
        box.count[write_at + last] = outside;
    }
}

__global__ void machine_map_kernel(const unsigned int *peaks, unsigned int leaves, unsigned int clear, int *map)
{
    const unsigned int leaf = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (leaf >= leaves)
    {
        return;
    }
    map[peaks[leaf]] = (clear != 0u) ? -1 : (int)leaf;
}

__global__ void machine_row_kernel(const unsigned int *labels, const int *map, unsigned int rows,
                                   MachineGeometry geometry, const unsigned int *offsets, unsigned int *counts,
                                   unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf)
{
    const unsigned int row = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (row >= rows)
    {
        return;
    }
    const unsigned int first = row * geometry.width;
    const unsigned int end = first + geometry.width;
    unsigned int slot = (offsets != NULL) ? offsets[row] : 0u;
    unsigned int runs = 0u;
    unsigned int voxel = first;
    while (voxel < end)
    {
        const unsigned int label = labels[voxel];
        const unsigned int start = voxel;
        voxel += 1u;
        while ((voxel < end) && (labels[voxel] == label))
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

__global__ void machine_gather_kernel(const unsigned int *order, unsigned int runs, const unsigned int *unsorted_start,
                                      const unsigned int *unsorted_length, const unsigned int *unsorted_leaf,
                                      unsigned int *run_start, unsigned int *run_length, unsigned int *run_leaf,
                                      unsigned int *run_at_row)
{
    const unsigned int run = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (run >= runs)
    {
        return;
    }
    const unsigned int at = order[run];
    run_start[run] = unsorted_start[at];
    run_length[run] = unsorted_length[at];
    run_leaf[run] = unsorted_leaf[at];
    run_at_row[at] = run;
}

int machine_launched(void)
{
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

unsigned int machine_slot_of(const ClimbMachine *machine, unsigned int frame)
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

int machine_grow(void **host, void **device, size_t bytes)
{
    free(*host);
    cudaFree(*device);
    *device = NULL;
    *host = malloc(bytes);
    return ((*host != NULL) && (cudaMalloc(device, bytes) == cudaSuccess)) ? 1 : 0;
}
