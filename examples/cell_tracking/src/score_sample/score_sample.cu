// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "score_sample.h"

#include "answer_key.h"
#include "bodies.h"
#include "coherence.h"
#include "group_objects.h"
#include "link_objects.h"
#include "relate_frames.h"
#include "run_log.h"
#include "track.h"
#include "climb_machine.h"
#include "cycle.h"
#include "engine.h"
#include "heaviest_matching.h"
#include "golden_bands.h"
#include "max_tree.h"
#include "velocity.h"
#include "division.h"
#include "marginal.h"
#include "contact_side.h"
#include "box_history.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOWER_ROUNDS 64u

static int score_flattened_slice(const char *sample, const TreeFrame *frames, unsigned int frame_count,
                                 const TreeRules *rules, unsigned long long *first, unsigned long long *bodies)
{
    unsigned int held = rules->flattened_samples;
    for (unsigned int named = 0u; named < rules->flattened_samples; named += 1u)
    {
        held = ((held == rules->flattened_samples) && (strcmp(rules->flattened_names[named], sample) == 0)) ? named
                                                                                                          : held;
    }
    if (held == rules->flattened_samples)
    {
        fprintf(stderr, "  %s: not among the samples the set's .ksh holds; flatten it first\n", sample);
        return 0;
    }
    *first = rules->flattened_start[held];
    *bodies = rules->flattened_start[held + 1u] - *first;
    unsigned long long leaves = 0ull;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        leaves += (unsigned long long)frames[frame].leaf_count;
    }
    if ((leaves != *bodies) || (*bodies > 0xFFFFFFFFull))
    {
        fprintf(stderr, "  %s: the tracker holds %llu bodies and the set's .ksh %llu; flatten it again\n", sample,
                leaves, *bodies);
        return 0;
    }
    return 1;
}

static int score_print_match(const char *sample, TreeFrame *frames, unsigned int frame_count, const TreeRules *rules)
{
    unsigned long long first = 0ull;
    unsigned long long bodies = 0ull;
    if (score_flattened_slice(sample, frames, frame_count, rules, &first, &bodies) == 0)
    {
        return 0;
    }
    unsigned long long room = 0ull;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        room += (frames[frame].forward != NULL)
              ? ((unsigned long long)frames[frame].leaf_count
                 + ((frames[frame].triple_start != NULL) ? (unsigned long long)frames[frame].triple_count : 0ull))
              : 0ull;
    }
    if (room > 0x3FFFFFFFull)
    {
        fprintf(stderr, "  %s: %llu candidate pairs are more than one sweep's index holds\n", sample, room);
        return 0;
    }
    unsigned int *const frame_first = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    unsigned int *const pair_start = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    unsigned int *const index = (unsigned int *)malloc(((size_t)room + 1u) * 2u * sizeof(unsigned int));
    unsigned int *const before = (unsigned int *)malloc(((size_t)room + 1u) * sizeof(unsigned int));
    unsigned int *const after = (unsigned int *)malloc(((size_t)room + 1u) * sizeof(unsigned int));
    unsigned int *const weight = (unsigned int *)malloc(((size_t)room + 1u) * sizeof(unsigned int));
    unsigned char *const chosen = (unsigned char *)malloc((size_t)room + 1u);
    int good = (frame_first != NULL) && (pair_start != NULL) && (index != NULL) && (before != NULL) && (after != NULL)
            && (weight != NULL) && (chosen != NULL);
    unsigned int made = 0u;
    if (good)
    {
        frame_first[0] = 0u;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        frame_first[frame + 1u] = frame_first[frame] + frames[frame].leaf_count;
        pair_start[frame] = made;
        const TreeFrame *const tree = &frames[frame];
        for (unsigned int leaf = 0u; (tree->forward != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            const unsigned int leaf_first = made;
            const unsigned int triples_first = (tree->triple_start != NULL) ? tree->triple_start[leaf] : 0u;
            const unsigned int triples_past = (tree->triple_start != NULL) ? tree->triple_start[leaf + 1u] : 0u;
            for (unsigned int triple = triples_first; triple <= triples_past; triple += 1u)
            {
                const int other = (triple < triples_past) ? (int)tree->triple_after[triple] : tree->forward[leaf];
                int fresh = (other >= 0) ? 1 : 0;
                for (unsigned int seen = leaf_first; fresh && (seen < made); seen += 1u)
                {
                    fresh = (after[seen] != (unsigned int)other) ? 1 : 0;
                }
                if (fresh != 0)
                {
                    before[made] = leaf;
                    after[made] = (unsigned int)other;
                    index[2u * made] = frame_first[frame] + leaf;
                    index[(2u * made) + 1u] = frame_first[frame + 1u] + (unsigned int)other;
                    made += 1u;
                }
            }
        }
    }
    pair_start[frame_count] = made;
    unsigned long long sweep = 0ull;
    const unsigned int *const sample_prints = &rules->prints[first * rules->print_limbs];
    EngineError error;
    memset(&error, 0, sizeof(error));
    const EngineRecordSweep run = {rules->print_pair, {sample_prints, sample_prints}, {bodies, bodies}, index,
                                   made,              weight,                         &sweep,           &error};
    good = good && ((made == 0u) || (engine_record_sweep(&run) == (long)made));
    if (error.kind != ENGINE_ERROR_NONE)
    {
        track_error_report("print match sweep", &error);
    }
    unsigned int matched = 0u;
    unsigned int changed = 0u;
    unsigned int asked = 0u;
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        const unsigned int start = pair_start[frame];
        const unsigned int count = pair_start[frame + 1u] - start;
        if (tree->forward == NULL)
        {
            continue;
        }
        const HeaviestMatchingRequest match = {&before[start], &after[start], &weight[start], count,
                                               tree->leaf_count, frames[frame + 1u].leaf_count, &chosen[start]};
        good = (count == 0u) || (heaviest_matching_run(&match) >= 0L);
        unsigned int cursor = start;
        for (unsigned int leaf = 0u; good && (leaf < tree->leaf_count); leaf += 1u)
        {
            int landed = -1;
            while ((cursor < pair_start[frame + 1u]) && (before[cursor] == leaf))
            {
                landed = (chosen[cursor] != 0u) ? (int)after[cursor] : landed;
                cursor += 1u;
            }
            matched += (landed >= 0) ? 1u : 0u;
            changed += (landed != tree->forward[leaf]) ? 1u : 0u;
            tree->forward[leaf] = landed;
        }
        asked += tree->leaf_count;
    }
    if (good)
    {
        printf("  %s: the print match swept %u pairs at once in %llu us; %u of %u leaves matched one to one, %u "
               "forwards changed\n", sample, made, sweep, matched, asked, changed);
    }
    else
    {
        fprintf(stderr, "  %s: the print match was refused\n", sample);
    }
    free(frame_first);
    free(pair_start);
    free(index);
    free(before);
    free(after);
    free(weight);
    free(chosen);
    return good;
}

static int score_field_truthy(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned int held = 0u;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int at = offset + bit;
        held |= (record[at / 32u] >> (at % 32u)) & 1u;
    }
    return (held != 0u) ? 1 : 0;
}

static int score_velocity_sweep(const char *sample, const char *pass, const TreeRules *rules,
                                const unsigned int *magnitudes, unsigned long long bodies, const unsigned int *lags,
                                const unsigned int *index, unsigned int lanes)
{
    const unsigned int out_limbs = cycle_record_out_limbs(rules->velocity_record);
    const size_t words = (size_t)lanes * out_limbs;
    unsigned int *const device = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    unsigned int *const host = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    unsigned long long sweep = 0ull;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const EngineRecordSweep run = {rules->velocity_record, {magnitudes, magnitudes, lags}, {bodies, bodies, bodies},
                                   index,                  lanes,                         device,
                                   &sweep,                 &error};
    const EngineRecordSweep host_run = {NULL,  {magnitudes, magnitudes, lags}, {bodies, bodies, bodies},
                                        index, lanes,                         host,
                                        NULL,  &error};
    const int good = (device != NULL) && (host != NULL)
                  && ((lanes == 0u) || ((engine_record_sweep(&run) == (long)lanes)
                                        && (engine_record_host(rules->velocity_imprint, &host_run) == (long)lanes)));
    if (error.kind != ENGINE_ERROR_NONE)
    {
        track_error_report("velocity sweep", &error);
    }
    const unsigned int *const offset = rules->velocity_imprint->output_offset;
    const unsigned int *const bits = rules->velocity_imprint->output_bits;
    unsigned int agree[ENGINE_AXES + 1u] = {0u, 0u, 0u, 0u};
    unsigned int differ = 0u;
    for (unsigned int lane = 0u; good && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device[(size_t)lane * out_limbs];
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            agree[axis] += (unsigned int)score_field_truthy(record, offset[VELOCITY_AGREES + axis],
                                                            bits[VELOCITY_AGREES + axis]);
        }
        agree[ENGINE_AXES] += (unsigned int)score_field_truthy(record, offset[VELOCITY_ALL_AGREE],
                                                               bits[VELOCITY_ALL_AGREE]);
        differ += (memcmp(record, &host[(size_t)lane * out_limbs], out_limbs * sizeof(unsigned int)) != 0) ? 1u : 0u;
    }
    if (good)
    {
        printf("  %s: velocity %s, %u lanes in %llu us: the climbed lag stands beside the dipole's change on %u (z %u,"
               " y %u, x %u); %u differ from the host\n", sample, pass, lanes, sweep, agree[ENGINE_AXES], agree[0],
               agree[1], agree[2], differ);
    }
    else
    {
        fprintf(stderr, "  %s: the velocity %s was refused\n", sample, pass);
    }
    free(device);
    free(host);
    return (good && (differ == 0u)) ? 1 : 0;
}

static int score_velocity(const char *sample, const TreeFrame *frames, unsigned int frame_count, const TreeRules *rules)
{
    unsigned long long first = 0ull;
    unsigned long long bodies = 0ull;
    if (score_flattened_slice(sample, frames, frame_count, rules, &first, &bodies) == 0)
    {
        return 0;
    }
    unsigned int *const frame_first = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    unsigned int *const lags = (unsigned int *)malloc(((size_t)bodies * ENGINE_AXES + 1u) * sizeof(unsigned int));
    unsigned int *const checked = (unsigned int *)malloc(((size_t)bodies * VELOCITY_MEMBERS + 1u)
                                                         * sizeof(unsigned int));
    unsigned int *const predicted = (unsigned int *)malloc(((size_t)bodies * VELOCITY_MEMBERS + 1u)
                                                           * sizeof(unsigned int));
    int good = (frame_first != NULL) && (lags != NULL) && (checked != NULL) && (predicted != NULL);
    unsigned int checks = 0u;
    unsigned int predictions = 0u;
    if (good)
    {
        frame_first[0] = 0u;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        frame_first[frame + 1u] = frame_first[frame] + frames[frame].leaf_count;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
        {
            const unsigned int body = frame_first[frame] + leaf;
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                lags[(ENGINE_AXES * body) + axis] = (tree->forward_lag != NULL)
                                                  ? (unsigned int)tree->forward_lag[(ENGINE_AXES * leaf) + axis] : 0u;
            }
            if ((tree->forward_lag != NULL) && (tree->forward != NULL) && (tree->forward[leaf] >= 0))
            {
                checked[VELOCITY_MEMBERS * checks] = body;
                checked[(VELOCITY_MEMBERS * checks) + 1u] = frame_first[frame + 1u] + (unsigned int)tree->forward[leaf];
                checked[(VELOCITY_MEMBERS * checks) + 2u] = body;
                checks += 1u;
            }
            if ((tree->forward_lag != NULL) && (tree->backward != NULL) && (tree->backward[leaf] >= 0))
            {
                predicted[VELOCITY_MEMBERS * predictions] = frame_first[frame - 1u] + (unsigned int)tree->backward[leaf];
                predicted[(VELOCITY_MEMBERS * predictions) + 1u] = body;
                predicted[(VELOCITY_MEMBERS * predictions) + 2u] = body;
                predictions += 1u;
            }
        }
    }
    const unsigned int *const magnitudes = &rules->flattened[first * rules->flattened_limbs];
    good = good && (score_velocity_sweep(sample, "check, each body and its climbed forward", rules, magnitudes, bodies,
                                         lags, checked, checks) != 0);
    good = good && (score_velocity_sweep(sample, "prediction, each body's last change against its next climb", rules,
                                         magnitudes, bodies, lags, predicted, predictions) != 0);
    free(frame_first);
    free(lags);
    free(checked);
    free(predicted);
    return good;
}

static unsigned long long score_division_room(const TreeFrame *frames, unsigned int frame_count, unsigned int **start)
{
    unsigned long long room = 0ull;
    for (unsigned int frame = 1u; frame < frame_count; frame += 1u)
    {
        const TreeFrame *const later = &frames[frame];
        const unsigned int parents = frames[frame - 1u].leaf_count;
        start[frame] = (later->backward != NULL) ? (unsigned int *)calloc((size_t)parents + 2u, sizeof(unsigned int))
                                                 : NULL;
        for (unsigned int leaf = 0u; (start[frame] != NULL) && (leaf < later->leaf_count); leaf += 1u)
        {
            const int parent = later->backward[leaf];
            start[frame][(parent >= 0) ? ((unsigned int)parent + 1u) : (parents + 1u)] += (parent >= 0) ? 1u : 0u;
        }
        for (unsigned int parent = 0u; (start[frame] != NULL) && (parent < parents); parent += 1u)
        {
            const unsigned long long children = (unsigned long long)start[frame][parent + 1u];
            room += (children * (children - ((children != 0ull) ? 1ull : 0ull))) / 2ull;
            start[frame][parent + 1u] += start[frame][parent];
        }
    }
    return room;
}

static unsigned int *score_key_successors(const AnswerKey *key)
{
    // node_count widens from unsigned int to size_t, so node_count + 1 cannot wrap before calloc sees it
    unsigned int *const successors = (unsigned int *)calloc((size_t)key->node_count + 1u, 3u * sizeof(unsigned int));
    for (unsigned int edge = 0u; (successors != NULL) && (edge < key->edge_count); edge += 1u)
    {
        const long source = node_slot_of(key, key->edge_ends[2u * edge]);
        const long target = node_slot_of(key, key->edge_ends[(2u * edge) + 1u]);
        if ((source >= 0L) && (target >= 0L))
        {
            unsigned int *const node_successors = &successors[3L * source];
            // target is a node slot, non-negative and below node_count, so it narrows from long to unsigned int exactly
            node_successors[(node_successors[0] < 2u) ? (node_successors[0] + 1u) : 0u]
                = (node_successors[0] < 2u) ? (unsigned int)target : node_successors[0];
            node_successors[0] += 1u;
        }
    }
    return successors;
}

