// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include "exact_integer.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// qasm_test <fixture directory>: refusals by line and column, known answers on the device and the host, the
// bound's formula, the probabilities within the proved slack of their true values, and the device against the
// host word for word.

#define TEXT_ROOM (1u << 20u)

static unsigned int g_passed = 0u;
static unsigned int g_failed = 0u;

static void check(int held, const char *format, ...)
{
    char what[1024];
    va_list list;
    va_start(list, format);
    vsnprintf(what, sizeof(what), format, list);
    va_end(list);
    if (held != 0)
    {
        g_passed += 1u;
        printf("  ok   %s\n", what);
    }
    else
    {
        g_failed += 1u;
        printf("  FAIL %s\n", what);
    }
}

static const char HEADER[] = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\n";

typedef struct
{
    char *text;
    size_t length;
} Text;

static void text_add(Text *text, const char *format, ...)
{
    va_list list;
    va_start(list, format);
    const int written = vsnprintf(text->text + text->length, TEXT_ROOM - text->length, format, list);
    va_end(list);
    if (written > 0)
    {
        text->length += (size_t)written;
    }
}

static int read_text(const char *name, const char *text, QasmCircuit *circuit, char *reason, size_t room)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    reason[0] = '\0';
    const QasmReadRequest request = {name, text, strlen(text), reason, room, &error};
    return qasm_read(&request, circuit) != QASM_REFUSED;
}

static int run(const QasmCircuit *circuit, int on_host, QasmOutcome *outcome, unsigned int *state)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const QasmRunRequest request = {circuit, on_host, state, &error};
    if (qasm_run(&request, outcome) == QASM_REFUSED)
    {
        printf("  run refused on the %s: error kind %d, module %d, site %u, status %d\n", on_host ? "host" : "device",
               (int)error.kind, (int)error.module, error.site, error.status);
        return 0;
    }
    return 1;
}

static void units_exact(const unsigned int units[QASM_WIDE_LIMBS], AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    int any = 0;
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        value->limb[limb] = units[limb];
        any |= (units[limb] != 0u);
    }
    value->sign = any ? 1 : 0;
}

// |units - num 2^shift| <= slack, all in units of 2^-2F
static int within(const unsigned int units[QASM_WIDE_LIMBS], unsigned int num, unsigned int shift,
                  const unsigned int slack_units[QASM_WIDE_LIMBS])
{
    AnchorExactInteger value;
    AnchorExactInteger target;
    AnchorExactInteger slack;
    AnchorExactInteger gap;
    units_exact(units, &value);
    units_exact(slack_units, &slack);
    anchor_exact_zero(&target);
    target.limb[shift / 32u] = num << (shift % 32u);
    if ((shift % 32u) != 0u)
    {
        target.limb[(shift / 32u) + 1u] = (unsigned int)((unsigned long long)num >> (32u - (shift % 32u)));
    }
    target.sign = (num != 0u) ? 1 : 0;
    anchor_exact_subtract(&value, &target, &gap);
    gap.sign = (gap.sign < 0) ? 1 : gap.sign;
    return anchor_exact_compare(&gap, &slack) <= 0;
}

static int units_are_power(const unsigned int units[QASM_WIDE_LIMBS], unsigned int shift)
{
    for (unsigned int limb = 0u; limb < QASM_WIDE_LIMBS; limb += 1u)
    {
        const unsigned int wanted = (limb == (shift / 32u)) ? (1u << (shift % 32u)) : 0u;
        if (units[limb] != wanted)
        {
            return 0;
        }
    }
    return 1;
}

// ---------------------------------------------------------------------------------------------------------------

typedef struct
{
    const char *body;
    unsigned int qubits;
    const char *expected;
} KnownAnswer;

