// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Catalog: EXP-x-029
//
// Harish-Chandra's spherical function of SL(2, R) / SO(2), the hyperbolic plane the modular surface SL(2, Z)\H is a
// quotient of, by two routes, one lane a point (r, u) of a grid, swept on the device as one program of the record
// machine, one job on the device's tessera daemon.
//
//   Usage:  exact_zeta_spherical <input> <output>
//
// phi_r at distance d is the eigenfunction of the Laplacian with eigenvalue -(1/4 + r^2), radial about a point and
// 1 there. With u = sinh^2(d / 2), phi_r = 2F1(1/2 + i r, 1/2 - i r; 1; -u).
//
// Route one: the series in -u, whose coefficients prod over k < n of ((k + 1/2)^2 + r^2) / (n!)^2 are real and
// positive. Term n + 1 is term n times -u ((n + 1/2)^2 + r^2) / (n + 1)^2, an alternating series for u < 1.
//
// Route two: Pfaff's transformation, phi_r = (1 + u)^(-1/2) exp(-i r ln(1 + u)) 2F1(1/2 + i r, 1/2 + i r; 1; z),
// z = u / (1 + u), whose term n + 1 is term n times z (n + 1/2 + i r)^2 / (n + 1)^2, complex. ln(1 + u) is
// 2 artanh(u / (2 + u)) by Horner's rule; (1 + u)^(-1/2) is Newton's rule y (3 - w y^2) / 2 from 4/5, below the root
// for w <= 25/16; exp(i pi s) is cos(pi s) by Horner's rule in s^2 and sin(pi s) as cos(pi (s - 1/2)).
//
// The two routes are the same function: route two's real part is route one, and its imaginary part is 0.
//
// Lane l stands at r = (l / U) r_unit and u = (l mod U) u_unit, U the grid's count of u. Every value is an integer at
// the scale 2^62, and a product taken back to it divides by 2^31 twice, toward zero.
//
// The input, little-endian: 64-bit words lanes, checked, U, A, K, L1, L2, M, then the constants, each a 64-bit word
// count w, w 32-bit limbs of its magnitude least significant first, and a 64-bit sign word: u_unit, r_unit, 1 / pi,
// the A constants 1 / (2k + 1) of artanh and the K constants (-1)^k pi^(2k) / (2k)! of cos, every one at 2^62.
//
// The output: the line "out_limbs L", one line an output "output name offset bits", one line a lane of L hex limbs,
// least significant first, the line "host 1" where the host's records over the first `checked` lanes equal the
// device's word for word, else "host 0", and the line "steps P".

#include "../../src/c/engine/analysis/cycle/cycle.h"
#include "../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../src/c/engine/analysis/keymath/keymath.h"
#include "../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

// the scale every value is held at, and the half of it one division takes
#define SPHERICAL_SCALE_BITS 62u
#define SPHERICAL_HALF_BITS 31u
// every value taken back is below 2^95 in size at the scale, the wrap to this width passes it unchanged
#define SPHERICAL_HELD_BITS 96u
// the lanes, below 2^24
#define SPHERICAL_LANE_BITS 24u

typedef struct
{
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> field_bits;
    std::vector<unsigned int> field_offset;
    unsigned int shared_bits;
} SphericalProgram;

typedef struct
{
    unsigned int re;
    unsigned int im;
} SphericalComplex;

typedef struct
{
    std::vector<unsigned int> magnitude;
    long long sign;
    unsigned int bits;
} SphericalConstant;

typedef struct
{
    SphericalProgram program;
    std::vector<unsigned int> outputs;
    std::vector<std::string> names;
    std::vector<unsigned int> shared;
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    std::vector<unsigned int> records;
    int same;
} SphericalStage;

static unsigned int spherical_step(SphericalProgram *program, EngineRecordOperation operation, unsigned int left,
                                   unsigned int right)
{
    EngineRecordStep step = {operation, left, right, 0u};
    program->steps.push_back(step);
    return (unsigned int)program->steps.size() - 1u;
}