static int score_division(const char *sample, const TreeFrame *frames, unsigned int frame_count, const TreeRules *rules,
                          const AnswerKey *key, const int *node_leaf, const int *tree_index_of_time,
                          unsigned int volume_frames)
{
    unsigned long long first = 0ull;
    unsigned long long bodies = 0ull;
    if (score_flattened_slice(sample, frames, frame_count, rules, &first, &bodies) == 0)
    {
        return 0;
    }
    unsigned int *const frame_first = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    unsigned int **const start = (unsigned int **)calloc((size_t)frame_count + 1u, sizeof(unsigned int *));
    int good = (frame_first != NULL) && (start != NULL);
    const unsigned long long room = good ? score_division_room(frames, frame_count, start) : 0ull;
    if (good && (room > 0x3FFFFFFFull))
    {
        fprintf(stderr, "  %s: %llu division triples are more than one sweep's index holds\n", sample, room);
        good = 0;
    }
    unsigned int *const index = good ? (unsigned int *)malloc(((size_t)room * DIVISION_MEMBERS + 1u)
                                                              * sizeof(unsigned int)) : NULL;
    unsigned int *const children = good ? (unsigned int *)malloc(((size_t)bodies + 1u) * sizeof(unsigned int)) : NULL;
    good = good && (index != NULL) && (children != NULL);
    if (good)
    {
        frame_first[0] = 0u;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        frame_first[frame + 1u] = frame_first[frame] + frames[frame].leaf_count;
    }
    unsigned int lanes = 0u;
    for (unsigned int frame = 1u; good && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const later = &frames[frame];
        const unsigned int parents = frames[frame - 1u].leaf_count;
        unsigned int *const cursor = start[frame];
        if (cursor == NULL)
        {
            continue;
        }
        for (unsigned int leaf = 0u; leaf < later->leaf_count; leaf += 1u)
        {
            const int parent = later->backward[leaf];
            if (parent >= 0)
            {
                children[cursor[parent]] = leaf;
                cursor[parent] += 1u;
            }
        }
        unsigned int from = 0u;
        for (unsigned int parent = 0u; parent < parents; parent += 1u)
        {
            const unsigned int past = cursor[parent];
            for (unsigned int one = from; one < past; one += 1u)
            {
                for (unsigned int other = one + 1u; other < past; other += 1u)
                {
                    index[DIVISION_MEMBERS * lanes] = frame_first[frame - 1u] + parent;
                    index[(DIVISION_MEMBERS * lanes) + 1u] = frame_first[frame] + children[one];
                    index[(DIVISION_MEMBERS * lanes) + 2u] = frame_first[frame] + children[other];
                    lanes += 1u;
                }
            }
            from = past;
        }
    }
    const unsigned int *const magnitudes = &rules->flattened[first * rules->flattened_limbs];
    const unsigned int out_limbs = cycle_record_out_limbs(rules->division_record);
    const size_t words = (size_t)lanes * out_limbs;
    unsigned int *const device = good ? (unsigned int *)malloc((words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const host = good ? (unsigned int *)malloc((words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned long long sweep = 0ull;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const EngineRecordSweep run = {rules->division_record, {magnitudes, magnitudes, magnitudes}, {bodies, bodies, bodies},
                                   index,                  lanes,                               device,
                                   &sweep,                 &error};
    const EngineRecordSweep host_run = {NULL,  {magnitudes, magnitudes, magnitudes}, {bodies, bodies, bodies},
                                        index, lanes,                               host,
                                        NULL,  &error};
    good = good && (device != NULL) && (host != NULL)
        && ((lanes == 0u) || ((engine_record_sweep(&run) == (long)lanes)
                              && (engine_record_host(rules->division_imprint, &host_run) == (long)lanes)));
    if (error.kind != ENGINE_ERROR_NONE)
    {
        track_error_report("division sweep", &error);
    }
    const unsigned int *const offset = rules->division_imprint->output_offset;
    const unsigned int *const bits = rules->division_imprint->output_bits;
    unsigned int holds[DIVISION_OUTPUTS] = {0u, 0u, 0u};
    unsigned int differ = 0u;
    for (unsigned int lane = 0u; good && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device[(size_t)lane * out_limbs];
        for (unsigned int output = 0u; output < DIVISION_OUTPUTS; output += 1u)
        {
            holds[output] += (unsigned int)score_field_truthy(record, offset[output], bits[output]);
        }
        differ += (memcmp(record, &host[(size_t)lane * out_limbs], out_limbs * sizeof(unsigned int)) != 0) ? 1u : 0u;
    }
    unsigned int *const successors = good ? score_key_successors(key) : NULL;
    good = good && (successors != NULL);
    unsigned int truths = 0u;
    unsigned int resolved = 0u;
    unsigned int among = 0u;
    unsigned int truth_holds[DIVISION_OUTPUTS] = {0u, 0u, 0u};
    unsigned int lost_time = 0u;
    unsigned int lost_off_leaf = 0u;
    unsigned int lost_one_leaf = 0u;
    unsigned int back_to_parent = 0u;
    for (unsigned int node = 0u; good && (node < key->node_count); node += 1u)
    {
        const unsigned int *const held = &successors[3u * node];
        if (held[0] != 2u)
        {
            continue;
        }
        truths += 1u;
        const int time = key->node_coordinates[(size_t)node * 4u];
        const int child_time = key->node_coordinates[(size_t)held[1] * 4u];
        const int sibling_time = key->node_coordinates[(size_t)held[2] * 4u];
        const int parent_leaf = node_leaf[node];
        const int child_leaf = node_leaf[held[1]];
        const int sibling_leaf = node_leaf[held[2]];
        const int timed = (time >= 0) && ((unsigned int)time + 1u < volume_frames) && (child_time == time + 1)
                       && (sibling_time == time + 1) && (tree_index_of_time[time] >= 0);
        lost_time += (timed == 0) ? 1u : 0u;
        lost_off_leaf += ((timed != 0) && ((parent_leaf < 0) || (child_leaf < 0) || (sibling_leaf < 0))) ? 1u : 0u;
        lost_one_leaf += ((timed != 0) && (parent_leaf >= 0) && (child_leaf >= 0) && (child_leaf == sibling_leaf))
                       ? 1u : 0u;
        if ((timed != 0) && (parent_leaf >= 0) && (child_leaf >= 0) && (sibling_leaf >= 0) && (child_leaf != sibling_leaf))
        {
            const TreeFrame *const later = &frames[(unsigned int)tree_index_of_time[time] + 1u];
            const int child_back = (later->backward != NULL) ? later->backward[child_leaf] : -1;
            const int sibling_back = (later->backward != NULL) ? later->backward[sibling_leaf] : -1;
            back_to_parent += (unsigned int)(child_back == parent_leaf) + (unsigned int)(sibling_back == parent_leaf);
        }
        if ((time < 0) || ((unsigned int)time + 1u >= volume_frames) || (child_time != time + 1)
         || (sibling_time != time + 1) || (parent_leaf < 0) || (child_leaf < 0) || (sibling_leaf < 0)
         || (child_leaf == sibling_leaf) || (tree_index_of_time[time] < 0))
        {
            continue;
        }
        resolved += 1u;
        const unsigned int frame = (unsigned int)tree_index_of_time[time];
        const unsigned int parent_body = frame_first[frame] + (unsigned int)parent_leaf;
        const unsigned int child_body = frame_first[frame + 1u] + (unsigned int)child_leaf;
        const unsigned int sibling_body = frame_first[frame + 1u] + (unsigned int)sibling_leaf;
        for (unsigned int lane = 0u; lane < lanes; lane += 1u)
        {
            const unsigned int *const triple = &index[DIVISION_MEMBERS * lane];
            const int same = (triple[0] == parent_body)
                          && (((triple[1] == child_body) && (triple[2] == sibling_body))
                              || ((triple[1] == sibling_body) && (triple[2] == child_body)));
            if (same)
            {
                among += 1u;
                for (unsigned int output = 0u; output < DIVISION_OUTPUTS; output += 1u)
                {
                    truth_holds[output] += (unsigned int)score_field_truthy(&device[(size_t)lane * out_limbs],
                                                                           offset[output], bits[output]);
                }
            }
        }
    }
    if (good)
    {
        printf("  %s: division, %u triples (a parent and two pieces whose climbs land back on it) in %llu us: mass"
               " conserved on %u, split along the parent's long axis on %u, both on %u; %u differ from the host\n",
               sample, lanes, sweep, holds[DIVISION_MASS_HOLDS], holds[DIVISION_AXIS_HOLDS],
               holds[DIVISION_BOTH_HOLD], differ);
        printf("  %s: the key holds %u divisions, %u on three separate leaves, %u among the triples: mass on %u, axis"
               " on %u, both on %u\n", sample, truths, resolved, among, truth_holds[DIVISION_MASS_HOLDS],
               truth_holds[DIVISION_AXIS_HOLDS], truth_holds[DIVISION_BOTH_HOLD]);
        printf("  %s: of the key's divisions, %u fall outside consecutive tracked frames, %u have a node on no leaf,"
               " %u have both children on one leaf; on three separate leaves, %u of the %u children climb back to"
               " their parent\n", sample, lost_time, lost_off_leaf, lost_one_leaf, back_to_parent, 2u * resolved);
    }
    else
    {
        fprintf(stderr, "  %s: the division sweep was refused\n", sample);
    }
    for (unsigned int frame = 0u; (start != NULL) && (frame < frame_count); frame += 1u)
    {
        free(start[frame]);
    }
    free(start);
    free(frame_first);
    free(index);
    free(children);
    free(device);
    free(host);
    free(successors);
    return (good && (differ == 0u)) ? 1 : 0;
}

static int score_limbs_order(const unsigned int *left, const unsigned int *right)
{
    for (unsigned int limb = MARGINAL_LIMBS; limb > 0u; limb -= 1u)
    {
        if (left[limb - 1u] != right[limb - 1u])
        {
            return (left[limb - 1u] < right[limb - 1u]) ? -1 : 1;
        }
    }
    return 0;
}

typedef struct
{
    MarginalQuestion *questions;
    MarginalSource *sources;
    MarginalOption *options;
    unsigned int question_count;
    unsigned int source_count;
    unsigned int option_count;
    size_t source_room;
    size_t option_room;
    unsigned int *asked_leaf;
    unsigned int *asked_frame;
} ScoreMarginalSet;

static int score_marginal_room(ScoreMarginalSet *set, size_t sources, size_t options)
{
    if ((set->source_count + sources) > set->source_room)
    {
        const size_t room = (set->source_count + sources) * 2u;
        MarginalSource *const grown = (MarginalSource *)realloc(set->sources, room * sizeof(MarginalSource));
        set->sources = (grown != NULL) ? grown : set->sources;
        set->source_room = (grown != NULL) ? room : set->source_room;
        if (grown == NULL)
        {
            return 0;
        }
    }
    if ((set->option_count + options) > set->option_room)
    {
        const size_t room = (set->option_count + options) * 2u;
        MarginalOption *const grown = (MarginalOption *)realloc(set->options, room * sizeof(MarginalOption));
        set->options = (grown != NULL) ? grown : set->options;
        set->option_room = (grown != NULL) ? room : set->option_room;
        if (grown == NULL)
        {
            return 0;
        }
    }
    return 1;
}

static unsigned int score_best_null(const TreeFrame *tree, unsigned int leaf)
{
    unsigned int best = 0u;
    for (unsigned int draw = 0u; draw < tree->null_count; draw += 1u)
    {
        const unsigned int drawn = tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u)) + leaf];
        best = (drawn > best) ? drawn : best;
    }
    return best;
}

typedef struct
{
    const unsigned int *start;
    const unsigned int *target;
    const unsigned int *weight;
    unsigned int count;
} ScoreChoices;

static ScoreChoices score_choices_of(const TreeFrame *frames, const ScoreChoices *stars, unsigned int frame)
{
    const TreeFrame *const tree = &frames[frame];
    const ScoreChoices triples = {tree->triple_start, tree->triple_after, tree->triple_shared, tree->triple_count};
    return ((stars != NULL) && (stars[frame].start != NULL)) ? stars[frame] : triples;
}

static int score_marginal_ask(ScoreMarginalSet *set, const TreeFrame *tree, const ScoreChoices *choices,
                              const unsigned int *target_start, const unsigned int *target_sources, unsigned int leaf,
                              int alone)
{
    unsigned int local_leaf[MARGINAL_SOURCES_MOST];
    unsigned int local_target[MARGINAL_TARGETS_MOST];
    unsigned int leaves = 1u;
    unsigned int targets = 0u;
    local_leaf[0] = leaf;
    for (unsigned int triple = choices->start[leaf]; (alone == 0) && (triple < choices->start[leaf + 1u]);
         triple += 1u)
    {
        const unsigned int target = choices->target[triple];
        for (unsigned int at = target_start[target]; at < target_start[target + 1u]; at += 1u)
        {
            const unsigned int other = target_sources[at];
            int fresh = 1;
            for (unsigned int seen = 0u; seen < leaves; seen += 1u)
            {
                fresh = fresh && (local_leaf[seen] != other);
            }
            if (fresh && (leaves == MARGINAL_SOURCES_MOST))
            {
                return 0;
            }
            local_leaf[leaves] = fresh ? other : local_leaf[leaves];
            leaves += fresh ? 1u : 0u;
        }
    }
    size_t wanted = 0u;
    for (unsigned int local = 0u; local < leaves; local += 1u)
    {
        wanted += (size_t)(choices->start[local_leaf[local] + 1u] - choices->start[local_leaf[local]]);
    }
    if (score_marginal_room(set, leaves, wanted) == 0)
    {
        return -1;
    }
    const unsigned int source_first = set->source_count;
    const unsigned int option_mark = set->option_count;
    for (unsigned int local = 0u; local < leaves; local += 1u)
    {
        const unsigned int own = local_leaf[local];
        MarginalSource *const source = &set->sources[set->source_count + local];
        source->option_first = set->option_count;
        source->options = 0u;
        source->absent = score_best_null(tree, own);
        for (unsigned int triple = choices->start[own]; triple < choices->start[own + 1u]; triple += 1u)
        {
            const unsigned int target = choices->target[triple];
            unsigned int slot = targets;
            for (unsigned int seen = 0u; seen < targets; seen += 1u)
            {
                slot = (local_target[seen] == target) ? seen : slot;
            }
            if ((slot == targets) && (targets == MARGINAL_TARGETS_MOST))
            {
                set->option_count = option_mark;
                return 0;
            }
            local_target[slot] = target;
            targets += (slot == targets) ? 1u : 0u;
            set->options[set->option_count].target = slot;
            set->options[set->option_count].weight = choices->weight[triple];
            set->option_count += 1u;
            source->options += 1u;
        }
    }
    const MarginalRequest probe = {set->questions, 0u, set->sources, source_first + leaves, set->options,
                                   set->option_count, NULL, NULL};
    const MarginalQuestion asked = {source_first, leaves};
    if (marginal_arrangements(&probe, &asked) == MARGINAL_REFUSED)
    {
        set->option_count = option_mark;
        return 0;
    }
    set->questions[set->question_count] = asked;
    set->source_count += leaves;
    return 1;
}

typedef struct
{
    ScoreChoices *choices;
    unsigned int *start;
    unsigned int *target;
    unsigned int *weight;
} ScoreStars;

static void score_stars_release(ScoreStars *stars)
{
    free(stars->choices);
    free(stars->start);
    free(stars->target);
    free(stars->weight);
    memset(stars, 0, sizeof(*stars));
}

static unsigned int score_box_cell(const ClimbMachineBox *box, unsigned int boxed, const int *lag)
{
    unsigned int found = 0xFFFFFFFFu;
    for (unsigned int cell = box->cell_first[boxed]; cell < box->cell_first[boxed + 1u]; cell += 1u)
    {
        const int *const shift = &box->cell_shift[3u * cell];
        const int same = (shift[0] == lag[0]) && (shift[1] == lag[1]) && (shift[2] == lag[2]);
        found = ((found == 0xFFFFFFFFu) && same) ? cell : found;
    }
    return found;
}

static int score_box(const char *sample, const TreeFrame *frames, unsigned int frame_count, ClimbMachine *machine,
                     const int *tree_index_of_time, unsigned int volume_frames, ScoreStars *stars,
                     ClimbMachineBox *kept)
{
    ClimbMachineBox box;
    memset(kept, 0, sizeof(*kept));
    if (climb_machine_box(machine, &box) == 0)
    {
        fprintf(stderr, "  %s: the box was refused: %u climbers, %u cells; %u cells met more than %u bodies, %u cells"
                " counted fewer positive voxels than labeled ones\n", sample, box.climbers, box.cells, box.crowded,
                CLIMB_MACHINE_BOX_TARGETS, box.broken);
        return 0;
    }
    size_t starts = 0u;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        starts += (size_t)frames[frame].leaf_count + 1u;
    }
    memset(stars, 0, sizeof(*stars));
    stars->choices = (ScoreChoices *)calloc((size_t)frame_count + 1u, sizeof(ScoreChoices));
    stars->start = (unsigned int *)calloc(starts + 1u, sizeof(unsigned int));
    stars->target = (unsigned int *)malloc(((size_t)box.entries + 1u) * sizeof(unsigned int));
    stars->weight = (unsigned int *)malloc(((size_t)box.entries + 1u) * sizeof(unsigned int));
    int good = (stars->choices != NULL) && (stars->start != NULL) && (stars->target != NULL) && (stars->weight != NULL);
    unsigned int *const frame_offset = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    good = good && (frame_offset != NULL);
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        frame_offset[frame + 1u] = frame_offset[frame] + frames[frame].leaf_count + 1u;
    }
    unsigned int placed = 0u;
    unsigned int frame_base = 0u;
    unsigned int drift_asked = 0u;
    unsigned int drift_differ = 0u;
    unsigned int starred = 0u;
    for (unsigned int boxed = 0u; good && (boxed < box.climbers); boxed += 1u)
    {
        const unsigned int earlier = box.earlier[boxed];
        const unsigned int later = box.later[boxed];
        if ((later != earlier + 1u) || (earlier >= volume_frames) || (tree_index_of_time[earlier] < 0))
        {
            continue;
        }
        const unsigned int frame = (unsigned int)tree_index_of_time[earlier];
        const TreeFrame *const tree = &frames[frame];
        const unsigned int leaf = box.leaf[boxed];
        if (((frame + 1u) >= frame_count) || (frames[frame + 1u].time != later) || (tree->forward_lag == NULL)
         || (leaf >= tree->leaf_count))
        {
            continue;
        }
        unsigned int *const start = &stars->start[frame_offset[frame]];
        if (leaf == 0u)
        {
            frame_base = placed;
            stars->choices[frame].start = start;
            stars->choices[frame].target = &stars->target[frame_base];
            stars->choices[frame].weight = &stars->weight[frame_base];
        }
        start[leaf] = placed - frame_base;
        const unsigned int climbed = score_box_cell(&box, boxed, &tree->forward_lag[3u * leaf]);
        good = (climbed != 0xFFFFFFFFu);
        for (unsigned int entry = good ? box.entry_first[climbed] : 0u;
             good && (entry < box.entry_first[climbed + 1u]); entry += 1u)
        {
            if (box.target[entry] == CLIMB_MACHINE_BOX_NONE)
            {
                continue;
            }
            stars->target[placed] = box.target[entry];
            stars->weight[placed] = box.count[entry];
            placed += 1u;
        }
        start[leaf + 1u] = placed - frame_base;
        stars->choices[frame].count = placed - frame_base;
        starred += 1u;
        const unsigned int drifted = score_box_cell(&box, boxed, tree->lag_to_next);
        if ((drifted == 0xFFFFFFFFu) || (tree->triple_start == NULL))
        {
            continue;
        }
        drift_asked += 1u;
        unsigned int labeled = 0u;
        unsigned int agreed = 0u;
        for (unsigned int entry = box.entry_first[drifted]; entry < box.entry_first[drifted + 1u]; entry += 1u)
        {
            if (box.target[entry] == CLIMB_MACHINE_BOX_NONE)
            {
                continue;
            }
            labeled += 1u;
            for (unsigned int triple = tree->triple_start[leaf]; triple < tree->triple_start[leaf + 1u]; triple += 1u)
            {
                agreed += ((tree->triple_after[triple] == box.target[entry])
                           && (tree->triple_shared[triple] == box.count[entry])) ? 1u : 0u;
            }
        }
        const unsigned int triples = tree->triple_start[leaf + 1u] - tree->triple_start[leaf];
        drift_differ += ((labeled != triples) || (agreed != triples)) ? 1u : 0u;
    }
    free(frame_offset);
    if (good)
    {
        printf("  %s: the box C, %u climbers (every forward and null pair), %u cells (the 27 shifts around each climbed"
               " lag and the drift), %u entries (%u cells met more bodies than the fast table and were merged exactly),"
               " in %llu us\n", sample, box.climbers, box.cells, box.entries, box.crowded, box.microseconds);
        printf("  %s: at the climbed lag C sums to the climb's held count on all but %u; the climbed lag is highest in"
               " its neighbourhood on all but %u; at the drift C equals the overlap triples on all but %u of %u bodies;"
               " T* laid out for %u bodies, %u options\n", sample, box.held_differ, box.not_highest, drift_differ,
               drift_asked, starred, placed);
    }
    else
    {
        fprintf(stderr, "  %s: a climbed lag fell outside its own box\n", sample);
        score_stars_release(stars);
    }
    *kept = good ? box : *kept;
    return (good && (box.held_differ == 0u) && (drift_differ == 0u)) ? 1 : 0;
}

