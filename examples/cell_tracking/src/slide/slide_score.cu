// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "max_tree.h"

typedef struct
{
    unsigned int present;
    unsigned int alone;
} ScoreSlidePresence;

static ScoreSlidePresence score_slide_tally(const unsigned int *partition, unsigned int keys,
                                            unsigned char *ever_alone)
{
    ScoreSlidePresence presence = {0u, 0u};
    for (unsigned int key = 0u; key < keys; key += 1u)
    {
        unsigned int sharers = 0u;
        for (unsigned int other = 0u; other < keys; other += 1u)
        {
            sharers += (partition[other] == partition[key]) ? 1u : 0u;
        }
        const unsigned int present = (partition[key] != MAX_TREE_ABSENT) ? 1u : 0u;
        const unsigned int alone = present * ((sharers == 1u) ? 1u : 0u);
        presence.present += present;
        presence.alone += alone;
        if (ever_alone != NULL)
        {
            // alone is 0 or 1, so it narrows to unsigned char exactly
            ever_alone[key] |= (unsigned char)alone;
        }
    }
    return presence;
}

typedef struct
{
    unsigned int frames;
    unsigned int keys;
    unsigned int present_at_cut;
    unsigned int alone_at_cut;
    unsigned int separable;
    unsigned int best_alone;
    unsigned long long labelings;
} ScoreSlideTally;

typedef struct
{
    unsigned int *levels;
    unsigned int count;
} ScoreSlideLevels;

static int score_slide_frame(const AnswerKey *key, unsigned int time, const EngineBuffers *buffers,
                             ScoreSlideTally *tally, ScoreSlideLevels *kept)
{
    kept->levels = NULL;
    kept->count = 0u;
    unsigned int *const key_voxels = (unsigned int *)malloc(((size_t)key->node_count + 1u) * sizeof(unsigned int));
    unsigned int keys = 0u;
    for (unsigned int node = 0u; (key_voxels != NULL) && (node < key->node_count); node += 1u)
    {
        const int *const place = &key->node_coordinates[(size_t)node * 4u];
        // the time re-signs to unsigned int only after it is checked non-negative
        if ((place[0] < 0) || ((unsigned int)place[0] != time))
        {
            continue;
        }
        // the key holds every place on the grid, so each coordinate is non-negative and re-signs to unsigned int exactly
        key_voxels[keys] = ((((unsigned int)place[1] * buffers->height) + (unsigned int)place[2]) * buffers->width)
                         + (unsigned int)place[3];
        keys += 1u;
    }
    if ((key_voxels == NULL) || (keys == 0u))
    {
        free(key_voxels);
        return (key_voxels != NULL) ? 1 : 0;
    }
    const unsigned int step_room = (2u * keys) + 2u;
    MaxTreeSlideStep *const steps = (MaxTreeSlideStep *)malloc((size_t)step_room * sizeof(MaxTreeSlideStep));
    unsigned int *const partitions = (unsigned int *)malloc((size_t)step_room * keys * sizeof(unsigned int));
    unsigned char *const ever_alone = (unsigned char *)calloc(keys, 1u);
    unsigned int step_count = 0u;
    unsigned int top = 0u;
    unsigned int cut = 0u;
    unsigned int labelings = 0u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const MaxTreeSlideRequest request = {.probe_voxels = key_voxels,
                                         .probe_count = keys,
                                         .steps = steps,
                                         .partitions = partitions,
                                         .step_room = step_room,
                                         .step_count = &step_count,
                                         .top_level = &top,
                                         .cut_level = &cut,
                                         .labelings = &labelings,
                                         .error = &error};
    const int steps_succeeded = (steps != NULL) && (partitions != NULL) && (ever_alone != NULL)
                             && (max_tree_slide(&request) == 0L);
    if ((steps != NULL) && (partitions != NULL) && (ever_alone != NULL) && !steps_succeeded)
    {
        track_error_report("slide", &error);
    }
    unsigned int present_at_cut = 0u;
    unsigned int alone_at_cut = 0u;
    unsigned int best_alone = 0u;
    for (unsigned int step = 0u; steps_succeeded && (step < step_count); step += 1u)
    {
        const ScoreSlidePresence presence = score_slide_tally(&partitions[(size_t)step * keys], keys, ever_alone);
        present_at_cut = (steps[step].level >= cut) ? presence.present : present_at_cut;
        alone_at_cut = (steps[step].level >= cut) ? presence.alone : alone_at_cut;
        best_alone = (presence.alone > best_alone) ? presence.alone : best_alone;
    }
    unsigned int separable = 0u;
    for (unsigned int each = 0u; steps_succeeded && (each < keys); each += 1u)
    {
        separable += (unsigned int)ever_alone[each];
    }
    if (steps_succeeded)
    {
        printf("    slide t=%u: %u key cells; the cut at level %u of %u holds %u, %u alone; alone at some level %u, at"
               " the best single level %u; level:components:present:alone", time, keys, cut, top, present_at_cut,
               alone_at_cut, separable, best_alone);
        for (unsigned int step = 0u; step < step_count; step += 1u)
        {
            const ScoreSlidePresence presence = score_slide_tally(&partitions[(size_t)step * keys], keys, NULL);
            printf(" %u:%u:%u:%u", steps[step].level, steps[step].components, presence.present, presence.alone);
        }
        printf("\n");
        tally->frames += 1u;
        tally->keys += keys;
        tally->present_at_cut += present_at_cut;
        tally->alone_at_cut += alone_at_cut;
        tally->separable += separable;
        tally->best_alone += best_alone;
        tally->labelings += labelings;
        kept->levels = (unsigned int *)malloc(((size_t)step_count + 1u) * sizeof(unsigned int));
    }
    for (unsigned int step = 0u; (kept->levels != NULL) && (step < step_count); step += 1u)
    {
        kept->levels[step] = steps[step].level;
    }
    if (kept->levels != NULL)
    {
        kept->levels[step_count] = cut;
        kept->count = step_count + 1u;
    }
    free(key_voxels);
    free(steps);
    free(partitions);
    free(ever_alone);
    return steps_succeeded && (kept->levels != NULL);
}

