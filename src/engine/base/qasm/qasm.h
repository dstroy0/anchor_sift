// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QASM_H
#define QASM_H

#include "engine_config.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define QASM_REFUSED (-1L)

// Every amplitude is a pair of exact integers, re and im, in units of 2^-QASM_FRACTION_BITS. A rounded gate's
// entries lie within one unit of the true entry in each component, and one division by 2^QASM_FRACTION_BITS
// ends each lane's arithmetic.
#define QASM_FRACTION_BITS 60u

// The index names a record by a 32-bit number, and a sweep has one lane per amplitude.
#define QASM_QUBITS_MOST 30u

// the widest register or bit count a circuit declares in all
#define QASM_CLBITS_MOST 64u

// how many limbs one amplitude takes in the state: re and im, 64 bits each, two's complement
#define QASM_STATE_LIMBS 4u

// the bound E and the probabilities are held in units of 2^-(2 QASM_FRACTION_BITS), in this many 32-bit limbs
#define QASM_WIDE_LIMBS 8u

#define QASM_REASON_ROOM 512u

typedef enum
{
    QASM_GATE_PAIR = 1,     // a 2x2 matrix on the target, under its controls: rounded, one division per lane
    QASM_GATE_DIAGONAL = 2, // a diagonal phase: rounded, one division per lane
    QASM_GATE_PERMUTE = 3   // a permutation times a power of i: exact, no division
} QasmGateKind;

typedef enum
{
    QASM_DIAGONAL_BIT = 1,    // entry 0 or 1 by the target's bit
    QASM_DIAGONAL_PARITY = 2, // entry 0 or 1 by the parity of the target's and the second qubit's bits
} QasmDiagonalShape;

typedef enum
{
    QASM_PERMUTE_FLIP = 1,  // X: the target's bit flips
    QASM_PERMUTE_Y = 2,     // Y: the target's bit flips, then -i on a 0 and i on a 1
    QASM_PERMUTE_PHASE = 3, // Z, S, Sdg: i^phase where the target's bit is 1
    QASM_PERMUTE_SWAP = 4   // the target's and the second qubit's bits trade places
} QasmPermuteShape;

typedef struct
{
    unsigned int kind;
    unsigned int shape;
    unsigned int target;
    unsigned int second;
    unsigned long long controls;
    unsigned int control_count;
    // PAIR: m00 re, m00 im, m01 re, m01 im, m10 re, m10 im, m11 re, m11 im.
    // DIAGONAL: d0 re, d0 im, d1 re, d1 im. Units of 2^-QASM_FRACTION_BITS.
    long long entries[8];
    // the entries are the true entries exactly: the gate adds no entry error
    unsigned int exact_entries;
    // PERMUTE PHASE: the quarter turns i^phase
    unsigned int phase;
    unsigned int line;
    unsigned int column;
} QasmGate;

typedef struct
{
    unsigned int qubits;
    unsigned int clbits;
    QasmGate *gates;
    unsigned int gate_count;
    unsigned int gate_room;
    // for each qubit, the clbit it is measured into plus one, or 0 when it is not measured
    unsigned int measure[QASM_QUBITS_MOST];
    unsigned int measured;
    // no measure statement: every qubit is read into the clbit of its own number
    unsigned int measured_all_by_default;
    unsigned int rounded_gates;
    unsigned int exact_gates;
    // E, the proved bound on the 2-norm distance between the run's state and the true state, in units of
    // 2^-(2 QASM_FRACTION_BITS), rounded up: E_k = (1 + delta_k) E_(k-1) + local_k over the gates
    unsigned int bound[QASM_WIDE_LIMBS];
} QasmCircuit;

typedef struct
{
    const char *path;   // named in every refusal, and read when text is NULL
    const char *text;   // the program itself, or NULL to read path
    size_t length;
    char *reason;       // path:line:column: why, on a refusal
    size_t reason_room;
    EngineError *error;
} QasmReadRequest;

long qasm_read(const QasmReadRequest *request, QasmCircuit *circuit);

void qasm_release(QasmCircuit *circuit);

typedef struct
{
    // the outcome over the clbits, c[0] in bit 0
    unsigned long long peak;
    unsigned long long runner_up;
    // p' of each, in units of 2^-(2 QASM_FRACTION_BITS)
    unsigned int peak_units[QASM_WIDE_LIMBS];
    unsigned int runner_up_units[QASM_WIDE_LIMBS];
    // 2E + E^2 in the same units: every p' lies within it of the true p
    unsigned int slack_units[QASM_WIDE_LIMBS];
    // p'(peak) - p'(runner-up) exceeds twice the slack: the peak is the true peak
    unsigned int proved;
    unsigned int sweeps;
    unsigned long long lanes;
    unsigned long long microseconds;
} QasmOutcome;

typedef struct
{
    const QasmCircuit *circuit;
    int on_host;              // run the same programs through the exact integer library instead of the device
    unsigned int *state_out;  // optional: the final state, QASM_STATE_LIMBS limbs per amplitude
    EngineError *error;
} QasmRunRequest;

