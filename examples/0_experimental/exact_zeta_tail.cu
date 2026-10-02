// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Catalog: EXP-x-023
//
// Euler-Maclaurin's tail coefficient C at every point of a pass, one lane a point, swept on the device as a
// program of the record machine, one job on the device's tessera daemon.
//
//   Usage:  exact_zeta_tail <input> <output>
//
// C = N / (s - 1) + 1/2 + sum over k from 1 to N of B_2k / (2k)! s (s + 1) ... (s + 2k - 2) N^(1 - 2k), with
// s = 1/2 + it, at the fixed scale S the input names. The sum is carried as tau_1 = s / 12N and
// tau_k = tau_(k-1) (s + 2k - 3)(s + 2k - 2) rho_k, rho_k = B_2k (2k - 2)! / (B_(2k-2) (2k)! N^2). Every term
// sits near the scale: B_2k / (2k)! alone falls under it and the rising product alone outgrows it. Each tau is
// wrapped to W bits after its quotient, W from a bound on every tau the input's writer derives, and a quotient
// rounds toward zero.
//
// The input, written by exact_zeta_riemann_siegel.py: the line "N W", the line "fields F", F lines of a field's
// bits and offset, the line "in_limbs L0 L1", the line "points P", P lines of L0 hex limbs each, a point's record
// (field 0, t S, signed), and one line of L1 hex limbs, the shared record (field 1, S; field 2, S / 2; fields 3 on,
// rho_k S for k from 2 to N, signed). Limbs are least significant first.
//
// The output: the line "out_limbs L", the line "outputs re_offset re_bits im_offset im_bits", P lines of L hex limbs,
// the device's records, and the line "host 1" where the same program on the host, from the exact integer library,
// gives the device's records word for word, else "host 0".

#include "../../src/c/engine/analysis/cycle/cycle.h"
#include "../../src/c/types/integers/exact_integer.h"
#include "../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../src/c/engine/analysis/keymath/keymath.h"
#include "../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vector>

typedef struct
{
    std::vector<EngineRecordStep> steps;
} TailProgram;

static unsigned int tail_step(TailProgram *program, EngineRecordOperation operation, unsigned int left,
                              unsigned int right, unsigned int member)
{
    EngineRecordStep step = {operation, left, right, member};
    program->steps.push_back(step);
    return (unsigned int)program->steps.size() - 1u;
}

// (re, im) times (c + i t), each product divided by S and wrapped to W bits
static void tail_turn(TailProgram *program, unsigned int *re, unsigned int *im, unsigned int c, unsigned int t,
                      unsigned int s, unsigned int width)
{
    const unsigned int one = tail_step(program, ENGINE_RECORD_PRODUCT, *re, c, 0u);
    const unsigned int two = tail_step(program, ENGINE_RECORD_PRODUCT, *im, t, 0u);
    const unsigned int three = tail_step(program, ENGINE_RECORD_PRODUCT, *re, t, 0u);
    const unsigned int four = tail_step(program, ENGINE_RECORD_PRODUCT, *im, c, 0u);
    const unsigned int real = tail_step(program, ENGINE_RECORD_DIFFERENCE, one, two, 0u);
    const unsigned int imaginary = tail_step(program, ENGINE_RECORD_SUM, three, four, 0u);
    const unsigned int real_scaled = tail_step(program, ENGINE_RECORD_QUOTIENT, real, s, 0u);
    const unsigned int imaginary_scaled = tail_step(program, ENGINE_RECORD_QUOTIENT, imaginary, s, 0u);
    *re = tail_step(program, ENGINE_RECORD_WRAP, real_scaled, width, 0u);
    *im = tail_step(program, ENGINE_RECORD_WRAP, imaginary_scaled, width, 0u);
}

