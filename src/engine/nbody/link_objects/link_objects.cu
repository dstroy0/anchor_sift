// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "link_objects.h"

#include "golden_bands.h"
#include "relate_frames.h"
#include "track.h"
#include "radix_keys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DAMP_DIMENSIONS 3u

static unsigned long long s_forest_placed = 0ull;

static unsigned long long s_forest_kept = 0ull;

unsigned long long g_mutual_alone = 0ull;

unsigned long long g_mutual_split = 0ull;

unsigned long long g_mutual_empty = 0ull;

unsigned long long g_mutual_moved = 0ull;

unsigned long long g_damp_leaves = 0ull;

unsigned long long g_damp_landings = 0ull;

#define SETTLE_ROUNDS 64u

#define FOCUS_PASSES 8u

#define FOCUS_MEMBERS 4u

unsigned long long web_count(const TreeFrame *earlier, unsigned int object, const TreeFrame *later,
                                    unsigned int candidate, const unsigned int *near_start,
                                    const unsigned int *nearby, const unsigned int *later_near_start,
                                    const unsigned int *later_nearby, unsigned int *seen, unsigned int mark)
{
    unsigned long long kept = 0ull;
    for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u];
         member += 1u)
    {
        const unsigned int leaf = earlier->members[member];
        for (unsigned int near = near_start[leaf]; near < near_start[leaf + 1u]; near += 1u)
        {
            const unsigned int neighbour = nearby[near];
            const unsigned int outside = (unsigned int)(earlier->object_of[neighbour] != object);
            const unsigned int fresh = (unsigned int)(seen[neighbour] != mark);
            seen[neighbour] = (outside != 0u) ? mark : seen[neighbour];
            const int landing = ((outside != 0u) && (fresh != 0u)) ? earlier->forward[neighbour] : -1;
            if (landing < 0)
            {
                continue;
            }
            const unsigned int landed = (unsigned int)landing;
            unsigned int beside = 0u;
            for (unsigned int step = later_near_start[landed]; step <= later_near_start[landed + 1u]; step += 1u)
            {
                const unsigned int other = (step < later_near_start[landed + 1u]) ? later_nearby[step] : landed;
                beside |= (unsigned int)(later->object_of[other] == candidate);
            }
            kept += (unsigned long long)(beside != 0u);
        }
    }
    return kept;
}

unsigned long long g_web_asked = 0ull;

unsigned long long g_web_moved = 0ull;

unsigned long long g_web_capped = 0ull;

static unsigned int arm_landing(const TreeFrame *tree, unsigned int object, const TreeFrame *beyond,
                                unsigned int by_band)
{
    if ((tree->arm_forward == NULL) || (tree->arm_count == 0u) || (beyond == NULL))
    {
        return 0xFFFFFFFFu;
    }
    unsigned long long widest = 0ull;
    unsigned int landed = 0xFFFFFFFFu;
    for (unsigned int member = tree->member_start[object]; member < tree->member_start[object + 1u]; member += 1u)
    {
        const unsigned int leaf = tree->members[member];
        const int reached = tree->arm_forward[leaf];
        const unsigned long long voxels = band_or_count(by_band, tree->sizes[leaf]);
        landed = ((reached >= 0) && (voxels > widest)) ? beyond->object_of[(unsigned int)reached] : landed;
        widest = ((reached >= 0) && (voxels > widest)) ? voxels : widest;
    }
    return landed;
}

static unsigned int onward_of(const TreeFrame *later, unsigned int target)
{
    if ((later->link_start == NULL) || (later->link_start[target + 1u] <= later->link_start[target]))
    {
        return 0xFFFFFFFFu;
    }
    return later->link_target[later->link_start[target]];
}

