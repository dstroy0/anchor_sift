// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// relate_frames_contacts.cu: peaks, coherence, lag and contacts
#include "relate_frames_internal.h"

static int land_peak(const EngineBuffers *buffers, unsigned int peak, const int *lag, const unsigned int *labels,
                     const TreeFrame *other)
{
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int rest = peak % plane;
    const long z = (long)(peak / plane) + (long)lag[0];
    const long y = (long)(rest / buffers->width) + (long)lag[1];
    const long x = (long)(rest % buffers->width) + (long)lag[2];
    if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height) || (x < 0L) ||
        (x >= (long)buffers->width))
    {
        return -1;
    }
    const unsigned int voxel = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
    return engine_leaf_of_peak(other->peaks, other->leaf_count, labels[voxel]);
}

static long long body_coherence(const EngineBuffers *buffers, const unsigned int *body, unsigned int count,
                                const unsigned long long *own_positive, const unsigned long long *other_positive,
                                const int *lag)
{
    const unsigned int plane = buffers->height * buffers->width;
    long long score = 0LL;
    for (unsigned int member = 0u; member < count; member += 1u)
    {
        const unsigned int voxel = body[member];
        const unsigned int rest = voxel % plane;
        const long z = (long)(voxel / plane) + (long)lag[0];
        const long y = (long)(rest / buffers->width) + (long)lag[1];
        const long x = (long)(rest % buffers->width) + (long)lag[2];
        if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height) || (x < 0L) ||
            (x >= (long)buffers->width))
        {
            continue;
        }
        const unsigned int landed = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
        const unsigned long long own = (own_positive[voxel / 64u] >> (voxel % 64u)) & 1ULL;
        const unsigned long long other = (other_positive[landed / 64u] >> (landed % 64u)) & 1ULL;
        score += (own == other) ? 1LL : 0LL;
    }
    return score;
}

static void climb_lag(const EngineBuffers *buffers, unsigned int slot, unsigned int leaf,
                      const unsigned int *contact_start, const unsigned int *contacts,
                      const unsigned long long *own_positive, const unsigned long long *other_positive,
                      const int *start, int *climbed)
{
    const auto patch_coherence = [&](const int *lag) -> long long {
        const unsigned int *const leaf_start = buffers->leaf_start[slot];
        long long total = body_coherence(buffers, &buffers->leaf_voxels[slot][leaf_start[leaf]],
                                         leaf_start[leaf + 1u] - leaf_start[leaf], own_positive, other_positive, lag);
        for (unsigned int contact = (contact_start != NULL) ? contact_start[leaf] : 0u;
             (contact_start != NULL) && (contact < contact_start[leaf + 1u]); contact += 1u)
        {
            const unsigned int near = contacts[contact];
            total += body_coherence(buffers, &buffers->leaf_voxels[slot][leaf_start[near]],
                                    leaf_start[near + 1u] - leaf_start[near], own_positive, other_positive, lag);
        }
        return total;
    };
    int here[3] = {start[0], start[1], start[2]};
    long long here_score = patch_coherence(here);
    for (;;)
    {
        int best[3] = {here[0], here[1], here[2]};
        long long best_score = here_score;
        unsigned long long best_length = 0ULL;
        int moved = 0;
        for (int step_z = -1; step_z <= 1; step_z += 1)
        {
            for (int step_y = -1; step_y <= 1; step_y += 1)
            {
                for (int step_x = -1; step_x <= 1; step_x += 1)
                {
                    if ((step_z == 0) && (step_y == 0) && (step_x == 0))
                    {
                        continue;
                    }
                    const int candidate[3] = {here[0] + step_z, here[1] + step_y, here[2] + step_x};
                    const long long score = patch_coherence(candidate);
                    const unsigned long long length =
                        (unsigned long long)AXIS_WEIGHTS[0] * (unsigned long long)(candidate[0] * candidate[0]) +
                        (unsigned long long)(candidate[1] * candidate[1]) +
                        (unsigned long long)(candidate[2] * candidate[2]);
                    if ((score > best_score) || ((moved != 0) && (score == best_score) && (length < best_length)))
                    {
                        best[0] = candidate[0];
                        best[1] = candidate[1];
                        best[2] = candidate[2];
                        best_score = score;
                        best_length = length;
                        moved = 1;
                    }
                }
            }
        }
        if (moved == 0)
        {
            break;
        }
        here[0] = best[0];
        here[1] = best[1];
        here[2] = best[2];
        here_score = best_score;
    }
    climbed[0] = here[0];
    climbed[1] = here[1];
    climbed[2] = here[2];
}

