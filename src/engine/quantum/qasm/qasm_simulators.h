// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_simulators.h: the dense, self and chain simulators (qasm.h includes the parts in order)
#ifndef QASM_SIMULATORS_H
#define QASM_SIMULATORS_H

#include "qasm_number.h"

#ifdef __cplusplus
extern "C"
{
#endif

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

    // X, Z, S, H, CNOT, CZ and the controlled phase as exact_qubits.py applies them, Y as its Z then X then S, and the
    // two matrix gates as mps_qubits.py's Dense applies them. On a refusal the state may be part applied.
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
#define QASM_SELF_QUBITS_MAX 5u

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
        unsigned long long record_capacity;
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
    } QasmSelfMeasurement;

    long qasm_self_run(const QasmSelfRequest *request, QasmSelfMeasurement *measurement);

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

    // The boundary lens: <psi|O|psi> with each site's operator (2 x 2 elements, [sigma'][sigma], operators[4 site +
    // ...]) inserted and the legs contracted from the edge inward, never the 2^n vector.
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

    // An element of Q(sqrt2)[i](w), w = e^{i k/Delta^3} carried as a formal unit on the circle. Kept as
    // symbolic_qubits.py's rat_make keeps it: both shifted to no negative power with one of them free of w, reduced by
    // their monic gcd, and the denominator monic. That form is unique. Two equal functions hold equal coefficients.
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
    long qasm_rational_function_text(const QasmRationalFunction *value, char *text, size_t capacity,
                                     EngineError *error);

// The boundary lens on the reduced-round SHA-256 wedge field (boundary_lens.py). Two boundary strands are pinned at a
// mid-compression anchor: the forward chunk seen from the digest and the backward chunk seen from the message. The
// lens reads invariants of the field between them, never its points.

// second differences drawn per field, per read
#define QASM_LENS_CURVATURE_SAMPLES 400u

// the degree-2 lift's ambient bits, the raw 256 and 256 AND-monomials
#define QASM_LENS_LIFT_BITS 512u

// the widest aperture, 2^20 images a strand
#define QASM_LENS_BITS_MAX 20u

// SHA-256's compression has 64 rounds
#define QASM_LENS_ROUNDS_MAX 64u

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
    } QasmLensMeasurement;

    // One frozen read (read_instance): both boundary fields at the anchor, and their invariants.
    long qasm_lens_read(const QasmLensRequest *request, QasmLensMeasurement *measurement, EngineError *error);

    // The seal self-test (seal_selftest): the forward field's generators sealed clean, then with one bit flipped.
    long qasm_lens_seal_check(const QasmLensRequest *request, unsigned char *clean, unsigned char *flipped,
                              EngineError *error);

#ifdef __cplusplus
}
#endif

#endif
