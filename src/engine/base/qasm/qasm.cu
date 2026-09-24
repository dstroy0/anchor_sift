// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
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
// sweep, so every program reads one fixed layout.

#define QASM_HELD(held_, evacaddr_, error_, kind_)                                                                     \
    engine_error_check((held_) ? 1 : 0, (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__,                           \
                       (const void *)(evacaddr_), (error_))

#define QASM_TOOK(call_, evacaddr_, error_)                                                                            \
    engine_status_check((int)(call_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define QASM_BLOCK 256u
#define QASM_BLOCKS_MOST 65535u

// the lanes of probabilities copied to the host at once
#define QASM_CHUNK_LANES (1ull << 20u)

// a state field: 62 bits of two's complement, the low bits of each 64-bit half of an amplitude
#define QASM_FIELD_BITS 62u

#define QASM_JOB_HOLDING_MICROSECONDS 2000000ull
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
    unsigned int laid;
} QasmProgram;

struct QasmJob
{
    TesseraClient *client;
    unsigned long long declared;
};

static void qasm_step(EngineRecordStep *steps, unsigned int *count, EngineRecordOperation operation, unsigned int left,
                      unsigned int right, unsigned int member)
{
    steps[*count].operation = operation;
    steps[*count].left = left;
    steps[*count].right = right;
    steps[*count].member = member;
    *count += 1u;
}

static void qasm_program_release(QasmProgram *program)
{
    if (program->record != NULL)
    {
        cycle_record_release(program->record);
        program->record = NULL;
    }
    if (program->laid != 0u)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        program->laid = 0u;
    }
}

// 2^QASM_FRACTION_BITS as a CONSTANT step: left + 2^32 right
static void qasm_step_scale(EngineRecordStep *steps, unsigned int *count)
{
    qasm_step(steps, count, ENGINE_RECORD_CONSTANT, 0u, 1u << (QASM_FRACTION_BITS - 32u), 0u);
}

static int qasm_program_load(QasmProgram *program, unsigned int which, int on_host, EngineError *error)
{
    memset(program, 0, sizeof(*program));
    EngineRecordStep steps[32];
    unsigned int count = 0u;
    unsigned int field_bits[6] = {QASM_FIELD_BITS, QASM_FIELD_BITS, QASM_FIELD_BITS,
                                  QASM_FIELD_BITS, QASM_FIELD_BITS, QASM_FIELD_BITS};
    unsigned int field_offset[6] = {0u, 64u, 0u, 64u, 128u, 192u};
    unsigned int fields = 2u;
    unsigned int members = 1u;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {QASM_STATE_LIMBS, 0u, 0u};
    unsigned int outputs[2] = {0u, 0u};
    unsigned int output_count = 2u;
    if (which == QASM_PROGRAM_PAIR)
    {
        // members: the amplitude with the target's bit clear (a), the one with it set (b), and the row (u, v)
        fields = 6u;
        members = 3u;
        in_limbs[1] = QASM_STATE_LIMBS;
        in_limbs[2] = QASM_PAIR_ROW_LIMBS;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);  // 0 a re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);  // 1 a im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 1u);  // 2 b re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 1u);  // 3 b im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u, 2u);  // 4 u re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 3u, 0u, 2u);  // 5 u im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 4u, 0u, 2u);  // 6 v re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 5u, 0u, 2u);  // 7 v im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 0u, 0u);       // 8 u re a re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 5u, 1u, 0u);       // 9 u im a im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 6u, 2u, 0u);       // 10 v re b re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 7u, 3u, 0u);       // 11 v im b im
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 8u, 9u, 0u);    // 12 re(u a)
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 10u, 11u, 0u);  // 13 re(v b)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 12u, 13u, 0u);         // 14 re(u a + v b)
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 1u, 0u);       // 15 u re a im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 5u, 0u, 0u);       // 16 u im a re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 6u, 3u, 0u);       // 17 v re b im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 7u, 2u, 0u);       // 18 v im b re
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 15u, 16u, 0u);         // 19 im(u a)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 17u, 18u, 0u);         // 20 im(v b)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 19u, 20u, 0u);         // 21 im(u a + v b)
        qasm_step_scale(steps, &count);                                     // 22 2^F
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 14u, 22u, 0u);    // 23 re, toward zero
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 21u, 22u, 0u);    // 24 im, toward zero
        outputs[0] = 23u;
        outputs[1] = 24u;
    }
    else if (which == QASM_PROGRAM_DIAGONAL)
    {
        // members: the amplitude, and the entry d, which shares the amplitude's layout
        members = 2u;
        in_limbs[1] = QASM_DIAGONAL_ENTRY_LIMBS;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);  // 0 s re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);  // 1 s im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 1u);  // 2 d re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 1u);  // 3 d im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 0u, 0u);       // 4
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 1u, 0u);       // 5
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 4u, 5u, 0u);    // 6 re(d s)
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 1u, 0u);       // 7
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 0u, 0u);       // 8
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);           // 9 im(d s)
        qasm_step_scale(steps, &count);                                     // 10 2^F
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 6u, 10u, 0u);     // 11
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 9u, 10u, 0u);     // 12
        outputs[0] = 11u;
        outputs[1] = 12u;
    }
    else if (which == QASM_PROGRAM_PERMUTE)
    {
        // members: the amplitude moved here, and i^q as (c, s) = (cos, sin) of q quarter turns, two bits each
        fields = 4u;
        members = 2u;
        in_limbs[1] = QASM_PHASE_LIMBS;
        field_bits[2] = 2u;
        field_bits[3] = 2u;
        field_offset[2] = 0u;
        field_offset[3] = 32u;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);  // 0 s re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);  // 1 s im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u, 1u);  // 2 c
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 3u, 0u, 1u);  // 3 s
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 0u, 0u);       // 4
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 1u, 0u);       // 5
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 4u, 5u, 0u);    // 6 re, exact
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 1u, 0u);       // 7
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 0u, 0u);       // 8
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);           // 9 im, exact
        outputs[0] = 6u;
        outputs[1] = 9u;
    }
    else
    {
        // |amplitude|^2 in units of 2^-2F, exact
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);  // 0 re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);  // 1 im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 0u, 0u, 0u);       // 2
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 1u, 1u, 0u);       // 3
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 2u, 3u, 0u);           // 4
        outputs[0] = 4u;
        output_count = 1u;
    }
    const KeymathRecordRequest imprint = {steps, count, field_bits, fields, members, outputs, output_count, NULL, 0u,
                                          &program->key, error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        engine_error_frame(error);
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&program->key, field_offset, fields, in_limbs, 1, &program->layout, error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&program->key);
        engine_error_frame(error);
        return 0;
    }
    program->laid = 1u;
    program->outputs = output_count;
    for (unsigned int output = 0u; output < output_count; output += 1u)
    {
        program->out_offset[output] = program->layout.step_table[outputs[output]].out_offset;
        program->out_bits[output] = program->layout.step_table[outputs[output]].out_bits;
    }
    if (!QASM_HELD(program->layout.out_limbs <= QASM_WIDE_LIMBS, &program->layout, error, ENGINE_ERROR_LOGIC))
    {
        qasm_program_release(program);
        return 0;
    }
    if ((on_host == 0) && (cycle_record_load(&program->layout, &program->record, error) == CYCLE_REFUSED))
    {
        qasm_program_release(program);
        engine_error_frame(error);
        return 0;
    }
    return 1;
}

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
    const int fits = qasm_output_read(record, offset0, bits0, &re) && qasm_output_read(record, offset1, bits1, &im)
                  && qasm_field_fits(re) && qasm_field_fits(im);
    state[2ull * lane] = (fits != 0) ? re : 0;
    state[(2ull * lane) + 1ull] = (fits != 0) ? im : 0;
    return fits;
}

