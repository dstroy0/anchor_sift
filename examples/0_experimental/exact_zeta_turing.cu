// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Catalog: EXP-x-028
//
// The automata of Turing's method over one cell of the Riemann-Siegel formula, as programs of the record machine on
// the device, one job on the device's tessera daemon. The machine one level up, exact_zeta_turing.py, runs a cell
// at a time and joins the cells.
//
//   Usage:  exact_zeta_turing <input> <output>
//
// Point j of cell nu stands at t = 2 pi s, s = x^2 = S / 2^p, S = nu^2 2^p + j (2 nu + 1), for j below P = 2^p: the
// lattice is even in t, and in theta to within 1 / nu across the cell. Every value is an integer at the scale 2^62,
// and a step that takes a product back to that scale divides by 2^31 twice, toward zero, an error below one unit;
// the bound on every value's error is the machine's to hold, from the program's own steps.
//
// The logarithm folds: ln(V / 2^b) = f ln 2 + 2 artanh((V - 2^(b + f)) / (V + 2^(b + f))), where 2^f is the product
// over i of 1 + [V > 2^(b + i)]; the artanh's argument lies in [0, 1/3]. w^(-1/2) is Newton's rule
// y (3 - w y^2) / 2 from 2^(-g - 1), where 2^g is the product over i of 1 + [w > 4^i]; it starts within a factor 2
// of the root and below it. Each lane works out its own.
//
// The pole stage, one lane a k <= nu: ln k and k^(-1/2), and for the multiple evaluation each pole's place, weight
// and charge.
//
// The point stage, one lane a point: theta / pi = s ln s - s - 1/8 + 1 / (96 pi^2 s); x = s s^(-1/2); C_0(z),
// z = 1 - 2 (x - nu), by Horner's rule over its Taylor coefficients; x^(-1/2); and (-1)^(nu - 1) x^(-1/2) C_0.
//
// The pair stage, one lane a pair (j, k), lane (j - start) nu + k - 1, reads its pole's record and its point's record
// through the index: the phase over pi, theta / pi - 2 s ln k, taken modulo 2 into [-1, 1) by a wrap, which leaves
// cos(pi Q) as it is; cos(pi s) by Horner's rule in s^2 over (-1)^k pi^(2k) / (2k)!; and the term k^(-1/2) cos(pi s).
// It runs in pieces of points from `start` up, and the sum over each point's nu lanes is the main sum's half.
//
// The verdict stage, one lane a point, reads the sums, the point records and the shared record as its three members:
// Z = 2 sum + (-1)^(nu - 1) x^(-1/2) C_0, its sign where |Z| exceeds the bound, else 0, theta / pi less and more its
// bound, and each times the step of S, 2 nu + 1, the same at every point and from the cell's last point to the next
// cell's point 0.
//
// The count stage, one lane a point q, reads the verdict records at q, q - 1 and q - 2 as its three members: a zero
// ends at q where q's sign is certified and the last certified sign before it, one or two points back, is the other;
// it gives that, S at q and at the zero's other end, and a mark where q follows two uncertified points.
//
// Over the first certified point F of the cell, the device sums: the less-steps over [0, F) and [F, P), the
// more-steps over [1, F] and (F, P), the zeros and their S at each end over [0, F] and (F, P), and the marks over
// (F, P).
//
// The main sum's half comes from the pair stage, or from the multiple evaluation below, or from both, the method
// word 0, 1 or 2; with both, the verdict is the multiple evaluation's and the most the two Z differ by is written.
// The multiple evaluation runs each of its programs many times a cell: the host checks a stage's first run over
// `checked` lanes and each later run over its first lane.
//
// The input, little-endian: 64-bit words points (2^p), checked, nu, p, L, K, J, N Newton steps, piece, method, the
// expansions' order, beta, E, R, then the constants, each a 64-bit word count w, w 32-bit limbs of its magnitude least
// significant first, and a 64-bit sign word: ln 2, the J coefficients of C_0, the L constants 1 / (2k + 1) of artanh,
// the K constants of cos, 1 / (96 pi^2), the bound on Z, the bound on theta / pi, pi, the E constants
// 1 / (n + 1)! of E1 and the R constants of S, every one at 2^62.
//
// The output: lines "key value" and "key value value ...", values signed hexadecimal: the cell, its first and last
// certified points and point 0, each with its sign, S, and theta / pi less and more its bound, the sums, Z at two
// points for the positive control, the host's checks of every stage and sum, each 1 where they equal the device's
// word for word, the steps of each program, and with both methods the most the two Z differ by and the point it
// falls at.

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

// the scale every value is held at, 2^62, and the half of it one division takes
#define TURING_SCALE_BITS 62u
#define TURING_HALF_BITS 31u
// nu below 2^16, k and x below 2^16, s below 2^32, and the lanes of a run below 2^24
#define TURING_NU_BITS 16u
#define TURING_LANE_BITS 24u
// a quotient keeps its dividend's width at imprint, and the wrap to TURING_HELD_BITS gives it the width its value
// has: every value taken back is below 2^(TURING_HELD_BITS - 1) in size, by the bounds exact_zeta_turing.py holds, and
// a value inside the wrap's range passes it unchanged
#define TURING_HELD_BITS 76u
// every coefficient of an expansion, and every value the transform carries, wrapped to one width, which lays every
// expansion record out alike
#define TURING_EXP_BITS 72u
// the verdict records laid before the first, read as uncertified points by the count stage
#define TURING_PADS 2u
// the width of S, nu^2 2^p + j (2 nu + 1), below 2^56
#define TURING_S_BITS 58u
// the lanes of an indexed run of the multiple evaluation, below 2^26
#define TURING_OS_LANE_BITS 26u
// an array a stage holds live across its steps, each value below 2 in size, wrapped to two limbs a register: the
// register file holds the array beside the steps that read it
#define TURING_LIVE_BITS 64u

typedef struct
{
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> field_bits;
    std::vector<unsigned int> field_offset;
    unsigned int shared_bits;
} TuringProgram;

typedef struct
{
    const char *name;
    TuringProgram program;
    std::vector<unsigned int> outputs;
    std::vector<unsigned int> shared;
    unsigned int members;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    // the shared fields of the run's parameters, in the order the build lays them, filled before each run
    std::vector<unsigned int> params;
    // the shared fields still to fill, each with its constant
    std::vector<unsigned int> put_field;
    std::vector<std::vector<unsigned int> > put_limbs;
    std::vector<long long> put_sign;
    // a shared field TURING_EXP_BITS wide holding 0, added to each expansion value before its wrap: a field is as wide
    // as it is laid, which gives every expansion's outputs one width whatever bound the imprint finds on the value
    int anchored;
    unsigned int anchor_field;
    unsigned int anchor_member;
    // the sweeps the stage has run: the first is checked over `checked` lanes, each later one over its first lane
    unsigned int swept;
} TuringStage;

typedef struct
{
    std::vector<unsigned int> magnitude;
    long long sign;
    unsigned int bits;
} TuringConstant;

typedef struct
{
    unsigned int re;
    unsigned int im;
} TuringComplex;

// the shared fields of the logarithm, by number
typedef struct
{
    unsigned int ln2;
    std::vector<unsigned int> artanh;
} TuringLogFields;

static unsigned int turing_step(TuringProgram *program, EngineRecordOperation operation, unsigned int left,
                                unsigned int right, unsigned int member)
{
    EngineRecordStep step = {operation, left, right, member};
    program->steps.push_back(step);
    return (unsigned int)program->steps.size() - 1u;
}

static unsigned int turing_op(TuringProgram *program, EngineRecordOperation operation, unsigned int left,
                              unsigned int right)
{
    return turing_step(program, operation, left, right, 0u);
}

static unsigned int turing_constant(TuringProgram *program, unsigned long long value)
{
    return turing_step(program, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull), (unsigned int)(value >> 32u),
                       0u);
}

// 2^bits, for bits up to 126, as one constant or the product of two
static unsigned int turing_power(TuringProgram *program, unsigned int bits)
{
    if (bits < 64u)
    {
        return turing_constant(program, 1ull << bits);
    }
    return turing_op(program, ENGINE_RECORD_PRODUCT, turing_constant(program, 1ull << 63u),
                     turing_constant(program, 1ull << (bits - 63u)));
}

// a field laid at the shared record's next bit
static unsigned int turing_field(TuringProgram *program, unsigned int bits)
{
    const unsigned int field = (unsigned int)program->field_bits.size();
    program->field_bits.push_back(bits);
    program->field_offset.push_back(program->shared_bits);
    program->shared_bits += bits;
    return field;
}

// a field at a given place in another member's records
static unsigned int turing_member_field(TuringProgram *program, unsigned int bits, unsigned int offset)
{
    const unsigned int field = (unsigned int)program->field_bits.size();
    program->field_bits.push_back(bits);
    program->field_offset.push_back(offset);
    return field;
}

static unsigned int turing_read(TuringProgram *program, unsigned int field, unsigned int member)
{
    return turing_step(program, ENGINE_RECORD_FIELD_SIGNED, field, 0u, member);
}

// a product taken back to the scale: divided by 2^31 twice, toward zero, one division by 2^62, then wrapped to the
// width its value has
static unsigned int turing_scaled(TuringProgram *program, unsigned int left, unsigned int right)
{
    const unsigned int product = turing_op(program, ENGINE_RECORD_PRODUCT, left, right);
    const unsigned int half = turing_op(program, ENGINE_RECORD_QUOTIENT, product,
                                        turing_constant(program, 1ull << TURING_HALF_BITS));
    const unsigned int whole =
        turing_op(program, ENGINE_RECORD_QUOTIENT, half, turing_constant(program, 1ull << TURING_HALF_BITS));
    return turing_op(program, ENGINE_RECORD_WRAP, whole, TURING_HELD_BITS);
}

// the lane, below 2^bits, and the and with 2^bits - 1 gives its register that width
static unsigned int turing_lane(TuringProgram *program, unsigned int bits)
{
    const unsigned int counted = turing_step(program, ENGINE_RECORD_LANE, 0u, 0u, 0u);
    return turing_op(program, ENGINE_RECORD_AND, counted, turing_constant(program, (1ull << bits) - 1ull));
}

// [a > b], 0 or 1: (c + |c|) / 2 with c = COMPARE(a, b)
static unsigned int turing_above(TuringProgram *program, unsigned int a, unsigned int b)
{
    const unsigned int c = turing_op(program, ENGINE_RECORD_COMPARE, a, b);
    return turing_op(program, ENGINE_RECORD_EXACT_QUOTIENT,
                     turing_op(program, ENGINE_RECORD_SUM, c, turing_op(program, ENGINE_RECORD_ABSOLUTE, c, 0u)),
                     turing_constant(program, 2ull));
}

// 1 where a equals b, else 0: 1 - |COMPARE(a, b)|
static unsigned int turing_equal(TuringProgram *program, unsigned int a, unsigned int b)
{
    const unsigned int c = turing_op(program, ENGINE_RECORD_COMPARE, a, b);
    return turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 1ull),
                     turing_op(program, ENGINE_RECORD_ABSOLUTE, c, 0u));
}

static unsigned int turing_negate(TuringProgram *program, unsigned int value)
{
    return turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 0ull), value);
}

static unsigned int turing_wrap(TuringProgram *program, unsigned int value, unsigned int bits)
{
    return turing_op(program, ENGINE_RECORD_WRAP, value, bits);
}

// a shared field holding a constant, filled when the stage is sealed
static unsigned int turing_const_field(TuringStage *stage, const TuringConstant &constant)
{
    const unsigned int field = turing_field(&stage->program, constant.bits);
    stage->put_field.push_back(field);
    stage->put_limbs.push_back(constant.magnitude);
    stage->put_sign.push_back(constant.sign);
    return field;
}

// a parameter field `bits` wide, signed, set before each run
static unsigned int turing_param_field(TuringStage *stage, unsigned int bits)
{
    const unsigned int field = turing_field(&stage->program, bits);
    stage->params.push_back(field);
    return field;
}

static std::vector<unsigned int> turing_const_fields(TuringStage *stage, const std::vector<TuringConstant> &constants)
{
    std::vector<unsigned int> fields;
    for (size_t k = 0u; k < constants.size(); k += 1u)
    {
        fields.push_back(turing_const_field(stage, constants[k]));
    }
    return fields;
}

// the constants of the multiple evaluation, read from member `member`'s shared record
typedef struct
{
    unsigned int member;
    unsigned int pi;
    std::vector<unsigned int> cosine;
    std::vector<unsigned int> fact;
    std::vector<unsigned int> sinc;
} TuringOsFields;

typedef struct
{
    TuringConstant pi;
    std::vector<TuringConstant> cosine;
    std::vector<TuringConstant> fact;
    std::vector<TuringConstant> sinc;
} TuringOsConstants;

static void turing_os_fields(TuringStage *stage, TuringOsFields *fields, unsigned int member, const TuringOsConstants &os)
{
    fields->member = member;
    fields->pi = turing_const_field(stage, os.pi);
    fields->cosine = turing_const_fields(stage, os.cosine);
    fields->fact = turing_const_fields(stage, os.fact);
    fields->sinc = turing_const_fields(stage, os.sinc);
}

static unsigned int turing_horner(TuringProgram *program, unsigned int u, const std::vector<unsigned int> &fields,
                                  unsigned int member)
{
    unsigned int acc = turing_read(program, fields[fields.size() - 1u], member);
    for (size_t k = fields.size() - 1u; k > 0u; k -= 1u)
    {
        acc = turing_op(program, ENGINE_RECORD_SUM, turing_scaled(program, acc, u), turing_read(program, fields[k - 1u], member));
    }
    return acc;
}

// cos(pi s) and sin(pi s) for s in [-1, 1) at the scale, sin(pi s) = cos(pi (s - 1/2))
static TuringComplex turing_cis(TuringProgram *program, unsigned int s, const TuringOsFields *fields)
{
    TuringComplex out;
    out.re = turing_horner(program, turing_scaled(program, s, s), fields->cosine, fields->member);
    const unsigned int shifted = turing_wrap(
        program, turing_op(program, ENGINE_RECORD_DIFFERENCE, s, turing_constant(program, 1ull << (TURING_SCALE_BITS - 1u))),
        TURING_SCALE_BITS + 1u);
    out.im = turing_horner(program, turing_scaled(program, shifted, shifted), fields->cosine, fields->member);
    return out;
}

// E1(i x) = (exp(i x) - 1) / (i x), the sum of (i x)^n / (n + 1)!, by Horner's rule in i x
static TuringComplex turing_e1i(TuringProgram *program, unsigned int x, const TuringOsFields *fields)
{
    const size_t terms = fields->fact.size();
    TuringComplex acc;
    acc.re = turing_read(program, fields->fact[terms - 1u], fields->member);
    acc.im = turing_constant(program, 0ull);
    for (size_t n = terms - 1u; n > 0u; n -= 1u)
    {
        const unsigned int re = turing_op(program, ENGINE_RECORD_SUM, turing_negate(program, turing_scaled(program, acc.im, x)),
                                          turing_read(program, fields->fact[n - 1u], fields->member));
        acc.im = turing_scaled(program, acc.re, x);
        acc.re = re;
    }
    return acc;
}

// S(u) = sin(pi r) / (pi r) at u = r^2, by Horner's rule over (-1)^n pi^(2n) / (2n + 1)!
static unsigned int turing_sinc(TuringProgram *program, unsigned int u, const TuringOsFields *fields)
{
    return turing_horner(program, u, fields->sinc, fields->member);
}

static TuringComplex turing_cmul(TuringProgram *program, TuringComplex a, TuringComplex b)
{
    TuringComplex out;
    out.re = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_scaled(program, a.re, b.re), turing_scaled(program, a.im, b.im));
    out.im = turing_op(program, ENGINE_RECORD_SUM, turing_scaled(program, a.re, b.im), turing_scaled(program, a.im, b.re));
    out.re = turing_wrap(program, out.re, TURING_HELD_BITS);
    out.im = turing_wrap(program, out.im, TURING_HELD_BITS);
    return out;
}

static TuringComplex turing_cadd(TuringProgram *program, TuringComplex a, TuringComplex b)
{
    TuringComplex out = {turing_op(program, ENGINE_RECORD_SUM, a.re, b.re), turing_op(program, ENGINE_RECORD_SUM, a.im, b.im)};
    return out;
}

// a times the real r at the scale
static TuringComplex turing_cscale(TuringProgram *program, TuringComplex a, unsigned int r)
{
    TuringComplex out = {turing_scaled(program, a.re, r), turing_scaled(program, a.im, r)};
    return out;
}

// i a
static TuringComplex turing_ctimes_i(TuringProgram *program, TuringComplex a)
{
    TuringComplex out = {turing_negate(program, a.im), a.re};
    return out;
}

static TuringComplex turing_chalf(TuringProgram *program, TuringComplex a)
{
    TuringComplex out = {turing_op(program, ENGINE_RECORD_QUOTIENT, a.re, turing_constant(program, 2ull)),
                         turing_op(program, ENGINE_RECORD_QUOTIENT, a.im, turing_constant(program, 2ull))};
    return out;
}

