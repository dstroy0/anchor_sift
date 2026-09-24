// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "obsignatio.h"
#include "scriptura.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_PATTERN_PERIOD 251u

#define TEST_BYTE_BITS 8u

#define TEST_FLIP_BATCH (TEST_PATTERN_PERIOD * TEST_BYTE_BITS)

#define TEST_LAYOUT_MESSAGES 3ull

#define TEST_NAME_COLUMNS 16u

#define TEST_COUNT_COLUMNS 20u

#define TEST_REPORT_ROW \
    (2ull + TEST_NAME_COLUMNS + TEST_COUNT_COLUMNS + sizeof(" cases, ") + TEST_COUNT_COLUMNS + sizeof(" failed") \
     + sizeof(", first at case ") + TEST_COUNT_COLUMNS + 1ull)

typedef struct
{
    unsigned long long length;
    unsigned long long out_bytes;
    unsigned char *hash;
    unsigned char *keyed;
    unsigned char *derived;
} TestCase;

typedef struct
{
    TestCase *cases;
    unsigned int count;
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    char *context;
    unsigned long long longest;
} TestVectors;

typedef struct
{
    const char *name;
    unsigned long long cases;
    unsigned long long failures;
    unsigned long long first_failure;
} TestTally;

static void test_count(TestTally *tally, int passed)
{
    if ((passed == 0) && (tally->failures == 0ull))
    {
        tally->first_failure = tally->cases;
    }
    tally->failures += (passed == 0) ? 1ull : 0ull;
    tally->cases += 1ull;
}

static char *test_file_read(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return NULL;
    }
    const int sought = fseek(file, 0L, SEEK_END);
    const long size = (sought == 0) ? ftell(file) : -1L;
    // a size of zero or more from ftell converts to size_t exactly
    char *const text = (size >= 0L) ? (char *)malloc((size_t)size + 1u) : NULL;
    const int rewound = (text != NULL) ? fseek(file, 0L, SEEK_SET) : -1;
    // a size of zero or more from ftell converts to size_t exactly
    const size_t read = (rewound == 0) ? fread(text, 1u, (size_t)size, file) : 0u;
    fclose(file);
    // a size of zero or more from ftell converts to size_t exactly
    if ((text == NULL) || (read != (size_t)size))
    {
        free(text);
        return NULL;
    }
    text[read] = '\0';
    return text;
}

static const char *test_string_after(const char *from, const char *key, unsigned long long *length)
{
    const char *const found = strstr(from, key);
    if (found == NULL)
    {
        return NULL;
    }
    const char *const start = found + strlen(key);
    const char *const end = strchr(start, '"');
    if (end == NULL)
    {
        return NULL;
    }
    // the closing quote lies after the start, so the difference is positive
    *length = (unsigned long long)(end - start);
    return start;
}

static int test_hex_nibble(char digit, unsigned int *value)
{
    if ((digit >= '0') && (digit <= '9'))
    {
        // a decimal digit less '0' lies in 0 to 9
        *value = (unsigned int)(digit - '0');
        return 1;
    }
    if ((digit >= 'a') && (digit <= 'f'))
    {
        // a hex letter less 'a' lies in 0 to 5
        *value = (unsigned int)(digit - 'a') + 10u;
        return 1;
    }
    return 0;
}

static unsigned char *test_hex_decode(const char *hex, unsigned long long digits)
{
    if ((digits % 2ull) != 0ull)
    {
        return NULL;
    }
    unsigned char *const bytes = (unsigned char *)malloc((size_t)(digits / 2ull) + 1u);
    if (bytes == NULL)
    {
        return NULL;
    }
    for (unsigned long long byte = 0ull; byte < (digits / 2ull); byte += 1ull)
    {
        unsigned int high = 0u;
        unsigned int low = 0u;
        if ((test_hex_nibble(hex[2ull * byte], &high) == 0) || (test_hex_nibble(hex[(2ull * byte) + 1ull], &low) == 0))
        {
            free(bytes);
            return NULL;
        }
        // two nibbles make one byte below 256
        bytes[byte] = (unsigned char)((high << 4u) | low);
    }
    return bytes;
}

static void test_vectors_release(TestVectors *vectors)
{
    for (unsigned int index = 0u; index < vectors->count; index += 1u)
    {
        free(vectors->cases[index].hash);
        free(vectors->cases[index].keyed);
        free(vectors->cases[index].derived);
    }
    free(vectors->cases);
    free(vectors->context);
    memset(vectors, 0, sizeof(*vectors));
}

