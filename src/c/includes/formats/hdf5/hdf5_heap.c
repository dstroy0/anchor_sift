// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// hdf5_heap.c: the fractal heap, version 2 B-trees and dense links
#include "hdf5_internal.h"

static int hdf5_heap_open(Hdf5File *file, unsigned long long address, Hdf5Heap *heap)
{
    memset(heap, 0, sizeof(*heap));
    heap->block = NULL;
    const unsigned int offset_bytes = file->offset_bytes;
    const unsigned int length_bytes = file->length_bytes;
    const unsigned long long total = 26ull + (12ull * length_bytes) + (3ull * offset_bytes);
    unsigned char *const header = hdf5_load(file, address, total);
    if (header == NULL)
    {
        return 0;
    }
    Hdf5Cursor cursor = {header, (size_t)total, 4u, 0};
    const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
    (void)hdf5_take(&cursor, 2u);
    const unsigned int filter_length = (unsigned int)hdf5_take(&cursor, 2u);
    heap->flags = (unsigned int)hdf5_take(&cursor, 1u);
    const unsigned long long managed_largest = hdf5_take(&cursor, 4u);
    (void)hdf5_take(&cursor, length_bytes);
    (void)hdf5_take(&cursor, offset_bytes);
    (void)hdf5_take(&cursor, length_bytes);
    (void)hdf5_take(&cursor, offset_bytes);
    for (unsigned int skipped = 0u; skipped < 8u; skipped += 1u)
    {
        (void)hdf5_take(&cursor, length_bytes);
    }
    heap->width = hdf5_take(&cursor, 2u);
    heap->start_block = hdf5_take(&cursor, length_bytes);
    heap->largest_direct = hdf5_take(&cursor, length_bytes);
    heap->heap_bits = (unsigned int)hdf5_take(&cursor, 2u);
    (void)hdf5_take(&cursor, 2u);
    heap->root = hdf5_take(&cursor, offset_bytes);
    heap->root_rows = (unsigned int)hdf5_take(&cursor, 2u);
    const int signed_right = (memcmp(header, "FRHP", 4u) == 0) && (version == 0u);
    const int sealed = (filter_length == 0u) && hdf5_sealed(header, (size_t)total);
    free(header);
    if (filter_length != 0u)
    {
        return hdf5_error(file, "a filtered fractal heap for dense links");
    }
    if (cursor.broken || !signed_right || !sealed)
    {
        return hdf5_error(file, "a fractal heap header whose signature or checksum does not match");
    }
    const int shaped = hdf5_power_of_two(heap->width) && hdf5_power_of_two(heap->start_block) &&
                       hdf5_power_of_two(heap->largest_direct) && (heap->largest_direct >= heap->start_block) &&
                       (heap->largest_direct <= HDF5_LARGEST_DIRECT_BLOCK) && (heap->heap_bits >= 1u) &&
                       (heap->heap_bits <= 64u) && (managed_largest > 0ull);
    if (!shaped)
    {
        return hdf5_error(file, "a fractal heap with an impossible doubling table");
    }
    heap->header = address;
    heap->start_bits = hdf5_log2(heap->start_block);
    heap->first_row_bits = heap->start_bits + hdf5_log2(heap->width);
    heap->direct_rows = (hdf5_log2(heap->largest_direct) - heap->start_bits) + 2u;
    heap->position_bytes = (heap->heap_bits + 7u) / 8u;
    const unsigned int direct_offset_bytes = (hdf5_log2(heap->largest_direct) + 7u) / 8u;
    const unsigned int managed_bytes = (hdf5_log2(managed_largest) / 8u) + 1u;
    heap->size_bytes = (direct_offset_bytes < managed_bytes) ? direct_offset_bytes : managed_bytes;
    if ((heap->first_row_bits >= 63u) || (heap->root_rows > (64u - heap->start_bits)))
    {
        return hdf5_error(file, "a fractal heap with an impossible doubling table");
    }
    return 1;
}

