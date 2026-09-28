// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_ledger_core_heap.h: events, sums, the heap, headroom and history (tessera_ledger_core.h includes the parts in
// order)
#ifndef TESSERA_LEDGER_CORE_HEAP_H
#define TESSERA_LEDGER_CORE_HEAP_H

// tessera's ledger decisions as one source the host and the device both compile. There are two tesseras: the host's
// daemon (tessera_daemon_*.c) runs them through tessera_ledger.c over arrays it grows, with no CUDA context of its own,
// and the device's tessera (tessera_device.cu) runs them in one thread over arrays it laid out in the device's memory.
// The core never grows an array. Each decision errors where an array it needs is full, as the host's errored where a
// an array did not grow, and tessera_core_call errors on a call before it changes anything where the ledger lacks room
// for the most the call could add: the caller grows the arrays and makes the call again, which decides the same

#include "tessera_ledger.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define TESSERA_CORE __host__ __device__ static inline
#else
#define TESSERA_CORE static inline
#endif

#define TESSERA_FOREVER 0xFFFFFFFFFFFFFFFFull

// the most a call can add to each of a ledger's arrays: its jobs, its kept peaks and its deadlines
typedef struct
{
    unsigned long long jobs;
    unsigned long long history;
    unsigned long long heap;
} TesseraCapacity;

TESSERA_CORE TesseraEvent tessera_core_event(TesseraEventKind kind, unsigned long long identity,
                                             unsigned long long bytes, unsigned long long measured)
{
    const TesseraEvent event = {kind, identity, bytes, measured};
    return event;
}

TESSERA_CORE unsigned long long tessera_core_sum(unsigned long long left, unsigned long long right)
{
    return (right > (TESSERA_FOREVER - left)) ? TESSERA_FOREVER : (left + right);
}

// 1 where two signums are the same byte for byte
TESSERA_CORE int tessera_core_signum_same(const EngineSignum *left, const EngineSignum *right)
{
    int same = 1;
    for (unsigned int at = 0u; at < ENGINE_SIGNUM_BYTES; at += 1u)
    {
        same = same && (left->bytes[at] == right->bytes[at]);
    }
    return same;
}

// the arrays a ledger's call of `kind` can take: a job and a deadline for a submit, a kept peak and a deadline for a
// release, a deadline for an idle, a kept peak for a remember, and a deadline for each job an admit could start
TESSERA_CORE TesseraCapacity tessera_core_capacity(const TesseraLedger *ledger, TesseraCallKind kind)
{
    TesseraCapacity needed = {ledger->job_count, ledger->history_count, ledger->heap_count};
    needed.jobs += (kind == TESSERA_CALL_SUBMIT) ? 1ull : 0ull;
    needed.history += ((kind == TESSERA_CALL_RELEASE) || (kind == TESSERA_CALL_REMEMBER)) ? 1ull : 0ull;
    needed.heap += ((kind == TESSERA_CALL_SUBMIT) || (kind == TESSERA_CALL_RELEASE) || (kind == TESSERA_CALL_IDLE))
                       ? 1ull
                       : ((kind == TESSERA_CALL_ADMIT) ? ledger->job_count : 0ull);
    return needed;
}

// 1 where the ledger's arrays hold `needed`
TESSERA_CORE int tessera_core_fits(const TesseraLedger *ledger, const TesseraCapacity *needed)
{
    return (needed->jobs <= ledger->job_capacity) && (needed->history <= ledger->history_capacity) &&
           (needed->heap <= ledger->heap_capacity);
}

TESSERA_CORE int tessera_core_heap_push(TesseraLedger *ledger, unsigned long long when, unsigned long long identity,
                                        TesseraEventKind kind)
{
    if (ledger->heap_count >= ledger->heap_capacity)
    {
        return 0;
    }
    unsigned long long at = ledger->heap_count;
    ledger->heap_count += 1ull;
    while (at != 0ull)
    {
        const unsigned long long parent = (at - 1ull) / 2ull;
        if (ledger->heap[parent].when <= when)
        {
            break;
        }
        ledger->heap[at] = ledger->heap[parent];
        at = parent;
    }
    ledger->heap[at].when = when;
    ledger->heap[at].identity = identity;
    ledger->heap[at].kind = kind;
    return 1;
}

