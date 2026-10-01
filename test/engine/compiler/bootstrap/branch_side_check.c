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
// Every branch is solved in exact integers, one pass a trial, and two branches compare at a link by cross-multiplying
// their exact costs. Nothing is summed and nothing is rounded. A trial reads first-dearer where the branch asked first
// is dearer at more of its seven links than not, and counts once: a slow pass lands on every link of the branch it
// falls in, and counting links apart would count one slow pass seven times. The sides are read apart where the trials
// lean past twice their own spread: (2·first - trials)² > 4·trials.
//
// One claim is held. Two branches that do not do the same work, the second reading 512 more times at every link,
// read the first as cheaper at every link, whichever side it is asked from: the sign follows the cost and not the
// side. Its trials are a descent: a link stands while its count leans past twice its spread neither way, and the
// trials end the first trial nothing stands, or at CHECK_TRIALS_MOST. Whether the side leaves a mark is printed and
// not held, since that is the part's to say. Its trials are not cut short where the count first leans: two branches
// doing the same work give a count that leans by chance at some trial more often than the spread says. It is read on
// the whole record, at CHECK_TRIALS_MOST. The run size is steered by the part, as query_descent.h states.
#include "query_descent.h"

#include <stdio.h>

#define CHECK_LINKS QUERY_DESCENT_LINKS
// the most trials either reading puts: the bound it is held to, fixed before it starts
#define CHECK_TRIALS_MOST 64u

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

// one branch's reading of one pass: its exact link costs, numerator[link] / denominator
typedef struct
{
    AnchorExactInteger numerator[CHECK_LINKS];
    AnchorExactInteger denominator;
} CheckReading;

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

// `link` put through the known order on `clock`, one pass of `repeat` puts, solved exactly
static void check_solve(const QueryAsk *link, unsigned long long clock, unsigned long long repeat, CheckReading *reading)
{
    static QueryCost s_cost[CHECK_LINKS];
    QueryOrder order = {0};
    order.link = link;
    order.links = CHECK_LINKS;
    order.clock = clock;
    order.repeat = repeat;
    order.passes = 1u;
    query_order_put(&order, s_cost);
    query_order_solve(CHECK_LINKS, s_cost, reading->numerator, &reading->denominator);
}

// the sign of one's cost less two's at `link`: one's numerator times two's denominator against the reverse
static int check_against(const CheckReading *one, const CheckReading *two, unsigned int link)
{
    AnchorExactInteger left;
    AnchorExactInteger right;
    anchor_exact_multiply(&one->numerator[link], &two->denominator, &left);
    anchor_exact_multiply(&two->numerator[link], &one->denominator, &right);
    return anchor_exact_compare(&left, &right);
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

    static QueryAsk s_left[CHECK_LINKS];
    static QueryAsk s_right[CHECK_LINKS];
    static CheckReading s_first;
    static CheckReading s_second;
    check_branch(s_left, 0u, 0ull);
    QueryOrder sized = {0};
    sized.link = s_left;
    sized.links = CHECK_LINKS;
    sized.clock = clock;
    QueryDescent kept;
    unsigned int solved = 0u;
    const unsigned long long repeat = query_descent_size(&sized, &kept, &solved);

    // the held claim: the sign follows the cost from either side, a bit for every trial at every link, 1 where the
    // cheaper branch reads cheaper
    check_branch(s_right, 1u, 512ull);
    unsigned int cheaper[CHECK_LINKS] = {0u};
    unsigned int trials = 0u;
    unsigned int standing = CHECK_LINKS;
    while ((standing > 0u) && (trials < CHECK_TRIALS_MOST))
    {
        const unsigned int cheap_first = ((trials % 2u) == 0u) ? 1u : 0u;
        check_solve((cheap_first != 0u) ? s_left : s_right, clock, repeat, &s_first);
        check_solve((cheap_first != 0u) ? s_right : s_left, clock, repeat, &s_second);
        trials += 1u;
        standing = 0u;
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            const int first_less = check_against(&s_first, &s_second, number) < 0;
            cheaper[number] += ((first_less != 0) == (cheap_first != 0u)) ? 1u : 0u;
            const int decided = (query_descent_leans(cheaper[number], trials) != 0) ||
                                (query_descent_leans(trials - cheaper[number], trials) != 0);
            standing += (decided != 0) ? 0u : 1u;
        }
    }
    unsigned int followed = 0u;
    printf("  branches 512 reads apart at every link, the cheaper read cheaper, link by link:");
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        printf(" %u", cheaper[number]);
        followed += (query_descent_leans(cheaper[number], trials) != 0) ? 1u : 0u;
    }
    printf(" of %u trials, from both sides alike\n", trials);
    check_that(followed == CHECK_LINKS, "the cheaper branch reads cheaper at every link past twice the spread");

    // the experiment: two branches doing the same work, read on its whole record
    check_branch(s_right, 1u, 0ull);
    unsigned int first_dearer = 0u;
    unsigned int link_first_dearer[CHECK_LINKS] = {0u};
    for (unsigned int trial = 0u; trial < CHECK_TRIALS_MOST; trial += 1u)
    {
        const unsigned int left_first = ((trial % 2u) == 0u) ? 1u : 0u;
        check_solve((left_first != 0u) ? s_left : s_right, clock, repeat, &s_first);
        check_solve((left_first != 0u) ? s_right : s_left, clock, repeat, &s_second);
        unsigned int dearer = 0u;
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            const unsigned int link_dearer = (check_against(&s_first, &s_second, number) > 0) ? 1u : 0u;
            dearer += link_dearer;
            link_first_dearer[number] += link_dearer;
        }
        // seven links never split evenly
        first_dearer += ((2u * dearer) > CHECK_LINKS) ? 1u : 0u;
    }
    const int marked = (query_descent_leans(first_dearer, CHECK_TRIALS_MOST) != 0) ||
                       (query_descent_leans(CHECK_TRIALS_MOST - first_dearer, CHECK_TRIALS_MOST) != 0);
    printf("  branches doing the same work, %u trials, the side asked first changing every trial:\n", CHECK_TRIALS_MOST);
    printf("    the branch asked first reads dearer in %u, the other in %u\n", first_dearer,
           CHECK_TRIALS_MOST - first_dearer);
    printf("    the branch asked first reads dearer, link by link:");
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        printf(" %u", link_first_dearer[number]);
    }
    printf(" of %u\n", CHECK_TRIALS_MOST);
    const char *const verdict = (marked != 0) ? "leaves a mark" : "leaves no mark";
    printf("    the side asked from %s past twice the spread\n", verdict);
#else
    printf("  no shared page named to this test on this platform: the branches are not put\n");
#endif

    printf("  branch side: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
