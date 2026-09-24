// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "bodies.h"

#include "golden_bands.h"
#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int assign_bodies(TreeFrame *frames, unsigned int frame_count, unsigned int by_band)
{
    int good = 1;
    unsigned int widest = 1u;
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        const size_t room = (size_t)tree->leaf_count + 1u;
        tree->body_id = (unsigned int *)malloc(room * sizeof(unsigned int));
        tree->body_parent = (unsigned int *)malloc(room * sizeof(unsigned int));
        tree->body_state = (unsigned int *)calloc(room, sizeof(unsigned int));
        good = (tree->body_id != NULL) && (tree->body_parent != NULL) && (tree->body_state != NULL);
        widest = (tree->leaf_count > widest) ? tree->leaf_count : widest;
    }
    int *const heaviest = (int *)malloc((size_t)widest * sizeof(int));
    unsigned int *const arrivals = (unsigned int *)malloc((size_t)widest * sizeof(unsigned int));
    good = good && (heaviest != NULL) && (arrivals != NULL);
    unsigned int next_id = 0u;
    for (unsigned int body = 0u; good && (frame_count != 0u) && (body < frames[0].leaf_count); body += 1u)
    {
        frames[0].body_id[body] = next_id;
        frames[0].body_parent[body] = BODY_NONE;
        frames[0].body_state[body] = BODY_PRESENT;
        next_id += 1u;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        const int follows = (tree->step_next != 0u) && ((frame + 1u) < frame_count) && (tree->forward != NULL);
        if (follows == 0)
        {
            for (unsigned int body = 0u; body < tree->leaf_count; body += 1u)
            {
                tree->body_state[body] |= BODY_ENDED;
            }
            continue;
        }
        TreeFrame *const later = &frames[frame + 1u];
        for (unsigned int body = 0u; body < later->leaf_count; body += 1u)
        {
            heaviest[body] = -1;
            arrivals[body] = 0u;
        }
        for (unsigned int body = 0u; body < tree->leaf_count; body += 1u)
        {
            const int onto = tree->forward[body];
            if (onto < 0)
            {
                continue;
            }
            const unsigned int target = (unsigned int)onto;
            arrivals[target] += 1u;
            const int held = heaviest[target];
            heaviest[target] = ((held < 0) || (band_or_count(by_band, tree->sizes[body])
                                               > band_or_count(by_band, tree->sizes[(unsigned int)held])))
                             ? (int)body : held;
        }
        for (unsigned int body = 0u; body < later->leaf_count; body += 1u)
        {
            const unsigned int at_face = (later->touches != NULL) ? (unsigned int)(later->touches[body] != 0u) : 0u;
            if (arrivals[body] != 0u)
            {
                later->body_id[body] = tree->body_id[(unsigned int)heaviest[body]];
                later->body_parent[body] = BODY_NONE;
                later->body_state[body] = (arrivals[body] > 1u) ? BODY_MERGED : 0u;
                continue;
            }
            const int source = (later->backward != NULL) ? later->backward[body] : -1;
            const unsigned int split = (unsigned int)((source >= 0) && (tree->forward[(unsigned int)source] >= 0));
            later->body_id[body] = next_id;
            next_id += 1u;
            later->body_parent[body] = (split != 0u) ? tree->body_id[(unsigned int)source] : BODY_NONE;
            later->body_state[body] = (split != 0u) ? BODY_SPLIT : ((at_face != 0u) ? BODY_ENTERED : BODY_APPEARED);
        }
        for (unsigned int body = 0u; body < tree->leaf_count; body += 1u)
        {
            const int onto = tree->forward[body];
            const unsigned int carried = (unsigned int)((onto >= 0) && (heaviest[(unsigned int)(onto * (onto >= 0))]
                                                                        == (int)body));
            const unsigned int at_face = (tree->touches != NULL) ? (unsigned int)(tree->touches[body] != 0u) : 0u;
            const unsigned int ended = (onto >= 0) ? BODY_ABSORBED : ((at_face != 0u) ? BODY_LEFT : BODY_VANISHED);
            tree->body_state[body] |= (carried != 0u) ? 0u : ended;
        }
    }
    free(heaviest);
    free(arrivals);
    return good;
}
