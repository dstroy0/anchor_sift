// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Catalog: EXP-x-024
//
// The waves m^(-1/2) e^(-i t ln m) at the boundaries t = 2pi n^2, every wave a lane, swept on the device as a program of
// the record machine, one job on the device's tessera daemon.
//
//   Usage:  exact_zeta_arrival <input> <output>
//
// At t = 2pi n^2 wave m stands at u = e^(-2pi i n^2 ln m). Its phase has the constant second difference 4pi ln m in n:
// from one boundary to the next a lane steps by its relation alone, u <- u r and r <- r q, with
// r = e^(-2pi i (2n + 1) ln m) and q = e^(-4pi i ln m), each product divided by the scale S = 2^62 and wrapped to 64
// bits. Each boundary's reading is m^(-1/2) u where m < n and 0 otherwise, and the sum across lanes,
// V_n = sum over m < n of m^(-1/2) e^(-2pi i n^2 ln m), is taken on the device by cycle_record_sum, exact. A sweep
// covers B boundaries; its state, the last u and r, is the next sweep's first member, read where the sweep wrote it.
//
// The input, written by exact_zeta_arrival.py, little-endian 64-bit integers: M, n0, sweeps, B, K and G, then for
// each lane from 1 to M: u, r and q, each its real part then its imaginary part, and m^(-1/2), each times S, two's
// complement. The lanes are M / G runs of G, summed run by run, and a lane's m is its place in its run, 1 to G. K lanes
// of the first sweep are run on the host too, from the exact integer library.
//
// The output: the line "sum_limbs L", one line a boundary, "n", then each run's sum, its real part and its imaginary
// part, L hex limbs each, least significant first, two's complement times S; then "host 1" where the host's records of
// the first sweep equal the device's word for word over K lanes, else "host 0", and the line
// "steps P out_limbs O compiled C".

#include "../../src/c/engine/analysis/cycle/cycle.h"
#include "../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../src/c/engine/analysis/keymath/keymath.h"
#include "../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vector>

#define ARRIVAL_SCALE_BITS 62u
#define ARRIVAL_WIDTH 64u
#define ARRIVAL_SUM_LIMBS 4u
#define ARRIVAL_CONSTANT_LIMBS 8u
#define ARRIVAL_SHARED_LIMBS 2u

typedef struct
{
    std::vector<EngineRecordStep> steps;
} ArrivalProgram;

static unsigned int arrival_step(ArrivalProgram *program, EngineRecordOperation operation, unsigned int left,
                                 unsigned int right, unsigned int member)
{
    EngineRecordStep step = {operation, left, right, member};
    program->steps.push_back(step);
    return (unsigned int)program->steps.size() - 1u;
}

// (re, im) times (c_re + i c_im), each product divided by S and wrapped to 64 bits
static void arrival_turn(ArrivalProgram *program, unsigned int *re, unsigned int *im, unsigned int c_re,
                         unsigned int c_im, unsigned int scale)
{
    const unsigned int one = arrival_step(program, ENGINE_RECORD_PRODUCT, *re, c_re, 0u);
    const unsigned int two = arrival_step(program, ENGINE_RECORD_PRODUCT, *im, c_im, 0u);
    const unsigned int three = arrival_step(program, ENGINE_RECORD_PRODUCT, *re, c_im, 0u);
    const unsigned int four = arrival_step(program, ENGINE_RECORD_PRODUCT, *im, c_re, 0u);
    const unsigned int real = arrival_step(program, ENGINE_RECORD_DIFFERENCE, one, two, 0u);
    const unsigned int imaginary = arrival_step(program, ENGINE_RECORD_SUM, three, four, 0u);
    const unsigned int real_scaled = arrival_step(program, ENGINE_RECORD_QUOTIENT, real, scale, 0u);
    const unsigned int imaginary_scaled = arrival_step(program, ENGINE_RECORD_QUOTIENT, imaginary, scale, 0u);
    *re = arrival_step(program, ENGINE_RECORD_WRAP, real_scaled, ARRIVAL_WIDTH, 0u);
    *im = arrival_step(program, ENGINE_RECORD_WRAP, imaginary_scaled, ARRIVAL_WIDTH, 0u);
}

