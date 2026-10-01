// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_exact_test_gates.cu: numbers, functions, gates, GHZ, scramblers, bonds, amplitudes
#include "../../../../engine/quantum/qasm/qasm_exact_test_internal.h"

void qasm_test_check(QasmResults *results, int passed, const char *claim)
{
    results->checks += 1u;
    if (passed == 0)
    {
        results->failed += 1u;
        printf("  FAIL %s\n", claim);
    }
}

static char qasm_test_text[QASM_NUMBER_TEXT_CAPACITY];

// f_str's text of a number, without the float the Python printed beside it
static int qasm_test_number_is(const QasmNumber *value, const char *expected, EngineError *error)
{
    return (qasm_number_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L) &&
           (strcmp(qasm_test_text, expected) == 0);
}

int qasm_test_short_is(const QasmNumber *value, const char *expected, EngineError *error)
{
    return (qasm_number_short_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L) &&
           (strcmp(qasm_test_text, expected) == 0);
}

int qasm_test_function_is(const QasmRationalFunction *value, const char *expected, EngineError *error)
{
    return (qasm_rational_function_text(value, qasm_test_text, sizeof(qasm_test_text), error) == 0L) &&
           (strcmp(qasm_test_text, expected) == 0);
}

int qasm_test_clean(const EngineError *error)
{
    return error->kind == ENGINE_ERROR_NONE;
}

int qasm_test_error_here(long status, const EngineError *error)
{
    return (status == QASM_ERROR) && (error->kind == ENGINE_ERROR_REQUEST) && (error->module == ENGINE_MODULE_QASM);
}

// the gates, as mps_qubits.py builds them: [out][in], and [2 t0 + t1][2 s0 + s1]
QasmNumber qasm_test_hadamard[4];
QasmNumber qasm_test_cnot[16];
QasmNumber qasm_test_controlled_t[16];
QasmNumber qasm_test_controlled_t_back[16];

void qasm_test_gates(void)
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

long qasm_test_one(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error)
{
    if (target->chain != NULL)
    {
        return qasm_chain_apply_one(target->chain, gate, site, error);
    }
    const QasmExactGate apply = {QASM_EXACT_GATE_ONE_QUBIT, site, 0u, gate};
    return qasm_dense_apply(target->dense, &apply, error);
}

long qasm_test_two(const QasmTestTarget *target, const QasmNumber *gate, unsigned int site, EngineError *error)
{
    if (target->chain != NULL)
    {
        return qasm_chain_apply_two(target->chain, gate, site, error);
    }
    const QasmExactGate apply = {QASM_EXACT_GATE_TWO_QUBIT, site, 0u, gate};
    return qasm_dense_apply(target->dense, &apply, error);
}

// build_ghz: H on 0, then a cascade of adjacent CNOTs
long qasm_test_ghz(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    long status = qasm_test_one(target, qasm_test_hadamard, 0u, error);
    for (unsigned int site = 0u; (status == 0L) && ((site + 1u) < sites); site += 1u)
    {
        status = qasm_test_two(target, qasm_test_cnot, site, error);
    }
    return status;
}

// nc_build: the GHZ chain, then a controlled-T on sites 2 and 3
long qasm_test_ghz_t(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    const long status = qasm_test_ghz(target, sites, error);
    return (status == 0L) ? qasm_test_two(target, qasm_test_controlled_t, 2u, error) : status;
}

// build_scrambler: |+..+>, then bricks of controlled-T, H on every wire between bricks
long qasm_test_scrambler(const QasmTestTarget *target, unsigned int sites, unsigned int depth, EngineError *error)
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

long qasm_test_scrambler_six(const QasmTestTarget *target, unsigned int sites, EngineError *error)
{
    return qasm_test_scrambler(target, sites, 6u, error);
}

int qasm_test_bonds_are(const QasmChain *chain, const unsigned int *bonds)
{
    int equal = 1;
    for (unsigned int site = 0u; (equal != 0) && ((site + 1u) < chain->sites); site += 1u)
    {
        equal = (qasm_chain_bond(chain, site) == bonds[site]);
    }
    return equal;
}

void qasm_test_bits(unsigned long long index, unsigned int sites, unsigned char *bits)
{
    for (unsigned int site = 0u; site < sites; site += 1u)
    {
        // one bit of the index, 0 or 1
        bits[site] = (unsigned char)((index >> site) & 1ull);
    }
}

