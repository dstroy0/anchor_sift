// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The cell test (engine_table.md item 11(f) 3). The cell runs cell_probe, one question a process, and each check holds
// how the probe ended to what the host's rules say it must: an exit and its status, the output it wrote, a fault and
// the rule it names, a probe past its limit, and a program that never started. After every death the cell asks again
// from a fresh process. The first argument is cell_probe's path, the second a folder for the probes' output
#include "cell.h"

#include <stdio.h>
#include <string.h>

// a POSIX signal's name, which a Windows build never reads (it has no SIGTRAP, and its SIGABRT is 22)
#if defined(_WIN32)
#define CELL_TEST_WINDOWS 1
#define CELL_TEST_SIGNAL(posix_) 0
#else
#include <signal.h>
#define CELL_TEST_WINDOWS 0
#define CELL_TEST_SIGNAL(posix_) (posix_)
#endif

#define CELL_TEST_ROOM 256u
// a question's limit, and the shorter one the probe that hangs is given
#define CELL_TEST_LIMIT 30000000ull
#define CELL_TEST_HANG_LIMIT 500000ull
// the most past its limit a probe that hangs may take to be ended and reaped
#define CELL_TEST_HANG_SLACK 5000000ull

typedef struct
{
    const char *probe;
    const char *folder;
    unsigned int checks;
    unsigned int failed;
} CellTest;

static void cell_test_check(CellTest *test, int held, const char *what)
{
    test->checks += 1u;
    test->failed += held ? 0u : 1u;
    printf("  %s %s\n", held ? "ok  " : "FAIL", what);
}

// one probe run to its end, its answer printed whole; 0 where the cell itself failed
static int cell_test_ask(CellTest *test, const char *name, char *const *command, unsigned long long limit,
                         CellAnswer *answer, char *output, unsigned long long room)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.out", test->folder, name);
    const CellProbe probe = {command, path, limit};
    memset(answer, 0, sizeof(*answer));
    answer->output = output;
    answer->output_room = room;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long asked = cell_probe_run(&probe, answer, &error);
    if (asked != 0L)
    {
        printf("  %s: the cell failed, module %d site %u status %d\n", name, (int)error.module, error.site, error.status);
        return 0;
    }
    printf("  %s: %s, code %llu (0x%llx), fault %s, %llu bytes of output, %llu.%06llu s\n", name,
           cell_ending_name(answer->ending), answer->code, answer->code, cell_fault_name(answer->fault),
           answer->output_bytes, answer->microseconds / 1000000ull, answer->microseconds % 1000000ull);
    return 1;
}

// a question whose answer is a fault: on Windows the NTSTATUS given, on POSIX the signal given, and the rule both name
static void cell_test_fault(CellTest *test, const char *question, unsigned long long windows_code, int posix_signal,
                            CellFault fault)
{
    char *const command[] = {(char *)test->probe, (char *)question, NULL};
    CellAnswer answer;
    char output[CELL_TEST_ROOM];
    char what[256];
    const int asked = cell_test_ask(test, question, command, CELL_TEST_LIMIT, &answer, output, sizeof(output));
#if CELL_TEST_WINDOWS
    (void)posix_signal;
    snprintf(what, sizeof(what), "%s faults with 0x%llx, the rule %s", question, windows_code, cell_fault_name(fault));
    cell_test_check(test, asked && (answer.ending == CELL_ENDING_FAULTED) && (answer.code == windows_code)
                              && (answer.fault == fault), what);
#else
    (void)windows_code;
    snprintf(what, sizeof(what), "%s is ended by signal %d, the rule %s", question, posix_signal, cell_fault_name(fault));
    // a signal's number is positive
    cell_test_check(test, asked && (answer.ending == CELL_ENDING_SIGNALED)
                              && (answer.code == (unsigned long long)posix_signal) && (answer.fault == fault), what);
#endif
}

// the cell asks again from a fresh process, and the answer is the plain exit
static void cell_test_fresh(CellTest *test, const char *after)
{
    char *const command[] = {(char *)test->probe, "exit", "0", NULL};
    CellAnswer answer;
    char what[256];
    const int asked = cell_test_ask(test, "fresh", command, CELL_TEST_LIMIT, &answer, NULL, 0ull);
    snprintf(what, sizeof(what), "a fresh probe after %s exits 0", after);
    cell_test_check(test, asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull), what);
}

