// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Catalog: EXP-x-027
//
// The curves R holds at every point of a cell, and the logarithm the phase turns by, one lane a point, swept on the
// device as two programs of the record machine, one job on the device's tessera daemon. Every value is a mantissa in a
// register and a binary exponent the program holds: a product multiplies the mantissas and adds the exponents, a power
// of two is where a mantissa is laid in the record, and nothing is divided.
//
//   Usage:  exact_zeta_lobes <input> <output>
//
// Lane l stands at x = nu + l / 2^b, X = nu 2^b + l, and z = 1 - 2p = Zt / 2^b with Zt = 2^b - 2l. C_n(z) is
// sum over j of g_(n,j) z^j, each g a mantissa at the exponent -E, read by Horner's rule as the integer
// H_n = sum over j of g_(n,j) Zt^j 2^(b (J_n - 1 - j)) at the exponent -(E + b (J_n - 1)). The record holds each
// g_(n,j) 2^(b (J_n - 1 - j)), the mantissa laid b (J_n - 1 - j) bits up with zeros below, and each step of Horner's
// rule is then one product by Zt and one sum. With the sign s = (-1)^(nu - 1),
// the curve n's part of R x^(1/2) is s C_n(z) x^(-n) = s H_n 2^(b n) / X^n, and over the common denominator X^K every
// curve is the integer T_n = s H_n 2^(b n) X^(K - n), each at its own exponent, each held as an output.
//
// The logarithm: ln(x / m) = ln(nu / m) + A for every m, with A = ln(X / (nu 2^b)) = 2 artanh(l / D) and
// D = X + nu 2^b: one series a lane serves every term of the main sum, and ln(nu / m) is the cell's constant. With
// c_k = Lambda / (2k + 1), Lambda the least common multiple of the odd numbers below 2L, the first L terms of the
// series are 2 l S / (Lambda D^(2L - 1)) with S = sum over k < L of c_k l^(2k) D^(2(L - 1 - k)), an integer read by
// Horner's rule in l^2 against the powers of D^2. Every term is positive and each is below (l / D)^2 times the one
// before it: the tail past the last term is positive and below 2 l^(2L + 1) / ((2L + 1) D^(2L - 1) (D^2 - l^2)):
// A lies at or above the first quotient and below the first plus the second, and the stage holds the four integers
// l S, D^(2L - 1), l^(2L + 1) and D^2 - l^2 as its outputs.
//
// The input, little-endian: 64-bit words lanes, checked, nu, b, K, E, L, then K + 1 words J_n, then the mantissas
// g_(n,j), then the L constants c_k, each a 64-bit word count w and w 32-bit limbs of its magnitude least significant
// first, and a 64-bit sign word, -1, 0 or 1.
//
// The output, a stage at a time, R's curves and then the logarithm: the line "stage name out_limbs L", one line an
// output "output name offset bits exponent", one line a lane of L hex limbs, least significant first, the line
// "host 1" where the host's records over the first `checked` lanes equal the device's word for word, else "host 0",
// and the line "steps P compiled C".

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

typedef struct
{
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> field_bits;
    std::vector<unsigned int> field_offset;
    unsigned int shared_bits;
} LobesProgram;

// a value: the register holding its mantissa and the binary exponent the program holds for it
typedef struct
{
    unsigned int reg;
    long long exponent;
} LobesReal;

// a program, the outputs it lists with their names and exponents, its shared record, and what the device made of it
typedef struct
{
    const char *name;
    LobesProgram program;
    std::vector<unsigned int> outputs;
    std::vector<std::string> names;
    std::vector<long long> exponents;
    std::vector<unsigned int> shared;
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    std::vector<unsigned int> records;
    int same;
} LobesStage;

static unsigned int lobes_step(LobesProgram *program, EngineRecordOperation operation, unsigned int left,
                               unsigned int right, unsigned int member)
{
    EngineRecordStep step = {operation, left, right, member};
    program->steps.push_back(step);
    return (unsigned int)program->steps.size() - 1u;
}

static unsigned int lobes_constant(LobesProgram *program, unsigned long long value)
{
    return lobes_step(program, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull), (unsigned int)(value >> 32u),
                      0u);
}

// a field of the shared record, `bits` wide and signed, laid at the record's next bit; the step that reads it is
// written where it is read, and the register is live only from there to its reader
static unsigned int lobes_field(LobesProgram *program, unsigned int bits)
{
    const unsigned int field = (unsigned int)program->field_bits.size();
    program->field_bits.push_back(bits);
    program->field_offset.push_back(program->shared_bits);
    program->shared_bits += bits;
    return field;
}

