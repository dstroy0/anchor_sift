#include "basin_overlap.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(unsigned int) == 4u, "basin_overlap: unsigned int must be 32 bits, a peak index");
_Static_assert(sizeof(unsigned long long) == 8u, "basin_overlap: unsigned long long must be 64 bits, a pair");

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

static long long overlap_moved(const BasinOverlapRequest *args, unsigned int position)
{
    unsigned int rest = position;
    long long moved = 0ll;
    long long stride = 1ll;
    for (unsigned int axis = args->axes; axis > 0u; axis -= 1u)
    {
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
    unsigned long long product = 1ull;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        product *= (unsigned long long)args->extents[axis];
    }
    if (product != (unsigned long long)args->voxels)
    {
        return BASIN_OVERLAP_REFUSED;
    }

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

        answer = (long)distinct;
        if (distinct <= (size_t)args->room)
        {
            size_t slot = 0u;
            for (size_t pair = 0u; pair < total; pair += 1u)
            {
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
