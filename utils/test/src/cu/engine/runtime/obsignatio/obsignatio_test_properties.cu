// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_test_properties.cu: every length, bit flips, determinism, errors and the seal
#include "../../../../c/engine/runtime/obsignatio/obsignatio_test_internal.h"

#if (defined(__CUDACC__))

void test_every_length(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *device_pattern,
                       const unsigned char *context_key, unsigned char *device_signum, TestResults *results)
{
    for (unsigned long long length = 0ull; length <= vectors->longest; length += 1ull)
    {
        for (unsigned int mode = 0u; mode < 3u; mode += 1u)
        {
            const unsigned char *const key = test_mode_key(test_modes[mode], vectors, context_key);
            unsigned char host[OBSIGNATIO_SIGNUM_BYTES];
            unsigned char device[OBSIGNATIO_SIGNUM_BYTES];
            memset(device, 0, sizeof(device));
            const int ran =
                (test_signum(pattern, length, key, test_modes[mode], host, OBSIGNATIO_SIGNUM_BYTES) == 0L) &&
                (test_many(device_pattern, 1ull, length, length, key, test_modes[mode], device_signum) == 0L) &&
                (cudaMemcpy(device, device_signum, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost) == cudaSuccess);
            test_count(results, ran && (memcmp(host, device, OBSIGNATIO_SIGNUM_BYTES) == 0));
        }
    }
}

__global__ static void test_flip_kernel(const unsigned char *pattern, unsigned long long length,
                                        unsigned long long first_flip, unsigned long long flips, unsigned char *out)
{
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         index < (flips * length); index += jump)
    {
        const unsigned long long byte = index % length;
        const unsigned long long flip = first_flip + (index / length);
        // a bit index below 8 selects one bit of a byte
        const unsigned char mask = (unsigned char)(1u << (unsigned int)(flip % TEST_BYTE_BITS));
        // the flipped byte is a byte XOR a one-bit mask, still below 256
        out[index] = (unsigned char)(pattern[byte] ^ ((byte == (flip / TEST_BYTE_BITS)) ? mask : 0u));
    }
}

static int test_signum_order(const void *left, const void *right)
{
    return memcmp(left, right, OBSIGNATIO_SIGNUM_BYTES);
}