static int test_vectors_load(const char *path, TestVectors *vectors)
{
    memset(vectors, 0, sizeof(*vectors));
    char *const text = test_file_read(path);
    if (text == NULL)
    {
        return 0;
    }
    unsigned long long key_length = 0ull;
    unsigned long long context_length = 0ull;
    const char *const key = test_string_after(text, "\"key\": \"", &key_length);
    const char *const context = test_string_after(text, "\"context_string\": \"", &context_length);
    unsigned int count = 0u;
    for (const char *at = strstr(text, "\"input_len\": "); at != NULL; at = strstr(at + 1, "\"input_len\": "))
    {
        count += 1u;
    }
    int good = (key != NULL) && (key_length == OBSIGNATIO_KEY_BYTES) && (context != NULL) && (count != 0u);
    vectors->cases = good ? (TestCase *)calloc(count, sizeof(TestCase)) : NULL;
    vectors->context = good ? (char *)malloc((size_t)context_length + 1u) : NULL;
    good = good && (vectors->cases != NULL) && (vectors->context != NULL);
    if (good)
    {
        memcpy(vectors->key, key, OBSIGNATIO_KEY_BYTES);
        memcpy(vectors->context, context, (size_t)context_length);
        vectors->context[context_length] = '\0';
        vectors->count = count;
    }
    const char *at = text;
    for (unsigned int index = 0u; good && (index < count); index += 1u)
    {
        at = strstr(at, "\"input_len\": ");
        TestCase *const one = &vectors->cases[index];
        char *after = NULL;
        one->length = strtoull(at + strlen("\"input_len\": "), &after, 10);
        unsigned long long hash_digits = 0ull;
        unsigned long long keyed_digits = 0ull;
        unsigned long long derived_digits = 0ull;
        const char *const hash = test_string_after(after, "\"hash\": \"", &hash_digits);
        const char *const keyed = test_string_after(after, "\"keyed_hash\": \"", &keyed_digits);
        const char *const derived = test_string_after(after, "\"derive_key\": \"", &derived_digits);
        good = (hash != NULL) && (keyed != NULL) && (derived != NULL) && (hash_digits == keyed_digits)
            && (hash_digits == derived_digits) && (hash_digits >= (2ull * OBSIGNATIO_SIGNUM_BYTES));
        one->out_bytes = hash_digits / 2ull;
        one->hash = good ? test_hex_decode(hash, hash_digits) : NULL;
        one->keyed = good ? test_hex_decode(keyed, keyed_digits) : NULL;
        one->derived = good ? test_hex_decode(derived, derived_digits) : NULL;
        good = good && (one->hash != NULL) && (one->keyed != NULL) && (one->derived != NULL);
        vectors->longest = (one->length > vectors->longest) ? one->length : vectors->longest;
        at = after;
    }
    free(text);
    if (good == 0)
    {
        test_vectors_release(vectors);
    }
    return good;
}

static long test_signum(const unsigned char *bytes, unsigned long long count, const unsigned char *key,
                        unsigned int mode, unsigned char *out, unsigned long long out_bytes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSignumRequest request = {bytes, count, key, mode, out, out_bytes, &error};
    return obsignatio_signum(&request);
}

static long test_many(const unsigned char *device_bytes, unsigned long long messages, unsigned long long length,
                      unsigned long long stride, const unsigned char *key, unsigned int mode,
                      unsigned char *device_signa)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest request = {device_bytes, messages, length, stride, key, mode, device_signa, &error};
    return obsignatio_many(&request);
}

static const unsigned char *test_mode_key(unsigned int mode, const TestVectors *vectors,
                                          const unsigned char *context_key)
{
    if (mode == OBSIGNATIO_MODE_KEYED)
    {
        return vectors->key;
    }
    return (mode == OBSIGNATIO_MODE_MATERIAL) ? context_key : NULL;
}

static const unsigned char *test_mode_expected(unsigned int mode, const TestCase *one)
{
    if (mode == OBSIGNATIO_MODE_KEYED)
    {
        return one->keyed;
    }
    return (mode == OBSIGNATIO_MODE_MATERIAL) ? one->derived : one->hash;
}

static const unsigned int test_modes[3] = {OBSIGNATIO_MODE_HASH, OBSIGNATIO_MODE_KEYED, OBSIGNATIO_MODE_MATERIAL};

static void test_host_vectors(const TestVectors *vectors, const unsigned char *pattern,
                              const unsigned char *context_key, TestTally *tally)
{
    for (unsigned int index = 0u; index < vectors->count; index += 1u)
    {
        const TestCase *const one = &vectors->cases[index];
        unsigned char *const out = (unsigned char *)malloc((size_t)one->out_bytes);
        for (unsigned int mode = 0u; mode < 3u; mode += 1u)
        {
            const unsigned char *const key = test_mode_key(test_modes[mode], vectors, context_key);
            const unsigned char *const expected = test_mode_expected(test_modes[mode], one);
            const long extended = (out != NULL)
                                    ? test_signum(pattern, one->length, key, test_modes[mode], out, one->out_bytes)
                                    : OBSIGNATIO_REFUSED;
            test_count(tally, (extended == 0L) && (memcmp(out, expected, (size_t)one->out_bytes) == 0));
            unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
            const long plain = test_signum(pattern, one->length, key, test_modes[mode], signum, OBSIGNATIO_SIGNUM_BYTES);
            test_count(tally, (plain == 0L) && (memcmp(signum, expected, OBSIGNATIO_SIGNUM_BYTES) == 0));
        }
        free(out);
    }
}

static void test_device_vectors(const TestVectors *vectors, const unsigned char *pattern,
                                const unsigned char *context_key, TestTally *tally)
{
    for (unsigned int index = 0u; index < vectors->count; index += 1u)
    {
        const TestCase *const one = &vectors->cases[index];
        for (unsigned long long offset = 0ull; offset < 2ull; offset += 1ull)
        {
            for (unsigned long long gap = 0ull; gap < 2ull; gap += 1ull)
            {
                const unsigned long long stride = one->length + gap;
                const unsigned long long room = offset + (stride * TEST_LAYOUT_MESSAGES) + 1ull;
                unsigned char *const laid = (unsigned char *)malloc((size_t)room);
                unsigned char *device_laid = NULL;
                unsigned char *device_signa = NULL;
                unsigned char signa[TEST_LAYOUT_MESSAGES * OBSIGNATIO_SIGNUM_BYTES];
                int ready = (laid != NULL) && (cudaMalloc((void **)&device_laid, (size_t)room) == cudaSuccess)
                         && (cudaMalloc((void **)&device_signa, sizeof(signa)) == cudaSuccess);
                if (ready)
                {
                    memset(laid, 0xFF, (size_t)room);
                    for (unsigned long long message = 0ull; message < TEST_LAYOUT_MESSAGES; message += 1ull)
                    {
                        memcpy(&laid[offset + (message * stride)], pattern, (size_t)one->length);
                    }
                    ready = cudaMemcpy(device_laid, laid, (size_t)room, cudaMemcpyHostToDevice) == cudaSuccess;
                }
                for (unsigned int mode = 0u; mode < 3u; mode += 1u)
                {
                    const unsigned char *const key = test_mode_key(test_modes[mode], vectors, context_key);
                    const unsigned char *const expected = test_mode_expected(test_modes[mode], one);
                    memset(signa, 0, sizeof(signa));
                    const int ran = ready
                                 && (test_many(&device_laid[offset], TEST_LAYOUT_MESSAGES, one->length, stride, key,
                                               test_modes[mode], device_signa)
                                     == 0L)
                                 && (cudaMemcpy(signa, device_signa, sizeof(signa), cudaMemcpyDeviceToHost)
                                     == cudaSuccess);
                    for (unsigned long long message = 0ull; message < TEST_LAYOUT_MESSAGES; message += 1ull)
                    {
                        test_count(tally, ran
                                              && (memcmp(&signa[message * OBSIGNATIO_SIGNUM_BYTES], expected,
                                                         OBSIGNATIO_SIGNUM_BYTES)
                                                  == 0));
                    }
                }
                cudaFree(device_signa);
                cudaFree(device_laid);
                free(laid);
            }
        }
    }
}

