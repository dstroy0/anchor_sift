// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ask_order.c: the known order of asks, its solve, and the read of whether the links contend
#include "ask_order.h"

#include "../../arithmetic/no_rounding/exact_integer.h"

#include <string.h>

// the count of ones in `word`
static unsigned int ask_ones(unsigned int word)
{
    unsigned int count = 0u;
    while (word != 0u)
    {
        word &= word - 1u;
        count += 1u;
    }
    return count;
}

// the next word of the sweep's generator. A zero state never leaves zero, and the caller keeps it off zero
static unsigned int ask_swept(unsigned int *state)
{
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;
    return *state;
}

int ask_order_fits(unsigned int links)
{
    return ((links >= 3u) && (links <= ASK_ORDER_LINKS_MOST) && (((links + 1u) & links) == 0u)) ? 1 : 0;
}

int ask_order_covers(unsigned int links, unsigned int ask, unsigned int link)
{
    if ((ask_order_fits(links) == 0) || (ask >= links) || (link >= links))
    {
        return 0;
    }
    return ((ask_ones((ask + 1u) & (link + 1u)) & 1u) != 0u) ? 1 : 0;
}

int ask_order_solve(unsigned int links, const unsigned long long *cost, long long *scaled)
{
    if (ask_order_fits(links) == 0)
    {
        return 0;
    }
    // a summed cost is under 2^55 by the header's bound, which a signed 64 bit word holds
    long long whole = 0;
    for (unsigned int ask = 0u; ask < links; ask += 1u)
    {
        whole += (long long)cost[ask];
    }
    for (unsigned int link = 0u; link < links; link += 1u)
    {
        long long covered = 0;
        for (unsigned int ask = 0u; ask < links; ask += 1u)
        {
            covered += (ask_order_covers(links, ask, link) != 0) ? (long long)cost[ask] : 0;
        }
        scaled[link] = (4 * covered) - (2 * whole);
    }
    return 1;
}

unsigned int ask_sweep_covers(unsigned int links, unsigned int seed, unsigned int ask, unsigned char *covered)
{
    if ((links == 0u) || (links > ASK_ORDER_LINKS_MOST))
    {
        return 0u;
    }
    unsigned char order[ASK_ORDER_LINKS_MOST];
    for (unsigned int at = 0u; at < links; at += 1u)
    {
        // a link index is under ASK_ORDER_LINKS_MOST, which a byte holds
        order[at] = (unsigned char)at;
    }
    unsigned int state = seed ^ ((ask + 1u) * 0x9e3779b9u);
    state = (state != 0u) ? state : 0x9e3779b9u;
    for (unsigned int at = links; at > 1u; at -= 1u)
    {
        const unsigned int with = ask_swept(&state) % at;
        const unsigned char held = order[at - 1u];
        order[at - 1u] = order[with];
        order[with] = held;
    }
    // one link, half plus one, and every link, in turn: a square read against a line has the least spread with its
    // asks at the two ends and the middle
    const unsigned int counts[3] = {1u, (links + 1u) / 2u, links};
    const unsigned int count = counts[ask % 3u];
    memset(covered, 0, links);
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        covered[order[at]] = 1u;
    }
    return count;
}

// `given` as an exact integer
static void ask_exact(AnchorExactInteger *value, long long given)
{
    anchor_exact_zero(value);
    // the magnitude of the most negative word is one past the most positive, which the unsigned word holds
    const unsigned long long magnitude = (given < 0) ? (0ull - (unsigned long long)given) : (unsigned long long)given;
    value->limb[0] = (uint32_t)(magnitude & 0xffffffffull);
    value->limb[1] = (uint32_t)(magnitude >> 32);
    value->sign = (given > 0) ? 1 : ((given < 0) ? -1 : 0);
}

