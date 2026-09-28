// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zarr_read.c: the shard index, fill and the read
#include "zarr_internal.h"

static int zarr_shard_index(ZarrWalk *walk, const char *path, long long file_bytes)
{
    const ZarrLayout *const layout = walk->request->layout;
    unsigned long long entries = 1ull;
    for (unsigned int axis = 0u; axis < walk->rank; axis += 1u)
    {
        entries *= layout->chunk[axis] / layout->inner[axis];
    }
    const unsigned long long index_bytes = (entries * 16ull) + ((layout->index_chain.crc32c != 0u) ? 4ull : 0ull);
    if ((layout->index_chain.count != 0u) || ((unsigned long long)file_bytes < index_bytes))
    {
        return 0;
    }
    unsigned char *const raw = (unsigned char *)malloc((size_t)index_bytes);
    unsigned long long *const index =
        (unsigned long long *)malloc((size_t)(entries * 2ull * sizeof(unsigned long long)));
    const unsigned long long at =
        (layout->index_at_start != 0u) ? 0ull : ((unsigned long long)file_bytes - index_bytes);
    int ok = (raw != NULL) && (index != NULL) &&
             (zarr_file_read(walk, path, at, index_bytes, raw) == (long long)index_bytes);
    if (ok && (layout->index_chain.crc32c != 0u))
    {
        ok = (zarr_crc32c(raw, index_bytes - 4ull) == (unsigned int)zarr_little(&raw[index_bytes - 4ull], 4u));
    }
    for (unsigned long long word = 0ull; ok && (word < (entries * 2ull)); word += 1ull)
    {
        index[word] =
            (layout->index_big_endian != 0u) ? zarr_big(&raw[word * 8ull], 8u) : zarr_little(&raw[word * 8ull], 8u);
    }
    free(raw);
    if (ok == 0)
    {
        free(index);
        return 0;
    }
    free(walk->shard_index);
    walk->shard_index = index;
    walk->shard_entries = entries;
    return 1;
}

static int zarr_leaf(ZarrWalk *walk, const unsigned long long *position)
{
    const ZarrLayout *const layout = walk->request->layout;
    const unsigned int rank = walk->rank;
    char path[ZARR_PATH_CAPACITY];
    unsigned long long actual[ENGINE_ARRAY_RANK];
    unsigned long long expected = walk->element_bytes;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        actual[axis] = walk->leaf[axis];
        expected *= walk->leaf[axis];
    }
    long long taken = 0ll;
    unsigned long long payload_at = 0ull;
    const ZarrChain *chain = &layout->chain;
    if (layout->sharded != 0u)
    {
        unsigned long long shard[ENGINE_ARRAY_RANK];
        unsigned long long inner[ENGINE_ARRAY_RANK];
        unsigned long long entry = 0ull;
        unsigned int same = walk->shard_valid;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            const unsigned long long per = layout->chunk[axis] / layout->inner[axis];
            shard[axis] = position[axis] / per;
            inner[axis] = position[axis] % per;
            entry = (entry * per) + inner[axis];
            same &= (unsigned int)(shard[axis] == walk->cached_shard[axis]);
        }
        if (zarr_key(layout, walk->request->root, shard, rank, path) == 0)
        {
            return 0;
        }
        const long long file_bytes = walk->request->tools->size(path);
        if (file_bytes < 0ll)
        {
            return 1;
        }
        if (same == 0u)
        {
            if (zarr_shard_index(walk, path, file_bytes) == 0)
            {
                return 0;
            }
            memcpy(walk->cached_shard, shard, sizeof(shard));
            walk->shard_valid = 1u;
        }
        const unsigned long long offset = walk->shard_index[entry * 2ull];
        const unsigned long long bytes = walk->shard_index[(entry * 2ull) + 1ull];
        if ((offset == ZARR_EMPTY_ENTRY) && (bytes == ZARR_EMPTY_ENTRY))
        {
            return 1;
        }
        if ((offset > (unsigned long long)file_bytes) || (bytes > ((unsigned long long)file_bytes - offset)) ||
            (zarr_reserve(&walk->raw, &walk->raw_capacity, bytes + 1ull) == 0))
        {
            return 0;
        }
        taken = zarr_file_read(walk, path, offset, bytes, walk->raw);
        if (taken != (long long)bytes)
        {
            return 0;
        }
        chain = &layout->inner_chain;
    }
    else
    {
        if (zarr_key(layout, walk->request->root, position, rank, path) == 0)
        {
            return 0;
        }
        const long long file_bytes = walk->request->tools->size(path);
        if (file_bytes < 0ll)
        {
            return 1;
        }
        if (zarr_reserve(&walk->raw, &walk->raw_capacity, (unsigned long long)file_bytes + 1ull) == 0)
        {
            return 0;
        }
        taken = zarr_file_read(walk, path, 0ull, (unsigned long long)file_bytes, walk->raw);
        if (taken != file_bytes)
        {
            return 0;
        }
        if (layout->format == ZARR_FORMAT_N5)
        {
            const unsigned int head = 4u + (4u * rank);
            if (((unsigned long long)taken < head) || (zarr_big(walk->raw, 2u) != 0ull) ||
                (zarr_big(&walk->raw[2], 2u) != (unsigned long long)rank))
            {
                return 0;
            }
            expected = walk->element_bytes;
            for (unsigned int axis = 0u; axis < rank; axis += 1u)
            {
                actual[rank - 1u - axis] = zarr_big(&walk->raw[4u + (4u * axis)], 4u);
                if ((actual[rank - 1u - axis] == 0ull) || (actual[rank - 1u - axis] > walk->leaf[rank - 1u - axis]))
                {
                    return 0;
                }
            }
            for (unsigned int axis = 0u; axis < rank; axis += 1u)
            {
                expected *= actual[axis];
            }
            payload_at = head;
        }
    }
    const long long made = zarr_unchain(walk, chain, &walk->raw[payload_at], (unsigned long long)taken - payload_at,
                                        walk->chunk, expected);
    if (made < 0ll)
    {
        return 0;
    }
    if (layout->big_endian != 0u)
    {
        zarr_swap(walk->chunk, expected / walk->element_bytes, walk->element_bytes);
    }
    zarr_place(walk, position, actual, expected / walk->element_bytes);
    return 1;
}

