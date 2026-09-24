// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera_ledger.h"

#include <stdlib.h>
#include <string.h>

#define TESSERA_FOREVER 0xFFFFFFFFFFFFFFFFull

static int tessera_grow(void **items, unsigned long long *room, unsigned long long count, size_t size)
{
    if (count < *room)
    {
        return 1;
    }
    const unsigned long long wanted = (*room == 0ull) ? 1ull : (*room * 2ull);
    void *const grown = realloc(*items, (size_t)wanted * size);
    if (grown == NULL)
    {
        return 0;
    }
    *items = grown;
    *room = wanted;
    return 1;
}

static unsigned long long tessera_sum(unsigned long long left, unsigned long long right)
{
    return (right > (TESSERA_FOREVER - left)) ? TESSERA_FOREVER : (left + right);
}

static int tessera_heap_push(TesseraLedger *ledger, unsigned long long when, unsigned long long identity,
                             TesseraEventKind kind)
{
    if (!tessera_grow((void **)&ledger->heap, &ledger->heap_room, ledger->heap_count, sizeof(TesseraDeadline)))
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

static void tessera_heap_pop(TesseraLedger *ledger)
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

static TesseraJob *tessera_find(const TesseraLedger *ledger, unsigned long long identity)
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

static void tessera_remove(TesseraLedger *ledger, const TesseraJob *job)
{
    // the job points into the array; its distance from the start is its index
    const unsigned long long at = (unsigned long long)(job - ledger->jobs);
    memmove(&ledger->jobs[at], &ledger->jobs[at + 1ull], (size_t)(ledger->job_count - at - 1ull) * sizeof(TesseraJob));
    ledger->job_count -= 1ull;
}

static unsigned long long tessera_blocked(const TesseraJob *job)
{
    return (job->reservation > job->used) ? job->reservation : job->used;
}

static unsigned long long tessera_unallocated(const TesseraJob *job)
{
    return (job->reservation > job->used) ? (job->reservation - job->used) : 0ull;
}

int tessera_ledger_open(TesseraLedger *ledger)
{
    memset(ledger, 0, sizeof(*ledger));
    ledger->next_identity = 1ull;
    return 1;
}

void tessera_ledger_close(TesseraLedger *ledger)
{
    free(ledger->jobs);
    free(ledger->history);
    free(ledger->heap);
    memset(ledger, 0, sizeof(*ledger));
}

void tessera_ledger_device(TesseraLedger *ledger, unsigned long long capacity, unsigned long long in_use)
{
    ledger->capacity = capacity;
    ledger->in_use = in_use;
}

long long tessera_ledger_headroom(const TesseraLedger *ledger)
{
    unsigned long long owed = 0ull;
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        if (ledger->jobs[at].state == TESSERA_JOB_RUNNING)
        {
            owed = tessera_sum(owed, tessera_unallocated(&ledger->jobs[at]));
        }
    }
    const unsigned long long taken = tessera_sum(ledger->in_use, owed);
    // a device's bytes and every sum here stay below two to the sixty-third; each difference is exact signed
    return (taken <= ledger->capacity) ? (long long)(ledger->capacity - taken) : -(long long)(taken - ledger->capacity);
}

const TesseraJob *tessera_ledger_job(const TesseraLedger *ledger, unsigned long long identity)
{
    return tessera_find(ledger, identity);
}

const TesseraHistory *tessera_ledger_history(const TesseraLedger *ledger, const EngineSignum *signum)
{
    for (unsigned long long at = 0ull; at < ledger->history_count; at += 1ull)
    {
        if (memcmp(ledger->history[at].signum.bytes, signum->bytes, sizeof(signum->bytes)) == 0)
        {
            return &ledger->history[at];
        }
    }
    return NULL;
}

unsigned long long tessera_ledger_wants(const TesseraLedger *ledger, const TesseraJob *job)
{
    // a job is reserved its signum's kept peak when that is more than it declares; the room it will take is
    // held from its start and not only once a sweep has seen it grow
    const TesseraHistory *const past = tessera_ledger_history(ledger, &job->request.signum);
    return ((past != NULL) && (past->peak > job->request.declared)) ? past->peak : job->request.declared;
}

