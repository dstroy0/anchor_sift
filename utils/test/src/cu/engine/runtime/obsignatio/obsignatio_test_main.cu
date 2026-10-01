// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// obsignatio_test_main.cu: device errors, staging, the report and main
#include "../../../../../engine/runtime/obsignatio/obsignatio_test_internal.h"

#if !(defined(__CUDACC__))
// with no device, a request for device memory errors as a resource the part lacks, and one with no error errors
static void test_device_error(TestResults *results)
{
    unsigned char bytes[OBSIGNATIO_SIGNUM_BYTES] = {0};
    unsigned char signa[OBSIGNATIO_SIGNUM_BYTES];
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioManyRequest many = {bytes, 1ull, 1ull, 1ull, NULL, OBSIGNATIO_MODE_HASH, signa, &error};
    test_count(results, (obsignatio_many(&many) == OBSIGNATIO_ERROR) && (error.kind == ENGINE_ERROR_RESOURCE) &&
                            (error.module == ENGINE_MODULE_OBSIGNATIO));
    test_count(results, obsignatio_many(NULL) == OBSIGNATIO_ERROR);
    memset(&error, 0, sizeof(error));
    const unsigned long long offsets[2] = {0ull, 0ull};
    const ObsignatioBitsRequest bits = {NULL, offsets, 1ull, 0ull, NULL, OBSIGNATIO_MODE_HASH, signa, &error};
    test_count(results, (obsignatio_bits(&bits) == OBSIGNATIO_ERROR) && (error.kind == ENGINE_ERROR_RESOURCE) &&
                            (error.module == ENGINE_MODULE_OBSIGNATIO));
    test_count(results, obsignatio_bits(NULL) == OBSIGNATIO_ERROR);
}
#endif

static int test_staged(ScripturaLine *line, const char *text, unsigned int columns)
{
    const size_t length = strlen(text);
    char *const staged = (char *)calloc((length / 8u) + 1u, 8u);
    if (staged == NULL)
    {
        line->at = line->capacity;
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

static int test_report(const TestResults *tallies, unsigned int count, const char *vectors_path)
{
    const unsigned long long capacity =
        strlen("  obsignatio against \n") + strlen(vectors_path) + (count * TEST_REPORT_ROW) + 1ull;
    ScripturaLine line = {(char *)malloc((size_t)capacity), capacity, 0ull};
    if (line.out == NULL)
    {
        return 0;
    }
    test_staged(&line, "  obsignatio against ", 0u);
    test_staged(&line, vectors_path, 0u);
    scriptura_character(&line, '\n');
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        const TestResults *const results = &tallies[index];
        test_staged(&line, "  ", 0u);
        test_staged(&line, results->name, TEST_NAME_COLUMNS);
        scriptura_decimal_columns(&line, results->cases, TEST_COUNT_COLUMNS);
        test_staged(&line, " cases, ", 0u);
        scriptura_decimal(&line, results->failures, 1u);
        test_staged(&line, " failed", 0u);
        if (results->failures != 0ull)
        {
            test_staged(&line, ", first at case ", 0u);
            scriptura_decimal(&line, results->first_failure, 1u);
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
    unsigned char context_key[OBSIGNATIO_KEY_BYTES];
#if defined(__CUDACC__)
    unsigned char *device_pattern = NULL;
    unsigned char *device_signum = NULL;
    const int ready = (pattern != NULL) &&
                      (cudaMalloc((void **)&device_pattern, (size_t)vectors.longest + 1u) == cudaSuccess) &&
                      (cudaMalloc((void **)&device_signum, OBSIGNATIO_SIGNUM_BYTES) == cudaSuccess);
#else
    const int ready = pattern != NULL;
#endif
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
#if defined(__CUDACC__)
    const int copied =
        cudaMemcpy(device_pattern, pattern, (size_t)vectors.longest + 1u, cudaMemcpyHostToDevice) == cudaSuccess;
#else
    const int copied = 1;
#endif
    const int placed = copied && (test_signum((const unsigned char *)vectors.context, strlen(vectors.context), NULL,
                                              OBSIGNATIO_MODE_CONTEXT, context_key, OBSIGNATIO_KEY_BYTES) == 0L);
    if (placed == 0)
    {
        fputs("  the test could not place its pattern or context key\n", stderr);
        return 2;
    }
#if defined(__CUDACC__)
    TestResults tallies[] = {{"host vectors", 0ull, 0ull, 0ull},
                             {"device vectors", 0ull, 0ull, 0ull},
                             {"device context", 0ull, 0ull, 0ull},
                             {"every length", 0ull, 0ull, 0ull},
                             {"bit flips", 0ull, 0ull, 0ull},
                             {"determinism", 0ull, 0ull, 0ull},
                             {"fail closed", 0ull, 0ull, 0ull},
                             {"level keys", 0ull, 0ull, 0ull},
                             {"lanes reference", 0ull, 0ull, 0ull},
                             {"lanes locality", 0ull, 0ull, 0ull},
                             {"lanes closed", 0ull, 0ull, 0ull},
                             {"bits reference", 0ull, 0ull, 0ull},
                             {"bits locality", 0ull, 0ull, 0ull},
                             {"bits closed", 0ull, 0ull, 0ull},
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
#else
    TestResults tallies[] = {{"host vectors", 0ull, 0ull, 0ull},
                             {"level keys", 0ull, 0ull, 0ull},
                             {"seal", 0ull, 0ull, 0ull},
                             {"device errored", 0ull, 0ull, 0ull}};
    test_host_vectors(&vectors, pattern, context_key, &tallies[0]);
    test_level_keys(&tallies[1]);
    test_seal(pattern, &tallies[2]);
    test_device_error(&tallies[3]);
#endif
    const unsigned int count = (unsigned int)(sizeof(tallies) / sizeof(tallies[0]));
    const int reported = test_report(tallies, count, argv[1]);
    unsigned long long failures = (reported != 0) ? 0ull : 1ull;
    for (unsigned int index = 0u; index < count; index += 1u)
    {
        failures += tallies[index].failures;
    }
#if defined(__CUDACC__)
    cudaFree(device_signum);
    cudaFree(device_pattern);
#endif
    free(pattern);
    test_vectors_release(&vectors);
    return (failures == 0ull) ? 0 : 1;
}
