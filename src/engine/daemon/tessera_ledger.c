// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The host daemon's ledger: each decision is tessera_ledger_core.h's, the source the device's tessera runs too. Before
// a decision that can add a job, a kept peak or a deadline, the ledger grows each room to the most the decision can
// add. A room that does not grow is left to the core, which refuses where it needs the room, as the ledger refused
// before where a room did not grow.
#include "tessera_ledger.h"
#include "tessera_ledger_core.h"

#include <stdlib.h>
#include <string.h>

// `items` grown to hold `wanted` of `size` bytes each, its room doubled until it does
static int tessera_grow(void **items, unsigned long long *room, unsigned long long wanted, size_t size)
{
    if (wanted <= *room)
    {
        return 1;
    }
    unsigned long long grown_room = (*room == 0ull) ? 1ull : *room;
    while (grown_room < wanted)
    {
        grown_room *= 2ull;
    }
    void *const grown = realloc(*items, (size_t)grown_room * size);
    if (grown == NULL)
    {
        return 0;
    }
    *items = grown;
    *room = grown_room;
    return 1;
}

// each of the ledger's rooms grown to the most a call of `kind` can add
static int tessera_room(TesseraLedger *ledger, TesseraCallKind kind)
{
    const TesseraRooms rooms = tessera_core_rooms(ledger, kind);
    const int jobs = tessera_grow((void **)&ledger->jobs, &ledger->job_room, rooms.jobs, sizeof(TesseraJob));
    const int history
        = tessera_grow((void **)&ledger->history, &ledger->history_room, rooms.history, sizeof(TesseraHistory));
    const int heap = tessera_grow((void **)&ledger->heap, &ledger->heap_room, rooms.heap, sizeof(TesseraDeadline));
    return jobs && history && heap;
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
    tessera_core_device(ledger, capacity, in_use);
}

long long tessera_ledger_headroom(const TesseraLedger *ledger)
{
    return tessera_core_headroom(ledger);
}

const TesseraJob *tessera_ledger_job(const TesseraLedger *ledger, unsigned long long identity)
{
    return tessera_core_find(ledger, identity);
}

const TesseraHistory *tessera_ledger_history(const TesseraLedger *ledger, const EngineSignum *signum)
{
    return tessera_core_history(ledger, signum);
}

unsigned long long tessera_ledger_wants(const TesseraLedger *ledger, const TesseraJob *job)
{
    return tessera_core_wants(ledger, job);
}

int tessera_ledger_submit(TesseraLedger *ledger, const TesseraJobRequest *request, unsigned long long now,
                          unsigned long long *identity, TesseraEvent *event)
{
    (void)tessera_room(ledger, TESSERA_CALL_SUBMIT);
    return tessera_core_submit(ledger, request, now, identity, event);
}

int tessera_ledger_override(TesseraLedger *ledger, unsigned long long identity, unsigned long long now)
{
    return tessera_core_override(ledger, identity, now);
}

int tessera_ledger_measure(TesseraLedger *ledger, unsigned long long identity, unsigned long long used,
                           TesseraEvent *event)
{
    return tessera_core_measure(ledger, identity, used, event);
}

int tessera_ledger_remember(TesseraLedger *ledger, const TesseraHistory *kept)
{
    (void)tessera_room(ledger, TESSERA_CALL_REMEMBER);
    return tessera_core_remember(ledger, kept);
}

int tessera_ledger_release(TesseraLedger *ledger, unsigned long long identity, unsigned long long now, int finished)
{
    (void)tessera_room(ledger, TESSERA_CALL_RELEASE);
    return tessera_core_release(ledger, identity, now, finished);
}

int tessera_ledger_idle(TesseraLedger *ledger, unsigned long long now, unsigned long long idle_microseconds)
{
    (void)tessera_room(ledger, TESSERA_CALL_IDLE);
    return tessera_core_idle(ledger, now, idle_microseconds);
}

unsigned long long tessera_ledger_admit(TesseraLedger *ledger, unsigned long long now, TesseraEvent *events,
                                        unsigned long long room)
{
    (void)tessera_room(ledger, TESSERA_CALL_ADMIT);
    return tessera_core_admit(ledger, now, events, room);
}

int tessera_ledger_next(const TesseraLedger *ledger, TesseraDeadline *root)
{
    return tessera_core_next(ledger, root);
}

int tessera_ledger_fire(TesseraLedger *ledger, unsigned long long now, TesseraEvent *event)
{
    return tessera_core_fire(ledger, now, event);
}

void tessera_ledger_call(TesseraLedger *ledger, const TesseraCall *call, TesseraAnswer *answer)
{
    (void)tessera_room(ledger, call->kind);
    tessera_core_call(ledger, call, answer);
}
