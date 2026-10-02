// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_object.c: layout, pipeline, links and symbol tables
#include "hdf5_internal.h"

static Hdf5Walk hdf5_object_layout(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int version = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int kind = (unsigned int)hdf5_take(cursor, 1u);
    if (cursor->broken || object->has_layout)
    {
        return hdf5_walk_error(file, "a malformed or repeated data layout message");
    }
    object->has_layout = 1;
    object->layout_version = version;
    object->layout_class = kind;
    if ((version < 3u) || (version > 5u))
    {
        hdf5_object_unsupported(object, "data layout message version", version);
        return HDF5_WALK_ON;
    }
    if (kind == 0u)
    {
        const unsigned long long size = hdf5_take(cursor, 2u);
        const unsigned char *const data = hdf5_span(cursor, size);
        if (cursor->broken || (data == NULL))
        {
            return hdf5_walk_error(file, "a malformed compact layout message");
        }
        object->data_bytes = size;
        object->compact = (size > 0ull) ? (unsigned char *)malloc((size_t)size) : NULL;
        if ((size > 0ull) && (object->compact == NULL))
        {
            return hdf5_walk_error(file, "no memory for compact data");
        }
        if (size > 0ull)
        {
            memcpy(object->compact, data, (size_t)size);
        }
        return HDF5_WALK_ON;
    }
    if (kind == 1u)
    {
        object->data_address = hdf5_take(cursor, file->offset_bytes);
        object->data_bytes = hdf5_take(cursor, file->length_bytes);
        return cursor->broken ? hdf5_walk_error(file, "a malformed contiguous layout message") : HDF5_WALK_ON;
    }
    if (kind == 2u)
    {
        return hdf5_object_chunking(file, object, cursor, version);
    }
    hdf5_object_unsupported(object, (kind == 3u) ? "the virtual dataset layout; class" : "an unknown layout class",
                            kind);
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_pipeline(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int version = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int count = (unsigned int)hdf5_take(cursor, 1u);
    if (cursor->broken || object->has_pipeline || (count > HDF5_FILTERS))
    {
        return hdf5_walk_error(file, "a malformed or repeated filter pipeline message");
    }
    object->has_pipeline = 1;
    if ((version != 1u) && (version != 2u))
    {
        hdf5_object_unsupported(object, "filter pipeline message version", version);
        return HDF5_WALK_ON;
    }
    (void)hdf5_span(cursor, (version == 1u) ? 6u : 0u);
    object->filter_count = count;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        Hdf5Filter *const filter = &object->filters[place];
        filter->identifier = (unsigned int)hdf5_take(cursor, 2u);
        const unsigned long long name_length =
            ((version == 1u) || (filter->identifier >= 256u)) ? hdf5_take(cursor, 2u) : 0ull;
        filter->flags = (unsigned int)hdf5_take(cursor, 2u);
        const unsigned int values = (unsigned int)hdf5_take(cursor, 2u);
        (void)hdf5_span(cursor, (version == 1u) ? ((name_length + 7ull) & ~7ull) : name_length);
        filter->value_count = values;
        for (unsigned int value = 0u; value < values; value += 1u)
        {
            const unsigned int taken = (unsigned int)hdf5_take(cursor, 4u);
            if (value < HDF5_FILTER_VALUES)
            {
                filter->values[value] = taken;
            }
        }
        (void)hdf5_span(cursor, ((version == 1u) && ((values % 2u) != 0u)) ? 4u : 0u);
    }
    return cursor->broken ? hdf5_walk_error(file, "a malformed filter pipeline message") : HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_message(Hdf5File *file, void *state, unsigned int type, unsigned int flags,
                                    const unsigned char *body, size_t size)
{
    Hdf5Object *const object = (Hdf5Object *)state;
    Hdf5Cursor cursor = {body, size, 0u, 0};
    const int data_message =
        (type == 0x01u) || (type == 0x03u) || (type == 0x04u) || (type == 0x05u) || (type == 0x08u) || (type == 0x0Bu);
    if (data_message && ((flags & 0x02u) != 0u))
    {
        hdf5_object_unsupported(object, "a shared (committed) object header message of type", type);
        object->has_type = object->has_type || (type == 0x03u);
        object->has_space = object->has_space || (type == 0x01u);
        object->has_layout = object->has_layout || (type == 0x08u);
        return HDF5_WALK_ON;
    }
    if ((type == 0x01u) && object->has_space)
    {
        return hdf5_walk_error(file, "a repeated dataspace message");
    }
    if ((type == 0x03u) && object->has_type)
    {
        return hdf5_walk_error(file, "a repeated datatype message");
    }
    if (type == 0x01u)
    {
        return hdf5_object_space(file, object, &cursor);
    }
    if (type == 0x03u)
    {
        return hdf5_object_type(file, object, &cursor);
    }
    if ((type == 0x04u) || (type == 0x05u))
    {
        return hdf5_object_fill(file, object, &cursor, type == 0x04u);
    }
    if (type == 0x08u)
    {
        return hdf5_object_layout(file, object, &cursor);
    }
    if (type == 0x0Bu)
    {
        return hdf5_object_pipeline(file, object, &cursor);
    }
    object->external = object->external || (type == 0x07u);
    object->group = object->group || (type == 0x02u) || (type == 0x06u) || (type == 0x11u);
    if ((type > 0x18u) && ((flags & 0x80u) != 0u))
    {
        hdf5_object_unsupported(object, "an unknown object header message marked must-understand, type", type);
    }
    return HDF5_WALK_ON;
}

void hdf5_object_close(Hdf5Object *object)
{
    free(object->compact);
    object->compact = NULL;
}

int hdf5_object_open(Hdf5File *file, unsigned long long address, Hdf5Object *object)
{
    memset(object, 0, sizeof(*object));
    object->compact = NULL;
    if (hdf5_header_walk(file, address, hdf5_object_message, object) == HDF5_WALK_FAILED)
    {
        hdf5_object_close(object);
        return 0;
    }
    return 1;
}

Hdf5Walk hdf5_link_decode(Hdf5File *file, const unsigned char *body, size_t size, Hdf5LinkVisit visit, void *state)
{
    Hdf5Cursor cursor = {body, size, 0u, 0};
    const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
    const unsigned int flags = (unsigned int)hdf5_take(&cursor, 1u);
    if (cursor.broken || (version != 1u) || ((flags & 0xE0u) != 0u))
    {
        return hdf5_walk_error(file, "a link message of an unknown version");
    }
    const unsigned int link_type = ((flags & 0x08u) != 0u) ? (unsigned int)hdf5_take(&cursor, 1u) : 0u;
    (void)hdf5_span(&cursor, ((flags & 0x04u) != 0u) ? 8u : 0u);
    (void)hdf5_span(&cursor, ((flags & 0x10u) != 0u) ? 1u : 0u);
    const unsigned long long name_length = hdf5_take(&cursor, 1u << (flags & 3u));
    const unsigned char *const name = hdf5_span(&cursor, name_length);
    const unsigned long long address = (link_type == 0u) ? hdf5_take(&cursor, file->offset_bytes) : 0ull;
    if (cursor.broken || (name == NULL) || (name_length == 0ull))
    {
        return hdf5_walk_error(file, "a malformed link message");
    }
    return visit(file, state, name, (size_t)name_length, link_type, address);
}

Hdf5Walk hdf5_group_message(Hdf5File *file, void *state, unsigned int type, unsigned int flags,
                            const unsigned char *body, size_t size)
{
    Hdf5GroupWalk *const walk = (Hdf5GroupWalk *)state;
    Hdf5Cursor cursor = {body, size, 0u, 0};
    (void)flags;
    if (type == 0x06u)
    {
        return hdf5_link_decode(file, body, size, walk->visit, walk->state);
    }
    if (type == 0x11u)
    {
        walk->table_tree = hdf5_take(&cursor, file->offset_bytes);
        walk->table_heap = hdf5_take(&cursor, file->offset_bytes);
        walk->table = 1;
        return cursor.broken ? hdf5_walk_error(file, "a malformed symbol table message") : HDF5_WALK_ON;
    }
    if (type == 0x02u)
    {
        const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
        const unsigned int link_flags = (unsigned int)hdf5_take(&cursor, 1u);
        (void)hdf5_span(&cursor, ((link_flags & 1u) != 0u) ? 8u : 0u);
        walk->dense_heap = hdf5_take(&cursor, file->offset_bytes);
        walk->dense_names = hdf5_take(&cursor, file->offset_bytes);
        walk->dense = 1;
        return (cursor.broken || (version != 0u)) ? hdf5_walk_error(file, "a malformed link info message")
                                                  : HDF5_WALK_ON;
    }
    return HDF5_WALK_ON;
}

static int hdf5_name_after(const unsigned char *name, size_t length, const unsigned char *last, size_t last_length)
{
    const size_t shared = (length < last_length) ? length : last_length;
    const int order = memcmp(name, last, shared);
    return (order > 0) || ((order == 0) && (length > last_length));
}

static Hdf5Walk hdf5_table_symbols(Hdf5File *file, Hdf5GroupWalk *walk, const unsigned char *names, size_t names_length,
                                   unsigned long long address)
{
    unsigned char head[8u];
    if (!hdf5_fetch(file, address, sizeof(head), head))
    {
        return HDF5_WALK_FAILED;
    }
    if ((memcmp(head, "SNOD", 4u) != 0) || (head[4u] != 1u))
    {
        return hdf5_walk_error(file, "a symbol table node whose signature does not match");
    }
    const size_t count = (size_t)hdf5_little(&head[6u], 2u);
    if (count == 0u)
    {
        return hdf5_walk_error(file, "an empty symbol table node");
    }
    const size_t entry_bytes = (2u * (size_t)file->offset_bytes) + 24u;
    unsigned char *const node = hdf5_load(file, address, sizeof(head) + (count * entry_bytes));
    if (node == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    Hdf5Walk step = HDF5_WALK_ON;
    for (size_t entry = 0u; (step == HDF5_WALK_ON) && (entry < count); entry += 1u)
    {
        const unsigned char *const symbol = &node[sizeof(head) + (entry * entry_bytes)];
        const unsigned long long name_offset = hdf5_little(symbol, file->offset_bytes);
        const unsigned long long object = hdf5_little(&symbol[file->offset_bytes], file->offset_bytes);
        const unsigned long long cache = hdf5_little(&symbol[2u * file->offset_bytes], 4u);
        const unsigned char *const name = (name_offset < names_length) ? &names[name_offset] : NULL;
        const unsigned char *const end =
            (name != NULL) ? (const unsigned char *)memchr(name, 0, names_length - (size_t)name_offset) : NULL;
        const size_t length = (end != NULL) ? (size_t)(end - name) : 0u;
        const int ordered = (end != NULL) && ((walk->last_name == NULL) ||
                                              hdf5_name_after(name, length, walk->last_name, walk->last_length));
        walk->last_name = ordered ? name : walk->last_name;
        walk->last_length = ordered ? length : walk->last_length;
        step = !ordered ? hdf5_walk_error(file, "a symbol whose name lies outside the local heap or out of order")
                        : walk->visit(file, walk->state, name, length, (cache == 2ull) ? 1u : 0u, object);
    }
    free(node);
    return step;
}

static Hdf5Walk hdf5_table_node(Hdf5File *file, Hdf5GroupWalk *walk, const unsigned char *names, size_t names_length,
                                unsigned long long address, unsigned int level, int root, unsigned int depth)
{
    const size_t pointer_bytes = file->offset_bytes;
    const size_t key_bytes = file->length_bytes;
    const size_t head = 8u + (2u * pointer_bytes);
    unsigned char prefix[24u];
    if (depth > HDF5_TREE_LEVELS)
    {
        return hdf5_walk_error(file, "a group B-tree deeper than any real file");
    }
    if (!hdf5_fetch(file, address, head, prefix))
    {
        return HDF5_WALK_FAILED;
    }
    const unsigned int node_level = prefix[5u];
    const size_t entries = (size_t)hdf5_little(&prefix[6u], 2u);
    if ((memcmp(prefix, "TREE", 4u) != 0) || (prefix[4u] != 0u) || (!root && (node_level != level)))
    {
        return hdf5_walk_error(file, "a group B-tree node whose signature, type or level is wrong");
    }
    if (entries == 0u)
    {
        return root ? HDF5_WALK_ON : hdf5_walk_error(file, "an empty group B-tree node below the root");
    }
    unsigned char *const node = hdf5_load(file, address, head + (entries * (key_bytes + pointer_bytes)) + key_bytes);
    if (node == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    Hdf5Walk step = HDF5_WALK_ON;
    for (size_t child = 0u; (step == HDF5_WALK_ON) && (child < entries); child += 1u)
    {
        const unsigned char *const left_key = &node[head + (child * (key_bytes + pointer_bytes))];
        const unsigned long long child_address = hdf5_little(&left_key[key_bytes], file->offset_bytes);
        const unsigned long long left = hdf5_little(left_key, file->length_bytes);
        const unsigned long long right = hdf5_little(&left_key[key_bytes + pointer_bytes], file->length_bytes);
        const unsigned char *const left_end =
            (left < names_length) ? (const unsigned char *)memchr(&names[left], 0, names_length - (size_t)left) : NULL;
        const unsigned char *const right_end =
            (right < names_length) ? (const unsigned char *)memchr(&names[right], 0, names_length - (size_t)right)
                                   : NULL;
        const int keyed = (left_end != NULL) && (right_end != NULL);
        const int wanted =
            (walk->target == NULL) ||
            (keyed &&
             hdf5_name_after(walk->target, walk->target_length, &names[left], (size_t)(left_end - &names[left])) &&
             !hdf5_name_after(walk->target, walk->target_length, &names[right], (size_t)(right_end - &names[right])));
        step = ((walk->target != NULL) && !keyed) ? hdf5_walk_error(file, "a group B-tree key outside the local heap")
               : !wanted                          ? HDF5_WALK_ON
               : (node_level > 0u)
                   ? hdf5_table_node(file, walk, names, names_length, child_address, node_level - 1u, 0, depth + 1u)
                   : hdf5_table_symbols(file, walk, names, names_length, child_address);
    }
    free(node);
    return step;
}

Hdf5Walk hdf5_table_links(Hdf5File *file, Hdf5GroupWalk *walk)
{
    const size_t head = 8u + (2u * (size_t)file->length_bytes) + file->offset_bytes;
    unsigned char prefix[32u];
    if (!hdf5_fetch(file, walk->table_heap, head, prefix))
    {
        return HDF5_WALK_FAILED;
    }
    if ((memcmp(prefix, "HEAP", 4u) != 0) || (prefix[4u] != 0u))
    {
        return hdf5_walk_error(file, "a local heap whose signature does not match");
    }
    const unsigned long long names_bytes = hdf5_little(&prefix[8u], file->length_bytes);
    const unsigned long long names_address = hdf5_little(&prefix[8u + (2u * file->length_bytes)], file->offset_bytes);
    unsigned char *const names = hdf5_load(file, names_address, names_bytes);
    if (names == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    const Hdf5Walk step = hdf5_table_node(file, walk, names, (size_t)names_bytes, walk->table_tree, 0u, 1, 0u);
    free(names);
    return step;
}
