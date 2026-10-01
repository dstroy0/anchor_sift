// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// branch_side_check.c: whether the side a branch is asked from leaves a mark on its reading, put to the host
//
//     branch_side_check
//
// gnascor names a steady LEAD and a steady RITE apart, CORE and SURV. LEAD and RITE are the sign of the signed
// difference between two branches at a link, and the two names are one state seen from either side unless the side
// itself leaves a mark. This asks the part whether it does. Two branches doing the same work, seven links each, are
// put through the known order one after the other, the one asked first changing from trial to trial, and every
// link's solved cost read against the other branch's. If asking first leaves no mark, the first branch reads dearer
// in as many trials as the second does.
//
// A trial counts once, by the sign of its summed difference over every link: a slow pass lands on every link of the
// branch it falls in, and counting links apart would count one slow pass seven times. The sides are read apart where
// the count leans past twice its own spread: (2·first - trials)² > 4·trials, every term an exact integer.
//
// One claim is held. Two branches that do not do the same work, the second reading 512 more times at every link,
// read the first as cheaper at every link whichever side it is asked from: the sign follows the cost and not the side.
// Whether the side leaves a mark is printed and not held, since that is the part's to say.
#include "../../../../src/engine/compiler/bootstrap/query_order.h"

#include <stdio.h>

#define CHECK_LINKS 7u
#define CHECK_TRIALS 64u
#define CHECK_UNEQUAL 8u

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

#if defined(_WIN32)
// a word for every link of both branches, a cache line apart
static volatile unsigned int s_owned[2u * CHECK_LINKS * 16u];

// a branch: seven links reading a still word, link k `extra` + 64·k more times past its first read
static void check_branch(QueryAsk *link, unsigned int side, unsigned long long extra)
{
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        QueryAsk asked = {0};
        // a pointer widened to the 64-bit integer an ask carries, which host_entry.h narrows back to the same pointer
        asked.address = (unsigned long long)&s_owned[((side * CHECK_LINKS) + number) * 16u];
        asked.qualifier = QUERY_ADVANCES;
        asked.turns = extra + (64ull * number);
        link[number] = asked;
    }
}

// every link's scaled cost for `link`, put through the known order on `clock`
static void check_solve(const QueryAsk *link, unsigned long long clock, long long *scaled)
{
    QueryOrder order = {0};
    order.link = link;
    order.links = CHECK_LINKS;
    order.clock = clock;
    order.repeat = 1ull << 12;
    order.passes = 16u;
    unsigned long long cost[CHECK_LINKS];
    query_order_put(&order, cost);
    ask_order_solve(CHECK_LINKS, cost, scaled);
}
#endif

int main(void)
{
#if defined(_WIN32)
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

    QueryAsk left[CHECK_LINKS];
    QueryAsk right[CHECK_LINKS];
    long long first[CHECK_LINKS];
    long long second[CHECK_LINKS];

    // the held claim: the sign follows the cost from either side
    check_branch(left, 0u, 0ull);
    check_branch(right, 1u, 512ull);
    unsigned int followed = 0u;
    for (unsigned int trial = 0u; trial < CHECK_UNEQUAL; trial += 1u)
    {
        const unsigned int cheap_first = ((trial % 2u) == 0u) ? 1u : 0u;
        check_solve((cheap_first != 0u) ? left : right, clock, first);
        check_solve((cheap_first != 0u) ? right : left, clock, second);
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            const long long cheap = (cheap_first != 0u) ? first[number] : second[number];
            const long long dear = (cheap_first != 0u) ? second[number] : first[number];
            followed += (cheap < dear) ? 1u : 0u;
        }
    }
    printf("  branches 512 reads apart at every link: the cheaper read cheaper at %u of %u links\n", followed,
           CHECK_UNEQUAL * CHECK_LINKS);
    check_that(followed == (CHECK_UNEQUAL * CHECK_LINKS),
               "the cheaper branch reads cheaper at every link from either side");

    // the experiment: two branches doing the same work
    check_branch(right, 1u, 0ull);
    unsigned int first_dearer = 0u;
    unsigned int ties = 0u;
    long long side_sum = 0ll;
    unsigned int link_first_dearer[CHECK_LINKS] = {0u};
    for (unsigned int trial = 0u; trial < CHECK_TRIALS; trial += 1u)
    {
        const unsigned int left_first = ((trial % 2u) == 0u) ? 1u : 0u;
        check_solve((left_first != 0u) ? left : right, clock, first);
        check_solve((left_first != 0u) ? right : left, clock, second);
        long long apart = 0ll;
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            apart += first[number] - second[number];
            link_first_dearer[number] += (first[number] > second[number]) ? 1u : 0u;
        }
        side_sum += apart;
        if (apart == 0ll)
        {
            ties += 1u;
        }
        else if (apart > 0ll)
        {
            first_dearer += 1u;
        }
    }
    const long long counted = (long long)(CHECK_TRIALS - ties);
    const long long lean = (2ll * (long long)first_dearer) - counted;
    const int marked = (counted > 0ll) && ((lean * lean) > (4ll * counted));
    printf("  branches doing the same work, %u trials, the side asked first changing every trial:\n", CHECK_TRIALS);
    printf("    the branch asked first reads dearer in %u, the other in %lld, %u even\n", first_dearer,
           counted - (long long)first_dearer, ties);
    printf("    the summed difference, first less second, over every trial and link: %lld scaled counts\n", side_sum);
    printf("    the branch asked first reads dearer, link by link:");
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        printf(" %u", link_first_dearer[number]);
    }
    printf(" of %u\n", CHECK_TRIALS);
    const char *const verdict = (marked != 0) ? "leaves a mark" : "leaves no mark";
    printf("    the side asked from %s past twice the spread\n", verdict);
#else
    printf("  no shared page named to this test on this platform: the branches are not put\n");
#endif

    printf("  branch side: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
