// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_order_check.c: the known order of asks put to the host through the query protocol, and its solve held to the
// work each link does
//
// Seven links, each an ask at a word the test owns and nothing writes: QUERY_ADVANCES, which reads the word until it
// moves or its turns run out. A still word never moves, and link k reads it 1 + 64·k times: the work each link
// does is known and the links are far apart in it. One access against five is not far apart: an ask's own overhead is
// larger than four reads, and the order put over QUERY_HOLDS against QUERY_EQUALS does not tell them apart.
//
// The clock is not named to the order: the test asks every word of the page every Windows process shares whether it
// advances, and takes the first that does. The clock turns over now and then, and a run is read on it finely by
// counting reads of the clock between turns, its cost the exact rational that gives. The known order is then put, every
// pass is solved on its own in exact integers, and every link has to come out dearer than the link before it, past
// twice the spread. That is the claim held here: the solve, run on the part's own clock with nothing rounded and
// nothing summed away, orders links by the work they do.
//
// The run size and the count of passes are steered by the part, as query_descent.h states. The claim is read on the
// record of the size kept: every pair has to lean dearer on one same pass, over every pass put at that size.
#include "query_descent.h"

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

int main(void)
{
#if defined(_WIN32)
    // the clock, found by asking: the first word of the shared page's head that advances
    const unsigned long long page = 0x7ffe0000ull;
    unsigned long long clock = 0ull;
    for (unsigned long long word = 0ull; (word < 16ull) && (clock == 0ull); word += 1ull)
    {
        QueryAsk counts = {0};
        counts.address = page + (word * 4ull);
        counts.qualifier = QUERY_ADVANCES;
        counts.turns = 1ull << 26;
        clock = (query_ask(&counts) == 1u) ? counts.address : 0ull;
    }
    check_that(clock != 0ull, "a word of the shared page advances, and it is the clock");
    printf("  the clock, found by asking: 0x%llx\n", clock);

    // a word for each link, a cache line apart
    static volatile unsigned int s_owned[QUERY_DESCENT_LINKS * 16u];
    QueryAsk link[QUERY_DESCENT_LINKS] = {{0}};
    for (unsigned int number = 0u; number < QUERY_DESCENT_LINKS; number += 1u)
    {
        // a pointer widened to the 64-bit integer an ask carries, which host_entry.h narrows back to the same pointer
        link[number].address = (unsigned long long)&s_owned[number * 16u];
        link[number].qualifier = QUERY_ADVANCES;
        link[number].turns = 64ull * number;
    }

    QueryOrder order = {0};
    order.link = link;
    order.links = QUERY_DESCENT_LINKS;
    order.clock = clock;

    // Held at the size the descent kept. Every pass solved on its own, exactly, and every pair of neighboring links
    // compared in it: a bit a pass, 1 where the link that reads 64 more times costs more. Nothing is summed across
    // passes and nothing is cut to a least
    QueryDescent held;
    unsigned int solved = 0u;
    query_descent_size(&order, &held, &solved);
    check_that(solved == 1u, "every pass solves exactly inside the exact width");
    unsigned int ordered = 0u;
    printf("  at %llu puts a run, each pass solved exactly, %u passes put, the link reading 64 more times:\n",
           order.repeat, held.passes);
    for (unsigned int number = 1u; number < QUERY_DESCENT_LINKS; number += 1u)
    {
        ordered += (held.decided[number] == QUERY_DESCENT_DEARER) ? 1u : 0u;
        const char *leans = (held.decided[number] == QUERY_DESCENT_DEARER)    ? ""
                            : (held.decided[number] == QUERY_DESCENT_CHEAPER) ? ", leaning cheaper"
                                                                              : ", not past twice the spread";
        printf("    link %u over link %u: dearer in %u of %u passes%s\n", number, number - 1u, held.dearer[number],
               held.passes, leans);
    }
    check_that(ordered == (QUERY_DESCENT_LINKS - 1u),
               "every link is decided dearer than the one before it past the spread");
#else
    printf("  no shared page named to this test on this platform: the order is not put\n");
#endif

    printf("  query order: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
