// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_open.cu: the runs cut, the machine opened and a frame stored
#include "climb_machine_internal.h"

static int machine_split_runs(ClimbMachine *machine, unsigned int slot, const unsigned int *labels,
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
        machine_map_kernel<<<leaf_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_peaks, leaves, 0u,
                                                                 machine->device_map);
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
    if ((ok != 0) && (runs + 1u > machine->unsorted_capacity))
    {
        const size_t capacity = runs + (runs / 2u) + 1u;
        cudaFree(machine->device_unsorted_start);
        cudaFree(machine->device_unsorted_length);
        cudaFree(machine->device_unsorted_leaf);
        machine->device_unsorted_start = NULL;
        machine->device_unsorted_length = NULL;
        machine->device_unsorted_leaf = NULL;
        ok = ok &&
             (cudaMalloc((void **)&machine->device_unsorted_start, capacity * sizeof(unsigned int)) == cudaSuccess);
        ok = ok &&
             (cudaMalloc((void **)&machine->device_unsorted_length, capacity * sizeof(unsigned int)) == cudaSuccess);
        ok =
            ok && (cudaMalloc((void **)&machine->device_unsorted_leaf, capacity * sizeof(unsigned int)) == cudaSuccess);
        ok = ok &&
             machine_grow((void **)&machine->order, (void **)&machine->device_order, capacity * sizeof(unsigned int));
        free(machine->unsorted_leaf);
        machine->unsorted_leaf = (unsigned int *)malloc(capacity * sizeof(unsigned int));
        ok = ok && (machine->unsorted_leaf != NULL);
        machine->unsorted_capacity = (ok != 0) ? capacity : 0u;
    }
    ok = ok && (cudaMemcpy(machine->device_row_offsets, machine->row_counts, (size_t)rows * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        machine_row_kernel<<<row_blocks, CLIMB_MACHINE_BLOCK>>>(
            labels, machine->device_map, rows, geometry, machine->device_row_offsets, machine->device_row_counts,
            machine->device_unsorted_start, machine->device_unsorted_length, machine->device_unsorted_leaf);
        ok = machine_launched();
    }
    if ((ok != 0) && (leaves != 0u))
    {
        machine_map_kernel<<<leaf_blocks, CLIMB_MACHINE_BLOCK>>>(machine->device_peaks, leaves, 1u,
                                                                 machine->device_map);
        ok = machine_launched();
    }
    ok = ok && ((runs == 0u) || (cudaMemcpy(machine->unsorted_leaf, machine->device_unsorted_leaf,
                                            runs * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess));
    if (ok == 0)
    {
        return 0;
    }

    unsigned int *const counts = machine->leaf_counts;
    memset(counts, 0, ((size_t)leaves + 1u) * sizeof(unsigned int));
    for (size_t run = 0u; run < runs; run += 1u)
    {
        counts[machine->unsorted_leaf[run] + 1u] += 1u;
    }
    for (unsigned int leaf = 0u; leaf < leaves; leaf += 1u)
    {
        counts[leaf + 1u] += counts[leaf];
    }
    for (size_t run = 0u; run < runs; run += 1u)
    {
        const unsigned int leaf = machine->unsorted_leaf[run];
        machine->order[counts[leaf]] = (unsigned int)run;
        counts[leaf] += 1u;
    }

    if (runs > machine->run_capacity)
    {
        const size_t capacity = runs + (runs / 4u) + 1u;
        const size_t slots = (size_t)machine->capacity;
        unsigned int *grown[4] = {NULL, NULL, NULL, NULL};
        unsigned int *const kept[4] = {machine->run_start, machine->run_length, machine->run_leaf, machine->run_at_row};
        ok = ok && ((slots * capacity) <= 0xFFFFFFFFull);
        for (unsigned int which = 0u; (ok != 0) && (which < 4u); which += 1u)
        {
            ok = (cudaMalloc((void **)&grown[which], slots * capacity * sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
        }
        for (unsigned int other_slot = 0u; (ok != 0) && (other_slot < machine->capacity); other_slot += 1u)
        {
            const size_t count = (size_t)machine->slot_runs[other_slot];
            if ((other_slot == slot) || (machine->slot_frame[other_slot] == CLIMB_MACHINE_EMPTY) || (count == 0u))
            {
                continue;
            }
            for (unsigned int which = 0u; (ok != 0) && (which < 4u); which += 1u)
            {
                ok = (cudaMemcpy(&grown[which][(size_t)other_slot * capacity],
                                 &kept[which][(size_t)other_slot * machine->run_capacity], count * sizeof(unsigned int),
                                 cudaMemcpyDeviceToDevice) == cudaSuccess)
                         ? 1
                         : 0;
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
        machine->run_capacity = (ok != 0) ? capacity : 0u;
    }
    ok = ok && ((runs == 0u) || (cudaMemcpy(machine->device_order, machine->order, runs * sizeof(unsigned int),
                                            cudaMemcpyHostToDevice) == cudaSuccess));
    if ((ok != 0) && (runs != 0u))
    {
        const size_t base = (size_t)slot * machine->run_capacity;
        const unsigned int run_blocks = (unsigned int)((runs + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK);
        machine_gather_kernel<<<run_blocks, CLIMB_MACHINE_BLOCK>>>(
            machine->device_order, (unsigned int)runs, machine->device_unsorted_start, machine->device_unsorted_length,
            machine->device_unsorted_leaf, &machine->run_start[base], &machine->run_length[base],
            &machine->run_leaf[base], &machine->run_at_row[base]);
        ok = machine_launched();
    }
    if (ok != 0)
    {
        const size_t offsets = (size_t)slot * ((size_t)rows + 1u);
        const unsigned int total = (unsigned int)runs;
        ok = (cudaMemcpy(&machine->row_first[offsets], machine->row_counts, (size_t)rows * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess)
                 ? 1
                 : 0;
        ok = ok && (cudaMemcpy(&machine->row_first[offsets + rows], &total, sizeof(unsigned int),
                               cudaMemcpyHostToDevice) == cudaSuccess);
    }

    free(machine->slot_leaf_bundles[slot]);
    free(machine->slot_bundle_first[slot]);
    free(machine->slot_bundle_end[slot]);
    machine->slot_leaf_bundles[slot] = (unsigned int *)malloc(((size_t)leaves + 1u) * sizeof(unsigned int));
    const size_t bundle_capacity = (runs / CLIMB_MACHINE_BUNDLE) + (size_t)leaves + 1u;
    machine->slot_bundle_first[slot] = (unsigned int *)malloc(bundle_capacity * sizeof(unsigned int));
    machine->slot_bundle_end[slot] = (unsigned int *)malloc(bundle_capacity * sizeof(unsigned int));
    ok = ok && (machine->slot_leaf_bundles[slot] != NULL) && (machine->slot_bundle_first[slot] != NULL) &&
         (machine->slot_bundle_end[slot] != NULL);
    unsigned int bundles = 0u;
    unsigned int leaf_first = 0u;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < leaves); leaf += 1u)
    {
        const unsigned int leaf_end = counts[leaf];
        machine->slot_leaf_bundles[slot][leaf] = bundles;
        for (unsigned int first = leaf_first; first < leaf_end; first += CLIMB_MACHINE_BUNDLE)
        {
            machine->slot_bundle_first[slot][bundles] = first;
            machine->slot_bundle_end[slot][bundles] =
                ((leaf_end - first) < CLIMB_MACHINE_BUNDLE) ? leaf_end : (first + CLIMB_MACHINE_BUNDLE);
            bundles += 1u;
        }
        leaf_first = leaf_end;
    }
    if (ok != 0)
    {
        machine->slot_leaf_bundles[slot][leaves] = bundles;
        machine->slot_runs[slot] = (unsigned int)runs;
    }
    return ok;
}

extern "C" ClimbMachine *climb_machine_open(const ClimbMachineExtent *extent)
{
    if ((extent == NULL) || (extent->depth == 0u) || (extent->height == 0u) || (extent->width == 0u))
    {
        return NULL;
    }
    ClimbMachine *const machine = (ClimbMachine *)calloc(1u, sizeof(ClimbMachine));
    if (machine == NULL)
    {
        return NULL;
    }
    MachineGeometry *const geometry = &machine->geometry;
    geometry->depth = extent->depth;
    geometry->height = extent->height;
    geometry->width = extent->width;
    geometry->weight_z = extent->weight_z;
    geometry->voxels = (unsigned long long)extent->depth * extent->height * extent->width;
    geometry->words = (geometry->voxels + 63ull) / 64ull;
    machine->peak_capacity = extent->peak_capacity;
    machine->capacity = (extent->frames < 2u) ? 2u : extent->frames;
    const size_t slots = (size_t)machine->capacity;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&machine->scratch_labels, 2u * (size_t)geometry->voxels * sizeof(unsigned int)) ==
                cudaSuccess);
    machine->scratch_frame[0] = CLIMB_MACHINE_EMPTY;
    machine->scratch_frame[1] = CLIMB_MACHINE_EMPTY;
    ok = ok && (cudaMalloc((void **)&machine->positive, slots * (size_t)geometry->words * sizeof(unsigned long long)) ==
                cudaSuccess);
    ok = ok && (cudaMalloc((void **)&machine->row_first, slots * (((size_t)extent->depth * extent->height) + 1u) *
                                                             sizeof(unsigned int)) == cudaSuccess);
    machine->slot_frame = (unsigned int *)malloc(slots * sizeof(unsigned int));
    machine->slot_leaves = (unsigned int *)calloc(slots, sizeof(unsigned int));
    machine->slot_runs = (unsigned int *)calloc(slots, sizeof(unsigned int));
    machine->slot_leaf_bundles = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_bundle_first = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_bundle_end = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_contact_start = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    machine->slot_contacts = (unsigned int **)calloc(slots, sizeof(unsigned int *));
    ok = ok && (machine->slot_frame != NULL) && (machine->slot_leaves != NULL) && (machine->slot_runs != NULL) &&
         (machine->slot_leaf_bundles != NULL) && (machine->slot_bundle_first != NULL) &&
         (machine->slot_bundle_end != NULL) && (machine->slot_contact_start != NULL) &&
         (machine->slot_contacts != NULL);
    for (size_t slot = 0u; (ok != 0) && (slot < slots); slot += 1u)
    {
        machine->slot_frame[slot] = CLIMB_MACHINE_EMPTY;
    }
    const size_t rows = (size_t)extent->depth * extent->height;
    ok = ok && (cudaMalloc((void **)&machine->device_map, (size_t)geometry->voxels * sizeof(int)) == cudaSuccess);
    ok = ok && (cudaMemset(machine->device_map, 0xFF, (size_t)geometry->voxels * sizeof(int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&machine->device_peaks,
                           ((size_t)extent->peak_capacity + 1u) * sizeof(unsigned int)) == cudaSuccess);
    ok = ok &&
         machine_grow((void **)&machine->row_counts, (void **)&machine->device_row_counts, rows * sizeof(unsigned int));
    ok = ok && (cudaMalloc((void **)&machine->device_row_offsets, rows * sizeof(unsigned int)) == cudaSuccess);
    machine->leaf_counts = (unsigned int *)malloc(((size_t)extent->peak_capacity + 2u) * sizeof(unsigned int));
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
    if ((machine == NULL) || (frame == NULL) || (frame->labels == NULL) || (frame->positive == NULL) ||
        (frame->leaf_count > machine->peak_capacity))
    {
        return 0;
    }
    unsigned int slot = machine_slot_of(machine, CLIMB_MACHINE_EMPTY);
    int ok = 1;
    if (slot == CLIMB_MACHINE_EMPTY)
    {
        ok = climb_machine_run(machine);
        for (unsigned int other_slot = 0u; (ok != 0) && (other_slot < machine->capacity); other_slot += 1u)
        {
            if (other_slot != machine->newest)
            {
                machine->slot_frame[other_slot] = CLIMB_MACHINE_EMPTY;
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
    ok =
        ok && (cudaMemcpy(&machine->positive[at * (size_t)geometry->words], frame->positive,
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
        ok = machine_split_runs(machine, slot, labels, frame);
    }
    if ((ok != 0) && (frame->contact_start != NULL) && (frame->contacts != NULL))
    {
        const size_t contacts = (size_t)frame->contact_start[frame->leaf_count];
        machine->slot_contact_start[slot] =
            (unsigned int *)malloc(((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
        machine->slot_contacts[slot] = (unsigned int *)malloc((contacts + 1u) * sizeof(unsigned int));
        ok = (machine->slot_contact_start[slot] != NULL) && (machine->slot_contacts[slot] != NULL);
        if (ok != 0)
        {
            memcpy(machine->slot_contact_start[slot], frame->contact_start,
                   ((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
            memcpy(machine->slot_contacts[slot], frame->contacts, contacts * sizeof(unsigned int));
        }
    }
    machine->slot_frame[slot] = (ok != 0) ? frame->frame : CLIMB_MACHINE_EMPTY;
    machine->newest = (ok != 0) ? slot : machine->newest;
    return ok;
}