static unsigned int lobes_read(LobesProgram *program, unsigned int field)
{
    return lobes_step(program, ENGINE_RECORD_FIELD_SIGNED, field, 0u, 0u);
}

static void lobes_output(LobesStage *stage, const std::string &name, unsigned int step, long long exponent)
{
    stage->outputs.push_back(step);
    stage->names.push_back(name);
    stage->exponents.push_back(exponent);
}

// the lane, at most 2^b, and the and with 2^(b + 1) - 1 gives its register that width and keeps its value
static unsigned int lobes_lane(LobesProgram *program, unsigned int b)
{
    const unsigned int counted = lobes_step(program, ENGINE_RECORD_LANE, 0u, 0u, 0u);
    return lobes_step(program, ENGINE_RECORD_AND, counted, lobes_constant(program, (2ull << b) - 1ull), 0u);
}

// the curves: T_n for n from 0 to K over the denominator X^K, from the mantissas' widths gamma_bits[n][j]
static void lobes_build(LobesStage *stage, unsigned int b, long long big_e,
                        const std::vector<std::vector<unsigned int>> &gamma_bits)
{
    LobesProgram *const program = &stage->program;
    program->shared_bits = 0u;
    const unsigned int sign_field = lobes_field(program, 2u);
    // nu 2^b, read from the record at a width b alone sets: one program serves every cell up to nu = 127
    const unsigned int floor_field = lobes_field(program, b + 8u);
    std::vector<std::vector<unsigned int>> gamma(gamma_bits.size());
    for (size_t n = 0u; n < gamma_bits.size(); n += 1u)
    {
        const unsigned int count = (unsigned int)gamma_bits[n].size();
        for (unsigned int j = 0u; j < count; j += 1u)
        {
            gamma[n].push_back(lobes_field(program, gamma_bits[n][j] + b * (count - 1u - j)));
        }
    }
    const unsigned int lane = lobes_lane(program, b);
    const unsigned int big_x = lobes_step(program, ENGINE_RECORD_SUM, lane, lobes_read(program, floor_field), 0u);
    const unsigned int doubled = lobes_step(program, ENGINE_RECORD_SUM, lane, lane, 0u);
    const unsigned int zt = lobes_step(program, ENGINE_RECORD_DIFFERENCE, lobes_constant(program, 1ull << b), doubled, 0u);
    const LobesReal z = {zt, -(long long)b};
    const unsigned int curves = (unsigned int)gamma.size();
    const unsigned int top = curves - 1u;
    std::vector<unsigned int> x_power(curves);
    x_power[0] = lobes_constant(program, 1ull);
    for (unsigned int n = 1u; n < curves; n += 1u)
    {
        x_power[n] = lobes_step(program, ENGINE_RECORD_PRODUCT, x_power[n - 1u], big_x, 0u);
    }
    for (unsigned int n = 0u; n < curves; n += 1u)
    {
        const unsigned int count = (unsigned int)gamma[n].size();
        unsigned int acc = lobes_read(program, gamma[n][count - 1u]);
        for (unsigned int j = count - 1u; j > 0u; j -= 1u)
        {
            const unsigned int turned = lobes_step(program, ENGINE_RECORD_PRODUCT, acc, z.reg, 0u);
            acc = lobes_step(program, ENGINE_RECORD_SUM, turned, lobes_read(program, gamma[n][j - 1u]), 0u);
        }
        const LobesReal held = {acc, -big_e - (long long)b * (long long)(count - 1u)};
        // s H_n 2^(b n) X^(K - n): the 2^(b n) is the exponent's, the rest the mantissa's
        const unsigned int sign = lobes_read(program, sign_field);
        const unsigned int signed_h = lobes_step(program, ENGINE_RECORD_PRODUCT, held.reg, sign, 0u);
        lobes_output(stage, "curve" + std::to_string(n),
                     lobes_step(program, ENGINE_RECORD_PRODUCT, signed_h, x_power[top - n], 0u),
                     held.exponent + (long long)b * n);
    }
    lobes_output(stage, "denominator", x_power[top], 0);
}