static void test_device_context(const TestVectors *vectors, const unsigned char *context_key, TestTally *tally)
{
    const unsigned long long length = strlen(vectors->context);
    unsigned char *device_context = NULL;
    unsigned char *device_signum = NULL;
    unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
    const int ran = (cudaMalloc((void **)&device_context, (size_t)length + 1u) == cudaSuccess)
                 && (cudaMalloc((void **)&device_signum, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess)
                 && (cudaMemcpy(device_context, vectors->context, (size_t)length, cudaMemcpyHostToDevice)
                     == cudaSuccess)
                 && (test_many(device_context, 1ull, length, length, NULL, OBSIGNATIO_MODE_CONTEXT, device_signum)
                     == 0L)
                 && (cudaMemcpy(signum, device_signum, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost) == cudaSuccess);
    test_count(tally, ran && (memcmp(signum, context_key, OBSIGNATIO_SIGNUM_BYTES) == 0));
    cudaFree(device_signum);
    cudaFree(device_context);
}

static void test_every_length(const TestVectors *vectors, const unsigned char *pattern,
                              const unsigned char *device_pattern, const unsigned char *context_key,
                              unsigned char *device_signum, TestTally *tally)
{
    for (unsigned long long length = 0ull; length <= vectors->longest; length += 1ull)
    {
        for (unsigned int mode = 0u; mode < 3u; mode += 1u)
        {
            const unsigned char *const key = test_mode_key(test_modes[mode], vectors, context_key);
            unsigned char host[OBSIGNATIO_SIGNUM_BYTES];
            unsigned char device[OBSIGNATIO_SIGNUM_BYTES];
            memset(device, 0, sizeof(device));
            const int ran = (test_signum(pattern, length, key, test_modes[mode], host, OBSIGNATIO_SIGNUM_BYTES) == 0L)
                         && (test_many(device_pattern, 1ull, length, length, key, test_modes[mode], device_signum)
                             == 0L)
                         && (cudaMemcpy(device, device_signum, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost)
                             == cudaSuccess);
            test_count(tally, ran && (memcmp(host, device, OBSIGNATIO_SIGNUM_BYTES) == 0));
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

static void test_bit_flips(const TestVectors *vectors, const unsigned char *device_pattern, TestTally *tally)
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
        int ready = (signa != NULL)
                 && (cudaMalloc((void **)&device_flipped, (size_t)(TEST_FLIP_BATCH * one->length)) == cudaSuccess)
                 && (cudaMalloc((void **)&device_signa, (size_t)(TEST_FLIP_BATCH * OBSIGNATIO_SIGNUM_BYTES))
                     == cudaSuccess);
        for (unsigned long long first = 0ull; ready && (first < flips); first += TEST_FLIP_BATCH)
        {
            const unsigned long long batch = ((flips - first) < TEST_FLIP_BATCH) ? (flips - first) : TEST_FLIP_BATCH;
            test_flip_kernel<<<TEST_PATTERN_PERIOD, TEST_PATTERN_PERIOD>>>(device_pattern, one->length, first, batch,
                                                                          device_flipped);
            ready = (cudaGetLastError() == cudaSuccess)
                 && (test_many(device_flipped, batch, one->length, one->length, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa)
                     == 0L)
                 && (cudaMemcpy(&signa[first * OBSIGNATIO_SIGNUM_BYTES], device_signa,
                                (size_t)(batch * OBSIGNATIO_SIGNUM_BYTES), cudaMemcpyDeviceToHost)
                     == cudaSuccess);
        }
        for (unsigned long long flip = 0ull; flip < flips; flip += 1ull)
        {
            test_count(tally, ready
                                  && (memcmp(&signa[flip * OBSIGNATIO_SIGNUM_BYTES], one->hash,
                                             OBSIGNATIO_SIGNUM_BYTES)
                                      != 0));
        }
        int distinct = ready;
        if (ready)
        {
            memcpy(&signa[flips * OBSIGNATIO_SIGNUM_BYTES], one->hash, OBSIGNATIO_SIGNUM_BYTES);
            qsort(signa, (size_t)(flips + 1ull), OBSIGNATIO_SIGNUM_BYTES, test_signum_order);
            for (unsigned long long at = 1ull; at <= flips; at += 1ull)
            {
                distinct = distinct
                        && (memcmp(&signa[(at - 1ull) * OBSIGNATIO_SIGNUM_BYTES], &signa[at * OBSIGNATIO_SIGNUM_BYTES],
                                   OBSIGNATIO_SIGNUM_BYTES)
                            != 0);
            }
        }
        test_count(tally, distinct);
        cudaFree(device_signa);
        cudaFree(device_flipped);
        free(signa);
    }
}

static void test_determinism(const TestVectors *vectors, const unsigned char *device_pattern, TestTally *tally)
{
    const unsigned long long length = vectors->longest - TEST_PATTERN_PERIOD;
    const size_t bytes = (size_t)(TEST_PATTERN_PERIOD * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const first = (unsigned char *)malloc(bytes);
    unsigned char *const second = (unsigned char *)malloc(bytes);
    unsigned char *device_signa = NULL;
    const int ran = (first != NULL) && (second != NULL) && (vectors->longest > TEST_PATTERN_PERIOD)
                 && (cudaMalloc((void **)&device_signa, bytes) == cudaSuccess)
                 && (test_many(device_pattern, TEST_PATTERN_PERIOD, length, 1ull, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa)
                     == 0L)
                 && (cudaMemcpy(first, device_signa, bytes, cudaMemcpyDeviceToHost) == cudaSuccess)
                 && (cudaMemset(device_signa, 0, bytes) == cudaSuccess)
                 && (test_many(device_pattern, TEST_PATTERN_PERIOD, length, 1ull, NULL, OBSIGNATIO_MODE_HASH,
                               device_signa)
                     == 0L)
                 && (cudaMemcpy(second, device_signa, bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    test_count(tally, ran && (memcmp(first, second, bytes) == 0));
    int windows_differ = ran;
    for (unsigned long long window = 1ull; ran && (window < TEST_PATTERN_PERIOD); window += 1ull)
    {
        windows_differ = windows_differ
                      && (memcmp(&first[(window - 1ull) * OBSIGNATIO_SIGNUM_BYTES],
                                 &first[window * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES)
                          != 0);
    }
    test_count(tally, windows_differ);
    cudaFree(device_signa);
    free(second);
    free(first);
}

static int test_refused_signum(const ObsignatioSignumRequest *request, const unsigned char *out_before,
                               const unsigned char *out)
{
    const long status = obsignatio_signum(request);
    const int untouched = (out == NULL) || (memcmp(out, out_before, OBSIGNATIO_SIGNUM_BYTES) == 0);
    const int raised = (request == NULL) || (request->error == NULL)
                    || ((request->error->kind == ENGINE_ERROR_REQUEST)
                        && (request->error->module == ENGINE_MODULE_OBSIGNATIO));
    return (status == OBSIGNATIO_REFUSED) && untouched && raised;
}

static int test_refused_many(const ObsignatioManyRequest *request, const unsigned char *device_signa,
                             const unsigned char *signa_before)
{
    const long status = obsignatio_many(request);
    unsigned char after[OBSIGNATIO_SIGNUM_BYTES];
    const int read = cudaMemcpy(after, device_signa, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost) == cudaSuccess;
    const int raised = (request == NULL) || (request->error == NULL)
                    || ((request->error->kind == ENGINE_ERROR_REQUEST)
                        && (request->error->module == ENGINE_MODULE_OBSIGNATIO));
    return (status == OBSIGNATIO_REFUSED) && read && (memcmp(after, signa_before, OBSIGNATIO_SIGNUM_BYTES) == 0)
        && raised;
}

static void test_fail_closed(const TestVectors *vectors, const unsigned char *pattern,
                             const unsigned char *device_pattern, unsigned char *device_signum, TestTally *tally)
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
        test_count(tally, test_refused_signum(&signum_cases[index], before, out));
    }
    memset(&error, 0, sizeof(error));
    memcpy(out, before, sizeof(out));
    const ObsignatioSignumRequest unfinished = {pattern, 1ull, NULL, OBSIGNATIO_MODE_HASH, out,
                                                OBSIGNATIO_SIGNUM_BYTES, NULL};
    test_count(tally, test_refused_signum(&unfinished, before, out));
    test_count(tally, obsignatio_signum(NULL) == OBSIGNATIO_REFUSED);
    memset(&error, 0, sizeof(error));
    const ObsignatioSignumRequest empty = {NULL, 0ull, NULL, OBSIGNATIO_MODE_HASH, out, OBSIGNATIO_SIGNUM_BYTES, &error};
    test_count(tally, (obsignatio_signum(&empty) == 0L) && (memcmp(out, vectors->cases[0].hash, sizeof(out)) == 0)
                          && (vectors->cases[0].length == 0ull) && (error.kind == ENGINE_ERROR_NONE));
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
        test_count(tally, placed && test_refused_many(&many_cases[index], device_signum, before));
    }
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest unsigned_out = {device_pattern, 1ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_HASH, NULL,
                                                &error};
    test_count(tally, (obsignatio_many(&unsigned_out) == OBSIGNATIO_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST));
    test_count(tally, obsignatio_many(NULL) == OBSIGNATIO_REFUSED);
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest nothing = {NULL, 0ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_HASH, NULL, &error};
    test_count(tally, (obsignatio_many(&nothing) == 0L) && (error.kind == ENGINE_ERROR_NONE));
}

static void test_level_keys(TestTally *tally)
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
        const int held = (context != NULL) && (strncmp(context, prefix, strlen(prefix)) == 0)
                      && (obsignatio_level_key(named, keys[level], &error) == 0L)
                      && (test_signum((const unsigned char *)context, strlen(context), NULL, OBSIGNATIO_MODE_CONTEXT,
                                      expected, OBSIGNATIO_KEY_BYTES)
                          == 0L)
                      && (memcmp(expected, keys[level], OBSIGNATIO_KEY_BYTES) == 0);
        test_count(tally, held);
        derived = derived && held;
    }
    int distinct = derived;
    for (unsigned int left = 0u; derived && (left < OBSIGNATIO_LEVELS); left += 1u)
    {
        for (unsigned int right = left + 1u; right < OBSIGNATIO_LEVELS; right += 1u)
        {
            distinct = distinct && (memcmp(keys[left], keys[right], OBSIGNATIO_KEY_BYTES) != 0)
                    && (strcmp(contexts[left], contexts[right]) != 0);
        }
    }
    test_count(tally, distinct);
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned char key[OBSIGNATIO_KEY_BYTES];
    test_count(tally, (obsignatio_level_context(OBSIGNATIO_LEVELS) == NULL)
                          && (obsignatio_level_key(OBSIGNATIO_LEVELS, key, &error) == OBSIGNATIO_REFUSED)
                          && (error.kind == ENGINE_ERROR_REQUEST) && (error.module == ENGINE_MODULE_OBSIGNATIO));
    memset(&error, 0, sizeof(error));
    test_count(tally, (obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, NULL, &error) == OBSIGNATIO_REFUSED)
                          && (error.kind == ENGINE_ERROR_REQUEST));
    test_count(tally, obsignatio_level_key(OBSIGNATIO_LEVEL_ROW, key, NULL) == OBSIGNATIO_REFUSED);
}