static const KnownAnswer KNOWN[] = {
    {"x q[0];", 3u, "001"},
    {"u3(pi,0,pi) q[0];", 1u, "1"},
    {"U(pi,0,pi) q[0];", 1u, "1"},
    {"u(pi,0,pi) q[0];", 1u, "1"},
    {"rx(pi) q[0];", 1u, "1"},
    {"ry(pi/2) q[0]; ry(pi/2) q[0];", 1u, "1"},
    {"sx q[0]; sx q[0];", 1u, "1"},
    {"sxdg q[0]; sxdg q[0];", 1u, "1"},
    {"h q[0]; t q[0]; t q[0]; t q[0]; t q[0]; h q[0];", 1u, "1"},
    {"h q[0]; tdg q[0]; tdg q[0]; tdg q[0]; tdg q[0]; h q[0];", 1u, "1"},
    {"h q[0]; rz(pi) q[0]; h q[0];", 1u, "1"},
    {"h q[0]; u1(pi/2) q[0]; u1(pi/2) q[0]; h q[0];", 1u, "1"},
    {"h q[0]; p(0.5) q[0]; p(pi-0.5) q[0]; h q[0];", 1u, "1"},
    {"u2(0,pi) q[0]; u2(0,pi) q[0];", 1u, "0"},
    {"h q[0]; s q[0]; s q[0]; h q[0];", 1u, "1"},
    {"h q[0]; sdg q[0]; sdg q[0]; h q[0];", 1u, "1"},
    {"h q[0]; z q[0]; h q[0];", 1u, "1"},
    {"y q[0];", 1u, "1"},
    {"x q[0]; cy q[0],q[1];", 2u, "11"},
    {"x q[0]; h q[1]; cz q[0],q[1]; h q[1];", 2u, "11"},
    {"x q[0]; h q[1]; ch q[0],q[1];", 2u, "01"},
    {"h q[1]; ch q[0],q[1]; h q[1];", 2u, "00"},
    {"x q[0]; crx(pi) q[0],q[1];", 2u, "11"},
    {"crx(pi) q[0],q[1];", 2u, "00"},
    {"x q[0]; cry(pi) q[0],q[1];", 2u, "11"},
    {"x q[0]; h q[1]; crz(pi) q[0],q[1]; h q[1];", 2u, "11"},
    {"x q[0]; h q[1]; cu1(pi) q[0],q[1]; h q[1];", 2u, "11"},
    {"x q[0]; h q[1]; cp(pi/3) q[0],q[1]; cp(2*pi/3) q[0],q[1]; h q[1];", 2u, "11"},
    {"x q[0]; cu3(pi,0,pi) q[0],q[1];", 2u, "11"},
    {"x q[0]; cu(pi,0,pi,pi/2) q[0],q[1];", 2u, "11"},
    {"x q[0]; csx q[0],q[1]; csx q[0],q[1];", 2u, "11"},
    {"x q[0]; swap q[0],q[1];", 2u, "10"},
    {"x q[0]; x q[1]; cswap q[0],q[1],q[2];", 3u, "101"},
    {"x q[1]; cswap q[0],q[1],q[2];", 3u, "010"},
    {"x q[0]; x q[1]; ccx q[0],q[1],q[2];", 3u, "111"},
    {"x q[0]; ccx q[0],q[1],q[2];", 3u, "001"},
    {"x q[0]; x q[1]; x q[2]; c3x q[0],q[1],q[2],q[3];", 4u, "1111"},
    {"rxx(pi) q[0],q[1];", 2u, "11"},
    {"ryy(pi) q[0],q[1];", 2u, "11"},
    {"h q[0]; h q[1]; rzz(pi) q[0],q[1]; h q[0]; h q[1];", 2u, "11"},
    {"id q[0]; u0(1) q[0]; x q[1];", 2u, "10"},
    {"x q[1]; barrier q; x q[2];", 3u, "110"},
    {"x q;", 3u, "111"},
    {"gate g(t) a { ry(t) a; } g(pi) q;", 3u, "111"},
    {"gate f(t) a,b { ry(t) a; cx a,b; } f(pi) q[0],q[1];", 2u, "11"},
    {"gate f(t) a,b { ry(t) a; cx a,b; } gate g(t) b,a { f(2*t) a,b; } g(pi/2) q[1],q[0];", 3u, "011"},
    {"gate h a { x a; } h q[0];", 1u, "1"},
    {"rx(-(-pi)) q[0];", 1u, "1"},
    {"rx(pi*1) q[0]; rx(2*pi/2 - 0) q[0]; rx(1e0*pi) q[0];", 1u, "1"},
    {"rx(pi + 100*pi) q[0];", 1u, "1"},
    {"ry(3.14159265358979323846264338327950288) q[0];", 1u, "1"},
    {"ry(-3.14159265358979323846264338327950288e0) q[0];", 1u, "1"},
    {"/* a comment */ x q[0]; // and another\n", 1u, "1"},
};

