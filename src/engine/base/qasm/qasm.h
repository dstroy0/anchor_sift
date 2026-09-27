// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QASM_H
#define QASM_H

#include "engine_config.h"
#include "exact_integer.h"

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

// Exact qubits, ported from exact_qubits.py, mps_qubits.py, symbolic_qubits.py and boundary_lens.py, which sit beside
// this header. An amplitude is an element of Q(sqrt2)[i] held as four exact rationals, so H's 1/sqrt2 and T's
// (1 + i)/sqrt2 are carried exactly and never rounded. A value past the exact integer's width refuses; it never wraps.

// The widest dense state: 2^30 amplitudes. The index of an amplitude is an unsigned long long either way.
#define QASM_DENSE_QUBITS_MOST 30u

// A rational as Python's Fraction keeps one: the denominator positive, no factor common to the two, and zero as 0/1.
typedef struct
{
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
} QasmRational;

// A number of Q(sqrt2): rational + sqrt2 x sqrt2.
typedef struct
{
    QasmRational rational;
    QasmRational sqrt2;
} QasmRealNumber;

// A number of Q(sqrt2)[i]: real + i imaginary.
typedef struct
{
    QasmRealNumber real;
    QasmRealNumber imaginary;
} QasmNumber;

// 0/1, 1/1 and the number one as initializers, for data the build lays out
#define QASM_RATIONAL_ZERO_INITIALIZER {{{0u}, 0}, {{1u}, 1}}
#define QASM_RATIONAL_ONE_INITIALIZER {{{1u}, 1}, {{1u}, 1}}
#define QASM_NUMBER_ONE_INITIALIZER                                          \
    {{QASM_RATIONAL_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},        \
     {QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER}}

// Room for any number's text in either form, its terminator included: eight integers of the width's decimal digits
// (log10 2 < 0.302), each with its sign and separator, and the form's own characters.
#define QASM_NUMBER_TEXT_ROOM ((8ull * ((((unsigned long long)(ANCHOR_EXACT_BITS) * 302ull) / 1000ull) + 4ull)) + 32ull)

// The arithmetic below reads no pointer it is not given; `error` is never NULL.

extern const QasmNumber qasm_number_zero;
extern const QasmNumber qasm_number_one;
extern const QasmNumber qasm_number_minus_one;
extern const QasmNumber qasm_number_i;
// 1/sqrt2, held as sqrt2/2
extern const QasmNumber qasm_number_half_sqrt2;
// e^{i pi/4} = (1 + i)/sqrt2, the controlled-T phase, and its conjugate e^{-i pi/4}
extern const QasmNumber qasm_number_eighth_turn;
extern const QasmNumber qasm_number_eighth_turn_back;

// numerator / denominator, reduced; a zero denominator refuses
long qasm_rational_set(QasmRational *value, long long numerator, long long denominator, EngineError *error);

// Each result may alias either operand. On a refusal the result is left unchanged.
long qasm_rational_add(const QasmRational *left, const QasmRational *right, QasmRational *sum, EngineError *error);

long qasm_rational_subtract(const QasmRational *left, const QasmRational *right, QasmRational *difference,
                            EngineError *error);

long qasm_rational_multiply(const QasmRational *left, const QasmRational *right, QasmRational *product,
                            EngineError *error);

// a zero divisor refuses
long qasm_rational_divide(const QasmRational *numerator, const QasmRational *divisor, QasmRational *quotient,
                          EngineError *error);

void qasm_rational_negate(const QasmRational *value, QasmRational *negated);

int qasm_rational_equal(const QasmRational *left, const QasmRational *right);

int qasm_rational_is_zero(const QasmRational *value);

// the text Python's str(Fraction) gives: "numerator" where the denominator is 1, "numerator/denominator" otherwise
long qasm_rational_text(const QasmRational *value, char *text, size_t room, EngineError *error);

long qasm_number_add(const QasmNumber *left, const QasmNumber *right, QasmNumber *sum, EngineError *error);

long qasm_number_subtract(const QasmNumber *left, const QasmNumber *right, QasmNumber *difference, EngineError *error);

long qasm_number_multiply(const QasmNumber *left, const QasmNumber *right, QasmNumber *product, EngineError *error);

// 1/x = conj(x) / |x|^2, with 1/(r0 + r1 sqrt2) = (r0 - r1 sqrt2)/(r0^2 - 2 r1^2); zero refuses
long qasm_number_invert(const QasmNumber *value, QasmNumber *inverse, EngineError *error);

