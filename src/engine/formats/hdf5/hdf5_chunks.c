// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_chunks.c: decoding and placing chunks
#include "hdf5_internal.h"

static long long hdf5_decode(const Hdf5File *file, EngineCodec codec, const unsigned char *in, size_t in_bytes,
                             unsigned char *out, size_t capacity)
{
    const EngineBytesDecode decode = file->tools->decode[codec];
    if (decode == NULL)
    {
        return -1LL;
    }
    const EngineBytesRequest request = {in, in_bytes, out, capacity};
    const long long made = decode(&request);
    return ((made < 0LL) || ((unsigned long long)made > (unsigned long long)capacity)) ? -1LL : made;
}

static long long hdf5_lz4_frames(const Hdf5File *file, const unsigned char *in, size_t length, unsigned char *out,
                                 size_t capacity)
{
    if (length < 12u)
    {
        return -1LL;
    }
    const unsigned long long total = hdf5_big(in, 8u);
    const unsigned long long declared = hdf5_big(&in[8u], 4u);
    const unsigned long long block = (declared > total) ? total : declared;
    if ((total > (unsigned long long)capacity) || ((block == 0ull) && (total != 0ull)))
    {
        return -1LL;
    }
    size_t at = 12u;
    unsigned long long made = 0ull;
    while (made < total)
    {
        const unsigned long long piece = ((total - made) < block) ? (total - made) : block;
        if ((length - at) < 4u)
        {
            return -1LL;
        }
        const unsigned long long packed = hdf5_big(&in[at], 4u);
        at += 4u;
        if (packed > (unsigned long long)(length - at))
        {
            return -1LL;
        }
        if (packed == piece)
        {
            memcpy(&out[made], &in[at], (size_t)piece);
        }
        else if (hdf5_decode(file, ENGINE_CODEC_LZ4, &in[at], (size_t)packed, &out[made], (size_t)piece) !=
                 (long long)piece)
        {
            return -1LL;
        }
        at += (size_t)packed;
        made += piece;
    }
    return (long long)made;
}

static long long hdf5_unshuffle(const unsigned char *in, size_t length, unsigned char *out, unsigned int width)
{
    const size_t count = (width > 1u) ? (length / width) : 0u;
    for (size_t lane = 0u; lane < ((count > 0u) ? width : 0u); lane += 1u)
    {
        for (size_t element = 0u; element < count; element += 1u)
        {
            out[(element * width) + lane] = in[(lane * count) + element];
        }
    }
    const size_t settled = count * width;
    memcpy(&out[settled], &in[settled], length - settled);
    return (long long)length;
}

static long long hdf5_fletcher(const unsigned char *in, size_t length, unsigned char *out)
{
    if (length < HDF5_SEAL_BYTES)
    {
        return -1LL;
    }
    const size_t body = length - HDF5_SEAL_BYTES;
    const uint32_t stored = (uint32_t)hdf5_little(&in[body], 4u);
    const uint32_t computed = hdf5_fletcher32(in, body);
    const uint32_t swapped = ((computed & 0x00FF00FFu) << 8u) | ((computed >> 8u) & 0x00FF00FFu);
    if ((stored != computed) && (stored != swapped))
    {
        return -1LL;
    }
    memcpy(out, in, body);
    return (long long)body;
}

static int hdf5_unfilter(Hdf5Gather *gather, unsigned char **data, unsigned char **spare, size_t *length,
                         size_t capacity, unsigned int mask)
{
    Hdf5File *const file = gather->file;
    const Hdf5Object *const object = gather->object;
    for (unsigned int step = object->filter_count; step > 0u; step -= 1u)
    {
        const unsigned int place = step - 1u;
        const Hdf5Filter *const filter = &object->filters[place];
        const unsigned int identifier = filter->identifier;
        const int skipped = ((mask >> place) & 1u) != 0u;
        const unsigned char *const in = *data;
        unsigned char *const out = *spare;
        const long long made =
            skipped              ? (long long)*length
            : (identifier == 1u) ? hdf5_decode(file, ENGINE_CODEC_ZLIB, in, *length, out, capacity)
            : (identifier == 2u)
                ? hdf5_unshuffle(in, *length, out,
                                 (filter->value_count > 0u) ? filter->values[0u] : object->element_bytes)
            : (identifier == 3u)     ? hdf5_fletcher(in, *length, out)
            : (identifier == 32001u) ? hdf5_decode(file, ENGINE_CODEC_BLOSC, in, *length, out, capacity)
            : (identifier == 32004u) ? hdf5_lz4_frames(file, in, *length, out, capacity)
            : (identifier == 32015u) ? hdf5_decode(file, ENGINE_CODEC_ZSTD, in, *length, out, capacity)
                                     : -1LL;
        if (made < 0LL)
        {
            return hdf5_refuse_number(file, "a chunk its filter would not decode, or whose checksum failed; filter",
                                      identifier);
        }
        if (!skipped)
        {
            *spare = *data;
            *data = out;
            *length = (size_t)made;
        }
    }
    return 1;
}