static void known_answers(void)
{
    char *const text = (char *)malloc(TEXT_ROOM);
    char reason[QASM_REASON_ROOM];
    for (size_t at = 0u; at < (sizeof(KNOWN) / sizeof(KNOWN[0])); at += 1u)
    {
        const KnownAnswer *const known = &KNOWN[at];
        Text built = {text, 0u};
        text_add(&built, "%sqreg q[%u];\ncreg c[%u];\n%s\nmeasure q -> c;\n", HEADER, known->qubits, known->qubits,
                 known->body);
        QasmCircuit circuit;
        if (!read_text("known.qasm", text, &circuit, reason, sizeof(reason)))
        {
            check(0, "known answer '%s' reads (%s)", known->body, reason);
            continue;
        }
        QasmOutcome device;
        QasmOutcome host;
        const unsigned long long lanes = 1ull << circuit.qubits;
        unsigned int *const device_state = (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
        unsigned int *const host_state = (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
        const int ran = run(&circuit, 0, &device, device_state) && run(&circuit, 1, &host, host_state);
        char bitstring[QASM_CLBITS_MOST + 1u];
        qasm_bitstring(&circuit, ran ? device.peak : 0ull, bitstring, sizeof(bitstring));
        check(ran && (device.proved != 0u) && (strcmp(bitstring, known->expected) == 0)
                  && (memcmp(device_state, host_state, (size_t)(lanes * QASM_STATE_LIMBS * sizeof(unsigned int))) == 0)
                  && (host.peak == device.peak) && (host.proved == device.proved),
              "known answer %-78s -> %s (wanted %s, %s, device = host)", known->body, bitstring, known->expected,
              (ran && device.proved) ? "proved" : "not proved");
        free(device_state);
        free(host_state);
        qasm_release(&circuit);
    }
    free(text);
}

// ---------------------------------------------------------------------------------------------------------------

typedef struct
{
    const char *body;
    const char *prefix;
    const char *fragment;
} Refusal;

static void refusals(void)
{
    static const Refusal REFUSALS[] = {
        {"OPENQASM 3.0;\n", "r.qasm:1:10:", "only OpenQASM 2.0"},
        {"OPENQASM 2.0;\ninclude \"other.inc\";\n", "r.qasm:2:9:", "qelib1.inc"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nreset q[0];\n", "r.qasm:4:1:", "'reset' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nmeasure q[0] -> c[0];\nh q[0];\n",
         "r.qasm:6:1:", "follows the measure"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(sin(1)) q[0];\n", "r.qasm:4:4:", "sin()"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nfoo q[0];\n", "r.qasm:4:1:", "not defined"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[31];\n", "r.qasm:3:6:", "past 30 qubits"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\ncreg c[1];\nif (c==1) x q[0];\n", "r.qasm:5:1:",
         "'if' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nopaque g a;\n", "r.qasm:4:1:", "'opaque' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncx q[0],q[0];\n", "r.qasm:4:1:", "names qubit 0 twice"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(pi*pi) q[0];\n", "r.qasm:4:6:", "pi times pi"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(1/pi) q[0];\n", "r.qasm:4:5:", "division by a multiple of pi"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(2^3) q[0];\n", "r.qasm:4:5:", "'^'"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nh q[2];\n", "r.qasm:4:5:", "past the register"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nrx(pi) q[0], q[1];\n", "r.qasm:4:1:", "takes 1 parameters and 1 qubits"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nmeasure q[0] -> c[0];\nmeasure q[0] -> c[1];\n",
         "r.qasm:6:9:", "measured twice"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nx q[0]\n", "r.qasm:5:1:", "';' was expected"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\ngate g a { measure a -> a; }\nqreg q[1];\ng q[0];\n", "r.qasm:3:12:",
         "inside a gate definition"},
    };
    char reason[QASM_REASON_ROOM];
    for (size_t at = 0u; at < (sizeof(REFUSALS) / sizeof(REFUSALS[0])); at += 1u)
    {
        QasmCircuit circuit;
        const int read = read_text("r.qasm", REFUSALS[at].body, &circuit, reason, sizeof(reason));
        if (read)
        {
            qasm_release(&circuit);
        }
        check(!read && (strncmp(reason, REFUSALS[at].prefix, strlen(REFUSALS[at].prefix)) == 0)
                  && (strstr(reason, REFUSALS[at].fragment) != NULL),
              "refused: %s", read ? "(it was read)" : reason);
    }
}

// ---------------------------------------------------------------------------------------------------------------

// a tie at 1/2: not proved, and each p' within the slack of 1/2
static void ties(void)
{
    static const struct
    {
        const char *body;
        unsigned int qubits;
        const char *one;
        const char *other;
    } TIES[] = {
        {"h q[0]; cx q[0],q[1];", 2u, "00", "11"},
        {"h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];", 5u, "00000", "11111"},
    };
    char *const text = (char *)malloc(TEXT_ROOM);
    char reason[QASM_REASON_ROOM];
    for (size_t at = 0u; at < (sizeof(TIES) / sizeof(TIES[0])); at += 1u)
    {
        Text built = {text, 0u};
        text_add(&built, "%sqreg q[%u];\ncreg c[%u];\n%s\nmeasure q -> c;\n", HEADER, TIES[at].qubits, TIES[at].qubits,
                 TIES[at].body);
        QasmCircuit circuit;
        QasmOutcome outcome;
        const int ran = read_text("tie.qasm", text, &circuit, reason, sizeof(reason)) && run(&circuit, 0, &outcome, NULL);
        char peak[QASM_CLBITS_MOST + 1u];
        char second[QASM_CLBITS_MOST + 1u];
        qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, peak, sizeof(peak));
        qasm_bitstring(&circuit, ran ? outcome.runner_up : 0ull, second, sizeof(second));
        const int pair = ((strcmp(peak, TIES[at].one) == 0) && (strcmp(second, TIES[at].other) == 0))
                      || ((strcmp(peak, TIES[at].other) == 0) && (strcmp(second, TIES[at].one) == 0));
        check(ran && pair && (outcome.proved == 0u)
                  && within(outcome.peak_units, 1u, (2u * QASM_FRACTION_BITS) - 1u, outcome.slack_units)
                  && within(outcome.runner_up_units, 1u, (2u * QASM_FRACTION_BITS) - 1u, outcome.slack_units),
              "tie %s / %s at 1/2 within the slack, not proved", peak, second);
        if (ran)
        {
            qasm_release(&circuit);
        }
    }
    free(text);
}

// the bound's formula: a Bell pair has one rounded gate at n = 2, so E' = (3 + 2^ceil(3/2)) 2^F = 7 2^60
static void bound_formula(void)
{
    char reason[QASM_REASON_ROOM];
    QasmCircuit circuit;
    const char *const text = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nh q[0];\ncx q[0],q[1];\n"
                             "measure q -> c;\n";
    const int read = read_text("bell.qasm", text, &circuit, reason, sizeof(reason));
    unsigned int wanted[QASM_WIDE_LIMBS] = {0u, 7u << 28u, 0u, 0u, 0u, 0u, 0u, 0u};
    check(read && (circuit.rounded_gates == 1u) && (circuit.exact_gates == 1u)
              && (memcmp(circuit.bound, wanted, sizeof(wanted)) == 0),
          "bound after one rounded gate on 2 qubits is exactly 7 * 2^60 units");
    if (read)
    {
        qasm_release(&circuit);
    }
    // a second rounded gate grows it by ceil(3 E / 2^F) and adds the same local term: 7 2^60 + 21 + 7 2^60
    const char *const twice = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nh q[0];\nh q[0];\n"
                              "measure q -> c;\n";
    const int again = read_text("twice.qasm", twice, &circuit, reason, sizeof(reason));
    unsigned int grown[QASM_WIDE_LIMBS] = {21u, 14u << 28u, 0u, 0u, 0u, 0u, 0u, 0u};
    check(again && (memcmp(circuit.bound, grown, sizeof(grown)) == 0),
          "bound after two rounded gates is (1 + 3 / 2^F) 7 2^60 + 7 2^60, rounded up");
    if (again)
    {
        qasm_release(&circuit);
    }
}

// exact gates alone: E = 0 and the peak's probability is 1 exactly
static void exact_only(void)
{
    char reason[QASM_REASON_ROOM];
    QasmCircuit circuit;
    const char *const text = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[4];\ncreg c[4];\nx q[0];\ncx q[0],q[1];\n"
                             "swap q[1],q[2];\ns q[2];\ny q[3];\nccx q[2],q[3],q[0];\ncz q[2],q[3];\nmeasure q -> c;\n";
    QasmOutcome outcome;
    const int ran = read_text("exact.qasm", text, &circuit, reason, sizeof(reason)) && run(&circuit, 0, &outcome, NULL);
    char bitstring[QASM_CLBITS_MOST + 1u];
    qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, bitstring, sizeof(bitstring));
    const unsigned int zero[QASM_WIDE_LIMBS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    check(ran && (circuit.rounded_gates == 0u) && (memcmp(circuit.bound, zero, sizeof(zero)) == 0)
              && units_are_power(outcome.peak_units, 2u * QASM_FRACTION_BITS) && (outcome.proved != 0u)
              && (strcmp(bitstring, "1100") == 0),
          "exact gates only: E = 0, p(%s) = 1 exactly, proved", bitstring);
    if (ran)
    {
        qasm_release(&circuit);
    }
}

// rxx(2 pi / 3) on |00>: cos(pi/3)|00> - i sin(pi/3)|11>, so p(11) = 3/4 and p(00) = 1/4
static void rxx_split(void)
{
    char reason[QASM_REASON_ROOM];
    QasmCircuit circuit;
    const char *const text = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nrxx(2*pi/3) q[0],q[1];\n"
                             "measure q -> c;\n";
    QasmOutcome outcome;
    const int ran = read_text("rxx.qasm", text, &circuit, reason, sizeof(reason)) && run(&circuit, 0, &outcome, NULL);
    char peak[QASM_CLBITS_MOST + 1u];
    char second[QASM_CLBITS_MOST + 1u];
    qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, peak, sizeof(peak));
    qasm_bitstring(&circuit, ran ? outcome.runner_up : 0ull, second, sizeof(second));
    check(ran && (strcmp(peak, "11") == 0) && (strcmp(second, "00") == 0) && (outcome.proved != 0u)
              && within(outcome.peak_units, 3u, (2u * QASM_FRACTION_BITS) - 2u, outcome.slack_units)
              && within(outcome.runner_up_units, 1u, (2u * QASM_FRACTION_BITS) - 2u, outcome.slack_units),
          "rxx(2 pi/3): p(%s) = 3/4 and p(%s) = 1/4 within the slack, proved", peak, second);
    if (ran)
    {
        qasm_release(&circuit);
    }
}

