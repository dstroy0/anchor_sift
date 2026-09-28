// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_LEDGER_CORE_H
#define TESSERA_LEDGER_CORE_H

// tessera's ledger decisions as one source the host and the device both compile. There are two tesseras: the host's
// daemon (tessera_daemon.c) runs them through tessera_ledger.c over rooms it grows, with no CUDA context of its own,
// and the device's tessera (tessera_device.cu) runs them in one thread over rooms it laid in the device's memory.
// The core never grows a room. Each decision refuses where a room it needs is full, as the host's refused where a
// room did not grow, and tessera_core_call refuses a call before it changes anything where the ledger lacks room
// for the most the call could add: the caller grows the rooms and makes the call again, which decides the same

#include "tessera_ledger.h"

#include <stddef.h>

#if defined(__CUDACC__)
#define TESSERA_CORE __host__ __device__ static inline
#else
#define TESSERA_CORE static inline
#endif

#define TESSERA_FOREVER 0xFFFFFFFFFFFFFFFFull

// the most a call can add to each of a ledger's rooms: its jobs, its kept peaks and its deadlines
typedef struct
{
    unsigned long long jobs;
    unsigned long long history;
    unsigned long long heap;
} TesseraRooms;

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

// the rooms a ledger's call of `kind` can take: a job and a deadline for a submit, a kept peak and a deadline for a
// release, a deadline for an idle, a kept peak for a remember, and a deadline for each job an admit could start
TESSERA_CORE TesseraRooms tessera_core_rooms(const TesseraLedger *ledger, TesseraCallKind kind)
{
    TesseraRooms rooms = {ledger->job_count, ledger->history_count, ledger->heap_count};
    rooms.jobs += (kind == TESSERA_CALL_SUBMIT) ? 1ull : 0ull;
    rooms.history += ((kind == TESSERA_CALL_RELEASE) || (kind == TESSERA_CALL_REMEMBER)) ? 1ull : 0ull;
    rooms.heap += ((kind == TESSERA_CALL_SUBMIT) || (kind == TESSERA_CALL_RELEASE) || (kind == TESSERA_CALL_IDLE))
                      ? 1ull
                      : ((kind == TESSERA_CALL_ADMIT) ? ledger->job_count : 0ull);
    return rooms;
}

// 1 where the ledger's rooms hold `rooms`
TESSERA_CORE int tessera_core_fits(const TesseraLedger *ledger, const TesseraRooms *rooms)
{
    return (rooms->jobs <= ledger->job_room) && (rooms->history <= ledger->history_room)
        && (rooms->heap <= ledger->heap_room);
}

TESSERA_CORE int tessera_core_heap_push(TesseraLedger *ledger, unsigned long long when, unsigned long long identity,
                                        TesseraEventKind kind)
{
    if (ledger->heap_count >= ledger->heap_room)
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
        const unsigned long long least
            = ((right < ledger->heap_count) && (ledger->heap[right].when < ledger->heap[left].when)) ? right : left;
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
// or its signum's kept peak when that is more: the room it will take is held from its start and not only once a
// sweep has seen it grow
TESSERA_CORE unsigned long long tessera_core_wants(const TesseraLedger *ledger, const TesseraJob *job)
{
    const TesseraHistory *const past = tessera_core_history(ledger, &job->request.signum);
    const unsigned long long whole = tessera_core_sum(job->request.standing, job->request.declared);
    return ((past != NULL) && (past->peak > whole)) ? past->peak : whole;
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
    if ((request->declared == 0ull) || (ledger->job_count >= ledger->job_room))
    {
        return 0;
    }
    const TesseraHistory *const past = tessera_core_history(ledger, &request->signum);
    const int over = (past != NULL) && (request->declared > past->peak) && (request->override_budget == 0u);
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
                                (past != NULL) ? past->peak : 0ull);
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
    if (ledger->history_count >= ledger->history_room)
    {
        return 0;
    }
    ledger->history[ledger->history_count] = *kept;
    ledger->history_count += 1ull;
    return 1;
}

TESSERA_CORE int tessera_core_history_keep(TesseraLedger *ledger, const TesseraJob *job, unsigned long long now)
{
    TesseraHistory kept;
    kept.signum = job->request.signum;
    kept.peak = job->peak;
    kept.duration = now - job->started;
    return tessera_core_remember(ledger, &kept);
}

TESSERA_CORE int tessera_core_release(TesseraLedger *ledger, unsigned long long identity, unsigned long long now,
                                      int finished)
{
    TesseraJob *const job = tessera_core_find(ledger, identity);
    if (job == NULL)
    {
        return 0;
    }
    const int kept = (finished == 0) || (job->state != TESSERA_JOB_RUNNING) || (job->measures == 0ull)
                  || tessera_core_history_keep(ledger, job, now);
    ledger->idle_microseconds = job->request.idle_microseconds;
    tessera_core_remove(ledger, job);
    if (ledger->job_count == 0ull)
    {
        ledger->idle_since = now;
        return tessera_core_heap_push(ledger, tessera_core_sum(now, ledger->idle_microseconds), 0ull,
                                      TESSERA_EVENT_IDLE)
            && kept;
    }
    return kept;
}