#define QASM_EACH(at_, count_)                                                                                         \
    for (unsigned long long at_ = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; at_ < (count_);          \
         at_ += (unsigned long long)gridDim.x * blockDim.x)

__global__ static void qasm_index_kernel(QasmGate gate, unsigned long long count, unsigned int members,
                                         unsigned int *index)
{
    QASM_EACH(lane, count)
    {
        qasm_lane_index(&gate, lane, &index[lane * members]);
    }
}

__global__ static void qasm_repack_kernel(const unsigned int *out, unsigned int out_limbs, unsigned int offset0,
                                          unsigned int bits0, unsigned int offset1, unsigned int bits1,
                                          unsigned long long count, long long *state, unsigned int *overflow)
{
    QASM_EACH(lane, count)
    {
        if (qasm_repack_lane(out, out_limbs, offset0, bits0, offset1, bits1, lane, state) == 0)
        {
            atomicOr(overflow, 1u);
        }
    }
}

static unsigned int qasm_blocks(unsigned long long count)
{
    const unsigned long long needed = (count + QASM_BLOCK - 1ull) / QASM_BLOCK;
    return (unsigned int)((needed < QASM_BLOCKS_MOST) ? needed : QASM_BLOCKS_MOST);
}

// ---------------------------------------------------------------------------------------------------------------
// gate records

static void qasm_put_word(unsigned int *limbs, long long value)
{
    limbs[0] = (unsigned int)((unsigned long long)value & 0xFFFFFFFFull);
    limbs[1] = (unsigned int)((unsigned long long)value >> 32u);
}

