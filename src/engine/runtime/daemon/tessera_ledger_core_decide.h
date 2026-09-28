// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_ledger_core_decide.h: release, idle, start, shadow, admission and calls (tessera_ledger_core.h includes the
// parts in order)
#ifndef TESSERA_LEDGER_CORE_DECIDE_H
#define TESSERA_LEDGER_CORE_DECIDE_H

#include "tessera_ledger_core_heap.h"

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
    const int kept = (finished == 0) || (job->state != TESSERA_JOB_RUNNING) || (job->measures == 0ull) ||
                     tessera_core_history_keep(ledger, job, now);
    ledger->idle_microseconds = job->request.idle_microseconds;
    tessera_core_remove(ledger, job);
    if (ledger->job_count == 0ull)
    {
        ledger->idle_since = now;
        return tessera_core_heap_push(ledger, tessera_core_sum(now, ledger->idle_microseconds), 0ull,
                                      TESSERA_EVENT_IDLE) &&
               kept;
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
    const TesseraHistory *const previous = tessera_core_history(ledger, &job->request.signum);
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
    job->expected_end = (previous != NULL) ? tessera_core_sum(now, previous->duration) : TESSERA_FOREVER;
    job->next_sweep = next_sweep;
    *event = tessera_core_event(TESSERA_EVENT_ADMITTED, job->identity, job->reservation,
                                (previous != NULL) ? previous->peak : 0ull);
    return 1;
}

TESSERA_CORE int tessera_core_shadow(const TesseraLedger *ledger, unsigned long long wanted, long long headroom,
                                     unsigned long long *shadow, unsigned long long *spare)
{
    *shadow = 0ull;
    *spare = 0ull;
    long long available = headroom;
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
                available += (long long)tessera_core_blocked(job);
            }
        }
        after = soonest;
        // the wanted bytes are a device's bytes, below two to the sixty-third
        if (available >= (long long)wanted)
        {
            *shadow = soonest;
            // the capacity is at least the wanted bytes here, and the difference is not negative
            *spare = (unsigned long long)(available - (long long)wanted);
            return 1;
        }
    }
}

TESSERA_CORE unsigned long long tessera_core_admit(TesseraLedger *ledger, unsigned long long now, TesseraEvent *events,
                                                   unsigned long long start_limit)
{
    unsigned long long made = 0ull;
    TesseraJob *head = NULL;
    for (unsigned long long at = 0ull; (made < start_limit) && (at < ledger->job_count); at += 1ull)
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
    if ((head == NULL) || (made >= start_limit))
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
    for (unsigned long long at = head_at + 1ull; (made < start_limit) && (at < ledger->job_count); at += 1ull)
    {
        TesseraJob *const job = &ledger->jobs[at];
        const TesseraHistory *const previous = tessera_core_history(ledger, &job->request.signum);
        const unsigned long long needs = tessera_core_needs(ledger, job);
        // the needed bytes are a device's bytes, below two to the sixty-third
        const int fits = (long long)needs <= tessera_core_headroom(ledger);
        if ((job->state != TESSERA_JOB_WAITING) || (previous == NULL) || !fits)
        {
            continue;
        }
        const int before_shadow = tessera_core_sum(now, previous->duration) <= shadow;
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
            if ((ledger->job_count == 0ull) &&
                (tessera_core_sum(ledger->idle_since, ledger->idle_microseconds) == due.when))
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

// one call made of the ledger and answered: errored on whole, with nothing changed, where the ledger lacks room for the
// most the call could add, and otherwise the decision the call names, with the headroom after it
TESSERA_CORE void tessera_core_call(TesseraLedger *ledger, const TesseraCall *call, TesseraAnswer *answer)
{
    answer->result = 0ull;
    answer->full = 0;
    answer->identity = 0ull;
    answer->root.when = 0ull;
    answer->root.identity = 0ull;
    answer->root.kind = TESSERA_EVENT_NONE;
    for (unsigned int at = 0u; at < TESSERA_CALL_EVENTS; at += 1u)
    {
        answer->events[at] = tessera_core_event(TESSERA_EVENT_NONE, 0ull, 0ull, 0ull);
    }
    const TesseraCapacity needed = tessera_core_capacity(ledger, call->kind);
    if (!tessera_core_fits(ledger, &needed))
    {
        answer->full = 1;
        answer->headroom = tessera_core_headroom(ledger);
        return;
    }
    // each decision's 1 or 0 is widened to the answer's word, where an admit's count of jobs started converts exactly
    switch (call->kind)
    {
    case TESSERA_CALL_DEVICE:
        tessera_core_device(ledger, call->capacity, call->in_use);
        answer->result = 1ull;
        break;
    case TESSERA_CALL_SUBMIT:
        answer->result = (unsigned long long)tessera_core_submit(ledger, &call->request, call->now, &answer->identity,
                                                                 &answer->events[0]);
        break;
    case TESSERA_CALL_OVERRIDE:
        answer->result = (unsigned long long)tessera_core_override(ledger, call->identity, call->now);
        break;
    case TESSERA_CALL_MEASURE:
        answer->result =
            (unsigned long long)tessera_core_measure(ledger, call->identity, call->used, &answer->events[0]);
        break;
    case TESSERA_CALL_RELEASE:
        answer->result = (unsigned long long)tessera_core_release(ledger, call->identity, call->now, call->finished);
        break;
    case TESSERA_CALL_ADMIT:
        answer->result =
            tessera_core_admit(ledger, call->now, answer->events,
                               (call->start_limit < TESSERA_CALL_EVENTS) ? call->start_limit : TESSERA_CALL_EVENTS);
        break;
    case TESSERA_CALL_FIRE:
        answer->result = (unsigned long long)tessera_core_fire(ledger, call->now, &answer->events[0]);
        break;
    case TESSERA_CALL_IDLE:
        answer->result = (unsigned long long)tessera_core_idle(ledger, call->now, call->idle_microseconds);
        break;
    case TESSERA_CALL_REMEMBER:
        answer->result = (unsigned long long)tessera_core_remember(ledger, &call->kept);
        break;
    case TESSERA_CALL_NEXT:
        answer->result = (unsigned long long)tessera_core_next(ledger, &answer->root);
        break;
    default:
        break;
    }
    answer->headroom = tessera_core_headroom(ledger);
}

#endif
