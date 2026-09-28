// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_pairs.c: pairs and overlap sums
#include "max_tree_internal.h"

unsigned int max_tree_probe_partition(const unsigned int *sorted, const unsigned int *own_level,
                                      const unsigned int *joined, unsigned int probe_count, unsigned int level,
                                      unsigned int *part)
{
    if ((sorted == NULL) || (own_level == NULL) || (part == NULL) || ((probe_count > 1u) && (joined == NULL)))
    {
        return 0u;
    }
    unsigned int parts = 0u;
    int open = 0;
    for (unsigned int at = 0u; at < probe_count; at += 1u)
    {
        const unsigned int probe = sorted[at];
        if ((at > 0u) && (joined[at - 1u] < level))
        {
            open = 0;
        }
        if ((own_level[probe] == 0u) || (own_level[probe] < level))
        {
            part[probe] = MAX_TREE_ABSENT;
            open = 0;
            continue;
        }
        if (open == 0)
        {
            open = 1;
            parts += 1u;
        }
        part[probe] = parts - 1u;
    }
    return parts;
}

void max_tree_pairs_release(MaxTreePairs *pairs)
{
    if (pairs == NULL)
    {
        return;
    }
    free(pairs->earlier);
    free(pairs->later);
    free(pairs->voxels);
    memset(pairs, 0, sizeof(*pairs));
}

long max_tree_pairs(const MaxTreePairsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const MaxTreeNodes *const earlier = request->earlier;
    const MaxTreeNodes *const later = request->later;
    MaxTreePairs *const pairs = request->pairs;
    if (!MAX_TREE_HOST_CHECK((earlier != NULL) && (later != NULL) && (pairs != NULL) && (earlier->own != NULL) &&
                                 (later->own != NULL),
                             request, error, ENGINE_ERROR_REQUEST) ||
        !MAX_TREE_HOST_CHECK((earlier->depth == later->depth) && (earlier->height == later->height) &&
                                 (earlier->width == later->width) && (earlier->voxels == later->voxels),
                             later, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_ERROR;
    }
    memset(pairs, 0, sizeof(*pairs));
    const size_t voxels = earlier->voxels;
    const size_t plane = (size_t)earlier->height * earlier->width;
    unsigned long long *const keys = (unsigned long long *)malloc((voxels + 1u) * sizeof(unsigned long long));
    if (!MAX_TREE_HOST_CHECK(keys != NULL, request, error, ENGINE_ERROR_RESOURCE))
    {
        return MAX_TREE_ERROR;
    }
    size_t found = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int from = earlier->own[voxel];
        if (from == MAX_TREE_ABSENT)
        {
            continue;
        }
        // each coordinate is below its extent, far under 2^63, and the lag is an int
        const long long z = (long long)(voxel / plane) + request->lag[0];
        const long long y = (long long)((voxel % plane) / earlier->width) + request->lag[1];
        const long long x = (long long)((voxel % plane) % earlier->width) + request->lag[2];
        if ((z < 0) || (z >= (long long)earlier->depth) || (y < 0) || (y >= (long long)earlier->height) || (x < 0) ||
            (x >= (long long)earlier->width))
        {
            continue;
        }
        // the target lies inside the extent: its index is below the voxel count
        const size_t target = (size_t)((((z * (long long)earlier->height) + y) * (long long)earlier->width) + x);
        const unsigned int to = later->own[target];
        if (to == MAX_TREE_ABSENT)
        {
            continue;
        }
        keys[found] = ((unsigned long long)from << 32u) | to;
        found += 1u;
    }
    qsort(keys, found, sizeof(unsigned long long), max_tree_key_compare);
    unsigned int distinct = 0u;
    for (size_t at = 0u; at < found; at += 1u)
    {
        distinct += ((at == 0u) || (keys[at] != keys[at - 1u])) ? 1u : 0u;
    }
    pairs->earlier = (unsigned int *)malloc(((size_t)distinct + 1u) * sizeof(unsigned int));
    pairs->later = (unsigned int *)malloc(((size_t)distinct + 1u) * sizeof(unsigned int));
    pairs->voxels = (unsigned long long *)malloc(((size_t)distinct + 1u) * sizeof(unsigned long long));
    if (!MAX_TREE_HOST_CHECK((pairs->earlier != NULL) && (pairs->later != NULL) && (pairs->voxels != NULL), request,
                             error, ENGINE_ERROR_RESOURCE))
    {
        free(keys);
        max_tree_pairs_release(pairs);
        return MAX_TREE_ERROR;
    }
    unsigned int entry = 0u;
    for (size_t at = 0u; at < found; at += 1u)
    {
        if ((at != 0u) && (keys[at] == keys[at - 1u]))
        {
            pairs->voxels[entry - 1u] += 1ull;
            continue;
        }
        // the high word is the earlier node and the low word the later one
        pairs->earlier[entry] = (unsigned int)(keys[at] >> 32u);
        pairs->later[entry] = (unsigned int)(keys[at] & 0xFFFFFFFFull);
        pairs->voxels[entry] = 1ull;
        entry += 1u;
    }
    free(keys);
    pairs->count = distinct;
    return (long)distinct;
}