static_assert(CLIMB_MACHINE_EXTENT_FIELDS == BOX_HISTORY_EXTENT_FIELDS,
              "score_sample: the climb machine's extents are the box history's boxes");

static void score_box_history_series(const char *role, const TreeFrame *tree, unsigned int leaf,
                                     const unsigned int *counts, unsigned int windows)
{
    // leaf widens from unsigned int to size_t before the multiply, so leaf * 6 cannot wrap in 32 bits
    const unsigned int *const extent = &tree->extents[(size_t)leaf * BOX_HISTORY_EXTENT_FIELDS];
    printf(" %s leaf %u (%u voxels, box %u..%u %u..%u %u..%u):", role, leaf, tree->sizes[leaf], extent[0], extent[3],
           extent[1], extent[4], extent[2], extent[5]);
    for (unsigned int window = 0u; window < windows; window += 1u)
    {
        unsigned long long density = 0ull;
        for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
        {
            // the count widens from unsigned int to unsigned long long, so shifting it by a history bit stays in 64 bits
            density += (unsigned long long)counts[(window * ENGINE_HISTORY_BITS) + bit] << bit;
        }
        printf(" %llu", density);
    }
    printf(";");
}

static int score_box_history(const char *set, const char *sample, const TreeFrame *frames, unsigned int frame_count,
                             const AnswerKey *key, const int *node_leaf, const int *tree_index_of_time,
                             unsigned int volume_frames)
{
    char path[ENGINE_PATH_ROOM];
    EngineHistory history;
    memset(&history, 0, sizeof(history));
    EngineError error;
    memset(&error, 0, sizeof(error));
    if ((engine_sample_path(path, sizeof(path), set, sample, ".knf") == 0)
     || (engine_entropy_history_read(path, &history, &error) != 0L))
    {
        fprintf(stderr, "  %s: no noise floor (.knf) to gather the boxes from\n", sample);
        if (error.kind != ENGINE_ERROR_NONE)
        {
            track_error_report("entropy history read", &error);
        }
        return 0;
    }
    unsigned int *const frame_first = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    int steps_succeeded = (frame_first != NULL);
    unsigned int bodies = 0u;
    for (unsigned int frame = 0u; steps_succeeded && (frame < frame_count); frame += 1u)
    {
        frame_first[frame] = bodies;
        bodies += frames[frame].leaf_count;
        steps_succeeded = (frames[frame].extents != NULL) || (frames[frame].leaf_count == 0u);
    }
    const unsigned int windows = (unsigned int)history.windows;
    unsigned int *const extents = steps_succeeded ? (unsigned int *)malloc(((size_t)bodies + 1u) * BOX_HISTORY_EXTENT_FIELDS
                                                                           * sizeof(unsigned int)) : NULL;
    unsigned int *const counts = steps_succeeded ? (unsigned int *)malloc(((size_t)bodies * windows + 1u) * ENGINE_HISTORY_BITS
                                                                          * sizeof(unsigned int)) : NULL;
    steps_succeeded = steps_succeeded && (extents != NULL) && (counts != NULL);
    for (unsigned int frame = 0u; steps_succeeded && (frame < frame_count); frame += 1u)
    {
        memcpy(&extents[(size_t)frame_first[frame] * BOX_HISTORY_EXTENT_FIELDS], frames[frame].extents,
               (size_t)frames[frame].leaf_count * BOX_HISTORY_EXTENT_FIELDS * sizeof(unsigned int));
    }
    if (steps_succeeded)
    {
        frame_first[frame_count] = bodies;
    }
    unsigned long long disagreements = 0ull;
    unsigned long long microseconds = 0ull;
    const BoxHistoryRequest request = {&history, bodies, extents, counts, &disagreements, &microseconds};
    steps_succeeded = steps_succeeded && (box_history_gather(&request) == 0L);
    if (steps_succeeded)
    {
        printf("  %s: the box history, %u bodies' boxes gathered from %u windows of %u transitions, %u bits, by 8 corners"
               " of each window's running-sum key, in %llu us; %llu of %llu differ from walking every box\n", sample,
               bodies, windows, ENGINE_HISTORY_WINDOW, ENGINE_HISTORY_BITS, microseconds, disagreements,
               (unsigned long long)bodies * windows * ENGINE_HISTORY_BITS);
    }
    unsigned int *const successors = steps_succeeded ? score_key_successors(key) : NULL;
    steps_succeeded = steps_succeeded && (successors != NULL);
    for (unsigned int node = 0u; steps_succeeded && (node < key->node_count); node += 1u)
    {
        const unsigned int *const node_successors = &successors[3u * node];
        const int time = key->node_coordinates[(size_t)node * 4u];
        if ((node_successors[0] != 2u) || (time < 0) || (((unsigned int)time + 1u) >= volume_frames)
         || (tree_index_of_time[time] < 0) || (node_leaf[node] < 0))
        {
            continue;
        }
        const unsigned int frame = (unsigned int)tree_index_of_time[time];
        printf("    division at frame %d, the transition to %d in window %u (density, the flips times 2^bit, a window each):", time,
               time + 1, (unsigned int)time / ENGINE_HISTORY_WINDOW);
        score_box_history_series("parent", &frames[frame], (unsigned int)node_leaf[node],
                                 &counts[(size_t)(frame_first[frame] + (unsigned int)node_leaf[node]) * windows
                                         * ENGINE_HISTORY_BITS], windows);
        for (unsigned int child = 1u; child <= 2u; child += 1u)
        {
            const int child_time = key->node_coordinates[(size_t)node_successors[child] * 4u];
            const int child_leaf = node_leaf[node_successors[child]];
            const int child_frame = ((child_time >= 0) && ((unsigned int)child_time < volume_frames))
                                  ? tree_index_of_time[child_time] : -1;
            if ((child_leaf < 0) || (child_frame < 0))
            {
                printf(" child on no leaf;");
                continue;
            }
            score_box_history_series("child", &frames[child_frame], (unsigned int)child_leaf,
                                     &counts[(size_t)(frame_first[child_frame] + (unsigned int)child_leaf) * windows
                                             * ENGINE_HISTORY_BITS], windows);
        }
        printf("\n");
    }
    unsigned int *const leaf_node_count = steps_succeeded
                                        ? (unsigned int *)calloc((size_t)bodies + 1u, sizeof(unsigned int)) : NULL;
    steps_succeeded = steps_succeeded && (leaf_node_count != NULL);
    unsigned int placed_nodes = 0u;
    for (unsigned int node = 0u; steps_succeeded && (node < key->node_count); node += 1u)
    {
        const int time = key->node_coordinates[(size_t)node * 4u];
        if ((time < 0) || ((unsigned int)time >= volume_frames) || (tree_index_of_time[time] < 0) || (node_leaf[node] < 0))
        {
            continue;
        }
        leaf_node_count[frame_first[tree_index_of_time[time]] + (unsigned int)node_leaf[node]] += 1u;
        placed_nodes += 1u;
    }
    unsigned int shared_nodes = 0u;
    unsigned int shared_leaves = 0u;
    unsigned int most_nodes_on_leaf = 0u;
    unsigned int most_nodes_leaf_voxels = 0u;
    for (unsigned int frame = 0u; steps_succeeded && (frame < frame_count); frame += 1u)
    {
        for (unsigned int leaf = 0u; leaf < frames[frame].leaf_count; leaf += 1u)
        {
            const unsigned int nodes_on_leaf = leaf_node_count[frame_first[frame] + leaf];
            shared_nodes += (nodes_on_leaf >= 2u) ? nodes_on_leaf : 0u;
            shared_leaves += (nodes_on_leaf >= 2u) ? 1u : 0u;
            most_nodes_leaf_voxels = (nodes_on_leaf > most_nodes_on_leaf) ? frames[frame].sizes[leaf]
                                                                          : most_nodes_leaf_voxels;
            most_nodes_on_leaf = (nodes_on_leaf > most_nodes_on_leaf) ? nodes_on_leaf : most_nodes_on_leaf;
        }
    }
    if (steps_succeeded)
    {
        printf("  %s: of %u key nodes on a leaf, %u share their leaf with another key node, on %u leaves; the most on"
               " one leaf is %u, a leaf of %u voxels\n", sample, placed_nodes, shared_nodes, shared_leaves,
               most_nodes_on_leaf, most_nodes_leaf_voxels);
    }
    free(leaf_node_count);
    if (steps_succeeded == 0)
    {
        fprintf(stderr, "  %s: the box history was refused\n", sample);
    }
    free(successors);
    free(counts);
    free(extents);
    free(frame_first);
    engine_entropy_history_release(&history);
    return (steps_succeeded && (disagreements == 0ull)) ? 1 : 0;
}

static const unsigned long long *score_core_fields(const ClimbMachineCore *core, unsigned int climber, unsigned int width)
{
    const unsigned int width_first = core->width_first[climber];
    const unsigned int width_count = core->width_first[climber + 1u] - width_first;
    return (width < width_count) ? &core->fields[(size_t)(width_first + width) * CLIMB_MACHINE_CORE_FIELDS] : NULL;
}

static int score_core(const char *sample, ClimbMachine *machine, const ClimbMachineBox *box)
{
    ClimbMachineCore core;
    if (climb_machine_core(machine, &core) == 0)
    {
        fprintf(stderr, "  %s: the core was refused\n", sample);
        return 0;
    }
    unsigned int most_widths = 0u;
    for (unsigned int climber = 0u; climber < core.climbers; climber += 1u)
    {
        const unsigned int width_count = core.width_first[climber + 1u] - core.width_first[climber];
        most_widths = (width_count > most_widths) ? width_count : most_widths;
    }
    const size_t room = (size_t)most_widths + 1u;
    unsigned long long *const climbers_at = (unsigned long long *)calloc(room, sizeof(unsigned long long));
    unsigned long long *const mass_at = (unsigned long long *)calloc(room, sizeof(unsigned long long));
    unsigned long long *const pairs_at = (unsigned long long *)calloc(room, sizeof(unsigned long long));
    unsigned long long *const within_half_voxel_at = (unsigned long long *)calloc(room, sizeof(unsigned long long));
    if ((climbers_at == NULL) || (mass_at == NULL) || (pairs_at == NULL) || (within_half_voxel_at == NULL))
    {
        free(climbers_at);
        free(mass_at);
        free(pairs_at);
        free(within_half_voxel_at);
        return 0;
    }
    unsigned int proved = 0u;
    unsigned int differing_climbers = 0u;
    unsigned int unboxed = 0u;
    unsigned int box_cursor = 0u;
    unsigned int pair_start = 0u;
    unsigned int earlier_count = 0u;
    for (unsigned int climber = 0u; climber < core.climbers; climber += 1u)
    {
        const unsigned int widths = core.width_first[climber + 1u] - core.width_first[climber];
        for (unsigned int width = 0u; width < widths; width += 1u)
        {
            climbers_at[width] += 1ull;
            mass_at[width] += score_core_fields(&core, climber, width)[0];
        }
        const int new_pair = (climber == 0u) || (core.earlier[climber] != core.earlier[climber - 1u])
                          || (core.later[climber] != core.later[climber - 1u]);
        if (new_pair)
        {
            pair_start = climber;
            earlier_count = 0u;
            while (((pair_start + earlier_count) < core.climbers) && (core.side[pair_start + earlier_count] == 0u)
                   && (core.earlier[pair_start + earlier_count] == core.earlier[climber])
                   && (core.later[pair_start + earlier_count] == core.later[climber]))
            {
                earlier_count += 1u;
            }
        }
        const unsigned int match = core.match[climber];
        if ((core.side[climber] != 0u) || (match == CLIMB_MACHINE_BOX_NONE))
        {
            continue;
        }
        unsigned int box_place = box_cursor;
        while ((box != NULL) && (box_place < box->climbers)
               && ((box->earlier[box_place] != core.earlier[climber]) || (box->later[box_place] != core.later[climber])
                   || (box->leaf[box_place] != core.leaf[climber])))
        {
            box_place += 1u;
        }
        if ((box != NULL) && (box_place < box->climbers))
        {
            box_cursor = box_place;
            const unsigned int cell = box->cell_first[box_place] + CLIMB_MACHINE_BOX_CENTRE;
            unsigned long long box_count_at_match = 0ull;
            for (unsigned int entry = box->entry_first[cell]; entry < box->entry_first[cell + 1u]; entry += 1u)
            {
                box_count_at_match += (box->target[entry] == match) ? box->count[entry] : 0ull;
            }
            const unsigned long long *const width_zero_fields = score_core_fields(&core, climber, 0u);
            differing_climbers += (box_count_at_match != ((width_zero_fields != NULL) ? width_zero_fields[0] : 0ull))
                                ? 1u : 0u;
            proved += 1u;
        }
        else
        {
            unboxed += 1u;
        }
        const unsigned int partner = pair_start + earlier_count + match;
        if ((partner >= core.climbers) || (core.side[partner] != 1u) || (core.leaf[partner] != match)
         || (core.earlier[partner] != core.earlier[climber]) || (core.later[partner] != core.later[climber])
         || (core.match[partner] != core.leaf[climber]))
        {
            continue;
        }
        const int *const lag = &core.lag[ENGINE_AXES * climber];
        for (unsigned int width = 0u; width < most_widths; width += 1u)
        {
            const unsigned long long *const forward = score_core_fields(&core, climber, width);
            const unsigned long long *const backward = score_core_fields(&core, partner, width);
            if ((forward == NULL) || (backward == NULL))
            {
                break;
            }
            pairs_at[width] += 1ull;
            const long long mass_product = (long long)(forward[0] * backward[0]);
            unsigned int within_half_voxel = 1u;
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                const long long displacement_scaled = (long long)(forward[0] * backward[1u + axis])
                                                    - (long long)(backward[0] * forward[1u + axis]);
                const long long lag_error_doubled = 2ll * (displacement_scaled - ((long long)lag[axis] * mass_product));
                within_half_voxel *= (((lag_error_doubled < 0ll) ? -lag_error_doubled : lag_error_doubled)
                                      <= mass_product) ? 1u : 0u;
            }
            within_half_voxel_at[width] += within_half_voxel;
        }
    }
    printf("  %s: the core, %u climbers on adjacent frames (both sides), %u widths kept, in %llu us; the width-0 core mass"
           " equals C at the climbed lag on all but %u of %u forward climbers (%u not in a box)\n", sample,
           core.climbers, core.widths, core.microseconds, differing_climbers, proved, unboxed);
    for (unsigned int width = 0u; width < most_widths; width += 1u)
    {
        printf("    width %u: %llu climbers reach it, core mass %llu; %llu mutual pairs hold both cores, the core"
               " displacement within half a voxel of the climbed lag on every axis for %llu\n", width,
               climbers_at[width], mass_at[width], pairs_at[width], within_half_voxel_at[width]);
    }
    free(climbers_at);
    free(mass_at);
    free(pairs_at);
    free(within_half_voxel_at);
    return (differing_climbers == 0u) ? 1 : 0;
}