int tessera_ledger_submit(TesseraLedger *ledger, const TesseraJobRequest *request, unsigned long long now,
                          unsigned long long *identity, TesseraEvent *event)
{
    memset(event, 0, sizeof(*event));
    if ((request->declared == 0ull)
        || !tessera_grow((void **)&ledger->jobs, &ledger->job_room, ledger->job_count, sizeof(TesseraJob)))
    {
        return 0;
    }
    const TesseraHistory *const past = tessera_ledger_history(ledger, &request->signum);
    const int over = (past != NULL) && (request->declared > past->peak) && (request->override_budget == 0u);
    TesseraJob *const job = &ledger->jobs[ledger->job_count];
    memset(job, 0, sizeof(*job));
    job->identity = ledger->next_identity;
    job->request = *request;
    job->submitted = now;
    job->state = over ? TESSERA_JOB_HELD : TESSERA_JOB_WAITING;
    job->hold_until = over ? tessera_sum(now, request->holding_microseconds) : 0ull;
    if (over && !tessera_heap_push(ledger, job->hold_until, job->identity, TESSERA_EVENT_LOST))
    {
        return 0;
    }
    ledger->job_count += 1ull;
    ledger->next_identity += 1ull;
    *identity = job->identity;
    event->kind = over ? TESSERA_EVENT_ASKED : TESSERA_EVENT_NONE;
    event->identity = job->identity;
    event->bytes = request->declared;
    event->measured = (past != NULL) ? past->peak : 0ull;
    return 1;
}

int tessera_ledger_override(TesseraLedger *ledger, unsigned long long identity, unsigned long long now)
{
    TesseraJob *const job = tessera_find(ledger, identity);
    if ((job == NULL) || (job->state != TESSERA_JOB_HELD) || (now > job->hold_until))
    {
        return 0;
    }
    job->state = TESSERA_JOB_WAITING;
    job->request.override_budget = 1u;
    return 1;
}

int tessera_ledger_measure(TesseraLedger *ledger, unsigned long long identity, unsigned long long used,
                           TesseraEvent *event)
{
    memset(event, 0, sizeof(*event));
    TesseraJob *const job = tessera_find(ledger, identity);
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
        event->kind = TESSERA_EVENT_GREW;
        event->identity = identity;
        event->bytes = job->request.declared;
        event->measured = used;
    }
    return 1;
}

int tessera_ledger_remember(TesseraLedger *ledger, const TesseraHistory *kept)
{
    for (unsigned long long at = 0ull; at < ledger->history_count; at += 1ull)
    {
        if (memcmp(ledger->history[at].signum.bytes, kept->signum.bytes, sizeof(kept->signum.bytes)) == 0)
        {
            ledger->history[at] = *kept;
            return 1;
        }
    }
    if (!tessera_grow((void **)&ledger->history, &ledger->history_room, ledger->history_count, sizeof(TesseraHistory)))
    {
        return 0;
    }
    ledger->history[ledger->history_count] = *kept;
    ledger->history_count += 1ull;
    return 1;
}

static int tessera_history_keep(TesseraLedger *ledger, const TesseraJob *job, unsigned long long now)
{
    TesseraHistory kept;
    kept.signum = job->request.signum;
    kept.peak = job->peak;
    kept.duration = now - job->started;
    return tessera_ledger_remember(ledger, &kept);
}

int tessera_ledger_release(TesseraLedger *ledger, unsigned long long identity, unsigned long long now, int finished)
{
    TesseraJob *const job = tessera_find(ledger, identity);
    if (job == NULL)
    {
        return 0;
    }
    const int kept = (finished == 0) || (job->state != TESSERA_JOB_RUNNING) || (job->measures == 0ull)
                  || tessera_history_keep(ledger, job, now);
    ledger->idle_microseconds = job->request.idle_microseconds;
    tessera_remove(ledger, job);
    if (ledger->job_count == 0ull)
    {
        ledger->idle_since = now;
        return tessera_heap_push(ledger, tessera_sum(now, ledger->idle_microseconds), 0ull, TESSERA_EVENT_IDLE) && kept;
    }
    return kept;
}

int tessera_ledger_idle(TesseraLedger *ledger, unsigned long long now, unsigned long long idle_microseconds)
{
    if (ledger->job_count != 0ull)
    {
        return 0;
    }
    ledger->idle_since = now;
    ledger->idle_microseconds = idle_microseconds;
    return tessera_heap_push(ledger, tessera_sum(now, idle_microseconds), 0ull, TESSERA_EVENT_IDLE);
}

