// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The four Python models' demonstrations, run on the port, each result checked against the value the Python printed
// (exact_qubits.py, mps_qubits.py, symbolic_qubits.py and boundary_lens.py 13 13 8 6 2024 1 16 30).
#include "qasm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} QasmTally;

static void qasm_test_check(QasmTally *tally, int held, const char *claim)
{
    tally->checks += 1u;
    if (held == 0)
    {
        tally->failed += 1u;
        printf("  FAIL %s\n", claim);
    }
}

static char qasm_test_text[QASM_NUMBER_TEXT_ROOM];

// f_str's text of a number, without the float the Python printed beside it
static int qasm_test_number_is(const QasmNumber *value, const char *expected, EngineError *error)
{
    return (qasm_number_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L)
        && (strcmp(qasm_test_text, expected) == 0);
}

static int qasm_test_short_is(const QasmNumber *value, const char *expected, EngineError *error)
{
    return (qasm_number_short_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L)
        && (strcmp(qasm_test_text, expected) == 0);
}

static int qasm_test_function_is(const QasmRationalFunction *value, const char *expected, EngineError *error)
{
    return (qasm_rational_function_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L)
        && (strcmp(qasm_test_text, expected) == 0);
}

static int qasm_test_clean(const EngineError *error)
{
    return error->kind == ENGINE_ERROR_NONE;
}

static int qasm_test_refused_here(long status, const EngineError *error)
{
    return (status == QASM_REFUSED) && (error->kind == ENGINE_ERROR_REQUEST) && (error->module == ENGINE_MODULE_QASM);
}

// the gates, as mps_qubits.py builds them: [out][in], and [2 t0 + t1][2 s0 + s1]
static QasmNumber qasm_test_hadamard[4];
static QasmNumber qasm_test_cnot[16];
static QasmNumber qasm_test_controlled_t[16];
static QasmNumber qasm_test_controlled_t_back[16];

static void qasm_test_gates(void)
{
    QasmNumber minus_half_sqrt2;
    qasm_number_negate(&qasm_number_half_sqrt2, &minus_half_sqrt2);
    qasm_test_hadamard[0] = qasm_number_half_sqrt2;
    qasm_test_hadamard[1] = qasm_number_half_sqrt2;
    qasm_test_hadamard[2] = qasm_number_half_sqrt2;
    qasm_test_hadamard[3] = minus_half_sqrt2;
    for (unsigned int entry = 0u; entry < 16u; entry += 1u)
    {
        qasm_test_cnot[entry] = qasm_number_zero;
        qasm_test_controlled_t[entry] = qasm_number_zero;
        qasm_test_controlled_t_back[entry] = qasm_number_zero;
    }
    // 00 -> 00, 01 -> 01, 11 -> 10, 10 -> 11: the control is the left qubit
    qasm_test_cnot[0] = qasm_number_one;
    qasm_test_cnot[5] = qasm_number_one;
    qasm_test_cnot[11] = qasm_number_one;
    qasm_test_cnot[14] = qasm_number_one;
    for (unsigned int diagonal = 0u; diagonal < 3u; diagonal += 1u)
    {
        qasm_test_controlled_t[5u * diagonal] = qasm_number_one;
        qasm_test_controlled_t_back[5u * diagonal] = qasm_number_one;
    }
    qasm_test_controlled_t[15] = qasm_number_eighth_turn;
    qasm_test_controlled_t_back[15] = qasm_number_eighth_turn_back;
}

// one build runs on the chain or on the dense state, so the two can be compared amplitude for amplitude
typedef struct
{
    QasmChain *chain;
    QasmDense *dense;
} QasmTestTarget;

static long qasm_test_one(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error)
{
    if (target->chain != NULL)
    {
        return qasm_chain_apply_one(target->chain, gate, site, error);
    }
    const QasmGate apply = {QASM_GATE_ONE_QUBIT, site, 0u, gate};
    return qasm_dense_apply(target->dense, &apply, error);
}

static long qasm_test_two(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error)
{
    if (target->chain != NULL)
    {
        return qasm_chain_apply_two(target->chain, gate, site, error);
    }
    const QasmGate apply = {QASM_GATE_TWO_QUBIT, site, 0u, gate};
    return qasm_dense_apply(target->dense, &apply, error);
}

// build_ghz: H on 0, then a cascade of adjacent CNOTs
static long qasm_test_ghz(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    long status = qasm_test_one(target, qasm_test_hadamard, 0u, error);
    for (unsigned int site = 0u; (status == 0L) && ((site + 1u) < sites); site += 1u)
    {
        status = qasm_test_two(target, qasm_test_cnot, site, error);
    }
    return status;
}