// 1 / a at the scale: conj(a) 2^124 / |a|^2, the norm held at 2^124 whole, which keeps a small a's relative precision
static TuringComplex turing_crecip(TuringProgram *program, TuringComplex a)
{
    const unsigned int norm = turing_op(program, ENGINE_RECORD_SUM, turing_op(program, ENGINE_RECORD_PRODUCT, a.re, a.re),
                                        turing_op(program, ENGINE_RECORD_PRODUCT, a.im, a.im));
    const unsigned int unit = turing_power(program, 2u * TURING_SCALE_BITS);
    TuringComplex out;
    out.re = turing_wrap(program,
                         turing_op(program, ENGINE_RECORD_QUOTIENT, turing_op(program, ENGINE_RECORD_PRODUCT, a.re, unit), norm),
                         TURING_HELD_BITS);
    out.im = turing_wrap(program,
                         turing_op(program, ENGINE_RECORD_QUOTIENT,
                                   turing_op(program, ENGINE_RECORD_PRODUCT, turing_negate(program, a.im), unit), norm),
                         TURING_HELD_BITS);
    return out;
}

static TuringComplex turing_cone(TuringProgram *program)
{
    TuringComplex out = {turing_constant(program, 1ull << TURING_SCALE_BITS), turing_constant(program, 0ull)};
    return out;
}

static TuringComplex turing_cwrap(TuringProgram *program, TuringComplex a, unsigned int bits)
{
    TuringComplex out = {turing_wrap(program, a.re, bits), turing_wrap(program, a.im, bits)};
    return out;
}

// ln(V / 2^b) at the scale, for V in [2^b, 2^(b + folds + 1)), folded to f ln 2 + 2 artanh(y) with y in [0, 1/3]
static unsigned int turing_log(TuringProgram *program, unsigned int value, unsigned int b, unsigned int folds,
                               const TuringLogFields *fields)
{
    unsigned int count = turing_constant(program, 0ull);
    unsigned int power = turing_constant(program, 1ull);
    for (unsigned int i = 1u; i <= folds; i += 1u)
    {
        const unsigned int past = turing_above(program, value, turing_power(program, b + i));
        count = turing_op(program, ENGINE_RECORD_SUM, count, past);
        power = turing_op(program, ENGINE_RECORD_PRODUCT, power,
                          turing_op(program, ENGINE_RECORD_SUM, turing_constant(program, 1ull), past));
    }
    // 2^(b + f) lies in [V / 2, V], below 2^(b + folds + 1), and y in [0, 1/3]
    const unsigned int base = turing_op(program, ENGINE_RECORD_WRAP,
                                        turing_op(program, ENGINE_RECORD_PRODUCT, power, turing_power(program, b)),
                                        b + folds + 3u);
    const unsigned int over = turing_op(program, ENGINE_RECORD_PRODUCT, turing_op(program, ENGINE_RECORD_DIFFERENCE, value, base),
                                        turing_constant(program, 1ull << TURING_SCALE_BITS));
    const unsigned int y = turing_op(program, ENGINE_RECORD_WRAP,
                                     turing_op(program, ENGINE_RECORD_QUOTIENT, over, turing_op(program, ENGINE_RECORD_SUM, value, base)),
                                     TURING_SCALE_BITS + 1u);
    const unsigned int y2 = turing_scaled(program, y, y);
    const size_t terms = fields->artanh.size();
    unsigned int acc = turing_read(program, fields->artanh[terms - 1u], 0u);
    for (size_t k = terms - 1u; k > 0u; k -= 1u)
    {
        acc = turing_op(program, ENGINE_RECORD_SUM, turing_scaled(program, acc, y2), turing_read(program, fields->artanh[k - 1u], 0u));
    }
    const unsigned int half = turing_scaled(program, acc, y);
    const unsigned int twice = turing_op(program, ENGINE_RECORD_SUM, half, half);
    return turing_op(program, ENGINE_RECORD_SUM, turing_op(program, ENGINE_RECORD_PRODUCT, count, turing_read(program, fields->ln2, 0u)),
                     twice);
}

// w^(-1/2) at the scale, w = `times` / 2^`per`, for w in [1, 4^(folds + 1)), by Newton's rule from 2^(-g - 1) below it
static unsigned int turing_root(TuringProgram *program, unsigned int times, unsigned int per, unsigned int folds,
                                unsigned int steps)
{
    unsigned int power = turing_constant(program, 2ull);
    for (unsigned int i = 1u; i <= folds; i += 1u)
    {
        const unsigned int past = turing_above(program, times, turing_power(program, per + 2u * i));
        power = turing_op(program, ENGINE_RECORD_PRODUCT, power,
                          turing_op(program, ENGINE_RECORD_SUM, turing_constant(program, 1ull), past));
    }
    unsigned int y = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_constant(program, 1ull << TURING_SCALE_BITS),
                               turing_op(program, ENGINE_RECORD_WRAP, power, folds + 4u));
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int squared = turing_scaled(program, y, y);
        unsigned int wy2 = turing_op(program, ENGINE_RECORD_PRODUCT, times, squared);
        if (per != 0u)
        {
            wy2 = turing_op(program, ENGINE_RECORD_QUOTIENT, wy2, turing_power(program, per));
        }
        const unsigned int three = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 3ull << TURING_SCALE_BITS), wy2);
        y = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_scaled(program, y, three), turing_constant(program, 2ull));
    }
    return y;
}

static void turing_log_fields(TuringProgram *program, TuringLogFields *fields, const TuringConstant &ln2,
                              const std::vector<TuringConstant> &artanh)
{
    fields->ln2 = turing_field(program, ln2.bits);
    for (size_t k = 0u; k < artanh.size(); k += 1u)
    {
        fields->artanh.push_back(turing_field(program, artanh[k].bits));
    }
}

// the pole stage: shared fields the logarithm's, then, for the multiple evaluation, its constants. With them it
// gives, besides ln k and k^(-1/2): pos = (2 nu + 1) ln k, where the pole sits among the frequencies h;
// a = k^(-1/2) exp(-2 pi i nu^2 ln k); and q = -a (1 - exp(-2 pi i pos)) exp(2 pi i pos / P) / P, its charge
static void turing_pole_build(TuringStage *stage, unsigned int newton, const TuringConstant &ln2,
                              const std::vector<TuringConstant> &artanh, unsigned int p,
                              const TuringOsConstants *os)
{
    TuringProgram *const program = &stage->program;
    TuringLogFields fields;
    turing_log_fields(program, &fields, ln2, artanh);
    const unsigned int k = turing_op(program, ENGINE_RECORD_SUM, turing_lane(program, TURING_NU_BITS + 1u),
                                     turing_constant(program, 1ull));
    const unsigned int log = turing_log(program, k, 0u, TURING_NU_BITS, &fields);
    const unsigned int root = turing_root(program, k, 0u, TURING_NU_BITS / 2u, newton);
    stage->outputs.push_back(log);
    stage->outputs.push_back(root);
    if (os == NULL)
    {
        return;
    }
    TuringOsFields of;
    turing_os_fields(stage, &of, 0u, *os);
    // 2 nu + 1 and 2 nu^2 are the stage's parameters, which leaves one program for every cell at P points
    const unsigned int step_field = turing_param_field(stage, TURING_NU_BITS + 3u);
    const unsigned int twice_square_field = turing_param_field(stage, 2u * TURING_NU_BITS + 3u);
    const unsigned int pos = turing_op(program, ENGINE_RECORD_PRODUCT, log, turing_read(program, step_field, 0u));
    const unsigned int alpha = turing_wrap(program, turing_op(program, ENGINE_RECORD_PRODUCT, log, turing_read(program, twice_square_field, 0u)),
                                           TURING_SCALE_BITS + 1u);
    const TuringComplex turn = turing_cis(program, alpha, &of);
    const TuringComplex a = {turing_scaled(program, root, turn.re), turing_negate(program, turing_scaled(program, root, turn.im))};
    const unsigned int whole = turing_wrap(program, turing_op(program, ENGINE_RECORD_SUM, pos, pos), TURING_SCALE_BITS + 1u);
    const TuringComplex back = turing_cis(program, whole, &of);
    const TuringComplex less = {turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 1ull << TURING_SCALE_BITS), back.re),
                                back.im};
    const TuringComplex c = turing_cmul(program, a, less);
    const TuringComplex omega = turing_cis(program, turing_op(program, ENGINE_RECORD_QUOTIENT, pos, turing_power(program, p - 1u)), &of);
    const TuringComplex charge = turing_cmul(program, c, omega);
    const unsigned int big_p = turing_power(program, p);
    stage->outputs.push_back(pos);
    stage->outputs.push_back(a.re);
    stage->outputs.push_back(a.im);
    stage->outputs.push_back(turing_op(program, ENGINE_RECORD_QUOTIENT, turing_negate(program, charge.re), big_p));
    stage->outputs.push_back(turing_op(program, ENGINE_RECORD_QUOTIENT, turing_negate(program, charge.im), big_p));
}

// the point stage: shared fields sign, nu^2 2^p, 2 nu + 1, nu, then the logarithm's, 1 / (96 pi^2), then C_0's
static void turing_point_build(TuringStage *stage, unsigned int p, unsigned int newton, const TuringConstant &ln2,
                               const std::vector<TuringConstant> &artanh, const TuringConstant &c96,
                               const std::vector<TuringConstant> &gamma, const TuringOsConstants *os)
{
    TuringProgram *const program = &stage->program;
    const unsigned int sign_field = turing_field(program, 2u);
    const unsigned int floor_field = turing_field(program, TURING_S_BITS);
    const unsigned int step_field = turing_field(program, TURING_NU_BITS + 3u);
    const unsigned int nu_field = turing_field(program, TURING_NU_BITS + 2u);
    TuringLogFields fields;
    turing_log_fields(program, &fields, ln2, artanh);
    const unsigned int c96_field = turing_field(program, c96.bits);
    std::vector<unsigned int> gamma_field;
    for (size_t k = 0u; k < gamma.size(); k += 1u)
    {
        gamma_field.push_back(turing_field(program, gamma[k].bits));
    }
    const unsigned int lane = turing_lane(program, p + 1u);
    const unsigned int big_s = turing_op(program, ENGINE_RECORD_SUM, turing_read(program, floor_field, 0u),
                                         turing_op(program, ENGINE_RECORD_PRODUCT, lane, turing_read(program, step_field, 0u)));

    // theta / pi = S ln(S / 2^p) / 2^p - S / 2^p - 1/8 + 2^p / (96 pi^2 S)
    const unsigned int log = turing_log(program, big_s, p, 2u * TURING_NU_BITS + 1u, &fields);
    const unsigned int leading = turing_op(program, ENGINE_RECORD_QUOTIENT,
                                           turing_op(program, ENGINE_RECORD_PRODUCT, big_s, log), turing_power(program, p));
    const unsigned int square = turing_op(program, ENGINE_RECORD_PRODUCT, big_s, turing_power(program, TURING_SCALE_BITS - p));
    const unsigned int small = turing_op(program, ENGINE_RECORD_QUOTIENT,
                                         turing_op(program, ENGINE_RECORD_PRODUCT, turing_read(program, c96_field, 0u),
                                                   turing_power(program, p)),
                                         big_s);
    const unsigned int less = turing_op(program, ENGINE_RECORD_DIFFERENCE, leading, square);
    const unsigned int eighth = turing_op(program, ENGINE_RECORD_DIFFERENCE, less, turing_constant(program, 1ull << (TURING_SCALE_BITS - 3u)));
    const unsigned int theta = turing_op(program, ENGINE_RECORD_SUM, eighth, small);

    // x = S s^(-1/2) / 2^p, below 2^(62 + 16), and z = 1 - 2 (x - nu) in [-1, 1]
    const unsigned int inverse = turing_root(program, big_s, p, TURING_NU_BITS, newton);
    const unsigned int x = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_op(program, ENGINE_RECORD_PRODUCT, big_s, inverse),
                                     turing_power(program, p));
    const unsigned int lifted = turing_op(program, ENGINE_RECORD_PRODUCT,
                                          turing_op(program, ENGINE_RECORD_SUM,
                                                    turing_op(program, ENGINE_RECORD_SUM, turing_read(program, nu_field, 0u),
                                                              turing_read(program, nu_field, 0u)),
                                                    turing_constant(program, 1ull)),
                                          turing_constant(program, 1ull << TURING_SCALE_BITS));
    const unsigned int z = turing_op(program, ENGINE_RECORD_WRAP,
                                     turing_op(program, ENGINE_RECORD_DIFFERENCE, lifted, turing_op(program, ENGINE_RECORD_SUM, x, x)),
                                     TURING_SCALE_BITS + 2u);
    unsigned int acc = turing_read(program, gamma_field[gamma_field.size() - 1u], 0u);
    for (size_t k = gamma_field.size() - 1u; k > 0u; k -= 1u)
    {
        acc = turing_op(program, ENGINE_RECORD_SUM, turing_scaled(program, acc, z), turing_read(program, gamma_field[k - 1u], 0u));
    }
    const unsigned int root = turing_root(program, x, TURING_SCALE_BITS, TURING_NU_BITS / 2u, newton);
    const unsigned int held = turing_scaled(program, acc, root);
    stage->outputs.push_back(turing_op(program, ENGINE_RECORD_PRODUCT, held, turing_read(program, sign_field, 0u)));
    stage->outputs.push_back(theta);
    if (os != NULL)
    {
        // cos theta and sin theta, for Z = 2 Re(exp(i theta) F) + R
        TuringOsFields of;
        turing_os_fields(stage, &of, 0u, *os);
        const TuringComplex turn = turing_cis(program, turing_wrap(program, theta, TURING_SCALE_BITS + 1u), &of);
        stage->outputs.push_back(turn.re);
        stage->outputs.push_back(turn.im);
    }
}

// a step's output place in a laid-out stage
static const DeviceRecordStep *turing_place(const TuringStage *stage, unsigned int output)
{
    return &stage->layout.step_table[stage->outputs[output]];
}

// the pair stage: member 0 the pole records, member 1 the point records, member 2 the shared record of nu,
// nu^2 2^p, 2 nu + 1, start, then cos's constants
static void turing_pair_build(TuringStage *stage, unsigned int p, const TuringStage *pole, const TuringStage *point,
                              const std::vector<TuringConstant> &cosine)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const log_place = turing_place(pole, 0u);
    const DeviceRecordStep *const root_place = turing_place(pole, 1u);
    const DeviceRecordStep *const theta_place = turing_place(point, 1u);
    const unsigned int log_field = turing_member_field(program, log_place->out_bits, log_place->out_offset);
    const unsigned int root_field = turing_member_field(program, root_place->out_bits, root_place->out_offset);
    const unsigned int theta_field = turing_member_field(program, theta_place->out_bits, theta_place->out_offset);
    program->shared_bits = 0u;
    const unsigned int nu_field = turing_field(program, TURING_NU_BITS + 2u);
    const unsigned int floor_field = turing_field(program, TURING_S_BITS);
    const unsigned int step_field = turing_field(program, TURING_NU_BITS + 3u);
    const unsigned int start_field = turing_field(program, TURING_LANE_BITS + 2u);
    std::vector<unsigned int> cos_field;
    for (size_t k = 0u; k < cosine.size(); k += 1u)
    {
        cos_field.push_back(turing_field(program, cosine[k].bits));
    }
    const unsigned int lane = turing_lane(program, TURING_LANE_BITS + 1u);
    const unsigned int j = turing_op(program, ENGINE_RECORD_SUM,
                                     turing_op(program, ENGINE_RECORD_QUOTIENT, lane, turing_read(program, nu_field, 2u)),
                                     turing_read(program, start_field, 2u));
    const unsigned int big_s = turing_op(program, ENGINE_RECORD_SUM, turing_read(program, floor_field, 2u),
                                         turing_op(program, ENGINE_RECORD_PRODUCT, j, turing_read(program, step_field, 2u)));
    // 2 s ln k = S ln k / 2^(p - 1)
    const unsigned int twice = turing_op(program, ENGINE_RECORD_QUOTIENT,
                                         turing_op(program, ENGINE_RECORD_PRODUCT, big_s, turing_read(program, log_field, 0u)),
                                         turing_power(program, p - 1u));
    const unsigned int q = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_read(program, theta_field, 1u), twice);
    const unsigned int s = turing_op(program, ENGINE_RECORD_WRAP, q, TURING_SCALE_BITS + 1u);
    const unsigned int u = turing_scaled(program, s, s);
    unsigned int c = turing_read(program, cos_field[cos_field.size() - 1u], 2u);
    for (size_t k = cos_field.size() - 1u; k > 0u; k -= 1u)
    {
        c = turing_op(program, ENGINE_RECORD_SUM, turing_scaled(program, c, u), turing_read(program, cos_field[k - 1u], 2u));
    }
    stage->outputs.push_back(turing_scaled(program, c, turing_read(program, root_field, 0u)));
    stage->shared.assign((program->shared_bits + 31u) / 32u, 0u);
}

// THE MULTIPLE EVALUATION
//
// F_j = sum over k of a_k exp(-2 pi i j pos_k / P) at every point j is the transform of
// u_h = sum over k of c_k / (1 - exp(2 pi i (h - pos_k) / P)), c_k = a_k (1 - exp(-2 pi i pos_k)), h in [-P/2, P/2):
// F_j = sum over h of (u_h / P) exp(-2 pi i j h / P). With z = exp(2 pi i h / P) and w_k = exp(2 pi i pos_k / P),
// u_h / P = sum over k of q_k / (z - w_k), q_k = -c_k w_k / P, the poles' charges on the unit circle. The leaves are
// runs of W = 2^beta frequencies, and the tree over them halves at each level; a box of width V has center
// sigma = exp(2 pi i c / P) and radius rho = pi V / P, and every pole in it has eta = (w / sigma - 1) / rho with
// |eta| <= 1, every point zeta = (z / sigma - 1) / rho likewise. A box's multipole is
// M_m = sum over its poles of (q / sigma) eta^m, m < N; a box's local expansion is the L_n with
// u_h / P = sum of L_n zeta^n over the poles outside its near field. Each is one record of 2N values, the real and
// imaginary parts, every one wrapped to TURING_EXP_BITS.
//
// Between a target box T and a source box S of the same level, Delta = T - S, D = exp(2 pi i Delta V / P) - 1:
// 1 / (z - w) = (1 / (sigma_S D)) sum of binom(m + n, n) (-(1 + D) rho zeta / D)^n (rho eta / D)^m. Both ratios are
// at most rho / |D|, a third or less where |Delta| >= 3, and the terms past N are the error the machine bounds.

