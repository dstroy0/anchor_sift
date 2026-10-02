// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_table_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_TABLE_TEST_INTERNAL_H
#define RECORD_TABLE_TEST_INTERNAL_H

//
// The lookup table (ENGINE_RECORD_TABLE) proved against the ordinary record operations. Every table is
// filled by running an ordinary-ops program over its whole alphabet. The ops are the oracle: a table
// step must then reproduce those ops lane for lane, on the device and on the host, and a chain of table
// steps must compose the way reading one table through another does. The register reuse the scheduler
// grew for long programs is proved to leave the output unchanged while shrinking the file. The test is one job on the
// device's tessera daemon, submitted before its first device work.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define TABLE_TEST_LINE 8192ull

#define TABLE_TEST_ALPHABET 65536u

#define TABLE_TEST_LANES 4096u

#define TABLE_TEST_STEPS 64u

// The widest output record any program here writes, in 32-bit words.
#define ANCHOR_RECORD_OUT_WORDS 4u

// the most the test puts on the device at once: two tables over the alphabet, and a sweep's atoms and records
#define TABLE_TEST_DECLARED                                                                                            \
    ((2ull * TABLE_TEST_ALPHABET * sizeof(unsigned int)) +                                                             \
     ((unsigned long long)TABLE_TEST_LANES * (1ull + ANCHOR_RECORD_OUT_WORDS) * sizeof(unsigned int)))

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} TableResults;

typedef struct
{
    EngineRecordStep steps[TABLE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[4];
    unsigned int field_offset[4];
    unsigned int fields;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[4];
    unsigned int output_count;
    EngineRecordTable tables[4];
    unsigned int table_count;
    int reuse;
} TableProgram;

unsigned int table_random(void);

void table_check(TableResults *results, int passed, const char *what);

void table_program_init(TableProgram *program);

void table_step(TableProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right);

int table_run_host(TableProgram *program, const unsigned int *atoms, unsigned long long count, unsigned int *out,
                   unsigned int *out_limbs);

int table_run_device(TableProgram *program, const unsigned int *atoms, unsigned long long count, unsigned int *out,
                     unsigned int *out_limbs);

int table_fill_from_ops(TableProgram *oracle, unsigned int value_bits, unsigned int *values);

void table_case(TableResults *results, const char *name, TableProgram *oracle, unsigned int value_bits);

#endif