typedef struct
{
    unsigned int pairs;
    unsigned long long evaluations;
    unsigned long long components_at_cut;
    unsigned long long one_at_cut;
    unsigned long long mutual_at_cut;
    unsigned long long best_mutual;
    unsigned long long disappear_at_cut;
    unsigned long long appear_at_cut;
    unsigned long long divisions_at_cut;
    unsigned long long merges_at_cut;
    unsigned long long key_divisions;
    unsigned long long parted_at_cut;
    unsigned long long caught_at_cut;
    unsigned long long best_parted;
    unsigned long long best_caught;
    unsigned long long best_present;
    unsigned long long best_apart;
    unsigned int mutual_differ;
    unsigned long long chosen_components;
    unsigned long long chosen_later_components;
    unsigned long long chosen_mutual;
    unsigned long long chosen_cells_present;
    unsigned long long chosen_cells_alone;
    unsigned long long chosen_parted;
    unsigned long long chosen_caught;
    unsigned long long cut_cells_present;
    unsigned long long cut_cells_alone;
    unsigned long long key_cells;
} ScoreOverlapTally;

static int score_code_descending(const void *left, const void *right)
{
    const unsigned int one = *(const unsigned int *)left;
    const unsigned int other = *(const unsigned int *)right;
    return (one < other) ? 1 : ((one > other) ? -1 : 0);
}

