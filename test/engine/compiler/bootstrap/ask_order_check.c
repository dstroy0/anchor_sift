// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// ask_order_check.c: the known order of asks, held to its exact claims at every size it covers
//
// The exact claims are checked over the whole of every set they are about, and the count is printed:
//
//   inverse     4 S' - 2 J times S is (links + 1) times the identity, entry by entry
//   coverage    every ask covers (links + 1) / 2 links and any two share (links + 1) / 4
//   solve       costs built from integer link costs solve back to (links + 1) times each link, at any pass count
//   overhead    a fixed cost on every ask moves every link by the same amount
//   contention  a cost that grows with the square of the count an ask covers does the same
//   refusal     a link count no known order covers is refused, and the solve writes nothing
//   sweep       the sweep's asks cover one link, half plus one and every link, in turn
//
// The contention read is a test on noisy costs and is measured, not proved: costs drawn in integers around an
// overhead, pairs of links contending by an amount drawn per pair, and the rate the read finds contention at each
// amount, the rate at none being its false alarms.
#include "../../../../src/engine/compiler/bootstrap/ask_order.h"

#include <stdio.h>
#include <string.h>

static const unsigned int s_sizes[] = {3u, 7u, 15u, 31u, 63u};
#define SIZE_COUNT (sizeof(s_sizes) / sizeof(s_sizes[0]))

static unsigned long long s_checks = 0ull;
static unsigned long long s_failed = 0ull;

static void check_that(int held, const char *what, unsigned int links)
{
    s_checks += 1ull;
    if (held == 0)
    {
        s_failed += 1ull;
        printf("  FAILED: %s at %u links\n", what, links);
    }
}

// the test's own generator, kept off zero
static unsigned int check_drawn(unsigned int *state)
{
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;
    return *state;
}

// a draw near a bell curve in integers: the sum of twelve draws in [-500, 500], whose spread is 1000
static long long check_noise(unsigned int *state)
{
    long long sum = 0;
    for (unsigned int at = 0u; at < 12u; at += 1u)
    {
        sum += (long long)(check_drawn(state) % 1001u) - 500;
    }
    return sum;
}

static void check_inverse_and_coverage(unsigned int links)
{
    int inverse = 1;
    for (unsigned int row = 0u; row < links; row += 1u)
    {
        for (unsigned int column = 0u; column < links; column += 1u)
        {
            long long sum = 0;
            for (unsigned int ask = 0u; ask < links; ask += 1u)
            {
                const long long term = 2 * ((2 * (long long)ask_order_covers(links, ask, row)) - 1);
                sum += term * (long long)ask_order_covers(links, ask, column);
            }
            inverse = inverse && (sum == ((row == column) ? (long long)(links + 1u) : 0));
        }
    }
    check_that(inverse, "4 S' - 2 J times S is (links + 1) times the identity", links);

    int halves = 1;
    int quarters = 1;
    for (unsigned int ask = 0u; ask < links; ask += 1u)
    {
        unsigned int covered = 0u;
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            covered += (unsigned int)ask_order_covers(links, ask, link);
        }
        halves = halves && (covered == ((links + 1u) / 2u));
        for (unsigned int other = ask + 1u; other < links; other += 1u)
        {
            unsigned int shared = 0u;
            for (unsigned int link = 0u; link < links; link += 1u)
            {
                shared += (unsigned int)(ask_order_covers(links, ask, link) & ask_order_covers(links, other, link));
            }
            quarters = quarters && (shared == ((links + 1u) / 4u));
        }
    }
    check_that(halves, "every ask covers (links + 1) / 2 links", links);
    check_that(quarters, "any two asks share (links + 1) / 4 links", links);
}

// the costs of the known order's asks for integer link costs `cost`, each with `fixed` added and `per_square` times
// the square of the count it covers, summed over `passes`
static void check_asks(unsigned int links, const unsigned long long *cost, unsigned long long fixed,
                       unsigned long long per_square, unsigned int passes, unsigned long long *asked)
{
    for (unsigned int ask = 0u; ask < links; ask += 1u)
    {
        unsigned long long sum = 0ull;
        unsigned long long count = 0ull;
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            const int covers = ask_order_covers(links, ask, link);
            sum += (covers != 0) ? cost[link] : 0ull;
            count += (covers != 0) ? 1ull : 0ull;
        }
        asked[ask] = (unsigned long long)passes * (sum + fixed + (per_square * count * count));
    }
}

