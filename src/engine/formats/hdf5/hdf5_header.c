// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_header.c: the file's opening and the object header's messages
#include "hdf5_internal.h"

int hdf5_open(Hdf5File *file, const char *path, const EngineIngestTools *tools)
{
    memset(file, 0, sizeof(*file));
    file->path = path;
    file->tools = tools;
    file->budget = HDF5_BUDGET;
    file->offset_bytes = 8u;
    if ((path == NULL) || (tools == NULL) || (tools->read == NULL) || (tools->size == NULL))
    {
        return hdf5_error(file, "no path or no file reader");
    }
    const long long size = tools->size(path);
    if (size < 0LL)
    {
        return hdf5_error(file, "the file cannot be sized");
    }
    file->file_bytes = (unsigned long long)size;
    static const unsigned char signature[8u] = {0x89u, 0x48u, 0x44u, 0x46u, 0x0Du, 0x0Au, 0x1Au, 0x0Au};
    unsigned long long place = 0ull;
    int found = 0;
    while (!found && (file->file_bytes >= 16ull) && (place <= (file->file_bytes - 16ull)))
    {
        unsigned char probe[8u];
        if (!hdf5_fetch(file, place, sizeof(probe), probe))
        {
            return 0;
        }
        found = (memcmp(probe, signature, sizeof(probe)) == 0);
        place = found ? place : ((place == 0ull) ? 512ull : (place * 2ull));
    }
    if (!found)
    {
        return hdf5_error(file, "no HDF5 signature at byte 0, 512 or any doubling of 512");
    }
    unsigned char head[16u];
    if (!hdf5_fetch(file, place, sizeof(head), head))
    {
        return 0;
    }
    const unsigned int version = head[8u];
    if (version > 3u)
    {
        return hdf5_error_number(file, "superblock version", version);
    }
    const int old = (version <= 1u);
    file->offset_bytes = old ? head[13u] : head[9u];
    file->length_bytes = old ? head[14u] : head[10u];
    const int offsets_known = (file->offset_bytes == 2u) || (file->offset_bytes == 4u) || (file->offset_bytes == 8u);
    const int lengths_known = (file->length_bytes == 2u) || (file->length_bytes == 4u) || (file->length_bytes == 8u);
    if (!offsets_known || !lengths_known)
    {
        file->offset_bytes = 8u;
        return hdf5_error(file, "sizes of offsets or lengths other than 2, 4 or 8 bytes");
    }
    const size_t fixed = old ? ((version == 0u) ? 24u : 28u) : 12u;
    const unsigned long long total =
        old ? (fixed + (6ull * file->offset_bytes) + 24ull) : (fixed + (4ull * file->offset_bytes) + 4ull);
    unsigned char *const block = hdf5_load(file, place, total);
    if (block == NULL)
    {
        return 0;
    }
    Hdf5Cursor cursor = {block, (size_t)total, fixed, 0};
    const unsigned long long stored_base = hdf5_take(&cursor, file->offset_bytes);
    (void)hdf5_take(&cursor, file->offset_bytes);
    const unsigned long long stored_end = hdf5_take(&cursor, file->offset_bytes);
    const unsigned long long fourth = hdf5_take(&cursor, file->offset_bytes);
    (void)hdf5_take(&cursor, old ? file->offset_bytes : 0u);
    const unsigned long long root = old ? hdf5_take(&cursor, file->offset_bytes) : fourth;
    const int sealed = old || hdf5_sealed(block, (size_t)total);
    free(block);
    if (cursor.broken || !sealed)
    {
        return hdf5_error(file, "a superblock whose checksum does not match");
    }
    if (old && !hdf5_undefined(file, fourth))
    {
        return hdf5_error(file, "a file driver information block (family, multi or split driver)");
    }
    const unsigned long long shift_up = (stored_base <= place) ? (place - stored_base) : 0ull;
    const unsigned long long shift_down = (stored_base > place) ? (stored_base - place) : 0ull;
    const int wraps = (stored_end > (~0ull - shift_up)) || (stored_end < shift_down);
    const unsigned long long end = wraps ? ~0ull : ((stored_end + shift_up) - shift_down);
    if (end > file->file_bytes)
    {
        return hdf5_error_number(file, "a truncated file; the superblock says it ends at byte", end);
    }
    file->base = place;
    file->root = root;
    return 1;
}