static void qasm_gate_records(const QasmGate *gate, unsigned int *records)
{
    const long long one = 1ll << QASM_FRACTION_BITS;
    if (gate->kind == QASM_GATE_PAIR)
    {
        // row r is (u, v) = (m_r0, m_r1); rows 2 and 3 are the identity's
        // each row is u re, u im, v re, v im
        const long long rows[QASM_PAIR_ROWS][4] = {
            {gate->entries[0], gate->entries[1], gate->entries[2], gate->entries[3]},
            {gate->entries[4], gate->entries[5], gate->entries[6], gate->entries[7]},
            {one, 0, 0, 0},
            {0, 0, one, 0}};
        for (unsigned int row = 0u; row < QASM_PAIR_ROWS; row += 1u)
        {
            for (unsigned int word = 0u; word < 4u; word += 1u)
            {
                qasm_put_word(&records[(row * QASM_PAIR_ROW_LIMBS) + (2u * word)], rows[row][word]);
            }
        }
        return;
    }
    if (gate->kind == QASM_GATE_DIAGONAL)
    {
        const long long entries[QASM_DIAGONAL_ENTRIES][2] = {
            {gate->entries[0], gate->entries[1]}, {gate->entries[2], gate->entries[3]}, {one, 0}};
        for (unsigned int entry = 0u; entry < QASM_DIAGONAL_ENTRIES; entry += 1u)
        {
            qasm_put_word(&records[entry * QASM_DIAGONAL_ENTRY_LIMBS], entries[entry][0]);
            qasm_put_word(&records[(entry * QASM_DIAGONAL_ENTRY_LIMBS) + 2u], entries[entry][1]);
        }
        return;
    }
    // i^q as (c, s) in two bits of two's complement: 1 = 01, -1 = 11
    const unsigned int phases[QASM_PHASES][QASM_PHASE_LIMBS] = {{1u, 0u}, {0u, 1u}, {3u, 0u}, {0u, 3u}};
    memcpy(records, phases, sizeof(phases));
}

static unsigned long long qasm_gate_bodies(const QasmGate *gate)
{
    return (gate->kind == QASM_GATE_PAIR) ? QASM_PAIR_ROWS
         : ((gate->kind == QASM_GATE_DIAGONAL) ? QASM_DIAGONAL_ENTRIES : QASM_PHASES);
}

// ---------------------------------------------------------------------------------------------------------------
// the probabilities and their top two

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} QasmWide;

static void qasm_wide_add(QasmWide *sum, const QasmWide *value)
{
    const unsigned long long low = sum->low + value->low;
    sum->high += value->high + ((low < sum->low) ? 1ull : 0ull);
    sum->low = low;
}

static int qasm_wide_greater(const QasmWide *left, const QasmWide *right)
{
    return (left->high > right->high) || ((left->high == right->high) && (left->low > right->low));
}

static void qasm_wide_units(const QasmWide *value, unsigned int units[QASM_WIDE_LIMBS])
{
    memset(units, 0, QASM_WIDE_LIMBS * sizeof(unsigned int));
    units[0] = (unsigned int)(value->low & 0xFFFFFFFFull);
    units[1] = (unsigned int)(value->low >> 32u);
    units[2] = (unsigned int)(value->high & 0xFFFFFFFFull);
    units[3] = (unsigned int)(value->high >> 32u);
}

// the probability output, read from its limbs: never negative, below 2^126
static QasmWide qasm_probability(const unsigned int *record, unsigned int bits)
{
    QasmWide value;
    value.low = (unsigned long long)record[0] | ((unsigned long long)record[1] << 32u);
    value.high = (unsigned long long)record[2] | ((unsigned long long)record[3] << 32u);
    if (bits < 128u)
    {
        value.high &= (1ull << (bits - 64u)) - 1ull;
    }
    return value;
}

typedef struct
{
    QasmWide best;
    QasmWide second;
    unsigned long long best_key;
    unsigned long long second_key;
    unsigned int seen;
} QasmTopTwo;

static void qasm_top_two(QasmTopTwo *top, const QasmWide *value, unsigned long long key)
{
    if ((top->seen == 0u) || qasm_wide_greater(value, &top->best))
    {
        top->second = top->best;
        top->second_key = top->best_key;
        top->best = *value;
        top->best_key = key;
        top->seen += 1u;
        return;
    }
    if ((top->seen == 1u) || qasm_wide_greater(value, &top->second))
    {
        top->second = *value;
        top->second_key = key;
        top->seen += 1u;
    }
}

typedef struct
{
    const QasmCircuit *circuit;
    // every qubit measured: each lane is its own outcome; otherwise bins over the measured qubits' bits
    int full;
    unsigned int measured_qubit[QASM_QUBITS_MOST];
    unsigned int measured_count;
    QasmWide *bins;
    QasmTopTwo top;
} QasmTally;

