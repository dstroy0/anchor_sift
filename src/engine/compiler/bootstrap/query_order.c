// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_order.c: the known order of asks put through the query protocol and timed on a clock that is an address
#include "query_order.h"

// The links `covered` marks, each put `repeat` times, between two reads of the clock. The clock's advance in its own
// width, which holds one wrap of the counter
static unsigned long long query_order_run(const QueryOrder *order, const unsigned char *covered)
{
    const unsigned int start = host_read(order->clock);
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
    const unsigned int end = host_read(order->clock);
    return (unsigned long long)(end - start);
}

int query_order_put(const QueryOrder *order, unsigned long long *cost)
{
    if ((ask_order_fits(order->links) == 0) || (order->clock == 0ull))
    {
        return 0;
    }
    unsigned char covered[ASK_ORDER_LINKS_MOST];
    for (unsigned int ask = 0u; ask < order->links; ask += 1u)
    {
        cost[ask] = 0ull;
    }
    for (unsigned int pass = 0u; pass < order->passes; pass += 1u)
    {
        for (unsigned int ask = 0u; ask < order->links; ask += 1u)
        {
            for (unsigned int link = 0u; link < order->links; link += 1u)
            {
                // ask_order_covers answers 1 or 0
                covered[link] = (unsigned char)ask_order_covers(order->links, ask, link);
            }
            cost[ask] += query_order_run(order, covered);
        }
    }
    return 1;
}

int query_order_sweep(const QueryOrder *order, unsigned int seed, unsigned int sweeps, unsigned long long *sweep_cost)
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
