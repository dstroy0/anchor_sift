// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera_ledger.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_EVENTS 64u
#define TEST_SCENARIO_JOBS 12u
#define TEST_NEVER 0xFFFFFFFFFFFFFFFFull

typedef struct
{
    const char *name;
    unsigned long long cases;
    unsigned long long failed;
} TestTally;

static unsigned long long test_state = 0x9E3779B97F4A7C15ull;

static unsigned long long test_random(void)
{
    test_state ^= test_state << 13u;
    test_state ^= test_state >> 7u;
    test_state ^= test_state << 17u;
    return test_state;
}

static unsigned long long test_below(unsigned long long bound)
{
    return test_random() % bound;
}

static void test_check(TestTally *tally, int held)
{
    tally->cases += 1ull;
    tally->failed += held ? 0ull : 1ull;
}

static void test_report(const TestTally *tally)
{
    printf("  %-30s %9llu cases, %llu failed\n", tally->name, tally->cases, tally->failed);
}

static EngineSignum test_signum(unsigned long long seed)
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

static TesseraJobRequest test_request(unsigned long long seed, unsigned long long declared)
{
    TesseraJobRequest request;
    memset(&request, 0, sizeof(request));
    request.signum = test_signum(seed);
    request.declared = declared;
    request.holding_microseconds = 1000ull;
    request.sweep_microseconds = 100ull;
    request.idle_microseconds = 5000ull;
    return request;
}

static long long test_headroom_direct(const TesseraLedger *ledger)
{
    long long used = 0ll;
    long long blocked = 0ll;
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        const TesseraJob *const job = &ledger->jobs[at];
        if (job->state == TESSERA_JOB_RUNNING)
        {
            // the test's bytes stay far below two to the sixty-third
            used += (long long)job->used;
            // the test's bytes stay far below two to the sixty-third
            blocked += (long long)((job->reservation > job->used) ? job->reservation : job->used);
        }
    }
    // the test's bytes stay far below two to the sixty-third
    const long long outside = (long long)ledger->in_use - used;
    // the test's bytes stay far below two to the sixty-third
    return (long long)ledger->capacity - outside - blocked;
}

static void test_headroom(TestTally *tally)
{
    for (unsigned int round = 0u; round < 2000u; round += 1u)
    {
        TesseraLedger ledger;
        tessera_ledger_open(&ledger);
        const unsigned long long capacity = 1000000ull + test_below(1000000ull);
        tessera_ledger_device(&ledger, capacity, 0ull);
        const unsigned int jobs = 1u + (unsigned int)test_below(8u);
        TesseraEvent events[TEST_EVENTS];
        for (unsigned int job = 0u; job < jobs; job += 1u)
        {
            unsigned long long identity = 0ull;
            TesseraEvent event;
            const TesseraJobRequest request = test_request(round * 64ull + job, 1ull + test_below(capacity / jobs));
            tessera_ledger_submit(&ledger, &request, 0ull, &identity, &event);
        }
        tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS);
        unsigned long long used_total = 0ull;
        for (unsigned long long at = 0ull; at < ledger.job_count; at += 1ull)
        {
            if (ledger.jobs[at].state == TESSERA_JOB_RUNNING)
            {
                TesseraEvent event;
                const unsigned long long used = test_below(2ull * ledger.jobs[at].reservation + 1ull);
                tessera_ledger_measure(&ledger, ledger.jobs[at].identity, used, &event);
                used_total += used;
            }
        }
        tessera_ledger_device(&ledger, capacity, used_total + test_below(capacity / 4ull));
        test_check(tally, tessera_ledger_headroom(&ledger) == test_headroom_direct(&ledger));
        tessera_ledger_close(&ledger);
    }
}

static void test_heap_order(TestTally *tally)
{
    for (unsigned int round = 0u; round < 200u; round += 1u)
    {
        TesseraLedger ledger;
        tessera_ledger_open(&ledger);
        tessera_ledger_device(&ledger, 1ull << 40u, 0ull);
        const unsigned int jobs = 1u + (unsigned int)test_below(300u);
        for (unsigned int job = 0u; job < jobs; job += 1u)
        {
            unsigned long long identity = 0ull;
            TesseraEvent event;
            TesseraJobRequest request = test_request(job, 1ull);
            request.sweep_microseconds = 1ull + test_below(100000ull);
            tessera_ledger_submit(&ledger, &request, 0ull, &identity, &event);
        }
        TesseraEvent events[TEST_EVENTS];
        while (tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS) != 0ull)
        {
        }
        unsigned long long last = 0ull;
        unsigned long long fired = 0ull;
        int ordered = 1;
        TesseraDeadline root;
        while ((fired < 3000ull) && tessera_ledger_next(&ledger, &root))
        {
            TesseraEvent event;
            if (tessera_ledger_fire(&ledger, root.when, &event))
            {
                ordered = ordered && (root.when >= last) && (event.kind == TESSERA_EVENT_SWEEP);
                last = root.when;
                fired += 1ull;
            }
        }
        test_check(tally, ordered && (fired == 3000ull));
        tessera_ledger_close(&ledger);
    }
}