static unsigned long long qasm_lane_bin(const QasmTally *tally, unsigned long long lane)
{
    unsigned long long bin = 0ull;
    for (unsigned int at = 0u; at < tally->measured_count; at += 1u)
    {
        bin |= ((lane >> tally->measured_qubit[at]) & 1ull) << at;
    }
    return bin;
}

static unsigned long long qasm_bin_outcome(const QasmTally *tally, unsigned long long bin)
{
    unsigned long long outcome = 0ull;
    for (unsigned int at = 0u; at < tally->measured_count; at += 1u)
    {
        const unsigned int clbit = tally->circuit->measure[tally->measured_qubit[at]] - 1u;
        outcome |= ((bin >> at) & 1ull) << clbit;
    }
    return outcome;
}

static void qasm_tally_lanes(QasmTally *tally, const unsigned int *records, unsigned int limbs, unsigned int bits,
                             unsigned long long first, unsigned long long count)
{
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        const QasmWide value = qasm_probability(&records[at * limbs], bits);
        const unsigned long long lane = first + at;
        if (tally->full != 0)
        {
            qasm_top_two(&tally->top, &value, lane);
        }
        else
        {
            qasm_wide_add(&tally->bins[qasm_lane_bin(tally, lane)], &value);
        }
    }
}

// the slack 2E + E^2 and whether the peak is proved
static void qasm_outcome_close(const QasmTally *tally, QasmOutcome *outcome)
{
    const QasmCircuit *const circuit = tally->circuit;
    outcome->peak = qasm_bin_outcome(tally, tally->full ? qasm_lane_bin(tally, tally->top.best_key) : tally->top.best_key);
    outcome->runner_up =
        qasm_bin_outcome(tally, tally->full ? qasm_lane_bin(tally, tally->top.second_key) : tally->top.second_key);
    qasm_wide_units(&tally->top.best, outcome->peak_units);
    qasm_wide_units(&tally->top.second, outcome->runner_up_units);
    AnchorExactInteger bound;
    AnchorExactInteger square;
    AnchorExactInteger scale;
    AnchorExactInteger rest;
    AnchorExactInteger slack;
    AnchorExactInteger one;
    anchor_exact_zero(&bound);
    anchor_exact_zero(&scale);
    anchor_exact_zero(&one);
    int any = 0;
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        bound.limb[limb] = circuit->bound[limb];
        any |= (circuit->bound[limb] != 0u);
    }
    bound.sign = any ? 1 : 0;
    scale.limb[(2u * QASM_FRACTION_BITS) / 32u] = 1u << ((2u * QASM_FRACTION_BITS) % 32u);
    scale.sign = 1;
    one.limb[0] = 1u;
    one.sign = 1;
    // E^2 / 2^2F rounded up, then 2E added
    anchor_exact_multiply(&bound, &bound, &square);
    anchor_exact_divide(&square, &scale, &slack, &rest);
    if (rest.sign != 0)
    {
        anchor_exact_add(&slack, &one, &slack);
    }
    anchor_exact_add(&slack, &bound, &slack);
    anchor_exact_add(&slack, &bound, &slack);
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        outcome->slack_units[limb] = slack.limb[limb];
    }
    // proved when p'(peak) - p'(runner-up) > 2 slack
    AnchorExactInteger best;
    AnchorExactInteger second;
    AnchorExactInteger gap;
    AnchorExactInteger twice;
    anchor_exact_zero(&best);
    anchor_exact_zero(&second);
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        best.limb[limb] = outcome->peak_units[limb];
        second.limb[limb] = outcome->runner_up_units[limb];
    }
    best.sign = ((tally->top.best.low | tally->top.best.high) != 0ull) ? 1 : 0;
    second.sign = ((tally->top.second.low | tally->top.second.high) != 0ull) ? 1 : 0;
    anchor_exact_subtract(&best, &second, &gap);
    anchor_exact_add(&slack, &slack, &twice);
    outcome->proved = (anchor_exact_compare(&gap, &twice) > 0) ? 1u : 0u;
}

// ---------------------------------------------------------------------------------------------------------------
// the run

unsigned long long qasm_device_bytes(const QasmCircuit *circuit)
{
    if ((circuit == NULL) || (circuit->qubits == 0u) || (circuit->qubits > QASM_QUBITS_MOST))
    {
        return 0ull;
    }
    const unsigned long long lanes = 1ull << circuit->qubits;
    // the state, the widest program's outputs, the widest index, and the gate records
    const unsigned long long per_lane = (QASM_STATE_LIMBS + QASM_WIDE_LIMBS + ENGINE_RECORD_MEMBERS_MAX)
                                      * sizeof(unsigned int);
    const unsigned long long records = (QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS) + (QASM_DIAGONAL_ENTRIES * QASM_DIAGONAL_ENTRY_LIMBS)
                                     + (QASM_PHASES * QASM_PHASE_LIMBS);
    return (lanes * per_lane) + (records * sizeof(unsigned int)) + sizeof(unsigned int);
}

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