static void check_solve(unsigned int links, unsigned int *state)
{
    unsigned long long cost[ASK_ORDER_LINKS_MOST];
    unsigned long long asked[ASK_ORDER_LINKS_MOST];
    long long scaled[ASK_ORDER_LINKS_MOST];
    long long shifted[ASK_ORDER_LINKS_MOST];
    for (unsigned int trial = 0u; trial < 64u; trial += 1u)
    {
        const unsigned int passes = 1u + (trial % 8u);
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            cost[link] = 1ull + (check_drawn(state) % 1000000u);
        }
        check_asks(links, cost, 0ull, 0ull, passes, asked);
        int exact = ask_order_solve(links, asked, scaled);
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            exact = exact && (scaled[link] == ((long long)passes * (long long)(links + 1u) * (long long)cost[link]));
        }
        check_that(exact, "integer link costs solve back exactly", links);

        const unsigned long long fixed = check_drawn(state) % 100000u;
        check_asks(links, cost, fixed, 0ull, passes, asked);
        ask_order_solve(links, asked, shifted);
        int even = 1;
        for (unsigned int link = 1u; link < links; link += 1u)
        {
            even = even && ((shifted[link] - scaled[link]) == (shifted[0] - scaled[0]));
        }
        check_that(even, "a fixed cost on every ask moves every link by one amount", links);

        const unsigned long long per_square = 1ull + (check_drawn(state) % 1000u);
        check_asks(links, cost, 0ull, per_square, passes, asked);
        ask_order_solve(links, asked, shifted);
        even = 1;
        for (unsigned int link = 1u; link < links; link += 1u)
        {
            even = even && ((shifted[link] - scaled[link]) == (shifted[0] - scaled[0]));
        }
        check_that(even, "contention on the count covered moves every link by one amount", links);
    }
}

static void check_sweep(unsigned int links)
{
    unsigned char covered[ASK_ORDER_LINKS_MOST];
    const unsigned int counts[3] = {1u, (links + 1u) / 2u, links};
    int every = 1;
    for (unsigned int ask = 0u; ask < (3u * links); ask += 1u)
    {
        const unsigned int count = ask_sweep_covers(links, 0x51a7u, ask, covered);
        unsigned int marked = 0u;
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            marked += covered[link];
        }
        every = every && (count == counts[ask % 3u]) && (marked == count);
    }
    check_that(every, "the sweep covers one link, half plus one and every link, in turn", links);
}

static void check_refusals(void)
{
    unsigned long long asked[128];
    long long scaled[128];
    memset(asked, 0, sizeof(asked));
    for (unsigned int links = 0u; links < 128u; links += 1u)
    {
        const int covered = ((links == 3u) || (links == 7u) || (links == 15u) || (links == 31u) || (links == 63u));
        check_that(ask_order_fits(links) == covered, "a known order exists exactly where it should", links);
        if (covered == 0)
        {
            scaled[0] = 12345;
            check_that((ask_order_solve(links, asked, scaled) == 0) && (scaled[0] == 12345),
                       "a refused count writes nothing", links);
        }
    }
}

