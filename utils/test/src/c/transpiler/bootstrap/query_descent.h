// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_descent.h: the run size and the count of passes of a known order, steered by the part, for the checks that put
// the order to the host
//
// NO COUNT OF PASSES AND NO RUN SIZE IS SET HERE. Both are steered, the way the engine's descent steers its probes.
// Each pass is a level: its bit for a pair of neighboring links is 1 where the later link reads dearer. A pair stands
// while its count over every pass put so far leans past twice its own spread neither way, and the descent ends the
// first pass nothing stands, or at QUERY_DESCENT_PASSES_MOST, the bound it is held to before it starts. A pair is read
// on its whole record at every pass and is never closed early: the reads carry noise, and a count that leans at a few
// passes can stop leaning at more. The run size is the candidate the descent is steered over. Every size is read, and
// the one that leaves the fewest pairs standing, then spends the fewest puts, is kept, a tie going to the shorter. A
// size stops once it has spent the puts the best so far needed with a pair still standing, since past that it cannot
// do better.
#ifndef QUERY_DESCENT_H
#define QUERY_DESCENT_H

#include "../../../../../../src/c/transpiler/bootstrap/query_order.h"

#include <stdio.h>

#if defined(_WIN32)

#define QUERY_DESCENT_LINKS 7u
// the most passes a descent puts: the bound it is held to, fixed before it starts
#define QUERY_DESCENT_PASSES_MOST 64u
// the run sizes the descent may reach, as powers of two puts a run
#define QUERY_DESCENT_SIZE_LEAST 10u
#define QUERY_DESCENT_SIZE_MOST 16u

// a pair still standing, a pair whose later link leans dearer, and a pair whose later link leans cheaper
#define QUERY_DESCENT_STANDING 0u
#define QUERY_DESCENT_DEARER 1u
#define QUERY_DESCENT_CHEAPER 2u

// one descent: for every pair, the passes it read dearer in and which way its count leans at the end
typedef struct
{
    unsigned int dearer[QUERY_DESCENT_LINKS];
    unsigned int decided[QUERY_DESCENT_LINKS];
    unsigned int passes;
    unsigned int standing;
    unsigned int solved;
} QueryDescent;

// `count`, a count, as an exact integer
static void query_descent_exact(AnchorExactInteger *value, unsigned int count)
{
    anchor_exact_zero(value);
    value->limb[0] = count;
    value->sign = (count != 0u) ? 1 : 0;
}

