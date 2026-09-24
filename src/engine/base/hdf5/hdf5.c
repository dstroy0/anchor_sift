// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "hdf5.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HDF5_REASON_ROOM 256u
#define HDF5_PATH_ROOM ENGINE_PATH_ROOM
#define HDF5_FILTERS 32u
#define HDF5_FILTER_VALUES 8u
#define HDF5_CONTINUATIONS 64u
#define HDF5_TREE_LEVELS 64u
#define HDF5_TREE2_LEVELS 16u
#define HDF5_GROUP_DEPTH 32u
#define HDF5_HEAP_DESCENT 64u
#define HDF5_BUDGET 16777216ull
#define HDF5_OBJECTS 65536u
#define HDF5_SEAL_BYTES 4u
#define HDF5_LARGEST_DIRECT_BLOCK 1073741824ull
#define HDF5_LARGEST_CHUNK 4294967296ull
#define HDF5_RUN_RECORDS 16u
#define HDF5_RECORD_ROOM 64u

typedef enum
{
    HDF5_WALK_FAILED = -1,
    HDF5_WALK_ON = 0,
    HDF5_WALK_STOPPED = 1
} Hdf5Walk;

typedef enum
{
    HDF5_INDEX_TREE = 0,
    HDF5_INDEX_SINGLE = 1,
    HDF5_INDEX_IMPLICIT = 2,
    HDF5_INDEX_FIXED = 3
} Hdf5ChunkIndex;

typedef struct
{
    const char *path;
    const EngineIngestTools *tools;
    unsigned long long file_bytes;
    unsigned long long base;
    unsigned int offset_bytes;
    unsigned int length_bytes;
    unsigned long long root;
    unsigned long long budget;
    char reason[HDF5_REASON_ROOM];
} Hdf5File;

typedef struct
{
    const unsigned char *bytes;
    size_t length;
    size_t at;
    int broken;
} Hdf5Cursor;

typedef struct
{
    unsigned int identifier;
    unsigned int flags;
    unsigned int value_count;
    unsigned int values[HDF5_FILTER_VALUES];
} Hdf5Filter;

typedef struct
{
    int has_space;
    int has_type;
    int has_layout;
    int has_fill;
    int has_old_fill;
    int has_pipeline;
    int group;
    int external;
    char unsupported[HDF5_REASON_ROOM];
    unsigned int rank;
    unsigned long long extent[ENGINE_ARRAY_RANK];
    unsigned long long maximum[ENGINE_ARRAY_RANK];
    unsigned int element_bytes;
    EngineElementKind element_kind;
    int big_endian;
    unsigned long long fill_bytes;
    unsigned char fill[8u];
    unsigned long long old_fill_bytes;
    unsigned char old_fill[8u];
    unsigned int layout_version;
    unsigned int layout_class;
    unsigned long long data_address;
    unsigned long long data_bytes;
    unsigned char *compact;
    unsigned int chunk_rank;
    unsigned long long chunk[ENGINE_ARRAY_RANK + 1u];
    unsigned int chunk_flags;
    Hdf5ChunkIndex chunk_index;
    unsigned long long single_bytes;
    unsigned int single_mask;
    unsigned int page_bits;
    unsigned int filter_count;
    Hdf5Filter filters[HDF5_FILTERS];
} Hdf5Object;

typedef Hdf5Walk (*Hdf5MessageVisit)(Hdf5File *file, void *state, unsigned int type, unsigned int flags, const unsigned char *body, size_t size);

typedef Hdf5Walk (*Hdf5LinkVisit)(Hdf5File *file, void *state, const unsigned char *name, size_t name_length, unsigned int link_type, unsigned long long address);

typedef Hdf5Walk (*Hdf5RecordVisit)(Hdf5File *file, void *state, const unsigned char *record, size_t record_bytes);

typedef struct
{
    unsigned long long address;
    unsigned long long length;
} Hdf5Continuation;

typedef struct
{
    Hdf5LinkVisit visit;
    void *state;
    int table;
    unsigned long long table_tree;
    unsigned long long table_heap;
    int dense;
    unsigned long long dense_heap;
    unsigned long long dense_names;
    int hashed;
    uint32_t hash;
    const unsigned char *last_name;
    size_t last_length;
    const unsigned char *target;
    size_t target_length;
} Hdf5GroupWalk;

typedef struct
{
    unsigned long long header;
    unsigned int flags;
    unsigned long long width;
    unsigned long long start_block;
    unsigned long long largest_direct;
    unsigned int heap_bits;
    unsigned long long root;
    unsigned int root_rows;
    unsigned int position_bytes;
    unsigned int size_bytes;
    unsigned int direct_rows;
    unsigned int first_row_bits;
    unsigned int start_bits;
    unsigned char *block;
    unsigned long long block_address;
    unsigned long long block_bytes;
    size_t block_prefix;
} Hdf5Heap;

typedef struct
{
    unsigned int type;
    unsigned int node_bytes;
    unsigned int record_bytes;
    unsigned int depth;
    unsigned int count_bytes;
    unsigned long long maximum[HDF5_TREE2_LEVELS + 1u];
    unsigned int total_bytes[HDF5_TREE2_LEVELS + 1u];
    Hdf5RecordVisit visit;
    void *state;
    int hashed;
    uint32_t hash;
    int ordered_any;
    uint32_t last_hash;
    unsigned int run_count;
    unsigned char run[HDF5_RUN_RECORDS][HDF5_RECORD_ROOM];
} Hdf5Tree2;

typedef struct
{
    const char *name;
    size_t length;
    int found;
    unsigned int link_type;
    unsigned long long address;
} Hdf5Find;

typedef struct
{
    const Hdf5GroupWalk *walk;
    Hdf5Heap *heap;
} Hdf5DenseWalk;

typedef struct
{
    int printing;
    unsigned int candidates;
    unsigned long long chosen;
    unsigned int depth;
    size_t path_length;
    char path[HDF5_PATH_ROOM];
    unsigned long long *seen;
    size_t seen_count;
    size_t seen_room;
} Hdf5Survey;

typedef struct
{
    unsigned long long block;
    int filtered;
    unsigned int entry_bytes;
    unsigned int size_bytes;
    unsigned long long count;
    unsigned long long page_elements;
    unsigned long long page_count;
    size_t head_bytes;
    size_t prefix_bytes;
    unsigned char *prefix;
    unsigned char *page;
    unsigned long long page_loaded;
} Hdf5Fixed;

typedef struct
{
    Hdf5File *file;
    const Hdf5Object *object;
    unsigned long long first;
    unsigned long long past;
    unsigned char *out;
    size_t chunk_bytes;
    unsigned long long out_stride[ENGINE_ARRAY_RANK];
    unsigned long long chunk_stride[ENGINE_ARRAY_RANK];
    unsigned long long grid[ENGINE_ARRAY_RANK];
    unsigned long long reach[ENGINE_ARRAY_RANK];
    int keyed;
    unsigned long long last_key[ENGINE_ARRAY_RANK + 1u];
} Hdf5Gather;

static int hdf5_refuse(Hdf5File *file, const char *reason)
{
    if (file->reason[0u] == '\0')
    {
        (void)snprintf(file->reason, sizeof(file->reason), "%s", reason);
    }
    return 0;
}

static int hdf5_refuse_number(Hdf5File *file, const char *reason, unsigned long long number)
{
    if (file->reason[0u] == '\0')
    {
        (void)snprintf(file->reason, sizeof(file->reason), "%s %llu", reason, number);
    }
    return 0;
}

static Hdf5Walk hdf5_walk_refuse(Hdf5File *file, const char *reason)
{
    (void)hdf5_refuse(file, reason);
    return HDF5_WALK_FAILED;
}

static void hdf5_report(const Hdf5File *file)
{
    fprintf(stderr, "hdf5: %s: %s\n", (file->path != NULL) ? file->path : "(no path)",
            (file->reason[0u] != '\0') ? file->reason : "a malformed file");
}

static unsigned long long hdf5_little(const unsigned char *bytes, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < width; place += 1u)
    {
        value |= ((unsigned long long)bytes[place]) << (8u * place);
    }
    return value;
}

static unsigned long long hdf5_big(const unsigned char *bytes, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < width; place += 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place];
    }
    return value;
}

static unsigned long long hdf5_take(Hdf5Cursor *cursor, unsigned int width)
{
    const int fits = !cursor->broken && (width <= 8u) && ((cursor->length - cursor->at) >= width);
    cursor->broken = !fits;
    const unsigned long long value = fits ? hdf5_little(&cursor->bytes[cursor->at], width) : 0ull;
    cursor->at += fits ? width : 0u;
    return value;
}

static const unsigned char *hdf5_span(Hdf5Cursor *cursor, unsigned long long width)
{
    const int fits = !cursor->broken && ((unsigned long long)(cursor->length - cursor->at) >= width);
    cursor->broken = !fits;
    const unsigned char *const span = fits ? &cursor->bytes[cursor->at] : NULL;
    cursor->at += fits ? (size_t)width : 0u;
    return span;
}

static unsigned int hdf5_log2(unsigned long long value)
{
    unsigned int bits = 0u;
    while ((value >> bits) > 1ull)
    {
        bits += 1u;
    }
    return bits;
}

