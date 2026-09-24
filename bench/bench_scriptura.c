// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#if !defined(_MSC_VER)
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "scriptura_arm.h"

#if defined(__x86_64__) || defined(__i386__)
#include <x86intrin.h>
#define TICKS_ARE_CYCLES 1
#elif defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#include <intrin.h>
#define TICKS_ARE_CYCLES 1
#else
#include <time.h>
#define TICKS_ARE_CYCLES 0
#endif

#define BENCH_ALIGN 64u
#define BENCH_LARGEST 1048576u
#define BENCH_SHIFT 64u
#define BENCH_BUFFER (BENCH_LARGEST + 4096u)
#define BENCH_TRIALS 7u
#define BENCH_WORK 4194304ull
#define BENCH_SIZES 9u
#define BENCH_CANDIDATES 7u
#define BENCH_OPERATIONS 6u
#define BENCH_PLANTED 0x80u
#define BENCH_FILLED 0x3Cu
#define BENCH_ROOM 65536ull

static _Alignas(BENCH_ALIGN) unsigned char bench_source[BENCH_BUFFER];
static _Alignas(BENCH_ALIGN) unsigned char bench_other[BENCH_BUFFER];
static _Alignas(BENCH_ALIGN) unsigned char bench_target[BENCH_BUFFER];

static const unsigned long long bench_sizes[BENCH_SIZES] = {16ull,   32ull,    64ull,     256ull,   1024ull,
                                                             4096ull, 16384ull, 262144ull, 1048576ull};

static const char *const bench_operation_names[BENCH_OPERATIONS] = {"length vs strnlen", "find vs memchr",
                                                                     "copy vs memcpy",    "move_up vs memmove",
                                                                     "compare vs memcmp", "fill vs memset"};

static volatile unsigned long long bench_sink;

static unsigned long long bench_ticks(void)
{
#if TICKS_ARE_CYCLES
#if defined(_MSC_VER)
    _ReadWriteBarrier();
    // the time stamp counter is read as the unsigned count it is
    const unsigned long long taken = (unsigned long long)__rdtsc();
    _ReadWriteBarrier();
    return taken;
#else
    __asm__ __volatile__("" ::: "memory");
    // the time stamp counter is read as the unsigned count it is
    const unsigned long long taken = (unsigned long long)__rdtsc();
    __asm__ __volatile__("" ::: "memory");
    return taken;
#endif
#else
    struct timespec taken;
    (void)clock_gettime(CLOCK_MONOTONIC, &taken);
    // seconds and nanoseconds since an arbitrary start are non-negative
    return ((unsigned long long)taken.tv_sec * 1000000000ull) + (unsigned long long)taken.tv_nsec;
#endif
}

static unsigned long long bench_crt_length(const char *text, unsigned long long room)
{
    // the room is at most the bench buffer, which a size_t holds
    return (unsigned long long)strnlen(text, (size_t)room);
}

static unsigned long long bench_crt_find(const void *from, unsigned char value, unsigned long long bytes)
{
    // the byte count is at most the bench buffer, which a size_t holds
    const unsigned char *const found = (const unsigned char *)memchr(from, value, (size_t)bytes);
    // the match lies inside the region, so its offset from the start is non-negative
    return (found == NULL) ? bytes : (unsigned long long)(found - (const unsigned char *)from);
}

static void bench_crt_copy(void *to, const void *from, unsigned long long bytes)
{
    // the byte count is at most the bench buffer, which a size_t holds
    memcpy(to, from, (size_t)bytes);
}

static void bench_crt_move_up(void *to, const void *from, unsigned long long bytes)
{
    // the byte count is at most the bench buffer, which a size_t holds
    memmove(to, from, (size_t)bytes);
}

static int bench_crt_compare(const void *one, const void *other, unsigned long long bytes)
{
    // the byte count is at most the bench buffer, which a size_t holds
    const int order = memcmp(one, other, (size_t)bytes);
    return (order < 0) ? -1 : ((order > 0) ? 1 : 0);
}

static void bench_crt_fill(void *to, unsigned char value, unsigned long long bytes)
{
    // the byte count is at most the bench buffer, which a size_t holds
    memset(to, value, (size_t)bytes);
}

static const ScripturaArm bench_crt_arm = {"crt",           0ull,
                                           bench_crt_length, bench_crt_find,
                                           bench_crt_copy,   bench_crt_move_up,
                                           bench_crt_compare, bench_crt_fill};

static const ScripturaArm bench_dispatch_arm = {"dispatch",        0ull,
                                                scriptura_length,  scriptura_find,
                                                scriptura_copy,    scriptura_move_up,
                                                scriptura_compare, scriptura_fill};

