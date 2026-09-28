// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_seal.cu: levels, bits, the seal and the lanes
#include "obsignatio_internal.h"

#if (defined(__CUDACC__))

__global__ static void obsignatio_level_kernel(const unsigned int *from, unsigned long long messages,
                                               unsigned long long width, ObsignatioKey key, unsigned int mode,
                                               unsigned int *to, unsigned char *signa)
{
    const unsigned long long half = (width + 1ull) / 2ull;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         index < (messages * half); index += jump)
    {
        const unsigned long long message = index / half;
        const unsigned long long pair = index % half;
        const unsigned int *const left = &from[((message * width) + (2ull * pair)) * OBSIGNATIO_CHAINING_WORDS];
        unsigned int *const out = &to[index * OBSIGNATIO_CHAINING_WORDS];
        if (((2ull * pair) + 1ull) < width)
        {
            ObsignatioNode node;
            obsignatio_parent(key.words, mode, left, left + OBSIGNATIO_CHAINING_WORDS, &node);
            if (width == 2ull)
            {
                obsignatio_root(&node, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
            }
            else
            {
                obsignatio_chaining(&node, out);
            }
        }
        else
        {
            for (unsigned int word = 0u; word < OBSIGNATIO_CHAINING_WORDS; word += 1u)
            {
                out[word] = left[word];
            }
        }
    }
}

static int obsignatio_launch_config(const void *kernel, unsigned long long work, unsigned int *grid,
                                    unsigned int *threads, EngineError *error)
{
    int least_grid = 0;
    int block = 0;
    if (OBSIGNATIO_STATUS_CHECK(cudaOccupancyMaxPotentialBlockSize(&least_grid, &block, kernel), kernel, error) == 0)
    {
        return 0;
    }
    // the occupancy query returns positive counts below INT_MAX. Both convert to unsigned exactly
    const unsigned long long wanted = (work + (unsigned long long)block - 1ull) / (unsigned long long)block;
    // the grid is capped at the occupancy grid, which fits an unsigned int
    *grid = (wanted < (unsigned long long)least_grid) ? (unsigned int)wanted : (unsigned int)least_grid;
    // a positive block size below INT_MAX converts to unsigned exactly
    *threads = (unsigned int)block;
    return 1;
}

extern "C" long obsignatio_many(const ObsignatioManyRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_CHECK(
            ((request->messages == 0ull) || ((request->device_bytes != NULL) && (request->device_signa != NULL))) &&
                obsignatio_mode_valid(request->mode, request->key),
            request, error) == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    if (request->messages == 0ull)
    {
        return 0L;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    const unsigned long long chunks =
        (request->length == 0ull) ? 1ull
                                  : ((request->length + OBSIGNATIO_CHUNK_BYTES - 1ull) >> OBSIGNATIO_CHUNK_SHIFT);
    const unsigned long long halves = (chunks + 1ull) / 2ull;
    unsigned int *wide = NULL;
    unsigned int *narrow = NULL;
    const size_t wide_bytes = (size_t)(request->messages * chunks * OBSIGNATIO_CHAINING_WORDS * sizeof(unsigned int));
    const size_t narrow_bytes = (size_t)(request->messages * halves * OBSIGNATIO_CHAINING_WORDS * sizeof(unsigned int));
    unsigned int grid = 0u;
    unsigned int threads = 0u;
    int ok =
        ((chunks == 1ull) || (OBSIGNATIO_STATUS_CHECK(cudaMalloc((void **)&wide, wide_bytes), &wide, error) &&
                              OBSIGNATIO_STATUS_CHECK(cudaMalloc((void **)&narrow, narrow_bytes), &narrow, error))) &&
        obsignatio_launch_config((const void *)obsignatio_chunk_kernel, request->messages * chunks, &grid, &threads,
                                 error);
    if (ok)
    {
        obsignatio_chunk_kernel<<<grid, threads>>>(request->device_bytes, request->messages, request->length,
                                                   request->stride, chunks, key, request->mode, wide,
                                                   request->device_signa);
        ok = OBSIGNATIO_STATUS_CHECK(cudaGetLastError(), request->device_bytes, error);
    }
    unsigned int *from = wide;
    unsigned int *to = narrow;
    for (unsigned long long width = chunks; ok && (width > 1ull); width = (width + 1ull) / 2ull)
    {
        ok = obsignatio_launch_config((const void *)obsignatio_level_kernel,
                                      request->messages * ((width + 1ull) / 2ull), &grid, &threads, error);
        if (ok)
        {
            obsignatio_level_kernel<<<grid, threads>>>(from, request->messages, width, key, request->mode, to,
                                                       request->device_signa);
            ok = OBSIGNATIO_STATUS_CHECK(cudaGetLastError(), from, error);
        }
        unsigned int *const swapped = from;
        from = to;
        to = swapped;
    }
    ok = ok && OBSIGNATIO_STATUS_CHECK(cudaDeviceSynchronize(), request->device_signa, error);
    cudaFree(wide);
    cudaFree(narrow);
    return ok ? 0L : OBSIGNATIO_ERROR;
}

__global__ static void obsignatio_bits_check_kernel(const unsigned long long *offsets, unsigned long long messages,
                                                    unsigned long long bits, unsigned int *broken)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long message = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; message < messages;
         message += jump)
    {
        const unsigned long long end = ((message + 1ull) < messages) ? offsets[message + 1ull] : bits;
        if ((offsets[message] > end) || (end > bits))
        {
            atomicOr(broken, 1u);
        }
    }
}