// an expansion record's layout: each value's offset and width
typedef struct
{
    std::vector<unsigned int> offset;
    std::vector<unsigned int> bits;
    unsigned int out_limbs;
} TuringExpansion;

static TuringExpansion turing_expansion_of(const TuringStage *stage)
{
    TuringExpansion layout;
    for (size_t at = 0u; at < stage->outputs.size(); at += 1u)
    {
        layout.offset.push_back(turing_place(stage, (unsigned int)at)->out_offset);
        layout.bits.push_back(turing_place(stage, (unsigned int)at)->out_bits);
    }
    layout.out_limbs = stage->layout.out_limbs;
    return layout;
}

static int turing_same_expansion(const TuringExpansion &a, const TuringExpansion &b)
{
    const int same = (a.offset == b.offset) && (a.bits == b.bits) && (a.out_limbs == b.out_limbs);
    if (!same)
    {
        fprintf(stderr, "  layouts differ: %zu %zu values, %u %u limbs\n", a.bits.size(), b.bits.size(), a.out_limbs, b.out_limbs);
        for (size_t at = 0u; at < a.bits.size() && at < b.bits.size(); at += 1u)
        {
            if ((a.bits[at] != b.bits[at]) || (a.offset[at] != b.offset[at]))
            {
                fprintf(stderr, "  value %zu: %u at %u, %u at %u\n", at, a.bits[at], a.offset[at], b.bits[at], b.offset[at]);
                break;
            }
        }
    }
    return same;
}

// an expansion's fields in member `member`, laid once; each value is read at the step that wants it, which keeps it
// out of the register file until then
typedef struct
{
    std::vector<unsigned int> re;
    std::vector<unsigned int> im;
    unsigned int member;
} TuringExpansionFields;

static TuringExpansionFields turing_expansion_fields(TuringProgram *program, const TuringExpansion &layout, unsigned int member)
{
    TuringExpansionFields fields;
    fields.member = member;
    for (size_t at = 0u; at + 1u < layout.offset.size(); at += 2u)
    {
        fields.re.push_back(turing_member_field(program, layout.bits[at], layout.offset[at]));
        fields.im.push_back(turing_member_field(program, layout.bits[at + 1u], layout.offset[at + 1u]));
    }
    return fields;
}

static TuringComplex turing_read_at(TuringProgram *program, const TuringExpansionFields &fields, size_t at)
{
    TuringComplex value = {turing_read(program, fields.re[at], fields.member), turing_read(program, fields.im[at], fields.member)};
    return value;
}

// the stage's anchor, a field of its shared record in member `member`
static void turing_anchor(TuringStage *stage, unsigned int member)
{
    stage->anchor_field = turing_field(&stage->program, TURING_EXP_BITS);
    stage->anchor_member = member;
    stage->anchored = 1;
}

// the stage's next value of an expansion, its two outputs written at the step that makes them
static void turing_put_value(TuringStage *stage, TuringComplex value)
{
    if (stage->anchored)
    {
        TuringProgram *const program = &stage->program;
        value.re = turing_op(program, ENGINE_RECORD_SUM, value.re, turing_read(program, stage->anchor_field, stage->anchor_member));
        value.im = turing_op(program, ENGINE_RECORD_SUM, value.im, turing_read(program, stage->anchor_field, stage->anchor_member));
    }
    const TuringComplex wrapped = turing_cwrap(&stage->program, value, TURING_EXP_BITS);
    stage->outputs.push_back(wrapped.re);
    stage->outputs.push_back(wrapped.im);
}

// binom(n, k), below 2^63 for the orders the stages run
static unsigned long long turing_binomial(unsigned int n, unsigned int k)
{
    unsigned long long value = 1ull;
    for (unsigned int i = 1u; i <= k; i += 1u)
    {
        value = value * (n - k + i) / i;
    }
    return value;
}

// the integer c 2^e as a register, one constant where it fits 64 bits and a product of two where it does not
static unsigned int turing_weight(TuringProgram *program, unsigned long long c, unsigned int e)
{
    unsigned int width = 0u;
    while ((width < 64u) && ((c >> width) != 0ull))
    {
        width += 1u;
    }
    if (width + e < 64u)
    {
        return turing_constant(program, c << e);
    }
    return turing_op(program, ENGINE_RECORD_PRODUCT, turing_constant(program, c), turing_power(program, e));
}

// a + w b for an integer weight w, exact
static TuringComplex turing_cweigh(TuringProgram *program, TuringComplex a, unsigned int w, TuringComplex b)
{
    TuringComplex out = {turing_op(program, ENGINE_RECORD_SUM, a.re, turing_op(program, ENGINE_RECORD_PRODUCT, w, b.re)),
                         turing_op(program, ENGINE_RECORD_SUM, a.im, turing_op(program, ENGINE_RECORD_PRODUCT, w, b.im))};
    return out;
}

// a / 2^e toward zero, within a unit
static TuringComplex turing_cshift_down(TuringProgram *program, TuringComplex a, unsigned int e)
{
    if (e == 0u)
    {
        return a;
    }
    TuringComplex out = {turing_op(program, ENGINE_RECORD_QUOTIENT, a.re, turing_power(program, e)),
                         turing_op(program, ENGINE_RECORD_QUOTIENT, a.im, turing_power(program, e))};
    return out;
}

// the count stage of the leaves: lane b nu + k - 1 reads pole k through the index and gives [b W > pos_k]; the sum
// over each run of nu is the poles below the leaf boundary b W
static void turing_below_build(TuringStage *stage, unsigned int beta, const TuringStage *pole)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const pos_place = turing_place(pole, 2u);
    const unsigned int pos = turing_read(program, turing_member_field(program, pos_place->out_bits, pos_place->out_offset), 0u);
    // member 1 the shared record of nu, the stage's parameter
    const unsigned int nu_field = turing_param_field(stage, TURING_NU_BITS + 2u);
    const unsigned int lane = turing_lane(program, TURING_OS_LANE_BITS);
    const unsigned int boundary = turing_op(program, ENGINE_RECORD_PRODUCT,
                                            turing_op(program, ENGINE_RECORD_QUOTIENT, lane, turing_read(program, nu_field, 1u)),
                                            turing_power(program, beta + TURING_SCALE_BITS));
    stage->outputs.push_back(turing_above(program, boundary, pos));
}

// the leaf multipoles' terms: lane (leaf, slot) reads its pole through the index, finds its leaf from pos, and gives
// (q / sigma) eta^m for every m < N; the sum over a leaf's slots is its multipole
static void turing_p2m_build(TuringStage *stage, unsigned int p, unsigned int beta, unsigned int order, const TuringStage *pole,
                             const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const pos_place = turing_place(pole, 2u);
    const DeviceRecordStep *const qre_place = turing_place(pole, 5u);
    const DeviceRecordStep *const qim_place = turing_place(pole, 6u);
    const unsigned int pos = turing_read(program, turing_member_field(program, pos_place->out_bits, pos_place->out_offset), 0u);
    TuringComplex q;
    q.re = turing_read(program, turing_member_field(program, qre_place->out_bits, qre_place->out_offset), 0u);
    q.im = turing_read(program, turing_member_field(program, qim_place->out_bits, qim_place->out_offset), 0u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 1u, os);
    turing_anchor(stage, 1u);
    const unsigned int half = turing_power(program, p - 1u + TURING_SCALE_BITS);
    const unsigned int width = turing_power(program, beta + TURING_SCALE_BITS);
    const unsigned int leaf = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_op(program, ENGINE_RECORD_SUM, pos, half), width);
    const unsigned int center = turing_op(program, ENGINE_RECORD_SUM,
                                          turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_op(program, ENGINE_RECORD_PRODUCT, leaf, width), half),
                                          turing_power(program, beta - 1u + TURING_SCALE_BITS));
    // u = 2 (pos - c) / W in [-1, 1], psi = 2 pi (pos - c) / P = u pi W / P, eta = u i E1(i psi)
    const unsigned int u = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_op(program, ENGINE_RECORD_DIFFERENCE, pos, center),
                                     turing_power(program, beta - 1u));
    const unsigned int psi = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_scaled(program, u, turing_read(program, of.pi, 1u)),
                                       turing_power(program, p - beta));
    const TuringComplex eta = turing_cscale(program, turing_ctimes_i(program, turing_e1i(program, psi, &of)), u);
    const unsigned int angle = turing_wrap(program, turing_op(program, ENGINE_RECORD_QUOTIENT, center, turing_power(program, p - 1u)),
                                           TURING_SCALE_BITS + 1u);
    const TuringComplex sigma = turing_cis(program, angle, &of);
    const TuringComplex conj = {sigma.re, turing_negate(program, sigma.im)};
    TuringComplex term = turing_cmul(program, q, conj);
    for (unsigned int m = 0u; m < order; m += 1u)
    {
        turing_put_value(stage, term);
        if (m + 1u < order)
        {
            term = turing_cmul(program, term, eta);
        }
    }
}

// three expansions' sum, the fold that gathers a box's terms
static void turing_fold_build(TuringStage *stage, const TuringExpansion &layout)
{
    TuringProgram *const program = &stage->program;
    const TuringExpansionFields a = turing_expansion_fields(program, layout, 0u);
    const TuringExpansionFields b = turing_expansion_fields(program, layout, 1u);
    const TuringExpansionFields c = turing_expansion_fields(program, layout, 2u);
    for (size_t at = 0u; at < a.re.size(); at += 1u)
    {
        turing_put_value(stage, turing_cadd(program, turing_cadd(program, turing_read_at(program, a, at), turing_read_at(program, b, at)),
                                            turing_read_at(program, c, at)));
    }
}

// the child's center over the parent's, kappa = exp(i phi), phi = -/+ pi V_c / P for the lower and the upper child;
// s = (kappa - 1) / rho_p and r = kappa rho_c / rho_p = kappa / 2, from which eta_p = s + r eta_c and
// zeta_p = s + r zeta_c
typedef struct
{
    TuringComplex kappa;
    TuringComplex s;
    TuringComplex r_over_s;
} TuringShift;

// `turn` = phi / pi, `phi` = phi, `sign` = +1 or -1 the side, each a register
static TuringShift turing_shift(TuringProgram *program, unsigned int turn, unsigned int phi, unsigned int sign,
                                const TuringOsFields *of)
{
    TuringShift shift;
    shift.kappa = turing_cis(program, turn, of);
    const TuringComplex e1 = turing_e1i(program, phi, of);
    const TuringComplex ie1 = turing_ctimes_i(program, e1);
    // s = i phi E1(i phi) / (2 |phi|) = sign i E1 / 2
    TuringComplex signed_ie1;
    signed_ie1.re = turing_op(program, ENGINE_RECORD_PRODUCT, ie1.re, sign);
    signed_ie1.im = turing_op(program, ENGINE_RECORD_PRODUCT, ie1.im, sign);
    shift.s = turing_chalf(program, signed_ie1);
    const TuringComplex r = turing_chalf(program, shift.kappa);
    shift.r_over_s = turing_cmul(program, r, turing_crecip(program, shift.s));
    return shift;
}

// a child's multipole carried to its parent's center: member 0 the child's multipole, member 1 the shared record of
// 2^(l + 1) at parent level l, the side, -1 for the lower child and +1 for the upper, and the constants. The sum of
// a parent's two children's is its multipole.
// M_p,m = kappa (2 s)^m 2^(-m) sum over j <= m of binom(m, j) z_j, z_j = (r/s)^j M_c,j: |r/s| = 1 / |E1(i phi)|, which
// keeps each z_j within 1.2 |M_c|, held live in two limbs, and the binomial sum is exact; its one division by 2^m
// leaves each z_j's error where it was
static void turing_m2m_build(TuringStage *stage, const TuringExpansion &layout, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const TuringExpansionFields child = turing_expansion_fields(program, layout, 0u);
    const unsigned int order = (unsigned int)child.re.size();
    const unsigned int level_field = turing_param_field(stage, 48u);
    const unsigned int side_field = turing_param_field(stage, 3u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 1u, os);
    turing_anchor(stage, 1u);
    const unsigned int level = turing_read(program, level_field, 1u);
    const unsigned int side = turing_read(program, side_field, 1u);
    const unsigned int phi = turing_op(program, ENGINE_RECORD_PRODUCT,
                                       turing_op(program, ENGINE_RECORD_QUOTIENT, turing_read(program, of.pi, 1u), level), side);
    const unsigned int turn = turing_op(program, ENGINE_RECORD_PRODUCT,
                                        turing_op(program, ENGINE_RECORD_QUOTIENT, turing_constant(program, 1ull << TURING_SCALE_BITS), level),
                                        side);
    const TuringShift shift = turing_shift(program, turn, phi, side, &of);
    std::vector<TuringComplex> z(order);
    TuringComplex power = turing_cone(program);
    for (unsigned int j = 0u; j < order; j += 1u)
    {
        z[j] = turing_cwrap(program, turing_cmul(program, power, turing_read_at(program, child, j)), TURING_LIVE_BITS);
        if (j + 1u < order)
        {
            power = turing_cmul(program, power, shift.r_over_s);
        }
    }
    const TuringComplex two_s = turing_cadd(program, shift.s, shift.s);
    TuringComplex scale = shift.kappa;
    for (unsigned int m = 0u; m < order; m += 1u)
    {
        TuringComplex sum = {turing_constant(program, 0ull), turing_constant(program, 0ull)};
        for (unsigned int j = 0u; j <= m; j += 1u)
        {
            sum = turing_cweigh(program, sum, turing_weight(program, turing_binomial(m, j), 0u), z[j]);
        }
        turing_put_value(stage, turing_cmul(program, scale, turing_cshift_down(program, sum, m)));
        if (m + 1u < order)
        {
            scale = turing_cmul(program, scale, two_s);
        }
    }
}

// a source box's multipole carried to a target box's local expansion: member 0 the source's multipole, member 1 the
// shared record of Delta and 2^l at level l and the constants.
// L_n = (1 / D) (-(1 + D) rho / D)^n sum over m of binom(m + n, n) (rho / D)^m M_m. Both ratios are at most
// rho / |D| <= 0.22, and with y_m = (4 rho / D)^m M_m, held live in two limbs,
// L_n = (1 / D) (4 c)^n 4^(-2(N - 1)) sum over m of binom(m + n, n) 4^(2(N - 1) - m - n) y_m, c = -(1 + D) rho / D:
// the binomial sum is exact, and its one division leaves each y_m's error weighed by binom(m + n, n) 4^(-m - n)
static void turing_m2l_build(TuringStage *stage, const TuringExpansion &layout, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const TuringExpansionFields source = turing_expansion_fields(program, layout, 0u);
    const unsigned int order = (unsigned int)source.re.size();
    const unsigned int delta_field = turing_param_field(stage, 8u);
    const unsigned int level_field = turing_param_field(stage, 48u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 1u, os);
    turing_anchor(stage, 1u);
    const unsigned int delta = turing_read(program, delta_field, 1u);
    const unsigned int level = turing_read(program, level_field, 1u);
    const unsigned int phi = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_read(program, of.pi, 1u), level);
    // D = exp(i theta) - 1, theta / pi = 2 Delta / 2^l exactly, from cos and sin, whose Horner's rule runs in an
    // argument of at most 1; rho / D = phi / D and -(1 + D) rho / D = -(rho / D + phi)
    const unsigned int turn = turing_wrap(
        program,
        turing_op(program, ENGINE_RECORD_QUOTIENT,
                  turing_op(program, ENGINE_RECORD_PRODUCT, turing_op(program, ENGINE_RECORD_SUM, delta, delta),
                            turing_constant(program, 1ull << TURING_SCALE_BITS)),
                  level),
        TURING_SCALE_BITS + 1u);
    const TuringComplex around = turing_cis(program, turn, &of);
    const TuringComplex d = {turing_op(program, ENGINE_RECORD_DIFFERENCE, around.re, turing_constant(program, 1ull << TURING_SCALE_BITS)),
                             around.im};
    const TuringComplex inverse_d = turing_crecip(program, d);
    const TuringComplex rd = turing_cscale(program, inverse_d, phi);
    const TuringComplex ce = {turing_negate(program, turing_op(program, ENGINE_RECORD_SUM, rd.re, phi)), turing_negate(program, rd.im)};
    const unsigned int four = turing_constant(program, 4ull);
    const TuringComplex four_rd = {turing_op(program, ENGINE_RECORD_PRODUCT, rd.re, four), turing_op(program, ENGINE_RECORD_PRODUCT, rd.im, four)};
    const TuringComplex four_ce = {turing_op(program, ENGINE_RECORD_PRODUCT, ce.re, four), turing_op(program, ENGINE_RECORD_PRODUCT, ce.im, four)};
    std::vector<TuringComplex> y(order);
    TuringComplex power = turing_cone(program);
    for (unsigned int m = 0u; m < order; m += 1u)
    {
        y[m] = turing_cwrap(program, turing_cmul(program, power, turing_read_at(program, source, m)), TURING_LIVE_BITS);
        if (m + 1u < order)
        {
            power = turing_cmul(program, power, four_rd);
        }
    }
    const unsigned int top = 2u * (order - 1u);
    TuringComplex scale = inverse_d;
    for (unsigned int n = 0u; n < order; n += 1u)
    {
        TuringComplex sum = {turing_constant(program, 0ull), turing_constant(program, 0ull)};
        for (unsigned int m = 0u; m < order; m += 1u)
        {
            sum = turing_cweigh(program, sum, turing_weight(program, turing_binomial(m + n, n), 2u * (top - m - n)), y[m]);
        }
        turing_put_value(stage, turing_cmul(program, scale, turing_cshift_down(program, sum, 2u * top)));
        if (n + 1u < order)
        {
            scale = turing_cmul(program, scale, four_ce);
        }
    }
}