// the logarithm: l S, D^(2L - 1), l^(2L + 1) and D^2 - l^2, from the widths of the constants c_k. Every power of D
// is as wide as the field nu 2^b is read at. The field is as wide as nu's own bits set, and one program serves every
// nu of that many bits
static void lobes_log_build(LobesStage *stage, unsigned int b, unsigned int nu_bits, const std::vector<unsigned int> &c_bits)
{
    LobesProgram *const program = &stage->program;
    program->shared_bits = 0u;
    const unsigned int floor_field = lobes_field(program, b + nu_bits + 1u);
    const unsigned int terms = (unsigned int)c_bits.size();
    std::vector<unsigned int> c(terms);
    for (unsigned int k = 0u; k < terms; k += 1u)
    {
        c[k] = lobes_field(program, c_bits[k]);
    }
    const unsigned int lane = lobes_lane(program, b);
    const unsigned int big_x = lobes_step(program, ENGINE_RECORD_SUM, lane, lobes_read(program, floor_field), 0u);
    const unsigned int big_d = lobes_step(program, ENGINE_RECORD_SUM, big_x, lobes_read(program, floor_field), 0u);
    const unsigned int u = lobes_step(program, ENGINE_RECORD_PRODUCT, lane, lane, 0u);
    const unsigned int v = lobes_step(program, ENGINE_RECORD_PRODUCT, big_d, big_d, 0u);
    // Horner's rule from c_(L-1) down: the step that adds c_(k-1) turns the sum by l^2 and lays c_(k-1) at D^(2(L - k))
    unsigned int acc = lobes_read(program, c[terms - 1u]);
    unsigned int v_power = v;
    for (unsigned int k = terms - 1u; k > 0u; k -= 1u)
    {
        const unsigned int turned = lobes_step(program, ENGINE_RECORD_PRODUCT, acc, u, 0u);
        const unsigned int laid = lobes_step(program, ENGINE_RECORD_PRODUCT, lobes_read(program, c[k - 1u]), v_power, 0u);
        acc = lobes_step(program, ENGINE_RECORD_SUM, turned, laid, 0u);
        if (k > 1u)
        {
            v_power = lobes_step(program, ENGINE_RECORD_PRODUCT, v_power, v, 0u);
        }
    }
    lobes_output(stage, "numerator", lobes_step(program, ENGINE_RECORD_PRODUCT, lane, acc, 0u), 0);
    lobes_output(stage, "power", lobes_step(program, ENGINE_RECORD_PRODUCT, big_d, v_power, 0u), 0);
    unsigned int tail = lane;
    for (unsigned int k = 0u; k < terms; k += 1u)
    {
        tail = lobes_step(program, ENGINE_RECORD_PRODUCT, tail, u, 0u);
    }
    lobes_output(stage, "tail", tail, 0);
    lobes_output(stage, "gap", lobes_step(program, ENGINE_RECORD_DIFFERENCE, v, u, 0u), 0);
}

static int lobes_word(FILE *in, long long *value)
{
    return fread(value, sizeof(long long), 1u, in) == 1u;
}

// a mantissa of the input: its magnitude's limbs, its sign, and the signed width that holds it
static int lobes_mantissa(FILE *in, std::vector<unsigned int> *magnitude, long long *sign, unsigned int *bits)
{
    long long limbs = 0;
    int read = lobes_word(in, &limbs) && (limbs >= 0) && (limbs < (1 << 20));
    magnitude->assign(read ? (size_t)limbs : 0u, 0u);
    read = read && (fread(magnitude->data(), sizeof(unsigned int), magnitude->size(), in) == magnitude->size());
    read = read && lobes_word(in, sign);
    unsigned int width = 32u * (unsigned int)magnitude->size();
    while ((width > 0u) && ((((*magnitude)[(width - 1u) / 32u] >> ((width - 1u) % 32u)) & 1u) == 0u))
    {
        width -= 1u;
    }
    *bits = width + 1u;
    return read;
}

// a magnitude's limbs moved `shift` bits up, zeros below
static std::vector<unsigned int> lobes_shifted(const std::vector<unsigned int> &limbs, unsigned int shift)
{
    std::vector<unsigned int> out(limbs.size() + shift / 32u + 1u, 0u);
    for (size_t at = 0u; at < limbs.size(); at += 1u)
    {
        const unsigned long long moved = (unsigned long long)limbs[at] << (shift % 32u);
        out[at + shift / 32u] |= (unsigned int)moved;
        out[at + shift / 32u + 1u] |= (unsigned int)(moved >> 32u);
    }
    return out;
}

