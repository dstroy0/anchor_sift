// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// link_objects_unbound.cu: linking unbound objects
#include "link_objects_internal.h"

unsigned long long g_damp_leaves = 0ull;

unsigned long long g_damp_landings = 0ull;

unsigned long long g_web_asked = 0ull;

unsigned long long g_web_moved = 0ull;

unsigned long long g_web_capped = 0ull;

int link_objects_unbound(TreeFrame *earlier, const TreeFrame *later, const TreeFrame *before, const TreeFrame *after,
                         const TreeRules *rules)
{
    const unsigned int objects = earlier->object_count;
    const size_t capacity = (size_t)earlier->triple_count + (size_t)earlier->leaf_count + 1u;
    unsigned int *const pool = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const cost =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    unsigned long long *const weight =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    unsigned long long *const under =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    unsigned int *const stamp = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    unsigned int *const place = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    unsigned long long *const votes =
        (rules->vote != 0)
            ? (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long))
            : NULL;
    unsigned long long *const target_voxels =
        (unsigned long long *)calloc((size_t)later->object_count + 1u, sizeof(unsigned long long));
    for (unsigned int leaf = 0u; (target_voxels != NULL) && (leaf < later->leaf_count); leaf += 1u)
    {
        target_voxels[later->object_of[leaf]] += (unsigned long long)later->sizes[leaf];
    }
    unsigned int *near_start = NULL;
    unsigned int *nearby = NULL;
    unsigned int *later_near_start = NULL;
    unsigned int *later_nearby = NULL;
    unsigned int *seen = NULL;
    unsigned int mark = 0u;
    if (rules->web != 0)
    {
        const int joined = (frame_contacts(earlier, &near_start, &nearby) != 0) &&
                           (frame_contacts(later, &later_near_start, &later_nearby) != 0);
        seen = (unsigned int *)calloc((size_t)earlier->leaf_count + 2u, sizeof(unsigned int));
        if ((joined == 0) || (seen == NULL))
        {
            free(near_start);
            free(nearby);
            free(later_near_start);
            free(later_nearby);
            free(seen);
            near_start = NULL;
            nearby = NULL;
            later_near_start = NULL;
            later_nearby = NULL;
            seen = NULL;
        }
    }
    earlier->link_start = (unsigned int *)calloc((size_t)objects + 2u, sizeof(unsigned int));
    earlier->link_target = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    if ((pool == NULL) || (cost == NULL) || (weight == NULL) || (under == NULL) || (stamp == NULL) || (place == NULL) ||
        (target_voxels == NULL) || (earlier->link_start == NULL) || (earlier->link_target == NULL))
    {
        free(pool);
        free(cost);
        free(weight);
        free(under);
        free(stamp);
        free(place);
        free(target_voxels);
        free(votes);
        free(near_start);
        free(nearby);
        free(later_near_start);
        free(later_nearby);
        free(seen);
        return 0;
    }
    earlier->pool_start = (unsigned int *)calloc((size_t)objects + 2u, sizeof(unsigned int));
    earlier->pool_target = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    earlier->pool_weight = (unsigned int *)malloc(capacity * sizeof(unsigned int));
    earlier->pool_cost = (unsigned long long *)malloc(capacity * sizeof(unsigned long long));
    if ((earlier->pool_start == NULL) || (earlier->pool_target == NULL) || (earlier->pool_weight == NULL) ||
        (earlier->pool_cost == NULL))
    {
        free(earlier->pool_start);
        free(earlier->pool_target);
        free(earlier->pool_weight);
        free(earlier->pool_cost);
        earlier->pool_start = NULL;
        earlier->pool_target = NULL;
        earlier->pool_weight = NULL;
        earlier->pool_cost = NULL;
    }
    unsigned int *level = NULL;
    if ((rules->damp != 0) && (earlier->forward_lag != NULL) && (earlier->leaf_count != 0u))
    {
        level = (unsigned int *)calloc((size_t)earlier->leaf_count + 2u, sizeof(unsigned int));
    }
    unsigned int *spectrum =
        (level != NULL) ? (unsigned int *)calloc((size_t)DAMP_DIMENSIONS * DAMP_BANDS, sizeof(unsigned int)) : NULL;
    unsigned int *gain =
        (spectrum != NULL)
            ? (unsigned int *)calloc(((size_t)earlier->leaf_count + 2u) * DAMP_DIMENSIONS, sizeof(unsigned int))
            : NULL;
    if (gain != NULL)
    {
        unsigned long long spread[DAMP_DIMENSIONS] = {0ull, 0ull, 0ull};
        const unsigned long long counted = (unsigned long long)earlier->leaf_count;
        for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
        {
            const int *const own = &earlier->forward_lag[3u * leaf];
            for (unsigned int axis = 0u; axis < DAMP_DIMENSIONS; axis += 1u)
            {
                const int apart = own[axis] - earlier->lag_to_next[axis];
                const unsigned long long far = (unsigned long long)((apart < 0) ? -apart : apart);
                spread[axis] += far;
                spectrum[(axis * DAMP_BANDS) + band_of(far)] += 1u;
            }
        }
        const unsigned int near_band = band_of(counted);
        for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
        {
            const int *const own = &earlier->forward_lag[3u * leaf];
            unsigned int out = 0u;
            for (unsigned int axis = 0u; axis < DAMP_DIMENSIONS; axis += 1u)
            {
                const int apart = own[axis] - earlier->lag_to_next[axis];
                const unsigned long long far = (unsigned long long)((apart < 0) ? -apart : apart);
                const unsigned int far_band = band_of((unsigned long long)spectrum[(axis * DAMP_BANDS) + band_of(far)]);
                gain[(leaf * DAMP_DIMENSIONS) + axis] = (near_band > far_band) ? (near_band - far_band) : 0u;
                out += (unsigned int)((far * counted) > (spread[axis] * DAMP_DEVIATIONS));
            }
            level[leaf] = (out != 0u) ? 1u : 0u;
            g_damp_leaves += (unsigned long long)(out != 0u);
        }
    }
    unsigned int written = 0u;
    unsigned int gathered = 0u;
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        unsigned int filled = 0u;
        for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u];
             member += 1u)
        {
            const unsigned int leaf = earlier->members[member];
            const unsigned int first = (earlier->triple_start != NULL) ? earlier->triple_start[leaf] : 0u;
            const unsigned int last = (earlier->triple_start != NULL) ? earlier->triple_start[leaf + 1u] : 0u;
            for (unsigned int pair = first; pair <= last; pair += 1u)
            {
                const unsigned int quieter = (level != NULL) ? level[leaf] : 0u;
                const int landing = ((earlier->forward != NULL) && (quieter == 0u)) ? earlier->forward[leaf] : -1;
                g_damp_landings += (unsigned long long)((pair == last) && (quieter != 0u) &&
                                                        (earlier->forward != NULL) && (earlier->forward[leaf] >= 0));
                const int met = (pair < last) ? (int)earlier->triple_after[pair] : landing;
                if (met < 0)
                {
                    continue;
                }
                const unsigned int other = (unsigned int)met;
                const unsigned int target = later->object_of[other];
                const unsigned int fresh = (unsigned int)(stamp[target] != (object + 1u));
                pool[filled] = target;
                place[target] = (fresh != 0u) ? filled : place[target];
                filled += fresh;
                stamp[target] = object + 1u;
                weight[place[target]] = (fresh != 0u) ? 0ull : weight[place[target]];
                cost[place[target]] = (fresh != 0u) ? 0xFFFFFFFFFFFFFFFFull : cost[place[target]];
                const unsigned int *const meeting =
                    (earlier->triple_still != NULL) ? earlier->triple_still : earlier->triple_shared;
                weight[place[target]] += (pair < last) ? ((unsigned long long)meeting[pair] >> quieter) : 0ull;
                const unsigned long long apart = leaf_disagreement(
                    earlier, leaf, later, other, (gain != NULL) ? &gain[(size_t)leaf * DAMP_DIMENSIONS] : NULL);
                cost[place[target]] = (apart < cost[place[target]]) ? apart : cost[place[target]];
            }
        }
        unsigned long long source_voxels = 0ull;
        for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u];
             member += 1u)
        {
            source_voxels += (unsigned long long)earlier->sizes[earlier->members[member]];
        }
        for (unsigned int slot = 0u; (rules->share != 0) && (slot < filled); slot += 1u)
        {
            under[slot] = (source_voxels + target_voxels[pool[slot]]) - weight[slot];
        }
        for (unsigned int slot = 0u; (votes != NULL) && (slot < filled); slot += 1u)
        {
            votes[slot] = 0ull;
        }
        for (unsigned int member = earlier->member_start[object];
             (votes != NULL) && (member < earlier->member_start[object + 1u]); member += 1u)
        {
            const unsigned int leaf = earlier->members[member];
            const int landing = (earlier->forward != NULL) ? earlier->forward[leaf] : -1;
            const unsigned int target = (landing >= 0) ? later->object_of[(unsigned int)landing] : 0u;
            const unsigned int known = (unsigned int)((landing >= 0) && (stamp[target] == (object + 1u)));
            votes[place[target]] += (known != 0u) ? 1ull : 0ull;
        }
        unsigned int leader = 0u;
        for (unsigned int slot = 1u; slot < filled; slot += 1u)
        {
            const int carried = (rules->share != 0) ? ((weight[slot] * under[leader]) > (weight[leader] * under[slot]))
                                                    : (weight[slot] > weight[leader]);
            const int ahead =
                (votes != NULL) ? ((votes[slot] > votes[leader]) || ((votes[slot] == votes[leader]) && (carried != 0)))
                                : carried;
            leader = (ahead != 0) ? slot : leader;
        }
        unsigned int company = 0u;
        for (unsigned int slot = 0u; (near_start != NULL) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const int close = ((weight[slot] * 2ull) >= weight[leader]);
            company += (unsigned int)((same != 0) && (close != 0) && (slot != leader));
        }
        const unsigned int members = earlier->member_start[object + 1u] - earlier->member_start[object];
        const int asks_web = (near_start != NULL) && (company != 0u) && (members <= WEB_MEMBERS);
        g_web_asked += (unsigned long long)(asks_web != 0);
        g_web_capped += (unsigned long long)((near_start != NULL) && (company != 0u) && (members > WEB_MEMBERS));
        unsigned int followed = leader;
        unsigned long long maximum = 0ull;
        if (asks_web != 0)
        {
            mark += 1u;
            maximum = web_count(earlier, object, later, pool[leader], near_start, nearby, later_near_start,
                                later_nearby, seen, mark);
        }
        for (unsigned int slot = 0u; (asks_web != 0) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const int close = ((weight[slot] * 2ull) >= weight[leader]);
            if ((same == 0) || (close == 0) || (slot == leader))
            {
                continue;
            }
            mark += 1u;
            const unsigned long long kept = web_count(earlier, object, later, pool[slot], near_start, nearby,
                                                      later_near_start, later_nearby, seen, mark);
            followed = (kept > maximum) ? slot : followed;
            maximum = (kept > maximum) ? kept : maximum;
        }
        g_web_moved += (unsigned long long)((asks_web != 0) && (followed != leader));
        leader = (asks_web != 0) ? followed : leader;
        unsigned int contested = 0u;
        for (unsigned int slot = 0u; (rules->arc != 0) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const int level = ((weight[slot] * 2ull) >= weight[leader]);
            contested += (unsigned int)((same != 0) && (level != 0) && (slot != leader));
        }
        unsigned int champion = leader;
        unsigned int inside = 0u;
        for (unsigned int slot = 0u; (contested != 0u) && (slot < filled); slot += 1u)
        {
            const int same = ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[leader] >> LINK_MAGNITUDE_BITS));
            const unsigned long long bend = (same != 0) ? track_bend(before, earlier, object, later, pool[slot], after,
                                                                     (unsigned int)rules->mass_band)
                                                        : 0xFFFFFFFFFFFFFFFFull;
            const unsigned int walled = (unsigned int)(bend > 0xFFFFFull);
            const unsigned long long capacity = source_voxels * source_voxels * 64ull;
            const int bend_fits = (walled == 0u) && ((bend * bend * bend) <= capacity);
            const int ahead = (same != 0) && (bend_fits != 0) && (inside == 0u);
            champion = (ahead != 0) ? slot : champion;
            inside += (unsigned int)((same != 0) && (bend_fits != 0));
            cost[slot] = ((same != 0) && (bend_fits != 0))
                             ? ((cost[slot] & ~LINK_MAGNITUDE_MASK) | (bend & LINK_MAGNITUDE_MASK))
                             : cost[slot];
        }
        const unsigned long long leader_bend =
            (contested != 0u)
                ? track_bend(before, earlier, object, later, pool[leader], after, (unsigned int)rules->mass_band)
                : 0ull;
        const int leader_fits = (leader_bend <= 0xFFFFull) &&
                                ((leader_bend * leader_bend * leader_bend) <= (source_voxels * source_voxels * 64ull));
        const unsigned int winner = ((contested != 0u) && (leader_fits == 0) && (inside != 0u)) ? champion : leader;
        unsigned long long best = 0xFFFFFFFFFFFFFFFFull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level =
                (contested != 0u)
                    ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                    : ((rules->share != 0) ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                                           : (weight[slot] == weight[winner]));
            best = ((level != 0) && (cost[slot] < best)) ? cost[slot] : best;
        }
        unsigned long long crowned = 0ull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level =
                (contested != 0u)
                    ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                    : ((rules->share != 0) ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                                           : (weight[slot] == weight[winner]));
            crowned = ((level != 0) && (cost[slot] == best) && (weight[slot] > crowned)) ? weight[slot] : crowned;
        }
        unsigned int kept = 0u;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level =
                (contested != 0u)
                    ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                    : ((rules->share != 0) ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                                           : (weight[slot] == weight[winner]));
            earlier->link_target[written + kept] = pool[slot];
            kept += (unsigned int)((level != 0) && (cost[slot] == best) && (weight[slot] == crowned));
        }
        earlier->link_start[object + 1u] = kept;
        written += kept;
        for (unsigned int slot = 0u; (earlier->pool_target != NULL) && (slot < filled); slot += 1u)
        {
            earlier->pool_target[gathered + slot] = pool[slot];
            earlier->pool_weight[gathered + slot] = (unsigned int)weight[slot];
            earlier->pool_cost[gathered + slot] = cost[slot];
        }
        gathered += (earlier->pool_target != NULL) ? filled : 0u;
        earlier->pool_start[object + 1u] = gathered;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        earlier->link_start[object + 1u] += earlier->link_start[object];
    }
    if ((rules->mutual != 0) && (earlier->pool_start != NULL) && (later->backward != NULL) &&
        (later->member_start != NULL))
    {
        link_objects_mutual(earlier, later, objects);
    }
    if ((rules->forest != 0) && (earlier->pool_start != NULL) && (earlier->link_start != NULL))
    {
        link_objects_forest(earlier, later, objects);
    }
    const int settled = (rules->settle != 0) ? settle_links(earlier, later) : 1;
    free(pool);
    free(cost);
    free(weight);
    free(under);
    free(stamp);
    free(place);
    free(target_voxels);
    free(votes);
    free(near_start);
    free(nearby);
    free(later_near_start);
    free(later_nearby);
    free(seen);
    free(level);
    free(spectrum);
    free(gain);
    return settled;
}