// a parent's local expansion carried to a child, with the child's own multipole-to-local sum added: member 0 the
// parent's local expansion, member 1 the child's sum, member 2 the shared record of 2^l at child level l and the
// constants. Lane T is box T, the lower child where T is even.
// L_c,j = (r/s)^j 2^(-(N - 1)) sum over n >= j of binom(n, j) 2^(N - 1 - n) (2 s)^n L_p,n. |2 s| = |E1(i phi)| <= 1,
// and the powers (2 s)^n are held live in two limbs; each (2 s)^n L_p,n is taken again where it is wanted, the
// binomial sum is exact, and its one division leaves each term's error weighed by binom(n, j) 2^(-n)
static void turing_l2l_build(TuringStage *stage, const TuringExpansion &layout, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const TuringExpansionFields parent = turing_expansion_fields(program, layout, 0u);
    const TuringExpansionFields own = turing_expansion_fields(program, layout, 1u);
    const unsigned int order = (unsigned int)parent.re.size();
    const unsigned int level_field = turing_param_field(stage, 48u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 2u, os);
    turing_anchor(stage, 2u);
    const unsigned int level = turing_read(program, level_field, 2u);
    const unsigned int parity = turing_op(program, ENGINE_RECORD_AND, turing_step(program, ENGINE_RECORD_LANE, 0u, 0u, 0u),
                                          turing_constant(program, 1ull));
    const unsigned int sign = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_op(program, ENGINE_RECORD_SUM, parity, parity),
                                        turing_constant(program, 1ull));
    const unsigned int phi = turing_op(program, ENGINE_RECORD_PRODUCT,
                                       turing_op(program, ENGINE_RECORD_QUOTIENT, turing_read(program, of.pi, 2u), level), sign);
    const unsigned int turn = turing_op(program, ENGINE_RECORD_PRODUCT,
                                        turing_op(program, ENGINE_RECORD_QUOTIENT, turing_constant(program, 1ull << TURING_SCALE_BITS), level),
                                        sign);
    const TuringShift shift = turing_shift(program, turn, phi, sign, &of);
    const TuringComplex two_s = turing_cadd(program, shift.s, shift.s);
    std::vector<TuringComplex> powers(order);
    powers[0] = turing_cone(program);
    for (unsigned int n = 1u; n < order; n += 1u)
    {
        powers[n] = turing_cwrap(program, turing_cmul(program, powers[n - 1u], two_s), TURING_LIVE_BITS);
    }
    TuringComplex scale = turing_cone(program);
    for (unsigned int j = 0u; j < order; j += 1u)
    {
        TuringComplex sum = {turing_constant(program, 0ull), turing_constant(program, 0ull)};
        for (unsigned int n = j; n < order; n += 1u)
        {
            const TuringComplex x = turing_cmul(program, powers[n], turing_read_at(program, parent, n));
            sum = turing_cweigh(program, sum, turing_weight(program, turing_binomial(n, j), order - 1u - n), x);
        }
        const TuringComplex carried = turing_cmul(program, scale, turing_cshift_down(program, sum, order - 1u));
        turing_put_value(stage, turing_cadd(program, carried, turing_read_at(program, own, j)));
        if (j + 1u < order)
        {
            scale = turing_cmul(program, scale, shift.r_over_s);
        }
    }
}

// the near field: lane (h - h_lo) S + slot reads its pole through the index and gives a D_P(h - pos) / P, where
// D_P(d) / P = exp(i pi d (P - 1) / P) sin(pi d) / (P sin(pi d / P)) = exp(...) (-1)^m (r / d) S(r^2) / S((d / P)^2),
// d = m + r with r in [-1/2, 1/2), which holds its precision where d is near 0. Member 1 the shared record of h_lo,
// S and the constants
static void turing_near_build(TuringStage *stage, unsigned int p, const TuringStage *pole, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const pos_place = turing_place(pole, 2u);
    const DeviceRecordStep *const are_place = turing_place(pole, 3u);
    const DeviceRecordStep *const aim_place = turing_place(pole, 4u);
    const unsigned int pos = turing_read(program, turing_member_field(program, pos_place->out_bits, pos_place->out_offset), 0u);
    TuringComplex a;
    a.re = turing_read(program, turing_member_field(program, are_place->out_bits, are_place->out_offset), 0u);
    a.im = turing_read(program, turing_member_field(program, aim_place->out_bits, aim_place->out_offset), 0u);
    const unsigned int low_field = turing_param_field(stage, 48u);
    const unsigned int slots_field = turing_param_field(stage, 48u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 1u, os);
    const unsigned int unit = turing_constant(program, 1ull << TURING_SCALE_BITS);
    const unsigned int h = turing_op(program, ENGINE_RECORD_SUM, turing_read(program, low_field, 1u),
                                     turing_op(program, ENGINE_RECORD_QUOTIENT, turing_lane(program, TURING_OS_LANE_BITS),
                                               turing_read(program, slots_field, 1u)));
    const unsigned int d = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_op(program, ENGINE_RECORD_PRODUCT, h, unit), pos);
    const unsigned int r = turing_wrap(program, d, TURING_SCALE_BITS);
    const unsigned int whole = turing_op(program, ENGINE_RECORD_EXACT_QUOTIENT, turing_op(program, ENGINE_RECORD_DIFFERENCE, d, r), unit);
    const unsigned int parity = turing_op(program, ENGINE_RECORD_AND, whole, turing_constant(program, 1ull));
    const unsigned int sign = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 1ull),
                                        turing_op(program, ENGINE_RECORD_SUM, parity, parity));
    const unsigned int zero = turing_equal(program, d, turing_constant(program, 0ull));
    const unsigned int r_over_d = turing_op(program, ENGINE_RECORD_QUOTIENT,
                                            turing_op(program, ENGINE_RECORD_PRODUCT, turing_op(program, ENGINE_RECORD_SUM, r, zero), unit),
                                            turing_op(program, ENGINE_RECORD_SUM, d, zero));
    const unsigned int top = turing_sinc(program, turing_scaled(program, r, r), &of);
    const unsigned int small = turing_op(program, ENGINE_RECORD_QUOTIENT, d, turing_power(program, p));
    const unsigned int bottom = turing_sinc(program, turing_scaled(program, small, small), &of);
    const unsigned int ratio = turing_op(program, ENGINE_RECORD_PRODUCT,
                                         turing_scaled(program,
                                                       turing_wrap(program,
                                                                   turing_op(program, ENGINE_RECORD_QUOTIENT,
                                                                             turing_op(program, ENGINE_RECORD_PRODUCT, top, unit), bottom),
                                                                   TURING_HELD_BITS),
                                                       r_over_d),
                                         sign);
    const unsigned int phase = turing_wrap(program, turing_op(program, ENGINE_RECORD_DIFFERENCE, d, small), TURING_SCALE_BITS + 1u);
    const TuringComplex turn = turing_cis(program, phase, &of);
    const TuringComplex value = turing_cmul(program, a, turing_cscale(program, turn, ratio));
    stage->outputs.push_back(value.re);
    stage->outputs.push_back(value.im);
}

// u_h / P at each point: lane o, h = o - P/2, reads its leaf's local expansion and its near sum through the index:
// sum of L_n zeta^n + near, zeta = (z / sigma - 1) / rho = u i E1(i psi), u = 2 (h - c) / W, psi = u pi W / P.
// Member 2 the shared record of the constants
static void turing_eval_build(TuringStage *stage, unsigned int p, unsigned int beta, const TuringExpansion &layout,
                              unsigned int near_bits, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    const TuringExpansionFields local = turing_expansion_fields(program, layout, 0u);
    TuringComplex near;
    near.re = turing_read(program, turing_member_field(program, near_bits, 0u), 1u);
    near.im = turing_read(program, turing_member_field(program, near_bits, near_bits), 1u);
    TuringOsFields of;
    turing_os_fields(stage, &of, 2u, os);
    const unsigned int lane = turing_lane(program, TURING_OS_LANE_BITS);
    const unsigned int offset = turing_op(program, ENGINE_RECORD_DIFFERENCE,
                                          turing_op(program, ENGINE_RECORD_AND, lane, turing_constant(program, (1ull << beta) - 1ull)),
                                          turing_constant(program, 1ull << (beta - 1u)));
    const unsigned int u = turing_op(program, ENGINE_RECORD_PRODUCT, offset, turing_power(program, TURING_SCALE_BITS + 1u - beta));
    const unsigned int psi = turing_op(program, ENGINE_RECORD_QUOTIENT, turing_scaled(program, u, turing_read(program, of.pi, 2u)),
                                       turing_power(program, p - beta));
    const TuringComplex zeta = turing_cscale(program, turing_ctimes_i(program, turing_e1i(program, psi, &of)), u);
    TuringComplex acc = turing_read_at(program, local, local.re.size() - 1u);
    for (size_t n = local.re.size() - 1u; n > 0u; n -= 1u)
    {
        acc = turing_cadd(program, turing_cmul(program, acc, zeta), turing_read_at(program, local, n - 1u));
    }
    const TuringComplex value = turing_cwrap(program, turing_cadd(program, acc, near), TURING_EXP_BITS);
    stage->outputs.push_back(value.re);
    stage->outputs.push_back(value.im);
}

// the transform's twiddles exp(-2 pi i t / P), lane t
static void turing_twiddle_build(TuringStage *stage, unsigned int p, const TuringOsConstants &os)
{
    TuringProgram *const program = &stage->program;
    TuringOsFields of;
    turing_os_fields(stage, &of, 0u, os);
    const unsigned int angle = turing_wrap(
        program,
        turing_negate(program, turing_op(program, ENGINE_RECORD_PRODUCT, turing_lane(program, TURING_OS_LANE_BITS),
                                         turing_power(program, TURING_SCALE_BITS + 1u - p))),
        TURING_SCALE_BITS + 1u);
    const TuringComplex turn = turing_cis(program, angle, &of);
    stage->outputs.push_back(turn.re);
    stage->outputs.push_back(turn.im);
}

// one stage of Stockham's transform: lane o reads x[j], x[j + P/2] and the twiddle t through the index and gives
// x[j] + w_t x[j + P/2]; the index carries the stage, with w_(t + P/2) = -w_t for the lower half
static void turing_fft_build(TuringStage *stage, const TuringExpansion &values, const TuringStage *twiddle)
{
    TuringProgram *const program = &stage->program;
    const TuringComplex v0 = turing_read_at(program, turing_expansion_fields(program, values, 0u), 0u);
    const TuringComplex v1 = turing_read_at(program, turing_expansion_fields(program, values, 1u), 0u);
    const DeviceRecordStep *const re_place = turing_place(twiddle, 0u);
    const DeviceRecordStep *const im_place = turing_place(twiddle, 1u);
    TuringComplex w;
    w.re = turing_read(program, turing_member_field(program, re_place->out_bits, re_place->out_offset), 2u);
    w.im = turing_read(program, turing_member_field(program, im_place->out_bits, im_place->out_offset), 2u);
    const TuringComplex value = turing_cwrap(program, turing_cadd(program, v0, turing_cmul(program, w, v1)), TURING_EXP_BITS);
    stage->outputs.push_back(value.re);
    stage->outputs.push_back(value.im);
}

// the verdict stage over the transform: member 0 F at each point, member 1 the point records, member 2 the shared
// record; the main sum's half is Re(exp(i theta) F) = cos theta Re F - sin theta Im F
static unsigned int turing_main_from_transform(TuringProgram *program, const TuringExpansion &values, const TuringStage *point)
{
    const TuringComplex f = turing_read_at(program, turing_expansion_fields(program, values, 0u), 0u);
    const DeviceRecordStep *const cos_place = turing_place(point, 2u);
    const DeviceRecordStep *const sin_place = turing_place(point, 3u);
    const unsigned int c = turing_read(program, turing_member_field(program, cos_place->out_bits, cos_place->out_offset), 1u);
    const unsigned int s = turing_read(program, turing_member_field(program, sin_place->out_bits, sin_place->out_offset), 1u);
    return turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_scaled(program, c, f.re), turing_scaled(program, s, f.im));
}

// the verdict stage: member 0 the sums, member 1 the point records, member 2 the shared record of nu^2 2^p,
// 2 nu + 1 and the bounds
// member 0 is the transform's F where `transform` is given, its layout, and the pair stage's sums where it is not.
// The shared record's fields are the stage's parameters, in order
static void turing_verdict_build(TuringStage *stage, unsigned int p, unsigned int sum_limbs, const TuringStage *point,
                                 unsigned int bound_bits, unsigned int theta_bits, const TuringExpansion *transform)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const held_place = turing_place(point, 0u);
    const DeviceRecordStep *const theta_place = turing_place(point, 1u);
    const unsigned int held_field = turing_member_field(program, held_place->out_bits, held_place->out_offset);
    const unsigned int theta_field = turing_member_field(program, theta_place->out_bits, theta_place->out_offset);
    program->shared_bits = 0u;
    const unsigned int floor_field = turing_param_field(stage, TURING_S_BITS);
    const unsigned int step_field = turing_param_field(stage, TURING_NU_BITS + 3u);
    const unsigned int bound_field = turing_param_field(stage, bound_bits);
    const unsigned int theta_bound_field = turing_param_field(stage, theta_bits);
    stage->shared.assign((program->shared_bits + 31u) / 32u, 0u);

    const unsigned int lane = turing_lane(program, p + 1u);
    const unsigned int step = turing_read(program, step_field, 2u);
    const unsigned int big_s = turing_op(program, ENGINE_RECORD_SUM, turing_read(program, floor_field, 2u),
                                         turing_op(program, ENGINE_RECORD_PRODUCT, lane, step));
    const unsigned int sum = (transform != NULL) ? turing_main_from_transform(program, *transform, point)
                                                 : turing_read(program, turing_member_field(program, 32u * sum_limbs, 0u), 0u);
    const unsigned int z = turing_op(program, ENGINE_RECORD_SUM, turing_op(program, ENGINE_RECORD_SUM, sum, sum),
                                     turing_read(program, held_field, 1u));
    const unsigned int bound = turing_read(program, bound_field, 2u);
    const unsigned int below = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 0ull), bound);
    const unsigned int sign = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_above(program, z, bound),
                                        turing_above(program, below, z));
    const unsigned int theta = turing_read(program, theta_field, 1u);
    const unsigned int theta_bound = turing_read(program, theta_bound_field, 2u);
    const unsigned int low = turing_op(program, ENGINE_RECORD_DIFFERENCE, theta, theta_bound);
    const unsigned int high = turing_op(program, ENGINE_RECORD_SUM, theta, theta_bound);
    const unsigned int low_step = turing_op(program, ENGINE_RECORD_PRODUCT, step, low);
    const unsigned int high_step = turing_op(program, ENGINE_RECORD_PRODUCT, step, high);
    const unsigned int listed[7] = {sign, big_s, low, high, low_step, high_step, z};
    stage->outputs.assign(listed, listed + 7);
}

// the count stage: members 0, 1 and 2 the verdict records at q, q - 1 and q - 2
static void turing_count_build(TuringStage *stage, unsigned int p, const TuringStage *verdict)
{
    TuringProgram *const program = &stage->program;
    const DeviceRecordStep *const sign_place = turing_place(verdict, 0u);
    const DeviceRecordStep *const s_place = turing_place(verdict, 1u);
    const unsigned int sign_field = turing_member_field(program, sign_place->out_bits, sign_place->out_offset);
    const unsigned int s_field = turing_member_field(program, s_place->out_bits, s_place->out_offset);
    unsigned int sign[3], big_s[3];
    for (unsigned int back = 0u; back < 3u; back += 1u)
    {
        sign[back] = turing_read(program, sign_field, back);
        big_s[back] = turing_read(program, s_field, back);
    }
    const unsigned int certified = turing_op(program, ENGINE_RECORD_ABSOLUTE, sign[0], 0u);
    const unsigned int other = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 0ull), sign[0]);
    const unsigned int one_back = turing_equal(program, sign[1], other);
    const unsigned int gap = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 1ull),
                                       turing_op(program, ENGINE_RECORD_ABSOLUTE, sign[1], 0u));
    const unsigned int two_back = turing_op(program, ENGINE_RECORD_PRODUCT, gap, turing_equal(program, sign[2], other));
    const unsigned int zero = turing_op(program, ENGINE_RECORD_PRODUCT, certified,
                                        turing_op(program, ENGINE_RECORD_SUM, one_back, two_back));
    const unsigned int at_q = turing_op(program, ENGINE_RECORD_PRODUCT, zero, big_s[0]);
    const unsigned int at_p = turing_op(program, ENGINE_RECORD_PRODUCT, certified,
                                        turing_op(program, ENGINE_RECORD_SUM,
                                                  turing_op(program, ENGINE_RECORD_PRODUCT, one_back, big_s[1]),
                                                  turing_op(program, ENGINE_RECORD_PRODUCT, two_back, big_s[2])));
    const unsigned int grown = turing_above(program, turing_lane(program, p + 1u), turing_constant(program, 1ull));
    const unsigned int second_gap = turing_op(program, ENGINE_RECORD_DIFFERENCE, turing_constant(program, 1ull),
                                              turing_op(program, ENGINE_RECORD_ABSOLUTE, sign[2], 0u));
    const unsigned int loose = turing_op(program, ENGINE_RECORD_PRODUCT, turing_op(program, ENGINE_RECORD_PRODUCT, grown, certified),
                                         turing_op(program, ENGINE_RECORD_PRODUCT, gap, second_gap));
    const unsigned int listed[4] = {zero, at_q, at_p, loose};
    stage->outputs.assign(listed, listed + 4);
}

