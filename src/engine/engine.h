// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ENGINE_H
#define ENGINE_H

#include "engine_config.h"

#include <stddef.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENGINE_REFUSED (-1L)

void engine_percent_of(unsigned long long numerator, unsigned long long denominator, unsigned long long *whole,
                       unsigned long long *tenth);

int engine_order_keys(const void *left, const void *right);

unsigned int engine_sort_unique(unsigned long long *keys, unsigned int count);

void engine_error_read(EngineError *error);

void engine_error_clear(void);

long engine_key_imprint(const EngineStep *steps, unsigned int count, CycleKey **key, EngineError *error);

void engine_key_release(CycleKey *key);

typedef struct
{
    const EngineRecordStep *steps;
    unsigned int count;
    const unsigned int *field_bits;
    const unsigned int *field_offset;
    unsigned int fields;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int members;
    const unsigned int *outputs;
    unsigned int output_count;
    unsigned int *output_offset;
    unsigned int *output_bits;
    const EngineRecordTable *tables;
    unsigned int table_count;
    int reuse;
} EngineRecordRequest;

long engine_record_imprint(const EngineRecordRequest *request, CycleRecord **record, EngineError *error);

typedef struct
{
    const CycleRecord *record;
    const unsigned int *magnitudes[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    unsigned long long count;
    unsigned int *records;
    unsigned long long *sweep_microseconds;
    EngineError *error;
} EngineRecordSweep;

long engine_record_sweep(const EngineRecordSweep *request);

long engine_record_host(const EngineRecordRequest *request, const EngineRecordSweep *sweep);

long engine_residual(const EngineResidualRequest *request, const unsigned int **device_residual);

typedef struct
{
    EngineResidualRequest residual;
    unsigned int room;
    EngineBody *bodies;
    unsigned int *labels;
    unsigned long long *positive_words;
    EngineError *error;
} EngineBodiesRequest;

long engine_frame_bodies(const EngineBodiesRequest *request, EngineLeaves *leaves);

typedef struct
{
    unsigned long long frames;
    unsigned long long held;
    unsigned long long bodies;
    unsigned long long levels;
} EngineBodiesTally;

void engine_bodies_tally(EngineBodiesTally *tally);

typedef struct
{
    unsigned long long frames;
    unsigned long long proved_frames;
    unsigned long long differing_frames;
    unsigned long long differing_lanes;
    unsigned long long key_microseconds;
    unsigned long long sweep_microseconds;
} EngineResidualTally;

void engine_residual_tally(EngineResidualTally *tally);

void engine_group_voxels(const EngineGroupRequest *request);

int engine_directories_make(const char *path, int whole);

int engine_program_directory(char *out, size_t room);

typedef struct
{
    unsigned long long placed;
    unsigned long long source_read;
    unsigned long long crystal_written;
    unsigned long long crystal_read;
    unsigned long long held;
    unsigned long long floors;
    unsigned long long crystal_bytes;
    unsigned long long raw_bytes;
    unsigned long long extent[4];
    EngineSignum root;
    EngineSignum rebuilt_root;
    unsigned long long voxels_differ;
    unsigned long long pixels_differ;
    unsigned long long rows_differ;
    unsigned long long first_row_differ;
    unsigned long long chunks_differ;
    unsigned long long first_chunk_differ;
    unsigned long long roots_differ;
    unsigned long long shape_differ;
    unsigned long long root_rebuilt;
} EngineSampleRecord;

typedef struct
{
    EngineSampleRecord *samples;
    unsigned long long reached;
    unsigned long long held;
    unsigned long long voxels;
    unsigned long long crystal_bytes;
    unsigned long long raw_bytes;
    unsigned long long microseconds;
    EngineSignum set_root;
} EngineSetReport;

typedef struct
{
    const char *set;
    char *const *samples;
    unsigned int count;
    EngineError *error;
    EngineSetReport *report;
} EngineSetRequest;

int engine_sample_path(char *out, size_t room, const char *set, const char *sample, const char *suffix);

typedef struct
{
    const char *path;
    const char *member;
    const char *axes;
    EngineSideBytes *side;
    unsigned long long *lane_offset;
    EngineError *error;
} EngineSourceRequest;

long engine_source_read(const EngineSourceRequest *request, unsigned long long extent[4], unsigned short **volume);

int engine_source_find(const char *source, const char *sample, char *out, size_t room);

long engine_source_lanes(const char *source, const char *sample, unsigned long long *lanes, EngineError *error);

unsigned int engine_source_samples(const char *source, char ***names);

unsigned int engine_set_samples(const char *set, char ***names);

typedef struct
{
    const char *source;
    const char *set;
    char *const *samples;
    unsigned int count;
    const char *axes;
    EngineError *error;
    EngineSetReport *report;
} EngineIngestRequest;

long engine_ingest_set(const EngineIngestRequest *request);

int engine_ingest_print(const EngineIngestRequest *request, FILE *file);

int engine_prove_print(const EngineSetRequest *request, FILE *file);

long engine_iapx_head(const char *set, const char *sample, unsigned long long extent[4], EngineError *error);

typedef struct
{
    unsigned long long nodes;
    unsigned long long edges;
    unsigned long long *node_identity;
    long long *node_place;
    unsigned long long *edge_ends;
} EngineGeff;

long engine_geff_read(const char *path, EngineGeff *geff);

void engine_geff_release(EngineGeff *geff);

long engine_iapx_prove_set(const EngineSetRequest *request);

long engine_iapx_load(const char *set, const char *sample, unsigned long long extent[4], unsigned short **volume,
                      EngineSignum *root, EngineSideBytes *side, EngineError *error);

void engine_side_release(EngineSideBytes *side);

typedef struct
{
    EngineSetRequest set;
    unsigned int keep;
} EngineEntropySetRequest;

long engine_entropy_set(const EngineEntropySetRequest *request);

long engine_entropy_cloud(const char *path, unsigned int *windows, unsigned long long *cloud, EngineError *error);

long engine_entropy_history_read(const char *path, EngineHistory *history, EngineError *error);

void engine_entropy_history_release(EngineHistory *history);

long engine_bodies_write(const char *set, const char *sample, EngineBodyTable *table, EngineError *error);

long engine_bodies_read(const char *set, const char *sample, EngineBodyTable *table, EngineError *error);

void engine_bodies_release(EngineBodyTable *table);

#ifdef __cplusplus
}
#endif

#endif
