// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The self run against the dense port: every circuit's lanes on the host, from each basis state and from general
// states, each lane equal to the dense port's run from the same start amplitude for amplitude; then the same programs
// on the device inside one tessera job, their records equal to the host's word for word; then the refusals.
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
    else
    {
        printf("  ok   %s\n", claim);
    }
}

static int qasm_test_refused_here(long status, const EngineError *error)
{
    return (status == QASM_REFUSED) && (error->kind == ENGINE_ERROR_REQUEST) && (error->module == ENGINE_MODULE_QASM);
}

// the matrix gates: [out][in], and [2 t0 + t1][2 s0 + s1]
static QasmNumber qasm_test_hadamard[4];
static QasmNumber qasm_test_rotation[4];
static QasmNumber qasm_test_cnot[16];
static QasmNumber qasm_test_controlled_t[16];

static int qasm_test_gates(EngineError *error)
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
    }
    // 00 -> 00, 01 -> 01, 11 -> 10, 10 -> 11: the control is the left qubit
    qasm_test_cnot[0] = qasm_number_one;
    qasm_test_cnot[5] = qasm_number_one;
    qasm_test_cnot[11] = qasm_number_one;
    qasm_test_cnot[14] = qasm_number_one;
    for (unsigned int diagonal = 0u; diagonal < 3u; diagonal += 1u)
    {
        qasm_test_controlled_t[5u * diagonal] = qasm_number_one;
    }
    qasm_test_controlled_t[15] = qasm_number_eighth_turn;
    // [[3/5, 4/5], [4/5, -3/5]]: a real rotation and reflection whose entries are rationals, not powers of sqrt2
    for (unsigned int entry = 0u; entry < 4u; entry += 1u)
    {
        qasm_test_rotation[entry] = qasm_number_zero;
    }
    return (qasm_rational_set(&qasm_test_rotation[0].real.rational, 3LL, 5LL, error) == 0L)
        && (qasm_rational_set(&qasm_test_rotation[1].real.rational, 4LL, 5LL, error) == 0L)
        && (qasm_rational_set(&qasm_test_rotation[2].real.rational, 4LL, 5LL, error) == 0L)
        && (qasm_rational_set(&qasm_test_rotation[3].real.rational, -3LL, 5LL, error) == 0L);
}

typedef struct
{
    const char *name;
    unsigned int qubits;
    const QasmExactGate *gates;
    unsigned int gate_count;
} QasmTestCircuit;

static const QasmExactGate qasm_test_bell[] = {{QASM_EXACT_GATE_H, 0u, 0u, NULL}, {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL}};

static const QasmExactGate qasm_test_ghz3[] = {
    {QASM_EXACT_GATE_H, 0u, 0u, NULL}, {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL}, {QASM_EXACT_GATE_CNOT, 0u, 2u, NULL}};

static const QasmExactGate qasm_test_phased[] = {{QASM_EXACT_GATE_H, 0u, 0u, NULL},
                                                 {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL},
                                                 {QASM_EXACT_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn}};

static const QasmExactGate qasm_test_five[] = {{QASM_EXACT_GATE_H, 0u, 0u, NULL},
                                               {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL},
                                               {QASM_EXACT_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn},
                                               {QASM_EXACT_GATE_CNOT, 1u, 2u, NULL},
                                               {QASM_EXACT_GATE_H, 2u, 0u, NULL}};

static const QasmExactGate qasm_test_paulis[] = {
    {QASM_EXACT_GATE_H, 0u, 0u, NULL}, {QASM_EXACT_GATE_H, 1u, 0u, NULL},  {QASM_EXACT_GATE_Y, 0u, 0u, NULL},
    {QASM_EXACT_GATE_Z, 1u, 0u, NULL}, {QASM_EXACT_GATE_S, 0u, 0u, NULL},  {QASM_EXACT_GATE_CZ, 0u, 1u, NULL},
    {QASM_EXACT_GATE_S, 1u, 0u, NULL}, {QASM_EXACT_GATE_X, 0u, 0u, NULL}};

static const QasmExactGate qasm_test_rational[] = {{QASM_EXACT_GATE_ONE_QUBIT, 1u, 0u, qasm_test_rotation},
                                                   {QASM_EXACT_GATE_H, 0u, 0u, NULL},
                                                   {QASM_EXACT_GATE_ONE_QUBIT, 0u, 0u, qasm_test_rotation},
                                                   {QASM_EXACT_GATE_CNOT, 1u, 0u, NULL}};