int qasm_test_amplitude_is(const QasmChain *chain, unsigned int value, const char *expected, EngineError *error)
{
    unsigned char bits[128];
    QasmNumber amplitude = qasm_number_zero;
    for (unsigned int site = 0u; site < chain->sites; site += 1u)
    {
        // the value is 0 or 1, which an unsigned char holds exactly
        bits[site] = (unsigned char)value;
    }
    return (qasm_chain_amplitude(chain, bits, &amplitude, error) == 0L) &&
           qasm_test_number_is(&amplitude, expected, error);
}

int qasm_test_norm_is_one(const QasmChain *chain, EngineError *error)
{
    QasmNumber norm = qasm_number_zero;
    return (qasm_chain_norm(chain, &norm, error) == 0L) && qasm_number_equal(&norm, &qasm_number_one);
}

void qasm_test_exact_qubits(QasmResults *results)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    QasmNumber norm = qasm_number_zero;
    const unsigned long long start = engine_clock_microseconds();

    // Bell: H0, CNOT 0 -> 1
    QasmDense bell = {0u, NULL};
    const QasmExactGate hadamard_zero = {QASM_EXACT_GATE_H, 0u, 0u, NULL};
    const QasmExactGate cnot_zero_one = {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL};
    const int bell_built = (qasm_dense_alloc(&bell, 2u, &error) == 0L) &&
                           (qasm_dense_apply(&bell, &hadamard_zero, &error) == 0L) &&
                           (qasm_dense_apply(&bell, &cnot_zero_one, &error) == 0L);
    qasm_test_check(results, bell_built, "exact: the Bell pair builds");
    qasm_test_check(results,
                    bell_built && qasm_test_number_is(&bell.amplitudes[0], "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_number_is(&bell.amplitudes[3], "1/2*sqrt2 + 0 i", &error) &&
                        qasm_number_is_zero(&bell.amplitudes[1]) && qasm_number_is_zero(&bell.amplitudes[2]),
                    "exact: Bell |00> = |11> = 1/2*sqrt2 + 0 i, |01> = |10> = 0");
    qasm_test_check(results,
                    bell_built && (qasm_dense_norm(&bell, &norm, &error) == 0L) &&
                        qasm_number_equal(&norm, &qasm_number_one),
                    "exact: Bell <psi|psi> is exactly 1");

    // GHZ3: H0, CNOT 0 -> 1, CNOT 0 -> 2
    QasmDense ghz = {0u, NULL};
    const QasmExactGate cnot_zero_two = {QASM_EXACT_GATE_CNOT, 0u, 2u, NULL};
    const int ghz_built = (qasm_dense_alloc(&ghz, 3u, &error) == 0L) &&
                          (qasm_dense_apply(&ghz, &hadamard_zero, &error) == 0L) &&
                          (qasm_dense_apply(&ghz, &cnot_zero_one, &error) == 0L) &&
                          (qasm_dense_apply(&ghz, &cnot_zero_two, &error) == 0L);
    int ghz_rest_zero = ghz_built;
    for (unsigned int index = 1u; (ghz_rest_zero != 0) && (index < 7u); index += 1u)
    {
        ghz_rest_zero = qasm_number_is_zero(&ghz.amplitudes[index]);
    }
    qasm_test_check(results,
                    ghz_rest_zero && qasm_test_number_is(&ghz.amplitudes[0], "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_number_is(&ghz.amplitudes[7], "1/2*sqrt2 + 0 i", &error) &&
                        (qasm_dense_norm(&ghz, &norm, &error) == 0L) && qasm_number_equal(&norm, &qasm_number_one),
                    "exact: GHZ3 |000> = |111> = 1/2*sqrt2 + 0 i, the rest 0, <psi|psi> exactly 1");

    // Bell, then the controlled-T: an exact e^{i pi/4} phase on |11>
    QasmDense phased = {0u, NULL};
    const QasmExactGate controlled_t = {QASM_EXACT_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn};
    const int phased_built = (qasm_dense_alloc(&phased, 2u, &error) == 0L) &&
                             (qasm_dense_apply(&phased, &hadamard_zero, &error) == 0L) &&
                             (qasm_dense_apply(&phased, &cnot_zero_one, &error) == 0L) &&
                             (qasm_dense_apply(&phased, &controlled_t, &error) == 0L);
    qasm_test_check(results,
                    phased_built && qasm_test_number_is(&phased.amplitudes[0], "1/2*sqrt2 + 0 i", &error) &&
                        qasm_test_number_is(&phased.amplitudes[3], "1/2 + 1/2 i", &error) &&
                        (qasm_dense_norm(&phased, &norm, &error) == 0L) && qasm_number_equal(&norm, &qasm_number_one),
                    "exact: Bell + controlled-T, |11> = 1/2 + 1/2 i, <psi|psi> exactly 1");

    // reversibility: a unitary run, then its exact inverse, back to |000>
    QasmDense round_trip = {0u, NULL};
    QasmDense ground = {0u, NULL};
    const QasmExactGate cnot_one_two = {QASM_EXACT_GATE_CNOT, 1u, 2u, NULL};
    const QasmExactGate hadamard_two = {QASM_EXACT_GATE_H, 2u, 0u, NULL};
    const QasmExactGate controlled_t_back = {QASM_EXACT_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn_back};
    const QasmExactGate forward[5] = {hadamard_zero, cnot_zero_one, controlled_t, cnot_one_two, hadamard_two};
    const QasmExactGate inverse[5] = {hadamard_two, cnot_one_two, controlled_t_back, cnot_zero_one, hadamard_zero};
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
    qasm_test_check(results, moved && turned && qasm_dense_equal(&round_trip, &ground),
                    "exact: five gates, then their exact inverse, return |000> to the bit");

    // the seal: the same state seals the same, and one rational moved by 1/10^9 changes it
    unsigned char clean[ENGINE_SIGNUM_BYTES];
    unsigned char again[ENGINE_SIGNUM_BYTES];
    unsigned char tampered[ENGINE_SIGNUM_BYTES];
    QasmRational nudge;
    const int sealed =
        bell_built && (qasm_dense_seal(&bell, clean, &error) == 0L) && (qasm_dense_seal(&bell, again, &error) == 0L) &&
        (qasm_rational_set(&nudge, 1LL, 1000000000LL, &error) == 0L) &&
        (qasm_rational_add(&bell.amplitudes[0].real.rational, &nudge, &bell.amplitudes[0].real.rational, &error) ==
         0L) &&
        (qasm_dense_seal(&bell, tampered, &error) == 0L);
    qasm_test_check(
        results, sealed && (memcmp(clean, again, sizeof(clean)) == 0) && (memcmp(clean, tampered, sizeof(clean)) != 0),
        "exact: the seal repeats, and one rational moved by 1/10^9 changes it");

    // errors: a qubit past the state, and a division by zero
    EngineError engine_error;
    memset(&engine_error, 0, sizeof(engine_error));
    const QasmExactGate over_limit = {QASM_EXACT_GATE_H, 2u, 0u, NULL};
    qasm_test_check(results, qasm_test_error_here(qasm_dense_apply(&phased, &over_limit, &engine_error), &engine_error),
                    "exact: a gate on a qubit past the state errors, a request error from qasm");
    memset(&engine_error, 0, sizeof(engine_error));
    QasmRational quotient;
    const QasmRational zero_rational = QASM_RATIONAL_ZERO_INITIALIZER;
    qasm_test_check(
        results,
        qasm_test_error_here(qasm_rational_divide(&nudge, &zero_rational, &quotient, &engine_error), &engine_error),
        "exact: a division by zero errors, a request error from qasm");
    qasm_test_check(results, qasm_test_clean(&error), "exact: no error was raised on the paths that held");
    qasm_dense_release(&bell);
    qasm_dense_release(&ghz);
    qasm_dense_release(&phased);
    qasm_dense_release(&round_trip);
    qasm_dense_release(&ground);
    printf("  exact qubits: %llu us\n", engine_clock_microseconds() - start);
}

// compact against dense on six qubits, all 64 amplitudes
int qasm_test_cross(QasmTestBuild build, EngineError *error)
{
    QasmChain chain = {NULL, 0u, NULL};
    QasmDense dense = {0u, NULL};
    const QasmTestTarget on_chain = {&chain, NULL};
    const QasmTestTarget on_dense = {NULL, &dense};
    int agree = (qasm_chain_alloc(&chain, &qasm_number_field, 6u, error) == 0L) &&
                (qasm_dense_alloc(&dense, 6u, error) == 0L) && (build(&on_chain, 6u, error) == 0L) &&
                (build(&on_dense, 6u, error) == 0L);
    for (unsigned long long index = 0ull; (agree != 0) && (index < 64ull); index += 1ull)
    {
        unsigned char bits[6];
        QasmNumber amplitude = qasm_number_zero;
        qasm_test_bits(index, 6u, bits);
        agree = (qasm_chain_amplitude(&chain, bits, &amplitude, error) == 0L) &&
                qasm_number_equal(&amplitude, &dense.amplitudes[index]);
    }
    qasm_chain_release(&chain);
    qasm_dense_release(&dense);
    return agree;
}
