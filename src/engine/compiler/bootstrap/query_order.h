// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QUERY_ORDER_H
#define QUERY_ORDER_H

// The known order of asks put through the query protocol: links that are asks, costs read off a clock that is an
// address, and every link's cost solved from the order's answers.
//
// A link is one ask, an address and a qualifier. Ask r of the known order puts every link it covers, `repeat` times
// over, between two reads of the clock, and its cost is the clock's advance across them. A clock that steps far less
// often than an ask takes reads a single ask as a step or nothing, and `repeat` makes one ask of the order
// last many steps. The order's asks are put in turn, `passes` times over: a drift in the part's speed falls on
// every ask alike. ask_order_solve then gives every link's cost from those answers, and ask_links_read says whether
// the links add or contend. Nothing here holds a floating point value.

#include "ask_order.h"
#include "query_ask.h"

// a known order of asks over links that are asks
typedef struct
{
    // the links, `links` of them, a count a known order holds; each is put as it stands, its bound left unread
    const QueryAsk *link;
    unsigned int links;
    // the address of a counter found by QUERY_ADVANCES, read before and after every ask of the order
    unsigned long long clock;
    // how many times each covered link is put inside one ask of the order
    unsigned long long repeat;
    // how many times the whole order is put
    unsigned int passes;
} QueryOrder;

// The order put, every ask's cost summed over every pass into `cost`, which holds `order->links` of them. 1, or 0
// where the link count has no known order or no clock was given
int query_order_put(const QueryOrder *order, unsigned long long *cost);

// The sweep asks from `seed` put once each, `sweeps` of them, their costs into `sweep_cost`. 1, or 0 as above
int query_order_sweep(const QueryOrder *order, unsigned int seed, unsigned int sweeps, unsigned long long *sweep_cost);

#endif