// B boundaries. Fields 0 to 3 are the state, u and r, in member 0; 4 to 7 are q, m^(-1/2) and m in member 1; 8 is n0 in
// member 2. outputs[2j] and outputs[2j + 1] are boundary j's reading, and outputs[2B] on are the last u and r
static void arrival_build(ArrivalProgram *program, unsigned int floors, std::vector<unsigned int> *outputs)
{
    unsigned int u_re = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    unsigned int u_im = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u);
    unsigned int r_re = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u, 0u);
    unsigned int r_im = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 3u, 0u, 0u);
    const unsigned int q_re = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 4u, 0u, 1u);
    const unsigned int q_im = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 5u, 0u, 1u);
    const unsigned int amplitude = arrival_step(program, ENGINE_RECORD_FIELD_SIGNED, 6u, 0u, 1u);
    const unsigned int m = arrival_step(program, ENGINE_RECORD_FIELD, 7u, 0u, 1u);
    const unsigned int n0 = arrival_step(program, ENGINE_RECORD_FIELD, 8u, 0u, 2u);
    // S = 2^62 = 0 + 2^32 * 2^30
    const unsigned int scale = arrival_step(program, ENGINE_RECORD_CONSTANT, 0u, 1u << 30u, 0u);
    const unsigned int two = arrival_step(program, ENGINE_RECORD_CONSTANT, 2u, 0u, 0u);
    for (unsigned int j = 0u; j < floors; j += 1u)
    {
        const unsigned int offset = arrival_step(program, ENGINE_RECORD_CONSTANT, j, 0u, 0u);
        const unsigned int n = arrival_step(program, ENGINE_RECORD_SUM, n0, offset, 0u);
        const unsigned int order = arrival_step(program, ENGINE_RECORD_COMPARE, n, m, 0u);
        const unsigned int size = arrival_step(program, ENGINE_RECORD_ABSOLUTE, order, 0u, 0u);
        const unsigned int doubled = arrival_step(program, ENGINE_RECORD_SUM, order, size, 0u);
        const unsigned int below = arrival_step(program, ENGINE_RECORD_QUOTIENT, doubled, two, 0u);
        const unsigned int weighted_re = arrival_step(program, ENGINE_RECORD_PRODUCT, amplitude, u_re, 0u);
        const unsigned int weighted_im = arrival_step(program, ENGINE_RECORD_PRODUCT, amplitude, u_im, 0u);
        const unsigned int scaled_re = arrival_step(program, ENGINE_RECORD_QUOTIENT, weighted_re, scale, 0u);
        const unsigned int scaled_im = arrival_step(program, ENGINE_RECORD_QUOTIENT, weighted_im, scale, 0u);
        outputs->push_back(arrival_step(program, ENGINE_RECORD_PRODUCT, scaled_re, below, 0u));
        outputs->push_back(arrival_step(program, ENGINE_RECORD_PRODUCT, scaled_im, below, 0u));
        arrival_turn(program, &u_re, &u_im, r_re, r_im, scale);
        arrival_turn(program, &r_re, &r_im, q_re, q_im, scale);
    }
    outputs->push_back(u_re);
    outputs->push_back(u_im);
    outputs->push_back(r_re);
    outputs->push_back(r_im);
}

// `bits` of a two's complement value laid into a record at `offset`
static void arrival_put(unsigned int *record, unsigned int offset, unsigned int bits, long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int to = offset + bit;
        const unsigned int bit_value = (bit < 64u) ? (unsigned int)(((unsigned long long)value >> bit) & 1ull)
                                                   : (unsigned int)((value < 0) ? 1u : 0u);
        record[to / 32u] = (record[to / 32u] & ~(1u << (to % 32u))) | (bit_value << (to % 32u));
    }
}

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
} ArrivalLaid;

// the program imprinted and laid out with the state fields at the given offsets and widths, member 0 `in_limbs` wide
static int arrival_lay(ArrivalProgram *program, std::vector<unsigned int> *outputs, const unsigned int state_bits[4],
                       const unsigned int state_offset[4], unsigned int state_limbs, ArrivalLaid *laid,
                       EngineError *error)
{
    memset(laid, 0, sizeof(*laid));
    unsigned int field_bits[9];
    unsigned int field_offset[9];
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        field_bits[at] = state_bits[at];
        field_offset[at] = state_offset[at];
    }
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        field_bits[4u + at] = 64u;
        field_offset[4u + at] = 64u * at;
    }
    field_bits[8] = 64u;
    field_offset[8] = 0u;
    const KeymathRecordRequest encode = {program->steps.data(), (unsigned int)program->steps.size(), field_bits, 9u, 3u,
                                         outputs->data(),       (unsigned int)outputs->size(),      NULL,       0u,
                                         &laid->key,            error};
    if (keymath_record_encode(&encode) == KEYMATH_ERROR)
    {
        return 0;
    }
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {state_limbs, ARRIVAL_CONSTANT_LIMBS, ARRIVAL_SHARED_LIMBS};
    const KeyScheduleRecordRequest lay = {&laid->key, field_offset, 9u, in_limbs, 1, &laid->layout, error};
    if (key_schedule_record_layout(&lay) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&laid->key);
        return 0;
    }
    return 1;
}

static void arrival_unlay(ArrivalLaid *laid)
{
    key_schedule_record_release(&laid->layout);
    keymath_record_release(&laid->key);
}

