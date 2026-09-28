// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// link_objects_web.cu: the web, landings, links settled, and the mutual and forest passes
#include "link_objects_internal.h"

static unsigned long long s_forest_placed = 0ull;

static unsigned long long s_forest_kept = 0ull;

unsigned long long g_mutual_alone = 0ull;

unsigned long long g_mutual_split = 0ull;

unsigned long long g_mutual_empty = 0ull;

unsigned long long g_mutual_moved = 0ull;

unsigned long long web_count(const TreeFrame *earlier, unsigned int object, const TreeFrame *later,
                             unsigned int candidate, const unsigned int *near_start, const unsigned int *nearby,
                             const unsigned int *later_near_start, const unsigned int *later_nearby, unsigned int *seen,
                             unsigned int mark)
{
    unsigned long long kept = 0ull;
    for (unsigned int member = earlier->member_start[object]; member < earlier->member_start[object + 1u]; member += 1u)
    {
        const unsigned int leaf = earlier->members[member];
        for (unsigned int near = near_start[leaf]; near < near_start[leaf + 1u]; near += 1u)
        {
            const unsigned int neighbor = nearby[near];
            const unsigned int outside = (unsigned int)(earlier->object_of[neighbor] != object);
            const unsigned int fresh = (unsigned int)(seen[neighbor] != mark);
            seen[neighbor] = (outside != 0u) ? mark : seen[neighbor];
            const int landing = ((outside != 0u) && (fresh != 0u)) ? earlier->forward[neighbor] : -1;
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
                unsigned int target_weight = 0u;
                for (unsigned int slot = tree->pool_start[object]; slot < tree->pool_start[object + 1u]; slot += 1u)
                {
                    target_weight = (tree->pool_target[slot] == taken) ? tree->pool_weight[slot] : target_weight;
                }
                unsigned int found = 0xFFFFFFFFu;
                unsigned int maximum = 0u;
                for (unsigned int slot = tree->pool_start[object]; slot < tree->pool_start[object + 1u]; slot += 1u)
                {
                    const unsigned int candidate = tree->pool_target[slot];
                    const unsigned int agrees = (unsigned int)(onward_of(later, candidate) == reached);
                    const unsigned int level = (unsigned int)((tree->pool_weight[slot] * 2u) >= target_weight);
                    const int ahead = (agrees != 0u) && (level != 0u) &&
                                      ((tree->pool_weight[slot] > maximum) || (found == 0xFFFFFFFFu));
                    maximum = (ahead != 0) ? tree->pool_weight[slot] : maximum;
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

int settle_links(TreeFrame *earlier, const TreeFrame *later)
{
    const unsigned int objects = earlier->object_count;
    if ((earlier->pool_start == NULL) || (earlier->link_start == NULL))
    {
        return 1;
    }
    unsigned int *const object_slot = (unsigned int *)malloc(((size_t)objects + 1u) * sizeof(unsigned int));
    unsigned char *const turned = (unsigned char *)calloc((size_t)earlier->pool_start[objects] + 1u, 1u);
    unsigned int *const survivor = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const standing =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    if ((object_slot == NULL) || (turned == NULL) || (survivor == NULL) || (standing == NULL))
    {
        free(object_slot);
        free(turned);
        free(survivor);
        free(standing);
        return 0;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int linked = (earlier->link_start[object + 1u] > earlier->link_start[object])
                                        ? earlier->link_target[earlier->link_start[object]]
                                        : 0xFFFFFFFFu;
        object_slot[object] = 0xFFFFFFFFu;
        for (unsigned int slot = earlier->pool_start[object]; slot < earlier->pool_start[object + 1u]; slot += 1u)
        {
            object_slot[object] = (earlier->pool_target[slot] == linked) ? slot : object_slot[object];
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
            const unsigned int slot = object_slot[object];
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
                             ? (unsigned long long)earlier->pool_weight[other]
                             : second;
            }
            const unsigned long long mine = (unsigned long long)earlier->pool_weight[slot];
            const unsigned long long delta = (mine > second) ? (mine - second) : 0ull;
            const unsigned int target = earlier->pool_target[slot];
            const int ahead =
                (delta > standing[target]) || ((delta == standing[target]) && (survivor[target] == 0xFFFFFFFFu));
            standing[target] = (ahead != 0) ? delta : standing[target];
            survivor[target] = (ahead != 0) ? object : survivor[target];
        }
        moving = 0u;
        for (unsigned int object = 0u; object < objects; object += 1u)
        {
            const unsigned int slot = object_slot[object];
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
            unsigned long long maximum = 0ull;
            for (unsigned int other = earlier->pool_start[object]; other < earlier->pool_start[object + 1u];
                 other += 1u)
            {
                const int open = (turned[other] == 0u);
                const int better = (open != 0) && (((unsigned long long)earlier->pool_weight[other] > maximum) ||
                                                   (next == 0xFFFFFFFFu));
                maximum = (better != 0) ? (unsigned long long)earlier->pool_weight[other] : maximum;
                next = (better != 0) ? other : next;
            }
            object_slot[object] = (next != 0xFFFFFFFFu) ? next : slot;
            turned[slot] = (next != 0xFFFFFFFFu) ? 1u : 0u;
            moving += (unsigned int)(next != 0xFFFFFFFFu);
        }
    }
    unsigned int written = 0u;
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        const unsigned int slot = object_slot[object];
        earlier->link_target[written] = (slot != 0xFFFFFFFFu) ? earlier->pool_target[slot] : 0u;
        written += (unsigned int)(slot != 0xFFFFFFFFu);
        earlier->link_start[object + 1u] = written;
    }
    free(object_slot);
    free(turned);
    free(survivor);
    free(standing);
    return 1;
}

// the mutual pass: each later object chooses the earlier object whose members reach it most, and an earlier
// object with one link moves it to the one candidate that chose it
void link_objects_mutual(TreeFrame *earlier, const TreeFrame *later, unsigned int objects)
{
    unsigned int *const chooses = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const reached = (unsigned long long *)calloc((size_t)objects + 2u, sizeof(unsigned long long));
    unsigned char *const claimed = (unsigned char *)calloc((size_t)later->object_count + 2u, 1u);
    if ((chooses != NULL) && (reached != NULL) && (claimed != NULL))
    {
        for (unsigned int target = 0u; target < later->object_count; target += 1u)
        {
            const unsigned int first = later->member_start[target];
            const unsigned int end = later->member_start[target + 1u];
            for (unsigned int member = first; member < end; member += 1u)
            {
                const int back = later->backward[later->members[member]];
                const unsigned int where = (back >= 0) ? earlier->object_of[(unsigned int)back] : objects;
                reached[where] += (unsigned long long)later->sizes[later->members[member]];
            }
            unsigned int best = 0xFFFFFFFFu;
            unsigned long long maximum = 0ull;
            for (unsigned int member = first; member < end; member += 1u)
            {
                const int back = later->backward[later->members[member]];
                const unsigned int where = (back >= 0) ? earlier->object_of[(unsigned int)back] : objects;
                const int ahead = (back >= 0) && (reached[where] > maximum);
                maximum = (ahead != 0) ? reached[where] : maximum;
                best = (ahead != 0) ? where : best;
            }
            for (unsigned int member = first; member < end; member += 1u)
            {
                const int back = later->backward[later->members[member]];
                reached[(back >= 0) ? earlier->object_of[(unsigned int)back] : objects] = 0ull;
            }
            chooses[target] = best;
        }
        for (unsigned int own = 0u; own < objects; own += 1u)
        {
            unsigned int survivors = 0u;
            for (unsigned int slot = earlier->pool_start[own]; slot < earlier->pool_start[own + 1u]; slot += 1u)
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
                    const unsigned int lives =
                        (unsigned int)((chooses[candidate] == own) && (claimed[candidate] == 0u));
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

// the forest pass: the pool's entries taken strongest first, and an object with one link given a candidate no
// other object has taken
void link_objects_forest(TreeFrame *earlier, const TreeFrame *later, unsigned int objects)
{
    const unsigned int capacity = earlier->pool_start[objects];
    unsigned long long *const order =
        (unsigned long long *)malloc(((size_t)capacity + 1u) * sizeof(unsigned long long));
    unsigned char *const taken = (unsigned char *)calloc((size_t)later->object_count + 2u, 1u);
    unsigned char *const settled = (unsigned char *)calloc((size_t)objects + 2u, 1u);
    if ((order != NULL) && (taken != NULL) && (settled != NULL))
    {
        unsigned int order_count = 0u;
        for (unsigned int own = 0u; own < objects; own += 1u)
        {
            for (unsigned int slot = earlier->pool_start[own]; slot < earlier->pool_start[own + 1u]; slot += 1u)
            {
                const unsigned long long strength = (unsigned long long)earlier->pool_weight[slot];
                order[order_count] = (strength << 32u) | (unsigned long long)slot;
                order_count += 1u;
            }
        }
        radix_sort_keys(order, order_count);
        for (unsigned int at = order_count; at > 0u; at -= 1u)
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
            const unsigned int free_pair =
                (unsigned int)((links == 1u) && (settled[own] == 0u) && (taken[candidate] == 0u));
            earlier->link_target[(links == 1u) ? earlier->link_start[own] : 0u] =
                (free_pair != 0u) ? candidate : earlier->link_target[(links == 1u) ? earlier->link_start[own] : 0u];
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