static void zarr_fill(const ZarrReadRequest *request, unsigned long long bytes, unsigned int element_bytes)
{
    unsigned int zero = 1u;
    for (unsigned int place = 0u; place < element_bytes; place += 1u)
    {
        zero &= (unsigned int)(request->layout->fill[place] == 0u);
    }
    if (zero != 0u)
    {
        memset(request->out, 0, (size_t)bytes);
        return;
    }
    for (unsigned long long at = 0ull; at < bytes; at += element_bytes)
    {
        memcpy(&request->out[at], request->layout->fill, element_bytes);
    }
}

long long zarr_read(const ZarrReadRequest *request)
{
    if ((request == NULL) || (request->layout == NULL) || (request->tools == NULL) || (request->tools->read == NULL) ||
        (request->tools->size == NULL) || (request->root == NULL) || (request->out == NULL))
    {
        return ZARR_ERROR;
    }
    const ZarrLayout *const layout = request->layout;
    const unsigned int rank = layout->extent.rank;
    const unsigned int element_bytes = layout->extent.element_bytes;
    if ((rank == 0u) || (rank > ENGINE_ARRAY_RANK) || (element_bytes == 0u) || (element_bytes > 8u) ||
        ((element_bytes & (element_bytes - 1u)) != 0u) || (request->first >= request->end) ||
        (request->end > layout->extent.sizes[0]) || (layout->chain.count > 1u) || (layout->inner_chain.count > 1u))
    {
        return ZARR_ERROR;
    }
    ZarrWalk walk;
    memset(&walk, 0, sizeof(walk));
    walk.request = request;
    walk.rank = rank;
    walk.element_bytes = element_bytes;
    walk.leaf = (layout->sharded != 0u) ? layout->inner : layout->chunk;
    unsigned long long total = (request->end - request->first) * element_bytes;
    unsigned long long leaf_bytes = element_bytes;
    unsigned int seen[ENGINE_ARRAY_RANK];
    memset(seen, 0, sizeof(seen));
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned int placed = layout->order[axis];
        if ((walk.leaf[axis] == 0ull) || (layout->extent.sizes[axis] == 0ull) || (placed >= rank) ||
            (seen[placed] != 0u) ||
            ((layout->sharded != 0u) && ((layout->chunk[axis] % layout->inner[axis]) != 0ull)) ||
            (walk.leaf[axis] > (1ull << 32u)))
        {
            return ZARR_ERROR;
        }
        seen[placed] = 1u;
        walk.grid[axis] = (layout->extent.sizes[axis] + walk.leaf[axis] - 1ull) / walk.leaf[axis];
        total *= (axis == 0u) ? 1ull : layout->extent.sizes[axis];
        leaf_bytes *= walk.leaf[axis];
    }
    if (total > request->out_capacity)
    {
        return ZARR_ERROR;
    }
    walk.chunk = (unsigned char *)malloc((size_t)leaf_bytes);
    walk.chunk_capacity = leaf_bytes;
    if (walk.chunk == NULL)
    {
        return ZARR_ERROR;
    }
    zarr_fill(request, total, element_bytes);
    const unsigned long long first_chunk = request->first / walk.leaf[0];
    const unsigned long long end_chunk = (request->end + walk.leaf[0] - 1ull) / walk.leaf[0];
    unsigned long long position[ENGINE_ARRAY_RANK];
    memset(position, 0, sizeof(position));
    position[0] = first_chunk;
    int ok = 1;
    while (ok && (position[0] < end_chunk))
    {
        ok = zarr_leaf(&walk, position);
        for (unsigned int axis = rank; axis > 0u; axis -= 1u)
        {
            position[axis - 1u] += 1ull;
            if ((position[axis - 1u] < walk.grid[axis - 1u]) || (axis == 1u))
            {
                break;
            }
            position[axis - 1u] = 0ull;
        }
    }
    free(walk.chunk);
    free(walk.raw);
    free(walk.shard_index);
    return ok ? (long long)total : ZARR_ERROR;
}
