// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "group_objects.h"

#include "golden_bands.h"
#include "track.h"
#include "radix_keys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long long s_cohere_joined = 0ull;

static unsigned long long s_cohere_pairs = 0ull;

int group_objects(TreeFrame *frame, const TreeFrame *previous, const TreeFrame *next,
                         unsigned int height, unsigned int width, const TreeRules *rules)
{
    const unsigned int count = frame->leaf_count;
    unsigned int *const parent = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    free(frame->object_of);
    free(frame->member_start);
    free(frame->members);
    frame->object_of = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    frame->member_start = (unsigned int *)calloc((size_t)count + 2u, sizeof(unsigned int));
    frame->members = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    if ((parent == NULL) || (frame->object_of == NULL) || (frame->member_start == NULL) || (frame->members == NULL))
    {
        free(parent);
        return 0;
    }
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        parent[leaf] = leaf;
    }
    for (unsigned int pair = 0u; pair < frame->joined_count; pair += 1u)
    {
        const unsigned int left = frame->joined[2u * pair];
        const unsigned int right = frame->joined[2u * pair + 1u];
        int same_origin = 0;
        if (frame->backward != NULL)
        {
            const int left_from = frame->backward[left];
            const int right_from = frame->backward[right];
            if ((left_from >= 0) && (right_from >= 0))
            {
                if ((rules->merge_split != 0) && (previous != NULL))
                {
                    same_origin = (previous->object_of[(unsigned int)left_from]
                                   == previous->object_of[(unsigned int)right_from]);
                }
                else
                {
                    same_origin = (left_from == right_from);
                }
            }
        }
        int same_destination = 0;
        int destinations_differ = 0;
        if (frame->forward != NULL)
        {
            same_destination = (frame->forward[left] >= 0) && (frame->forward[left] == frame->forward[right]);
            const int left_to = frame->forward[left];
            const int right_to = frame->forward[right];
            const int apart = ((next != NULL) && (next->object_of != NULL))
                            ? (next->object_of[(unsigned int)((left_to >= 0) ? left_to : 0)]
                               != next->object_of[(unsigned int)((right_to >= 0) ? right_to : 0)])
                            : (left_to != right_to);
            destinations_differ = (left_to >= 0) && (right_to >= 0) && (apart != 0);
        }
        const int origin_holds = (same_origin != 0) && ((rules->agree == 0) || (destinations_differ == 0));
        if ((rules->dish == 0) && ((origin_holds != 0) || (same_destination != 0)))
        {
            const unsigned int first = engine_find_root(parent, left);
            const unsigned int second = engine_find_root(parent, right);
            if (first != second)
            {
                parent[second] = first;
            }
        }
    }
    if (rules->dish != 0)
    {
        const unsigned int measured = (unsigned int)((frame->null_held != NULL) && (frame->null_count != 0u)
                                                     && (frame->forward_held != NULL));
        unsigned int centre = 0u;
        unsigned long long substance = 0ull;
        for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
        {
            substance += (unsigned long long)frame->sizes[leaf];
        }
        unsigned long long per_band[DAMP_BANDS];
        memset(per_band, 0, sizeof(per_band));
        for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
        {
            per_band[band_of(frame->sizes[leaf])] += (unsigned long long)frame->sizes[leaf];
        }
        unsigned long long running = 0ull;
        for (unsigned int band = 0u; band < DAMP_BANDS; band += 1u)
        {
            running += per_band[band];
            if ((running * 2ull) >= substance)
            {
                centre = (unsigned int)band_floor(band);
                break;
            }
        }
        unsigned char *const stands = (unsigned char *)malloc((size_t)count + 1u);
        unsigned int *const leans_on = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        if ((stands == NULL) || (leans_on == NULL))
        {
            free(stands);
            free(leans_on);
            free(parent);
            return 0;
        }
        for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
        {
            unsigned int reached = 0u;
            for (unsigned int draw = 0u; (measured != 0u) && (draw < frame->null_count); draw += 1u)
            {
                const unsigned int drawn = frame->null_held[((size_t)draw * ((size_t)count + 1u)) + leaf];
                reached += (unsigned int)(drawn >= frame->forward_held[leaf]);
            }
            stands[leaf] = (unsigned char)((measured != 0u) ? (reached == 0u)
                                                            : (frame->sizes[leaf] >= centre));
            leans_on[leaf] = leaf;
        }
        for (unsigned int pass = 0u; pass < 2u; pass += 1u)
        {
            for (unsigned int pair = 0u; pair < frame->joined_count; pair += 1u)
            {
                const unsigned int left = frame->joined[2u * pair];
                const unsigned int right = frame->joined[2u * pair + 1u];
                const unsigned int left_eligible = (unsigned int)((pass != 0u) || (stands[left] != 0u));
                const unsigned int right_eligible = (unsigned int)((pass != 0u) || (stands[right] != 0u));
                const unsigned int left_settled = (unsigned int)((pass != 0u) && (leans_on[right] != right));
                const unsigned int right_settled = (unsigned int)((pass != 0u) && (leans_on[left] != left));
                const unsigned int by_band = (unsigned int)rules->mass_band;
                const int left_bigger = (left_eligible != 0u) && (left_settled == 0u)
                                     && (band_or_count(by_band, frame->sizes[left])
                                         > band_or_count(by_band, frame->sizes[leans_on[right]]));
                const int right_bigger = (right_eligible != 0u) && (right_settled == 0u)
                                      && (band_or_count(by_band, frame->sizes[right])
                                          > band_or_count(by_band, frame->sizes[leans_on[left]]));
                leans_on[right] = (left_bigger != 0) ? left : leans_on[right];
                leans_on[left] = (right_bigger != 0) ? right : leans_on[left];
            }
        }
        for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
        {
            const unsigned int leans = (unsigned int)((stands[leaf] == 0u) && (leans_on[leaf] != leaf)
                                                      && (band_or_count((unsigned int)rules->mass_band,
                                                                        frame->sizes[leans_on[leaf]])
                                                          > band_or_count((unsigned int)rules->mass_band,
                                                                          frame->sizes[leaf])));
            parent[leaf] = (leans != 0u) ? leans_on[leaf] : leaf;
        }
        free(stands);
        free(leans_on);
    }
    if (((rules->cohere != 0) || (rules->accrue != 0)) && (frame->forward_lag != NULL)
     && (frame->joined_count != 0u))
    {
        const unsigned int gathered = (unsigned int)((rules->accrue != 0) && (frame->backward_lag != NULL));
        unsigned long long *const apart = (unsigned long long *)malloc(((size_t)frame->joined_count + 1u)
                                                                        * sizeof(unsigned long long));
        if (apart == NULL)
        {
            free(parent);
            return 0;
        }
        const unsigned long long plane = (unsigned long long)height * width;
        for (unsigned int pair = 0u; pair < frame->joined_count; pair += 1u)
        {
            const unsigned int left = frame->joined[2u * pair];
            const unsigned int right = frame->joined[2u * pair + 1u];
            const int went_left = (frame->forward != NULL) ? frame->forward[left] : -1;
            const int went_right = (frame->forward != NULL) ? frame->forward[right] : -1;
            if ((went_left < 0) || (went_right < 0) || (next == NULL) || (next->peaks == NULL))
            {
                apart[pair] = 0xFFFFFFFFull;
                continue;
            }
            const unsigned long long here_left = (unsigned long long)frame->peaks[left];
            const unsigned long long here_right = (unsigned long long)frame->peaks[right];
            const unsigned long long there_left = (unsigned long long)next->peaks[(unsigned int)went_left];
            const unsigned long long there_right = (unsigned long long)next->peaks[(unsigned int)went_right];
            const long long step[3] = {
                ((long long)(there_left / plane) - (long long)(here_left / plane))
                - ((long long)(there_right / plane) - (long long)(here_right / plane)),
                ((long long)((there_left % plane) / width) - (long long)((here_left % plane) / width))
                - ((long long)((there_right % plane) / width) - (long long)((here_right % plane) / width)),
                ((long long)((there_left % plane) % width) - (long long)((here_left % plane) % width))
                - ((long long)((there_right % plane) % width) - (long long)((here_right % plane) % width)),
            };
            unsigned long long between = 0ull;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                between += (unsigned long long)(step[axis] * step[axis])
                         * (unsigned long long)AXIS_WEIGHTS[axis];
            }
            for (unsigned int axis = 0u; (gathered != 0u) && (axis < 3u); axis += 1u)
            {
                const long long back = (long long)frame->backward_lag[(3u * left) + axis]
                                     - (long long)frame->backward_lag[(3u * right) + axis];
                between += (unsigned long long)(back * back) * (unsigned long long)AXIS_WEIGHTS[axis];
            }
            apart[pair] = between;
        }
        unsigned long long *const order = (unsigned long long *)malloc(((size_t)frame->joined_count + 1u)
                                                                        * sizeof(unsigned long long));
        unsigned long long *const absorbed = (unsigned long long *)calloc((size_t)count + 1u,
                                                                           sizeof(unsigned long long));
        if ((order == NULL) || (absorbed == NULL))
        {
            free(apart);
            free(order);
            free(absorbed);
            free(parent);
            return 0;
        }
        for (unsigned int pair = 0u; pair < frame->joined_count; pair += 1u)
        {
            const unsigned long long held = (apart[pair] > 0xFFFFFFFFull) ? 0xFFFFFFFFull : apart[pair];
            order[pair] = (held << 32u) | (unsigned long long)pair;
        }
        radix_sort_keys(order, frame->joined_count);
        long long *const motion = (long long *)calloc(((size_t)count + 1u) * 3u, sizeof(long long));
        unsigned long long *const mass = (unsigned long long *)calloc((size_t)count + 1u,
                                                                       sizeof(unsigned long long));
        if ((motion == NULL) || (mass == NULL))
        {
            free(apart);
            free(order);
            free(absorbed);
            free(motion);
            free(mass);
            free(parent);
            return 0;
        }
        for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
        {
            mass[leaf] = (unsigned long long)frame->sizes[leaf];
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                motion[(3u * leaf) + axis] = (long long)frame->forward_lag[(3u * leaf) + axis]
                                           * (long long)frame->sizes[leaf];
            }
        }
        for (unsigned int at = 0u; at < frame->joined_count; at += 1u)
        {
            const unsigned int pair = (unsigned int)(order[at] & 0xFFFFFFFFull);
            const unsigned int first = engine_find_root(parent, frame->joined[2u * pair]);
            const unsigned int second = engine_find_root(parent, frame->joined[2u * pair + 1u]);
            if (first == second)
            {
                continue;
            }
            unsigned long long between = 0ull;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                const long long step = (motion[(3u * first) + axis] * (long long)mass[second])
                                     - (motion[(3u * second) + axis] * (long long)mass[first]);
                const unsigned long long scale = mass[first] * mass[second];
                const long long mean = (scale != 0ull) ? (step / (long long)scale) : 0ll;
                between += (unsigned long long)(mean * mean) * (unsigned long long)AXIS_WEIGHTS[axis];
            }
            const unsigned long long history = (absorbed[first] > absorbed[second]) ? absorbed[first]
                                                                                     : absorbed[second];
            const unsigned int fresh = (unsigned int)(history == 0ull);
            const unsigned int near = (unsigned int)(band_of(between) <= (band_of(history) + 1u));
            const unsigned int joins = (unsigned int)((fresh != 0u) || (near != 0u));
            absorbed[first] = ((joins != 0u) && (fresh != 0u)) ? ((between != 0ull) ? between : 1ull)
                                                              : absorbed[first];
            for (unsigned int axis = 0u; (joins != 0u) && (axis < 3u); axis += 1u)
            {
                motion[(3u * first) + axis] += motion[(3u * second) + axis];
            }
            mass[first] += (joins != 0u) ? mass[second] : 0ull;
            parent[second] = (joins != 0u) ? first : parent[second];
            s_cohere_joined += (unsigned long long)(joins != 0u);
        }
        free(motion);
        free(mass);
        s_cohere_pairs += (unsigned long long)frame->joined_count;
        free(apart);
        free(order);
        free(absorbed);
    }
    unsigned int *const number_of_root = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    if (number_of_root == NULL)
    {
        free(parent);
        return 0;
    }
    unsigned int objects = 0u;
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        if (engine_find_root(parent, leaf) == leaf)
        {
            number_of_root[leaf] = objects;
            objects += 1u;
        }
    }
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        frame->object_of[leaf] = number_of_root[engine_find_root(parent, leaf)];
        frame->member_start[frame->object_of[leaf] + 1u] += 1u;
    }
    for (unsigned int object = 0u; object < objects; object += 1u)
    {
        frame->member_start[object + 1u] += frame->member_start[object];
    }
    unsigned int *const fill = (unsigned int *)malloc(((size_t)objects + 1u) * sizeof(unsigned int));
    if (fill == NULL)
    {
        free(parent);
        free(number_of_root);
        return 0;
    }
    memcpy(fill, frame->member_start, (size_t)objects * sizeof(unsigned int));
    for (unsigned int leaf = 0u; leaf < count; leaf += 1u)
    {
        frame->members[fill[frame->object_of[leaf]]] = leaf;
        fill[frame->object_of[leaf]] += 1u;
    }
    frame->object_count = objects;
    free(fill);
    free(number_of_root);
    free(parent);
    return 1;
}