// `bits` of a two's complement value, its magnitude's limbs given, laid into the record at `offset`
static void lobes_put(unsigned int *record, unsigned int offset, unsigned int bits, const std::vector<unsigned int> &limbs,
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
            const unsigned int flipped = ~word[at];
            carry += (unsigned long long)flipped;
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

// the record a stage's fields are laid into, sized to them
static void lobes_open_shared(LobesStage *stage)
{
    stage->shared.assign((stage->program.shared_bits + 31u) / 32u + 1u, 0u);
}

// nu 2^b into the stage's field `field`
static void lobes_put_floor(LobesStage *stage, unsigned int field, unsigned long long nu, unsigned int b)
{
    const unsigned long long floor_value = nu << b;
    const std::vector<unsigned int> floor_limbs = {(unsigned int)floor_value, (unsigned int)(floor_value >> 32u)};
    lobes_put(stage->shared.data(), stage->program.field_offset[field], stage->program.field_bits[field], floor_limbs, 1);
}

static void lobes_open_stage(LobesStage *stage, const char *name)
{
    stage->name = name;
    memset(&stage->key, 0, sizeof(stage->key));
    memset(&stage->layout, 0, sizeof(stage->layout));
    stage->record = NULL;
    stage->same = 0;
}

// imprints and lays out a stage's program, and says where the imprint stops when it does
static int lobes_lay(SimResults *job, LobesStage *stage, EngineError *error)
{
    LobesProgram *const program = &stage->program;
    const unsigned int fields = (unsigned int)program->field_bits.size();
    const KeymathRecordRequest encode = {program->steps.data(), (unsigned int)program->steps.size(),
                                         program->field_bits.data(),
                                         fields,
                                         1u,
                                         stage->outputs.data(),
                                         (unsigned int)stage->outputs.size(),
                                         NULL,
                                         0u,
                                         &stage->key,
                                         error};
    int ok = keymath_record_encode(&encode) != KEYMATH_ERROR;
    if (!ok)
    {
        const EngineRecordStep *const first = program->steps.data();
        const EngineRecordStep *const last = first + program->steps.size();
        const EngineRecordStep *const at = (const EngineRecordStep *)error->evacaddr;
        const long long step = ((at >= first) && (at < last)) ? (long long)(at - first) : -1;
        fprintf(stderr,
                "  exact_zeta_lobes: the %s imprint errors, site %u, at step %lld of %zu, operation %d left %u right %u\n",
                stage->name, error->site, step, program->steps.size(), (step >= 0) ? (int)at->operation : -1,
                (step >= 0) ? at->left : 0u, (step >= 0) ? at->right : 0u);
    }
    sim_check(job, ok, (std::string("keymath imprints the ") + stage->name + " program").c_str());
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {(program->shared_bits + 31u) / 32u, 0u, 0u};
    const KeyScheduleRecordRequest lay = {&stage->key, program->field_offset.data(), fields, in_limbs, 1, &stage->layout,
                                          error};
    const int laid = ok && (key_schedule_record_layout(&lay) != KEY_SCHEDULE_ERROR);
    if (ok && !laid)
    {
        const char *const end = (error->evacaddr == (const void *)&stage->key)       ? "the register file"
                                : (error->evacaddr == (const void *)stage->key.output) ? "the outputs"
                                                                                        : "a step";
        const long long step = (end[0] == 'a') ? (long long)((const EngineRecordTerm *)error->evacaddr - stage->key.term)
                                               : -1;
        fprintf(stderr, "  exact_zeta_lobes: the %s layout ends at %s, step %lld of %zu\n", stage->name, end, step,
                program->steps.size());
    }
    ok = laid;
    sim_check(job, ok, (std::string("the scheduler lays the ") + stage->name + " program out").c_str());
    stage->shared.resize((program->shared_bits + 31u) / 32u);
    return ok;
}

// the bytes a stage holds on the device over `lanes` lanes
static unsigned long long lobes_declared(const LobesStage *stage, unsigned long long lanes)
{
    return lanes * stage->layout.out_limbs * sizeof(unsigned int) + stage->shared.size() * sizeof(unsigned int) +
           (unsigned long long)stage->layout.steps * sizeof(DeviceRecordStep);
}

// loads a stage onto the device, runs every lane, and holds the host's first `checked` records against the device's
static int lobes_sweep(SimResults *job, LobesStage *stage, unsigned long long lanes, unsigned long long checked,
                       EngineError *error)
{
    const std::string name(stage->name);
    int ok = cycle_record_load(&stage->layout, &stage->record, error) != CYCLE_ERROR;
    sim_check(job, ok, ("the " + name + " program loads onto the device").c_str());
    const unsigned int out_limbs = stage->layout.out_limbs;
    unsigned int *device_shared = NULL;
    unsigned int *device_out = NULL;
    ok = ok && (cudaMalloc((void **)&device_shared, stage->shared.size() * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_out, lanes * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMemcpy(device_shared, stage->shared.data(), stage->shared.size() * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    const CycleRecordRunRequest run = {stage->record, {device_shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes,
                                       device_out, error};
    ok = ok && (cycle_record_run(&run) == (long)lanes);
    sim_check(job, ok, ("every lane of the cell runs the " + name + " program on the device").c_str());
    stage->records.assign((size_t)(ok ? lanes * out_limbs : 0ull), 0u);
    ok = ok && (cudaMemcpy(stage->records.data(), device_out, stage->records.size() * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    std::vector<unsigned int> host_out((size_t)(checked * out_limbs));
    const CycleRecordHostRequest host = {&stage->layout, {stage->shared.data(), NULL, NULL}, {1ull, 0ull, 0ull}, NULL,
                                         checked,        host_out.data(),                     error};
    stage->same = ok && (cycle_record_run_host(&host) == (long)checked) &&
                  (memcmp(host_out.data(), stage->records.data(), host_out.size() * sizeof(unsigned int)) == 0);
    sim_check(job, stage->same, ("the host's " + name + " records equal the device's word for word").c_str());
    cudaFree(device_shared);
    cudaFree(device_out);
    return ok;
}

static void lobes_write(FILE *out, const LobesStage *stage, unsigned long long lanes)
{
    const unsigned int out_limbs = stage->layout.out_limbs;
    fprintf(out, "stage %s out_limbs %u\n", stage->name, out_limbs);
    for (size_t at = 0u; at < stage->outputs.size(); at += 1u)
    {
        const DeviceRecordStep *const step = &stage->layout.step_table[stage->outputs[at]];
        fprintf(out, "output %s %u %u %lld\n", stage->names[at].c_str(), step->out_offset, step->out_bits,
                stage->exponents[at]);
    }
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        for (unsigned int limb = 0u; limb < out_limbs; limb += 1u)
        {
            fprintf(out, (limb == 0u) ? "%x" : " %x", stage->records[(size_t)(lane * out_limbs + limb)]);
        }
        fprintf(out, "\n");
    }
    fprintf(out, "host %d\nsteps %u compiled %d\n", stage->same, stage->layout.steps,
            (stage->record != NULL) ? cycle_record_compiled(stage->record) : 0);
}

static void lobes_release(LobesStage *stage)
{
    if (stage->record != NULL)
    {
        cycle_record_release(stage->record);
    }
    key_schedule_record_release(&stage->layout);
    keymath_record_release(&stage->key);
}

int main(int count, char **arguments)
{
    SimResults job;
    char job_capacity[SIM_LINE_CAPACITY];
    sim_open(&job, job_capacity);
    if (count != 3)
    {
        fprintf(stderr, "  usage: exact_zeta_lobes <input> <output>\n");
        return 2;
    }
    FILE *in = fopen(arguments[1], "rb");
    long long header[7] = {0, 0, 0, 0, 0, 0, 0};
    int read = (in != NULL);
    for (unsigned int at = 0u; read && (at < 7u); at += 1u)
    {
        read = lobes_word(in, &header[at]);
    }
    read = read && (header[0] > 0) && (header[1] > 0) && (header[1] <= header[0]) && (header[2] > 0) &&
           (header[2] < 128) && (header[3] > 0) && (header[3] <= 48) && (header[0] <= (2ll << header[3])) &&
           (header[4] >= 0) && (header[5] >= 0) && (header[6] >= 2) && (header[6] < 4096);
    const unsigned long long lanes = read ? (unsigned long long)header[0] : 0ull;
    const unsigned long long checked = read ? (unsigned long long)header[1] : 0ull;
    const unsigned long long nu = read ? (unsigned long long)header[2] : 0ull;
    const unsigned int b = read ? (unsigned int)header[3] : 0u;
    const unsigned int curves = read ? (unsigned int)header[4] + 1u : 0u;
    const long long big_e = read ? header[5] : 0;
    const unsigned int log_terms = read ? (unsigned int)header[6] : 0u;
    std::vector<long long> terms(curves, 0);
    for (unsigned int n = 0u; read && (n < curves); n += 1u)
    {
        read = lobes_word(in, &terms[n]) && (terms[n] > 0);
    }
    std::vector<std::vector<std::vector<unsigned int>>> magnitudes(curves);
    std::vector<std::vector<long long>> signs(curves);
    std::vector<std::vector<unsigned int>> gamma_bits(curves);
    for (unsigned int n = 0u; read && (n < curves); n += 1u)
    {
        for (long long j = 0; read && (j < terms[n]); j += 1)
        {
            std::vector<unsigned int> magnitude;
            long long sign = 0;
            unsigned int bits = 0u;
            read = lobes_mantissa(in, &magnitude, &sign, &bits);
            magnitudes[n].push_back(magnitude);
            signs[n].push_back(sign);
            gamma_bits[n].push_back(bits);
        }
    }
    std::vector<std::vector<unsigned int>> c_magnitudes(log_terms);
    std::vector<long long> c_signs(log_terms, 0);
    std::vector<unsigned int> c_bits(log_terms, 0u);
    for (unsigned int k = 0u; read && (k < log_terms); k += 1u)
    {
        read = lobes_mantissa(in, &c_magnitudes[k], &c_signs[k], &c_bits[k]);
    }
    if (in != NULL)
    {
        fclose(in);
    }
    if (!read)
    {
        fprintf(stderr, "  exact_zeta_lobes: %s is not an input this program reads\n", arguments[1]);
        return 2;
    }

    EngineError error;
    memset(&error, 0, sizeof(error));
    LobesStage curve_stage;
    lobes_open_stage(&curve_stage, "curves");
    lobes_build(&curve_stage, b, big_e, gamma_bits);
    lobes_open_shared(&curve_stage);
    std::vector<unsigned int> one_limb(1u, 1u);
    lobes_put(curve_stage.shared.data(), curve_stage.program.field_offset[0], curve_stage.program.field_bits[0], one_limb,
              ((nu - 1ull) % 2ull) ? -1 : 1);
    lobes_put_floor(&curve_stage, 1u, nu, b);
    unsigned int field = 2u;
    for (unsigned int n = 0u; n < curves; n += 1u)
    {
        const unsigned int held = (unsigned int)magnitudes[n].size();
        for (unsigned int j = 0u; j < held; j += 1u, field += 1u)
        {
            const std::vector<unsigned int> laid = lobes_shifted(magnitudes[n][j], b * (held - 1u - j));
            lobes_put(curve_stage.shared.data(), curve_stage.program.field_offset[field],
                      curve_stage.program.field_bits[field], laid, signs[n][j]);
        }
    }

    LobesStage log_stage;
    lobes_open_stage(&log_stage, "log");
    unsigned int nu_bits = 0u;
    while ((nu >> nu_bits) != 0ull)
    {
        nu_bits += 1u;
    }
    lobes_log_build(&log_stage, b, nu_bits, c_bits);
    lobes_open_shared(&log_stage);
    lobes_put_floor(&log_stage, 0u, nu, b);
    for (unsigned int k = 0u; k < log_terms; k += 1u)
    {
        lobes_put(log_stage.shared.data(), log_stage.program.field_offset[1u + k], log_stage.program.field_bits[1u + k],
                  c_magnitudes[k], c_signs[k]);
    }

    int ok = lobes_lay(&job, &curve_stage, &error);
    ok = ok && lobes_lay(&job, &log_stage, &error);
    const unsigned long long declared =
        lobes_declared(&curve_stage, lanes) + lobes_declared(&log_stage, lanes) + (256ull << 20u);
    ok = ok && sim_job_submit(&job, "exact_zeta_lobes", count, arguments, declared);
    ok = ok && lobes_sweep(&job, &curve_stage, lanes, checked, &error);
    ok = ok && lobes_sweep(&job, &log_stage, lanes, checked, &error);

    FILE *out = ok ? fopen(arguments[2], "w") : NULL;
    if (out != NULL)
    {
        lobes_write(out, &curve_stage, lanes);
        lobes_write(out, &log_stage, lanes);
        fclose(out);
    }
    sim_check(&job, out != NULL, "the records are written out");

    lobes_release(&curve_stage);
    lobes_release(&log_stage);
    return sim_close(&job, "exact_zeta_lobes");
}
