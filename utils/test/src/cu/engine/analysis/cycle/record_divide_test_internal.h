// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_divide_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_DIVIDE_TEST_INTERNAL_H
#define RECORD_DIVIDE_TEST_INTERNAL_H

//
// The exact integer's division as key primitives (ENGINE_RECORD_QUOTIENT, _REMAINDER, _GCD, _EXACT_QUOTIENT),
// proved on the register bit arrays. Each program runs on the device and on the host (whose steps are the
// exact integer library itself), the two records must agree word for word, and the decoded registers must meet
// numerator = quotient . divisor + remainder with the remainder below the divisor and carrying the numerator's
// sign, a gcd dividing both, and an exact quotient returning the factor it was built from. A zero divisor and an
// inexact division error, on both sides. Both register files are exercised: the 64-limb kernel on signed
// 160-bit numerators and the 256-limb kernel on 2048-bit numerators. The test is one job on the device's tessera
// daemon, submitted before its first device work.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/types/integers/exact_integer.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define DIVIDE_TEST_LINE 8192ull

#define DIVIDE_TEST_STEPS 16u

#define DIVIDE_TEST_FIELDS 4u

#define DIVIDE_TEST_NARROW_LANES 4096u

#define DIVIDE_TEST_WIDE_LANES 512u

// the most the test puts on the device at once: the wide sweep's 96-limb atoms and records of up to 256 limbs
#define DIVIDE_TEST_DECLARED ((unsigned long long)DIVIDE_TEST_WIDE_LANES * (96ull + 256ull) * sizeof(unsigned int))

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} DivideResults;

typedef struct
{
    EngineRecordStep steps[DIVIDE_TEST_STEPS];
    unsigned int count;
    unsigned int field_bits[DIVIDE_TEST_FIELDS];
    unsigned int field_offset[DIVIDE_TEST_FIELDS];
    unsigned int fields;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int outputs[DIVIDE_TEST_FIELDS];
    unsigned int output_count;
} DivideProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} DivideLoaded;

unsigned int divide_random(void);

void divide_check(DivideResults *results, int passed, const char *what);

void divide_step(DivideProgram *program, EngineRecordOperation operation, unsigned int left, unsigned int right);

int divide_load(DivideProgram *program, DivideLoaded *loaded);

void divide_free(DivideLoaded *loaded);

void divide_run(DivideLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                unsigned int *device_out, int *host_ran, int *device_ran);

void divide_put(unsigned int *atom, unsigned int offset, unsigned int bits, const AnchorExactInteger *value);

void divide_take(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value);

void divide_settle(AnchorExactInteger *value, int sign);

void divide_magnitude(AnchorExactInteger *value, unsigned int bits, unsigned int pattern);

int divide_valid(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor,
                 const AnchorExactInteger *quotient, const AnchorExactInteger *remainder,
                 const AnchorExactInteger *common);

void divide_narrow(DivideResults *results);

#endif