void test_bit_flips(const TestVectors *vectors, const unsigned char *device_pattern, TestResults *results)
{
    for (unsigned int index = 0u; index < vectors->count; index += 1u)
    {
        const TestCase *const one = &vectors->cases[index];
        const unsigned long long flips = one->length * TEST_BYTE_BITS;
        if (flips == 0ull)
        {
            continue;
        }
        unsigned char *const signa = (unsigned char *)malloc((size_t)((flips + 1ull) * OBSIGNATIO_SIGNUM_BYTES));
        unsigned char *device_flipped = NULL;
        unsigned char *device_signa = NULL;
        int ready =
            (signa != NULL) &&
            (cudaMalloc((void **)&device_flipped, (size_t)(TEST_FLIP_BATCH * one->length)) == cudaSuccess) &&
            (cudaMalloc((void **)&device_signa, (size_t)(TEST_FLIP_BATCH * OBSIGNATIO_SIGNUM_BYTES)) == cudaSuccess);
        for (unsigned long long first = 0ull; ready && (first < flips); first += TEST_FLIP_BATCH)
        {
            const unsigned long long batch = ((flips - first) < TEST_FLIP_BATCH) ? (flips - first) : TEST_FLIP_BATCH;
            test_flip_kernel<<<TEST_PATTERN_PERIOD, TEST_PATTERN_PERIOD>>>(device_pattern, one->length, first, batch,
                                                                           device_flipped);
            ready = (cudaGetLastError() == cudaSuccess) &&
                    (test_many(device_flipped, batch, one->length, one->length, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa) == 0L) &&
                    (cudaMemcpy(&signa[first * OBSIGNATIO_SIGNUM_BYTES], device_signa,
                                (size_t)(batch * OBSIGNATIO_SIGNUM_BYTES), cudaMemcpyDeviceToHost) == cudaSuccess);
        }
        for (unsigned long long flip = 0ull; flip < flips; flip += 1ull)
        {
            test_count(results, ready && (memcmp(&signa[flip * OBSIGNATIO_SIGNUM_BYTES], one->hash,
                                                 OBSIGNATIO_SIGNUM_BYTES) != 0));
        }
        int distinct = ready;
        if (ready)
        {
            memcpy(&signa[flips * OBSIGNATIO_SIGNUM_BYTES], one->hash, OBSIGNATIO_SIGNUM_BYTES);
            qsort(signa, (size_t)(flips + 1ull), OBSIGNATIO_SIGNUM_BYTES, test_signum_order);
            for (unsigned long long at = 1ull; at <= flips; at += 1ull)
            {
                distinct = distinct && (memcmp(&signa[(at - 1ull) * OBSIGNATIO_SIGNUM_BYTES],
                                               &signa[at * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES) != 0);
            }
        }
        test_count(results, distinct);
        cudaFree(device_signa);
        cudaFree(device_flipped);
        free(signa);
    }
}

void test_determinism(const TestVectors *vectors, const unsigned char *device_pattern, TestResults *results)
{
    const unsigned long long length = vectors->longest - TEST_PATTERN_PERIOD;
    const size_t bytes = (size_t)(TEST_PATTERN_PERIOD * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const first = (unsigned char *)malloc(bytes);
    unsigned char *const second = (unsigned char *)malloc(bytes);
    unsigned char *device_signa = NULL;
    const int ran = (first != NULL) && (second != NULL) && (vectors->longest > TEST_PATTERN_PERIOD) &&
                    (cudaMalloc((void **)&device_signa, bytes) == cudaSuccess) &&
                    (test_many(device_pattern, TEST_PATTERN_PERIOD, length, 1ull, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa) == 0L) &&
                    (cudaMemcpy(first, device_signa, bytes, cudaMemcpyDeviceToHost) == cudaSuccess) &&
                    (cudaMemset(device_signa, 0, bytes) == cudaSuccess) &&
                    (test_many(device_pattern, TEST_PATTERN_PERIOD, length, 1ull, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa) == 0L) &&
                    (cudaMemcpy(second, device_signa, bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    test_count(results, ran && (memcmp(first, second, bytes) == 0));
    int windows_differ = ran;
    for (unsigned long long window = 1ull; ran && (window < TEST_PATTERN_PERIOD); window += 1ull)
    {
        windows_differ =
            windows_differ && (memcmp(&first[(window - 1ull) * OBSIGNATIO_SIGNUM_BYTES],
                                      &first[window * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES) != 0);
    }
    test_count(results, windows_differ);
    cudaFree(device_signa);
    free(second);
    free(first);
}

static int test_error_signum(const ObsignatioSignumRequest *request, const unsigned char *out_before,
                               const unsigned char *out)
{
    const long status = obsignatio_signum(request);
    const int untouched = (out == NULL) || (memcmp(out, out_before, OBSIGNATIO_SIGNUM_BYTES) == 0);
    const int raised =
        (request == NULL) || (request->error == NULL) ||
        ((request->error->kind == ENGINE_ERROR_REQUEST) && (request->error->module == ENGINE_MODULE_OBSIGNATIO));
    return (status == OBSIGNATIO_ERROR) && untouched && raised;
}

static int test_error_many(const ObsignatioManyRequest *request, const unsigned char *device_signa,
                             const unsigned char *signa_before)
{
    const long status = obsignatio_many(request);
    unsigned char after[OBSIGNATIO_SIGNUM_BYTES];
    const int read = cudaMemcpy(after, device_signa, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost) == cudaSuccess;
    const int raised =
        (request == NULL) || (request->error == NULL) ||
        ((request->error->kind == ENGINE_ERROR_REQUEST) && (request->error->module == ENGINE_MODULE_OBSIGNATIO));
    return (status == OBSIGNATIO_ERROR) && read && (memcmp(after, signa_before, OBSIGNATIO_SIGNUM_BYTES) == 0) &&
           raised;
}

void test_fail_closed(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *device_pattern,
                      unsigned char *device_signum, TestResults *results)
{
    unsigned char before[OBSIGNATIO_SIGNUM_BYTES];
    unsigned char out[OBSIGNATIO_SIGNUM_BYTES];
    memset(before, 0xA5, sizeof(before));
    const unsigned char *const key = vectors->key;
    EngineError error;
    const ObsignatioSignumRequest signum_cases[] = {
        {NULL, 1ull, NULL, OBSIGNATIO_MODE_HASH, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, NULL, OBSIGNATIO_MODE_HASH, NULL, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, NULL, 1u, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, key, OBSIGNATIO_MODE_KEYED | OBSIGNATIO_MODE_MATERIAL, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, NULL, OBSIGNATIO_MODE_KEYED, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, NULL, OBSIGNATIO_MODE_MATERIAL, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, key, OBSIGNATIO_MODE_HASH, out, OBSIGNATIO_SIGNUM_BYTES, &error},
        {pattern, 1ull, key, OBSIGNATIO_MODE_CONTEXT, out, OBSIGNATIO_SIGNUM_BYTES, &error},
    };
    for (unsigned int index = 0u; index < (unsigned int)(sizeof(signum_cases) / sizeof(signum_cases[0])); index += 1u)
    {
        memset(&error, 0, sizeof(error));
        memcpy(out, before, sizeof(out));
        test_count(results, test_error_signum(&signum_cases[index], before, out));
    }
    memset(&error, 0, sizeof(error));
    memcpy(out, before, sizeof(out));
    const ObsignatioSignumRequest unfinished = {pattern, 1ull, NULL, OBSIGNATIO_MODE_HASH, out, OBSIGNATIO_SIGNUM_BYTES,
                                                NULL};
    test_count(results, test_error_signum(&unfinished, before, out));
    test_count(results, obsignatio_signum(NULL) == OBSIGNATIO_ERROR);
    memset(&error, 0, sizeof(error));
    const ObsignatioSignumRequest empty = {NULL,  0ull, NULL, OBSIGNATIO_MODE_HASH, out, OBSIGNATIO_SIGNUM_BYTES,
                                           &error};
    test_count(results, (obsignatio_signum(&empty) == 0L) && (memcmp(out, vectors->cases[0].hash, sizeof(out)) == 0) &&
                            (vectors->cases[0].length == 0ull) && (error.kind == ENGINE_ERROR_NONE));
    const int placed = cudaMemcpy(device_signum, before, sizeof(before), cudaMemcpyHostToDevice) == cudaSuccess;
    const ObsignatioManyRequest many_cases[] = {
        {NULL, 1ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_HASH, device_signum, &error},
        {device_pattern, 1ull, 1ull, 1ull, NULL, 1u, device_signum, &error},
        {device_pattern, 1ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_KEYED, device_signum, &error},
        {device_pattern, 1ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_MATERIAL, device_signum, &error},
        {device_pattern, 1ull, 1ull, 1ull, key, OBSIGNATIO_MODE_HASH, device_signum, &error},
        {device_pattern, 1ull, 1ull, 1ull, key, OBSIGNATIO_MODE_CONTEXT, device_signum, &error},
    };
    for (unsigned int index = 0u; index < (unsigned int)(sizeof(many_cases) / sizeof(many_cases[0])); index += 1u)
    {
        memset(&error, 0, sizeof(error));
        test_count(results, placed && test_error_many(&many_cases[index], device_signum, before));
    }
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest unsigned_out = {device_pattern,       1ull, 1ull,  1ull, NULL,
                                                OBSIGNATIO_MODE_HASH, NULL, &error};
    test_count(results, (obsignatio_many(&unsigned_out) == OBSIGNATIO_ERROR) && (error.kind == ENGINE_ERROR_REQUEST));
    test_count(results, obsignatio_many(NULL) == OBSIGNATIO_ERROR);
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest nothing = {NULL, 0ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_HASH, NULL, &error};
    test_count(results, (obsignatio_many(&nothing) == 0L) && (error.kind == ENGINE_ERROR_NONE));
}
#endif

void test_level_keys(TestResults *results)
{
    unsigned char keys[OBSIGNATIO_LEVELS][OBSIGNATIO_KEY_BYTES];
    const char *contexts[OBSIGNATIO_LEVELS];
    const char *const prefix = "obsignatio aeterna 2026-09-23 ";
    int derived = 1;
    for (unsigned int level = 0u; level < OBSIGNATIO_LEVELS; level += 1u)
    {
        EngineError error;
        memset(&error, 0, sizeof(error));
        // a level below OBSIGNATIO_LEVELS is one of the enumerated levels
        const ObsignatioLevel named = (ObsignatioLevel)level;
        const char *const context = obsignatio_level_context(named);
        contexts[level] = context;
        unsigned char expected[OBSIGNATIO_KEY_BYTES];
        // the context's chars are hashed as the unsigned bytes they are stored as
        const int passed = (context != NULL) && (strncmp(context, prefix, strlen(prefix)) == 0) &&
                           (obsignatio_level_key(named, keys[level], &error) == 0L) &&
                           (test_signum((const unsigned char *)context, strlen(context), NULL, OBSIGNATIO_MODE_CONTEXT,
                                        expected, OBSIGNATIO_KEY_BYTES) == 0L) &&
                           (memcmp(expected, keys[level], OBSIGNATIO_KEY_BYTES) == 0);
        test_count(results, passed);
        derived = derived && passed;
    }
    int distinct = derived;
    for (unsigned int left = 0u; derived && (left < OBSIGNATIO_LEVELS); left += 1u)
    {
        for (unsigned int right = left + 1u; right < OBSIGNATIO_LEVELS; right += 1u)
        {
            distinct = distinct && (memcmp(keys[left], keys[right], OBSIGNATIO_KEY_BYTES) != 0) &&
                       (strcmp(contexts[left], contexts[right]) != 0);
        }
    }
    test_count(results, distinct);
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    test_count(results, (obsignatio_level_context(OBSIGNATIO_LEVELS) == NULL) &&
                            (obsignatio_level_key(OBSIGNATIO_LEVELS, key, &error) == OBSIGNATIO_ERROR) &&
                            (error.kind == ENGINE_ERROR_REQUEST) && (error.module == ENGINE_MODULE_OBSIGNATIO));
    memset(&error, 0, sizeof(error));
    test_count(results, (obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, NULL, &error) == OBSIGNATIO_ERROR) &&
                            (error.kind == ENGINE_ERROR_REQUEST));
    test_count(results, obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, key, NULL) == OBSIGNATIO_ERROR);
}

void test_seal(const unsigned char *pattern, TestResults *results)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned char file_key[OBSIGNATIO_KEY_BYTES];
    const int keyed = obsignatio_level_key(OBSIGNATIO_LEVEL_FILE, file_key, &error) == 0L;
    test_count(results, keyed);
    const unsigned long long lengths[4] = {0ull, 1ull, 64ull, 1500ull};
    for (unsigned int which = 0u; which < 4u; which += 1u)
    {
        unsigned char sealed[OBSIGNATIO_SIGNUM_BYTES];
        unsigned char expected[OBSIGNATIO_SIGNUM_BYTES];
        const ObsignatioSealRequest seal = {pattern, lengths[which], sealed, &error};
        const int passed = keyed && (obsignatio_seal(&seal) == 0L) &&
                           (test_signum(pattern, lengths[which], file_key, OBSIGNATIO_MODE_KEYED, expected,
                                        OBSIGNATIO_SIGNUM_BYTES) == 0L) &&
                           (memcmp(sealed, expected, OBSIGNATIO_SIGNUM_BYTES) == 0) &&
                           (obsignatio_seal_verify(&seal) == 1L);
        test_count(results, passed);
    }
    unsigned char message[64];
    memcpy(message, pattern, sizeof(message));
    unsigned char sealed[OBSIGNATIO_SIGNUM_BYTES];
    const ObsignatioSealRequest clean = {message, sizeof(message), sealed, &error};
    const int sealed_clean = obsignatio_seal(&clean) == 0L;
    for (unsigned int bit = 0u; bit < (8u * sizeof(message)); bit += 1u)
    {
        // one bit of the message flipped
        message[bit / 8u] = (unsigned char)(message[bit / 8u] ^ (1u << (bit % 8u)));
        test_count(results, sealed_clean && (obsignatio_seal_verify(&clean) == 0L));
        // the same bit flipped back
        message[bit / 8u] = (unsigned char)(message[bit / 8u] ^ (1u << (bit % 8u)));
    }
    for (unsigned int bit = 0u; bit < (8u * OBSIGNATIO_SIGNUM_BYTES); bit += 1u)
    {
        // one bit of the seal flipped
        sealed[bit / 8u] = (unsigned char)(sealed[bit / 8u] ^ (1u << (bit % 8u)));
        test_count(results, sealed_clean && (obsignatio_seal_verify(&clean) == 0L));
        // the same bit flipped back
        sealed[bit / 8u] = (unsigned char)(sealed[bit / 8u] ^ (1u << (bit % 8u)));
    }
    test_count(results, sealed_clean && (obsignatio_seal_verify(&clean) == 1L));
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest no_signum = {message, sizeof(message), NULL, &error};
    test_count(results, (obsignatio_seal(&no_signum) == OBSIGNATIO_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                            (error.module == ENGINE_MODULE_OBSIGNATIO));
    memset(&error, 0, sizeof(error));
    test_count(results,
               (obsignatio_seal_verify(&no_signum) == OBSIGNATIO_ERROR) && (error.kind == ENGINE_ERROR_REQUEST));
    const ObsignatioSealRequest no_error = {message, sizeof(message), sealed, NULL};
    test_count(results, (obsignatio_seal(&no_error) == OBSIGNATIO_ERROR) &&
                            (obsignatio_seal_verify(&no_error) == OBSIGNATIO_ERROR));
    test_count(results, obsignatio_seal(NULL) == OBSIGNATIO_ERROR);
}