static Hdf5Walk hdf5_header_region(Hdf5File *file, const unsigned char *bytes, size_t length, unsigned int version,
                                   int ordered, Hdf5Continuation *chain, unsigned int *chained, Hdf5MessageVisit visit,
                                   void *state)
{
    const size_t head = (version == 1u) ? 8u : (ordered ? 6u : 4u);
    size_t at = 0u;
    while ((length - at) >= head)
    {
        Hdf5Cursor cursor = {&bytes[at], length - at, 0u, 0};
        const unsigned int type = (unsigned int)hdf5_take(&cursor, (version == 1u) ? 2u : 1u);
        const size_t size = (size_t)hdf5_take(&cursor, 2u);
        const unsigned int flags = (unsigned int)hdf5_take(&cursor, 1u);
        (void)hdf5_span(&cursor, head - cursor.at);
        const unsigned char *const body = hdf5_span(&cursor, size);
        if (body == NULL)
        {
            return hdf5_walk_error(file, "an object header message that runs past its block");
        }
        if (type == 0x10u)
        {
            Hdf5Cursor link = {body, size, 0u, 0};
            const unsigned long long address = hdf5_take(&link, file->offset_bytes);
            const unsigned long long extent = hdf5_take(&link, file->length_bytes);
            if (link.broken || (*chained >= HDF5_CONTINUATIONS))
            {
                return hdf5_walk_error(file, "an object header continuation that is malformed or one of too many");
            }
            chain[*chained].address = address;
            chain[*chained].length = extent;
            *chained += 1u;
        }
        else
        {
            const Hdf5Walk step = visit(file, state, type, flags, body, size);
            if (step != HDF5_WALK_ON)
            {
                return step;
            }
        }
        at += head + size;
    }
    return HDF5_WALK_ON;
}

