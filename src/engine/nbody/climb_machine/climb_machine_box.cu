// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_box.cu: boxes released, ordered and merged
#include "climb_machine_internal.h"

void machine_box_release(ClimbMachine *machine)
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
        const unsigned int end = machine->box_entry_first[cell + 1u];
        machine->box_entry_first[cell] = (unsigned int)kept;
        if (cell_raw[cell] == 0u)
        {
            for (unsigned int entry = from; entry < end; entry += 1u)
            {
                machine->box_target[kept] = machine->box_target[entry];
                machine->box_count[kept] = machine->box_count[entry];
                kept += 1u;
            }
            from = end;
            continue;
        }
        size_t piece_count = 0u;
        unsigned int outside = 0u;
        for (unsigned int entry = from; entry < end; entry += 1u)
        {
            const unsigned int none = (unsigned int)(machine->box_target[entry] == CLIMB_MACHINE_BOX_NONE);
            outside = (none != 0u) ? machine->box_count[entry] : outside;
            pieces[piece_count].target = machine->box_target[entry];
            pieces[piece_count].count = machine->box_count[entry];
            piece_count += (none != 0u) ? 0u : 1u;
        }
        qsort(pieces, piece_count, sizeof(MachineBoxPiece), machine_box_piece_order);
        for (size_t piece = 0u; piece < piece_count; piece += 1u)
        {
            const int same = (piece != 0u) && (pieces[piece].target == pieces[piece - 1u].target);
            machine->box_target[kept - (same ? 1u : 0u)] = pieces[piece].target;
            machine->box_count[kept - (same ? 1u : 0u)] =
                same ? (machine->box_count[kept - 1u] + pieces[piece].count) : pieces[piece].count;
            kept += same ? 0u : 1u;
        }
        if (outside != 0u)
        {
            machine->box_target[kept] = CLIMB_MACHINE_BOX_NONE;
            machine->box_count[kept] = outside;
            kept += 1u;
        }
        from = end;
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
    const size_t capacity = (size_t)boxed + 1u;
    const unsigned long long cells = (unsigned long long)boxed * CLIMB_MACHINE_BOX_CELLS;
    const size_t cell_count = (cells <= 0x7FFFFFFFull) ? (size_t)cells : 0u;
    machine->box_earlier = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->box_later = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->box_leaf = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    machine->box_cell_first = (unsigned int *)malloc((capacity + 1u) * sizeof(unsigned int));
    machine->box_cell_shift = (int *)malloc((cell_count + 1u) * 3u * sizeof(int));
    machine->box_entry_first = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const climber_of_box = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    unsigned int *const cell_climber = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const cell_total = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    unsigned int *const cell_raw = (unsigned int *)malloc((cell_count + 1u) * sizeof(unsigned int));
    int ok = (cells <= 0x7FFFFFFFull) && (machine->box_earlier != NULL) && (machine->box_later != NULL) &&
             (machine->box_leaf != NULL) && (machine->box_cell_first != NULL) && (machine->box_cell_shift != NULL) &&
             (machine->box_entry_first != NULL) && (climber_of_box != NULL) && (cell_climber != NULL) &&
             (cell_total != NULL) && (cell_raw != NULL);
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
    unsigned int *device_error = NULL;
    ok = ok && (cudaMalloc((void **)&device_cell_climber, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_climber_of_box, capacity * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_cell_shift, (cell_count + 1u) * 3u * sizeof(int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_entry_first, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_cell_entries, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_cell_total, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_cell_raw, (cell_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_error, 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemset(device_error, 0, 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_cell_climber, cell_climber, cell_count * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
          cudaSuccess) &&
         (cudaMemcpy(device_climber_of_box, climber_of_box, (size_t)boxed * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_cell_shift, machine->box_cell_shift, cell_count * 3u * sizeof(int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    device.cell_climber = device_cell_climber;
    device.climber_of_box = device_climber_of_box;
    device.cell_shift = device_cell_shift;
    device.entry_first = device_entry_first;
    device.cell_entries = device_cell_entries;
    device.cell_total = device_cell_total;
    device.cell_raw = device_cell_raw;
    device.error = device_error;
    const unsigned int cell_blocks = (unsigned int)((cell_count + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK);
    if (ok && (cell_count != 0u))
    {
        machine_box_kernel<<<cell_blocks, CLIMB_MACHINE_BLOCK>>>(
            (unsigned int)cell_count, 0u, device, machine->device_climber_side, machine->device_side_slots,
            machine->device_climber_entry_start, machine->device_entry_first, machine->device_entry_end,
            machine->row_first, machine->run_at_row, machine->run_start, machine->run_length, machine->run_leaf,
            (unsigned int)machine->run_capacity, machine->positive, machine->geometry);
        ok = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
    }
    ok = ok && ((cell_count == 0u) ||
                ((cudaMemcpy(machine->box_entry_first, device_cell_entries, cell_count * sizeof(unsigned int),
                             cudaMemcpyDeviceToHost) == cudaSuccess) &&
                 (cudaMemcpy(cell_total, device_cell_total, cell_count * sizeof(unsigned int),
                             cudaMemcpyDeviceToHost) == cudaSuccess) &&
                 (cudaMemcpy(cell_raw, device_cell_raw, cell_count * sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
                  cudaSuccess)));
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
    ok = ok && (machine->box_target != NULL) && (machine->box_count != NULL) &&
         (cudaMalloc((void **)&device_target, (entry_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_count, (entry_count + 1u) * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_entry_first, machine->box_entry_first, (cell_count + 1u) * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    device.target = device_target;
    device.count = device_count;
    if (ok && (cell_count != 0u))
    {
        machine_box_kernel<<<cell_blocks, CLIMB_MACHINE_BLOCK>>>(
            (unsigned int)cell_count, 1u, device, machine->device_climber_side, machine->device_side_slots,
            machine->device_climber_entry_start, machine->device_entry_first, machine->device_entry_end,
            machine->row_first, machine->run_at_row, machine->run_start, machine->run_length, machine->run_leaf,
            (unsigned int)machine->run_capacity, machine->positive, machine->geometry);
        ok = machine_launched() && (cudaDeviceSynchronize() == cudaSuccess);
    }
    unsigned int error[2] = {0u, 0u};
    ok = ok &&
         ((entry_count == 0u) || ((cudaMemcpy(machine->box_target, device_target, entry_count * sizeof(unsigned int),
                                              cudaMemcpyDeviceToHost) == cudaSuccess) &&
                                  (cudaMemcpy(machine->box_count, device_count, entry_count * sizeof(unsigned int),
                                              cudaMemcpyDeviceToHost) == cudaSuccess)));
    const int counted = (device_error != NULL) && (cudaMemcpy(error, device_error, 2u * sizeof(unsigned int),
                                                                cudaMemcpyDeviceToHost) == cudaSuccess);
    box->climbers = boxed;
    box->cells = (unsigned int)((cells <= 0xFFFFFFFFull) ? cells : 0xFFFFFFFFull);
    box->crowded = counted ? error[0] : 0u;
    box->broken = counted ? error[1] : 0u;
    ok = ok && counted && (error[1] == 0u) && machine_box_merge(machine, cell_raw, cell_count);
    unsigned int final_score_differ = 0u;
    unsigned int not_highest = 0u;
    for (unsigned int one = 0u; ok && (one < boxed); one += 1u)
    {
        const unsigned int first = machine->box_cell_first[one];
        const unsigned int top = cell_total[first + CLIMB_MACHINE_BOX_CENTER];
        final_score_differ += (top != machine->final_score[climber_of_box[one]]) ? 1u : 0u;
        unsigned int higher = 0u;
        for (unsigned int near = 0u; near < CLIMB_MACHINE_BOX_NEIGHBORS; near += 1u)
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
    cudaFree(device_error);
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
    box->final_score_differ = final_score_differ;
    box->not_highest = not_highest;
    box->microseconds = engine_clock_microseconds() - started;
    return 1;
}