// the inverse quantum Fourier transform of the Fourier state of k returns k
static void inverse_fourier(void)
{
    const unsigned int n = 12u;
    const unsigned int k = 2741u;
    const unsigned int size = 1u << n;
    char *const text = (char *)malloc(TEXT_ROOM);
    Text built = {text, 0u};
    text_add(&built, "%sqreg q[%u];\ncreg c[%u];\n", HEADER, n, n);
    // (|0> + e^{2 pi i k 2^j / N}|1>) / sqrt 2 on qubit j is the Fourier state of k, bit j of x on qubit j
    for (unsigned int j = 0u; j < n; j += 1u)
    {
        text_add(&built, "h q[%u];\nu1(2*pi*%u/%u) q[%u];\n", j, (k << j) % size, size, j);
    }
    // the inverse of Qiskit's QFT: the swaps, then for each j its controlled phases and its h
    for (unsigned int i = 0u; i < (n / 2u); i += 1u)
    {
        text_add(&built, "swap q[%u],q[%u];\n", i, n - 1u - i);
    }
    for (unsigned int j = 0u; j < n; j += 1u)
    {
        for (unsigned int m = 0u; m < j; m += 1u)
        {
            text_add(&built, "cp(-pi/%u) q[%u],q[%u];\n", 1u << (j - m), j, m);
        }
        text_add(&built, "h q[%u];\n", j);
    }
    text_add(&built, "measure q -> c;\n");
    char reason[QASM_REASON_ROOM];
    QasmCircuit circuit;
    QasmOutcome outcome;
    const int read = read_text("fourier.qasm", text, &circuit, reason, sizeof(reason));
    const int ran = read && run(&circuit, 0, &outcome, NULL);
    char bitstring[QASM_CLBITS_MOST + 1u];
    char wanted[QASM_CLBITS_MOST + 1u];
    qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, bitstring, sizeof(bitstring));
    qasm_bitstring(&circuit, k, wanted, sizeof(wanted));
    check(ran && (strcmp(bitstring, wanted) == 0) && (outcome.proved != 0u)
              && within(outcome.peak_units, 1u, 2u * QASM_FRACTION_BITS, outcome.slack_units),
          "inverse QFT over %u qubits returns k = %u as %s (%u gates, %u rounded), p = 1 within the slack, proved", n,
          k, bitstring, read ? circuit.gate_count : 0u, read ? circuit.rounded_gates : 0u);
    if (!read)
    {
        printf("  %s\n", reason);
    }
    if (read)
    {
        qasm_release(&circuit);
    }
    free(text);
}