unsigned int focus_links(TreeFrame *frames, unsigned int frame_count, unsigned int by_band)
{
    unsigned int moved = 0u;
    for (unsigned int pass = 0u; pass < FOCUS_PASSES; pass += 1u)
    {
        unsigned int moving = 0u;
        for (unsigned int step = 0u; (step + 2u) < frame_count; step += 1u)
        {
            const unsigned int frame = ((pass & 1u) == 0u) ? step : (frame_count - 3u - step);
            TreeFrame *const tree = &frames[frame];
            const TreeFrame *const later = &frames[frame + 1u];
            const TreeFrame *const beyond = &frames[frame + 2u];
            if ((tree->pool_start == NULL) || (tree->link_start == NULL) || (tree->arm_forward == NULL))
            {
                continue;
            }
            for (unsigned int object = 0u; object < tree->object_count; object += 1u)
            {
                const unsigned int members = tree->member_start[object + 1u] - tree->member_start[object];
                if (members > FOCUS_MEMBERS)
                {
                    continue;
                }
                const unsigned int reached = arm_landing(tree, object, beyond, by_band);
                const unsigned int links = tree->link_start[object + 1u] - tree->link_start[object];
                const unsigned int taken = (links == 1u) ? tree->link_target[tree->link_start[object]] : 0xFFFFFFFFu;
                const unsigned int leads = (taken != 0xFFFFFFFFu) ? onward_of(later, taken) : 0xFFFFFFFFu;
                if ((reached == 0xFFFFFFFFu) || (leads == 0xFFFFFFFFu) || (reached == leads))
                {
                    continue;
                }
                unsigned int held = 0u;
                for (unsigned int slot = tree->pool_start[object]; slot < tree->pool_start[object + 1u]; slot += 1u)
                {
                    held = (tree->pool_target[slot] == taken) ? tree->pool_weight[slot] : held;
                }
                unsigned int found = 0xFFFFFFFFu;
                unsigned int most = 0u;
                for (unsigned int slot = tree->pool_start[object]; slot < tree->pool_start[object + 1u]; slot += 1u)
                {
                    const unsigned int candidate = tree->pool_target[slot];
                    const unsigned int agrees = (unsigned int)(onward_of(later, candidate) == reached);
                    const unsigned int level = (unsigned int)((tree->pool_weight[slot] * 2u) >= held);
                    const int ahead = (agrees != 0u) && (level != 0u)
                                   && ((tree->pool_weight[slot] > most) || (found == 0xFFFFFFFFu));
                    most = (ahead != 0) ? tree->pool_weight[slot] : most;
                    found = (ahead != 0) ? candidate : found;
                }
                if ((found == 0xFFFFFFFFu) || (found == taken))
                {
                    continue;
                }
                tree->link_target[tree->link_start[object]] = found;
                moving += 1u;
            }
        }
        moved += moving;
        if (moving == 0u)
        {
            break;
        }
    }
    return moved;
}

