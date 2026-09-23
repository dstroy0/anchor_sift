/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_load_limit.h
 * @brief How much of a shared machine a bench is allowed to take.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note This machine is not a cluster node. The desktop, the browser and the operating system live
 *       on it while a bench runs, and a measurement that makes the machine unusable is a bad
 *       measurement however good its numbers are.
 * @note Cores minus one was the standing rule and it is not enough on its own. A bench holding
 *       fifteen of sixteen threads at normal priority with a four gigabyte working set starves the
 *       interactive session even though one core is nominally free, because the contention is for
 *       memory bandwidth and for scheduler turns and not for cores.
 * @note So two things and not one. The worker count leaves real headroom, and the process runs
 *       below normal priority so that anything the user does preempts it. Below normal costs a
 *       long run almost nothing when the machine is otherwise idle, since an idle machine has no
 *       higher-priority work to give the turns to.
 */

#ifndef BENCH_LOAD_LIMIT_H
#define BENCH_LOAD_LIMIT_H

#include <cstdint>
#include <cstdlib>
#include <thread>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

/**
 * @brief Drops this process below normal priority so interactive work preempts it.
 *
 * @note Called once at the top of a bench. Failure is ignored deliberately: a bench that cannot
 *       lower its own priority should still run, it should just be noted that it will be ruder.
 */
static inline void bench_lower_priority(void)
{
#ifdef _WIN32
    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
#endif
}

/**
 * @brief How many bytes a bench may allocate, measured once at launch.
 *
 * @return Bytes the bench is allowed to take, or zero where it cannot be determined.
 * @note Eighty percent of what was free when the process started, not eighty percent of what is
 *       free now. Sampling it later would let a bench grow into memory something else released and
 *       then refuse to give it back, and it would make the limit depend on when it was asked.
 * @note A bench that wants more than this says so and skips the pass. Allocating past the limit and
 *       letting the machine page defeats the measurement, because a paged run produces a number
 *       nobody can trust the timing of and a desktop nobody can use.
 */
static inline uint64_t bench_memory_budget(void)
{
#ifdef _WIN32
    static uint64_t settled = 0u;
    if (settled == 0u)
    {
        MEMORYSTATUSEX status;
        status.dwLength = sizeof(status);
        if (GlobalMemoryStatusEx(&status) != 0)
        {
            settled = (uint64_t)((double)status.ullAvailPhys * 0.80);
        }
    }
    return settled;
#else
    return 0u;
#endif
}

/**
 * @brief How many worker threads a bench should start on this machine.
 *
 * @param[in] requested Zero to choose, or an explicit count the caller was given.
 * @return              Worker count, at least one.
 * @note The default keeps a quarter of the machine, rounded up to at least two cores, out of the
 *       bench's hands. On sixteen logical cores that is twelve workers and not fifteen, which
 *       costs a fifth of the throughput and is the difference between a machine that is slow and a
 *       machine that is unusable.
 * @note BENCH_THREADS overrides it, and a run on an idle machine can still take everything without
 *       the number being edited into a file.
 */
static inline unsigned bench_worker_count(unsigned requested)
{
    if (requested > 0u)
    {
        return requested;
    }

    const char *const asked = std::getenv("BENCH_THREADS");
    if (asked != nullptr)
    {
        const unsigned long parsed = std::strtoul(asked, nullptr, 10);
        if (parsed > 0ul)
        {
            return (unsigned)parsed;
        }
    }

    const unsigned present = std::thread::hardware_concurrency();
    if (present <= 2u)
    {
        return 1u;
    }

    const unsigned reserved = (present / 4u) > 2u ? (present / 4u) : 2u;
    return present - reserved;
}

#endif
