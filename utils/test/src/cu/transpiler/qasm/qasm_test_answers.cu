// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_test_answers.cu: text, runs, known answers, errors, ties and bounds
#include "../../../../engine/quantum/qasm/qasm_test_internal.h"

unsigned int g_passed = 0u;
unsigned int g_failed = 0u;

void check(int passed, const char *format, ...)
{
    char what[1024];
    va_list list;
    va_start(list, format);
    vsnprintf(what, sizeof(what), format, list);
    va_end(list);
    if (passed != 0)
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

void text_add(Text *text, const char *format, ...)
{
    va_list list;
    va_start(list, format);
    const int written = vsnprintf(text->text + text->length, TEXT_CAPACITY - text->length, format, list);
    va_end(list);
    if (written > 0)
    {
        text->length += (size_t)written;
    }
}

int read_text(const char *name, const char *text, QasmCircuit *circuit, char *reason, size_t capacity)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    reason[0] = '\0';
    const QasmReadRequest request = {name, text, strlen(text), reason, capacity, &error};
    return qasm_read(&request, circuit) != QASM_ERROR;
}

int run(const QasmCircuit *circuit, int on_host, QasmOutcome *outcome, unsigned int *state)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const QasmRunRequest request = {circuit, on_host, state, &error};
    if (qasm_run(&request, outcome) == QASM_ERROR)
    {
        printf("  run errored on the %s: error kind %d, module %d, site %u, status %d\n", on_host ? "host" : "device",
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
int within(const unsigned int units[QASM_WIDE_LIMBS], unsigned int num, unsigned int shift,
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

int units_are_power(const unsigned int units[QASM_WIDE_LIMBS], unsigned int shift)
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

void known_answers(void)
{
    char *const text = (char *)malloc(TEXT_CAPACITY);
    char reason[QASM_REASON_CAPACITY];
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
        unsigned int *const device_state =
            (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
        unsigned int *const host_state =
            (unsigned int *)calloc((size_t)(lanes * QASM_STATE_LIMBS), sizeof(unsigned int));
        const int ran = run(&circuit, 0, &device, device_state) && run(&circuit, 1, &host, host_state);
        char bitstring[QASM_CLBITS_MAX + 1u];
        qasm_bitstring(&circuit, ran ? device.peak : 0ull, bitstring, sizeof(bitstring));
        check(ran && (device.proved != 0u) && (strcmp(bitstring, known->expected) == 0) &&
                  (memcmp(device_state, host_state, (size_t)(lanes * QASM_STATE_LIMBS * sizeof(unsigned int))) == 0) &&
                  (host.peak == device.peak) && (host.proved == device.proved),
              "known answer %-78s -> %s (wanted %s, %s, device = host)", known->body, bitstring, known->expected,
              (ran && device.proved) ? "proved" : "not proved");
        free(device_state);
        free(host_state);
        qasm_release(&circuit);
    }
    free(text);
}

void errors(void)
{
    static const Error ERRORS[] = {
        {"OPENQASM 3.0;\n", "r.qasm:1:10:", "only OpenQASM 2.0"},
        {"OPENQASM 2.0;\ninclude \"other.inc\";\n", "r.qasm:2:9:", "qelib1.inc"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nreset q[0];\n", "r.qasm:4:1:", "'reset' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nmeasure q[0] -> c[0];\nh q[0];\n",
         "r.qasm:6:1:", "follows the measure"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(sin(1)) q[0];\n", "r.qasm:4:4:", "sin()"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nfoo q[0];\n", "r.qasm:4:1:", "not defined"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[31];\n", "r.qasm:3:6:", "past 30 qubits"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\ncreg c[1];\nif (c==1) x q[0];\n",
         "r.qasm:5:1:", "'if' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nopaque g a;\n", "r.qasm:4:1:", "'opaque' is not read"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncx q[0],q[0];\n", "r.qasm:4:1:", "names qubit 0 twice"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(pi*pi) q[0];\n", "r.qasm:4:6:", "pi times pi"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(1/pi) q[0];\n",
         "r.qasm:4:5:", "division by a multiple of pi"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nrx(2^3) q[0];\n", "r.qasm:4:5:", "'^'"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nh q[2];\n", "r.qasm:4:5:", "past the register"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\nrx(pi) q[0], q[1];\n",
         "r.qasm:4:1:", "takes 1 parameters and 1 qubits"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nmeasure q[0] -> c[0];\nmeasure q[0] -> "
         "c[1];\n",
         "r.qasm:6:9:", "measured twice"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nx q[0]\n", "r.qasm:5:1:", "';' was expected"},
        {"OPENQASM 2.0;\ninclude \"qelib1.inc\";\ngate g a { measure a -> a; }\nqreg q[1];\ng q[0];\n",
         "r.qasm:3:12:", "inside a gate definition"},
    };
    char reason[QASM_REASON_CAPACITY];
    for (size_t at = 0u; at < (sizeof(ERRORS) / sizeof(ERRORS[0])); at += 1u)
    {
        QasmCircuit circuit;
        const int read = read_text("r.qasm", ERRORS[at].body, &circuit, reason, sizeof(reason));
        if (read)
        {
            qasm_release(&circuit);
        }
        check(!read && (strncmp(reason, ERRORS[at].prefix, strlen(ERRORS[at].prefix)) == 0) &&
                  (strstr(reason, ERRORS[at].fragment) != NULL),
              "errored: %s", read ? "(it was read)" : reason);
    }
}

// ---------------------------------------------------------------------------------------------------------------

// a tie at 1/2: not proved, and each p' within the slack of 1/2
void ties(void)
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
    char *const text = (char *)malloc(TEXT_CAPACITY);
    char reason[QASM_REASON_CAPACITY];
    for (size_t at = 0u; at < (sizeof(TIES) / sizeof(TIES[0])); at += 1u)
    {
        Text built = {text, 0u};
        text_add(&built, "%sqreg q[%u];\ncreg c[%u];\n%s\nmeasure q -> c;\n", HEADER, TIES[at].qubits, TIES[at].qubits,
                 TIES[at].body);
        QasmCircuit circuit;
        QasmOutcome outcome;
        const int ran =
            read_text("tie.qasm", text, &circuit, reason, sizeof(reason)) && run(&circuit, 0, &outcome, NULL);
        char peak[QASM_CLBITS_MAX + 1u];
        char second[QASM_CLBITS_MAX + 1u];
        qasm_bitstring(&circuit, ran ? outcome.peak : 0ull, peak, sizeof(peak));
        qasm_bitstring(&circuit, ran ? outcome.runner_up : 0ull, second, sizeof(second));
        const int pair = ((strcmp(peak, TIES[at].one) == 0) && (strcmp(second, TIES[at].other) == 0)) ||
                         ((strcmp(peak, TIES[at].other) == 0) && (strcmp(second, TIES[at].one) == 0));
        check(ran && pair && (outcome.proved == 0u) &&
                  within(outcome.peak_units, 1u, (2u * QASM_FRACTION_BITS) - 1u, outcome.slack_units) &&
                  within(outcome.runner_up_units, 1u, (2u * QASM_FRACTION_BITS) - 1u, outcome.slack_units),
              "tie %s / %s at 1/2 within the slack, not proved", peak, second);
        if (ran)
        {
            qasm_release(&circuit);
        }
    }
    free(text);
}

// the bound's formula: a Bell pair has one rounded gate at n = 2. E' = (3 + 2^ceil(3/2)) 2^F = 7 2^60
void bound_formula(void)
{
    char reason[QASM_REASON_CAPACITY];
    QasmCircuit circuit;
    const char *const text = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nh q[0];\ncx q[0],q[1];\n"
                             "measure q -> c;\n";
    const int read = read_text("bell.qasm", text, &circuit, reason, sizeof(reason));
    unsigned int wanted[QASM_WIDE_LIMBS] = {0u, 7u << 28u, 0u, 0u, 0u, 0u, 0u, 0u};
    check(read && (circuit.rounded_gates == 1u) && (circuit.exact_gates == 1u) &&
              (memcmp(circuit.bound, wanted, sizeof(wanted)) == 0),
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