// the measure's clbits, measuring part of the register, and no measure at all
static void measurement(void)
{
    static const struct
    {
        const char *text;
        const char *expected;
        const char *what;
    } CASES[] = {
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[3];\ncreg c[3];\nx q[0];\nmeasure q[0] -> c[2];\n"
         "measure q[1] -> c[0];\nmeasure q[2] -> c[1];\n",
         "100", "q[0] measured into c[2]"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[1];\nh q[0];\nx q[1];\nmeasure q[1] -> c[0];\n", "1",
         "q[1] alone measured, q[0] summed over"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nx q[1];\n", "10", "no measure: every qubit into its own clbit"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg a[2];\nqreg b[2];\ncreg c[4];\nx a;\ncx a, b;\n"
         "measure a[0] -> c[0];\nmeasure a[1] -> c[1];\nmeasure b[0] -> c[2];\nmeasure b[1] -> c[3];\n",
         "1111", "two registers broadcast together"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg a[2];\nqreg b[1];\ncreg c[2];\ncreg d[1];\nx b[0];\n"
         "measure a -> c;\nmeasure b -> d;\n",
         "100", "registers flattened in declaration order"},
    };
    char reason[QASM_REASON_ROOM];
    for (size_t at = 0u; at < (sizeof(CASES) / sizeof(CASES[0])); at += 1u)
    {
        QasmCircuit circuit;
        QasmOutcome outcome;
        const int read = read_text("measure.qasm", CASES[at].text, &circuit, reason, sizeof(reason));
        const int ran = read && run(&circuit, 0, &outcome, NULL);
        char bitstring[QASM_CLBITS_MOST + 1u];
        qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, bitstring, sizeof(bitstring));
        check(ran && (strcmp(bitstring, CASES[at].expected) == 0) && (outcome.proved != 0u)
                  && within(outcome.peak_units, 1u, 2u * QASM_FRACTION_BITS, outcome.slack_units),
              "%s: %s (wanted %s), p = 1 within the slack, proved", CASES[at].what, bitstring, CASES[at].expected);
        if (!read)
        {
            printf("  %s\n", reason);
        }
        if (read)
        {
            qasm_release(&circuit);
        }
    }
}

