// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_ask_check.c: the query protocol's ask, held to what it says on addresses whose answers are known
//
// Each check puts an ask to an address whose state the test set itself, or to one a reader can name as a counter,
// and holds the bit, the kind and the cost to what that address has to answer:
//
//   holds      memory the test owns gives back both words it is put, and is left as it was found
//   equals     a word the test wrote reads as that word, and as no other
//   advances   a word nothing writes does not advance
//   bound      a bound with no clock reads 0 past the bound, and an unbound ask carries its kind
//   clock      a counter named by the platform advances under the ADVANCES qualifier, and an ask clocked on it
//              returns a cost that a bound below it fails and a bound above it passes
//
// Only the counter sits at an address the test does not own. On Windows every process can read the
// interrupt time the kernel keeps at 0x7FFE0008 with a plain load and no call: the test forms its question there,
// and the protocol's answer is checked against the fact that the word counts. A platform that names no such address
// to the test skips the clock checks and says so.
#include "../../../../../../src/c/transpiler/bootstrap/query_ask.h"

#include <stdio.h>

static unsigned int s_checks = 0u;
static unsigned int s_failed = 0u;

static void check_that(int held, const char *what)
{
    s_checks += 1u;
    if (held == 0)
    {
        s_failed += 1u;
        printf("  FAILED: %s\n", what);
    }
}

// an address in this program, as the integer an ask carries
static unsigned long long check_address(volatile unsigned int *word)
{
    // a pointer widened to the 64-bit integer an ask carries, which host_entry.h narrows back to the same pointer
    return (unsigned long long)word;
}

int main(void)
{
    static volatile unsigned int s_owned[4] = {0x1234u, 0x5678u, 0u, 0u};

    QueryAsk asked = {0};
    asked.address = check_address(&s_owned[0]);
    asked.qualifier = QUERY_HOLDS;
    check_that(query_ask(&asked) == 1u, "owned memory holds what it is given");
    check_that(asked.kind == QUERY_HELD, "holding reads as held");
    check_that(s_owned[0] == 0x1234u, "a holding ask leaves the word as it found it");
    check_that(asked.cost_read == 0u, "an ask given no clock reports its cost unread");

    QueryAsk equals = {0};
    equals.address = check_address(&s_owned[1]);
    equals.qualifier = QUERY_EQUALS;
    equals.word = 0x5678u;
    check_that(query_ask(&equals) == 1u, "a written word equals itself");
    equals.word = 0x5679u;
    check_that(query_ask(&equals) == 0u, "a written word equals no other word");
    check_that(equals.kind == QUERY_NOT_HELD, "a qualifier that does not hold reads as not held");

    QueryAsk still = {0};
    still.address = check_address(&s_owned[2]);
    still.qualifier = QUERY_ADVANCES;
    check_that(query_ask(&still) == 0u, "a word nothing writes does not advance");

    QueryAsk unclocked = {0};
    unclocked.address = check_address(&s_owned[1]);
    unclocked.qualifier = QUERY_EQUALS;
    unclocked.word = 0x5678u;
    unclocked.bound = 1000ull;
    check_that(query_ask(&unclocked) == 0u, "a bound with no clock to read it against reads 0");
    check_that(unclocked.kind == QUERY_PAST_BOUND, "and reads as past its bound, not as not held");

#if defined(_WIN32)
    const unsigned long long clock = 0x7ffe0008ull;
    QueryAsk counts = {0};
    counts.address = clock;
    counts.qualifier = QUERY_ADVANCES;
    // The counter is kept in hundred-nanosecond counts and is stepped once per clock interrupt: it moves by a whole
    // interrupt at a time and an ask is far shorter than one. The ADVANCES ask reads until the counter moves, and
    // every clocked ask below is put until the counter moves under it; each cap is far past the reads one interrupt
    // takes
    const unsigned int turns = 1u << 30;
    counts.turns = turns;
    check_that(query_ask(&counts) == 1u, "the interrupt time advances under the ADVANCES qualifier, asked once");
    QueryAsk once = counts;
    once.turns = 0ull;
    unsigned int caught = 0u;
    for (unsigned int turn = 0u; turn < 1000u; turn += 1u)
    {
        caught += query_ask(&once);
    }
    check_that(caught < 1000u, "two reads in a row see the counter still more often than not");

    // an ask clocked on that counter, put until one ask has a step of the counter inside it
    QueryAsk timed = {0};
    timed.address = check_address(&s_owned[1]);
    timed.qualifier = QUERY_EQUALS;
    timed.word = 0x5678u;
    timed.clock = clock;
    unsigned int put = 0u;
    for (put = 0u; (put < turns) && (timed.cost == 0ull); put += 1u)
    {
        query_ask(&timed);
    }
    const unsigned long long step = timed.cost;
    check_that(timed.cost_read == 1u, "an ask given a clock reads its cost");
    check_that(step > 0ull, "an ask put until the counter moves under it reads a cost above nothing");
    check_that(timed.kind == QUERY_HELD, "an unbound ask that held reads as held, whatever it cost");

    // the bound judged against the cost the ask itself read: a bound past one step of the counter holds wherever the
    // ask lasts less than two steps, and a bound of one count fails on the ask a step lands inside
    timed.bound = (step * 2ull) + 1ull;
    check_that(query_ask(&timed) == 1u, "a bound past two steps of the counter holds");
    QueryAsk tight = timed;
    tight.bound = 1ull;
    unsigned int failed_tight = 0u;
    for (unsigned int turn = 0u; (turn < turns) && (failed_tight == 0u); turn += 1u)
    {
        failed_tight = ((query_ask(&tight) == 0u) && (tight.kind == QUERY_PAST_BOUND)) ? 1u : 0u;
    }
    check_that(failed_tight == 1u, "a bound of one count fails on the ask a step of the counter lands inside");
    printf("  the clock at 0x%llx: one step is %llu counts, read after %u asks\n", clock, step, put);
#else
    printf("  no counter named to this test on this platform: the clock checks are skipped\n");
#endif

    printf("  query ask: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