static void hdf5_chunk_copy(const Hdf5Gather *gather, const unsigned char *chunk, const unsigned long long *origin,
                            const unsigned long long *low, const unsigned long long *high)
{
    const unsigned int rank = gather->object->rank;
    const unsigned long long element = gather->object->element_bytes;
    const size_t run = (size_t)((high[rank - 1u] - low[rank - 1u]) * element);
    unsigned long long position[ENGINE_ARRAY_RANK];
    memcpy(position, low, rank * sizeof(position[0u]));
    int more = 1;
    while (more)
    {
        unsigned long long source = 0ull;
        unsigned long long target = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            source += (position[axis] - origin[axis]) * gather->chunk_stride[axis];
            target += (position[axis] - ((axis == 0u) ? gather->first : 0ull)) * gather->out_stride[axis];
        }
        memcpy(&gather->out[target * element], &chunk[source * element], run);
        more = 0;
        for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
        {
            const unsigned int moving = axis - 1u;
            position[moving] += 1ull;
            if (position[moving] < high[moving])
            {
                more = 1;
                break;
            }
            position[moving] = low[moving];
        }
    }
}

int hdf5_chunk_place(Hdf5Gather *gather, const unsigned long long *origin, unsigned long long address,
                     unsigned long long stored, unsigned int mask)
{
    Hdf5File *const file = gather->file;
    const Hdf5Object *const object = gather->object;
    unsigned long long low[ENGINE_ARRAY_RANK];
    unsigned long long high[ENGINE_ARRAY_RANK];
    int edge = 0;
    int overlaps = 1;
    for (unsigned int axis = 0u; overlaps && (axis < object->rank); axis += 1u)
    {
        const unsigned long long span = object->chunk[axis];
        if ((origin[axis] % span) != 0ull)
        {
            return hdf5_refuse(file, "a chunk that does not sit on the chunk grid");
        }
        const unsigned long long bottom = (axis == 0u) ? gather->first : 0ull;
        const unsigned long long top = (axis == 0u) ? gather->end : object->extent[axis];
        const unsigned long long end = (origin[axis] > (~0ull - span)) ? ~0ull : (origin[axis] + span);
        low[axis] = (origin[axis] > bottom) ? origin[axis] : bottom;
        high[axis] = (end < top) ? end : top;
        overlaps = (low[axis] < high[axis]);
        edge = edge || (end > object->extent[axis]);
    }
    if (!overlaps || hdf5_undefined(file, address))
    {
        return 1;
    }
    const int filtered = (object->filter_count > 0u) && !(edge && ((object->chunk_flags & 1u) != 0u));
    if (!filtered && (stored != gather->chunk_bytes))
    {
        return hdf5_refuse(file, "an unfiltered chunk whose stored size is not the chunk size");
    }
    if ((stored == 0ull) || (stored > hdf5_bytes_remaining(file, address)))
    {
        return hdf5_refuse(file, "a chunk that lies past the end of the file");
    }
    const size_t capacity = (((size_t)stored > gather->chunk_bytes) ? (size_t)stored : gather->chunk_bytes) + 64u;
    unsigned char *data = (unsigned char *)malloc(capacity);
    unsigned char *spare = filtered ? (unsigned char *)malloc(capacity) : NULL;
    int ok = (data != NULL) && (!filtered || (spare != NULL));
    ok = ok ? hdf5_fetch(file, address, stored, data) : hdf5_refuse(file, "no memory for a chunk");
    size_t length = (size_t)stored;
    ok = ok && (!filtered || hdf5_unfilter(gather, &data, &spare, &length, capacity, mask));
    ok = ok && ((length == gather->chunk_bytes) || hdf5_refuse(file, "a chunk that does not decode to the chunk size"));
    if (ok)
    {
        hdf5_chunk_copy(gather, data, origin, low, high);
    }
    free(data);
    free(spare);
    return ok;
}