static int settle_links(TreeFrame *earlier, const TreeFrame *later)
{
    const unsigned int objects = earlier->object_count;
    if ((earlier->pool_start == NULL) || (earlier->link_start == NULL))
    {
        return 1;
    }
    unsigned int *const held = (unsigned int *)malloc(((size_t)objects + 1u) * sizeof(unsigned int));
    unsigned char *const turned = (unsigned char *)calloc((size_t)earlier->pool_start[objects] + 1u, 1u);
    unsigned int *const survivor = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const standing = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                      * sizeof(unsigned long long));
    if ((held == NULL) || (turned == NULL) || (survivor == NULL) || (standing == NULL))
    {
        free(held);
        free(turned);
        free(survivor);
        free(standing);
        return 0;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int linked = (earlier->link_start[object + 1u] > earlier->link_start[object])
                                  ? earlier->link_target[earlier->link_start[object]] : 0xFFFFFFFFu;
        held[object] = 0xFFFFFFFFu;
        for (unsigned int slot = earlier->pool_start[object]; slot < earlier->pool_start[object + 1u]; slot += 1u)
        {
            held[object] = (earlier->pool_target[slot] == linked) ? slot : held[object];
        }
    }
    unsigned int moving = 1u;
    for (unsigned int round = 0u; (round < SETTLE_ROUNDS) && (moving != 0u); round += 1u)
    {
        for (unsigned int target = 0u; target <= later->object_count; target += 1u)
        {
            survivor[target] = 0xFFFFFFFFu;
            standing[target] = 0ull;
        }
        for (unsigned int object = 0u; object < objects; object += 1u)
        {
            const unsigned int slot = held[object];
            if (slot == 0xFFFFFFFFu)
            {
                continue;
            }
            unsigned long long second = 0ull;
            for (unsigned int other = earlier->pool_start[object]; other < earlier->pool_start[object + 1u];
                 other += 1u)
            {
                const int open = (turned[other] == 0u) && (other != slot);
                second = ((open != 0) && ((unsigned long long)earlier->pool_weight[other] > second))
                       ? (unsigned long long)earlier->pool_weight[other] : second;
            }
            const unsigned long long mine = (unsigned long long)earlier->pool_weight[slot];
            const unsigned long long delta = (mine > second) ? (mine - second) : 0ull;
            const unsigned int target = earlier->pool_target[slot];
            const int ahead = (delta > standing[target])
                           || ((delta == standing[target]) && (survivor[target] == 0xFFFFFFFFu));
            standing[target] = (ahead != 0) ? delta : standing[target];
            survivor[target] = (ahead != 0) ? object : survivor[target];
        }
        moving = 0u;
        for (unsigned int object = 0u; object < objects; object += 1u)
        {
            const unsigned int slot = held[object];
            if (slot == 0xFFFFFFFFu)
            {
                continue;
            }
            const unsigned int target = earlier->pool_target[slot];
            if (survivor[target] == object)
            {
                continue;
            }
            turned[slot] = 1u;
            unsigned int next = 0xFFFFFFFFu;
            unsigned long long most = 0ull;
            for (unsigned int other = earlier->pool_start[object]; other < earlier->pool_start[object + 1u];
                 other += 1u)
            {
                const int open = (turned[other] == 0u);
                const int better = (open != 0) && (((unsigned long long)earlier->pool_weight[other] > most)
                                                   || (next == 0xFFFFFFFFu));
                most = (better != 0) ? (unsigned long long)earlier->pool_weight[other] : most;
                next = (better != 0) ? other : next;
            }
            held[object] = (next != 0xFFFFFFFFu) ? next : slot;
            turned[slot] = (next != 0xFFFFFFFFu) ? 1u : 0u;
            moving += (unsigned int)(next != 0xFFFFFFFFu);
        }
    }
    unsigned int written = 0u;
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int slot = held[object];
        earlier->link_target[written] = (slot != 0xFFFFFFFFu) ? earlier->pool_target[slot] : 0u;
        written += (unsigned int)(slot != 0xFFFFFFFFu);
        earlier->link_start[object + 1u] = written;
    }
    free(held);
    free(turned);
    free(survivor);
    free(standing);
    return 1;
}

