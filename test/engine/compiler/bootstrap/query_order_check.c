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
// advances, and takes the first that does. The known order is then put and solved, and every link has to come out
// dearer than the link before it. That is the claim held here: the solve, run on the part's own clock, orders links by
// the work they do. What each costs in counts, and whether the links contend, are printed and not held, since both are
// the part's to say.
#include "../../../../src/engine/compiler/bootstrap/query_order.h"

#include <stdio.h>

#define CHECK_LINKS 7u
#define CHECK_SWEEPS 45u

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
    static volatile unsigned int s_owned[CHECK_LINKS * 16u];
    QueryAsk link[CHECK_LINKS] = {{0}};
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        // a pointer widened to the 64-bit integer an ask carries, which host_entry.h narrows back to the same pointer
        link[number].address = (unsigned long long)&s_owned[number * 16u];
        link[number].qualifier = QUERY_ADVANCES;
        link[number].turns = 64ull * number;
    }

    QueryOrder order = {0};
    order.link = link;
    order.links = CHECK_LINKS;
    order.clock = clock;
    order.repeat = 1ull << 14;
    order.passes = 128u;
    unsigned long long cost[CHECK_LINKS];
    long long scaled[CHECK_LINKS];
    check_that(query_order_put(&order, cost) == 1, "the order is put over seven links");
    check_that(ask_order_solve(CHECK_LINKS, cost, scaled) == 1, "and solved");

    unsigned int rising = 1u;
    printf("  every link's cost, solved, in clock counts over %u passes of %llu puts:\n", order.passes, order.repeat);
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        // the scaled cost is (links + 1) times the link's own: 8 here
        printf("    link %u, %3llu reads: %lld\n", number, link[number].turns + 1ull,
               scaled[number] / (long long)(CHECK_LINKS + 1u));
        rising = ((number == 0u) || (scaled[number] > scaled[number - 1u])) ? rising : 0u;
    }
    check_that(rising == 1u, "every link costs more than the link before it, which reads 64 fewer times");

    unsigned long long sweep_cost[CHECK_SWEEPS];
    check_that(query_order_sweep(&order, 1u, CHECK_SWEEPS, sweep_cost) == 1, "the sweep asks are put");
    // each sweep ask is one pass, and the solve's costs are over `passes` of them
    const AskLinks read = ask_links_read(CHECK_LINKS, scaled, order.passes, 1u, sweep_cost, CHECK_SWEEPS);
    printf("  the links, read off %u sweep asks: %s\n", CHECK_SWEEPS,
           (read == ASK_LINKS_ADD) ? "add" : ((read == ASK_LINKS_CONTEND) ? "contend" : "unread"));
    check_that(read != ASK_LINKS_UNREAD, "the sweep asks give the contention read something to read");
#else
    printf("  no shared page named to this test on this platform: the order is not put\n");
#endif

    printf("  query order: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