// the program for N terms; outputs[0] and outputs[1] are C's real and imaginary parts
static void tail_build(TailProgram *program, unsigned int terms, unsigned int width, unsigned int outputs[2])
{
    const unsigned int t = tail_step(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u);
    const unsigned int s = tail_step(program, ENGINE_RECORD_FIELD, 1u, 0u, 1u);
    const unsigned int h = tail_step(program, ENGINE_RECORD_FIELD, 2u, 0u, 1u);
    const unsigned int twelve_n = tail_step(program, ENGINE_RECORD_CONSTANT, 12u * terms, 0u, 0u);
    unsigned int re = tail_step(program, ENGINE_RECORD_QUOTIENT, h, twelve_n, 0u);
    unsigned int im = tail_step(program, ENGINE_RECORD_QUOTIENT, t, twelve_n, 0u);
    unsigned int sum_re = re;
    unsigned int sum_im = im;
    for (unsigned int k = 2u; k <= terms; k += 1u)
    {
        for (unsigned int j = 2u * k - 3u; j <= 2u * k - 2u; j += 1u)
        {
            const unsigned int whole = tail_step(program, ENGINE_RECORD_CONSTANT, j, 0u, 0u);
            const unsigned int shift = tail_step(program, ENGINE_RECORD_PRODUCT, whole, s, 0u);
            const unsigned int c = tail_step(program, ENGINE_RECORD_SUM, h, shift, 0u);
            tail_turn(program, &re, &im, c, t, s, width);
        }
        const unsigned int rho = tail_step(program, ENGINE_RECORD_FIELD_SIGNED, 1u + k, 0u, 1u);
        const unsigned int rho_re = tail_step(program, ENGINE_RECORD_PRODUCT, re, rho, 0u);
        const unsigned int rho_im = tail_step(program, ENGINE_RECORD_PRODUCT, im, rho, 0u);
        const unsigned int scaled_re = tail_step(program, ENGINE_RECORD_QUOTIENT, rho_re, s, 0u);
        const unsigned int scaled_im = tail_step(program, ENGINE_RECORD_QUOTIENT, rho_im, s, 0u);
        re = tail_step(program, ENGINE_RECORD_WRAP, scaled_re, width, 0u);
        im = tail_step(program, ENGINE_RECORD_WRAP, scaled_im, width, 0u);
        sum_re = tail_step(program, ENGINE_RECORD_SUM, sum_re, re, 0u);
        sum_im = tail_step(program, ENGINE_RECORD_SUM, sum_im, im, 0u);
    }
    // N / (s - 1) = -N (S/2 + i t S) S^2 / ((S/2)^2 + (t S)^2), at the scale S
    const unsigned int n = tail_step(program, ENGINE_RECORD_CONSTANT, terms, 0u, 0u);
    const unsigned int hh = tail_step(program, ENGINE_RECORD_PRODUCT, h, h, 0u);
    const unsigned int tt = tail_step(program, ENGINE_RECORD_PRODUCT, t, t, 0u);
    const unsigned int size = tail_step(program, ENGINE_RECORD_SUM, hh, tt, 0u);
    const unsigned int ss = tail_step(program, ENGINE_RECORD_PRODUCT, s, s, 0u);
    const unsigned int ss_n = tail_step(program, ENGINE_RECORD_PRODUCT, ss, n, 0u);
    const unsigned int top_re = tail_step(program, ENGINE_RECORD_PRODUCT, h, ss_n, 0u);
    const unsigned int top_im = tail_step(program, ENGINE_RECORD_PRODUCT, t, ss_n, 0u);
    const unsigned int pole_re = tail_step(program, ENGINE_RECORD_QUOTIENT, top_re, size, 0u);
    const unsigned int pole_im = tail_step(program, ENGINE_RECORD_QUOTIENT, top_im, size, 0u);
    const unsigned int half = tail_step(program, ENGINE_RECORD_SUM, sum_re, h, 0u);
    outputs[0] = tail_step(program, ENGINE_RECORD_DIFFERENCE, half, pole_re, 0u);
    outputs[1] = tail_step(program, ENGINE_RECORD_DIFFERENCE, sum_im, pole_im, 0u);
}

static int tail_words(FILE *in, unsigned int *words, unsigned int count)
{
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        if (fscanf(in, "%x", &words[at]) != 1)
        {
            return 0;
        }
    }
    return 1;
}