Hdf5Walk hdf5_header_walk(Hdf5File *file, unsigned long long address, Hdf5MessageVisit visit, void *state)
{
    unsigned char prefix[40u];
    const unsigned long long capacity = hdf5_bytes_remaining(file, address);
    const unsigned long long probe = (capacity < sizeof(prefix)) ? capacity : sizeof(prefix);
    if ((probe < 12ull) || !hdf5_fetch(file, address, probe, prefix))
    {
        return hdf5_walk_error(file, "an object header past the end of the file");
    }
    const int modern = (memcmp(prefix, "OHDR", 4u) == 0);
    const unsigned int flags = prefix[5u];
    const size_t times = (modern && ((flags & 0x20u) != 0u)) ? 16u : 0u;
    const size_t phases = (modern && ((flags & 0x10u) != 0u)) ? 4u : 0u;
    const unsigned int width = 1u << (flags & 3u);
    const size_t start = modern ? (6u + times + phases + width) : 16u;
    const int known =
        modern ? ((prefix[4u] == 2u) && ((flags & 0xC0u) == 0u)) : ((prefix[0u] == 1u) && (probe >= 16ull));
    if (!known || (start > probe))
    {
        return hdf5_walk_error(file, "an object header of an unknown version");
    }
    const unsigned long long chunk =
        modern ? hdf5_little(&prefix[6u + times + phases], width) : hdf5_little(&prefix[8u], 4u);
    const unsigned int version = modern ? 2u : 1u;
    const int ordered = modern && ((flags & 0x04u) != 0u);
    const unsigned long long total = start + chunk + (modern ? HDF5_SEAL_BYTES : 0u);
    if (chunk > capacity)
    {
        return hdf5_walk_error(file, "an object header larger than the file");
    }
    unsigned char *const first = hdf5_load(file, address, total);
    if (first == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    if (modern && !hdf5_sealed(first, (size_t)total))
    {
        free(first);
        return hdf5_walk_error(file, "an object header whose checksum does not match");
    }
    Hdf5Continuation chain[HDF5_CONTINUATIONS];
    unsigned int chained = 0u;
    Hdf5Walk step =
        hdf5_header_region(file, &first[start], (size_t)chunk, version, ordered, chain, &chained, visit, state);
    free(first);
    for (unsigned int next = 0u; (step == HDF5_WALK_ON) && (next < chained); next += 1u)
    {
        unsigned char *const block = hdf5_load(file, chain[next].address, chain[next].length);
        const size_t length = (size_t)chain[next].length;
        const int sound =
            (block != NULL) &&
            (!modern || ((length >= 8u) && (memcmp(block, "OCHK", 4u) == 0) && hdf5_sealed(block, length)));
        step = !sound
                   ? hdf5_walk_error(file, "an object header continuation whose signature or checksum does not match")
               : modern
                   ? hdf5_header_region(file, &block[4u], length - 8u, version, ordered, chain, &chained, visit, state)
                   : hdf5_header_region(file, block, length, version, ordered, chain, &chained, visit, state);
        free(block);
    }
    return step;
}

void hdf5_object_unsupported(Hdf5Object *object, const char *reason, unsigned long long number)
{
    if (object->unsupported[0u] == '\0')
    {
        (void)snprintf(object->unsupported, sizeof(object->unsupported), "%s %llu", reason, number);
    }
}

Hdf5Walk hdf5_object_space(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int version = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int rank = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int flags = (unsigned int)hdf5_take(cursor, 1u);
    object->has_space = 1;
    if ((version != 1u) && (version != 2u))
    {
        hdf5_object_unsupported(object, "dataspace message version", version);
        return HDF5_WALK_ON;
    }
    (void)hdf5_span(cursor, (version == 1u) ? 5u : 1u);
    object->rank = rank;
    if (rank > ENGINE_ARRAY_RANK)
    {
        hdf5_object_unsupported(object, "a dataspace of rank", rank);
        return HDF5_WALK_ON;
    }
    if ((flags & 2u) != 0u)
    {
        hdf5_object_unsupported(object, "a dataspace permutation index, flags", flags);
    }
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        object->extent[axis] = hdf5_take(cursor, file->length_bytes);
    }
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        object->maximum[axis] = ((flags & 1u) != 0u) ? hdf5_take(cursor, file->length_bytes) : object->extent[axis];
    }
    return cursor->broken ? hdf5_walk_error(file, "a malformed dataspace message") : HDF5_WALK_ON;
}

Hdf5Walk hdf5_object_type(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int head = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int bits = (unsigned int)hdf5_take(cursor, 3u);
    const unsigned long long size = hdf5_take(cursor, 4u);
    const unsigned int kind = head & 0x0Fu;
    const unsigned int version = head >> 4u;
    const unsigned int offset = (kind <= 1u) ? (unsigned int)hdf5_take(cursor, 2u) : 0u;
    const unsigned int precision = (kind <= 1u) ? (unsigned int)hdf5_take(cursor, 2u) : 0u;
    if (cursor->broken)
    {
        return hdf5_walk_error(file, "a malformed datatype message");
    }
    object->has_type = 1;
    const int sized = (size == 1ull) || (size == 2ull) || (size == 4ull) || (size == 8ull);
    const int packed = (offset == 0u) && ((unsigned long long)precision == (size * 8ull));
    const unsigned int order = (bits & 1u) | ((bits >> 5u) & 2u);
    if ((version < 1u) || (version > 5u))
    {
        hdf5_object_unsupported(object, "datatype message version", version);
    }
    else if ((kind != 0u) && (kind != 1u))
    {
        hdf5_object_unsupported(object, "datatype class", kind);
    }
    else if (!sized || ((kind == 1u) && (size == 1ull)))
    {
        hdf5_object_unsupported(object, "an element of byte size", size);
    }
    else if (!packed)
    {
        hdf5_object_unsupported(object, "an element with padding bits; precision", precision);
    }
    else if ((kind == 1u) && (order > 1u))
    {
        hdf5_object_unsupported(object, "a floating-point byte order (VAX or reserved), code", order);
    }
    object->element_bytes = (unsigned int)size;
    object->big_endian = (order & 1u) != 0u;
    object->element_kind =
        (kind == 1u) ? ENGINE_ELEMENT_FLOAT : (((bits & 8u) != 0u) ? ENGINE_ELEMENT_SIGNED : ENGINE_ELEMENT_UNSIGNED);
    return HDF5_WALK_ON;
}

