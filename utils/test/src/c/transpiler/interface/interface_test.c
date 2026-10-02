// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The interface test (engine_table.md item 11(f) 3). The interface runs interface_probe, one question a process, and each check holds
// how the probe ended to what the host's rules say it must: an exit and its status, the output it wrote, a fault and
// the rule it names, a probe past its limit, and a program that never started. After every death the interface asks again
// from a fresh process. The first argument is interface_probe's path, the second a folder for the probes' output
#include "../../../../../../src/c/transpiler/interface/interface.h"

#include <stdio.h>
#include <string.h>

// a POSIX signal's name, which a Windows build never reads (it has no SIGTRAP, and its SIGABRT is 22)
#if defined(_WIN32)
#define INTERFACE_TEST_WINDOWS 1
#define INTERFACE_TEST_SIGNAL(posix_) 0
#else
#include <signal.h>
#define INTERFACE_TEST_WINDOWS 0
#define INTERFACE_TEST_SIGNAL(posix_) (posix_)
#endif

// how the part answers an integer division by zero and INT_MIN / -1: x86 faults on both (#DE); AArch64 returns a
// quotient of 0 for a zero divisor and INT_MIN for the overflow; RISC-V returns all ones (-1) and INT_MIN. Each
// answered quotient is the probe's printed line
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#define INTERFACE_TEST_DIVISION_FAULTS 1
#define INTERFACE_TEST_ZERO_QUOTIENT ""
#elif defined(__aarch64__) || defined(_M_ARM64)
#define INTERFACE_TEST_DIVISION_FAULTS 0
#define INTERFACE_TEST_ZERO_QUOTIENT "0\n"
#elif defined(__riscv)
#define INTERFACE_TEST_DIVISION_FAULTS 0
#define INTERFACE_TEST_ZERO_QUOTIENT "-1\n"
#else
#error "the interface test knows how x86, AArch64 and RISC-V answer a division; add this part's answer"
#endif

#define INTERFACE_TEST_CAPACITY 256u
// a question's limit, and the shorter one the probe that hangs is given
#define INTERFACE_TEST_LIMIT 30000000ull
#define INTERFACE_TEST_HANG_LIMIT 500000ull
// the most past its limit a probe that hangs may take to be ended and reaped
#define INTERFACE_TEST_HANG_SLACK 5000000ull

typedef struct
{
    const char *probe;
    const char *folder;
    unsigned int checks;
    unsigned int failed;
} InterfaceTest;

static void interface_test_check(InterfaceTest *test, int passed, const char *what)
{
    test->checks += 1u;
    test->failed += passed ? 0u : 1u;
    printf("  %s %s\n", passed ? "ok  " : "FAIL", what);
}

// one probe run to its end, its answer printed whole; 0 where the interface itself failed
static int interface_test_ask(InterfaceTest *test, const char *name, char *const *command, unsigned long long limit,
                         InterfaceAnswer *answer, char *output, unsigned long long capacity)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.out", test->folder, name);
    const InterfaceProbe probe = {command, path, limit};
    memset(answer, 0, sizeof(*answer));
    answer->output = output;
    answer->output_capacity = capacity;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long asked = interface_probe_run(&probe, answer, &error);
    if (asked != 0L)
    {
        printf("  %s: the interface failed, module %d site %u status %d\n", name, (int)error.module, error.site,
               error.status);
        return 0;
    }
    printf("  %s: %s, code %llu (0x%llx), fault %s, %llu bytes of output, %llu.%06llu s\n", name,
           interface_ending_name(answer->ending), answer->code, answer->code, interface_fault_name(answer->fault),
           answer->output_bytes, answer->microseconds / 1000000ull, answer->microseconds % 1000000ull);
    return 1;
}