static void test_budget(TestTally *tally)
{
    TesseraLedger ledger;
    tessera_ledger_open(&ledger);
    tessera_ledger_device(&ledger, 1000ull, 0ull);
    unsigned long long first = 0ull;
    TesseraEvent event;
    TesseraEvent events[TEST_EVENTS];
    const TesseraJobRequest request = test_request(7ull, 400ull);
    test_check(tally, tessera_ledger_submit(&ledger, &request, 0ull, &first, &event) && (event.kind == TESSERA_EVENT_NONE));
    test_check(tally, (tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS) == 1ull)
                          && (events[0].kind == TESSERA_EVENT_ADMITTED));
    test_check(tally, tessera_ledger_measure(&ledger, first, 250ull, &event) && (event.kind == TESSERA_EVENT_NONE));
    test_check(tally, tessera_ledger_measure(&ledger, first, 450ull, &event) && (event.kind == TESSERA_EVENT_GREW)
                          && (tessera_ledger_job(&ledger, first)->reservation == 450ull) && (event.measured == 450ull));
    test_check(tally, tessera_ledger_measure(&ledger, first, 300ull, &event)
                          && (tessera_ledger_job(&ledger, first)->reservation == 450ull));
    test_check(tally, tessera_ledger_release(&ledger, first, 90ull, 1));
    const TesseraHistory *const past = tessera_ledger_history(&ledger, &request.signum);
    test_check(tally, (past != NULL) && (past->peak == 450ull) && (past->duration == 90ull));

    unsigned long long second = 0ull;
    const TesseraJobRequest greedy = test_request(7ull, 600ull);
    test_check(tally, tessera_ledger_submit(&ledger, &greedy, 100ull, &second, &event)
                          && (event.kind == TESSERA_EVENT_ASKED) && (event.measured == 450ull)
                          && (tessera_ledger_job(&ledger, second)->state == TESSERA_JOB_HELD));
    test_check(tally, tessera_ledger_admit(&ledger, 100ull, events, TEST_EVENTS) == 0ull);
    test_check(tally, !tessera_ledger_fire(&ledger, 100ull + 999ull, &event));
    test_check(tally, tessera_ledger_fire(&ledger, 100ull + 1000ull, &event) && (event.kind == TESSERA_EVENT_LOST)
                          && (event.identity == second) && (tessera_ledger_job(&ledger, second) == NULL));

    unsigned long long third = 0ull;
    test_check(tally, tessera_ledger_submit(&ledger, &greedy, 2000ull, &third, &event)
                          && (event.kind == TESSERA_EVENT_ASKED));
    test_check(tally, tessera_ledger_override(&ledger, third, 2500ull)
                          && (tessera_ledger_job(&ledger, third)->state == TESSERA_JOB_WAITING));
    test_check(tally, (tessera_ledger_admit(&ledger, 2500ull, events, TEST_EVENTS) == 1ull)
                          && (events[0].bytes == 600ull));
    int lost_after_override = 0;
    while (tessera_ledger_fire(&ledger, 3000ull, &event))
    {
        lost_after_override = lost_after_override || (event.kind == TESSERA_EVENT_LOST);
    }
    test_check(tally, lost_after_override == 0);
    test_check(tally, tessera_ledger_release(&ledger, third, 3100ull, 0)
                          && (tessera_ledger_history(&ledger, &greedy.signum)->peak == 450ull));

    unsigned long long late = 0ull;
    test_check(tally, tessera_ledger_submit(&ledger, &greedy, 4000ull, &late, &event)
                          && !tessera_ledger_override(&ledger, late, 5001ull));
    const TesseraJobRequest empty = test_request(9ull, 0ull);
    unsigned long long refused = 0ull;
    test_check(tally, !tessera_ledger_submit(&ledger, &empty, 6000ull, &refused, &event));
    tessera_ledger_close(&ledger);

    // declaring under its kept peak, a job is reserved the peak: with room for its declaration but not its peak it
    // waits, and once the peak fits it is admitted holding the peak
    TesseraLedger kept;
    tessera_ledger_open(&kept);
    tessera_ledger_device(&kept, 1000ull, 700ull);
    const TesseraHistory remembered = {request.signum, 450ull, 90ull};
    test_check(tally, tessera_ledger_remember(&kept, &remembered));
    unsigned long long modest = 0ull;
    const TesseraJobRequest under = test_request(7ull, 100ull);
    test_check(tally, tessera_ledger_submit(&kept, &under, 7000ull, &modest, &event) && (event.kind == TESSERA_EVENT_NONE)
                          && (tessera_ledger_wants(&kept, tessera_ledger_job(&kept, modest)) == 450ull));
    test_check(tally, tessera_ledger_admit(&kept, 7000ull, events, TEST_EVENTS) == 0ull);
    tessera_ledger_device(&kept, 1000ull, 500ull);
    test_check(tally, (tessera_ledger_admit(&kept, 7100ull, events, TEST_EVENTS) == 1ull) && (events[0].bytes == 450ull)
                          && (tessera_ledger_job(&kept, modest)->reservation == 450ull));
    tessera_ledger_close(&kept);
}