static int score_peak_levels(const EngineBuffers *buffers, const TreeFrame *frame, ScoreSlideLevels *kept)
{
    kept->count = 0u;
    // leaf_count widens from unsigned int to size_t, so leaf_count + 1 cannot wrap before malloc sees it
    kept->levels = (unsigned int *)malloc(((size_t)frame->leaf_count + 1u) * sizeof(unsigned int));
    MaxTreeSlideStep no_step;
    unsigned int step_count = 0u;
    unsigned int cut = 0u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const MaxTreeSlideRequest request = {.steps = &no_step,
                                         .step_room = 1u,
                                         .step_count = &step_count,
                                         .cut_level = &cut,
                                         .error = &error};
    if ((kept->levels == NULL) || (max_tree_slide(&request) != 0L))
    {
        if (kept->levels != NULL)
        {
            track_error_report("peak levels", &error);
        }
        free(kept->levels);
        kept->levels = NULL;
        return 0;
    }
    for (unsigned int leaf = 0u; leaf < frame->leaf_count; leaf += 1u)
    {
        kept->levels[leaf] = buffers->bodies[leaf].code;
    }
    qsort(kept->levels, frame->leaf_count, sizeof(unsigned int), score_code_descending);
    for (unsigned int leaf = 0u; leaf < frame->leaf_count; leaf += 1u)
    {
        if ((kept->count == 0u) || (kept->levels[kept->count - 1u] != kept->levels[leaf]))
        {
            kept->levels[kept->count] = kept->levels[leaf];
            kept->count += 1u;
        }
    }
    kept->levels[kept->count] = cut;
    kept->count += 1u;
    return 1;
}

typedef struct
{
    const AnswerKey *key;
    const unsigned int *successors;
    unsigned int height;
    unsigned int width;
} ScoreKeyDivisions;

static unsigned int score_key_voxel(const ScoreKeyDivisions *divisions, unsigned int node)
{
    const int *const place = &divisions->key->node_coordinates[(size_t)node * 4u];
    // the key holds every place on the grid, so each coordinate is non-negative and re-signs to unsigned int exactly
    return ((((unsigned int)place[1] * divisions->height) + (unsigned int)place[2]) * divisions->width)
         + (unsigned int)place[3];
}

static unsigned int *score_key_division_voxels(const ScoreKeyDivisions *divisions, unsigned int earlier_time,
                                               unsigned int later_time, unsigned int *count)
{
    const AnswerKey *const key = divisions->key;
    // node_count widens from unsigned int to size_t, so (node_count + 1) * 3 cannot wrap before malloc sees it
    unsigned int *const voxels = (unsigned int *)malloc(((size_t)key->node_count + 1u) * 3u * sizeof(unsigned int));
    *count = 0u;
    for (unsigned int node = 0u; (voxels != NULL) && (node < key->node_count); node += 1u)
    {
        const unsigned int *const successors = &divisions->successors[(size_t)node * 3u];
        const int *const place = &key->node_coordinates[(size_t)node * 4u];
        const int *const one = &key->node_coordinates[(size_t)successors[1] * 4u];
        const int *const other = &key->node_coordinates[(size_t)successors[2] * 4u];
        // each time re-signs to unsigned int only after it is checked non-negative
        const int held = (successors[0] == 2u) && (place[0] >= 0) && ((unsigned int)place[0] == earlier_time)
                      && (one[0] >= 0) && ((unsigned int)one[0] == later_time) && (other[0] >= 0)
                      && ((unsigned int)other[0] == later_time);
        if (held)
        {
            voxels[(3u * *count)] = score_key_voxel(divisions, node);
            voxels[(3u * *count) + 1u] = score_key_voxel(divisions, successors[1]);
            voxels[(3u * *count) + 2u] = score_key_voxel(divisions, successors[2]);
            *count += 1u;
        }
    }
    return voxels;
}

static unsigned int *score_key_cell_voxels(const ScoreKeyDivisions *divisions, unsigned int time, unsigned int *count)
{
    const AnswerKey *const key = divisions->key;
    // node_count widens from unsigned int to size_t, so node_count + 1 cannot wrap before malloc sees it
    unsigned int *const voxels = (unsigned int *)malloc(((size_t)key->node_count + 1u) * sizeof(unsigned int));
    *count = 0u;
    for (unsigned int node = 0u; (voxels != NULL) && (node < key->node_count); node += 1u)
    {
        const int *const place = &key->node_coordinates[(size_t)node * 4u];
        // the time re-signs to unsigned int only after it is checked non-negative
        if ((place[0] >= 0) && ((unsigned int)place[0] == time))
        {
            voxels[*count] = score_key_voxel(divisions, node);
            *count += 1u;
        }
    }
    return voxels;
}