static void max_tree_fenwick_add(unsigned long long *fenwick, unsigned int size, unsigned int at,
                                 unsigned long long amount)
{
    for (unsigned int slot = at + 1u; slot <= size; slot += slot & (0u - slot))
    {
        fenwick[slot] += amount;
    }
}

static unsigned long long max_tree_fenwick_below(const unsigned long long *fenwick, unsigned int end)
{
    unsigned long long total = 0ull;
    for (unsigned int slot = end; slot > 0u; slot -= slot & (0u - slot))
    {
        total += fenwick[slot];
    }
    return total;
}

long max_tree_overlap_sums(const MaxTreeOverlapSumsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const MaxTreeNodes *const earlier = request->earlier;
    const MaxTreeNodes *const later = request->later;
    const MaxTreePairs *const pairs = request->pairs;
    const unsigned int asked = request->asked;
    if (!MAX_TREE_HOST_CHECK((earlier != NULL) && (later != NULL) && (pairs != NULL) && (asked <= 0x7FFFFFFFu) &&
                                 ((asked == 0u) || ((request->earlier_nodes != NULL) &&
                                                    (request->later_nodes != NULL) && (request->sums != NULL))),
                             request, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_ERROR;
    }
    for (unsigned int entry = 0u; entry < pairs->count; entry += 1u)
    {
        // the sweep reads the table in the order max_tree_pairs lays it out, sorted by the earlier node
        if (!MAX_TREE_HOST_CHECK((pairs->earlier[entry] < earlier->count) && (pairs->later[entry] < later->count) &&
                                     ((entry == 0u) || (pairs->earlier[entry - 1u] <= pairs->earlier[entry])),
                                 &pairs->earlier[entry], error, ENGINE_ERROR_REQUEST))
        {
            return MAX_TREE_ERROR;
        }
    }
    for (unsigned int query = 0u; query < asked; query += 1u)
    {
        if (!MAX_TREE_HOST_CHECK((request->earlier_nodes[query] < earlier->count) &&
                                     (request->later_nodes[query] < later->count),
                                 &request->earlier_nodes[query], error, ENGINE_ERROR_REQUEST))
        {
            return MAX_TREE_ERROR;
        }
    }
    if (asked == 0u)
    {
        return 0L;
    }
    const size_t events = 2u * (size_t)asked;
    unsigned long long *const keys = (unsigned long long *)malloc(events * sizeof(unsigned long long));
    unsigned long long *const below = (unsigned long long *)malloc((size_t)asked * sizeof(unsigned long long));
    unsigned long long *const fenwick =
        (unsigned long long *)calloc((size_t)later->count + 1u, sizeof(unsigned long long));
    if (!MAX_TREE_HOST_CHECK((keys != NULL) && (below != NULL) && (fenwick != NULL), request, error,
                             ENGINE_ERROR_RESOURCE))
    {
        free(keys);
        free(below);
        free(fenwick);
        return MAX_TREE_ERROR;
    }
    for (unsigned int query = 0u; query < asked; query += 1u)
    {
        const unsigned int node = request->earlier_nodes[query];
        // an event's low word is twice the query, plus 1 for the range's lower edge; the high word is the row edge
        keys[2u * (size_t)query] = ((unsigned long long)earlier->subtree_end[node] << 32u) | (2ull * query);
        keys[(2u * (size_t)query) + 1u] = ((unsigned long long)node << 32u) | ((2ull * query) + 1ull);
    }
    qsort(keys, events, sizeof(unsigned long long), max_tree_key_compare);
    unsigned int entry = 0u;
    for (size_t at = 0u; at < events; at += 1u)
    {
        // the high word is a node index or a subtree's end, each below 2^32
        const unsigned int edge = (unsigned int)(keys[at] >> 32u);
        while ((entry < pairs->count) && (pairs->earlier[entry] < edge))
        {
            max_tree_fenwick_add(fenwick, later->count, pairs->later[entry], pairs->voxels[entry]);
            entry += 1u;
        }
        // the low word is twice the query plus the edge, below 2^32
        const unsigned int event = (unsigned int)(keys[at] & 0xFFFFFFFFull);
        const unsigned int query = event / 2u;
        const unsigned int node = request->later_nodes[query];
        const unsigned long long sum =
            max_tree_fenwick_below(fenwick, later->subtree_end[node]) - max_tree_fenwick_below(fenwick, node);
        if ((event % 2u) == 0u)
        {
            request->sums[query] = sum;
        }
        else
        {
            below[query] = sum;
        }
    }
    int ok = 1;
    for (unsigned int query = 0u; (ok != 0) && (query < asked); query += 1u)
    {
        // the rows below a subtree's start are a subset of the rows below its end
        ok =
            MAX_TREE_HOST_CHECK(request->sums[query] >= below[query], &request->sums[query], error, ENGINE_ERROR_LOGIC);
        request->sums[query] -= (ok != 0) ? below[query] : 0ull;
    }
    free(keys);
    free(below);
    free(fenwick);
    return (ok != 0) ? (long)asked : MAX_TREE_ERROR;
}
