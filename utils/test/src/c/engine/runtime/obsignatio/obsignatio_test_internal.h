// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the obsignatio_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef OBSIGNATIO_TEST_INTERNAL_H
#define OBSIGNATIO_TEST_INTERNAL_H

#include "../../../../../../../src/c/engine/runtime/obsignatio/obsignatio.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"

// a part with no CUDA toolchain builds the test as C++ and asks the host's questions alone: the vectors, the level
// keys and the seal, and that a request for device memory errors
#if defined(__CUDACC__)
#include <cuda_runtime.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_PATTERN_PERIOD 251u

#define TEST_BYTE_BITS 8u

#define TEST_FLIP_BATCH (TEST_PATTERN_PERIOD * TEST_BYTE_BITS)

#define TEST_LAYOUT_MESSAGES 3ull

#define TEST_NAME_COLUMNS 16u

#define TEST_COUNT_COLUMNS 20u

#define TEST_REPORT_ROW                                                                                                \
    (2ull + TEST_NAME_COLUMNS + TEST_COUNT_COLUMNS + sizeof(" cases, ") + TEST_COUNT_COLUMNS + sizeof(" failed") +     \
     sizeof(", first at case ") + TEST_COUNT_COLUMNS + 1ull)

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
} TestResults;

void test_count(TestResults *results, int passed);

void test_vectors_release(TestVectors *vectors);

int test_vectors_load(const char *path, TestVectors *vectors);

long test_signum(const unsigned char *bytes, unsigned long long count, const unsigned char *key, unsigned int mode,
                 unsigned char *out, unsigned long long out_bytes);
#if (defined(__CUDACC__))

long test_many(const unsigned char *device_bytes, unsigned long long messages, unsigned long long length,
               unsigned long long stride, const unsigned char *key, unsigned int mode, unsigned char *device_signa);
#endif

const unsigned char *test_mode_key(unsigned int mode, const TestVectors *vectors, const unsigned char *context_key);

static const unsigned int test_modes[3] = {OBSIGNATIO_MODE_HASH, OBSIGNATIO_MODE_KEYED, OBSIGNATIO_MODE_MATERIAL};

void test_host_vectors(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *context_key,
                       TestResults *results);
#if (defined(__CUDACC__))

void test_device_vectors(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *context_key,
                         TestResults *results);

void test_device_context(const TestVectors *vectors, const unsigned char *context_key, TestResults *results);

void test_every_length(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *device_pattern,
                       const unsigned char *context_key, unsigned char *device_signum, TestResults *results);

void test_bit_flips(const TestVectors *vectors, const unsigned char *device_pattern, TestResults *results);

void test_determinism(const TestVectors *vectors, const unsigned char *device_pattern, TestResults *results);

void test_fail_closed(const TestVectors *vectors, const unsigned char *pattern, const unsigned char *device_pattern,
                      unsigned char *device_signum, TestResults *results);
#endif

void test_level_keys(TestResults *results);

void test_seal(const unsigned char *pattern, TestResults *results);
#if (defined(__CUDACC__))

void test_lanes_reference(TestResults *results);

void test_lanes_locality(TestResults *results);

void test_lanes_closed(TestResults *results);

typedef struct
{
    unsigned int *limbs;
    unsigned long long limb_count;
    unsigned long long *offsets;
    unsigned long long messages;
    unsigned long long bits;
} TestBitStream;

typedef struct
{
    unsigned int *limbs;
    unsigned long long *offsets;
    unsigned char *signa;
} TestBitDevice;

void test_bits_reference(const TestVectors *vectors, TestResults *results);

void test_bits_locality(TestResults *results);

void test_bits_closed(const TestVectors *vectors, TestResults *results);
#endif

#endif
