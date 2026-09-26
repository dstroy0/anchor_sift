// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_burn <threads> <milliseconds> <exit code>: spins that many threads for that long, prints the processors and
// the priority it ran on, and exits with the code given; run.sh reads what tessera_run set on its command from these
#if !defined(_WIN32)
// threads, the affinity mask and the clock are outside strict C11
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <pthread.h>
#include <sched.h>
#include <sys/resource.h>
#include <time.h>
#endif

#define BURN_THREADS_MOST 64u

static unsigned long long burn_now(void)
{
#if defined(_WIN32)
    return GetTickCount64();
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    // a monotonic clock's seconds and nanoseconds are not negative
    return ((unsigned long long)now.tv_sec * 1000ull) + ((unsigned long long)now.tv_nsec / 1000000ull);
#endif
}

static unsigned long long s_burn_until;

#if defined(_WIN32)
static DWORD WINAPI burn_spin(LPVOID unused)
#else
static void *burn_spin(void *unused)
#endif
{
    (void)unused;
    volatile unsigned long long turns = 0ull;
    while (burn_now() < s_burn_until)
    {
        turns = turns + 1ull;
    }
#if defined(_WIN32)
    return 0u;
#else
    return NULL;
#endif
}

int main(int count, char **arguments)
{
    if (count != 4)
    {
        fputs("  tessera_burn: <threads> <milliseconds> <exit code>\n", stderr);
        return 2;
    }
    const unsigned long long threads = strtoull(arguments[1], NULL, 10);
    const unsigned long long milliseconds = strtoull(arguments[2], NULL, 10);
    const int code = atoi(arguments[3]);
    if ((threads == 0ull) || (threads > BURN_THREADS_MOST))
    {
        fputs("  tessera_burn: 1 to 64 threads\n", stderr);
        return 2;
    }
    unsigned long long mask = 0ull;
    int below_normal = 0;
#if defined(_WIN32)
    DWORD_PTR process_mask = 0u;
    DWORD_PTR system_mask = 0u;
    GetProcessAffinityMask(GetCurrentProcess(), &process_mask, &system_mask);
    // the machine word's mask widens whole
    mask = (unsigned long long)process_mask;
    below_normal = GetPriorityClass(GetCurrentProcess()) == BELOW_NORMAL_PRIORITY_CLASS;
#else
    cpu_set_t set;
    CPU_ZERO(&set);
    sched_getaffinity(0, sizeof(set), &set);
    for (unsigned int processor = 0u; processor < 64u; processor += 1u)
    {
        mask |= CPU_ISSET(processor, &set) ? (1ull << processor) : 0ull;
    }
    below_normal = getpriority(PRIO_PROCESS, 0) > 0;
#endif
    printf("  tessera_burn: processors 0x%llx, below normal %d\n", mask, below_normal);
    fflush(stdout);
    s_burn_until = burn_now() + milliseconds;
#if defined(_WIN32)
    HANDLE spinning[BURN_THREADS_MOST];
    for (unsigned long long at = 0ull; at < threads; at += 1ull)
    {
        spinning[at] = CreateThread(NULL, 0u, burn_spin, NULL, 0u, NULL);
    }
    for (unsigned long long at = 0ull; at < threads; at += 1ull)
    {
        if (spinning[at] != NULL)
        {
            WaitForSingleObject(spinning[at], INFINITE);
            CloseHandle(spinning[at]);
        }
    }
#else
    pthread_t spinning[BURN_THREADS_MOST];
    int made[BURN_THREADS_MOST];
    for (unsigned long long at = 0ull; at < threads; at += 1ull)
    {
        made[at] = pthread_create(&spinning[at], NULL, burn_spin, NULL) == 0;
    }
    for (unsigned long long at = 0ull; at < threads; at += 1ull)
    {
        if (made[at])
        {
            pthread_join(spinning[at], NULL);
        }
    }
#endif
    return code;
}