int hdf5_chunk_tree(Hdf5Gather *gather, unsigned long long address, unsigned int level, int root, unsigned int depth)
{
    Hdf5File *const file = gather->file;
    const Hdf5Object *const object = gather->object;
    const unsigned int dimensions = object->rank + 1u;
    const size_t key_bytes = 8u + (8u * (size_t)dimensions);
    const size_t pointer_bytes = file->offset_bytes;
    const size_t head = 8u + (2u * pointer_bytes);
    unsigned char prefix[24u];
    if (depth > HDF5_TREE_LEVELS)
    {
        return hdf5_refuse(file, "a chunk B-tree deeper than any real file");
    }
    if (!hdf5_fetch(file, address, head, prefix))
    {
        return 0;
    }
    const unsigned int node_level = prefix[5u];
    const size_t entries = (size_t)hdf5_little(&prefix[6u], 2u);
    if ((memcmp(prefix, "TREE", 4u) != 0) || (prefix[4u] != 1u) || (!root && (node_level != level)))
    {
        return hdf5_refuse(file, "a chunk B-tree node whose signature, type or level is wrong");
    }
    if (entries == 0u)
    {
        return root ? 1 : hdf5_refuse(file, "an empty chunk B-tree node below the root");
    }
    unsigned char *const node = hdf5_load(file, address, head + (entries * (key_bytes + pointer_bytes)) + key_bytes);
    if (node == NULL)
    {
        return 0;
    }
    int ok = 1;
    for (size_t child = 0u; ok && (child < entries); child += 1u)
    {
        const unsigned char *const key = &node[head + (child * (key_bytes + pointer_bytes))];
        const unsigned char *const next = &key[key_bytes + pointer_bytes];
        const unsigned long long child_address = hdf5_little(&key[key_bytes], file->offset_bytes);
        unsigned long long origin[ENGINE_ARRAY_RANK + 1u];
        for (unsigned int axis = 0u; axis < dimensions; axis += 1u)
        {
            origin[axis] = hdf5_little(&key[8u + (8u * axis)], 8u);
        }
        if (node_level == 0u)
        {
            int after = !gather->keyed;
            for (unsigned int axis = 0u; !after && (axis < dimensions); axis += 1u)
            {
                if (origin[axis] != gather->last_key[axis])
                {
                    after = (origin[axis] > gather->last_key[axis]) ? 1 : -1;
                }
            }
            ok = (after > 0) ? 1 : hdf5_refuse(file, "chunk B-tree keys that repeat or run out of order");
            memcpy(gather->last_key, origin, dimensions * sizeof(origin[0u]));
            gather->keyed = 1;
            ok = ok && hdf5_chunk_place(gather, origin, child_address, hdf5_little(key, 4u),
                                        (unsigned int)hdf5_little(&key[4u], 4u));
        }
        else
        {
            const unsigned long long upper = hdf5_little(&next[8u], 8u);
            const int ranges = (upper > (~0ull - object->chunk[0u])) || ((upper + object->chunk[0u]) > gather->first);
            const int needed = (origin[0u] < gather->end) && ranges;
            ok = !needed || hdf5_chunk_tree(gather, child_address, node_level - 1u, 0, depth + 1u);
        }
    }
    free(node);
    return ok;
}

void hdf5_fixed_close(Hdf5Fixed *fixed)
{
    free(fixed->prefix);
    free(fixed->page);
    fixed->prefix = NULL;
    fixed->page = NULL;
}