long qasm_run(const QasmRunRequest *request, QasmOutcome *outcome);

// the device bytes a run of this circuit holds at once
unsigned long long qasm_device_bytes(const QasmCircuit *circuit);

// the bitstring over the clbits in Qiskit's order, c[clbits - 1] first; room holds clbits + 1
void qasm_bitstring(const QasmCircuit *circuit, unsigned long long outcome, char *text, size_t room);

// units of 2^-(2 QASM_FRACTION_BITS) as a decimal with `places` digits after the point, truncated
void qasm_units_decimal(const unsigned int units[QASM_WIDE_LIMBS], unsigned int places, char *text, size_t room);

// the run as one tessera job on the current device; the request's bytes name it
typedef struct QasmJob QasmJob;

long qasm_job_submit(const unsigned char *request, unsigned long long bytes, unsigned long long declared,
                     QasmJob **job, EngineError *error);

long qasm_job_release(QasmJob *job, EngineError *error);

// The per-lane arithmetic the host port and the device share. Both sweep the same index.

#if defined(__CUDACC__)
#define QASM_BOTH __host__ __device__ static inline
#else
#define QASM_BOTH static inline
#endif

// members each gate kind's program reads
QASM_BOTH unsigned int qasm_gate_members(const QasmGate *gate)
{
    return (gate->kind == QASM_GATE_PAIR) ? 3u : 2u;
}

// lane i's records: which amplitude each state member reads, and which gate record
QASM_BOTH void qasm_lane_index(const QasmGate *gate, unsigned long long lane, unsigned int *index)
{
    const unsigned long long target = 1ull << gate->target;
    const unsigned int on = ((lane & gate->controls) == gate->controls) ? 1u : 0u;
    const unsigned int bit = ((lane & target) != 0ull) ? 1u : 0u;
    if (gate->kind == QASM_GATE_PAIR)
    {
        index[0] = (unsigned int)(lane & ~target);
        index[1] = (unsigned int)(lane | target);
        // rows 0 and 1 are the gate's, rows 2 and 3 the identity's
        index[2] = (on != 0u) ? bit : (2u + bit);
        return;
    }
    if (gate->kind == QASM_GATE_DIAGONAL)
    {
        const unsigned int second = (unsigned int)((lane >> gate->second) & 1ull);
        index[0] = (unsigned int)lane;
        // entries 0 and 1 are the gate's, entry 2 is 1
        index[1] = (on == 0u) ? 2u : ((gate->shape == QASM_DIAGONAL_PARITY) ? (bit ^ second) : bit);
        return;
    }
    unsigned long long source = lane;
    unsigned int phase = 0u;
    if ((on != 0u) && ((gate->shape == QASM_PERMUTE_FLIP) || (gate->shape == QASM_PERMUTE_Y)))
    {
        source = lane ^ target;
        // Y|0> = i|1> and Y|1> = -i|0>: the new amplitude at a 1 is i times the old at 0, at a 0 it is -i times
        phase = (gate->shape == QASM_PERMUTE_Y) ? ((bit != 0u) ? 1u : 3u) : 0u;
    }
    if ((on != 0u) && (gate->shape == QASM_PERMUTE_PHASE))
    {
        phase = (bit != 0u) ? gate->phase : 0u;
    }
    if ((on != 0u) && (gate->shape == QASM_PERMUTE_SWAP))
    {
        const unsigned long long other = 1ull << gate->second;
        const unsigned int other_bit = ((lane & other) != 0ull) ? 1u : 0u;
        source = (bit != other_bit) ? (lane ^ target ^ other) : lane;
    }
    index[0] = (unsigned int)source;
    index[1] = phase;
}

// One output of a record, `bits` wide at bit `offset`, as a 64-bit two's complement value. Returns 0 where the
// value does not fit 64 bits.
QASM_BOTH int qasm_output_read(const unsigned int *record, unsigned int offset, unsigned int bits, long long *value)
{
    unsigned long long low = 0ull;
    const unsigned int kept = (bits < 64u) ? bits : 64u;
    for (unsigned int at = 0u; at < kept; at += 1u)
    {
        const unsigned int place = offset + at;
        low |= (unsigned long long)((record[place >> 5u] >> (place & 31u)) & 1u) << at;
    }
    const unsigned int top = offset + bits - 1u;
    const unsigned int sign = (record[top >> 5u] >> (top & 31u)) & 1u;
    // every bit from 63 up to the top must repeat the sign
    for (unsigned int at = 63u; at < bits; at += 1u)
    {
        const unsigned int place = offset + at;
        if (((record[place >> 5u] >> (place & 31u)) & 1u) != sign)
        {
            return 0;
        }
    }
    if ((bits < 64u) && (sign != 0u))
    {
        low |= ~0ull << bits;
    }
    *value = (long long)low;
    return 1;
}

#ifdef __cplusplus
}
#endif

#endif
