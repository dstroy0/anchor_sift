// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// relate_frames_triples.cu: disagreement, triples, centers and bends
#include "relate_frames_internal.h"

unsigned long long leaf_disagreement(const TreeFrame *earlier, unsigned int leaf, const TreeFrame *later,
                                     unsigned int other, const unsigned int *band)
{
    const int *const lag =
        (earlier->forward_lag != NULL) ? &earlier->forward_lag[3u * (size_t)leaf] : earlier->lag_to_next;
    const int *const came = (earlier->backward_lag != NULL) ? &earlier->backward_lag[3u * (size_t)leaf] : NULL;
    const int *const back = (later->backward_lag != NULL) ? &later->backward_lag[3u * (size_t)other] : NULL;
    const int *const onward = (later->forward_lag != NULL) ? &later->forward_lag[3u * (size_t)other] : NULL;
    const int other_lag[3] = {(back != NULL) ? back[0] : -lag[0], (back != NULL) ? back[1] : -lag[1],
                              (back != NULL) ? back[2] : -lag[2]};
    const long long ahead = (long long)((later->step_back != 0u) ? later->step_back : 1u);
    const long long behind = (long long)((earlier->step_back != 0u) ? earlier->step_back : 1u);
    const long long onwards = (long long)((later->step_next != 0u) ? later->step_next : 1u);
    int lead[3];
    int other_lead[3];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const long long mine = (came != NULL) ? (-(long long)came[axis] * ahead) : ((long long)lag[axis] * behind);
        const long long theirs =
            (onward != NULL) ? (-(long long)onward[axis] * ahead) : ((long long)other_lag[axis] * onwards);
        lead[axis] = (int)((mine + ((mine >= 0ll) ? behind : -behind) / 2ll) / behind);
        other_lead[axis] = (int)((theirs + ((theirs >= 0ll) ? onwards : -onwards) / 2ll) / onwards);
    }
    unsigned long long shortest = 0xFFFFFFFFFFFFFFFFull;
    for (unsigned int pairing = 0u; pairing < 4u; pairing += 1u)
    {
        const int *const mine = ((pairing & 1u) == 0u) ? lag : lead;
        const int *const theirs = ((pairing & 2u) == 0u) ? other_lag : other_lead;
        unsigned long long magnitude = 0ull;
        unsigned long long widest = 0ull;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long apart = (long long)mine[axis] + (long long)theirs[axis];
            const unsigned long long spread = (unsigned long long)((apart < 0ll) ? -apart : apart);
            const unsigned int shift = (band != NULL) ? band[axis] : 0u;
            magnitude += ((unsigned long long)(apart * apart) * (unsigned long long)AXIS_WEIGHTS[axis]) >> shift;
            widest = (spread > widest) ? spread : widest;
        }
        unsigned int step = 0u;
        for (unsigned int sweep = 0u; sweep < LINK_SWEEP_STEPS; sweep += 1u)
        {
            step += (unsigned int)((1ull << step) < widest);
        }
        const unsigned long long swept =
            ((unsigned long long)step << LINK_MAGNITUDE_BITS) | (magnitude & LINK_MAGNITUDE_MASK);
        shortest = (swept < shortest) ? swept : shortest;
    }
    return shortest;
}