static int turing_word(FILE *in, long long *value)
{
    return fread(value, sizeof(long long), 1u, in) == 1u;
}

static int turing_read_constant(FILE *in, TuringConstant *constant)
{
    long long limbs = 0;
    int read = turing_word(in, &limbs) && (limbs >= 0) && (limbs < 4096);
    constant->magnitude.assign(read ? (size_t)limbs : 0u, 0u);
    read = read && (fread(constant->magnitude.data(), sizeof(unsigned int), constant->magnitude.size(), in) ==
                    constant->magnitude.size());
    read = read && turing_word(in, &constant->sign);
    unsigned int width = 32u * (unsigned int)constant->magnitude.size();
    while ((width > 0u) && (((constant->magnitude[(width - 1u) / 32u] >> ((width - 1u) % 32u)) & 1u) == 0u))
    {
        width -= 1u;
    }
    constant->bits = width + 1u;
    return read;
}

// `bits` of a two's complement value, its magnitude's limbs given, laid at `offset` of `record`
static void turing_put(unsigned int *record, unsigned int offset, unsigned int bits, const std::vector<unsigned int> &limbs,
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

static void turing_put_field(TuringStage *stage, unsigned int field, const std::vector<unsigned int> &limbs, long long sign)
{
    turing_put(stage->shared.data(), stage->program.field_offset[field], stage->program.field_bits[field], limbs, sign);
}

static void turing_put_small(TuringStage *stage, unsigned int field, unsigned long long value, long long sign)
{
    const std::vector<unsigned int> limbs = {(unsigned int)value, (unsigned int)(value >> 32u)};
    turing_put_field(stage, field, limbs, sign);
}

// the stage's shared record laid out and its constants filled
static void turing_seal(TuringStage *stage)
{
    stage->shared.assign((stage->program.shared_bits + 31u) / 32u + 1u, 0u);
    for (size_t at = 0u; at < stage->put_field.size(); at += 1u)
    {
        turing_put_field(stage, stage->put_field[at], stage->put_limbs[at], stage->put_sign[at]);
    }
}

static void turing_open_stage(TuringStage *stage, const char *name, unsigned int members)
{
    stage->name = name;
    stage->members = members;
    stage->program.shared_bits = 0u;
    stage->anchored = 0;
    stage->swept = 0u;
    memset(stage->in_limbs, 0, sizeof(stage->in_limbs));
    memset(&stage->key, 0, sizeof(stage->key));
    memset(&stage->layout, 0, sizeof(stage->layout));
    stage->record = NULL;
}

// imprints, lays out and loads a stage's program, and says where it stops when it does
static int turing_load(SimResults *job, TuringStage *stage, EngineError *error)
{
    TuringProgram *const program = &stage->program;
    const unsigned int fields = (unsigned int)program->field_bits.size();
    const KeymathRecordRequest encode = {program->steps.data(),
                                         (unsigned int)program->steps.size(),
                                         program->field_bits.data(),
                                         fields,
                                         stage->members,
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
                "  exact_zeta_turing: the %s imprint errors, site %u, at step %lld of %zu, operation %d left %u right %u\n",
                stage->name, error->site, step, program->steps.size(), (step >= 0) ? (int)at->operation : -1,
                (step >= 0) ? at->left : 0u, (step >= 0) ? at->right : 0u);
    }
    sim_check(job, ok, (std::string("keymath imprints the ") + stage->name + " program").c_str());
    const KeyScheduleRecordRequest lay = {&stage->key, program->field_offset.data(), fields, stage->in_limbs, 1,
                                          &stage->layout, error};
    const int laid = ok && (key_schedule_record_layout(&lay) != KEY_SCHEDULE_ERROR);
    if (ok && !laid)
    {
        const char *const end = (error->evacaddr == (const void *)&stage->key)       ? "the register file"
                                : (error->evacaddr == (const void *)stage->key.output) ? "the outputs"
                                                                                        : "a step";
        fprintf(stderr, "  exact_zeta_turing: the %s layout ends at %s\n", stage->name, end);
    }
    ok = laid;
    sim_check(job, ok, (std::string("the scheduler lays the ") + stage->name + " program out").c_str());
    ok = ok && (cycle_record_load(&stage->layout, &stage->record, error) != CYCLE_ERROR);
    sim_check(job, ok, (std::string("the ") + stage->name + " program loads onto the device").c_str());
    return ok;
}

// runs a stage's lanes on the device over its members, the records left in device memory
static int turing_run(TuringStage *stage, unsigned int *const members[3], const unsigned long long bodies[3],
                      const unsigned int *device_index, unsigned long long lanes, unsigned int *device_out,
                      EngineError *error)
{
    const CycleRecordRunRequest run = {stage->record, {members[0], members[1], members[2]}, {bodies[0], bodies[1], bodies[2]},
                                       device_index, lanes, device_out, error};
    return cycle_record_run(&run) == (long)lanes;
}

// the host's run of a stage over its first `checked` lanes, against the device's records
static int turing_check(const TuringStage *stage, unsigned int *const members[3], const unsigned long long bodies[3],
                        const unsigned int *index, unsigned long long checked, const unsigned int *device_records,
                        EngineError *error)
{
    std::vector<unsigned int> host_out((size_t)(checked * stage->layout.out_limbs));
    const CycleRecordHostRequest host = {&stage->layout, {members[0], members[1], members[2]},
                                         {bodies[0], bodies[1], bodies[2]}, index, checked, host_out.data(), error};
    return (cycle_record_run_host(&host) == (long)checked) &&
           (memcmp(host_out.data(), device_records, host_out.size() * sizeof(unsigned int)) == 0);
}

static std::vector<unsigned int> turing_copy_back(const unsigned int *device, size_t words)
{
    std::vector<unsigned int> host(words, 0u);
    if ((words != 0u) && (cudaMemcpy(host.data(), device, words * sizeof(unsigned int), cudaMemcpyDeviceToHost) != cudaSuccess))
    {
        host.clear();
    }
    return host;
}

// a two's complement value of `limbs` limbs, written as a signed hexadecimal integer
static void turing_hex(FILE *out, const unsigned int *word, unsigned int limbs)
{
    std::vector<unsigned int> value(word, word + limbs);
    const int negative = (limbs != 0u) && ((value[limbs - 1u] >> 31u) != 0u);
    if (negative)
    {
        unsigned long long carry = 1ull;
        for (unsigned int at = 0u; at < limbs; at += 1u)
        {
            const unsigned int flipped = ~value[at];
            carry += (unsigned long long)flipped;
            value[at] = (unsigned int)carry;
            carry >>= 32u;
        }
    }
    unsigned int top = limbs;
    while ((top > 1u) && (value[top - 1u] == 0u))
    {
        top -= 1u;
    }
    fprintf(out, negative ? " -%x" : " %x", (top != 0u) ? value[top - 1u] : 0u);
    for (unsigned int at = top - 1u; (top != 0u) && (at-- > 0u);)
    {
        fprintf(out, "%08x", value[at]);
    }
}

// output `output` of record `lane` of a stage's records on the host, sign-extended into limbs
static std::vector<unsigned int> turing_output(const TuringStage *stage, const std::vector<unsigned int> &records,
                                               unsigned long long lane, unsigned int output)
{
    const DeviceRecordStep *const step = turing_place(stage, output);
    const unsigned int limbs = (step->out_bits + 31u) / 32u + 1u;
    std::vector<unsigned int> value(limbs, 0u);
    const unsigned int *const record = &records[(size_t)(lane * stage->layout.out_limbs)];
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        value[bit / 32u] |= ((record[from / 32u] >> (from % 32u)) & 1u) << (bit % 32u);
    }
    if (((value[(step->out_bits - 1u) / 32u] >> ((step->out_bits - 1u) % 32u)) & 1u) != 0u)
    {
        for (unsigned int bit = step->out_bits; bit < 32u * limbs; bit += 1u)
        {
            value[bit / 32u] |= 1u << (bit % 32u);
        }
    }
    return value;
}

static void turing_write_output(FILE *out, const TuringStage *stage, const std::vector<unsigned int> &records,
                                unsigned long long lane, unsigned int output)
{
    const std::vector<unsigned int> value = turing_output(stage, records, lane, output);
    turing_hex(out, value.data(), (unsigned int)value.size());
}

// the sum of output `output` over lanes [first, first + count) of a stage's records, on the device and on the host,
// written after `key`; 1 where the two agree word for word
static int turing_range(FILE *out, const char *key, const TuringStage *stage, const unsigned int *device_records,
                        const std::vector<unsigned int> &host_records, unsigned long long first, unsigned long long count,
                        unsigned int output, EngineError *error)
{
    const DeviceRecordStep *const step = turing_place(stage, output);
    const unsigned int limbs = (step->out_bits + 40u + 31u) / 32u + 1u;
    std::vector<unsigned int> sum(limbs, 0u), host_sum(limbs, 0u);
    int same = 1;
    if (count != 0ull)
    {
        const unsigned int out_limbs = stage->layout.out_limbs;
        const CycleRecordSumRequest device = {device_records + first * out_limbs, count, count, out_limbs,
                                              step->out_offset, step->out_bits, limbs, sum.data(), error};
        const CycleRecordSumRequest host = {host_records.data() + first * out_limbs, count, count, out_limbs,
                                            step->out_offset, step->out_bits, limbs, host_sum.data(), error};
        same = (cycle_record_sum(&device) != CYCLE_ERROR) && (cycle_record_sum_host(&host) != CYCLE_ERROR) &&
               (memcmp(sum.data(), host_sum.data(), limbs * sizeof(unsigned int)) == 0);
    }
    fprintf(out, "%s", key);
    turing_hex(out, sum.data(), limbs);
    fprintf(out, "\n");
    return same;
}

static void turing_release(TuringStage *stage)
{
    if (stage->record != NULL)
    {
        cycle_record_release(stage->record);
    }
    key_schedule_record_release(&stage->layout);
    keymath_record_release(&stage->key);
}


// device memory the run owns, zeroed, freed at its end
static unsigned int *turing_alloc(std::vector<unsigned int *> *owned, size_t words)
{
    unsigned int *device = NULL;
    if ((cudaMalloc((void **)&device, (words + 1u) * sizeof(unsigned int)) != cudaSuccess) ||
        (cudaMemset(device, 0, (words + 1u) * sizeof(unsigned int)) != cudaSuccess))
    {
        return NULL;
    }
    owned->push_back(device);
    return device;
}

static unsigned int *turing_upload(std::vector<unsigned int *> *owned, const std::vector<unsigned int> &host)
{
    unsigned int *const device = turing_alloc(owned, host.size());
    if ((device != NULL) && !host.empty() &&
        (cudaMemcpy(device, host.data(), host.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) != cudaSuccess))
    {
        return NULL;
    }
    return device;
}

