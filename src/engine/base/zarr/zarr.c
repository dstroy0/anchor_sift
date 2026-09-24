// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "zarr.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZARR_PATH_ROOM ENGINE_PATH_ROOM

#define ZARR_N5_HEAD_MAX (4u + (4u * ENGINE_ARRAY_RANK))

#define ZARR_EMPTY_ENTRY 0xFFFFFFFFFFFFFFFFull

typedef struct
{
    const ZarrReadRequest *request;
    unsigned int rank;
    unsigned int element_bytes;
    const unsigned long long *leaf;
    unsigned long long grid[ENGINE_ARRAY_RANK];
    unsigned long long row_bytes;
    unsigned char *chunk;
    unsigned long long chunk_room;
    unsigned char *raw;
    unsigned long long raw_room;
    unsigned long long shard_held[ENGINE_ARRAY_RANK];
    unsigned int shard_valid;
    unsigned long long *shard_index;
    unsigned long long shard_entries;
} ZarrWalk;

static unsigned int zarr_crc32c_step(unsigned int crc, unsigned int byte)
{
    unsigned int carried = crc ^ byte;
    for (unsigned int bit = 0u; bit < 8u; bit += 1u)
    {
        carried = ((carried & 1u) != 0u) ? ((carried >> 1u) ^ 0x82F63B78u) : (carried >> 1u);
    }
    return carried;
}

static unsigned int zarr_crc32c(const unsigned char *bytes, unsigned long long count)
{
    static unsigned int table[256];
    static int table_ready = 0;
    if (table_ready == 0)
    {
        for (unsigned int byte = 0u; byte < 256u; byte += 1u)
        {
            table[byte] = zarr_crc32c_step(0u, byte);
        }
        table_ready = 1;
    }
    unsigned int crc = 0xFFFFFFFFu;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        crc = table[(crc ^ bytes[at]) & 0xFFu] ^ (crc >> 8u);
    }
    return crc ^ 0xFFFFFFFFu;
}

static unsigned long long zarr_little(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        value |= (unsigned long long)bytes[place] << (8u * place);
    }
    return value;
}

static unsigned long long zarr_big(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place];
    }
    return value;
}

static int zarr_room(unsigned char **buffer, unsigned long long *room, unsigned long long wanted)
{
    if (wanted <= *room)
    {
        return 1;
    }
    unsigned char *const grown = (unsigned char *)realloc(*buffer, (size_t)wanted);
    if (grown == NULL)
    {
        return 0;
    }
    *buffer = grown;
    *room = wanted;
    return 1;
}

static int zarr_key(const ZarrLayout *layout, const char *root, const unsigned long long *position, unsigned int rank,
                    char *path)
{
    int written = snprintf(path, ZARR_PATH_ROOM, "%s/", root);
    if ((written < 0) || ((unsigned int)written >= ZARR_PATH_ROOM))
    {
        return 0;
    }
    size_t at = (size_t)written;
    const char separator = (layout->format == ZARR_FORMAT_N5) ? '/' : layout->separator;
    if (layout->prefixed != 0u)
    {
        written = snprintf(&path[at], ZARR_PATH_ROOM - at, "c");
        at += (written > 0) ? (size_t)written : 0u;
    }
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned int named = (layout->format == ZARR_FORMAT_N5) ? (rank - 1u - axis) : axis;
        const int joined = (layout->prefixed != 0u) || (axis != 0u);
        written = joined ? snprintf(&path[at], ZARR_PATH_ROOM - at, "%c%llu", separator, position[named])
                         : snprintf(&path[at], ZARR_PATH_ROOM - at, "%llu", position[named]);
        if ((written < 0) || ((size_t)written >= (ZARR_PATH_ROOM - at)))
        {
            return 0;
        }
        at += (size_t)written;
    }
    if ((rank == 0u) && (layout->prefixed == 0u))
    {
        written = snprintf(&path[at], ZARR_PATH_ROOM - at, "0");
        at += (written > 0) ? (size_t)written : 0u;
    }
    return at < ZARR_PATH_ROOM;
}

static long long zarr_file_read(const ZarrWalk *walk, const char *path, unsigned long long offset,
                                unsigned long long bytes, unsigned char *out)
{
    EngineFileRange range;
    range.path = path;
    range.offset = offset;
    range.bytes = bytes;
    range.out = out;
    return walk->request->tools->read(&range);
}

