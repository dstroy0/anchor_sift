// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_test_streams.cu: lanes and bit streams
#include "../../../../c/engine/runtime/obsignatio/obsignatio_test_internal.h"

#if (defined(__CUDACC__))
static int test_lanes_host(const unsigned char *lane_bytes, const unsigned long long *extent, unsigned char *nodes)
{
    unsigned char keys[OBSIGNATIO_EXTENT_AXES][OBSIGNATIO_KEY_BYTES];
    const ObsignatioLevel levels[OBSIGNATIO_EXTENT_AXES] = {OBSIGNATIO_LEVEL_ROW, OBSIGNATIO_LEVEL_PLANE,
                                                            OBSIGNATIO_LEVEL_VOLUME, OBSIGNATIO_LEVEL_LANES};
    for (unsigned int level = 0u; level < OBSIGNATIO_EXTENT_AXES; level += 1u)
    {
        const char *const context = obsignatio_level_context(levels[level]);
        // the context's chars are hashed as the unsigned bytes they are stored as
        if (test_signum((const unsigned char *)context, strlen(context), NULL, OBSIGNATIO_MODE_CONTEXT, keys[level],
                        OBSIGNATIO_KEY_BYTES) != 0L)
        {
            return 0;
        }
    }
    const unsigned long long counts[OBSIGNATIO_EXTENT_AXES] = {extent[0] * extent[1] * extent[2], extent[0] * extent[1],
                                                               extent[0], 1ull};
    const unsigned long long lengths[OBSIGNATIO_EXTENT_AXES] = {
        extent[3] * sizeof(unsigned short), extent[2] * OBSIGNATIO_SIGNUM_BYTES, extent[1] * OBSIGNATIO_SIGNUM_BYTES,
        extent[0] * OBSIGNATIO_SIGNUM_BYTES};
    const unsigned char *from = lane_bytes;
    unsigned char *to = nodes;
    for (unsigned int level = 0u; level < OBSIGNATIO_EXTENT_AXES; level += 1u)
    {
        for (unsigned long long node = 0ull; node < counts[level]; node += 1ull)
        {
            if (test_signum(&from[node * lengths[level]], lengths[level], keys[level], OBSIGNATIO_MODE_KEYED,
                            &to[node * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES) != 0L)
            {
                return 0;
            }
        }
        from = to;
        to = &to[counts[level] * OBSIGNATIO_SIGNUM_BYTES];
    }
    return 1;
}

static long test_lanes_device(const unsigned short *device_lanes, const unsigned long long *extent,
                              unsigned char *device_nodes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioLanesRequest request = {device_lanes, extent, device_nodes, &error};
    return obsignatio_lanes(&request);
}

void test_lanes_reference(TestResults *results)
{
    const unsigned long long extents[][OBSIGNATIO_EXTENT_AXES] = {
        {1ull, 1ull, 1ull, 1ull},    {1ull, 1ull, 1ull, 512ull},   {2ull, 3ull, 5ull, 511ull},
        {3ull, 2ull, 33ull, 513ull}, {2ull, 33ull, 3ull, 1025ull}, {33ull, 1ull, 2ull, 7ull},
        {1ull, 65ull, 1ull, 3ull}};
    for (unsigned int extent_index = 0u; extent_index < (unsigned int)(sizeof(extents) / sizeof(extents[0]));
         extent_index += 1u)
    {
        const unsigned long long *const extent = extents[extent_index];
        const unsigned long long lanes = extent[0] * extent[1] * extent[2] * extent[3];
        const unsigned long long bytes = lanes * sizeof(unsigned short);
        const unsigned long long nodes = obsignatio_lanes_nodes(extent);
        const unsigned long long node_bytes = nodes * OBSIGNATIO_SIGNUM_BYTES;
        unsigned char *const lane_bytes = (unsigned char *)malloc((size_t)bytes);
        unsigned char *const host = (unsigned char *)malloc((size_t)node_bytes);
        unsigned char *const device = (unsigned char *)malloc((size_t)node_bytes);
        unsigned short *device_lanes = NULL;
        unsigned char *device_nodes = NULL;
        int ready = (lane_bytes != NULL) && (host != NULL) && (device != NULL) && (nodes != 0ull);
        for (unsigned long long byte = 0ull; ready && (byte < bytes); byte += 1ull)
        {
            // a byte index taken modulo 251 lies below 256
            lane_bytes[byte] = (unsigned char)(byte % TEST_PATTERN_PERIOD);
        }
        ready = ready && (cudaMalloc((void **)&device_lanes, (size_t)bytes) == cudaSuccess) &&
                (cudaMalloc((void **)&device_nodes, (size_t)node_bytes) == cudaSuccess) &&
                (cudaMemcpy(device_lanes, lane_bytes, (size_t)bytes, cudaMemcpyHostToDevice) == cudaSuccess) &&
                (test_lanes_device(device_lanes, extent, device_nodes) == 0L) &&
                (cudaMemcpy(device, device_nodes, (size_t)node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess) &&
                test_lanes_host(lane_bytes, extent, host);
        test_count(results, ready && (memcmp(host, device, (size_t)node_bytes) == 0));
        cudaFree(device_nodes);
        cudaFree(device_lanes);
        free(device);
        free(host);
        free(lane_bytes);
    }
}

void test_lanes_locality(TestResults *results)
{
    const unsigned long long extent[OBSIGNATIO_EXTENT_AXES] = {2ull, 3ull, 3ull, 513ull};
    const unsigned long long lanes = extent[0] * extent[1] * extent[2] * extent[3];
    const unsigned long long rows = extent[0] * extent[1] * extent[2];
    const unsigned long long planes = extent[0] * extent[1];
    const unsigned long long nodes = obsignatio_lanes_nodes(extent);
    const size_t node_bytes = (size_t)(nodes * OBSIGNATIO_SIGNUM_BYTES);
    unsigned short *const host_lanes = (unsigned short *)malloc((size_t)lanes * sizeof(unsigned short));
    unsigned char *const base = (unsigned char *)malloc(node_bytes);
    unsigned char *const flipped = (unsigned char *)malloc(node_bytes);
    unsigned short *device_lanes = NULL;
    unsigned char *device_nodes = NULL;
    int ready = (host_lanes != NULL) && (base != NULL) && (flipped != NULL);
    for (unsigned long long lane = 0ull; ready && (lane < lanes); lane += 1ull)
    {
        // a value taken modulo 65536 fits an unsigned short
        host_lanes[lane] = (unsigned short)((lane * TEST_PATTERN_PERIOD) % 65536ull);
    }
    ready = ready && (cudaMalloc((void **)&device_lanes, (size_t)lanes * sizeof(unsigned short)) == cudaSuccess) &&
            (cudaMalloc((void **)&device_nodes, node_bytes) == cudaSuccess) &&
            (cudaMemcpy(device_lanes, host_lanes, (size_t)lanes * sizeof(unsigned short), cudaMemcpyHostToDevice) ==
             cudaSuccess) &&
            (test_lanes_device(device_lanes, extent, device_nodes) == 0L) &&
            (cudaMemcpy(base, device_nodes, node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        // a bit index below 16 selects one bit of a lane, and the XOR stays below 65536
        const unsigned short changed = (unsigned short)(host_lanes[lane] ^ (1u << (unsigned int)(lane % 16ull)));
        const int ran =
            ready &&
            (cudaMemcpy(&device_lanes[lane], &changed, sizeof(changed), cudaMemcpyHostToDevice) == cudaSuccess) &&
            (test_lanes_device(device_lanes, extent, device_nodes) == 0L) &&
            (cudaMemcpy(flipped, device_nodes, node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess) &&
            (cudaMemcpy(&device_lanes[lane], &host_lanes[lane], sizeof(changed), cudaMemcpyHostToDevice) ==
             cudaSuccess);
        const unsigned long long row = lane / extent[3];
        const unsigned long long plane = row / extent[2];
        const unsigned long long volume = plane / extent[1];
        const unsigned long long path[OBSIGNATIO_EXTENT_AXES] = {row, rows + plane, rows + planes + volume,
                                                                 nodes - 1ull};
        int local = ran;
        for (unsigned long long node = 0ull; ran && (node < nodes); node += 1ull)
        {
            const int on_path = (node == path[0]) || (node == path[1]) || (node == path[2]) || (node == path[3]);
            const int differs = memcmp(&base[node * OBSIGNATIO_SIGNUM_BYTES], &flipped[node * OBSIGNATIO_SIGNUM_BYTES],
                                       OBSIGNATIO_SIGNUM_BYTES) != 0;
            local = local && (on_path == differs);
        }
        test_count(results, local);
    }
    cudaFree(device_nodes);
    cudaFree(device_lanes);
    free(flipped);
    free(base);
    free(host_lanes);
}

void test_lanes_closed(TestResults *results)
{
    const unsigned long long extent[OBSIGNATIO_EXTENT_AXES] = {1ull, 1ull, 1ull, 2ull};
    const unsigned long long zero_axes[OBSIGNATIO_EXTENT_AXES][OBSIGNATIO_EXTENT_AXES] = {
        {0ull, 1ull, 1ull, 2ull}, {1ull, 0ull, 1ull, 2ull}, {1ull, 1ull, 0ull, 2ull}, {1ull, 1ull, 1ull, 0ull}};
    unsigned short *device_lanes = NULL;
    unsigned char *device_nodes = NULL;
    unsigned char before[OBSIGNATIO_SIGNUM_BYTES];
    memset(before, 0xA5, sizeof(before));
    const int ready = (cudaMalloc((void **)&device_lanes, 2u * sizeof(unsigned short)) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_nodes, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess) &&
                      (cudaMemset(device_lanes, 0, 2u * sizeof(unsigned short)) == cudaSuccess) &&
                      (cudaMemcpy(device_nodes, before, sizeof(before), cudaMemcpyHostToDevice) == cudaSuccess);
    EngineError error;
    const ObsignatioLanesRequest cases[] = {{device_lanes, zero_axes[0], device_nodes, &error},
                                            {device_lanes, zero_axes[1], device_nodes, &error},
                                            {device_lanes, zero_axes[2], device_nodes, &error},
                                            {device_lanes, zero_axes[3], device_nodes, &error},
                                            {NULL, extent, device_nodes, &error},
                                            {device_lanes, NULL, device_nodes, &error},
                                            {device_lanes, extent, NULL, &error}};
    for (unsigned int index = 0u; index < (unsigned int)(sizeof(cases) / sizeof(cases[0])); index += 1u)
    {
        memset(&error, 0, sizeof(error));
        const long status = obsignatio_lanes(&cases[index]);
        unsigned char after[OBSIGNATIO_SIGNUM_BYTES];
        const int read = cudaMemcpy(after, device_nodes, sizeof(after), cudaMemcpyDeviceToHost) == cudaSuccess;
        test_count(results, ready && (status == OBSIGNATIO_ERROR) && read &&
                                (memcmp(after, before, sizeof(after)) == 0) && (error.kind == ENGINE_ERROR_REQUEST) &&
                                (error.module == ENGINE_MODULE_OBSIGNATIO));
    }
    const ObsignatioLanesRequest unfinished = {device_lanes, extent, device_nodes, NULL};
    test_count(results, obsignatio_lanes(&unfinished) == OBSIGNATIO_ERROR);
    test_count(results, obsignatio_lanes(NULL) == OBSIGNATIO_ERROR);
    test_count(results, (obsignatio_lanes_nodes(NULL) == 0ull) && (obsignatio_lanes_nodes(zero_axes[3]) == 0ull) &&
                            (obsignatio_lanes_nodes(extent) == 4ull));
    cudaFree(device_nodes);
    cudaFree(device_lanes);
}

#define TEST_LENGTH_BYTES 8ull

#define TEST_CHUNK_BITS ((1024ull - TEST_LENGTH_BYTES) * 8ull)

static void test_bit_stream_release(TestBitStream *stream)
{
    free(stream->limbs);
    free(stream->offsets);
    memset(stream, 0, sizeof(*stream));
}

static int test_bit_stream_make(TestBitStream *stream)
{
    const unsigned long long lengths[] = {0ull,
                                          1ull,
                                          7ull,
                                          8ull,
                                          9ull,
                                          31ull,
                                          32ull,
                                          33ull,
                                          63ull,
                                          64ull,
                                          65ull,
                                          TEST_CHUNK_BITS - 1ull,
                                          TEST_CHUNK_BITS,
                                          TEST_CHUNK_BITS + 1ull,
                                          2ull * TEST_CHUNK_BITS,
                                          (2ull * TEST_CHUNK_BITS) + 1ull};
    memset(stream, 0, sizeof(*stream));
    stream->messages = (unsigned long long)(sizeof(lengths) / sizeof(lengths[0]));
    const unsigned long long first = 5ull;
    unsigned long long end = first;
    for (unsigned long long message = 0ull; message < stream->messages; message += 1ull)
    {
        end += lengths[message];
    }
    stream->bits = end;
    stream->limb_count = (end + 31ull) / 32ull;
    stream->limbs = (unsigned int *)calloc((size_t)stream->limb_count, sizeof(unsigned int));
    stream->offsets = (unsigned long long *)calloc((size_t)stream->messages, sizeof(unsigned long long));
    if ((stream->limbs == NULL) || (stream->offsets == NULL))
    {
        test_bit_stream_release(stream);
        return 0;
    }
    unsigned long long at = first;
    for (unsigned long long message = 0ull; message < stream->messages; message += 1ull)
    {
        stream->offsets[message] = at;
        at += lengths[message];
    }
    for (unsigned long long limb = 0ull; limb < stream->limb_count; limb += 1ull)
    {
        // a value taken modulo 2^32 fits an unsigned int
        stream->limbs[limb] = (unsigned int)((limb * 2654435761ull) % 4294967296ull);
    }
    return 1;
}

static int test_bits_host(const TestBitStream *stream, const unsigned char *key, unsigned int mode,
                          unsigned char *signa)
{
    for (unsigned long long message = 0ull; message < stream->messages; message += 1ull)
    {
        const unsigned long long end =
            ((message + 1ull) < stream->messages) ? stream->offsets[message + 1ull] : stream->bits;
        const unsigned long long length = end - stream->offsets[message];
        const unsigned long long count = TEST_LENGTH_BYTES + ((length + 7ull) / 8ull);
        unsigned char *const bytes = (unsigned char *)calloc((size_t)count + 1u, 1u);
        if (bytes == NULL)
        {
            return 0;
        }
        for (unsigned long long byte = 0ull; byte < TEST_LENGTH_BYTES; byte += 1ull)
        {
            // one byte of the length, shifted down and masked, fits an unsigned char
            bytes[byte] = (unsigned char)((length >> (8ull * byte)) & 0xFFull);
        }
        for (unsigned long long bit = 0ull; bit < length; bit += 1ull)
        {
            const unsigned long long place = stream->offsets[message] + bit;
            const unsigned int value = (stream->limbs[place / 32ull] >> (place % 32ull)) & 1u;
            // a single bit shifted below 8 fits an unsigned char
            bytes[TEST_LENGTH_BYTES + (bit / 8ull)] |= (unsigned char)(value << (bit % 8ull));
        }
        const long hashed =
            test_signum(bytes, count, key, mode, &signa[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES);
        free(bytes);
        if (hashed != 0L)
        {
            return 0;
        }
    }
    return 1;
}

static long test_bits_device(const unsigned int *device_limbs, const unsigned long long *device_offsets,
                             const TestBitStream *stream, const unsigned char *key, unsigned int mode,
                             unsigned char *device_signa)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioBitsRequest request = {device_limbs, device_offsets, stream->messages, stream->bits,
                                           key,          mode,           device_signa,     &error};
    return obsignatio_bits(&request);
}

static int test_bit_device_place(const TestBitStream *stream, TestBitDevice *device)
{
    memset(device, 0, sizeof(*device));
    return (cudaMalloc((void **)&device->limbs, (size_t)stream->limb_count * sizeof(unsigned int)) == cudaSuccess) &&
           (cudaMalloc((void **)&device->offsets, (size_t)stream->messages * sizeof(unsigned long long)) ==
            cudaSuccess) &&
           (cudaMalloc((void **)&device->signa, (size_t)stream->messages * OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess) &&
           (cudaMemcpy(device->limbs, stream->limbs, (size_t)stream->limb_count * sizeof(unsigned int),
                       cudaMemcpyHostToDevice) == cudaSuccess) &&
           (cudaMemcpy(device->offsets, stream->offsets, (size_t)stream->messages * sizeof(unsigned long long),
                       cudaMemcpyHostToDevice) == cudaSuccess);
}

static void test_bit_device_release(TestBitDevice *device)
{
    cudaFree(device->signa);
    cudaFree(device->offsets);
    cudaFree(device->limbs);
    memset(device, 0, sizeof(*device));
}

void test_bits_reference(const TestVectors *vectors, TestResults *results)
{
    TestBitStream stream;
    TestBitDevice device;
    int ready = test_bit_stream_make(&stream) && test_bit_device_place(&stream, &device);
    const size_t signa_bytes = (size_t)(stream.messages * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const host = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned char *const read = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    ready = ready && (host != NULL) && (read != NULL);
    const unsigned int modes[2] = {OBSIGNATIO_MODE_HASH, OBSIGNATIO_MODE_KEYED};
    for (unsigned int mode = 0u; mode < 2u; mode += 1u)
    {
        const unsigned char *const key = (modes[mode] == OBSIGNATIO_MODE_KEYED) ? vectors->key : NULL;
        const int ran =
            ready && test_bits_host(&stream, key, modes[mode], host) &&
            (test_bits_device(device.limbs, device.offsets, &stream, key, modes[mode], device.signa) == 0L) &&
            (cudaMemcpy(read, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
        for (unsigned long long message = 0ull; message < stream.messages; message += 1ull)
        {
            test_count(results,
                       ran && (memcmp(&host[message * OBSIGNATIO_SIGNUM_BYTES],
                                      &read[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES) == 0));
        }
    }
    free(read);
    free(host);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}

void test_bits_locality(TestResults *results)
{
    TestBitStream stream;
    TestBitDevice device;
    int ready = test_bit_stream_make(&stream) && test_bit_device_place(&stream, &device);
    const size_t signa_bytes = (size_t)(stream.messages * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const base = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned char *const flipped = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    ready = ready && (base != NULL) && (flipped != NULL) &&
            (test_bits_device(device.limbs, device.offsets, &stream, NULL, OBSIGNATIO_MODE_HASH, device.signa) == 0L) &&
            (cudaMemcpy(base, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    for (unsigned long long bit = 0ull; bit < (stream.limb_count * 32ull); bit += 1ull)
    {
        const unsigned int changed = stream.limbs[bit / 32ull] ^ (1u << (bit % 32ull));
        const int ran =
            ready &&
            (cudaMemcpy(&device.limbs[bit / 32ull], &changed, sizeof(changed), cudaMemcpyHostToDevice) ==
             cudaSuccess) &&
            (test_bits_device(device.limbs, device.offsets, &stream, NULL, OBSIGNATIO_MODE_HASH, device.signa) == 0L) &&
            (cudaMemcpy(flipped, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess) &&
            (cudaMemcpy(&device.limbs[bit / 32ull], &stream.limbs[bit / 32ull], sizeof(changed),
                        cudaMemcpyHostToDevice) == cudaSuccess);
        int local = ran;
        for (unsigned long long message = 0ull; ran && (message < stream.messages); message += 1ull)
        {
            const unsigned long long end =
                ((message + 1ull) < stream.messages) ? stream.offsets[message + 1ull] : stream.bits;
            const int inside = (bit >= stream.offsets[message]) && (bit < end);
            const int differs = memcmp(&base[message * OBSIGNATIO_SIGNUM_BYTES],
                                       &flipped[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES) != 0;
            local = local && (inside == differs);
        }
        test_count(results, local);
    }
    free(flipped);
    free(base);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}

void test_bits_closed(const TestVectors *vectors, TestResults *results)
{
    TestBitStream stream;
    TestBitDevice device;
    memset(&device, 0, sizeof(device));
    const int placed = test_bit_stream_make(&stream) && test_bit_device_place(&stream, &device);
    if (placed == 0)
    {
        test_count(results, 0);
        test_bit_device_release(&device);
        test_bit_stream_release(&stream);
        return;
    }
    const size_t signa_bytes = (size_t)(stream.messages * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const before = placed ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned char *const after = placed ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned long long *device_backward = NULL;
    unsigned long long *const backward =
        placed ? (unsigned long long *)malloc((size_t)stream.messages * sizeof(unsigned long long)) : NULL;
    int ready = placed && (before != NULL) && (after != NULL) && (backward != NULL);
    if (ready)
    {
        memset(before, 0xA5, signa_bytes);
        memcpy(backward, stream.offsets, (size_t)stream.messages * sizeof(unsigned long long));
        backward[2] = backward[3] + 1ull;
        ready = (cudaMemcpy(device.signa, before, signa_bytes, cudaMemcpyHostToDevice) == cudaSuccess) &&
                (cudaMalloc((void **)&device_backward, (size_t)stream.messages * sizeof(unsigned long long)) ==
                 cudaSuccess) &&
                (cudaMemcpy(device_backward, backward, (size_t)stream.messages * sizeof(unsigned long long),
                            cudaMemcpyHostToDevice) == cudaSuccess);
    }
    EngineError error;
    const ObsignatioBitsRequest cases[] = {
        {device.limbs, device_backward, stream.messages, stream.bits, NULL, OBSIGNATIO_MODE_HASH, device.signa, &error},
        {device.limbs, device.offsets, stream.messages, stream.offsets[stream.messages - 1ull] - 1ull, NULL,
         OBSIGNATIO_MODE_HASH, device.signa, &error},
        {device.limbs, NULL, stream.messages, stream.bits, NULL, OBSIGNATIO_MODE_HASH, device.signa, &error},
        {device.limbs, device.offsets, stream.messages, stream.bits, NULL, OBSIGNATIO_MODE_HASH, NULL, &error},
        {NULL, device.offsets, stream.messages, stream.bits, NULL, OBSIGNATIO_MODE_HASH, device.signa, &error},
        {device.limbs, device.offsets, stream.messages, stream.bits, NULL, OBSIGNATIO_MODE_KEYED, device.signa, &error},
        {device.limbs, device.offsets, stream.messages, stream.bits, vectors->key, OBSIGNATIO_MODE_HASH, device.signa,
         &error},
        {device.limbs, device.offsets, stream.messages, stream.bits, NULL, 1u, device.signa, &error}};
    for (unsigned int index = 0u; index < (unsigned int)(sizeof(cases) / sizeof(cases[0])); index += 1u)
    {
        memset(&error, 0, sizeof(error));
        const long status = obsignatio_bits(&cases[index]);
        const int read = ready && (cudaMemcpy(after, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
        test_count(results, read && (status == OBSIGNATIO_ERROR) && (memcmp(after, before, signa_bytes) == 0) &&
                                (error.kind == ENGINE_ERROR_REQUEST) && (error.module == ENGINE_MODULE_OBSIGNATIO));
    }
    const ObsignatioBitsRequest unfinished = {device.limbs, device.offsets,       stream.messages, stream.bits,
                                              NULL,         OBSIGNATIO_MODE_HASH, device.signa,    NULL};
    test_count(results, obsignatio_bits(&unfinished) == OBSIGNATIO_ERROR);
    test_count(results, obsignatio_bits(NULL) == OBSIGNATIO_ERROR);
    memset(&error, 0, sizeof(error));
    const ObsignatioBitsRequest nothing = {NULL, NULL, 0ull, 0ull, NULL, OBSIGNATIO_MODE_HASH, NULL, &error};
    test_count(results, (obsignatio_bits(&nothing) == 0L) && (error.kind == ENGINE_ERROR_NONE));
    cudaFree(device_backward);
    free(backward);
    free(after);
    free(before);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}
#endif
