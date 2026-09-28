// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the hdf5_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef HDF5_INTERNAL_H
#define HDF5_INTERNAL_H

#include "hdf5.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HDF5_REASON_CAPACITY 256u
#define HDF5_PATH_CAPACITY ENGINE_PATH_CAPACITY
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
#define HDF5_RECORD_CAPACITY 64u

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
    char reason[HDF5_REASON_CAPACITY];
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
    char unsupported[HDF5_REASON_CAPACITY];
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

typedef Hdf5Walk (*Hdf5MessageVisit)(Hdf5File *file, void *state, unsigned int type, unsigned int flags,
                                     const unsigned char *body, size_t size);

typedef Hdf5Walk (*Hdf5LinkVisit)(Hdf5File *file, void *state, const unsigned char *name, size_t name_length,
                                  unsigned int link_type, unsigned long long address);

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
    unsigned char run[HDF5_RUN_RECORDS][HDF5_RECORD_CAPACITY];
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
    char path[HDF5_PATH_CAPACITY];
    unsigned long long *seen;
    size_t seen_count;
    size_t seen_capacity;
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
    unsigned long long end;
    unsigned char *out;
    size_t chunk_bytes;
    unsigned long long out_stride[ENGINE_ARRAY_RANK];
    unsigned long long chunk_stride[ENGINE_ARRAY_RANK];
    unsigned long long grid[ENGINE_ARRAY_RANK];
    unsigned long long range[ENGINE_ARRAY_RANK];
    int keyed;
    unsigned long long last_key[ENGINE_ARRAY_RANK + 1u];
} Hdf5Gather;

int hdf5_refuse(Hdf5File *file, const char *reason);

int hdf5_refuse_number(Hdf5File *file, const char *reason, unsigned long long number);

Hdf5Walk hdf5_walk_refuse(Hdf5File *file, const char *reason);

void hdf5_report(const Hdf5File *file);

unsigned long long hdf5_little(const unsigned char *bytes, unsigned int width);

unsigned long long hdf5_big(const unsigned char *bytes, unsigned int width);

unsigned long long hdf5_take(Hdf5Cursor *cursor, unsigned int width);

const unsigned char *hdf5_span(Hdf5Cursor *cursor, unsigned long long width);

unsigned int hdf5_log2(unsigned long long value);

int hdf5_power_of_two(unsigned long long value);

unsigned long long hdf5_all_ones(unsigned int width);

int hdf5_undefined(const Hdf5File *file, unsigned long long address);

int hdf5_product(const unsigned long long *values, unsigned int count, unsigned long long start,
                 unsigned long long *product);

uint32_t hdf5_lookup3(const unsigned char *bytes, size_t length);

int hdf5_sealed(const unsigned char *bytes, size_t length);

uint32_t hdf5_fletcher32(const unsigned char *bytes, size_t length);

unsigned long long hdf5_bytes_remaining(const Hdf5File *file, unsigned long long address);

int hdf5_fetch(Hdf5File *file, unsigned long long address, unsigned long long bytes, unsigned char *out);

unsigned char *hdf5_load(Hdf5File *file, unsigned long long address, unsigned long long bytes);

int hdf5_open(Hdf5File *file, const char *path, const EngineIngestTools *tools);

Hdf5Walk hdf5_header_walk(Hdf5File *file, unsigned long long address, Hdf5MessageVisit visit, void *state);

void hdf5_object_unsupported(Hdf5Object *object, const char *reason, unsigned long long number);

Hdf5Walk hdf5_object_space(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor);

Hdf5Walk hdf5_object_type(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor);

Hdf5Walk hdf5_object_fill(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, int old);

Hdf5Walk hdf5_object_chunking(Hdf5File *file, Hdf5Object *object, Hdf5Cursor *cursor, unsigned int version);

void hdf5_object_close(Hdf5Object *object);

int hdf5_object_open(Hdf5File *file, unsigned long long address, Hdf5Object *object);

Hdf5Walk hdf5_link_decode(Hdf5File *file, const unsigned char *body, size_t size, Hdf5LinkVisit visit, void *state);

Hdf5Walk hdf5_group_message(Hdf5File *file, void *state, unsigned int type, unsigned int flags,
                            const unsigned char *body, size_t size);

Hdf5Walk hdf5_table_links(Hdf5File *file, Hdf5GroupWalk *walk);

Hdf5Walk hdf5_dense_links(Hdf5File *file, const Hdf5GroupWalk *walk);

int hdf5_locate(Hdf5File *file, const char *member, unsigned long long *address);

int hdf5_dataset_check(Hdf5File *file, const Hdf5Object *object);

int hdf5_chunk_place(Hdf5Gather *gather, const unsigned long long *origin, unsigned long long address,
                     unsigned long long stored, unsigned int mask);

int hdf5_chunk_tree(Hdf5Gather *gather, unsigned long long address, unsigned int level, int root, unsigned int depth);

void hdf5_fixed_close(Hdf5Fixed *fixed);

int hdf5_fixed_open(Hdf5File *file, const Hdf5Object *object, const Hdf5Gather *gather, Hdf5Fixed *fixed);

int hdf5_fixed_entry(Hdf5File *file, Hdf5Fixed *fixed, unsigned long long linear, unsigned long long *address,
                     unsigned long long *stored, unsigned int *mask);

#endif