static long long zarr_unchain(const ZarrWalk *walk, const ZarrChain *chain, unsigned char *raw,
                              unsigned long long raw_bytes, unsigned char *out, unsigned long long expected)
{
    unsigned long long held = raw_bytes;
    if (chain->crc32c != 0u)
    {
        if (held < 4ull)
        {
            return ZARR_REFUSED;
        }
        held -= 4ull;
        if (zarr_crc32c(raw, held) != (unsigned int)zarr_little(&raw[held], 4u))
        {
            return ZARR_REFUSED;
        }
    }
    if (chain->count == 0u)
    {
        if (held != expected)
        {
            return ZARR_REFUSED;
        }
        memcpy(out, raw, (size_t)expected);
        return (long long)expected;
    }
    if (chain->count != 1u)
    {
        return ZARR_REFUSED;
    }
    const EngineBytesDecode decode = walk->request->tools->decode[chain->codec[0]];
    if (decode == NULL)
    {
        return ZARR_REFUSED;
    }
    EngineBytesRequest bytes;
    bytes.in = raw;
    bytes.in_bytes = held;
    bytes.out = out;
    bytes.out_room = expected;
    const long long made = decode(&bytes);
    return (made == (long long)expected) ? made : ZARR_REFUSED;
}

static void zarr_swap(unsigned char *bytes, unsigned long long elements, unsigned int element_bytes)
{
    for (unsigned long long element = 0ull; element < elements; element += 1ull)
    {
        unsigned char *const at = &bytes[element * element_bytes];
        for (unsigned int low = 0u; low < (element_bytes / 2u); low += 1u)
        {
            const unsigned char held = at[low];
            at[low] = at[element_bytes - 1u - low];
            at[element_bytes - 1u - low] = held;
        }
    }
}