static void test_seal(const unsigned char *pattern, TestTally *tally)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned char file_key[OBSIGNATIO_KEY_BYTES];
    const int keyed = obsignatio_level_key(OBSIGNATIO_LEVEL_FILE, file_key, &error) == 0L;
    test_count(tally, keyed);
    const unsigned long long lengths[4] = {0ull, 1ull, 64ull, 1500ull};
    for (unsigned int which = 0u; which < 4u; which += 1u)
    {
        unsigned char sealed[OBSIGNATIO_SIGNUM_BYTES];
        unsigned char expected[OBSIGNATIO_SIGNUM_BYTES];
        const ObsignatioSealRequest seal = {pattern, lengths[which], sealed, &error};
        const int held = keyed && (obsignatio_seal(&seal) == 0L)
                      && (test_signum(pattern, lengths[which], file_key, OBSIGNATIO_MODE_KEYED, expected,
                                      OBSIGNATIO_SIGNUM_BYTES)
                          == 0L)
                      && (memcmp(sealed, expected, OBSIGNATIO_SIGNUM_BYTES) == 0) && (obsignatio_seal_holds(&seal) == 1L);
        test_count(tally, held);
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
        test_count(tally, sealed_clean && (obsignatio_seal_holds(&clean) == 0L));
        // the same bit flipped back
        message[bit / 8u] = (unsigned char)(message[bit / 8u] ^ (1u << (bit % 8u)));
    }
    for (unsigned int bit = 0u; bit < (8u * OBSIGNATIO_SIGNUM_BYTES); bit += 1u)
    {
        // one bit of the seal flipped
        sealed[bit / 8u] = (unsigned char)(sealed[bit / 8u] ^ (1u << (bit % 8u)));
        test_count(tally, sealed_clean && (obsignatio_seal_holds(&clean) == 0L));
        // the same bit flipped back
        sealed[bit / 8u] = (unsigned char)(sealed[bit / 8u] ^ (1u << (bit % 8u)));
    }
    test_count(tally, sealed_clean && (obsignatio_seal_holds(&clean) == 1L));
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest no_signum = {message, sizeof(message), NULL, &error};
    test_count(tally, (obsignatio_seal(&no_signum) == OBSIGNATIO_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
                          && (error.module == ENGINE_MODULE_OBSIGNATIO));
    memset(&error, 0, sizeof(error));
    test_count(tally, (obsignatio_seal_holds(&no_signum) == OBSIGNATIO_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST));
    const ObsignatioSealRequest no_error = {message, sizeof(message), sealed, NULL};
    test_count(tally, (obsignatio_seal(&no_error) == OBSIGNATIO_REFUSED)
                          && (obsignatio_seal_holds(&no_error) == OBSIGNATIO_REFUSED));
    test_count(tally, obsignatio_seal(NULL) == OBSIGNATIO_REFUSED);
}

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
                        OBSIGNATIO_KEY_BYTES)
            != 0L)
        {
            return 0;
        }
    }
    const unsigned long long counts[OBSIGNATIO_EXTENT_AXES] = {extent[0] * extent[1] * extent[2],
                                                                 extent[0] * extent[1], extent[0], 1ull};
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
                            &to[node * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES)
                != 0L)
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

