// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The two tesseras held to each other: the device's tessera (tessera_device.h) makes the host daemon's ledger's
// decisions (tessera_ledger.c), one source for both (tessera_ledger_core.h). Each round draws a stream of calls,
// every kind of call with its times, bytes and jobs drawn from a seeded stream, and makes them of a host ledger and
// of a ledger on the device, laid with rooms of one to make it grow. Every answer must be the host's field for field,
// and the ledger each is left with the host's job for job, kept peak for kept peak and deadline for deadline. The
// test is one job on the device's tessera daemon, submitted before its first device work.
#include "sim.h"
#include "tessera_device.h"
#include "tessera_ledger.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <string.h>

#include <vector>

// the most the test puts on the device at once: a round's calls and answers, and the ledger's rooms
#define DEVICE_TEST_DECLARED (64ull << 20u)

#define DEVICE_TEST_ROUNDS 200u
#define DEVICE_TEST_CALLS 400u

// the signums a round's jobs are drawn from, few enough that a signum's kept peak judges later jobs
#define DEVICE_TEST_SIGNUMS 6u

// the device's capacity in each round
#define DEVICE_TEST_CAPACITY 1000ull

static unsigned long long s_device_test_state = 0x9E3779B97F4A7C15ull;

static unsigned long long device_test_random(void)
{
    s_device_test_state ^= s_device_test_state << 13u;
    s_device_test_state ^= s_device_test_state >> 7u;
    s_device_test_state ^= s_device_test_state << 17u;
    return s_device_test_state;
}

static unsigned long long device_test_below(unsigned long long bound)
{
    return device_test_random() % bound;
}

// the checks made and failed
struct DeviceTestTally
{
    unsigned int checks;
    unsigned int failed;
};

static void device_test_check(DeviceTestTally *tally, int held, const char *what, unsigned int round)
{
    tally->checks += 1u;
    tally->failed += held ? 0u : 1u;
    if (!held)
    {
        printf("  FAIL round %u: %s\n", round, what);
    }
}

static EngineSignum device_test_signum(unsigned long long seed)
{
    EngineSignum signum;
    memset(&signum, 0, sizeof(signum));
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        // each byte is one eighth of the seed, held whole in an unsigned char
        signum.bytes[at] = (unsigned char)(seed >> (8u * at));
    }
    return signum;
}

// one call drawn: its kind, and what that kind reads, at `now`; `submitted` is the submits drawn before it, and a
// job it names is one of those or one past them
static TesseraCall device_test_call(unsigned long long now, unsigned long long submitted)
{
    TesseraCall call;
    memset(&call, 0, sizeof(call));
    // the kinds are ten, and the draw is below ten
    call.kind = (TesseraCallKind)device_test_below(10ull);
    call.now = now;
    call.identity = 1ull + device_test_below(submitted + 1ull);
    call.capacity = DEVICE_TEST_CAPACITY;
    call.in_use = device_test_below(DEVICE_TEST_CAPACITY);
    call.used = device_test_below(900ull);
    call.finished = (int)device_test_below(2ull);
    call.room = 1ull + device_test_below(TESSERA_CALL_EVENTS + 4ull);
    call.idle_microseconds = 1000ull + device_test_below(5000ull);
    call.request.signum = device_test_signum(device_test_below(DEVICE_TEST_SIGNUMS));
    call.request.declared = 1ull + device_test_below(600ull);
    call.request.holding_microseconds = 1000ull;
    call.request.sweep_microseconds = 100ull + device_test_below(400ull);
    call.request.idle_microseconds = 5000ull;
    call.request.override_budget = (device_test_below(4ull) == 0ull) ? 1u : 0u;
    call.request.standing = device_test_below(300ull);
    call.kept.signum = device_test_signum(device_test_below(DEVICE_TEST_SIGNUMS));
    call.kept.peak = device_test_below(900ull);
    call.kept.duration = device_test_below(3000ull);
    return call;
}

static int device_test_event_same(const TesseraEvent *left, const TesseraEvent *right)
{
    return (left->kind == right->kind) && (left->identity == right->identity) && (left->bytes == right->bytes)
        && (left->measured == right->measured);
}

static int device_test_answer_same(const TesseraAnswer *left, const TesseraAnswer *right)
{
    int same = (left->held == right->held) && (left->full == right->full) && (left->identity == right->identity)
            && (left->headroom == right->headroom) && (left->root.when == right->root.when)
            && (left->root.identity == right->root.identity) && (left->root.kind == right->root.kind);
    for (unsigned int at = 0u; at < TESSERA_CALL_EVENTS; at += 1u)
    {
        same = same && device_test_event_same(&left->events[at], &right->events[at]);
    }
    return same;
}

static int device_test_signum_same(const EngineSignum *left, const EngineSignum *right)
{
    return memcmp(left->bytes, right->bytes, sizeof(left->bytes)) == 0;
}