static unsigned long long hdf5_heap_row_block(const Hdf5Heap *heap, unsigned int row)
{
    return (row == 0u) ? heap->start_block : (heap->start_block << (row - 1u));
}

static unsigned long long hdf5_heap_row_start(const Hdf5Heap *heap, unsigned int row)
{
    return (row == 0u) ? 0ull : ((heap->width * heap->start_block) << (row - 1u));
}

static int hdf5_heap_locate(Hdf5File *file, const Hdf5Heap *heap, unsigned long long offset, unsigned long long *block,
                            unsigned long long *block_bytes, unsigned long long *block_offset)
{
    if (heap->root_rows == 0u)
    {
        *block = heap->root;
        *block_bytes = heap->start_block;
        *block_offset = 0ull;
        return (offset < heap->start_block) ? 1 : hdf5_error(file, "a fractal heap object past its root block");
    }
    unsigned long long indirect = heap->root;
    unsigned int rows = heap->root_rows;
    unsigned long long base_offset = 0ull;
    const size_t head = 5u + (size_t)file->offset_bytes + heap->position_bytes;
    for (unsigned int descent = 0u; descent < HDF5_HEAP_DESCENT; descent += 1u)
    {
        const unsigned long long relative = offset - base_offset;
        const int first_row = (relative < (heap->width * heap->start_block));
        const unsigned int high = hdf5_log2(relative);
        const unsigned int row = first_row ? 0u : ((high - heap->first_row_bits) + 1u);
        if ((row >= rows) || (row >= (64u - heap->start_bits)))
        {
            return hdf5_error(file, "a fractal heap object outside its indirect block");
        }
        const unsigned long long column =
            first_row ? (relative / heap->start_block) : ((relative - (1ull << high)) / hdf5_heap_row_block(heap, row));
        const unsigned int direct = (rows < heap->direct_rows) ? rows : heap->direct_rows;
        const unsigned long long entries = (unsigned long long)rows * heap->width;
        const unsigned long long bytes = head + (entries * file->offset_bytes) + HDF5_SEAL_BYTES;
        unsigned char *const node = hdf5_load(file, indirect, bytes);
        if (node == NULL)
        {
            return 0;
        }
        const int sound = (memcmp(node, "FHIB", 4u) == 0) && (node[4u] == 0u) && hdf5_sealed(node, (size_t)bytes) &&
                          (hdf5_little(&node[5u], file->offset_bytes) == heap->header) &&
                          (hdf5_little(&node[5u + file->offset_bytes], heap->position_bytes) == base_offset);
        const unsigned long long entry = ((unsigned long long)row * heap->width) + column;
        const unsigned long long child =
            sound ? hdf5_little(&node[head + (size_t)(entry * file->offset_bytes)], file->offset_bytes) : 0ull;
        free(node);
        if (!sound || hdf5_undefined(file, child))
        {
            return hdf5_error(file, "a fractal heap indirect block whose signature, checksum or entry is wrong");
        }
        const unsigned long long child_offset =
            base_offset + hdf5_heap_row_start(heap, row) + (column * hdf5_heap_row_block(heap, row));
        if (row < direct)
        {
            *block = child;
            *block_bytes = hdf5_heap_row_block(heap, row);
            *block_offset = child_offset;
            return 1;
        }
        indirect = child;
        rows = (hdf5_log2(hdf5_heap_row_block(heap, row)) - heap->first_row_bits) + 1u;
        base_offset = child_offset;
    }
    return hdf5_error(file, "a fractal heap nested deeper than any real file");
}