typedef struct
{
    unsigned int key_present;
    unsigned int key_apart;
    unsigned int key_parted;
    unsigned int key_caught;
    unsigned int key_cells_present;
    unsigned int key_cells_alone;
} ScoreOverlapGrade;

static ScoreOverlapGrade score_overlap_grade(const MaxTreeOverlapProbe *probes, const unsigned char *links_held,
                                             unsigned int key_divisions, unsigned int key_cells)
{
    ScoreOverlapGrade grade = {0u, 0u, 0u, 0u, 0u, 0u};
    const MaxTreeOverlapProbe *const parents = probes;
    const MaxTreeOverlapProbe *const cells = &probes[key_divisions];
    const MaxTreeOverlapProbe *const daughters = &probes[key_divisions + key_cells];
    for (unsigned int division = 0u; division < key_divisions; division += 1u)
    {
        const MaxTreeOverlapProbe *const parent = &parents[division];
        const MaxTreeOverlapProbe *const one = &daughters[division];
        const MaxTreeOverlapProbe *const other = &daughters[key_divisions + division];
        const unsigned int present = (unsigned int)((parent->root != MAX_TREE_ABSENT) && (one->root != MAX_TREE_ABSENT)
                                                    && (other->root != MAX_TREE_ABSENT));
        const unsigned int apart = present & (unsigned int)(one->root != other->root);
        const unsigned int parted = apart & (unsigned int)(links_held[2u * division] != 0u)
                                  & (unsigned int)(links_held[(2u * division) + 1u] != 0u);
        const unsigned int caught = parted & (unsigned int)((parent->degree == 2u) && (parent->backs == 2u));
        grade.key_present += present;
        grade.key_apart += apart;
        grade.key_parted += parted;
        grade.key_caught += caught;
    }
    for (unsigned int cell = 0u; cell < key_cells; cell += 1u)
    {
        unsigned int sharers = 0u;
        for (unsigned int other = 0u; other < key_cells; other += 1u)
        {
            sharers += (cells[other].root == cells[cell].root) ? 1u : 0u;
        }
        const unsigned int present = (unsigned int)(cells[cell].root != MAX_TREE_ABSENT);
        grade.key_cells_present += present;
        grade.key_cells_alone += present * (unsigned int)(sharers == 1u);
    }
    return grade;
}

