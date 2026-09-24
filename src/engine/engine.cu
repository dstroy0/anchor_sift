// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "engine.h"

#include "blosc.h"
#include "cfg_json.h"
#include "compression.h"
#include "crc.h"
#include "cycle.h"
#include "entropy_history.h"
#include "key_schedule.h"
#include "grow.h"
#include "hdf5.h"
#include "deflate.h"
#include "inflate.h"
#include "keymath.h"
#include "krep.h"
#include "lz4.h"
#include "max_tree.h"
#include "nifti.h"
#include "dicom.h"
#include "npy.h"
#include "scriptura.h"
#include "zip.h"
#include "nrrd.h"
#include "obsignatio.h"
#include "residual.h"
#include "snappy.h"
#include "stack.h"
#include "tiff.h"
#include "tower.h"
#include "unit_sweep.h"
#include "zarr.h"
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

extern "C" void engine_percent_of(unsigned long long numerator, unsigned long long denominator,
                                  unsigned long long *whole, unsigned long long *tenth)
{
    const unsigned long long scaled = (numerator * 1000ULL * 2ULL + denominator) / (2ULL * denominator);
    *whole = scaled / 10ULL;
    *tenth = scaled % 10ULL;
}

extern "C" int engine_order_keys(const void *left, const void *right)
{
    const unsigned long long first = *(const unsigned long long *)left;
    const unsigned long long second = *(const unsigned long long *)right;
    return (first < second) ? -1 : ((first > second) ? 1 : 0);
}

extern "C" unsigned int engine_sort_unique(unsigned long long *keys, unsigned int count)
{
    if (count == 0u)
    {
        return 0u;
    }
    qsort(keys, count, sizeof(unsigned long long), engine_order_keys);
    unsigned int kept = 1u;
    for (unsigned int position = 1u; position < count; position += 1u)
    {
        if (keys[position] != keys[kept - 1u])
        {
            keys[kept] = keys[position];
            kept += 1u;
        }
    }
    return kept;
}

static EngineError s_engine_error;

static void engine_error_keep(const EngineError *error)
{
    if ((error->kind != ENGINE_ERROR_NONE) && (s_engine_error.kind == ENGINE_ERROR_NONE))
    {
        s_engine_error = *error;
    }
}

extern "C" void engine_error_read(EngineError *error)
{
    *error = s_engine_error;
}

extern "C" void engine_error_clear(void)
{
    memset(&s_engine_error, 0, sizeof(s_engine_error));
}

#define ENGINE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define ENGINE_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ENGINE_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_ENGINE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ENTRY_PATH_ROOM ENGINE_PATH_ROOM

#define ENTRY_CRYSTAL_SUFFIX ".kcr"

#define ENTRY_NOISE_FLOOR_SUFFIX ".knf"

#define ENTRY_CONSTRUCTION_SET_SUFFIX ".kcs"

