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
#define FLATTEN_STATUS_CHECK(call_, evacaddr_, error_)                                                                 \
    engine_status_check((int)(call_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__, (const void *)(evacaddr_),        \
                        (error_))

#define FLATTEN_CHECK(condition_, evacaddr_, error_, kind_)                                                            \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__,                           \
                       (const void *)(evacaddr_), (error_))

#define FLATTEN_IO(condition_, evacaddr_, error_)                                                                      \
    engine_io_check((condition_), ENGINE_MODULE_FLATTEN, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

// The flattened file's format word, first in its head. Format 2 records each sample's orders after its name. The first
// format held MAX_TREE_FIELDS in that place and recorded no orders, and a file of it errors.
#define FLATTEN_FORMAT 2u

#define FLATTEN_HEAD_LIMBS 5u

static int flatten_write_iapx(const char *path, const MaxTreeLayout *layout, char *const *names,
                              const FlattenOrders *orders, unsigned int count, const unsigned int *magnitudes,
                              unsigned long long bodies, EngineError *error)
{
    const size_t words = (size_t)bodies * layout->limbs;
    unsigned int *const again = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    int ok = FLATTEN_CHECK(again != NULL, &again, error, ENGINE_ERROR_RESOURCE);
    const unsigned int head[FLATTEN_HEAD_LIMBS] = {FLATTEN_FORMAT, MAX_TREE_FIELDS, layout->total_bits, layout->limbs,
                                                   count};
    FILE *file = ok ? fopen(path, "wb") : NULL;
    ok = ok && FLATTEN_IO(file != NULL, path, error) &&
         FLATTEN_IO(apxrep_head_write(file, APXREP_KIND_INPUT) != 0, file, error) &&
         FLATTEN_IO(apxrep_limbs_write(file, head, FLATTEN_HEAD_LIMBS) != 0, head, error) &&
         FLATTEN_IO(apxrep_limbs_write(file, layout->bits, MAX_TREE_FIELDS) != 0, layout->bits, error) &&
         FLATTEN_IO(apxrep_limbs_write(file, layout->offset, MAX_TREE_FIELDS) != 0, layout->offset, error);
    for (unsigned int sample = 0u; ok && (sample < count); sample += 1u)
    {
        const unsigned int length = (unsigned int)strlen(names[sample]);
        ok = FLATTEN_IO(apxrep_limbs_write(file, &length, 1u) != 0, &length, error) &&
             FLATTEN_IO(fwrite(names[sample], 1u, length, file) == length, names[sample], error) &&
             FLATTEN_IO(apxrep_limbs_write(file, orders[sample].smooth, ENGINE_AXES) != 0, orders[sample].smooth,
                        error) &&
             FLATTEN_IO(apxrep_limbs_write(file, orders[sample].background, ENGINE_AXES) != 0,
                        orders[sample].background, error);
    }
    ok = ok && FLATTEN_IO(apxrep_words_write(file, &bodies, 1u) != 0, &bodies, error) &&
         FLATTEN_IO(apxrep_limbs_write(file, magnitudes, words) != 0, magnitudes, error);
    if (file != NULL)
    {
        ok = FLATTEN_IO(fclose(file) == 0, file, error) && ok;
    }

    file = ok ? fopen(path, "rb") : NULL;
    unsigned int read_head[FLATTEN_HEAD_LIMBS] = {0u, 0u, 0u, 0u, 0u};
    unsigned int read_bits[MAX_TREE_FIELDS];
    unsigned int read_offset[MAX_TREE_FIELDS];
    ok = ok && FLATTEN_IO(file != NULL, path, error) &&
         FLATTEN_IO(apxrep_head_read(file, APXREP_KIND_INPUT) != 0, file, error) &&
         FLATTEN_IO(apxrep_limbs_read(file, read_head, FLATTEN_HEAD_LIMBS) != 0, read_head, error) &&
         FLATTEN_CHECK(memcmp(read_head, head, sizeof(head)) == 0, read_head, error, ENGINE_ERROR_LOGIC) &&
         FLATTEN_IO(apxrep_limbs_read(file, read_bits, MAX_TREE_FIELDS) != 0, read_bits, error) &&
         FLATTEN_CHECK(memcmp(read_bits, layout->bits, sizeof(read_bits)) == 0, read_bits, error, ENGINE_ERROR_LOGIC) &&
         FLATTEN_IO(apxrep_limbs_read(file, read_offset, MAX_TREE_FIELDS) != 0, read_offset, error) &&
         FLATTEN_CHECK(memcmp(read_offset, layout->offset, sizeof(read_offset)) == 0, read_offset, error,
                       ENGINE_ERROR_LOGIC);
    for (unsigned int sample = 0u; ok && (sample < count); sample += 1u)
    {
        char name[ENGINE_PATH_CAPACITY];
        unsigned int length = 0u;
        FlattenOrders read_orders;
        ok = FLATTEN_IO(apxrep_limbs_read(file, &length, 1u) != 0, &length, error) &&
             FLATTEN_CHECK(length < sizeof(name), &length, error, ENGINE_ERROR_LOGIC) &&
             FLATTEN_IO(fread(name, 1u, length, file) == length, name, error) &&
             FLATTEN_CHECK((length == strlen(names[sample])) && (memcmp(name, names[sample], length) == 0), name, error,
                           ENGINE_ERROR_LOGIC) &&
             FLATTEN_IO(apxrep_limbs_read(file, read_orders.smooth, ENGINE_AXES) != 0, read_orders.smooth, error) &&
             FLATTEN_IO(apxrep_limbs_read(file, read_orders.background, ENGINE_AXES) != 0, read_orders.background,
                        error) &&
             FLATTEN_CHECK(memcmp(&read_orders, &orders[sample], sizeof(read_orders)) == 0, &read_orders, error,
                           ENGINE_ERROR_LOGIC);
    }
    unsigned long long read_bodies = 0ull;
    ok =
        ok && FLATTEN_IO(apxrep_words_read(file, &read_bodies, 1u) != 0, &read_bodies, error) &&
        FLATTEN_CHECK(read_bodies == bodies, &read_bodies, error, ENGINE_ERROR_LOGIC) &&
        FLATTEN_IO(apxrep_limbs_read(file, again, words) != 0, again, error) &&
        FLATTEN_CHECK(memcmp(again, magnitudes, words * sizeof(unsigned int)) == 0, again, error, ENGINE_ERROR_LOGIC) &&
        FLATTEN_CHECK(fgetc(file) == EOF, file, error, ENGINE_ERROR_LOGIC);
    if (file != NULL)
    {
        fclose(file);
    }
    free(again);
    return ok;
}

int flatten_read(const char *set, FlattenResident *resident, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    memset(resident, 0, sizeof(*resident));
    char path[ENGINE_PATH_CAPACITY];
    const int written = snprintf(path, sizeof(path), "%s/flattened.iapx", set);
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const file = named ? fopen(path, "rb") : NULL;
    unsigned int head[FLATTEN_HEAD_LIMBS] = {0u, 0u, 0u, 0u, 0u};
    int ok = FLATTEN_CHECK(named, set, error, ENGINE_ERROR_REQUEST) && FLATTEN_IO(file != NULL, path, error) &&
             FLATTEN_IO(apxrep_head_read(file, APXREP_KIND_INPUT) != 0, file, error) &&
             FLATTEN_IO(apxrep_limbs_read(file, head, FLATTEN_HEAD_LIMBS) != 0, head, error) &&
             FLATTEN_CHECK(head[0] == FLATTEN_FORMAT, &head[0], error, ENGINE_ERROR_REQUEST) &&
             FLATTEN_CHECK(head[1] == MAX_TREE_FIELDS, &head[1], error, ENGINE_ERROR_LOGIC) &&
             FLATTEN_IO(apxrep_limbs_read(file, resident->layout.bits, MAX_TREE_FIELDS) != 0, resident->layout.bits,
                        error) &&
             FLATTEN_IO(apxrep_limbs_read(file, resident->layout.offset, MAX_TREE_FIELDS) != 0, resident->layout.offset,
                        error);
    resident->layout.total_bits = head[2];
    resident->layout.limbs = head[3];
    resident->samples = head[4];
    resident->names = ok ? (char **)calloc((size_t)resident->samples + 1u, sizeof(char *)) : NULL;
    resident->orders = ok ? (FlattenOrders *)calloc((size_t)resident->samples + 1u, sizeof(FlattenOrders)) : NULL;
    resident->offset_halves = ok ? (int *)calloc(((size_t)resident->samples + 1u) * ENGINE_AXES, sizeof(int)) : NULL;
    ok = ok &&
         FLATTEN_CHECK((resident->names != NULL) && (resident->orders != NULL) && (resident->offset_halves != NULL),
                       &resident->names, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int sample = 0u; ok && (sample < resident->samples); sample += 1u)
    {
        unsigned int length = 0u;
        ok = FLATTEN_IO(apxrep_limbs_read(file, &length, 1u) != 0, &length, error) &&
             FLATTEN_CHECK(length < 1024u, &length, error, ENGINE_ERROR_LOGIC);
        resident->names[sample] = ok ? (char *)calloc((size_t)length + 1u, 1u) : NULL;
        FlattenOrders *const orders = &resident->orders[sample];
        ok = ok &&
             FLATTEN_CHECK(resident->names[sample] != NULL, &resident->names[sample], error, ENGINE_ERROR_RESOURCE) &&
             FLATTEN_IO(fread(resident->names[sample], 1u, length, file) == length, resident->names[sample], error) &&
             FLATTEN_IO(apxrep_limbs_read(file, orders->smooth, ENGINE_AXES) != 0, orders->smooth, error) &&
             FLATTEN_IO(apxrep_limbs_read(file, orders->background, ENGINE_AXES) != 0, orders->background, error);
        for (unsigned int axis = 0u; ok && (axis < ENGINE_AXES); axis += 1u)
        {
            ok = FLATTEN_CHECK((orders->background[axis] & 1u) == 0u, &orders->background[axis], error,
                               ENGINE_ERROR_LOGIC);
            // an order's parity is 0 or 1, which re-signs to int exactly
            resident->offset_halves[((size_t)sample * ENGINE_AXES) + axis] = -(int)(orders->smooth[axis] & 1u);
        }
    }
    ok =
        ok && FLATTEN_IO(apxrep_words_read(file, &resident->bodies, 1u) != 0, &resident->bodies, error) &&
        FLATTEN_CHECK((resident->layout.limbs != 0u) && (resident->layout.total_bits <= (32u * resident->layout.limbs)),
                      &resident->layout, error, ENGINE_ERROR_LOGIC);
    const size_t words = ok ? (size_t)resident->bodies * resident->layout.limbs : 0u;
    resident->magnitudes = ok ? (unsigned int *)malloc((words + 1u) * sizeof(unsigned int)) : NULL;
    ok = ok && FLATTEN_CHECK(resident->magnitudes != NULL, &resident->magnitudes, error, ENGINE_ERROR_RESOURCE) &&
         FLATTEN_IO(apxrep_limbs_read(file, resident->magnitudes, words) != 0, resident->magnitudes, error) &&
         FLATTEN_CHECK(fgetc(file) == EOF, file, error, ENGINE_ERROR_LOGIC);
    if (file != NULL)
    {
        fclose(file);
    }
    if (ok == 0)
    {
        flatten_release(resident);
    }
    return ok;
}

void flatten_release(FlattenResident *resident)
{
    for (unsigned int sample = 0u; (resident->names != NULL) && (sample < resident->samples); sample += 1u)
    {
        free(resident->names[sample]);
    }
    free(resident->names);
    free(resident->orders);
    free(resident->offset_halves);
    free(resident->magnitudes);
    memset(resident, 0, sizeof(*resident));
}

static int flatten_header(const char *set, const char *name, unsigned int header[4], EngineError *error)
{
    unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
    const int ok = FLATTEN_CHECK(engine_iapx_head(set, name, extent, error) == 0L, name, error, ENGINE_ERROR_REQUEST) &&
                   FLATTEN_CHECK((extent[0] <= 0xFFFFFFFFull) && (extent[1] <= 0xFFFFFFFFull) &&
                                     (extent[2] <= 0xFFFFFFFFull) && (extent[3] <= 0xFFFFFFFFull),
                                 extent, error, ENGINE_ERROR_REQUEST);
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        header[axis] = ok ? (unsigned int)extent[axis] : 0u;
    }
    return ok;
}