static void test_lanes_reference(TestTally *tally)
{
    const unsigned long long shapes[][OBSIGNATIO_EXTENT_AXES] = {{1ull, 1ull, 1ull, 1ull},    {1ull, 1ull, 1ull, 512ull},
                                                                   {2ull, 3ull, 5ull, 511ull},  {3ull, 2ull, 33ull, 513ull},
                                                                   {2ull, 33ull, 3ull, 1025ull}, {33ull, 1ull, 2ull, 7ull},
                                                                   {1ull, 65ull, 1ull, 3ull}};
    for (unsigned int shape = 0u; shape < (unsigned int)(sizeof(shapes) / sizeof(shapes[0])); shape += 1u)
    {
        const unsigned long long *const extent = shapes[shape];
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
        ready = ready && (cudaMalloc((void **)&device_lanes, (size_t)bytes) == cudaSuccess)
             && (cudaMalloc((void **)&device_nodes, (size_t)node_bytes) == cudaSuccess)
             && (cudaMemcpy(device_lanes, lane_bytes, (size_t)bytes, cudaMemcpyHostToDevice) == cudaSuccess)
             && (test_lanes_device(device_lanes, extent, device_nodes) == 0L)
             && (cudaMemcpy(device, device_nodes, (size_t)node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess)
             && test_lanes_host(lane_bytes, extent, host);
        test_count(tally, ready && (memcmp(host, device, (size_t)node_bytes) == 0));
        cudaFree(device_nodes);
        cudaFree(device_lanes);
        free(device);
        free(host);
        free(lane_bytes);
    }
}

static void test_lanes_locality(TestTally *tally)
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
    ready = ready && (cudaMalloc((void **)&device_lanes, (size_t)lanes * sizeof(unsigned short)) == cudaSuccess)
         && (cudaMalloc((void **)&device_nodes, node_bytes) == cudaSuccess)
         && (cudaMemcpy(device_lanes, host_lanes, (size_t)lanes * sizeof(unsigned short), cudaMemcpyHostToDevice)
             == cudaSuccess)
         && (test_lanes_device(device_lanes, extent, device_nodes) == 0L)
         && (cudaMemcpy(base, device_nodes, node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        // a bit index below 16 selects one bit of a lane, and the XOR stays below 65536
        const unsigned short changed = (unsigned short)(host_lanes[lane] ^ (1u << (unsigned int)(lane % 16ull)));
        const int ran = ready
                     && (cudaMemcpy(&device_lanes[lane], &changed, sizeof(changed), cudaMemcpyHostToDevice)
                         == cudaSuccess)
                     && (test_lanes_device(device_lanes, extent, device_nodes) == 0L)
                     && (cudaMemcpy(flipped, device_nodes, node_bytes, cudaMemcpyDeviceToHost) == cudaSuccess)
                     && (cudaMemcpy(&device_lanes[lane], &host_lanes[lane], sizeof(changed), cudaMemcpyHostToDevice)
                         == cudaSuccess);
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
                                       OBSIGNATIO_SIGNUM_BYTES)
                             != 0;
            local = local && (on_path == differs);
        }
        test_count(tally, local);
    }
    cudaFree(device_nodes);
    cudaFree(device_lanes);
    free(flipped);
    free(base);
    free(host_lanes);
}