static void qasm_space_release(QasmSpace *space)
{
    if (space->lanes == 0ull)
    {
        return;
    }
    if (space->on_host != 0)
    {
        free(space->state);
        free(space->out);
        free(space->index);
        free(space->pair_rows);
        free(space->diagonal_entries);
        free(space->phases);
        free(space->overflow);
    }
    else
    {
        cudaFree(space->state);
        cudaFree(space->out);
        cudaFree(space->index);
        cudaFree(space->pair_rows);
        cudaFree(space->diagonal_entries);
        cudaFree(space->phases);
        cudaFree(space->overflow);
    }
    memset(space, 0, sizeof(*space));
}

static int qasm_space_hold(QasmSpace *space, const QasmCircuit *circuit, int on_host, EngineError *error)
{
    memset(space, 0, sizeof(*space));
    space->on_host = on_host;
    space->lanes = 1ull << circuit->qubits;
    const size_t sizes[7] = {(size_t)(space->lanes * QASM_STATE_LIMBS * sizeof(unsigned int)),
                             (size_t)(space->lanes * QASM_WIDE_LIMBS * sizeof(unsigned int)),
                             (size_t)(space->lanes * ENGINE_RECORD_MEMBERS_MAX * sizeof(unsigned int)),
                             QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS * sizeof(unsigned int),
                             QASM_DIAGONAL_ENTRIES * QASM_DIAGONAL_ENTRY_LIMBS * sizeof(unsigned int),
                             QASM_PHASES * QASM_PHASE_LIMBS * sizeof(unsigned int),
                             sizeof(unsigned int)};
    unsigned int **const held[7] = {&space->state, &space->out, &space->index, &space->pair_rows,
                                    &space->diagonal_entries, &space->phases, &space->overflow};
    if (on_host == 0)
    {
        size_t free_bytes = 0u;
        size_t total_bytes = 0u;
        if (!QASM_TOOK(cudaMemGetInfo(&free_bytes, &total_bytes), space, error)
         || !QASM_HELD(qasm_device_bytes(circuit) <= (unsigned long long)free_bytes, space, error,
                       ENGINE_ERROR_RESOURCE))
        {
            return 0;
        }
    }
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        if (on_host != 0)
        {
            *held[at] = (unsigned int *)calloc(1u, sizes[at]);
            if (!QASM_HELD(*held[at] != NULL, held[at], error, ENGINE_ERROR_RESOURCE))
            {
                qasm_space_release(space);
                return 0;
            }
        }
        else if (!QASM_TOOK(cudaMalloc((void **)held[at], sizes[at]), held[at], error)
              || !QASM_TOOK(cudaMemset(*held[at], 0, sizes[at]), held[at], error))
        {
            qasm_space_release(space);
            return 0;
        }
    }
    // |0...0>: amplitude 1 at lane 0
    const long long one[2] = {1ll << QASM_FRACTION_BITS, 0};
    unsigned int phases[QASM_PHASES * QASM_PHASE_LIMBS];
    QasmGate permute;
    memset(&permute, 0, sizeof(permute));
    permute.kind = QASM_GATE_PERMUTE;
    qasm_gate_records(&permute, phases);
    if (on_host != 0)
    {
        memcpy(space->state, one, sizeof(one));
        memcpy(space->phases, phases, sizeof(phases));
        return 1;
    }
    if (!QASM_TOOK(cudaMemcpy(space->state, one, sizeof(one), cudaMemcpyHostToDevice), space->state, error)
     || !QASM_TOOK(cudaMemcpy(space->phases, phases, sizeof(phases), cudaMemcpyHostToDevice), space->phases, error))
    {
        qasm_space_release(space);
        return 0;
    }
    return 1;
}