static int score_marginal(const char *sample, const TreeFrame *frames, unsigned int frame_count, const AnswerKey *key,
                          const int *node_leaf, const int *tree_index_of_time, unsigned int volume_frames,
                          const ScoreChoices *stars)
{
    ScoreMarginalSet set;
    memset(&set, 0, sizeof(set));
    unsigned int leaves = 0u;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        leaves += frames[frame].leaf_count;
    }
    set.questions = (MarginalQuestion *)malloc(((size_t)leaves + 1u) * sizeof(MarginalQuestion));
    set.asked_leaf = (unsigned int *)malloc(((size_t)leaves + 1u) * sizeof(unsigned int));
    set.asked_frame = (unsigned int *)malloc(((size_t)leaves + 1u) * sizeof(unsigned int));
    unsigned int **const question_of = (unsigned int **)calloc((size_t)frame_count + 1u, sizeof(unsigned int *));
    int good = (set.questions != NULL) && (set.asked_leaf != NULL) && (set.asked_frame != NULL) && (question_of != NULL);
    unsigned int in_context = 0u;
    unsigned int alone = 0u;
    unsigned int refused = 0u;
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        const ScoreChoices choices = score_choices_of(frames, stars, frame);
        if ((choices.start == NULL) || (tree->forward == NULL) || ((frame + 1u) >= frame_count))
        {
            continue;
        }
        if (tree->null_held == NULL)
        {
            fprintf(stderr, "  %s: the marginal needs each body's null reading; run with --null or a floor\n", sample);
            good = 0;
            break;
        }
        const unsigned int targets = frames[frame + 1u].leaf_count;
        unsigned int *const target_start = (unsigned int *)calloc((size_t)targets + 2u, sizeof(unsigned int));
        unsigned int *const target_sources = (unsigned int *)malloc(((size_t)choices.count + 1u) * sizeof(unsigned int));
        question_of[frame] = (unsigned int *)malloc(((size_t)tree->leaf_count + 1u) * sizeof(unsigned int));
        good = (target_start != NULL) && (target_sources != NULL) && (question_of[frame] != NULL);
        for (unsigned int triple = 0u; good && (triple < choices.count); triple += 1u)
        {
            target_start[choices.target[triple] + 1u] += 1u;
        }
        for (unsigned int target = 0u; good && (target < targets); target += 1u)
        {
            target_start[target + 1u] += target_start[target];
        }
        for (unsigned int leaf = 0u; good && (leaf < tree->leaf_count); leaf += 1u)
        {
            for (unsigned int triple = choices.start[leaf]; triple < choices.start[leaf + 1u]; triple += 1u)
            {
                const unsigned int target = choices.target[triple];
                target_sources[target_start[target]] = leaf;
                target_start[target] += 1u;
            }
        }
        for (unsigned int target = targets; good && (target > 0u); target -= 1u)
        {
            target_start[target] = target_start[target - 1u];
        }
        if (good)
        {
            target_start[0] = 0u;
        }
        for (unsigned int leaf = 0u; good && (leaf < tree->leaf_count); leaf += 1u)
        {
            question_of[frame][leaf] = 0xFFFFFFFFu;
            if (choices.start[leaf + 1u] == choices.start[leaf])
            {
                continue;
            }
            int made = score_marginal_ask(&set, tree, &choices, target_start, target_sources, leaf, 0);
            in_context += (made > 0) ? 1u : 0u;
            if (made == 0)
            {
                made = score_marginal_ask(&set, tree, &choices, target_start, target_sources, leaf, 1);
                alone += (made > 0) ? 1u : 0u;
                refused += (made == 0) ? 1u : 0u;
            }
            good = (made >= 0);
            if (made > 0)
            {
                question_of[frame][leaf] = set.question_count;
                set.asked_leaf[set.question_count] = leaf;
                set.asked_frame[set.question_count] = frame;
                set.question_count += 1u;
            }
        }
        free(target_start);
        free(target_sources);
    }
    const size_t question_words = (size_t)set.question_count * MARGINAL_SUMS * MARGINAL_LIMBS;
    const size_t option_words = (size_t)set.option_count * MARGINAL_LIMBS;
    unsigned int *const device_questions = good ? (unsigned int *)malloc((question_words + 1u) * sizeof(unsigned int))
                                                : NULL;
    unsigned int *const device_options = good ? (unsigned int *)malloc((option_words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const host_questions = good ? (unsigned int *)malloc((question_words + 1u) * sizeof(unsigned int))
                                              : NULL;
    unsigned int *const host_options = good ? (unsigned int *)malloc((option_words + 1u) * sizeof(unsigned int)) : NULL;
    good = good && (device_questions != NULL) && (device_options != NULL) && (host_questions != NULL)
        && (host_options != NULL);
    const MarginalRequest device = {set.questions, set.question_count, set.sources, set.source_count, set.options,
                                    set.option_count, device_questions, device_options};
    const MarginalRequest host = {set.questions, set.question_count, set.sources, set.source_count, set.options,
                                  set.option_count, host_questions, host_options};
    const unsigned long long started = engine_clock_microseconds();
    good = good && (marginal_run(&device) == (long)set.question_count);
    const unsigned long long swept = engine_clock_microseconds() - started;
    good = good && (marginal_run_host(&host) == (long)set.question_count);
    const int same = good && (memcmp(device_questions, host_questions, question_words * sizeof(unsigned int)) == 0)
                  && (memcmp(device_options, host_options, option_words * sizeof(unsigned int)) == 0);
    unsigned int edges = 0u;
    unsigned int by_context = 0u;
    unsigned int by_absent = 0u;
    unsigned int by_weight = 0u;
    unsigned int by_climb = 0u;
    for (unsigned int edge = 0u; good && (edge < key->edge_count); edge += 1u)
    {
        const long source = node_slot_of(key, key->edge_ends[2u * edge]);
        const long target = node_slot_of(key, key->edge_ends[(2u * edge) + 1u]);
        if ((source < 0L) || (target < 0L))
        {
            continue;
        }
        const int time = key->node_coordinates[(size_t)source * 4u];
        const int next_time = key->node_coordinates[(size_t)target * 4u];
        if ((time < 0) || (next_time != time + 1) || ((unsigned int)next_time >= volume_frames)
         || (tree_index_of_time[time] < 0) || (node_leaf[source] < 0) || (node_leaf[target] < 0))
        {
            continue;
        }
        const unsigned int frame = (unsigned int)tree_index_of_time[time];
        const unsigned int leaf = (unsigned int)node_leaf[source];
        const unsigned int truth = (unsigned int)node_leaf[target];
        const unsigned int question = (question_of[frame] != NULL) ? question_of[frame][leaf] : 0xFFFFFFFFu;
        if (question == 0xFFFFFFFFu)
        {
            continue;
        }
        edges += 1u;
        const TreeFrame *const tree = &frames[frame];
        const ScoreChoices choices = score_choices_of(frames, stars, frame);
        const MarginalSource *const own = &set.sources[set.questions[question].source_first];
        const unsigned int *best = &device_questions[((size_t)question * MARGINAL_SUMS + MARGINAL_ABSENT)
                                                     * MARGINAL_LIMBS];
        int context_leaf = -1;
        unsigned int heaviest = 0u;
        int weight_leaf = -1;
        for (unsigned int option = 0u; option < own->options; option += 1u)
        {
            const unsigned int triple = choices.start[leaf] + option;
            const unsigned int *const sum = &device_options[(size_t)(own->option_first + option) * MARGINAL_LIMBS];
            const int ahead = (score_limbs_order(sum, best) > 0);
            best = ahead ? sum : best;
            context_leaf = ahead ? (int)choices.target[triple] : context_leaf;
            weight_leaf = (choices.weight[triple] > heaviest) ? (int)choices.target[triple] : weight_leaf;
            heaviest = (choices.weight[triple] > heaviest) ? choices.weight[triple] : heaviest;
        }
        by_context += (context_leaf == (int)truth) ? 1u : 0u;
        by_absent += (context_leaf < 0) ? 1u : 0u;
        by_weight += (weight_leaf == (int)truth) ? 1u : 0u;
        by_climb += (tree->forward[leaf] == (int)truth) ? 1u : 0u;
    }
    if (good)
    {
        printf("  %s: marginal, %u bodies asked (%u in their context, %u alone, %u too wide to ask), %u options, in %llu"
               " us; device %s the host\n", sample, set.question_count, in_context, alone, refused, set.option_count,
               swept, same ? "equals" : "DIFFERS FROM");
        printf("  %s: of %u key edges asked, the most probable in context lands on the truth for %u (no link is the"
               " most probable for %u), the heaviest candidate alone for %u, the climb's forward for %u\n", sample,
               edges, by_context, by_absent, by_weight, by_climb);
    }
    else
    {
        fprintf(stderr, "  %s: the marginal was refused\n", sample);
    }
    for (unsigned int frame = 0u; (question_of != NULL) && (frame < frame_count); frame += 1u)
    {
        free(question_of[frame]);
    }
    free(question_of);
    free(set.questions);
    free(set.sources);
    free(set.options);
    free(set.asked_leaf);
    free(set.asked_frame);
    free(device_questions);
    free(device_options);
    free(host_questions);
    free(host_options);
    return (good && same) ? 1 : 0;
}

static int score_contact_side(const char *sample, const TreeFrame *frames, unsigned int frame_count,
                              const TreeRules *rules)
{
    unsigned long long first = 0ull;
    unsigned long long bodies = 0ull;
    if (score_flattened_slice(sample, frames, frame_count, rules, &first, &bodies) == 0)
    {
        return 0;
    }
    size_t room = 0u;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        room += (size_t)frames[frame].joined_count;
    }
    unsigned int *const frame_first = (unsigned int *)malloc(((size_t)frame_count + 1u) * sizeof(unsigned int));
    unsigned int *const pairs = (unsigned int *)malloc(((room * 2u * CONTACT_SIDE_MEMBERS) + 1u) * sizeof(unsigned int));
    unsigned int *const sides = (unsigned int *)malloc(((room * CONTACT_SIDE_MEMBERS) + 1u) * sizeof(unsigned int));
    int good = (frame_first != NULL) && (pairs != NULL) && (sides != NULL) && ((room * 2u) <= 0x3FFFFFFFu);
    if (good)
    {
        frame_first[0] = 0u;
    }
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        frame_first[frame + 1u] = frame_first[frame] + frames[frame].leaf_count;
    }
    unsigned int contacts = 0u;
    unsigned int landed_together = 0u;
    for (unsigned int frame = 0u; good && ((frame + 1u) < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        for (unsigned int pair = 0u; (tree->forward != NULL) && (pair < tree->joined_count); pair += 1u)
        {
            const unsigned int one = tree->joined[2u * pair];
            const unsigned int other = tree->joined[(2u * pair) + 1u];
            const int one_after = tree->forward[one];
            const int other_after = tree->forward[other];
            if ((one_after < 0) || (other_after < 0))
            {
                continue;
            }
            unsigned int *const lane = &pairs[(size_t)contacts * 2u * CONTACT_SIDE_MEMBERS];
            lane[0] = frame_first[frame] + one;
            lane[1] = frame_first[frame] + other;
            lane[2] = frame_first[frame + 1u] + (unsigned int)one_after;
            lane[3] = frame_first[frame + 1u] + (unsigned int)other_after;
            sides[(size_t)contacts * CONTACT_SIDE_MEMBERS] = 2u * contacts;
            sides[((size_t)contacts * CONTACT_SIDE_MEMBERS) + 1u] = (2u * contacts) + 1u;
            landed_together += (one_after == other_after) ? 1u : 0u;
            contacts += 1u;
        }
    }
    const unsigned int *const magnitudes = &rules->flattened[first * rules->flattened_limbs];
    const unsigned int apart_limbs = cycle_record_out_limbs(rules->contact_difference_record);
    const unsigned int kept_limbs = cycle_record_out_limbs(rules->contact_kept_record);
    const unsigned int differences = 2u * contacts;
    const size_t apart_words = (size_t)differences * apart_limbs;
    const size_t kept_words = (size_t)contacts * kept_limbs;
    unsigned int *const apart_device = good ? (unsigned int *)malloc((apart_words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const apart_host = good ? (unsigned int *)malloc((apart_words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const kept_device = good ? (unsigned int *)malloc((kept_words + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const kept_host = good ? (unsigned int *)malloc((kept_words + 1u) * sizeof(unsigned int)) : NULL;
    good = good && (apart_device != NULL) && (apart_host != NULL) && (kept_device != NULL) && (kept_host != NULL);
    unsigned long long apart_sweep = 0ull;
    unsigned long long kept_sweep = 0ull;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const EngineRecordSweep apart_run = {rules->contact_difference_record, {magnitudes, magnitudes}, {bodies, bodies},
                                         pairs, differences, apart_device, &apart_sweep, &error};
    const EngineRecordSweep apart_host_run = {NULL, {magnitudes, magnitudes}, {bodies, bodies}, pairs, differences,
                                              apart_host, NULL, &error};
    const EngineRecordSweep kept_run = {rules->contact_kept_record, {apart_device, apart_device},
                                        {differences, differences}, sides, contacts, kept_device, &kept_sweep, &error};
    const EngineRecordSweep kept_host_run = {NULL, {apart_device, apart_device}, {differences, differences}, sides,
                                             contacts, kept_host, NULL, &error};
    good = good && ((contacts == 0u)
                    || ((engine_record_sweep(&apart_run) == (long)differences)
                        && (engine_record_host(rules->contact_difference_imprint, &apart_host_run) == (long)differences)
                        && (engine_record_sweep(&kept_run) == (long)contacts)
                        && (engine_record_host(rules->contact_kept_imprint, &kept_host_run) == (long)contacts)));
    if (error.kind != ENGINE_ERROR_NONE)
    {
        track_error_report("contact side sweep", &error);
    }
    const unsigned int differ = good ? ((memcmp(apart_device, apart_host, apart_words * sizeof(unsigned int)) != 0) ? 1u
                                                                                                                  : 0u)
                                     : 0u;
    const unsigned int *const offset = good ? rules->contact_kept_imprint->output_offset : NULL;
    const unsigned int *const bits = good ? rules->contact_kept_imprint->output_bits : NULL;
    unsigned int kept = 0u;
    unsigned int crossed = 0u;
    unsigned int kept_differ = 0u;
    for (unsigned int contact = 0u; good && (contact < contacts); contact += 1u)
    {
        const unsigned int *const record = &kept_device[(size_t)contact * kept_limbs];
        kept += (unsigned int)score_field_truthy(record, offset[CONTACT_SIDE_KEPT], bits[CONTACT_SIDE_KEPT]);
        crossed += (unsigned int)score_field_truthy(record, offset[CONTACT_SIDE_CROSSED], bits[CONTACT_SIDE_CROSSED]);
        kept_differ += (memcmp(record, &kept_host[(size_t)contact * kept_limbs], kept_limbs * sizeof(unsigned int)) != 0)
                     ? 1u : 0u;
    }
    if (good)
    {
        printf("  %s: contact side, %u touching pairs whose bodies both climb onward (%u differences in %llu us, the"
               " verdicts in %llu us): the centroid difference keeps its side on %u, crosses on %u, meets on %u (%u of"
               " them landed on one body); the differences %s the host, %u verdicts differ from it\n", sample,
               contacts, differences, apart_sweep, kept_sweep, kept, crossed, contacts - kept - crossed, landed_together,
               (differ == 0u) ? "equal" : "DIFFER FROM", kept_differ);
    }
    else
    {
        fprintf(stderr, "  %s: the contact side sweeps were refused\n", sample);
    }
    free(frame_first);
    free(pairs);
    free(sides);
    free(apart_device);
    free(apart_host);
    free(kept_device);
    free(kept_host);
    return (good && (differ == 0u) && (kept_differ == 0u)) ? 1 : 0;
}

static unsigned long long s_web_logged[5] = {0ull, 0ull, 0ull, 0ull, 0ull};

static int score_truth_hold(const char *source, const char *sample, AnswerKey *key)
{
    memset(key, 0, sizeof(*key));
    if (source == NULL)
    {
        return 1;
    }
    char path[ENGINE_PATH_ROOM];
    const int written = snprintf(path, sizeof(path), "%s/%s.geff", source, sample);
    if ((written <= 0) || ((size_t)written >= sizeof(path)))
    {
        fprintf(stderr, "  %s: %s/%s.geff is longer than a path may be\n", sample, source, sample);
        return 0;
    }
    EngineGeff geff;
    memset(&geff, 0, sizeof(geff));
    if (engine_geff_read(path, &geff) != 0L)
    {
        printf("  %s: no answer key at %s; run unscored\n", sample, path);
        return 1;
    }
    AnswerKeyTruth truth;
    truth.nodes = geff.nodes;
    truth.edges = geff.edges;
    truth.node_identity = geff.node_identity;
    truth.node_place = geff.node_place;
    truth.edge_ends = geff.edge_ends;
    const int held = hold_answer_key(&truth, key);
    engine_geff_release(&geff);
    if (held == 0)
    {
        fprintf(stderr, "  %s: the answer key at %s does not hold: ids past 63 bits, places off the grid or ids twice\n",
                sample, path);
    }
    return held;
}

int score_sample(const char *set, const char *source, const char *sample, const TreeRules *rules, EdgeTally *tally)
{
    memset(tally, 0, sizeof(*tally));
    AnswerKey key;
    if (score_truth_hold(source, sample, &key) == 0)
    {
        return 0;
    }
    unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
    unsigned short *volume = NULL;
    EngineSignum volume_root;
    EngineError error;
    memset(&error, 0, sizeof(error));
    if ((engine_kcr_load(set, sample, extent, &volume, &volume_root, NULL, &error) != 0L) || (extent[0] > 0xFFFFFFFFull)
        || (extent[1] > 0xFFFFFFFFull) || (extent[2] > 0xFFFFFFFFull) || (extent[3] > 0xFFFFFFFFull))
    {
        fprintf(stderr, "  %s: its .kcr in %s did not load and prove\n", sample, set);
        if (error.kind != ENGINE_ERROR_NONE)
        {
            track_error_report("kcr load", &error);
        }
        free(volume);
        release_answer_key(&key);
        return 0;
    }
    const unsigned int header[4] = {(unsigned int)extent[0], (unsigned int)extent[1], (unsigned int)extent[2],
                                    (unsigned int)extent[3]};
    const unsigned int volume_frames = header[0];

    unsigned char *const reached = (unsigned char *)calloc((size_t)volume_frames + 1u, 1u);
    int *const tree_index_of_time = (int *)malloc(((size_t)volume_frames + 1u) * sizeof(int));
    if ((reached == NULL) || (tree_index_of_time == NULL))
    {
        free(volume);
        free(reached);
        free(tree_index_of_time);
        release_answer_key(&key);
        return 0;
    }
    for (unsigned int time = 0u; time < volume_frames; time += 1u)
    {
        reached[time] = 1u;
    }
    unsigned int frame_count = 0u;
    for (unsigned int time = 0u; time < volume_frames; time += 1u)
    {
        tree_index_of_time[time] = (reached[time] != 0u) ? (int)frame_count : -1;
        frame_count += (reached[time] != 0u) ? 1u : 0u;
    }
    TreeFrame *const frames = (TreeFrame *)calloc((size_t)frame_count + 1u, sizeof(TreeFrame));
    if (frames != NULL)
    {
        unsigned int written = 0u;
        for (unsigned int time = 0u; time < volume_frames; time += 1u)
        {
            if (reached[time] != 0u)
            {
                frames[written].time = time;
                written += 1u;
            }
        }
    }

    EngineBuffers buffers;
    memset(&buffers, 0, sizeof(buffers));
    buffers.unit_sweep = rules->unit_sweep;
    buffers.depth = header[1];
    buffers.height = header[2];
    buffers.width = header[3];
    const size_t voxels = (size_t)buffers.depth * buffers.height * buffers.width;
    buffers.peak_room = ((buffers.depth + 1u) / 2u) * ((buffers.height + 1u) / 2u) * ((buffers.width + 1u) / 2u);
    buffers.pair_room = 1u << 18u;
    buffers.overlap_room = 1u << 16u;
    buffers.volume = (unsigned short *)malloc(voxels * sizeof(unsigned short));
    buffers.peak_indices = (unsigned int *)malloc((size_t)buffers.peak_room * sizeof(unsigned int));
    buffers.sizes = (unsigned int *)malloc((size_t)buffers.peak_room * sizeof(unsigned int));
    buffers.sums = (unsigned long long *)malloc((size_t)buffers.peak_room * 3u * sizeof(unsigned long long));
    buffers.peak_limbs = (unsigned int *)malloc((size_t)buffers.peak_room * ENGINE_RESIDUAL_LIMBS
                                                * sizeof(unsigned int));
    buffers.bodies = (EngineBody *)malloc((size_t)buffers.peak_room * sizeof(EngineBody));
    buffers.adjacency =(unsigned int *)malloc((size_t)buffers.pair_room * 2u * sizeof(unsigned int));
    buffers.joined = (unsigned int *)malloc((size_t)buffers.pair_room * 2u * sizeof(unsigned int));
    buffers.overlap_before = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    buffers.overlap_after = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    buffers.overlap_shared = (unsigned int *)malloc((size_t)buffers.overlap_room * sizeof(unsigned int));
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        buffers.labels[slot] = (unsigned int *)malloc(voxels * sizeof(unsigned int));
        buffers.positive[slot] = (unsigned long long *)malloc(((voxels + 63u) / 64u) * sizeof(unsigned long long));
        if ((rules->climb != 0) || (rules->cast != 0) || (rules->parallax != 0))
        {
            buffers.leaf_at_peak[slot] = (int *)malloc(voxels * sizeof(int));
            buffers.leaf_start[slot] = (unsigned int *)malloc(((size_t)buffers.peak_room + 2u) * sizeof(unsigned int));
            buffers.leaf_voxels[slot] = (unsigned int *)malloc(voxels * sizeof(unsigned int));
            for (size_t voxel = 0u; (buffers.leaf_at_peak[slot] != NULL) && (voxel < voxels); voxel += 1u)
            {
                buffers.leaf_at_peak[slot][voxel] = -1;
            }
        }
    }

    int *const node_leaf = (int *)malloc(((size_t)key.node_count + 1u) * sizeof(int));
    if (node_leaf != NULL)
    {
        for (unsigned int node = 0u; node < key.node_count; node += 1u)
        {
            node_leaf[node] = -1;
        }
    }

    int good = (frames != NULL) && (node_leaf != NULL) && (buffers.volume != NULL) && (buffers.peak_indices != NULL)
            && (buffers.sizes != NULL) && (buffers.sums != NULL) && (buffers.peak_limbs != NULL)
            && (buffers.adjacency != NULL) && (buffers.joined != NULL) && (buffers.overlap_before != NULL)
            && (buffers.overlap_after != NULL) && (buffers.overlap_shared != NULL) && (buffers.labels[0] != NULL)
            && (buffers.labels[1] != NULL) && (buffers.positive[0] != NULL) && (buffers.positive[1] != NULL)
            && ((rules->climb == 0) || ((buffers.leaf_at_peak[0] != NULL) && (buffers.leaf_at_peak[1] != NULL)
                                        && (buffers.leaf_start[0] != NULL) && (buffers.leaf_start[1] != NULL)
                                        && (buffers.leaf_voxels[0] != NULL) && (buffers.leaf_voxels[1] != NULL)));
    const int machine_wanted = (rules->pick != 0) || (rules->climb == 1) || (rules->climb == 3);
    const unsigned long long started = engine_clock_microseconds() / 1000ull;
    StageClock clocks;
    memset(&clocks, 0, sizeof(clocks));
    const bool object = rules->object;
    size_t object_cut_room = 0u;
    unsigned int *object_cut = NULL;
    size_t object_run_room = 0u;
    size_t object_run_count = 0u;
    unsigned int *object_runs = NULL;
    size_t object_leaf_room = 0u;
    size_t object_leaf_count = 0u;
    unsigned int *object_leaf_runs = NULL;
    unsigned int *const object_first_run = (unsigned int *)calloc(((size_t)frame_count + 1u) * object, sizeof(unsigned int));
    unsigned int *const object_leaf_code = (unsigned int *)calloc(voxels * object, sizeof(unsigned int));
    good = good && (!object || (object_first_run && object_leaf_code));
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        unsigned long long mark = engine_clock_microseconds();
        memcpy(buffers.volume, &volume[(size_t)frames[frame].time * voxels], voxels * sizeof(unsigned short));
        clocks.read += engine_clock_microseconds() - mark;
        mark = engine_clock_microseconds();
        good = (good != 0) && (track_frame_bodies(&buffers, 1u, &frames[frame]) != 0);
        clocks.bodies += engine_clock_microseconds() - mark;
        mark = engine_clock_microseconds();
        if ((good != 0) && machine_wanted && (buffers.machine == NULL))
        {
            unsigned long long padded = 1ull;
            const unsigned int extents[3] = {buffers.depth, buffers.height, buffers.width};
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                unsigned long long power = 1ull;
                while (power < (2ull * (unsigned long long)extents[axis]) - 1ull)
                {
                    power <<= 1u;
                }
                padded *= power;
            }
            ClimbMachineShape shape;
            memset(&shape, 0, sizeof(shape));
            shape.depth = buffers.depth;
            shape.height = buffers.height;
            shape.width = buffers.width;
            shape.peak_room = buffers.peak_room;
            shape.frames = frame_count;
            shape.weight_z = AXIS_WEIGHTS[0];
            shape.reserve_bytes = (unsigned int)(((padded * 16ull) >> 20u) + 768ull);
            buffers.machine = climb_machine_open(&shape);
            climb_machine_land_by_mass(buffers.machine,
                                       (unsigned int)((rules->mass != 0) || (rules->spiral != 0u)));
            good = (good != 0) && (climb_machine_spiral(buffers.machine, rules->spiral) != 0);
            good = (buffers.machine != NULL) ? 1 : 0;
        }
        if ((good != 0) && ((rules->climb >= 2) || (rules->cast != 0) || (rules->parallax != 0)))
        {
            track_group_voxels(&buffers, 1u, buffers.labels[1], &frames[frame]);
        }
        if ((good != 0) && (buffers.machine != NULL))
        {
            ClimbMachineFrame stored;
            memset(&stored, 0, sizeof(stored));
            stored.frame = frames[frame].time;
            stored.leaf_count = frames[frame].leaf_count;
            stored.labels = buffers.labels[1];
            stored.positive = buffers.positive[1];
            unsigned int *contact_start = NULL;
            unsigned int *contacts = NULL;
            if ((rules->climb == 1) || (rules->climb == 3))
            {
                stored.peaks = frames[frame].peaks;
                good = (rules->sticky == 0) || (frame_contacts(&frames[frame], &contact_start, &contacts) != 0);
                stored.contact_start = contact_start;
                stored.contacts = contacts;
            }
            good = (good != 0) && (climb_machine_store(buffers.machine, &stored) != 0);
            free(contact_start);
            free(contacts);
            if ((good != 0) && (rules->box_history != 0))
            {
                // leaf_count widens from unsigned int to size_t, so (leaf_count + 1) * 6 cannot wrap before malloc sees it
                frames[frame].extents = (unsigned int *)malloc(((size_t)frames[frame].leaf_count + 1u)
                                                               * CLIMB_MACHINE_EXTENT_FIELDS * sizeof(unsigned int));
                const ClimbMachineExtentsRequest extents_request = {frames[frame].time, frames[frame].extents};
                good = (frames[frame].extents != NULL) && (climb_machine_extents(buffers.machine, &extents_request) != 0);
            }
        }
        clocks.store += engine_clock_microseconds() - mark;
        mark = engine_clock_microseconds();
        if (good == 0)
        {
            break;
        }
        if (object)
        {
            const unsigned long long *const positive = buffers.positive[1];
            size_t positives = 0u;
            for (size_t word = 0u; word < (voxels + 63u) / 64u; word += 1u)
            {
                positives += engine_word_population(positive[word]);
            }
            good = good && engine_object_room_fit(&object_cut, &object_cut_room, positives + 2u, 2u)
                && engine_object_room_fit(&object_runs, &object_run_room, object_run_count + positives, 1u)
                && engine_object_room_fit(&object_leaf_runs, &object_leaf_room,
                                          object_leaf_count + frames[frame].leaf_count, 2u);
        }
        if (object && good)
        {
            const TreeFrame *const tree = &frames[frame];
            const unsigned int *const labels = buffers.labels[1];
            const unsigned long long *const positive = buffers.positive[1];
            unsigned int *const runs = object_cut;
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                object_leaf_code[tree->peaks[leaf]] = leaf + 1u;
            }
            runs[0] = 0u;
            runs[1] = 0u;
            size_t count = 0u;
            size_t voxel = 0u;
            for (unsigned int row = 0u; row < buffers.depth * buffers.height; row += 1u)
            {
                unsigned int previous = 0u;
                for (unsigned int column = 0u; column < buffers.width; column += 1u)
                {
                    const unsigned int live = (unsigned int)((positive[voxel >> 6u] >> (voxel & 63u)) & 1ULL);
                    const unsigned int code = live * object_leaf_code[labels[voxel] * live];
                    const unsigned int held = !!code;
                    const unsigned int begins = held & (unsigned int)(code != previous);
                    runs[2u * (count + 1u)] = (unsigned int)voxel;
                    count += begins;
                    const size_t slot = count * held;
                    runs[(2u * slot) + 1u] = ((code - held) << 8u) | ((unsigned int)voxel - runs[2u * slot]);
                    previous = code;
                    voxel += 1u;
                }
            }
            unsigned int *const leaf_runs = &object_leaf_runs[2u * object_leaf_count];
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                object_leaf_code[tree->peaks[leaf]] = 0u;
                leaf_runs[2u * leaf] = 0u;
                leaf_runs[(2u * leaf) + 1u] = 0u;
            }
            for (size_t slot = 1u; slot <= count; slot += 1u)
            {
                leaf_runs[(2u * (runs[(2u * slot) + 1u] >> 8u)) + 1u] += 1u;
            }
            unsigned int placed = (unsigned int)object_run_count;
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                leaf_runs[2u * leaf] = placed;
                placed += leaf_runs[(2u * leaf) + 1u];
            }
            for (size_t slot = 1u; slot <= count; slot += 1u)
            {
                const unsigned int word = runs[(2u * slot) + 1u];
                unsigned int *const cursor = &leaf_runs[2u * (word >> 8u)];
                object_runs[*cursor] = (runs[2u * slot] << 8u) | (word & 0xFFu);
                *cursor += 1u;
            }
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                leaf_runs[2u * leaf] -= leaf_runs[(2u * leaf) + 1u];
            }
            object_first_run[frame] = (unsigned int)object_run_count;
            object_run_count += count;
            object_leaf_count += tree->leaf_count;
        }
        if (rules->export_directory != NULL)
        {
            TreeFrame *const tree = &frames[frame];
            free(tree->moments);
            tree->moments = (unsigned long long *)calloc((size_t)tree->leaf_count * 6u + 1u, sizeof(unsigned long long));
            tree->exposed = (unsigned int *)calloc((size_t)tree->leaf_count + 1u, sizeof(unsigned int));
            tree->contact_faces = (unsigned int *)calloc((size_t)tree->joined_count + 1u, sizeof(unsigned int));
            good = (tree->moments != NULL) && (tree->exposed != NULL) && (tree->contact_faces != NULL);
            const unsigned int plane = buffers.height * buffers.width;
            for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
            {
                if (((buffers.positive[1][voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
                {
                    continue;
                }
                const int leaf = engine_leaf_of_peak(tree->peaks, tree->leaf_count, buffers.labels[1][voxel]);
                if (leaf < 0)
                {
                    continue;
                }
                const unsigned long long z = (unsigned long long)(voxel / plane);
                const unsigned long long y = (unsigned long long)((voxel % plane) / buffers.width);
                const unsigned long long x = (unsigned long long)((voxel % plane) % buffers.width);
                unsigned long long *const moment = &tree->moments[(size_t)(unsigned int)leaf * 6u];
                moment[0] += z * z;
                moment[1] += y * y;
                moment[2] += x * x;
                moment[3] += z * y;
                moment[4] += z * x;
                moment[5] += y * x;
                const long neighbours[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
                for (unsigned int face = 0u; face < 6u; face += 1u)
                {
                    const long near_z = (long)z + neighbours[face][0];
                    const long near_y = (long)y + neighbours[face][1];
                    const long near_x = (long)x + neighbours[face][2];
                    if ((near_z < 0L) || (near_z >= (long)buffers.depth) || (near_y < 0L) || (near_y >= (long)buffers.height)
                     || (near_x < 0L) || (near_x >= (long)buffers.width))
                    {
                        tree->exposed[(unsigned int)leaf] += 1u;
                        continue;
                    }
                    const size_t near = (size_t)((near_z * (long)buffers.height + near_y) * (long)buffers.width + near_x);
                    if (((buffers.positive[1][near / 64u] >> (near % 64u)) & 1ULL) == 0ULL)
                    {
                        tree->exposed[(unsigned int)leaf] += 1u;
                        continue;
                    }
                    const int other = engine_leaf_of_peak(tree->peaks, tree->leaf_count, buffers.labels[1][near]);
                    if ((other < 0) || (other <= leaf))
                    {
                        tree->exposed[(unsigned int)leaf] += (other < 0) ? 1u : 0u;
                        continue;
                    }
                    const unsigned long long sought = ((unsigned long long)(unsigned int)leaf << 32u) | (unsigned int)other;
                    unsigned int low = 0u;
                    unsigned int high = tree->joined_count;
                    while (low < high)
                    {
                        const unsigned int middle = low + (high - low) / 2u;
                        const unsigned long long key = ((unsigned long long)tree->joined[2u * middle] << 32u)
                                                     | tree->joined[2u * middle + 1u];
                        if (key < sought)
                        {
                            low = middle + 1u;
                        }
                        else
                        {
                            high = middle;
                        }
                    }
                    if ((low < tree->joined_count) && (tree->joined[2u * low] == (unsigned int)leaf)
                     && (tree->joined[2u * low + 1u] == (unsigned int)other))
                    {
                        tree->contact_faces[low] += 1u;
                    }
                }
            }
        }
        for (unsigned int node = 0u; node < key.node_count; node += 1u)
        {
            const int *const place = &key.node_coordinates[(size_t)node * 4u];
            if ((place[0] < 0) || ((unsigned int)place[0] != frames[frame].time))
            {
                continue;
            }
            const size_t voxel = ((size_t)place[1] * buffers.height + (size_t)place[2]) * buffers.width
                               + (size_t)place[3];
            node_leaf[node] = engine_leaf_of_peak(frames[frame].peaks, frames[frame].leaf_count,
                                                  buffers.labels[1][voxel]);
        }
        clocks.ties += engine_clock_microseconds() - mark;
        if ((frame > 0u) && (frames[frame].time == frames[frame - 1u].time + 1u))
        {
            good = relate_frames(&buffers, &frames[frame - 1u], &frames[frame], rules, &clocks);
        }
        unsigned int *const labels = buffers.labels[0];
        buffers.labels[0] = buffers.labels[1];
        buffers.labels[1] = labels;
        unsigned long long *const positive = buffers.positive[0];
        buffers.positive[0] = buffers.positive[1];
        buffers.positive[1] = positive;
        int *const leaf_at_peak = buffers.leaf_at_peak[0];
        buffers.leaf_at_peak[0] = buffers.leaf_at_peak[1];
        buffers.leaf_at_peak[1] = leaf_at_peak;
        unsigned int *const leaf_start = buffers.leaf_start[0];
        buffers.leaf_start[0] = buffers.leaf_start[1];
        buffers.leaf_start[1] = leaf_start;
        unsigned int *const leaf_voxels = buffers.leaf_voxels[0];
        buffers.leaf_voxels[0] = buffers.leaf_voxels[1];
        buffers.leaf_voxels[1] = leaf_voxels;
    }
    unsigned int floors = 0u;
    unsigned long long cloud[ENGINE_HISTORY_WINDOWS_MAX * ENGINE_HISTORY_WINDOWS_MAX];
    if ((good != 0) && (rules->null_draws != 0u) && (rules->floor_entropy != 0))
    {
        char cloud_path[ENGINE_PATH_ROOM];
        good = engine_sample_path(cloud_path, sizeof(cloud_path), set, sample, ".knf")
            && (engine_entropy_cloud(cloud_path, &floors, cloud, &error) == 0L);
        if (good == 0)
        {
            fprintf(stderr, "  %s: the floor's cloud could not be read from %s\n", sample, cloud_path);
            if (error.kind != ENGINE_ERROR_NONE)
            {
                track_error_report("entropy cloud read", &error);
            }
        }
    }
    const unsigned int draw_room = (floors != 0u) ? floors : rules->null_draws;
    int **null_scratch = NULL;
    unsigned int null_scratch_count = 0u;
    for (unsigned int frame = 0u; (good != 0) && (rules->null_draws != 0u) && (buffers.machine != NULL) && (frame < frame_count);
         frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        if (tree->forward_held == NULL)
        {
            continue;
        }
        tree->null_held = (unsigned int *)calloc(((size_t)tree->leaf_count + 1u) * draw_room, sizeof(unsigned int));
        int **const grown = (int **)realloc(null_scratch, ((size_t)null_scratch_count + (4u * draw_room)) * sizeof(int *));
        good = (tree->null_held != NULL) && (grown != NULL);
        null_scratch = (grown != NULL) ? grown : null_scratch;
        unsigned int aimed[ENGINE_HISTORY_WINDOWS_MAX];
        const unsigned int own_floor = (floors != 0u)
            ? (((tree->time / ENGINE_HISTORY_WINDOW) < floors) ? (tree->time / ENGINE_HISTORY_WINDOW) : (floors - 1u)) : 0u;
        for (unsigned int floor = 0u; floor < floors; floor += 1u)
        {
            aimed[floor] = floor;
        }
        for (unsigned int at = 1u; at < floors; at += 1u)
        {
            const unsigned int moving = aimed[at];
            unsigned int slot = at;
            while ((slot > 0u) && (cloud[(own_floor * floors) + aimed[slot - 1u]] > cloud[(own_floor * floors) + moving]))
            {
                aimed[slot] = aimed[slot - 1u];
                slot -= 1u;
            }
            aimed[slot] = moving;
        }
        for (unsigned int draw = 0u; (good != 0) && (draw < draw_room); draw += 1u)
        {
            unsigned int other = (frame + (frame_count / 2u) + draw) % frame_count;
            if (floors != 0u)
            {
                const unsigned int floor = aimed[draw];
                const unsigned int place = tree->time - (own_floor * ENGINE_HISTORY_WINDOW);
                const unsigned int line = (floor * ENGINE_HISTORY_WINDOW) + place;
                if ((floor == own_floor) || (line >= volume_frames) || (tree_index_of_time[line] < 0))
                {
                    continue;
                }
                other = (unsigned int)tree_index_of_time[line];
            }
            const unsigned int apart = (other > frame) ? (other - frame) : (frame - other);
            if ((frame_count < 8u) || (apart <= 2u) || ((frame_count - apart) <= 2u))
            {
                continue;
            }
            const TreeFrame *const null_frame = &frames[other];
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = tree->time;
            pair.later = null_frame->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                pair.lag[axis] = tree->lag_to_next[axis];
            }
            pair.earlier_leaves = tree->leaf_count;
            pair.earlier_peaks = tree->peaks;
            pair.later_leaves = null_frame->leaf_count;
            pair.later_peaks = null_frame->peaks;
            pair.forward_lags = (int *)malloc(((size_t)tree->leaf_count + 1u) * 3u * sizeof(int));
            pair.forward = (int *)malloc(((size_t)tree->leaf_count + 1u) * sizeof(int));
            pair.backward_lags = (int *)malloc(((size_t)null_frame->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward = (int *)malloc(((size_t)null_frame->leaf_count + 1u) * sizeof(int));
            pair.forward_held = &tree->null_held[(size_t)tree->null_count * ((size_t)tree->leaf_count + 1u)];
            null_scratch[null_scratch_count] = pair.forward_lags;
            null_scratch[null_scratch_count + 1u] = pair.forward;
            null_scratch[null_scratch_count + 2u] = pair.backward_lags;
            null_scratch[null_scratch_count + 3u] = pair.backward;
            null_scratch_count += 4u;
            good = (pair.forward_lags != NULL) && (pair.forward != NULL) && (pair.backward_lags != NULL) && (pair.backward != NULL)
                && (climb_machine_pend(buffers.machine, &pair) != 0);
            tree->null_count += (good != 0) ? 1u : 0u;
        }
    }
    int **arm_scratch = NULL;
    unsigned int arm_scratch_count = 0u;
    for (unsigned int frame = 0u; (good != 0) && (rules->arms != 0u) && (buffers.machine != NULL)
         && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        tree->arm_forward = (int *)malloc(((size_t)tree->leaf_count + 1u) * rules->arms * sizeof(int));
        int **const grown = (int **)realloc(arm_scratch, ((size_t)arm_scratch_count + (3u * rules->arms))
                                            * sizeof(int *));
        good = (tree->arm_forward != NULL) && (grown != NULL);
        arm_scratch = (grown != NULL) ? grown : arm_scratch;
        for (size_t slot = 0u; (good != 0) && (slot < ((size_t)tree->leaf_count + 1u) * rules->arms); slot += 1u)
        {
            tree->arm_forward[slot] = CLIMB_MACHINE_NO_LEAF;
        }
        for (unsigned int arm = 0u; (good != 0) && (arm < rules->arms); arm += 1u)
        {
            const unsigned int gap = arm + 2u;
            if ((frame + gap) >= frame_count)
            {
                continue;
            }
            const TreeFrame *const far = &frames[frame + gap];
            ClimbMachinePair pair;
            memset(&pair, 0, sizeof(pair));
            pair.earlier = tree->time;
            pair.later = far->time;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                pair.lag[axis] = (int)((long long)tree->lag_to_next[axis] * (long long)gap);
            }
            pair.earlier_leaves = tree->leaf_count;
            pair.earlier_peaks = tree->peaks;
            pair.later_leaves = far->leaf_count;
            pair.later_peaks = far->peaks;
            pair.forward_lags = (int *)malloc(((size_t)tree->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward_lags = (int *)malloc(((size_t)far->leaf_count + 1u) * 3u * sizeof(int));
            pair.backward = (int *)malloc(((size_t)far->leaf_count + 1u) * sizeof(int));
            pair.forward = &tree->arm_forward[(size_t)arm * ((size_t)tree->leaf_count + 1u)];
            arm_scratch[arm_scratch_count] = pair.forward_lags;
            arm_scratch[arm_scratch_count + 1u] = pair.backward_lags;
            arm_scratch[arm_scratch_count + 2u] = pair.backward;
            arm_scratch_count += 3u;
            good = (pair.forward_lags != NULL) && (pair.backward_lags != NULL) && (pair.backward != NULL)
                && (climb_machine_pend(buffers.machine, &pair) != 0);
            tree->arm_count += (good != 0) ? 1u : 0u;
        }
    }
    const unsigned long long climbing = engine_clock_microseconds();
    good = (good != 0) && ((buffers.machine == NULL) || (climb_machine_run(buffers.machine) != 0));
    clocks.climb += engine_clock_microseconds() - climbing;
    for (unsigned int scratch = 0u; scratch < null_scratch_count; scratch += 1u)
    {
        free(null_scratch[scratch]);
    }
    free(null_scratch);
    for (unsigned int scratch = 0u; scratch < arm_scratch_count; scratch += 1u)
    {
        free(arm_scratch[scratch]);
    }
    free(arm_scratch);
    for (unsigned int frame = 0u; (good != 0) && (rules->climb == 3) && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        for (unsigned int leaf = 0u; (tree->check_forward_lag != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            if (memcmp(&tree->check_forward_lag[3u * leaf], &tree->forward_lag[3u * leaf], 3u * sizeof(int)) != 0)
            {
                fprintf(stderr, "    climb disagrees: earlier frame %u leaf %u\n", tree->time, leaf);
            }
        }
        for (unsigned int leaf = 0u; (tree->check_backward_lag != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            if (memcmp(&tree->check_backward_lag[3u * leaf], &tree->backward_lag[3u * leaf], 3u * sizeof(int)) != 0)
            {
                fprintf(stderr, "    climb disagrees: later frame %u leaf %u\n", tree->time, leaf);
            }
        }
    }
    good = (good != 0) && ((rules->velocity == 0) || (score_velocity(sample, frames, frame_count, rules) != 0));
    good = (good != 0) && ((rules->division == 0)
                           || (score_division(sample, frames, frame_count, rules, &key, node_leaf, tree_index_of_time,
                                              volume_frames) != 0));
    good = (good != 0) && ((rules->contact_side == 0) || (score_contact_side(sample, frames, frame_count, rules) != 0));
    ScoreStars stars;
    memset(&stars, 0, sizeof(stars));
    ClimbMachineBox box;
    memset(&box, 0, sizeof(box));
    good = (good != 0) && ((rules->box == 0) || (buffers.machine == NULL)
                           || (score_box(sample, frames, frame_count, buffers.machine, tree_index_of_time, volume_frames,
                                         &stars, &box) != 0));
    good = (good != 0) && ((rules->core == 0) || (buffers.machine == NULL)
                           || (score_core(sample, buffers.machine, (rules->box != 0) ? &box : NULL) != 0));
    good = (good != 0) && ((rules->box_history == 0)
                           || (score_box_history(set, sample, frames, frame_count, &key, node_leaf, tree_index_of_time,
                                                 volume_frames) != 0));
    good = (good != 0) && ((rules->marginal == 0)
                           || (score_marginal(sample, frames, frame_count, &key, node_leaf, tree_index_of_time,
                                              volume_frames, stars.choices) != 0));
    score_stars_release(&stars);
    good = (good != 0) && ((rules->print_match == 0) || (score_print_match(sample, frames, frame_count, rules) != 0));
    const unsigned long long engines_done = engine_clock_microseconds() / 1000ull;

    for (unsigned int frame = 0u; (good != 0) && (rules->tower != 0) && (frame < frame_count); frame += 1u)
    {
        frames[frame].held_target = (unsigned int *)malloc(((size_t)frames[frame].leaf_count + 1u)
                                                            * sizeof(unsigned int));
        frames[frame].held_count = (unsigned int *)calloc((size_t)frames[frame].leaf_count + 1u,
                                                           sizeof(unsigned int));
        frames[frame].held_rounds = (unsigned int *)calloc((size_t)frames[frame].leaf_count + 1u,
                                                            sizeof(unsigned int));
        good = (frames[frame].held_target != NULL) && (frames[frame].held_count != NULL)
            && (frames[frame].held_rounds != NULL);
        for (unsigned int leaf = 0u; (good != 0) && (leaf < frames[frame].leaf_count); leaf += 1u)
        {
            frames[frame].held_target[leaf] = 0xFFFFFFFFu;
        }
    }
    unsigned int **const was_target = (unsigned int **)calloc((size_t)frame_count + 1u, sizeof(unsigned int *));
    unsigned int *const was_count = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    const unsigned int rounds = ((rules->tower != 0) && (was_target != NULL) && (was_count != NULL))
                              ? TOWER_ROUNDS : 1u;
    unsigned int turned = 0u;
    unsigned int moving = 1u;
    for (unsigned int round = 0u; (good != 0) && (round < rounds) && (moving != 0u); round += 1u)
    {
        turned = round + 1u;
        for (unsigned int frame = 0u; (round != 0u) && (frame < frame_count); frame += 1u)
        {
            free(frames[frame].link_start);
            free(frames[frame].link_target);
            free(frames[frame].pool_start);
            free(frames[frame].pool_target);
            free(frames[frame].pool_weight);
            free(frames[frame].pool_cost);
            frames[frame].link_start = NULL;
            frames[frame].link_target = NULL;
            frames[frame].pool_start = NULL;
            frames[frame].pool_target = NULL;
            frames[frame].pool_weight = NULL;
            frames[frame].pool_cost = NULL;
        }
        const unsigned int grouping_passes = (rules->agree != 0) ? 2u : 1u;
        for (unsigned int pass = 0u; (good != 0) && (pass < grouping_passes); pass += 1u)
        {
            for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
            {
                const TreeFrame *const previous = (frames[frame].backward != NULL) ? &frames[frame - 1u] : NULL;
                const TreeFrame *const next = ((pass != 0u) && ((frame + 1u) < frame_count))
                                            ? &frames[frame + 1u] : NULL;
                good = group_objects(&frames[frame], previous, next, buffers.height, buffers.width, rules);
            }
        }
        for (unsigned int frame = 0u; (good != 0) && (frame + 1u < frame_count); frame += 1u)
        {
            if (frames[frame].forward != NULL)
            {
                const TreeFrame *const before = (frame > 0u) ? &frames[frame - 1u] : NULL;
                const TreeFrame *const after = ((frame + 2u) < frame_count) ? &frames[frame + 2u] : NULL;
                good = (rules->unbound != 0) ? link_objects_unbound(&frames[frame], &frames[frame + 1u],
                                                                    before, after, rules)
                                             : link_objects(&frames[frame], &frames[frame + 1u], rules);
            }
        }
        for (unsigned int frame = 0u; (good != 0) && (rounds > 1u) && ((frame + 1u) < frame_count); frame += 1u)
        {
            TreeFrame *const tree = &frames[frame];
            const TreeFrame *const ahead = &frames[frame + 1u];
            if ((tree->link_start == NULL) || (tree->held_target == NULL) || (ahead->member_start == NULL))
            {
                continue;
            }
            for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
            {
                const unsigned int object = tree->object_of[leaf];
                const unsigned int links = tree->link_start[object + 1u] - tree->link_start[object];
                unsigned int target = 0xFFFFFFFFu;
                if (links == 1u)
                {
                    const unsigned int went = tree->link_target[tree->link_start[object]];
                    unsigned long long widest = 0ull;
                    for (unsigned int member = ahead->member_start[went];
                         member < ahead->member_start[went + 1u]; member += 1u)
                    {
                        const unsigned int other = ahead->members[member];
                        const unsigned long long size = band_or_count((unsigned int)rules->mass_band,
                                                                      ahead->sizes[other]);
                        const unsigned int bigger = (unsigned int)((target == 0xFFFFFFFFu) || (size > widest));
                        widest = (bigger != 0u) ? size : widest;
                        target = (bigger != 0u) ? other : target;
                    }
                }
                const unsigned int empty = (unsigned int)(tree->held_count[leaf] == 0u);
                const unsigned int agrees = (unsigned int)(target == tree->held_target[leaf]);
                tree->held_target[leaf] = (empty != 0u) ? target : tree->held_target[leaf];
                tree->held_count[leaf] = ((empty != 0u) || (agrees != 0u))
                                       ? (tree->held_count[leaf] + 1u) : (tree->held_count[leaf] - 1u);
                tree->held_rounds[leaf] += (unsigned int)(agrees != 0u);
            }
        }
        moving = 0u;
        for (unsigned int frame = 0u; (good != 0) && (rounds > 1u) && (frame < frame_count); frame += 1u)
        {
            const unsigned int links = (frames[frame].link_start != NULL)
                                     ? frames[frame].link_start[frames[frame].object_count] : 0u;
            const unsigned int same = (unsigned int)((links == was_count[frame]) && (was_target[frame] != NULL)
                                                     && ((links == 0u)
                                                         || (memcmp(was_target[frame], frames[frame].link_target,
                                                                    (size_t)links * sizeof(unsigned int)) == 0)));
            moving += (unsigned int)(same == 0u);
            unsigned int *const kept = (links != 0u)
                                     ? (unsigned int *)malloc((size_t)links * sizeof(unsigned int)) : NULL;
            if (kept != NULL)
            {
                memcpy(kept, frames[frame].link_target, (size_t)links * sizeof(unsigned int));
            }
            free(was_target[frame]);
            was_target[frame] = kept;
            was_count[frame] = links;
        }
    }
    for (unsigned int frame = 0u; (was_target != NULL) && (frame < frame_count); frame += 1u)
    {
        free(was_target[frame]);
    }
    free(was_target);
    free(was_count);
    if ((rules->tower != 0) && (rules->edges != NULL))
    {
        printf("    tower: %u rounds, %s\n", turned,
               (moving == 0u) ? "settled" : "still moving when the rounds ran out");
    }
    const unsigned int refocused = ((good != 0) && (rules->focus != 0))
                                 ? focus_links(frames, frame_count, (unsigned int)rules->mass_band) : 0u;
    if ((rules->focus != 0) && (rules->edges != NULL))
    {
        printf("    focus moved %u links\n", refocused);
    }

    NodeIndex index;
    memset(&index, 0, sizeof(index));
    index.frame_count = frame_count;
    index.frames = frames;
    index.node_offset = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    good = (good != 0) && (index.node_offset != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        index.node_offset[frame + 1u] = index.node_offset[frame] + frames[frame].object_count;
    }
    index.node_count = (good != 0) ? index.node_offset[frame_count] : 0u;
    index.node_frame = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    unsigned int *const parent = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    good = (good != 0) && (index.node_frame != NULL) && (parent != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        for (unsigned int node = index.node_offset[frame]; node < index.node_offset[frame + 1u]; node += 1u)
        {
            index.node_frame[node] = frame;
            parent[node] = node;
        }
    }

    unsigned int rejoined = 0u;
    unsigned int visited_room = 64u;
    unsigned int *visited = (unsigned int *)malloc((size_t)visited_room * 2u * sizeof(unsigned int));
    good = (good != 0) && (visited != NULL);
    for (unsigned int frame = 0u; (good != 0) && (rules->resolve != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start == NULL)
        {
            continue;
        }
        const unsigned int next_offset = index.node_offset[frame + 1u];
        for (unsigned int object = 0u; (good != 0) && (object < frames[frame].object_count); object += 1u)
        {
            const unsigned int *const children = &frames[frame].link_target[frames[frame].link_start[object]];
            const unsigned int child_count = frames[frame].link_start[object + 1u] - frames[frame].link_start[object];
            if (child_count < 2u)
            {
                continue;
            }
            for (unsigned int first_slot = 0u; (good != 0) && (first_slot < child_count); first_slot += 1u)
            {
                for (unsigned int second_slot = first_slot + 1u; (good != 0) && (second_slot < child_count);
                     second_slot += 1u)
                {
                    const unsigned int first = next_offset + children[first_slot];
                    const unsigned int second = next_offset + children[second_slot];
                    if (engine_find_root(parent, first) == engine_find_root(parent, second))
                    {
                        continue;
                    }
                    unsigned int left = first;
                    unsigned int right = second;
                    visited[0] = left;
                    visited[1] = right;
                    unsigned int steps = 1u;
                    while (left != right)
                    {
                        const unsigned int *left_next = NULL;
                        const unsigned int *right_next = NULL;
                        unsigned int left_count = 0u;
                        unsigned int right_count = 0u;
                        links_of_node(&index, left, &left_next, &left_count);
                        links_of_node(&index, right, &right_next, &right_count);
                        if ((left_count != 1u) || (right_count != 1u))
                        {
                            break;
                        }
                        left = index.node_offset[index.node_frame[left] + 1u] + left_next[0];
                        right = index.node_offset[index.node_frame[right] + 1u] + right_next[0];
                        if (steps == visited_room)
                        {
                            visited_room *= 2u;
                            unsigned int *const grown = (unsigned int *)realloc(visited, (size_t)visited_room * 2u
                                                                                * sizeof(unsigned int));
                            if (grown == NULL)
                            {
                                good = 0;
                                break;
                            }
                            visited = grown;
                        }
                        visited[2u * steps] = left;
                        visited[2u * steps + 1u] = right;
                        steps += 1u;
                    }
                    if ((good != 0) && (left == right))
                    {
                        rejoined += 1u;
                        for (unsigned int step = 0u; step + 1u < steps; step += 1u)
                        {
                            const unsigned int one = engine_find_root(parent, visited[2u * step]);
                            const unsigned int other = engine_find_root(parent, visited[2u * step + 1u]);
                            if (one != other)
                            {
                                parent[(one > other) ? one : other] = (one < other) ? one : other;
                            }
                        }
                    }
                }
            }
        }
    }
    free(visited);

    unsigned int *const unified_of = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    unsigned int *const rank_of_root = (unsigned int *)malloc(((size_t)index.node_count + 1u) * sizeof(unsigned int));
    good = (good != 0) && (unified_of != NULL) && (rank_of_root != NULL);
    unsigned int unified_count = 0u;
    unsigned int *const unified_first = (unsigned int *)calloc((size_t)frame_count + 1u, sizeof(unsigned int));
    good = (good != 0) && (unified_first != NULL);
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        unified_first[frame] = unified_count;
        for (unsigned int node = index.node_offset[frame]; node < index.node_offset[frame + 1u]; node += 1u)
        {
            if (engine_find_root(parent, node) == node)
            {
                rank_of_root[node] = unified_count;
                unified_count += 1u;
            }
        }
    }
    if (good != 0)
    {
        unified_first[frame_count] = unified_count;
    }
    for (unsigned int node = 0u; (good != 0) && (node < index.node_count); node += 1u)
    {
        unified_of[node] = rank_of_root[engine_find_root(parent, node)];
    }
    unsigned int link_total = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start != NULL)
        {
            link_total += frames[frame].link_start[frames[frame].object_count];
        }
    }
    unsigned long long *const unified_link = (unsigned long long *)malloc(((size_t)link_total + 1u)
                                                                         * sizeof(unsigned long long));
    good = (good != 0) && (unified_link != NULL);
    unsigned int unified_links = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        if (frames[frame].link_start == NULL)
        {
            continue;
        }
        for (unsigned int object = 0u; object < frames[frame].object_count; object += 1u)
        {
            const unsigned int source = unified_of[index.node_offset[frame] + object];
            for (unsigned int link = frames[frame].link_start[object]; link < frames[frame].link_start[object + 1u];
                 link += 1u)
            {
                const unsigned int child = unified_of[index.node_offset[frame + 1u] + frames[frame].link_target[link]];
                unified_link[unified_links] = ((unsigned long long)source << 32u) | child;
                unified_links += 1u;
            }
        }
    }
    unified_links = (good != 0) ? engine_sort_unique(unified_link, unified_links) : 0u;
    unsigned int *const unified_start = (unsigned int *)calloc((size_t)unified_count + 2u, sizeof(unsigned int));
    good = (good != 0) && (unified_start != NULL);
    for (unsigned int link = 0u; (good != 0) && (link < unified_links); link += 1u)
    {
        unified_start[(unsigned int)(unified_link[link] >> 32u) + 1u] += 1u;
    }
    for (unsigned int unified = 0u; (good != 0) && (unified < unified_count); unified += 1u)
    {
        unified_start[unified + 1u] += unified_start[unified];
    }

    unsigned int *const successors = (unsigned int *)calloc((size_t)key.node_count + 1u, sizeof(unsigned int));
    signed char *const edge_status = (signed char *)malloc((size_t)key.edge_count + 1u);
    good = (good != 0) && (successors != NULL) && (edge_status != NULL);
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        edge_status[edge] = -1;
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        if (source >= 0L)
        {
            successors[(unsigned long)source] += 1u;
        }
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key.edge_count); edge += 1u)
    {
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        const long target = node_slot_of(&key, key.edge_ends[2u * edge + 1u]);
        if ((source < 0L) || (target < 0L))
        {
            continue;
        }
        const int source_time = key.node_coordinates[(size_t)source * 4u];
        const int target_time = key.node_coordinates[(size_t)target * 4u];
        if ((source_time < 0) || (target_time < 0) || ((unsigned int)source_time >= volume_frames)
         || ((unsigned int)target_time >= volume_frames))
        {
            continue;
        }
        const int source_frame = tree_index_of_time[source_time];
        const int target_frame = tree_index_of_time[target_time];
        const int source_leaf = node_leaf[source];
        const int target_leaf = node_leaf[target];
        if ((source_leaf < 0) || (target_leaf < 0))
        {
            tally->missed += 1ULL;
            edge_status[edge] = 4;
            continue;
        }
        const unsigned int source_unified
            = unified_of[index.node_offset[source_frame] + frames[source_frame].object_of[source_leaf]];
        const unsigned int target_unified
            = unified_of[index.node_offset[target_frame] + frames[target_frame].object_of[target_leaf]];
        const unsigned int made = unified_start[source_unified + 1u] - unified_start[source_unified];
        if (made == 0u)
        {
            tally->unlinked += 1ULL;
            edge_status[edge] = 3;
            continue;
        }
        int holds_target = 0;
        for (unsigned int link = unified_start[source_unified]; link < unified_start[source_unified + 1u]; link += 1u)
        {
            if ((unsigned int)(unified_link[link] & 0xFFFFFFFFULL) == target_unified)
            {
                holds_target = 1;
            }
        }
        if ((holds_target != 0) && ((made == 1u) || (made == successors[source])))
        {
            tally->correct += 1ULL;
            edge_status[edge] = 0;
        }
        else if (holds_target != 0)
        {
            tally->branched += 1ULL;
            edge_status[edge] = 1;
        }
        else
        {
            tally->wrong += 1ULL;
            edge_status[edge] = 2;
        }
    }
    unsigned int *edge_near_start = NULL;
    unsigned int *edge_nearby = NULL;
    unsigned int *edge_later_near_start = NULL;
    unsigned int *edge_later_nearby = NULL;
    unsigned int *edge_seen = NULL;
    unsigned int edge_mark = 0u;
    unsigned int edge_pair_from = 0xFFFFFFFFu;
    unsigned int edge_pair_to = 0xFFFFFFFFu;
    for (unsigned int edge = 0u; (good != 0) && (rules->edges != NULL) && (edge < key.edge_count); edge += 1u)
    {
        const int status = edge_status[edge];
        if ((status < 0) || (status == 4))
        {
            continue;
        }
        const long source = node_slot_of(&key, key.edge_ends[2u * edge]);
        const long target = node_slot_of(&key, key.edge_ends[2u * edge + 1u]);
        const int *const from = &key.node_coordinates[(size_t)source * 4u];
        const int *const to = &key.node_coordinates[(size_t)target * 4u];
        const TreeFrame *const tree = &frames[tree_index_of_time[from[0]]];
        const unsigned int leaf = (unsigned int)node_leaf[source];
        const int *const carried = (tree->forward_lag != NULL) ? &tree->forward_lag[3u * leaf] : tree->lag_to_next;
        const unsigned int held = (tree->forward_held != NULL) ? tree->forward_held[leaf] : 0u;
        unsigned int null_at_least = 0u;
        unsigned int null_best = 0u;
        for (unsigned int draw = 0u; (tree->null_held != NULL) && (draw < tree->null_count); draw += 1u)
        {
            const unsigned int drawn = tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u)) + leaf];
            null_at_least += (drawn >= held) ? 1u : 0u;
            null_best = (drawn > null_best) ? drawn : null_best;
        }
        const TreeFrame *const next_tree = &frames[tree_index_of_time[to[0]]];
        if ((edge_pair_from != tree_index_of_time[from[0]]) || (edge_pair_to != tree_index_of_time[to[0]]))
        {
            free(edge_near_start);
            free(edge_nearby);
            free(edge_later_near_start);
            free(edge_later_nearby);
            free(edge_seen);
            edge_near_start = NULL;
            edge_nearby = NULL;
            edge_later_near_start = NULL;
            edge_later_nearby = NULL;
            edge_seen = NULL;
            const int joined = (frame_contacts(tree, &edge_near_start, &edge_nearby) != 0)
                            && (frame_contacts(next_tree, &edge_later_near_start, &edge_later_nearby) != 0);
            edge_seen = (unsigned int *)calloc((size_t)tree->leaf_count + 2u, sizeof(unsigned int));
            if ((joined == 0) || (edge_seen == NULL))
            {
                free(edge_near_start);
                free(edge_nearby);
                free(edge_later_near_start);
                free(edge_later_nearby);
                free(edge_seen);
                edge_near_start = NULL;
                edge_nearby = NULL;
                edge_later_near_start = NULL;
                edge_later_nearby = NULL;
                edge_seen = NULL;
            }
            edge_mark = 0u;
            edge_pair_from = tree_index_of_time[from[0]];
            edge_pair_to = tree_index_of_time[to[0]];
        }
        const int truth_leaf = node_leaf[target];
        const int chosen_leaf = (tree->forward != NULL) ? tree->forward[leaf] : -1;
        const unsigned int pairs_first = (tree->triple_start != NULL) ? tree->triple_start[leaf] : 0u;
        const unsigned int pairs_past = (tree->triple_start != NULL) ? tree->triple_start[leaf + 1u] : 0u;
        unsigned int truth_shared = 0u;
        unsigned int chosen_shared = 0u;
        unsigned int best_shared = 0u;
        int best_leaf = -1;
        for (unsigned int pair = pairs_first; pair < pairs_past; pair += 1u)
        {
            const int after = (int)tree->triple_after[pair];
            const unsigned int shared = tree->triple_shared[pair];
            truth_shared = (after == truth_leaf) ? shared : truth_shared;
            chosen_shared = (after == chosen_leaf) ? shared : chosen_shared;
            best_leaf = (shared > best_shared) ? after : best_leaf;
            best_shared = (shared > best_shared) ? shared : best_shared;
        }
        const int truth_back = ((truth_leaf >= 0) && (next_tree->backward != NULL)) ? next_tree->backward[truth_leaf] : -1;
        const unsigned int truth_mutual = (unsigned int)((truth_back >= 0)
                                                         && (tree->object_of[truth_back] == tree->object_of[leaf]));
        const unsigned int one_object = (unsigned int)((truth_leaf >= 0) && (chosen_leaf >= 0)
                                                       && (next_tree->object_of[truth_leaf]
                                                           == next_tree->object_of[chosen_leaf]));
        const unsigned int own_object = tree->object_of[leaf];
        const unsigned int truth_object = (truth_leaf >= 0) ? next_tree->object_of[truth_leaf] : 0xFFFFFFFFu;
        const unsigned int object_links = (tree->link_start != NULL)
                                        ? (tree->link_start[own_object + 1u] - tree->link_start[own_object]) : 0u;
        unsigned int object_links_truth = 0u;
        for (unsigned int link = 0u; (tree->link_start != NULL) && (link < object_links); link += 1u)
        {
            object_links_truth += (unsigned int)(tree->link_target[tree->link_start[own_object] + link] == truth_object);
        }
        const unsigned int linked_object = ((tree->link_start != NULL) && (object_links != 0u))
                                         ? tree->link_target[tree->link_start[own_object]] : 0xFFFFFFFFu;
        unsigned long long truth_weight = 0ULL;
        unsigned long long linked_weight = 0ULL;
        const unsigned int members = tree->member_start[own_object + 1u] - tree->member_start[own_object];
        for (unsigned int member = tree->member_start[own_object]; member < tree->member_start[own_object + 1u];
             member += 1u)
        {
            const unsigned int other = tree->members[member];
            const unsigned int other_first = (tree->triple_start != NULL) ? tree->triple_start[other] : 0u;
            const unsigned int other_past = (tree->triple_start != NULL) ? tree->triple_start[other + 1u] : 0u;
            for (unsigned int pair = other_first; pair < other_past; pair += 1u)
            {
                const unsigned int after_object = next_tree->object_of[tree->triple_after[pair]];
                truth_weight += (after_object == truth_object) ? tree->triple_shared[pair] : 0u;
                linked_weight += (after_object == linked_object) ? tree->triple_shared[pair] : 0u;
            }
        }
        unsigned long long truth_web = 0ULL;
        unsigned long long linked_web = 0ULL;
        if ((edge_near_start != NULL) && (edge_later_near_start != NULL) && (edge_seen != NULL))
        {
            edge_mark += 1u;
            truth_web = (truth_object != 0xFFFFFFFFu)
                      ? web_count(tree, own_object, next_tree, truth_object, edge_near_start, edge_nearby,
                                  edge_later_near_start, edge_later_nearby, edge_seen, edge_mark) : 0ULL;
            edge_mark += 1u;
            linked_web = (linked_object != 0xFFFFFFFFu)
                       ? web_count(tree, own_object, next_tree, linked_object, edge_near_start, edge_nearby,
                                   edge_later_near_start, edge_later_nearby, edge_seen, edge_mark) : 0ULL;
        }
        const unsigned int own_unified = unified_of[index.node_offset[tree_index_of_time[from[0]]] + own_object];
        const unsigned int truth_unified = (truth_leaf >= 0)
                                         ? unified_of[index.node_offset[tree_index_of_time[to[0]]] + truth_object]
                                         : 0xFFFFFFFFu;
        const unsigned int unified_links = unified_start[own_unified + 1u] - unified_start[own_unified];
        unsigned int unified_holds_truth = 0u;
        for (unsigned int link = unified_start[own_unified]; link < unified_start[own_unified + 1u]; link += 1u)
        {
            unified_holds_truth += (unsigned int)((unsigned int)(unified_link[link] & 0xFFFFFFFFULL) == truth_unified);
        }
        fprintf(rules->edges, "%s\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t", sample, from[0],
                EDGE_STATUS_NAMES[status], to[1] - from[1], to[2] - from[2], to[3] - from[3], tree->lag_to_next[0],
                tree->lag_to_next[1], tree->lag_to_next[2], carried[0], carried[1], carried[2], tree->sizes[leaf],
                (tree->forward != NULL) ? 1u : 0u, held, tree->null_count, null_at_least, null_best);
        for (unsigned int draw = 0u; (tree->null_held != NULL) && (draw < tree->null_count); draw += 1u)
        {
            fprintf(rules->edges, "%s%u", (draw == 0u) ? "" : ",",
                    tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u)) + leaf]);
        }
        const int kept_pool = (rules->pool != NULL) && (tree->pool_start != NULL);
        const unsigned int pool_first = (kept_pool != 0) ? tree->pool_start[own_object] : 0u;
        const unsigned int pool_past = (kept_pool != 0) ? tree->pool_start[own_object + 1u] : 0u;
        for (unsigned int slot = pool_first; slot < pool_past; slot += 1u)
        {
            const unsigned int candidate = tree->pool_target[slot];
            unsigned int candidate_voxels = 0u;
            for (unsigned int member = next_tree->member_start[candidate];
                 member < next_tree->member_start[candidate + 1u]; member += 1u)
            {
                candidate_voxels += next_tree->sizes[next_tree->members[member]];
            }
            unsigned int linked = 0u;
            for (unsigned int link = tree->link_start[own_object]; link < tree->link_start[own_object + 1u];
                 link += 1u)
            {
                linked += (unsigned int)(tree->link_target[link] == candidate);
            }
            fprintf(rules->pool, "%s\t%d\t%s\t%u\t%u\t%u\t%u\t%u\t%llu\t%llu\t%u\t%u\t%llu\t%u\n", sample, from[0],
                    EDGE_STATUS_NAMES[status], own_object, candidate, (unsigned int)(candidate == truth_object),
                    linked, tree->pool_weight[slot], tree->pool_cost[slot] >> LINK_MAGNITUDE_BITS,
                    tree->pool_cost[slot] & LINK_MAGNITUDE_MASK, candidate_voxels,
                    next_tree->member_start[candidate + 1u] - next_tree->member_start[candidate],
                    (unsigned long long)tree->sizes[leaf], members);
        }
        const TreeFrame *const beyond = ((tree_index_of_time[from[0]] + 2u) < frame_count)
                                      ? &frames[tree_index_of_time[from[0]] + 2u] : NULL;
        const int arm_leaf = ((tree->arm_forward != NULL) && (tree->arm_count != 0u))
                           ? tree->arm_forward[leaf] : CLIMB_MACHINE_NO_LEAF;
        const unsigned int arm_object = ((arm_leaf >= 0) && (beyond != NULL))
                                      ? beyond->object_of[(unsigned int)arm_leaf] : 0xFFFFFFFFu;
        unsigned int truth_onward = 0xFFFFFFFFu;
        for (unsigned int link = 0u; (truth_leaf >= 0) && (next_tree->link_start != NULL) && (beyond != NULL)
             && (link < (next_tree->link_start[truth_object + 1u] - next_tree->link_start[truth_object])); link += 1u)
        {
            truth_onward = next_tree->link_target[next_tree->link_start[truth_object] + link];
        }
        unsigned int linked_onward = 0xFFFFFFFFu;
        for (unsigned int link = 0u; (linked_object != 0xFFFFFFFFu) && (next_tree->link_start != NULL)
             && (beyond != NULL)
             && (link < (next_tree->link_start[linked_object + 1u] - next_tree->link_start[linked_object]));
             link += 1u)
        {
            linked_onward = next_tree->link_target[next_tree->link_start[linked_object] + link];
        }
        fprintf(rules->edges, "\t%u\t%u\t%u", arm_object, truth_onward, linked_onward);
        fprintf(rules->edges, "\t%d\t%d\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%llu\t%llu\t%llu\t%llu\n", truth_leaf,
                chosen_leaf, best_leaf, truth_shared, chosen_shared, best_shared, truth_mutual, one_object,
                object_links, object_links_truth, unified_links, unified_holds_truth, members, truth_weight,
                linked_weight, truth_web, linked_web);
    }
    good = good && ((rules->nodes == NULL) || assign_bodies(frames, frame_count, (unsigned int)rules->mass_band));
    for (unsigned int frame = 0u; (good != 0) && (rules->nodes != NULL) && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        const size_t plane = (size_t)buffers.height * buffers.width;
        for (unsigned int leaf = 0u; (tree->peaks != NULL) && (leaf < tree->leaf_count); leaf += 1u)
        {
            const unsigned int peak = tree->peaks[leaf];
            unsigned long long departure = 0ull;
            for (unsigned int axis = 0u; (tree->forward_lag != NULL) && (axis < 3u); axis += 1u)
            {
                const long long apart = (long long)tree->forward_lag[(3u * leaf) + axis]
                                      - (long long)tree->lag_to_next[axis];
                departure += (unsigned long long)(apart * apart) * (unsigned long long)AXIS_WEIGHTS[axis];
            }
            const unsigned int object = tree->object_of[leaf];
            const unsigned int object_links = (tree->link_start != NULL)
                                            ? (tree->link_start[object + 1u] - tree->link_start[object]) : 0u;
            const int object_link = ((tree->link_start != NULL) && (object_links != 0u))
                                  ? (int)tree->link_target[tree->link_start[object]] : -1;
            const unsigned int held_here = (tree->forward_held != NULL) ? tree->forward_held[leaf] : 0u;
            unsigned int null_at_least = 0u;
            unsigned int null_best = 0u;
            for (unsigned int draw = 0u; (tree->null_held != NULL) && (draw < tree->null_count); draw += 1u)
            {
                const unsigned int drawn = tree->null_held[((size_t)draw * ((size_t)tree->leaf_count + 1u))
                                                           + leaf];
                null_at_least += (unsigned int)(drawn >= held_here);
                null_best = (drawn > null_best) ? drawn : null_best;
            }
            fprintf(rules->nodes, "%s\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%d\t%llu\t%u\t%d\t%u\t%u\t%u\t%u\t%d\t%u\t%d",
                    sample, tree->time, leaf,
                    (unsigned int)(peak / plane), (unsigned int)((peak % plane) / buffers.width),
                    (unsigned int)((peak % plane) % buffers.width), tree->sizes[leaf], object,
                    (tree->member_start != NULL)
                    ? (tree->member_start[object + 1u] - tree->member_start[object]) : 0u,
                    (tree->forward != NULL) ? tree->forward[leaf] : -1,
                    departure, (tree->forward_held != NULL) ? tree->forward_held[leaf] : 0u,
                    object_link, object_links, tree->null_count, null_at_least, null_best,
                    (tree->held_target != NULL) ? (int)tree->held_target[leaf] : -1,
                    (tree->held_rounds != NULL) ? tree->held_rounds[leaf] : 0u,
                    (tree->backward != NULL) ? tree->backward[leaf] : -1);
            fprintf(rules->nodes, "\t%u\t%u\t%d\t%u", tree->body_id[leaf], tree->body_state[leaf],
                    (tree->body_parent[leaf] == BODY_NONE) ? -1 : (int)tree->body_parent[leaf],
                    (tree->touches != NULL) ? tree->touches[leaf] : 0u);
            const int split_from = (((tree->body_state[leaf] & BODY_SPLIT) != 0u) && (tree->backward != NULL))
                                 ? tree->backward[leaf] : -1;
            fprintf(rules->nodes, "\t%d\n", split_from);
        }
    }
    if (good && (object || (rules->coherence != NULL) || (rules->vis_index != NULL) || (rules->export_directory != NULL)))
    {
        CoherenceInputs inputs;
        memset(&inputs, 0, sizeof(inputs));
        inputs.sample = sample;
        inputs.volume = volume;
        inputs.key = &key;
        inputs.frames = frames;
        inputs.frame_count = frame_count;
        inputs.node_offset = index.node_offset;
        inputs.unified_of = unified_of;
        inputs.unified_count = unified_count;
        inputs.node_leaf = node_leaf;
        inputs.tree_index_of_time = tree_index_of_time;
        inputs.volume_frames = volume_frames;
        inputs.edge_status = edge_status;
        inputs.unified_start = unified_start;
        inputs.unified_link = unified_link;
        inputs.vis_directory = rules->vis_directory;
        inputs.vis_index = rules->vis_index;
        inputs.unified_first = unified_first;
        if ((rules->coherence != NULL) || (rules->vis_index != NULL))
        {
            good = read_coherence(&buffers, &inputs, rules->coherence);
        }
        if ((good != 0) && (rules->export_directory != NULL))
        {
            good = export_room(&buffers, &inputs, rules->export_directory);
        }
        if (good && object)
        {
            object_first_run[frame_count] = (unsigned int)object_run_count;
            good = export_object(&buffers, &inputs, object_runs, object_first_run, object_leaf_runs, rules);
        }
    }
    free(object_cut);
    free(object_runs);
    free(object_leaf_runs);
    free(object_first_run);
    free(object_leaf_code);
    const unsigned long long finished = engine_clock_microseconds() / 1000ull;
    unsigned int object_total = 0u;
    unsigned int leaf_total = 0u;
    unsigned int largest_object = 0u;
    for (unsigned int frame = 0u; (good != 0) && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &frames[frame];
        object_total += tree->object_count;
        leaf_total += tree->leaf_count;
        for (unsigned int object = 0u; (tree->member_start != NULL) && (object < tree->object_count); object += 1u)
        {
            const unsigned int members = tree->member_start[object + 1u] - tree->member_start[object];
            largest_object = (members > largest_object) ? members : largest_object;
        }
    }
    if (good != 0)
    {
        const unsigned long long scored = tally->correct + tally->branched + tally->wrong + tally->unlinked
                                        + tally->missed;
        printf("  %-24.24s %-6llu %llu/%llu/%llu/%llu/%llu   %u frames, %u objects of %u leaves, largest %u,"
               " rejoined %u, engines %llu ms"
               " (read %llu, bodies %llu, store %llu, ties %llu, motion %llu, landing %llu, overlap %llu,"
               " climb %llu), tree %llu ms\n",
               sample, scored, tally->correct, tally->branched, tally->wrong, tally->unlinked, tally->missed,
               frame_count, object_total, leaf_total, largest_object,
               rejoined, engines_done - started, clocks.read / 1000ULL, clocks.bodies / 1000ULL,
               clocks.store / 1000ULL, clocks.ties / 1000ULL, clocks.motion / 1000ULL, clocks.landing / 1000ULL,
               clocks.overlap / 1000ULL, clocks.climb / 1000ULL, finished - engines_done);
        fflush(stdout);
        FILE *const log = log_open();
        if (log != NULL)
        {
            char when[32];
            log_when(when, sizeof(when));
            fprintf(log, "%s\tsample\t%s\t%s\t%u\t%u\t%u\t%u\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu"
                         "\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu"
                         "\t%llu\t%llu\t%llu\t%u\t%llu\t%llu\t%llu\n",
                    when, log_rules(), sample, frame_count, object_total, leaf_total, largest_object, rejoined,
                    scored, tally->correct, tally->branched, tally->wrong, tally->unlinked, tally->missed,
                    clocks.read / 1000ULL, clocks.bodies / 1000ULL, clocks.store / 1000ULL, clocks.ties / 1000ULL,
                    clocks.motion / 1000ULL, clocks.landing / 1000ULL, clocks.overlap / 1000ULL,
                    clocks.climb / 1000ULL, engines_done - started, finished - engines_done,
                    g_web_asked - s_web_logged[0], g_web_moved - s_web_logged[1],
                    g_web_capped - s_web_logged[2], WEB_MEMBERS,
                    g_damp_leaves - s_web_logged[3], g_damp_landings - s_web_logged[4],
                    (unsigned long long)DAMP_DEVIATIONS);
            fclose(log);
            s_web_logged[0] = g_web_asked;
            s_web_logged[1] = g_web_moved;
            s_web_logged[2] = g_web_capped;
            s_web_logged[3] = g_damp_leaves;
            s_web_logged[4] = g_damp_landings;
        }
    }

    free(edge_status);
    free(unified_first);
    free(successors);
    free(unified_start);
    free(unified_link);
    free(rank_of_root);
    free(unified_of);
    free(parent);
    free(index.node_frame);
    free(index.node_offset);
    for (unsigned int frame = 0u; (frames != NULL) && (frame < frame_count); frame += 1u)
    {
        TreeFrame *const tree = &frames[frame];
        free(tree->peaks);
        free(tree->sizes);
        free(tree->sums);
        free(tree->moments);
        free(tree->exposed);
        free(tree->touches);
        free(tree->body_id);
        free(tree->body_parent);
        free(tree->body_state);
        free(tree->contact_faces);
        free(tree->extents);
        free(tree->joined);
        free(tree->forward);
        free(tree->forward_lag);
        free(tree->backward_lag);
        free(tree->check_forward_lag);
        free(tree->check_backward_lag);
        free(tree->forward_held);
        free(tree->null_held);
        free(tree->arm_forward);
        free(tree->backward);
        free(tree->triple_start);
        free(tree->triple_after);
        free(tree->triple_shared);
        free(tree->triple_still);
        free(tree->pool_start);
        free(tree->pool_target);
        free(tree->pool_weight);
        free(tree->pool_cost);
        free(tree->object_of);
        free(tree->member_start);
        free(tree->members);
        free(tree->link_start);
        free(tree->link_target);
    }
    free(frames);
    free(node_leaf);
    free(tree_index_of_time);
    free(reached);
    free(volume);
    free(buffers.volume);
    free(buffers.peak_indices);
    free(buffers.sizes);
    free(buffers.sums);
    free(buffers.peak_limbs);
    free(buffers.bodies);
    free(buffers.adjacency);
    free(buffers.joined);
    free(buffers.overlap_before);
    free(buffers.overlap_after);
    free(buffers.overlap_shared);
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        free(buffers.labels[slot]);
        free(buffers.positive[slot]);
        free(buffers.leaf_at_peak[slot]);
        free(buffers.leaf_start[slot]);
        free(buffers.leaf_voxels[slot]);
    }
    climb_machine_close(buffers.machine);
    release_answer_key(&key);
    return good;
}