// a question whose answer is a fault: on Windows the NTSTATUS given, on POSIX the signal given, and the rule both name
static void interface_test_fault(InterfaceTest *test, const char *question, unsigned long long windows_code, int posix_signal,
                            InterfaceFault fault)
{
    char *const command[] = {(char *)test->probe, (char *)question, NULL};
    InterfaceAnswer answer;
    char output[INTERFACE_TEST_CAPACITY];
    char what[256];
    const int asked = interface_test_ask(test, question, command, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
#if INTERFACE_TEST_WINDOWS
    (void)posix_signal;
    snprintf(what, sizeof(what), "%s faults with 0x%llx, the rule %s", question, windows_code, interface_fault_name(fault));
    interface_test_check(test,
                    asked && (answer.ending == INTERFACE_ENDING_FAULTED) && (answer.code == windows_code) &&
                        (answer.fault == fault),
                    what);
#else
    (void)windows_code;
    snprintf(what, sizeof(what), "%s is ended by signal %d, the rule %s", question, posix_signal,
             interface_fault_name(fault));
    // a signal's number is positive
    interface_test_check(test,
                    asked && (answer.ending == INTERFACE_ENDING_SIGNALED) &&
                        (answer.code == (unsigned long long)posix_signal) && (answer.fault == fault),
                    what);
#endif
}

// a question the part answers where another faults: the probe exits 0, having printed exactly `printed`
static void interface_test_answered(InterfaceTest *test, const char *question, const char *printed)
{
    char *const command[] = {(char *)test->probe, (char *)question, NULL};
    InterfaceAnswer answer;
    char output[INTERFACE_TEST_CAPACITY];
    char what[256];
    const int asked = interface_test_ask(test, question, command, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
    snprintf(what, sizeof(what), "%s is answered, not faulted: the quotient %.*s", question,
             (int)(strlen(printed) - 1u), printed);
    interface_test_check(
        test, asked && (answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 0ull) && (strcmp(output, printed) == 0),
        what);
}

// the interface asks again from a fresh process, and the answer is the plain exit
static void interface_test_fresh(InterfaceTest *test, const char *after)
{
    char *const command[] = {(char *)test->probe, "exit", "0", NULL};
    InterfaceAnswer answer;
    char what[256];
    const int asked = interface_test_ask(test, "fresh", command, INTERFACE_TEST_LIMIT, &answer, NULL, 0ull);
    snprintf(what, sizeof(what), "a fresh probe after %s exits 0", after);
    interface_test_check(test, asked && (answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 0ull), what);
}

int main(int count, char **arguments)
{
    if (count < 3)
    {
        fprintf(stderr, "  interface_test: <interface_probe> <output folder>\n");
        return 2;
    }
    InterfaceTest test = {arguments[1], arguments[2], 0u, 0u};
    InterfaceAnswer answer;
    char output[INTERFACE_TEST_CAPACITY];

    char *const exit_zero[] = {(char *)test.probe, "exit", "0", NULL};
    int asked = interface_test_ask(&test, "exit_0", exit_zero, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
    interface_test_check(&test,
                    asked && (answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 0ull) &&
                        (answer.fault == INTERFACE_FAULT_NONE) && (answer.output_bytes == 0ull),
                    "exit 0 exits 0 with no output");

    char *const exit_three[] = {(char *)test.probe, "exit", "3", NULL};
    asked = interface_test_ask(&test, "exit_3", exit_three, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
    interface_test_check(&test, asked && (answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 3ull), "exit 3 exits 3");

    // the output and the errors land in one file, in the order written
    char *const write_words[] = {(char *)test.probe, "write", "a word with spaces", NULL};
    const char written[] = "out: a word with spaces\nerr: a word with spaces\n";
    asked = interface_test_ask(&test, "write", write_words, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
    const size_t written_length = strlen(written);
    // on Windows the C runtime writes a line's end as two bytes
    const size_t written_windows = written_length + 2u;
    const int length_ok =
        (answer.output_bytes == written_length) || (INTERFACE_TEST_WINDOWS && (answer.output_bytes == written_windows));
    const int text_ok =
        (strstr(output, "out: a word with spaces") == output) && (strstr(output, "err: a word with spaces") != NULL);
    interface_test_check(&test,
                    asked && (answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 0ull) && length_ok && text_ok,
                    "write gives its output then its errors, one word with spaces kept whole");

    // a capacity smaller than the output keeps what fits and counts it all
    char small[8];
    asked = interface_test_ask(&test, "write_small", write_words, INTERFACE_TEST_LIMIT, &answer, small, sizeof(small));
    interface_test_check(&test, asked && (strcmp(small, "out: a ") == 0) && length_ok,
                    "a capacity of 8 keeps 7 bytes and a zero, and counts the whole output");

#if INTERFACE_TEST_DIVISION_FAULTS
    interface_test_fault(&test, "divide_by_zero", 0xC0000094ull, INTERFACE_TEST_SIGNAL(SIGFPE), INTERFACE_FAULT_ARITHMETIC);
    interface_test_fresh(&test, "a division by zero");
    interface_test_fault(&test, "divide_overflow", 0xC0000095ull, INTERFACE_TEST_SIGNAL(SIGFPE), INTERFACE_FAULT_ARITHMETIC);
#else
    interface_test_answered(&test, "divide_by_zero", INTERFACE_TEST_ZERO_QUOTIENT);
    interface_test_fresh(&test, "a division by zero");
    interface_test_answered(&test, "divide_overflow", "-2147483648\n");
#endif
    interface_test_fault(&test, "read_address", 0xC0000005ull, INTERFACE_TEST_SIGNAL(SIGSEGV), INTERFACE_FAULT_ADDRESS);
    interface_test_fresh(&test, "a read of an address out of range");
    interface_test_fault(&test, "illegal_instruction", 0xC000001Dull, INTERFACE_TEST_SIGNAL(SIGILL), INTERFACE_FAULT_INSTRUCTION);
    interface_test_fault(&test, "breakpoint", 0x80000003ull, INTERFACE_TEST_SIGNAL(SIGTRAP), INTERFACE_FAULT_TRAP);
    // Windows tells a stack run past its end apart; POSIX delivers it as SIGSEGV, an address
    interface_test_fault(&test, "stack", 0xC00000FDull, INTERFACE_TEST_SIGNAL(SIGSEGV),
                    INTERFACE_TEST_WINDOWS ? INTERFACE_FAULT_STACK : INTERFACE_FAULT_ADDRESS);
    interface_test_fault(&test, "abort", 0xC0000409ull, INTERFACE_TEST_SIGNAL(SIGABRT), INTERFACE_FAULT_ABORT);
    interface_test_fresh(&test, "an abort");

    char *const hang[] = {(char *)test.probe, "hang", NULL};
    asked = interface_test_ask(&test, "hang", hang, INTERFACE_TEST_HANG_LIMIT, &answer, output, sizeof(output));
    interface_test_check(&test,
                    asked && (answer.ending == INTERFACE_ENDING_OUT_OF_TIME) &&
                        (answer.microseconds >= INTERFACE_TEST_HANG_LIMIT) &&
                        (answer.microseconds < (INTERFACE_TEST_HANG_LIMIT + INTERFACE_TEST_HANG_SLACK)),
                    "a probe that hangs is ended once its 0.5 s limit runs out, and reaped within 5 s of it");
    interface_test_fresh(&test, "a probe ended for its time");

    char *const absent[] = {"interface_probe_no_such_program", NULL};
    asked = interface_test_ask(&test, "absent", absent, INTERFACE_TEST_LIMIT, &answer, output, sizeof(output));
    interface_test_check(&test, asked && (answer.ending == INTERFACE_ENDING_NOT_STARTED),
                    "a program that is not there is not started");

    printf("  interface test: %u checks, %u failed\n", test.checks, test.failed);
    return (test.failed == 0u) ? 0 : 1;
}
