// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// climb_machine_score.cu: scoring and deciding
#include "climb_machine_internal.h"

__global__ void machine_score_kernel(const unsigned int *run_start, const unsigned int *run_length,
                                     const unsigned int *entry_first, const unsigned int *entry_end,
                                     const unsigned int *entry_climber, unsigned int entries,
                                     const unsigned int *climber_side, const unsigned int *side_slots,
                                     const int *centers, const unsigned int *active, const unsigned long long *positive,
                                     MachineGeometry geometry, unsigned int *scores)
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
    for (unsigned int run = entry_first[entry]; run < entry_end[entry]; run += 1u)
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
                    const long long end = (width_left < length) ? width_left : length;
                    if ((inside_z != 0) && (inside_y != 0) && (first < end))
                    {
                        const unsigned long long row =
                            (unsigned long long)((z * (long long)geometry.height + y) * (long long)geometry.width);
                        counts[candidate] += machine_agreeing(
                            positive, geometry.words, own_word, (unsigned long long)start + (unsigned long long)first,
                            other_word, row + (unsigned long long)(x + first), (unsigned int)(end - first));
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

__global__ void machine_decide_kernel(const unsigned int *climber_entry_start, const unsigned int *scores,
                                      unsigned int climbers, MachineGeometry geometry, int *centers,
                                      unsigned int *active, unsigned int *moved, unsigned int *final_score)
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
                const unsigned long long length =
                    (unsigned long long)geometry.weight_z * (unsigned long long)(lag[0] * lag[0]) +
                    (unsigned long long)(lag[1] * lag[1]) + (unsigned long long)(lag[2] * lag[2]);
                if ((candidate != 13u) &&
                    ((sums[candidate] > best_score) ||
                     ((stepped != 0) && (sums[candidate] == best_score) && (length < best_length))))
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
        final_score[climber] = (unsigned int)sums[13];
    }
}