// one gate: its index, its program's sweep, and the outputs narrowed back into the state
static int qasm_sweep(QasmSpace *space, const QasmProgram *programs, const QasmGate *gate, EngineError *error)
{
    const QasmProgram *const program = &programs[gate->kind - 1u];
    const unsigned int members = qasm_gate_members(gate);
    unsigned int records[QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS];
    unsigned int *const gate_records = (gate->kind == QASM_GATE_PAIR)       ? space->pair_rows
                                     : ((gate->kind == QASM_GATE_DIAGONAL) ? space->diagonal_entries : space->phases);
    const size_t record_bytes = (gate->kind == QASM_GATE_PAIR) ? (QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS * sizeof(unsigned int))
                              : (QASM_DIAGONAL_ENTRIES * QASM_DIAGONAL_ENTRY_LIMBS * sizeof(unsigned int));
    const unsigned long long lanes = space->lanes;
    const unsigned int out_limbs = program->layout.out_limbs;
    if (space->on_host != 0)
    {
        if (gate->kind != QASM_GATE_PERMUTE)
        {
            qasm_gate_records(gate, records);
            memcpy(gate_records, records, record_bytes);
        }
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            qasm_lane_index(gate, lane, &space->index[lane * members]);
        }
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program->layout;
        run.in[0] = space->state;
        run.bodies[0] = lanes;
        run.in[members - 1u] = gate_records;
        run.bodies[members - 1u] = qasm_gate_bodies(gate);
        if (members == 3u)
        {
            run.in[1] = space->state;
            run.bodies[1] = lanes;
        }
        run.index = space->index;
        run.count = lanes;
        run.out = space->out;
        if (!QASM_HELD(cycle_record_run_host(&run) != CYCLE_REFUSED, gate, error, ENGINE_ERROR_LOGIC))
        {
            return 0;
        }
        int fits = 1;
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            fits &= qasm_repack_lane(space->out, out_limbs, program->out_offset[0], program->out_bits[0],
                                     program->out_offset[1], program->out_bits[1], lane, (long long *)space->state);
        }
        return QASM_HELD(fits != 0, gate, error, ENGINE_ERROR_LOGIC);
    }
    if (gate->kind != QASM_GATE_PERMUTE)
    {
        qasm_gate_records(gate, records);
        if (!QASM_TOOK(cudaMemcpy(gate_records, records, record_bytes, cudaMemcpyHostToDevice), gate_records, error))
        {
            return 0;
        }
    }
    qasm_index_kernel<<<qasm_blocks(lanes), QASM_BLOCK>>>(*gate, lanes, members, space->index);
    if (!QASM_TOOK(cudaGetLastError(), space->index, error))
    {
        return 0;
    }
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.record = program->record;
    run.device_in[0] = space->state;
    run.bodies[0] = lanes;
    run.device_in[members - 1u] = gate_records;
    run.bodies[members - 1u] = qasm_gate_bodies(gate);
    if (members == 3u)
    {
        run.device_in[1] = space->state;
        run.bodies[1] = lanes;
    }
    run.device_index = space->index;
    run.count = lanes;
    run.device_out = space->out;
    run.error = error;
    if (cycle_record_run(&run) == CYCLE_REFUSED)
    {
        engine_error_frame(error);
        return 0;
    }
    qasm_repack_kernel<<<qasm_blocks(lanes), QASM_BLOCK>>>(space->out, out_limbs, program->out_offset[0],
                                                           program->out_bits[0], program->out_offset[1],
                                                           program->out_bits[1], lanes, (long long *)space->state,
                                                           space->overflow);
    return QASM_TOOK(cudaGetLastError(), space->out, error);
}