// the fixtures, read by path
static void fixtures(const char *directory)
{
    static const struct
    {
        const char *file;
        const char *expected;
        unsigned int proved;
    } FIXTURES[] = {
        {"bernstein_vazirani.qasm", "101101001101", 1u},
        {"bell.qasm", NULL, 0u},
    };
    for (size_t at = 0u; at < (sizeof(FIXTURES) / sizeof(FIXTURES[0])); at += 1u)
    {
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", directory, FIXTURES[at].file);
        char reason[QASM_REASON_ROOM];
        reason[0] = '\0';
        EngineError error;
        memset(&error, 0, sizeof(error));
        QasmCircuit circuit;
        const QasmReadRequest request = {path, NULL, 0u, reason, sizeof(reason), &error};
        const int read = qasm_read(&request, &circuit) != QASM_REFUSED;
        QasmOutcome outcome;
        const int ran = read && run(&circuit, 0, &outcome, NULL);
        char bitstring[QASM_CLBITS_MOST + 1u];
        qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, bitstring, sizeof(bitstring));
        check(ran && (outcome.proved == FIXTURES[at].proved)
                  && ((FIXTURES[at].expected == NULL) || (strcmp(bitstring, FIXTURES[at].expected) == 0)),
              "fixture %s: %s, %s", FIXTURES[at].file, bitstring, (ran && outcome.proved) ? "proved" : "not proved");
        if (!read)
        {
            printf("  %s\n", reason);
        }
        if (read)
        {
            qasm_release(&circuit);
        }
    }
}