int main(int count, char **arguments)
{
    if (count < 3)
    {
        fprintf(stderr, "  cell_test: <cell_probe> <output folder>\n");
        return 2;
    }
    CellTest test = {arguments[1], arguments[2], 0u, 0u};
    CellAnswer answer;
    char output[CELL_TEST_ROOM];

    char *const exit_zero[] = {(char *)test.probe, "exit", "0", NULL};
    int asked = cell_test_ask(&test, "exit_0", exit_zero, CELL_TEST_LIMIT, &answer, output, sizeof(output));
    cell_test_check(&test, asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull)
                               && (answer.fault == CELL_FAULT_NONE) && (answer.output_bytes == 0ull),
                    "exit 0 exits 0 with no output");

    char *const exit_three[] = {(char *)test.probe, "exit", "3", NULL};
    asked = cell_test_ask(&test, "exit_3", exit_three, CELL_TEST_LIMIT, &answer, output, sizeof(output));
    cell_test_check(&test, asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 3ull),
                    "exit 3 exits 3");

    // the output and the errors land in one file, in the order written
    char *const write_words[] = {(char *)test.probe, "write", "a word with spaces", NULL};
    const char written[] = "out: a word with spaces\nerr: a word with spaces\n";
    asked = cell_test_ask(&test, "write", write_words, CELL_TEST_LIMIT, &answer, output, sizeof(output));
    const size_t written_length = strlen(written);
    // on Windows the C runtime writes a line's end as two bytes
    const size_t written_windows = written_length + 2u;
    const int length_held = (answer.output_bytes == written_length)
                         || (CELL_TEST_WINDOWS && (answer.output_bytes == written_windows));
    const int text_held = (strstr(output, "out: a word with spaces") == output)
                       && (strstr(output, "err: a word with spaces") != NULL);
    cell_test_check(&test, asked && (answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull) && length_held
                               && text_held,
                    "write gives its output then its errors, one word with spaces kept whole");

    // a room smaller than the output keeps what fits and counts it all
    char small[8];
    asked = cell_test_ask(&test, "write_small", write_words, CELL_TEST_LIMIT, &answer, small, sizeof(small));
    cell_test_check(&test, asked && (strcmp(small, "out: a ") == 0) && length_held,
                    "a room of 8 keeps 7 bytes and a zero, and counts the whole output");

    cell_test_fault(&test, "divide_by_zero", 0xC0000094ull, CELL_TEST_SIGNAL(SIGFPE), CELL_FAULT_ARITHMETIC);
    cell_test_fresh(&test, "a division by zero");
    cell_test_fault(&test, "divide_overflow", 0xC0000095ull, CELL_TEST_SIGNAL(SIGFPE), CELL_FAULT_ARITHMETIC);
    cell_test_fault(&test, "read_address", 0xC0000005ull, CELL_TEST_SIGNAL(SIGSEGV), CELL_FAULT_ADDRESS);
    cell_test_fresh(&test, "a read of an address out of range");
    cell_test_fault(&test, "illegal_instruction", 0xC000001Dull, CELL_TEST_SIGNAL(SIGILL), CELL_FAULT_INSTRUCTION);
    cell_test_fault(&test, "breakpoint", 0x80000003ull, CELL_TEST_SIGNAL(SIGTRAP), CELL_FAULT_TRAP);
    // Windows tells a stack run past its end apart; POSIX delivers it as SIGSEGV, an address
    cell_test_fault(&test, "stack", 0xC00000FDull, CELL_TEST_SIGNAL(SIGSEGV),
                    CELL_TEST_WINDOWS ? CELL_FAULT_STACK : CELL_FAULT_ADDRESS);
    cell_test_fault(&test, "abort", 0xC0000409ull, CELL_TEST_SIGNAL(SIGABRT), CELL_FAULT_ABORT);
    cell_test_fresh(&test, "an abort");

    char *const hang[] = {(char *)test.probe, "hang", NULL};
    asked = cell_test_ask(&test, "hang", hang, CELL_TEST_HANG_LIMIT, &answer, output, sizeof(output));
    cell_test_check(&test, asked && (answer.ending == CELL_ENDING_OUT_OF_TIME)
                               && (answer.microseconds >= CELL_TEST_HANG_LIMIT)
                               && (answer.microseconds < (CELL_TEST_HANG_LIMIT + CELL_TEST_HANG_SLACK)),
                    "a probe that hangs is ended once its 0.5 s limit runs out, and reaped within 5 s of it");
    cell_test_fresh(&test, "a probe ended for its time");

    char *const absent[] = {"cell_probe_no_such_program", NULL};
    asked = cell_test_ask(&test, "absent", absent, CELL_TEST_LIMIT, &answer, output, sizeof(output));
    cell_test_check(&test, asked && (answer.ending == CELL_ENDING_NOT_STARTED),
                    "a program that is not there is not started");

    printf("  cell test: %u checks, %u failed\n", test.checks, test.failed);
    return (test.failed == 0u) ? 0 : 1;
}