// `left` times `right` added into `sum`; 1, or 0 where the exact width could not hold it
static int ask_exact_add_product(AnchorExactInteger *sum, const AnchorExactInteger *left,
                                 const AnchorExactInteger *right)
{
    AnchorExactInteger product;
    if (anchor_exact_multiply(left, right, &product) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    return (anchor_exact_add(sum, &product, sum) == ANCHOR_EXACT_OK) ? 1 : 0;
}

// `first` times `second` less `third` times `fourth`, into `out`; 1, or 0 where the exact width could not hold it
static int ask_exact_difference(AnchorExactInteger *out, const AnchorExactInteger *first,
                                const AnchorExactInteger *second, const AnchorExactInteger *third,
                                const AnchorExactInteger *fourth)
{
    AnchorExactInteger kept;
    AnchorExactInteger taken;
    if ((anchor_exact_multiply(first, second, &kept) != ANCHOR_EXACT_OK) ||
        (anchor_exact_multiply(third, fourth, &taken) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    return (anchor_exact_subtract(&kept, &taken, out) == ANCHOR_EXACT_OK) ? 1 : 0;
}

// the three things a sweep ask's leftover is read against, and the leftover, summed alone and in pairs
enum
{
    ASK_COUNT,
    ASK_SQUARE,
    ASK_LEFT,
    ASK_TERMS
};

AskLinks ask_links_read(unsigned int links, const long long *scaled, unsigned int passes, unsigned int seed,
                        const unsigned long long *sweep_cost, unsigned int sweeps)
{
    // the constant, the count and the square are three unknowns, and the spread past them needs a fourth ask
    if ((ask_order_fits(links) == 0) || (passes == 0u) || (sweeps < 4u))
    {
        return ASK_LINKS_UNREAD;
    }
    // each sweep cost is from one pass, and the solve's costs are scaled by the passes and by links + 1
    const long long scale = (long long)passes * (long long)(links + 1u);

    AnchorExactInteger sum[ASK_TERMS];
    AnchorExactInteger pair[ASK_TERMS][ASK_TERMS];
    for (unsigned int term = 0u; term < ASK_TERMS; term += 1u)
    {
        anchor_exact_zero(&sum[term]);
        for (unsigned int other = 0u; other < ASK_TERMS; other += 1u)
        {
            anchor_exact_zero(&pair[term][other]);
        }
    }

    int held = 1;
    for (unsigned int ask = 0u; ask < sweeps; ask += 1u)
    {
        unsigned char covered[ASK_ORDER_LINKS_MOST];
        const unsigned int count = ask_sweep_covers(links, seed, ask, covered);
        long long predicted = 0;
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            predicted += (covered[link] != 0u) ? scaled[link] : 0;
        }
        // what the solve's links leave of this ask's cost, at the solve's scale; a summed cost is under the
        // header's bound, which keeps the scaled cost inside a signed 64 bit word
        AnchorExactInteger value[ASK_TERMS];
        ask_exact(&value[ASK_COUNT], (long long)count);
        ask_exact(&value[ASK_SQUARE], (long long)count * (long long)count);
        ask_exact(&value[ASK_LEFT], (scale * (long long)sweep_cost[ask]) - predicted);
        for (unsigned int term = 0u; term < ASK_TERMS; term += 1u)
        {
            held = held && (anchor_exact_add(&sum[term], &value[term], &sum[term]) == ANCHOR_EXACT_OK);
            for (unsigned int other = term; other < ASK_TERMS; other += 1u)
            {
                held = held && ask_exact_add_product(&pair[term][other], &value[term], &value[other]);
            }
        }
    }
    if (held == 0)
    {
        return ASK_LINKS_UNREAD;
    }

    // Every sum centered and scaled by the ask count N, which keeps it an integer
    AnchorExactInteger asks;
    AnchorExactInteger centered[ASK_TERMS][ASK_TERMS];
    ask_exact(&asks, (long long)sweeps);
    for (unsigned int term = 0u; term < ASK_TERMS; term += 1u)
    {
        for (unsigned int other = term; other < ASK_TERMS; other += 1u)
        {
            if (ask_exact_difference(&centered[term][other], &asks, &pair[term][other], &sum[term], &sum[other]) == 0)
            {
                return ASK_LINKS_UNREAD;
            }
        }
    }
    // a sweep whose asks all cover one count has nothing to read the square against
    if (centered[ASK_COUNT][ASK_COUNT].sign <= 0)
    {
        return ASK_LINKS_UNREAD;
    }

    // The count taken out of the square and of the leftover, each scaled by the count's own spread, which keeps
    // every one an integer. The constant takes the overhead every ask pays, and the count takes the share of it the
    // solve spreads over every link and therefore over every ask in proportion to the count it covers
    AnchorExactInteger square_square;
    AnchorExactInteger square_left;
    AnchorExactInteger left_left;
    const AnchorExactInteger *const count_count = &centered[ASK_COUNT][ASK_COUNT];
    if ((ask_exact_difference(&square_square, count_count, &centered[ASK_SQUARE][ASK_SQUARE],
                              &centered[ASK_COUNT][ASK_SQUARE], &centered[ASK_COUNT][ASK_SQUARE]) == 0) ||
        (ask_exact_difference(&square_left, count_count, &centered[ASK_SQUARE][ASK_LEFT],
                              &centered[ASK_COUNT][ASK_SQUARE], &centered[ASK_COUNT][ASK_LEFT]) == 0) ||
        (ask_exact_difference(&left_left, count_count, &centered[ASK_LEFT][ASK_LEFT], &centered[ASK_COUNT][ASK_LEFT],
                              &centered[ASK_COUNT][ASK_LEFT]) == 0))
    {
        return ASK_LINKS_UNREAD;
    }
    // fewer than three counts covered leaves the square on the line the count draws, and nothing to read
    if (square_square.sign <= 0)
    {
        return ASK_LINKS_UNREAD;
    }
    if (square_left.sign <= 0)
    {
        return ASK_LINKS_ADD;
    }

    // With N - 3 left over, the square's slope clears twice its own spread exactly where
    // square_left^2 (N + 1) > 4 left_left square_square
    AnchorExactInteger widened;
    AnchorExactInteger four;
    AnchorExactInteger cross_squared;
    AnchorExactInteger cleared;
    AnchorExactInteger spreads;
    AnchorExactInteger bar;
    ask_exact(&widened, (long long)sweeps + 1);
    ask_exact(&four, 4);
    if ((anchor_exact_multiply(&square_left, &square_left, &cross_squared) != ANCHOR_EXACT_OK) ||
        (anchor_exact_multiply(&cross_squared, &widened, &cleared) != ANCHOR_EXACT_OK) ||
        (anchor_exact_multiply(&left_left, &square_square, &spreads) != ANCHOR_EXACT_OK) ||
        (anchor_exact_multiply(&spreads, &four, &bar) != ANCHOR_EXACT_OK))
    {
        return ASK_LINKS_UNREAD;
    }
    return (anchor_exact_compare(&cleared, &bar) > 0) ? ASK_LINKS_CONTEND : ASK_LINKS_ADD;
}
