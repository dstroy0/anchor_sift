// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_exact_test_symbols.cu: MPS qubits, symbols, the lens and main
#include "qasm_exact_test_internal.h"

static void qasm_test_mps_qubits(QasmResults *results)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();

    // Bell
    QasmChain bell = {NULL, 0u, NULL};
    const QasmTestTarget on_bell = {&bell, NULL};
    const unsigned int bell_bonds[1] = {2u};
    const int bell_built =
        (qasm_chain_alloc(&bell, &qasm_number_field, 2u, &error) == 0L) && (qasm_test_ghz(&on_bell, 2u, &error) == 0L);
    qasm_test_check(results,
                    bell_built && qasm_test_bonds_are(&bell, bell_bonds) && (qasm_chain_elements(&bell) == 8ull) &&
                        qasm_test_norm_is_one(&bell, &error) &&
                        qasm_test_amplitude_is(&bell, 0u, "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_amplitude_is(&bell, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: Bell, bond [2], 8 elements, <psi|psi> exactly 1, <00| = <11| = 1/2*sqrt2 + 0 i");

    // GHZ-6
    QasmChain ghz_six = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_six = {&ghz_six, NULL};
    const unsigned int ghz_six_bonds[5] = {2u, 2u, 2u, 2u, 2u};
    const int ghz_six_built = (qasm_chain_alloc(&ghz_six, &qasm_number_field, 6u, &error) == 0L) &&
                              (qasm_test_ghz(&on_ghz_six, 6u, &error) == 0L);
    qasm_test_check(results,
                    ghz_six_built && qasm_test_bonds_are(&ghz_six, ghz_six_bonds) &&
                        (qasm_chain_elements(&ghz_six) == 40ull) && qasm_test_norm_is_one(&ghz_six, &error) &&
                        qasm_test_amplitude_is(&ghz_six, 0u, "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_amplitude_is(&ghz_six, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: GHZ-6, bonds [2, 2, 2, 2, 2], 40 elements, <psi|psi> exactly 1");

    // GHZ-4, then a controlled-T on the last pair
    QasmChain ghz_t = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_t = {&ghz_t, NULL};
    const unsigned int ghz_t_bonds[3] = {2u, 2u, 2u};
    const int ghz_t_built = (qasm_chain_alloc(&ghz_t, &qasm_number_field, 4u, &error) == 0L) &&
                            (qasm_test_ghz_t(&on_ghz_t, 4u, &error) == 0L);
    qasm_test_check(results,
                    ghz_t_built && qasm_test_bonds_are(&ghz_t, ghz_t_bonds) && (qasm_chain_elements(&ghz_t) == 24ull) &&
                        qasm_test_norm_is_one(&ghz_t, &error) &&
                        qasm_test_amplitude_is(&ghz_t, 0u, "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_amplitude_is(&ghz_t, 1u, "1/2 + 1/2 i", &error),
                    "mps: GHZ-4 + controlled-T, bonds [2, 2, 2], 24 elements, <1111| = 1/2 + 1/2 i");

    // GHZ-100
    const unsigned long long hundred_start = engine_clock_microseconds();
    QasmChain ghz_hundred = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_hundred = {&ghz_hundred, NULL};
    const int hundred_built = (qasm_chain_alloc(&ghz_hundred, &qasm_number_field, 100u, &error) == 0L) &&
                              (qasm_test_ghz(&on_ghz_hundred, 100u, &error) == 0L);
    unsigned int widest = 0u;
    for (unsigned int site = 0u; (hundred_built != 0) && ((site + 1u) < 100u); site += 1u)
    {
        const unsigned int bond = qasm_chain_bond(&ghz_hundred, site);
        widest = (bond > widest) ? bond : widest;
    }
    qasm_test_check(results,
                    hundred_built && (widest == 2u) && (qasm_chain_elements(&ghz_hundred) == 792ull) &&
                        qasm_test_norm_is_one(&ghz_hundred, &error) &&
                        qasm_test_amplitude_is(&ghz_hundred, 0u, "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_amplitude_is(&ghz_hundred, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: GHZ-100, widest bond 2, 792 elements, <psi|psi> exactly 1, both ends 1/2*sqrt2 + 0 i");
    printf("  GHZ-100: %llu field elements, %llu us\n", qasm_chain_elements(&ghz_hundred),
           engine_clock_microseconds() - hundred_start);

    // the scrambler: 10 qubits, depth 6
    const unsigned long long scrambler_start = engine_clock_microseconds();
    QasmChain scrambled = {NULL, 0u, NULL};
    const QasmTestTarget on_scrambled = {&scrambled, NULL};
    const unsigned int scrambled_bonds[9] = {2u, 3u, 6u, 8u, 8u, 8u, 6u, 3u, 2u};
    const int scrambled_built = (qasm_chain_alloc(&scrambled, &qasm_number_field, 10u, &error) == 0L) &&
                                (qasm_test_scrambler(&on_scrambled, 10u, 6u, &error) == 0L);
    qasm_test_check(results,
                    scrambled_built && qasm_test_bonds_are(&scrambled, scrambled_bonds) &&
                        (qasm_chain_elements(&scrambled) == 552ull) && qasm_test_norm_is_one(&scrambled, &error),
                    "mps: scrambler 10 x 6, bonds [2, 3, 6, 8, 8, 8, 6, 3, 2], 552 elements, <psi|psi> exactly 1");
    printf("  scrambler: bonds");
    for (unsigned int site = 0u; (scrambled_built != 0) && ((site + 1u) < 10u); site += 1u)
    {
        printf(" %u", qasm_chain_bond(&scrambled, site));
    }
    printf(", %llu us\n", engine_clock_microseconds() - scrambler_start);

    // reversibility on the compact form
    QasmChain round_trip = {NULL, 0u, NULL};
    QasmChain ground = {NULL, 0u, NULL};
    const QasmTestTarget on_round_trip = {&round_trip, NULL};
    int turned = (qasm_chain_alloc(&round_trip, &qasm_number_field, 5u, &error) == 0L) &&
                 (qasm_chain_alloc(&ground, &qasm_number_field, 5u, &error) == 0L) &&
                 (qasm_test_one(&on_round_trip, qasm_test_hadamard, 0u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 0u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 1u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_controlled_t, 2u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 3u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 3u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_controlled_t_back, 2u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 1u, &error) == 0L) &&
                 (qasm_test_two(&on_round_trip, qasm_test_cnot, 0u, &error) == 0L) &&
                 (qasm_test_one(&on_round_trip, qasm_test_hadamard, 0u, &error) == 0L);
    for (unsigned long long index = 0ull; (turned != 0) && (index < 32ull); index += 1ull)
    {
        unsigned char bits[5];
        QasmNumber returned = qasm_number_zero;
        QasmNumber expected = qasm_number_zero;
        qasm_test_bits(index, 5u, bits);
        turned = (qasm_chain_amplitude(&round_trip, bits, &returned, &error) == 0L) &&
                 (qasm_chain_amplitude(&ground, bits, &expected, &error) == 0L) &&
                 qasm_number_equal(&returned, &expected);
    }
    qasm_test_check(results, turned, "mps: a five-qubit circuit, then its exact inverse, returns |00000> to the bit");

    // compact against dense
    qasm_test_check(results, qasm_test_cross(qasm_test_ghz, &error),
                    "mps: cross-check GHZ chain, compact against dense on 6 qubits, all 64 amplitudes agree");
    qasm_test_check(results, qasm_test_cross(qasm_test_ghz_t, &error),
                    "mps: cross-check GHZ + controlled-T, compact against dense on 6 qubits, all 64 agree");
    qasm_test_check(results, qasm_test_cross(qasm_test_scrambler_six, &error),
                    "mps: cross-check scrambler depth 6, compact against dense on 6 qubits, all 64 agree");

    // the chain's seal repeats and tells GHZ-6 from GHZ-4 + controlled-T
    unsigned char six_root[ENGINE_SIGNUM_BYTES];
    unsigned char six_again[ENGINE_SIGNUM_BYTES];
    unsigned char t_root[ENGINE_SIGNUM_BYTES];
    const int sealed = ghz_six_built && ghz_t_built && (qasm_chain_seal(&ghz_six, six_root, &error) == 0L) &&
                       (qasm_chain_seal(&ghz_six, six_again, &error) == 0L) &&
                       (qasm_chain_seal(&ghz_t, t_root, &error) == 0L);
    qasm_test_check(results,
                    sealed && (memcmp(six_root, six_again, sizeof(six_root)) == 0) &&
                        (memcmp(six_root, t_root, sizeof(six_root)) != 0),
                    "mps: the chain's seal repeats, and two different states seal differently");

    EngineError engine_error;
    memset(&engine_error, 0, sizeof(engine_error));
    qasm_test_check(results,
                    qasm_test_error_here(qasm_chain_apply_two(&bell, qasm_test_cnot, 1u, &engine_error), &engine_error),
                    "mps: a two-site gate on the last site errors, a request error from qasm");
    // site + 1 wraps here and reads past the tensors
    qasm_test_check(results, (qasm_chain_bond(&bell, 1u) == 0u) && (qasm_chain_bond(&bell, 0xFFFFFFFFu) == 0u),
                    "mps: the bond past the last cut is 0, the widest site index included");
    qasm_test_check(results, qasm_test_clean(&error), "mps: no error was raised on the paths that held");
    qasm_chain_release(&bell);
    qasm_chain_release(&ghz_six);
    qasm_chain_release(&ghz_t);
    qasm_chain_release(&ghz_hundred);
    qasm_chain_release(&scrambled);
    qasm_chain_release(&round_trip);
    qasm_chain_release(&ground);
    printf("  mps qubits: %llu us\n", engine_clock_microseconds() - start);
}

static long qasm_test_symbol(QasmRationalFunction *slot, const QasmNumber *coefficient, int exponent,
                             EngineError *error)
{
    return qasm_rational_function_set(slot, coefficient, exponent, error);
}

static long qasm_test_symbols(QasmTestSymbols *symbols, EngineError *error)
{
    QasmNumber minus_half_sqrt2;
    qasm_number_negate(&qasm_number_half_sqrt2, &minus_half_sqrt2);
    long status = qasm_test_symbol(&symbols->omega, &qasm_number_one, 1, error);
    for (unsigned int entry = 0u; (status == 0L) && (entry < 16u); entry += 1u)
    {
        const int cnot_one = (entry == 0u) || (entry == 5u) || (entry == 11u) || (entry == 14u);
        const int diagonal = (entry == 0u) || (entry == 5u) || (entry == 10u);
        status = qasm_test_symbol(&symbols->cnot[entry], cnot_one ? &qasm_number_one : &qasm_number_zero, 0, error);
        status = (status == 0L) ? qasm_test_symbol(&symbols->cphase[entry],
                                                   diagonal ? &qasm_number_one : &qasm_number_zero, 0, error)
                                : status;
    }
    status = (status == 0L) ? qasm_rational_function_copy(&symbols->omega, &symbols->cphase[15], error) : status;
    for (unsigned int entry = 0u; (status == 0L) && (entry < 4u); entry += 1u)
    {
        const int diagonal = (entry == 0u) || (entry == 3u);
        status = qasm_test_symbol(&symbols->hadamard[entry],
                                  (entry == 3u) ? &minus_half_sqrt2 : &qasm_number_half_sqrt2, 0, error);
        status = (status == 0L) ? qasm_test_symbol(&symbols->identity[entry],
                                                   diagonal ? &qasm_number_one : &qasm_number_zero, 0, error)
                                : status;
        status = (status == 0L) ? qasm_test_symbol(&symbols->pauli_x[entry],
                                                   diagonal ? &qasm_number_zero : &qasm_number_one, 0, error)
                                : status;
        status = (status == 0L)
                     ? qasm_test_symbol(&symbols->pauli_z[entry],
                                        (entry == 0u) ? &qasm_number_one
                                                      : ((entry == 3u) ? &qasm_number_minus_one : &qasm_number_zero),
                                        0, error)
                     : status;
        status = (status == 0L) ? qasm_test_symbol(&symbols->local_phase[entry],
                                                   diagonal ? &qasm_number_one : &qasm_number_zero, 0, error)
                                : status;
    }
    status = (status == 0L) ? qasm_rational_function_copy(&symbols->omega, &symbols->local_phase[3], error) : status;
    return status;
}

static void qasm_test_symbols_release(QasmTestSymbols *symbols)
{
    for (unsigned int entry = 0u; entry < 16u; entry += 1u)
    {
        qasm_rational_function_release(&symbols->cnot[entry]);
        qasm_rational_function_release(&symbols->cphase[entry]);
    }
    for (unsigned int entry = 0u; entry < 4u; entry += 1u)
    {
        qasm_rational_function_release(&symbols->hadamard[entry]);
        qasm_rational_function_release(&symbols->identity[entry]);
        qasm_rational_function_release(&symbols->pauli_x[entry]);
        qasm_rational_function_release(&symbols->pauli_z[entry]);
        qasm_rational_function_release(&symbols->local_phase[entry]);
    }
    qasm_rational_function_release(&symbols->omega);
}

// <psi|O|psi> with one site's operator per site, copied into a run of slots the chain reads
static long qasm_test_lens(const QasmChain *chain, const QasmRationalFunction *const *each, QasmRationalFunction *value,
                           EngineError *error)
{
    QasmRationalFunction operators[12];
    memset(operators, 0, sizeof(operators));
    long status = 0L;
    for (unsigned int site = 0u; (status == 0L) && (site < chain->sites); site += 1u)
    {
        for (unsigned int entry = 0u; (status == 0L) && (entry < 4u); entry += 1u)
        {
            status = qasm_rational_function_copy(&each[site][entry], &operators[(4u * site) + entry], error);
        }
    }
    status = (status == 0L) ? qasm_chain_expectation(chain, operators, value, error) : status;
    for (unsigned int entry = 0u; entry < 12u; entry += 1u)
    {
        qasm_rational_function_release(&operators[entry]);
    }
    return status;
}

static void qasm_test_symbolic_qubits(QasmResults *results)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();
    QasmTestSymbols symbols;
    memset(&symbols, 0, sizeof(symbols));
    const int symbols_built = (qasm_test_symbols(&symbols, &error) == 0L);
    qasm_test_check(results, symbols_built, "symbolic: the gates and observables build over Q(sqrt2)[i](w)");

    // the delta-Bell state (|00> + w|11>)/sqrt2
    QasmChain bell = {NULL, 0u, NULL};
    const unsigned int bell_bonds[1] = {2u};
    const int bell_built = symbols_built &&
                           (qasm_chain_alloc(&bell, &qasm_rational_function_field, 2u, &error) == 0L) &&
                           (qasm_chain_apply_one(&bell, symbols.hadamard, 0u, &error) == 0L) &&
                           (qasm_chain_apply_two(&bell, symbols.cnot, 0u, &error) == 0L) &&
                           (qasm_chain_apply_two(&bell, symbols.cphase, 0u, &error) == 0L);
    QasmRationalFunction value;
    memset(&value, 0, sizeof(value));
    const unsigned char zeros[2] = {0u, 0u};
    const unsigned char ones[2] = {1u, 1u};
    qasm_test_check(results,
                    bell_built && qasm_test_bonds_are(&bell, bell_bonds) &&
                        (qasm_chain_amplitude(&bell, zeros, &value, &error) == 0L) &&
                        qasm_test_function_is(&value, "1/2sqrt2", &error) &&
                        (qasm_chain_amplitude(&bell, ones, &value, &error) == 0L) &&
                        qasm_test_function_is(&value, "(1/2sqrt2)w", &error),
                    "symbolic: delta-Bell, bond [2], <00| = 1/2sqrt2, <11| = (1/2sqrt2)w");

    QasmRationalFunction norm;
    QasmRationalFunction xx;
    QasmRationalFunction zz;
    QasmRationalFunction x0;
    memset(&norm, 0, sizeof(norm));
    memset(&xx, 0, sizeof(xx));
    memset(&zz, 0, sizeof(zz));
    memset(&x0, 0, sizeof(x0));
    const QasmRationalFunction *const identities[2] = {symbols.identity, symbols.identity};
    const QasmRationalFunction *const both_x[3] = {symbols.pauli_x, symbols.pauli_x, symbols.pauli_x};
    const QasmRationalFunction *const both_z[2] = {symbols.pauli_z, symbols.pauli_z};
    const QasmRationalFunction *const first_x[2] = {symbols.pauli_x, symbols.identity};
    const int norm_read = bell_built && (qasm_test_lens(&bell, identities, &norm, &error) == 0L);
    qasm_test_check(
        results,
        norm_read && qasm_test_function_is(&norm, "1", &error) &&
            qasm_rational_function_equal(&norm, (const QasmRationalFunction *)qasm_rational_function_field.one),
        "symbolic: <psi|psi> = 1 exactly, w cancels");
    const int lens_read = bell_built && (qasm_test_lens(&bell, both_x, &xx, &error) == 0L) &&
                          (qasm_test_lens(&bell, both_z, &zz, &error) == 0L) &&
                          (qasm_test_lens(&bell, first_x, &x0, &error) == 0L);
    qasm_test_check(results, lens_read && qasm_test_function_is(&xx, "(1/2 + (1/2)w^2) / (w)", &error),
                    "symbolic: the boundary lens reads <X0 X1> = (1/2 + (1/2)w^2) / (w)");
    qasm_test_check(results,
                    lens_read && qasm_test_function_is(&zz, "1", &error) && qasm_test_function_is(&x0, "0", &error),
                    "symbolic: <Z0 Z1> = 1 and <X0> = 0");

    // delta-GHZ3
    QasmChain ghz = {NULL, 0u, NULL};
    const unsigned int ghz_bonds[2] = {2u, 2u};
    QasmRationalFunction xxx;
    memset(&xxx, 0, sizeof(xxx));
    const int ghz_read = symbols_built && (qasm_chain_alloc(&ghz, &qasm_rational_function_field, 3u, &error) == 0L) &&
                         (qasm_chain_apply_one(&ghz, symbols.hadamard, 0u, &error) == 0L) &&
                         (qasm_chain_apply_two(&ghz, symbols.cnot, 0u, &error) == 0L) &&
                         (qasm_chain_apply_two(&ghz, symbols.cnot, 1u, &error) == 0L) &&
                         (qasm_chain_apply_two(&ghz, symbols.cphase, 1u, &error) == 0L) &&
                         (qasm_test_lens(&ghz, both_x, &xxx, &error) == 0L);
    qasm_test_check(results,
                    ghz_read && qasm_test_bonds_are(&ghz, ghz_bonds) &&
                        qasm_test_function_is(&xxx, "(1/2 + (1/2)w^2) / (w)", &error),
                    "symbolic: delta-GHZ3, bonds [2, 2], <X0 X1 X2> = (1/2 + (1/2)w^2) / (w)");

    // a single-qubit phase couples nothing: the product stays rank 1
    QasmChain product = {NULL, 0u, NULL};
    const unsigned int product_bonds[2] = {1u, 1u};
    int product_built = symbols_built && (qasm_chain_alloc(&product, &qasm_rational_function_field, 3u, &error) == 0L);
    for (unsigned int site = 0u; (product_built != 0) && (site < 3u); site += 1u)
    {
        product_built = (qasm_chain_apply_one(&product, symbols.hadamard, site, &error) == 0L);
    }
    product_built = product_built && (qasm_chain_apply_one(&product, symbols.local_phase, 0u, &error) == 0L);
    qasm_test_check(results, product_built && qasm_test_bonds_are(&product, product_bonds),
                    "symbolic: |+++> with a phase on wire 0 keeps bonds [1, 1]");

    // host against host: w = e^{i pi/4} specializes the symbolic reading to the controlled-T one
    QasmChain numeric = {NULL, 0u, NULL};
    QasmNumber symbolic_xx = qasm_number_zero;
    QasmNumber numeric_xx = qasm_number_zero;
    QasmNumber symbolic_norm = qasm_number_zero;
    QasmNumber numeric_x[4];
    QasmNumber both_numeric_x[8];
    numeric_x[0] = qasm_number_zero;
    numeric_x[1] = qasm_number_one;
    numeric_x[2] = qasm_number_one;
    numeric_x[3] = qasm_number_zero;
    for (unsigned int entry = 0u; entry < 8u; entry += 1u)
    {
        both_numeric_x[entry] = numeric_x[entry % 4u];
    }
    const int crossed =
        lens_read && norm_read &&
        (qasm_rational_function_evaluate(&xx, &qasm_number_eighth_turn, &symbolic_xx, &error) == 0L) &&
        (qasm_rational_function_evaluate(&norm, &qasm_number_eighth_turn, &symbolic_norm, &error) == 0L) &&
        (qasm_chain_alloc(&numeric, &qasm_number_field, 2u, &error) == 0L) &&
        (qasm_chain_apply_one(&numeric, qasm_test_hadamard, 0u, &error) == 0L) &&
        (qasm_chain_apply_two(&numeric, qasm_test_cnot, 0u, &error) == 0L) &&
        (qasm_chain_apply_two(&numeric, qasm_test_controlled_t, 0u, &error) == 0L) &&
        (qasm_chain_expectation(&numeric, both_numeric_x, &numeric_xx, &error) == 0L);
    qasm_test_check(results,
                    crossed && qasm_number_equal(&symbolic_xx, &numeric_xx) &&
                        qasm_test_short_is(&symbolic_xx, "1/2sqrt2", &error),
                    "symbolic: <X0 X1> at w = e^{i pi/4} equals the controlled-T reading, 1/2sqrt2");
    qasm_test_check(results, crossed && qasm_number_equal(&symbolic_norm, &qasm_number_one),
                    "symbolic: the norm at w = e^{i pi/4} is exactly 1");

    // The evaluation forms one power past the highest. w^(bits - 1) at w = 2 is
    // 2^(bits - 1), which the width holds; the power past it, 2^bits, does not.
    QasmRationalFunction widest;
    memset(&widest, 0, sizeof(widest));
    QasmNumber two = qasm_number_zero;
    QasmNumber evaluated = qasm_number_zero;
    AnchorExactInteger top_bit;
    anchor_exact_zero(&top_bit);
    top_bit.limb[ANCHOR_EXACT_LIMBS - 1u] = 0x80000000u;
    top_bit.sign = 1;
    AnchorExactInteger unit;
    anchor_exact_zero(&unit);
    unit.limb[0] = 1u;
    unit.sign = 1;
    // the width's bits are a power of two far below 2^31. Bits - 1 fits in an int
    const int widest_power = (int)(ANCHOR_EXACT_BITS - 1ull);
    const int widest_read = (qasm_rational_set(&two.real.rational, 2LL, 1LL, &error) == 0L) &&
                            (qasm_rational_function_set(&widest, &qasm_number_one, widest_power, &error) == 0L) &&
                            (qasm_rational_function_evaluate(&widest, &two, &evaluated, &error) == 0L);
    qasm_test_check(results,
                    widest_read && anchor_exact_equal(&evaluated.real.rational.numerator, &top_bit) &&
                        anchor_exact_equal(&evaluated.real.rational.denominator, &unit) &&
                        qasm_rational_is_zero(&evaluated.real.sqrt2) &&
                        qasm_rational_is_zero(&evaluated.imaginary.rational) &&
                        qasm_rational_is_zero(&evaluated.imaginary.sqrt2),
                    "symbolic: w^(bits - 1) at w = 2 evaluates to 2^(bits - 1), the widest power the width holds");
    qasm_rational_function_release(&widest);

    EngineError engine_error;
    memset(&engine_error, 0, sizeof(engine_error));
    QasmRationalFunction zero_function;
    QasmRationalFunction inverse;
    memset(&zero_function, 0, sizeof(zero_function));
    memset(&inverse, 0, sizeof(inverse));
    const int zero_set = (qasm_rational_function_set(&zero_function, &qasm_number_zero, 0, &error) == 0L);
    qasm_test_check(
        results,
        zero_set &&
            qasm_test_error_here(qasm_rational_function_invert(&zero_function, &inverse, &engine_error), &engine_error),
        "symbolic: inverting zero errors, a request error from qasm");
    qasm_test_check(results, qasm_test_clean(&error), "symbolic: no error was raised on the paths that held");
    qasm_rational_function_release(&value);
    qasm_rational_function_release(&norm);
    qasm_rational_function_release(&xx);
    qasm_rational_function_release(&zz);
    qasm_rational_function_release(&x0);
    qasm_rational_function_release(&xxx);
    qasm_rational_function_release(&zero_function);
    qasm_rational_function_release(&inverse);
    qasm_test_symbols_release(&symbols);
    qasm_chain_release(&bell);
    qasm_chain_release(&ghz);
    qasm_chain_release(&product);
    qasm_chain_release(&numeric);
    printf("  symbolic qubits: %llu us\n", engine_clock_microseconds() - start);
}

static void qasm_test_boundary_lens(QasmResults *results)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();
    // lens_counts: every round from 16 to 30 read 126, 130, 0, 30, 14, 64, 64, True, True
    int every = 1;
    for (unsigned int rounds = 16u; rounds <= 30u; rounds += 1u)
    {
        const QasmLensRequest request = {13u, 13u, 8u, 6u, 2024ull, 0ull, rounds};
        QasmLensMeasurement measurement;
        memset(&measurement, 0, sizeof(measurement));
        const int read = (qasm_lens_read(&request, &measurement, &error) == 0L);
        const int ok = read && (measurement.raw_rank == 126u) && (measurement.complement == 130u) &&
                       (measurement.lift_extra_rank == 0u) && (measurement.forward_vanish == 30u) &&
                       (measurement.backward_vanish == 14u) && (measurement.forward_fiber == 64ull) &&
                       (measurement.backward_fiber == 64ull) && (measurement.reversible != 0) &&
                       (measurement.root_stable != 0);
        if (ok == 0)
        {
            printf("  round %u: rank %u, complement %u, lift %u, vanish %u and %u, fibers %llu and %llu, clock %d, "
                   "root %d\n",
                   rounds, measurement.raw_rank, measurement.complement, measurement.lift_extra_rank,
                   measurement.forward_vanish, measurement.backward_vanish, measurement.forward_fiber,
                   measurement.backward_fiber, measurement.reversible, measurement.root_stable);
        }
        every = every && ok;
    }
    qasm_test_check(results, every,
                    "lens: rounds 16 to 30 each read rank 126, complement 130, lift 0, vanish 30 and 14 of 400, "
                    "fibers 64 and 64, the clock closed and the root stable, as the Python did");
    unsigned char clean[ENGINE_SIGNUM_BYTES];
    unsigned char flipped[ENGINE_SIGNUM_BYTES];
    const QasmLensRequest seal_request = {13u, 13u, 8u, 6u, 2024ull, 0ull, 30u};
    qasm_test_check(results,
                    (qasm_lens_seal_check(&seal_request, clean, flipped, &error) == 0L) &&
                        (memcmp(clean, flipped, sizeof(clean)) != 0),
                    "lens: one flipped generator bit changes the seal");
    EngineError engine_error;
    memset(&engine_error, 0, sizeof(engine_error));
    QasmLensMeasurement measurement;
    const QasmLensRequest too_wide = {13u, 13u, 8u, QASM_LENS_BITS_MAX + 1u, 2024ull, 0ull, 30u};
    qasm_test_check(results,
                    qasm_test_error_here(qasm_lens_read(&too_wide, &measurement, &engine_error), &engine_error),
                    "lens: an aperture past the widest errors, a request error from qasm");
    qasm_test_check(results, qasm_test_clean(&error), "lens: no error was raised on the paths that held");
    printf("  boundary lens: %llu us\n", engine_clock_microseconds() - start);
}

int main(void)
{
    QasmResults results = {0u, 0u};
    qasm_test_gates();
    qasm_test_exact_qubits(&results);
    qasm_test_mps_qubits(&results);
    qasm_test_symbolic_qubits(&results);
    qasm_test_boundary_lens(&results);
    printf("  qasm exact test: %u checks, %u failed\n", results.checks, results.failed);
    return (results.failed == 0u) ? 0 : 1;
}