// nc_build: the GHZ chain, then a controlled-T on sites 2 and 3
static long qasm_test_ghz_t(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    const long status = qasm_test_ghz(target, sites, error);
    return (status == 0L) ? qasm_test_two(target, qasm_test_controlled_t, 2u, error) : status;
}

// build_scrambler: |+..+>, then bricks of controlled-T, H on every wire between bricks
static long qasm_test_scrambler(const QasmTestTarget *target, unsigned int sites, unsigned int depth,
                                EngineError *error)
{
    long status = 0L;
    for (unsigned int site = 0u; (status == 0L) && (site < sites); site += 1u)
    {
        status = qasm_test_one(target, qasm_test_hadamard, site, error);
    }
    for (unsigned int layer = 0u; (status == 0L) && (layer < depth); layer += 1u)
    {
        for (unsigned int site = layer % 2u; (status == 0L) && ((site + 1u) < sites); site += 2u)
        {
            status = qasm_test_two(target, qasm_test_controlled_t, site, error);
        }
        for (unsigned int site = 0u; (status == 0L) && (site < sites); site += 1u)
        {
            status = qasm_test_one(target, qasm_test_hadamard, site, error);
        }
    }
    return status;
}

static long qasm_test_scrambler_six(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    return qasm_test_scrambler(target, sites, 6u, error);
}

static int qasm_test_bonds_are(const QasmChain *chain, const unsigned int *bonds)
{
    int equal = 1;
    for (unsigned int site = 0u; (equal != 0) && ((site + 1u) < chain->sites); site += 1u)
    {
        equal = (qasm_chain_bond(chain, site) == bonds[site]);
    }
    return equal;
}

static void qasm_test_bits(unsigned long long index, unsigned int sites, unsigned char *bits)
{
    for (unsigned int site = 0u; site < sites; site += 1u)
    {
        // one bit of the index, 0 or 1
        bits[site] = (unsigned char)((index >> site) & 1ull);
    }
}

static int qasm_test_amplitude_is(const QasmChain *chain, unsigned int value, const char *expected,
                                  EngineError *error)
{
    unsigned char bits[128];
    QasmNumber amplitude = qasm_number_zero;
    for (unsigned int site = 0u; site < chain->sites; site += 1u)
    {
        // the value is 0 or 1, which an unsigned char holds exactly
        bits[site] = (unsigned char)value;
    }
    return (qasm_chain_amplitude(chain, bits, &amplitude, error) == 0L)
        && qasm_test_number_is(&amplitude, expected, error);
}

static int qasm_test_norm_is_one(const QasmChain *chain, EngineError *error)
{
    QasmNumber norm = qasm_number_zero;
    return (qasm_chain_norm(chain, &norm, error) == 0L) && qasm_number_equal(&norm, &qasm_number_one);
}

