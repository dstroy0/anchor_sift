// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QASM_H
#define QASM_H

#include "engine_config.h"
#include "exact_integer.h"

#ifdef __cplusplus
extern "C" {
#endif

// Exact qubits, ported from exact_qubits.py, mps_qubits.py, symbolic_qubits.py and boundary_lens.py, which sit beside
// this header. An amplitude is an element of Q(sqrt2)[i] held as four exact rationals, so H's 1/sqrt2 and T's
// (1 + i)/sqrt2 are carried exactly and never rounded. A value past the exact integer's width refuses; it never wraps.

#define QASM_REFUSED (-1L)

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

typedef enum
{
    QASM_GATE_X = 0,
    QASM_GATE_Y = 1,
    QASM_GATE_Z = 2,
    QASM_GATE_S = 3,
    QASM_GATE_H = 4,
    QASM_GATE_CNOT = 5,
    QASM_GATE_CZ = 6,
    // numbers[0] on every amplitude whose `first` and `second` bits are both 1
    QASM_GATE_CONTROLLED_PHASE = 7,
    // numbers: a 2 x 2 matrix, [out][in], on qubit `first`
    QASM_GATE_ONE_QUBIT = 8,
    // numbers: a 4 x 4 matrix, [2 t0 + t1][2 s0 + s1], on qubits `first` (s0) and `first + 1` (s1)
    QASM_GATE_TWO_QUBIT = 9
} QasmGateKind;

typedef struct
{
    QasmGateKind kind;
    unsigned int first;
    unsigned int second;
    const QasmNumber *numbers;
} QasmGate;

// |0...0>
long qasm_dense_alloc(QasmDense *state, unsigned int qubits, EngineError *error);

void qasm_dense_release(QasmDense *state);

// X, Z, S, H, CNOT, CZ and the controlled phase as exact_qubits.py applies them, Y as its Z then X then S, and the two
// matrix gates as mps_qubits.py's Dense applies them. On a refusal the state may be part applied.
long qasm_dense_apply(QasmDense *state, const QasmGate *gate, EngineError *error);

// <psi|psi>, the sum of every amplitude's |x|^2
long qasm_dense_norm(const QasmDense *state, QasmNumber *norm, EngineError *error);

int qasm_dense_equal(const QasmDense *left, const QasmDense *right);

// the engine's seal over the amplitudes' bytes in index order, where the Python keyed a blake2b over their text
long qasm_dense_seal(const QasmDense *state, unsigned char *signum, EngineError *error);

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