extern "C" long engine_key_imprint(const EngineStep *steps, unsigned int count, CycleKey **key, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    if (!ENGINE_HELD(key != NULL, &key, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    *key = NULL;
    EngineKey math;
    const KeymathImprintRequest imprint = {steps, count, &math, error};
    if (!ENGINE_HELD(keymath_imprint(&imprint) != KEYMATH_REFUSED, steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    EngineKeyLayout layout;
    const long laid = key_schedule_lay(&math, &layout, error);
    keymath_key_release(&math);
    if (!ENGINE_HELD(laid != KEY_SCHEDULE_REFUSED, steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    const long bits = cycle_key_load(&layout, key, error);
    key_schedule_release(&layout);
    return (bits == CYCLE_REFUSED) ? ENGINE_REFUSED : bits;
}

extern "C" void engine_key_release(CycleKey *key)
{
    cycle_key_release(key);
}

extern "C" long engine_record_imprint(const EngineRecordRequest *request, CycleRecord **record, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    if (!ENGINE_HELD((request != NULL) && (record != NULL), request, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    *record = NULL;
    EngineRecordKey math;
    const KeymathRecordRequest imprint = {request->steps,   request->count,       request->field_bits,
                                          request->fields,  request->members,     request->outputs,
                                          request->output_count, request->tables, request->table_count,
                                          &math,            error};
    if (!ENGINE_HELD(keymath_record_imprint(&imprint) != KEYMATH_REFUSED, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    EngineRecordLayout layout;
    const KeyScheduleRecordRequest lay = {&math,           request->field_offset, request->fields, request->in_limbs,
                                          request->reuse,  &layout,               error};
    const long laid = key_schedule_record_lay(&lay);
    keymath_record_release(&math);
    if (!ENGINE_HELD(laid != KEY_SCHEDULE_REFUSED, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    for (unsigned int output = 0u; (request->output_offset != NULL) && (request->output_bits != NULL)
         && (output < request->output_count); output += 1u)
    {
        request->output_offset[output] = layout.step_table[request->outputs[output]].out_offset;
        request->output_bits[output] = layout.step_table[request->outputs[output]].out_bits;
    }
    const long bits = cycle_record_load(&layout, record, error);
    key_schedule_record_release(&layout);
    return (bits == CYCLE_REFUSED) ? ENGINE_REFUSED : bits;
}

extern "C" long engine_record_host(const EngineRecordRequest *request, const EngineRecordSweep *sweep)
{
    if ((sweep == NULL) || (sweep->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = sweep->error;
    if (!ENGINE_HELD(request != NULL, request, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    EngineRecordKey math;
    const KeymathRecordRequest imprint = {request->steps,   request->count,       request->field_bits,
                                          request->fields,  request->members,     request->outputs,
                                          request->output_count, request->tables, request->table_count,
                                          &math,            error};
    if (!ENGINE_HELD(keymath_record_imprint(&imprint) != KEYMATH_REFUSED, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    EngineRecordLayout layout;
    const KeyScheduleRecordRequest lay = {&math,           request->field_offset, request->fields, request->in_limbs,
                                          request->reuse,  &layout,               error};
    const long laid = key_schedule_record_lay(&lay);
    keymath_record_release(&math);
    if (!ENGINE_HELD(laid != KEY_SCHEDULE_REFUSED, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    CycleRecordHostRequest run;
    memset(&run, 0, sizeof(run));
    run.layout = &layout;
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        run.in[member] = sweep->magnitudes[member];
        run.bodies[member] = sweep->bodies[member];
    }
    run.index = sweep->index;
    run.count = sweep->count;
    run.out = sweep->records;
    const long ran = cycle_record_run_host(&run);
    key_schedule_record_release(&layout);
    return ENGINE_HELD(ran != CYCLE_REFUSED, sweep->records, error, ENGINE_ERROR_REQUEST) ? ran : ENGINE_REFUSED;
}

extern "C" long engine_record_sweep(const EngineRecordSweep *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    const unsigned int members = cycle_record_members(request->record);
    const size_t index_words = (request->index != NULL) ? (size_t)request->count * members : 0u;
    const size_t out_words = (size_t)request->count * cycle_record_out_limbs(request->record);
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.error = error;
    unsigned int *device_in[ENGINE_RECORD_MEMBERS_MAX];
    memset(device_in, 0, sizeof(device_in));
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    int good = ENGINE_HELD((members != 0u) && (out_words != 0u) && (request->sweep_microseconds != NULL), request,
                           error, ENGINE_ERROR_REQUEST)
            && ENGINE_TOOK(cudaMalloc((void **)&device_out, out_words * sizeof(unsigned int)), &device_out, error);
    for (unsigned int member = 0u; good && (member < members); member += 1u)
    {
        const unsigned int in_limbs = cycle_record_in_limbs(request->record, member);
        unsigned int shared = member;
        for (unsigned int earlier = 0u; earlier < member; earlier += 1u)
        {
            const int same = (request->magnitudes[earlier] == request->magnitudes[member])
                          && (request->bodies[earlier] == request->bodies[member])
                          && (cycle_record_in_limbs(request->record, earlier) == in_limbs);
            shared = ((shared == member) && (same != 0)) ? earlier : shared;
        }
        const size_t in_words = (size_t)request->bodies[member] * in_limbs;
        good = (shared != member)
            || (ENGINE_HELD(in_words != 0u, &request->bodies[member], error, ENGINE_ERROR_REQUEST)
                && ENGINE_TOOK(cudaMalloc((void **)&device_in[member], in_words * sizeof(unsigned int)),
                               &device_in[member], error)
                && ENGINE_TOOK(cudaMemcpy(device_in[member], request->magnitudes[member], in_words * sizeof(unsigned int),
                                          cudaMemcpyHostToDevice),
                               device_in[member], error));
        run.device_in[member] = (shared != member) ? run.device_in[shared] : device_in[member];
        run.bodies[member] = request->bodies[member];
    }
    if (good && (index_words != 0u))
    {
        good = ENGINE_TOOK(cudaMalloc((void **)&device_index, index_words * sizeof(unsigned int)), &device_index, error)
            && ENGINE_TOOK(cudaMemcpy(device_index, request->index, index_words * sizeof(unsigned int),
                                      cudaMemcpyHostToDevice),
                           device_index, error);
    }
    good = good && ENGINE_TOOK(cudaDeviceSynchronize(), device_out, error);
    const unsigned long long started = engine_clock_microseconds();
    run.record = request->record;
    run.device_index = device_index;
    run.count = request->count;
    run.device_out = device_out;
    good = good && (cycle_record_run(&run) == (long)request->count);
    *request->sweep_microseconds = engine_clock_microseconds() - started;
    good = good
        && ENGINE_TOOK(cudaMemcpy(request->records, device_out, out_words * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                       request->records, error);
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        cudaFree(device_in[member]);
    }
    cudaFree(device_index);
    cudaFree(device_out);
    return (good != 0) ? (long)request->count : ENGINE_REFUSED;
}

struct EngineResidualHeld
{
    CycleKey *key;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    unsigned short *volume;
    unsigned int *residual;
    unsigned int *check;
    size_t voxels;
};

static EngineResidualHeld s_residual_held;

static EngineResidualTally s_residual_tally;

static int engine_residual_key(const EngineResidualRequest *request)
{
    EngineResidualHeld *const held = &s_residual_held;
    EngineError *const error = request->error;
    if ((held->key != NULL)
     && (memcmp(held->smooth_orders, request->smooth_orders, sizeof(held->smooth_orders)) == 0)
     && (memcmp(held->background_orders, request->background_orders, sizeof(held->background_orders)) == 0))
    {
        return 1;
    }
    cycle_key_release(held->key);
    held->key = NULL;
    EngineStep program[RESIDUAL_STEPS];
    if (!ENGINE_HELD(residual_program(request, program) != RESIDUAL_REFUSED, request->smooth_orders, error,
                     ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    CycleKey *key = NULL;
    const long bits = engine_key_imprint(program, RESIDUAL_STEPS, &key, error);
    // bits is checked non-negative before it re-signs to unsigned long
    const int imprinted = ENGINE_HELD(bits >= 0L, program, error, ENGINE_ERROR_REQUEST)
                       && ENGINE_HELD((unsigned long)bits <= (32ul * ENGINE_RESIDUAL_LIMBS), request->background_orders,
                                      error, ENGINE_ERROR_REQUEST);
    if (imprinted == 0)
    {
        cycle_key_release(key);
        return 0;
    }
    held->key = key;
    memcpy(held->smooth_orders, request->smooth_orders, sizeof(held->smooth_orders));
    memcpy(held->background_orders, request->background_orders, sizeof(held->background_orders));
    return 1;
}

static int engine_residual_hold(size_t voxels, EngineError *error)
{
    EngineResidualHeld *const held = &s_residual_held;
    if (held->voxels == voxels)
    {
        return 1;
    }
    cudaFree(held->volume);
    cudaFree(held->residual);
    cudaFree(held->check);
    held->volume = NULL;
    held->residual = NULL;
    held->check = NULL;
    held->voxels = 0u;
    const int ok = ENGINE_TOOK(cudaMalloc((void **)&held->volume, voxels * sizeof(unsigned short)), &held->volume, error)
                && ENGINE_TOOK(cudaMalloc((void **)&held->residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                               &held->residual, error)
                && ENGINE_TOOK(cudaMalloc((void **)&held->check, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                               &held->check, error);
    held->voxels = (ok != 0) ? voxels : 0u;
    return ok;
}

extern "C" long engine_residual(const EngineResidualRequest *request, const unsigned int **device_residual)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!ENGINE_HELD(device_residual != NULL, &device_residual, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_REFUSED;
    }
    *device_residual = NULL;
    const int asked = ENGINE_HELD(request->volume != NULL, &request->volume, error, ENGINE_ERROR_REQUEST)
                   && ENGINE_HELD((request->depth != 0u) && (request->height != 0u) && (request->width != 0u),
                                  &request->depth, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return ENGINE_REFUSED;
    }
    const unsigned long long plane_voxels = (unsigned long long)request->height * request->width;
    const unsigned long long voxels = (plane_voxels <= 0xFFFFFFFFull) ? (plane_voxels * request->depth) : 0ull;
    const int sized = ENGINE_HELD((voxels != 0ull) && (voxels <= (0xFFFFFFFFull / ENGINE_RESIDUAL_LIMBS)),
                                  &request->depth, error, ENGINE_ERROR_REQUEST)
                   && engine_residual_key(request);
    if (sized == 0)
    {
        return ENGINE_REFUSED;
    }
    EngineResidualHeld *const held = &s_residual_held;
    int steps_succeeded = engine_residual_hold((size_t)voxels, error)
                       && ENGINE_TOOK(cudaMemcpy(held->volume, request->volume, (size_t)voxels * sizeof(unsigned short),
                                                 cudaMemcpyHostToDevice),
                                      held->volume, error);
    Atom atom;
    memset(&atom, 0, sizeof(atom));
    atom.lanes = held->volume;
    atom.depth = request->depth;
    atom.height = request->height;
    atom.width = request->width;
    CycleRunRequest cycle_request;
    memset(&cycle_request, 0, sizeof(cycle_request));
    cycle_request.key = held->key;
    cycle_request.atoms = &atom;
    cycle_request.count = 1ull;
    cycle_request.limbs = ENGINE_RESIDUAL_LIMBS;
    cycle_request.device_out = held->residual;
    cycle_request.error = error;
    UnitSweepRequest sweep_request;
    memset(&sweep_request, 0, sizeof(sweep_request));
    sweep_request.device_volume = held->volume;
    sweep_request.depth = request->depth;
    sweep_request.height = request->height;
    sweep_request.width = request->width;
    memcpy(sweep_request.smooth_orders, request->smooth_orders, sizeof(sweep_request.smooth_orders));
    memcpy(sweep_request.background_orders, request->background_orders, sizeof(sweep_request.background_orders));
    sweep_request.limbs = ENGINE_RESIDUAL_LIMBS;
    sweep_request.device_out = (request->unit_sweep == ENGINE_RESIDUAL_BOTH_PROVED) ? held->check : held->residual;
    sweep_request.error = error;
    const int key_runs = (request->unit_sweep != ENGINE_RESIDUAL_BY_UNIT_SWEEP) ? 1 : 0;
    const int sweep_runs = (request->unit_sweep != ENGINE_RESIDUAL_BY_KEY) ? 1 : 0;
    const int proving = (request->unit_sweep == ENGINE_RESIDUAL_BOTH_PROVED) ? 1 : 0;
    steps_succeeded = steps_succeeded && ENGINE_TOOK(cudaDeviceSynchronize(), held->volume, error);
    const unsigned long long key_started = engine_clock_microseconds();
    steps_succeeded = steps_succeeded
                   && ((key_runs == 0)
                       || (ENGINE_HELD(cycle_run(&cycle_request) == 1L, held->key, error, ENGINE_ERROR_RESOURCE)
                           && ENGINE_TOOK(cudaDeviceSynchronize(), held->residual, error)));
    const unsigned long long sweep_started = engine_clock_microseconds();
    steps_succeeded = steps_succeeded
                   && ((sweep_runs == 0)
                       || (ENGINE_HELD(unit_sweep_residual(&sweep_request) == 0L, sweep_request.device_out, error,
                                       ENGINE_ERROR_RESOURCE)
                           && ENGINE_TOOK(cudaDeviceSynchronize(), sweep_request.device_out, error)));
    const unsigned long long sweep_finished = engine_clock_microseconds();
    unsigned long long differing_lanes = 0ull;
    const UnitSweepComparison comparison = {held->residual, held->check, voxels, ENGINE_RESIDUAL_LIMBS,
                                            &differing_lanes, error};
    steps_succeeded = steps_succeeded
                   && ((proving == 0)
                       || ENGINE_HELD(unit_sweep_lanes_compare(&comparison) == 0L, held->check, error,
                                      ENGINE_ERROR_RESOURCE));
    if (steps_succeeded && (proving != 0))
    {
        s_residual_tally.proved_frames += 1ull;
        s_residual_tally.differing_frames += (differing_lanes != 0ull) ? 1ull : 0ull;
        s_residual_tally.differing_lanes += differing_lanes;
        steps_succeeded = ENGINE_HELD(differing_lanes == 0ull, held->check, error, ENGINE_ERROR_LOGIC);
    }
    if (steps_succeeded == 0)
    {
        cudaFree(held->volume);
        cudaFree(held->residual);
        cudaFree(held->check);
        held->volume = NULL;
        held->residual = NULL;
        held->check = NULL;
        held->voxels = 0u;
        return ENGINE_REFUSED;
    }
    s_residual_tally.frames += 1ull;
    s_residual_tally.key_microseconds += (key_runs != 0) ? (sweep_started - key_started) : 0ull;
    s_residual_tally.sweep_microseconds += (sweep_runs != 0) ? (sweep_finished - sweep_started) : 0ull;
    *device_residual = held->residual;
    return 0L;
}

static EngineBodiesTally s_bodies_tally;

extern "C" long engine_frame_bodies(const EngineBodiesRequest *request, EngineLeaves *leaves)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    if (ENGINE_HELD(leaves != NULL, &leaves, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    memset(leaves, 0, sizeof(*leaves));
    const unsigned int *device_residual = NULL;
    EngineResidualRequest residual = request->residual;
    residual.error = error;
    if (ENGINE_HELD(engine_residual(&residual, &device_residual) == 0L, &request->residual, error,
                    ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    unsigned int level_code = 0u;
    unsigned int held = 0u;
    MaxTreeObjectsRequest objects;
    memset(&objects, 0, sizeof(objects));
    objects.error = error;
    objects.device_residual = device_residual;
    objects.depth = request->residual.depth;
    objects.height = request->residual.height;
    objects.width = request->residual.width;
    objects.room = request->room;
    objects.bodies = request->bodies;
    objects.labels = request->labels;
    objects.positive_words = request->positive_words;
    objects.level_code = &level_code;
    objects.proof_held = &held;
    const long count = max_tree_objects(&objects);
    const int grown = (count >= 0L)
                   && ENGINE_HELD(grow_leaves(request->bodies, (unsigned int)count, leaves, error) != GROW_REFUSED, leaves,
                                  error, ENGINE_ERROR_REQUEST);
    if (grown == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    s_bodies_tally.frames += 1ull;
    s_bodies_tally.held += (unsigned long long)held;
    s_bodies_tally.bodies += (unsigned long long)count;
    s_bodies_tally.levels += (unsigned long long)level_code;
    return count;
}

extern "C" void engine_bodies_tally(EngineBodiesTally *tally)
{
    *tally = s_bodies_tally;
}

extern "C" void engine_residual_tally(EngineResidualTally *tally)
{
    *tally = s_residual_tally;
}

extern "C" void engine_group_voxels(const EngineGroupRequest *request)
{
    grow_group_voxels(request);
}

static int entry_directory_end(const char *walk, size_t at, size_t length, int whole)
{
    const int separator = (walk[at] == '/') || (walk[at] == '\\');
    const int last = (at == length) && (whole != 0);
    const int drive = (at == 2u) && (walk[1] == ':');
    return ((separator != 0) || (last != 0)) && (drive == 0);
}

static int entry_directories_make(const char *path, int whole, unsigned int *made)
{
    *made = 0u;
    const size_t length = strlen(path);
    char *const walk = (char *)malloc(length + 1u);
    if (walk == NULL)
    {
        return 0;
    }
    memcpy(walk, path, length + 1u);
    int good = 1;
    for (size_t at = 1u; good && (at <= length); at += 1u)
    {
        if (entry_directory_end(walk, at, length, whole) == 0)
        {
            continue;
        }
        const char held = walk[at];
        walk[at] = '\0';
        const int created = ENGINE_DIRECTORY_MAKE(walk) == 0;
        good = created || (errno == EEXIST);
        *made += created ? 1u : 0u;
        walk[at] = held;
    }
    free(walk);
    return good;
}

static void entry_directories_remove(const char *path, int whole, unsigned int made)
{
    if (made == 0u)
    {
        return;
    }
    const size_t length = strlen(path);
    char *const walk = (char *)malloc(length + 1u);
    if (walk == NULL)
    {
        return;
    }
    memcpy(walk, path, length + 1u);
    unsigned int left = made;
    for (size_t at = length; (left != 0u) && (at >= 1u); at -= 1u)
    {
        if (entry_directory_end(walk, at, length, whole) == 0)
        {
            continue;
        }
        walk[at] = '\0';
        ENGINE_DIRECTORY_REMOVE(walk);
        left -= 1u;
    }
    free(walk);
}

extern "C" int engine_directories_make(const char *path, int whole)
{
    unsigned int made = 0u;
    return entry_directories_make(path, whole, &made);
}

extern "C" int engine_program_directory(char *out, size_t room)
{
    if ((out == NULL) || (room < 2u))
    {
        return 0;
    }
#ifdef _WIN32
    // the room is a buffer size the caller holds, which a DWORD counts on every Windows target
    const DWORD written = GetModuleFileNameA(NULL, out, (DWORD)room);
    const size_t length = (size_t)written;
#else
    const ssize_t written = readlink("/proc/self/exe", out, room - 1u);
    // a failed read is -1 and is held as no length at all
    const size_t length = (written > 0) ? (size_t)written : 0u;
#endif
    size_t cut = (length < room) ? length : 0u;
    out[cut] = '\0';
    while ((cut != 0u) && (out[cut - 1u] != '/') && (out[cut - 1u] != '\\'))
    {
        cut -= 1u;
    }
    if (cut == 0u)
    {
        out[0] = '\0';
        return 0;
    }
    out[cut - 1u] = '\0';
    return 1;
}

extern "C" int engine_sample_path(char *out, size_t room, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(out, room, "%s/%s/%s%s", set, sample, sample, suffix);
    return (written > 0) && ((size_t)written < room);
}

static long long entry_raw_decode(const EngineBytesRequest *request)
{
    if ((request == NULL) || (request->in_bytes > request->out_room))
    {
        return ENGINE_BYTES_REFUSED;
    }
    memcpy(request->out, request->in, (size_t)request->in_bytes);
    return (long long)request->in_bytes;
}

static EngineIngestTools s_ingest_tools;

static long long entry_blosc_decode(const EngineBytesRequest *request)
{
    BloscDecodeRequest blosc;
    blosc.bytes = *request;
    blosc.decode = s_ingest_tools.decode;
    return blosc_decode(&blosc);
}

static const EngineIngestTools *entry_ingest_tools(void)
{
    EngineIngestTools *const tools = &s_ingest_tools;
    tools->decode[ENGINE_CODEC_RAW] = entry_raw_decode;
    tools->decode[ENGINE_CODEC_ZSTD] = zstd_decode;
    tools->decode[ENGINE_CODEC_ZLIB] = inflate_zlib_decode;
    tools->decode[ENGINE_CODEC_GZIP] = inflate_gzip_decode;
    tools->decode[ENGINE_CODEC_DEFLATE] = inflate_raw_decode;
    tools->decode[ENGINE_CODEC_LZ4] = lz4_block_decode;
    tools->decode[ENGINE_CODEC_LZ4_FRAME] = lz4_frame_decode;
    tools->decode[ENGINE_CODEC_SNAPPY] = snappy_decode;
    tools->decode[ENGINE_CODEC_BLOSCLZ] = blosclz_decode;
    tools->decode[ENGINE_CODEC_BLOSC] = entry_blosc_decode;
    tools->decode[ENGINE_CODEC_LZ4_SIZED] = lz4_numcodecs_decode;
    tools->read = stack_file_read;
    tools->size = stack_file_size;
    return tools;
}

static int entry_exists(const char *path)
{
#ifdef _WIN32
    return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
#else
    struct stat status;
    return stat(path, &status) == 0;
#endif
}

static int entry_is_file(const char *path)
{
#ifdef _WIN32
    const DWORD attributes = GetFileAttributesA(path);
    return (attributes != INVALID_FILE_ATTRIBUTES) && ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0u);
#else
    struct stat status;
    return (stat(path, &status) == 0) && S_ISREG(status.st_mode);
#endif
}

static int entry_joined(char *out, size_t room, const char *root, const char *leaf)
{
    const int written = snprintf(out, room, "%s/%s", root, leaf);
    return (written > 0) && ((size_t)written < room);
}

struct EntryJson
{
    char *text;
    size_t length;
    CfgJsonToken *tokens;
    unsigned int count;
};

static void entry_json_release(EntryJson *json)
{
    free(json->text);
    free(json->tokens);
    memset(json, 0, sizeof(*json));
}

static int entry_file_whole(const char *path, char **bytes, size_t *length)
{
    const long long size = stack_file_size(path);
    if (size < 0ll)
    {
        return 0;
    }
    char *const held = (char *)malloc((size_t)size + 1u);
    EngineFileRange range;
    range.path = path;
    range.offset = 0ull;
    range.bytes = (unsigned long long)size;
    range.out = (unsigned char *)held;
    if ((held == NULL) || (stack_file_read(&range) != size))
    {
        free(held);
        return 0;
    }
    held[size] = '\0';
    *bytes = held;
    *length = (size_t)size;
    return 1;
}

static int entry_json_load(const char *path, EntryJson *json)
{
    memset(json, 0, sizeof(*json));
    if (entry_file_whole(path, &json->text, &json->length) == 0)
    {
        return 0;
    }
    const unsigned int room = (unsigned int)(json->length / 2u) + 4u;
    json->tokens = (CfgJsonToken *)malloc((size_t)room * sizeof(CfgJsonToken));
    CfgJsonParse parse;
    memset(&parse, 0, sizeof(parse));
    const int good = (json->tokens != NULL)
                  && cfg_json_parse_metadata(json->text, json->length, json->tokens, room, &parse)
                  && (json->tokens[0].kind == CFG_JSON_OBJECT);
    if (good == 0)
    {
        fprintf(stderr, "  %s: %s\n", path, (parse.reason != NULL) ? parse.reason : "not one JSON object");
        entry_json_release(json);
        return 0;
    }
    json->count = parse.tokens;
    return 1;
}

static unsigned int entry_json_at(const EntryJson *json, unsigned int object, const char *name)
{
    const int held = (object < json->count) && (json->tokens[object].kind == CFG_JSON_OBJECT);
    return (held != 0) ? cfg_json_member(json->text, json->tokens, object, name) : 0u;
}

static unsigned int entry_json_element(const EntryJson *json, unsigned int array, unsigned int slot)
{
    if ((array == 0u) || (array >= json->count) || (json->tokens[array].kind != CFG_JSON_ARRAY)
     || (slot >= json->tokens[array].count))
    {
        return 0u;
    }
    unsigned int at = array + 1u;
    for (unsigned int step = 0u; step < slot; step += 1u)
    {
        at = json->tokens[at].past;
    }
    return at;
}

static int entry_json_text(const EntryJson *json, unsigned int token, char *out, size_t room)
{
    return (token != 0u) && cfg_json_string(json->text, &json->tokens[token], out, room);
}

static int entry_json_list(const EntryJson *json, unsigned int array, unsigned long long *values, unsigned int *count,
                           unsigned int room)
{
    if ((array == 0u) || (json->tokens[array].kind != CFG_JSON_ARRAY) || (json->tokens[array].count > room))
    {
        return 0;
    }
    *count = json->tokens[array].count;
    int good = 1;
    for (unsigned int slot = 0u; good && (slot < *count); slot += 1u)
    {
        good = cfg_json_unsigned(json->text, &json->tokens[entry_json_element(json, array, slot)], &values[slot]);
    }
    return good;
}

static int entry_element_named(const char *name, EngineArrayShape *shape, unsigned int *big_endian)
{
    static const char *const NAMES[10] = {"uint8", "uint16", "uint32", "uint64", "int8",
                                          "int16", "int32", "int64", "float32", "float64"};
    static const unsigned int BYTES[10] = {1u, 2u, 4u, 8u, 1u, 2u, 4u, 8u, 4u, 8u};
    static const EngineElementKind KINDS[10] = {ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_UNSIGNED,
                                                ENGINE_ELEMENT_UNSIGNED, ENGINE_ELEMENT_SIGNED, ENGINE_ELEMENT_SIGNED,
                                                ENGINE_ELEMENT_SIGNED, ENGINE_ELEMENT_SIGNED, ENGINE_ELEMENT_FLOAT,
                                                ENGINE_ELEMENT_FLOAT};
    for (unsigned int slot = 0u; slot < 10u; slot += 1u)
    {
        if (strcmp(name, NAMES[slot]) == 0)
        {
            shape->element_bytes = BYTES[slot];
            shape->element_kind = KINDS[slot];
            return 1;
        }
    }
    const size_t length = strlen(name);
    const int ordered = (length >= 3u) && ((name[0] == '<') || (name[0] == '>') || (name[0] == '|') || (name[0] == '='));
    const char kind = ordered ? name[1] : '\0';
    const unsigned long width = ordered ? strtoul(&name[2], NULL, 10) : 0ul;
    if ((ordered == 0) || ((kind != 'u') && (kind != 'i') && (kind != 'f'))
     || ((width != 1ul) && (width != 2ul) && (width != 4ul) && (width != 8ul)))
    {
        return 0;
    }
    shape->element_bytes = (unsigned int)width;
    shape->element_kind = (kind == 'u') ? ENGINE_ELEMENT_UNSIGNED
                        : (kind == 'i') ? ENGINE_ELEMENT_SIGNED : ENGINE_ELEMENT_FLOAT;
    *big_endian = (name[0] == '>') ? 1u : 0u;
    return 1;
}

static int entry_codec_named(const char *name, EngineCodec *codec)
{
    static const char *const NAMES[6] = {"blosc", "zstd", "gzip", "zlib", "lz4", "snappy"};
    static const EngineCodec CODECS[6] = {ENGINE_CODEC_BLOSC, ENGINE_CODEC_ZSTD, ENGINE_CODEC_GZIP, ENGINE_CODEC_ZLIB,
                                          ENGINE_CODEC_LZ4_SIZED, ENGINE_CODEC_SNAPPY};
    for (unsigned int slot = 0u; slot < 6u; slot += 1u)
    {
        if (strcmp(name, NAMES[slot]) == 0)
        {
            *codec = CODECS[slot];
            return 1;
        }
    }
    return 0;
}

static char entry_axis_named(const char *name)
{
    static const char *const NAMES[7] = {"t", "time", "c", "channel", "z", "y", "x"};
    static const char AXES[7] = {'t', 't', 'c', 'c', 'z', 'y', 'x'};
    char lowered[16];
    size_t length = 0u;
    while ((name[length] != '\0') && (length + 1u < sizeof(lowered)))
    {
        lowered[length] = (char)(((name[length] >= 'A') && (name[length] <= 'Z')) ? (name[length] + 32) : name[length]);
        length += 1u;
    }
    lowered[length] = '\0';
    for (unsigned int slot = 0u; slot < 7u; slot += 1u)
    {
        if (strcmp(lowered, NAMES[slot]) == 0)
        {
            return AXES[slot];
        }
    }
    return '\0';
}

struct EntryOme
{
    unsigned int rank;
    char axes[ENGINE_ARRAY_RANK];
    char path[256];
};

static int entry_ome(const EntryJson *json, unsigned int attributes, EntryOme *ome)
{
    memset(ome, 0, sizeof(*ome));
    unsigned int scales = entry_json_at(json, attributes, "multiscales");
    scales = (scales != 0u) ? scales : entry_json_at(json, entry_json_at(json, attributes, "ome"), "multiscales");
    const unsigned int first = entry_json_element(json, scales, 0u);
    const unsigned int datasets = entry_json_at(json, first, "datasets");
    if (entry_json_text(json, entry_json_at(json, entry_json_element(json, datasets, 0u), "path"), ome->path,
                        sizeof(ome->path)) == 0)
    {
        return 0;
    }
    const unsigned int axes = entry_json_at(json, first, "axes");
    const unsigned int named = ((axes != 0u) && (json->tokens[axes].kind == CFG_JSON_ARRAY))
                             ? json->tokens[axes].count : 0u;
    ome->rank = (named <= ENGINE_ARRAY_RANK) ? named : 0u;
    for (unsigned int slot = 0u; slot < ome->rank; slot += 1u)
    {
        const unsigned int axis = entry_json_element(json, axes, slot);
        const unsigned int held = (json->tokens[axis].kind == CFG_JSON_OBJECT) ? entry_json_at(json, axis, "name") : axis;
        char name[32];
        ome->axes[slot] = entry_json_text(json, held, name, sizeof(name)) ? entry_axis_named(name) : '\0';
    }
    return 1;
}

static int entry_zarr_v3_chain(const EntryJson *json, unsigned int codecs, ZarrLayout *layout, int inner)
{
    ZarrChain *const chain = (inner != 0) ? &layout->inner_chain : &layout->chain;
    if ((codecs == 0u) || (json->tokens[codecs].kind != CFG_JSON_ARRAY))
    {
        return 0;
    }
    const unsigned int rank = layout->shape.rank;
    int bytes_seen = 0;
    for (unsigned int slot = 0u; slot < json->tokens[codecs].count; slot += 1u)
    {
        const unsigned int codec = entry_json_element(json, codecs, slot);
        const unsigned int configuration = entry_json_at(json, codec, "configuration");
        char name[64];
        if ((entry_json_text(json, entry_json_at(json, codec, "name"), name, sizeof(name)) == 0) || (chain->crc32c != 0u))
        {
            fprintf(stderr, "  zarr: a codec is unnamed, or follows crc32c\n");
            return 0;
        }
        if (strcmp(name, "bytes") == 0)
        {
            char endian[16] = "little";
            const unsigned int stated = entry_json_at(json, configuration, "endian");
            if ((stated != 0u) && (entry_json_text(json, stated, endian, sizeof(endian)) == 0))
            {
                return 0;
            }
            layout->big_endian = (strcmp(endian, "big") == 0) ? 1u : 0u;
            bytes_seen = 1;
        }
        else if (strcmp(name, "transpose") == 0)
        {
            unsigned long long order[ENGINE_ARRAY_RANK];
            unsigned int count = 0u;
            if ((bytes_seen != 0)
             || (entry_json_list(json, entry_json_at(json, configuration, "order"), order, &count, ENGINE_ARRAY_RANK) == 0)
             || (count != rank))
            {
                fprintf(stderr, "  zarr: transpose is held only as an order list before bytes\n");
                return 0;
            }
            for (unsigned int axis = 0u; axis < rank; axis += 1u)
            {
                layout->order[axis] = (unsigned int)order[axis];
            }
        }
        else if (strcmp(name, "sharding_indexed") == 0)
        {
            unsigned int count = 0u;
            if ((inner != 0) || (slot != 0u)
             || (entry_json_list(json, entry_json_at(json, configuration, "chunk_shape"), layout->inner, &count,
                                 ENGINE_ARRAY_RANK) == 0)
             || (count != rank) || (entry_zarr_v3_chain(json, entry_json_at(json, configuration, "codecs"), layout, 1) == 0))
            {
                fprintf(stderr, "  zarr: sharding_indexed is held only as the first codec, with its own chain\n");
                return 0;
            }
            layout->sharded = 1u;
            const unsigned int index = entry_json_at(json, configuration, "index_codecs");
            for (unsigned int held = 0u; (index != 0u) && (held < json->tokens[index].count); held += 1u)
            {
                const unsigned int step = entry_json_element(json, index, held);
                char step_name[64];
                char endian[16] = "little";
                if (entry_json_text(json, entry_json_at(json, step, "name"), step_name, sizeof(step_name)) == 0)
                {
                    return 0;
                }
                const unsigned int stated = entry_json_at(json, entry_json_at(json, step, "configuration"), "endian");
                if ((strcmp(step_name, "bytes") == 0) && (stated != 0u) && entry_json_text(json, stated, endian, sizeof(endian)))
                {
                    layout->index_big_endian = (strcmp(endian, "big") == 0) ? 1u : 0u;
                }
                layout->index_chain.crc32c |= (strcmp(step_name, "crc32c") == 0) ? 1u : 0u;
                layout->index_chain.count += ((strcmp(step_name, "bytes") != 0) && (strcmp(step_name, "crc32c") != 0)) ? 1u : 0u;
            }
            char location[16] = "end";
            const unsigned int placed = entry_json_at(json, configuration, "index_location");
            if ((placed != 0u) && (entry_json_text(json, placed, location, sizeof(location)) == 0))
            {
                return 0;
            }
            layout->index_at_start = (strcmp(location, "start") == 0) ? 1u : 0u;
            bytes_seen = 1;
        }
        else if (strcmp(name, "crc32c") == 0)
        {
            chain->crc32c = 1u;
        }
        else
        {
            EngineCodec byte_codec = ENGINE_CODEC_RAW;
            if ((bytes_seen == 0) || (entry_codec_named(name, &byte_codec) == 0) || (chain->count >= ZARR_CODECS))
            {
                fprintf(stderr, "  zarr: the codec %s is not held here\n", name);
                return 0;
            }
            chain->codec[chain->count] = byte_codec;
            chain->count += 1u;
        }
    }
    return bytes_seen;
}

static void entry_fill(const EntryJson *json, unsigned int token, ZarrLayout *layout)
{
    unsigned long long value = 0ull;
    const int counted = (token != 0u) && cfg_json_unsigned(json->text, &json->tokens[token], &value);
    for (unsigned int place = 0u; place < 8u; place += 1u)
    {
        layout->fill[place] = (counted != 0) ? (unsigned char)((value >> (8u * place)) & 0xFFull) : 0u;
    }
}

static int entry_zarr_v3(const EntryJson *json, ZarrLayout *layout)
{
    unsigned int rank = 0u;
    char type[32];
    if ((entry_json_list(json, entry_json_at(json, 0u, "shape"), layout->shape.shape, &rank, ENGINE_ARRAY_RANK) == 0)
     || (rank == 0u) || (entry_json_text(json, entry_json_at(json, 0u, "data_type"), type, sizeof(type)) == 0)
     || (entry_element_named(type, &layout->shape, &layout->big_endian) == 0))
    {
        fprintf(stderr, "  zarr: the array's shape or data type is not held\n");
        return 0;
    }
    layout->shape.rank = rank;
    unsigned int chunk_rank = 0u;
    const unsigned int grid = entry_json_at(json, entry_json_at(json, 0u, "chunk_grid"), "configuration");
    if ((entry_json_list(json, entry_json_at(json, grid, "chunk_shape"), layout->chunk, &chunk_rank, ENGINE_ARRAY_RANK) == 0)
     || (chunk_rank != rank))
    {
        fprintf(stderr, "  zarr: only a regular chunk grid is held\n");
        return 0;
    }
    const unsigned int encoding = entry_json_at(json, 0u, "chunk_key_encoding");
    char encoding_name[16] = "default";
    char separator[4] = "";
    entry_json_text(json, entry_json_at(json, encoding, "name"), encoding_name, sizeof(encoding_name));
    const int split = entry_json_text(json, entry_json_at(json, entry_json_at(json, encoding, "configuration"), "separator"),
                                      separator, sizeof(separator));
    layout->prefixed = (strcmp(encoding_name, "v2") == 0) ? 0u : 1u;
    layout->separator = (split != 0) ? separator[0] : ((layout->prefixed != 0u) ? '/' : '.');
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->order[axis] = axis;
    }
    entry_fill(json, entry_json_at(json, 0u, "fill_value"), layout);
    layout->format = ZARR_FORMAT_V3;
    const int chained = entry_zarr_v3_chain(json, entry_json_at(json, 0u, "codecs"), layout, 0);
    if ((chained == 0) || ((layout->sharded != 0u) && ((layout->chain.count != 0u) || (layout->chain.crc32c != 0u))))
    {
        fprintf(stderr, "  zarr: the codec chain is not held\n");
        return 0;
    }
    return 1;
}

static int entry_zarr_v2(const EntryJson *json, ZarrLayout *layout)
{
    unsigned int rank = 0u;
    unsigned int chunk_rank = 0u;
    char type[32];
    if ((entry_json_list(json, entry_json_at(json, 0u, "shape"), layout->shape.shape, &rank, ENGINE_ARRAY_RANK) == 0)
     || (rank == 0u)
     || (entry_json_list(json, entry_json_at(json, 0u, "chunks"), layout->chunk, &chunk_rank, ENGINE_ARRAY_RANK) == 0)
     || (chunk_rank != rank) || (entry_json_text(json, entry_json_at(json, 0u, "dtype"), type, sizeof(type)) == 0)
     || (entry_element_named(type, &layout->shape, &layout->big_endian) == 0))
    {
        fprintf(stderr, "  zarr: the v2 array's shape, chunks or dtype is not held\n");
        return 0;
    }
    layout->shape.rank = rank;
    const unsigned int filters = entry_json_at(json, 0u, "filters");
    if ((filters != 0u) && (json->tokens[filters].kind != CFG_JSON_NULL)
     && !((json->tokens[filters].kind == CFG_JSON_ARRAY) && (json->tokens[filters].count == 0u)))
    {
        fprintf(stderr, "  zarr: v2 filters are not held\n");
        return 0;
    }
    const unsigned int compressor = entry_json_at(json, 0u, "compressor");
    if ((compressor != 0u) && (json->tokens[compressor].kind == CFG_JSON_OBJECT))
    {
        char name[32];
        EngineCodec codec = ENGINE_CODEC_RAW;
        if ((entry_json_text(json, entry_json_at(json, compressor, "id"), name, sizeof(name)) == 0)
         || (entry_codec_named(name, &codec) == 0))
        {
            fprintf(stderr, "  zarr: the v2 compressor is not held\n");
            return 0;
        }
        layout->chain.codec[0] = codec;
        layout->chain.count = 1u;
    }
    char order[4] = "C";
    entry_json_text(json, entry_json_at(json, 0u, "order"), order, sizeof(order));
    char separator[4] = ".";
    entry_json_text(json, entry_json_at(json, 0u, "dimension_separator"), separator, sizeof(separator));
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->order[axis] = (order[0] == 'F') ? (rank - 1u - axis) : axis;
    }
    layout->separator = separator[0];
    layout->prefixed = 0u;
    entry_fill(json, entry_json_at(json, 0u, "fill_value"), layout);
    layout->format = ZARR_FORMAT_V2;
    return 1;
}

static int entry_n5(const EntryJson *json, ZarrLayout *layout)
{
    unsigned long long dimensions[ENGINE_ARRAY_RANK];
    unsigned long long blocks[ENGINE_ARRAY_RANK];
    unsigned int rank = 0u;
    unsigned int block_rank = 0u;
    char type[32];
    unsigned int ignored = 0u;
    if ((entry_json_list(json, entry_json_at(json, 0u, "dimensions"), dimensions, &rank, ENGINE_ARRAY_RANK) == 0)
     || (rank == 0u) || (entry_json_list(json, entry_json_at(json, 0u, "blockSize"), blocks, &block_rank, ENGINE_ARRAY_RANK) == 0)
     || (block_rank != rank) || (entry_json_text(json, entry_json_at(json, 0u, "dataType"), type, sizeof(type)) == 0)
     || (entry_element_named(type, &layout->shape, &ignored) == 0))
    {
        fprintf(stderr, "  n5: the dataset's dimensions, blockSize or dataType is not held\n");
        return 0;
    }
    layout->shape.rank = rank;
    for (unsigned int axis = 0u; axis < rank; axis += 1u)
    {
        layout->shape.shape[axis] = dimensions[rank - 1u - axis];
        layout->chunk[axis] = blocks[rank - 1u - axis];
        layout->order[axis] = axis;
    }
    const unsigned int compression = entry_json_at(json, 0u, "compression");
    char kind[32] = "raw";
    if (compression != 0u)
    {
        entry_json_text(json, entry_json_at(json, compression, "type"), kind, sizeof(kind));
    }
    else
    {
        entry_json_text(json, entry_json_at(json, 0u, "compressionType"), kind, sizeof(kind));
    }
    const unsigned int zlib = entry_json_at(json, compression, "useZlib");
    if (strcmp(kind, "gzip") == 0)
    {
        layout->chain.codec[0] = ((zlib != 0u) && (json->tokens[zlib].kind == CFG_JSON_TRUE)) ? ENGINE_CODEC_ZLIB
                                                                                             : ENGINE_CODEC_GZIP;
        layout->chain.count = 1u;
    }
    else if ((strcmp(kind, "blosc") == 0) || (strcmp(kind, "zstd") == 0))
    {
        layout->chain.codec[0] = (kind[0] == 'b') ? ENGINE_CODEC_BLOSC : ENGINE_CODEC_ZSTD;
        layout->chain.count = 1u;
    }
    else if (strcmp(kind, "raw") != 0)
    {
        fprintf(stderr, "  n5: the compression %s is not held\n", kind);
        return 0;
    }
    layout->big_endian = 1u;
    layout->separator = '/';
    layout->prefixed = 0u;
    layout->format = ZARR_FORMAT_N5;
    const unsigned int axes = entry_json_at(json, 0u, "axes");
    for (unsigned int slot = 0u; (axes != 0u) && (json->tokens[axes].count == rank) && (slot < rank); slot += 1u)
    {
        char name[32];
        layout->shape.axes[rank - 1u - slot] = entry_json_text(json, entry_json_element(json, axes, slot), name, sizeof(name))
                                             ? entry_axis_named(name) : '\0';
    }
    return 1;
}

static int entry_zarr_describe(const char *root, const char *member, ZarrLayout *layout, char *array_root, size_t room)
{
    memset(layout, 0, sizeof(*layout));
    char path[ENTRY_PATH_ROOM];
    EntryJson json;
    memset(&json, 0, sizeof(json));
    EntryOme ome;
    memset(&ome, 0, sizeof(ome));
    int good = 0;
    if (entry_joined(path, sizeof(path), root, "zarr.json") && entry_json_load(path, &json))
    {
        char node[16] = "";
        entry_json_text(&json, entry_json_at(&json, 0u, "node_type"), node, sizeof(node));
        const int group = (strcmp(node, "group") == 0);
        const int described = group ? entry_ome(&json, entry_json_at(&json, 0u, "attributes"), &ome) : 0;
        const char *const leaf = (member != NULL) ? member : (described ? ome.path : NULL);
        entry_json_release(&json);
        if (group && (leaf == NULL))
        {
            fprintf(stderr, "  %s: a group with no multiscales; name the array\n", root);
            return 0;
        }
        good = (group ? entry_joined(array_root, room, root, leaf) : entry_joined(array_root, room, root, "."))
            && entry_joined(path, sizeof(path), array_root, "zarr.json") && entry_json_load(path, &json);
        good = good && entry_zarr_v3(&json, layout);
        if (good)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, ".zarray") && entry_exists(path))
    {
        good = entry_joined(array_root, room, root, ".") && entry_json_load(path, &json);
        good = good && entry_zarr_v2(&json, layout);
        if (good)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, ".zgroup") && entry_exists(path))
    {
        const int attributed = entry_joined(path, sizeof(path), root, ".zattrs") && entry_json_load(path, &json);
        const int described = attributed && entry_ome(&json, 0u, &ome);
        if (attributed)
        {
            entry_json_release(&json);
        }
        const char *const leaf = (member != NULL) ? member : (described ? ome.path : NULL);
        good = (leaf != NULL) && entry_joined(array_root, room, root, leaf)
            && entry_joined(path, sizeof(path), array_root, ".zarray") && entry_json_load(path, &json);
        good = good && entry_zarr_v2(&json, layout);
        if (good)
        {
            entry_json_release(&json);
        }
    }
    else if (entry_joined(path, sizeof(path), root, "attributes.json") && entry_json_load(path, &json))
    {
        const int dataset = (entry_json_at(&json, 0u, "dimensions") != 0u);
        entry_json_release(&json);
        const char *const leaf = (member != NULL) ? member : (dataset ? "." : "s0");
        good = entry_joined(array_root, room, root, leaf) && entry_joined(path, sizeof(path), array_root, "attributes.json")
            && entry_json_load(path, &json);
        good = good && entry_n5(&json, layout);
        if (good)
        {
            entry_json_release(&json);
        }
    }
    if (good == 0)
    {
        entry_json_release(&json);
        return 0;
    }
    for (unsigned int axis = 0u; (ome.rank == layout->shape.rank) && (axis < ome.rank); axis += 1u)
    {
        layout->shape.axes[axis] = ome.axes[axis];
    }
    return 1;
}

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
    char path[ENTRY_PATH_ROOM];
    const char *member;
    ZarrLayout layout;
    EngineArrayShape shape;
};

static int entry_ends(const char *path, const char *suffix)
{
    const size_t length = strlen(path);
    const size_t size = strlen(suffix);
    int same = (length >= size);
    for (size_t at = 0u; same && (at < size); at += 1u)
    {
        const char held = path[length - size + at];
        const char lowered = (char)(((held >= 'A') && (held <= 'Z')) ? (held + 32) : held);
        same = (lowered == suffix[at]);
    }
    return same;
}

static int entry_zip_names(const char *path, const char *member)
{
    EngineError probe;
    memset(&probe, 0, sizeof(probe));
    const ZipArchive *const archive = zip_archive_held(entry_ingest_tools(), path, &probe);
    unsigned long long first = 0ull;
    unsigned long long count = 0ull;
    if ((archive == NULL) || (zip_folder_find(archive, member, &first, &count) && (count != 0ull)))
    {
        return archive != NULL;
    }
    const size_t length = strlen(member);
    int named = 0;
    for (unsigned long long slot = 0ull; (named == 0) && (slot < archive->entries); slot += 1ull)
    {
        ZipEntry entry;
        if (!zip_entry_at(archive, slot, &entry, &probe))
        {
            return 0;
        }
        const int stem = (entry.name_length >= length) && (memcmp(entry.name, member, length) == 0);
        named = stem
             && ((entry.name_length == length)
                 || ((entry.name_length == (length + 4u)) && (memcmp(entry.name + length, ".npy", 4u) == 0)));
    }
    return named;
}

static EntrySourceKind entry_source_kind(const char *path, const char *member)
{
    char probe[ENTRY_PATH_ROOM];
    static const char *const MARKS[4] = {"zarr.json", ".zarray", ".zgroup", "attributes.json"};
    for (unsigned int mark = 0u; mark < 4u; mark += 1u)
    {
        if (entry_joined(probe, sizeof(probe), path, MARKS[mark]) && (stack_file_size(probe) >= 0ll))
        {
            return ENTRY_SOURCE_ZARR;
        }
    }
    if (entry_ends(path, ".stack"))
    {
        return ENTRY_SOURCE_STACK;
    }
    unsigned char head[352];
    memset(head, 0, sizeof(head));
    EngineFileRange range;
    range.path = path;
    range.offset = 0ull;
    range.bytes = sizeof(head);
    range.out = head;
    const long long held = stack_file_read(&range);
    if (held < 8ll)
    {
        return ENTRY_SOURCE_NONE;
    }
    const unsigned int little_header = (unsigned int)head[0] | ((unsigned int)head[1] << 8u) | ((unsigned int)head[2] << 16u)
                                     | ((unsigned int)head[3] << 24u);
    const unsigned int big_header = ((unsigned int)head[0] << 24u) | ((unsigned int)head[1] << 16u)
                                  | ((unsigned int)head[2] << 8u) | (unsigned int)head[3];
    if (((head[0] == 'I') && (head[1] == 'I') && ((head[2] == 42u) || (head[2] == 43u)) && (head[3] == 0u))
     || ((head[0] == 'M') && (head[1] == 'M') && (head[2] == 0u) && ((head[3] == 42u) || (head[3] == 43u))))
    {
        return ENTRY_SOURCE_TIFF;
    }
    if ((memcmp(head, "\x89HDF\r\n\x1a\n", 8u) == 0) || entry_ends(path, ".h5") || entry_ends(path, ".hdf5")
     || entry_ends(path, ".ims"))
    {
        return ENTRY_SOURCE_HDF5;
    }
    if ((memcmp(head, "PK\x03\x04", 4u) == 0) && dicom_zip_holds(entry_ingest_tools(), path, member))
    {
        return ENTRY_SOURCE_DICOM;
    }
    if ((memcmp(head, "PK\x03\x04", 4u) == 0) && (member != NULL) && !entry_zip_names(path, member))
    {
        return ENTRY_SOURCE_NO_MEMBER;
    }
    if ((memcmp(head, "\x93NUMPY", 6u) == 0) || (memcmp(head, "PK\x03\x04", 4u) == 0))
    {
        return ENTRY_SOURCE_NPY;
    }
    if (memcmp(head, "NRRD000", 7u) == 0)
    {
        return ENTRY_SOURCE_NRRD;
    }
    if ((little_header == 348u) || (big_header == 348u) || (little_header == 540u) || (big_header == 540u)
     || entry_ends(path, ".nii.gz") || entry_ends(path, ".nii"))
    {
        return ENTRY_SOURCE_NIFTI;
    }
    return ENTRY_SOURCE_NONE;
}

static int entry_source_describe(const char *path, const char *member, EntrySource *source, EngineError *error)
{
    memset(source, 0, sizeof(*source));
    source->kind = entry_source_kind(path, member);
    source->member = member;
    const EngineIngestTools *const tools = entry_ingest_tools();
    EngineDescribeRequest describe;
    describe.path = path;
    describe.member = member;
    describe.tools = tools;
    describe.shape = &source->shape;
    describe.error = error;
    snprintf(source->path, sizeof(source->path), "%s", path);
    switch (source->kind)
    {
    case ENTRY_SOURCE_ZARR:
    {
        const int good = entry_zarr_describe(path, member, &source->layout, source->path, sizeof(source->path));
        source->shape = source->layout.shape;
        return good;
    }
    case ENTRY_SOURCE_TIFF:
        return tiff_describe(&describe) == 0L;
    case ENTRY_SOURCE_HDF5:
        return hdf5_describe(&describe) == 0L;
    case ENTRY_SOURCE_NPY:
        return npy_describe(&describe) == 0L;
    case ENTRY_SOURCE_DICOM:
        return dicom_describe(&describe) == 0L;
    case ENTRY_SOURCE_NRRD:
        return nrrd_describe(&describe) == 0L;
    case ENTRY_SOURCE_NIFTI:
        return nifti_describe(&describe) == 0L;
    case ENTRY_SOURCE_STACK:
    {
        unsigned int header[4] = {0u, 0u, 0u, 0u};
        FILE *const stack = stack_open(path, header);
        if (stack == NULL)
        {
            return 0;
        }
        fclose(stack);
        source->shape.rank = 4u;
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            source->shape.shape[axis] = header[axis];
            source->shape.axes[axis] = "tzyx"[axis];
        }
        source->shape.element_bytes = 2u;
        source->shape.element_kind = ENGINE_ELEMENT_UNSIGNED;
        return 1;
    }
    case ENTRY_SOURCE_NO_MEMBER:
        fprintf(stderr, "  %s: the archive holds no member named %s\n", path, member);
        return ENGINE_HELD(0, member, error, ENGINE_ERROR_REQUEST);
    default:
        fprintf(stderr, "  %s: not a dataset format the engine reads\n", path);
        return 0;
    }
}

static long long entry_source_bytes(const EntrySource *source, unsigned char *out, unsigned long long room,
                                    EngineSideBytes *side, EngineError *error)
{
    const EngineIngestTools *const tools = entry_ingest_tools();
    EngineArrayRead read;
    read.path = source->path;
    read.member = source->member;
    read.tools = tools;
    read.shape = &source->shape;
    read.first = 0ull;
    read.past = source->shape.shape[0];
    read.out = out;
    read.out_room = room;
    read.side = side;
    read.error = error;
    switch (source->kind)
    {
    case ENTRY_SOURCE_ZARR:
    {
        ZarrReadRequest zarr;
        zarr.root = source->path;
        zarr.layout = &source->layout;
        zarr.tools = tools;
        zarr.first = 0ull;
        zarr.past = source->shape.shape[0];
        zarr.out = out;
        zarr.out_room = room;
        return zarr_read(&zarr);
    }
    case ENTRY_SOURCE_TIFF:
        return tiff_read(&read);
    case ENTRY_SOURCE_HDF5:
        return hdf5_read(&read);
    case ENTRY_SOURCE_NPY:
        return npy_read(&read);
    case ENTRY_SOURCE_DICOM:
        return dicom_read(&read);
    case ENTRY_SOURCE_NRRD:
        return nrrd_read(&read);
    case ENTRY_SOURCE_NIFTI:
        return nifti_read(&read);
    case ENTRY_SOURCE_STACK:
        return stack_read_uncached(source->path, room / 2ull, (unsigned short *)out) ? (long long)room : -1ll;
    default:
        return -1ll;
    }
}

extern "C" long engine_source_read(const EngineSourceRequest *request, unsigned long long extent[4], unsigned short **volume)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    *volume = NULL;
    EntrySource *const source = (EntrySource *)calloc(1u, sizeof(EntrySource));
    if ((ENGINE_HELD(source != NULL, &source, error, ENGINE_ERROR_RESOURCE) == 0)
        || (entry_source_describe(request->path, request->member, source, error) == 0))
    {
        free(source);
        return ENGINE_REFUSED;
    }
    const EngineArrayShape *const shape = &source->shape;
    const unsigned int rank = shape->rank;
    char axes[ENGINE_ARRAY_RANK];
    const size_t stated = (request->axes != NULL) ? strlen(request->axes) : 0u;
    int good = (rank != 0u) && ((request->axes == NULL) || (stated == rank));
    for (unsigned int axis = 0u; good && (axis < rank); axis += 1u)
    {
        axes[axis] = (request->axes != NULL) ? request->axes[axis] : shape->axes[axis];
        good = (axes[axis] == 't') || (axes[axis] == 'z') || (axes[axis] == 'y') || (axes[axis] == 'x')
            || ((axes[axis] == 'c') && (shape->shape[axis] == 1ull));
    }
    if (good == 0)
    {
        fprintf(stderr, "  %s: the source's %u axes are not all named t z y x (a c of size one may stand); name them in "
                        "the .cfg's input axes\n", request->path, rank);
        free(source);
        return ENGINE_REFUSED;
    }
    if ((shape->element_kind == ENGINE_ELEMENT_FLOAT) || ((shape->element_bytes != 1u) && (shape->element_bytes != 2u)))
    {
        fprintf(stderr, "  %s: %u byte %s elements are not held; the engine takes 8 and 16 bit integer samples\n",
                request->path, shape->element_bytes,
                (shape->element_kind == ENGINE_ELEMENT_FLOAT) ? "float" : ((shape->element_kind == ENGINE_ELEMENT_SIGNED)
                                                                          ? "signed" : "unsigned"));
        free(source);
        return ENGINE_REFUSED;
    }
    int placed[4] = {-1, -1, -1, -1};
    unsigned long long stride[ENGINE_ARRAY_RANK];
    unsigned long long elements = 1ull;
    for (unsigned int axis = rank; axis > 0u; axis -= 1u)
    {
        stride[axis - 1u] = elements;
        elements *= shape->shape[axis - 1u];
    }
    for (unsigned int target = 0u; good && (target < 4u); target += 1u)
    {
        for (unsigned int axis = 0u; axis < rank; axis += 1u)
        {
            good = good && !((axes[axis] == "tzyx"[target]) && (placed[target] >= 0));
            placed[target] = (axes[axis] == "tzyx"[target]) ? (int)axis : placed[target];
        }
        extent[target] = (placed[target] >= 0) ? shape->shape[placed[target]] : 1ull;
    }
    int ordered = good;
    int last = -1;
    for (unsigned int target = 0u; target < 4u; target += 1u)
    {
        ordered = ordered && ((placed[target] < 0) || (placed[target] > last));
        last = (placed[target] >= 0) ? placed[target] : last;
    }
    const unsigned long long bytes = elements * shape->element_bytes;
    unsigned char *const raw = good ? (unsigned char *)malloc((size_t)bytes + 1u) : NULL;
    good = good && (raw != NULL) && (entry_source_bytes(source, raw, bytes, request->side, error) == (long long)bytes);
    if (good == 0)
    {
        fprintf(stderr, "  %s: the source was not read whole\n", request->path);
        free(raw);
        free(source);
        return ENGINE_REFUSED;
    }
    const int signed_lanes = (shape->element_kind == ENGINE_ELEMENT_SIGNED);
    const unsigned int lane_offset = signed_lanes ? 0x8000u : 0u;
    if (request->lane_offset != NULL)
    {
        *request->lane_offset = lane_offset;
    }
    if (ordered && (shape->element_bytes == 2u))
    {
        unsigned short *const words = (unsigned short *)raw;
        for (unsigned long long word = 0ull; signed_lanes && (word < elements); word += 1ull)
        {
            // a two's complement word plus 2^15 is the word with its top bit flipped, exactly, and stays 16 bits
            words[word] = (unsigned short)(words[word] ^ 0x8000u);
        }
        *volume = words;
        free(source);
        return 0L;
    }
    unsigned short *const lanes = (unsigned short *)malloc((size_t)elements * sizeof(unsigned short));
    if (lanes == NULL)
    {
        free(raw);
        free(source);
        return ENGINE_REFUSED;
    }
    unsigned long long at = 0ull;
    for (unsigned long long time = 0ull; time < extent[0]; time += 1ull)
    {
        for (unsigned long long depth = 0ull; depth < extent[1]; depth += 1ull)
        {
            for (unsigned long long row = 0ull; row < extent[2]; row += 1ull)
            {
                for (unsigned long long column = 0ull; column < extent[3]; column += 1ull)
                {
                    const unsigned long long where[4] = {time, depth, row, column};
                    unsigned long long from = 0ull;
                    for (unsigned int target = 0u; target < 4u; target += 1u)
                    {
                        from += (placed[target] >= 0) ? (where[target] * stride[placed[target]]) : 0ull;
                    }
                    const unsigned int word = (shape->element_bytes == 1u)
                                            ? (unsigned int)raw[from]
                                            : ((unsigned int)raw[2ull * from] | ((unsigned int)raw[(2ull * from) + 1ull] << 8u));
                    const unsigned int sign_bit = (shape->element_bytes == 1u) ? 0x80u : 0x8000u;
                    const unsigned int value_span = (shape->element_bytes == 1u) ? 0x100u : 0x10000u;
                    const unsigned int shifted = ((word & sign_bit) != 0u) ? ((lane_offset + word) - value_span)
                                                                           : (lane_offset + word);
                    // an unsigned word, or a signed one plus 2^15, lies in 0 to 65535 and is held whole in an unsigned short
                    lanes[at] = (unsigned short)(signed_lanes ? shifted : word);
                    at += 1ull;
                }
            }
        }
    }
    free(raw);
    free(source);
    *volume = lanes;
    return 0L;
}

#define ENTRY_SOURCE_SUFFIX_COUNT 18u

static const char *const ENTRY_SOURCE_SUFFIXES[ENTRY_SOURCE_SUFFIX_COUNT] = {
    ".ome.zarr", ".zarr", ".n5", ".ome.tiff", ".ome.tif", ".tiff", ".tif", ".hdf5", ".h5",
    ".ims",      ".npz",  ".npy", ".nhdr",    ".nrrd",    ".nii.gz", ".nii", ".hdr", ".stack"};

extern "C" int engine_source_find(const char *source, const char *sample, char *out, size_t room)
{
    for (unsigned int suffix = 0u; suffix < ENTRY_SOURCE_SUFFIX_COUNT; suffix += 1u)
    {
        const int written = snprintf(out, room, "%s/%s%s", source, sample, ENTRY_SOURCE_SUFFIXES[suffix]);
        if ((written > 0) && ((size_t)written < room) && entry_exists(out))
        {
            return 1;
        }
    }
    return 0;
}

extern "C" long engine_source_lanes(const char *source, const char *sample, unsigned long long *lanes,
                                    EngineError *error)
{
    // the sample's source is found as ingest finds it and only described, so no voxel is read
    if ((error == NULL) || (lanes == NULL))
    {
        return ENGINE_REFUSED;
    }
    *lanes = 0ull;
    char path[ENTRY_PATH_ROOM];
    const int archived = (source != NULL) && entry_is_file(source);
    const int placed = (source != NULL) && (sample != NULL)
                    && (archived ? (snprintf(path, sizeof(path), "%s", source) > 0)
                                 : engine_source_find(source, sample, path, sizeof(path)));
    EntrySource *const described = placed ? (EntrySource *)calloc(1u, sizeof(EntrySource)) : NULL;
    int good = ENGINE_HELD(placed != 0, sample, error, ENGINE_ERROR_REQUEST)
            && ENGINE_HELD(described != NULL, &described, error, ENGINE_ERROR_RESOURCE)
            && entry_source_describe(path, archived ? sample : NULL, described, error);
    unsigned long long elements = good ? 1ull : 0ull;
    for (unsigned int axis = 0u; good && (axis < described->shape.rank); axis += 1u)
    {
        const unsigned long long extent = described->shape.shape[axis];
        good = (extent != 0ull) && (elements <= (~0ull / extent));
        elements = good ? (elements * extent) : 0ull;
    }
    free(described);
    *lanes = elements;
    return (good && (elements != 0ull)) ? 0L : ENGINE_REFUSED;
}

static int entry_order_names(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static unsigned int entry_listing(const char *directory, char ***names, int samples_of_set)
{
    std::vector<char *> found;
#ifdef _WIN32
    char pattern[ENTRY_PATH_ROOM];
    snprintf(pattern, sizeof(pattern), "%s/*", directory);
    struct __finddata64_t entry;
    const intptr_t search = _findfirst64(pattern, &entry);
    for (int more = (search != -1) ? 0 : -1; more == 0; more = _findnext64(search, &entry))
    {
        const char *const name = entry.name;
#else
    DIR *const search = opendir(directory);
    for (struct dirent *entry = (search != NULL) ? readdir(search) : NULL; entry != NULL; entry = readdir(search))
    {
        const char *const name = entry->d_name;
#endif
        if (name[0] == '.')
        {
            continue;
        }
        char stem[ENTRY_PATH_ROOM];
        snprintf(stem, sizeof(stem), "%s", name);
        int kept = 0;
        if (samples_of_set != 0)
        {
            char held[ENTRY_PATH_ROOM];
            kept = engine_sample_path(held, sizeof(held), directory, name, ENTRY_CRYSTAL_SUFFIX) && entry_exists(held);
        }
        for (unsigned int suffix = 0u; (samples_of_set == 0) && (kept == 0) && (suffix < ENTRY_SOURCE_SUFFIX_COUNT); suffix += 1u)
        {
            if (entry_ends(stem, ENTRY_SOURCE_SUFFIXES[suffix]))
            {
                stem[strlen(stem) - strlen(ENTRY_SOURCE_SUFFIXES[suffix])] = '\0';
                kept = 1;
            }
        }
        if (kept != 0)
        {
            const size_t size = strlen(stem) + 1u;
            char *const copy = (char *)malloc(size);
            if (copy != NULL)
            {
                memcpy(copy, stem, size);
                found.push_back(copy);
            }
        }
    }
#ifdef _WIN32
    if (search != -1)
    {
        _findclose(search);
    }
#else
    if (search != NULL)
    {
        closedir(search);
    }
#endif
    char **const listed = (char **)calloc(found.size() + 1u, sizeof(char *));
    if (listed == NULL)
    {
        for (size_t slot = 0u; slot < found.size(); slot += 1u)
        {
            free(found[slot]);
        }
        *names = NULL;
        return 0u;
    }
    for (size_t slot = 0u; slot < found.size(); slot += 1u)
    {
        listed[slot] = found[slot];
    }
    qsort(listed, found.size(), sizeof(char *), entry_order_names);
    *names = listed;
    return (unsigned int)found.size();
}

extern "C" unsigned int engine_source_samples(const char *source, char ***names)
{
    return entry_listing(source, names, 0);
}

extern "C" unsigned int engine_set_samples(const char *set, char ***names)
{
    return entry_listing(set, names, 1);
}

static long long entry_geff_array(const char *root, const char *leaf, unsigned long long want_rank,
                                  unsigned long long *rows, unsigned char **bytes)
{
    char path[ENTRY_PATH_ROOM];
    char array_root[ENTRY_PATH_ROOM];
    ZarrLayout layout;
    *bytes = NULL;
    if ((entry_joined(path, sizeof(path), root, leaf) == 0)
     || (entry_zarr_describe(path, NULL, &layout, array_root, sizeof(array_root)) == 0)
     || (layout.shape.rank != want_rank) || (layout.shape.element_bytes != 8u)
     || (layout.shape.element_kind == ENGINE_ELEMENT_FLOAT))
    {
        fprintf(stderr, "  %s/%s: not an 8 byte integer array of rank %llu\n", root, leaf, want_rank);
        return -1ll;
    }
    unsigned long long elements = 1ull;
    for (unsigned int axis = 0u; axis < layout.shape.rank; axis += 1u)
    {
        elements *= layout.shape.shape[axis];
    }
    *rows = layout.shape.shape[0];
    unsigned char *const out = (unsigned char *)malloc((size_t)(elements * 8ull) + 8u);
    ZarrReadRequest read;
    read.root = array_root;
    read.layout = &layout;
    read.tools = entry_ingest_tools();
    read.first = 0ull;
    read.past = layout.shape.shape[0];
    read.out = out;
    read.out_room = elements * 8ull;
    if ((out == NULL) || ((elements != 0ull) && (zarr_read(&read) != (long long)(elements * 8ull))))
    {
        free(out);
        return -1ll;
    }
    *bytes = out;
    return (long long)elements;
}

extern "C" void engine_geff_release(EngineGeff *geff)
{
    free(geff->node_identity);
    free(geff->node_place);
    free(geff->edge_ends);
    memset(geff, 0, sizeof(*geff));
}

extern "C" long engine_geff_read(const char *path, EngineGeff *geff)
{
    memset(geff, 0, sizeof(*geff));
    static const char *const PLACES[4] = {"nodes/props/t/values", "nodes/props/z/values", "nodes/props/y/values",
                                          "nodes/props/x/values"};
    unsigned long long rows = 0ull;
    unsigned char *ids = NULL;
    unsigned char *edges = NULL;
    unsigned char *places[4] = {NULL, NULL, NULL, NULL};
    int good = (entry_geff_array(path, "nodes/ids", 1ull, &geff->nodes, &ids) >= 0ll);
    for (unsigned int axis = 0u; good && (axis < 4u); axis += 1u)
    {
        good = (entry_geff_array(path, PLACES[axis], 1ull, &rows, &places[axis]) >= 0ll) && (rows == geff->nodes);
    }
    good = good && (entry_geff_array(path, "edges/ids", 2ull, &geff->edges, &edges) >= 0ll);
    geff->node_identity = good ? (unsigned long long *)malloc((size_t)(geff->nodes + 1ull) * sizeof(unsigned long long)) : NULL;
    geff->node_place = good ? (long long *)malloc((size_t)(geff->nodes + 1ull) * 4u * sizeof(long long)) : NULL;
    good = good && (geff->node_identity != NULL) && (geff->node_place != NULL);
    for (unsigned long long node = 0ull; good && (node < geff->nodes); node += 1ull)
    {
        memcpy(&geff->node_identity[node], &ids[8ull * node], 8u);
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            memcpy(&geff->node_place[(4ull * node) + axis], &places[axis][8ull * node], 8u);
        }
    }
    if (good)
    {
        geff->edge_ends = (unsigned long long *)edges;
        edges = NULL;
    }
    free(ids);
    free(edges);
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        free(places[axis]);
    }
    if (good == 0)
    {
        engine_geff_release(geff);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" long engine_kcr_head(const char *set, const char *sample, unsigned long long extent[4], EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    char path[ENTRY_PATH_ROOM];
    EngineStream stream;
    memset(&stream, 0, sizeof(stream));
    if ((ENGINE_HELD(engine_sample_path(path, sizeof(path), set, sample, ENTRY_CRYSTAL_SUFFIX) != 0, sample, error,
                     ENGINE_ERROR_REQUEST) == 0)
        || (krep_crystal_head(path, &stream, NULL, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    memcpy(extent, stream.extent, sizeof(stream.extent));
    return 0L;
}

static unsigned long long entry_lanes(const unsigned long long extent[4])
{
    unsigned long long lanes = 1ull;
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        if ((extent[axis] == 0ull) || (extent[axis] > (1ull << 40u)) || (lanes > ((1ull << 40u) / extent[axis])))
        {
            return 0ull;
        }
        lanes *= extent[axis];
    }
    return lanes;
}

static int entry_kcr_decode(const EngineStream *stream, const unsigned short *device_lanes, unsigned short *rebuilt,
                            unsigned long long *mismatches, const unsigned short **device_rebuilt, EngineError *error)
{
    int *coefficients = NULL;
    if (tower_room(stream->extent, &coefficients, error) != 0L)
    {
        return 0;
    }
    CompressionDecodeRequest code;
    memset(&code, 0, sizeof(code));
    code.offsets = stream->offsets;
    code.chunks = stream->chunks;
    code.stream = stream->stream;
    code.bits = stream->bits;
    code.count = entry_lanes(stream->extent);
    code.device_coefficients = coefficients;
    code.error = error;
    if (compression_decode(&code) != 0L)
    {
        return 0;
    }
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    lower.device_lanes = device_lanes;
    memcpy(lower.extent, stream->extent, sizeof(lower.extent));
    lower.mismatches = mismatches;
    lower.device_rebuilt = device_rebuilt;
    lower.rebuilt = rebuilt;
    lower.error = error;
    return (tower_lower(&lower) == 0L) ? 1 : 0;
}

static int entry_kcr_encode(const unsigned short *device_lanes, const unsigned long long extent[4],
                            EngineStream *stream, unsigned int *floors, EngineError *error)
{
    memset(stream, 0, sizeof(*stream));
    memcpy(stream->extent, extent, sizeof(stream->extent));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = device_lanes;
    memcpy(lift.extent, extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = floors;
    lift.error = error;
    if (tower_lift(&lift) != 0L)
    {
        return 0;
    }
    CompressionEncodeRequest code;
    memset(&code, 0, sizeof(code));
    code.device_coefficients = coefficients;
    code.count = entry_lanes(extent);
    code.device_scratch = scratch;
    code.chunks = &stream->chunks;
    code.bits = &stream->bits;
    code.offsets = &stream->offsets;
    code.stream = &stream->stream;
    code.error = error;
    return (compression_encode(&code) == 0L) ? 1 : 0;
}

static int entry_side_pack(EngineSideSection *section, EngineError *error)
{
    if (section->side.leaves == 0ull)
    {
        return 1;
    }
    const unsigned long long bytes = section->side.byte_start[section->side.leaves];
    const unsigned long long room = deflate_raw_bound(bytes);
    section->packed = (unsigned char *)malloc((size_t)room + 1u);
    if (ENGINE_HELD(section->packed != NULL, &section->packed, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    EngineBytesRequest pack;
    pack.in = section->side.bytes;
    pack.in_bytes = bytes;
    pack.out = section->packed;
    pack.out_room = room;
    const long long packed = deflate_raw_encode(&pack);
    // a packed count that is not refused is at least zero, and fits an unsigned long long exactly
    section->packed_bytes = (packed >= 0ll) ? (unsigned long long)packed : 0ull;
    return ENGINE_HELD(packed >= 0ll, section->packed, error, ENGINE_ERROR_RESOURCE);
}

static int entry_side_unpack(EngineSideSection *section, EngineError *error)
{
    if (section->side.leaves == 0ull)
    {
        return 1;
    }
    const unsigned long long bytes = section->side.byte_start[section->side.leaves];
    section->side.bytes = (unsigned char *)malloc((size_t)bytes + 1u);
    if (ENGINE_HELD(section->side.bytes != NULL, &section->side.bytes, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    EngineBytesRequest unpack;
    unpack.in = section->packed;
    unpack.in_bytes = section->packed_bytes;
    unpack.out = section->side.bytes;
    unpack.out_room = bytes;
    const long long unpacked = inflate_raw_decode(&unpack);
    // the count is compared against a size in memory, which fits a long long
    return ENGINE_HELD(unpacked == (long long)bytes, section->side.bytes, error, ENGINE_ERROR_LOGIC);
}

static int entry_side_same(const EngineSideBytes *one, const EngineSideBytes *other)
{
    const size_t leaves = (size_t)one->leaves;
    const size_t words = leaves * sizeof(unsigned long long);
    const size_t fenced = (leaves + 1u) * sizeof(unsigned long long);
    if (one->leaves != other->leaves)
    {
        return 0;
    }
    if (leaves == 0u)
    {
        return 1;
    }
    return (memcmp(one->pixel_at, other->pixel_at, words) == 0) && (memcmp(one->pixel_kept, other->pixel_kept, words) == 0)
        && (memcmp(one->byte_start, other->byte_start, fenced) == 0)
        && (memcmp(one->name_start, other->name_start, fenced) == 0)
        && (memcmp(one->member_crc, other->member_crc, words) == 0)
        && (memcmp(one->member_bytes, other->member_bytes, words) == 0)
        && (memcmp(one->bytes, other->bytes, (size_t)one->byte_start[leaves]) == 0)
        && (memcmp(one->names, other->names, (size_t)one->name_start[leaves]) == 0);
}

static_assert(OBSIGNATIO_SIGNUM_BYTES == ENGINE_SIGNUM_BYTES, "the engine's signum is obsignatio's");

#define ENTRY_SAMPLE_WORDS 12u

#define ENTRY_SAMPLE_ROOTS 4u

static int entry_signum_same(const EngineSignum *one, const EngineSignum *other)
{
    return memcmp(one->bytes, other->bytes, ENGINE_SIGNUM_BYTES) == 0;
}

static int entry_keyed(ObsignatioLevel level, const unsigned char *bytes, unsigned long long count, EngineSignum *out,
                       EngineError *error)
{
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    if (obsignatio_level_key(level, key, error) != 0L)
    {
        return 0;
    }
    const ObsignatioSignumRequest request = {bytes, count, key, OBSIGNATIO_MODE_KEYED, out->bytes, ENGINE_SIGNUM_BYTES,
                                             error};
    return obsignatio_signum(&request) == 0L;
}

static void entry_words_place(unsigned char *out, const unsigned long long *words, unsigned long long count)
{
    for (unsigned long long word = 0ull; word < count; word += 1ull)
    {
        for (unsigned int place = 0u; place < 8u; place += 1u)
        {
            // one byte of the word, shifted down and masked, fits an unsigned char
            out[(8ull * word) + place] = (unsigned char)((words[word] >> (8u * place)) & 0xFFull);
        }
    }
}

static int entry_seal_lanes(const unsigned short *device_lanes, const unsigned long long extent[4], EngineSignum *nodes,
                            unsigned long long count, EngineError *error)
{
    const size_t bytes = (size_t)count * sizeof(EngineSignum);
    unsigned char *device_nodes = NULL;
    int good = ENGINE_TOOK(cudaMalloc((void **)&device_nodes, bytes), &device_nodes, error);
    if (good)
    {
        const ObsignatioLanesRequest request = {device_lanes, extent, device_nodes, error};
        good = (obsignatio_lanes(&request) == 0L)
            && ENGINE_TOOK(cudaMemcpy(nodes, device_nodes, bytes, cudaMemcpyDeviceToHost), nodes, error);
    }
    cudaFree(device_nodes);
    return good;
}

static int entry_seal_chunks(const EngineStream *stream, EngineSignum *leaves, EngineError *error)
{
    if (stream->chunks == 0ull)
    {
        return 1;
    }
    const size_t limbs = (size_t)((stream->bits + 31ull) / 32ull);
    const size_t leaf_bytes = (size_t)stream->chunks * sizeof(EngineSignum);
    unsigned long long *device_offsets = NULL;
    unsigned int *device_limbs = NULL;
    unsigned char *device_leaves = NULL;
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    int good = (obsignatio_level_key(OBSIGNATIO_LEVEL_CHUNK, key, error) == 0L)
            && ENGINE_TOOK(cudaMalloc((void **)&device_offsets, (size_t)stream->chunks * sizeof(unsigned long long)),
                           &device_offsets, error)
            && ENGINE_TOOK(cudaMalloc((void **)&device_limbs, (limbs + 1u) * sizeof(unsigned int)), &device_limbs, error)
            && ENGINE_TOOK(cudaMalloc((void **)&device_leaves, leaf_bytes), &device_leaves, error)
            && ENGINE_TOOK(cudaMemcpy(device_offsets, stream->offsets, (size_t)stream->chunks * sizeof(unsigned long long),
                                      cudaMemcpyHostToDevice),
                           device_offsets, error)
            && ENGINE_TOOK(cudaMemcpy(device_limbs, stream->stream, limbs * sizeof(unsigned int), cudaMemcpyHostToDevice),
                           device_limbs, error);
    if (good)
    {
        const ObsignatioBitsRequest request = {device_limbs, device_offsets, stream->chunks, stream->bits, key,
                                               OBSIGNATIO_MODE_KEYED, device_leaves, error};
        good = (obsignatio_bits(&request) == 0L)
            && ENGINE_TOOK(cudaMemcpy(leaves, device_leaves, leaf_bytes, cudaMemcpyDeviceToHost), leaves, error);
    }
    cudaFree(device_leaves);
    cudaFree(device_limbs);
    cudaFree(device_offsets);
    return good;
}

static int entry_seal_stream(const EngineStream *stream, const EngineSignum *leaves, EngineSignum *root,
                             EngineError *error)
{
    const unsigned long long offset_bytes = 8ull * stream->chunks;
    const unsigned long long bytes = offset_bytes + 8ull + (ENGINE_SIGNUM_BYTES * stream->chunks);
    unsigned char *const held = (unsigned char *)malloc((size_t)bytes);
    if (ENGINE_HELD(held != NULL, &held, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    entry_words_place(held, stream->offsets, stream->chunks);
    entry_words_place(&held[offset_bytes], &stream->bits, 1ull);
    memcpy(&held[offset_bytes + 8ull], leaves, (size_t)(ENGINE_SIGNUM_BYTES * stream->chunks));
    const int good = entry_keyed(OBSIGNATIO_LEVEL_STREAM, held, bytes, root, error);
    free(held);
    return good;
}

static int entry_seal_side_stored(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const unsigned long long stored = (section->side.leaves != 0ull) ? section->packed_bytes : 0ull;
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE_STORED, section->packed, stored, root, error);
}

static int entry_seal_side_inflated(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const unsigned long long inflated = (section->side.leaves != 0ull) ? section->side.byte_start[section->side.leaves]
                                                                        : 0ull;
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE_INFLATED, section->side.bytes, inflated, root, error);
}

static int entry_seal_side_root(EngineSignum *roots, EngineError *error)
{
    unsigned char both[2u * ENGINE_SIGNUM_BYTES];
    memcpy(both, roots[ENGINE_SEAL_SIDE_STORED].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&both[ENGINE_SIGNUM_BYTES], roots[ENGINE_SEAL_SIDE_INFLATED].bytes, ENGINE_SIGNUM_BYTES);
    return entry_keyed(OBSIGNATIO_LEVEL_SIDE, both, sizeof(both), &roots[ENGINE_SEAL_SIDE], error);
}

static int entry_seal_members(const EngineSideSection *section, EngineSignum *root, EngineError *error)
{
    const EngineSideBytes *const side = &section->side;
    const unsigned long long leaves = side->leaves;
    const unsigned long long words = (leaves != 0ull) ? ((6ull * leaves) + 2ull) : 0ull;
    const unsigned long long names = (leaves != 0ull) ? side->name_start[leaves] : 0ull;
    const unsigned long long bytes = (8ull * words) + names;
    unsigned char *const held = (unsigned char *)malloc((size_t)bytes + 1u);
    if (ENGINE_HELD(held != NULL, &held, error, ENGINE_ERROR_RESOURCE) == 0)
    {
        return 0;
    }
    if (leaves != 0ull)
    {
        unsigned char *at = held;
        entry_words_place(at, side->pixel_at, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->pixel_kept, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->byte_start, leaves + 1ull);
        at = &at[8ull * (leaves + 1ull)];
        entry_words_place(at, side->name_start, leaves + 1ull);
        at = &at[8ull * (leaves + 1ull)];
        entry_words_place(at, side->member_crc, leaves);
        at = &at[8ull * leaves];
        entry_words_place(at, side->member_bytes, leaves);
        at = &at[8ull * leaves];
        memcpy(at, side->names, (size_t)names);
    }
    const int good = entry_keyed(OBSIGNATIO_LEVEL_MEMBERS, held, bytes, root, error);
    free(held);
    return good;
}

static int entry_seal_sample(const EngineStream *stream, const EngineSideSection *section, EngineSeal *seal,
                             EngineError *error)
{
    const EngineSideBytes *const side = &section->side;
    const int sided = side->leaves != 0ull;
    const unsigned long long words[ENTRY_SAMPLE_WORDS] = {stream->extent[0],
                                                          stream->extent[1],
                                                          stream->extent[2],
                                                          stream->extent[3],
                                                          stream->chunks,
                                                          stream->bits,
                                                          stream->lane_offset,
                                                          side->leaves,
                                                          sided ? side->byte_start[side->leaves] : 0ull,
                                                          sided ? section->packed_bytes : 0ull,
                                                          sided ? side->name_start[side->leaves] : 0ull,
                                                          seal->lane_count};
    unsigned char held[(8u * ENTRY_SAMPLE_WORDS) + (ENTRY_SAMPLE_ROOTS * ENGINE_SIGNUM_BYTES)];
    entry_words_place(held, words, ENTRY_SAMPLE_WORDS);
    unsigned char *const roots = &held[8u * ENTRY_SAMPLE_WORDS];
    memcpy(roots, seal->lane_nodes[seal->lane_count - 1ull].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_STREAM].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[2u * ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_SIDE].bytes, ENGINE_SIGNUM_BYTES);
    memcpy(&roots[3u * ENGINE_SIGNUM_BYTES], seal->roots[ENGINE_SEAL_MEMBERS].bytes, ENGINE_SIGNUM_BYTES);
    return entry_keyed(OBSIGNATIO_LEVEL_SAMPLE, held, sizeof(held), &seal->roots[ENGINE_SEAL_SAMPLE], error);
}

static int entry_seal_hold(const EngineStream *stream, EngineSeal *seal, EngineError *error)
{
    memset(seal, 0, sizeof(*seal));
    seal->lane_count = obsignatio_lanes_nodes(stream->extent);
    seal->chunk_count = stream->chunks;
    seal->lane_nodes = (EngineSignum *)calloc((size_t)seal->lane_count + 1u, sizeof(EngineSignum));
    seal->chunk_leaves = (EngineSignum *)calloc((size_t)seal->chunk_count + 1u, sizeof(EngineSignum));
    return ENGINE_HELD((seal->lane_count != 0ull) && (seal->lane_nodes != NULL) && (seal->chunk_leaves != NULL), seal,
                       error, ENGINE_ERROR_RESOURCE);
}

static int entry_seal_make(const unsigned short *device_lanes, const EngineStream *stream,
                           const EngineSideSection *section, EngineSeal *seal, EngineError *error)
{
    const int good = entry_seal_hold(stream, seal, error)
                  && entry_seal_lanes(device_lanes, stream->extent, seal->lane_nodes, seal->lane_count, error)
                  && entry_seal_chunks(stream, seal->chunk_leaves, error)
                  && entry_seal_stream(stream, seal->chunk_leaves, &seal->roots[ENGINE_SEAL_STREAM], error)
                  && entry_seal_side_stored(section, &seal->roots[ENGINE_SEAL_SIDE_STORED], error)
                  && entry_seal_side_inflated(section, &seal->roots[ENGINE_SEAL_SIDE_INFLATED], error)
                  && entry_seal_side_root(seal->roots, error)
                  && entry_seal_members(section, &seal->roots[ENGINE_SEAL_MEMBERS], error)
                  && entry_seal_sample(stream, section, seal, error);
    if (good == 0)
    {
        krep_seal_release(seal);
    }
    return good;
}

static unsigned long long entry_roots_differ(const EngineSeal *fresh, const EngineSeal *stored, EngineSealRoot root)
{
    return entry_signum_same(&fresh->roots[root], &stored->roots[root]) ? 0ull : 1ull;
}

static int entry_crystal_verify(const EngineStream *file, EngineSideSection *section, const EngineSeal *seal,
                                const unsigned short *device_source, unsigned short *rebuilt,
                                EngineSampleRecord *record, EngineError *error)
{
    record->crystal_read = 1ull;
    memcpy(record->extent, file->extent, sizeof(record->extent));
    record->root = seal->roots[ENGINE_SEAL_SAMPLE];
    EngineSeal fresh;
    int good = entry_seal_hold(file, &fresh, error);
    record->shape_differ = (good && ((seal->lane_count != fresh.lane_count) || (seal->chunk_count != fresh.chunk_count)))
                             ? 1ull
                             : 0ull;
    good = good && ENGINE_HELD(record->shape_differ == 0ull, seal, error, ENGINE_ERROR_LOGIC)
        && entry_seal_chunks(file, fresh.chunk_leaves, error);
    for (unsigned long long chunk = 0ull; good && (chunk < fresh.chunk_count); chunk += 1ull)
    {
        const int differs = entry_signum_same(&fresh.chunk_leaves[chunk], &seal->chunk_leaves[chunk]) ? 0 : 1;
        record->first_chunk_differ = ((differs != 0) && (record->chunks_differ == 0ull)) ? chunk
                                                                                          : record->first_chunk_differ;
        record->chunks_differ += (differs != 0) ? 1ull : 0ull;
    }
    good = good && entry_seal_stream(file, fresh.chunk_leaves, &fresh.roots[ENGINE_SEAL_STREAM], error)
        && entry_seal_side_stored(section, &fresh.roots[ENGINE_SEAL_SIDE_STORED], error)
        && entry_seal_members(section, &fresh.roots[ENGINE_SEAL_MEMBERS], error);
    if (good)
    {
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_STREAM)
                              + entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE_STORED)
                              + entry_roots_differ(&fresh, seal, ENGINE_SEAL_MEMBERS);
    }
    const unsigned short *device_rebuilt = NULL;
    good = good && ENGINE_HELD((record->chunks_differ == 0ull) && (record->roots_differ == 0ull), seal, error,
                               ENGINE_ERROR_LOGIC)
        && entry_side_unpack(section, error)
        && entry_seal_side_inflated(section, &fresh.roots[ENGINE_SEAL_SIDE_INFLATED], error)
        && entry_seal_side_root(fresh.roots, error);
    if (good)
    {
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE_INFLATED)
                              + entry_roots_differ(&fresh, seal, ENGINE_SEAL_SIDE);
    }
    good = good && ENGINE_HELD(record->roots_differ == 0ull, seal, error, ENGINE_ERROR_LOGIC)
        && (entry_kcr_decode(file, device_source, rebuilt, &record->voxels_differ, &device_rebuilt, error) != 0)
        && entry_seal_lanes(device_rebuilt, file->extent, fresh.lane_nodes, fresh.lane_count, error);
    const unsigned long long rows = file->extent[0] * file->extent[1] * file->extent[2];
    for (unsigned long long node = 0ull; good && (node < fresh.lane_count); node += 1ull)
    {
        const int differs = entry_signum_same(&fresh.lane_nodes[node], &seal->lane_nodes[node]) ? 0 : 1;
        const int row = node < rows;
        record->first_row_differ = ((differs != 0) && row && (record->rows_differ == 0ull)) ? node
                                                                                              : record->first_row_differ;
        record->rows_differ += ((differs != 0) && row) ? 1ull : 0ull;
        record->roots_differ += ((differs != 0) && !row) ? 1ull : 0ull;
    }
    good = good && entry_seal_sample(file, section, &fresh, error);
    if (good)
    {
        record->rebuilt_root = fresh.roots[ENGINE_SEAL_SAMPLE];
        record->root_rebuilt = 1ull;
        record->roots_differ += entry_roots_differ(&fresh, seal, ENGINE_SEAL_SAMPLE);
    }
    good = good
        && ENGINE_HELD((record->rows_differ == 0ull) && (record->roots_differ == 0ull) && (record->voxels_differ == 0ull),
                       seal, error, ENGINE_ERROR_LOGIC);
    krep_seal_release(&fresh);
    return good;
}

static int entry_set_root(const EngineSignum *roots, unsigned long long count, EngineSignum *root, EngineError *error)
{
    // the roots are an array of 32-byte signa, hashed as their bytes
    return entry_keyed(OBSIGNATIO_LEVEL_SET, (const unsigned char *)roots, count * ENGINE_SIGNUM_BYTES, root, error);
}

#define ENTRY_ROW_TEXT 640u

static void entry_signum_text(ScripturaLine *line, const EngineSignum *signum)
{
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        scriptura_hex(line, signum->bytes[byte], 2u);
    }
}

static void entry_percent(ScripturaLine *line, unsigned long long part, unsigned long long whole)
{
    scriptura_decimal_columns(line, (whole != 0ull) ? ((100ull * part) / whole) : 0ull, 3u);
    scriptura_character(line, '.');
    scriptura_decimal(line, (whole != 0ull) ? (((1000ull * part) / whole) % 10ull) : 0ull, 1u);
    scriptura_character(line, '%');
}

static unsigned long long entry_report_room(char *const *samples, unsigned long long reached, const char *source,
                                            const char *set)
{
    const unsigned long long fixed = scriptura_length(source, ENTRY_PATH_ROOM) + scriptura_length(set, ENTRY_PATH_ROOM);
    unsigned long long room = (2ull * ENTRY_ROW_TEXT) + fixed;
    for (unsigned long long sample = 0ull; sample < reached; sample += 1ull)
    {
        room += ENTRY_ROW_TEXT + fixed + scriptura_length(samples[sample], ENTRY_PATH_ROOM);
    }
    return room;
}

static void entry_report_total(ScripturaLine *line, const EngineSetReport *report, unsigned int count)
{
    scriptura_text(line, "\n  ");
    scriptura_decimal(line, report->held, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " samples held, ");
    scriptura_decimal(line, report->voxels, 1u);
    scriptura_text(line, " voxels: ");
    scriptura_decimal(line, report->crystal_bytes, 1u);
    scriptura_text(line, " bytes of ");
    scriptura_decimal(line, report->raw_bytes, 1u);
    scriptura_text(line, " raw, ");
    entry_percent(line, report->crystal_bytes, report->raw_bytes);
    scriptura_text(line, ", in ");
    scriptura_decimal(line, report->microseconds / 1000ull, 1u);
    if (report->held != count)
    {
        scriptura_text(line, " ms\n  no set root: it seals every sample's, and not every sample held\n");
        return;
    }
    scriptura_text(line, " ms\n  the set's root, sealing every sample's in the order named: ");
    entry_signum_text(line, &report->set_root);
    scriptura_character(line, '\n');
}

static void entry_seal_failure(ScripturaLine *line, const EngineSampleRecord *record)
{
    if (record->crystal_read == 0ull)
    {
        scriptura_text(line, "the file did not read as a crystal (missing, short, or laid out otherwise than its head "
                             "describes), so no node was compared");
        return;
    }
    if (record->shape_differ != 0ull)
    {
        scriptura_text(line, "the head's shape disagrees with its seal's node counts, so no node was compared");
        return;
    }
    scriptura_decimal(line, record->chunks_differ, 1u);
    scriptura_text(line, " stored chunks differ");
    if (record->chunks_differ != 0ull)
    {
        scriptura_text(line, " (first chunk ");
        scriptura_decimal(line, record->first_chunk_differ, 1u);
        scriptura_character(line, ')');
    }
    scriptura_text(line, ", ");
    scriptura_decimal(line, record->rows_differ, 1u);
    scriptura_text(line, " rows differ");
    if ((record->rows_differ != 0ull) && (record->extent[1] != 0ull) && (record->extent[2] != 0ull))
    {
        const unsigned long long row = record->first_row_differ;
        scriptura_text(line, " (first at t ");
        scriptura_decimal(line, row / (record->extent[1] * record->extent[2]), 1u);
        scriptura_text(line, ", z ");
        scriptura_decimal(line, (row / record->extent[2]) % record->extent[1], 1u);
        scriptura_text(line, ", y ");
        scriptura_decimal(line, row % record->extent[2], 1u);
        scriptura_character(line, ')');
    }
    scriptura_text(line, ", ");
    scriptura_decimal(line, record->roots_differ, 1u);
    scriptura_text(line, " other nodes differ; ");
    if (record->root_rebuilt == 0ull)
    {
        scriptura_text(line, "the check stopped before a root was rebuilt, against the file's ");
        entry_signum_text(line, &record->root);
        return;
    }
    scriptura_text(line, "root ");
    entry_signum_text(line, &record->rebuilt_root);
    scriptura_text(line, " rebuilt against the file's ");
    entry_signum_text(line, &record->root);
}

static int entry_report_write(ScripturaLine *line, FILE *file)
{
    const int written = scriptura_write(line, file);
    free(line->out);
    return written;
}

extern "C" int engine_ingest_print(const EngineIngestRequest *request, FILE *file)
{
    const EngineSetReport *const report = request->report;
    if ((report == NULL) || (report->samples == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.room = entry_report_room(request->samples, report->reached, request->source, request->set);
    line.out = (char *)malloc((size_t)line.room);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    for (unsigned long long sample = 0ull; sample < report->reached; sample += 1ull)
    {
        const EngineSampleRecord *const record = &report->samples[sample];
        scriptura_text(&line, "  ");
        if (record->held != 0ull)
        {
            scriptura_text_columns(&line, request->samples[sample], 24u);
            scriptura_character(&line, ' ');
            scriptura_decimal(&line, record->floors, 1u);
            scriptura_text(&line, " floors, rebuilt from the file, voxel for voxel and pixel for pixel: ");
            scriptura_decimal_columns(&line, record->crystal_bytes, 11u);
            scriptura_text(&line, " bytes of ");
            scriptura_decimal_columns(&line, record->raw_bytes, 11u);
            scriptura_text(&line, ", ");
            entry_percent(&line, record->crystal_bytes, record->raw_bytes);
            scriptura_text(&line, ", sealed ");
            entry_signum_text(&line, &record->root);
        }
        else if (record->placed == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": no source for it under ");
            scriptura_text(&line, request->source);
            scriptura_text(&line, ", or its place in ");
            scriptura_text(&line, request->set);
            scriptura_text(&line, " could not be made");
        }
        else if (record->source_read == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": its source under ");
            scriptura_text(&line, request->source);
            scriptura_text(&line, " could not be read; nothing kept");
        }
        else if (record->crystal_written == 0ull)
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": its " ENTRY_CRYSTAL_SUFFIX " could not be written; nothing kept");
        }
        else
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not rebuild its source: ");
            scriptura_decimal(&line, record->voxels_differ, 1u);
            scriptura_text(&line, " voxels differ on the device, ");
            scriptura_decimal(&line, record->pixels_differ, 1u);
            scriptura_text(&line, " pixels off it, ");
            entry_seal_failure(&line, record);
            scriptura_text(&line, "; nothing kept");
        }
        scriptura_character(&line, '\n');
    }
    entry_report_total(&line, report, request->count);
    return entry_report_write(&line, file);
}

extern "C" int engine_prove_print(const EngineSetRequest *request, FILE *file)
{
    const EngineSetReport *const report = request->report;
    if ((report == NULL) || (report->samples == NULL))
    {
        return 0;
    }
    ScripturaLine line;
    line.room = entry_report_room(request->samples, report->reached, "", request->set);
    line.out = (char *)malloc((size_t)line.room);
    line.at = 0ull;
    if (line.out == NULL)
    {
        return 0;
    }
    for (unsigned long long sample = 0ull; sample < report->reached; sample += 1ull)
    {
        const EngineSampleRecord *const record = &report->samples[sample];
        scriptura_text(&line, "  ");
        if (record->held != 0ull)
        {
            scriptura_text_columns(&line, request->samples[sample], 24u);
            scriptura_text(&line, " decoded from the file alone, every node of its seal holds, root ");
            entry_signum_text(&line, &record->root);
            scriptura_text(&line, ": ");
            scriptura_decimal_columns(&line, record->crystal_bytes, 11u);
            scriptura_text(&line, " bytes of ");
            scriptura_decimal_columns(&line, record->raw_bytes, 11u);
            scriptura_text(&line, ", ");
            entry_percent(&line, record->crystal_bytes, record->raw_bytes);
        }
        else
        {
            scriptura_text(&line, request->samples[sample]);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not hold: ");
            entry_seal_failure(&line, record);
        }
        scriptura_character(&line, '\n');
    }
    entry_report_total(&line, report, request->count);
    return entry_report_write(&line, file);
}

extern "C" long engine_ingest_set(const EngineIngestRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    if (ENGINE_HELD((request->source != NULL) && (request->set != NULL)
                        && ((request->samples != NULL) || (request->count == 0u)),
                    request, error, ENGINE_ERROR_REQUEST)
        == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    EngineSetReport silent;
    memset(&silent, 0, sizeof(silent));
    EngineSetReport *const report = (request->report != NULL) ? request->report : &silent;
    EngineSampleRecord *const records = report->samples;
    memset(report, 0, sizeof(*report));
    report->samples = records;
    const unsigned long long began = engine_clock_microseconds();
    EngineSignum *const sample_roots = (EngineSignum *)calloc((size_t)request->count + 1u, sizeof(EngineSignum));
    int good = ENGINE_HELD(sample_roots != NULL, &sample_roots, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; good && (sample < request->count); sample += 1u)
    {
        EngineSampleRecord unkept;
        EngineSampleRecord *const record = (records != NULL) ? &records[sample] : &unkept;
        memset(record, 0, sizeof(*record));
        report->reached = sample + 1ull;
        char source_path[ENTRY_PATH_ROOM];
        char kcr_path[ENTRY_PATH_ROOM];
        const int archived = entry_is_file(request->source);
        const int placed = archived ? (snprintf(source_path, sizeof(source_path), "%s", request->source) > 0)
                                    : engine_source_find(request->source, request->samples[sample], source_path,
                                                         sizeof(source_path));
        unsigned int made = 0u;
        good = ENGINE_HELD(placed != 0, request->samples[sample], error, ENGINE_ERROR_REQUEST)
            && ENGINE_HELD(engine_sample_path(kcr_path, sizeof(kcr_path), request->set, request->samples[sample],
                                              ENTRY_CRYSTAL_SUFFIX)
                               != 0,
                           request->samples[sample], error, ENGINE_ERROR_REQUEST)
            && ENGINE_IO(entry_directories_make(kcr_path, 0, &made) != 0, kcr_path, error);
        if (good == 0)
        {
            entry_directories_remove(kcr_path, 0, made);
            break;
        }
        record->placed = 1ull;
        EngineSideSection section;
        memset(&section, 0, sizeof(section));
        unsigned long long lane_offset = 0ull;
        EngineSourceRequest source;
        source.path = source_path;
        source.member = archived ? request->samples[sample] : NULL;
        source.axes = request->axes;
        source.side = &section.side;
        source.lane_offset = &lane_offset;
        source.error = error;
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *host_lanes = NULL;
        good = ENGINE_HELD(engine_source_read(&source, extent, &host_lanes) == 0L, source_path, error,
                           ENGINE_ERROR_REQUEST)
            && entry_side_pack(&section, error);
        section.side.lane_offset = lane_offset;
        source.side = NULL;
        record->source_read = good ? 1ull : 0ull;
        const unsigned long long lanes = good ? entry_lanes(extent) : 0ull;
        unsigned short *device_lanes = NULL;
        good = good && ENGINE_HELD(lanes != 0ull, extent, error, ENGINE_ERROR_REQUEST)
            && ENGINE_TOOK(cudaMalloc((void **)&device_lanes, (size_t)lanes * sizeof(unsigned short)), &device_lanes,
                           error)
            && ENGINE_TOOK(cudaMemcpy(device_lanes, host_lanes, (size_t)lanes * sizeof(unsigned short),
                                      cudaMemcpyHostToDevice),
                           device_lanes, error);
        free(host_lanes);

        EngineStream written;
        unsigned int floors = 0u;
        memset(&written, 0, sizeof(written));
        EngineSeal seal;
        memset(&seal, 0, sizeof(seal));
        good = good && (entry_kcr_encode(device_lanes, extent, &written, &floors, error) != 0);
        written.lane_offset = lane_offset;
        good = good && entry_seal_make(device_lanes, &written, &section, &seal, error);
        const KrepCrystalRequest write = {kcr_path, &written, &section, &seal, error};
        good = good && (krep_crystal_write(&write) != 0);
        record->crystal_written = good ? 1ull : 0ull;

        EngineStream file;
        memset(&file, 0, sizeof(file));
        EngineSideSection back;
        memset(&back, 0, sizeof(back));
        EngineSeal back_seal;
        memset(&back_seal, 0, sizeof(back_seal));
        unsigned long long pixels_differ = 0ull;
        std::vector<unsigned short> rebuilt(good ? (size_t)lanes : 0u);
        const KrepCrystalRequest read = {kcr_path, &file, &back, &back_seal, error};
        good = good && krep_crystal_read(&read)
            && ENGINE_HELD((memcmp(file.extent, extent, sizeof(extent)) == 0) && (file.chunks == written.chunks)
                               && (file.bits == written.bits) && (file.lane_offset == written.lane_offset)
                               && entry_signum_same(&back_seal.roots[ENGINE_SEAL_SAMPLE], &seal.roots[ENGINE_SEAL_SAMPLE]),
                           &file, error, ENGINE_ERROR_LOGIC)
            && entry_crystal_verify(&file, &back, &back_seal, device_lanes, rebuilt.data(), record, error)
            && ENGINE_HELD(entry_side_same(&back.side, &section.side), &back, error, ENGINE_ERROR_LOGIC);
        krep_crystal_release(&file);
        krep_side_release(&back);
        krep_seal_release(&back_seal);
        cudaFree(device_lanes);
        unsigned long long again[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *disk = NULL;
        good = good
            && ENGINE_HELD(engine_source_read(&source, again, &disk) == 0L, source_path, error, ENGINE_ERROR_REQUEST)
            && ENGINE_HELD(memcmp(again, extent, sizeof(again)) == 0, again, error, ENGINE_ERROR_LOGIC);
        if (good)
        {
            for (size_t pixel = 0u; pixel < (size_t)lanes; pixel += 1u)
            {
                pixels_differ += (disk[pixel] != rebuilt[pixel]) ? 1ull : 0ull;
            }
            good = ENGINE_HELD(pixels_differ == 0ull, &pixels_differ, error, ENGINE_ERROR_LOGIC);
        }
        free(disk);
        record->floors = floors;
        record->crystal_bytes = krep_crystal_bytes(&written, &section, &seal);
        record->raw_bytes = lanes * 2ull;
        record->root = seal.roots[ENGINE_SEAL_SAMPLE];
        record->pixels_differ = pixels_differ;
        krep_side_release(&section);
        krep_seal_release(&seal);
        if (good == 0)
        {
            remove(kcr_path);
            entry_directories_remove(kcr_path, 0, made);
            break;
        }
        record->held = 1ull;
        sample_roots[report->held] = record->root;
        report->held += 1ull;
        report->raw_bytes += record->raw_bytes;
        report->crystal_bytes += record->crystal_bytes;
        report->voxels += lanes;
    }
    zip_held_release();
    good = good && entry_set_root(sample_roots, report->held, &report->set_root, error);
    free(sample_roots);
    report->microseconds = engine_clock_microseconds() - began;
    if ((good == 0) || (report->held != request->count))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" long engine_kcr_prove_set(const EngineSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->error;
    if (ENGINE_HELD((request->set != NULL) && ((request->samples != NULL) || (request->count == 0u)), request, error,
                    ENGINE_ERROR_REQUEST)
        == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    EngineSetReport silent;
    memset(&silent, 0, sizeof(silent));
    EngineSetReport *const report = (request->report != NULL) ? request->report : &silent;
    EngineSampleRecord *const records = report->samples;
    memset(report, 0, sizeof(*report));
    report->samples = records;
    const unsigned long long began = engine_clock_microseconds();
    EngineSignum *const sample_roots = (EngineSignum *)calloc((size_t)request->count + 1u, sizeof(EngineSignum));
    const int rooted = ENGINE_HELD(sample_roots != NULL, &sample_roots, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; rooted && (sample < request->count); sample += 1u)
    {
        EngineSampleRecord unkept;
        EngineSampleRecord *const record = (records != NULL) ? &records[sample] : &unkept;
        memset(record, 0, sizeof(*record));
        report->reached = sample + 1ull;
        char kcr_path[ENTRY_PATH_ROOM];
        EngineStream file;
        memset(&file, 0, sizeof(file));
        EngineSideSection section;
        memset(&section, 0, sizeof(section));
        EngineSeal seal;
        memset(&seal, 0, sizeof(seal));
        const KrepCrystalRequest read = {kcr_path, &file, &section, &seal, error};
        const int held = ENGINE_HELD(engine_sample_path(kcr_path, sizeof(kcr_path), request->set,
                                                        request->samples[sample], ENTRY_CRYSTAL_SUFFIX)
                                         != 0,
                                     request->samples[sample], error, ENGINE_ERROR_REQUEST)
                      && krep_crystal_read(&read)
                      && entry_crystal_verify(&file, &section, &seal, NULL, NULL, record, error);
        const unsigned long long lanes = entry_lanes(file.extent);
        record->placed = 1ull;
        record->crystal_bytes = krep_crystal_bytes(&file, &section, &seal);
        record->raw_bytes = lanes * 2ull;
        krep_crystal_release(&file);
        krep_side_release(&section);
        krep_seal_release(&seal);
        if (held == 0)
        {
            continue;
        }
        record->held = 1ull;
        sample_roots[report->held] = record->root;
        report->held += 1ull;
        report->raw_bytes += record->raw_bytes;
        report->crystal_bytes += record->crystal_bytes;
        report->voxels += lanes;
    }
    const int sealed = rooted && entry_set_root(sample_roots, report->held, &report->set_root, error);
    free(sample_roots);
    report->microseconds = engine_clock_microseconds() - began;
    if ((sealed == 0) || (report->held != request->count))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" void engine_side_release(EngineSideBytes *side)
{
    EngineSideSection section;
    memset(&section, 0, sizeof(section));
    section.side = *side;
    krep_side_release(&section);
    memset(side, 0, sizeof(*side));
}

extern "C" long engine_kcr_load(const char *set, const char *sample, unsigned long long extent[4],
                                unsigned short **volume, EngineSignum *root, EngineSideBytes *side,
                                EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    if (ENGINE_HELD((extent != NULL) && (volume != NULL) && (root != NULL), &volume, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    *volume = NULL;
    memset(root, 0, sizeof(*root));
    char kcr_path[ENTRY_PATH_ROOM];
    EngineStream file;
    memset(&file, 0, sizeof(file));
    EngineSideSection section;
    memset(&section, 0, sizeof(section));
    EngineSeal seal;
    memset(&seal, 0, sizeof(seal));
    EngineSampleRecord record;
    memset(&record, 0, sizeof(record));
    const KrepCrystalRequest read = {kcr_path, &file, &section, &seal, error};
    int good = ENGINE_HELD(engine_sample_path(kcr_path, sizeof(kcr_path), set, sample, ENTRY_CRYSTAL_SUFFIX) != 0,
                           sample, error, ENGINE_ERROR_REQUEST)
            && krep_crystal_read(&read);
    const unsigned long long lanes = good ? entry_lanes(file.extent) : 0ull;
    unsigned short *const rebuilt = good ? (unsigned short *)malloc((size_t)lanes * sizeof(unsigned short)) : NULL;
    good = good && ENGINE_HELD(rebuilt != NULL, &rebuilt, error, ENGINE_ERROR_RESOURCE)
        && entry_crystal_verify(&file, &section, &seal, NULL, rebuilt, &record, error);
    krep_crystal_release(&file);
    krep_seal_release(&seal);
    if (good == 0)
    {
        free(rebuilt);
        krep_side_release(&section);
        ScripturaLine line;
        line.room = ENTRY_ROW_TEXT + scriptura_length(sample, ENTRY_PATH_ROOM);
        line.out = (char *)malloc((size_t)line.room);
        line.at = 0ull;
        if (line.out != NULL)
        {
            scriptura_text(&line, "  ");
            scriptura_text(&line, sample);
            scriptura_text(&line, ": the " ENTRY_CRYSTAL_SUFFIX " did not load: ");
            entry_seal_failure(&line, &record);
            scriptura_character(&line, '\n');
            entry_report_write(&line, stderr);
        }
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    memcpy(extent, file.extent, sizeof(file.extent));
    *volume = rebuilt;
    *root = record.root;
    if (side != NULL)
    {
        *side = section.side;
        side->lane_offset = file.lane_offset;
        free(section.packed);
    }
    else
    {
        krep_side_release(&section);
    }
    return 0L;
}

static int entry_history_same(const EngineHistory *one, const EngineHistory *other)
{
    const size_t entries = (size_t)(one->windows * one->windows);
    const size_t words = (size_t)(one->windows * one->extent[1] * one->extent[2] * one->extent[3]);
    return (memcmp(one->extent, other->extent, sizeof(one->extent)) == 0) && (one->windows == other->windows)
        && entry_signum_same(&one->sample, &other->sample) && (one->payload_crc == other->payload_crc)
        && (one->cloud_crc == other->cloud_crc)
        && (memcmp(one->cloud, other->cloud, entries * sizeof(unsigned long long)) == 0)
        && (memcmp(one->history, other->history, words * sizeof(unsigned long long)) == 0);
}

extern "C" long engine_entropy_set(const EngineEntropySetRequest *request)
{
    if ((request == NULL) || (request->set.error == NULL))
    {
        return ENGINE_REFUSED;
    }
    EngineError *const error = request->set.error;
    if (ENGINE_HELD((request->set.set != NULL) && (request->set.samples != NULL), request, error, ENGINE_ERROR_REQUEST)
        == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    int good = 1;
    for (unsigned int sample = 0u; good && (sample < request->set.count); sample += 1u)
    {
        const char *const name = request->set.samples[sample];
        char path[ENTRY_PATH_ROOM];
        char kcr_path[ENTRY_PATH_ROOM];
        good = ENGINE_HELD(engine_sample_path(path, sizeof(path), request->set.set, name, ENTRY_NOISE_FLOOR_SUFFIX) != 0,
                           name, error, ENGINE_ERROR_REQUEST)
            && ENGINE_HELD(engine_sample_path(kcr_path, sizeof(kcr_path), request->set.set, name, ENTRY_CRYSTAL_SUFFIX) != 0, name,
                           error, ENGINE_ERROR_REQUEST);
        if (good == 0)
        {
            break;
        }
        const unsigned long long began = engine_clock_microseconds();
        EngineStream standing;
        EngineSignum standing_root;
        EngineError probe;
        memset(&probe, 0, sizeof(probe));
        if ((request->keep != 0u) && krep_crystal_head(kcr_path, &standing, &standing_root, &probe))
        {
            EngineHistory kept;
            const int whole = krep_history_read(path, &kept, 1u, &probe);
            const int same = whole && entry_signum_same(&kept.sample, &standing_root);
            krep_history_release(&kept);
            if (same)
            {
                printf("  %-24s laid down already: read back whole, projected from the " ENTRY_CRYSTAL_SUFFIX
                       " as it stands, in %llu ms\n",
                       name, (engine_clock_microseconds() - began) / 1000ull);
                fflush(stdout);
                continue;
            }
        }

        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        EngineSignum sample_root;
        memset(&sample_root, 0, sizeof(sample_root));
        good = (engine_kcr_load(request->set.set, name, extent, &volume, &sample_root, NULL, error) == 0L);
        const long windows = good ? entropy_history_windows(extent, error) : ENTROPY_HISTORY_REFUSED;
        good = good && (windows != ENTROPY_HISTORY_REFUSED);
        const unsigned long long window_count = good ? (unsigned long long)windows : 0ull;
        std::vector<unsigned long long> cloud((size_t)(window_count * window_count));
        std::vector<unsigned long long> payload((size_t)(window_count * extent[1] * extent[2] * extent[3]));
        EngineHistory history;
        memset(&history, 0, sizeof(history));
        history.cloud = cloud.data();
        history.history = payload.data();
        EntropyHistoryProjectRequest project;
        memset(&project, 0, sizeof(project));
        project.volume = volume;
        memcpy(project.extent, extent, sizeof(project.extent));
        project.sample = sample_root;
        project.history = &history;
        project.error = error;
        unsigned long long broken = 0ull;
        good = good && (entropy_history_project(&project, &broken) == 0L);
        free(volume);
        if (ENGINE_HELD(broken == 0ull, &broken, error, ENGINE_ERROR_LOGIC) == 0)
        {
            fprintf(stderr, "  %s: entropy not conserved: %llu voxels' flips break parity with their net change\n", name,
                    broken);
            good = 0;
            break;
        }

        EngineHistory read;
        memset(&read, 0, sizeof(read));
        good = good && ENGINE_IO(engine_directories_make(path, 0) != 0, path, error)
            && krep_history_write(path, &history, error) && krep_history_read(path, &read, 1u, error)
            && ENGINE_HELD(entry_history_same(&history, &read) != 0, &read, error, ENGINE_ERROR_LOGIC);
        krep_history_release(&read);
        if (good == 0)
        {
            fprintf(stderr, "  %s: the entropy history was not written and read back whole\n", name);
            break;
        }
        printf("  %-24s %llu frames, %llu windows of %u transitions, entropy conserved at every voxel, %llu MiB, read "
               "back whole, CRC-64 %016llx, in %llu ms\n", name, extent[0], window_count, ENGINE_HISTORY_WINDOW,
               (unsigned long long)(payload.size() * sizeof(unsigned long long)) >> 20u, history.payload_crc,
               (engine_clock_microseconds() - began) / 1000ull);
        entropy_history_report(&history);
        fflush(stdout);
    }
    if (good == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" long engine_entropy_cloud(const char *path, unsigned int *windows, unsigned long long *cloud,
                                     EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    EngineHistory held;
    if ((ENGINE_HELD((windows != NULL) && (cloud != NULL), &cloud, error, ENGINE_ERROR_REQUEST) == 0)
        || (krep_history_read(path, &held, 0u, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    *windows = (unsigned int)held.windows;
    memcpy(cloud, held.cloud, (size_t)(held.windows * held.windows) * sizeof(unsigned long long));
    krep_history_release(&held);
    return 0L;
}

extern "C" long engine_entropy_history_read(const char *path, EngineHistory *history, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    if (krep_history_read(path, history, 1u, error) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" void engine_entropy_history_release(EngineHistory *history)
{
    krep_history_release(history);
}

extern "C" long engine_bodies_write(const char *set, const char *sample, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    if (ENGINE_HELD(table != NULL, &table, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    char path[ENTRY_PATH_ROOM];
    table->crc = crc_words(CRC_TABLE, table->words, (size_t)(table->bodies * ENGINE_BODY_WORDS));
    if ((ENGINE_HELD(engine_sample_path(path, sizeof(path), set, sample, ENTRY_CONSTRUCTION_SET_SUFFIX) != 0, sample,
                     error, ENGINE_ERROR_REQUEST) == 0)
        || (krep_bodies_write(path, table, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    EngineBodyTable back;
    const int held = krep_bodies_read(path, &back, error);
    const int same = (held != 0)
                  && ENGINE_HELD((back.bodies == table->bodies) && (back.crc == table->crc)
                                     && (memcmp(back.frame_start, table->frame_start,
                                                (size_t)(table->frames + 1ull) * sizeof(unsigned long long))
                                         == 0)
                                     && (memcmp(back.words, table->words,
                                                (size_t)(table->bodies * ENGINE_BODY_WORDS) * sizeof(unsigned long long))
                                         == 0),
                                 &back, error, ENGINE_ERROR_LOGIC);
    krep_bodies_release(&back);
    if (same == 0)
    {
        remove(path);
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" long engine_bodies_read(const char *set, const char *sample, EngineBodyTable *table, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_REFUSED;
    }
    char path[ENTRY_PATH_ROOM];
    if ((ENGINE_HELD(engine_sample_path(path, sizeof(path), set, sample, ENTRY_CONSTRUCTION_SET_SUFFIX) != 0, sample,
                     error, ENGINE_ERROR_REQUEST) == 0)
        || (krep_bodies_read(path, table, error) == 0))
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_REFUSED;
    }
    return 0L;
}

extern "C" void engine_bodies_release(EngineBodyTable *table)
{
    krep_bodies_release(table);
}