static const QasmExactGate qasm_test_matrices[] = {{QASM_EXACT_GATE_ONE_QUBIT, 0u, 0u, qasm_test_hadamard},
                                                   {QASM_EXACT_GATE_TWO_QUBIT, 0u, 0u, qasm_test_cnot},
                                                   {QASM_EXACT_GATE_TWO_QUBIT, 1u, 0u, qasm_test_controlled_t},
                                                   {QASM_EXACT_GATE_X, 2u, 0u, NULL}};

// |+...+>, a brick of controlled-T, H on every wire, the other brick, H on every wire
static const QasmExactGate qasm_test_scrambler[] = {
    {QASM_EXACT_GATE_H, 0u, 0u, NULL},
    {QASM_EXACT_GATE_H, 1u, 0u, NULL},
    {QASM_EXACT_GATE_H, 2u, 0u, NULL},
    {QASM_EXACT_GATE_H, 3u, 0u, NULL},
    {QASM_EXACT_GATE_CONTROLLED_PHASE, 0u, 1u, &qasm_number_eighth_turn},
    {QASM_EXACT_GATE_CONTROLLED_PHASE, 2u, 3u, &qasm_number_eighth_turn},
    {QASM_EXACT_GATE_H, 0u, 0u, NULL},
    {QASM_EXACT_GATE_H, 1u, 0u, NULL},
    {QASM_EXACT_GATE_H, 2u, 0u, NULL},
    {QASM_EXACT_GATE_H, 3u, 0u, NULL},
    {QASM_EXACT_GATE_CONTROLLED_PHASE, 1u, 2u, &qasm_number_eighth_turn},
    {QASM_EXACT_GATE_H, 0u, 0u, NULL},
    {QASM_EXACT_GATE_H, 1u, 0u, NULL},
    {QASM_EXACT_GATE_H, 2u, 0u, NULL},
    {QASM_EXACT_GATE_H, 3u, 0u, NULL}};

static const QasmExactGate qasm_test_ghz5[] = {{QASM_EXACT_GATE_H, 0u, 0u, NULL},
                                               {QASM_EXACT_GATE_CNOT, 0u, 1u, NULL},
                                               {QASM_EXACT_GATE_CNOT, 1u, 2u, NULL},
                                               {QASM_EXACT_GATE_CNOT, 2u, 3u, NULL},
                                               {QASM_EXACT_GATE_CNOT, 3u, 4u, NULL},
                                               {QASM_EXACT_GATE_CONTROLLED_PHASE, 3u, 4u, &qasm_number_eighth_turn},
                                               {QASM_EXACT_GATE_H, 4u, 0u, NULL}};

// a circuit's gate count is a handful, held by an unsigned int
#define QASM_TEST_GATES(gates_) (unsigned int)(sizeof(gates_) / sizeof((gates_)[0]))

static const QasmTestCircuit qasm_test_circuits[] = {
    {"Bell", 2u, qasm_test_bell, QASM_TEST_GATES(qasm_test_bell)},
    {"GHZ3", 3u, qasm_test_ghz3, QASM_TEST_GATES(qasm_test_ghz3)},
    {"Bell + controlled-T", 2u, qasm_test_phased, QASM_TEST_GATES(qasm_test_phased)},
    {"five gates", 3u, qasm_test_five, QASM_TEST_GATES(qasm_test_five)},
    {"Y, Z, S, CZ, X", 2u, qasm_test_paulis, QASM_TEST_GATES(qasm_test_paulis)},
    {"rational rotation", 2u, qasm_test_rational, QASM_TEST_GATES(qasm_test_rational)},
    {"matrix gates", 3u, qasm_test_matrices, QASM_TEST_GATES(qasm_test_matrices)},
    {"scrambler", 4u, qasm_test_scrambler, QASM_TEST_GATES(qasm_test_scrambler)},
    {"GHZ5 + controlled-T", 5u, qasm_test_ghz5, QASM_TEST_GATES(qasm_test_ghz5)}};

#define QASM_TEST_CIRCUITS (sizeof(qasm_test_circuits) / sizeof(qasm_test_circuits[0]))

// the general states: lanes of signed rationals in every part over the common denominator 12, none of them a basis
// state
#define QASM_TEST_GENERAL_LANES 3u