// the probabilities swept, read to the host in chunks, and tallied
static int qasm_probabilities(QasmSpace *space, const QasmProgram *program, QasmTally *tally, EngineError *error)
{
    const unsigned long long lanes = space->lanes;
    const unsigned int limbs = program->layout.out_limbs;
    const unsigned int bits = program->out_bits[0];
    if (!QASM_HELD((program->out_offset[0] == 0u) && (limbs == 4u) && (bits <= 128u) && (bits > 64u), program, error,
                   ENGINE_ERROR_LOGIC))
    {
        return 0;
    }
    if (space->on_host != 0)
    {
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program->layout;
        run.in[0] = space->state;
        run.bodies[0] = lanes;
        run.count = lanes;
        run.out = space->out;
        if (!QASM_HELD(cycle_record_run_host(&run) != CYCLE_REFUSED, space, error, ENGINE_ERROR_LOGIC))
        {
            return 0;
        }
        qasm_tally_lanes(tally, space->out, limbs, bits, 0ull, lanes);
        return 1;
    }
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.record = program->record;
    run.device_in[0] = space->state;
    run.bodies[0] = lanes;
    run.count = lanes;
    run.device_out = space->out;
    run.error = error;
    if (cycle_record_run(&run) == CYCLE_REFUSED)
    {
        engine_error_frame(error);
        return 0;
    }
    const unsigned long long chunk = (lanes < QASM_CHUNK_LANES) ? lanes : QASM_CHUNK_LANES;
    unsigned int *const staging = (unsigned int *)malloc((size_t)(chunk * limbs * sizeof(unsigned int)));
    if (!QASM_HELD(staging != NULL, space, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    int good = 1;
    for (unsigned long long first = 0ull; good && (first < lanes); first += chunk)
    {
        const unsigned long long count = ((lanes - first) < chunk) ? (lanes - first) : chunk;
        good = QASM_TOOK(cudaMemcpy(staging, &space->out[first * limbs], (size_t)(count * limbs * sizeof(unsigned int)),
                                    cudaMemcpyDeviceToHost),
                         staging, error);
        if (good)
        {
            qasm_tally_lanes(tally, staging, limbs, bits, first, count);
        }
    }
    free(staging);
    return good;
}

long qasm_run(const QasmRunRequest *request, QasmOutcome *outcome)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_REFUSED;
    }
    EngineError *const error = request->error;
    const QasmCircuit *const circuit = request->circuit;
    if (!QASM_HELD((outcome != NULL) && (circuit != NULL) && (circuit->qubits != 0u)
                       && (circuit->qubits <= QASM_QUBITS_MOST) && (circuit->measured != 0u)
                       && ((circuit->gate_count == 0u) || (circuit->gates != NULL)),
                   request, error, ENGINE_ERROR_REQUEST))
    {
        return QASM_REFUSED;
    }
    memset(outcome, 0, sizeof(*outcome));
    const auto started = std::chrono::steady_clock::now();
    const int on_host = (request->on_host != 0) ? 1 : 0;
    QasmProgram programs[QASM_PROGRAMS];
    memset(programs, 0, sizeof(programs));
    int good = 1;
    for (unsigned int which = 0u; good && (which < QASM_PROGRAMS); which += 1u)
    {
        good = qasm_program_load(&programs[which], which, on_host, error);
    }
    QasmSpace space;
    memset(&space, 0, sizeof(space));
    good = good && qasm_space_hold(&space, circuit, on_host, error);
    for (unsigned int gate = 0u; good && (gate < circuit->gate_count); gate += 1u)
    {
        good = qasm_sweep(&space, programs, &circuit->gates[gate], error);
    }
    if (good && (on_host == 0))
    {
        unsigned int overflow = 1u;
        good = QASM_TOOK(cudaDeviceSynchronize(), space.state, error)
            && QASM_TOOK(cudaMemcpy(&overflow, space.overflow, sizeof(overflow), cudaMemcpyDeviceToHost), space.overflow,
                         error)
            && QASM_HELD(overflow == 0u, space.overflow, error, ENGINE_ERROR_LOGIC);
    }
    if (good && (request->state_out != NULL))
    {
        const size_t bytes = (size_t)(space.lanes * QASM_STATE_LIMBS * sizeof(unsigned int));
        if (on_host != 0)
        {
            memcpy(request->state_out, space.state, bytes);
        }
        else
        {
            good = QASM_TOOK(cudaMemcpy(request->state_out, space.state, bytes, cudaMemcpyDeviceToHost),
                             request->state_out, error);
        }
    }
    QasmTally tally;
    memset(&tally, 0, sizeof(tally));
    tally.circuit = circuit;
    for (unsigned int qubit = 0u; qubit < circuit->qubits; qubit += 1u)
    {
        if (circuit->measure[qubit] != 0u)
        {
            tally.measured_qubit[tally.measured_count] = qubit;
            tally.measured_count += 1u;
        }
    }
    tally.full = (tally.measured_count == circuit->qubits);
    if (good && (tally.full == 0))
    {
        tally.bins = (QasmWide *)calloc((size_t)(1ull << tally.measured_count), sizeof(QasmWide));
        good = QASM_HELD(tally.bins != NULL, &tally, error, ENGINE_ERROR_RESOURCE);
    }
    good = good && qasm_probabilities(&space, &programs[QASM_PROGRAM_PROBABILITY], &tally, error);
    if (good && (tally.full == 0))
    {
        for (unsigned long long bin = 0ull; bin < (1ull << tally.measured_count); bin += 1ull)
        {
            qasm_top_two(&tally.top, &tally.bins[bin], bin);
        }
    }
    if (good)
    {
        qasm_outcome_close(&tally, outcome);
        outcome->sweeps = circuit->gate_count + 1u;
        outcome->lanes = space.lanes;
    }
    free(tally.bins);
    qasm_space_release(&space);
    for (unsigned int which = 0u; which < QASM_PROGRAMS; which += 1u)
    {
        qasm_program_release(&programs[which]);
    }
    outcome->microseconds = (unsigned long long)std::chrono::duration_cast<std::chrono::microseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
    if (!good)
    {
        engine_error_frame(error);
        return QASM_REFUSED;
    }
    return 0L;
}

// ---------------------------------------------------------------------------------------------------------------
// the tessera job

static int qasm_job_daemon(char *path, size_t room)
{
    // $TESSERA_DAEMON names the daemon; otherwise it is the tessera_daemon beside this program
    const char *const named = getenv("TESSERA_DAEMON");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(path, room, "%s", named);
        return (written > 0) && ((size_t)written < room);
    }