static unsigned int spherical_constant(SphericalProgram *program, unsigned long long value)
{
    return spherical_step(program, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull), (unsigned int)(value >> 32u));
}

static unsigned int spherical_field(SphericalProgram *program, unsigned int bits)
{
    const unsigned int field = (unsigned int)program->field_bits.size();
    program->field_bits.push_back(bits);
    program->field_offset.push_back(program->shared_bits);
    program->shared_bits += bits;
    return field;
}

static unsigned int spherical_read(SphericalProgram *program, unsigned int field)
{
    return spherical_step(program, ENGINE_RECORD_FIELD_SIGNED, field, 0u);
}

static unsigned int spherical_sum(SphericalProgram *program, unsigned int a, unsigned int b)
{
    return spherical_step(program, ENGINE_RECORD_SUM, a, b);
}

static unsigned int spherical_difference(SphericalProgram *program, unsigned int a, unsigned int b)
{
    return spherical_step(program, ENGINE_RECORD_DIFFERENCE, a, b);
}

static unsigned int spherical_wrap(SphericalProgram *program, unsigned int value, unsigned int bits)
{
    return spherical_step(program, ENGINE_RECORD_WRAP, value, bits);
}

// a product taken back to the scale: divided by 2^31 twice, toward zero, then wrapped to the width its value has
static unsigned int spherical_scaled(SphericalProgram *program, unsigned int a, unsigned int b)
{
    const unsigned int half = spherical_constant(program, 1ull << SPHERICAL_HALF_BITS);
    const unsigned int product = spherical_step(program, ENGINE_RECORD_PRODUCT, a, b);
    const unsigned int once = spherical_step(program, ENGINE_RECORD_QUOTIENT, product, half);
    return spherical_wrap(program, spherical_step(program, ENGINE_RECORD_QUOTIENT, once, half), SPHERICAL_HELD_BITS);
}

// a value divided by an integer, toward zero
static unsigned int spherical_divided(SphericalProgram *program, unsigned int value, unsigned long long by)
{
    return spherical_step(program, ENGINE_RECORD_QUOTIENT, value, spherical_constant(program, by));
}

// (2n + 1)^2 / 4 at the scale, (2n + 1)^2 times 2^60, a product of two constants that keeps every n's value whole
static unsigned int spherical_quarter(SphericalProgram *program, unsigned long long odd_square)
{
    return spherical_step(program, ENGINE_RECORD_PRODUCT, spherical_constant(program, odd_square),
                          spherical_constant(program, 1ull << (SPHERICAL_SCALE_BITS - 2u)));
}

static SphericalComplex spherical_cmul(SphericalProgram *program, SphericalComplex a, SphericalComplex b)
{
    SphericalComplex out;
    out.re = spherical_wrap(program, spherical_difference(program, spherical_scaled(program, a.re, b.re), spherical_scaled(program, a.im, b.im)),
                            SPHERICAL_HELD_BITS);
    out.im = spherical_wrap(program, spherical_sum(program, spherical_scaled(program, a.re, b.im), spherical_scaled(program, a.im, b.re)),
                            SPHERICAL_HELD_BITS);
    return out;
}

// Horner's rule in x over the fields' constants, the first the constant term
static unsigned int spherical_horner(SphericalProgram *program, unsigned int x, const std::vector<unsigned int> &fields)
{
    unsigned int acc = spherical_read(program, fields.back());
    for (size_t k = fields.size() - 1u; k > 0u; k -= 1u)
    {
        acc = spherical_sum(program, spherical_scaled(program, acc, x), spherical_read(program, fields[k - 1u]));
    }
    return acc;
}

// cos(pi s) and sin(pi s) for s in [-1, 1)
static SphericalComplex spherical_cis(SphericalProgram *program, unsigned int s, const std::vector<unsigned int> &cosine)
{
    SphericalComplex out;
    out.re = spherical_horner(program, spherical_scaled(program, s, s), cosine);
    const unsigned int shifted = spherical_wrap(
        program, spherical_difference(program, s, spherical_constant(program, 1ull << (SPHERICAL_SCALE_BITS - 1u))),
        SPHERICAL_SCALE_BITS + 1u);
    out.im = spherical_horner(program, spherical_scaled(program, shifted, shifted), cosine);
    return out;
}

