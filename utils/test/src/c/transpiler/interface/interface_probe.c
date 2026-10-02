// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#if !defined(_WIN32)
// nanosleep is POSIX, outside strict C11
#define _POSIX_C_SOURCE 200809L
#endif
// A probe for the interface test: one question a process, named by its first word, asked of the host part and its system.
// Built with no optimization: each question reaches the part as written. The operands are volatile: no compiler
// folds a division it can see is undefined, and the part itself answers
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <intrin.h>
#include <windows.h>
#else
#include <time.h>
#endif

// the exit of a question this part is not asked
#define PROBE_NOT_ASKED 77

// a question this probe does not know
#define PROBE_UNKNOWN 64

static volatile int s_probe_numerator = 7;
static volatile int s_probe_zero = 0;
static volatile int s_probe_least = INT_MIN;
static volatile int s_probe_minus_one = -1;

// each frame holds a page the compiler cannot drop, and the call is not the frame's last act. No call becomes a
// jump. The recursion without end is the question, and MSVC's warning that it overflows the stack is its answer
// foretold
#if defined(_MSC_VER)
#pragma warning(disable : 4717)
#endif
static int probe_descend(int depth)
{
    volatile char page[4096];
    page[0] = (char)depth;
    page[sizeof(page) - 1u] = page[0];
    return probe_descend(depth + 1) + page[sizeof(page) - 1u];
}

static void probe_pause_second(void)
{
#if defined(_WIN32)
    Sleep(1000u);
#else
    struct timespec second;
    second.tv_sec = 1;
    second.tv_nsec = 0L;
    nanosleep(&second, NULL);
#endif
}

int main(int count, char **arguments)
{
    const char *const question = (count > 1) ? arguments[1] : "";
    if ((strcmp(question, "exit") == 0) && (count > 2))
    {
        return atoi(arguments[2]);
    }
    if ((strcmp(question, "write") == 0) && (count > 2))
    {
        fprintf(stdout, "out: %s\n", arguments[2]);
        fflush(stdout);
        fprintf(stderr, "err: %s\n", arguments[2]);
        fflush(stderr);
        return 0;
    }
    if (strcmp(question, "divide_by_zero") == 0)
    {
        printf("%d\n", s_probe_numerator / s_probe_zero);
        return 0;
    }
    if (strcmp(question, "divide_overflow") == 0)
    {
        printf("%d\n", s_probe_least / s_probe_minus_one);
        return 0;
    }
    if (strcmp(question, "read_address") == 0)
    {
        // the sixteenth byte of the address space, in the first page, which no process maps
        volatile const int *const address = (volatile const int *)(uintptr_t)16u;
        printf("%d\n", *address);
        return 0;
    }
    if (strcmp(question, "illegal_instruction") == 0)
    {
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
        __ud2();
#elif defined(__GNUC__) && (defined(__x86_64__) || defined(__i386__))
        __asm__ volatile("ud2");
#elif defined(__GNUC__) && defined(__aarch64__)
        __asm__ volatile("udf #0");
#else
        return PROBE_NOT_ASKED;
#endif
        return 0;
    }
    if (strcmp(question, "breakpoint") == 0)
    {
#if defined(_MSC_VER)
        __debugbreak();
#elif defined(__GNUC__) && (defined(__x86_64__) || defined(__i386__))
        __asm__ volatile("int3");
#elif defined(__GNUC__) && defined(__aarch64__)
        __asm__ volatile("brk #0");
#else
        return PROBE_NOT_ASKED;
#endif
        return 0;
    }
    if (strcmp(question, "stack") == 0)
    {
        return probe_descend(0);
    }
    if (strcmp(question, "abort") == 0)
    {
        abort();
    }
    if (strcmp(question, "hang") == 0)
    {
        for (;;)
        {
            probe_pause_second();
        }
    }
    fprintf(stderr, "interface_probe: no question \"%s\"\n", question);
    return PROBE_UNKNOWN;
}