// Whether `toward` of `of` leans past twice its own spread toward it: 2 * toward - of is positive and its square is
// past 4 * of. Every term an exact integer
static int query_descent_leans(unsigned int toward, unsigned int of)
{
    AnchorExactInteger twice;
    AnchorExactInteger whole;
    AnchorExactInteger lean;
    AnchorExactInteger square;
    AnchorExactInteger four;
    query_descent_exact(&twice, 2u * toward);
    query_descent_exact(&whole, of);
    query_descent_exact(&four, 4u * of);
    if ((anchor_exact_subtract(&twice, &whole, &lean) != ANCHOR_EXACT_OK) || (lean.sign <= 0) ||
        (anchor_exact_multiply(&lean, &lean, &square) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    return (anchor_exact_compare(&square, &four) > 0) ? 1 : 0;
}

// The order put one pass at a time at `order->repeat`, each pass solved on its own, until no pair stands, the bound
// is reached, or `spend_most` puts are spent with a pair still standing. 0 for `spend_most` sets no such limit
static void query_descent_put(QueryOrder *order, unsigned long long spend_most, QueryDescent *descent)
{
    static QueryCost s_cost[QUERY_DESCENT_LINKS];
    descent->passes = 0u;
    descent->solved = 1u;
    descent->standing = QUERY_DESCENT_LINKS - 1u;
    for (unsigned int number = 0u; number < QUERY_DESCENT_LINKS; number += 1u)
    {
        descent->dearer[number] = 0u;
        descent->decided[number] = QUERY_DESCENT_STANDING;
    }
    order->passes = 1u;
    while ((descent->standing > 0u) && (descent->passes < QUERY_DESCENT_PASSES_MOST))
    {
        if ((spend_most != 0ull) && (((unsigned long long)descent->passes * order->repeat) >= spend_most))
        {
            return;
        }
        if (query_order_put(order, s_cost) == 0)
        {
            descent->solved = 0u;
            return;
        }
        descent->passes += 1u;
        AnchorExactInteger numerator[QUERY_DESCENT_LINKS];
        AnchorExactInteger denominator;
        if (query_order_solve(QUERY_DESCENT_LINKS, s_cost, numerator, &denominator) == 0)
        {
            descent->solved = 0u;
            continue;
        }
        descent->standing = 0u;
        for (unsigned int number = 1u; number < QUERY_DESCENT_LINKS; number += 1u)
        {
            // one pass's links share one denominator, and its sign is positive: the numerators order them
            descent->dearer[number] +=
                (anchor_exact_compare(&numerator[number], &numerator[number - 1u]) > 0) ? 1u : 0u;
            descent->decided[number] = QUERY_DESCENT_STANDING;
            if (query_descent_leans(descent->dearer[number], descent->passes) != 0)
            {
                descent->decided[number] = QUERY_DESCENT_DEARER;
            }
            else if (query_descent_leans(descent->passes - descent->dearer[number], descent->passes) != 0)
            {
                descent->decided[number] = QUERY_DESCENT_CHEAPER;
            }
            descent->standing += (descent->decided[number] == QUERY_DESCENT_STANDING) ? 1u : 0u;
        }
    }
}

// Whether `next` at `next_repeat` puts a run does strictly better than `kept` at `kept_repeat`: fewer pairs standing,
// or as many for fewer puts spent. Every ask of a pass puts `repeat` runs of its links: a descent spends its passes
// times its repeat
static int query_descent_better(const QueryDescent *next, unsigned long long next_repeat, const QueryDescent *kept,
                                unsigned long long kept_repeat)
{
    if (next->standing != kept->standing)
    {
        return (next->standing < kept->standing) ? 1 : 0;
    }
    return (((unsigned long long)next->passes * next_repeat) < ((unsigned long long)kept->passes * kept_repeat)) ? 1
                                                                                                                 : 0;
}

// The run size, steered over every size the descent may reach, each one printed. The size kept is returned and its
// descent written to `kept`; `solved` is 1 where every pass of every size solved inside the exact width. A short run
// drowns in the counting's own spread and a long one gathers whatever else the part is doing, and where the floor
// between them falls is the part's to say
static unsigned long long query_descent_size(QueryOrder *order, QueryDescent *kept, unsigned int *solved)
{
    QueryDescent next;
    unsigned long long kept_repeat = 0ull;
    kept->passes = 0u;
    kept->standing = QUERY_DESCENT_LINKS - 1u;
    *solved = 1u;
    for (unsigned int power = QUERY_DESCENT_SIZE_LEAST; power <= QUERY_DESCENT_SIZE_MOST; power += 1u)
    {
        order->repeat = 1ull << power;
        const unsigned long long spend_most =
            ((kept_repeat != 0ull) && (kept->standing == 0u)) ? ((unsigned long long)kept->passes * kept_repeat) : 0ull;
        query_descent_put(order, spend_most, &next);
        *solved = (next.solved == 1u) ? *solved : 0u;
        printf("  2^%u puts a run: %u pairs standing after %u passes, %llu puts spent\n", power, next.standing,
               next.passes, (unsigned long long)next.passes * order->repeat);
        if ((kept_repeat == 0ull) || (query_descent_better(&next, order->repeat, kept, kept_repeat) != 0))
        {
            *kept = next;
            kept_repeat = order->repeat;
        }
    }
    order->repeat = kept_repeat;
    printf("  the descent keeps %llu puts a run\n", kept_repeat);
    return kept_repeat;
}

#endif

#endif