// a random circuit on the device and on the host: the same state word for word
static unsigned long long g_seed = 0x9E3779B97F4A7C15ull;

static unsigned int next_random(unsigned int below)
{
    g_seed = (g_seed * 6364136223846793005ull) + 1442695040888963407ull;
    return (unsigned int)((g_seed >> 33u) % below);
}

static void random_angle(char *angle, size_t room)
{
    const unsigned int form = next_random(3u);
    if (form == 0u)
    {
        snprintf(angle, room, "%d*pi/%u", (int)next_random(17u) - 8, 1u + next_random(12u));
    }
    else if (form == 1u)
    {
        snprintf(angle, room, "0.%06u", next_random(1000000u));
    }
    else
    {
        snprintf(angle, room, "-%u.%03u + pi/%u", next_random(4u), next_random(1000u), 1u + next_random(7u));
    }
}

static void device_against_host(void)
{
    static const char *const ONE[] = {"h", "x", "y", "z", "s", "sdg", "t", "tdg", "sx", "sxdg"};
    static const char *const ONE_ANGLE[] = {"rx", "ry", "rz", "u1", "p"};
    static const char *const TWO[] = {"cx", "cz", "cy", "ch", "swap", "csx"};
    static const char *const TWO_ANGLE[] = {"crx", "cry", "crz", "cu1", "cp", "rzz", "rxx", "ryy"};
    const unsigned int n = 8u;
    const unsigned int gates = 200u;
    char *const text = (char *)malloc(TEXT_ROOM);
    Text built = {text, 0u};
    text_add(&built, "%sqreg q[%u];\ncreg c[%u];\n", HEADER, n, n);
    for (unsigned int gate = 0u; gate < gates; gate += 1u)
    {
        const unsigned int a = next_random(n);
        const unsigned int b = (a + 1u + next_random(n - 1u)) % n;
        unsigned int c = next_random(n);
        while ((c == a) || (c == b))
        {
            c = (c + 1u) % n;
        }
        char one[64];
        char two[64];
        char three[64];
        random_angle(one, sizeof(one));
        random_angle(two, sizeof(two));
        random_angle(three, sizeof(three));
        const unsigned int kind = next_random(8u);
        if (kind == 0u)
        {
            text_add(&built, "%s q[%u];\n", ONE[next_random(10u)], a);
        }
        else if (kind == 1u)
        {
            text_add(&built, "%s(%s) q[%u];\n", ONE_ANGLE[next_random(5u)], one, a);
        }
        else if (kind == 2u)
        {
            text_add(&built, "u3(%s,%s,%s) q[%u];\n", one, two, three, a);
        }
        else if (kind == 3u)
        {
            text_add(&built, "u2(%s,%s) q[%u];\n", one, two, a);
        }
        else if (kind == 4u)
        {
            text_add(&built, "%s q[%u],q[%u];\n", TWO[next_random(6u)], a, b);
        }
        else if (kind == 5u)
        {
            text_add(&built, "%s(%s) q[%u],q[%u];\n", TWO_ANGLE[next_random(8u)], one, a, b);
        }
        else if (kind == 6u)
        {
            text_add(&built, "cu3(%s,%s,%s) q[%u],q[%u];\n", one, two, three, a, b);
        }
        else
        {
            text_add(&built, "%s q[%u],q[%u],q[%u];\n", (next_random(2u) == 0u) ? "ccx" : "cswap", a, b, c);
        }
    }
    text_add(&built, "measure q -> c;\n");
    char reason[QASM_REASON_ROOM];
    QasmCircuit circuit;
    const int read = read_text("random.qasm", text, &circuit, reason, sizeof(reason));
    const unsigned long long lanes = 1ull << n;
    unsigned int *const device_state = (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
    unsigned int *const host_state = (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
    QasmOutcome device;
    QasmOutcome host;
    const int ran = read && run(&circuit, 0, &device, device_state) && run(&circuit, 1, &host, host_state);
    check(ran && (memcmp(device_state, host_state, (size_t)(lanes * QASM_STATE_LIMBS * sizeof(unsigned int))) == 0)
              && (device.peak == host.peak) && (device.runner_up == host.runner_up)
              && (memcmp(device.peak_units, host.peak_units, sizeof(device.peak_units)) == 0)
              && (memcmp(device.slack_units, host.slack_units, sizeof(device.slack_units)) == 0)
              && (device.proved == host.proved),
          "random circuit, %u qubits, %u gates (%u rounded): device and host agree word for word", n,
          read ? circuit.gate_count : 0u, read ? circuit.rounded_gates : 0u);
    if (!read)
    {
        printf("  %s\n", reason);
    }
    if (read)
    {
        qasm_release(&circuit);
    }
    free(device_state);
    free(host_state);
    free(text);
}

int main(int count, char **arguments)
{
    const char *const directory = (count > 1) ? arguments[1] : ".";
    // the job reserves the widest run here: 13 qubits
    QasmCircuit widest;
    memset(&widest, 0, sizeof(widest));
    widest.qubits = 13u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    QasmJob *job = NULL;
    static const unsigned char named[] = "qasm_test";
    if (qasm_job_submit(named, sizeof(named) - 1u, qasm_device_bytes(&widest), &job, &error) == QASM_REFUSED)
    {
        printf("  FAIL the device's tessera daemon did not admit the test (error kind %d, module %d, site %u)\n",
               (int)error.kind, (int)error.module, error.site);
        return 1;
    }
    refusals();
    bound_formula();
    known_answers();
    ties();
    exact_only();
    rxx_split();
    inverse_fourier();
    measurement();
    fixtures(directory);
    device_against_host();
    EngineError released;
    memset(&released, 0, sizeof(released));
    qasm_job_release(job, &released);
    printf("qasm_test: %u passed, %u failed\n", g_passed, g_failed);
    return (g_failed == 0u) ? 0 : 1;
}