static void test_lanes_closed(TestTally *tally)
{
    const unsigned long long extent[OBSIGNATIO_EXTENT_AXES] = {1ull, 1ull, 1ull, 2ull};
    const unsigned long long zero_axes[OBSIGNATIO_EXTENT_AXES][OBSIGNATIO_EXTENT_AXES] = {
        {0ull, 1ull, 1ull, 2ull}, {1ull, 0ull, 1ull, 2ull}, {1ull, 1ull, 0ull, 2ull}, {1ull, 1ull, 1ull, 0ull}};
    unsigned short *device_lanes = NULL;
    unsigned char *device_nodes = NULL;
    unsigned char before[OBSIGNATIO_SIGNUM_BYTES];
    memset(before, 0xA5, sizeof(before));
    const int ready = (cudaMalloc((void **)&device_lanes, 2u * sizeof(unsigned short)) == cudaSuccess)
                   && (cudaMalloc((void **)&device_nodes, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess)
                   && (cudaMemset(device_lanes, 0, 2u * sizeof(unsigned short)) == cudaSuccess)
                   && (cudaMemcpy(device_nodes, before, sizeof(before), cudaMemcpyHostToDevice) == cudaSuccess);
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
        test_count(tally, ready && (status == OBSIGNATIO_REFUSED) && read && (memcmp(after, before, sizeof(after)) == 0)
                              && (error.kind == ENGINE_ERROR_REQUEST) && (error.module == ENGINE_MODULE_OBSIGNATIO));
    }
    const ObsignatioLanesRequest unfinished = {device_lanes, extent, device_nodes, NULL};
    test_count(tally, obsignatio_lanes(&unfinished) == OBSIGNATIO_REFUSED);
    test_count(tally, obsignatio_lanes(NULL) == OBSIGNATIO_REFUSED);
    test_count(tally, (obsignatio_lanes_nodes(NULL) == 0ull) && (obsignatio_lanes_nodes(zero_axes[3]) == 0ull)
                          && (obsignatio_lanes_nodes(extent) == 4ull));
    cudaFree(device_nodes);
    cudaFree(device_lanes);
}

#define TEST_LENGTH_BYTES 8ull

#define TEST_CHUNK_BITS ((1024ull - TEST_LENGTH_BYTES) * 8ull)

typedef struct
{
    unsigned int *limbs;
    unsigned long long limb_count;
    unsigned long long *offsets;
    unsigned long long messages;
    unsigned long long bits;
} TestBitStream;

static void test_bit_stream_release(TestBitStream *stream)
{
    free(stream->limbs);
    free(stream->offsets);
    memset(stream, 0, sizeof(*stream));
}