int hdf5_fixed_open(Hdf5File *file, const Hdf5Object *object, const Hdf5Gather *gather, Hdf5Fixed *fixed)
{
    memset(fixed, 0, sizeof(*fixed));
    fixed->prefix = NULL;
    fixed->page = NULL;
    if (hdf5_undefined(file, object->data_address))
    {
        return 1;
    }
    const unsigned int offset_bytes = file->offset_bytes;
    const size_t header_bytes = 8u + (size_t)file->length_bytes + offset_bytes + HDF5_SEAL_BYTES;
    unsigned char *const header = hdf5_load(file, object->data_address, header_bytes);
    if (header == NULL)
    {
        return 0;
    }
    const int sound = hdf5_sealed(header, header_bytes) && (memcmp(header, "FAHD", 4u) == 0) && (header[4u] == 0u);
    const unsigned int client = header[5u];
    fixed->entry_bytes = header[6u];
    const unsigned int page_bits = header[7u];
    fixed->count = hdf5_little(&header[8u], file->length_bytes);
    fixed->block = hdf5_little(&header[8u + file->length_bytes], offset_bytes);
    free(header);
    if (!sound)
    {
        return hdf5_refuse(file, "a fixed array header whose signature or checksum does not match");
    }
    unsigned long long expected = 0ull;
    fixed->filtered = (client == 1u);
    const int entry_fits =
        fixed->filtered ? ((fixed->entry_bytes > (offset_bytes + 4u)) && (fixed->entry_bytes <= (offset_bytes + 12u)))
                        : (fixed->entry_bytes == offset_bytes);
    const int shaped = (client <= 1u) && (fixed->filtered == (object->filter_count > 0u)) && entry_fits &&
                       (page_bits < 32u) && hdf5_product(gather->range, object->rank, 1ull, &expected) &&
                       (fixed->count == expected) && (fixed->count <= file->file_bytes);
    if (!shaped)
    {
        return hdf5_refuse(file, "a fixed array header that does not fit the dataset");
    }
    fixed->size_bytes = fixed->filtered ? (fixed->entry_bytes - offset_bytes - 4u) : 0u;
    if (hdf5_undefined(file, fixed->block))
    {
        return 1;
    }
    fixed->page_elements = 1ull << page_bits;
    fixed->page_count = (fixed->count > fixed->page_elements)
                            ? ((fixed->count + fixed->page_elements - 1ull) / fixed->page_elements)
                            : 0ull;
    fixed->head_bytes = 6u + (size_t)offset_bytes;
    fixed->prefix_bytes = fixed->head_bytes + (size_t)((fixed->page_count + 7ull) / 8ull) + HDF5_SEAL_BYTES;
    const unsigned long long loaded = (fixed->page_count == 0ull)
                                          ? (fixed->head_bytes + (fixed->count * fixed->entry_bytes) + HDF5_SEAL_BYTES)
                                          : fixed->prefix_bytes;
    fixed->prefix = hdf5_load(file, fixed->block, loaded);
    if (fixed->prefix == NULL)
    {
        return 0;
    }
    const int block_sound = hdf5_sealed(fixed->prefix, (size_t)loaded) && (memcmp(fixed->prefix, "FADB", 4u) == 0) &&
                            (fixed->prefix[4u] == 0u) && (fixed->prefix[5u] == client) &&
                            (hdf5_little(&fixed->prefix[6u], offset_bytes) == object->data_address);
    if (!block_sound)
    {
        hdf5_fixed_close(fixed);
        return hdf5_refuse(file, "a fixed array data block whose signature or checksum does not match");
    }
    return 1;
}

int hdf5_fixed_entry(Hdf5File *file, Hdf5Fixed *fixed, unsigned long long linear, unsigned long long *address,
                     unsigned long long *stored, unsigned int *mask)
{
    *address = hdf5_all_ones(file->offset_bytes);
    if (fixed->prefix == NULL)
    {
        return 1;
    }
    if (linear >= fixed->count)
    {
        return hdf5_refuse(file, "a chunk outside the fixed array");
    }
    const unsigned char *entry = NULL;
    if (fixed->page_count == 0ull)
    {
        entry = &fixed->prefix[fixed->head_bytes + (size_t)(linear * fixed->entry_bytes)];
    }
    else
    {
        const unsigned long long page = linear / fixed->page_elements;
        const unsigned long long within = linear % fixed->page_elements;
        if ((fixed->prefix[fixed->head_bytes + (size_t)(page / 8ull)] & (0x80u >> (unsigned int)(page % 8ull))) == 0u)
        {
            return 1;
        }
        if ((fixed->page == NULL) || (fixed->page_loaded != (page + 1ull)))
        {
            free(fixed->page);
            fixed->page = NULL;
            const unsigned long long elements = ((page + 1ull) == fixed->page_count)
                                                    ? (fixed->count - (page * fixed->page_elements))
                                                    : fixed->page_elements;
            const unsigned long long page_bytes = (elements * fixed->entry_bytes) + HDF5_SEAL_BYTES;
            const unsigned long long stride = (fixed->page_elements * fixed->entry_bytes) + HDF5_SEAL_BYTES;
            fixed->page = hdf5_load(file, fixed->block + fixed->prefix_bytes + (page * stride), page_bytes);
            if (fixed->page == NULL)
            {
                return 0;
            }
            if (!hdf5_sealed(fixed->page, (size_t)page_bytes))
            {
                free(fixed->page);
                fixed->page = NULL;
                return hdf5_refuse(file, "a fixed array page whose checksum does not match");
            }
            fixed->page_loaded = page + 1ull;
        }
        entry = &fixed->page[(size_t)(within * fixed->entry_bytes)];
    }
    *address = hdf5_little(entry, file->offset_bytes);
    if (fixed->filtered)
    {
        *stored = hdf5_little(&entry[file->offset_bytes], fixed->size_bytes);
        *mask = (unsigned int)hdf5_little(&entry[file->offset_bytes + fixed->size_bytes], 4u);
    }
    return 1;
}