// a process holding bytes as it asks is reserved them beside its declaration, and admitted on what it has yet to find,
// since the device's measured use already counts what it holds; the held rule weighs the declaration alone against
// the kept peak
static void test_standing(TestTally *tally)
{
    TesseraLedger ledger;
    tessera_ledger_open(&ledger);
    tessera_ledger_device(&ledger, 1000ull, 300ull);
    TesseraEvent event;
    TesseraEvent events[TEST_EVENTS];
    TesseraJobRequest request = test_request(11ull, 650ull);
    request.standing = 200ull;
    unsigned long long first = 0ull;
    test_check(tally, tessera_ledger_submit(&ledger, &request, 0ull, &first, &event) && (event.kind == TESSERA_EVENT_NONE)
                          && (tessera_ledger_wants(&ledger, tessera_ledger_job(&ledger, first)) == 850ull));
    // its whole 850 passes the 700 free, but the 650 it has yet to find fits
    test_check(tally, (tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS) == 1ull) && (events[0].bytes == 850ull)
                          && (tessera_ledger_job(&ledger, first)->used == 200ull));
    test_check(tally, tessera_ledger_headroom(&ledger) == 50ll);
    unsigned long long second = 0ull;
    const TesseraJobRequest after = test_request(12ull, 100ull);
    test_check(tally, tessera_ledger_submit(&ledger, &after, 0ull, &second, &event)
                          && (tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS) == 0ull));
    test_check(tally, tessera_ledger_measure(&ledger, first, 900ull, &event) && (event.kind == TESSERA_EVENT_GREW)
                          && (tessera_ledger_job(&ledger, first)->reservation == 900ull));
    test_check(tally, tessera_ledger_release(&ledger, first, 50ull, 1)
                          && (tessera_ledger_history(&ledger, &request.signum)->peak == 900ull));
    // standing on 300 and declaring 650 under the kept 900 is not held, and is reserved its whole 950
    request.standing = 300ull;
    unsigned long long third = 0ull;
    test_check(tally, tessera_ledger_submit(&ledger, &request, 60ull, &third, &event) && (event.kind == TESSERA_EVENT_NONE)
                          && (tessera_ledger_wants(&ledger, tessera_ledger_job(&ledger, third)) == 950ull));
    // declaring 950 over the kept 900 is held, whatever its process stands on
    const TesseraJobRequest greedy = test_request(11ull, 950ull);
    unsigned long long fourth = 0ull;
    test_check(tally, tessera_ledger_submit(&ledger, &greedy, 70ull, &fourth, &event)
                          && (event.kind == TESSERA_EVENT_ASKED));
    tessera_ledger_close(&ledger);
}

static int test_idle_fired(TesseraLedger *ledger, unsigned long long now)
{
    TesseraEvent event;
    int idle = 0;
    while (tessera_ledger_fire(ledger, now, &event))
    {
        idle = idle || (event.kind == TESSERA_EVENT_IDLE);
    }
    return idle;
}