static int tessera_start(TesseraLedger *ledger, TesseraJob *job, unsigned long long now, TesseraEvent *event)
{
    const TesseraHistory *const past = tessera_ledger_history(ledger, &job->request.signum);
    const unsigned long long next_sweep = tessera_sum(now, job->request.sweep_microseconds);
    if (!tessera_heap_push(ledger, next_sweep, job->identity, TESSERA_EVENT_SWEEP))
    {
        return 0;
    }
    job->state = TESSERA_JOB_RUNNING;
    job->reservation = tessera_ledger_wants(ledger, job);
    job->used = 0ull;
    job->peak = 0ull;
    job->measures = 0ull;
    job->started = now;
    job->expected_end = (past != NULL) ? tessera_sum(now, past->duration) : TESSERA_FOREVER;
    job->next_sweep = next_sweep;
    event->kind = TESSERA_EVENT_ADMITTED;
    event->identity = job->identity;
    event->bytes = job->reservation;
    event->measured = (past != NULL) ? past->peak : 0ull;
    return 1;
}

static int tessera_shadow(const TesseraLedger *ledger, unsigned long long wanted, long long headroom,
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
                room += (long long)tessera_blocked(job);
            }
        }
        after = soonest;
        // the wanted bytes are a device's bytes, below two to the sixty-third
        if (room >= (long long)wanted)
        {
            *shadow = soonest;
            // the room is at least the wanted bytes here; the difference is not negative
            *spare = (unsigned long long)(room - (long long)wanted);
            return 1;
        }
    }
}

unsigned long long tessera_ledger_admit(TesseraLedger *ledger, unsigned long long now, TesseraEvent *events,
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
        // the wanted bytes are a device's bytes, below two to the sixty-third
        if ((long long)tessera_ledger_wants(ledger, job) <= tessera_ledger_headroom(ledger))
        {
            if (!tessera_start(ledger, job, now, &events[made]))
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
    if (!tessera_shadow(ledger, tessera_ledger_wants(ledger, head), tessera_ledger_headroom(ledger), &shadow, &spare))
    {
        return made;
    }
    // the head points into the array; its distance from the start is its index
    for (unsigned long long at = (unsigned long long)(head - ledger->jobs) + 1ull; (made < room) && (at < ledger->job_count);
         at += 1ull)
    {
        TesseraJob *const job = &ledger->jobs[at];
        const TesseraHistory *const past = tessera_ledger_history(ledger, &job->request.signum);
        const unsigned long long wants = tessera_ledger_wants(ledger, job);
        // the wanted bytes are a device's bytes, below two to the sixty-third
        const int fits = (long long)wants <= tessera_ledger_headroom(ledger);
        if ((job->state != TESSERA_JOB_WAITING) || (past == NULL) || !fits)
        {
            continue;
        }
        const int before_shadow = tessera_sum(now, past->duration) <= shadow;
        const int in_spare = wants <= spare;
        if (!before_shadow && !in_spare)
        {
            continue;
        }
        spare -= (!before_shadow) ? wants : 0ull;
        if (!tessera_start(ledger, job, now, &events[made]))
        {
            return made;
        }
        made += 1ull;
    }
    return made;
}

int tessera_ledger_next(const TesseraLedger *ledger, TesseraDeadline *root)
{
    if (ledger->heap_count == 0ull)
    {
        return 0;
    }
    *root = ledger->heap[0];
    return 1;
}

int tessera_ledger_fire(TesseraLedger *ledger, unsigned long long now, TesseraEvent *event)
{
    memset(event, 0, sizeof(*event));
    while ((ledger->heap_count != 0ull) && (ledger->heap[0].when <= now))
    {
        const TesseraDeadline due = ledger->heap[0];
        tessera_heap_pop(ledger);
        if (due.kind == TESSERA_EVENT_IDLE)
        {
            if ((ledger->job_count == 0ull) && (tessera_sum(ledger->idle_since, ledger->idle_microseconds) == due.when))
            {
                event->kind = TESSERA_EVENT_IDLE;
                return 1;
            }
            continue;
        }
        TesseraJob *const job = tessera_find(ledger, due.identity);
        if (job == NULL)
        {
            continue;
        }
        if ((due.kind == TESSERA_EVENT_SWEEP) && (job->state == TESSERA_JOB_RUNNING) && (job->next_sweep == due.when))
        {
            job->next_sweep = tessera_sum(due.when, job->request.sweep_microseconds);
            event->kind = TESSERA_EVENT_SWEEP;
            event->identity = job->identity;
            return tessera_heap_push(ledger, job->next_sweep, job->identity, TESSERA_EVENT_SWEEP);
        }
        if ((due.kind == TESSERA_EVENT_LOST) && (job->state == TESSERA_JOB_HELD) && (job->hold_until == due.when))
        {
            event->kind = TESSERA_EVENT_LOST;
            event->identity = job->identity;
            event->bytes = job->request.declared;
            tessera_remove(ledger, job);
            return 1;
        }
    }
    return 0;
}