// the share, in tenths of a percent, of `trials` passes the read finds contention on, links contending by up to
// `most` per pair, over `links` links, `passes` passes of the known order and `sweeps` sweep asks
static unsigned int check_contention_rate(unsigned int links, unsigned int passes, unsigned int sweeps,
                                          unsigned int most, unsigned int trials, unsigned int *state)
{
    static unsigned int contend[ASK_ORDER_LINKS_MOST][ASK_ORDER_LINKS_MOST];
    unsigned long long cost[ASK_ORDER_LINKS_MOST];
    unsigned long long asked[ASK_ORDER_LINKS_MOST];
    unsigned long long swept[4u * ASK_ORDER_LINKS_MOST];
    long long scaled[ASK_ORDER_LINKS_MOST];
    unsigned char covered[ASK_ORDER_LINKS_MOST];
    const long long overhead = 20000;
    unsigned int found = 0u;
    for (unsigned int trial = 0u; trial < trials; trial += 1u)
    {
        for (unsigned int link = 0u; link < links; link += 1u)
        {
            cost[link] = 500ull + (check_drawn(state) % 1001u);
            for (unsigned int other = link + 1u; other < links; other += 1u)
            {
                contend[link][other] = (most == 0u) ? 0u : (check_drawn(state) % (most + 1u));
            }
        }
        for (unsigned int ask = 0u; ask < links; ask += 1u)
        {
            long long sum = 0;
            for (unsigned int link = 0u; link < links; link += 1u)
            {
                covered[link] = (unsigned char)ask_order_covers(links, ask, link);
            }
            for (unsigned int pass = 0u; pass < passes; pass += 1u)
            {
                long long one = overhead + check_noise(state);
                for (unsigned int link = 0u; link < links; link += 1u)
                {
                    one += (covered[link] != 0u) ? (long long)cost[link] : 0;
                    for (unsigned int other = link + 1u; other < links; other += 1u)
                    {
                        one += ((covered[link] != 0u) && (covered[other] != 0u)) ? (long long)contend[link][other] : 0;
                    }
                }
                sum += one;
            }
            // the overhead holds every pass far above the noise, and a pass is never below zero
            asked[ask] = (unsigned long long)sum;
        }
        ask_order_solve(links, asked, scaled);
        const unsigned int seed = 0x51a7u + trial;
        for (unsigned int ask = 0u; ask < sweeps; ask += 1u)
        {
            ask_sweep_covers(links, seed, ask, covered);
            long long one = overhead + check_noise(state);
            for (unsigned int link = 0u; link < links; link += 1u)
            {
                one += (covered[link] != 0u) ? (long long)cost[link] : 0;
                for (unsigned int other = link + 1u; other < links; other += 1u)
                {
                    one += ((covered[link] != 0u) && (covered[other] != 0u)) ? (long long)contend[link][other] : 0;
                }
            }
            swept[ask] = (unsigned long long)one;
        }
        found += (ask_links_read(links, scaled, passes, seed, swept, sweeps) == ASK_LINKS_CONTEND) ? 1u : 0u;
    }
    return (1000u * found) / trials;
}

int main(void)
{
    unsigned int state = 0x9e3779b9u;
    for (unsigned int at = 0u; at < SIZE_COUNT; at += 1u)
    {
        check_inverse_and_coverage(s_sizes[at]);
        check_solve(s_sizes[at], &state);
        check_sweep(s_sizes[at]);
    }
    check_refusals();
    printf("  exact claims at 3, 7, 15, 31 and 63 links: %llu checks, %llu failed\n", s_checks, s_failed);

    // the noise's spread is 1000, the floor; links cost 500 to 1500, under it, and a pair contends by up to `most`
    const unsigned int links = 15u;
    const unsigned int passes = 4u;
    const unsigned int sweeps = 3u * links;
    const unsigned int trials = 300u;
    static const unsigned int s_most[] = {0u, 80u, 200u};
    unsigned int rate[3];
    printf("  contention read, %u links, %u passes of the known order, %u sweep asks, %u trials:\n", links, passes,
           sweeps, trials);
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        rate[at] = check_contention_rate(links, passes, sweeps, s_most[at], trials, &state);
        printf("    up to %3u a pair: contention found on %u.%u%%\n", s_most[at], rate[at] / 10u, rate[at] % 10u);
    }
    // the read is held to a false alarm rate under one in ten and to finding the largest contention nine times in ten
    const int read_held = (rate[0] < 100u) && (rate[2] >= 900u);
    printf("  the read holds its false alarms under 10%% and finds the largest contention on 90%% or more: %s\n",
           read_held ? "yes" : "NO");
    return ((s_failed == 0ull) && read_held) ? 0 : 1;
}
