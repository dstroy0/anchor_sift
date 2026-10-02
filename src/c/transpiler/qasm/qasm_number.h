// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_number.h: rationals, reals and the numbers of the field (qasm.h includes the parts in order)
#ifndef QASM_NUMBER_H
#define QASM_NUMBER_H

#include "qasm_circuit.h"

#ifdef __cplusplus
extern "C"
{
#endif

// Exact qubits, ported from exact_qubits.py, mps_qubits.py, symbolic_qubits.py and boundary_lens.py, which sit beside
// this header. An amplitude is an element of Q(sqrt2)[i] held as four exact rationals. H's 1/sqrt2 and T's
// (1 + i)/sqrt2 are carried exactly and never rounded. A value past the exact integer's width errors; it never wraps.

// The widest dense state: 2^30 amplitudes. The index of an amplitude is an unsigned long long either way.
#define QASM_DENSE_QUBITS_MAX 30u

    // A rational as Python's Fraction keeps one: the denominator positive, no factor common to the two, and zero as
    // 0/1.
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
#define QASM_NUMBER_ONE_INITIALIZER                                                                                    \
    {                                                                                                                  \
        {QASM_RATIONAL_ONE_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER},                                               \
        {                                                                                                              \
            QASM_RATIONAL_ZERO_INITIALIZER, QASM_RATIONAL_ZERO_INITIALIZER                                             \
        }                                                                                                              \
    }

// Room for any number's text in either form, its terminator included: eight integers of the width's decimal digits
// (log10 2 < 0.302), each with its sign and separator, and the form's own characters.
#define QASM_NUMBER_TEXT_CAPACITY                                                                                      \
    ((8ull * ((((unsigned long long)(ANCHOR_EXACT_BITS) * 302ull) / 1000ull) + 4ull)) + 32ull)

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

    // numerator / denominator, reduced; a zero denominator errors
    long qasm_rational_set(QasmRational *value, long long numerator, long long denominator, EngineError *error);

    // Each result may alias either operand. On an error the result is left unchanged.
    long qasm_rational_add(const QasmRational *left, const QasmRational *right, QasmRational *sum, EngineError *error);

    long qasm_rational_subtract(const QasmRational *left, const QasmRational *right, QasmRational *difference,
                                EngineError *error);

    long qasm_rational_multiply(const QasmRational *left, const QasmRational *right, QasmRational *product,
                                EngineError *error);

    // a zero divisor errors
    long qasm_rational_divide(const QasmRational *numerator, const QasmRational *divisor, QasmRational *quotient,
                              EngineError *error);

    void qasm_rational_negate(const QasmRational *value, QasmRational *negated);

    int qasm_rational_equal(const QasmRational *left, const QasmRational *right);

    int qasm_rational_is_zero(const QasmRational *value);

    // the text Python's str(Fraction) gives: "numerator" where the denominator is 1, "numerator/denominator" otherwise
    long qasm_rational_text(const QasmRational *value, char *text, size_t capacity, EngineError *error);

    long qasm_number_add(const QasmNumber *left, const QasmNumber *right, QasmNumber *sum, EngineError *error);

    long qasm_number_subtract(const QasmNumber *left, const QasmNumber *right, QasmNumber *difference,
                              EngineError *error);

    long qasm_number_multiply(const QasmNumber *left, const QasmNumber *right, QasmNumber *product, EngineError *error);

    // 1/x = conj(x) / |x|^2, with 1/(r0 + r1 sqrt2) = (r0 - r1 sqrt2)/(r0^2 - 2 r1^2); zero errors
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
    // used limbs (a 4-byte count, then 4 bytes a limb), little-endian. Two equal numbers give the same bytes at any
    // width. With bytes NULL it only counts; it returns the count either way.
    size_t qasm_number_bytes(const QasmNumber *value, unsigned char *bytes);

    // mps_qubits' f_str without its float: "a + b i", each part "p", "q*sqrt2" or "(p + q*sqrt2)"
    long qasm_number_text(const QasmNumber *value, char *text, size_t capacity, EngineError *error);

    // symbolic_qubits' k_short: "p", "q i" or "p + q i", each part "p", "qsqrt2", "sqrt2" or "(p+qsqrt2)"
    long qasm_number_short_text(const QasmNumber *value, char *text, size_t capacity, EngineError *error);

    // A field the chain runs over, unchanged: Q(sqrt2)[i] or its rational functions. An element slot is either filled
    // with zero bytes or holds a live element. Copy and each operation write a slot of either kind, releasing what it
    // held, and release frees what a slot holds and leaves it zero bytes. A result may alias an operand.
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

#ifdef __cplusplus
}
#endif

#endif
