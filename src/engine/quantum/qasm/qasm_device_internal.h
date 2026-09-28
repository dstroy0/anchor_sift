// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the qasm_device_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef QASM_DEVICE_INTERNAL_H
#define QASM_DEVICE_INTERNAL_H

#include "qasm.h"

#include "cycle.h"
#include "exact_integer.h"
#include "key_schedule.h"
#include "keymath.h"
#include "obsignatio.h"
#include "tessera.h"

#include <cuda_runtime.h>

#include <chrono>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <unistd.h>
#endif

// A circuit runs as one sweep of the record machine per gate. Each amplitude is a lane; its program reads the
// amplitudes the gate mixes into it through the index, and one gate record (a row of the matrix, a diagonal entry,
// or a power of i) chosen by the same index. The outputs are narrowed back into the canonical state after each
// sweep. Every program reads one fixed layout.

#define QASM_CHECK(condition_, evacaddr_, error_, kind_)                                                               \
    engine_error_check((condition_) ? 1 : 0, (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__,                      \
                       (const void *)(evacaddr_), (error_))

#define QASM_STATUS_CHECK(call_, evacaddr_, error_)                                                                    \
    engine_status_check((int)(call_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define QASM_BLOCK 256u
#define QASM_BLOCKS_MAX 65535u

// the lanes of probabilities copied to the host at once
#define QASM_CHUNK_LANES (1ull << 20u)

// a state field: 62 bits of two's complement, the low bits of each 64-bit half of an amplitude
#define QASM_FIELD_BITS 62u

#define QASM_JOB_RUNNING_MICROSECONDS 2000000ull
#define QASM_JOB_SWEEP_MICROSECONDS 20000ull
#define QASM_JOB_IDLE_MICROSECONDS 5000000ull

enum
{
    QASM_PROGRAM_PAIR = 0,
    QASM_PROGRAM_DIAGONAL = 1,
    QASM_PROGRAM_PERMUTE = 2,
    QASM_PROGRAM_PROBABILITY = 3,
    QASM_PROGRAMS = 4
};

// the gate records: a pair's rows (the gate's two, then the identity's), a diagonal's entries (the gate's two, then
// 1), and the four powers of i
#define QASM_PAIR_ROWS 4u
#define QASM_PAIR_ROW_LIMBS 8u
#define QASM_DIAGONAL_ENTRIES 3u
#define QASM_DIAGONAL_ENTRY_LIMBS 4u
#define QASM_PHASES 4u
#define QASM_PHASE_LIMBS 2u

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    unsigned int outputs;
    unsigned int out_offset[2];
    unsigned int out_bits[2];
    unsigned int layout_built;
} QasmProgram;

struct QasmJob
{
    TesseraClient *client;
    unsigned long long declared;
};

void qasm_program_release(QasmProgram *program);

int qasm_program_load(QasmProgram *program, unsigned int which, int on_host, EngineError *error);

// ---------------------------------------------------------------------------------------------------------------
// per-lane work, one body for the host and the device

// the value fits a state field: 62 bits of two's complement
QASM_BOTH int qasm_field_fits(long long value)
{
    return (value >= -(1ll << (QASM_FIELD_BITS - 1u))) && (value < (1ll << (QASM_FIELD_BITS - 1u)));
}

// a lane's two outputs narrowed into its canonical amplitude; 0 where either does not fit
QASM_BOTH int qasm_repack_lane(const unsigned int *out, unsigned int out_limbs, unsigned int offset0,
                               unsigned int bits0, unsigned int offset1, unsigned int bits1, unsigned long long lane,
                               long long *state)
{
    const unsigned int *const record = &out[lane * out_limbs];
    long long re = 0;
    long long im = 0;
    const int fits = qasm_output_read(record, offset0, bits0, &re) && qasm_output_read(record, offset1, bits1, &im) &&
                     qasm_field_fits(re) && qasm_field_fits(im);
    state[2ull * lane] = (fits != 0) ? re : 0;
    state[(2ull * lane) + 1ull] = (fits != 0) ? im : 0;
    return fits;
}

__global__ void qasm_index_kernel(QasmGate gate, unsigned long long count, unsigned int members, unsigned int *index);

__global__ void qasm_repack_kernel(const unsigned int *out, unsigned int out_limbs, unsigned int offset0,
                                   unsigned int bits0, unsigned int offset1, unsigned int bits1,
                                   unsigned long long count, long long *state, unsigned int *overflow);

unsigned int qasm_blocks(unsigned long long count);

void qasm_gate_records(const QasmGate *gate, unsigned int *records);

unsigned long long qasm_gate_bodies(const QasmGate *gate);

// ---------------------------------------------------------------------------------------------------------------
// the probabilities and their top two

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} QasmWide;

typedef struct
{
    QasmWide best;
    QasmWide second;
    unsigned long long best_key;
    unsigned long long second_key;
    unsigned int seen;
} QasmTopTwo;

void qasm_top_two(QasmTopTwo *top, const QasmWide *value, unsigned long long key);

typedef struct
{
    const QasmCircuit *circuit;
    // every qubit measured: each lane is its own outcome; otherwise bins over the measured qubits' bits
    int full;
    unsigned int measured_qubit[QASM_QUBITS_MAX];
    unsigned int measured_count;
    QasmWide *bins;
    QasmTopTwo top;
} QasmResults;

void qasm_results_lanes(QasmResults *results, const unsigned int *records, unsigned int limbs, unsigned int bits,
                        unsigned long long first, unsigned long long count);

void qasm_outcome_close(const QasmResults *results, QasmOutcome *outcome);

typedef struct
{
    int on_host;
    unsigned long long lanes;
    unsigned int *state;
    unsigned int *out;
    unsigned int *index;
    unsigned int *pair_rows;
    unsigned int *diagonal_entries;
    unsigned int *phases;
    unsigned int *overflow;
} QasmSpace;

void qasm_space_release(QasmSpace *space);

int qasm_space_reserve(QasmSpace *space, const QasmCircuit *circuit, int on_host, EngineError *error);

#endif
