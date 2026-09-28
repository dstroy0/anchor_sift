// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_core.cu: painting, reach and the core
#include "climb_machine_internal.h"

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

__global__ static void machine_range_row_kernel(const unsigned int *painted, MachineGeometry geometry,
                                                unsigned int *range)
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
        range[voxel] = edge_distance;
    }
    edge_distance = 0u;
    for (unsigned int width_end = geometry.width; width_end > 0u; width_end -= 1u)
    {
        const unsigned int voxel = row_first + width_end - 1u;
        const unsigned int label_boundary =
            ((width_end == geometry.width) || (painted[voxel] != painted[voxel + 1u])) ? 1u : 0u;
        edge_distance = (label_boundary != 0u) ? 1u : (edge_distance + 1u);
        range[voxel] = (edge_distance < range[voxel]) ? edge_distance : range[voxel];
    }
}

__global__ static void machine_range_column_kernel(const unsigned int *painted, MachineGeometry geometry,
                                                   unsigned int axis, const unsigned int *range_in,
                                                   unsigned int *range_out)
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
    const unsigned int base = (axis == 0u) ? column : (((column / geometry.width) * plane) + (column % geometry.width));
    for (unsigned int place = 0u; place < extent; place += 1u)
    {
        const unsigned int voxel = base + (place * stride);
        const unsigned int label = painted[voxel];
        unsigned int least_range = range_in[voxel];
        for (unsigned int radius = 1u; (label != CLIMB_MACHINE_OUTSIDE) && (radius < least_range); radius += 1u)
        {
            for (unsigned int direction = 0u; direction < 2u; direction += 1u)
            {
                const unsigned int neighbor_inside =
                    (direction == 0u) ? ((radius <= place) ? 1u : 0u) : (((place + radius) < extent) ? 1u : 0u);
                const unsigned int neighbor_place = (direction == 0u) ? (place - radius) : (place + radius);
                const unsigned int neighbor = (neighbor_inside != 0u) ? (base + (neighbor_place * stride)) : 0u;
                const unsigned int neighbor_range =
                    ((neighbor_inside != 0u) && (painted[neighbor] == label)) ? range_in[neighbor] : 0u;
                const unsigned int candidate_range = (neighbor_range > radius) ? neighbor_range : radius;
                least_range = (candidate_range < least_range) ? candidate_range : least_range;
            }
        }
        range_out[voxel] = (label != CLIMB_MACHINE_OUTSIDE) ? least_range : 0u;
    }
}