Hdf5Walk hdf5_object_fill(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, int old)
{
    const unsigned int version = old ? 1u : (unsigned int)hdf5_take(cursor, 1u);
    int defined = 1;
    if (!old && ((version == 1u) || (version == 2u)))
    {
        (void)hdf5_take(cursor, 2u);
        const unsigned int stated = (unsigned int)hdf5_take(cursor, 1u);
        defined = (version == 1u) || (stated != 0u);
    }
    else if (!old && (version == 3u))
    {
        const unsigned int flags = (unsigned int)hdf5_take(cursor, 1u);
        defined = (flags & 0x20u) != 0u;
    }
    else if (!old)
    {
        hdf5_object_unsupported(object, "fill value message version", version);
        return HDF5_WALK_ON;
    }
    const unsigned long long size = defined ? hdf5_take(cursor, 4u) : 0ull;
    const unsigned char *const value = hdf5_span(cursor, size);
    if (cursor->broken || (value == NULL))
    {
        return hdf5_walk_error(file, "a malformed fill value message");
    }
    unsigned char *const kept = old ? object->old_fill : object->fill;
    memcpy(kept, value, (size_t)((size < 8ull) ? size : 8ull));
    object->has_fill = object->has_fill || !old;
    object->has_old_fill = object->has_old_fill || old;
    object->fill_bytes = old ? object->fill_bytes : size;
    object->old_fill_bytes = old ? size : object->old_fill_bytes;
    return HDF5_WALK_ON;
}

Hdf5Walk hdf5_object_chunking(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, unsigned int version)
{
    const int indexed = (version >= 4u);
    const unsigned int flags = indexed ? (unsigned int)hdf5_take(cursor, 1u) : 0u;
    const unsigned int dimensions = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int width = indexed ? (unsigned int)hdf5_take(cursor, 1u) : 4u;
    object->data_address = (version == 3u) ? hdf5_take(cursor, file->offset_bytes) : 0ull;
    if (cursor->broken || (dimensions < 2u) || (dimensions > (ENGINE_ARRAY_RANK + 1u)) || (width < 1u) || (width > 8u))
    {
        return hdf5_walk_error(file, "a chunked layout message of an impossible rank");
    }
    object->chunk_flags = flags;
    object->chunk_rank = dimensions;
    for (unsigned int axis = 0u; axis < dimensions; axis += 1u)
    {
        object->chunk[axis] = hdf5_take(cursor, width);
    }
    object->chunk_index = HDF5_INDEX_TREE;
    if (indexed)
    {
        const unsigned int index = (unsigned int)hdf5_take(cursor, 1u);
        if (index == 1u)
        {
            object->chunk_index = HDF5_INDEX_SINGLE;
            object->single_bytes = ((flags & 2u) != 0u) ? hdf5_take(cursor, file->length_bytes) : 0ull;
            object->single_mask = ((flags & 2u) != 0u) ? (unsigned int)hdf5_take(cursor, 4u) : 0u;
        }
        else if (index == 2u)
        {
            object->chunk_index = HDF5_INDEX_IMPLICIT;
        }
        else if (index == 3u)
        {
            object->chunk_index = HDF5_INDEX_FIXED;
            object->page_bits = (unsigned int)hdf5_take(cursor, 1u);
        }
        else
        {
            hdf5_object_unsupported(object,
                                    (index == 4u)   ? "the extensible array chunk index; index type"
                                    : (index == 5u) ? "the version 2 B-tree chunk index; index type"
                                                    : "an unknown chunk index type",
                                    index);
            return HDF5_WALK_ON;
        }
        object->data_address = hdf5_take(cursor, file->offset_bytes);
    }
    return cursor->broken ? hdf5_walk_error(file, "a malformed chunked layout message") : HDF5_WALK_ON;
}