__global__ static void obsignatio_bits_kernel(const unsigned int *limbs, const unsigned long long *offsets,
                                              unsigned long long messages, unsigned long long bits, ObsignatioKey key,
                                              unsigned int mode, unsigned char *signa)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long message = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; message < messages;
         message += jump)
    {
        const unsigned long long end = ((message + 1ull) < messages) ? offsets[message + 1ull] : bits;
        const unsigned long long length = end - offsets[message];
        const ObsignatioSource source = {NULL, limbs, offsets[message], length,
                                         OBSIGNATIO_LENGTH_BYTES + ((length + 7ull) / 8ull)};
        obsignatio_digest(key.words, mode, &source, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
    }
}

extern "C" long obsignatio_bits(const ObsignatioBitsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_CHECK(
            ((request->messages == 0ull) || ((request->device_offsets != NULL) && (request->device_signa != NULL) &&
                                             ((request->device_limbs != NULL) || (request->bits == 0ull)))) &&
                obsignatio_mode_valid(request->mode, request->key),
            request, error) == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    if (request->messages == 0ull)
    {
        return 0L;
    }
    const ObsignatioKey key = obsignatio_key_load(request->key);
    unsigned int *device_broken = NULL;
    unsigned int broken = 0u;
    unsigned int grid = 0u;
    unsigned int threads = 0u;
    int ok =
        OBSIGNATIO_STATUS_CHECK(cudaMalloc((void **)&device_broken, sizeof(unsigned int)), &device_broken, error) &&
        OBSIGNATIO_STATUS_CHECK(cudaMemset(device_broken, 0, sizeof(unsigned int)), device_broken, error) &&
        obsignatio_launch_config((const void *)obsignatio_bits_check_kernel, request->messages, &grid, &threads, error);
    if (ok)
    {
        obsignatio_bits_check_kernel<<<grid, threads>>>(request->device_offsets, request->messages, request->bits,
                                                        device_broken);
        ok = OBSIGNATIO_STATUS_CHECK(cudaGetLastError(), request->device_offsets, error) &&
             OBSIGNATIO_STATUS_CHECK(cudaMemcpy(&broken, device_broken, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                     device_broken, error) &&
             OBSIGNATIO_CHECK(broken == 0u, request->device_offsets, error) &&
             obsignatio_launch_config((const void *)obsignatio_bits_kernel, request->messages, &grid, &threads, error);
    }
    if (ok)
    {
        obsignatio_bits_kernel<<<grid, threads>>>(request->device_limbs, request->device_offsets, request->messages,
                                                  request->bits, key, request->mode, request->device_signa);
        ok = OBSIGNATIO_STATUS_CHECK(cudaGetLastError(), request->device_limbs, error) &&
             OBSIGNATIO_STATUS_CHECK(cudaDeviceSynchronize(), request->device_signa, error);
    }
    cudaFree(device_broken);
    return ok ? 0L : OBSIGNATIO_ERROR;
}
#endif
#if !(defined(__CUDACC__))
// a part with no CUDA toolchain has no device memory to seal: a request for it errors, a resource the part lacks
extern "C" long obsignatio_many(const ObsignatioManyRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    engine_error_check(0, ENGINE_ERROR_RESOURCE, ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__,
                       (const void *)request, request->error);
    return OBSIGNATIO_ERROR;
}

extern "C" long obsignatio_bits(const ObsignatioBitsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    engine_error_check(0, ENGINE_ERROR_RESOURCE, ENGINE_MODULE_OBSIGNATIO, (unsigned int)__LINE__,
                       (const void *)request, request->error);
    return OBSIGNATIO_ERROR;
}
#endif

#define OBSIGNATIO_CONTEXT_PREFIX "obsignatio aeterna 2026-09-23 "

extern "C" const char *obsignatio_level_context(ObsignatioLevel level)
{
    switch (level)
    {
    case OBSIGNATIO_LEVEL_ROW:
        return OBSIGNATIO_CONTEXT_PREFIX "row";
    case OBSIGNATIO_LEVEL_PLANE:
        return OBSIGNATIO_CONTEXT_PREFIX "plane";
    case OBSIGNATIO_LEVEL_VOLUME:
        return OBSIGNATIO_CONTEXT_PREFIX "volume";
    case OBSIGNATIO_LEVEL_LANES:
        return OBSIGNATIO_CONTEXT_PREFIX "lanes";
    case OBSIGNATIO_LEVEL_CHUNK:
        return OBSIGNATIO_CONTEXT_PREFIX "chunk";
    case OBSIGNATIO_LEVEL_STREAM:
        return OBSIGNATIO_CONTEXT_PREFIX "stream";
    case OBSIGNATIO_LEVEL_SIDE:
        return OBSIGNATIO_CONTEXT_PREFIX "side";
    case OBSIGNATIO_LEVEL_MEMBERS:
        return OBSIGNATIO_CONTEXT_PREFIX "members";
    case OBSIGNATIO_LEVEL_SAMPLE:
        return OBSIGNATIO_CONTEXT_PREFIX "sample";
    case OBSIGNATIO_LEVEL_SET:
        return OBSIGNATIO_CONTEXT_PREFIX "set";
    case OBSIGNATIO_LEVEL_FILE:
        return OBSIGNATIO_CONTEXT_PREFIX "file";
    case OBSIGNATIO_LEVEL_UNIVERSAL:
        return OBSIGNATIO_CONTEXT_PREFIX "universal";
    case OBSIGNATIO_LEVEL_SIDE_STORED:
        return OBSIGNATIO_CONTEXT_PREFIX "side stored";
    case OBSIGNATIO_LEVEL_SIDE_INFLATED:
        return OBSIGNATIO_CONTEXT_PREFIX "side inflated";
    default:
        return NULL;
    }
}

extern "C" long obsignatio_level_key(ObsignatioLevel level, unsigned char *key, EngineError *error)
{
    if (error == NULL)
    {
        return OBSIGNATIO_ERROR;
    }
    const char *const context = obsignatio_level_context(level);
    if (OBSIGNATIO_CHECK((context != NULL) && (key != NULL), key, error) == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    // the context's chars are hashed as the unsigned bytes they are stored as
    const ObsignatioSignumRequest request = {(const unsigned char *)context,
                                             strlen(context),
                                             NULL,
                                             OBSIGNATIO_MODE_CONTEXT,
                                             key,
                                             OBSIGNATIO_KEY_BYTES,
                                             error};
    return obsignatio_signum(&request);
}

extern "C" long obsignatio_seal(const ObsignatioSealRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    if ((OBSIGNATIO_CHECK(request->signum != NULL, request, request->error) == 0) ||
        (obsignatio_level_key(OBSIGNATIO_LEVEL_FILE, key, request->error) != 0L))
    {
        return OBSIGNATIO_ERROR;
    }
    const ObsignatioSignumRequest signum = {request->bytes,        request->count,  key,
                                            OBSIGNATIO_MODE_KEYED, request->signum, OBSIGNATIO_SIGNUM_BYTES,
                                            request->error};
    return obsignatio_signum(&signum);
}

extern "C" long obsignatio_seal_verify(const ObsignatioSealRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    unsigned char rebuilt[OBSIGNATIO_SIGNUM_BYTES];
    const ObsignatioSealRequest again = {request->bytes, request->count, rebuilt, request->error};
    if ((OBSIGNATIO_CHECK(request->signum != NULL, request, request->error) == 0) || (obsignatio_seal(&again) != 0L))
    {
        return OBSIGNATIO_ERROR;
    }
    return (memcmp(rebuilt, request->signum, OBSIGNATIO_SIGNUM_BYTES) == 0) ? 1L : 0L;
}

extern "C" unsigned long long obsignatio_lanes_nodes(const unsigned long long *extent)
{
    if ((extent == NULL) || (extent[0] == 0ull) || (extent[1] == 0ull) || (extent[2] == 0ull) || (extent[3] == 0ull))
    {
        return 0ull;
    }
    const unsigned long long volumes = extent[0];
    const unsigned long long planes = volumes * extent[1];
    const unsigned long long rows = planes * extent[2];
    return rows + planes + volumes + 1ull;
}

extern "C" long obsignatio_lanes(const ObsignatioLanesRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return OBSIGNATIO_ERROR;
    }
    EngineError *const error = request->error;
    if (OBSIGNATIO_CHECK((request->device_lanes != NULL) && (request->device_nodes != NULL) &&
                             (obsignatio_lanes_nodes(request->extent) != 0ull),
                         request, error) == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    unsigned char row_key[OBSIGNATIO_KEY_BYTES];
    unsigned char plane_key[OBSIGNATIO_KEY_BYTES];
    unsigned char volume_key[OBSIGNATIO_KEY_BYTES];
    unsigned char lanes_key[OBSIGNATIO_KEY_BYTES];
    const int keyed = (obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, row_key, error) == 0L) &&
                      (obsignatio_level_key(OBSIGNATIO_LEVEL_PLANE, plane_key, error) == 0L) &&
                      (obsignatio_level_key(OBSIGNATIO_LEVEL_VOLUME, volume_key, error) == 0L) &&
                      (obsignatio_level_key(OBSIGNATIO_LEVEL_LANES, lanes_key, error) == 0L);
    if (keyed == 0)
    {
        return OBSIGNATIO_ERROR;
    }
    const unsigned long long *const extent = request->extent;
    const unsigned long long volumes = extent[0];
    const unsigned long long planes = volumes * extent[1];
    const unsigned long long rows = planes * extent[2];
    const unsigned long long row_bytes = extent[3] * sizeof(unsigned short);
    unsigned char *const row_nodes = request->device_nodes;
    unsigned char *const plane_nodes = &row_nodes[rows * OBSIGNATIO_SIGNUM_BYTES];
    unsigned char *const volume_nodes = &plane_nodes[planes * OBSIGNATIO_SIGNUM_BYTES];
    unsigned char *const lanes_node = &volume_nodes[volumes * OBSIGNATIO_SIGNUM_BYTES];
    // the device is little-endian. The lanes' bytes are their little-endian u16 form
    const unsigned char *const lane_bytes = (const unsigned char *)request->device_lanes;
    const ObsignatioManyRequest levels[OBSIGNATIO_EXTENT_AXES] = {
        {lane_bytes, rows, row_bytes, row_bytes, row_key, OBSIGNATIO_MODE_KEYED, row_nodes, error},
        {row_nodes, planes, extent[2] * OBSIGNATIO_SIGNUM_BYTES, extent[2] * OBSIGNATIO_SIGNUM_BYTES, plane_key,
         OBSIGNATIO_MODE_KEYED, plane_nodes, error},
        {plane_nodes, volumes, extent[1] * OBSIGNATIO_SIGNUM_BYTES, extent[1] * OBSIGNATIO_SIGNUM_BYTES, volume_key,
         OBSIGNATIO_MODE_KEYED, volume_nodes, error},
        {volume_nodes, 1ull, volumes * OBSIGNATIO_SIGNUM_BYTES, volumes * OBSIGNATIO_SIGNUM_BYTES, lanes_key,
         OBSIGNATIO_MODE_KEYED, lanes_node, error}};
    for (unsigned int level = 0u; level < OBSIGNATIO_EXTENT_AXES; level += 1u)
    {
        if (obsignatio_many(&levels[level]) != 0L)
        {
            return OBSIGNATIO_ERROR;
        }
    }
    return 0L;
}