static int qasm_test_general(unsigned int qubits, QasmNumber *inputs, EngineError *error)
{
    const unsigned int amplitudes = 1u << qubits;
    int built = 1;
    for (unsigned int lane = 0u; built && (lane < QASM_TEST_GENERAL_LANES); lane += 1u)
    {
        for (unsigned int amplitude = 0u; built && (amplitude < amplitudes); amplitude += 1u)
        {
            QasmNumber *const number = &inputs[(lane * amplitudes) + amplitude];
            // the lane and the amplitude are below 2^5, so each is held whole in a long long
            const long long k = (long long)lane;
            const long long t = (long long)amplitude;
            built = (qasm_rational_set(&number->real.rational, k + 1LL - t, 2LL, error) == 0L)
                 && (qasm_rational_set(&number->real.sqrt2, t - k, 3LL, error) == 0L)
                 && (qasm_rational_set(&number->imaginary.rational, (2LL * k) - t, 4LL, error) == 0L)
                 && (qasm_rational_set(&number->imaginary.sqrt2, -1LL - k, 6LL, error) == 0L);
        }
    }
    return built;
}

// every lane against the dense port run from the same start: the lane's input, or |lane> without inputs
static int qasm_test_matches_dense(const QasmTestCircuit *circuit, const QasmNumber *inputs, unsigned long long lanes,
                                   const QasmNumber *outputs, EngineError *error)
{
    const unsigned int amplitudes = 1u << circuit->qubits;
    QasmDense dense = {0u, NULL};
    int agree = (qasm_dense_alloc(&dense, circuit->qubits, error) == 0L);
    for (unsigned long long lane = 0ull; agree && (lane < lanes); lane += 1ull)
    {
        for (unsigned int amplitude = 0u; amplitude < amplitudes; amplitude += 1u)
        {
            const QasmNumber *const basis = (amplitude == lane) ? &qasm_number_one : &qasm_number_zero;
            dense.amplitudes[amplitude] = (inputs != NULL) ? inputs[(lane * amplitudes) + amplitude] : *basis;
        }
        for (unsigned int gate = 0u; agree && (gate < circuit->gate_count); gate += 1u)
        {
            agree = (qasm_dense_apply(&dense, &circuit->gates[gate], error) == 0L);
        }
        for (unsigned int amplitude = 0u; agree && (amplitude < amplitudes); amplitude += 1u)
        {
            agree = qasm_number_equal(&dense.amplitudes[amplitude], &outputs[(lane * amplitudes) + amplitude]);
        }
    }
    qasm_dense_release(&dense);
    return agree;
}

static int qasm_test_run(const QasmTestCircuit *circuit, const QasmNumber *inputs, unsigned long long lanes,
                         int on_host, QasmNumber *outputs, unsigned int *records, unsigned long long room,
                         QasmSelfReading *reading)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const QasmSelfRequest request = {circuit->qubits, circuit->gates, circuit->gate_count, inputs, lanes, on_host,
                                     outputs, records, room, &error};
    if (qasm_self_run(&request, reading) == QASM_REFUSED)
    {
        printf("  %s refused on the %s: error kind %d, module %d, site %u, status %d\n", circuit->name,
               (on_host != 0) ? "host" : "device", (int)error.kind, (int)error.module, error.site, error.status);
        return 0;
    }
    return 1;
}

// the host against the dense port; the widest run's device bytes, which the job declares
static unsigned long long qasm_test_host(QasmTally *tally)
{
    unsigned long long widest = 0ull;
    char claim[256];
    for (unsigned int which = 0u; which < QASM_TEST_CIRCUITS; which += 1u)
    {
        const QasmTestCircuit *const circuit = &qasm_test_circuits[which];
        const unsigned int amplitudes = 1u << circuit->qubits;
        EngineError error;
        memset(&error, 0, sizeof(error));
        // widening: at most 2^10 numbers
        QasmNumber *const outputs = (QasmNumber *)calloc((size_t)amplitudes * amplitudes, sizeof(QasmNumber));
        QasmNumber *const general = (QasmNumber *)calloc((size_t)QASM_TEST_GENERAL_LANES * amplitudes,
                                                         sizeof(QasmNumber));
        QasmSelfReading reading;
        memset(&reading, 0, sizeof(reading));
        const int basis = (outputs != NULL) && (general != NULL)
                       && qasm_test_run(circuit, NULL, amplitudes, 1, outputs, NULL, 0ull, &reading)
                       && qasm_test_matches_dense(circuit, NULL, amplitudes, outputs, &error);
        snprintf(claim, sizeof(claim),
                 "self: %s, %u qubits, %u gates: each of the %u basis lanes on the host equals the dense port",
                 circuit->name, circuit->qubits, circuit->gate_count, amplitudes);
        qasm_test_check(tally, basis, claim);
        if (basis)
        {
            printf("         %u steps, %u file limbs, %u in limbs, %u out limbs, %llu device bytes, %llu us\n",
                   reading.steps, reading.file_limbs, reading.in_limbs, reading.out_limbs, reading.device_bytes,
                   reading.microseconds);
            widest = (reading.device_bytes > widest) ? reading.device_bytes : widest;
        }
        const int moved = (outputs != NULL) && (general != NULL)
                       && qasm_test_general(circuit->qubits, general, &error)
                       && qasm_test_run(circuit, general, QASM_TEST_GENERAL_LANES, 1, outputs, NULL, 0ull, &reading)
                       && qasm_test_matches_dense(circuit, general, QASM_TEST_GENERAL_LANES, outputs, &error);
        snprintf(claim, sizeof(claim),
                 "self: %s: %u general lanes on the host equal the dense port from the same states", circuit->name,
                 QASM_TEST_GENERAL_LANES);
        qasm_test_check(tally, moved, claim);
        free(outputs);
        free(general);
    }
    return widest;
}