static int hdf5_power_of_two(unsigned long long value)
{
    return (value != 0ull) && ((value & (value - 1ull)) == 0ull);
}

static unsigned long long hdf5_all_ones(unsigned int width)
{
    return (width >= 8u) ? ~0ull : ((1ull << (8u * width)) - 1ull);
}

static int hdf5_undefined(const Hdf5File *file, unsigned long long address)
{
    return address == hdf5_all_ones(file->offset_bytes);
}

static int hdf5_product(const unsigned long long *values, unsigned int count, unsigned long long start, unsigned long long *product)
{
    unsigned long long total = start;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        if ((values[place] != 0ull) && (total > (~0ull / values[place])))
        {
            return 0;
        }
        total *= values[place];
    }
    *product = total;
    return 1;
}

static uint32_t hdf5_rotate(uint32_t value, unsigned int turn)
{
    return (value << turn) | (value >> (32u - turn));
}

static uint32_t hdf5_lookup3(const unsigned char *bytes, size_t length)
{
    uint32_t first = 0xDEADBEEFu + (uint32_t)length;
    uint32_t second = first;
    uint32_t third = first;
    size_t at = 0u;
    while ((length - at) > 12u)
    {
        first += (uint32_t)hdf5_little(&bytes[at], 4u);
        second += (uint32_t)hdf5_little(&bytes[at + 4u], 4u);
        third += (uint32_t)hdf5_little(&bytes[at + 8u], 4u);
        first -= third;
        first ^= hdf5_rotate(third, 4u);
        third += second;
        second -= first;
        second ^= hdf5_rotate(first, 6u);
        first += third;
        third -= second;
        third ^= hdf5_rotate(second, 8u);
        second += first;
        first -= third;
        first ^= hdf5_rotate(third, 16u);
        third += second;
        second -= first;
        second ^= hdf5_rotate(first, 19u);
        first += third;
        third -= second;
        third ^= hdf5_rotate(second, 4u);
        second += first;
        at += 12u;
    }
    if (length == at)
    {
        return third;
    }
    unsigned char tail[12u];
    memset(tail, 0, sizeof(tail));
    memcpy(tail, &bytes[at], length - at);
    first += (uint32_t)hdf5_little(&tail[0u], 4u);
    second += (uint32_t)hdf5_little(&tail[4u], 4u);
    third += (uint32_t)hdf5_little(&tail[8u], 4u);
    third ^= second;
    third -= hdf5_rotate(second, 14u);
    first ^= third;
    first -= hdf5_rotate(third, 11u);
    second ^= first;
    second -= hdf5_rotate(first, 25u);
    third ^= second;
    third -= hdf5_rotate(second, 16u);
    first ^= third;
    first -= hdf5_rotate(third, 4u);
    second ^= first;
    second -= hdf5_rotate(first, 14u);
    third ^= second;
    third -= hdf5_rotate(second, 24u);
    return third;
}

static int hdf5_sealed(const unsigned char *bytes, size_t length)
{
    return (length >= HDF5_SEAL_BYTES)
        && ((uint32_t)hdf5_little(&bytes[length - HDF5_SEAL_BYTES], 4u) == hdf5_lookup3(bytes, length - HDF5_SEAL_BYTES));
}

static uint32_t hdf5_fletcher32(const unsigned char *bytes, size_t length)
{
    uint32_t low = 0u;
    uint32_t high = 0u;
    size_t remaining = length / 2u;
    size_t at = 0u;
    while (remaining > 0u)
    {
        const size_t run = (remaining > 360u) ? 360u : remaining;
        remaining -= run;
        for (size_t step = 0u; step < run; step += 1u)
        {
            low += ((uint32_t)bytes[at] << 8u) | (uint32_t)bytes[at + 1u];
            high += low;
            at += 2u;
        }
        low = (low & 0xFFFFu) + (low >> 16u);
        high = (high & 0xFFFFu) + (high >> 16u);
    }
    if ((length % 2u) != 0u)
    {
        low += (uint32_t)bytes[at] << 8u;
        high += low;
        low = (low & 0xFFFFu) + (low >> 16u);
        high = (high & 0xFFFFu) + (high >> 16u);
    }
    low = (low & 0xFFFFu) + (low >> 16u);
    high = (high & 0xFFFFu) + (high >> 16u);
    return (high << 16u) | low;
}

static unsigned long long hdf5_room(const Hdf5File *file, unsigned long long address)
{
    const unsigned long long start = file->base + address;
    return ((start < file->base) || (start > file->file_bytes)) ? 0ull : (file->file_bytes - start);
}

static int hdf5_fetch(Hdf5File *file, unsigned long long address, unsigned long long bytes, unsigned char *out)
{
    if ((bytes == 0ull) || (bytes > hdf5_room(file, address)))
    {
        return hdf5_refuse(file, "a structure that lies past the end of the file");
    }
    const EngineFileRange range = {file->path, file->base + address, bytes, out};
    if (file->tools->read(&range) != (long long)bytes)
    {
        return hdf5_refuse(file, "a file read that came back short");
    }
    return 1;
}

static unsigned char *hdf5_load(Hdf5File *file, unsigned long long address, unsigned long long bytes)
{
    const size_t length = (size_t)bytes;
    if (file->budget == 0ull)
    {
        (void)hdf5_refuse(file, "more reads than any sane file needs");
        return NULL;
    }
    file->budget -= 1ull;
    if (((unsigned long long)length != bytes) || (bytes == 0ull) || (bytes > hdf5_room(file, address)))
    {
        (void)hdf5_refuse(file, "a structure that lies past the end of the file");
        return NULL;
    }
    unsigned char *const buffer = (unsigned char *)malloc(length);
    if (buffer == NULL)
    {
        (void)hdf5_refuse(file, "no memory for a structure");
        return NULL;
    }
    if (!hdf5_fetch(file, address, bytes, buffer))
    {
        free(buffer);
        return NULL;
    }
    return buffer;
}

static int hdf5_open(Hdf5File *file, const char *path, const EngineIngestTools *tools)
{
    memset(file, 0, sizeof(*file));
    file->path = path;
    file->tools = tools;
    file->budget = HDF5_BUDGET;
    file->offset_bytes = 8u;
    if ((path == NULL) || (tools == NULL) || (tools->read == NULL) || (tools->size == NULL))
    {
        return hdf5_refuse(file, "no path or no file reader");
    }
    const long long size = tools->size(path);
    if (size < 0LL)
    {
        return hdf5_refuse(file, "the file cannot be sized");
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
        return hdf5_refuse(file, "no HDF5 signature at byte 0, 512 or any doubling of 512");
    }
    unsigned char head[16u];
    if (!hdf5_fetch(file, place, sizeof(head), head))
    {
        return 0;
    }
    const unsigned int version = head[8u];
    if (version > 3u)
    {
        return hdf5_refuse_number(file, "superblock version", version);
    }
    const int old = (version <= 1u);
    file->offset_bytes = old ? head[13u] : head[9u];
    file->length_bytes = old ? head[14u] : head[10u];
    const int offsets_known = (file->offset_bytes == 2u) || (file->offset_bytes == 4u) || (file->offset_bytes == 8u);
    const int lengths_known = (file->length_bytes == 2u) || (file->length_bytes == 4u) || (file->length_bytes == 8u);
    if (!offsets_known || !lengths_known)
    {
        file->offset_bytes = 8u;
        return hdf5_refuse(file, "sizes of offsets or lengths other than 2, 4 or 8 bytes");
    }
    const size_t fixed = old ? ((version == 0u) ? 24u : 28u) : 12u;
    const unsigned long long total = old ? (fixed + (6ull * file->offset_bytes) + 24ull) : (fixed + (4ull * file->offset_bytes) + 4ull);
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
        return hdf5_refuse(file, "a superblock whose checksum does not match");
    }
    if (old && !hdf5_undefined(file, fourth))
    {
        return hdf5_refuse(file, "a file driver information block (family, multi or split driver)");
    }
    const unsigned long long shift_up = (stored_base <= place) ? (place - stored_base) : 0ull;
    const unsigned long long shift_down = (stored_base > place) ? (stored_base - place) : 0ull;
    const int wraps = (stored_end > (~0ull - shift_up)) || (stored_end < shift_down);
    const unsigned long long end = wraps ? ~0ull : ((stored_end + shift_up) - shift_down);
    if (end > file->file_bytes)
    {
        return hdf5_refuse_number(file, "a truncated file; the superblock says it ends at byte", end);
    }
    file->base = place;
    file->root = root;
    return 1;
}