// x/sqrt2: (a + b sqrt2)/sqrt2 = b + (a/2) sqrt2 on each part, the step H takes
long qasm_number_half_sqrt2_times(const QasmNumber *value, QasmNumber *product, EngineError *error);

// |x|^2 = real part squared plus imaginary part squared, a number whose imaginary parts are 0
long qasm_number_norm(const QasmNumber *value, QasmNumber *norm, EngineError *error);

void qasm_number_negate(const QasmNumber *value, QasmNumber *negated);

// i x
void qasm_number_i_times(const QasmNumber *value, QasmNumber *product);

void qasm_number_conjugate(const QasmNumber *value, QasmNumber *conjugate);

int qasm_number_equal(const QasmNumber *left, const QasmNumber *right);

int qasm_number_is_zero(const QasmNumber *value);

// A number's bytes for a seal: per rational, the numerator then the denominator, each as its sign (4 bytes) and its
// used limbs (a 4-byte count, then 4 bytes a limb), little-endian. Two equal numbers give the same bytes at any width.
// With bytes NULL it only counts; it returns the count either way.
size_t qasm_number_bytes(const QasmNumber *value, unsigned char *bytes);

// mps_qubits' f_str without its float: "a + b i", each part "p", "q*sqrt2" or "(p + q*sqrt2)"
long qasm_number_text(const QasmNumber *value, char *text, size_t room, EngineError *error);

// symbolic_qubits' k_short: "p", "q i" or "p + q i", each part "p", "qsqrt2", "sqrt2" or "(p+qsqrt2)"
long qasm_number_short_text(const QasmNumber *value, char *text, size_t room, EngineError *error);

// A field the chain runs over, unchanged: Q(sqrt2)[i] or its rational functions. An element slot is either filled with
// zero bytes or holds a live element. Copy and each operation write a slot of either kind, releasing what it held, and
// release frees what a slot holds and leaves it zero bytes. A result may alias an operand.
typedef struct
{
    size_t element_bytes;
    const void *zero;
    const void *one;
    long (*copy)(const void *from, void *to, EngineError *error);
    void (*release)(void *element);
    long (*add)(const void *left, const void *right, void *sum, EngineError *error);
    long (*subtract)(const void *left, const void *right, void *difference, EngineError *error);
    long (*multiply)(const void *left, const void *right, void *product, EngineError *error);
    long (*invert)(const void *value, void *inverse, EngineError *error);
    long (*conjugate)(const void *value, void *conjugate, EngineError *error);
    int (*is_zero)(const void *value);
} QasmField;

// Q(sqrt2)[i]; its elements are QasmNumber
extern const QasmField qasm_number_field;

// A dense state: 2^qubits amplitudes, qubit 0 the least significant bit of an amplitude's index.
typedef struct
{
    unsigned int qubits;
    QasmNumber *amplitudes;
} QasmDense;

// An exact gate, as the Python ports apply one. The ingester's QasmGate above is a rounded gate the record machine
// runs.
typedef enum
{
    QASM_EXACT_GATE_X = 0,
    QASM_EXACT_GATE_Y = 1,
    QASM_EXACT_GATE_Z = 2,
    QASM_EXACT_GATE_S = 3,
    QASM_EXACT_GATE_H = 4,
    QASM_EXACT_GATE_CNOT = 5,
    QASM_EXACT_GATE_CZ = 6,
    // numbers[0] on every amplitude whose `first` and `second` bits are both 1
    QASM_EXACT_GATE_CONTROLLED_PHASE = 7,
    // numbers: a 2 x 2 matrix, [out][in], on qubit `first`
    QASM_EXACT_GATE_ONE_QUBIT = 8,
    // numbers: a 4 x 4 matrix, [2 t0 + t1][2 s0 + s1], on qubits `first` (s0) and `first + 1` (s1)
    QASM_EXACT_GATE_TWO_QUBIT = 9
} QasmExactGateKind;

typedef struct
{
    QasmExactGateKind kind;
    unsigned int first;
    unsigned int second;
    const QasmNumber *numbers;
} QasmExactGate;

// |0...0>
long qasm_dense_alloc(QasmDense *state, unsigned int qubits, EngineError *error);

void qasm_dense_release(QasmDense *state);