#if defined(_WIN32)
    const size_t length = (size_t)GetModuleFileNameA(NULL, path, (DWORD)room);
    const char *const daemon = "tessera_daemon.exe";
#else
    const ssize_t read = readlink("/proc/self/exe", path, room - 1u);
    const size_t length = (read > 0) ? (size_t)read : 0u;
    const char *const daemon = "tessera_daemon";
#endif
    size_t cut = (length < room) ? length : 0u;
    while ((cut != 0u) && (path[cut - 1u] != '/') && (path[cut - 1u] != '\\'))
    {
        cut -= 1u;
    }
    if ((cut == 0u) || ((cut + strlen(daemon) + 1u) > room))
    {
        return 0;
    }
    memcpy(path + cut, daemon, strlen(daemon) + 1u);
    return 1;
}

long qasm_job_submit(const unsigned char *request, unsigned long long bytes, unsigned long long declared,
                     QasmJob **job, EngineError *error)
{
    if (error == NULL)
    {
        return QASM_REFUSED;
    }
    if (!QASM_HELD((request != NULL) && (bytes != 0ull) && (declared != 0ull) && (job != NULL), request, error,
                   ENGINE_ERROR_REQUEST))
    {
        return QASM_REFUSED;
    }
    *job = NULL;
    static char daemon[ENGINE_PATH_ROOM];
    int device = 0;
    cudaDeviceProp properties;
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    if (!QASM_HELD(qasm_job_daemon(daemon, sizeof(daemon)), daemon, error, ENGINE_ERROR_RESOURCE)
     || !QASM_TOOK(cudaGetDevice(&device), &device, error)
     || !QASM_TOOK(cudaGetDeviceProperties(&properties, device), &properties, error))
    {
        return QASM_REFUSED;
    }
    const ObsignatioSignumRequest signum = {request, bytes, NULL, OBSIGNATIO_MODE_HASH, ask.signum.bytes,
                                            ENGINE_SIGNUM_BYTES, error};
    if (obsignatio_signum(&signum) != 0L)
    {
        engine_error_frame(error);
        return QASM_REFUSED;
    }
    memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
#if defined(_WIN32)
    memcpy(&ask.luid, properties.luid, sizeof(ask.luid));
#endif
    ask.declared = declared;
    ask.holding_microseconds = QASM_JOB_HOLDING_MICROSECONDS;
    ask.sweep_microseconds = QASM_JOB_SWEEP_MICROSECONDS;
    ask.idle_microseconds = QASM_JOB_IDLE_MICROSECONDS;
    ask.override_budget = (getenv("TESSERA_OVERRIDE") != NULL) ? 1u : 0u;
    ask.daemon_path = daemon;
    ask.error = error;
    TesseraTicket ticket;
    memset(&ticket, 0, sizeof(ticket));
    TesseraClient *client = NULL;
    if (tessera_job_submit(&ask, &client, &ticket) != 0L)
    {
        engine_error_frame(error);
        return QASM_REFUSED;
    }
    if (ticket.asked != 0u)
    {
        fprintf(stderr, "tessera: the run declares %llu bytes over its kept peak of %llu; TESSERA_OVERRIDE=1 admits it\n",
                declared, ticket.last_peak);
        const int admitted = (tessera_job_wait(client, &ticket, error) == 0L) && (ticket.lost == 0u);
        if (!admitted)
        {
            if (ticket.lost != 0u)
            {
                fprintf(stderr, "tessera: the run was held past its holding time and lost (ticket in %s)\n",
                        ticket.lost_path);
                tessera_job_precalc_kept(client, error);
            }
            QASM_HELD(0, client, error, ENGINE_ERROR_RESOURCE);
            return QASM_REFUSED;
        }
    }
    QasmJob *const held = (QasmJob *)calloc(1u, sizeof(QasmJob));
    if (!QASM_HELD(held != NULL, job, error, ENGINE_ERROR_RESOURCE))
    {
        TesseraTicket released;
        tessera_job_release(client, &released, error);
        return QASM_REFUSED;
    }
    held->client = client;
    held->declared = declared;
    *job = held;
    fprintf(stderr, "tessera: admitted, %llu bytes reserved\n", ticket.granted);
    return 0L;
}

long qasm_job_release(QasmJob *job, EngineError *error)
{
    if ((job == NULL) || (error == NULL))
    {
        return 0L;
    }
    TesseraTicket ticket;
    memset(&ticket, 0, sizeof(ticket));
    const long released = tessera_job_release(job->client, &ticket, error);
    if (released == 0L)
    {
        fprintf(stderr, "tessera: released, peak %llu bytes%s\n", ticket.last_peak,
                (ticket.last_peak > job->declared) ? ", more than it declared" : "");
    }
    free(job);
    return (released == 0L) ? 0L : QASM_REFUSED;
}