// the program: fields U, u_unit, r_unit, 1 / pi, the artanh constants and the cos constants; outputs route one, and
// route two's real and imaginary parts
static void spherical_build(SphericalStage *stage, unsigned int artanh_terms, unsigned int cos_terms, unsigned int first_terms,
                            unsigned int second_terms, unsigned int newton, const std::vector<unsigned int> &constant_bits)
{
    SphericalProgram *const program = &stage->program;
    const unsigned int count_field = spherical_field(program, SPHERICAL_LANE_BITS + 2u);
    const unsigned int u_field = spherical_field(program, constant_bits[0]);
    const unsigned int r_field = spherical_field(program, constant_bits[1]);
    const unsigned int inv_pi_field = spherical_field(program, constant_bits[2]);
    std::vector<unsigned int> artanh, cosine;
    for (unsigned int k = 0u; k < artanh_terms; k += 1u)
    {
        artanh.push_back(spherical_field(program, constant_bits[3u + k]));
    }
    for (unsigned int k = 0u; k < cos_terms; k += 1u)
    {
        cosine.push_back(spherical_field(program, constant_bits[3u + artanh_terms + k]));
    }
    const unsigned int unit = spherical_constant(program, 1ull << SPHERICAL_SCALE_BITS);
    const unsigned int lane = spherical_step(program, ENGINE_RECORD_AND, spherical_step(program, ENGINE_RECORD_LANE, 0u, 0u),
                                             spherical_constant(program, (1ull << SPHERICAL_LANE_BITS) - 1ull));
    const unsigned int count = spherical_read(program, count_field);
    const unsigned int u = spherical_step(program, ENGINE_RECORD_PRODUCT, spherical_step(program, ENGINE_RECORD_REMAINDER, lane, count),
                                          spherical_read(program, u_field));
    const unsigned int r = spherical_step(program, ENGINE_RECORD_PRODUCT, spherical_step(program, ENGINE_RECORD_QUOTIENT, lane, count),
                                          spherical_read(program, r_field));
    const unsigned int r2 = spherical_scaled(program, r, r);

    // route one: term n + 1 = -term n u ((n + 1/2)^2 + r^2) / (n + 1)^2
    unsigned int term = unit;
    unsigned int first = unit;
    for (unsigned int n = 0u; n + 1u < first_terms; n += 1u)
    {
        const unsigned long long quarter = (unsigned long long)(2u * n + 1u) * (2u * n + 1u);
        const unsigned int weight = spherical_sum(program, spherical_quarter(program, quarter), r2);
        const unsigned int grown = spherical_scaled(program, spherical_scaled(program, term, u), weight);
        term = spherical_difference(program, spherical_constant(program, 0ull),
                                    spherical_divided(program, grown, (unsigned long long)(n + 1u) * (n + 1u)));
        first = spherical_sum(program, first, term);
    }

    // route two: z = u / (1 + u), term n + 1 = term n z (n + 1/2 + i r)^2 / (n + 1)^2
    const unsigned int one_more = spherical_sum(program, unit, u);
    const unsigned int z = spherical_step(program, ENGINE_RECORD_QUOTIENT, spherical_step(program, ENGINE_RECORD_PRODUCT, u, unit), one_more);
    SphericalComplex step_term = {unit, spherical_constant(program, 0ull)};
    SphericalComplex second = step_term;
    for (unsigned int n = 0u; n + 1u < second_terms; n += 1u)
    {
        const unsigned long long quarter = (unsigned long long)(2u * n + 1u) * (2u * n + 1u);
        SphericalComplex square;
        square.re = spherical_difference(program, spherical_quarter(program, quarter), r2);
        square.im = spherical_step(program, ENGINE_RECORD_PRODUCT, r, spherical_constant(program, 2ull * n + 1ull));
        const SphericalComplex grown = spherical_cmul(program, step_term, square);
        step_term.re = spherical_divided(program, spherical_scaled(program, grown.re, z), (unsigned long long)(n + 1u) * (n + 1u));
        step_term.im = spherical_divided(program, spherical_scaled(program, grown.im, z), (unsigned long long)(n + 1u) * (n + 1u));
        second.re = spherical_sum(program, second.re, step_term.re);
        second.im = spherical_sum(program, second.im, step_term.im);
    }
    // ln(1 + u) = 2 artanh(y), y = u / (2 + u)
    const unsigned int y = spherical_step(program, ENGINE_RECORD_QUOTIENT, spherical_step(program, ENGINE_RECORD_PRODUCT, u, unit),
                                          spherical_sum(program, one_more, unit));
    const unsigned int series = spherical_horner(program, spherical_scaled(program, y, y), artanh);
    const unsigned int half_log = spherical_scaled(program, series, y);
    const unsigned int log = spherical_sum(program, half_log, half_log);
    // (1 + u)^(-1/2) by Newton's rule from 4/5
    unsigned int root = spherical_constant(program, ((1ull << SPHERICAL_SCALE_BITS) / 5ull) * 4ull);
    for (unsigned int k = 0u; k < newton; k += 1u)
    {
        const unsigned int w_y2 = spherical_scaled(program, one_more, spherical_scaled(program, root, root));
        root = spherical_divided(program, spherical_scaled(program, root, spherical_difference(program, spherical_constant(program, 3ull << SPHERICAL_SCALE_BITS), w_y2)),
                                 2ull);
    }
    // exp(-i r ln(1 + u)), the angle over pi taken modulo 2
    const unsigned int turn = spherical_wrap(
        program, spherical_difference(program, spherical_constant(program, 0ull),
                                      spherical_scaled(program, spherical_scaled(program, r, log), spherical_read(program, inv_pi_field))),
        SPHERICAL_SCALE_BITS + 1u);
    const SphericalComplex around = spherical_cis(program, turn, cosine);
    const SphericalComplex turned = spherical_cmul(program, around, second);
    stage->outputs.push_back(spherical_wrap(program, first, SPHERICAL_HELD_BITS));
    stage->names.push_back("first");
    stage->outputs.push_back(spherical_scaled(program, turned.re, root));
    stage->names.push_back("second_re");
    stage->outputs.push_back(spherical_scaled(program, turned.im, root));
    stage->names.push_back("second_im");
}

