// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_device_kernels.cu: the kernels, probabilities and outcomes
#include "qasm_device_internal.h"

unsigned int qasm_blocks(unsigned long long count)
{
    const unsigned long long needed = (count + QASM_BLOCK - 1ull) / QASM_BLOCK;
    return (unsigned int)((needed < QASM_BLOCKS_MAX) ? needed : QASM_BLOCKS_MAX);
}

// ---------------------------------------------------------------------------------------------------------------
// gate records

static void qasm_put_word(unsigned int *limbs, long long value)
{
    limbs[0] = (unsigned int)((unsigned long long)value & 0xFFFFFFFFull);
    limbs[1] = (unsigned int)((unsigned long long)value >> 32u);
}

void qasm_gate_records(const QasmGate *gate, unsigned int *records)
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

unsigned long long qasm_gate_bodies(const QasmGate *gate)
{
    return (gate->kind == QASM_GATE_PAIR) ? QASM_PAIR_ROWS
                                          : ((gate->kind == QASM_GATE_DIAGONAL) ? QASM_DIAGONAL_ENTRIES : QASM_PHASES);
}

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

void qasm_top_two(QasmTopTwo *top, const QasmWide *value, unsigned long long key)
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

static unsigned long long qasm_lane_bin(const QasmResults *results, unsigned long long lane)
{
    unsigned long long bin = 0ull;
    for (unsigned int at = 0u; at < results->measured_count; at += 1u)
    {
        bin |= ((lane >> results->measured_qubit[at]) & 1ull) << at;
    }
    return bin;
}

static unsigned long long qasm_bin_outcome(const QasmResults *results, unsigned long long bin)
{
    unsigned long long outcome = 0ull;
    for (unsigned int at = 0u; at < results->measured_count; at += 1u)
    {
        const unsigned int clbit = results->circuit->measure[results->measured_qubit[at]] - 1u;
        outcome |= ((bin >> at) & 1ull) << clbit;
    }
    return outcome;
}

void qasm_results_lanes(QasmResults *results, const unsigned int *records, unsigned int limbs, unsigned int bits,
                        unsigned long long first, unsigned long long count)
{
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        const QasmWide value = qasm_probability(&records[at * limbs], bits);
        const unsigned long long lane = first + at;
        if (results->full != 0)
        {
            qasm_top_two(&results->top, &value, lane);
        }
        else
        {
            qasm_wide_add(&results->bins[qasm_lane_bin(results, lane)], &value);
        }
    }
}

// the slack 2E + E^2 and whether the peak is proved
void qasm_outcome_close(const QasmResults *results, QasmOutcome *outcome)
{
    const QasmCircuit *const circuit = results->circuit;
    outcome->peak = qasm_bin_outcome(results, results->full ? qasm_lane_bin(results, results->top.best_key)
                                                            : results->top.best_key);
    outcome->runner_up = qasm_bin_outcome(results, results->full ? qasm_lane_bin(results, results->top.second_key)
                                                                 : results->top.second_key);
    qasm_wide_units(&results->top.best, outcome->peak_units);
    qasm_wide_units(&results->top.second, outcome->runner_up_units);
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
    best.sign = ((results->top.best.low | results->top.best.high) != 0ull) ? 1 : 0;
    second.sign = ((results->top.second.low | results->top.second.high) != 0ull) ? 1 : 0;
    anchor_exact_subtract(&best, &second, &gap);
    anchor_exact_add(&slack, &slack, &twice);
    outcome->proved = (anchor_exact_compare(&gap, &twice) > 0) ? 1u : 0u;
}

// ---------------------------------------------------------------------------------------------------------------
// the run

unsigned long long qasm_device_bytes(const QasmCircuit *circuit)
{
    if ((circuit == NULL) || (circuit->qubits == 0u) || (circuit->qubits > QASM_QUBITS_MAX))
    {
        return 0ull;
    }
    const unsigned long long lanes = 1ull << circuit->qubits;
    // the state, the widest program's outputs, the widest index, and the gate records
    const unsigned long long per_lane =
        (QASM_STATE_LIMBS + QASM_WIDE_LIMBS + ENGINE_RECORD_MEMBERS_MAX) * sizeof(unsigned int);
    const unsigned long long records = (QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS) +
                                       (QASM_DIAGONAL_ENTRIES * QASM_DIAGONAL_ENTRY_LIMBS) +
                                       (QASM_PHASES * QASM_PHASE_LIMBS);
    return (lanes * per_lane) + (records * sizeof(unsigned int)) + sizeof(unsigned int);
}

void qasm_space_release(QasmSpace *space)
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

int qasm_space_reserve(QasmSpace *space, const QasmCircuit *circuit, int on_host, EngineError *error)
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
    unsigned int **const buffers[7] = {
        &space->state,  &space->out,     &space->index, &space->pair_rows, &space->diagonal_entries,
        &space->phases, &space->overflow};
    if (on_host == 0)
    {
        size_t free_bytes = 0u;
        size_t total_bytes = 0u;
        if (!QASM_STATUS_CHECK(cudaMemGetInfo(&free_bytes, &total_bytes), space, error) ||
            !QASM_CHECK(qasm_device_bytes(circuit) <= (unsigned long long)free_bytes, space, error,
                        ENGINE_ERROR_RESOURCE))
        {
            return 0;
        }
    }
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        if (on_host != 0)
        {
            *buffers[at] = (unsigned int *)calloc(1u, sizes[at]);
            if (!QASM_CHECK(*buffers[at] != NULL, buffers[at], error, ENGINE_ERROR_RESOURCE))
            {
                qasm_space_release(space);
                return 0;
            }
        }
        else if (!QASM_STATUS_CHECK(cudaMalloc((void **)buffers[at], sizes[at]), buffers[at], error) ||
                 !QASM_STATUS_CHECK(cudaMemset(*buffers[at], 0, sizes[at]), buffers[at], error))
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
    if (!QASM_STATUS_CHECK(cudaMemcpy(space->state, one, sizeof(one), cudaMemcpyHostToDevice), space->state, error) ||
        !QASM_STATUS_CHECK(cudaMemcpy(space->phases, phases, sizeof(phases), cudaMemcpyHostToDevice), space->phases,
                           error))
    {
        qasm_space_release(space);
        return 0;
    }
    return 1;
}
