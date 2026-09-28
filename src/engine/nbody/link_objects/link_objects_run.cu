// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// link_objects_run.cu: link_objects
#include "link_objects_internal.h"

int link_objects(TreeFrame *earlier, const TreeFrame *later, const TreeRules *rules)
{
    unsigned long long *const candidate =
        (unsigned long long *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned long long));
    unsigned long long *const confirmed =
        (unsigned long long *)malloc(((size_t)later->leaf_count + 1u) * sizeof(unsigned long long));
    unsigned int *const incoming = (unsigned int *)calloc((size_t)later->object_count + 1u, sizeof(unsigned int));
    earlier->link_start = (unsigned int *)calloc((size_t)earlier->object_count + 2u, sizeof(unsigned int));
    earlier->link_target = (unsigned int *)malloc(((size_t)earlier->leaf_count + 1u) * sizeof(unsigned int));
    unsigned int *const mutual = (unsigned int *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned int));
    unsigned long long *const weight =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    unsigned long long *const under =
        (unsigned long long *)malloc(((size_t)later->object_count + 1u) * sizeof(unsigned long long));
    if ((candidate == NULL) || (confirmed == NULL) || (incoming == NULL) || (earlier->link_start == NULL) ||
        (earlier->link_target == NULL) || (mutual == NULL) || (weight == NULL) || (under == NULL))
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
            candidate[candidates] = ((unsigned long long)earlier->object_of[leaf] << 32u) |
                                    later->object_of[(unsigned int)earlier->forward[leaf]];
            candidates += 1u;
        }
    }
    candidates = engine_sort_unique(candidate, candidates);
    unsigned int confirmations = 0u;
    for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
    {
        if (later->backward[leaf] >= 0)
        {
            confirmed[confirmations] = ((unsigned long long)later->object_of[leaf] << 32u) |
                                       earlier->object_of[(unsigned int)later->backward[leaf]];
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
                const void *const found =
                    bsearch(&sought, confirmed, confirmations, sizeof(unsigned long long), engine_order_keys);
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