// One launch on the device against the same lanes on the host: every record limb and every state equal. The host's
// first run lays the program and gives the record's limbs.
static void qasm_test_agree(QasmTally *tally, const QasmTestCircuit *circuit, const QasmNumber *inputs,
                            unsigned long long lanes, const char *which)
{
    const unsigned int amplitudes = 1u << circuit->qubits;
    // the lanes are at most 2^5, so the numbers are at most 2^10, held by a size_t
    const size_t numbers = (size_t)(lanes * amplitudes);
    QasmNumber *const host_outputs = (QasmNumber *)calloc(numbers, sizeof(QasmNumber));
    QasmNumber *const device_outputs = (QasmNumber *)calloc(numbers, sizeof(QasmNumber));
    QasmSelfReading host;
    QasmSelfReading device;
    memset(&host, 0, sizeof(host));
    memset(&device, 0, sizeof(device));
    int agree = (host_outputs != NULL) && (device_outputs != NULL)
             && qasm_test_run(circuit, inputs, lanes, 1, host_outputs, NULL, 0ull, &host);
    // widening: the out limbs are an unsigned int
    const unsigned long long room = lanes * (unsigned long long)host.out_limbs;
    // at most 2^5 records of a layout the host just laid, held by a size_t
    unsigned int *const host_records = agree ? (unsigned int *)calloc((size_t)room, sizeof(unsigned int)) : NULL;
    unsigned int *const device_records = agree ? (unsigned int *)calloc((size_t)room, sizeof(unsigned int)) : NULL;
    agree = agree && (host_records != NULL) && (device_records != NULL)
         && qasm_test_run(circuit, inputs, lanes, 1, host_outputs, host_records, room, &host)
         && qasm_test_run(circuit, inputs, lanes, 0, device_outputs, device_records, room, &device)
         && (memcmp(host_records, device_records, (size_t)room * sizeof(unsigned int)) == 0);
    for (size_t number = 0u; agree && (number < numbers); number += 1u)
    {
        agree = qasm_number_equal(&host_outputs[number], &device_outputs[number]);
    }
    char claim[256];
    snprintf(claim, sizeof(claim),
             "self: %s, %llu %s lanes in one launch on the device: %llu record limbs equal the host's word for word",
             circuit->name, lanes, which, room);
    qasm_test_check(tally, agree, claim);
    if (agree)
    {
        printf("         device %llu us, host %llu us\n", device.microseconds, host.microseconds);
    }
    free(host_outputs);
    free(device_outputs);
    free(host_records);
    free(device_records);
}

static void qasm_test_device(QasmTally *tally)
{
    for (unsigned int which = 0u; which < QASM_TEST_CIRCUITS; which += 1u)
    {
        const QasmTestCircuit *const circuit = &qasm_test_circuits[which];
        const unsigned int amplitudes = 1u << circuit->qubits;
        EngineError error;
        memset(&error, 0, sizeof(error));
        qasm_test_agree(tally, circuit, NULL, amplitudes, "basis");
        // widening: at most 2^5 amplitudes a lane
        QasmNumber *const general = (QasmNumber *)calloc((size_t)QASM_TEST_GENERAL_LANES * amplitudes,
                                                         sizeof(QasmNumber));
        if ((general != NULL) && qasm_test_general(circuit->qubits, general, &error))
        {
            qasm_test_agree(tally, circuit, general, QASM_TEST_GENERAL_LANES, "general");
        }
        else
        {
            qasm_test_check(tally, 0, "self: the general lanes build for the device");
        }
        free(general);
    }
}