static int hdf5_heap_block(Hdf5File *file, Hdf5Heap *heap, unsigned long long address, unsigned long long bytes,
                           unsigned long long block_offset)
{
    if ((heap->block != NULL) && (heap->block_address == address))
    {
        return 1;
    }
    free(heap->block);
    heap->block = NULL;
    unsigned char *const block = hdf5_load(file, address, bytes);
    if (block == NULL)
    {
        return 0;
    }
    const size_t head = 5u + (size_t)file->offset_bytes + heap->position_bytes;
    const int summed = (heap->flags & 2u) != 0u;
    const size_t prefix = head + (summed ? HDF5_SEAL_BYTES : 0u);
    int sound = (bytes > prefix) && (memcmp(block, "FHDB", 4u) == 0) && (block[4u] == 0u) &&
                (hdf5_little(&block[5u], file->offset_bytes) == heap->header) &&
                (hdf5_little(&block[5u + file->offset_bytes], heap->position_bytes) == block_offset);
    if (sound && summed)
    {
        const uint32_t stored = (uint32_t)hdf5_little(&block[head], 4u);
        memset(&block[head], 0, HDF5_SEAL_BYTES);
        sound = (stored == hdf5_lookup3(block, (size_t)bytes));
    }
    if (!sound)
    {
        free(block);
        return hdf5_error(file, "a fractal heap direct block whose signature, offset or checksum does not match");
    }
    heap->block = block;
    heap->block_address = address;
    heap->block_bytes = bytes;
    heap->block_prefix = prefix;
    return 1;
}

static int hdf5_heap_object(Hdf5File *file, Hdf5Heap *heap, const unsigned char *identifier, size_t identifier_bytes,
                            const unsigned char **object, size_t *object_bytes)
{
    if (identifier_bytes == 0u)
    {
        return hdf5_error(file, "an empty fractal heap identifier");
    }
    const unsigned int flags = identifier[0u];
    const unsigned int kind = (flags >> 4u) & 3u;
    if ((flags >> 6u) != 0u)
    {
        return hdf5_error(file, "a fractal heap identifier of an unknown version");
    }
    if (kind == 1u)
    {
        return hdf5_error(file, "a huge object in a fractal heap");
    }
    if (kind == 2u)
    {
        const int extended = (identifier_bytes > 18u);
        const size_t head = extended ? 2u : 1u;
        const size_t length =
            extended ? ((((size_t)(flags & 0x0Fu)) << 8u) | identifier[1u]) + 1u : ((size_t)(flags & 0x0Fu) + 1u);
        if (identifier_bytes < (head + length))
        {
            return hdf5_error(file, "a tiny fractal heap object longer than its identifier");
        }
        *object = &identifier[head];
        *object_bytes = length;
        return 1;
    }
    if ((kind != 0u) || (identifier_bytes < (1u + (size_t)heap->position_bytes + heap->size_bytes)))
    {
        return hdf5_error(file, "a malformed fractal heap identifier");
    }
    const unsigned long long offset = hdf5_little(&identifier[1u], heap->position_bytes);
    const unsigned long long length = hdf5_little(&identifier[1u + heap->position_bytes], heap->size_bytes);
    unsigned long long block = 0ull;
    unsigned long long block_bytes = 0ull;
    unsigned long long block_offset = 0ull;
    if (!hdf5_heap_locate(file, heap, offset, &block, &block_bytes, &block_offset) ||
        !hdf5_heap_block(file, heap, block, block_bytes, block_offset))
    {
        return 0;
    }
    const unsigned long long within = offset - block_offset;
    if ((offset < block_offset) || (within < heap->block_prefix) || (length == 0ull) || (within > block_bytes) ||
        (length > (block_bytes - within)))
    {
        return hdf5_error(file, "a fractal heap object outside its direct block");
    }
    *object = &heap->block[within];
    *object_bytes = (size_t)length;
    return 1;
}

static int hdf5_tree2_ordered(Hdf5Tree2 *tree, const unsigned char *record)
{
    const uint32_t hash = (uint32_t)hdf5_little(record, 4u);
    if (tree->ordered_any && (hash < tree->last_hash))
    {
        return 0;
    }
    tree->run_count = (!tree->ordered_any || (hash > tree->last_hash)) ? 0u : tree->run_count;
    tree->ordered_any = 1;
    tree->last_hash = hash;
    for (unsigned int place = 0u; place < tree->run_count; place += 1u)
    {
        if (memcmp(tree->run[place], record, tree->record_bytes) == 0)
        {
            return 0;
        }
    }
    if (tree->run_count == HDF5_RUN_RECORDS)
    {
        return 0;
    }
    memcpy(tree->run[tree->run_count], record, tree->record_bytes);
    tree->run_count += 1u;
    return 1;
}