static void zarr_place(const ZarrWalk *walk, const unsigned long long *position, const unsigned long long *actual,
                       unsigned long long elements)
{
    const ZarrReadRequest *const request = walk->request;
    const ZarrLayout *const layout = request->layout;
    const unsigned int rank = walk->rank;
    const unsigned int element_bytes = walk->element_bytes;
    unsigned long long origin[ENGINE_ARRAY_RANK];
    unsigned long long stored[ENGINE_ARRAY_RANK];
    unsigned int identity = 1u;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        origin[axis] = position[axis] * walk->leaf[axis];
        stored[axis] = actual[layout->order[axis]];
        identity &= (unsigned int)(layout->order[axis] == axis);
    }
    unsigned long long counter[ENGINE_ARRAY_RANK];
    memset(counter, 0, sizeof(counter));
    unsigned long long source = 0ull;
    const unsigned long long last = (rank != 0u) ? stored[rank - 1u] : 1ull;
    const unsigned long long step = (identity != 0u) ? last : 1ull;
    while (source < elements)
    {
        unsigned long long logical[ENGINE_ARRAY_RANK];
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            logical[layout->order[axis]] = counter[axis];
        }
        unsigned int inside = 1u;
        unsigned long long target = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            const unsigned long long global = origin[axis] + logical[axis];
            const unsigned long long extent = (axis == 0u) ? (request->past - request->first)
                                                           : layout->shape.shape[axis];
            const unsigned long long shifted = (axis == 0u) ? (global - request->first) : global;
            inside &= (unsigned int)((axis != 0u) || ((global >= request->first) && (global < request->past)));
            inside &= (unsigned int)((axis == 0u) || (global < layout->shape.shape[axis]));
            target = (target * extent) + ((inside != 0u) ? shifted : 0ull);
        }
        if (inside != 0u)
        {
            unsigned long long run = step;
            if (identity != 0u)
            {
                const unsigned long long room = layout->shape.shape[rank - 1u] - (origin[rank - 1u] + counter[rank - 1u]);
                run = (run < room) ? run : room;
            }
            memcpy(&request->out[target * element_bytes], &walk->chunk[source * element_bytes],
                   (size_t)(run * element_bytes));
        }
        source += step;
        for (unsigned int axis = rank; axis > 0u; axis -= 1u)
        {
            counter[axis - 1u] += (axis == rank) ? step : 1ull;
            if ((counter[axis - 1u] < stored[axis - 1u]) || (axis == 1u))
            {
                break;
            }
            counter[axis - 1u] = 0ull;
        }
    }
}

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
    unsigned long long *const index = (unsigned long long *)malloc((size_t)(entries * 2ull * sizeof(unsigned long long)));
    const unsigned long long at = (layout->index_at_start != 0u) ? 0ull : ((unsigned long long)file_bytes - index_bytes);
    int good = (raw != NULL) && (index != NULL)
            && (zarr_file_read(walk, path, at, index_bytes, raw) == (long long)index_bytes);
    if (good && (layout->index_chain.crc32c != 0u))
    {
        good = (zarr_crc32c(raw, index_bytes - 4ull) == (unsigned int)zarr_little(&raw[index_bytes - 4ull], 4u));
    }
    for (unsigned long long word = 0ull; good && (word < (entries * 2ull)); word += 1ull)
    {
        index[word] = (layout->index_big_endian != 0u) ? zarr_big(&raw[word * 8ull], 8u)
                                                       : zarr_little(&raw[word * 8ull], 8u);
    }
    free(raw);
    if (good == 0)
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
    char path[ZARR_PATH_ROOM];
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
            same &= (unsigned int)(shard[axis] == walk->shard_held[axis]);
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
            memcpy(walk->shard_held, shard, sizeof(shard));
            walk->shard_valid = 1u;
        }
        const unsigned long long offset = walk->shard_index[entry * 2ull];
        const unsigned long long bytes = walk->shard_index[(entry * 2ull) + 1ull];
        if ((offset == ZARR_EMPTY_ENTRY) && (bytes == ZARR_EMPTY_ENTRY))
        {
            return 1;
        }
        if ((offset > (unsigned long long)file_bytes) || (bytes > ((unsigned long long)file_bytes - offset))
         || (zarr_room(&walk->raw, &walk->raw_room, bytes + 1ull) == 0))
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
        if (zarr_room(&walk->raw, &walk->raw_room, (unsigned long long)file_bytes + 1ull) == 0)
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
            if (((unsigned long long)taken < head) || (zarr_big(walk->raw, 2u) != 0ull)
             || (zarr_big(&walk->raw[2], 2u) != (unsigned long long)rank))
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
    if ((request == NULL) || (request->layout == NULL) || (request->tools == NULL) || (request->tools->read == NULL)
     || (request->tools->size == NULL) || (request->root == NULL) || (request->out == NULL))
    {
        return ZARR_REFUSED;
    }
    const ZarrLayout *const layout = request->layout;
    const unsigned int rank = layout->shape.rank;
    const unsigned int element_bytes = layout->shape.element_bytes;
    if ((rank == 0u) || (rank > ENGINE_ARRAY_RANK) || (element_bytes == 0u) || (element_bytes > 8u)
     || ((element_bytes & (element_bytes - 1u)) != 0u) || (request->first >= request->past)
     || (request->past > layout->shape.shape[0]) || (layout->chain.count > 1u) || (layout->inner_chain.count > 1u))
    {
        return ZARR_REFUSED;
    }
    ZarrWalk walk;
    memset(&walk, 0, sizeof(walk));
    walk.request = request;
    walk.rank = rank;
    walk.element_bytes = element_bytes;
    walk.leaf = (layout->sharded != 0u) ? layout->inner : layout->chunk;
    unsigned long long total = (request->past - request->first) * element_bytes;
    unsigned long long leaf_bytes = element_bytes;
    unsigned int seen[ENGINE_ARRAY_RANK];
    memset(seen, 0, sizeof(seen));
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned int placed = layout->order[axis];
        if ((walk.leaf[axis] == 0ull) || (layout->shape.shape[axis] == 0ull) || (placed >= rank) || (seen[placed] != 0u)
         || ((layout->sharded != 0u) && ((layout->chunk[axis] % layout->inner[axis]) != 0ull))
         || (walk.leaf[axis] > (1ull << 32u)))
        {
            return ZARR_REFUSED;
        }
        seen[placed] = 1u;
        walk.grid[axis] = (layout->shape.shape[axis] + walk.leaf[axis] - 1ull) / walk.leaf[axis];
        total *= (axis == 0u) ? 1ull : layout->shape.shape[axis];
        leaf_bytes *= walk.leaf[axis];
    }
    if (total > request->out_room)
    {
        return ZARR_REFUSED;
    }
    walk.chunk = (unsigned char *)malloc((size_t)leaf_bytes);
    walk.chunk_room = leaf_bytes;
    if (walk.chunk == NULL)
    {
        return ZARR_REFUSED;
    }
    zarr_fill(request, total, element_bytes);
    const unsigned long long first_chunk = request->first / walk.leaf[0];
    const unsigned long long past_chunk = (request->past + walk.leaf[0] - 1ull) / walk.leaf[0];
    unsigned long long position[ENGINE_ARRAY_RANK];
    memset(position, 0, sizeof(position));
    position[0] = first_chunk;
    int good = 1;
    while (good && (position[0] < past_chunk))
    {
        good = zarr_leaf(&walk, position);
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
    return good ? (long long)total : ZARR_REFUSED;
}