static int test_bit_stream_make(TestBitStream *stream)
{
    const unsigned long long lengths[] = {0ull,  1ull,  7ull,  8ull,  9ull,  31ull,
                                          32ull, 33ull, 63ull, 64ull, 65ull, TEST_CHUNK_BITS - 1ull,
                                          TEST_CHUNK_BITS, TEST_CHUNK_BITS + 1ull, 2ull * TEST_CHUNK_BITS,
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
        const unsigned long long end = ((message + 1ull) < stream->messages) ? stream->offsets[message + 1ull]
                                                                              : stream->bits;
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
        const long hashed = test_signum(bytes, count, key, mode, &signa[message * OBSIGNATIO_SIGNUM_BYTES],
                                        OBSIGNATIO_SIGNUM_BYTES);
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
    const ObsignatioBitsRequest request = {device_limbs, device_offsets, stream->messages, stream->bits, key, mode,
                                           device_signa, &error};
    return obsignatio_bits(&request);
}

typedef struct
{
    unsigned int *limbs;
    unsigned long long *offsets;
    unsigned char *signa;
} TestBitDevice;

static int test_bit_device_place(const TestBitStream *stream, TestBitDevice *device)
{
    memset(device, 0, sizeof(*device));
    return (cudaMalloc((void **)&device->limbs, (size_t)stream->limb_count * sizeof(unsigned int)) == cudaSuccess)
        && (cudaMalloc((void **)&device->offsets, (size_t)stream->messages * sizeof(unsigned long long)) == cudaSuccess)
        && (cudaMalloc((void **)&device->signa, (size_t)stream->messages * OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess)
        && (cudaMemcpy(device->limbs, stream->limbs, (size_t)stream->limb_count * sizeof(unsigned int),
                       cudaMemcpyHostToDevice)
            == cudaSuccess)
        && (cudaMemcpy(device->offsets, stream->offsets, (size_t)stream->messages * sizeof(unsigned long long),
                       cudaMemcpyHostToDevice)
            == cudaSuccess);
}

static void test_bit_device_release(TestBitDevice *device)
{
    cudaFree(device->signa);
    cudaFree(device->offsets);
    cudaFree(device->limbs);
    memset(device, 0, sizeof(*device));
}

static void test_bits_reference(const TestVectors *vectors, TestTally *tally)
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
        const int ran = ready && test_bits_host(&stream, key, modes[mode], host)
                     && (test_bits_device(device.limbs, device.offsets, &stream, key, modes[mode], device.signa) == 0L)
                     && (cudaMemcpy(read, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
        for (unsigned long long message = 0ull; message < stream.messages; message += 1ull)
        {
            test_count(tally, ran
                                  && (memcmp(&host[message * OBSIGNATIO_SIGNUM_BYTES],
                                             &read[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES)
                                      == 0));
        }
    }
    free(read);
    free(host);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}

static void test_bits_locality(TestTally *tally)
{
    TestBitStream stream;
    TestBitDevice device;
    int ready = test_bit_stream_make(&stream) && test_bit_device_place(&stream, &device);
    const size_t signa_bytes = (size_t)(stream.messages * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const base = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned char *const flipped = ready ? (unsigned char *)malloc(signa_bytes) : NULL;
    ready = ready && (base != NULL) && (flipped != NULL)
         && (test_bits_device(device.limbs, device.offsets, &stream, NULL, OBSIGNATIO_MODE_HASH, device.signa) == 0L)
         && (cudaMemcpy(base, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    for (unsigned long long bit = 0ull; bit < (stream.limb_count * 32ull); bit += 1ull)
    {
        const unsigned int changed = stream.limbs[bit / 32ull] ^ (1u << (bit % 32ull));
        const int ran = ready
                     && (cudaMemcpy(&device.limbs[bit / 32ull], &changed, sizeof(changed), cudaMemcpyHostToDevice)
                         == cudaSuccess)
                     && (test_bits_device(device.limbs, device.offsets, &stream, NULL, OBSIGNATIO_MODE_HASH,
                                          device.signa)
                         == 0L)
                     && (cudaMemcpy(flipped, device.signa, signa_bytes, cudaMemcpyDeviceToHost) == cudaSuccess)
                     && (cudaMemcpy(&device.limbs[bit / 32ull], &stream.limbs[bit / 32ull], sizeof(changed),
                                    cudaMemcpyHostToDevice)
                         == cudaSuccess);
        int local = ran;
        for (unsigned long long message = 0ull; ran && (message < stream.messages); message += 1ull)
        {
            const unsigned long long end = ((message + 1ull) < stream.messages) ? stream.offsets[message + 1ull]
                                                                                 : stream.bits;
            const int inside = (bit >= stream.offsets[message]) && (bit < end);
            const int differs = memcmp(&base[message * OBSIGNATIO_SIGNUM_BYTES],
                                       &flipped[message * OBSIGNATIO_SIGNUM_BYTES], OBSIGNATIO_SIGNUM_BYTES)
                             != 0;
            local = local && (inside == differs);
        }
        test_count(tally, local);
    }
    free(flipped);
    free(base);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}

static void test_bits_closed(const TestVectors *vectors, TestTally *tally)
{
    TestBitStream stream;
    TestBitDevice device;
    memset(&device, 0, sizeof(device));
    const int placed = test_bit_stream_make(&stream) && test_bit_device_place(&stream, &device);
    if (placed == 0)
    {
        test_count(tally, 0);
        test_bit_device_release(&device);
        test_bit_stream_release(&stream);
        return;
    }
    const size_t signa_bytes = (size_t)(stream.messages * OBSIGNATIO_SIGNUM_BYTES);
    unsigned char *const before = placed ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned char *const after = placed ? (unsigned char *)malloc(signa_bytes) : NULL;
    unsigned long long *device_backward = NULL;
    unsigned long long *const backward = placed ? (unsigned long long *)malloc(
                                                      (size_t)stream.messages * sizeof(unsigned long long))
                                                : NULL;
    int ready = placed && (before != NULL) && (after != NULL) && (backward != NULL);
    if (ready)
    {
        memset(before, 0xA5, signa_bytes);
        memcpy(backward, stream.offsets, (size_t)stream.messages * sizeof(unsigned long long));
        backward[2] = backward[3] + 1ull;
        ready = (cudaMemcpy(device.signa, before, signa_bytes, cudaMemcpyHostToDevice) == cudaSuccess)
             && (cudaMalloc((void **)&device_backward, (size_t)stream.messages * sizeof(unsigned long long))
                 == cudaSuccess)
             && (cudaMemcpy(device_backward, backward, (size_t)stream.messages * sizeof(unsigned long long),
                            cudaMemcpyHostToDevice)
                 == cudaSuccess);
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
        test_count(tally, read && (status == OBSIGNATIO_REFUSED) && (memcmp(after, before, signa_bytes) == 0)
                              && (error.kind == ENGINE_ERROR_REQUEST) && (error.module == ENGINE_MODULE_OBSIGNATIO));
    }
    const ObsignatioBitsRequest unfinished = {device.limbs, device.offsets, stream.messages, stream.bits, NULL,
                                              OBSIGNATIO_MODE_HASH, device.signa, NULL};
    test_count(tally, obsignatio_bits(&unfinished) == OBSIGNATIO_REFUSED);
    test_count(tally, obsignatio_bits(NULL) == OBSIGNATIO_REFUSED);
    memset(&error, 0, sizeof(error));
    const ObsignatioBitsRequest nothing = {NULL, NULL, 0ull, 0ull, NULL, OBSIGNATIO_MODE_HASH, NULL, &error};
    test_count(tally, (obsignatio_bits(&nothing) == 0L) && (error.kind == ENGINE_ERROR_NONE));
    cudaFree(device_backward);
    free(backward);
    free(after);
    free(before);
    test_bit_device_release(&device);
    test_bit_stream_release(&stream);
}

static int test_staged(ScripturaLine *line, const char *text, unsigned int columns)
{
    const size_t length = strlen(text);
    char *const staged = (char *)calloc((length / 8u) + 1u, 8u);
    if (staged == NULL)
    {
        line->at = line->room;
        return 0;
    }
    memcpy(staged, text, length);
    if (columns == 0u)
    {
        scriptura_text(line, staged);
    }
    else
    {
        scriptura_text_columns(line, staged, columns);
    }
    free(staged);
    return 1;
}

static int test_report(const TestTally *tallies, unsigned int count, const char *vectors_path)
{
    const unsigned long long room = strlen("  obsignatio against \n") + strlen(vectors_path)
                                  + (count * TEST_REPORT_ROW) + 1ull;
    ScripturaLine line = {(char *)malloc((size_t)room), room, 0ull};
    if (line.out == NULL)
    {
        return 0;
    }
    test_staged(&line, "  obsignatio against ", 0u);
    test_staged(&line, vectors_path, 0u);
    scriptura_character(&line, '\n');
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const TestTally *const tally = &tallies[index];
        test_staged(&line, "  ", 0u);
        test_staged(&line, tally->name, TEST_NAME_COLUMNS);
        scriptura_decimal_columns(&line, tally->cases, TEST_COUNT_COLUMNS);
        test_staged(&line, " cases, ", 0u);
        scriptura_decimal(&line, tally->failures, 1u);
        test_staged(&line, " failed", 0u);
        if (tally->failures != 0ull)
        {
            test_staged(&line, ", first at case ", 0u);
            scriptura_decimal(&line, tally->first_failure, 1u);
        }
        scriptura_character(&line, '\n');
    }
    const int written = scriptura_write(&line, stdout);
    free(line.out);
    return written;
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        fputs("  usage: obsignatio_test <test_vectors.json>\n", stderr);
        return 2;
    }
    TestVectors vectors;
    if (test_vectors_load(argv[1], &vectors) == 0)
    {
        fputs("  the test vectors could not be read\n", stderr);
        return 2;
    }
    unsigned char *const pattern = (unsigned char *)malloc((size_t)vectors.longest + 1u);
    unsigned char *device_pattern = NULL;
    unsigned char *device_signum = NULL;
    unsigned char context_key[OBSIGNATIO_KEY_BYTES];
    const int ready = (pattern != NULL)
                   && (cudaMalloc((void **)&device_pattern, (size_t)vectors.longest + 1u) == cudaSuccess)
                   && (cudaMalloc((void **)&device_signum, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess);
    if (ready == 0)
    {
        fputs("  the test could not place its pattern\n", stderr);
        return 2;
    }
    for (unsigned long long byte = 0ull; byte <= vectors.longest; byte += 1ull)
    {
        // a byte index taken modulo 251 lies below 256
        pattern[byte] = (unsigned char)(byte % TEST_PATTERN_PERIOD);
    }
    const int placed = (cudaMemcpy(device_pattern, pattern, (size_t)vectors.longest + 1u, cudaMemcpyHostToDevice)
                        == cudaSuccess)
                    && (test_signum((const unsigned char *)vectors.context, strlen(vectors.context), NULL,
                                    OBSIGNATIO_MODE_CONTEXT, context_key, OBSIGNATIO_KEY_BYTES)
                        == 0L);
    if (placed == 0)
    {
        fputs("  the test could not place its pattern or context key\n", stderr);
        return 2;
    }
    TestTally tallies[] = {{"host vectors", 0ull, 0ull, 0ull},   {"device vectors", 0ull, 0ull, 0ull},
                           {"device context", 0ull, 0ull, 0ull}, {"every length", 0ull, 0ull, 0ull},
                           {"bit flips", 0ull, 0ull, 0ull},      {"determinism", 0ull, 0ull, 0ull},
                           {"fail closed", 0ull, 0ull, 0ull},    {"level keys", 0ull, 0ull, 0ull},
                           {"lanes reference", 0ull, 0ull, 0ull}, {"lanes locality", 0ull, 0ull, 0ull},
                           {"lanes closed", 0ull, 0ull, 0ull},    {"bits reference", 0ull, 0ull, 0ull},
                           {"bits locality", 0ull, 0ull, 0ull},   {"bits closed", 0ull, 0ull, 0ull},
                           {"seal", 0ull, 0ull, 0ull}};
    test_host_vectors(&vectors, pattern, context_key, &tallies[0]);
    test_device_vectors(&vectors, pattern, context_key, &tallies[1]);
    test_device_context(&vectors, context_key, &tallies[2]);
    test_every_length(&vectors, pattern, device_pattern, context_key, device_signum, &tallies[3]);
    test_bit_flips(&vectors, device_pattern, &tallies[4]);
    test_determinism(&vectors, device_pattern, &tallies[5]);
    test_fail_closed(&vectors, pattern, device_pattern, device_signum, &tallies[6]);
    test_level_keys(&tallies[7]);
    test_lanes_reference(&tallies[8]);
    test_lanes_locality(&tallies[9]);
    test_lanes_closed(&tallies[10]);
    test_bits_reference(&vectors, &tallies[11]);
    test_bits_locality(&tallies[12]);
    test_bits_closed(&vectors, &tallies[13]);
    test_seal(pattern, &tallies[14]);
    const unsigned int count = (unsigned int)(sizeof(tallies) / sizeof(tallies[0]));
    const int reported = test_report(tallies, count, argv[1]);
    unsigned long long failures = (reported != 0) ? 0ull : 1ull;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        failures += tallies[index].failures;
    }
    cudaFree(device_signum);
    cudaFree(device_pattern);
    free(pattern);
    test_vectors_release(&vectors);
    return (failures == 0ull) ? 0 : 1;
}
