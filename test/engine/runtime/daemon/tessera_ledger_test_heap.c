// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_ledger_test_heap.c: requests, headroom, heap order and budget
#include "tessera_ledger_test_internal.h"

static unsigned long long test_state = 0x9E3779B97F4A7C15ull;

static unsigned long long test_random(void)
{
    test_state ^= test_state << 13u;
    test_state ^= test_state >> 7u;
    test_state ^= test_state << 17u;
    return test_state;
}

unsigned long long test_below(unsigned long long bound)
{
    return test_random() % bound;
}

void test_check(TestResults *results, int passed)
{
    results->cases += 1ull;
    results->failed += passed ? 0ull : 1ull;
}

void test_report(const TestResults *results)
{
    printf("  %-30s %9llu cases, %llu failed\n", results->name, results->cases, results->failed);
}

EngineSignum test_signum(unsigned long long seed)
{
    EngineSignum signum;
    memset(&signum, 0, sizeof(signum));
    for (unsigned int at = 0u; at < 8u; at += 1u)
    {
        // each byte is one eighth of the seed, which fits in an unsigned char
        signum.bytes[at] = (unsigned char)(seed >> (8u * at));
    }
    return signum;
}

TesseraJobRequest test_request(unsigned long long seed, unsigned long long declared)
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

void test_headroom(TestResults *results)
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
        test_check(results, tessera_ledger_headroom(&ledger) == test_headroom_direct(&ledger));
        tessera_ledger_close(&ledger);
    }
}

void test_heap_order(TestResults *results)
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
        test_check(results, ordered && (fired == 3000ull));
        tessera_ledger_close(&ledger);
    }
}

void test_budget(TestResults *results)
{
    TesseraLedger ledger;
    tessera_ledger_open(&ledger);
    tessera_ledger_device(&ledger, 1000ull, 0ull);
    unsigned long long first = 0ull;
    TesseraEvent event;
    TesseraEvent events[TEST_EVENTS];
    const TesseraJobRequest request = test_request(7ull, 400ull);
    test_check(results,
               tessera_ledger_submit(&ledger, &request, 0ull, &first, &event) && (event.kind == TESSERA_EVENT_NONE));
    test_check(results, (tessera_ledger_admit(&ledger, 0ull, events, TEST_EVENTS) == 1ull) &&
                            (events[0].kind == TESSERA_EVENT_ADMITTED));
    test_check(results, tessera_ledger_measure(&ledger, first, 250ull, &event) && (event.kind == TESSERA_EVENT_NONE));
    test_check(results, tessera_ledger_measure(&ledger, first, 450ull, &event) && (event.kind == TESSERA_EVENT_GREW) &&
                            (tessera_ledger_job(&ledger, first)->reservation == 450ull) && (event.measured == 450ull));
    test_check(results, tessera_ledger_measure(&ledger, first, 300ull, &event) &&
                            (tessera_ledger_job(&ledger, first)->reservation == 450ull));
    test_check(results, tessera_ledger_release(&ledger, first, 90ull, 1));
    const TesseraHistory *const previous = tessera_ledger_history(&ledger, &request.signum);
    test_check(results, (previous != NULL) && (previous->peak == 450ull) && (previous->duration == 90ull));

    unsigned long long second = 0ull;
    const TesseraJobRequest greedy = test_request(7ull, 600ull);
    test_check(results, tessera_ledger_submit(&ledger, &greedy, 100ull, &second, &event) &&
                            (event.kind == TESSERA_EVENT_ASKED) && (event.measured == 450ull) &&
                            (tessera_ledger_job(&ledger, second)->state == TESSERA_JOB_HELD));
    test_check(results, tessera_ledger_admit(&ledger, 100ull, events, TEST_EVENTS) == 0ull);
    test_check(results, !tessera_ledger_fire(&ledger, 100ull + 999ull, &event));
    test_check(results, tessera_ledger_fire(&ledger, 100ull + 1000ull, &event) && (event.kind == TESSERA_EVENT_LOST) &&
                            (event.identity == second) && (tessera_ledger_job(&ledger, second) == NULL));

    unsigned long long third = 0ull;
    test_check(results,
               tessera_ledger_submit(&ledger, &greedy, 2000ull, &third, &event) && (event.kind == TESSERA_EVENT_ASKED));
    test_check(results, tessera_ledger_override(&ledger, third, 2500ull) &&
                            (tessera_ledger_job(&ledger, third)->state == TESSERA_JOB_WAITING));
    test_check(results,
               (tessera_ledger_admit(&ledger, 2500ull, events, TEST_EVENTS) == 1ull) && (events[0].bytes == 600ull));
    int lost_after_override = 0;
    while (tessera_ledger_fire(&ledger, 3000ull, &event))
    {
        lost_after_override = lost_after_override || (event.kind == TESSERA_EVENT_LOST);
    }
    test_check(results, lost_after_override == 0);
    test_check(results, tessera_ledger_release(&ledger, third, 3100ull, 0) &&
                            (tessera_ledger_history(&ledger, &greedy.signum)->peak == 450ull));

    unsigned long long late = 0ull;
    test_check(results, tessera_ledger_submit(&ledger, &greedy, 4000ull, &late, &event) &&
                            !tessera_ledger_override(&ledger, late, 5001ull));
    const TesseraJobRequest empty = test_request(9ull, 0ull);
    unsigned long long refused = 0ull;
    test_check(results, !tessera_ledger_submit(&ledger, &empty, 6000ull, &refused, &event));
    tessera_ledger_close(&ledger);

    // declaring under its kept peak, a job is reserved the peak: with room for its declaration but not its peak it
    // waits, and once the peak fits it is admitted holding the peak
    TesseraLedger kept;
    tessera_ledger_open(&kept);
    tessera_ledger_device(&kept, 1000ull, 700ull);
    const TesseraHistory remembered = {request.signum, 450ull, 90ull};
    test_check(results, tessera_ledger_remember(&kept, &remembered));
    unsigned long long modest = 0ull;
    const TesseraJobRequest under = test_request(7ull, 100ull);
    test_check(results, tessera_ledger_submit(&kept, &under, 7000ull, &modest, &event) &&
                            (event.kind == TESSERA_EVENT_NONE) &&
                            (tessera_ledger_wants(&kept, tessera_ledger_job(&kept, modest)) == 450ull));
    test_check(results, tessera_ledger_admit(&kept, 7000ull, events, TEST_EVENTS) == 0ull);
    tessera_ledger_device(&kept, 1000ull, 500ull);
    test_check(results, (tessera_ledger_admit(&kept, 7100ull, events, TEST_EVENTS) == 1ull) &&
                            (events[0].bytes == 450ull) && (tessera_ledger_job(&kept, modest)->reservation == 450ull));
    tessera_ledger_close(&kept);
}
