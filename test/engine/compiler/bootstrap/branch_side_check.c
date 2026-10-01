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
// Every pass of every branch is solved on its own, in exact integers, and two branches compare at a link in a pass by
// cross-multiplying their exact costs. Nothing is summed and nothing is rounded. A trial reads first-dearer where the
// branch asked first is dearer in more of its pass-and-link comparisons than not, and counts once: a slow pass lands
// on every link of the branch it falls in, and counting links apart would count one slow pass seven times. The sides
// are read apart where the trials lean past twice their own spread: (2·first - trials)² > 4·trials.
//
// One claim is held. Two branches that do not do the same work, the second reading 512 more times at every link,
// read the first as cheaper at every link in more passes than not, whichever side it is asked from: the sign follows
// the cost and not the side. Whether the side leaves a mark is printed and not held, since that is the part's to say.
// The run size is read off the part as query_order_check reads it: the size whose weakest neighbor pair leans hardest.
#include "../../../../src/engine/compiler/bootstrap/query_order.h"

#include <stdio.h>

#define CHECK_LINKS 7u
#define CHECK_TRIALS 32u
#define CHECK_UNEQUAL 8u
#define CHECK_PASSES 8u
#define CHECK_PICK_PASSES 16u
#define CHECK_SIZE_LEAST 10u
#define CHECK_SIZE_MOST 16u

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