static Hdf5Walk hdf5_tree2_node(Hdf5File *file, Hdf5Tree2 *tree, unsigned long long address, unsigned long long records,
                                unsigned int level, int root)
{
    if ((records > tree->maximum[level]) || (!root && (records == 0ull)))
    {
        return hdf5_walk_error(file,
                                "a version 2 B-tree node with more records than it can hold, or none below the root");
    }
    const size_t pointer =
        (level == 0u)
            ? 0u
            : ((size_t)file->offset_bytes + tree->count_bytes + ((level > 1u) ? tree->total_bytes[level - 1u] : 0u));
    const size_t records_bytes = (size_t)records * tree->record_bytes;
    const size_t bytes =
        6u + records_bytes + ((level == 0u) ? 0u : ((size_t)(records + 1ull) * pointer)) + HDF5_SEAL_BYTES;
    if (bytes > tree->node_bytes)
    {
        return hdf5_walk_error(file, "a version 2 B-tree node larger than its node size");
    }
    unsigned char *const node = hdf5_load(file, address, bytes);
    if (node == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    const int sound = (memcmp(node, (level == 0u) ? "BTLF" : "BTIN", 4u) == 0) && (node[4u] == 0u) &&
                      (node[5u] == tree->type) && hdf5_sealed(node, bytes);
    Hdf5Walk step = sound
                        ? HDF5_WALK_ON
                        : hdf5_walk_error(file, "a version 2 B-tree node whose signature or checksum does not match");
    for (unsigned long long place = 0ull; (step == HDF5_WALK_ON) && (place <= records); place += 1ull)
    {
        const unsigned char *const record = &node[6u + ((size_t)place * tree->record_bytes)];
        const unsigned char *const before =
            (place > 0ull) ? &node[6u + ((size_t)(place - 1ull) * tree->record_bytes)] : record;
        const int after_low = !tree->hashed || (place == 0ull) || ((uint32_t)hdf5_little(before, 4u) <= tree->hash);
        const int before_high =
            !tree->hashed || (place == records) || ((uint32_t)hdf5_little(record, 4u) >= tree->hash);
        if ((level > 0u) && after_low && before_high)
        {
            const unsigned char *const entry = &node[6u + records_bytes + ((size_t)place * pointer)];
            const unsigned long long child = hdf5_little(entry, file->offset_bytes);
            const unsigned long long child_records = hdf5_little(&entry[file->offset_bytes], tree->count_bytes);
            step = hdf5_tree2_node(file, tree, child, child_records, level - 1u, 0);
        }
        const int matches = !tree->hashed || ((place < records) && ((uint32_t)hdf5_little(record, 4u) == tree->hash));
        if ((step == HDF5_WALK_ON) && (place < records) && matches)
        {
            step = hdf5_tree2_ordered(tree, record)
                       ? tree->visit(file, tree->state, record, tree->record_bytes)
                       : hdf5_walk_error(file, "version 2 B-tree records that repeat or run out of order");
        }
    }
    free(node);
    return step;
}

static Hdf5Walk hdf5_tree2_walk(Hdf5File *file, unsigned long long address, unsigned int type, Hdf5RecordVisit visit,
                                void *state, int hashed, uint32_t hash)
{
    if (hdf5_undefined(file, address))
    {
        return HDF5_WALK_ON;
    }
    Hdf5Tree2 tree;
    memset(&tree, 0, sizeof(tree));
    tree.type = type;
    tree.visit = visit;
    tree.state = state;
    tree.hashed = hashed;
    tree.hash = hash;
    const unsigned long long total = 22ull + file->offset_bytes + file->length_bytes;
    unsigned char *const header = hdf5_load(file, address, total);
    if (header == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    Hdf5Cursor cursor = {header, (size_t)total, 4u, 0};
    const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
    const unsigned int stated_type = (unsigned int)hdf5_take(&cursor, 1u);
    tree.node_bytes = (unsigned int)hdf5_take(&cursor, 4u);
    tree.record_bytes = (unsigned int)hdf5_take(&cursor, 2u);
    tree.depth = (unsigned int)hdf5_take(&cursor, 2u);
    (void)hdf5_take(&cursor, 2u);
    const unsigned long long root = hdf5_take(&cursor, file->offset_bytes);
    const unsigned long long root_records = hdf5_take(&cursor, 2u);
    const int sound = !cursor.broken && (memcmp(header, "BTHD", 4u) == 0) && (version == 0u) && (stated_type == type) &&
                      hdf5_sealed(header, (size_t)total);
    free(header);
    if (!sound)
    {
        return hdf5_walk_error(file, "a version 2 B-tree header whose signature, type or checksum does not match");
    }
    if ((tree.depth > HDF5_TREE2_LEVELS) || (tree.record_bytes < 4u) || (tree.record_bytes > HDF5_RECORD_CAPACITY) ||
        (tree.node_bytes <= (10u + tree.record_bytes)))
    {
        return hdf5_walk_error(file, "a version 2 B-tree of an impossible shape");
    }
    tree.maximum[0u] = (tree.node_bytes - 10u) / tree.record_bytes;
    tree.count_bytes = (hdf5_log2(tree.maximum[0u]) / 8u) + 1u;
    unsigned long long cumulative = tree.maximum[0u];
    for (unsigned int level = 1u; level <= tree.depth; level += 1u)
    {
        const unsigned int pointer =
            file->offset_bytes + tree.count_bytes + ((level > 1u) ? tree.total_bytes[level - 1u] : 0u);
        tree.maximum[level] = (tree.node_bytes - 10u) / (tree.record_bytes + pointer);
        const unsigned long long fanout = tree.maximum[level] + 1ull;
        if ((tree.maximum[level] == 0ull) || (cumulative > ((~0ull - tree.maximum[level]) / fanout)))
        {
            return hdf5_walk_error(file, "a version 2 B-tree of an impossible shape");
        }
        cumulative = (fanout * cumulative) + tree.maximum[level];
        tree.total_bytes[level] = (hdf5_log2(cumulative) / 8u) + 1u;
    }
    return hdf5_undefined(file, root) ? HDF5_WALK_ON : hdf5_tree2_node(file, &tree, root, root_records, tree.depth, 1);
}

static Hdf5Walk hdf5_dense_record(Hdf5File *file, void *state, const unsigned char *record, size_t record_bytes)
{
    Hdf5DenseWalk *const dense = (Hdf5DenseWalk *)state;
    if (record_bytes <= 4u)
    {
        return hdf5_walk_error(file, "a link name record too short to hold a heap identifier");
    }
    const unsigned char *object = NULL;
    size_t object_bytes = 0u;
    if (!hdf5_heap_object(file, dense->heap, &record[4u], record_bytes - 4u, &object, &object_bytes))
    {
        return HDF5_WALK_FAILED;
    }
    return hdf5_link_decode(file, object, object_bytes, dense->walk->visit, dense->walk->state);
}

Hdf5Walk hdf5_dense_links(Hdf5File *file, const Hdf5GroupWalk *walk)
{
    Hdf5Heap heap;
    if (!hdf5_heap_open(file, walk->dense_heap, &heap))
    {
        return HDF5_WALK_FAILED;
    }
    Hdf5DenseWalk dense = {walk, &heap};
    const Hdf5Walk step =
        hdf5_tree2_walk(file, walk->dense_names, 5u, hdf5_dense_record, &dense, walk->hashed, walk->hash);
    free(heap.block);
    return step;
}