static int score_overlap_pair(const TreeFrame *earlier, const TreeFrame *later, const ScoreSlideLevels *earlier_levels,
                              const ScoreSlideLevels *later_levels, const ScoreKeyDivisions *divisions,
                              int every_step, ScoreOverlapTally *tally)
{
    unsigned int key_divisions = 0u;
    unsigned int key_cells = 0u;
    unsigned int *const division_voxels = score_key_division_voxels(divisions, earlier->time, later->time,
                                                                    &key_divisions);
    unsigned int *const key_cell_voxels = score_key_cell_voxels(divisions, earlier->time, &key_cells);
    const unsigned int step_room = earlier_levels->count + later_levels->count;
    if ((division_voxels == NULL) || (key_cell_voxels == NULL) || (step_room == 0u))
    {
        free(division_voxels);
        free(key_cell_voxels);
        return (division_voxels != NULL) && (key_cell_voxels != NULL);
    }
    const unsigned int earlier_probes = key_divisions + key_cells;
    const unsigned int later_probes = 2u * key_divisions;
    const size_t probes_a_step = (size_t)earlier_probes + later_probes;
    const unsigned int link_count = 2u * key_divisions;
    unsigned int *const earlier_voxels = (unsigned int *)malloc(((size_t)earlier_probes + 1u) * sizeof(unsigned int));
    unsigned int *const later_voxels = (unsigned int *)malloc(((size_t)later_probes + 1u) * sizeof(unsigned int));
    unsigned int *const links = (unsigned int *)malloc(((size_t)link_count + 1u) * 2u * sizeof(unsigned int));
    MaxTreeOverlapStep *const steps = (MaxTreeOverlapStep *)malloc((size_t)step_room * sizeof(MaxTreeOverlapStep));
    MaxTreeOverlapProbe *const probes
        = (MaxTreeOverlapProbe *)malloc(((size_t)step_room * probes_a_step + 1u) * sizeof(MaxTreeOverlapProbe));
    unsigned char *const links_held = (unsigned char *)malloc(((size_t)step_room * link_count) + 1u);
    const int buffers_held = (earlier_voxels != NULL) && (later_voxels != NULL) && (links != NULL) && (steps != NULL)
                          && (probes != NULL) && (links_held != NULL);
    for (unsigned int division = 0u; buffers_held && (division < key_divisions); division += 1u)
    {
        earlier_voxels[division] = division_voxels[3u * division];
        later_voxels[division] = division_voxels[(3u * division) + 1u];
        later_voxels[key_divisions + division] = division_voxels[(3u * division) + 2u];
        links[4u * division] = division;
        links[(4u * division) + 1u] = division;
        links[(4u * division) + 2u] = division;
        links[(4u * division) + 3u] = key_divisions + division;
    }
    for (unsigned int cell = 0u; buffers_held && (cell < key_cells); cell += 1u)
    {
        earlier_voxels[key_divisions + cell] = key_cell_voxels[cell];
    }
    unsigned int step_count = 0u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    MaxTreeOverlapRequest request;
    memset(&request, 0, sizeof(request));
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        request.lag[axis] = earlier->lag_to_next[axis];
    }
    request.earlier_levels = earlier_levels->levels;
    request.earlier_level_count = earlier_levels->count;
    request.later_levels = later_levels->levels;
    request.later_level_count = later_levels->count;
    request.probe_voxels[0] = earlier_voxels;
    request.probe_counts[0] = earlier_probes;
    request.probe_voxels[1] = later_voxels;
    request.probe_counts[1] = later_probes;
    request.probe_links = links;
    request.link_count = link_count;
    request.probes = probes;
    request.links_held = links_held;
    request.steps = steps;
    request.step_room = step_room;
    request.step_count = &step_count;
    request.error = &error;
    const int steps_succeeded = buffers_held && (max_tree_overlap(&request) == 0L);
    if (buffers_held && !steps_succeeded)
    {
        track_error_report("overlap", &error);
    }
    if (steps_succeeded && every_step)
    {
        printf("    overlap t=%u->%u at the drift %d,%d,%d, %u key divisions; origin:level:earlier code:later code:earlier"
               " components:later components:earlier one:later one:mutual:disappear:appear:divisions:merges:key"
               " present:key apart:key parted:key caught", earlier->time, later->time, request.lag[0], request.lag[1],
               request.lag[2], key_divisions);
        for (unsigned int step = 0u; step < step_count; step += 1u)
        {
            const MaxTreeOverlapStep *const at = &steps[step];
            const ScoreOverlapGrade grade = score_overlap_grade(&probes[step * probes_a_step],
                                                                &links_held[(size_t)step * link_count], key_divisions,
                                                                key_cells);
            printf(" %u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u:%u", at->origin, at->level, at->earlier_code,
                   at->later_code, at->earlier_components, at->later_components, at->earlier_one, at->later_one,
                   at->earlier_mutual, at->earlier_unpaired, at->later_unpaired, at->earlier_forked, at->later_forked,
                   grade.key_present, grade.key_apart, grade.key_parted, grade.key_caught);
        }
        printf("\n");
    }
    if (steps_succeeded)
    {
        unsigned int best_mutual = 0u;
        unsigned int best_parted = 0u;
        unsigned int best_caught = 0u;
        unsigned int best_present = 0u;
        unsigned int best_apart = 0u;
        unsigned int chosen = 0u;
        for (unsigned int step = 0u; step < step_count; step += 1u)
        {
            const MaxTreeOverlapStep *const at = &steps[step];
            const ScoreOverlapGrade grade = score_overlap_grade(&probes[step * probes_a_step],
                                                                &links_held[(size_t)step * link_count], key_divisions,
                                                                key_cells);
            chosen = (at->earlier_mutual > steps[chosen].earlier_mutual) ? step : chosen;
            best_present = (grade.key_present > best_present) ? grade.key_present : best_present;
            best_apart = (grade.key_apart > best_apart) ? grade.key_apart : best_apart;
            best_mutual = (at->earlier_mutual > best_mutual) ? at->earlier_mutual : best_mutual;
            best_parted = (grade.key_parted > best_parted) ? grade.key_parted : best_parted;
            best_caught = (grade.key_caught > best_caught) ? grade.key_caught : best_caught;
            tally->mutual_differ += (at->earlier_mutual != at->later_mutual) ? 1u : 0u;
        }
        const MaxTreeOverlapStep *const pick = &steps[chosen];
        const ScoreOverlapGrade picked = score_overlap_grade(&probes[chosen * probes_a_step],
                                                             &links_held[(size_t)chosen * link_count], key_divisions,
                                                             key_cells);
        printf("    most mutual t=%u->%u: origin %u level %u, codes %u/%u, %u/%u components, %u mutual, %u of %u key cells"
               " present and %u alone, %u of %u key divisions parted and %u caught\n", earlier->time, later->time,
               pick->origin, pick->level, pick->earlier_code, pick->later_code, pick->earlier_components,
               pick->later_components, pick->earlier_mutual, picked.key_cells_present, key_cells,
               picked.key_cells_alone, picked.key_parted, key_divisions, picked.key_caught);
        tally->chosen_components += pick->earlier_components;
        tally->chosen_later_components += pick->later_components;
        tally->chosen_mutual += pick->earlier_mutual;
        tally->chosen_cells_present += picked.key_cells_present;
        tally->chosen_cells_alone += picked.key_cells_alone;
        tally->chosen_parted += picked.key_parted;
        tally->chosen_caught += picked.key_caught;
        tally->key_cells += key_cells;
        tally->pairs += 1u;
        tally->evaluations += step_count;
        tally->best_mutual += best_mutual;
        tally->key_divisions += key_divisions;
        tally->best_parted += best_parted;
        tally->best_caught += best_caught;
        tally->best_present += best_present;
        tally->best_apart += best_apart;
        if (earlier_levels->count != 0u)
        {
            const unsigned int cut_step = earlier_levels->count - 1u;
            const MaxTreeOverlapStep *const cut = &steps[cut_step];
            const ScoreOverlapGrade at_cut = score_overlap_grade(&probes[cut_step * probes_a_step],
                                                                 &links_held[(size_t)cut_step * link_count],
                                                                 key_divisions, key_cells);
            tally->components_at_cut += cut->earlier_components;
            tally->one_at_cut += cut->earlier_one;
            tally->mutual_at_cut += cut->earlier_mutual;
            tally->disappear_at_cut += cut->earlier_unpaired;
            tally->appear_at_cut += cut->later_unpaired;
            tally->divisions_at_cut += cut->earlier_forked;
            tally->merges_at_cut += cut->later_forked;
            tally->parted_at_cut += at_cut.key_parted;
            tally->caught_at_cut += at_cut.key_caught;
            tally->cut_cells_present += at_cut.key_cells_present;
            tally->cut_cells_alone += at_cut.key_cells_alone;
        }
    }
    free(earlier_voxels);
    free(later_voxels);
    free(links);
    free(steps);
    free(probes);
    free(links_held);
    free(division_voxels);
    free(key_cell_voxels);
    return steps_succeeded;
}

    ScoreSlideTally slide;
    memset(&slide, 0, sizeof(slide));
    ScoreSlideLevels slide_levels[2];
    memset(slide_levels, 0, sizeof(slide_levels));
    ScoreOverlapTally overlap;
    memset(&overlap, 0, sizeof(overlap));
    good = good && ((rules->overlap == 0) || (max_tree_keep_frames() != 0));
    unsigned int *const key_successors = (rules->overlap != 0) ? score_key_successors(&key) : NULL;
    good = good && ((rules->overlap == 0) || (key_successors != NULL));
    const ScoreKeyDivisions key_divisions = {&key, key_successors, buffers.height, buffers.width};

        free(slide_levels[1].levels);
        slide_levels[1].levels = NULL;
        slide_levels[1].count = 0u;
        good = (good != 0)
            && ((rules->slide == 0)
                || (score_slide_frame(&key, frames[frame].time, &buffers, &slide, &slide_levels[1]) != 0));
        good = (good != 0)
            && ((rules->overlap != 2) || (score_peak_levels(&buffers, &frames[frame], &slide_levels[1]) != 0));

            good = (good != 0)
                && ((rules->overlap == 0)
                    || (score_overlap_pair(&frames[frame - 1u], &frames[frame], &slide_levels[0], &slide_levels[1],
                                           &key_divisions, rules->overlap == 1, &overlap) != 0));

        free(slide_levels[0].levels);
        slide_levels[0] = slide_levels[1];
        slide_levels[1].levels = NULL;
        slide_levels[1].count = 0u;

    if ((good != 0) && (rules->slide != 0))
    {
        printf("  %s: the slide, %u frames with key cells, %u key cells: the cut holds %u, %u of them alone; alone at"
               " some level %u; at each frame's best single level %u; %llu labelings, each proved against the tree's"
               " count\n", sample, slide.frames, slide.keys, slide.present_at_cut, slide.alone_at_cut, slide.separable,
               slide.best_alone, slide.labelings);
    }
    if ((good != 0) && (rules->overlap != 0))
    {
        printf("  %s: the overlap at the same residual, %u frame pairs, %llu cuts: at the earlier frame's cut %llu"
               " components, %llu of them overlap exactly one, %llu mutual; the best mutual over each pair's cuts %llu;"
               " %u cuts where mutual counted from the later side differs\n",
               sample, overlap.pairs, overlap.evaluations, overlap.components_at_cut, overlap.one_at_cut,
               overlap.mutual_at_cut, overlap.best_mutual, overlap.mutual_differ);
        printf("  %s: the event census at the earlier frame's cut: %llu moves (1->1), %llu divisions (1->2), %llu merges"
               " (2->1), %llu disappear (1->0), %llu appear (0->1); the key holds %llu divisions over these pairs: at the"
               " cut %llu parted (the parent's component overlaps the two daughters' distinct components), %llu caught"
               " (and it is 1->2); at each pair's best sampled cut %llu present (parent and both daughters above the"
               " cut), %llu apart (the daughters in two components), %llu parted, %llu caught\n",
               sample, overlap.mutual_at_cut, overlap.divisions_at_cut, overlap.merges_at_cut, overlap.disappear_at_cut,
               overlap.appear_at_cut, overlap.key_divisions, overlap.parted_at_cut, overlap.caught_at_cut,
               overlap.best_present, overlap.best_apart, overlap.best_parted, overlap.best_caught);
        printf("  %s: at each pair's most-mutual cut (the first sampled cut with the most mutual): %llu earlier and %llu"
               " later components, %llu mutual; %llu of %llu key cells present, %llu alone (at the most-components cut:"
               " %llu present, %llu alone); %llu of %llu key divisions parted, %llu caught\n", sample,
               overlap.chosen_components, overlap.chosen_later_components, overlap.chosen_mutual,
               overlap.chosen_cells_present, overlap.key_cells, overlap.chosen_cells_alone, overlap.cut_cells_present,
               overlap.cut_cells_alone, overlap.chosen_parted, overlap.key_divisions, overlap.chosen_caught);
    }
    free(slide_levels[0].levels);
    free(slide_levels[1].levels);
    free(key_successors);

    int slide;
    int overlap;

        else if (strcmp(flag, "--slide") == 0)
        {
            rules.slide = 1;
        }
        else if (strcmp(flag, "--overlap") == 0)
        {
            rules.slide = 1;
            rules.overlap = 1;
        }
        else if (strcmp(flag, "--overlap-peaks") == 0)
        {
            rules.overlap = 2;
        }