static void bench_lay(unsigned long long size)
{
    for (unsigned long long at = 0ull; at < BENCH_BUFFER; at += 1ull)
    {
        // the top eight bits of the product are one byte, and the low bit is set so no byte is zero or planted
        const unsigned char held = (unsigned char)((((at + 1ull) * 0x9E3779B97F4A7C15ull) >> 56u) | 1ull);
        bench_source[at] = held;
        bench_other[at] = held;
        bench_target[at] = held;
    }
    bench_source[size - 1ull] = BENCH_PLANTED;
    bench_other[size] = 0u;
}

static unsigned long long bench_run(const ScripturaArm *arm, unsigned int operation, unsigned long long size,
                                    unsigned long long repeats)
{
    unsigned long long held = 0ull;
    for (unsigned long long repeat = 0ull; repeat < repeats; repeat += 1ull)
    {
        if (operation == 0u)
        {
            // the text buffer is read as the characters it holds
            held += arm->length((const char *)bench_other, size);
        }
        else if (operation == 1u)
        {
            held += arm->find(bench_source, BENCH_PLANTED, size);
        }
        else if (operation == 2u)
        {
            arm->copy(bench_target, bench_source, size);
            held += bench_target[size - 1ull];
        }
        else if (operation == 3u)
        {
            arm->move_up(bench_target + BENCH_SHIFT, bench_target, size);
            held += bench_target[BENCH_SHIFT];
        }
        else if (operation == 4u)
        {
            // the order is -1, 0 or 1, and one more than it is non-negative
            held += (unsigned long long)(arm->compare(bench_other, bench_target, size) + 1);
        }
        else
        {
            arm->fill(bench_target, BENCH_FILLED, size);
            held += bench_target[size - 1ull];
        }
    }
    return held;
}

static unsigned long long bench_measure(const ScripturaArm *arm, unsigned int operation, unsigned long long size)
{
    const unsigned long long repeats = (BENCH_WORK / size) + 1ull;
    unsigned long long best = 0xFFFFFFFFFFFFFFFFull;
    for (unsigned int trial = 0u; trial < BENCH_TRIALS; trial += 1u)
    {
        bench_lay(size);
        const unsigned long long started = bench_ticks();
        bench_sink = bench_run(arm, operation, size, repeats);
        const unsigned long long taken = bench_ticks() - started;
        best = (taken < best) ? taken : best;
    }
    return ((best * 1000ull) / repeats);
}

int main(void)
{
    const ScripturaArm *const candidates[BENCH_CANDIDATES] = {&bench_crt_arm,       &bench_dispatch_arm,
                                                              scriptura_portable_arm(), scriptura_avx2_arm(),
                                                              scriptura_avx512_arm(), scriptura_neon_arm(),
                                                              scriptura_sve_arm()};
    ScripturaLine line = {(char *)malloc((size_t)BENCH_ROOM), BENCH_ROOM, 0ull};
    if (line.out == NULL)
    {
        return 2;
    }
    scriptura_text(&line, (TICKS_ARE_CYCLES != 0) ? "bench_scriptura: time stamp ticks per thousand calls, best of "
                                                  : "bench_scriptura: nanoseconds per thousand calls, best of ");
    scriptura_decimal(&line, BENCH_TRIALS, 1u);
    scriptura_text(&line, ", 64 byte aligned, dispatch chose ");
    scriptura_text(&line, scriptura_arm());
    scriptura_text(&line, "\n  per arm: per thousand calls, then permille of the crt in brackets\n");
    for (unsigned int operation = 0u; operation < BENCH_OPERATIONS; operation += 1u)
    {
        scriptura_character(&line, '\n');
        scriptura_text(&line, bench_operation_names[operation]);
        scriptura_character(&line, '\n');
        scriptura_text_columns(&line, "bytes", 10u);
        for (unsigned int index = 0u; index < BENCH_CANDIDATES; index += 1u)
        {
            if (candidates[index] != NULL)
            {
                scriptura_text_columns(&line, candidates[index]->name, 22u);
            }
        }
        scriptura_character(&line, '\n');
        for (unsigned int size_index = 0u; size_index < BENCH_SIZES; size_index += 1u)
        {
            const unsigned long long size = bench_sizes[size_index];
            scriptura_decimal_columns(&line, size, 9u);
            scriptura_character(&line, ' ');
            const unsigned long long crt = bench_measure(&bench_crt_arm, operation, size);
            for (unsigned int index = 0u; index < BENCH_CANDIDATES; index += 1u)
            {
                const ScripturaArm *const arm = candidates[index];
                if (arm == NULL)
                {
                    continue;
                }
                const unsigned long long taken = (index == 0u) ? crt : bench_measure(arm, operation, size);
                const unsigned long long permille = (crt == 0ull) ? 0ull : ((taken * 1000ull) / crt);
                scriptura_decimal_columns(&line, taken, 12u);
                scriptura_text(&line, " [");
                scriptura_decimal_columns(&line, permille, 5u);
                scriptura_text(&line, "]  ");
            }
            scriptura_character(&line, '\n');
        }
    }
    const int written = scriptura_write(&line, stdout);
    free(line.out);
    return (written != 0) ? 0 : 1;
}