static int spherical_word(FILE *in, long long *value)
{
    return fread(value, sizeof(long long), 1u, in) == 1u;
}

static int spherical_read_constant(FILE *in, SphericalConstant *constant)
{
    long long limbs = 0;
    int read = spherical_word(in, &limbs) && (limbs >= 0) && (limbs < 4096);
    constant->magnitude.assign(read ? (size_t)limbs : 0u, 0u);
    read = read && (fread(constant->magnitude.data(), sizeof(unsigned int), constant->magnitude.size(), in) ==
                    constant->magnitude.size());
    read = read && spherical_word(in, &constant->sign);
    unsigned int width = 32u * (unsigned int)constant->magnitude.size();
    while ((width > 0u) && (((constant->magnitude[(width - 1u) / 32u] >> ((width - 1u) % 32u)) & 1u) == 0u))
    {
        width -= 1u;
    }
    constant->bits = width + 1u;
    return read;
}

// `bits` of a two's complement value, its magnitude's limbs given, laid at `offset` of `record`
static void spherical_put(unsigned int *record, unsigned int offset, unsigned int bits, const std::vector<unsigned int> &limbs,
                          long long sign)
{
    std::vector<unsigned int> word((bits + 31u) / 32u + 1u, 0u);
    for (size_t at = 0u; at < limbs.size() && at < word.size(); at += 1u)
    {
        word[at] = limbs[at];
    }
    if (sign < 0)
    {
        unsigned long long carry = 1ull;
        for (size_t at = 0u; at < word.size(); at += 1u)
        {
            carry += (unsigned long long)(~word[at] & 0xFFFFFFFFu);
            word[at] = (unsigned int)carry;
            carry >>= 32u;
        }
    }
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int to = offset + bit;
        const unsigned int value = (word[bit / 32u] >> (bit % 32u)) & 1u;
        record[to / 32u] = (record[to / 32u] & ~(1u << (to % 32u))) | (value << (to % 32u));
    }
}