int cast_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later)
{
    const long long depth = (long long)buffers->depth;
    const long long height = (long long)buffers->height;
    const long long width = (long long)buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int *const labels = buffers->labels[1];
    int *const leaf_at_peak = buffers->leaf_at_peak[1];
    unsigned int *const counts = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const largest_shared = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const stamp = (unsigned int *)calloc((size_t)later->leaf_count + 1u, sizeof(unsigned int));
    unsigned int *const touched = (unsigned int *)malloc(((size_t)later->leaf_count + 1u) * sizeof(unsigned int));
    size_t capacity = (size_t)earlier->leaf_count * 8u + 16u;
    unsigned int *const starts = (unsigned int *)calloc((size_t)earlier->leaf_count + 2u, sizeof(unsigned int));
    unsigned int *after = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    unsigned int *shared = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    int ok = (counts != NULL) && (largest_shared != NULL) && (stamp != NULL) && (touched != NULL) && (starts != NULL) &&
             (after != NULL) && (shared != NULL);
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < later->leaf_count); leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = (int)leaf;
    }
    unsigned int kept = 0u;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        const int *const lag =
            (earlier->forward_lag != NULL) ? &earlier->forward_lag[3u * (size_t)leaf] : earlier->lag_to_next;
        unsigned int met = 0u;
        const unsigned int triple_first = (earlier->triple_start != NULL) ? earlier->triple_start[leaf] : 0u;
        const unsigned int triple_end = (earlier->triple_start != NULL) ? earlier->triple_start[leaf + 1u] : 0u;
        for (unsigned int pair = triple_first; pair < triple_end; pair += 1u)
        {
            const unsigned int found = earlier->triple_after[pair];
            const unsigned int fresh = (unsigned int)(stamp[found] != (leaf + 1u));
            touched[met] = found;
            met += fresh;
            counts[found] = (fresh != 0u) ? 0u : counts[found];
            largest_shared[found] = (fresh != 0u) ? 0u : largest_shared[found];
            stamp[found] = leaf + 1u;
            largest_shared[found] = (earlier->triple_shared[pair] > largest_shared[found])
                                        ? earlier->triple_shared[pair]
                                        : largest_shared[found];
        }
        for (unsigned int at = buffers->leaf_start[0][leaf]; at < buffers->leaf_start[0][leaf + 1u]; at += 1u)
        {
            const unsigned int voxel = buffers->leaf_voxels[0][at];
            const unsigned int rest = voxel % plane;
            const long long z = (long long)(voxel / plane) + (long long)lag[0];
            const long long y = (long long)(rest / buffers->width) + (long long)lag[1];
            const long long x = (long long)(rest % buffers->width) + (long long)lag[2];
            const int inside = (z >= 0ll) && (z < depth) && (y >= 0ll) && (y < height) && (x >= 0ll) && (x < width);
            const unsigned int landed = (unsigned int)(((z * height) + y) * width + x);
            const int other = (inside != 0) ? leaf_at_peak[labels[landed]] : -1;
            if (other < 0)
            {
                continue;
            }
            const unsigned int found = (unsigned int)other;
            const unsigned int fresh = (unsigned int)(stamp[found] != (leaf + 1u));
            touched[met] = found;
            met += fresh;
            counts[found] = (fresh != 0u) ? 0u : counts[found];
            largest_shared[found] = (fresh != 0u) ? 0u : largest_shared[found];
            stamp[found] = leaf + 1u;
            counts[found] += 1u;
        }
        if ((kept + met) > capacity)
        {
            const size_t grown = (kept + met) * 2u;
            unsigned int *const wider_after = (unsigned int *)realloc(after, grown * sizeof(unsigned int));
            unsigned int *const wider_shared = (unsigned int *)realloc(shared, grown * sizeof(unsigned int));
            after = (wider_after != NULL) ? wider_after : after;
            shared = (wider_shared != NULL) ? wider_shared : shared;
            ok = (wider_after != NULL) && (wider_shared != NULL);
            capacity = (ok != 0) ? grown : capacity;
        }
        for (unsigned int step = 1u; (ok != 0) && (step < met); step += 1u)
        {
            const unsigned int value = touched[step];
            unsigned int place = step;
            while ((place > 0u) && (touched[place - 1u] > value))
            {
                touched[place] = touched[place - 1u];
                place -= 1u;
            }
            touched[place] = value;
        }
        for (unsigned int step = 0u; (ok != 0) && (step < met); step += 1u)
        {
            after[kept] = touched[step];
            shared[kept] = (counts[touched[step]] > largest_shared[touched[step]]) ? counts[touched[step]]
                                                                                   : largest_shared[touched[step]];
            counts[touched[step]] = 0u;
            largest_shared[touched[step]] = 0u;
            kept += 1u;
        }
        starts[leaf + 1u] = met;
    }
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        starts[leaf + 1u] += starts[leaf];
    }
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = -1;
    }
    free(counts);
    free(largest_shared);
    free(stamp);
    free(touched);
    if (ok == 0)
    {
        free(starts);
        free(after);
        free(shared);
        return 0;
    }
    free(earlier->triple_start);
    free(earlier->triple_after);
    free(earlier->triple_shared);
    earlier->triple_start = starts;
    earlier->triple_after = after;
    earlier->triple_shared = shared;
    earlier->triple_count = kept;
    return 1;
}

static void object_center(const TreeFrame *frame, unsigned int object, long long *center)
{
    unsigned long long voxels = 0ull;
    unsigned long long sums[3] = {0ull, 0ull, 0ull};
    for (unsigned int member = frame->member_start[object]; member < frame->member_start[object + 1u]; member += 1u)
    {
        const unsigned int leaf = frame->members[member];
        voxels += (unsigned long long)frame->sizes[leaf];
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            sums[axis] += frame->sums[(3u * (size_t)leaf) + axis];
        }
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        center[axis] = (long long)(((sums[axis] * 2ull) + voxels) / (voxels * 2ull));
    }
}