int main(int count, char **arguments)
{
    SimResults job;
    char job_capacity[SIM_LINE_CAPACITY];
    sim_open(&job, job_capacity);
    if (count != 3)
    {
        fprintf(stderr, "  usage: exact_zeta_tail <input> <output>\n");
        return 2;
    }
    FILE *in = fopen(arguments[1], "r");
    if (in == NULL)
    {
        fprintf(stderr, "  exact_zeta_tail: %s does not open\n", arguments[1]);
        return 2;
    }
    unsigned int terms = 0u;
    unsigned int width = 0u;
    unsigned int fields = 0u;
    int read = (fscanf(in, "%u %u fields %u", &terms, &width, &fields) == 3) && (terms > 0u) && (fields == terms + 2u);
    std::vector<unsigned int> field_bits(fields);
    std::vector<unsigned int> field_offset(fields);
    for (unsigned int at = 0u; read && (at < fields); at += 1u)
    {
        read = fscanf(in, "%u %u", &field_bits[at], &field_offset[at]) == 2;
    }
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {0u, 0u, 0u};
    unsigned long long points = 0ull;
    read = read && (fscanf(in, " in_limbs %u %u points %llu", &in_limbs[0], &in_limbs[1], &points) == 3) &&
           (points > 0ull);
    std::vector<unsigned int> point_records(read ? (size_t)(points * in_limbs[0]) : 0u);
    std::vector<unsigned int> shared(read ? in_limbs[1] : 0u);
    for (unsigned long long at = 0ull; read && (at < points); at += 1ull)
    {
        read = tail_words(in, &point_records[(size_t)(at * in_limbs[0])], in_limbs[0]);
    }
    read = read && tail_words(in, shared.data(), in_limbs[1]);
    fclose(in);
    if (!read)
    {
        fprintf(stderr, "  exact_zeta_tail: %s is not an input this program reads\n", arguments[1]);
        return 2;
    }

    TailProgram program;
    unsigned int outputs[2];
    tail_build(&program, terms, width, outputs);
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineRecordKey key;
    memset(&key, 0, sizeof(key));
    const KeymathRecordRequest encode = {program.steps.data(), (unsigned int)program.steps.size(), field_bits.data(),
                                         fields, 2u, outputs, 2u, NULL, 0u, &key, &error};
    int ok = keymath_record_encode(&encode) != KEYMATH_ERROR;
    sim_check(&job, ok, "keymath imprints the tail program");
    EngineRecordLayout layout;
    memset(&layout, 0, sizeof(layout));
    const KeyScheduleRecordRequest lay = {&key, field_offset.data(), fields, in_limbs, 1, &layout, &error};
    ok = ok && (key_schedule_record_layout(&lay) != KEY_SCHEDULE_ERROR);
    sim_check(&job, ok, "the scheduler lays the tail program out");
    const unsigned int out_limbs = ok ? layout.out_limbs : 0u;
    const unsigned long long declared =
        points * (2ull * in_limbs[0] + 2ull + 2ull * out_limbs) * sizeof(unsigned int) +
        in_limbs[1] * sizeof(unsigned int) + layout.steps * sizeof(DeviceRecordStep);
    ok = ok && sim_job_submit(&job, "exact_zeta_tail", count, arguments, declared);
    CycleRecord *record = NULL;
    ok = ok && (cycle_record_load(&layout, &record, &error) != CYCLE_ERROR);
    sim_check(&job, ok, "the tail program loads onto the device");

    std::vector<unsigned int> index((size_t)(points * 2ull));
    for (unsigned long long lane = 0ull; lane < points; lane += 1ull)
    {
        index[(size_t)(2ull * lane)] = (unsigned int)lane;
        index[(size_t)(2ull * lane + 1ull)] = 0u;
    }
    std::vector<unsigned int> device_out((size_t)(points * out_limbs));
    std::vector<unsigned int> host_out((size_t)(points * out_limbs));
    unsigned int *device_points = NULL;
    unsigned int *device_shared = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_record = NULL;
    ok = ok && (cudaMalloc((void **)&device_points, point_records.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_shared, shared.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_index, index.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_record, device_out.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_points, point_records.data(), point_records.size() * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(device_shared, shared.data(), shared.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
          cudaSuccess) &&
         (cudaMemcpy(device_index, index.data(), index.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
          cudaSuccess);
    if (ok)
    {
        const CycleRecordRunRequest run = {record, {device_points, device_shared, NULL}, {points, 1ull, 0ull},
                                           device_index, points, device_record, &error};
        ok = (cycle_record_run(&run) == (long)points) &&
             (cudaMemcpy(device_out.data(), device_record, device_out.size() * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    sim_check(&job, ok, "the tail program sweeps every point on the device");
    const CycleRecordHostRequest host = {&layout, {point_records.data(), shared.data(), NULL}, {points, 1ull, 0ull},
                                         index.data(), points, host_out.data(), &error};
    const int host_ran = ok && (cycle_record_run_host(&host) == (long)points);
    const int same = host_ran && (memcmp(host_out.data(), device_out.data(), device_out.size() * sizeof(unsigned int)) == 0);
    sim_check(&job, same, "the device's records equal the host's word for word");

    FILE *out = ok ? fopen(arguments[2], "w") : NULL;
    if (out != NULL)
    {
        fprintf(out, "out_limbs %u\n", out_limbs);
        fprintf(out, "outputs %u %u %u %u\n", layout.step_table[outputs[0]].out_offset,
                layout.step_table[outputs[0]].out_bits, layout.step_table[outputs[1]].out_offset,
                layout.step_table[outputs[1]].out_bits);
        for (unsigned long long lane = 0ull; lane < points; lane += 1ull)
        {
            for (unsigned int limb = 0u; limb < out_limbs; limb += 1u)
            {
                fprintf(out, (limb == 0u) ? "%x" : " %x", device_out[(size_t)(lane * out_limbs + limb)]);
            }
            fprintf(out, "\n");
        }
        fprintf(out, "host %d\nsteps %u file_limbs %u compiled %d\n", same, layout.steps, layout.file_limbs,
                (record != NULL) ? cycle_record_compiled(record) : 0);
        fclose(out);
    }
    sim_check(&job, out != NULL, "the records are written out");

    cudaFree(device_points);
    cudaFree(device_shared);
    cudaFree(device_index);
    cudaFree(device_record);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    key_schedule_record_release(&layout);
    keymath_record_release(&key);
    return sim_close(&job, "exact_zeta_tail");
}