// imprints, lays out and loads the program, runs every lane, and holds the host's first `checked` records against the
// device's
static int spherical_sweep(SimResults *job, SphericalStage *stage, unsigned long long lanes, unsigned long long checked,
                           EngineError *error, int count, char **arguments)
{
    SphericalProgram *const program = &stage->program;
    const unsigned int fields = (unsigned int)program->field_bits.size();
    const KeymathRecordRequest encode = {program->steps.data(), (unsigned int)program->steps.size(), program->field_bits.data(),
                                         fields, 1u, stage->outputs.data(), (unsigned int)stage->outputs.size(), NULL, 0u,
                                         &stage->key, error};
    int ok = keymath_record_encode(&encode) != KEYMATH_ERROR;
    sim_check(job, ok, "keymath imprints the spherical program");
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {(unsigned int)stage->shared.size(), 0u, 0u};
    const KeyScheduleRecordRequest lay = {&stage->key, program->field_offset.data(), fields, in_limbs, 1, &stage->layout, error};
    ok = ok && (key_schedule_record_layout(&lay) != KEY_SCHEDULE_ERROR);
    sim_check(job, ok, "the scheduler lays the spherical program out");
    const unsigned int out_limbs = ok ? stage->layout.out_limbs : 0u;
    const unsigned long long declared = (lanes * out_limbs + stage->shared.size()) * sizeof(unsigned int) + (64ull << 20u);
    ok = ok && sim_job_submit(job, "exact_zeta_spherical", count, arguments, declared);
    ok = ok && (cycle_record_load(&stage->layout, &stage->record, error) != CYCLE_ERROR);
    sim_check(job, ok, "the spherical program loads onto the device");
    unsigned int *device_shared = NULL;
    unsigned int *device_out = NULL;
    ok = ok && (cudaMalloc((void **)&device_shared, stage->shared.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_out, lanes * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_shared, stage->shared.data(), stage->shared.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
          cudaSuccess);
    const CycleRecordRunRequest run = {stage->record, {device_shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes, device_out, error};
    ok = ok && (cycle_record_run(&run) == (long)lanes);
    sim_check(job, ok, "every lane of the grid runs on the device");
    stage->records.assign((size_t)(ok ? lanes * out_limbs : 0ull), 0u);
    ok = ok && (cudaMemcpy(stage->records.data(), device_out, stage->records.size() * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    std::vector<unsigned int> host_out((size_t)(checked * out_limbs));
    const CycleRecordHostRequest host = {&stage->layout, {stage->shared.data(), NULL, NULL}, {1ull, 0ull, 0ull}, NULL,
                                         checked,        host_out.data(),                     error};
    stage->same = ok && (cycle_record_run_host(&host) == (long)checked) &&
                  (memcmp(host_out.data(), stage->records.data(), host_out.size() * sizeof(unsigned int)) == 0);
    sim_check(job, stage->same, "the host's records equal the device's word for word");
    cudaFree(device_shared);
    cudaFree(device_out);
    return ok;
}

int main(int count, char **arguments)
{
    SimResults job;
    char job_capacity[SIM_LINE_CAPACITY];
    sim_open(&job, job_capacity);
    if (count != 3)
    {
        fprintf(stderr, "  usage: exact_zeta_spherical <input> <output>\n");
        return 2;
    }
    FILE *in = fopen(arguments[1], "rb");
    long long header[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    int read = (in != NULL);
    for (unsigned int at = 0u; read && (at < 8u); at += 1u)
    {
        read = spherical_word(in, &header[at]);
    }
    read = read && (header[0] > 0) && (header[0] < (1ll << SPHERICAL_LANE_BITS)) && (header[1] > 0) && (header[1] <= header[0]) &&
           (header[2] > 0) && ((header[0] % header[2]) == 0) && (header[3] >= 2) && (header[3] < 256) && (header[4] >= 2) &&
           (header[4] < 256) && (header[5] >= 2) && (header[5] < 4096) && (header[6] >= 2) && (header[6] < 4096) &&
           (header[7] >= 1) && (header[7] < 64);
    const unsigned long long lanes = read ? (unsigned long long)header[0] : 0ull;
    const unsigned long long checked = read ? (unsigned long long)header[1] : 0ull;
    const unsigned int artanh_terms = read ? (unsigned int)header[3] : 0u;
    const unsigned int cos_terms = read ? (unsigned int)header[4] : 0u;
    std::vector<SphericalConstant> constants(read ? 3u + artanh_terms + cos_terms : 0u);
    for (size_t k = 0u; read && (k < constants.size()); k += 1u)
    {
        read = spherical_read_constant(in, &constants[k]);
    }
    if (in != NULL)
    {
        fclose(in);
    }
    if (!read)
    {
        fprintf(stderr, "  exact_zeta_spherical: %s is not an input this program reads\n", arguments[1]);
        return 2;
    }

    EngineError error;
    memset(&error, 0, sizeof(error));
    SphericalStage stage;
    stage.program.shared_bits = 0u;
    memset(&stage.key, 0, sizeof(stage.key));
    memset(&stage.layout, 0, sizeof(stage.layout));
    stage.record = NULL;
    stage.same = 0;
    std::vector<unsigned int> bits;
    for (size_t k = 0u; k < constants.size(); k += 1u)
    {
        bits.push_back(constants[k].bits);
    }
    spherical_build(&stage, artanh_terms, cos_terms, (unsigned int)header[5], (unsigned int)header[6], (unsigned int)header[7], bits);
    stage.shared.assign((stage.program.shared_bits + 31u) / 32u + 1u, 0u);
    const std::vector<unsigned int> grid = {(unsigned int)header[2], 0u};
    spherical_put(stage.shared.data(), stage.program.field_offset[0], stage.program.field_bits[0], grid, 1);
    for (size_t k = 0u; k < constants.size(); k += 1u)
    {
        spherical_put(stage.shared.data(), stage.program.field_offset[1u + k], stage.program.field_bits[1u + k],
                      constants[k].magnitude, constants[k].sign);
    }
    int ok = spherical_sweep(&job, &stage, lanes, checked, &error, count, arguments);

    FILE *out = ok ? fopen(arguments[2], "w") : NULL;
    if (out != NULL)
    {
        const unsigned int out_limbs = stage.layout.out_limbs;
        fprintf(out, "out_limbs %u\n", out_limbs);
        for (size_t at = 0u; at < stage.outputs.size(); at += 1u)
        {
            const DeviceRecordStep *const place = &stage.layout.step_table[stage.outputs[at]];
            fprintf(out, "output %s %u %u\n", stage.names[at].c_str(), place->out_offset, place->out_bits);
        }
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            for (unsigned int limb = 0u; limb < out_limbs; limb += 1u)
            {
                fprintf(out, (limb == 0u) ? "%x" : " %x", stage.records[(size_t)(lane * out_limbs + limb)]);
            }
            fprintf(out, "\n");
        }
        fprintf(out, "host %d\nsteps %u\n", stage.same, stage.layout.steps);
        fclose(out);
    }
    sim_check(&job, out != NULL, "the records are written out");
    if (stage.record != NULL)
    {
        cycle_record_release(stage.record);
    }
    key_schedule_record_release(&stage.layout);
    keymath_record_release(&stage.key);
    return sim_close(&job, "exact_zeta_spherical");
}