// a run of a stage over `lanes` lanes on the device, its members wired by `index` where it is not empty, and the
// host's run of its first `checked` lanes against the device's records; 1 where the run holds, and `same` keeps 0
// once a check differs
static int turing_sweep(TuringStage *stage, unsigned int *const members[3],
                        const unsigned long long bodies[3], const std::vector<unsigned int> &index, unsigned long long lanes,
                        unsigned int *device_out, unsigned long long checked, EngineError *error, int *same)
{
    if (lanes == 0ull)
    {
        return 1;
    }
    // the index lives for the run alone
    unsigned int *device_index = NULL;
    int ok = index.empty() ||
             ((cudaMalloc((void **)&device_index, index.size() * sizeof(unsigned int)) == cudaSuccess) &&
              (cudaMemcpy(device_index, index.data(), index.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
               cudaSuccess));
    ok = ok && turing_run(stage, members, bodies, device_index, lanes, device_out, error);
    if (device_index != NULL)
    {
        cudaFree(device_index);
    }
    const unsigned long long wanted = (stage->swept == 0u) ? checked : 1ull;
    const unsigned long long tried = (wanted < lanes) ? wanted : lanes;
    stage->swept += 1u;
    std::vector<std::vector<unsigned int> > host_members(3u);
    unsigned int *host_pointers[3] = {NULL, NULL, NULL};
    for (unsigned int member = 0u; ok && (member < stage->members); member += 1u)
    {
        host_members[member] = turing_copy_back(members[member], (size_t)(bodies[member] * stage->in_limbs[member]));
        ok = !host_members[member].empty();
        host_pointers[member] = host_members[member].data();
    }
    const std::vector<unsigned int> records =
        ok ? turing_copy_back(device_out, (size_t)(tried * stage->layout.out_limbs)) : std::vector<unsigned int>();
    ok = ok && !records.empty();
    const int checks = ok && turing_check(stage, host_pointers, bodies, index.empty() ? NULL : index.data(), tried,
                                          records.data(), error);
    *same = *same && checks;
    return ok;
}

// a stage's shared record on the device, its parameters set first
static unsigned int *turing_shared(std::vector<unsigned int *> *owned, TuringStage *stage, const std::vector<long long> &params)
{
    for (size_t at = 0u; (at < params.size()) && (at < stage->params.size()); at += 1u)
    {
        const unsigned long long magnitude = (params[at] < 0) ? (unsigned long long)(-params[at]) : (unsigned long long)params[at];
        turing_put_small(stage, stage->params[at], magnitude, (params[at] < 0) ? -1 : 1);
    }
    return turing_upload(owned, stage->shared);
}

// a stage's shared records on the device, one for each list of parameters, in order: a lane reads the one its index
// names
static unsigned int *turing_shared_records(std::vector<unsigned int *> *owned, TuringStage *stage,
                                           const std::vector<std::vector<long long> > &params)
{
    std::vector<unsigned int> records;
    for (size_t record = 0u; record < params.size(); record += 1u)
    {
        for (size_t at = 0u; (at < params[record].size()) && (at < stage->params.size()); at += 1u)
        {
            const long long value = params[record][at];
            turing_put_small(stage, stage->params[at], (value < 0) ? (unsigned long long)(-value) : (unsigned long long)value,
                             (value < 0) ? -1 : 1);
        }
        records.insert(records.end(), stage->shared.begin(), stage->shared.end());
    }
    return turing_upload(owned, records);
}

// sums of output `output` over each run of `group` records, to the host, each as a signed 64-bit value
static std::vector<long long> turing_group_sums(const TuringStage *stage, const unsigned int *device_records,
                                                unsigned long long count, unsigned long long group, unsigned int output,
                                                unsigned int sum_limbs, EngineError *error, int *ok)
{
    const DeviceRecordStep *const place = turing_place(stage, output);
    std::vector<unsigned int> sums((size_t)((count / group) * sum_limbs), 0u);
    const CycleRecordSumRequest request = {device_records, count, group, stage->layout.out_limbs, place->out_offset,
                                           place->out_bits, sum_limbs, sums.data(), error};
    *ok = *ok && (count == 0ull || cycle_record_sum(&request) != CYCLE_ERROR);
    std::vector<long long> values((size_t)(count / group), 0);
    for (size_t at = 0u; at < values.size(); at += 1u)
    {
        values[at] = (long long)(((unsigned long long)sums[at * sum_limbs + 1u] << 32u) | sums[at * sum_limbs]);
    }
    return values;
}

// the fold of each group of `group` expansions, record `map[g * group + slot]` of `records` (the array's last record,
// `zero`, where a slot is empty), into one expansion a group, by sums of three; returns the array of one a group
static unsigned int *turing_fold(std::vector<unsigned int *> *owned, TuringStage *fold, unsigned int *records,
                                 unsigned long long zero, std::vector<unsigned int> map, unsigned long long groups,
                                 unsigned long long group, unsigned long long checked, EngineError *error, int *same, int *ok)
{
    unsigned int *current = records;
    unsigned long long current_zero = zero;
    const unsigned int limbs = fold->layout.out_limbs;
    while (*ok && (group > 1ull || map.size() != groups))
    {
        const unsigned long long next = (group + 2ull) / 3ull;
        const unsigned long long lanes = groups * next;
        std::vector<unsigned int> index((size_t)(3ull * lanes), 0u);
        for (unsigned long long g = 0ull; g < groups; g += 1ull)
        {
            for (unsigned long long j = 0ull; j < next; j += 1ull)
            {
                for (unsigned long long t = 0ull; t < 3ull; t += 1ull)
                {
                    const unsigned long long slot = 3ull * j + t;
                    index[(size_t)(3ull * (g * next + j) + t)] =
                        (unsigned int)((slot < group) ? map[(size_t)(g * group + slot)] : current_zero);
                }
            }
        }
        unsigned int *const out = turing_alloc(owned, (size_t)((lanes + 1ull) * limbs));
        unsigned int *const members[3] = {current, current, current};
        const unsigned long long bodies[3] = {current_zero + 1ull, current_zero + 1ull, current_zero + 1ull};
        *ok = (out != NULL) && turing_sweep(fold, members, bodies, index, lanes, out, checked, error, same);
        current = out;
        current_zero = lanes;
        group = next;
        map.resize((size_t)lanes);
        for (unsigned long long at = 0ull; at < lanes; at += 1ull)
        {
            map[(size_t)at] = (unsigned int)at;
        }
    }
    return current;
}

// the circular distance of boxes a and b among `boxes`
static unsigned long long turing_apart(unsigned long long a, unsigned long long b, unsigned long long boxes)
{
    const unsigned long long d = (a > b) ? (a - b) : (b - a);
    return (d < boxes - d) ? d : boxes - d;
}

typedef struct
{
    std::vector<unsigned int> steps;
} TuringOsReport;

// the multiple evaluation: from the pole records (nu of them and a zero record after), F at every point of the cell
// into the returned array, laid out as `values`
static unsigned int *turing_os(SimResults *job, std::vector<unsigned int *> *owned, unsigned long long nu, unsigned int p,
                               unsigned int beta, unsigned int order, unsigned long long checked,
                               const TuringOsConstants &os, TuringStage *pole, unsigned int *device_pole,
                               TuringExpansion *values, TuringOsReport *report, EngineError *error, int *same)
{
    const unsigned long long points = 1ull << p;
    const unsigned long long width = 1ull << beta;
    const unsigned long long leaves = points >> beta;
    const unsigned int top = p - beta;
    const unsigned long long poles = nu + 1ull;
    int ok = (top >= 3u) && (beta >= 2u);
    sim_check(job, ok, "the cell holds three levels of boxes or more");

    TuringStage below, p2m, fold, m2m, m2l, l2l, near, eval, twiddle, fft;
    turing_open_stage(&below, "below", 2u);
    turing_open_stage(&p2m, "leaf multipole", 2u);
    turing_open_stage(&fold, "fold", 3u);
    turing_open_stage(&m2m, "multipole shift", 2u);
    turing_open_stage(&m2l, "multipole to local", 2u);
    turing_open_stage(&l2l, "local shift", 3u);
    turing_open_stage(&near, "near field", 2u);
    turing_open_stage(&eval, "evaluation", 3u);
    turing_open_stage(&twiddle, "twiddle", 1u);
    turing_open_stage(&fft, "transform", 3u);
    TuringStage *const stages[10] = {&below, &p2m, &fold, &m2m, &m2l, &l2l, &near, &eval, &twiddle, &fft};

    TuringExpansion expansion;
    unsigned int near_limbs = 0u;
    if (ok)
    {
        turing_below_build(&below, beta, pole);
        turing_seal(&below);
        below.in_limbs[0] = pole->layout.out_limbs;
        below.in_limbs[1] = (unsigned int)below.shared.size();
        ok = turing_load(job, &below, error);
    }
    if (ok)
    {
        turing_p2m_build(&p2m, p, beta, order, pole, os);
        turing_seal(&p2m);
        p2m.in_limbs[0] = pole->layout.out_limbs;
        p2m.in_limbs[1] = (unsigned int)p2m.shared.size();
        ok = turing_load(job, &p2m, error);
        expansion = turing_expansion_of(&p2m);
    }
    if (ok)
    {
        turing_fold_build(&fold, expansion);
        fold.in_limbs[0] = fold.in_limbs[1] = fold.in_limbs[2] = expansion.out_limbs;
        ok = turing_load(job, &fold, error) && turing_same_expansion(turing_expansion_of(&fold), expansion);
    }
    if (ok)
    {
        turing_m2m_build(&m2m, expansion, os);
        turing_seal(&m2m);
        m2m.in_limbs[0] = expansion.out_limbs;
        m2m.in_limbs[1] = (unsigned int)m2m.shared.size();
        ok = turing_load(job, &m2m, error) && turing_same_expansion(turing_expansion_of(&m2m), expansion);
    }
    if (ok)
    {
        turing_m2l_build(&m2l, expansion, os);
        turing_seal(&m2l);
        m2l.in_limbs[0] = expansion.out_limbs;
        m2l.in_limbs[1] = (unsigned int)m2l.shared.size();
        ok = turing_load(job, &m2l, error) && turing_same_expansion(turing_expansion_of(&m2l), expansion);
    }
    if (ok)
    {
        turing_l2l_build(&l2l, expansion, os);
        turing_seal(&l2l);
        l2l.in_limbs[0] = l2l.in_limbs[1] = expansion.out_limbs;
        l2l.in_limbs[2] = (unsigned int)l2l.shared.size();
        ok = turing_load(job, &l2l, error) && turing_same_expansion(turing_expansion_of(&l2l), expansion);
    }
    if (ok)
    {
        turing_near_build(&near, p, pole, os);
        turing_seal(&near);
        near.in_limbs[0] = pole->layout.out_limbs;
        near.in_limbs[1] = (unsigned int)near.shared.size();
        ok = turing_load(job, &near, error);
    }
    if (ok)
    {
        const unsigned int widest = (turing_place(&near, 0u)->out_bits > turing_place(&near, 1u)->out_bits)
                                        ? turing_place(&near, 0u)->out_bits
                                        : turing_place(&near, 1u)->out_bits;
        near_limbs = (widest + 24u + 31u) / 32u + 1u;
        turing_eval_build(&eval, p, beta, expansion, 32u * near_limbs, os);
        turing_seal(&eval);
        eval.in_limbs[0] = expansion.out_limbs;
        eval.in_limbs[1] = 2u * near_limbs;
        eval.in_limbs[2] = (unsigned int)eval.shared.size();
        ok = turing_load(job, &eval, error);
        *values = turing_expansion_of(&eval);
    }
    if (ok)
    {
        turing_twiddle_build(&twiddle, p, os);
        turing_seal(&twiddle);
        twiddle.in_limbs[0] = (unsigned int)twiddle.shared.size();
        ok = turing_load(job, &twiddle, error);
    }
    if (ok)
    {
        turing_fft_build(&fft, *values, &twiddle);
        fft.in_limbs[0] = fft.in_limbs[1] = values->out_limbs;
        fft.in_limbs[2] = twiddle.layout.out_limbs;
        ok = turing_load(job, &fft, error) && turing_same_expansion(turing_expansion_of(&fft), *values);
    }
    sim_check(job, ok, "the multiple evaluation's programs load, every expansion laid out alike");
    const unsigned int limbs = ok ? expansion.out_limbs : 0u;

    // the poles below each leaf boundary b W, b from 0, the frequency 0's leaf first, up to the leaf past
    // pos_nu = (2 nu + 1) ln nu <= (2 nu + 1) 0.7 log2(2 nu) and two leaves short of P/2 at most, which keeps every
    // pole's near field off the circle's far side; the device's count holds every pole below the last boundary, and the
    // leaves end at the first boundary with every pole below it
    unsigned int bits = 0u;
    while ((nu >> bits) != 0ull)
    {
        bits += 1u;
    }
    const unsigned long long reach = ((2ull * nu + 1ull) * bits * 7ull) / 10ull + 1ull;
    unsigned long long boundaries = reach / width + 2ull;
    if (boundaries > leaves / 2ull - 2ull)
    {
        boundaries = leaves / 2ull - 2ull;
    }
    std::vector<long long> below_count;
    if (ok)
    {
        const unsigned long long lanes = (boundaries + 1ull) * nu;
        std::vector<unsigned int> index((size_t)(2ull * lanes), 0u);
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            index[(size_t)(2ull * lane)] = (unsigned int)(lane % nu);
        }
        unsigned int *const out = turing_alloc(owned, (size_t)(lanes * below.layout.out_limbs));
        unsigned int *const shared = turing_shared(owned, &below, std::vector<long long>(1u, (long long)nu));
        unsigned int *const members[3] = {device_pole, shared, NULL};
        const unsigned long long bodies[3] = {poles, 1ull, 0ull};
        ok = (shared != NULL) && (out != NULL) && turing_sweep(&below, members, bodies, index, lanes, out, checked, error, same);
        below_count = turing_group_sums(&below, out, lanes, nu, 0u, 2u, error, &ok);
        ok = ok && (below_count.size() == boundaries + 1ull) && (below_count[(size_t)boundaries] == (long long)nu);
        for (unsigned long long b = 1ull; ok && (b < boundaries); b += 1ull)
        {
            if (below_count[(size_t)b] == (long long)nu)
            {
                boundaries = b;
            }
        }
    }
    sim_check(job, ok, "every pole falls in a leaf the multiple evaluation lays out");

    // the leaves' multipoles: lane (leaf, slot) over the leaves that hold poles
    std::vector<unsigned long long> source_leaf;
    unsigned long long slots = 1ull;
    for (unsigned long long r = 0ull; ok && (r < boundaries); r += 1ull)
    {
        const unsigned long long held = (unsigned long long)(below_count[(size_t)(r + 1ull)] - below_count[(size_t)r]);
        if (held != 0ull)
        {
            source_leaf.push_back(r);
            slots = (held > slots) ? held : slots;
        }
    }
    std::vector<std::vector<long long> > multipole_map(top + 1u);
    std::vector<unsigned int *> multipole(top + 1u, (unsigned int *)NULL);
    std::vector<unsigned long long> multipole_count(top + 1u, 0ull);
    if (ok)
    {
        const unsigned long long lanes = source_leaf.size() * slots;
        std::vector<unsigned int> index((size_t)(2ull * lanes), 0u);
        for (unsigned long long leaf = 0ull; leaf < source_leaf.size(); leaf += 1ull)
        {
            const unsigned long long r = source_leaf[(size_t)leaf];
            const unsigned long long first = (unsigned long long)below_count[(size_t)r];
            const unsigned long long held = (unsigned long long)below_count[(size_t)(r + 1ull)] - first;
            for (unsigned long long slot = 0ull; slot < slots; slot += 1ull)
            {
                index[(size_t)(2ull * (leaf * slots + slot))] = (unsigned int)((slot < held) ? first + slot : nu);
            }
        }
        unsigned int *const shared = turing_shared(owned, &p2m, std::vector<long long>());
        unsigned int *const out = turing_alloc(owned, (size_t)((lanes + 1ull) * limbs));
        unsigned int *const members[3] = {device_pole, shared, NULL};
        const unsigned long long bodies[3] = {poles, 1ull, 0ull};
        ok = (shared != NULL) && (out != NULL) &&
             turing_sweep(&p2m, members, bodies, index, lanes, out, checked, error, same);
        std::vector<unsigned int> map((size_t)lanes);
        for (unsigned long long at = 0ull; at < lanes; at += 1ull)
        {
            map[(size_t)at] = (unsigned int)at;
        }
        multipole[top] = (slots == 1ull) ? out
                                         : turing_fold(owned, &fold, out, lanes, map, source_leaf.size(), slots, checked,
                                                       error, same, &ok);
        multipole_count[top] = source_leaf.size();
        multipole_map[top].assign((size_t)leaves, -1);
        for (unsigned long long leaf = 0ull; leaf < source_leaf.size(); leaf += 1ull)
        {
            multipole_map[top][(size_t)(leaves / 2ull + source_leaf[(size_t)leaf])] = (long long)leaf;
        }
    }
    sim_check(job, ok, "the leaves' multipoles are summed on the device");

    // up the tree: each box with poles carried to its parent's center, the lower children in one run and the upper in
    // another, and each parent's two summed by a fold
    for (unsigned int level = top - 1u; ok && (level >= 3u) && (level < top); level -= 1u)
    {
        const unsigned long long boxes = 1ull << level;
        const std::vector<long long> &children = multipole_map[level + 1u];
        std::vector<unsigned long long> parents;
        std::vector<unsigned int> side_index[2];
        for (unsigned long long box = 0ull; box < boxes; box += 1ull)
        {
            if ((children[(size_t)(2ull * box)] >= 0) || (children[(size_t)(2ull * box + 1ull)] >= 0))
            {
                parents.push_back(box);
            }
            for (unsigned int side = 0u; side < 2u; side += 1u)
            {
                if (children[(size_t)(2ull * box + side)] >= 0)
                {
                    side_index[side].push_back((unsigned int)children[(size_t)(2ull * box + side)]);
                    side_index[side].push_back(side);
                }
            }
        }
        // the lower children's lanes first, then the upper's, each reading the shared record of its side
        const unsigned long long lower_count = side_index[0].size() / 2u;
        const unsigned long long shifted = lower_count + side_index[1].size() / 2u;
        std::vector<unsigned int> index(side_index[0]);
        index.insert(index.end(), side_index[1].begin(), side_index[1].end());
        std::vector<std::vector<long long> > params(2u, std::vector<long long>(1u, (long long)(1ull << (level + 1u))));
        params[0].push_back(-1);
        params[1].push_back(1);
        unsigned int *const shared = turing_shared_records(owned, &m2m, params);
        unsigned int *const out = turing_alloc(owned, (size_t)((shifted + 1ull) * limbs));
        unsigned int *const members[3] = {multipole[level + 1u], shared, NULL};
        const unsigned long long bodies[3] = {multipole_count[level + 1u] + 1ull, 2ull, 0ull};
        ok = (shared != NULL) && (out != NULL) && turing_sweep(&m2m, members, bodies, index, shifted, out, checked, error, same);
        // each parent's lower and upper shifted multipoles, where it has them, folded to one
        std::vector<unsigned int> map((size_t)(2ull * parents.size()), (unsigned int)shifted);
        multipole_map[level].assign((size_t)boxes, -1);
        unsigned long long lower_at = 0ull, upper_at = lower_count;
        for (unsigned long long at = 0ull; at < parents.size(); at += 1ull)
        {
            const unsigned long long box = parents[(size_t)at];
            if (children[(size_t)(2ull * box)] >= 0)
            {
                map[(size_t)(2ull * at)] = (unsigned int)lower_at++;
            }
            if (children[(size_t)(2ull * box + 1ull)] >= 0)
            {
                map[(size_t)(2ull * at + 1ull)] = (unsigned int)upper_at++;
            }
            multipole_map[level][(size_t)box] = (long long)at;
        }
        multipole[level] = ok ? turing_fold(owned, &fold, out, shifted, map, parents.size(), 2ull, checked, error, same, &ok) : NULL;
        multipole_count[level] = parents.size();
    }
    sim_check(job, ok, "the multipoles are carried up the tree on the device");

    // across: each box's interaction list, the children of its parent's neighbors that are not its own neighbors;
    // then each box's sum by folds
    std::vector<unsigned int *> local_sum(top + 1u, (unsigned int *)NULL);
    std::vector<std::vector<long long> > local_sum_map(top + 1u);
    std::vector<unsigned long long> local_sum_count(top + 1u, 0ull);
    for (unsigned int level = 3u; ok && (level <= top); level += 1u)
    {
        const unsigned long long boxes = 1ull << level;
        std::vector<std::vector<unsigned long long> > targets_of(11u);
        std::vector<std::vector<unsigned long long> > sources_of(11u);
        for (unsigned long long target = 0ull; target < boxes; target += 1ull)
        {
            std::vector<unsigned long long> list;
            if (level == 3u)
            {
                for (unsigned long long source = 0ull; source < boxes; source += 1ull)
                {
                    if (turing_apart(source, target, boxes) >= 3ull)
                    {
                        list.push_back(source);
                    }
                }
            }
            else
            {
                const unsigned long long parents = boxes / 2ull;
                for (long long shift = -2; shift <= 2; shift += 1)
                {
                    const unsigned long long parent = (unsigned long long)(((long long)(target / 2ull) + shift + (long long)parents) %
                                                                           (long long)parents);
                    for (unsigned long long child = 2ull * parent; child < 2ull * parent + 2ull; child += 1ull)
                    {
                        if (turing_apart(child, target, boxes) >= 3ull)
                        {
                            list.push_back(child);
                        }
                    }
                }
            }
            for (size_t at = 0u; at < list.size(); at += 1u)
            {
                const unsigned long long source = list[at];
                if (multipole_map[level][(size_t)source] < 0)
                {
                    continue;
                }
                long long delta = (long long)((target + boxes - source) % boxes);
                if (delta > (long long)(boxes / 2ull))
                {
                    delta -= (long long)boxes;
                }
                targets_of[(size_t)(delta + 5)].push_back(target);
                sources_of[(size_t)(delta + 5)].push_back(source);
            }
        }
        // one run over every pair of the level, each lane reading the shared record of its Delta
        std::vector<unsigned int> index;
        std::vector<std::vector<unsigned int> > pair_of(boxes);
        std::vector<std::vector<long long> > params(11u);
        for (size_t d = 0u; d < 11u; d += 1u)
        {
            params[d].push_back((long long)d - 5);
            params[d].push_back((long long)(1ull << level));
            for (size_t lane = 0u; lane < targets_of[d].size(); lane += 1u)
            {
                pair_of[(size_t)targets_of[d][lane]].push_back((unsigned int)(index.size() / 2u));
                index.push_back((unsigned int)multipole_map[level][(size_t)sources_of[d][lane]]);
                index.push_back((unsigned int)d);
            }
        }
        const unsigned long long pairs = index.size() / 2u;
        unsigned int *const shared = turing_shared_records(owned, &m2l, params);
        unsigned int *const out = turing_alloc(owned, (size_t)((pairs + 1ull) * limbs));
        unsigned int *const members[3] = {multipole[level], shared, NULL};
        const unsigned long long bodies[3] = {multipole_count[level] + 1ull, 11ull, 0ull};
        ok = (shared != NULL) && (out != NULL) && turing_sweep(&m2l, members, bodies, index, pairs, out, checked, error, same);
        // the boxes with pairs, each list padded to five with the zero record, folded to one sum a box
        std::vector<unsigned long long> with;
        for (unsigned long long target = 0ull; target < boxes; target += 1ull)
        {
            if (!pair_of[(size_t)target].empty())
            {
                with.push_back(target);
            }
        }
        std::vector<unsigned int> map((size_t)(5ull * with.size()), (unsigned int)pairs);
        local_sum_map[level].assign((size_t)boxes, -1);
        for (unsigned long long w = 0ull; w < with.size(); w += 1ull)
        {
            const std::vector<unsigned int> &list = pair_of[(size_t)with[(size_t)w]];
            for (size_t slot = 0u; slot < list.size() && slot < 5u; slot += 1u)
            {
                map[(size_t)(5ull * w + slot)] = list[slot];
            }
            local_sum_map[level][(size_t)with[(size_t)w]] = (long long)w;
        }
        local_sum[level] = with.empty() ? out
                                        : turing_fold(owned, &fold, out, pairs, map, with.size(), 5ull, checked, error, same, &ok);
        local_sum_count[level] = with.size();
    }
    sim_check(job, ok, "the multipoles are carried across to local expansions on the device");

    // down the tree: every box's local expansion from its parent's and its own sum
    unsigned int *local = NULL;
    unsigned long long local_count = 0ull;
    for (unsigned int level = 3u; ok && (level <= top); level += 1u)
    {
        const unsigned long long boxes = 1ull << level;
        std::vector<unsigned int> index((size_t)(3ull * boxes), 0u);
        unsigned int *const parent = (level == 3u) ? local_sum[level] : local;
        const unsigned long long parent_zero = (level == 3u) ? local_sum_count[level] : local_count;
        for (unsigned long long box = 0ull; box < boxes; box += 1ull)
        {
            index[(size_t)(3ull * box)] = (unsigned int)((level == 3u) ? parent_zero : box / 2ull);
            const long long own = local_sum_map[level][(size_t)box];
            index[(size_t)(3ull * box + 1ull)] = (unsigned int)((own >= 0) ? (unsigned long long)own : local_sum_count[level]);
        }
        unsigned int *const shared = turing_shared(owned, &l2l, std::vector<long long>(1u, (long long)boxes));
        unsigned int *const out = turing_alloc(owned, (size_t)((boxes + 1ull) * limbs));
        unsigned int *const members[3] = {parent, local_sum[level], shared};
        const unsigned long long bodies[3] = {parent_zero + 1ull, local_sum_count[level] + 1ull, 1ull};
        ok = (shared != NULL) && (out != NULL) &&
             turing_sweep(&l2l, members, bodies, index, boxes, out, checked, error, same);
        local = out;
        local_count = boxes;
    }
    sim_check(job, ok, "the local expansions are carried down the tree on the device");

    // the near field: the points of the leaves within two of a leaf with poles, each against the poles of the five
    // leaves about its own
    const long long near_low = -2ll * (long long)width;
    const long long near_high = ((long long)boundaries + 2ll) * (long long)width;
    const unsigned long long near_points = (unsigned long long)(near_high - near_low);
    unsigned long long near_slots = 1ull;
    for (long long leaf = -2; ok && (leaf < (long long)boundaries + 2); leaf += 1)
    {
        const long long lo = (leaf - 2 < 0) ? 0 : leaf - 2;
        const long long hi = (leaf + 3 > (long long)boundaries) ? (long long)boundaries : leaf + 3;
        if (lo < hi)
        {
            const unsigned long long held = (unsigned long long)(below_count[(size_t)hi] - below_count[(size_t)lo]);
            near_slots = (held > near_slots) ? held : near_slots;
        }
    }
    std::vector<unsigned int> near_records;
    if (ok)
    {
        const unsigned long long lanes = near_points * near_slots;
        std::vector<unsigned int> index((size_t)(2ull * lanes), 0u);
        for (unsigned long long h = 0ull; h < near_points; h += 1ull)
        {
            const long long point = near_low + (long long)h;
            const long long leaf = (point >= 0) ? point / (long long)width : -((-point + (long long)width - 1) / (long long)width);
            const long long lo = (leaf - 2 < 0) ? 0 : leaf - 2;
            const long long hi = (leaf + 3 > (long long)boundaries) ? (long long)boundaries : leaf + 3;
            const unsigned long long first = (lo < hi) ? (unsigned long long)below_count[(size_t)lo] : 0ull;
            const unsigned long long held = (lo < hi) ? (unsigned long long)below_count[(size_t)hi] - first : 0ull;
            for (unsigned long long slot = 0ull; slot < near_slots; slot += 1ull)
            {
                index[(size_t)(2ull * (h * near_slots + slot))] = (unsigned int)((slot < held) ? first + slot : nu);
            }
        }
        std::vector<long long> params;
        params.push_back(near_low);
        params.push_back((long long)near_slots);
        unsigned int *const shared = turing_shared(owned, &near, params);
        unsigned int *const out = turing_alloc(owned, (size_t)(lanes * near.layout.out_limbs));
        unsigned int *const members[3] = {device_pole, shared, NULL};
        const unsigned long long bodies[3] = {poles, 1ull, 0ull};
        ok = (shared != NULL) && (out != NULL) &&
             turing_sweep(&near, members, bodies, index, lanes, out, checked, error, same);
        // each point's sum, laid into a record of two fields of near_limbs limbs
        near_records.assign((size_t)((near_points + 1ull) * 2ull * near_limbs), 0u);
        for (unsigned int part = 0u; ok && (part < 2u); part += 1u)
        {
            const DeviceRecordStep *const place = turing_place(&near, part);
            std::vector<unsigned int> sums((size_t)(near_points * near_limbs), 0u);
            const CycleRecordSumRequest request = {out, lanes, near_slots, near.layout.out_limbs, place->out_offset,
                                                   place->out_bits, near_limbs, sums.data(), error};
            ok = cycle_record_sum(&request) != CYCLE_ERROR;
            for (unsigned long long h = 0ull; ok && (h < near_points); h += 1ull)
            {
                memcpy(&near_records[(size_t)((h * 2ull + part) * near_limbs)], &sums[(size_t)(h * near_limbs)],
                       near_limbs * sizeof(unsigned int));
            }
        }
    }
    unsigned int *const device_near = ok ? turing_upload(owned, near_records) : NULL;
    ok = ok && (device_near != NULL);
    sim_check(job, ok, "the near field runs on the device and sums over each point");

    // each point's u_h / P from its leaf's local expansion and its near sum, at record o, h = o - P/2
    unsigned int *transform = NULL;
    if (ok)
    {
        std::vector<unsigned int> index((size_t)(3ull * points), 0u);
        for (unsigned long long o = 0ull; o < points; o += 1ull)
        {
            const long long h = (long long)o - (long long)(points / 2ull);
            index[(size_t)(3ull * o)] = (unsigned int)(o >> beta);
            index[(size_t)(3ull * o + 1ull)] =
                (unsigned int)(((h >= near_low) && (h < near_high)) ? (unsigned long long)(h - near_low) : near_points);
        }
        unsigned int *const shared = turing_shared(owned, &eval, std::vector<long long>());
        transform = turing_alloc(owned, (size_t)(points * values->out_limbs));
        unsigned int *const members[3] = {local, device_near, shared};
        const unsigned long long bodies[3] = {local_count + 1ull, near_points + 1ull, 1ull};
        ok = (shared != NULL) && (transform != NULL) &&
             turing_sweep(&eval, members, bodies, index, points, transform, checked, error, same);
    }
    sim_check(job, ok, "every point's sum of its expansion and near field runs on the device");

    // the transform, p stages of Stockham's, the first reading u at frequency h mod P from record h + P/2 mod P
    unsigned int *twiddles = NULL;
    if (ok)
    {
        unsigned int *const shared = turing_shared(owned, &twiddle, std::vector<long long>());
        twiddles = turing_alloc(owned, (size_t)(points * twiddle.layout.out_limbs));
        unsigned int *const members[3] = {shared, NULL, NULL};
        const unsigned long long bodies[3] = {1ull, 0ull, 0ull};
        ok = (shared != NULL) && (twiddles != NULL) &&
             turing_sweep(&twiddle, members, bodies, std::vector<unsigned int>(), points, twiddles, checked, error, same);
    }
    // two arrays the stages run between, the evaluation's records left behind after the first
    unsigned int *const passes[2] = {ok ? turing_alloc(owned, (size_t)(points * values->out_limbs)) : NULL,
                                     ok ? turing_alloc(owned, (size_t)(points * values->out_limbs)) : NULL};
    for (unsigned int stage = 0u; ok && (stage < p); stage += 1u)
    {
        const unsigned long long span = 1ull << stage;
        std::vector<unsigned int> index((size_t)(3ull * points), 0u);
        for (unsigned long long o = 0ull; o < points; o += 1ull)
        {
            const unsigned long long e = (o >> stage) & 1ull;
            const unsigned long long k = o & (span - 1ull);
            const unsigned long long j = (o >> (stage + 1u)) * span + k;
            const unsigned long long at0 = (stage == 0u) ? (j + points / 2ull) % points : j;
            const unsigned long long at1 = (stage == 0u) ? j : j + points / 2ull;
            index[(size_t)(3ull * o)] = (unsigned int)at0;
            index[(size_t)(3ull * o + 1ull)] = (unsigned int)at1;
            index[(size_t)(3ull * o + 2ull)] = (unsigned int)(k * (points / (2ull * span)) + e * (points / 2ull));
        }
        unsigned int *const out = passes[stage % 2u];
        unsigned int *const members[3] = {transform, transform, twiddles};
        const unsigned long long bodies[3] = {points, points, points};
        ok = (out != NULL) && turing_sweep(&fft, members, bodies, index, points, out, checked, error, same);
        transform = out;
    }
    sim_check(job, ok, "the transform's stages run on the device");

    for (unsigned int at = 0u; at < 10u; at += 1u)
    {
        report->steps.push_back(stages[at]->layout.steps);
        turing_release(stages[at]);
    }
    return ok ? transform : NULL;
}

