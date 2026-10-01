// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// stem_group.c: members grouped on anchors, by a rule fixed by the members and not by the order they arrive in
#include "stem_group.h"

int stem_group_agree(const StemMember *one, const StemMember *two, unsigned int rows)
{
    const unsigned long long coarser = (one->floor > two->floor) ? one->floor : two->floor;
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        if (one->measured[row] != two->measured[row])
        {
            return 0;
        }
        if (one->measured[row] != 0u)
        {
            const unsigned long long high = (one->cost[row] > two->cost[row]) ? one->cost[row] : two->cost[row];
            const unsigned long long low = (one->cost[row] > two->cost[row]) ? two->cost[row] : one->cost[row];
            if ((high - low) > coarser)
            {
                return 0;
            }
        }
    }
    return 1;
}

// Whether `one` comes before `two` in the rule's order: the finer floor, then the rows, then the measured marks.
// Two members alike in all three are the same member as far as any answer goes, and either may come first
static int stem_group_before(const StemMember *one, const StemMember *two, unsigned int rows)
{
    if (one->floor != two->floor)
    {
        return (one->floor < two->floor) ? 1 : 0;
    }
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        if (one->cost[row] != two->cost[row])
        {
            return (one->cost[row] < two->cost[row]) ? 1 : 0;
        }
    }
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        if (one->measured[row] != two->measured[row])
        {
            return (one->measured[row] < two->measured[row]) ? 1 : 0;
        }
    }
    return 0;
}

unsigned int stem_group_build(const StemMember *member, unsigned int count, unsigned int rows, unsigned int *group)
{
    if ((count > STEM_GROUP_MEMBERS) || (rows > STEM_GROUP_ROWS))
    {
        return 0u;
    }
    // the members in the rule's order, by insertion: a set holds few enough members for that
    unsigned int order[STEM_GROUP_MEMBERS];
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        unsigned int place = at;
        while ((place > 0u) && (stem_group_before(&member[at], &member[order[place - 1u]], rows) != 0))
        {
            order[place] = order[place - 1u];
            place -= 1u;
        }
        order[place] = at;
        group[at] = STEM_GROUP_NONE;
    }
    unsigned int groups = 0u;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        const unsigned int anchor = order[at];
        if (group[anchor] != STEM_GROUP_NONE)
        {
            continue;
        }
        group[anchor] = anchor;
        groups += 1u;
        for (unsigned int later = at + 1u; later < count; later += 1u)
        {
            const unsigned int other = order[later];
            if ((group[other] == STEM_GROUP_NONE) && (stem_group_agree(&member[anchor], &member[other], rows) != 0))
            {
                group[other] = anchor;
            }
        }
    }
    return groups;
}