static void test_idle(TestTally *tally)
{
    TesseraLedger ledger;
    tessera_ledger_open(&ledger);
    tessera_ledger_device(&ledger, 1000ull, 0ull);
    unsigned long long identity = 0ull;
    TesseraEvent event;
    TesseraEvent events[TEST_EVENTS];
    const TesseraJobRequest request = test_request(3ull, 10ull);
    tessera_ledger_submit(&ledger, &request, 0ull, &identity, &event);
    tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS);
    tessera_ledger_release(&ledger, identity, 50ull, 1);
    test_check(tally, tessera_ledger_history(&ledger, &request.signum) == NULL);
    test_check(tally, test_idle_fired(&ledger, 50ull + 4999ull) == 0);
    test_check(tally, test_idle_fired(&ledger, 50ull + 5000ull) == 1);

    tessera_ledger_submit(&ledger, &request, 6000ull, &identity, &event);
    tessera_ledger_admit(&ledger, 6000ull, events, TEST_EVENTS);
    tessera_ledger_release(&ledger, identity, 6100ull, 1);
    tessera_ledger_submit(&ledger, &request, 6200ull, &identity, &event);
    test_check(tally, test_idle_fired(&ledger, 6100ull + 5000ull) == 0);
    tessera_ledger_close(&ledger);
}

static const TesseraJob *test_head(const TesseraLedger *ledger)
{
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        if (ledger->jobs[at].state == TESSERA_JOB_WAITING)
        {
            return &ledger->jobs[at];
        }
    }
    return NULL;
}

static unsigned long long test_shadow(const TesseraLedger *ledger, unsigned long long wanted)
{
    unsigned long long ends[TEST_SCENARIO_JOBS];
    unsigned long long frees[TEST_SCENARIO_JOBS];
    unsigned int count = 0u;
    for (unsigned long long at = 0ull; at < ledger->job_count; at += 1ull)
    {
        const TesseraJob *const job = &ledger->jobs[at];
        if (job->state == TESSERA_JOB_RUNNING)
        {
            ends[count] = job->expected_end;
            frees[count] = (job->reservation > job->used) ? job->reservation : job->used;
            count += 1u;
        }
    }
    for (unsigned int at = 1u; at < count; at += 1u)
    {
        for (unsigned int back = at; (back > 0u) && (ends[back - 1u] > ends[back]); back -= 1u)
        {
            const unsigned long long end = ends[back];
            const unsigned long long free_bytes = frees[back];
            ends[back] = ends[back - 1u];
            frees[back] = frees[back - 1u];
            ends[back - 1u] = end;
            frees[back - 1u] = free_bytes;
        }
    }
    long long room = tessera_ledger_headroom(ledger);
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        // the test's bytes stay far below two to the sixty-third
        room += (long long)frees[at];
        // the test's bytes stay far below two to the sixty-third
        if ((room >= (long long)wanted) && ((at + 1u == count) || (ends[at + 1u] != ends[at])))
        {
            return ends[at];
        }
    }
    return TEST_NEVER;
}

typedef struct
{
    unsigned long long declared;
    unsigned long long duration;
    unsigned long long arrival;
} TestScenarioJob;

