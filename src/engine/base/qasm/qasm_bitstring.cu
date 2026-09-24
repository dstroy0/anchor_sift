// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// qasm_bitstring [--host] circuit.qasm
// Reads an OpenQASM 2.0 circuit, runs it exactly in fixed point on the device (or the host), and prints the most
// likely bitstring, its probability, the runner-up, and whether the proved error bound separates them.
// Exit 0: the peak is proved. Exit 3: it is not. Exit 1: the circuit or the run was refused.

#define QASM_EXIT_PROVED 0
#define QASM_EXIT_REFUSED 1
#define QASM_EXIT_USAGE 2
#define QASM_EXIT_NOT_PROVED 3

#define QASM_PLACES 12u

static void qasm_print_error(const char *what, const EngineError *error)
{
    fprintf(stderr, "qasm_bitstring: %s (error kind %d, module %d, site %u, status %d)\n", what, (int)error->kind,
            (int)error->module, error->site, error->status);
}

int main(int count, char **arguments)
{
    int on_host = 0;
    const char *path = NULL;
    for (int at = 1; at < count; at += 1)
    {
        if (strcmp(arguments[at], "--host") == 0)
        {
            on_host = 1;
        }
        else if ((path == NULL) && (arguments[at][0] != '-'))
        {
            path = arguments[at];
        }
        else
        {
            path = NULL;
            break;
        }
    }
    if (path == NULL)
    {
        fprintf(stderr, "usage: qasm_bitstring [--host] circuit.qasm\n");
        return QASM_EXIT_USAGE;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    char reason[QASM_REASON_ROOM];
    reason[0] = '\0';
    QasmCircuit circuit;
    const QasmReadRequest read = {path, NULL, 0u, reason, sizeof(reason), &error};
    if (qasm_read(&read, &circuit) == QASM_REFUSED)
    {
        if (reason[0] != '\0')
        {
            fprintf(stderr, "%s\n", reason);
        }
        else
        {
            qasm_print_error("the circuit was not read", &error);
        }
        return QASM_EXIT_REFUSED;
    }
    QasmJob *job = NULL;
    if (on_host == 0)
    {
        // the job is named by the run's path and the circuit's size
        char named[QASM_REASON_ROOM];
        const int length = snprintf(named, sizeof(named), "qasm_bitstring %s %u %u", path, circuit.qubits,
                                    circuit.gate_count);
        const unsigned long long bytes = (length > 0) ? (unsigned long long)length : 0ull;
        if (qasm_job_submit((const unsigned char *)named, bytes, qasm_device_bytes(&circuit), &job, &error)
            == QASM_REFUSED)
        {
            qasm_print_error("the device's tessera daemon did not admit the run", &error);
            qasm_release(&circuit);
            return QASM_EXIT_REFUSED;
        }
    }
    QasmOutcome outcome;
    const QasmRunRequest run = {&circuit, on_host, NULL, &error};
    const long ran = qasm_run(&run, &outcome);
    if (job != NULL)
    {
        EngineError released;
        memset(&released, 0, sizeof(released));
        qasm_job_release(job, &released);
    }
    if (ran == QASM_REFUSED)
    {
        qasm_print_error((error.kind == ENGINE_ERROR_RESOURCE) ? "the run was refused: the state does not fit"
                                                               : "the run was refused",
                         &error);
        qasm_release(&circuit);
        return QASM_EXIT_REFUSED;
    }
    char bitstring[QASM_CLBITS_MOST + 1u];
    char runner_up[QASM_CLBITS_MOST + 1u];
    char bound[96];
    char peak[96];
    char second[96];
    char slack[96];
    qasm_bitstring(&circuit, outcome.peak, bitstring, sizeof(bitstring));
    qasm_bitstring(&circuit, outcome.runner_up, runner_up, sizeof(runner_up));
    qasm_units_decimal(circuit.bound, QASM_PLACES, bound, sizeof(bound));
    qasm_units_decimal(outcome.peak_units, QASM_PLACES, peak, sizeof(peak));
    qasm_units_decimal(outcome.runner_up_units, QASM_PLACES, second, sizeof(second));
    qasm_units_decimal(outcome.slack_units, QASM_PLACES, slack, sizeof(slack));
    printf("qubits     %u (%u measured%s)\n", circuit.qubits, circuit.measured,
           (circuit.measured_all_by_default != 0u) ? ", no measure: every qubit into its own clbit" : "");
    printf("gates      %u (%u rounded, %u exact)\n", circuit.gate_count, circuit.rounded_gates, circuit.exact_gates);
    printf("bound E    %s\n", bound);
    printf("bitstring  %s\n", bitstring);
    printf("p(peak)    %s\n", peak);
    printf("runner-up  %s  p %s\n", runner_up, second);
    printf("slack      %s\n", slack);
    printf("run        %s, %u sweeps over %llu lanes, %llu us\n", (on_host != 0) ? "host" : "device", outcome.sweeps,
           outcome.lanes, outcome.microseconds);
    printf("%s\n", (outcome.proved != 0u) ? "PROVED" : "NOT PROVED");
    qasm_release(&circuit);
    return (outcome.proved != 0u) ? QASM_EXIT_PROVED : QASM_EXIT_NOT_PROVED;
}
