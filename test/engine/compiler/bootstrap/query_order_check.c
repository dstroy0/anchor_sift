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
// pass is solved on its own in exact integers, and every link has to come out dearer than the link before it in more
// passes than not, past twice the spread. That is the claim held here: the solve, run on the part's own clock with
// nothing rounded and nothing summed away, orders links by the work they do.
#include "../../../../src/engine/compiler/bootstrap/query_order.h"

#include <stdio.h>

#define CHECK_LINKS 7u
#define CHECK_PASSES 64u
// the passes each run size is read over before one is kept, and the sizes read, as powers of two puts a run
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
// The order put over `order->passes` passes, every pass solved on its own, and for every link the passes it read
// dearer than the link before it in, into `dearer`. 1 where every pass solved inside the exact width
static unsigned int check_read(const QueryOrder *order, unsigned int *dearer)
{
    static QueryCost s_cost[CHECK_PASSES * CHECK_LINKS];
    unsigned int solved = (query_order_put(order, s_cost) == 1) ? 1u : 0u;
    for (unsigned int number = 0u; number < CHECK_LINKS; number += 1u)
    {
        dearer[number] = 0u;
    }
    for (unsigned int pass = 0u; pass < order->passes; pass += 1u)
    {
        AnchorExactInteger numerator[CHECK_LINKS];
        AnchorExactInteger denominator;
        if (query_order_solve(CHECK_LINKS, &s_cost[pass * CHECK_LINKS], numerator, &denominator) == 0)
        {
            solved = 0u;
            continue;
        }
        for (unsigned int number = 1u; number < CHECK_LINKS; number += 1u)
        {
            // one pass's links share one denominator, and its sign is positive: the numerators order them
            dearer[number] += (anchor_exact_compare(&numerator[number], &numerator[number - 1u]) > 0) ? 1u : 0u;
        }
    }
    return solved;
}

// `count`, a count, as an exact integer
static void check_exact(AnchorExactInteger *value, unsigned int count)
{
    anchor_exact_zero(value);
    value->limb[0] = count;
    value->sign = (count != 0u) ? 1 : 0;
}

// Whether `dearer` of `passes` leans past twice its own spread toward dearer: 2 * dearer - passes is positive and
// its square is past 4 * passes. Every term an exact integer
static int check_leans(unsigned int dearer, unsigned int passes)
{
    AnchorExactInteger twice;
    AnchorExactInteger whole;
    AnchorExactInteger lean;
    AnchorExactInteger square;
    AnchorExactInteger four;
    check_exact(&twice, 2u * dearer);
    check_exact(&whole, passes);
    check_exact(&four, 4u * passes);
    if ((anchor_exact_subtract(&twice, &whole, &lean) != ANCHOR_EXACT_OK) || (lean.sign <= 0) ||
        (anchor_exact_multiply(&lean, &lean, &square) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    return (anchor_exact_compare(&square, &four) > 0) ? 1 : 0;
}
#endif

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

    // The run size is the part's to name. A short run drowns in the counting's own spread and a long one gathers
    // whatever else the part is doing: the floor has a least between them, and where it falls is read. Each size is
    // put CHECK_PICK_PASSES times, and the size kept has the weakest neighbor pair that leans hardest
    unsigned int dearer[CHECK_LINKS];
    unsigned long long kept_repeat = 0ull;
    unsigned int kept_weakest = 0u;
    for (unsigned int power = CHECK_SIZE_LEAST; power <= CHECK_SIZE_MOST; power += 2u)
    {
        order.repeat = 1ull << power;
        order.passes = CHECK_PICK_PASSES;
        check_read(&order, dearer);
        // the weakest pair: the fewest passes any neighbor pair read dearer in
        unsigned int weakest = CHECK_PICK_PASSES;
        for (unsigned int number = 1u; number < CHECK_LINKS; number += 1u)
        {
            weakest = (dearer[number] < weakest) ? dearer[number] : weakest;
        }
        printf("  2^%u puts a run: the weakest neighbor pair reads dearer in %u of %u passes\n", power, weakest,
               CHECK_PICK_PASSES);
        if ((kept_repeat == 0ull) || (weakest > kept_weakest))
        {
            kept_weakest = weakest;
            kept_repeat = order.repeat;
        }
    }

    // Held at the size the part named. Every pass solved on its own, exactly, and every pair of neighboring links
    // compared in it: a bit a pass, 1 where the link that reads 64 more times costs more. Nothing is summed across
    // passes and nothing is cut to a least. A pair is ordered where its count leans past twice its own spread
    order.repeat = kept_repeat;
    order.passes = CHECK_PASSES;
    const unsigned int solved = check_read(&order, dearer);
    check_that(solved == 1u, "every pass solves exactly inside the exact width");
    unsigned int ordered = 0u;
    printf("  over %u passes of %llu puts, each solved exactly, the link reading 64 more times costs more in:\n",
           CHECK_PASSES, order.repeat);
    for (unsigned int number = 1u; number < CHECK_LINKS; number += 1u)
    {
        const int leans = check_leans(dearer[number], CHECK_PASSES);
        ordered += (leans != 0) ? 1u : 0u;
        printf("    link %u over link %u: %u of %u passes%s\n", number, number - 1u, dearer[number], CHECK_PASSES,
               (leans != 0) ? "" : ", not past twice the spread");
    }
    check_that(ordered == (CHECK_LINKS - 1u), "every link is read dearer than the one before it past the spread");
#else
    printf("  no shared page named to this test on this platform: the order is not put\n");
#endif

    printf("  query order: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