// one branch's reading: every pass's exact link costs, numerator[pass][link] / denominator[pass]
typedef struct
{
    AnchorExactInteger numerator[CHECK_PICK_PASSES][CHECK_LINKS];
    AnchorExactInteger denominator[CHECK_PICK_PASSES];
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

// `link` put through the known order on `clock`, `passes` passes of `repeat` puts, every pass solved exactly
static void check_solve(const QueryAsk *link, unsigned long long clock, unsigned long long repeat, unsigned int passes,
                        CheckReading *reading)
{
    static QueryCost s_cost[CHECK_PICK_PASSES * CHECK_LINKS];
    QueryOrder order = {0};
    order.link = link;
    order.links = CHECK_LINKS;
    order.clock = clock;
    order.repeat = repeat;
    order.passes = passes;
    query_order_put(&order, s_cost);
    for (unsigned int pass = 0u; pass < passes; pass += 1u)
    {
        query_order_solve(CHECK_LINKS, &s_cost[pass * CHECK_LINKS], reading->numerator[pass],
                          &reading->denominator[pass]);
    }
}

// the sign of one's cost less two's at `link` in `pass`: one's numerator times two's denominator against the reverse
static int check_against(const CheckReading *one, const CheckReading *two, unsigned int pass, unsigned int link)
{
    AnchorExactInteger left;
    AnchorExactInteger right;
    anchor_exact_multiply(&one->numerator[pass][link], &two->denominator[pass], &left);
    anchor_exact_multiply(&two->numerator[pass][link], &one->denominator[pass], &right);
    return anchor_exact_compare(&left, &right);
}

// `count`, a count, as an exact integer
static void check_exact(AnchorExactInteger *value, unsigned int count)
{
    anchor_exact_zero(value);
    value->limb[0] = count;
    value->sign = (count != 0u) ? 1 : 0;
}

// whether `some` of `of` leans past twice its own spread either way: (2·some - of)² > 4·of, every term exact
static int check_leans(unsigned int some, unsigned int of)
{
    AnchorExactInteger twice;
    AnchorExactInteger whole;
    AnchorExactInteger lean;
    AnchorExactInteger square;
    AnchorExactInteger four;
    check_exact(&twice, 2u * some);
    check_exact(&whole, of);
    check_exact(&four, 4u * of);
    if ((anchor_exact_subtract(&twice, &whole, &lean) != ANCHOR_EXACT_OK) ||
        (anchor_exact_multiply(&lean, &lean, &square) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    return (anchor_exact_compare(&square, &four) > 0) ? 1 : 0;
}

// the run size whose weakest neighbor pair, over one branch's links, reads dearer in the most passes
static unsigned long long check_size(const QueryAsk *link, unsigned long long clock, CheckReading *reading)
{
    unsigned long long kept = 0ull;
    unsigned int kept_weakest = 0u;
    for (unsigned int power = CHECK_SIZE_LEAST; power <= CHECK_SIZE_MOST; power += 2u)
    {
        check_solve(link, clock, 1ull << power, CHECK_PICK_PASSES, reading);
        unsigned int weakest = CHECK_PICK_PASSES;
        for (unsigned int number = 1u; number < CHECK_LINKS; number += 1u)
        {
            unsigned int dearer = 0u;
            for (unsigned int pass = 0u; pass < CHECK_PICK_PASSES; pass += 1u)
            {
                // one pass's links share one denominator: the numerators order them
                const int order =
                    anchor_exact_compare(&reading->numerator[pass][number], &reading->numerator[pass][number - 1u]);
                dearer += (order > 0) ? 1u : 0u;
            }
            weakest = (dearer < weakest) ? dearer : weakest;
        }
        if ((kept == 0ull) || (weakest > kept_weakest))
        {
            kept = 1ull << power;
            kept_weakest = weakest;
        }
    }
    return kept;
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
    const unsigned long long repeat = check_size(s_left, clock, &s_first);
    printf("  the part names 2^%u puts a run\n", (unsigned int)__builtin_ctzll(repeat));

    // the held claim: the sign follows the cost from either side
    check_branch(s_right, 1u, 512ull);
    // a bit for every trial and pass at every link, 1 where the cheaper branch reads cheaper
    unsigned int cheaper[CHECK_LINKS] = {0u};
    for (unsigned int trial = 0u; trial < CHECK_UNEQUAL; trial += 1u)
    {
        const unsigned int cheap_first = ((trial % 2u) == 0u) ? 1u : 0u;
        check_solve((cheap_first != 0u) ? s_left : s_right, clock, repeat, CHECK_PASSES, &s_first);
        check_solve((cheap_first != 0u) ? s_right : s_left, clock, repeat, CHECK_PASSES, &s_second);
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            for (unsigned int pass = 0u; pass < CHECK_PASSES; pass += 1u)
            {
                const int first_less = check_against(&s_first, &s_second, pass, number) < 0;
                cheaper[number] += ((first_less != 0) == (cheap_first != 0u)) ? 1u : 0u;
            }
        }
    }
    const unsigned int compared = CHECK_UNEQUAL * CHECK_PASSES;
    unsigned int followed = 0u;
    printf("  branches 512 reads apart at every link, the cheaper read cheaper, link by link:");
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        printf(" %u", cheaper[number]);
        followed += (((2u * cheaper[number]) > compared) && (check_leans(cheaper[number], compared) != 0)) ? 1u : 0u;
    }
    printf(" of %u, from both sides alike\n", compared);
    check_that(followed == CHECK_LINKS, "the cheaper branch reads cheaper at every link past twice the spread");

    // the experiment: two branches doing the same work
    check_branch(s_right, 1u, 0ull);
    unsigned int first_dearer = 0u;
    unsigned int even = 0u;
    unsigned int link_first_dearer[CHECK_LINKS] = {0u};
    for (unsigned int trial = 0u; trial < CHECK_TRIALS; trial += 1u)
    {
        const unsigned int left_first = ((trial % 2u) == 0u) ? 1u : 0u;
        check_solve((left_first != 0u) ? s_left : s_right, clock, repeat, CHECK_PASSES, &s_first);
        check_solve((left_first != 0u) ? s_right : s_left, clock, repeat, CHECK_PASSES, &s_second);
        unsigned int dearer = 0u;
        for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
        {
            unsigned int link_dearer = 0u;
            for (unsigned int pass = 0u; pass < CHECK_PASSES; pass += 1u)
            {
                link_dearer += (check_against(&s_first, &s_second, pass, number) > 0) ? 1u : 0u;
            }
            dearer += link_dearer;
            link_first_dearer[number] += ((2u * link_dearer) > CHECK_PASSES) ? 1u : 0u;
        }
        const unsigned int compared = CHECK_PASSES * CHECK_LINKS;
        if ((2u * dearer) == compared)
        {
            even += 1u;
        }
        else if ((2u * dearer) > compared)
        {
            first_dearer += 1u;
        }
    }
    const unsigned int counted = CHECK_TRIALS - even;
    const int marked = (counted > 0u) && (check_leans(first_dearer, counted) != 0);
    printf("  branches doing the same work, %u trials, the side asked first changing every trial:\n", CHECK_TRIALS);
    printf("    the branch asked first reads dearer in %u, the other in %u, %u even\n", first_dearer,
           counted - first_dearer, even);
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