int frame_contacts(const TreeFrame *tree, unsigned int **contact_start, unsigned int **contacts)
{
    *contact_start = (unsigned int *)calloc((size_t)tree->leaf_count + 2u, sizeof(unsigned int));
    *contacts = (unsigned int *)malloc(((size_t)tree->joined_count + 1u) * 2u * sizeof(unsigned int));
    if ((*contact_start == NULL) || (*contacts == NULL))
    {
        return 0;
    }
    unsigned int *const start = *contact_start;
    for (unsigned int pair = 0u; pair < tree->joined_count; pair += 1u)
    {
        start[tree->joined[2u * pair] + 1u] += 1u;
        start[tree->joined[2u * pair + 1u] + 1u] += 1u;
    }
    for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
    {
        start[leaf + 1u] += start[leaf];
    }
    for (unsigned int pair = 0u; pair < tree->joined_count; pair += 1u)
    {
        const unsigned int left = tree->joined[2u * pair];
        const unsigned int right = tree->joined[2u * pair + 1u];
        (*contacts)[start[left]] = right;
        start[left] += 1u;
        (*contacts)[start[right]] = left;
        start[right] += 1u;
    }
    for (unsigned int leaf = tree->leaf_count; leaf > 0u; leaf -= 1u)
    {
        start[leaf] = start[leaf - 1u];
    }
    start[0] = 0u;
    return 1;
}