// each sample's orders, its own where the request gives them and the shared ones where it does not; an odd background
// order errors here, before any sample is read
static int flatten_orders(const FlattenSetRequest *request, FlattenOrders *orders, EngineError *error)
{
    int ok = 1;
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        if (request->orders != NULL)
        {
            orders[sample] = request->orders[sample];
        }
        else
        {
            memcpy(orders[sample].smooth, request->smooth_orders, sizeof(orders[sample].smooth));
            memcpy(orders[sample].background, request->background_orders, sizeof(orders[sample].background));
        }
        for (unsigned int axis = 0u; ok && (axis < ENGINE_AXES); axis += 1u)
        {
            ok = FLATTEN_CHECK((orders[sample].background[axis] & 1u) == 0u, &orders[sample].background[axis], error,
                               ENGINE_ERROR_REQUEST);
        }
    }
    return ok;
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
    FlattenOrders *const orders = (FlattenOrders *)malloc(((size_t)count + 1u) * sizeof(FlattenOrders));
    int ok =
        FLATTEN_CHECK(orders != NULL, &orders, error, ENGINE_ERROR_RESOURCE) && flatten_orders(request, orders, error);
    unsigned int largest[3] = {0u, 0u, 0u};
    unsigned int max_frames = 0u;
    unsigned long long all_frames = 0ull;
    for (unsigned int sample = 0u; ok && (sample < count); sample += 1u)
    {
        unsigned int header[4] = {0u, 0u, 0u, 0u};
        ok = flatten_header(set, names[sample], header, error);
        for (unsigned int axis = 0u; ok && (axis < 3u); axis += 1u)
        {
            largest[axis] = (header[axis + 1u] > largest[axis]) ? header[axis + 1u] : largest[axis];
        }
        max_frames = (ok && (header[0] > max_frames)) ? header[0] : max_frames;
        all_frames += ok ? (unsigned long long)header[0] : 0ull;
    }
    if (ok == 0)
    {
        free(orders);
        return 0;
    }
    MaxTreeLayout layout;
    max_tree_layout(largest[0], largest[1], largest[2], max_frames, count, &layout);
    printf("  flatten: %u samples, %llu frames, largest view %ux%ux%u\n", count, all_frames, largest[0], largest[1],
           largest[2]);
    printf("  one vector magnitude per body: %u bits, %u limbs\n", layout.total_bits, layout.limbs);

    const size_t max_voxels = (size_t)largest[0] * largest[1] * largest[2];
    // one frame's packed bodies on the device, its capacity grown to the most any frame finds, and the set's gathered
    // on the host as each frame is packed
    unsigned int *magnitudes = NULL;
    size_t device_capacity = 0u;
    unsigned int *gathered = NULL;
    size_t gathered_capacity = 0u;
    ok = FLATTEN_CHECK(engine_object_reserve(&gathered, &gathered_capacity, 1u, layout.limbs), &gathered, error,
                       ENGINE_ERROR_RESOURCE);
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
    for (unsigned int sample = 0u; ok && (sample < count); sample += 1u)
    {
        unsigned long long mark = engine_clock_microseconds();
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        EngineSignum volume_root;
        ok = FLATTEN_CHECK(engine_iapx_load(set, names[sample], extent, &volume, &volume_root, NULL, error) == 0L,
                           names[sample], error, ENGINE_ERROR_REQUEST) &&
             FLATTEN_CHECK((extent[0] <= max_frames) && ((extent[1] * extent[2] * extent[3]) <= max_voxels), extent,
                           error, ENGINE_ERROR_LOGIC);
        const unsigned int header[4] = {ok ? (unsigned int)extent[0] : 0u, ok ? (unsigned int)extent[1] : 0u,
                                        ok ? (unsigned int)extent[2] : 0u, ok ? (unsigned int)extent[3] : 0u};
        const size_t voxels = (size_t)header[1] * header[2] * header[3];
        read_us += engine_clock_microseconds() - mark;
        for (unsigned int frame = 0u; ok && (frame < header[0]); frame += 1u)
        {
            mark = engine_clock_microseconds();
            int offset_halves[ENGINE_AXES] = {0, 0, 0};
            EngineResidualRequest residual_request;
            memset(&residual_request, 0, sizeof(residual_request));
            residual_request.volume = &volume[frame * voxels];
            residual_request.depth = header[1];
            residual_request.height = header[2];
            residual_request.width = header[3];
            memcpy(residual_request.smooth_orders, orders[sample].smooth, sizeof(residual_request.smooth_orders));
            memcpy(residual_request.background_orders, orders[sample].background,
                   sizeof(residual_request.background_orders));
            residual_request.unit_sweep = ENGINE_RESIDUAL_BY_UNIT_SWEEP;
            residual_request.offset_halves = offset_halves;
            residual_request.error = error;
            const unsigned int *device_residual = NULL;
            ok = FLATTEN_CHECK(engine_residual(&residual_request, &device_residual) == 0L, &residual_request, error,
                               ENGINE_ERROR_REQUEST);
            const unsigned long long swept = engine_clock_microseconds() - mark;
            residual_us += swept;
            device_us += swept;
            mark = engine_clock_microseconds();
            unsigned int proof_count = 0u;
            unsigned int differ = 0u;
            MaxTreeObjectsRequest objects;
            memset(&objects, 0, sizeof(objects));
            objects.error = error;
            objects.device_residual = device_residual;
            objects.depth = header[1];
            objects.height = header[2];
            objects.width = header[3];
            objects.proof_count = &proof_count;
            objects.grade = (unsigned int)(frame == 0u);
            objects.faces_differ = &differ;
            const long found = ok ? max_tree_objects(&objects) : -1L;
            ok = (found >= 0L);
            // a frame's capacity holds one body more than it found, and a frame of none still has a place to pack into
            const size_t frame_capacity = ok ? ((size_t)found + 1u) : 0u;
            if (ok && (frame_capacity > device_capacity))
            {
                cudaFree(magnitudes);
                magnitudes = NULL;
                ok = FLATTEN_STATUS_CHECK(
                    cudaMalloc((void **)&magnitudes, frame_capacity * layout.limbs * sizeof(unsigned int)), &magnitudes,
                    error);
                device_capacity = ok ? frame_capacity : 0u;
            }
            const size_t wanted = (size_t)bodies + (ok ? (size_t)found : 0u);
            ok = ok && ((wanted <= gathered_capacity) ||
                        FLATTEN_CHECK(engine_object_reserve(&gathered, &gathered_capacity, wanted, layout.limbs),
                                      &gathered, error, ENGINE_ERROR_RESOURCE));
            unsigned long long lost = 0ull;
            MaxTreePackRequest pack;
            memset(&pack, 0, sizeof(pack));
            pack.error = error;
            pack.layout = &layout;
            pack.sample = sample;
            pack.frame = frame;
            pack.device_magnitudes = ok ? magnitudes : NULL;
            pack.mismatches = &lost;
            ok = ok &&
                 FLATTEN_CHECK(max_tree_pack(&pack) == found, pack.device_magnitudes, error, ENGINE_ERROR_LOGIC) &&
                 ((found == 0L) || FLATTEN_STATUS_CHECK(cudaMemcpy(&gathered[(size_t)bodies * layout.limbs], magnitudes,
                                                                   (size_t)found * layout.limbs * sizeof(unsigned int),
                                                                   cudaMemcpyDeviceToHost),
                                                        gathered, error));
            device_us += engine_clock_microseconds() - mark;
            bodies += ok ? (unsigned long long)found : 0ull;
            lost_bits += lost;
            graded += (unsigned long long)(frame == 0u);
            graded_differ += (unsigned long long)differ;
            proofs += (unsigned long long)proof_count;
            frames_done += ok ? 1ull : 0ull;
        }
        free(volume);
        printf("  %-24s %4u frames, %8llu bodies so far\n", names[sample], ok ? header[0] : 0u, bodies);
        fflush(stdout);
    }
    const unsigned long long wall = engine_clock_microseconds() - began;
    const unsigned long long bytes = bodies * (unsigned long long)layout.limbs * 4ull;
    printf("\n  flattened %llu frames into %llu bodies, %llu per frame\n", frames_done, bodies,
           (frames_done != 0ull) ? (bodies / frames_done) : 0ull);
    printf("  gathered on the host: %llu bytes, %llu MiB, for the whole set; the device held one frame's bodies, %llu "
           "at most\n",
           bytes, bytes >> 20u, (device_capacity != 0u) ? (unsigned long long)(device_capacity - 1u) : 0ull);
    printf("  component counts proved on %llu of %llu frames; round trip lost %llu bits\n", proofs, frames_done,
           lost_bits);
    printf("  codebook graded on %llu frames against the full exact key: %llu faces chosen differently\n", graded,
           graded_differ);
    printf("  %llu ms: loading and proving the .iapx %llu ms, the device %llu ms, of which the residual %llu ms\n",
           wall / 1000ull, read_us / 1000ull, device_us / 1000ull, residual_us / 1000ull);
    max_tree_profile_report();
    char iapx_path[ENGINE_PATH_CAPACITY];
    const int named = snprintf(iapx_path, sizeof(iapx_path), "%s/flattened.iapx", set);
    const int proved =
        ok && FLATTEN_CHECK((named > 0) && ((size_t)named < sizeof(iapx_path)), set, error, ENGINE_ERROR_REQUEST) &&
        FLATTEN_CHECK((lost_bits == 0ull) && (proofs == frames_done), &proofs, error, ENGINE_ERROR_LOGIC);
    const int written = proved && flatten_write_iapx(iapx_path, &layout, names, orders, count, gathered, bodies, error);
    if (written)
    {
        printf("  the vector magnitudes are on disk: %s, %llu bodies, read back equal limb for limb\n", iapx_path,
               bodies);
    }
    cudaFree(magnitudes);
    free(gathered);
    free(orders);
    return written;
}