TESSERA_CORE void tessera_core_heap_pop(TesseraLedger *ledger)
{
    ledger->heap_count -= 1ull;
    const TesseraDeadline last = ledger->heap[ledger->heap_count];
    unsigned long long at = 0ull;
    for (;;)
    {
        const unsigned long long left = (2ull * at) + 1ull;
        if (left >= ledger->heap_count)
        {
            break;
        }
        const unsigned long long right = left + 1ull;
        const unsigned long long least =
            ((right < ledger->heap_count) && (ledger->heap[right].when < ledger->heap[left].when)) ? right : left;
        if (last.when <= ledger->heap[least].when)
        {
            break;
        }
        ledger->heap[at] = ledger->heap[least];
        at = least;
    }
    if (ledger->heap_count != 0ull)
    {
        ledger->heap[at] = last;
    }
}

TESSERA_CORE TesseraJob *tessera_core_find(const TesseraLedger *ledger, unsigned long long identity)
{
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        if (ledger->jobs[at].identity == identity)
        {
            return &ledger->jobs[at];
        }
    }
    return NULL;
}

TESSERA_CORE void tessera_core_remove(TesseraLedger *ledger, const TesseraJob *job)
{
    // the job points into the array, and its distance from the start is its index
    const unsigned long long at = (unsigned long long)(job - ledger->jobs);
    for (unsigned long long next = at + 1ull; next < ledger->job_count; next += 1ull)
    {
        ledger->jobs[next - 1ull] = ledger->jobs[next];
    }
    ledger->job_count -= 1ull;
}

TESSERA_CORE unsigned long long tessera_core_blocked(const TesseraJob *job)
{
    return (job->reservation > job->used) ? job->reservation : job->used;
}

TESSERA_CORE unsigned long long tessera_core_unallocated(const TesseraJob *job)
{
    return (job->reservation > job->used) ? (job->reservation - job->used) : 0ull;
}

TESSERA_CORE void tessera_core_device(TesseraLedger *ledger, unsigned long long capacity, unsigned long long in_use)
{
    ledger->capacity = capacity;
    ledger->in_use = in_use;
}

TESSERA_CORE long long tessera_core_headroom(const TesseraLedger *ledger)
{
    unsigned long long owed = 0ull;
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        if (ledger->jobs[at].state == TESSERA_JOB_RUNNING)
        {
            owed = tessera_core_sum(owed, tessera_core_unallocated(&ledger->jobs[at]));
        }
    }
    const unsigned long long taken = tessera_core_sum(ledger->in_use, owed);
    // a device's bytes and every sum here stay below two to the sixty-third, and each difference is exact signed
    return (taken <= ledger->capacity) ? (long long)(ledger->capacity - taken) : -(long long)(taken - ledger->capacity);
}

TESSERA_CORE const TesseraHistory *tessera_core_history(const TesseraLedger *ledger, const EngineSignum *signum)
{
    for (unsigned long long at = 0ull; at < ledger->history_count; at += 1ull)
    {
        if (tessera_core_signum_same(&ledger->history[at].signum, signum))
        {
            return &ledger->history[at];
        }
    }
    return NULL;
}

// a job is reserved its whole declaration, the bytes its process held as it asked and the bytes it declares on top,
// or its signum's kept peak when that is more: the capacity it will take is reserved from its start and not only once a
// sweep has seen it grow
TESSERA_CORE unsigned long long tessera_core_wants(const TesseraLedger *ledger, const TesseraJob *job)
{
    const TesseraHistory *const previous = tessera_core_history(ledger, &job->request.signum);
    const unsigned long long total = tessera_core_sum(job->request.standing, job->request.declared);
    return ((previous != NULL) && (previous->peak > total)) ? previous->peak : total;
}

