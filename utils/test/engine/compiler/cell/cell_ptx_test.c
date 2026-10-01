// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The cell's PTX test (engine_table.md item 11(f) 4). The cell runs cell_ptx_probe, one question a process: the
// membership queries, every arithmetic, test and conversion form of ptx.krs checked against the host's integers; then
// the illegal operations, each asked from a fresh process, since a fault on the device leaves its context unusable; and
// after each, a fresh process whose device answers. The first argument is cell_ptx_probe's path, the second a folder
// for the probes' output
#include "cell.h"

#include <stdio.h>
#include <string.h>

#define CELL_PTX_CAPACITY 65536u
// a question's limit: the membership queries assemble and run a kernel for each question
#define CELL_PTX_LIMIT 600000000ull

typedef struct
{
    const char *probe;
    const char *folder;
    unsigned int checks;
    unsigned int failed;
} CellPtxTest;

static char s_cell_ptx_output[CELL_PTX_CAPACITY];

static void cell_ptx_check(CellPtxTest *test, int passed, const char *what)
{
    test->checks += 1u;
    test->failed += passed ? 0u : 1u;
    printf("  %s %s\n", passed ? "ok  " : "FAIL", what);
}

// one question asked of the probe in a process of its own, its answer and its output printed whole; 0 where the cell
// itself failed
static int cell_ptx_ask(CellPtxTest *test, const char *question, CellAnswer *answer)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.out", test->folder, question);
    char *const command[] = {(char *)test->probe, (char *)question, NULL};
    const CellProbe probe = {command, path, CELL_PTX_LIMIT};
    memset(answer, 0, sizeof(*answer));
    answer->output = s_cell_ptx_output;
    answer->output_capacity = sizeof(s_cell_ptx_output);
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (cell_probe_run(&probe, answer, &error) != 0L)
    {
        printf("  %s: the cell failed, module %d site %u status %d\n", question, (int)error.module, error.site,
               error.status);
        return 0;
    }
    printf("  %s: %s, code %llu (0x%llx), fault %s, %llu bytes of output, %llu.%06llu s\n", question,
           cell_ending_name(answer->ending), answer->code, answer->code, cell_fault_name(answer->fault),
           answer->output_bytes, answer->microseconds / 1000000ull, answer->microseconds % 1000000ull);
    printf("%s", s_cell_ptx_output);
    return 1;
}

// a fresh process whose device answers 6 + 7
static void cell_ptx_alive(CellPtxTest *test, const char *after)
{
    CellAnswer answer;
    char what[256];
    const int asked = cell_ptx_ask(test, "alive", &answer);
    snprintf(what, sizeof(what), "a fresh probe after %s: the device answers 6 + 7 = 0x0000000d", after);
    cell_ptx_check(test,
                   asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull) &&
                       (strstr(s_cell_ptx_output, "answered 0000000d") != NULL),
                   what);
}

// an illegal operation the device errors: the probe exits 3 having printed the CUDA error, which `error` names where
// it is given
static void cell_ptx_error(CellPtxTest *test, const char *question, const char *error, const char *what)
{
    CellAnswer answer;
    const int asked = cell_ptx_ask(test, question, &answer);
    const int named =
        (error == NULL) ? (strstr(s_cell_ptx_output, "error ") != NULL) : (strstr(s_cell_ptx_output, error) != NULL);
    cell_ptx_check(test, asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 3ull) && named, what);
}

int main(int count, char **arguments)
{
    if (count < 3)
    {
        fprintf(stderr, "  cell_ptx_test: <cell_ptx_probe> <output folder>\n");
        return 2;
    }
    CellPtxTest test = {arguments[1], arguments[2], 0u, 0u};
    CellAnswer answer;

    cell_ptx_alive(&test, "nothing");

    int asked = cell_ptx_ask(&test, "membership", &answer);
    cell_ptx_check(&test,
                   asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull) &&
                       (strstr(s_cell_ptx_output, " questions, 0 with a case that differs") != NULL),
                   "membership: every defined answer of every form agrees with the host's integers");

    cell_ptx_error(&test, "address", "error 700 cudaErrorIllegalAddress",
                   "a load from address 16 errors as an illegal address (700)");
    cell_ptx_alive(&test, "an illegal address");
    cell_ptx_error(&test, "misaligned", "error 716 cudaErrorMisalignedAddress",
                   "a 32-bit load one byte in errors as a misaligned address (716)");
    cell_ptx_alive(&test, "a misaligned address");
    cell_ptx_error(&test, "trap", NULL, "trap errors with a CUDA error");
    cell_ptx_alive(&test, "a trap");

    asked = cell_ptx_ask(&test, "lacking", &answer);
    cell_ptx_check(&test,
                   asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 4ull) &&
                       (strstr(s_cell_ptx_output, "errored") != NULL),
                   "elect.sync, which PTX gives sm_90 and later, errors in the toolchain for this device");
    cell_ptx_alive(&test, "an instruction the part lacks");

    printf("  cell ptx test: %u checks, %u failed\n", test.checks, test.failed);
    return (test.failed == 0u) ? 0 : 1;
}