TESSERA_CORE int tessera_core_idle(TesseraLedger *ledger, unsigned long long now, unsigned long long idle_microseconds)
{
    if (ledger->job_count != 0ull)
    {
        return 0;
    }
    ledger->idle_since = now;
    ledger->idle_microseconds = idle_microseconds;
    return tessera_core_heap_push(ledger, tessera_core_sum(now, idle_microseconds), 0ull, TESSERA_EVENT_IDLE);
}

TESSERA_CORE int tessera_core_start(TesseraLedger *ledger, TesseraJob *job, unsigned long long now, TesseraEvent *event)
{
    const TesseraHistory *const past = tessera_core_history(ledger, &job->request.signum);
    const unsigned long long next_sweep = tessera_core_sum(now, job->request.sweep_microseconds);
    if (!tessera_core_heap_push(ledger, next_sweep, job->identity, TESSERA_EVENT_SWEEP))
    {
        return 0;
    }
    job->state = TESSERA_JOB_RUNNING;
    job->reservation = tessera_core_wants(ledger, job);
    // until its first sweep the job uses what its process held as it asked, which the device's measure already
    // counts: the headroom owes the device only the bytes it has yet to find
    job->used = job->request.standing;
    job->peak = 0ull;
    job->measures = 0ull;
    job->started = now;
    job->expected_end = (past != NULL) ? tessera_core_sum(now, past->duration) : TESSERA_FOREVER;
    job->next_sweep = next_sweep;
    *event = tessera_core_event(TESSERA_EVENT_ADMITTED, job->identity, job->reservation,
                                (past != NULL) ? past->peak : 0ull);
    return 1;
}

TESSERA_CORE int tessera_core_shadow(const TesseraLedger *ledger, unsigned long long wanted, long long headroom,
                                     unsigned long long *shadow, unsigned long long *spare)
{
    *shadow = 0ull;
    *spare = 0ull;
    long long room = headroom;
    unsigned long long after = 0ull;
    for (;;)
    {
        unsigned long long soonest = TESSERA_FOREVER;
        for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
        {
            const TesseraJob *const job = &ledger->jobs[at];
            if ((job->state == TESSERA_JOB_RUNNING) && (job->expected_end > after) && (job->expected_end < soonest))
            {
                soonest = job->expected_end;
            }
        }
        if (soonest == TESSERA_FOREVER)
        {
            return 0;
        }
        for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
        {
            const TesseraJob *const job = &ledger->jobs[at];
            if ((job->state == TESSERA_JOB_RUNNING) && (job->expected_end == soonest))
            {
                // a job's blocked bytes are a device's bytes, below two to the sixty-third
                room += (long long)tessera_core_blocked(job);
            }
        }
        after = soonest;
        // the wanted bytes are a device's bytes, below two to the sixty-third
        if (room >= (long long)wanted)
        {
            *shadow = soonest;
            // the room is at least the wanted bytes here, and the difference is not negative
            *spare = (unsigned long long)(room - (long long)wanted);
            return 1;
        }
    }
}

TESSERA_CORE unsigned long long tessera_core_admit(TesseraLedger *ledger, unsigned long long now, TesseraEvent *events,
                                                   unsigned long long room)
{
    unsigned long long made = 0ull;
    TesseraJob *head = NULL;
    for (unsigned long long at = 0ull; (made < room) && (at < ledger->job_count); at += 1ull)
    {
        TesseraJob *const job = &ledger->jobs[at];
        if (job->state != TESSERA_JOB_WAITING)
        {
            continue;
        }
        // the needed bytes are a device's bytes, below two to the sixty-third
        if ((long long)tessera_core_needs(ledger, job) <= tessera_core_headroom(ledger))
        {
            if (!tessera_core_start(ledger, job, now, &events[made]))
            {
                return made;
            }
            made += 1ull;
            continue;
        }
        head = job;
        break;
    }
    if ((head == NULL) || (made >= room))
    {
        return made;
    }
    unsigned long long shadow = 0ull;
    unsigned long long spare = 0ull;
    if (!tessera_core_shadow(ledger, tessera_core_needs(ledger, head), tessera_core_headroom(ledger), &shadow, &spare))
    {
        return made;
    }
    // the head points into the array, and its distance from the start is its index
    const unsigned long long head_at = (unsigned long long)(head - ledger->jobs);
    for (unsigned long long at = head_at + 1ull; (made < room) && (at < ledger->job_count); at += 1ull)
    {
        TesseraJob *const job = &ledger->jobs[at];
        const TesseraHistory *const past = tessera_core_history(ledger, &job->request.signum);
        const unsigned long long needs = tessera_core_needs(ledger, job);
        // the needed bytes are a device's bytes, below two to the sixty-third
        const int fits = (long long)needs <= tessera_core_headroom(ledger);
        if ((job->state != TESSERA_JOB_WAITING) || (past == NULL) || !fits)
        {
            continue;
        }
        const int before_shadow = tessera_core_sum(now, past->duration) <= shadow;
        const int in_spare = needs <= spare;
        if (!before_shadow && !in_spare)
        {
            continue;
        }
        spare -= (!before_shadow) ? needs : 0ull;
        if (!tessera_core_start(ledger, job, now, &events[made]))
        {
            return made;
        }
        made += 1ull;
    }
    return made;
}