static void test_scenario(TestTally *kept, TestTally *finished, const TestScenarioJob *jobs, unsigned int count,
                          unsigned long long capacity)
{
    TesseraLedger ledger;
    tessera_ledger_open(&ledger);
    ledger.history = (TesseraHistory *)calloc(count, sizeof(TesseraHistory));
    ledger.history_room = count;
    for (unsigned int job = 0u; job < count; job += 1u)
    {
        ledger.history[job].signum = test_signum(1000ull + job);
        ledger.history[job].peak = jobs[job].declared;
        ledger.history[job].duration = jobs[job].duration;
    }
    ledger.history_count = count;
    unsigned long long identities[TEST_SCENARIO_JOBS];
    unsigned long long ends[TEST_SCENARIO_JOBS];
    int running[TEST_SCENARIO_JOBS];
    memset(running, 0, sizeof(running));
    unsigned int submitted = 0u;
    unsigned int done = 0u;
    unsigned long long now = 0ull;
    unsigned long long steps = 0ull;
    while ((done < count) && (steps < 100000ull))
    {
        steps += 1ull;
        for (unsigned int job = 0u; job < count; job += 1u)
        {
            if (running[job] && (ends[job] == now))
            {
                tessera_ledger_release(&ledger, identities[job], now, 1);
                running[job] = 0;
                done += 1u;
            }
        }
        while ((submitted < count) && (jobs[submitted].arrival <= now))
        {
            TesseraEvent event;
            const TesseraJobRequest request = test_request(1000ull + submitted, jobs[submitted].declared);
            tessera_ledger_submit(&ledger, &request, now, &identities[submitted], &event);
            submitted += 1u;
        }
        unsigned long long in_use = 0ull;
        for (unsigned int job = 0u; job < count; job += 1u)
        {
            in_use += running[job] ? jobs[job].declared : 0ull;
        }
        tessera_ledger_device(&ledger, capacity, in_use);
        const TesseraJob *const before = test_head(&ledger);
        const unsigned long long head = (before != NULL) ? before->identity : 0ull;
        // the test's bytes stay far below two to the sixty-third
        const int blocked = (before != NULL) && ((long long)before->request.declared > tessera_ledger_headroom(&ledger));
        const unsigned long long shadow_before = blocked ? test_shadow(&ledger, before->request.declared) : TEST_NEVER;
        TesseraEvent events[TEST_EVENTS];
        const unsigned long long made = tessera_ledger_admit(&ledger, now, events, TEST_EVENTS);
        for (unsigned long long event = 0ull; event < made; event += 1ull)
        {
            for (unsigned int job = 0u; job < count; job += 1u)
            {
                if ((job < submitted) && (identities[job] == events[event].identity))
                {
                    running[job] = 1;
                    ends[job] = now + jobs[job].duration;
                    in_use += jobs[job].declared;
                    TesseraEvent measured;
                    tessera_ledger_measure(&ledger, identities[job], jobs[job].declared, &measured);
                }
            }
        }
        tessera_ledger_device(&ledger, capacity, in_use);
        const TesseraJob *const after = tessera_ledger_job(&ledger, head);
        if (blocked && (after != NULL) && (after->state == TESSERA_JOB_WAITING))
        {
            test_check(kept, test_shadow(&ledger, after->request.declared) <= shadow_before);
        }
        unsigned long long next = TEST_NEVER;
        for (unsigned int job = 0u; job < count; job += 1u)
        {
            next = (running[job] && (ends[job] < next)) ? ends[job] : next;
        }
        next = ((submitted < count) && (jobs[submitted].arrival < next)) ? jobs[submitted].arrival : next;
        now = (next == TEST_NEVER) ? (now + 1ull) : next;
    }
    test_check(finished, done == count);
    tessera_ledger_close(&ledger);
}

static void test_backfill(TestTally *kept, TestTally *finished)
{
    for (unsigned int round = 0u; round < 20000u; round += 1u)
    {
        const unsigned int count = 2u + (unsigned int)test_below(TEST_SCENARIO_JOBS - 1u);
        const unsigned long long capacity = 100ull;
        TestScenarioJob jobs[TEST_SCENARIO_JOBS];
        unsigned long long arrival = 0ull;
        for (unsigned int job = 0u; job < count; job += 1u)
        {
            jobs[job].declared = 1ull + test_below(capacity);
            jobs[job].duration = 1ull + test_below(50ull);
            jobs[job].arrival = arrival;
            arrival += test_below(10ull);
        }
        test_scenario(kept, finished, jobs, count, capacity);
    }
}

int main(void)
{
    TestTally headroom = {"headroom identity", 0ull, 0ull};
    TestTally heap = {"deadlines in order", 0ull, 0ull};
    TestTally budget = {"budget, hold, override, lost", 0ull, 0ull};
    TestTally standing = {"standing beside the declaration", 0ull, 0ull};
    TestTally idle = {"idle teardown", 0ull, 0ull};
    TestTally kept = {"backfill keeps the head", 0ull, 0ull};
    TestTally finished = {"every scenario finishes", 0ull, 0ull};
    test_headroom(&headroom);
    test_heap_order(&heap);
    test_budget(&budget);
    test_standing(&standing);
    test_idle(&idle);
    test_backfill(&kept, &finished);
    test_report(&headroom);
    test_report(&heap);
    test_report(&budget);
    test_report(&standing);
    test_report(&idle);
    test_report(&kept);
    test_report(&finished);
    const unsigned long long failed = headroom.failed + heap.failed + budget.failed + standing.failed + idle.failed
                                    + kept.failed + finished.failed;
    printf("  tessera ledger: %llu failed\n", failed);
    return (failed == 0ull) ? 0 : 1;
}
