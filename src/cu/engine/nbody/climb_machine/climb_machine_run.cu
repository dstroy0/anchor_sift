// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_run.cu: the landing options, the spiral, pending pairs and the run
#include "climb_machine_internal.h"

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
    const unsigned int capped_tries = (tries > SPIRAL_STEPS) ? SPIRAL_STEPS : tries;
    machine->spiral_tries = capped_tries + 1u;
    if ((machine->device_spiral != NULL) || (capped_tries == 0u))
    {
        return 1;
    }
    const int ok =
        (cudaMalloc((void **)&machine->device_spiral, (size_t)SPIRAL_STEPS * 3u * sizeof(int)) == cudaSuccess) &&
        (cudaMemcpy(machine->device_spiral, SPIRAL_OFFSETS, (size_t)SPIRAL_STEPS * 3u * sizeof(int),
                    cudaMemcpyHostToDevice) == cudaSuccess);
    return ok ? 1 : 0;
}

extern "C" const unsigned int *climb_machine_labels(const ClimbMachine *machine, unsigned int frame)
{
    if (machine == NULL)
    {
        return NULL;
    }
    const unsigned int slot = (unsigned int)(machine->scratch_frame[1] == frame);
    const unsigned int has = (unsigned int)((frame != CLIMB_MACHINE_EMPTY) && ((machine->scratch_frame[0] == frame) ||
                                                                               (machine->scratch_frame[1] == frame)));
    return (has != 0u) ? &machine->scratch_labels[(size_t)slot * (size_t)machine->geometry.voxels] : NULL;
}

extern "C" const unsigned long long *climb_machine_positive(const ClimbMachine *machine, unsigned int frame)
{
    const unsigned int slot = (machine != NULL) ? machine_slot_of(machine, frame) : CLIMB_MACHINE_EMPTY;
    return (slot == CLIMB_MACHINE_EMPTY) ? NULL : &machine->positive[(size_t)slot * (size_t)machine->geometry.words];
}

