// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_order.c: the known order of asks put through the query protocol, timed exactly on a clock that is an address
#include "query_order.h"

// reads of the clock word from now until it next turns over, and the word it turns over to
static unsigned long long query_order_to_edge(unsigned long long clock, unsigned int *edge)
{
    const unsigned int was = host_read(clock);
    unsigned int now = was;
    unsigned long long reads = 0ull;
    while (now == was)
    {
        now = host_read(clock);
        reads += 1ull;
    }
    *edge = now;
    return reads;
}

// `given`, a count, as an exact integer
static void query_order_exact(AnchorExactInteger *value, unsigned long long given)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(given & 0xffffffffull);
    value->limb[1] = (uint32_t)(given >> 32);
    value->sign = (given != 0ull) ? 1 : 0;
}

// The links `covered` marks, each put `repeat` times, timed on a clock that turns over now and then and read finely by
// counting. The run starts on a turn of the clock. When it ends, the reads of the clock word until its next turn are
// counted, and so are the reads across the whole turn after that. The run's cost is the clock's advance from the turn
// it started on to the turn after it ended, less the tail: the share of the following turn the counted reads cover.
// That is spanned - tail * turn_span / turn_reads, kept as the rational it is
static QueryCost query_order_run(const QueryOrder *order, const unsigned char *covered)
{
    unsigned int start = 0u;
    query_order_to_edge(order->clock, &start);
    for (unsigned long long turn = 0ull; turn < order->repeat; turn += 1ull)
    {
        for (unsigned int link = 0u; link < order->links; link += 1u)
        {
            if (covered[link] != 0u)
            {
                QueryAsk asked = order->link[link];
                asked.clock = 0ull;
                asked.bound = 0ull;
                query_ask(&asked);
            }
        }
    }
    unsigned int after = 0u;
    const unsigned long long tail = query_order_to_edge(order->clock, &after);
    unsigned int next = 0u;
    const unsigned long long turn_reads = query_order_to_edge(order->clock, &next);
    // each advance in the clock word's own width, which holds one wrap of the counter
    const unsigned long long spanned = (unsigned long long)(after - start);
    const unsigned long long turn_span = (unsigned long long)(next - after);
    QueryCost cost;
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger kept;
    AnchorExactInteger taken;
    query_order_exact(&left, spanned);
    query_order_exact(&right, turn_reads);
    anchor_exact_multiply(&left, &right, &kept);
    query_order_exact(&left, tail);
    query_order_exact(&right, turn_span);
    anchor_exact_multiply(&left, &right, &taken);
    anchor_exact_subtract(&kept, &taken, &cost.numerator);
    query_order_exact(&cost.denominator, turn_reads);
    return cost;
}

int query_order_put(const QueryOrder *order, QueryCost *cost)
{
    if ((ask_order_fits(order->links) == 0) || (order->clock == 0ull))
    {
        return 0;
    }
    unsigned char covered[ASK_ORDER_LINKS_MOST];
    // Every pass's answer is kept as it came back. Nothing is summed away and nothing is cut to a least: the spread
    // across passes is the noise floor, read and not set
    for (unsigned int pass = 0u; pass < order->passes; pass += 1u)
    {
        for (unsigned int ask = 0u; ask < order->links; ask += 1u)
        {
            for (unsigned int link = 0u; link < order->links; link += 1u)
            {
                // ask_order_covers answers 1 or 0
                covered[link] = (unsigned char)ask_order_covers(order->links, ask, link);
            }
            cost[(pass * order->links) + ask] = query_order_run(order, covered);
        }
    }
    return 1;
}

int query_order_solve(unsigned int links, const QueryCost *cost, AnchorExactInteger *numerator,
                      AnchorExactInteger *denominator)
{
    if (ask_order_fits(links) == 0)
    {
        return 0;
    }
    // every ask's denominator but its own, multiplied together: the factor its numerator takes onto the common one
    AnchorExactInteger others[ASK_ORDER_LINKS_MOST];
    AnchorExactInteger factor;
    for (unsigned int ask = 0u; ask < links; ask += 1u)
    {
        query_order_exact(&others[ask], 1ull);
        for (unsigned int other = 0u; other < links; other += 1u)
        {
            if (other == ask)
            {
                continue;
            }
            AnchorExactInteger product;
            if (anchor_exact_multiply(&others[ask], &cost[other].denominator, &product) != ANCHOR_EXACT_OK)
            {
                return 0;
            }
            others[ask] = product;
        }
    }
    // the common denominator: links + 1 times every ask's denominator
    AnchorExactInteger every;
    if (anchor_exact_multiply(&others[0], &cost[0].denominator, &every) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    query_order_exact(&factor, (unsigned long long)links + 1ull);
    if (anchor_exact_multiply(&every, &factor, denominator) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    // Link c: the sum over every ask r of (4 when r covers c, else 0, less 2) times r's numerator times the others. The
    // weight is 2 or -2, put as twice the term added or taken away
    for (unsigned int link = 0u; link < links; link += 1u)
    {
        anchor_exact_zero(&numerator[link]);
        for (unsigned int ask = 0u; ask < links; ask += 1u)
        {
            AnchorExactInteger term;
            AnchorExactInteger twice;
            AnchorExactInteger sum;
            if ((anchor_exact_multiply(&cost[ask].numerator, &others[ask], &term) != ANCHOR_EXACT_OK) ||
                (anchor_exact_add(&term, &term, &twice) != ANCHOR_EXACT_OK))
            {
                return 0;
            }
            AnchorExactStatus moved = ANCHOR_EXACT_OK;
            if (ask_order_covers(links, ask, link) != 0)
            {
                moved = anchor_exact_add(&numerator[link], &twice, &sum);
            }
            else
            {
                moved = anchor_exact_subtract(&numerator[link], &twice, &sum);
            }
            if (moved != ANCHOR_EXACT_OK)
            {
                return 0;
            }
            numerator[link] = sum;
        }
    }
    return 1;
}

int query_order_sweep(const QueryOrder *order, unsigned int seed, unsigned int sweeps, QueryCost *sweep_cost)
{
    if ((ask_order_fits(order->links) == 0) || (order->clock == 0ull))
    {
        return 0;
    }
    unsigned char covered[ASK_ORDER_LINKS_MOST];
    for (unsigned int ask = 0u; ask < sweeps; ask += 1u)
    {
        ask_sweep_covers(order->links, seed, ask, covered);
        sweep_cost[ask] = query_order_run(order, covered);
    }
    return 1;
}