// X, Z, S, H, CNOT, CZ and the controlled phase as exact_qubits.py applies them, Y as its Z then X then S, and the two
// matrix gates as mps_qubits.py's Dense applies them. On a refusal the state may be part applied.
long qasm_dense_apply(QasmDense *state, const QasmExactGate *gate, EngineError *error);

// <psi|psi>, the sum of every amplitude's |x|^2
long qasm_dense_norm(const QasmDense *state, QasmNumber *norm, EngineError *error);

int qasm_dense_equal(const QasmDense *left, const QasmDense *right);

// the engine's seal over the amplitudes' bytes in index order, where the Python keyed a blake2b over their text
long qasm_dense_seal(const QasmDense *state, unsigned char *signum, EngineError *error);

// The self run: a circuit of exact gates as one program on the record machine. Each gate is a floor of integer steps
// over the floor below, and with register reuse every lane runs the whole stack in one launch from its own state. A
// lane holds every amplitude's four parts as integers over one denominator the host keeps. The device's words equal the
// host's exact integers word for word, and each output is that integer over the denominator, reduced.
#define QASM_SELF_QUBITS_MOST 5u

typedef struct
{
    unsigned int qubits;
    const QasmExactGate *gates;
    unsigned int gate_count;
    // lanes x 2^qubits amplitudes, lane by lane; NULL starts lane j at |j>, and then lanes is 2^qubits
    const QasmNumber *inputs;
    unsigned long long lanes;
    // run the program through the exact integer library instead of the device
    int on_host;
    // lanes x 2^qubits amplitudes: each lane's state after the last gate
    QasmNumber *outputs;
    // optional: each lane's output record as the machine wrote it, out_limbs limbs a lane, in record_room limbs
    unsigned int *records;
    unsigned long long record_room;
    EngineError *error;
} QasmSelfRequest;

typedef struct
{
    unsigned int steps;
    unsigned int file_limbs;
    unsigned int in_limbs;
    unsigned int out_limbs;
    unsigned long long lanes;
    // the records and the step table the device holds
    unsigned long long device_bytes;
    unsigned long long microseconds;
} QasmSelfReading;

long qasm_self_run(const QasmSelfRequest *request, QasmSelfReading *reading);

// A matrix of field elements, row-major.
typedef struct
{
    const QasmField *field;
    unsigned int rows;
    unsigned int columns;
    unsigned char *elements;
} QasmMatrix;

// A matrix-product state: at each site two matrices, tensors[2 site + sigma], each (left bond) x (right bond), the
// bonds closing to 1 at the ends. The bond across a cut is trimmed to its exact rank after every two-site gate.
typedef struct
{
    const QasmField *field;
    unsigned int sites;
    QasmMatrix *tensors;
} QasmChain;

// |0...0>: every site 1 x 1, sigma 0 holding one and sigma 1 zero
long qasm_chain_alloc(QasmChain *chain, const QasmField *field, unsigned int sites, EngineError *error);

void qasm_chain_release(QasmChain *chain);

// gate: 2 x 2 elements, [out][in]
long qasm_chain_apply_one(QasmChain *chain, const void *gate, unsigned int site, EngineError *error);

// gate: 4 x 4 elements, [2 t0 + t1][2 s0 + s1], on sites `site` (s0) and `site + 1` (s1). The joined pair is split
// again by an exact rank factorization M = C F over the field, C the pivot columns and F the reduced rows.
long qasm_chain_apply_two(QasmChain *chain, const void *gate, unsigned int site, EngineError *error);

// <bits|psi>, bits[site] 0 or 1, into an element slot
long qasm_chain_amplitude(const QasmChain *chain, const unsigned char *bits, void *amplitude, EngineError *error);

// The boundary lens: <psi|O|psi> with each site's operator (2 x 2 elements, [sigma'][sigma], operators[4 site + ...])
// inserted and the legs contracted from the edge inward, never the 2^n vector.
long qasm_chain_expectation(const QasmChain *chain, const void *operators, void *value, EngineError *error);

// <psi|psi>: the lens with the identity at every site
long qasm_chain_norm(const QasmChain *chain, void *norm, EngineError *error);

// the bond across the cut after `site`, or 0 past the last cut
unsigned int qasm_chain_bond(const QasmChain *chain, unsigned int site);

// the field elements the tensors hold: 2 x left bond x right bond, summed over the sites
unsigned long long qasm_chain_elements(const QasmChain *chain);

// the engine's seal over every tensor entry's bytes in site, sigma, row, column order; the number field only
long qasm_chain_seal(const QasmChain *chain, unsigned char *signum, EngineError *error);