static void qasm_test_refusals(QasmTally *tally)
{
    QasmNumber outputs[4];
    unsigned int records[1];
    QasmSelfReading reading;
    const QasmExactGate past = {QASM_EXACT_GATE_H, 2u, 0u, NULL};
    const QasmSelfRequest none = {0u, qasm_test_bell, 2u, NULL, 1ull, 1, outputs, NULL, 0ull, NULL};
    const QasmSelfRequest cases[5] = {
        {0u, qasm_test_bell, 2u, NULL, 1ull, 1, outputs, NULL, 0ull, NULL},
        {QASM_SELF_QUBITS_MOST + 1u, qasm_test_bell, 2u, NULL, 1ull, 1, outputs, NULL, 0ull, NULL},
        {2u, qasm_test_bell, 2u, NULL, 3ull, 1, outputs, NULL, 0ull, NULL},
        {2u, &past, 1u, NULL, 4ull, 1, outputs, NULL, 0ull, NULL},
        {2u, qasm_test_bell, 2u, NULL, 4ull, 1, outputs, records, 1ull, NULL}};
    static const char *const claims[5] = {
        "self: no qubits refuses, a request error from qasm",
        "self: qubits past QASM_SELF_QUBITS_MOST refuse, a request error from qasm",
        "self: basis lanes other than 2^qubits refuse, a request error from qasm",
        "self: a gate on a qubit past the state refuses, a request error from qasm",
        "self: record room short of the lanes' records refuses, a request error from qasm"};
    for (unsigned int at = 0u; at < 5u; at += 1u)
    {
        EngineError error;
        memset(&error, 0, sizeof(error));
        QasmSelfRequest request = cases[at];
        request.error = &error;
        qasm_test_check(tally, qasm_test_refused_here(qasm_self_run(&request, &reading), &error), claims[at]);
    }
    qasm_test_check(tally, qasm_self_run(&none, &reading) == QASM_REFUSED, "self: a request with no error refuses");
    // A state whose fields are 201 bits wide: 128 of them take 7 limbs each, past the register file's 256, and the
    // lay refuses the program before any lane runs.
    const unsigned int amplitudes = 1u << QASM_SELF_QUBITS_MOST;
    QasmNumber *const wide = (QasmNumber *)calloc(amplitudes, sizeof(QasmNumber));
    QasmNumber *const landed = (QasmNumber *)calloc(amplitudes, sizeof(QasmNumber));
    int refused = 0;
    if ((wide != NULL) && (landed != NULL))
    {
        for (unsigned int amplitude = 0u; amplitude < amplitudes; amplitude += 1u)
        {
            wide[amplitude] = qasm_number_zero;
        }
        anchor_exact_zero(&wide[0].real.rational.numerator);
        wide[0].real.rational.numerator.limb[6] = 1u << 8u;
        wide[0].real.rational.numerator.sign = 1;
        EngineError error;
        memset(&error, 0, sizeof(error));
        const QasmSelfRequest request = {QASM_SELF_QUBITS_MOST, qasm_test_ghz5, QASM_TEST_GATES(qasm_test_ghz5), wide,
                                         1ull, 1, landed, NULL, 0ull, &error};
        refused = (qasm_self_run(&request, &reading) == QASM_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
               && (error.module == ENGINE_MODULE_KEY_SCHEDULE);
    }
    qasm_test_check(tally, refused,
                    "self: 2^200 in a 5-qubit lane is past the register file, and the lay refuses it before any run");
    free(wide);
    free(landed);
}

int main(void)
{
    QasmTally tally = {0u, 0u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    qasm_test_check(&tally, qasm_test_gates(&error), "self: the matrix gates build");
    const unsigned long long widest = qasm_test_host(&tally);
    qasm_test_refusals(&tally);
    QasmJob *job = NULL;
    static const unsigned char named[] = "qasm_self_test";
    if (qasm_job_submit(named, sizeof(named) - 1u, (widest != 0ull) ? widest : 1ull, &job, &error) == QASM_REFUSED)
    {
        printf("  FAIL the device's tessera daemon did not admit the test (error kind %d, module %d, site %u)\n",
               (int)error.kind, (int)error.module, error.site);
        tally.failed += 1u;
    }
    else
    {
        qasm_test_device(&tally);
        EngineError released;
        memset(&released, 0, sizeof(released));
        qasm_job_release(job, &released);
    }
    printf("  qasm self test: %u checks, %u failed\n", tally.checks, tally.failed);
    return (tally.failed == 0u) ? 0 : 1;
}