static void qasm_test_exact_qubits(QasmTally *tally)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    QasmNumber norm = qasm_number_zero;
    const unsigned long long start = engine_clock_microseconds();

    // Bell: H0, CNOT 0 -> 1
    QasmDense bell = {0u, NULL};
    const QasmGate hadamard_zero = {QASM_GATE_H, 0u, 0u, NULL};
    const QasmGate cnot_zero_one = {QASM_GATE_CNOT, 0u, 1u, NULL};
    const int bell_built = (qasm_dense_alloc(&bell, 2u, &error) == 0L)
                        && (qasm_dense_apply(&bell, &hadamard_zero, &error) == 0L)
                        && (qasm_dense_apply(&bell, &cnot_zero_one, &error) == 0L);
    qasm_test_check(tally, bell_built, "exact: the Bell pair builds");
    qasm_test_check(tally,
                    bell_built && qasm_test_number_is(&bell.amplitudes[0], "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_number_is(&bell.amplitudes[3], "1/2*sqrt2 + 0 i", &error)
                        && qasm_number_is_zero(&bell.amplitudes[1]) && qasm_number_is_zero(&bell.amplitudes[2]),
                    "exact: Bell |00> = |11> = 1/2*sqrt2 + 0 i, |01> = |10> = 0");
    qasm_test_check(tally,
                    bell_built && (qasm_dense_norm(&bell, &norm, &error) == 0L)
                        && qasm_number_equal(&norm, &qasm_number_one),
                    "exact: Bell <psi|psi> is exactly 1");

    // GHZ3: H0, CNOT 0 -> 1, CNOT 0 -> 2
    QasmDense ghz = {0u, NULL};
    const QasmGate cnot_zero_two = {QASM_GATE_CNOT, 0u, 2u, NULL};
    const int ghz_built = (qasm_dense_alloc(&ghz, 3u, &error) == 0L)
                       && (qasm_dense_apply(&ghz, &hadamard_zero, &error) == 0L)
                       && (qasm_dense_apply(&ghz, &cnot_zero_one, &error) == 0L)
                       && (qasm_dense_apply(&ghz, &cnot_zero_two, &error) == 0L);
    int ghz_rest_zero = ghz_built;
    for (unsigned int index = 1u; (ghz_rest_zero != 0) && (index < 7u); index += 1u)
    {
        ghz_rest_zero = qasm_number_is_zero(&ghz.amplitudes[index]);
    }
    qasm_test_check(tally,
                    ghz_rest_zero && qasm_test_number_is(&ghz.amplitudes[0], "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_number_is(&ghz.amplitudes[7], "1/2*sqrt2 + 0 i", &error)
                        && (qasm_dense_norm(&ghz, &norm, &error) == 0L) && qasm_number_equal(&norm, &qasm_number_one),
                    "exact: GHZ3 |000> = |111> = 1/2*sqrt2 + 0 i, the rest 0, <psi|psi> exactly 1");

    // Bell, then the controlled-T: an exact e^{i pi/4} phase on |11>
    QasmDense phased = {0u, NULL};
    const QasmGate controlled_t = {QASM_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn};
    const int phased_built = (qasm_dense_alloc(&phased, 2u, &error) == 0L)
                          && (qasm_dense_apply(&phased, &hadamard_zero, &error) == 0L)
                          && (qasm_dense_apply(&phased, &cnot_zero_one, &error) == 0L)
                          && (qasm_dense_apply(&phased, &controlled_t, &error) == 0L);
    qasm_test_check(tally,
                    phased_built && qasm_test_number_is(&phased.amplitudes[0], "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_number_is(&phased.amplitudes[3], "1/2 + 1/2 i", &error)
                        && (qasm_dense_norm(&phased, &norm, &error) == 0L)
                        && qasm_number_equal(&norm, &qasm_number_one),
                    "exact: Bell + controlled-T, |11> = 1/2 + 1/2 i, <psi|psi> exactly 1");

    // reversibility: a unitary run, then its exact inverse, back to |000>
    QasmDense round_trip = {0u, NULL};
    QasmDense ground = {0u, NULL};
    const QasmGate cnot_one_two = {QASM_GATE_CNOT, 1u, 2u, NULL};
    const QasmGate hadamard_two = {QASM_GATE_H, 2u, 0u, NULL};
    const QasmGate controlled_t_back = {QASM_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn_back};
    const QasmGate forward[5] = {hadamard_zero, cnot_zero_one, controlled_t, cnot_one_two, hadamard_two};
    const QasmGate inverse[5] = {hadamard_two, cnot_one_two, controlled_t_back, cnot_zero_one, hadamard_zero};
    int turned = (qasm_dense_alloc(&round_trip, 3u, &error) == 0L) && (qasm_dense_alloc(&ground, 3u, &error) == 0L);
    for (unsigned int gate = 0u; (turned != 0) && (gate < 5u); gate += 1u)
    {
        turned = (qasm_dense_apply(&round_trip, &forward[gate], &error) == 0L);
    }
    const int moved = turned && !qasm_dense_equal(&round_trip, &ground);
    for (unsigned int gate = 0u; (turned != 0) && (gate < 5u); gate += 1u)
    {
        turned = (qasm_dense_apply(&round_trip, &inverse[gate], &error) == 0L);
    }
    qasm_test_check(tally, moved && turned && qasm_dense_equal(&round_trip, &ground),
                    "exact: five gates, then their exact inverse, return |000> to the bit");

    // the seal: the same state seals the same, and one rational moved by 1/10^9 changes it
    unsigned char clean[ENGINE_SIGNUM_BYTES];
    unsigned char again[ENGINE_SIGNUM_BYTES];
    unsigned char tampered[ENGINE_SIGNUM_BYTES];
    QasmRational nudge;
    const int sealed = bell_built && (qasm_dense_seal(&bell, clean, &error) == 0L)
                    && (qasm_dense_seal(&bell, again, &error) == 0L)
                    && (qasm_rational_set(&nudge, 1LL, 1000000000LL, &error) == 0L)
                    && (qasm_rational_add(&bell.amplitudes[0].real.rational, &nudge,
                                          &bell.amplitudes[0].real.rational, &error)
                        == 0L)
                    && (qasm_dense_seal(&bell, tampered, &error) == 0L);
    qasm_test_check(tally,
                    sealed && (memcmp(clean, again, sizeof(clean)) == 0)
                        && (memcmp(clean, tampered, sizeof(clean)) != 0),
                    "exact: the seal repeats, and one rational moved by 1/10^9 changes it");

    // refusals: a qubit past the state, and a division by zero
    EngineError refused;
    memset(&refused, 0, sizeof(refused));
    const QasmGate past = {QASM_GATE_H, 2u, 0u, NULL};
    qasm_test_check(tally, qasm_test_refused_here(qasm_dense_apply(&phased, &past, &refused), &refused),
                    "exact: a gate on a qubit past the state refuses, a request error from qasm");
    memset(&refused, 0, sizeof(refused));
    QasmRational quotient;
    const QasmRational zero_rational = QASM_RATIONAL_ZERO_INITIALIZER;
    qasm_test_check(tally,
                    qasm_test_refused_here(qasm_rational_divide(&nudge, &zero_rational, &quotient, &refused),
                                           &refused),
                    "exact: a division by zero refuses, a request error from qasm");
    qasm_test_check(tally, qasm_test_clean(&error), "exact: no error was raised on the paths that held");
    qasm_dense_release(&bell);
    qasm_dense_release(&ghz);
    qasm_dense_release(&phased);
    qasm_dense_release(&round_trip);
    qasm_dense_release(&ground);
    printf("  exact qubits: %llu us\n", engine_clock_microseconds() - start);
}

typedef long (*QasmTestBuild)(const QasmTestTarget *target, unsigned int sites, EngineError *error);

// compact against dense on six qubits, all 64 amplitudes
static int qasm_test_cross(QasmTestBuild build, EngineError *error)
{
    QasmChain chain = {NULL, 0u, NULL};
    QasmDense dense = {0u, NULL};
    const QasmTestTarget on_chain = {&chain, NULL};
    const QasmTestTarget on_dense = {NULL, &dense};
    int agree = (qasm_chain_alloc(&chain, &qasm_number_field, 6u, error) == 0L)
             && (qasm_dense_alloc(&dense, 6u, error) == 0L) && (build(&on_chain, 6u, error) == 0L)
             && (build(&on_dense, 6u, error) == 0L);
    for (unsigned long long index = 0ull; (agree != 0) && (index < 64ull); index += 1ull)
    {
        unsigned char bits[6];
        QasmNumber amplitude = qasm_number_zero;
        qasm_test_bits(index, 6u, bits);
        agree = (qasm_chain_amplitude(&chain, bits, &amplitude, error) == 0L)
             && qasm_number_equal(&amplitude, &dense.amplitudes[index]);
    }
    qasm_chain_release(&chain);
    qasm_dense_release(&dense);
    return agree;
}

static void qasm_test_mps_qubits(QasmTally *tally)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();

    // Bell
    QasmChain bell = {NULL, 0u, NULL};
    const QasmTestTarget on_bell = {&bell, NULL};
    const unsigned int bell_bonds[1] = {2u};
    const int bell_built = (qasm_chain_alloc(&bell, &qasm_number_field, 2u, &error) == 0L)
                        && (qasm_test_ghz(&on_bell, 2u, &error) == 0L);
    qasm_test_check(tally,
                    bell_built && qasm_test_bonds_are(&bell, bell_bonds) && (qasm_chain_elements(&bell) == 8ull)
                        && qasm_test_norm_is_one(&bell, &error)
                        && qasm_test_amplitude_is(&bell, 0u, "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_amplitude_is(&bell, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: Bell, bond [2], 8 elements, <psi|psi> exactly 1, <00| = <11| = 1/2*sqrt2 + 0 i");

    // GHZ-6
    QasmChain ghz_six = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_six = {&ghz_six, NULL};
    const unsigned int ghz_six_bonds[5] = {2u, 2u, 2u, 2u, 2u};
    const int ghz_six_built = (qasm_chain_alloc(&ghz_six, &qasm_number_field, 6u, &error) == 0L)
                           && (qasm_test_ghz(&on_ghz_six, 6u, &error) == 0L);
    qasm_test_check(tally,
                    ghz_six_built && qasm_test_bonds_are(&ghz_six, ghz_six_bonds)
                        && (qasm_chain_elements(&ghz_six) == 40ull) && qasm_test_norm_is_one(&ghz_six, &error)
                        && qasm_test_amplitude_is(&ghz_six, 0u, "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_amplitude_is(&ghz_six, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: GHZ-6, bonds [2, 2, 2, 2, 2], 40 elements, <psi|psi> exactly 1");

    // GHZ-4, then a controlled-T on the last pair
    QasmChain ghz_t = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_t = {&ghz_t, NULL};
    const unsigned int ghz_t_bonds[3] = {2u, 2u, 2u};
    const int ghz_t_built = (qasm_chain_alloc(&ghz_t, &qasm_number_field, 4u, &error) == 0L)
                         && (qasm_test_ghz_t(&on_ghz_t, 4u, &error) == 0L);
    qasm_test_check(tally,
                    ghz_t_built && qasm_test_bonds_are(&ghz_t, ghz_t_bonds) && (qasm_chain_elements(&ghz_t) == 24ull)
                        && qasm_test_norm_is_one(&ghz_t, &error)
                        && qasm_test_amplitude_is(&ghz_t, 0u, "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_amplitude_is(&ghz_t, 1u, "1/2 + 1/2 i", &error),
                    "mps: GHZ-4 + controlled-T, bonds [2, 2, 2], 24 elements, <1111| = 1/2 + 1/2 i");

    // GHZ-100
    const unsigned long long hundred_start = engine_clock_microseconds();
    QasmChain ghz_hundred = {NULL, 0u, NULL};
    const QasmTestTarget on_ghz_hundred = {&ghz_hundred, NULL};
    const int hundred_built = (qasm_chain_alloc(&ghz_hundred, &qasm_number_field, 100u, &error) == 0L)
                           && (qasm_test_ghz(&on_ghz_hundred, 100u, &error) == 0L);
    unsigned int widest = 0u;
    for (unsigned int site = 0u; (hundred_built != 0) && ((site + 1u) < 100u); site += 1u)
    {
        const unsigned int bond = qasm_chain_bond(&ghz_hundred, site);
        widest = (bond > widest) ? bond : widest;
    }
    qasm_test_check(tally,
                    hundred_built && (widest == 2u) && (qasm_chain_elements(&ghz_hundred) == 792ull)
                        && qasm_test_norm_is_one(&ghz_hundred, &error)
                        && qasm_test_amplitude_is(&ghz_hundred, 0u, "1/2*sqrt2 + 0 i", &error)
                        && qasm_test_amplitude_is(&ghz_hundred, 1u, "1/2*sqrt2 + 0 i", &error),
                    "mps: GHZ-100, widest bond 2, 792 elements, <psi|psi> exactly 1, both ends 1/2*sqrt2 + 0 i");
    printf("  GHZ-100: %llu field elements, %llu us\n", qasm_chain_elements(&ghz_hundred),
           engine_clock_microseconds() - hundred_start);

    // the scrambler: 10 qubits, depth 6
    const unsigned long long scrambler_start = engine_clock_microseconds();
    QasmChain scrambled = {NULL, 0u, NULL};
    const QasmTestTarget on_scrambled = {&scrambled, NULL};
    const unsigned int scrambled_bonds[9] = {2u, 3u, 6u, 8u, 8u, 8u, 6u, 3u, 2u};
    const int scrambled_built = (qasm_chain_alloc(&scrambled, &qasm_number_field, 10u, &error) == 0L)
                             && (qasm_test_scrambler(&on_scrambled, 10u, 6u, &error) == 0L);
    qasm_test_check(tally,
                    scrambled_built && qasm_test_bonds_are(&scrambled, scrambled_bonds)
                        && (qasm_chain_elements(&scrambled) == 552ull) && qasm_test_norm_is_one(&scrambled, &error),
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
    int turned = (qasm_chain_alloc(&round_trip, &qasm_number_field, 5u, &error) == 0L)
              && (qasm_chain_alloc(&ground, &qasm_number_field, 5u, &error) == 0L)
              && (qasm_test_one(&on_round_trip, qasm_test_hadamard, 0u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 0u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 1u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_controlled_t, 2u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 3u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 3u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_controlled_t_back, 2u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 1u, &error) == 0L)
              && (qasm_test_two(&on_round_trip, qasm_test_cnot, 0u, &error) == 0L)
              && (qasm_test_one(&on_round_trip, qasm_test_hadamard, 0u, &error) == 0L);
    for (unsigned long long index = 0ull; (turned != 0) && (index < 32ull); index += 1ull)
    {
        unsigned char bits[5];
        QasmNumber returned = qasm_number_zero;
        QasmNumber expected = qasm_number_zero;
        qasm_test_bits(index, 5u, bits);
        turned = (qasm_chain_amplitude(&round_trip, bits, &returned, &error) == 0L)
              && (qasm_chain_amplitude(&ground, bits, &expected, &error) == 0L)
              && qasm_number_equal(&returned, &expected);
    }
    qasm_test_check(tally, turned, "mps: a five-qubit circuit, then its exact inverse, returns |00000> to the bit");

    // compact against dense
    qasm_test_check(tally, qasm_test_cross(qasm_test_ghz, &error),
                    "mps: cross-check GHZ chain, compact against dense on 6 qubits, all 64 amplitudes agree");
    qasm_test_check(tally, qasm_test_cross(qasm_test_ghz_t, &error),
                    "mps: cross-check GHZ + controlled-T, compact against dense on 6 qubits, all 64 agree");
    qasm_test_check(tally, qasm_test_cross(qasm_test_scrambler_six, &error),
                    "mps: cross-check scrambler depth 6, compact against dense on 6 qubits, all 64 agree");

    // the chain's seal repeats and tells GHZ-6 from GHZ-4 + controlled-T
    unsigned char six_root[ENGINE_SIGNUM_BYTES];
    unsigned char six_again[ENGINE_SIGNUM_BYTES];
    unsigned char t_root[ENGINE_SIGNUM_BYTES];
    const int sealed = ghz_six_built && ghz_t_built && (qasm_chain_seal(&ghz_six, six_root, &error) == 0L)
                    && (qasm_chain_seal(&ghz_six, six_again, &error) == 0L)
                    && (qasm_chain_seal(&ghz_t, t_root, &error) == 0L);
    qasm_test_check(tally,
                    sealed && (memcmp(six_root, six_again, sizeof(six_root)) == 0)
                        && (memcmp(six_root, t_root, sizeof(six_root)) != 0),
                    "mps: the chain's seal repeats, and two different states seal differently");

    EngineError refused;
    memset(&refused, 0, sizeof(refused));
    qasm_test_check(tally,
                    qasm_test_refused_here(qasm_chain_apply_two(&bell, qasm_test_cnot, 1u, &refused), &refused),
                    "mps: a two-site gate on the last site refuses, a request error from qasm");
    // the builder session's review found site + 1 wrapping here and reading past the tensors
    qasm_test_check(tally,
                    (qasm_chain_bond(&bell, 1u) == 0u) && (qasm_chain_bond(&bell, 0xFFFFFFFFu) == 0u),
                    "mps: the bond past the last cut is 0, the widest site index included");
    qasm_test_check(tally, qasm_test_clean(&error), "mps: no error was raised on the paths that held");
    qasm_chain_release(&bell);
    qasm_chain_release(&ghz_six);
    qasm_chain_release(&ghz_t);
    qasm_chain_release(&ghz_hundred);
    qasm_chain_release(&scrambled);
    qasm_chain_release(&round_trip);
    qasm_chain_release(&ground);
    printf("  mps qubits: %llu us\n", engine_clock_microseconds() - start);
}

// the symbolic gates and observables, as symbolic_qubits.py builds them over a field
typedef struct
{
    QasmRationalFunction hadamard[4];
    QasmRationalFunction cnot[16];
    QasmRationalFunction cphase[16];
    QasmRationalFunction identity[4];
    QasmRationalFunction pauli_x[4];
    QasmRationalFunction pauli_z[4];
    QasmRationalFunction local_phase[4];
    QasmRationalFunction omega;
} QasmTestSymbols;

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
        status = (status == 0L) ? qasm_test_symbol(&symbols->pauli_z[entry],
                                                   (entry == 0u) ? &qasm_number_one
                                                                 : ((entry == 3u) ? &qasm_number_minus_one
                                                                                  : &qasm_number_zero),
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

static void qasm_test_symbolic_qubits(QasmTally *tally)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();
    QasmTestSymbols symbols;
    memset(&symbols, 0, sizeof(symbols));
    const int symbols_built = (qasm_test_symbols(&symbols, &error) == 0L);
    qasm_test_check(tally, symbols_built, "symbolic: the gates and observables build over Q(sqrt2)[i](w)");

    // the delta-Bell state (|00> + w|11>)/sqrt2
    QasmChain bell = {NULL, 0u, NULL};
    const unsigned int bell_bonds[1] = {2u};
    const int bell_built = symbols_built
                        && (qasm_chain_alloc(&bell, &qasm_rational_function_field, 2u, &error) == 0L)
                        && (qasm_chain_apply_one(&bell, symbols.hadamard, 0u, &error) == 0L)
                        && (qasm_chain_apply_two(&bell, symbols.cnot, 0u, &error) == 0L)
                        && (qasm_chain_apply_two(&bell, symbols.cphase, 0u, &error) == 0L);
    QasmRationalFunction value;
    memset(&value, 0, sizeof(value));
    const unsigned char zeros[2] = {0u, 0u};
    const unsigned char ones[2] = {1u, 1u};
    qasm_test_check(tally,
                    bell_built && qasm_test_bonds_are(&bell, bell_bonds)
                        && (qasm_chain_amplitude(&bell, zeros, &value, &error) == 0L)
                        && qasm_test_function_is(&value, "1/2sqrt2", &error)
                        && (qasm_chain_amplitude(&bell, ones, &value, &error) == 0L)
                        && qasm_test_function_is(&value, "(1/2sqrt2)w", &error),
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
    qasm_test_check(tally,
                    norm_read && qasm_test_function_is(&norm, "1", &error)
                        && qasm_rational_function_equal(&norm, (const QasmRationalFunction *)qasm_rational_function_field.one),
                    "symbolic: <psi|psi> = 1 exactly, w cancels");
    const int lens_read = bell_built && (qasm_test_lens(&bell, both_x, &xx, &error) == 0L)
                       && (qasm_test_lens(&bell, both_z, &zz, &error) == 0L)
                       && (qasm_test_lens(&bell, first_x, &x0, &error) == 0L);
    qasm_test_check(tally, lens_read && qasm_test_function_is(&xx, "(1/2 + (1/2)w^2) / (w)", &error),
                    "symbolic: the boundary lens reads <X0 X1> = (1/2 + (1/2)w^2) / (w)");
    qasm_test_check(tally,
                    lens_read && qasm_test_function_is(&zz, "1", &error) && qasm_test_function_is(&x0, "0", &error),
                    "symbolic: <Z0 Z1> = 1 and <X0> = 0");

    // delta-GHZ3
    QasmChain ghz = {NULL, 0u, NULL};
    const unsigned int ghz_bonds[2] = {2u, 2u};
    QasmRationalFunction xxx;
    memset(&xxx, 0, sizeof(xxx));
    const int ghz_read = symbols_built && (qasm_chain_alloc(&ghz, &qasm_rational_function_field, 3u, &error) == 0L)
                      && (qasm_chain_apply_one(&ghz, symbols.hadamard, 0u, &error) == 0L)
                      && (qasm_chain_apply_two(&ghz, symbols.cnot, 0u, &error) == 0L)
                      && (qasm_chain_apply_two(&ghz, symbols.cnot, 1u, &error) == 0L)
                      && (qasm_chain_apply_two(&ghz, symbols.cphase, 1u, &error) == 0L)
                      && (qasm_test_lens(&ghz, both_x, &xxx, &error) == 0L);
    qasm_test_check(tally,
                    ghz_read && qasm_test_bonds_are(&ghz, ghz_bonds)
                        && qasm_test_function_is(&xxx, "(1/2 + (1/2)w^2) / (w)", &error),
                    "symbolic: delta-GHZ3, bonds [2, 2], <X0 X1 X2> = (1/2 + (1/2)w^2) / (w)");

    // a single-qubit phase couples nothing: the product stays rank 1
    QasmChain product = {NULL, 0u, NULL};
    const unsigned int product_bonds[2] = {1u, 1u};
    int product_built = symbols_built
                     && (qasm_chain_alloc(&product, &qasm_rational_function_field, 3u, &error) == 0L);
    for (unsigned int site = 0u; (product_built != 0) && (site < 3u); site += 1u)
    {
        product_built = (qasm_chain_apply_one(&product, symbols.hadamard, site, &error) == 0L);
    }
    product_built = product_built && (qasm_chain_apply_one(&product, symbols.local_phase, 0u, &error) == 0L);
    qasm_test_check(tally, product_built && qasm_test_bonds_are(&product, product_bonds),
                    "symbolic: |+++> with a phase on wire 0 keeps bonds [1, 1]");

    // host against host: w = e^{i pi/4} specialises the symbolic reading to the controlled-T one
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
    const int crossed = lens_read && norm_read
                     && (qasm_rational_function_evaluate(&xx, &qasm_number_eighth_turn, &symbolic_xx, &error) == 0L)
                     && (qasm_rational_function_evaluate(&norm, &qasm_number_eighth_turn, &symbolic_norm, &error)
                         == 0L)
                     && (qasm_chain_alloc(&numeric, &qasm_number_field, 2u, &error) == 0L)
                     && (qasm_chain_apply_one(&numeric, qasm_test_hadamard, 0u, &error) == 0L)
                     && (qasm_chain_apply_two(&numeric, qasm_test_cnot, 0u, &error) == 0L)
                     && (qasm_chain_apply_two(&numeric, qasm_test_controlled_t, 0u, &error) == 0L)
                     && (qasm_chain_expectation(&numeric, both_numeric_x, &numeric_xx, &error) == 0L);
    qasm_test_check(tally,
                    crossed && qasm_number_equal(&symbolic_xx, &numeric_xx)
                        && qasm_test_short_is(&symbolic_xx, "1/2sqrt2", &error),
                    "symbolic: <X0 X1> at w = e^{i pi/4} equals the controlled-T reading, 1/2sqrt2");
    qasm_test_check(tally, crossed && qasm_number_equal(&symbolic_norm, &qasm_number_one),
                    "symbolic: the norm at w = e^{i pi/4} is exactly 1");

    // The builder session's review found the evaluation forming one power past the highest. w^(bits - 1) at w = 2 is
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
    // the width's bits are a power of two far below 2^31, so bits - 1 is held whole in an int
    const int widest_power = (int)(ANCHOR_EXACT_BITS - 1ull);
    const int widest_read = (qasm_rational_set(&two.real.rational, 2LL, 1LL, &error) == 0L)
                         && (qasm_rational_function_set(&widest, &qasm_number_one, widest_power, &error) == 0L)
                         && (qasm_rational_function_evaluate(&widest, &two, &evaluated, &error) == 0L);
    qasm_test_check(tally,
                    widest_read && anchor_exact_equal(&evaluated.real.rational.numerator, &top_bit)
                        && anchor_exact_equal(&evaluated.real.rational.denominator, &unit)
                        && qasm_rational_is_zero(&evaluated.real.sqrt2)
                        && qasm_rational_is_zero(&evaluated.imaginary.rational)
                        && qasm_rational_is_zero(&evaluated.imaginary.sqrt2),
                    "symbolic: w^(bits - 1) at w = 2 evaluates to 2^(bits - 1), the widest power the width holds");
    qasm_rational_function_release(&widest);

    EngineError refused;
    memset(&refused, 0, sizeof(refused));
    QasmRationalFunction zero_function;
    QasmRationalFunction inverse;
    memset(&zero_function, 0, sizeof(zero_function));
    memset(&inverse, 0, sizeof(inverse));
    const int zero_set = (qasm_rational_function_set(&zero_function, &qasm_number_zero, 0, &error) == 0L);
    qasm_test_check(tally,
                    zero_set
                        && qasm_test_refused_here(qasm_rational_function_invert(&zero_function, &inverse, &refused),
                                                  &refused),
                    "symbolic: inverting zero refuses, a request error from qasm");
    qasm_test_check(tally, qasm_test_clean(&error), "symbolic: no error was raised on the paths that held");
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

static void qasm_test_boundary_lens(QasmTally *tally)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long start = engine_clock_microseconds();
    // lens_counts: every round from 16 to 30 read 126, 130, 0, 30, 14, 64, 64, True, True
    int every = 1;
    for (unsigned int rounds = 16u; rounds <= 30u; rounds += 1u)
    {
        const QasmLensRequest request = {13u, 13u, 8u, 6u, 2024ull, 0ull, rounds};
        QasmLensReading reading;
        memset(&reading, 0, sizeof(reading));
        const int read = (qasm_lens_read(&request, &reading, &error) == 0L);
        const int held = read && (reading.raw_rank == 126u) && (reading.complement == 130u)
                      && (reading.lift_extra_rank == 0u) && (reading.forward_vanish == 30u)
                      && (reading.backward_vanish == 14u) && (reading.forward_fiber == 64ull)
                      && (reading.backward_fiber == 64ull) && (reading.reversible != 0) && (reading.root_stable != 0);
        if (held == 0)
        {
            printf("  round %u: rank %u, complement %u, lift %u, vanish %u and %u, fibers %llu and %llu, clock %d, "
                   "root %d\n",
                   rounds, reading.raw_rank, reading.complement, reading.lift_extra_rank, reading.forward_vanish,
                   reading.backward_vanish, reading.forward_fiber, reading.backward_fiber, reading.reversible,
                   reading.root_stable);
        }
        every = every && held;
    }
    qasm_test_check(tally, every,
                    "lens: rounds 16 to 30 each read rank 126, complement 130, lift 0, vanish 30 and 14 of 400, "
                    "fibers 64 and 64, the clock closed and the root stable, as the Python did");
    unsigned char clean[ENGINE_SIGNUM_BYTES];
    unsigned char flipped[ENGINE_SIGNUM_BYTES];
    const QasmLensRequest seal_request = {13u, 13u, 8u, 6u, 2024ull, 0ull, 30u};
    qasm_test_check(tally,
                    (qasm_lens_seal_check(&seal_request, clean, flipped, &error) == 0L)
                        && (memcmp(clean, flipped, sizeof(clean)) != 0),
                    "lens: one flipped generator bit changes the seal");
    EngineError refused;
    memset(&refused, 0, sizeof(refused));
    QasmLensReading reading;
    const QasmLensRequest too_wide = {13u, 13u, 8u, QASM_LENS_BITS_MOST + 1u, 2024ull, 0ull, 30u};
    qasm_test_check(tally, qasm_test_refused_here(qasm_lens_read(&too_wide, &reading, &refused), &refused),
                    "lens: an aperture past the widest refuses, a request error from qasm");
    qasm_test_check(tally, qasm_test_clean(&error), "lens: no error was raised on the paths that held");
    printf("  boundary lens: %llu us\n", engine_clock_microseconds() - start);
}

int main(void)
{
    QasmTally tally = {0u, 0u};
    qasm_test_gates();
    qasm_test_exact_qubits(&tally);
    qasm_test_mps_qubits(&tally);
    qasm_test_symbolic_qubits(&tally);
    qasm_test_boundary_lens(&tally);
    printf("  qasm test: %u checks, %u failed\n", tally.checks, tally.failed);
    return (tally.failed == 0u) ? 0 : 1;
}
