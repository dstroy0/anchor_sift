// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the engine_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef ENGINE_INTERNAL_H
#define ENGINE_INTERNAL_H

#include "engine.h"

#include "apxrep.h"
#include "blosc.h"
#include "cfg_json.h"
#include "codegen_device.h"
#include "compression.h"
#include "crc.h"
#include "cycle.h"
#include "deflate.h"
#include "dicom.h"
#include "entropy_history.h"
#include "grow.h"
#include "hdf5.h"
#include "inflate.h"
#include "key_schedule.h"
#include "keymath.h"
#include "lz4.h"
#include "max_tree.h"
#include "nifti.h"
#include "npy.h"
#include "nrrd.h"
#include "obsignatio.h"
#include "residual.h"
#include "scriptura.h"
#include "snappy.h"
#include "stack.h"
#include "tiff.h"
#include "tower.h"
#include "unit_sweep.h"
#include "zarr.h"
#include "zip.h"
#include "zstd.h"

#include <cuda_runtime.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <vector>

#ifdef _WIN32
#define NOMINMAX
#include <direct.h>
#include <io.h>
#include <windows.h>
#define ENGINE_DIRECTORY_MAKE(path_) _mkdir(path_)
#define ENGINE_DIRECTORY_REMOVE(path_) _rmdir(path_)
#else
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#define ENGINE_DIRECTORY_MAKE(path_) mkdir((path_), 0777)
#define ENGINE_DIRECTORY_REMOVE(path_) rmdir(path_)
#endif

void engine_error_keep(const EngineError *error);

#define ENGINE_CHECK(condition_, evacaddr_, error_, kind_)                                                             \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// cudaError_t enumerates non-negative codes below INT_MAX. The status converts to int exactly
#define ENGINE_STATUS_CHECK(call_, evacaddr_, error_)                                                                  \
    engine_status_check((int)(call_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ENGINE_IO(condition_, evacaddr_, error_)                                                                       \
    engine_io_check((condition_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ENTRY_PATH_CAPACITY ENGINE_PATH_CAPACITY

#define ENTRY_CRYSTAL_SUFFIX ".kcr"

extern "C" long engine_key_encode(const EngineStep *steps, unsigned int count, CycleKey **key, EngineError *error);

struct EngineResidualResident
{
    CycleKey *key;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    unsigned short *volume;
    unsigned int *residual;
    unsigned int *check;
    size_t voxels;
};

struct EngineResidualPlanesResident
{
    unsigned int *planes;
    unsigned int *residual;
    size_t plane_words;
    size_t residual_words;
};

int entry_directories_make(const char *path, int include_last, unsigned int *made);

void entry_directories_remove(const char *path, int include_last, unsigned int made);

extern "C" int engine_directories_make(const char *path, int include_last);

extern "C" int engine_sample_path(char *out, size_t capacity, const char *set, const char *sample, const char *suffix);

const EngineIngestTools *entry_ingest_tools(void);

int entry_exists(const char *path);

int entry_is_file(const char *path);

int entry_joined(char *out, size_t capacity, const char *root, const char *leaf);

struct EntryJson
{
    char *text;
    size_t length;
    CfgJsonToken *tokens;
    unsigned int count;
};

void entry_json_release(EntryJson *json);

int entry_json_load(const char *path, EntryJson *json);

unsigned int entry_json_at(const EntryJson *json, unsigned int object, const char *name);

unsigned int entry_json_element(const EntryJson *json, unsigned int array, unsigned int slot);

int entry_json_text(const EntryJson *json, unsigned int token, char *out, size_t capacity);

int entry_json_list(const EntryJson *json, unsigned int array, unsigned long long *values, unsigned int *count,
                    unsigned int capacity);

int entry_element_named(const char *name, EngineArrayExtent *extent, unsigned int *big_endian);

int entry_codec_named(const char *name, EngineCodec *codec);

char entry_axis_named(const char *name);

struct EntryOme
{
    unsigned int rank;
    char axes[ENGINE_ARRAY_RANK];
    char path[256];
};

int entry_ome(const EntryJson *json, unsigned int attributes, EntryOme *ome);

int entry_zarr_describe(const char *root, const char *member, ZarrLayout *layout, char *array_root, size_t capacity);

enum EntrySourceKind
{
    ENTRY_SOURCE_NONE = 0,
    ENTRY_SOURCE_ZARR = 1,
    ENTRY_SOURCE_TIFF = 2,
    ENTRY_SOURCE_HDF5 = 3,
    ENTRY_SOURCE_NPY = 4,
    ENTRY_SOURCE_NRRD = 5,
    ENTRY_SOURCE_NIFTI = 6,
    ENTRY_SOURCE_STACK = 7,
    ENTRY_SOURCE_DICOM = 8,
    ENTRY_SOURCE_NO_MEMBER = 9
};

struct EntrySource
{
    EntrySourceKind kind;
    char path[ENTRY_PATH_CAPACITY];
    const char *member;
    ZarrLayout layout;
    EngineArrayExtent extent;
};

int entry_ends(const char *path, const char *suffix);

extern "C" long engine_source_read(const EngineSourceRequest *request, unsigned long long extent[4],
                                   unsigned short **volume);

#define ENTRY_SOURCE_SUFFIX_COUNT 18u

extern const char *const ENTRY_SOURCE_SUFFIXES[ENTRY_SOURCE_SUFFIX_COUNT];

extern "C" int engine_source_find(const char *source, const char *sample, char *out, size_t capacity);

unsigned long long entry_lanes(const unsigned long long extent[4]);

int entry_iapx_decode(const EngineStream *stream, const unsigned short *device_lanes, unsigned short *rebuilt,
                      unsigned long long *mismatches, const unsigned short **device_rebuilt, EngineError *error);

int entry_iapx_encode(const unsigned short *device_lanes, const unsigned long long extent[4], EngineStream *stream,
                      unsigned int *floors, EngineError *error);

int entry_side_pack(EngineSideSection *section, EngineError *error);

int entry_side_same(const EngineSideBytes *one, const EngineSideBytes *other);

static_assert(OBSIGNATIO_SIGNUM_BYTES == ENGINE_SIGNUM_BYTES, "the engine's signum is obsignatio's");

int entry_signum_same(const EngineSignum *one, const EngineSignum *other);

int entry_seal_make(const unsigned short *device_lanes, const EngineStream *stream, const EngineSideSection *section,
                    EngineSeal *seal, EngineError *error);

int entry_crystal_verify(const EngineStream *file, EngineSideSection *section, const EngineSeal *seal,
                         const unsigned short *device_source, unsigned short *rebuilt, EngineSampleRecord *record,
                         EngineError *error);

int entry_set_root(const EngineSignum *roots, unsigned long long count, EngineSignum *root, EngineError *error);

#define ENTRY_ROW_TEXT 640u

void entry_signum_text(ScripturaLine *line, const EngineSignum *signum);

void entry_percent(ScripturaLine *line, unsigned long long part, unsigned long long total);

unsigned long long entry_report_capacity(char *const *samples, unsigned long long reached, const char *source,
                                         const char *set);

void entry_report_total(ScripturaLine *line, const EngineSetReport *report, unsigned int count);

void entry_seal_failure(ScripturaLine *line, const EngineSampleRecord *record);

extern "C" long engine_iapx_load(const char *set, const char *sample, unsigned long long extent[4],
                                 unsigned short **volume, EngineSignum *root, EngineSideBytes *side,
                                 EngineError *error);

#endif