__global__ static void machine_core_kernel(unsigned int items, const unsigned int *item_run_first,
                                           const unsigned int *item_run_end, const int *item_center,
                                           const unsigned int *item_match, const unsigned int *run_start,
                                           const unsigned int *run_length, const unsigned int *painted,
                                           const unsigned int *range, MachineGeometry geometry, unsigned int widest,
                                           unsigned long long *fields, unsigned int *error)
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
    // item widens from unsigned int to unsigned long long before the multiply. Item * widest * 10 cannot wrap in 32
    // bits
    unsigned long long *const item_bins = &fields[(unsigned long long)item * widest * CLIMB_MACHINE_CORE_FIELDS];
    for (unsigned int run = item_run_first[item]; run < item_run_end[item]; run += 1u)
    {
        const unsigned int start = run_start[run];
        const unsigned int rest = start % plane;
        const unsigned long long depth_place = start / plane;
        const unsigned long long height_place = rest / geometry.width;
        // depth_place is below geometry.depth, a 32-bit count. It re-signs to long long exactly
        const long long lagged_depth = (long long)depth_place + shift_depth;
        // height_place is below geometry.height, a 32-bit count. It re-signs to long long exactly
        const long long lagged_height = (long long)height_place + shift_height;
        if ((lagged_depth < 0ll) || (lagged_depth >= geometry.depth) || (lagged_height < 0ll) ||
            (lagged_height >= geometry.height))
        {
            continue;
        }
        const long long lagged_row = ((lagged_depth * geometry.height) + lagged_height) * geometry.width;
        for (unsigned int step = 0u; step < run_length[run]; step += 1u)
        {
            const unsigned long long width_place = (rest % geometry.width) + step;
            // width_place is below geometry.width, a 32-bit count. It re-signs to long long exactly
            const long long lagged_width = (long long)width_place + shift_width;
            if ((lagged_width < 0ll) || (lagged_width >= geometry.width) ||
                (painted[lagged_row + lagged_width] != match))
            {
                continue;
            }
            const unsigned int core_width = range[lagged_row + lagged_width] - 1u;
            if (core_width >= widest)
            {
                atomicAdd(error, 1u);
                continue;
            }
            // core_width widens from unsigned int to unsigned long long, matching the 64-bit offset item_bins is
            // indexed by
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

void machine_core_release(ClimbMachine *machine)
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
        listed_count +=
            (pending->later == (pending->earlier + 1u)) ? (pending->earlier_leaves + pending->later_leaves) : 0u;
    }
    // listed_count widens from unsigned int to size_t. Listed_count + 1 cannot wrap in 32 bits
    const size_t capacity = (size_t)listed_count + 1u;
    const size_t slots = machine->capacity;
    machine->core_earlier = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->core_later = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->core_side = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->core_leaf = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->core_match = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->core_lag = (int *)malloc(capacity * 3u * sizeof(int));
    machine->core_width_first = (unsigned int *)malloc((capacity + 1u) * sizeof(unsigned int));
    unsigned int *const listed_slot = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    unsigned int *const listed_run_first = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    unsigned int *const listed_run_end = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    int *const listed_center = (int *)malloc(capacity * 3u * sizeof(int));
    unsigned int *const widths = (unsigned int *)calloc(capacity, sizeof(unsigned int));
    size_t *const staged_at = (size_t *)calloc(capacity, sizeof(size_t));
    unsigned int *const slot_first = (unsigned int *)calloc(slots + 1u, sizeof(unsigned int));
    unsigned int *const slot_order = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    int steps_succeeded = (widest != 0u) && (machine->core_earlier != NULL) && (machine->core_later != NULL) &&
                          (machine->core_side != NULL) && (machine->core_leaf != NULL) &&
                          (machine->core_match != NULL) && (machine->core_lag != NULL) &&
                          (machine->core_width_first != NULL) && (listed_slot != NULL) && (listed_run_first != NULL) &&
                          (listed_run_end != NULL) && (listed_center != NULL) && (widths != NULL) &&
                          (staged_at != NULL) && (slot_first != NULL) && (slot_order != NULL);
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
                const unsigned int bundle_end = leaf_bundles[leaf + 1u];
                // own_slot * run_room narrows from size_t to unsigned int exactly, as machine_split_runs holds capacity
                // * run_room within 32 bits
                const unsigned int run_base = (unsigned int)(own_slot * machine->run_capacity);
                const unsigned int empty = (bundle_end <= bundle_first) ? 1u : 0u;
                machine->core_earlier[listed_written] = pending->earlier;
                machine->core_later[listed_written] = pending->later;
                machine->core_side[listed_written] = side;
                machine->core_leaf[listed_written] = leaf;
                machine->core_match[listed_written] = machine->landed[climber];
                listed_slot[listed_written] = machine->side_slots[(2u * index) + 1u];
                listed_run_first[listed_written] =
                    (empty != 0u) ? 0u : (run_base + machine->slot_bundle_first[own_slot][bundle_first]);
                listed_run_end[listed_written] =
                    (empty != 0u) ? 0u : (run_base + machine->slot_bundle_end[own_slot][bundle_end - 1u]);
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
    unsigned int max_slot_items = 0u;
    for (size_t slot = 0u; steps_succeeded && (slot < slots); slot += 1u)
    {
        const unsigned int slot_items = slot_first[slot + 1u] - slot_first[slot];
        max_slot_items = (slot_items > max_slot_items) ? slot_items : max_slot_items;
    }
    // voxels narrows from unsigned long long to size_t exactly, as climb_machine_open already allocated this many
    // labels
    const size_t voxels = (size_t)geometry.voxels;
    // max_slot_items widens from unsigned int to size_t before the multiply. Items * widest * 10 cannot wrap in 32
    // bits
    const size_t bins = (size_t)max_slot_items * widest * CLIMB_MACHINE_CORE_FIELDS;
    // max_slot_items widens from unsigned int to size_t. Max_slot_items + 1 cannot wrap in 32 bits
    const size_t item_capacity = (size_t)max_slot_items + 1u;
    unsigned int *painted = NULL;
    unsigned int *range_first = NULL;
    unsigned int *range_second = NULL;
    unsigned int *device_run_first = NULL;
    unsigned int *device_run_end = NULL;
    int *device_center = NULL;
    unsigned int *device_match = NULL;
    unsigned long long *device_bins = NULL;
    unsigned int *device_error = NULL;
    unsigned int *const item_run_first =
        steps_succeeded ? (unsigned int *)malloc(item_capacity * sizeof(unsigned int)) : NULL;
    unsigned int *const item_run_end =
        steps_succeeded ? (unsigned int *)malloc(item_capacity * sizeof(unsigned int)) : NULL;
    int *const item_center = steps_succeeded ? (int *)malloc(item_capacity * 3u * sizeof(int)) : NULL;
    unsigned int *const item_match =
        steps_succeeded ? (unsigned int *)malloc(item_capacity * sizeof(unsigned int)) : NULL;
    unsigned long long *const host_bins =
        steps_succeeded ? (unsigned long long *)malloc((bins + 1u) * sizeof(unsigned long long)) : NULL;
    steps_succeeded = steps_succeeded && (item_run_first != NULL) && (item_run_end != NULL) && (item_center != NULL) &&
                      (item_match != NULL) && (host_bins != NULL) &&
                      (cudaMalloc((void **)&painted, voxels * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&range_first, voxels * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&range_second, voxels * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_run_first, item_capacity * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_run_end, item_capacity * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_center, item_capacity * 3u * sizeof(int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_match, item_capacity * sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_bins, (bins + 1u) * sizeof(unsigned long long)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_error, sizeof(unsigned int)) == cudaSuccess) &&
                      (cudaMemset(device_error, 0, sizeof(unsigned int)) == cudaSuccess);
    unsigned long long *staged = NULL;
    size_t staged_capacity = 0u;
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
            item_run_end[item] = listed_run_end[listed_place];
            item_center[3u * item] = listed_center[3u * listed_place];
            item_center[(3u * item) + 1u] = listed_center[(3u * listed_place) + 1u];
            item_center[(3u * item) + 2u] = listed_center[(3u * listed_place) + 2u];
            item_match[item] = machine->core_match[listed_place];
        }
        const size_t base = slot * machine->run_capacity;
        const unsigned int runs = machine->slot_runs[slot];
        // slot_items widens from unsigned int to size_t before the multiply. Items * widest * 10 cannot wrap in 32
        // bits
        const size_t slot_bins = (size_t)slot_items * widest * CLIMB_MACHINE_CORE_FIELDS;
        steps_succeeded =
            (cudaMemset(painted, 0xFF, voxels * sizeof(unsigned int)) == cudaSuccess) &&
            (cudaMemset(device_bins, 0, slot_bins * sizeof(unsigned long long)) == cudaSuccess) &&
            (cudaMemcpy(device_run_first, item_run_first, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
             cudaSuccess) &&
            (cudaMemcpy(device_run_end, item_run_end, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
             cudaSuccess) &&
            (cudaMemcpy(device_center, item_center, slot_items * sizeof(int) * 3u, cudaMemcpyHostToDevice) ==
             cudaSuccess) &&
            (cudaMemcpy(device_match, item_match, slot_items * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
             cudaSuccess);
        if (steps_succeeded && (runs != 0u))
        {
            machine_paint_kernel<<<(runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                &machine->run_start[base], &machine->run_length[base], &machine->run_leaf[base], runs, painted);
            steps_succeeded = machine_launched();
        }
        if (steps_succeeded)
        {
            machine_range_row_kernel<<<(rows + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                painted, geometry, range_first);
            machine_range_column_kernel<<<(height_columns + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK,
                                          CLIMB_MACHINE_BLOCK>>>(painted, geometry, 1u, range_first, range_second);
            machine_range_column_kernel<<<(plane + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK,
                                          CLIMB_MACHINE_BLOCK>>>(painted, geometry, 0u, range_second, range_first);
            machine_core_kernel<<<(slot_items + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK, CLIMB_MACHINE_BLOCK>>>(
                slot_items, device_run_first, device_run_end, device_center, device_match, machine->run_start,
                machine->run_length, painted, range_first, geometry, widest, device_bins, device_error);
            steps_succeeded = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
        }
        steps_succeeded = steps_succeeded && (cudaMemcpy(host_bins, device_bins, slot_bins * sizeof(unsigned long long),
                                                         cudaMemcpyDeviceToHost) == cudaSuccess);
        for (unsigned int item = 0u; steps_succeeded && (item < slot_items); item += 1u)
        {
            const unsigned int listed_place = slot_order[slot_item_first + item];
            // item widens from unsigned int to size_t before the multiply. Item * widest * 10 cannot wrap in 32 bits
            const unsigned long long *const item_bins = &host_bins[(size_t)item * widest * CLIMB_MACHINE_CORE_FIELDS];
            unsigned int top_width = 0u;
            for (unsigned int width = 0u; width < widest; width += 1u)
            {
                // width widens from unsigned int to size_t, matching the size_t offset item_bins is indexed by
                top_width = (item_bins[(size_t)width * CLIMB_MACHINE_CORE_FIELDS] != 0ull) ? (width + 1u) : top_width;
            }
            if ((staged_count + top_width) > staged_capacity)
            {
                const size_t grown_capacity = ((staged_count + top_width) * 2u) + 1u;
                unsigned long long *const grown = (unsigned long long *)realloc(
                    staged, grown_capacity * CLIMB_MACHINE_CORE_FIELDS * sizeof(unsigned long long));
                steps_succeeded = (grown != NULL);
                staged = steps_succeeded ? grown : staged;
                staged_capacity = steps_succeeded ? grown_capacity : staged_capacity;
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
    unsigned int error = 0u;
    steps_succeeded =
        steps_succeeded &&
        (cudaMemcpy(&error, device_error, sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess) &&
        (error == 0u) && (staged_count <= 0xFFFFFFFFull);
    machine->core_fields =
        steps_succeeded
            ? (unsigned long long *)malloc((staged_count + 1u) * CLIMB_MACHINE_CORE_FIELDS * sizeof(unsigned long long))
            : NULL;
    steps_succeeded = steps_succeeded && (machine->core_fields != NULL);
    size_t widths_written = 0u;
    for (unsigned int listed_place = 0u; steps_succeeded && (listed_place < listed_count); listed_place += 1u)
    {
        // widths_written is at most staged_count, held within 32 bits above. It narrows from size_t to unsigned int
        // exactly
        machine->core_width_first[listed_place] = (unsigned int)widths_written;
        memcpy(&machine->core_fields[widths_written * CLIMB_MACHINE_CORE_FIELDS],
               &staged[staged_at[listed_place] * CLIMB_MACHINE_CORE_FIELDS],
               widths[listed_place] * sizeof(unsigned long long) * CLIMB_MACHINE_CORE_FIELDS);
        widths_written += widths[listed_place];
    }
    if (steps_succeeded)
    {
        // widths_written equals staged_count, held within 32 bits above. It narrows from size_t to unsigned int
        // exactly
        machine->core_width_first[listed_count] = (unsigned int)widths_written;
    }
    cudaFree(painted);
    cudaFree(range_first);
    cudaFree(range_second);
    cudaFree(device_run_first);
    cudaFree(device_run_end);
    cudaFree(device_center);
    cudaFree(device_match);
    cudaFree(device_bins);
    cudaFree(device_error);
    free(item_run_first);
    free(item_run_end);
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
    free(listed_run_end);
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
    // widths_written equals staged_count, held within 32 bits above. It narrows from size_t to unsigned int exactly
    core->widths = (unsigned int)widths_written;
    core->microseconds = engine_clock_microseconds() - started;
    return 1;
}
