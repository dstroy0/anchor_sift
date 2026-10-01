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
// every ask alike. Every pass's answers are kept, ask_order_solve gives every link's cost pass by pass, and the spread
// across passes is the noise floor, read off the answers. ask_links_read says whether the links add or contend. Nothing here holds a floating point value.

#include "ask_order.h"
#include "query_ask.h"

#include "../../arithmetic/no_rounding/exact_integer.h"

// A clock is anything that turns over, noisily, now and then: its turns frame a run, and the run is read finely by
// counting reads of the clock between turns. A run's cost is the exact rational numerator / denominator in the clock
// word's own count, and nothing divides it
typedef struct
{
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
} QueryCost;

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

// The order put, every pass's cost of every ask into `cost`, pass by pass: cost[pass * links + ask], which holds
// `order->passes` times `order->links` of them. 1, or 0 where the link count has no known order or no clock was
// given
int query_order_put(const QueryOrder *order, QueryCost *cost);

// Every link's cost from one pass of the order's costs, exactly: link c costs numerator[c] / denominator, the
// denominator one for every link of the pass and (links + 1) times every ask's denominator multiplied together.
// Two links of one pass compare by their numerators alone. 1, or 0 where the link count has no known order or the
// exact width could not hold a term
int query_order_solve(unsigned int links, const QueryCost *cost, AnchorExactInteger *numerator,
                      AnchorExactInteger *denominator);

// The sweep asks from `seed` put once each, `sweeps` of them, their costs into `sweep_cost`. 1, or 0 as above
int query_order_sweep(const QueryOrder *order, unsigned int seed, unsigned int sweeps, QueryCost *sweep_cost);

#endif
