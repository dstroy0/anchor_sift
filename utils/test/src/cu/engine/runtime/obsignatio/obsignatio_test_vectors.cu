// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_test_vectors.cu: files, hex and the test vectors
#include "../../../../../engine/runtime/obsignatio/obsignatio_test_internal.h"

void test_count(TestResults *results, int passed)
{
    if ((passed == 0) && (results->failures == 0ull))
    {
        results->first_failure = results->cases;
    }
    results->failures += (passed == 0) ? 1ull : 0ull;
    results->cases += 1ull;
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
    // the closing quote lies after the start. The difference is positive
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

void test_vectors_release(TestVectors *vectors)
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

int test_vectors_load(const char *path, TestVectors *vectors)
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
    int ok = (key != NULL) && (key_length == OBSIGNATIO_KEY_BYTES) && (context != NULL) && (count != 0u);
    vectors->cases = ok ? (TestCase *)calloc(count, sizeof(TestCase)) : NULL;
    vectors->context = ok ? (char *)malloc((size_t)context_length + 1u) : NULL;
    ok = ok && (vectors->cases != NULL) && (vectors->context != NULL);
    if (ok)
    {
        memcpy(vectors->key, key, OBSIGNATIO_KEY_BYTES);
        memcpy(vectors->context, context, (size_t)context_length);
        vectors->context[context_length] = '\0';
        vectors->count = count;
    }
    const char *at = text;
    for (unsigned int index = 0u; ok && (index < count); index += 1u)
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
        ok = (hash != NULL) && (keyed != NULL) && (derived != NULL) && (hash_digits == keyed_digits) &&
             (hash_digits == derived_digits) && (hash_digits >= (2ull * OBSIGNATIO_SIGNUM_BYTES));
        one->out_bytes = hash_digits / 2ull;
        one->hash = ok ? test_hex_decode(hash, hash_digits) : NULL;
        one->keyed = ok ? test_hex_decode(keyed, keyed_digits) : NULL;
        one->derived = ok ? test_hex_decode(derived, derived_digits) : NULL;
        ok = ok && (one->hash != NULL) && (one->keyed != NULL) && (one->derived != NULL);
        vectors->longest = (one->length > vectors->longest) ? one->length : vectors->longest;
        at = after;
    }
    free(text);
    if (ok == 0)
    {
        test_vectors_release(vectors);
    }
    return ok;
}

long test_signum(const unsigned char *bytes, unsigned long long count, const unsigned char *key, unsigned int mode,
                 unsigned char *out, unsigned long long out_bytes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSignumRequest request = {bytes, count, key, mode, out, out_bytes, &error};
    return obsignatio_signum(&request);
}
#if (defined(__CUDACC__))
long test_many(const unsigned char *device_bytes, unsigned long long messages, unsigned long long length,
               unsigned long long stride, const unsigned char *key, unsigned int mode, unsigned char *device_signa)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest request = {device_bytes, messages, length, stride, key, mode, device_signa, &error};
    return obsignatio_many(&request);
}
#endif

const unsigned char *test_mode_key(unsigned int mode, const TestVectors *vectors, const unsigned char *context_key)
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

void test_host_vectors(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *context_key,
                       TestResults *results)
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
                                      : OBSIGNATIO_ERROR;
            test_count(results, (extended == 0L) && (memcmp(out, expected, (size_t)one->out_bytes) == 0));
            unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
            const long plain =
                test_signum(pattern, one->length, key, test_modes[mode], signum, OBSIGNATIO_SIGNUM_BYTES);
            test_count(results, (plain == 0L) && (memcmp(signum, expected, OBSIGNATIO_SIGNUM_BYTES) == 0));
        }
        free(out);
    }
}
#if (defined(__CUDACC__))
void test_device_vectors(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *context_key,
                         TestResults *results)
{
    for (unsigned int index = 0u; index < vectors->count; index += 1u)
    {
        const TestCase *const one = &vectors->cases[index];
        for (unsigned long long offset = 0ull; offset < 2ull; offset += 1ull)
        {
            for (unsigned long long gap = 0ull; gap < 2ull; gap += 1ull)
            {
                const unsigned long long stride = one->length + gap;
                const unsigned long long capacity = offset + (stride * TEST_LAYOUT_MESSAGES) + 1ull;
                unsigned char *const host_messages = (unsigned char *)malloc((size_t)capacity);
                unsigned char *device_messages = NULL;
                unsigned char *device_signa = NULL;
                unsigned char signa[TEST_LAYOUT_MESSAGES * OBSIGNATIO_SIGNUM_BYTES];
                int ready = (host_messages != NULL) &&
                            (cudaMalloc((void **)&device_messages, (size_t)capacity) == cudaSuccess) &&
                            (cudaMalloc((void **)&device_signa, sizeof(signa)) == cudaSuccess);
                if (ready)
                {
                    memset(host_messages, 0xFF, (size_t)capacity);
                    for (unsigned long long message = 0ull; message < TEST_LAYOUT_MESSAGES; message += 1ull)
                    {
                        memcpy(&host_messages[offset + (message * stride)], pattern, (size_t)one->length);
                    }
                    ready = cudaMemcpy(device_messages, host_messages, (size_t)capacity, cudaMemcpyHostToDevice) ==
                            cudaSuccess;
                }
                for (unsigned int mode = 0u; mode < 3u; mode += 1u)
                {
                    const unsigned char *const key = test_mode_key(test_modes[mode], vectors, context_key);
                    const unsigned char *const expected = test_mode_expected(test_modes[mode], one);
                    memset(signa, 0, sizeof(signa));
                    const int ran =
                        ready &&
                        (test_many(&device_messages[offset], TEST_LAYOUT_MESSAGES, one->length, stride, key,
                                   test_modes[mode], device_signa) == 0L) &&
                        (cudaMemcpy(signa, device_signa, sizeof(signa), cudaMemcpyDeviceToHost) == cudaSuccess);
                    for (unsigned long long message = 0ull; message < TEST_LAYOUT_MESSAGES; message += 1ull)
                    {
                        test_count(results, ran && (memcmp(&signa[message * OBSIGNATIO_SIGNUM_BYTES], expected,
                                                           OBSIGNATIO_SIGNUM_BYTES) == 0));
                    }
                }
                cudaFree(device_signa);
                cudaFree(device_messages);
                free(host_messages);
            }
        }
    }
}

void test_device_context(const TestVectors *vectors, const unsigned char *context_key, TestResults *results)
{
    const unsigned long long length = strlen(vectors->context);
    unsigned char *device_context = NULL;
    unsigned char *device_signum = NULL;
    unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
    const int ran =
        (cudaMalloc((void **)&device_context, (size_t)length + 1u) == cudaSuccess) &&
        (cudaMalloc((void **)&device_signum, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess) &&
        (cudaMemcpy(device_context, vectors->context, (size_t)length, cudaMemcpyHostToDevice) == cudaSuccess) &&
        (test_many(device_context, 1ull, length, length, NULL, OBSIGNATIO_MODE_CONTEXT, device_signum) == 0L) &&
        (cudaMemcpy(signum, device_signum, OBSIGNATIO_SIGNUM_BYTES, cudaMemcpyDeviceToHost) == cudaSuccess);
    test_count(results, ran && (memcmp(signum, context_key, OBSIGNATIO_SIGNUM_BYTES) == 0));
    cudaFree(device_signum);
    cudaFree(device_context);
}
#endif
