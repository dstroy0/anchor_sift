// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_coherence_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_COHERENCE_TEST_INTERNAL_H
#define RECORD_COHERENCE_TEST_INTERNAL_H

//
// The record machine computes coherently with the 2-adic integers. A two's complement register sign-extended without
// end is a 2-adic integer, and ENGINE_RECORD_WRAP to w bits is the projection onto Z / 2^w. Sum, difference, product,
// xor and and commute with every projection: a program of them run exactly and then wrapped to w equals the same
// program run wrapped to w at every step. Random programs are run both ways at several widths in one record program,
// and both must equal a third reckoning in native 64-bit two's complement reduced to w, on every lane; the device must
// equal the host word for word. A quotient and a comparison read the whole integer, not only its low bits, and must
// break the agreement on some lane. An exact quotient by an odd c is the product by c^-1 in Z_2, and must equal that
// product in every projection. The odd crystals Z_3, Z_5 and Z_7 are orthogonal to Z_2: a ring program commutes with
// the remainder by p^v as it does with the wrap, the machine joins the two windows into the exact run modulo 2^w p^v,
// and an xor, the 2-adic crystal's alone, breaks modulo 3. A table step indexes by its source's magnitude and breaks
// under the wrap; indexed by the two's complement residue x mod 2^b, the and with 2^b - 1 before it, it factors
// through the wrap to every w >= b and breaks narrower. The test is one job on the device's tessera daemon, submitted
// before its first device work.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/types/integers/exact_integer.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define COHERENCE_TEST_LINE 8192ull

#define COHERENCE_TEST_STEPS 256u

#define COHERENCE_TEST_OUTPUTS 16u

#define COHERENCE_TEST_INPUTS 4u

#define COHERENCE_TEST_INPUT_BITS 24u

#define COHERENCE_TEST_OPERATIONS 10u

// a program keeps at most this many products. The exact widths stay well inside the file
#define COHERENCE_TEST_PRODUCTS_MAX 2u

#define COHERENCE_TEST_PROGRAMS 16u

#define COHERENCE_TEST_WIDTHS 6u

#define COHERENCE_TEST_LANES 4096u

// the most the test puts on the device at once: a program's atoms and records, under 32 words a lane
#define COHERENCE_TEST_DECLARED ((unsigned long long)COHERENCE_TEST_LANES * 32ull * sizeof(unsigned int))

static const unsigned int s_coherence_widths[COHERENCE_TEST_WIDTHS] = {5u, 8u, 13u, 16u, 31u, 32u};

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} CoherenceResults;

typedef struct
{
    EngineRecordStep steps[COHERENCE_TEST_STEPS];
    unsigned int count;
    unsigned int outputs[COHERENCE_TEST_OUTPUTS];
    unsigned int output_count;
    const EngineRecordTable *tables;
    unsigned int table_count;
} CoherenceProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} CoherenceLoaded;

// one operation of a random program: which, and the two earlier values it reads, as indices into the program's values
typedef struct
{
    EngineRecordOperation operation;
    unsigned int left;
    unsigned int right;
} CoherenceOperation;

unsigned int coherence_random(void);

void coherence_check(CoherenceResults *results, int passed, const char *what);

unsigned int coherence_append(CoherenceProgram *program, EngineRecordOperation operation, unsigned int left,
                              unsigned int right);

void coherence_output(CoherenceProgram *program, unsigned int step);

int coherence_load(const CoherenceProgram *program, unsigned int fields, CoherenceLoaded *loaded);

void coherence_free(CoherenceLoaded *loaded);

void coherence_run(CoherenceLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                   unsigned int *device_out, int *host_ran, int *device_ran);

long long coherence_take(const unsigned int *record, const DeviceRecordStep *step);

long long coherence_reduce(unsigned long long word, unsigned int bits);

void coherence_draw(CoherenceOperation *operations, int ring_only);

unsigned int coherence_input(unsigned int pattern);

long long coherence_signed_input(unsigned int raw);

void coherence_programs(CoherenceResults *results);

void coherence_broken(CoherenceResults *results);

void coherence_odd_divisors(CoherenceResults *results);

void coherence_orthogonal(CoherenceResults *results);

#define COHERENCE_TEST_TABLE_BITS 8u

#define COHERENCE_TEST_TABLE_OUT_BITS 16u

#define COHERENCE_TEST_TABLE_INPUTS 3u

unsigned long long coherence_magnitude(long long value);

#endif
