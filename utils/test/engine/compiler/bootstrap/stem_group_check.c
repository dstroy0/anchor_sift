// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// stem_group_check.c: the stem membership rule held to what it says, on the three members order_check.py breaks
// pairwise agreement with and on drawn sets
//
//   the three     sm_86 at 100 with a floor of 3, sm_87 at 104 and sm_89 at 108 with floors of 5. sm_87 agrees with
//                 both others and they do not agree with each other. The rule anchors on sm_86, the finest, puts
//                 sm_87 with it and sm_89 in a group of its own, whichever order the three arrive in
//   refused       two members alike in every cost, one of which refused a row the other measured, are two groups
//   drawn sets    members drawn around a few centers, with drawn floors and drawn refusals. Every member agrees
//                 with its anchor, no two anchors agree, and the grouping is the same under every shuffle tried
#include "../../../../../src/engine/compiler/bootstrap/stem_group.h"

#include <stdio.h>

#define CHECK_ROWS 8u
#define CHECK_SETS 400u
#define CHECK_SHUFFLES 24u

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

static unsigned int s_drawn = 0x9e3779b9u;

static unsigned int check_draw(unsigned int below)
{
    s_drawn ^= s_drawn << 13;
    s_drawn ^= s_drawn >> 17;
    s_drawn ^= s_drawn << 5;
    return s_drawn % below;
}

// 1 where two groupings of the same members, `first` over members in `first_at` order and `then` over `then_at`,
// put every pair of members in a group together or apart alike
static int check_same_grouping(const unsigned int *first, const unsigned int *first_at, const unsigned int *then,
                               const unsigned int *then_at, unsigned int count)
{
    // where each member sits in each order: a group read in one order is read back in the other
    unsigned int first_place[STEM_GROUP_MEMBERS];
    unsigned int then_place[STEM_GROUP_MEMBERS];
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        first_place[first_at[at]] = at;
        then_place[then_at[at]] = at;
    }
    for (unsigned int one = 0u; one < count; one += 1u)
    {
        for (unsigned int two = one + 1u; two < count; two += 1u)
        {
            const int together_first = (first[first_place[one]] == first[first_place[two]]) ? 1 : 0;
            const int together_then = (then[then_place[one]] == then[then_place[two]]) ? 1 : 0;
            if (together_first != together_then)
            {
                return 0;
            }
        }
    }
    return 1;
}

static void check_three(void)
{
    static const unsigned long long s_cost[3] = {100ull, 104ull, 108ull};
    static const unsigned long long s_floor[3] = {3ull, 5ull, 5ull};
    static const unsigned int s_orders[6][3] = {{0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}};
    unsigned int held = 0u;
    for (unsigned int order = 0u; order < 6u; order += 1u)
    {
        StemMember member[3] = {0};
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            const unsigned int which = s_orders[order][at];
            member[at].cost[0] = s_cost[which];
            member[at].measured[0] = 1u;
            member[at].floor = s_floor[which];
        }
        unsigned int group[3];
        const unsigned int groups = stem_group_build(member, 3u, 1u, group);
        // where sm_86, sm_87 and sm_89 sit in this order
        unsigned int place[3];
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            place[s_orders[order][at]] = at;
        }
        const int sm_86_anchors = (group[place[0]] == place[0]) && (group[place[1]] == place[0]);
        if ((groups == 2u) && sm_86_anchors && (group[place[2]] == place[2]))
        {
            held += 1u;
        }
    }
    check_that(held == 6u, "the three group as sm_86 with sm_87 and sm_89 alone, in all six orders");
}

static void check_refused(void)
{
    StemMember member[2] = {0};
    for (unsigned int at = 0u; at < 2u; at += 1u)
    {
        for (unsigned int row = 0u; row < CHECK_ROWS; row += 1u)
        {
            member[at].cost[row] = 50ull + row;
            member[at].measured[row] = 1u;
        }
        member[at].floor = 10ull;
    }
    member[1].measured[3] = 0u;
    unsigned int group[2];
    check_that(stem_group_build(member, 2u, CHECK_ROWS, group) == 2u,
               "two members alike in cost and apart in one refused row are two groups");
}

