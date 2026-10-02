// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_self_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_SELF_INTERNAL_H
#define QASM_SELF_INTERNAL_H

#include "../../../c/transpiler/qasm/qasm.h"

#include "../../../c/engine/analysis/cycle/cycle.h"
#include "../../../c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../c/engine/analysis/keymath/keymath.h"

#include <cuda_runtime.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// The self run. A circuit becomes one program for the record machine: every gate is a floor of exact integer steps
// reading the floor below it, and with register reuse each lane runs the whole stack in one launch from its own input
// state. A lane's state is every amplitude's four integer parts, the rational and sqrt2 parts of its real half and then
// of its imaginary half, over one denominator the host keeps. A gate is the integer linear map its matrix makes over
// the least common denominator of its entries. Its columns are the dense port's own action on each basis state. The
// lanes apply exactly the gates the port applies. No step divides and nothing rounds.

// __LINE__ is a positive int, which the unsigned site holds unchanged
#define QASM_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_) ? 1 : 0, (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__,                      \
                       (const void *)(evacaddr_), (error_))

// a CUDA status is a small enumerator, which an int holds unchanged
#define QASM_STATUS_CHECK(call_, evacaddr_, error_)                                                                    \
    engine_status_check((int)(call_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

// an exact integer's status: anything but OK is a value the width does not hold
#define QASM_FITS(status_, evacaddr_, error_)                                                                          \
    QASM_CHECK((status_) == ANCHOR_EXACT_OK, (evacaddr_), (error_), ENGINE_ERROR_RESOURCE)

// an amplitude's integer parts: the real half's rational and sqrt2 parts, then the imaginary half's
#define QASM_SELF_PARTS 4u

// the distinct constants one floor keeps for reuse; a floor needing more builds the rest again
#define QASM_SELF_CONSTANTS_MAX 64u

// the most lanes one run takes: every count of numbers and limbs over them then stays within an unsigned long long
#define QASM_SELF_LANES_MAX (1ull << 32u)

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

static_assert((QASM_SELF_PARTS << QASM_SELF_QUBITS_MAX) <= ENGINE_RECORD_LIMBS_MAX,
              "qasm: the self run's widest state must fit the record machine's register file");

// an input field is at most one bit past the exact integer's width. The widest record's bits fit an unsigned int
static_assert(((((unsigned long long)QASM_SELF_PARTS << QASM_SELF_QUBITS_MAX) *
                ((unsigned long long)ANCHOR_EXACT_BITS + 1ull)) +
               31ull) <= 0xFFFFFFFFull,
              "qasm: the self run's widest input record must be counted in an unsigned int");

static const AnchorExactInteger qasm_self_one = {{1u}, 1};

const QasmRational *qasm_self_part(const QasmNumber *value, unsigned int part);

QasmRational *qasm_self_part_slot(QasmNumber *value, unsigned int part);

typedef struct
{
    EngineRecordStep *steps;
    unsigned int count;
    unsigned int capacity;
    // the list could not grow, and every later step errors with it
    int spent;
} QasmSelfSteps;

unsigned int qasm_self_step(QasmSelfSteps *list, EngineRecordOperation operation, unsigned int left, unsigned int right,
                            unsigned int member);

typedef struct
{
    QasmSelfSteps list;
    // the step holding 0, which a part no term reaches takes
    unsigned int zero;
    unsigned int amplitudes;
    // the registers of the floor below and of the floor being built, QASM_SELF_PARTS to an amplitude
    unsigned int *below;
    unsigned int *built;
    // the floor's constants: each magnitude and the step holding it
    AnchorExactInteger constant_value[QASM_SELF_CONSTANTS_MAX];
    unsigned int constant_step[QASM_SELF_CONSTANTS_MAX];
    unsigned int constant_count;
    // a gate's columns, column s from [s amplitudes], and each entry's parts over the gate's denominator
    QasmNumber *columns;
    AnchorExactInteger *numerators;
    // the state's denominator: the inputs', times every gate's
    AnchorExactInteger denominator;
    // a coefficient doubled past the width
    int over_width;
    EngineError *error;
} QasmSelfBuild;

int qasm_self_lcm(AnchorExactInteger *common, const AnchorExactInteger *denominator, EngineError *error);

int qasm_self_over(const QasmRational *value, const AnchorExactInteger *common, AnchorExactInteger *numerator,
                   EngineError *error);

int qasm_self_floor(QasmSelfBuild *build, unsigned int qubits, const QasmExactGate *gate);

unsigned int qasm_self_bits(const AnchorExactInteger *value);

void qasm_self_put(unsigned int *record, unsigned int offset, unsigned int bits, const AnchorExactInteger *value);

// the program laid out on the host: its encoding and its layout, with each output's step
typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    unsigned int *outputs;
    unsigned int layout_built;
} QasmSelfProgram;

#endif