unsigned long long track_bend(const TreeFrame *before, const TreeFrame *earlier, unsigned int object,
                              const TreeFrame *later, unsigned int candidate, const TreeFrame *after,
                              unsigned int by_band)
{
    long long here[3];
    long long there[3];
    object_center(earlier, object, here);
    object_center(later, candidate, there);
    unsigned long long bend = 0ull;
    unsigned int came_from = 0xFFFFFFFFu;
    unsigned long long widest = 0ull;
    for (unsigned int member = earlier->member_start[object];
         (before != NULL) && (earlier->backward != NULL) && (member < earlier->member_start[object + 1u]); member += 1u)
    {
        const unsigned int leaf = earlier->members[member];
        const int back = earlier->backward[leaf];
        const unsigned long long voxels = band_or_count(by_band, earlier->sizes[leaf]);
        came_from = ((back >= 0) && (voxels > widest)) ? before->object_of[(unsigned int)back] : came_from;
        widest = ((back >= 0) && (voxels > widest)) ? voxels : widest;
    }
    if (came_from != 0xFFFFFFFFu)
    {
        long long was[3];
        object_center(before, came_from, was);
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long turn = (there[axis] - here[axis]) - (here[axis] - was[axis]);
            bend += (unsigned long long)(turn * turn) * (unsigned long long)AXIS_WEIGHTS[axis];
        }
    }
    unsigned int goes_to = 0xFFFFFFFFu;
    widest = 0ull;
    for (unsigned int member = later->member_start[candidate];
         (after != NULL) && (later->forward != NULL) && (member < later->member_start[candidate + 1u]); member += 1u)
    {
        const unsigned int leaf = later->members[member];
        const int onward = later->forward[leaf];
        const unsigned long long voxels = band_or_count(by_band, later->sizes[leaf]);
        goes_to = ((onward >= 0) && (voxels > widest)) ? after->object_of[(unsigned int)onward] : goes_to;
        widest = ((onward >= 0) && (voxels > widest)) ? voxels : widest;
    }
    if (goes_to != 0xFFFFFFFFu)
    {
        long long will[3];
        object_center(after, goes_to, will);
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            const long long turn = (will[axis] - there[axis]) - (there[axis] - here[axis]);
            bend += (unsigned long long)(turn * turn) * (unsigned long long)AXIS_WEIGHTS[axis];
        }
    }
    return bend;
}

int still_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later)
{
    const long long depth = (long long)buffers->depth;
    const long long height = (long long)buffers->height;
    const long long width = (long long)buffers->width;
    const unsigned int plane = buffers->height * buffers->width;
    const unsigned int *const labels = buffers->labels[1];
    int *const leaf_at_peak = buffers->leaf_at_peak[1];
    free(earlier->triple_still);
    earlier->triple_still = (unsigned int *)calloc((size_t)earlier->triple_count + 1u, sizeof(unsigned int));
    int ok = (earlier->triple_still != NULL) ? 1 : 0;
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < later->leaf_count); leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = (int)leaf;
    }
    for (unsigned int leaf = 0u; (ok != 0) && (leaf < earlier->leaf_count); leaf += 1u)
    {
        const unsigned long long own_voxels = (unsigned long long)earlier->sizes[leaf];
        const unsigned int first = earlier->triple_start[leaf];
        const unsigned int end = earlier->triple_start[leaf + 1u];
        for (unsigned int pair = first; pair < end; pair += 1u)
        {
            const unsigned int other = earlier->triple_after[pair];
            const unsigned long long other_voxels = (unsigned long long)later->sizes[other];
            long long step[3];
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                const unsigned long long mine = earlier->sums[(3u * (size_t)leaf) + axis];
                const unsigned long long theirs = later->sums[(3u * (size_t)other) + axis];
                const long long from = (long long)(((mine * 2ull) + own_voxels) / (own_voxels * 2ull));
                const long long to = (long long)(((theirs * 2ull) + other_voxels) / (other_voxels * 2ull));
                step[axis] = to - from;
            }
            unsigned int still = 0u;
            for (unsigned int at = buffers->leaf_start[0][leaf]; at < buffers->leaf_start[0][leaf + 1u]; at += 1u)
            {
                const unsigned int voxel = buffers->leaf_voxels[0][at];
                const unsigned int rest = voxel % plane;
                const long long z = (long long)(voxel / plane) + step[0];
                const long long y = (long long)(rest / buffers->width) + step[1];
                const long long x = (long long)(rest % buffers->width) + step[2];
                const int inside = (z >= 0ll) && (z < depth) && (y >= 0ll) && (y < height) && (x >= 0ll) && (x < width);
                const unsigned int moved = (unsigned int)(((z * height) + y) * width + x);
                const int met = (inside != 0) ? leaf_at_peak[labels[moved]] : -1;
                still += (unsigned int)(met == (int)other);
            }
            earlier->triple_still[pair] = still;
        }
    }
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        leaf_at_peak[later->peaks[leaf]] = -1;
    }
    return ok;
}