static int device_test_job_same(const TesseraJob *left, const TesseraJob *right)
{
    const TesseraJobRequest *const asked = &left->request;
    const TesseraJobRequest *const other = &right->request;
    return (left->identity == right->identity) && device_test_signum_same(&asked->signum, &other->signum)
        && (asked->declared == other->declared) && (asked->holding_microseconds == other->holding_microseconds)
        && (asked->sweep_microseconds == other->sweep_microseconds)
        && (asked->idle_microseconds == other->idle_microseconds) && (asked->override_budget == other->override_budget)
        && (asked->standing == other->standing) && (left->state == right->state)
        && (left->reservation == right->reservation) && (left->used == right->used) && (left->peak == right->peak)
        && (left->measures == right->measures) && (left->submitted == right->submitted)
        && (left->started == right->started) && (left->expected_end == right->expected_end)
        && (left->hold_until == right->hold_until) && (left->next_sweep == right->next_sweep);
}

// 1 where two ledgers hold the same device, jobs, kept peaks, deadlines and idle time
static int device_test_ledger_same(const TesseraLedger *left, const TesseraLedger *right)
{
    int same = (left->capacity == right->capacity) && (left->in_use == right->in_use)
            && (left->job_count == right->job_count) && (left->history_count == right->history_count)
            && (left->heap_count == right->heap_count) && (left->next_identity == right->next_identity)
            && (left->idle_since == right->idle_since) && (left->idle_microseconds == right->idle_microseconds);
    for (unsigned long long at = 0ull; same && (at < left->job_count); at += 1ull)
    {
        same = device_test_job_same(&left->jobs[at], &right->jobs[at]);
    }
    for (unsigned long long at = 0ull; same && (at < left->history_count); at += 1ull)
    {
        same = device_test_signum_same(&left->history[at].signum, &right->history[at].signum)
            && (left->history[at].peak == right->history[at].peak)
            && (left->history[at].duration == right->history[at].duration);
    }
    for (unsigned long long at = 0ull; same && (at < left->heap_count); at += 1ull)
    {
        same = (left->heap[at].when == right->heap[at].when) && (left->heap[at].identity == right->heap[at].identity)
            && (left->heap[at].kind == right->heap[at].kind);
    }
    return same;
}

// one round: a stream of calls made of the host's ledger and the device's, the answers and the ledgers held equal
static void device_test_round(DeviceTestTally *tally, unsigned int round, unsigned long long *grown)
{
    std::vector<TesseraCall> calls(DEVICE_TEST_CALLS);
    unsigned long long now = 0ull;
    unsigned long long submitted = 0ull;
    for (unsigned int at = 0u; at < DEVICE_TEST_CALLS; at += 1u)
    {
        now += device_test_below(200ull);
        calls[at] = device_test_call(now, submitted);
        submitted += (calls[at].kind == TESSERA_CALL_SUBMIT) ? 1ull : 0ull;
    }
    TesseraLedger host;
    tessera_ledger_open(&host);
    std::vector<TesseraAnswer> host_answers(DEVICE_TEST_CALLS);
    for (unsigned int at = 0u; at < DEVICE_TEST_CALLS; at += 1u)
    {
        tessera_ledger_call(&host, &calls[at], &host_answers[at]);
    }
    TesseraDevice device;
    std::vector<TesseraAnswer> device_answers(DEVICE_TEST_CALLS);
    const int opened = tessera_device_open(&device, 1ull);
    const int made
        = opened && tessera_device_calls(&device, calls.data(), DEVICE_TEST_CALLS, device_answers.data());
    device_test_check(tally, made, "the device makes the calls", round);
    if (made)
    {
        unsigned int differ = 0u;
        for (unsigned int at = 0u; at < DEVICE_TEST_CALLS; at += 1u)
        {
            differ += device_test_answer_same(&host_answers[at], &device_answers[at]) ? 0u : 1u;
        }
        device_test_check(tally, differ == 0u, "each answer is the host's", round);
        TesseraLedger copy;
        const int read = tessera_device_read(&device, &copy);
        device_test_check(tally, read && device_test_ledger_same(&host, &copy),
                          "the device's ledger is the host's", round);
        *grown += (device.held.job_room > 1ull) ? 1ull : 0ull;
        if (read)
        {
            tessera_ledger_close(&copy);
        }
    }
    if (opened)
    {
        tessera_device_close(&device);
    }
    tessera_ledger_close(&host);
}

int main(int count, char **arguments)
{
    DeviceTestTally tally = {0u, 0u};
    char job_room[SIM_LINE_ROOM];
    SimTally job;
    sim_open(&job, job_room);
    const int admitted = sim_job_submit(&job, "tessera_device_test", count, arguments, DEVICE_TEST_DECLARED);
    unsigned long long grown = 0ull;
    if (admitted != 0)
    {
        for (unsigned int round = 0u; round < DEVICE_TEST_ROUNDS; round += 1u)
        {
            device_test_round(&tally, round, &grown);
        }
    }
    sim_job_release(&job);
    sim_flush(&job);
    device_test_check(&tally, (admitted != 0) && (job.failures == 0ull),
                      "tessera: the device's daemon admits the test's job and it releases", 0u);
    printf("  tessera device test: %u rounds of %u calls, %llu grew the device's job room past one; %u checks, "
           "%u failed\n",
           (admitted != 0) ? DEVICE_TEST_ROUNDS : 0u, DEVICE_TEST_CALLS, grown, tally.checks, tally.failed);
    return (tally.failed == 0u) ? 0 : 1;
}
