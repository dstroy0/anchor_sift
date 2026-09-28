// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_bitwise_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_BITWISE_TEST_INTERNAL_H
#define RECORD_BITWISE_TEST_INTERNAL_H

//
// The record machine's bitwise operations (ENGINE_RECORD_XOR, _AND) and its two's complement wrap (ENGINE_RECORD_WRAP),
// proved against an oracle that never reads a register. Every bit of every output is rebuilt from the raw two's
// complement fields in the atom, sign-extended, xored, anded and wrapped one bit at a time; a product's bits come from
// the exact integer library's multiply. Each program runs on the device and on the host, the two records must agree
// word for word, and the host's must equal the oracle on every written bit. The oracle's sign must also already
// extend for BITWISE_TEST_BEYOND bits past each written width. A bound keymath set too narrow cannot hide in a
// truncated record. Hand-worked answers, both register files, and the refusals at encode (a wrap below 4 bits, an
// operation reading a later step) are checked too. Last, a stack of floors far past a thousand steps (rounds over four
// 32-bit words, each floored by a wrap) runs as one program with register reuse, checked against the CPU's own 64-bit
// two's complement at every tapped floor. And one level of the tower's 5/3 lifting with its inverse, the floor
// divisions made from an and and an exact quotient, must equal tower_*.cu's formulas and return every sample exactly.
// The test is one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "exact_integer.h"
#include "key_schedule.h"
#include "keymath.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define BITWISE_TEST_LINE 8192ull

#define BITWISE_TEST_STEPS 24u

#define BITWISE_TEST_FIELDS 4u

#define BITWISE_TEST_NARROW_LANES 4096u

#define BITWISE_TEST_WIDE_LANES 512u

// the most the test puts on the device at once: the narrow sweep's atoms and records, under 64 words a lane
#define BITWISE_TEST_DECLARED ((unsigned long long)BITWISE_TEST_NARROW_LANES * 64ull * sizeof(unsigned int))

// how far past each output's written width the oracle's sign must already extend
#define BITWISE_TEST_BEYOND 64u

// the stack: floors of one round each over four 32-bit words, the round's steps, and the lanes it runs
#define BITWISE_TEST_FLOORS 700u

#define BITWISE_TEST_FLOOR_STEPS 6u

#define BITWISE_TEST_STACK_WORDS 4u

#define BITWISE_TEST_STACK_LANES 1024u

// the floors whose word is read out: the first, the middle, and the last four, which are the final state
#define BITWISE_TEST_STACK_TAPS 6u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} BitwiseResults;

typedef struct
{
    EngineRecordStep steps[BITWISE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[BITWISE_TEST_FIELDS];
    unsigned int field_offset[BITWISE_TEST_FIELDS];
    unsigned int fields;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[BITWISE_TEST_STEPS];
    unsigned int output_count;
} BitwiseProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} BitwiseLoaded;

// one lane's oracle: its atom, and each product step's exact value with its magnitude less one
typedef struct
{
    const BitwiseProgram *program;
    const unsigned int *atom;
    AnchorExactInteger product[BITWISE_TEST_STEPS];
    AnchorExactInteger product_less_one[BITWISE_TEST_STEPS];
} BitwiseOracle;

unsigned int bitwise_random(void);

void bitwise_check(BitwiseResults *results, int passed, const char *what);

void bitwise_step(BitwiseProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right);

void bitwise_field(BitwiseProgram *program, unsigned int bits);

int bitwise_load(const BitwiseProgram *program, BitwiseLoaded *loaded);

void bitwise_free(BitwiseLoaded *loaded);

void bitwise_run(BitwiseLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                 unsigned int *device_out, int *host_ran, int *device_ran);

void bitwise_field_fill(unsigned int *atom, unsigned int offset, unsigned int bits, unsigned int pattern);

void bitwise_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value);

int bitwise_oracle_open(BitwiseOracle *oracle, const BitwiseProgram *program, const unsigned int *atom);

int bitwise_record_valid(const BitwiseOracle *oracle, const DeviceRecordStep *table, const unsigned int *record);

void bitwise_narrow(BitwiseResults *results);

void bitwise_wide(BitwiseResults *results);

void bitwise_narrowed(BitwiseResults *results);

void bitwise_known(BitwiseResults *results);

void bitwise_refused(BitwiseResults *results);

long long bitwise_wrap_native(long long value, unsigned int bits);

unsigned int bitwise_floor_constant(unsigned int floor);

// room for the level and its inverse: 8 fields, 4 highs and 4 lows each way at up to 8 steps, and the constant 2
#define BITWISE_TEST_LIFT_STEPS 160u

typedef struct
{
    EngineRecordStep steps[BITWISE_TEST_LIFT_STEPS];
    unsigned int count;
} BitwiseLift;

#endif
