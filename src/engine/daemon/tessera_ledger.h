// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_LEDGER_H
#define TESSERA_LEDGER_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    TESSERA_JOB_WAITING = 0,
    TESSERA_JOB_HELD = 1,
    TESSERA_JOB_RUNNING = 2
} TesseraJobState;

typedef enum
{
    TESSERA_EVENT_NONE = 0,
    TESSERA_EVENT_ADMITTED = 1,
    TESSERA_EVENT_ASKED = 2,
    TESSERA_EVENT_GREW = 3,
    TESSERA_EVENT_LOST = 4,
    TESSERA_EVENT_SWEEP = 5,
    TESSERA_EVENT_IDLE = 6
} TesseraEventKind;

// A job as it asks. `declared` is the bytes the job says it will take; `standing` is the bytes its process already
// holds on the device as it asks (its CUDA context, and whatever it kept from an earlier job), measured by the daemon.
// The job's whole declaration is the two together, and the device's measured use already counts the standing bytes.
typedef struct
{
    EngineSignum signum;
    unsigned long long declared;
    unsigned long long holding_microseconds;
    unsigned long long sweep_microseconds;
    unsigned long long idle_microseconds;
    unsigned int override_budget;
    unsigned long long standing;
} TesseraJobRequest;

typedef struct
{
    unsigned long long identity;
    TesseraJobRequest request;
    TesseraJobState state;
    unsigned long long reservation;
    unsigned long long used;
    unsigned long long peak;
    unsigned long long measures;
    unsigned long long submitted;
    unsigned long long started;
    unsigned long long expected_end;
    unsigned long long hold_until;
    unsigned long long next_sweep;
} TesseraJob;

typedef struct
{
    EngineSignum signum;
    unsigned long long peak;
    unsigned long long duration;
} TesseraHistory;

typedef struct
{
    unsigned long long when;
    unsigned long long identity;
    TesseraEventKind kind;
} TesseraDeadline;

typedef struct
{
    TesseraEventKind kind;
    unsigned long long identity;
    unsigned long long bytes;
    unsigned long long measured;
} TesseraEvent;

typedef struct
{
    unsigned long long capacity;
    unsigned long long in_use;
    TesseraJob *jobs;
    unsigned long long job_count;
    unsigned long long job_room;
    TesseraHistory *history;
    unsigned long long history_count;
    unsigned long long history_room;
    TesseraDeadline *heap;
    unsigned long long heap_count;
    unsigned long long heap_room;
    unsigned long long next_identity;
    unsigned long long idle_since;
    unsigned long long idle_microseconds;
} TesseraLedger;

// the most events one call is answered with: an admit starts at most this many jobs in one call
#define TESSERA_CALL_EVENTS 16u

// the ledger's decisions, each one call: the host daemon's ledger and the device's tessera (tessera_device.h) make
// the same calls through one source (tessera_ledger_core.h)
typedef enum
{
    TESSERA_CALL_DEVICE = 0,
    TESSERA_CALL_SUBMIT = 1,
    TESSERA_CALL_OVERRIDE = 2,
    TESSERA_CALL_MEASURE = 3,
    TESSERA_CALL_RELEASE = 4,
    TESSERA_CALL_ADMIT = 5,
    TESSERA_CALL_FIRE = 6,
    TESSERA_CALL_IDLE = 7,
    TESSERA_CALL_REMEMBER = 8,
    TESSERA_CALL_NEXT = 9
} TesseraCallKind;

// one call and what it reads: the time; the job it names; the device's capacity and use (DEVICE); the bytes a job
// was measured using (MEASURE); 1 where a job finished (RELEASE); the events an admit may make, at most
// TESSERA_CALL_EVENTS (ADMIT); the idle time (IDLE); the job asked for (SUBMIT); the peak kept (REMEMBER)
typedef struct
{
    TesseraCallKind kind;
    unsigned long long now;
    unsigned long long identity;
    unsigned long long capacity;
    unsigned long long in_use;
    unsigned long long used;
    int finished;
    unsigned long long room;
    unsigned long long idle_microseconds;
    TesseraJobRequest request;
    TesseraHistory kept;
} TesseraCall;

// a call's answer: what the ledger function returned (for ADMIT the jobs it started); 1 where the ledger had no room
// for the most the call could add, and nothing changed; the identity a submit gave; the headroom after the call;
// the deadline due first (NEXT); and the events the call made
typedef struct
{
    unsigned long long held;
    int full;
    unsigned long long identity;
    long long headroom;
    TesseraDeadline root;
    TesseraEvent events[TESSERA_CALL_EVENTS];
} TesseraAnswer;

int tessera_ledger_open(TesseraLedger *ledger);

void tessera_ledger_close(TesseraLedger *ledger);

void tessera_ledger_device(TesseraLedger *ledger, unsigned long long capacity, unsigned long long in_use);

long long tessera_ledger_headroom(const TesseraLedger *ledger);

int tessera_ledger_submit(TesseraLedger *ledger, const TesseraJobRequest *request, unsigned long long now,
                          unsigned long long *identity, TesseraEvent *event);

int tessera_ledger_override(TesseraLedger *ledger, unsigned long long identity, unsigned long long now);

int tessera_ledger_measure(TesseraLedger *ledger, unsigned long long identity, unsigned long long used,
                           TesseraEvent *event);

int tessera_ledger_release(TesseraLedger *ledger, unsigned long long identity, unsigned long long now, int finished);

unsigned long long tessera_ledger_admit(TesseraLedger *ledger, unsigned long long now, TesseraEvent *events,
                                        unsigned long long room);

int tessera_ledger_next(const TesseraLedger *ledger, TesseraDeadline *root);

int tessera_ledger_fire(TesseraLedger *ledger, unsigned long long now, TesseraEvent *event);

const TesseraJob *tessera_ledger_job(const TesseraLedger *ledger, unsigned long long identity);

const TesseraHistory *tessera_ledger_history(const TesseraLedger *ledger, const EngineSignum *signum);

unsigned long long tessera_ledger_wants(const TesseraLedger *ledger, const TesseraJob *job);

int tessera_ledger_remember(TesseraLedger *ledger, const TesseraHistory *kept);

int tessera_ledger_idle(TesseraLedger *ledger, unsigned long long now, unsigned long long idle_microseconds);

void tessera_ledger_call(TesseraLedger *ledger, const TesseraCall *call, TesseraAnswer *answer);

#ifdef __cplusplus
}
#endif

#endif