int link_objects_unbound(TreeFrame *earlier, const TreeFrame *later, const TreeFrame *before,
                                const TreeFrame *after, const TreeRules *rules)
{
    const unsigned int objects = earlier->object_count;
    const size_t room = (size_t)earlier->triple_count + (size_t)earlier->leaf_count + 1u;
    unsigned int *const pool = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const cost = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                  * sizeof(unsigned long long));
    unsigned long long *const weight = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                    * sizeof(unsigned long long));
    unsigned long long *const under = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                   * sizeof(unsigned long long));
    unsigned int *const stamp = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    unsigned int *const place = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    unsigned long long *const votes = (rules->vote != 0)
                                    ? (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                   * sizeof(unsigned long long))
                                    : NULL;
    unsigned long long *const target_voxels = (unsigned long long *)calloc((size_t)later->object_count + 1u,
                                                                           sizeof(unsigned long long));
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
        const int joined = (frame_contacts(earlier, &near_start, &nearby) != 0)
                        && (frame_contacts(later, &later_near_start, &later_nearby) != 0);
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
    earlier->link_target = (unsigned int *)malloc(room * sizeof(unsigned int));
    if ((pool == NULL) || (cost == NULL) || (weight == NULL) || (under == NULL) || (stamp == NULL)
     || (place == NULL) || (target_voxels == NULL) || (earlier->link_start == NULL)
     || (earlier->link_target == NULL))
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
    earlier->pool_target = (unsigned int *)malloc(room * sizeof(unsigned int));
    earlier->pool_weight = (unsigned int *)malloc(room * sizeof(unsigned int));
    earlier->pool_cost = (unsigned long long *)malloc(room * sizeof(unsigned long long));
    if ((earlier->pool_start == NULL) || (earlier->pool_target == NULL) || (earlier->pool_weight == NULL)
     || (earlier->pool_cost == NULL))
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
    unsigned int *spectrum = (level != NULL)
                           ? (unsigned int *)calloc((size_t)DAMP_DIMENSIONS * DAMP_BANDS, sizeof(unsigned int))
                           : NULL;
    unsigned int *gain = (spectrum != NULL)
                       ? (unsigned int *)calloc(((size_t)earlier->leaf_count + 2u) * DAMP_DIMENSIONS,
                                                sizeof(unsigned int))
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
        const unsigned int whole = band_of(counted);
        for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
        {
            const int *const own = &earlier->forward_lag[3u * leaf];
            unsigned int out = 0u;
            for (unsigned int axis = 0u; axis < DAMP_DIMENSIONS; axis += 1u)
            {
                const int apart = own[axis] - earlier->lag_to_next[axis];
                const unsigned long long far = (unsigned long long)((apart < 0) ? -apart : apart);
                const unsigned int held = band_of((unsigned long long)spectrum[(axis * DAMP_BANDS) + band_of(far)]);
                gain[(leaf * DAMP_DIMENSIONS) + axis] = (whole > held) ? (whole - held) : 0u;
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
            const unsigned int past = (earlier->triple_start != NULL) ? earlier->triple_start[leaf + 1u] : 0u;
            for (unsigned int pair = first; pair <= past; pair += 1u)
            {
                const unsigned int quieter = (level != NULL) ? level[leaf] : 0u;
                const int landing = ((earlier->forward != NULL) && (quieter == 0u)) ? earlier->forward[leaf] : -1;
                g_damp_landings += (unsigned long long)((pair == past) && (quieter != 0u)
                                                        && (earlier->forward != NULL)
                                                        && (earlier->forward[leaf] >= 0));
                const int met = (pair < past) ? (int)earlier->triple_after[pair] : landing;
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
                const unsigned int *const meeting = (earlier->triple_still != NULL) ? earlier->triple_still
                                                                                    : earlier->triple_shared;
                weight[place[target]] += (pair < past) ? ((unsigned long long)meeting[pair] >> quieter) : 0ull;
                const unsigned long long apart = leaf_disagreement(earlier, leaf, later, other,
                                                                   (gain != NULL)
                                                                   ? &gain[(size_t)leaf * DAMP_DIMENSIONS] : NULL);
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
            const int carried = (rules->share != 0)
                              ? ((weight[slot] * under[leader]) > (weight[leader] * under[slot]))
                              : (weight[slot] > weight[leader]);
            const int ahead = (votes != NULL)
                            ? ((votes[slot] > votes[leader])
                               || ((votes[slot] == votes[leader]) && (carried != 0)))
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
        unsigned long long most = 0ull;
        if (asks_web != 0)
        {
            mark += 1u;
            most = web_count(earlier, object, later, pool[leader], near_start, nearby, later_near_start,
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
            followed = (kept > most) ? slot : followed;
            most = (kept > most) ? kept : most;
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
            const unsigned long long room = source_voxels * source_voxels * 64ull;
            const int held = (walled == 0u) && ((bend * bend * bend) <= room);
            const int ahead = (same != 0) && (held != 0) && (inside == 0u);
            champion = (ahead != 0) ? slot : champion;
            inside += (unsigned int)((same != 0) && (held != 0));
            cost[slot] = ((same != 0) && (held != 0))
                       ? ((cost[slot] & ~LINK_MAGNITUDE_MASK) | (bend & LINK_MAGNITUDE_MASK)) : cost[slot];
        }
        const unsigned long long leader_bend = (contested != 0u)
                                             ? track_bend(before, earlier, object, later, pool[leader], after,
                                                          (unsigned int)rules->mass_band) : 0ull;
        const int leader_held = (leader_bend <= 0xFFFFull)
                             && ((leader_bend * leader_bend * leader_bend)
                                 <= (source_voxels * source_voxels * 64ull));
        const unsigned int winner = ((contested != 0u) && (leader_held == 0) && (inside != 0u)) ? champion : leader;
        unsigned long long best = 0xFFFFFFFFFFFFFFFFull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                               : (weight[slot] == weight[winner]));
            best = ((level != 0) && (cost[slot] < best)) ? cost[slot] : best;
        }
        unsigned long long crowned = 0ull;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
                               : (weight[slot] == weight[winner]));
            crowned = ((level != 0) && (cost[slot] == best) && (weight[slot] > crowned)) ? weight[slot] : crowned;
        }
        unsigned int kept = 0u;
        for (unsigned int slot = 0u; slot < filled; slot += 1u)
        {
            const int level = (contested != 0u)
                            ? ((cost[slot] >> LINK_MAGNITUDE_BITS) == (cost[winner] >> LINK_MAGNITUDE_BITS))
                            : ((rules->share != 0)
                               ? ((weight[slot] * under[winner]) == (weight[winner] * under[slot]))
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
    if ((rules->mutual != 0) && (earlier->pool_start != NULL) && (later->backward != NULL)
     && (later->member_start != NULL))
    {
        unsigned int *const chooses = (unsigned int *)malloc(((size_t)later->object_count + 1u)
                                                             * sizeof(unsigned int));
        unsigned long long *const reached = (unsigned long long *)calloc((size_t)objects + 2u,
                                                                         sizeof(unsigned long long));
        unsigned char *const claimed = (unsigned char *)calloc((size_t)later->object_count + 2u, 1u);
        if ((chooses != NULL) && (reached != NULL) && (claimed != NULL))
        {
            for (unsigned int target = 0u; target < later->object_count; target += 1u)
            {
                const unsigned int first = later->member_start[target];
                const unsigned int past = later->member_start[target + 1u];
                for (unsigned int member = first; member < past; member += 1u)
                {
                    const int back = later->backward[later->members[member]];
                    const unsigned int where = (back >= 0) ? earlier->object_of[(unsigned int)back] : objects;
                    reached[where] += (unsigned long long)later->sizes[later->members[member]];
                }
                unsigned int best = 0xFFFFFFFFu;
                unsigned long long most = 0ull;
                for (unsigned int member = first; member < past; member += 1u)
                {
                    const int back = later->backward[later->members[member]];
                    const unsigned int where = (back >= 0) ? earlier->object_of[(unsigned int)back] : objects;
                    const int ahead = (back >= 0) && (reached[where] > most);
                    most = (ahead != 0) ? reached[where] : most;
                    best = (ahead != 0) ? where : best;
                }
                for (unsigned int member = first; member < past; member += 1u)
                {
                    const int back = later->backward[later->members[member]];
                    reached[(back >= 0) ? earlier->object_of[(unsigned int)back] : objects] = 0ull;
                }
                chooses[target] = best;
            }
            for (unsigned int own = 0u; own < objects; own += 1u)
            {
                unsigned int survivors = 0u;
                for (unsigned int slot = earlier->pool_start[own]; slot < earlier->pool_start[own + 1u];
                     slot += 1u)
                {
                    survivors += (unsigned int)(chooses[earlier->pool_target[slot]] == own);
                }
                g_mutual_alone += (unsigned long long)(survivors == 1u);
                g_mutual_split += (unsigned long long)(survivors > 1u);
                g_mutual_empty += (unsigned long long)(survivors == 0u);
            }
            unsigned int moving = 1u;
            while (moving != 0u)
            {
                moving = 0u;
                for (unsigned int own = 0u; own < objects; own += 1u)
                {
                    const unsigned int links = earlier->link_start[own + 1u] - earlier->link_start[own];
                    unsigned int survivors = 0u;
                    unsigned int only = 0xFFFFFFFFu;
                    for (unsigned int slot = earlier->pool_start[own];
                         (links == 1u) && (slot < earlier->pool_start[own + 1u]); slot += 1u)
                    {
                        const unsigned int candidate = earlier->pool_target[slot];
                        const unsigned int lives = (unsigned int)((chooses[candidate] == own)
                                                                  && (claimed[candidate] == 0u));
                        survivors += lives;
                        only = (lives != 0u) ? candidate : only;
                    }
                    const unsigned int at = earlier->link_start[own];
                    const unsigned int taken = (links == 1u) ? earlier->link_target[at] : 0xFFFFFFFFu;
                    const unsigned int settles = (unsigned int)((links == 1u) && (survivors == 1u));
                    const unsigned int changes = (unsigned int)((settles != 0u) && (only != taken));
                    earlier->link_target[(links == 1u) ? at : 0u] =
                        (settles != 0u) ? only : ((links == 1u) ? taken : earlier->link_target[0u]);
                    claimed[(settles != 0u) ? only : later->object_count] =
                        (settles != 0u) ? 1u : claimed[later->object_count];
                    g_mutual_moved += (unsigned long long)changes;
                    moving += changes;
                }
            }
        }
        free(chooses);
        free(reached);
        free(claimed);
    }
    if ((rules->forest != 0) && (earlier->pool_start != NULL) && (earlier->link_start != NULL))
    {
        const unsigned int room = earlier->pool_start[objects];
        unsigned long long *const order = (unsigned long long *)malloc(((size_t)room + 1u)
                                                                       * sizeof(unsigned long long));
        unsigned char *const taken = (unsigned char *)calloc((size_t)later->object_count + 2u, 1u);
        unsigned char *const settled = (unsigned char *)calloc((size_t)objects + 2u, 1u);
        if ((order != NULL) && (taken != NULL) && (settled != NULL))
        {
            unsigned int held = 0u;
            for (unsigned int own = 0u; own < objects; own += 1u)
            {
                for (unsigned int slot = earlier->pool_start[own]; slot < earlier->pool_start[own + 1u];
                     slot += 1u)
                {
                    const unsigned long long strength = (unsigned long long)earlier->pool_weight[slot];
                    order[held] = (strength << 32u) | (unsigned long long)slot;
                    held += 1u;
                }
            }
            radix_sort_keys(order, held);
            for (unsigned int at = held; at > 0u; at -= 1u)
            {
                const unsigned int slot = (unsigned int)(order[at - 1u] & 0xFFFFFFFFull);
                const unsigned int candidate = earlier->pool_target[slot];
                unsigned int own = 0u;
                unsigned int low = 0u;
                unsigned int high = objects;
                while ((high - low) > 1u)
                {
                    const unsigned int middle = low + ((high - low) / 2u);
                    low = (earlier->pool_start[middle] <= slot) ? middle : low;
                    high = (earlier->pool_start[middle] <= slot) ? high : middle;
                }
                own = low;
                const unsigned int links = earlier->link_start[own + 1u] - earlier->link_start[own];
                const unsigned int free_pair = (unsigned int)((links == 1u) && (settled[own] == 0u)
                                                              && (taken[candidate] == 0u));
                earlier->link_target[(links == 1u) ? earlier->link_start[own] : 0u] =
                    (free_pair != 0u) ? candidate
                                      : earlier->link_target[(links == 1u) ? earlier->link_start[own] : 0u];
                settled[own] = (free_pair != 0u) ? 1u : settled[own];
                taken[candidate] = (free_pair != 0u) ? 1u : taken[candidate];
                s_forest_placed += (unsigned long long)(free_pair != 0u);
            }
            for (unsigned int own = 0u; own < objects; own += 1u)
            {
                const unsigned int links = earlier->link_start[own + 1u] - earlier->link_start[own];
                s_forest_kept += (unsigned long long)((links == 1u) && (settled[own] == 0u));
            }
        }
        free(order);
        free(taken);
        free(settled);
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

int link_objects(TreeFrame *earlier, const TreeFrame *later, const TreeRules *rules)
{
    unsigned long long *const candidate = (unsigned long long *)malloc(((size_t)earlier->leaf_count + 1u)
                                                                       * sizeof(unsigned long long));
    unsigned long long *const confirmed = (unsigned long long *)malloc(((size_t)later->leaf_count + 1u)
                                                                       * sizeof(unsigned long long));
    unsigned int *const incoming = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    earlier->link_start = (unsigned int *)calloc((size_t)earlier->object_count + 2u, sizeof(unsigned int));
    earlier->link_target = (unsigned int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned int));
    unsigned int *const mutual = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const weight = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                    * sizeof(unsigned long long));
    unsigned long long *const under = (unsigned long long *)malloc(((size_t)later->object_count + 1u)
                                                                   * sizeof(unsigned long long));
    if ((candidate == NULL) || (confirmed == NULL) || (incoming == NULL) || (earlier->link_start == NULL)
     || (earlier->link_target == NULL) || (mutual == NULL) || (weight == NULL) || (under == NULL))
    {
        free(candidate);
        free(confirmed);
        free(incoming);
        free(mutual);
        free(weight);
        free(under);
        return 0;
    }
    unsigned int candidates = 0u;
    for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
    {
        if (earlier->forward[leaf] >= 0)
        {
            candidate[candidates] = ((unsigned long long)earlier->object_of[leaf] << 32u)
                                  | later->object_of[(unsigned int)earlier->forward[leaf]];
            candidates += 1u;
        }
    }
    candidates = engine_sort_unique(candidate, candidates);
    unsigned int confirmations = 0u;
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        if (later->backward[leaf] >= 0)
        {
            confirmed[confirmations] = ((unsigned long long)later->object_of[leaf] << 32u)
                                     | earlier->object_of[(unsigned int)later->backward[leaf]];
            confirmations += 1u;
        }
    }
    confirmations = engine_sort_unique(confirmed, confirmations);
    for (unsigned int position = 0u; position < candidates; position += 1u)
    {
        incoming[(unsigned int)(candidate[position] & 0xFFFFFFFFULL)] += 1u;
    }

    unsigned int written = 0u;
    unsigned int position = 0u;
    while (position < candidates)
    {
        const unsigned int source = (unsigned int)(candidate[position] >> 32u);
        unsigned int end = position;
        while ((end < candidates) && ((unsigned int)(candidate[end] >> 32u) == source))
        {
            end += 1u;
        }
        unsigned int mutual_count = 0u;
        for (unsigned int slot = position; slot < end; slot += 1u)
        {
            const unsigned int target = (unsigned int)(candidate[slot] & 0xFFFFFFFFULL);
            int keep = (rules->forward_only != 0);
            if (keep == 0)
            {
                const unsigned long long sought = ((unsigned long long)target << 32u) | source;
                const void *const found = bsearch(&sought, confirmed, confirmations, sizeof(unsigned long long),
                                                  engine_order_keys);
                keep = (found != NULL);
                if ((keep == 0) && (rules->merge_target != 0))
                {
                    keep = (incoming[target] >= 2u);
                }
            }
            if (keep != 0)
            {
                mutual[mutual_count] = target;
                mutual_count += 1u;
            }
        }
        if ((rules->pick != 0) && (mutual_count >= 2u))
        {
            for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
            {
                weight[slot] = 0ULL;
            }
            unsigned long long source_voxels = 0ULL;
            for (unsigned int member = earlier->member_start[source]; member < earlier->member_start[source + 1u];
                 member += 1u)
            {
                source_voxels += (unsigned long long)earlier->sizes[earlier->members[member]];
            }
            for (unsigned int member = earlier->member_start[source]; member < earlier->member_start[source + 1u];
                 member += 1u)
            {
                const unsigned int leaf = earlier->members[member];
                for (unsigned int pair = earlier->triple_start[leaf]; pair < earlier->triple_start[leaf + 1u];
                     pair += 1u)
                {
                    const unsigned int after_object = later->object_of[earlier->triple_after[pair]];
                    for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
                    {
                        if (mutual[slot] == after_object)
                        {
                            weight[slot] += earlier->triple_shared[pair];
                            break;
                        }
                    }
                }
            }
            for (unsigned int slot = 0u; (rules->share != 0) && (slot < mutual_count); slot += 1u)
            {
                unsigned long long target_voxels = 0ULL;
                for (unsigned int member = later->member_start[mutual[slot]];
                     member < later->member_start[mutual[slot] + 1u]; member += 1u)
                {
                    target_voxels += (unsigned long long)later->sizes[later->members[member]];
                }
                under[slot] = (source_voxels + target_voxels) - weight[slot];
            }
            unsigned int leader = 0u;
            for (unsigned int slot = 1u; slot < mutual_count; slot += 1u)
            {
                const int ahead = (rules->share != 0)
                                ? ((weight[slot] * under[leader]) > (weight[leader] * under[slot]))
                                : (weight[slot] > weight[leader]);
                leader = (ahead != 0) ? slot : leader;
            }
            if (weight[leader] > 0ULL)
            {
                unsigned int narrowed = 0u;
                for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
                {
                    const int level = (rules->share != 0)
                                    ? ((weight[slot] * under[leader]) == (weight[leader] * under[slot]))
                                    : (weight[slot] == weight[leader]);
                    mutual[narrowed] = mutual[slot];
                    narrowed += (unsigned int)(level != 0);
                }
                mutual_count = narrowed;
            }
        }
        for (unsigned int slot = 0u; slot < mutual_count; slot += 1u)
        {
            earlier->link_target[written] = mutual[slot];
            written += 1u;
        }
        earlier->link_start[source + 1u] = mutual_count;
        position = end;
    }
    for (unsigned int object = 0u; object < earlier->object_count; object += 1u)
    {
        earlier->link_start[object + 1u] += earlier->link_start[object];
    }
    free(candidate);
    free(confirmed);
    free(incoming);
    free(mutual);
    free(weight);
    free(under);
    return 1;
}