TESSERA_CORE int tessera_core_next(const TesseraLedger *ledger, TesseraDeadline *root)
{
    if (ledger->heap_count == 0ull)
    {
        return 0;
    }
    *root = ledger->heap[0];
    return 1;
}

TESSERA_CORE int tessera_core_fire(TesseraLedger *ledger, unsigned long long now, TesseraEvent *event)
{
    *event = tessera_core_event(TESSERA_EVENT_NONE, 0ull, 0ull, 0ull);
    while ((ledger->heap_count != 0ull) && (ledger->heap[0].when <= now))
    {
        const TesseraDeadline due = ledger->heap[0];
        tessera_core_heap_pop(ledger);
        if (due.kind == TESSERA_EVENT_IDLE)
        {
            if ((ledger->job_count == 0ull)
                && (tessera_core_sum(ledger->idle_since, ledger->idle_microseconds) == due.when))
            {
                event->kind = TESSERA_EVENT_IDLE;
                return 1;
            }
            continue;
        }
        TesseraJob *const job = tessera_core_find(ledger, due.identity);
        if (job == NULL)
        {
            continue;
        }
        if ((due.kind == TESSERA_EVENT_SWEEP) && (job->state == TESSERA_JOB_RUNNING) && (job->next_sweep == due.when))
        {
            job->next_sweep = tessera_core_sum(due.when, job->request.sweep_microseconds);
            event->kind = TESSERA_EVENT_SWEEP;
            event->identity = job->identity;
            return tessera_core_heap_push(ledger, job->next_sweep, job->identity, TESSERA_EVENT_SWEEP);
        }
        if ((due.kind == TESSERA_EVENT_LOST) && (job->state == TESSERA_JOB_HELD) && (job->hold_until == due.when))
        {
            *event = tessera_core_event(TESSERA_EVENT_LOST, job->identity, job->request.declared, 0ull);
            tessera_core_remove(ledger, job);
            return 1;
        }
    }
    return 0;
}

// one call made of the ledger and answered: refused whole, with nothing changed, where the ledger lacks room for the
// most the call could add, and otherwise the decision the call names, with the headroom after it
TESSERA_CORE void tessera_core_call(TesseraLedger *ledger, const TesseraCall *call, TesseraAnswer *answer)
{
    answer->held = 0ull;
    answer->full = 0;
    answer->identity = 0ull;
    answer->root.when = 0ull;
    answer->root.identity = 0ull;
    answer->root.kind = TESSERA_EVENT_NONE;
    for (unsigned int at = 0u; at < TESSERA_CALL_EVENTS; at += 1u)
    {
        answer->events[at] = tessera_core_event(TESSERA_EVENT_NONE, 0ull, 0ull, 0ull);
    }
    const TesseraRooms rooms = tessera_core_rooms(ledger, call->kind);
    if (!tessera_core_fits(ledger, &rooms))
    {
        answer->full = 1;
        answer->headroom = tessera_core_headroom(ledger);
        return;
    }
    // each decision's 1 or 0 is widened to the answer's word, where an admit's count of jobs started is held whole
    switch (call->kind)
    {
    case TESSERA_CALL_DEVICE:
        tessera_core_device(ledger, call->capacity, call->in_use);
        answer->held = 1ull;
        break;
    case TESSERA_CALL_SUBMIT:
        answer->held = (unsigned long long)tessera_core_submit(ledger, &call->request, call->now, &answer->identity,
                                                               &answer->events[0]);
        break;
    case TESSERA_CALL_OVERRIDE:
        answer->held = (unsigned long long)tessera_core_override(ledger, call->identity, call->now);
        break;
    case TESSERA_CALL_MEASURE:
        answer->held = (unsigned long long)tessera_core_measure(ledger, call->identity, call->used, &answer->events[0]);
        break;
    case TESSERA_CALL_RELEASE:
        answer->held = (unsigned long long)tessera_core_release(ledger, call->identity, call->now, call->finished);
        break;
    case TESSERA_CALL_ADMIT:
        answer->held = tessera_core_admit(ledger, call->now, answer->events,
                                          (call->room < TESSERA_CALL_EVENTS) ? call->room : TESSERA_CALL_EVENTS);
        break;
    case TESSERA_CALL_FIRE:
        answer->held = (unsigned long long)tessera_core_fire(ledger, call->now, &answer->events[0]);
        break;
    case TESSERA_CALL_IDLE:
        answer->held = (unsigned long long)tessera_core_idle(ledger, call->now, call->idle_microseconds);
        break;
    case TESSERA_CALL_REMEMBER:
        answer->held = (unsigned long long)tessera_core_remember(ledger, &call->kept);
        break;
    case TESSERA_CALL_NEXT:
        answer->held = (unsigned long long)tessera_core_next(ledger, &answer->root);
        break;
    default:
        break;
    }
    answer->headroom = tessera_core_headroom(ledger);
}

#endif
