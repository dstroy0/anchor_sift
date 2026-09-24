// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "flatten.h"

#include "apxrep.h"
#include "cycle.h"
#include "engine.h"
#include "max_tree.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define FLATTEN_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define FLATTEN_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

#define FLATTEN_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

static int flatten_write_iapx(const char *path, const MaxTreeLayout *layout, char *const *names, unsigned int count,
                              const unsigned int *device_magnitudes, unsigned long long bodies, EngineError *error)
{
    const size_t words = (size_t)bodies * layout->limbs;
    unsigned int *const host = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    unsigned int *const again = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    int good = FLATTEN_HELD(host != NULL, &host, error, ENGINE_ERROR_RESOURCE)
            && FLATTEN_HELD(again != NULL, &again, error, ENGINE_ERROR_RESOURCE)
            && FLATTEN_TOOK(cudaMemcpy(host, device_magnitudes, words * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                            host, error);
    const unsigned int head[4] = {MAX_TREE_FIELDS, layout->total_bits, layout->limbs, count};
    FILE *file = good ? fopen(path, "wb") : NULL;
    good = good && FLATTEN_IO(file != NULL, path, error)
        && FLATTEN_IO(apxrep_head_write(file, APXREP_KIND_INPUT) != 0, file, error)
        && FLATTEN_IO(apxrep_limbs_write(file, head, 4u) != 0, head, error)
        && FLATTEN_IO(apxrep_limbs_write(file, layout->bits, MAX_TREE_FIELDS) != 0, layout->bits, error)
        && FLATTEN_IO(apxrep_limbs_write(file, layout->offset, MAX_TREE_FIELDS) != 0, layout->offset, error);
    for (unsigned int sample = 0u; good && (sample < count); sample += 1u)
    {
        const unsigned int length = (unsigned int)strlen(names[sample]);
        good = FLATTEN_IO(apxrep_limbs_write(file, &length, 1u) != 0, &length, error)
            && FLATTEN_IO(fwrite(names[sample], 1u, length, file) == length, names[sample], error);
    }
    good = good && FLATTEN_IO(apxrep_words_write(file, &bodies, 1u) != 0, &bodies, error)
        && FLATTEN_IO(apxrep_limbs_write(file, host, words) != 0, host, error);
    if (file != NULL)
    {
        good = FLATTEN_IO(fclose(file) == 0, file, error) && good;
    }

    file = good ? fopen(path, "rb") : NULL;
    unsigned int read_head[4] = {0u, 0u, 0u, 0u};
    unsigned int read_bits[MAX_TREE_FIELDS];
    unsigned int read_offset[MAX_TREE_FIELDS];
    good = good && FLATTEN_IO(file != NULL, path, error)
        && FLATTEN_IO(apxrep_head_read(file, APXREP_KIND_INPUT) != 0, file, error)
        && FLATTEN_IO(apxrep_limbs_read(file, read_head, 4u) != 0, read_head, error)
        && FLATTEN_HELD(memcmp(read_head, head, sizeof(head)) == 0, read_head, error, ENGINE_ERROR_LOGIC)
        && FLATTEN_IO(apxrep_limbs_read(file, read_bits, MAX_TREE_FIELDS) != 0, read_bits, error)
        && FLATTEN_HELD(memcmp(read_bits, layout->bits, sizeof(read_bits)) == 0, read_bits, error, ENGINE_ERROR_LOGIC)
        && FLATTEN_IO(apxrep_limbs_read(file, read_offset, MAX_TREE_FIELDS) != 0, read_offset, error)
        && FLATTEN_HELD(memcmp(read_offset, layout->offset, sizeof(read_offset)) == 0, read_offset, error,
                        ENGINE_ERROR_LOGIC);
    for (unsigned int sample = 0u; good && (sample < count); sample += 1u)
    {
        char name[ENGINE_PATH_ROOM];
        unsigned int length = 0u;
        good = FLATTEN_IO(apxrep_limbs_read(file, &length, 1u) != 0, &length, error)
            && FLATTEN_HELD(length < sizeof(name), &length, error, ENGINE_ERROR_LOGIC)
            && FLATTEN_IO(fread(name, 1u, length, file) == length, name, error)
            && FLATTEN_HELD((length == strlen(names[sample])) && (memcmp(name, names[sample], length) == 0), name, error,
                            ENGINE_ERROR_LOGIC);
    }
    unsigned long long read_bodies = 0ull;
    good = good && FLATTEN_IO(apxrep_words_read(file, &read_bodies, 1u) != 0, &read_bodies, error)
        && FLATTEN_HELD(read_bodies == bodies, &read_bodies, error, ENGINE_ERROR_LOGIC)
        && FLATTEN_IO(apxrep_limbs_read(file, again, words) != 0, again, error)
        && FLATTEN_HELD(memcmp(again, host, words * sizeof(unsigned int)) == 0, again, error, ENGINE_ERROR_LOGIC)
        && FLATTEN_HELD(fgetc(file) == EOF, file, error, ENGINE_ERROR_LOGIC);
    if (file != NULL)
    {
        fclose(file);
    }
    free(host);
    free(again);
    return good;
}

int flatten_read(const char *set, FlattenHeld *held, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    memset(held, 0, sizeof(*held));
    char path[ENGINE_PATH_ROOM];
    const int written = snprintf(path, sizeof(path), "%s/flattened.iapx", set);
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const file = named ? fopen(path, "rb") : NULL;
    unsigned int head[4] = {0u, 0u, 0u, 0u};
    int good = FLATTEN_HELD(named, set, error, ENGINE_ERROR_REQUEST) && FLATTEN_IO(file != NULL, path, error)
            && FLATTEN_IO(apxrep_head_read(file, APXREP_KIND_INPUT) != 0, file, error)
            && FLATTEN_IO(apxrep_limbs_read(file, head, 4u) != 0, head, error)
            && FLATTEN_HELD(head[0] == MAX_TREE_FIELDS, &head[0], error, ENGINE_ERROR_LOGIC)
            && FLATTEN_IO(apxrep_limbs_read(file, held->layout.bits, MAX_TREE_FIELDS) != 0, held->layout.bits, error)
            && FLATTEN_IO(apxrep_limbs_read(file, held->layout.offset, MAX_TREE_FIELDS) != 0, held->layout.offset,
                          error);
    held->layout.total_bits = head[1];
    held->layout.limbs = head[2];
    held->samples = head[3];
    held->names = good ? (char **)calloc((size_t)held->samples + 1u, sizeof(char *)) : NULL;
    good = good && FLATTEN_HELD(held->names != NULL, &held->names, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; good && (sample < held->samples); sample += 1u)
    {
        unsigned int length = 0u;
        good = FLATTEN_IO(apxrep_limbs_read(file, &length, 1u) != 0, &length, error)
            && FLATTEN_HELD(length < 1024u, &length, error, ENGINE_ERROR_LOGIC);
        held->names[sample] = good ? (char *)calloc((size_t)length + 1u, 1u) : NULL;
        good = good && FLATTEN_HELD(held->names[sample] != NULL, &held->names[sample], error, ENGINE_ERROR_RESOURCE)
            && FLATTEN_IO(fread(held->names[sample], 1u, length, file) == length, held->names[sample], error);
    }
    good = good && FLATTEN_IO(apxrep_words_read(file, &held->bodies, 1u) != 0, &held->bodies, error)
        && FLATTEN_HELD((held->layout.limbs != 0u) && (held->layout.total_bits <= (32u * held->layout.limbs)),
                        &held->layout, error, ENGINE_ERROR_LOGIC);
    const size_t words = good ? (size_t)held->bodies * held->layout.limbs : 0u;
    held->magnitudes = good ? (unsigned int *)malloc((words + 1u) * sizeof(unsigned int)) : NULL;
    good = good && FLATTEN_HELD(held->magnitudes != NULL, &held->magnitudes, error, ENGINE_ERROR_RESOURCE)
        && FLATTEN_IO(apxrep_limbs_read(file, held->magnitudes, words) != 0, held->magnitudes, error)
        && FLATTEN_HELD(fgetc(file) == EOF, file, error, ENGINE_ERROR_LOGIC);
    if (file != NULL)
    {
        fclose(file);
    }
    if (good == 0)
    {
        flatten_release(held);
    }
    return good;
}

void flatten_release(FlattenHeld *held)
{
    for (unsigned int sample = 0u; (held->names != NULL) && (sample < held->samples); sample += 1u)
    {
        free(held->names[sample]);
    }
    free(held->names);
    free(held->magnitudes);
    memset(held, 0, sizeof(*held));
}

static int flatten_header(const char *set, const char *name, unsigned int header[4], EngineError *error)
{
    unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
    const int good = FLATTEN_HELD(engine_iapx_head(set, name, extent, error) == 0L, name, error, ENGINE_ERROR_REQUEST)
                  && FLATTEN_HELD((extent[0] <= 0xFFFFFFFFull) && (extent[1] <= 0xFFFFFFFFull)
                                  && (extent[2] <= 0xFFFFFFFFull) && (extent[3] <= 0xFFFFFFFFull),
                                  extent, error, ENGINE_ERROR_REQUEST);
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        header[axis] = good ? (unsigned int)extent[axis] : 0u;
    }
    return good;
}