int main(int count, char **arguments)
{
    SimResults job;
    char job_capacity[SIM_LINE_CAPACITY];
    sim_open(&job, job_capacity);
    if (count != 3)
    {
        fprintf(stderr, "  usage: exact_zeta_arrival <input> <output>\n");
        return 2;
    }
    FILE *in = fopen(arguments[1], "rb");
    long long header[6] = {0, 0, 0, 0, 0, 0};
    int read = (in != NULL) && (fread(header, sizeof(long long), 6u, in) == 6u) && (header[0] > 0) &&
               (header[2] > 0) && (header[3] > 0) && (header[4] > 0) && (header[4] <= header[0]) &&
               (header[5] > 0) && (header[0] % header[5] == 0);
    const unsigned long long lanes = read ? (unsigned long long)header[0] : 0ull;
    const unsigned long long first = read ? (unsigned long long)header[1] : 0ull;
    const unsigned int sweeps = read ? (unsigned int)header[2] : 0u;
    const unsigned int floors = read ? (unsigned int)header[3] : 0u;
    const unsigned long long checked = read ? (unsigned long long)header[4] : 0ull;
    const unsigned long long group = read ? (unsigned long long)header[5] : 1ull;
    std::vector<long long> seeds(read ? (size_t)(lanes * 7ull) : 0u);
    read = read && (fread(seeds.data(), sizeof(long long), seeds.size(), in) == seeds.size());
    if (in != NULL)
    {
        fclose(in);
    }
    if (!read)
    {
        fprintf(stderr, "  exact_zeta_arrival: %s is not an input this program reads\n", arguments[1]);
        return 2;
    }

    // laid out twice: once to learn where the state lands in the output, then with the state read from there
    ArrivalProgram program;
    std::vector<unsigned int> outputs;
    arrival_build(&program, floors, &outputs);
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned int guess_bits[4] = {65u, 65u, 65u, 65u};
    const unsigned int guess_offset[4] = {0u, 65u, 130u, 195u};
    ArrivalLaid probe;
    ArrivalLaid laid;
    memset(&laid, 0, sizeof(laid));
    int ok = arrival_lay(&program, &outputs, guess_bits, guess_offset, 9u, &probe, &error);
    sim_check(&job, ok, "keymath imprints the arrival program and the scheduler lays it out");
    unsigned int state_bits[4] = {0u, 0u, 0u, 0u};
    unsigned int state_offset[4] = {0u, 0u, 0u, 0u};
    unsigned int out_limbs = 0u;
    if (ok)
    {
        for (unsigned int at = 0u; at < 4u; at += 1u)
        {
            const DeviceRecordStep *const step = &probe.layout.step_table[outputs[2u * floors + at]];
            state_bits[at] = step->out_bits;
            state_offset[at] = step->out_offset;
        }
        out_limbs = probe.layout.out_limbs;
        arrival_unlay(&probe);
    }
    ok = ok && arrival_lay(&program, &outputs, state_bits, state_offset, out_limbs, &laid, &error);
    for (unsigned int at = 0u; ok && (at < 4u); at += 1u)
    {
        const DeviceRecordStep *const step = &laid.layout.step_table[outputs[2u * floors + at]];
        ok = (step->out_bits == state_bits[at]) && (step->out_offset == state_offset[at]) &&
             (laid.layout.out_limbs == out_limbs);
    }
    sim_check(&job, ok, "the state lands where the next sweep reads it");

    const unsigned long long declared = (2ull * lanes * out_limbs + lanes * ARRIVAL_CONSTANT_LIMBS) * sizeof(unsigned int) +
                                        (64ull << 20u);
    ok = ok && sim_job_submit(&job, "exact_zeta_arrival", count, arguments, declared);
    CycleRecord *record = NULL;
    ok = ok && (cycle_record_load(&laid.layout, &record, &error) != CYCLE_ERROR);
    sim_check(&job, ok, "the arrival program loads onto the device");

    // the first sweep's state in the output's own layout, and every lane's constants
    std::vector<unsigned int> state((size_t)(ok ? lanes * out_limbs : 0ull), 0u);
    std::vector<unsigned int> constants((size_t)(ok ? lanes * ARRIVAL_CONSTANT_LIMBS : 0ull), 0u);
    for (unsigned long long lane = 0ull; ok && (lane < lanes); lane += 1ull)
    {
        const long long *const seed = &seeds[(size_t)(lane * 7ull)];
        unsigned int *const here = &state[(size_t)(lane * out_limbs)];
        for (unsigned int at = 0u; at < 4u; at += 1u)
        {
            arrival_put(here, state_offset[at], state_bits[at], seed[at]);
        }
        unsigned int *const fixed = &constants[(size_t)(lane * ARRIVAL_CONSTANT_LIMBS)];
        arrival_put(fixed, 0u, 64u, seed[4]);
        arrival_put(fixed, 64u, 64u, seed[5]);
        arrival_put(fixed, 128u, 64u, seed[6]);
        arrival_put(fixed, 192u, 64u, (long long)(lane % group + 1ull));
    }
    unsigned int *device_state[2] = {NULL, NULL};
    unsigned int *device_constants = NULL;
    unsigned int *device_shared = NULL;
    const size_t state_bytes = state.size() * sizeof(unsigned int);
    ok = ok && (cudaMalloc((void **)&device_state[0], state_bytes) == cudaSuccess) &&
         (cudaMalloc((void **)&device_state[1], state_bytes) == cudaSuccess) &&
         (cudaMalloc((void **)&device_constants, constants.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_shared, ARRIVAL_SHARED_LIMBS * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_state[0], state.data(), state_bytes, cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_constants, constants.data(), constants.size() * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    sim_check(&job, ok, "the seeds and the constants are held on the device");

    FILE *out = ok ? fopen(arguments[2], "w") : NULL;
    ok = ok && (out != NULL);
    if (ok)
    {
        fprintf(out, "sum_limbs %u\n", ARRIVAL_SUM_LIMBS);
    }
    int same = 0;
    std::vector<unsigned int> sums((size_t)((lanes / group) * ARRIVAL_SUM_LIMBS), 0u);
    for (unsigned int sweep = 0u; ok && (sweep < sweeps); sweep += 1u)
    {
        unsigned int shared[ARRIVAL_SHARED_LIMBS] = {0u, 0u};
        const unsigned long long n0 = first + (unsigned long long)sweep * floors;
        arrival_put(shared, 0u, 64u, (long long)n0);
        ok = cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess;
        unsigned int *const from = device_state[sweep % 2u];
        unsigned int *const to = device_state[(sweep + 1u) % 2u];
        const CycleRecordRunRequest run = {record, {from, device_constants, device_shared}, {lanes, lanes, 1ull},
                                           NULL,   lanes,                                     to,
                                           &error};
        ok = ok && (cycle_record_run(&run) == (long)lanes);
        if (ok && (sweep == 0u))
        {
            // the port check: the same program on the host, from the exact integer library, over the first K lanes
            std::vector<unsigned int> host_out((size_t)(checked * out_limbs));
            std::vector<unsigned int> device_out((size_t)(checked * out_limbs));
            const CycleRecordHostRequest host = {&laid.layout,  {state.data(), constants.data(), shared},
                                                 {checked, checked, 1ull}, NULL, checked, host_out.data(), &error};
            same = (cycle_record_run_host(&host) == (long)checked) &&
                   (cudaMemcpy(device_out.data(), to, device_out.size() * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess) &&
                   (memcmp(host_out.data(), device_out.data(), device_out.size() * sizeof(unsigned int)) == 0);
        }
        for (unsigned int j = 0u; ok && (j < floors); j += 1u)
        {
            fprintf(out, "%llu", n0 + j);
            std::vector<unsigned int> parts((size_t)(2u * sums.size()), 0u);
            for (unsigned int part = 0u; ok && (part < 2u); part += 1u)
            {
                const DeviceRecordStep *const step = &laid.layout.step_table[outputs[2u * j + part]];
                const CycleRecordSumRequest sum = {to,         lanes,     group, out_limbs, step->out_offset,
                                                   step->out_bits, ARRIVAL_SUM_LIMBS, sums.data(), &error};
                ok = cycle_record_sum(&sum) != CYCLE_ERROR;
                memcpy(&parts[part * sums.size()], sums.data(), sums.size() * sizeof(unsigned int));
            }
            for (unsigned long long run = 0ull; ok && (run < lanes / group); run += 1ull)
            {
                for (unsigned int part = 0u; part < 2u; part += 1u)
                {
                    for (unsigned int limb = 0u; limb < ARRIVAL_SUM_LIMBS; limb += 1u)
                    {
                        fprintf(out, " %x", parts[part * sums.size() + run * ARRIVAL_SUM_LIMBS + limb]);
                    }
                }
            }
            fprintf(out, "\n");
        }
    }
    sim_check(&job, ok, "every sweep runs on the device and every boundary is summed across its lanes");
    sim_check(&job, same, "the host's records of the first sweep equal the device's word for word");
    if (out != NULL)
    {
        fprintf(out, "host %d\nsteps %u out_limbs %u compiled %d\n", same, laid.layout.steps, out_limbs,
                (record != NULL) ? cycle_record_compiled(record) : 0);
        fclose(out);
    }
    cudaFree(device_state[0]);
    cudaFree(device_state[1]);
    cudaFree(device_constants);
    cudaFree(device_shared);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    arrival_unlay(&laid);
    return sim_close(&job, "exact_zeta_arrival");
}