// A Laurent polynomial in w: coefficients[j] is the coefficient of w^(low + j). The first and last coefficients are
// nonzero; no coefficients is zero.
typedef struct
{
    int low;
    unsigned int count;
    QasmNumber *coefficients;
} QasmPolynomial;

// An element of Q(sqrt2)[i](w), w = e^{i k/Delta^3} carried as a formal unit on the circle. Kept as symbolic_qubits.py's
// rat_make keeps it: both shifted to no negative power with one of them free of w, reduced by their monic gcd, and the
// denominator monic. That form is unique, so two equal functions hold equal coefficients.
typedef struct
{
    QasmPolynomial numerator;
    QasmPolynomial denominator;
} QasmRationalFunction;

// Q(sqrt2)[i](w); its elements are QasmRationalFunction
extern const QasmField qasm_rational_function_field;

// coefficient w^exponent, into a slot
long qasm_rational_function_set(QasmRationalFunction *value, const QasmNumber *coefficient, int exponent,
                                EngineError *error);

long qasm_rational_function_copy(const QasmRationalFunction *from, QasmRationalFunction *to, EngineError *error);

void qasm_rational_function_release(QasmRationalFunction *value);

long qasm_rational_function_add(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                QasmRationalFunction *sum, EngineError *error);

long qasm_rational_function_subtract(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                     QasmRationalFunction *difference, EngineError *error);

long qasm_rational_function_multiply(const QasmRationalFunction *left, const QasmRationalFunction *right,
                                     QasmRationalFunction *product, EngineError *error);

// zero refuses
long qasm_rational_function_invert(const QasmRationalFunction *value, QasmRationalFunction *inverse,
                                   EngineError *error);

// w on the unit circle: w goes to 1/w and every coefficient to its conjugate
long qasm_rational_function_conjugate(const QasmRationalFunction *value, QasmRationalFunction *conjugate,
                                      EngineError *error);

int qasm_rational_function_equal(const QasmRationalFunction *left, const QasmRationalFunction *right);

int qasm_rational_function_is_zero(const QasmRationalFunction *value);

// the function at w = omega, a number; a zero denominator there refuses
long qasm_rational_function_evaluate(const QasmRationalFunction *value, const QasmNumber *omega, QasmNumber *result,
                                     EngineError *error);

// symbolic_qubits' rat_str: the numerator's text, or "(numerator) / (denominator)"
long qasm_rational_function_text(const QasmRationalFunction *value, char *text, size_t room, EngineError *error);

// The boundary lens on the reduced-round SHA-256 wedge field (boundary_lens.py). Two boundary strands are pinned at a
// mid-compression anchor: the forward chunk seen from the digest and the backward chunk seen from the message. The
// lens reads invariants of the field between them, never its points.

// second differences drawn per field, per read
#define QASM_LENS_CURVATURE_SAMPLES 400u

// the degree-2 lift's ambient bits, the raw 256 and 256 AND-monomials
#define QASM_LENS_LIFT_BITS 512u

// the widest aperture, 2^20 images a strand
#define QASM_LENS_BITS_MOST 20u

// SHA-256's compression has 64 rounds
#define QASM_LENS_ROUNDS_MOST 64u

typedef struct
{
    unsigned int middle;
    unsigned int forward_word;
    unsigned int backward_word;
    unsigned int bits;
    unsigned long long seed;
    unsigned long long instance;
    unsigned int rounds;
} QasmLensRequest;

typedef struct
{
    unsigned int raw_rank;
    unsigned int complement;
    unsigned int lift_extra_rank;
    // of QASM_LENS_CURVATURE_SAMPLES second differences, how many vanished
    unsigned int forward_vanish;
    unsigned int backward_vanish;
    unsigned long long forward_fiber;
    unsigned long long backward_fiber;
    int reversible;
    int root_stable;
    unsigned char root[ENGINE_SIGNUM_BYTES];
} QasmLensReading;

// One frozen read (read_instance): both boundary fields at the anchor, and their invariants.
long qasm_lens_read(const QasmLensRequest *request, QasmLensReading *reading, EngineError *error);

// The seal self-test (seal_selftest): the forward field's generators sealed clean, then with one bit flipped.
long qasm_lens_seal_check(const QasmLensRequest *request, unsigned char *clean, unsigned char *flipped,
                          EngineError *error);

#ifdef __cplusplus
}
#endif

#endif
