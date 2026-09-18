/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file basin_overlap.c
 * @brief The host arm of the lagged overlap count, the reference the device arm is graded against.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note One packed key per overlapping voxel, before label in the high half and after label in the
 *       low half. Sorting the keys puts every repeat of a pair side by side, and a pass over them
 *       counts each pair. Nothing here is compared except integers for equality and order.
 */

#include "basin_overlap.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(unsigned int) == 4u, "basin_overlap: unsigned int must be 32 bits, a peak index");
_Static_assert(sizeof(unsigned long long) == 8u, "basin_overlap: unsigned long long must be 64 bits, a pair");

/**
 * @brief Orders two packed pair keys for qsort.
 *
 * @param[in] left  One key [BORROWS].
 * @param[in] right The other key [BORROWS].
 * @return          -1, 0 or 1 as `left` is below, equal to or above `right`.
 */
static int overlap_order(const void *left, const void *right)
{
    const unsigned long long one = *(const unsigned long long *)left;
    const unsigned long long other = *(const unsigned long long *)right;
    if (one != other)
    {
        return (one < other) ? -1 : 1;
    }
    return 0;
}

/**
 * @brief Where a voxel lands after the lag, or that it leaves the volume.
 *
 * @param[in] args     The request, read for its axes, extents and lag [BORROWS].
 * @param[in] position The voxel's index, last axis fastest.
 * @return             The index of the voxel it lands on, or -1 where any axis's coordinate
 *                     leaves the volume.
 * @note The volume does not wrap. A voxel shifted past an edge has no partner, and it contributes
 *       nothing to any pair.
 */
static long long overlap_moved(const BasinOverlapRequest *args, unsigned int position)
{
    unsigned int rest = position;
    long long moved = 0ll;
    long long stride = 1ll;
    for (unsigned int axis = args->axes; axis > 0u; axis -= 1u)
    {
        // Widened to 64 bits so a coordinate plus a negative lag is computed signed and a coordinate
        // below zero is seen as below zero.
        const long long extent = (long long)args->extents[axis - 1u];
        const long long coordinate = (long long)(rest % args->extents[axis - 1u]) + (long long)args->lag[axis - 1u];
        rest /= args->extents[axis - 1u];
        if ((coordinate < 0ll) || (coordinate >= extent))
        {
            return -1ll;
        }
        moved += coordinate * stride;
        stride *= extent;
    }
    return moved;
}

long basin_overlap_host(const BasinOverlapRequest *args)
{
    if ((args == NULL) || (args->labels_before == NULL) || (args->positive_before == NULL)
     || (args->labels_after == NULL) || (args->positive_after == NULL) || (args->voxels == 0u)
     || (args->axes == 0u) || (args->axes > BASIN_OVERLAP_AXES)
     || (args->room > BASIN_OVERLAP_ROOM_LIMIT)
     || ((args->room != 0u) && ((args->peaks_before == NULL) || (args->peaks_after == NULL)
                                || (args->counts == NULL))))
    {
        return BASIN_OVERLAP_REFUSED;
    }
    // The extents have to describe the frames the caller sized, voxel for voxel.
    unsigned long long product = 1ull;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        product *= (unsigned long long)args->extents[axis];
    }
    if (product != (unsigned long long)args->voxels)
    {
        return BASIN_OVERLAP_REFUSED;
    }

    // At most one key per voxel, since each before voxel lands on at most one after voxel.
    const size_t voxels = (size_t)args->voxels;
    unsigned long long *const pairs = (unsigned long long *)malloc(voxels * sizeof(unsigned long long));
    if (pairs == NULL)
    {
        return BASIN_OVERLAP_REFUSED;
    }

    size_t total = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned long long bit = 1ull << (voxel % 64u);
        if ((args->positive_before[voxel / 64u] & bit) == 0ull)
        {
            continue;
        }

        // voxel is below args->voxels, an unsigned int, so the narrowing loses nothing.
        const long long moved = overlap_moved(args, (unsigned int)voxel);
        if (moved < 0ll)
        {
            continue;
        }

        const size_t there = (size_t)moved;
        if ((args->positive_after[there / 64u] & (1ull << (there % 64u))) == 0ull)
        {
            continue;
        }

        pairs[total] = ((unsigned long long)args->labels_before[voxel] << 32u)
                     | (unsigned long long)args->labels_after[there];
        total += 1u;
    }
    if (total != 0u)
    {
        qsort(pairs, total, sizeof(unsigned long long), overlap_order);
    }

    size_t distinct = 0u;
    for (size_t pair = 0u; pair < total; pair += 1u)
    {
        if ((pair == 0u) || (pairs[pair] != pairs[pair - 1u]))
        {
            distinct += 1u;
        }
    }
    long answer = BASIN_OVERLAP_REFUSED;
    if (distinct <= (size_t)BASIN_OVERLAP_ROOM_LIMIT)
    {

        // distinct is at most BASIN_OVERLAP_ROOM_LIMIT, which a long holds on every target.
        answer = (long)distinct;
        if (distinct <= (size_t)args->room)
        {
            size_t slot = 0u;
            for (size_t pair = 0u; pair < total; pair += 1u)
            {
                // A repeat of the pair just written adds one voxel to its count.
                if ((pair != 0u) && (pairs[pair] == pairs[pair - 1u]))
                {
                    args->counts[slot - 1u] += 1u;
                    continue;
                }

                args->peaks_before[slot] = (unsigned int)(pairs[pair] >> 32u);
                args->peaks_after[slot] = (unsigned int)(pairs[pair] & 0xFFFFFFFFull);
                args->counts[slot] = 1u;
                slot += 1u;
            }
        }
    }
    free(pairs);
    return answer;
}
