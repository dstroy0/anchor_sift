// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_ask.c: one ask of the query protocol, made of a word put and a word read
#include "query_ask.h"

// whether the qualifier holds at the address
static unsigned int query_held(const QueryAsk *asked)
{
    switch (asked->qualifier)
    {
    case QUERY_HOLDS: {
        unsigned int back = 0u;
        return (host_address_ask(asked->address, &back) == HOST_HOLDS) ? 1u : 0u;
    }
    case QUERY_EQUALS:
        return (host_read(asked->address) == asked->word) ? 1u : 0u;
    case QUERY_ADVANCES: {
        // a counter that wraps between the two reads still reads forward: the difference taken in the word's own
        // width is a forward step where it sits in the lower half of the word
        const unsigned int first = host_read(asked->address);
        const unsigned int then = host_read(asked->address);
        const unsigned int step = then - first;
        return ((step != 0u) && (step < 0x80000000u)) ? 1u : 0u;
    }
    default:
        return 0u;
    }
}

unsigned int query_ask(QueryAsk *asked)
{
    const unsigned int clocked = (asked->clock != 0ull) ? 1u : 0u;
    const unsigned int start = (clocked != 0u) ? host_read(asked->clock) : 0u;
    const unsigned int held = query_held(asked);
    const unsigned int end = (clocked != 0u) ? host_read(asked->clock) : 0u;

    // the clock's advance in its own width, which holds one wrap of the counter
    asked->cost = (clocked != 0u) ? (unsigned long long)(end - start) : 0ull;
    asked->cost_read = clocked;

    if (held == 0u)
    {
        asked->kind = QUERY_NOT_HELD;
        asked->bit = 0u;
    }
    // A bound is the most the answer may cost, and a cost nobody read cannot be shown to be inside it: a bound with
    // no clock reads 0 and is never a verdict nobody measured
    else if ((asked->bound != 0ull) && ((clocked == 0u) || (asked->cost > asked->bound)))
    {
        asked->kind = QUERY_PAST_BOUND;
        asked->bit = 0u;
    }
    else
    {
        // Unbound, the cost is what the ask returns, and the kind still says the qualifier held. The cost of an ask
        // whose qualifier did not hold is not the cost of an answer, and the unbound pass keeps the two apart
        asked->kind = QUERY_HELD;
        asked->bit = 1u;
    }
    return asked->bit;
}