int relate_frames(EngineBuffers *buffers, TreeFrame *earlier, TreeFrame *later, const TreeRules *rules,
                  StageClock *clocks)
{
    int lag[3] = {0, 0, 0};
    unsigned long long mark = engine_clock_microseconds();
    if (rules->keep_view == 0)
    {
        ShiftAgreementRequest motion;
        memset(&motion, 0, sizeof(motion));
        motion.axes = 3u;
        motion.extents[0] = buffers->depth;
        motion.extents[1] = buffers->height;
        motion.extents[2] = buffers->width;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            motion.weights[axis] = AXIS_WEIGHTS[axis];
        }
        motion.before = buffers->positive[0];
        motion.after = buffers->positive[1];
        motion.counts = NULL;
        ShiftAgreementRequest again = motion;
        size_t padded_total = 1u;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            unsigned long long power = 1ull;
            while (power < (2ull * (unsigned long long)motion.extents[axis]) - 1ull)
            {
                power <<= 1u;
            }
            padded_total *= (size_t)power;
        }
        if (rules->motion_check != 0)
        {
            motion.counts = (unsigned int *)malloc(padded_total * sizeof(unsigned int));
            again.counts = (unsigned int *)malloc(padded_total * sizeof(unsigned int));
        }
        int moved_ok = ((rules->motion_check == 0) || ((motion.counts != NULL) && (again.counts != NULL))) &&
                       (shift_agreement_run(&motion) == 0L);
        if ((moved_ok != 0) && (rules->motion_check != 0))
        {
            moved_ok = (shift_agreement_run(&again) == 0L);
            if ((moved_ok != 0) &&
                ((memcmp(motion.counts, again.counts, padded_total * sizeof(unsigned int)) != 0) ||
                 (memcmp(motion.lag, again.lag, sizeof(motion.lag)) != 0) || (motion.agreement != again.agreement)))
            {
                fprintf(stderr, "    motion disagrees: frame %u\n", earlier->time);
            }
        }
        free(motion.counts);
        free(again.counts);
        if (moved_ok == 0)
        {
            return 0;
        }
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            lag[axis] = motion.lag[axis];
        }
    }
    const int back[3] = {-lag[0], -lag[1], -lag[2]};
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        earlier->lag_to_next[axis] = lag[axis];
    }
    earlier->step_next = later->time - earlier->time;
    later->step_back = later->time - earlier->time;
    clocks->motion += engine_clock_microseconds() - mark;
    mark = engine_clock_microseconds();

    earlier->forward = (int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(int));
    later->backward = (int *)malloc(((size_t)later->leaf_count + 1u) * sizeof(int));
    if ((earlier->forward == NULL) || (later->backward == NULL))
    {
        return 0;
    }
    if (rules->climb == 0)
    {
        for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
        {
            earlier->forward[leaf] = land_peak(buffers, earlier->peaks[leaf], lag, buffers->labels[1], later);
        }
        for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
        {
            later->backward[leaf] = land_peak(buffers, later->peaks[leaf], back, buffers->labels[0], earlier);
        }
    }
    else
    {
        earlier->forward_lag = (int *)malloc(((size_t)earlier->leaf_count + 1u) * 3u * sizeof(int));
        later->backward_lag = (int *)malloc(((size_t)later->leaf_count + 1u) * 3u * sizeof(int));
        int climbed = (earlier->forward_lag != NULL) && (later->backward_lag != NULL);
        if ((climbed != 0) && (rules->climb != 2))
        {
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = earlier->time;
            pair.later = later->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                pair.lag[axis] = lag[axis];
            }
            pair.earlier_leaves = earlier->leaf_count;
            pair.earlier_peaks = earlier->peaks;
            pair.later_leaves = later->leaf_count;
            pair.later_peaks = later->peaks;
            pair.forward_lags = earlier->forward_lag;
            pair.forward = earlier->forward;
            pair.backward_lags = later->backward_lag;
            pair.backward = later->backward;
            earlier->forward_final_score =
                (unsigned int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned int));
            pair.forward_final_score = earlier->forward_final_score;
            climbed = (earlier->forward_final_score != NULL) && (climb_machine_pend(buffers->machine, &pair) != 0);
        }
        if ((climbed != 0) && (rules->climb >= 2))
        {
            int *const forward_lags = (rules->climb == 2)
                                          ? earlier->forward_lag
                                          : (int *)malloc(((size_t)earlier->leaf_count + 1u) * 3u * sizeof(int));
            int *const backward_lags = (rules->climb == 2)
                                           ? later->backward_lag
                                           : (int *)malloc(((size_t)later->leaf_count + 1u) * 3u * sizeof(int));
            earlier->check_forward_lag = (rules->climb == 3) ? forward_lags : NULL;
            later->check_backward_lag = (rules->climb == 3) ? backward_lags : NULL;
            unsigned int *contact_start[2] = {NULL, NULL};
            unsigned int *contacts[2] = {NULL, NULL};
            climbed = (forward_lags != NULL) && (backward_lags != NULL);
            climbed =
                climbed && ((rules->sticky == 0) || ((frame_contacts(earlier, &contact_start[0], &contacts[0]) != 0) &&
                                                     (frame_contacts(later, &contact_start[1], &contacts[1]) != 0)));
            for (unsigned int leaf = 0u; (climbed != 0) && (leaf < earlier->leaf_count); leaf += 1u)
            {
                climb_lag(buffers, 0u, leaf, contact_start[0], contacts[0], buffers->positive[0], buffers->positive[1],
                          lag, &forward_lags[3u * leaf]);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (leaf < later->leaf_count); leaf += 1u)
            {
                climb_lag(buffers, 1u, leaf, contact_start[1], contacts[1], buffers->positive[1], buffers->positive[0],
                          back, &backward_lags[3u * leaf]);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (rules->climb == 2) && (leaf < earlier->leaf_count);
                 leaf += 1u)
            {
                earlier->forward[leaf] =
                    land_peak(buffers, earlier->peaks[leaf], &forward_lags[3u * leaf], buffers->labels[1], later);
            }
            for (unsigned int leaf = 0u; (climbed != 0) && (rules->climb == 2) && (leaf < later->leaf_count);
                 leaf += 1u)
            {
                later->backward[leaf] =
                    land_peak(buffers, later->peaks[leaf], &backward_lags[3u * leaf], buffers->labels[0], earlier);
            }
            free(contact_start[0]);
            free(contact_start[1]);
            free(contacts[0]);
            free(contacts[1]);
        }
        if (climbed == 0)
        {
            return 0;
        }
    }
    clocks->landing += engine_clock_microseconds() - mark;
    mark = engine_clock_microseconds();

    if (rules->pick == 0)
    {
        return 1;
    }
    long total = -1L;
    for (;;)
    {
        BodyOverlapRequest overlap;
        memset(&overlap, 0, sizeof(overlap));
        overlap.labels_before = climb_machine_labels(buffers->machine, earlier->time);
        overlap.positive_before = climb_machine_positive(buffers->machine, earlier->time);
        overlap.labels_after = climb_machine_labels(buffers->machine, later->time);
        overlap.positive_after = climb_machine_positive(buffers->machine, later->time);
        overlap.axes = 3u;
        overlap.extents[0] = buffers->depth;
        overlap.extents[1] = buffers->height;
        overlap.extents[2] = buffers->width;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            overlap.lag[axis] = lag[axis];
        }
        overlap.voxels = buffers->depth * buffers->height * buffers->width;
        overlap.capacity = buffers->overlap_capacity;
        overlap.peaks_before = buffers->overlap_before;
        overlap.peaks_after = buffers->overlap_after;
        overlap.counts = buffers->overlap_shared;
        total = body_overlap_run_on_device(&overlap);
        if (total < 0L)
        {
            return 0;
        }
        if ((unsigned long)total <= (unsigned long)buffers->overlap_capacity)
        {
            break;
        }
        buffers->overlap_capacity = (unsigned int)total;
        free(buffers->overlap_before);
        free(buffers->overlap_after);
        free(buffers->overlap_shared);
        buffers->overlap_before = (unsigned int *)malloc((size_t)buffers->overlap_capacity * sizeof(unsigned int));
        buffers->overlap_after = (unsigned int *)malloc((size_t)buffers->overlap_capacity * sizeof(unsigned int));
        buffers->overlap_shared = (unsigned int *)malloc((size_t)buffers->overlap_capacity * sizeof(unsigned int));
        if ((buffers->overlap_before == NULL) || (buffers->overlap_after == NULL) || (buffers->overlap_shared == NULL))
        {
            return 0;
        }
    }
    const unsigned int pairs = (unsigned int)total;
    earlier->triple_start = (unsigned int *)calloc((size_t)earlier->leaf_count + 1u, sizeof(unsigned int));
    earlier->triple_after = (unsigned int *)malloc(((size_t)pairs + 1u) * sizeof(unsigned int));
    earlier->triple_shared = (unsigned int *)malloc(((size_t)pairs + 1u) * sizeof(unsigned int));
    if ((earlier->triple_start == NULL) || (earlier->triple_after == NULL) || (earlier->triple_shared == NULL))
    {
        return 0;
    }
    unsigned int kept = 0u;
    for (unsigned int pair = 0u; pair < pairs; pair += 1u)
    {
        const int before = engine_leaf_of_peak(earlier->peaks, earlier->leaf_count, buffers->overlap_before[pair]);
        const int after = engine_leaf_of_peak(later->peaks, later->leaf_count, buffers->overlap_after[pair]);
        if ((before < 0) || (after < 0))
        {
            continue;
        }
        earlier->triple_start[(unsigned int)before + 1u] += 1u;
        earlier->triple_after[kept] = (unsigned int)after;
        earlier->triple_shared[kept] = buffers->overlap_shared[pair];
        kept += 1u;
    }
    for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
    {
        earlier->triple_start[leaf + 1u] += earlier->triple_start[leaf];
    }
    earlier->triple_count = kept;
    clocks->overlap += engine_clock_microseconds() - mark;
    if (rules->cast != 0)
    {
        const unsigned long long casting = engine_clock_microseconds();
        const int made = cast_triples(buffers, earlier, later);
        clocks->overlap += engine_clock_microseconds() - casting;
        return made;
    }
    if (rules->parallax != 0)
    {
        const unsigned long long moving = engine_clock_microseconds();
        const int made = still_triples(buffers, earlier, later);
        clocks->overlap += engine_clock_microseconds() - moving;
        return made;
    }
    return 1;
}