static Hdf5Walk hdf5_header_region(Hdf5File *file, const unsigned char *bytes, size_t length, unsigned int version, int ordered,
                                   Hdf5Continuation *chain, unsigned int *chained, Hdf5MessageVisit visit, void *state)
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
            return hdf5_walk_refuse(file, "an object header message that runs past its block");
        }
        if (type == 0x10u)
        {
            Hdf5Cursor link = {body, size, 0u, 0};
            const unsigned long long address = hdf5_take(&link, file->offset_bytes);
            const unsigned long long extent = hdf5_take(&link, file->length_bytes);
            if (link.broken || (*chained >= HDF5_CONTINUATIONS))
            {
                return hdf5_walk_refuse(file, "an object header continuation that is malformed or one of too many");
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

static Hdf5Walk hdf5_header_walk(Hdf5File *file, unsigned long long address, Hdf5MessageVisit visit, void *state)
{
    unsigned char prefix[40u];
    const unsigned long long room = hdf5_room(file, address);
    const unsigned long long probe = (room < sizeof(prefix)) ? room : sizeof(prefix);
    if ((probe < 12ull) || !hdf5_fetch(file, address, probe, prefix))
    {
        return hdf5_walk_refuse(file, "an object header past the end of the file");
    }
    const int modern = (memcmp(prefix, "OHDR", 4u) == 0);
    const unsigned int flags = prefix[5u];
    const size_t times = (modern && ((flags & 0x20u) != 0u)) ? 16u : 0u;
    const size_t phases = (modern && ((flags & 0x10u) != 0u)) ? 4u : 0u;
    const unsigned int width = 1u << (flags & 3u);
    const size_t start = modern ? (6u + times + phases + width) : 16u;
    const int known = modern ? ((prefix[4u] == 2u) && ((flags & 0xC0u) == 0u)) : ((prefix[0u] == 1u) && (probe >= 16ull));
    if (!known || (start > probe))
    {
        return hdf5_walk_refuse(file, "an object header of an unknown version");
    }
    const unsigned long long chunk = modern ? hdf5_little(&prefix[6u + times + phases], width) : hdf5_little(&prefix[8u], 4u);
    const unsigned int version = modern ? 2u : 1u;
    const int ordered = modern && ((flags & 0x04u) != 0u);
    const unsigned long long total = start + chunk + (modern ? HDF5_SEAL_BYTES : 0u);
    if (chunk > room)
    {
        return hdf5_walk_refuse(file, "an object header larger than the file");
    }
    unsigned char *const first = hdf5_load(file, address, total);
    if (first == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    if (modern && !hdf5_sealed(first, (size_t)total))
    {
        free(first);
        return hdf5_walk_refuse(file, "an object header whose checksum does not match");
    }
    Hdf5Continuation chain[HDF5_CONTINUATIONS];
    unsigned int chained = 0u;
    Hdf5Walk step = hdf5_header_region(file, &first[start], (size_t)chunk, version, ordered, chain, &chained, visit, state);
    free(first);
    for (unsigned int next = 0u; (step == HDF5_WALK_ON) && (next < chained); next += 1u)
    {
        unsigned char *const block = hdf5_load(file, chain[next].address, chain[next].length);
        const size_t length = (size_t)chain[next].length;
        const int sound = (block != NULL)
                       && (!modern || ((length >= 8u) && (memcmp(block, "OCHK", 4u) == 0) && hdf5_sealed(block, length)));
        step = !sound ? hdf5_walk_refuse(file, "an object header continuation whose signature or checksum does not match")
             : modern ? hdf5_header_region(file, &block[4u], length - 8u, version, ordered, chain, &chained, visit, state)
                      : hdf5_header_region(file, block, length, version, ordered, chain, &chained, visit, state);
        free(block);
    }
    return step;
}

static void hdf5_object_unsupported(Hdf5Object *object, const char *reason, unsigned long long number)
{
    if (object->unsupported[0u] == '\0')
    {
        (void)snprintf(object->unsupported, sizeof(object->unsupported), "%s %llu", reason, number);
    }
}

static Hdf5Walk hdf5_object_space(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
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
    return cursor->broken ? hdf5_walk_refuse(file, "a malformed dataspace message") : HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_type(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
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
        return hdf5_walk_refuse(file, "a malformed datatype message");
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
    object->element_kind = (kind == 1u) ? ENGINE_ELEMENT_FLOAT : (((bits & 8u) != 0u) ? ENGINE_ELEMENT_SIGNED : ENGINE_ELEMENT_UNSIGNED);
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_fill(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, int old)
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
        return hdf5_walk_refuse(file, "a malformed fill value message");
    }
    unsigned char *const kept = old ? object->old_fill : object->fill;
    memcpy(kept, value, (size_t)((size < 8ull) ? size : 8ull));
    object->has_fill = object->has_fill || !old;
    object->has_old_fill = object->has_old_fill || old;
    object->fill_bytes = old ? object->fill_bytes : size;
    object->old_fill_bytes = old ? size : object->old_fill_bytes;
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_chunking(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, unsigned int version)
{
    const int indexed = (version >= 4u);
    const unsigned int flags = indexed ? (unsigned int)hdf5_take(cursor, 1u) : 0u;
    const unsigned int dimensions = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int width = indexed ? (unsigned int)hdf5_take(cursor, 1u) : 4u;
    object->data_address = (version == 3u) ? hdf5_take(cursor, file->offset_bytes) : 0ull;
    if (cursor->broken || (dimensions < 2u) || (dimensions > (ENGINE_ARRAY_RANK + 1u)) || (width < 1u) || (width > 8u))
    {
        return hdf5_walk_refuse(file, "a chunked layout message of an impossible rank");
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
    return cursor->broken ? hdf5_walk_refuse(file, "a malformed chunked layout message") : HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_layout(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int version = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int kind = (unsigned int)hdf5_take(cursor, 1u);
    if (cursor->broken || object->has_layout)
    {
        return hdf5_walk_refuse(file, "a malformed or repeated data layout message");
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
            return hdf5_walk_refuse(file, "a malformed compact layout message");
        }
        object->data_bytes = size;
        object->compact = (size > 0ull) ? (unsigned char *)malloc((size_t)size) : NULL;
        if ((size > 0ull) && (object->compact == NULL))
        {
            return hdf5_walk_refuse(file, "no memory for compact data");
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
        return cursor->broken ? hdf5_walk_refuse(file, "a malformed contiguous layout message") : HDF5_WALK_ON;
    }
    if (kind == 2u)
    {
        return hdf5_object_chunking(file, object, cursor, version);
    }
    hdf5_object_unsupported(object, (kind == 3u) ? "the virtual dataset layout; class" : "an unknown layout class", kind);
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_pipeline(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor)
{
    const unsigned int version = (unsigned int)hdf5_take(cursor, 1u);
    const unsigned int count = (unsigned int)hdf5_take(cursor, 1u);
    if (cursor->broken || object->has_pipeline || (count > HDF5_FILTERS))
    {
        return hdf5_walk_refuse(file, "a malformed or repeated filter pipeline message");
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
        const unsigned long long name_length = ((version == 1u) || (filter->identifier >= 256u)) ? hdf5_take(cursor, 2u) : 0ull;
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
    return cursor->broken ? hdf5_walk_refuse(file, "a malformed filter pipeline message") : HDF5_WALK_ON;
}

static Hdf5Walk hdf5_object_message(Hdf5File *file, void *state, unsigned int type, unsigned int flags, const unsigned char *body, size_t size)
{
    Hdf5Object *const object = (Hdf5Object *)state;
    Hdf5Cursor cursor = {body, size, 0u, 0};
    const int data_message = (type == 0x01u) || (type == 0x03u) || (type == 0x04u) || (type == 0x05u) || (type == 0x08u) || (type == 0x0Bu);
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
        return hdf5_walk_refuse(file, "a repeated dataspace message");
    }
    if ((type == 0x03u) && object->has_type)
    {
        return hdf5_walk_refuse(file, "a repeated datatype message");
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

static void hdf5_object_close(Hdf5Object *object)
{
    free(object->compact);
    object->compact = NULL;
}

static int hdf5_object_open(Hdf5File *file, unsigned long long address, Hdf5Object *object)
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

static Hdf5Walk hdf5_link_decode(Hdf5File *file, const unsigned char *body, size_t size, Hdf5LinkVisit visit, void *state)
{
    Hdf5Cursor cursor = {body, size, 0u, 0};
    const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
    const unsigned int flags = (unsigned int)hdf5_take(&cursor, 1u);
    if (cursor.broken || (version != 1u) || ((flags & 0xE0u) != 0u))
    {
        return hdf5_walk_refuse(file, "a link message of an unknown version");
    }
    const unsigned int link_type = ((flags & 0x08u) != 0u) ? (unsigned int)hdf5_take(&cursor, 1u) : 0u;
    (void)hdf5_span(&cursor, ((flags & 0x04u) != 0u) ? 8u : 0u);
    (void)hdf5_span(&cursor, ((flags & 0x10u) != 0u) ? 1u : 0u);
    const unsigned long long name_length = hdf5_take(&cursor, 1u << (flags & 3u));
    const unsigned char *const name = hdf5_span(&cursor, name_length);
    const unsigned long long address = (link_type == 0u) ? hdf5_take(&cursor, file->offset_bytes) : 0ull;
    if (cursor.broken || (name == NULL) || (name_length == 0ull))
    {
        return hdf5_walk_refuse(file, "a malformed link message");
    }
    return visit(file, state, name, (size_t)name_length, link_type, address);
}

static Hdf5Walk hdf5_group_message(Hdf5File *file, void *state, unsigned int type, unsigned int flags, const unsigned char *body, size_t size)
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
        return cursor.broken ? hdf5_walk_refuse(file, "a malformed symbol table message") : HDF5_WALK_ON;
    }
    if (type == 0x02u)
    {
        const unsigned int version = (unsigned int)hdf5_take(&cursor, 1u);
        const unsigned int link_flags = (unsigned int)hdf5_take(&cursor, 1u);
        (void)hdf5_span(&cursor, ((link_flags & 1u) != 0u) ? 8u : 0u);
        walk->dense_heap = hdf5_take(&cursor, file->offset_bytes);
        walk->dense_names = hdf5_take(&cursor, file->offset_bytes);
        walk->dense = 1;
        return (cursor.broken || (version != 0u)) ? hdf5_walk_refuse(file, "a malformed link info message") : HDF5_WALK_ON;
    }
    return HDF5_WALK_ON;
}

static int hdf5_name_after(const unsigned char *name, size_t length, const unsigned char *last, size_t last_length)
{
    const size_t shared = (length < last_length) ? length : last_length;
    const int order = memcmp(name, last, shared);
    return (order > 0) || ((order == 0) && (length > last_length));
}

static Hdf5Walk hdf5_table_symbols(Hdf5File *file, Hdf5GroupWalk *walk, const unsigned char *names, size_t names_length, unsigned long long address)
{
    unsigned char head[8u];
    if (!hdf5_fetch(file, address, sizeof(head), head))
    {
        return HDF5_WALK_FAILED;
    }
    if ((memcmp(head, "SNOD", 4u) != 0) || (head[4u] != 1u))
    {
        return hdf5_walk_refuse(file, "a symbol table node whose signature does not match");
    }
    const size_t count = (size_t)hdf5_little(&head[6u], 2u);
    if (count == 0u)
    {
        return hdf5_walk_refuse(file, "an empty symbol table node");
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
        const unsigned char *const end = (name != NULL) ? (const unsigned char *)memchr(name, 0, names_length - (size_t)name_offset) : NULL;
        const size_t length = (end != NULL) ? (size_t)(end - name) : 0u;
        const int ordered = (end != NULL) && ((walk->last_name == NULL) || hdf5_name_after(name, length, walk->last_name, walk->last_length));
        walk->last_name = ordered ? name : walk->last_name;
        walk->last_length = ordered ? length : walk->last_length;
        step = !ordered ? hdf5_walk_refuse(file, "a symbol whose name lies outside the local heap or out of order")
                        : walk->visit(file, walk->state, name, length, (cache == 2ull) ? 1u : 0u, object);
    }
    free(node);
    return step;
}

static Hdf5Walk hdf5_table_node(Hdf5File *file, Hdf5GroupWalk *walk, const unsigned char *names, size_t names_length, unsigned long long address,
                                unsigned int level, int root, unsigned int depth)
{
    const size_t pointer_bytes = file->offset_bytes;
    const size_t key_bytes = file->length_bytes;
    const size_t head = 8u + (2u * pointer_bytes);
    unsigned char prefix[24u];
    if (depth > HDF5_TREE_LEVELS)
    {
        return hdf5_walk_refuse(file, "a group B-tree deeper than any real file");
    }
    if (!hdf5_fetch(file, address, head, prefix))
    {
        return HDF5_WALK_FAILED;
    }
    const unsigned int node_level = prefix[5u];
    const size_t entries = (size_t)hdf5_little(&prefix[6u], 2u);
    if ((memcmp(prefix, "TREE", 4u) != 0) || (prefix[4u] != 0u) || (!root && (node_level != level)))
    {
        return hdf5_walk_refuse(file, "a group B-tree node whose signature, type or level is wrong");
    }
    if (entries == 0u)
    {
        return root ? HDF5_WALK_ON : hdf5_walk_refuse(file, "an empty group B-tree node below the root");
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
        const unsigned char *const left_end = (left < names_length) ? (const unsigned char *)memchr(&names[left], 0, names_length - (size_t)left) : NULL;
        const unsigned char *const right_end = (right < names_length) ? (const unsigned char *)memchr(&names[right], 0, names_length - (size_t)right) : NULL;
        const int keyed = (left_end != NULL) && (right_end != NULL);
        const int wanted = (walk->target == NULL)
                        || (keyed && hdf5_name_after(walk->target, walk->target_length, &names[left], (size_t)(left_end - &names[left]))
                            && !hdf5_name_after(walk->target, walk->target_length, &names[right], (size_t)(right_end - &names[right])));
        step = ((walk->target != NULL) && !keyed) ? hdf5_walk_refuse(file, "a group B-tree key outside the local heap")
             : !wanted                            ? HDF5_WALK_ON
             : (node_level > 0u)                  ? hdf5_table_node(file, walk, names, names_length, child_address, node_level - 1u, 0, depth + 1u)
                                                  : hdf5_table_symbols(file, walk, names, names_length, child_address);
    }
    free(node);
    return step;
}

static Hdf5Walk hdf5_table_links(Hdf5File *file, Hdf5GroupWalk *walk)
{
    const size_t head = 8u + (2u * (size_t)file->length_bytes) + file->offset_bytes;
    unsigned char prefix[32u];
    if (!hdf5_fetch(file, walk->table_heap, head, prefix))
    {
        return HDF5_WALK_FAILED;
    }
    if ((memcmp(prefix, "HEAP", 4u) != 0) || (prefix[4u] != 0u))
    {
        return hdf5_walk_refuse(file, "a local heap whose signature does not match");
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
        return hdf5_refuse(file, "a filtered fractal heap for dense links");
    }
    if (cursor.broken || !signed_right || !sealed)
    {
        return hdf5_refuse(file, "a fractal heap header whose signature or checksum does not match");
    }
    const int shaped = hdf5_power_of_two(heap->width) && hdf5_power_of_two(heap->start_block) && hdf5_power_of_two(heap->largest_direct)
                    && (heap->largest_direct >= heap->start_block) && (heap->largest_direct <= HDF5_LARGEST_DIRECT_BLOCK)
                    && (heap->heap_bits >= 1u) && (heap->heap_bits <= 64u) && (managed_largest > 0ull);
    if (!shaped)
    {
        return hdf5_refuse(file, "a fractal heap with an impossible doubling table");
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
        return hdf5_refuse(file, "a fractal heap with an impossible doubling table");
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
        return (offset < heap->start_block) ? 1 : hdf5_refuse(file, "a fractal heap object past its root block");
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
            return hdf5_refuse(file, "a fractal heap object outside its indirect block");
        }
        const unsigned long long column = first_row ? (relative / heap->start_block) : ((relative - (1ull << high)) / hdf5_heap_row_block(heap, row));
        const unsigned int direct = (rows < heap->direct_rows) ? rows : heap->direct_rows;
        const unsigned long long entries = (unsigned long long)rows * heap->width;
        const unsigned long long bytes = head + (entries * file->offset_bytes) + HDF5_SEAL_BYTES;
        unsigned char *const node = hdf5_load(file, indirect, bytes);
        if (node == NULL)
        {
            return 0;
        }
        const int sound = (memcmp(node, "FHIB", 4u) == 0) && (node[4u] == 0u) && hdf5_sealed(node, (size_t)bytes)
                       && (hdf5_little(&node[5u], file->offset_bytes) == heap->header)
                       && (hdf5_little(&node[5u + file->offset_bytes], heap->position_bytes) == base_offset);
        const unsigned long long entry = ((unsigned long long)row * heap->width) + column;
        const unsigned long long child = sound ? hdf5_little(&node[head + (size_t)(entry * file->offset_bytes)], file->offset_bytes) : 0ull;
        free(node);
        if (!sound || hdf5_undefined(file, child))
        {
            return hdf5_refuse(file, "a fractal heap indirect block whose signature, checksum or entry is wrong");
        }
        const unsigned long long child_offset = base_offset + hdf5_heap_row_start(heap, row) + (column * hdf5_heap_row_block(heap, row));
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
    return hdf5_refuse(file, "a fractal heap nested deeper than any real file");
}

static int hdf5_heap_block(Hdf5File *file, Hdf5Heap *heap, unsigned long long address, unsigned long long bytes, unsigned long long block_offset)
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
    int sound = (bytes > prefix) && (memcmp(block, "FHDB", 4u) == 0) && (block[4u] == 0u)
             && (hdf5_little(&block[5u], file->offset_bytes) == heap->header)
             && (hdf5_little(&block[5u + file->offset_bytes], heap->position_bytes) == block_offset);
    if (sound && summed)
    {
        const uint32_t stored = (uint32_t)hdf5_little(&block[head], 4u);
        memset(&block[head], 0, HDF5_SEAL_BYTES);
        sound = (stored == hdf5_lookup3(block, (size_t)bytes));
    }
    if (!sound)
    {
        free(block);
        return hdf5_refuse(file, "a fractal heap direct block whose signature, offset or checksum does not match");
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
        return hdf5_refuse(file, "an empty fractal heap identifier");
    }
    const unsigned int flags = identifier[0u];
    const unsigned int kind = (flags >> 4u) & 3u;
    if ((flags >> 6u) != 0u)
    {
        return hdf5_refuse(file, "a fractal heap identifier of an unknown version");
    }
    if (kind == 1u)
    {
        return hdf5_refuse(file, "a huge object in a fractal heap");
    }
    if (kind == 2u)
    {
        const int extended = (identifier_bytes > 18u);
        const size_t head = extended ? 2u : 1u;
        const size_t length = extended ? ((((size_t)(flags & 0x0Fu)) << 8u) | identifier[1u]) + 1u : ((size_t)(flags & 0x0Fu) + 1u);
        if (identifier_bytes < (head + length))
        {
            return hdf5_refuse(file, "a tiny fractal heap object longer than its identifier");
        }
        *object = &identifier[head];
        *object_bytes = length;
        return 1;
    }
    if ((kind != 0u) || (identifier_bytes < (1u + (size_t)heap->position_bytes + heap->size_bytes)))
    {
        return hdf5_refuse(file, "a malformed fractal heap identifier");
    }
    const unsigned long long offset = hdf5_little(&identifier[1u], heap->position_bytes);
    const unsigned long long length = hdf5_little(&identifier[1u + heap->position_bytes], heap->size_bytes);
    unsigned long long block = 0ull;
    unsigned long long block_bytes = 0ull;
    unsigned long long block_offset = 0ull;
    if (!hdf5_heap_locate(file, heap, offset, &block, &block_bytes, &block_offset)
        || !hdf5_heap_block(file, heap, block, block_bytes, block_offset))
    {
        return 0;
    }
    const unsigned long long within = offset - block_offset;
    if ((offset < block_offset) || (within < heap->block_prefix) || (length == 0ull) || (within > block_bytes) || (length > (block_bytes - within)))
    {
        return hdf5_refuse(file, "a fractal heap object outside its direct block");
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

static Hdf5Walk hdf5_tree2_node(Hdf5File *file, Hdf5Tree2 *tree, unsigned long long address, unsigned long long records, unsigned int level, int root)
{
    if ((records > tree->maximum[level]) || (!root && (records == 0ull)))
    {
        return hdf5_walk_refuse(file, "a version 2 B-tree node with more records than it can hold, or none below the root");
    }
    const size_t pointer = (level == 0u) ? 0u : ((size_t)file->offset_bytes + tree->count_bytes + ((level > 1u) ? tree->total_bytes[level - 1u] : 0u));
    const size_t records_bytes = (size_t)records * tree->record_bytes;
    const size_t bytes = 6u + records_bytes + ((level == 0u) ? 0u : ((size_t)(records + 1ull) * pointer)) + HDF5_SEAL_BYTES;
    if (bytes > tree->node_bytes)
    {
        return hdf5_walk_refuse(file, "a version 2 B-tree node larger than its node size");
    }
    unsigned char *const node = hdf5_load(file, address, bytes);
    if (node == NULL)
    {
        return HDF5_WALK_FAILED;
    }
    const int sound = (memcmp(node, (level == 0u) ? "BTLF" : "BTIN", 4u) == 0) && (node[4u] == 0u) && (node[5u] == tree->type) && hdf5_sealed(node, bytes);
    Hdf5Walk step = sound ? HDF5_WALK_ON : hdf5_walk_refuse(file, "a version 2 B-tree node whose signature or checksum does not match");
    for (unsigned long long place = 0ull; (step == HDF5_WALK_ON) && (place <= records); place += 1ull)
    {
        const unsigned char *const record = &node[6u + ((size_t)place * tree->record_bytes)];
        const unsigned char *const before = (place > 0ull) ? &node[6u + ((size_t)(place - 1ull) * tree->record_bytes)] : record;
        const int after_low = !tree->hashed || (place == 0ull) || ((uint32_t)hdf5_little(before, 4u) <= tree->hash);
        const int before_high = !tree->hashed || (place == records) || ((uint32_t)hdf5_little(record, 4u) >= tree->hash);
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
            step = hdf5_tree2_ordered(tree, record) ? tree->visit(file, tree->state, record, tree->record_bytes)
                                                    : hdf5_walk_refuse(file, "version 2 B-tree records that repeat or run out of order");
        }
    }
    free(node);
    return step;
}

static Hdf5Walk hdf5_tree2_walk(Hdf5File *file, unsigned long long address, unsigned int type, Hdf5RecordVisit visit, void *state, int hashed,
                                uint32_t hash)
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
    const int sound = !cursor.broken && (memcmp(header, "BTHD", 4u) == 0) && (version == 0u) && (stated_type == type) && hdf5_sealed(header, (size_t)total);
    free(header);
    if (!sound)
    {
        return hdf5_walk_refuse(file, "a version 2 B-tree header whose signature, type or checksum does not match");
    }
    if ((tree.depth > HDF5_TREE2_LEVELS) || (tree.record_bytes < 4u) || (tree.record_bytes > HDF5_RECORD_ROOM) || (tree.node_bytes <= (10u + tree.record_bytes)))
    {
        return hdf5_walk_refuse(file, "a version 2 B-tree of an impossible shape");
    }
    tree.maximum[0u] = (tree.node_bytes - 10u) / tree.record_bytes;
    tree.count_bytes = (hdf5_log2(tree.maximum[0u]) / 8u) + 1u;
    unsigned long long cumulative = tree.maximum[0u];
    for (unsigned int level = 1u; level <= tree.depth; level += 1u)
    {
        const unsigned int pointer = file->offset_bytes + tree.count_bytes + ((level > 1u) ? tree.total_bytes[level - 1u] : 0u);
        tree.maximum[level] = (tree.node_bytes - 10u) / (tree.record_bytes + pointer);
        const unsigned long long fanout = tree.maximum[level] + 1ull;
        if ((tree.maximum[level] == 0ull) || (cumulative > ((~0ull - tree.maximum[level]) / fanout)))
        {
            return hdf5_walk_refuse(file, "a version 2 B-tree of an impossible shape");
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
        return hdf5_walk_refuse(file, "a link name record too short to hold a heap identifier");
    }
    const unsigned char *object = NULL;
    size_t object_bytes = 0u;
    if (!hdf5_heap_object(file, dense->heap, &record[4u], record_bytes - 4u, &object, &object_bytes))
    {
        return HDF5_WALK_FAILED;
    }
    return hdf5_link_decode(file, object, object_bytes, dense->walk->visit, dense->walk->state);
}

static Hdf5Walk hdf5_dense_links(Hdf5File *file, const Hdf5GroupWalk *walk)
{
    Hdf5Heap heap;
    if (!hdf5_heap_open(file, walk->dense_heap, &heap))
    {
        return HDF5_WALK_FAILED;
    }
    Hdf5DenseWalk dense = {walk, &heap};
    const Hdf5Walk step = hdf5_tree2_walk(file, walk->dense_names, 5u, hdf5_dense_record, &dense, walk->hashed, walk->hash);
    free(heap.block);
    return step;
}

static Hdf5Walk hdf5_group_links(Hdf5File *file, unsigned long long header, Hdf5LinkVisit visit, void *state, const char *name, size_t name_length)
{
    const uint32_t hash = (name != NULL) ? hdf5_lookup3((const unsigned char *)name, name_length) : 0u;
    Hdf5GroupWalk walk = {visit, state, 0, 0ull, 0ull, 0, 0ull, 0ull, name != NULL, hash, NULL, 0u, (const unsigned char *)name, name_length};
    const Hdf5Walk messages = hdf5_header_walk(file, header, hdf5_group_message, &walk);
    if (messages != HDF5_WALK_ON)
    {
        return messages;
    }
    if (walk.table)
    {
        return hdf5_table_links(file, &walk);
    }
    if (walk.dense && !hdf5_undefined(file, walk.dense_heap))
    {
        return hdf5_dense_links(file, &walk);
    }
    return HDF5_WALK_ON;
}

static Hdf5Walk hdf5_find_link(Hdf5File *file, void *state, const unsigned char *name, size_t name_length, unsigned int link_type, unsigned long long address)
{
    Hdf5Find *const find = (Hdf5Find *)state;
    (void)file;
    if ((name_length != find->length) || (memcmp(name, find->name, name_length) != 0))
    {
        return HDF5_WALK_ON;
    }
    find->found = 1;
    find->link_type = link_type;
    find->address = address;
    return HDF5_WALK_STOPPED;
}

static void hdf5_print_candidate(const char *path, const Hdf5Object *object)
{
    fprintf(stderr, "hdf5: candidate %s shape (", path);
    const unsigned int shown = (object->rank > ENGINE_ARRAY_RANK) ? 0u : object->rank;
    for (unsigned int axis = 0u; axis < shown; axis += 1u)
    {
        fprintf(stderr, "%s%llu", (axis == 0u) ? "" : ", ", object->extent[axis]);
    }
    if (shown == 0u)
    {
        fprintf(stderr, "rank %u", object->rank);
    }
    fprintf(stderr, ")\n");
}

static int hdf5_survey_mark(Hdf5File *file, Hdf5Survey *survey, unsigned long long address)
{
    for (size_t place = 0u; place < survey->seen_count; place += 1u)
    {
        if (survey->seen[place] == address)
        {
            return 1;
        }
    }
    if (survey->seen_count == survey->seen_room)
    {
        const size_t grown = (survey->seen_room == 0u) ? 64u : (survey->seen_room * 2u);
        unsigned long long *const larger = (grown <= HDF5_OBJECTS) ? (unsigned long long *)realloc(survey->seen, grown * sizeof(*larger)) : NULL;
        if (larger == NULL)
        {
            return (hdf5_refuse(file, "more objects than the survey holds") - 1);
        }
        survey->seen = larger;
        survey->seen_room = grown;
    }
    survey->seen[survey->seen_count] = address;
    survey->seen_count += 1u;
    return 0;
}

static Hdf5Walk hdf5_survey_link(Hdf5File *file, void *state, const unsigned char *name, size_t name_length, unsigned int link_type, unsigned long long address)
{
    Hdf5Survey *const survey = (Hdf5Survey *)state;
    if (link_type != 0u)
    {
        return HDF5_WALK_ON;
    }
    const int marked = hdf5_survey_mark(file, survey, address);
    if (marked != 0)
    {
        return (marked < 0) ? HDF5_WALK_FAILED : HDF5_WALK_ON;
    }
    const size_t mark = survey->path_length;
    if ((name_length >= HDF5_PATH_ROOM) || ((mark + 1u + name_length) >= HDF5_PATH_ROOM))
    {
        return hdf5_walk_refuse(file, "a member path longer than the survey holds");
    }
    survey->path[mark] = '/';
    memcpy(&survey->path[mark + 1u], name, name_length);
    survey->path_length = mark + 1u + name_length;
    survey->path[survey->path_length] = '\0';
    Hdf5Object object;
    Hdf5Walk step = hdf5_object_open(file, address, &object) ? HDF5_WALK_ON : HDF5_WALK_FAILED;
    if ((step == HDF5_WALK_ON) && object.has_layout && (object.rank >= 2u))
    {
        survey->candidates += 1u;
        survey->chosen = (survey->candidates == 1u) ? address : survey->chosen;
        if (survey->printing)
        {
            hdf5_print_candidate(survey->path, &object);
        }
    }
    else if ((step == HDF5_WALK_ON) && object.group && !object.has_layout)
    {
        survey->depth += 1u;
        step = (survey->depth > HDF5_GROUP_DEPTH) ? hdf5_walk_refuse(file, "groups nested deeper than the survey goes")
                                                  : hdf5_group_links(file, address, hdf5_survey_link, survey, NULL, 0u);
        survey->depth -= 1u;
    }
    hdf5_object_close(&object);
    survey->path_length = mark;
    survey->path[mark] = '\0';
    return (step == HDF5_WALK_FAILED) ? HDF5_WALK_FAILED : HDF5_WALK_ON;
}

static int hdf5_survey_pass(Hdf5File *file, Hdf5Survey *survey, int printing)
{
    survey->printing = printing;
    survey->candidates = 0u;
    survey->chosen = 0ull;
    survey->depth = 0u;
    survey->path_length = 0u;
    survey->path[0u] = '\0';
    survey->seen_count = 0u;
    return (hdf5_survey_mark(file, survey, file->root) >= 0) && (hdf5_group_links(file, file->root, hdf5_survey_link, survey, NULL, 0u) != HDF5_WALK_FAILED);
}

static int hdf5_survey(Hdf5File *file, unsigned long long *address)
{
    Hdf5Survey *const survey = (Hdf5Survey *)calloc(1u, sizeof(Hdf5Survey));
    if (survey == NULL)
    {
        return hdf5_refuse(file, "no memory for the survey");
    }
    survey->seen = NULL;
    int good = hdf5_survey_pass(file, survey, 0);
    if (good && (survey->candidates == 0u))
    {
        good = hdf5_refuse(file, "no dataset of rank 2 or more in the file");
    }
    if (good && (survey->candidates > 1u))
    {
        fprintf(stderr, "hdf5: %s holds %u datasets of rank 2 or more; name one:\n", file->path, survey->candidates);
        (void)hdf5_survey_pass(file, survey, 1);
        good = hdf5_refuse(file, "more than one dataset of rank 2 or more; name the member");
    }
    *address = survey->chosen;
    free(survey->seen);
    free(survey);
    return good;
}

static int hdf5_locate(Hdf5File *file, const char *member, unsigned long long *address)
{
    if (member == NULL)
    {
        return hdf5_survey(file, address);
    }
    unsigned long long current = file->root;
    const size_t length = strlen(member);
    size_t at = 0u;
    while (at < length)
    {
        if (member[at] == '/')
        {
            at += 1u;
            continue;
        }
        size_t end = at;
        while ((end < length) && (member[end] != '/'))
        {
            end += 1u;
        }
        Hdf5Find find = {&member[at], end - at, 0, 0u, 0ull};
        if (hdf5_group_links(file, current, hdf5_find_link, &find, find.name, find.length) == HDF5_WALK_FAILED)
        {
            return 0;
        }
        if (!find.found)
        {
            if (file->reason[0u] == '\0')
            {
                (void)snprintf(file->reason, sizeof(file->reason), "no member named %s", member);
            }
            return 0;
        }
        if (find.link_type != 0u)
        {
            return hdf5_refuse_number(file, "a soft or external link on the member path; link type", find.link_type);
        }
        current = find.address;
        at = end;
    }
    *address = current;
    return 1;
}

static int hdf5_codec_ready(const Hdf5File *file, unsigned int identifier)
{
    const EngineBytesDecode *const decode = file->tools->decode;
    return (identifier == 2u) || (identifier == 3u) || ((identifier == 1u) && (decode[ENGINE_CODEC_ZLIB] != NULL))
        || ((identifier == 32001u) && (decode[ENGINE_CODEC_BLOSC] != NULL))
        || ((identifier == 32004u) && (decode[ENGINE_CODEC_LZ4] != NULL))
        || ((identifier == 32015u) && (decode[ENGINE_CODEC_ZSTD] != NULL));
}

static int hdf5_codec_known(unsigned int identifier)
{
    return (identifier == 1u) || (identifier == 2u) || (identifier == 3u) || (identifier == 32001u) || (identifier == 32004u)
        || (identifier == 32015u);
}

static int hdf5_chunking_check(Hdf5File *file, const Hdf5Object *object)
{
    const unsigned int rank = object->rank;
    if (object->chunk_rank != (rank + 1u))
    {
        return hdf5_refuse(file, "a chunk rank that does not match the dataspace");
    }
    if (object->chunk[rank] != object->element_bytes)
    {
        return hdf5_refuse(file, "a chunk element size that does not match the datatype");
    }
    unsigned long long chunk_bytes = 0ull;
    if (!hdf5_product(object->chunk, rank + 1u, 1ull, &chunk_bytes) || (chunk_bytes == 0ull) || ((unsigned long long)(size_t)chunk_bytes != chunk_bytes)
        || (chunk_bytes > HDF5_LARGEST_CHUNK))
    {
        return hdf5_refuse(file, "a chunk of zero size or larger than 4 GiB");
    }
    unsigned long long reach = 1ull;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const int bounded = (object->maximum[axis] != hdf5_all_ones(file->length_bytes)) && (object->maximum[axis] >= object->extent[axis]);
        const unsigned long long cells = bounded ? ((object->maximum[axis] / object->chunk[axis]) + (((object->maximum[axis] % object->chunk[axis]) != 0ull) ? 1ull : 0ull)) : 1ull;
        if (((object->chunk_index == HDF5_INDEX_FIXED) || (object->chunk_index == HDF5_INDEX_IMPLICIT)) && (!bounded || ((cells != 0ull) && (reach > (~0ull / cells)))))
        {
            return hdf5_refuse(file, "an unlimited or impossible dimension on a fixed-size chunk index");
        }
        reach *= (cells != 0ull) ? cells : 1ull;
        if ((object->chunk_index == HDF5_INDEX_SINGLE) && (object->chunk[axis] < object->extent[axis]))
        {
            return hdf5_refuse(file, "a single-chunk index whose chunk is smaller than the dataset");
        }
    }
    if ((object->chunk_index == HDF5_INDEX_IMPLICIT) && (object->filter_count > 0u))
    {
        return hdf5_refuse(file, "a filtered dataset on the implicit chunk index");
    }
    if ((object->chunk_index == HDF5_INDEX_SINGLE) && (object->filter_count > 0u) && ((object->chunk_flags & 2u) == 0u))
    {
        return hdf5_refuse(file, "a filtered single chunk with no stored size");
    }
    for (unsigned int place = 0u; place < object->filter_count; place += 1u)
    {
        const unsigned int identifier = object->filters[place].identifier;
        if (!hdf5_codec_known(identifier))
        {
            return hdf5_refuse_number(file, "an unsupported filter; filter", identifier);
        }
        if (!hdf5_codec_ready(file, identifier))
        {
            return hdf5_refuse_number(file, "a filter whose decoder slot is empty; filter", identifier);
        }
    }
    return 1;
}

static int hdf5_dataset_check(Hdf5File *file, const Hdf5Object *object)
{
    if (object->unsupported[0u] != '\0')
    {
        return hdf5_refuse(file, object->unsupported);
    }
    if (!object->has_layout || !object->has_space || !object->has_type)
    {
        return hdf5_refuse(file, object->group ? "the member is a group, not a dataset" : "the member is not a dataset");
    }
    if (object->external)
    {
        return hdf5_refuse(file, "a dataset stored in external data files");
    }
    if (object->rank == 0u)
    {
        return hdf5_refuse(file, "a scalar or null dataspace; there is no axis 0");
    }
    const unsigned long long fill_bytes = object->has_fill ? object->fill_bytes : object->old_fill_bytes;
    if ((fill_bytes != 0ull) && (fill_bytes != object->element_bytes))
    {
        return hdf5_refuse(file, "a fill value whose size is not the element size");
    }
    unsigned long long total = 0ull;
    if (!hdf5_product(object->extent, object->rank, object->element_bytes, &total))
    {
        return hdf5_refuse(file, "a dataset whose byte size overflows");
    }
    if ((object->layout_class != 2u) && (object->filter_count > 0u))
    {
        return hdf5_refuse(file, "a filter pipeline on an unchunked dataset");
    }
    if (object->layout_class == 0u)
    {
        return (object->data_bytes >= total) ? 1 : hdf5_refuse(file, "compact data shorter than the dataset");
    }
    if (object->layout_class == 1u)
    {
        return (hdf5_undefined(file, object->data_address) || (object->data_bytes >= total)) ? 1 : hdf5_refuse(file, "contiguous data shorter than the dataset");
    }
    return hdf5_chunking_check(file, object);
}

static long long hdf5_decode(const Hdf5File *file, EngineCodec codec, const unsigned char *in, size_t in_bytes, unsigned char *out, size_t room)
{
    const EngineBytesDecode decode = file->tools->decode[codec];
    if (decode == NULL)
    {
        return -1LL;
    }
    const EngineBytesRequest request = {in, in_bytes, out, room};
    const long long made = decode(&request);
    return ((made < 0LL) || ((unsigned long long)made > (unsigned long long)room)) ? -1LL : made;
}

static long long hdf5_lz4_frames(const Hdf5File *file, const unsigned char *in, size_t length, unsigned char *out, size_t room)
{
    if (length < 12u)
    {
        return -1LL;
    }
    const unsigned long long total = hdf5_big(in, 8u);
    const unsigned long long declared = hdf5_big(&in[8u], 4u);
    const unsigned long long block = (declared > total) ? total : declared;
    if ((total > (unsigned long long)room) || ((block == 0ull) && (total != 0ull)))
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
        else if (hdf5_decode(file, ENGINE_CODEC_LZ4, &in[at], (size_t)packed, &out[made], (size_t)piece) != (long long)piece)
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

static int hdf5_unfilter(Hdf5Gather *gather, unsigned char **data, unsigned char **spare, size_t *length, size_t room, unsigned int mask)
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
        const long long made = skipped                      ? (long long)*length
                             : (identifier == 1u)           ? hdf5_decode(file, ENGINE_CODEC_ZLIB, in, *length, out, room)
                             : (identifier == 2u)           ? hdf5_unshuffle(in, *length, out, (filter->value_count > 0u) ? filter->values[0u] : object->element_bytes)
                             : (identifier == 3u)           ? hdf5_fletcher(in, *length, out)
                             : (identifier == 32001u)       ? hdf5_decode(file, ENGINE_CODEC_BLOSC, in, *length, out, room)
                             : (identifier == 32004u)       ? hdf5_lz4_frames(file, in, *length, out, room)
                             : (identifier == 32015u)       ? hdf5_decode(file, ENGINE_CODEC_ZSTD, in, *length, out, room)
                                                            : -1LL;
        if (made < 0LL)
        {
            return hdf5_refuse_number(file, "a chunk its filter would not decode, or whose checksum failed; filter", identifier);
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

static void hdf5_chunk_copy(const Hdf5Gather *gather, const unsigned char *chunk, const unsigned long long *origin, const unsigned long long *low,
                            const unsigned long long *high)
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

static int hdf5_chunk_place(Hdf5Gather *gather, const unsigned long long *origin, unsigned long long address, unsigned long long stored, unsigned int mask)
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
        const unsigned long long top = (axis == 0u) ? gather->past : object->extent[axis];
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
    if ((stored == 0ull) || (stored > hdf5_room(file, address)))
    {
        return hdf5_refuse(file, "a chunk that lies past the end of the file");
    }
    const size_t room = (((size_t)stored > gather->chunk_bytes) ? (size_t)stored : gather->chunk_bytes) + 64u;
    unsigned char *data = (unsigned char *)malloc(room);
    unsigned char *spare = filtered ? (unsigned char *)malloc(room) : NULL;
    int good = (data != NULL) && (!filtered || (spare != NULL));
    good = good ? hdf5_fetch(file, address, stored, data) : hdf5_refuse(file, "no memory for a chunk");
    size_t length = (size_t)stored;
    good = good && (!filtered || hdf5_unfilter(gather, &data, &spare, &length, room, mask));
    good = good && ((length == gather->chunk_bytes) || hdf5_refuse(file, "a chunk that does not decode to the chunk size"));
    if (good)
    {
        hdf5_chunk_copy(gather, data, origin, low, high);
    }
    free(data);
    free(spare);
    return good;
}

static int hdf5_chunk_tree(Hdf5Gather *gather, unsigned long long address, unsigned int level, int root, unsigned int depth)
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
    int good = 1;
    for (size_t child = 0u; good && (child < entries); child += 1u)
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
            good = (after > 0) ? 1 : hdf5_refuse(file, "chunk B-tree keys that repeat or run out of order");
            memcpy(gather->last_key, origin, dimensions * sizeof(origin[0u]));
            gather->keyed = 1;
            good = good && hdf5_chunk_place(gather, origin, child_address, hdf5_little(key, 4u), (unsigned int)hdf5_little(&key[4u], 4u));
        }
        else
        {
            const unsigned long long upper = hdf5_little(&next[8u], 8u);
            const int reaches = (upper > (~0ull - object->chunk[0u])) || ((upper + object->chunk[0u]) > gather->first);
            const int needed = (origin[0u] < gather->past) && reaches;
            good = !needed || hdf5_chunk_tree(gather, child_address, node_level - 1u, 0, depth + 1u);
        }
    }
    free(node);
    return good;
}

static void hdf5_fixed_close(Hdf5Fixed *fixed)
{
    free(fixed->prefix);
    free(fixed->page);
    fixed->prefix = NULL;
    fixed->page = NULL;
}

static int hdf5_fixed_open(Hdf5File *file, const Hdf5Object *object, const Hdf5Gather *gather, Hdf5Fixed *fixed)
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
    const int entry_fits = fixed->filtered ? ((fixed->entry_bytes > (offset_bytes + 4u)) && (fixed->entry_bytes <= (offset_bytes + 12u)))
                                           : (fixed->entry_bytes == offset_bytes);
    const int shaped = (client <= 1u) && (fixed->filtered == (object->filter_count > 0u)) && entry_fits && (page_bits < 32u)
                    && hdf5_product(gather->reach, object->rank, 1ull, &expected) && (fixed->count == expected)
                    && (fixed->count <= file->file_bytes);
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
    fixed->page_count = (fixed->count > fixed->page_elements) ? ((fixed->count + fixed->page_elements - 1ull) / fixed->page_elements) : 0ull;
    fixed->head_bytes = 6u + (size_t)offset_bytes;
    fixed->prefix_bytes = fixed->head_bytes + (size_t)((fixed->page_count + 7ull) / 8ull) + HDF5_SEAL_BYTES;
    const unsigned long long loaded = (fixed->page_count == 0ull) ? (fixed->head_bytes + (fixed->count * fixed->entry_bytes) + HDF5_SEAL_BYTES) : fixed->prefix_bytes;
    fixed->prefix = hdf5_load(file, fixed->block, loaded);
    if (fixed->prefix == NULL)
    {
        return 0;
    }
    const int block_sound = hdf5_sealed(fixed->prefix, (size_t)loaded) && (memcmp(fixed->prefix, "FADB", 4u) == 0) && (fixed->prefix[4u] == 0u)
                         && (fixed->prefix[5u] == client) && (hdf5_little(&fixed->prefix[6u], offset_bytes) == object->data_address);
    if (!block_sound)
    {
        hdf5_fixed_close(fixed);
        return hdf5_refuse(file, "a fixed array data block whose signature or checksum does not match");
    }
    return 1;
}

static int hdf5_fixed_entry(Hdf5File *file, Hdf5Fixed *fixed, unsigned long long linear, unsigned long long *address, unsigned long long *stored,
                            unsigned int *mask)
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
            const unsigned long long elements = ((page + 1ull) == fixed->page_count) ? (fixed->count - (page * fixed->page_elements)) : fixed->page_elements;
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

static int hdf5_chunk_grid(Hdf5Gather *gather)
{
    Hdf5File *const file = gather->file;
    const Hdf5Object *const object = gather->object;
    const unsigned int rank = object->rank;
    unsigned long long down[ENGINE_ARRAY_RANK];
    down[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        down[axis - 1u] = down[axis] * gather->reach[axis];
    }
    Hdf5Fixed fixed;
    memset(&fixed, 0, sizeof(fixed));
    fixed.prefix = NULL;
    fixed.page = NULL;
    int good = (object->chunk_index != HDF5_INDEX_FIXED) || hdf5_fixed_open(file, object, gather, &fixed);
    const unsigned long long start = gather->first / object->chunk[0u];
    const unsigned long long stop = (gather->past / object->chunk[0u]) + (((gather->past % object->chunk[0u]) != 0ull) ? 1ull : 0ull);
    unsigned long long scaled[ENGINE_ARRAY_RANK];
    memset(scaled, 0, sizeof(scaled));
    scaled[0u] = start;
    int more = good && (start < stop);
    for (unsigned int axis = 1u; axis < rank; axis += 1u)
    {
        more = more && (gather->grid[axis] > 0ull);
    }
    while (more)
    {
        unsigned long long origin[ENGINE_ARRAY_RANK];
        unsigned long long linear = 0ull;
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            origin[axis] = scaled[axis] * object->chunk[axis];
            linear += scaled[axis] * down[axis];
        }
        unsigned long long address = hdf5_all_ones(file->offset_bytes);
        unsigned long long stored = gather->chunk_bytes;
        unsigned int mask = 0u;
        if (object->chunk_index == HDF5_INDEX_SINGLE)
        {
            address = object->data_address;
            stored = (object->filter_count > 0u) ? object->single_bytes : stored;
            mask = object->single_mask;
        }
        else if (object->chunk_index == HDF5_INDEX_IMPLICIT)
        {
            address = hdf5_undefined(file, object->data_address) ? address : (object->data_address + (linear * gather->chunk_bytes));
        }
        else
        {
            good = hdf5_fixed_entry(file, &fixed, linear, &address, &stored, &mask);
        }
        good = good && hdf5_chunk_place(gather, origin, address, stored, mask);
        more = 0;
        for (unsigned int axis = rank; good && (axis > 0u); axis -= 1u)
        {
            const unsigned int moving = axis - 1u;
            const unsigned long long bound = (moving == 0u) ? stop : gather->grid[moving];
            scaled[moving] += 1ull;
            if (scaled[moving] < bound)
            {
                more = 1;
                break;
            }
            scaled[moving] = (moving == 0u) ? start : 0ull;
        }
    }
    hdf5_fixed_close(&fixed);
    return good;
}

static void hdf5_swap(unsigned char *bytes, size_t length, unsigned int width)
{
    for (size_t element = 0u; (element + width) <= length; element += width)
    {
        for (unsigned int lane = 0u; lane < (width / 2u); lane += 1u)
        {
            const unsigned char kept = bytes[element + lane];
            bytes[element + lane] = bytes[element + width - 1u - lane];
            bytes[element + width - 1u - lane] = kept;
        }
    }
}

static int hdf5_request_check(Hdf5File *file, const Hdf5Object *object, const EngineArrayRead *request, unsigned long long *bytes)
{
    const EngineArrayShape *const shape = request->shape;
    int matches = (shape == NULL)
               || ((shape->rank == object->rank) && (shape->element_bytes == object->element_bytes) && (shape->element_kind == object->element_kind));
    for (unsigned int axis = 0u; matches && (shape != NULL) && (axis < object->rank); axis += 1u)
    {
        matches = (shape->shape[axis] == object->extent[axis]);
    }
    if (!matches)
    {
        return hdf5_refuse(file, "a request shape that does not match the dataset");
    }
    if ((request->first > request->past) || (request->past > object->extent[0u]))
    {
        return hdf5_refuse(file, "a row range outside the dataset");
    }
    unsigned long long row = 0ull;
    const unsigned long long rows = request->past - request->first;
    if (!hdf5_product(&object->extent[1u], object->rank - 1u, object->element_bytes, &row) || ((rows != 0ull) && (row > (~0ull / rows))))
    {
        return hdf5_refuse(file, "a row range whose byte size overflows");
    }
    const unsigned long long total = rows * row;
    if (((unsigned long long)(size_t)total != total) || (total > request->out_room) || ((total > 0ull) && (request->out == NULL)))
    {
        return hdf5_refuse(file, "an output buffer too small for the rows asked");
    }
    *bytes = total;
    return 1;
}

static int hdf5_gather_chunks(Hdf5Gather *gather)
{
    const Hdf5Object *const object = gather->object;
    const unsigned int rank = object->rank;
    unsigned long long chunk_bytes = 0ull;
    (void)hdf5_product(object->chunk, rank + 1u, 1ull, &chunk_bytes);
    gather->chunk_bytes = (size_t)chunk_bytes;
    gather->chunk_stride[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        gather->chunk_stride[axis - 1u] = gather->chunk_stride[axis] * object->chunk[axis];
    }
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        const unsigned long long span = object->chunk[axis];
        const unsigned long long bounded = (object->maximum[axis] >= object->extent[axis]) ? object->maximum[axis] : object->extent[axis];
        gather->grid[axis] = (object->extent[axis] / span) + (((object->extent[axis] % span) != 0ull) ? 1ull : 0ull);
        gather->reach[axis] = (bounded / span) + (((bounded % span) != 0ull) ? 1ull : 0ull);
    }
    if (object->chunk_index == HDF5_INDEX_TREE)
    {
        return hdf5_undefined(gather->file, object->data_address) || hdf5_chunk_tree(gather, object->data_address, 0u, 1, 0u);
    }
    return hdf5_chunk_grid(gather);
}

static long long hdf5_gather(Hdf5File *file, const Hdf5Object *object, const EngineArrayRead *request, unsigned long long bytes)
{
    if (bytes == 0ull)
    {
        return 0LL;
    }
    Hdf5Gather gather;
    memset(&gather, 0, sizeof(gather));
    gather.file = file;
    gather.object = object;
    gather.first = request->first;
    gather.past = request->past;
    gather.out = request->out;
    const unsigned int rank = object->rank;
    gather.out_stride[rank - 1u] = 1ull;
    for (unsigned int axis = rank - 1u; axis > 0u; axis -= 1u)
    {
        gather.out_stride[axis - 1u] = gather.out_stride[axis] * object->extent[axis];
    }
    const unsigned long long row_bytes = gather.out_stride[0u] * object->element_bytes;
    const size_t length = (size_t)bytes;
    const unsigned long long fill_bytes = object->has_fill ? object->fill_bytes : object->old_fill_bytes;
    const unsigned char *const fill = object->has_fill ? object->fill : object->old_fill;
    const int unallocated = (object->layout_class == 1u) && hdf5_undefined(file, object->data_address);
    if ((object->layout_class == 2u) || unallocated)
    {
        memset(request->out, 0, length);
        for (size_t element = 0u; (fill_bytes == object->element_bytes) && (element < length); element += object->element_bytes)
        {
            memcpy(&request->out[element], fill, object->element_bytes);
        }
    }
    int good = 1;
    if (object->layout_class == 0u)
    {
        memcpy(request->out, &object->compact[request->first * row_bytes], length);
    }
    else if ((object->layout_class == 1u) && !unallocated)
    {
        good = hdf5_fetch(file, object->data_address + (request->first * row_bytes), bytes, request->out);
    }
    else if (object->layout_class == 2u)
    {
        good = hdf5_gather_chunks(&gather);
    }
    if (!good)
    {
        memset(request->out, 0, length);
        return -1LL;
    }
    if (object->big_endian && (object->element_bytes > 1u))
    {
        hdf5_swap(request->out, length, object->element_bytes);
    }
    return (long long)bytes;
}

long hdf5_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->shape == NULL))
    {
        fprintf(stderr, "hdf5: a describe request with no shape to fill\n");
        return -1L;
    }
    Hdf5File file;
    Hdf5Object object;
    memset(&object, 0, sizeof(object));
    object.compact = NULL;
    unsigned long long address = 0ull;
    int good = hdf5_open(&file, request->path, request->tools);
    good = good && hdf5_locate(&file, request->member, &address);
    good = good && hdf5_object_open(&file, address, &object);
    good = good && hdf5_dataset_check(&file, &object);
    if (good)
    {
        EngineArrayShape *const shape = request->shape;
        memset(shape, 0, sizeof(*shape));
        shape->rank = object.rank;
        for (unsigned int axis = 0u; axis < object.rank; axis += 1u)
        {
            shape->shape[axis] = object.extent[axis];
            shape->axes[axis] = 0;
        }
        shape->element_bytes = object.element_bytes;
        shape->element_kind = object.element_kind;
    }
    hdf5_object_close(&object);
    if (!good)
    {
        hdf5_report(&file);
        return -1L;
    }
    return 0L;
}

long long hdf5_read(const EngineArrayRead *request)
{
    if (request == NULL)
    {
        fprintf(stderr, "hdf5: a read request that is missing\n");
        return -1LL;
    }
    Hdf5File file;
    Hdf5Object object;
    memset(&object, 0, sizeof(object));
    object.compact = NULL;
    unsigned long long address = 0ull;
    unsigned long long bytes = 0ull;
    int good = hdf5_open(&file, request->path, request->tools);
    good = good && hdf5_locate(&file, request->member, &address);
    good = good && hdf5_object_open(&file, address, &object);
    good = good && hdf5_dataset_check(&file, &object);
    good = good && hdf5_request_check(&file, &object, request, &bytes);
    const long long written = good ? hdf5_gather(&file, &object, request, bytes) : -1LL;
    hdf5_object_close(&object);
    if (written < 0LL)
    {
        hdf5_report(&file);
    }
    return written;
}