int flatten_set(const FlattenSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return 0;
    }
    EngineError *const error = request->error;
    const char *const set = request->set;
    char *const *const names = request->names;
    const unsigned int count = request->count;
    unsigned int largest[3] = {0u, 0u, 0u};
    unsigned int most_frames = 0u;
    unsigned long long all_frames = 0ull;
    int good = 1;
    for (unsigned int sample = 0u; good && (sample < count); sample += 1u)
    {
        unsigned int header[4] = {0u, 0u, 0u, 0u};
        good = flatten_header(set, names[sample], header, error);
        for (unsigned int axis = 0u; good && (axis < 3u); axis += 1u)
        {
            largest[axis] = (header[axis + 1u] > largest[axis]) ? header[axis + 1u] : largest[axis];
        }
        most_frames = (good && (header[0] > most_frames)) ? header[0] : most_frames;
        all_frames += good ? (unsigned long long)header[0] : 0ull;
    }
    if (good == 0)
    {
        return 0;
    }
    MaxTreeLayout layout;
    max_tree_layout(largest[0], largest[1], largest[2], most_frames, count, &layout);
    printf("  flatten: %u samples, %llu frames, largest view %ux%ux%u\n", count, all_frames, largest[0], largest[1],
           largest[2]);
    printf("  one vector magnitude per body: %u bits, %u limbs\n", layout.total_bits, layout.limbs);

    const size_t most_voxels = (size_t)largest[0] * largest[1] * largest[2];
    size_t room = (size_t)all_frames * 1024u;
    unsigned int *magnitudes = NULL;
    good = FLATTEN_TOOK(cudaMalloc((void **)&magnitudes, room * layout.limbs * sizeof(unsigned int)), &magnitudes,
                        error);
    printf("  one frame at a time: the residual by the unit sweeps, held in %u limbs a lane\n", ENGINE_RESIDUAL_LIMBS);
    unsigned long long bodies = 0ull;
    unsigned long long lost_bits = 0ull;
    unsigned long long frames_done = 0ull;
    unsigned long long proofs = 0ull;
    unsigned long long read_us = 0ull;
    unsigned long long device_us = 0ull;
    unsigned long long residual_us = 0ull;
    unsigned long long graded = 0ull;
    unsigned long long graded_differ = 0ull;
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; good && (sample < count); sample += 1u)
    {
        unsigned long long mark = engine_clock_microseconds();
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        EngineSignum volume_root;
        good = FLATTEN_HELD(engine_iapx_load(set, names[sample], extent, &volume, &volume_root, NULL, error) == 0L,
                            names[sample], error, ENGINE_ERROR_REQUEST)
            && FLATTEN_HELD((extent[0] <= most_frames) && ((extent[1] * extent[2] * extent[3]) <= most_voxels), extent,
                            error, ENGINE_ERROR_LOGIC);
        const unsigned int header[4] = {good ? (unsigned int)extent[0] : 0u, good ? (unsigned int)extent[1] : 0u,
                                        good ? (unsigned int)extent[2] : 0u, good ? (unsigned int)extent[3] : 0u};
        const size_t voxels = (size_t)header[1] * header[2] * header[3];
        read_us += engine_clock_microseconds() - mark;
        for (unsigned int frame = 0u; good && (frame < header[0]); frame += 1u)
        {
            mark = engine_clock_microseconds();
            EngineResidualRequest residual_request;
            memset(&residual_request, 0, sizeof(residual_request));
            residual_request.volume = &volume[frame * voxels];
            residual_request.depth = header[1];
            residual_request.height = header[2];
            residual_request.width = header[3];
            memcpy(residual_request.smooth_orders, request->smooth_orders, sizeof(residual_request.smooth_orders));
            memcpy(residual_request.background_orders, request->background_orders,
                   sizeof(residual_request.background_orders));
            residual_request.unit_sweep = ENGINE_RESIDUAL_BY_UNIT_SWEEP;
            residual_request.error = error;
            const unsigned int *device_residual = NULL;
            good = FLATTEN_HELD(engine_residual(&residual_request, &device_residual) == 0L, &residual_request, error,
                                ENGINE_ERROR_REQUEST);
            const unsigned long long swept = engine_clock_microseconds() - mark;
            residual_us += swept;
            device_us += swept;
            mark = engine_clock_microseconds();
            unsigned int held = 0u;
            unsigned int differ = 0u;
            MaxTreeObjectsRequest objects;
            memset(&objects, 0, sizeof(objects));
            objects.error = error;
            objects.device_residual = device_residual;
            objects.depth = header[1];
            objects.height = header[2];
            objects.width = header[3];
            objects.proof_held = &held;
            objects.grade = (unsigned int)(frame == 0u);
            objects.faces_differ = &differ;
            const long found = good ? max_tree_objects(&objects) : -1L;
            good = (found >= 0L);
            const size_t wanted = (size_t)bodies + (good ? (size_t)found : 0u);
            if (good && (wanted > room))
            {
                const size_t grown_room = wanted * 2u;
                unsigned int *grown = NULL;
                good = FLATTEN_TOOK(cudaMalloc((void **)&grown, grown_room * layout.limbs * sizeof(unsigned int)), &grown,
                                    error)
                    && FLATTEN_TOOK(cudaMemcpy(grown, magnitudes, (size_t)bodies * layout.limbs * sizeof(unsigned int),
                                               cudaMemcpyDeviceToDevice),
                                    grown, error);
                cudaFree(magnitudes);
                magnitudes = grown;
                room = grown_room;
            }
            unsigned long long lost = 0ull;
            MaxTreePackRequest pack;
            memset(&pack, 0, sizeof(pack));
            pack.error = error;
            pack.layout = &layout;
            pack.sample = sample;
            pack.frame = frame;
            pack.device_magnitudes = good ? &magnitudes[(size_t)bodies * layout.limbs] : NULL;
            pack.mismatches = &lost;
            good = good && FLATTEN_HELD(max_tree_pack(&pack) == found, pack.device_magnitudes, error, ENGINE_ERROR_LOGIC);
            device_us += engine_clock_microseconds() - mark;
            bodies += good ? (unsigned long long)found : 0ull;
            lost_bits += lost;
            graded += (unsigned long long)(frame == 0u);
            graded_differ += (unsigned long long)differ;
            proofs += (unsigned long long)held;
            frames_done += good ? 1ull : 0ull;
        }
        free(volume);
        printf("  %-24s %4u frames, %8llu bodies so far\n", names[sample], good ? header[0] : 0u, bodies);
        fflush(stdout);
    }
    const unsigned long long wall = engine_clock_microseconds() - began;
    const unsigned long long bytes = bodies * (unsigned long long)layout.limbs * 4ull;
    printf("\n  flattened %llu frames into %llu bodies, %llu per frame\n", frames_done, bodies,
           (frames_done != 0ull) ? (bodies / frames_done) : 0ull);
    printf("  resident on the device: %llu bytes, %llu MiB, for the whole set\n", bytes, bytes >> 20u);
    printf("  component counts proved on %llu of %llu frames; round trip lost %llu bits\n", proofs, frames_done,
           lost_bits);
    printf("  codebook graded on %llu frames against the full exact key: %llu faces chosen differently\n", graded,
           graded_differ);
    printf("  %llu ms: loading and proving the .iapx %llu ms, the device %llu ms, of which the residual %llu ms\n",
           wall / 1000ull, read_us / 1000ull, device_us / 1000ull, residual_us / 1000ull);
    max_tree_profile_report();
    char iapx_path[ENGINE_PATH_ROOM];
    const int named = snprintf(iapx_path, sizeof(iapx_path), "%s/flattened.iapx", set);
    const int proved = good && FLATTEN_HELD((named > 0) && ((size_t)named < sizeof(iapx_path)), set, error,
                                            ENGINE_ERROR_REQUEST)
                    && FLATTEN_HELD((lost_bits == 0ull) && (proofs == frames_done), &proofs, error, ENGINE_ERROR_LOGIC);
    const int written = proved && flatten_write_iapx(iapx_path, &layout, names, count, magnitudes, bodies, error);
    if (written)
    {
        printf("  the vector magnitudes are on disk: %s, %llu bodies, read back equal limb for limb\n", iapx_path,
               bodies);
    }
    cudaFree(magnitudes);
    return written;
}