extern "C" int climb_machine_pend(ClimbMachine *machine, const ClimbMachinePair *pair)
{
    if ((machine == NULL) || (pair == NULL) || (machine_slot_of(machine, pair->earlier) == CLIMB_MACHINE_EMPTY) ||
        (machine_slot_of(machine, pair->later) == CLIMB_MACHINE_EMPTY))
    {
        return 0;
    }
    if (machine->pending_count == machine->pending_capacity)
    {
        const unsigned int capacity = (machine->pending_capacity * 2u) + 8u;
        ClimbMachinePair *const grown =
            (ClimbMachinePair *)realloc(machine->pending, (size_t)capacity * sizeof(ClimbMachinePair));
        if (grown == NULL)
        {
            return 0;
        }
        machine->pending = grown;
        machine->pending_capacity = capacity;
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
        const unsigned int slots[2] = {machine_slot_of(machine, pending->earlier),
                                       machine_slot_of(machine, pending->later)};
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
    if (sides > machine->side_capacity)
    {
        ok = ok && machine_grow((void **)&machine->side_slots, (void **)&machine->device_side_slots,
                                sides * 2u * sizeof(unsigned int));
        machine->side_capacity = (ok != 0) ? sides : 0u;
    }
    if ((ok != 0) && (climbers + 1u > machine->climber_capacity))
    {
        const size_t capacity = climbers + (climbers / 2u) + 1u;
        ok = ok && machine_grow((void **)&machine->climber_side, (void **)&machine->device_climber_side,
                                capacity * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->climber_peak, (void **)&machine->device_climber_peak,
                                capacity * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->climber_entry_start, (void **)&machine->device_climber_entry_start,
                                (capacity + 1u) * sizeof(unsigned int));
        ok = ok &&
             machine_grow((void **)&machine->centers, (void **)&machine->device_centers, capacity * 3u * sizeof(int));
        ok = ok &&
             machine_grow((void **)&machine->active, (void **)&machine->device_active, capacity * sizeof(unsigned int));
        ok = ok &&
             machine_grow((void **)&machine->landed, (void **)&machine->device_landed, capacity * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->final_score, (void **)&machine->device_final_score,
                                capacity * sizeof(unsigned int));
        machine->climber_capacity = (ok != 0) ? capacity : 0u;
    }
    if ((ok != 0) && (entries + 1u > machine->entry_capacity))
    {
        const size_t capacity = entries + (entries / 2u) + 1u;
        ok = ok && machine_grow((void **)&machine->entry_first, (void **)&machine->device_entry_first,
                                capacity * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->entry_end, (void **)&machine->device_entry_end,
                                capacity * sizeof(unsigned int));
        ok = ok && machine_grow((void **)&machine->entry_climber, (void **)&machine->device_entry_climber,
                                capacity * sizeof(unsigned int));
        cudaFree(machine->device_scores);
        machine->device_scores = NULL;
        ok = ok && (cudaMalloc((void **)&machine->device_scores,
                               capacity * CLIMB_MACHINE_CANDIDATES * sizeof(unsigned int)) == cudaSuccess);
        machine->entry_capacity = (ok != 0) ? capacity : 0u;
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
            const unsigned int run_base = (unsigned int)((size_t)own * machine->run_capacity);
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
                        machine->entry_end[entry] = run_base + machine->slot_bundle_end[own][bundle];
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
    ok = ok && (cudaMemcpy(machine->device_centers, machine->centers, climbers * 3u * sizeof(int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->device_active, machine->active, climbers * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok &&
         ((entries == 0u) || ((cudaMemcpy(machine->device_entry_first, machine->entry_first,
                                          entries * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess) &&
                              (cudaMemcpy(machine->device_entry_end, machine->entry_end, entries * sizeof(unsigned int),
                                          cudaMemcpyHostToDevice) == cudaSuccess) &&
                              (cudaMemcpy(machine->device_entry_climber, machine->entry_climber,
                                          entries * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess)));

    const unsigned int entry_blocks = (entry + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    const unsigned int climber_blocks = (climber + CLIMB_MACHINE_BLOCK - 1u) / CLIMB_MACHINE_BLOCK;
    int settled = (climber == 0u) ? 1 : 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = (cudaMemcpyAsync(&machine->device_moved[parity], machine->pinned_zero, sizeof(unsigned int),
                              cudaMemcpyHostToDevice, 0) == cudaSuccess)
                 ? 1
                 : 0;
        for (unsigned int tick = 0u; (ok != 0) && (tick < CLIMB_MACHINE_TICKS); tick += 1u)
        {
            if (entry != 0u)
            {
                machine_score_kernel<<<entry_blocks, CLIMB_MACHINE_BLOCK>>>(
                    machine->run_start, machine->run_length, machine->device_entry_first, machine->device_entry_end,
                    machine->device_entry_climber, entry, machine->device_climber_side, machine->device_side_slots,
                    machine->device_centers, machine->device_active, machine->positive, geometry,
                    machine->device_scores);
                ok = machine_launched();
            }
            if (ok != 0)
            {
                machine_decide_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
                    machine->device_climber_entry_start, machine->device_scores, climber, geometry,
                    machine->device_centers, machine->device_active, &machine->device_moved[parity],
                    machine->device_final_score);
                ok = machine_launched();
            }
        }
        ok = ok && (cudaMemcpyAsync(&machine->pinned_moved[parity], &machine->device_moved[parity],
                                    sizeof(unsigned int), cudaMemcpyDeviceToHost, 0) == cudaSuccess);
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
                machine->device_entry_first, machine->device_entry_end, machine->device_centers, machine->row_first,
                machine->run_at_row, machine->run_start, machine->run_length, machine->run_leaf,
                (unsigned int)machine->run_capacity, climber, machine->device_spiral,
                (machine->spiral_tries != 0u) ? machine->spiral_tries : 1u, geometry, machine->device_landed);
        }
        else
        {
            machine_land_kernel<<<climber_blocks, CLIMB_MACHINE_BLOCK>>>(
                machine->device_climber_side, machine->device_side_slots, machine->device_climber_peak,
                machine->device_centers, machine->row_first, machine->run_at_row, machine->run_start,
                machine->run_length, machine->run_leaf, (unsigned int)machine->run_capacity, climber, geometry,
                machine->device_landed);
        }
        ok = machine_launched();
    }
    ok = ok && (cudaMemcpy(machine->centers, machine->device_centers, climbers * 3u * sizeof(int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->landed, machine->device_landed, climbers * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(machine->final_score, machine->device_final_score, climbers * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);

    climber = 0u;
    for (unsigned int pair = 0u; (ok != 0) && (pair < machine->pending_count); pair += 1u)
    {
        const ClimbMachinePair *const pending = &machine->pending[pair];
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int leaves = (side == 0u) ? pending->earlier_leaves : pending->later_leaves;
            int *const lag_out = (side == 0u) ? pending->forward_lags : pending->backward_lags;
            int *const landing_out = (side == 0u) ? pending->forward : pending->backward;
            unsigned int *const final_score_out =
                (side == 0u) ? pending->forward_final_score : pending->backward_final_score;
            for (unsigned int leaf = 0u; leaf < leaves; leaf += 1u)
            {
                if (final_score_out != NULL)
                {
                    final_score_out[leaf] = machine->final_score[climber];
                }
                lag_out[3u * leaf] = machine->centers[3u * climber];
                lag_out[(3u * leaf) + 1u] = machine->centers[(3u * climber) + 1u];
                lag_out[(3u * leaf) + 2u] = machine->centers[(3u * climber) + 2u];
                landing_out[leaf] = (machine->landed[climber] == CLIMB_MACHINE_OUTSIDE) ? CLIMB_MACHINE_NO_LEAF
                                                                                        : (int)machine->landed[climber];
                climber += 1u;
            }
        }
    }
    machine->ran_count = (ok != 0) ? machine->pending_count : 0u;
    machine->pending_count = 0u;
    return ok;
}