static void check_drawn(void)
{
    static StemMember s_member[STEM_GROUP_MEMBERS];
    static StemMember s_shuffled[STEM_GROUP_MEMBERS];
    unsigned int to_anchor = 0u;
    unsigned int anchors_apart = 0u;
    unsigned int shuffles_alike = 0u;
    unsigned long long groups_seen = 0ull;
    unsigned long long members_seen = 0ull;
    for (unsigned int set = 0u; set < CHECK_SETS; set += 1u)
    {
        const unsigned int count = 4u + check_draw(37u);
        unsigned long long center[4][CHECK_ROWS];
        for (unsigned int which = 0u; which < 4u; which += 1u)
        {
            for (unsigned int row = 0u; row < CHECK_ROWS; row += 1u)
            {
                center[which][row] = 200ull + check_draw(800u);
            }
        }
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            const unsigned int which = check_draw(4u);
            for (unsigned int row = 0u; row < CHECK_ROWS; row += 1u)
            {
                s_member[at].cost[row] = center[which][row] + check_draw(24u);
                s_member[at].measured[row] = (check_draw(40u) == 0u) ? 0u : 1u;
            }
            s_member[at].floor = 1ull + check_draw(30u);
        }
        unsigned int group[STEM_GROUP_MEMBERS];
        unsigned int at_first[STEM_GROUP_MEMBERS];
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            at_first[at] = at;
        }
        const unsigned int groups = stem_group_build(s_member, count, CHECK_ROWS, group);
        groups_seen += groups;
        members_seen += count;

        unsigned int agrees = 1u;
        unsigned int apart = 1u;
        for (unsigned int one = 0u; one < count; one += 1u)
        {
            agrees = (stem_group_agree(&s_member[one], &s_member[group[one]], CHECK_ROWS) != 0) ? agrees : 0u;
            for (unsigned int two = one + 1u; two < count; two += 1u)
            {
                const int both_anchor = (group[one] == one) && (group[two] == two);
                if (both_anchor && (stem_group_agree(&s_member[one], &s_member[two], CHECK_ROWS) != 0))
                {
                    apart = 0u;
                }
            }
        }
        to_anchor += agrees;
        anchors_apart += apart;

        unsigned int alike = 1u;
        for (unsigned int shuffle = 0u; shuffle < CHECK_SHUFFLES; shuffle += 1u)
        {
            unsigned int at_then[STEM_GROUP_MEMBERS];
            for (unsigned int at = 0u; at < count; at += 1u)
            {
                at_then[at] = at;
            }
            for (unsigned int at = count - 1u; at > 0u; at -= 1u)
            {
                const unsigned int swap = check_draw(at + 1u);
                const unsigned int held = at_then[at];
                at_then[at] = at_then[swap];
                at_then[swap] = held;
            }
            for (unsigned int at = 0u; at < count; at += 1u)
            {
                s_shuffled[at] = s_member[at_then[at]];
            }
            unsigned int group_then[STEM_GROUP_MEMBERS];
            const unsigned int groups_then = stem_group_build(s_shuffled, count, CHECK_ROWS, group_then);
            if ((groups_then != groups) || (check_same_grouping(group, at_first, group_then, at_then, count) == 0))
            {
                alike = 0u;
            }
        }
        shuffles_alike += alike;
    }
    printf("  %u drawn sets, %llu members in %llu groups\n", CHECK_SETS, members_seen, groups_seen);
    check_that(to_anchor == CHECK_SETS, "every member agrees with the member its group is anchored on");
    check_that(anchors_apart == CHECK_SETS, "no two anchors agree");
    check_that(shuffles_alike == CHECK_SETS, "every set groups alike under every shuffle tried");
}

int main(void)
{
    check_three();
    check_refused();
    check_drawn();
    printf("  stem group: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