int main(int count, char **arguments)
{
    SimResults job;
    char job_capacity[SIM_LINE_CAPACITY];
    sim_open(&job, job_capacity);
    if (count != 3)
    {
        fprintf(stderr, "  usage: exact_zeta_turing <input> <output>\n");
        return 2;
    }
    FILE *in = fopen(arguments[1], "rb");
    long long header[14] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    int read = (in != NULL);
    for (unsigned int at = 0u; read && (at < 14u); at += 1u)
    {
        read = turing_word(in, &header[at]);
    }
    read = read && (header[2] >= 2) && (header[2] < (1ll << TURING_NU_BITS)) && (header[3] >= 2) && (header[3] <= 24) &&
           (header[0] == (1ll << header[3])) && (header[1] > 0) && (header[4] >= 2) && (header[4] < 256) &&
           (header[5] >= 2) && (header[5] < 256) && (header[6] >= 2) && (header[6] < 1024) && (header[7] >= 1) &&
           (header[7] < 256) && (header[8] >= 1) && (header[8] <= header[0]) && ((header[0] % header[8]) == 0) &&
           (header[1] <= header[8]) && (header[8] * header[2] < (1ll << TURING_LANE_BITS)) && (header[9] >= 0) &&
           (header[9] <= 2) && (header[10] >= 2) && (header[10] < 128) && (header[11] >= 2) && (header[11] < header[3]) &&
           (header[12] >= 2) && (header[12] < 256) && (header[13] >= 2) && (header[13] < 256);
    const unsigned long long points = read ? (unsigned long long)header[0] : 0ull;
    const unsigned long long checked = read ? (unsigned long long)header[1] : 0ull;
    const unsigned long long nu = read ? (unsigned long long)header[2] : 0ull;
    const unsigned int p = read ? (unsigned int)header[3] : 0u;
    const unsigned int newton = read ? (unsigned int)header[7] : 0u;
    const unsigned long long piece = read ? (unsigned long long)header[8] : 1ull;
    const unsigned int method = read ? (unsigned int)header[9] : 0u;
    const unsigned int order = read ? (unsigned int)header[10] : 0u;
    const unsigned int beta = read ? (unsigned int)header[11] : 0u;
    TuringConstant ln2, c96, bound, theta_bound;
    TuringOsConstants os;
    std::vector<TuringConstant> gamma(read ? (size_t)header[6] : 0u), artanh(read ? (size_t)header[4] : 0u),
        cosine(read ? (size_t)header[5] : 0u);
    os.fact.resize(read ? (size_t)header[12] : 0u);
    os.sinc.resize(read ? (size_t)header[13] : 0u);
    read = read && turing_read_constant(in, &ln2);
    for (size_t k = 0u; read && (k < gamma.size()); k += 1u)
    {
        read = turing_read_constant(in, &gamma[k]);
    }
    for (size_t k = 0u; read && (k < artanh.size()); k += 1u)
    {
        read = turing_read_constant(in, &artanh[k]);
    }
    for (size_t k = 0u; read && (k < cosine.size()); k += 1u)
    {
        read = turing_read_constant(in, &cosine[k]);
    }
    read = read && turing_read_constant(in, &c96) && turing_read_constant(in, &bound) &&
           turing_read_constant(in, &theta_bound) && (bound.sign > 0) && (theta_bound.sign >= 0) &&
           turing_read_constant(in, &os.pi);
    for (size_t k = 0u; read && (k < os.fact.size()); k += 1u)
    {
        read = turing_read_constant(in, &os.fact[k]);
    }
    for (size_t k = 0u; read && (k < os.sinc.size()); k += 1u)
    {
        read = turing_read_constant(in, &os.sinc[k]);
    }
    os.cosine = cosine;
    if (in != NULL)
    {
        fclose(in);
    }
    if (!read)
    {
        fprintf(stderr, "  exact_zeta_turing: %s is not an input this program reads\n", arguments[1]);
        return 2;
    }
    const unsigned long long floor_s = (nu * nu) << p;
    const unsigned long long step_s = 2ull * nu + 1ull;
    const int pairs_run = (method != 1u);
    const int transform_run = (method != 0u);
    const TuringOsConstants *const with_os = transform_run ? &os : NULL;

    EngineError error;
    memset(&error, 0, sizeof(error));
    std::vector<unsigned int *> owned;
    TuringStage pole, point, pair, verdict, counted, verdict_pairs;
    turing_open_stage(&pole, "pole", 1u);
    turing_open_stage(&point, "point", 1u);
    turing_open_stage(&pair, "pair", 3u);
    turing_open_stage(&verdict, "verdict", 3u);
    turing_open_stage(&counted, "count", 3u);
    turing_open_stage(&verdict_pairs, "verdict of the pairs", 3u);

    turing_pole_build(&pole, newton, ln2, artanh, p, with_os);
    turing_seal(&pole);
    if (transform_run)
    {
        turing_put_small(&pole, pole.params[0], 2ull * nu + 1ull, 1);
        turing_put_small(&pole, pole.params[1], 2ull * nu * nu, 1);
    }
    pole.in_limbs[0] = (unsigned int)pole.shared.size();
    unsigned int field = 0u;
    turing_put_field(&pole, field++, ln2.magnitude, ln2.sign);
    for (size_t k = 0u; k < artanh.size(); k += 1u)
    {
        turing_put_field(&pole, field++, artanh[k].magnitude, artanh[k].sign);
    }

    turing_point_build(&point, p, newton, ln2, artanh, c96, gamma, with_os);
    turing_seal(&point);
    point.in_limbs[0] = (unsigned int)point.shared.size();
    turing_put_small(&point, 0u, 1ull, ((nu - 1ull) % 2ull) ? -1 : 1);
    turing_put_small(&point, 1u, floor_s, 1);
    turing_put_small(&point, 2u, step_s, 1);
    turing_put_small(&point, 3u, nu, 1);
    field = 4u;
    turing_put_field(&point, field++, ln2.magnitude, ln2.sign);
    for (size_t k = 0u; k < artanh.size(); k += 1u)
    {
        turing_put_field(&point, field++, artanh[k].magnitude, artanh[k].sign);
    }
    turing_put_field(&point, field++, c96.magnitude, c96.sign);
    for (size_t k = 0u; k < gamma.size(); k += 1u)
    {
        turing_put_field(&point, field++, gamma[k].magnitude, gamma[k].sign);
    }

    int ok = turing_load(&job, &pole, &error) && turing_load(&job, &point, &error);
    if (ok && pairs_run)
    {
        turing_pair_build(&pair, p, &pole, &point, cosine);
        pair.in_limbs[0] = pole.layout.out_limbs;
        pair.in_limbs[1] = point.layout.out_limbs;
        pair.in_limbs[2] = (unsigned int)pair.shared.size();
        turing_put_small(&pair, 3u, nu, 1);
        turing_put_small(&pair, 4u, floor_s, 1);
        turing_put_small(&pair, 5u, step_s, 1);
        for (size_t k = 0u; k < cosine.size(); k += 1u)
        {
            turing_put_field(&pair, 7u + (unsigned int)k, cosine[k].magnitude, cosine[k].sign);
        }
        ok = turing_load(&job, &pair, &error);
    }
    const unsigned int sum_limbs = (ok && pairs_run) ? (turing_place(&pair, 0u)->out_bits + TURING_NU_BITS + 31u) / 32u + 1u : 1u;

    const unsigned long long pair_lanes = piece * nu;
    // the multiple evaluation's records: every box's local expansion, about 2 P / W of them, the evaluation, the
    // transform's two arrays and the twiddles, each a few limbs a point, and the multipoles and near field, a few
    // expansions a pole
    const unsigned long long expansion_limbs = (2ull * order * (TURING_EXP_BITS + 1u) + 31ull) / 32ull + 1ull;
    const unsigned long long transform_words =
        transform_run ? points * (2ull * expansion_limbs / (1ull << beta) + 32ull) + 64ull * nu * expansion_limbs : 0ull;
    const unsigned long long declared =
        ((pairs_run ? pair_lanes * ((ok ? pair.layout.out_limbs : 0u) + 3u) : 0ull) + 2ull * points * sum_limbs +
         points * 8u * (ok ? point.layout.out_limbs : 0u) + transform_words) * sizeof(unsigned int) +
        (64ull << 20u);
    ok = ok && sim_job_submit(&job, "exact_zeta_turing", count, arguments, declared);

    // the pole and point stages; the pole records end in a zero record, the empty slot every wiring points at
    int host_pole = 1, host_point = 1, host_pair = 1, host_sums = 1, host_os = 1, host_verdict = 1, host_count = 1;
    const unsigned long long one[3] = {1ull, 0ull, 0ull};
    unsigned int *const device_pole_shared = ok ? turing_upload(&owned, pole.shared) : NULL;
    unsigned int *const device_pole = ok ? turing_alloc(&owned, (size_t)((nu + 1ull) * pole.layout.out_limbs)) : NULL;
    ok = ok && (device_pole_shared != NULL) && (device_pole != NULL);
    {
        unsigned int *const members[3] = {device_pole_shared, NULL, NULL};
        ok = ok && turing_sweep(&pole, members, one, std::vector<unsigned int>(), nu, device_pole, nu, &error, &host_pole);
    }
    sim_check(&job, ok && host_pole, "the pole stage runs and the host's records equal the device's");
    unsigned int *const device_point_shared = ok ? turing_upload(&owned, point.shared) : NULL;
    unsigned int *const device_point = ok ? turing_alloc(&owned, (size_t)(points * point.layout.out_limbs)) : NULL;
    ok = ok && (device_point_shared != NULL) && (device_point != NULL);
    {
        unsigned int *const members[3] = {device_point_shared, NULL, NULL};
        ok = ok && turing_sweep(&point, members, one, std::vector<unsigned int>(), points, device_point, checked, &error,
                                &host_point);
    }
    sim_check(&job, ok && host_point, "the point stage runs and the host's records equal the device's");

    // the pair stage, a piece of points at a time, each point's nu lanes summed on the device
    std::vector<unsigned int> sums((size_t)(points * sum_limbs), 0u);
    if (pairs_run)
    {
        const DeviceRecordStep *const term_place = ok ? turing_place(&pair, 0u) : NULL;
        std::vector<unsigned int> index((size_t)(3ull * pair_lanes), 0u);
        for (unsigned long long lane = 0ull; lane < pair_lanes; lane += 1ull)
        {
            index[(size_t)(3ull * lane)] = (unsigned int)(lane % nu);
            index[(size_t)(3ull * lane + 1ull)] = (unsigned int)(lane / nu);
        }
        unsigned int *const device_index = ok ? turing_upload(&owned, index) : NULL;
        unsigned int *const device_pair_shared = ok ? turing_alloc(&owned, pair.shared.size()) : NULL;
        unsigned int *const device_pair_out = ok ? turing_alloc(&owned, (size_t)(pair_lanes * pair.layout.out_limbs)) : NULL;
        ok = ok && (device_index != NULL) && (device_pair_shared != NULL) && (device_pair_out != NULL);
        for (unsigned long long start = 0ull; ok && (start < points); start += piece)
        {
            turing_put_small(&pair, 6u, start, 1);
            ok = cudaMemcpy(device_pair_shared, pair.shared.data(), pair.shared.size() * sizeof(unsigned int),
                            cudaMemcpyHostToDevice) == cudaSuccess;
            unsigned int *const members[3] = {device_pole, device_point + start * point.layout.out_limbs, device_pair_shared};
            const unsigned long long bodies[3] = {nu + 1ull, points - start, 1ull};
            ok = ok && turing_run(&pair, members, bodies, device_index, pair_lanes, device_pair_out, &error);
            const CycleRecordSumRequest sum = {device_pair_out, pair_lanes, nu, pair.layout.out_limbs, term_place->out_offset,
                                               term_place->out_bits, sum_limbs, &sums[(size_t)(start * sum_limbs)], &error};
            ok = ok && (cycle_record_sum(&sum) != CYCLE_ERROR);
            if (ok && (start == 0ull))
            {
                const std::vector<unsigned int> records =
                    turing_copy_back(device_pair_out, (size_t)(pair_lanes * pair.layout.out_limbs));
                const std::vector<unsigned int> pole_records =
                    turing_copy_back(device_pole, (size_t)((nu + 1ull) * pole.layout.out_limbs));
                const std::vector<unsigned int> point_records =
                    turing_copy_back(device_point, (size_t)(points * point.layout.out_limbs));
                unsigned int *const host_members[3] = {(unsigned int *)pole_records.data(), (unsigned int *)point_records.data(),
                                                       pair.shared.data()};
                host_pair = !records.empty() &&
                            turing_check(&pair, host_members, bodies, index.data(), checked * nu, records.data(), &error);
                std::vector<unsigned int> host_piece((size_t)(piece * sum_limbs), 0u);
                const CycleRecordSumRequest host_sum = {records.data(), pair_lanes, nu, pair.layout.out_limbs,
                                                        term_place->out_offset, term_place->out_bits, sum_limbs,
                                                        host_piece.data(), &error};
                host_sums = (cycle_record_sum_host(&host_sum) != CYCLE_ERROR) &&
                            (memcmp(host_piece.data(), sums.data(), host_piece.size() * sizeof(unsigned int)) == 0);
            }
        }
        sim_check(&job, ok, "every pair of the cell runs on the device and sums over its point");
        sim_check(&job, host_pair && host_sums, "the host's pair records and sums equal the device's word for word");
    }

    // the multiple evaluation
    TuringExpansion values;
    TuringOsReport report;
    unsigned int *device_transform = NULL;
    if (ok && transform_run)
    {
        device_transform = turing_os(&job, &owned, nu, p, beta, order, checked, os, &pole, device_pole, &values, &report,
                                     &error, &host_os);
        ok = (device_transform != NULL);
        sim_check(&job, ok && host_os, "the multiple evaluation runs and the host's records equal the device's");
    }

    // the verdict stage, over F or the sums, the point records and its shared record
    unsigned int *const device_sums = (ok && pairs_run) ? turing_upload(&owned, sums) : NULL;
    if (ok)
    {
        turing_verdict_build(&verdict, p, sum_limbs, &point, bound.bits, theta_bound.bits, transform_run ? &values : NULL);
        verdict.in_limbs[0] = transform_run ? values.out_limbs : sum_limbs;
        verdict.in_limbs[1] = point.layout.out_limbs;
        verdict.in_limbs[2] = (unsigned int)verdict.shared.size();
        turing_put_small(&verdict, verdict.params[0], floor_s, 1);
        turing_put_small(&verdict, verdict.params[1], step_s, 1);
        turing_put_field(&verdict, verdict.params[2], bound.magnitude, bound.sign);
        turing_put_field(&verdict, verdict.params[3], theta_bound.magnitude, theta_bound.sign);
        ok = turing_load(&job, &verdict, &error);
    }
    unsigned int *const device_verdict_shared = ok ? turing_upload(&owned, verdict.shared) : NULL;
    unsigned int *const device_verdict =
        ok ? turing_alloc(&owned, (size_t)((points + TURING_PADS) * verdict.layout.out_limbs)) : NULL;
    ok = ok && (device_verdict_shared != NULL) && (device_verdict != NULL);
    const unsigned int verdict_limbs = ok ? verdict.layout.out_limbs : 0u;
    {
        unsigned int *const members[3] = {transform_run ? device_transform : device_sums, device_point, device_verdict_shared};
        const unsigned long long bodies[3] = {points, points, 1ull};
        ok = ok && turing_sweep(&verdict, members, bodies, std::vector<unsigned int>(), points,
                                device_verdict + TURING_PADS * verdict_limbs, checked, &error, &host_verdict);
    }
    sim_check(&job, ok && host_verdict, "the verdict stage runs and the host's records equal the device's");
    std::vector<unsigned int> verdict_records =
        ok ? turing_copy_back(device_verdict, (size_t)((points + TURING_PADS) * verdict_limbs)) : std::vector<unsigned int>();
    const std::vector<unsigned int> verdicts(ok ? verdict_records.begin() + TURING_PADS * verdict_limbs : verdict_records.end(),
                                             verdict_records.end());

    // both ways at once: the pairs' verdict beside the transform's, and the most their Z differ by
    std::vector<unsigned int> apart;
    if (ok && pairs_run && transform_run)
    {
        turing_verdict_build(&verdict_pairs, p, sum_limbs, &point, bound.bits, theta_bound.bits, NULL);
        verdict_pairs.in_limbs[0] = sum_limbs;
        verdict_pairs.in_limbs[1] = point.layout.out_limbs;
        verdict_pairs.in_limbs[2] = (unsigned int)verdict_pairs.shared.size();
        turing_put_small(&verdict_pairs, verdict_pairs.params[0], floor_s, 1);
        turing_put_small(&verdict_pairs, verdict_pairs.params[1], step_s, 1);
        turing_put_field(&verdict_pairs, verdict_pairs.params[2], bound.magnitude, bound.sign);
        turing_put_field(&verdict_pairs, verdict_pairs.params[3], theta_bound.magnitude, theta_bound.sign);
        ok = turing_load(&job, &verdict_pairs, &error);
        unsigned int *const shared = ok ? turing_upload(&owned, verdict_pairs.shared) : NULL;
        unsigned int *const out = ok ? turing_alloc(&owned, (size_t)(points * verdict_pairs.layout.out_limbs)) : NULL;
        unsigned int *const members[3] = {device_sums, device_point, shared};
        const unsigned long long bodies[3] = {points, points, 1ull};
        int same = 1;
        ok = ok && (shared != NULL) && (out != NULL) &&
             turing_sweep(&verdict_pairs, members, bodies, std::vector<unsigned int>(), points, out, checked, &error, &same);
        const std::vector<unsigned int> other =
            ok ? turing_copy_back(out, (size_t)(points * verdict_pairs.layout.out_limbs)) : std::vector<unsigned int>();
        // the largest |Z_transform - Z_pairs| over the cell, as limbs, and where it falls
        unsigned long long widest_at = 0ull;
        std::vector<unsigned int> widest;
        for (unsigned long long lane = 0ull; ok && (lane < points); lane += 1ull)
        {
            const std::vector<unsigned int> a = turing_output(&verdict, verdicts, lane, 6u);
            const std::vector<unsigned int> b = turing_output(&verdict_pairs, other, lane, 6u);
            const size_t limbs = (a.size() > b.size()) ? a.size() : b.size();
            std::vector<unsigned int> d(limbs, 0u);
            long long borrow = 0;
            for (size_t at = 0u; at < limbs; at += 1u)
            {
                const long long left = (long long)((at < a.size()) ? a[at] : ((a.back() >> 31u) ? 0xFFFFFFFFu : 0u));
                const long long right = (long long)((at < b.size()) ? b[at] : ((b.back() >> 31u) ? 0xFFFFFFFFu : 0u));
                long long v = left - right - borrow;
                borrow = (v < 0) ? 1 : 0;
                d[at] = (unsigned int)(v & 0xFFFFFFFFll);
            }
            if (d.back() >> 31u)
            {
                unsigned long long carry = 1ull;
                for (size_t at = 0u; at < limbs; at += 1u)
                {
                    carry += (unsigned long long)(~d[at] & 0xFFFFFFFFu);
                    d[at] = (unsigned int)carry;
                    carry >>= 32u;
                }
            }
            int larger = widest.empty();
            for (size_t at = limbs; !larger && (at-- > 0u);)
            {
                const unsigned int w = (at < widest.size()) ? widest[at] : 0u;
                if (d[at] != w)
                {
                    larger = (d[at] > w);
                    break;
                }
            }
            if (larger)
            {
                widest = d;
                widest_at = lane;
            }
        }
        apart = widest;
        apart.push_back((unsigned int)widest_at);
    }

    // the count stage, over the verdict records at q, q - 1 and q - 2
    if (ok)
    {
        turing_count_build(&counted, p, &verdict);
        for (unsigned int member = 0u; member < 3u; member += 1u)
        {
            counted.in_limbs[member] = verdict.layout.out_limbs;
        }
        ok = turing_load(&job, &counted, &error);
    }
    unsigned int *const device_count = ok ? turing_alloc(&owned, (size_t)(points * counted.layout.out_limbs)) : NULL;
    ok = ok && (device_count != NULL);
    {
        unsigned int *const members[3] = {device_verdict + 2u * verdict_limbs, device_verdict + verdict_limbs, device_verdict};
        const unsigned long long bodies[3] = {points, points, points};
        ok = ok && turing_sweep(&counted, members, bodies, std::vector<unsigned int>(), points, device_count, checked,
                                &error, &host_count);
    }
    sim_check(&job, ok && host_count, "the count stage runs and the host's records equal the device's");
    const std::vector<unsigned int> count_records =
        ok ? turing_copy_back(device_count, (size_t)(points * counted.layout.out_limbs)) : std::vector<unsigned int>();

    // the cell's first and last certified points, read from the signs
    unsigned long long first = points, last = points;
    for (unsigned long long lane = 0ull; ok && (lane < points); lane += 1ull)
    {
        const std::vector<unsigned int> sign = turing_output(&verdict, verdicts, lane, 0u);
        if ((sign[0] != 0u) && (first == points))
        {
            first = lane;
        }
        if (sign[0] != 0u)
        {
            last = lane;
        }
    }
    ok = ok && (first < points);
    sim_check(&job, ok, "the cell holds a certified point");

    FILE *out = ok ? fopen(arguments[2], "w") : NULL;
    int host_ranges = 1;
    if (out != NULL)
    {
        fprintf(out, "cell %llu %u %llu %llu %llu\n", nu, p, points, first, last);
        const unsigned long long marked[3] = {first, last, 0ull};
        const char *const names[3] = {"first", "last", "origin"};
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            fprintf(out, "%s", names[at]);
            for (unsigned int output = 0u; output < 4u; output += 1u)
            {
                turing_write_output(out, &verdict, verdicts, marked[at], output);
            }
            fprintf(out, "\n");
        }
        fprintf(out, "control");
        turing_write_output(out, &verdict, verdicts, 0ull, 6u);
        turing_write_output(out, &verdict, verdicts, points / 3ull, 6u);
        fprintf(out, "\n");
        const unsigned int *const verdict_device_out = device_verdict + TURING_PADS * verdict_limbs;
        host_ranges &= turing_range(out, "low_before", &verdict, verdict_device_out, verdicts, 0ull, first, 4u, &error);
        host_ranges &= turing_range(out, "low_after", &verdict, verdict_device_out, verdicts, first, points - first, 4u, &error);
        host_ranges &= turing_range(out, "high_upto", &verdict, verdict_device_out, verdicts, 1ull, first, 5u, &error);
        host_ranges &= turing_range(out, "high_after", &verdict, verdict_device_out, verdicts, first + 1ull,
                                    points - first - 1ull, 5u, &error);
        const char *const zero_keys[3][2] = {{"zeros_upto", "zeros_after"}, {"zeros_q_upto", "zeros_q_after"},
                                             {"zeros_p_upto", "zeros_p_after"}};
        for (unsigned int output = 0u; output < 3u; output += 1u)
        {
            host_ranges &= turing_range(out, zero_keys[output][0], &counted, device_count, count_records, 0ull, first + 1ull,
                                        output, &error);
            host_ranges &= turing_range(out, zero_keys[output][1], &counted, device_count, count_records, first + 1ull,
                                        points - first - 1ull, output, &error);
        }
        host_ranges &= turing_range(out, "loose", &counted, device_count, count_records, first + 1ull,
                                    points - first - 1ull, 3u, &error);
        fprintf(out, "host %d %d %d %d %d %d %d %d\n", host_pole, host_point, host_pair, host_sums, host_os, host_verdict,
                host_count, host_ranges);
        fprintf(out, "steps %u %u %u %u %u", pole.layout.steps, point.layout.steps, pairs_run ? pair.layout.steps : 0u,
                verdict.layout.steps, counted.layout.steps);
        for (size_t at = 0u; at < report.steps.size(); at += 1u)
        {
            fprintf(out, " %u", report.steps[at]);
        }
        fprintf(out, "\n");
        if (!apart.empty())
        {
            fprintf(out, "apart");
            turing_hex(out, apart.data(), (unsigned int)apart.size() - 1u);
            fprintf(out, " %u\n", apart.back());
        }
        fclose(out);
    }
    sim_check(&job, out != NULL, "the cell's sums are written out");
    sim_check(&job, host_ranges, "the host's sums over the cell's ranges equal the device's word for word");

    for (size_t at = 0u; at < owned.size(); at += 1u)
    {
        cudaFree(owned[at]);
    }
    turing_release(&pole);
    turing_release(&point);
    turing_release(&pair);
    turing_release(&verdict);
    turing_release(&counted);
    turing_release(&verdict_pairs);
    return sim_close(&job, "exact_zeta_turing");
}