// the bytes a waiting job has yet to find on the device: what it wants less what its process already holds there,
// which the device's measured use counts
TESSERA_CORE unsigned long long tessera_core_needs(const TesseraLedger *ledger, const TesseraJob *job)
{
    const unsigned long long wants = tessera_core_wants(ledger, job);
    return (wants > job->request.standing) ? (wants - job->request.standing) : 0ull;
}

TESSERA_CORE int tessera_core_submit(TesseraLedger *ledger, const TesseraJobRequest *request, unsigned long long now,
                                     unsigned long long *identity, TesseraEvent *event)
{
    *event = tessera_core_event(TESSERA_EVENT_NONE, 0ull, 0ull, 0ull);
    if ((request->declared == 0ull) || (ledger->job_count >= ledger->job_capacity))
    {
        return 0;
    }
    const TesseraHistory *const previous = tessera_core_history(ledger, &request->signum);
    const int over = (previous != NULL) && (request->declared > previous->peak) && (request->override_budget == 0u);
    TesseraJob *const job = &ledger->jobs[ledger->job_count];
    job->identity = ledger->next_identity;
    job->request = *request;
    job->state = over ? TESSERA_JOB_HELD : TESSERA_JOB_WAITING;
    job->reservation = 0ull;
    job->used = 0ull;
    job->peak = 0ull;
    job->measures = 0ull;
    job->submitted = now;
    job->started = 0ull;
    job->expected_end = 0ull;
    job->hold_until = over ? tessera_core_sum(now, request->holding_microseconds) : 0ull;
    job->next_sweep = 0ull;
    if (over && !tessera_core_heap_push(ledger, job->hold_until, job->identity, TESSERA_EVENT_LOST))
    {
        return 0;
    }
    ledger->job_count += 1ull;
    ledger->next_identity += 1ull;
    *identity = job->identity;
    *event = tessera_core_event(over ? TESSERA_EVENT_ASKED : TESSERA_EVENT_NONE, job->identity, request->declared,
                                (previous != NULL) ? previous->peak : 0ull);
    return 1;
}

TESSERA_CORE int tessera_core_override(TesseraLedger *ledger, unsigned long long identity, unsigned long long now)
{
    TesseraJob *const job = tessera_core_find(ledger, identity);
    if ((job == NULL) || (job->state != TESSERA_JOB_HELD) || (now > job->hold_until))
    {
        return 0;
    }
    job->state = TESSERA_JOB_WAITING;
    job->request.override_budget = 1u;
    return 1;
}

TESSERA_CORE int tessera_core_measure(TesseraLedger *ledger, unsigned long long identity, unsigned long long used,
                                      TesseraEvent *event)
{
    *event = tessera_core_event(TESSERA_EVENT_NONE, 0ull, 0ull, 0ull);
    TesseraJob *const job = tessera_core_find(ledger, identity);
    if ((job == NULL) || (job->state != TESSERA_JOB_RUNNING))
    {
        return 0;
    }
    job->used = used;
    job->peak = (used > job->peak) ? used : job->peak;
    job->measures += 1ull;
    if (used > job->reservation)
    {
        job->reservation = used;
        *event = tessera_core_event(TESSERA_EVENT_GREW, identity, job->request.declared, used);
    }
    return 1;
}

TESSERA_CORE int tessera_core_remember(TesseraLedger *ledger, const TesseraHistory *kept)
{
    for (unsigned long long at = 0ull; at < ledger->history_count; at += 1ull)
    {
        if (tessera_core_signum_same(&ledger->history[at].signum, &kept->signum))
        {
            ledger->history[at] = *kept;
            return 1;
        }
    }
    if (ledger->history_count >= ledger->history_capacity)
    {
        return 0;
    }
    ledger->history[ledger->history_count] = *kept;
    ledger->history_count += 1ull;
    return 1;
}

#endif
