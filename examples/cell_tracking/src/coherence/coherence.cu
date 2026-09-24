// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "coherence.h"

#include "answer_key.h"
#include "track.h"
#include "vis_png.h"
#include "radix_keys.h"
#include "shift_agreement.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void links_of_node(const NodeIndex *index, unsigned int node, const unsigned int **first, unsigned int *count)
{
    const unsigned int frame = index->node_frame[node];
    const TreeFrame *const tree = &index->frames[frame];
    if (tree->link_start == NULL)
    {
        *first = NULL;
        *count = 0u;
        return;
    }
    const unsigned int object = node - index->node_offset[frame];
    *first = &tree->link_target[tree->link_start[object]];
    *count = tree->link_start[object + 1u] - tree->link_start[object];
}

static unsigned int frame_of_unified(const CoherenceInputs *inputs, unsigned int unified)
{
    unsigned int low = 0u;
    unsigned int high = inputs->frame_count;
    while (low + 1u < high)
    {
        const unsigned int middle = low + (high - low) / 2u;
        if (inputs->unified_first[middle] <= unified)
        {
            low = middle;
        }
        else
        {
            high = middle;
        }
    }
    return low;
}

int export_room(const EngineBuffers *buffers, const CoherenceInputs *inputs, const char *directory)
{
    char path[ENGINE_PATH_ROOM];
    const int written = snprintf(path, sizeof(path), "%s/%s.room", directory, inputs->sample);
    const size_t unified = inputs->unified_first[inputs->frame_count];
    const unsigned int link_total = inputs->unified_start[unified];
    unsigned long long *const cells = (unsigned long long *)calloc((unified + 1u) * 12u, sizeof(unsigned long long));
    unsigned int *const frame_table = (unsigned int *)calloc(((size_t)inputs->frame_count + 1u) * 12u, sizeof(unsigned int));
    unsigned int *const links = (unsigned int *)malloc(((size_t)link_total + 1u) * 3u * sizeof(unsigned int));
    size_t contact_room = 1u << 16u;
    size_t contact_total = 0u;
    unsigned int *contacts = (unsigned int *)malloc(contact_room * 3u * sizeof(unsigned int));
    int good = (written > 0) && ((size_t)written < sizeof(path)) && (cells != NULL) && (frame_table != NULL)
            && (links != NULL) && (contacts != NULL);

    for (unsigned int frame = 0u; (good != 0) && (frame < inputs->frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &inputs->frames[frame];
        for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
        {
            const unsigned int object = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[leaf]];
            unsigned long long *const cell = &cells[(size_t)object * 12u];
            cell[0] += tree->sizes[leaf];
            cell[1] += tree->sums[(size_t)leaf * 3u];
            cell[2] += tree->sums[(size_t)leaf * 3u + 1u];
            cell[3] += tree->sums[(size_t)leaf * 3u + 2u];
            for (unsigned int moment = 0u; (tree->moments != NULL) && (moment < 6u); moment += 1u)
            {
                cell[4u + moment] += tree->moments[(size_t)leaf * 6u + moment];
            }
            cell[10] += 1u;
            cell[11] += (tree->exposed != NULL) ? tree->exposed[leaf] : 0u;
        }
        unsigned long long *const keys = (unsigned long long *)malloc(((size_t)tree->joined_count + 1u) * sizeof(unsigned long long));
        good = (keys != NULL);
        unsigned int key_count = 0u;
        for (unsigned int pair = 0u; (good != 0) && (tree->contact_faces != NULL) && (pair < tree->joined_count); pair += 1u)
        {
            const unsigned int first = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[tree->joined[2u * pair]]];
            const unsigned int second = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[tree->joined[2u * pair + 1u]]];
            if ((first == second) || (tree->contact_faces[pair] == 0u))
            {
                continue;
            }
            cells[(size_t)first * 12u + 11u] += tree->contact_faces[pair];
            cells[(size_t)second * 12u + 11u] += tree->contact_faces[pair];
            const unsigned int low = ((first < second) ? first : second) - inputs->unified_first[frame];
            const unsigned int high = ((first < second) ? second : first) - inputs->unified_first[frame];
            keys[key_count] = ((unsigned long long)low << 42u) | ((unsigned long long)high << 20u) | tree->contact_faces[pair];
            key_count += 1u;
        }
        good = (good != 0) && radix_sort_keys(keys, key_count);
        frame_table[(size_t)frame * 12u] = tree->time;
        frame_table[(size_t)frame * 12u + 1u] = (tree->forward != NULL) ? 1u : 0u;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            frame_table[(size_t)frame * 12u + 2u + axis] = (unsigned int)tree->lag_to_next[axis];
        }
        frame_table[(size_t)frame * 12u + 5u] = inputs->unified_first[frame];
        frame_table[(size_t)frame * 12u + 6u] = inputs->unified_first[frame + 1u] - inputs->unified_first[frame];
        frame_table[(size_t)frame * 12u + 9u] = (unsigned int)contact_total;
        for (unsigned int at = 0u; (good != 0) && (at < key_count);)
        {
            const unsigned long long pair = keys[at] >> 20u;
            unsigned long long faces = 0ULL;
            while ((at < key_count) && ((keys[at] >> 20u) == pair))
            {
                faces += keys[at] & 0xFFFFFULL;
                at += 1u;
            }
            if (contact_total == contact_room)
            {
                contact_room *= 2u;
                unsigned int *const grown = (unsigned int *)realloc(contacts, contact_room * 3u * sizeof(unsigned int));
                if (grown == NULL)
                {
                    good = 0;
                    break;
                }
                contacts = grown;
            }
            contacts[contact_total * 3u] = (unsigned int)(pair >> 22u);
            contacts[contact_total * 3u + 1u] = (unsigned int)(pair & 0x3FFFFFULL);
            contacts[contact_total * 3u + 2u] = (unsigned int)faces;
            contact_total += 1u;
        }
        frame_table[(size_t)frame * 12u + 10u] = (unsigned int)contact_total - frame_table[(size_t)frame * 12u + 9u];
        free(keys);
    }
    for (unsigned int link = 0u; (good != 0) && (link < link_total); link += 1u)
    {
        const unsigned int source = (unsigned int)(inputs->unified_link[link] >> 32u);
        const unsigned int child = (unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL);
        const unsigned int frame = frame_of_unified(inputs, source);
        links[3u * link] = frame;
        links[3u * link + 1u] = source - inputs->unified_first[frame];
        links[3u * link + 2u] = child - inputs->unified_first[frame + 1u];
        if (frame_table[(size_t)frame * 12u + 8u] == 0u)
        {
            frame_table[(size_t)frame * 12u + 7u] = link;
        }
        frame_table[(size_t)frame * 12u + 8u] += 1u;
    }

    unsigned int edge_total = 0u;
    for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
    {
        edge_total += (inputs->edge_status[edge] >= 0) ? 1u : 0u;
    }
    FILE *const out = (good != 0) ? fopen(path, "wb") : NULL;
    good = (out != NULL);
    if (good != 0)
    {
        const unsigned int header[12] = {0x31525443u, 1u, inputs->frame_count, buffers->depth, buffers->height,
                                         buffers->width, (unsigned int)unified, link_total, (unsigned int)contact_total,
                                         inputs->key->node_count, edge_total, 0u};
        fwrite(header, sizeof(unsigned int), 12u, out);
        fwrite(frame_table, sizeof(unsigned int), (size_t)inputs->frame_count * 12u, out);
        fwrite(cells, sizeof(unsigned long long), unified * 12u, out);
        fwrite(links, sizeof(unsigned int), (size_t)link_total * 3u, out);
        fwrite(contacts, sizeof(unsigned int), contact_total * 3u, out);
        for (unsigned int node = 0u; node < inputs->key->node_count; node += 1u)
        {
            const int *const place = &inputs->key->node_coordinates[(size_t)node * 4u];
            int record[7] = {(int)(inputs->key->node_identity[node] & 0xFFFFFFFFLL), (int)(inputs->key->node_identity[node] >> 32),
                             place[0], place[1], place[2], place[3], -1};
            if ((place[0] >= 0) && ((unsigned int)place[0] < inputs->volume_frames) && (inputs->node_leaf[node] >= 0))
            {
                const int frame = inputs->tree_index_of_time[place[0]];
                if (frame >= 0)
                {
                    const unsigned int id = inputs->unified_of[inputs->node_offset[(unsigned int)frame]
                                                               + inputs->frames[frame].object_of[(unsigned int)inputs->node_leaf[node]]];
                    record[6] = (int)(id - inputs->unified_first[frame]);
                }
            }
            fwrite(record, sizeof(int), 7u, out);
        }
        for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
        {
            const int status = inputs->edge_status[edge];
            if (status < 0)
            {
                continue;
            }
            int record[9] = {(int)node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge]),
                             (int)node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge + 1u]), status, 0, 0, 0, -1, -1, -1};
            if (status != 4)
            {
                const int time = inputs->key->node_coordinates[(size_t)record[0] * 4u];
                const int frame = inputs->tree_index_of_time[time];
                const TreeFrame *const tree = &inputs->frames[frame];
                const unsigned int leaf = (unsigned int)inputs->node_leaf[record[0]];
                const int *const carried = (tree->forward_lag != NULL) ? &tree->forward_lag[3u * leaf] : tree->lag_to_next;
                const unsigned int plane = buffers->height * buffers->width;
                record[3] = carried[0];
                record[4] = carried[1];
                record[5] = carried[2];
                record[6] = (int)(tree->peaks[leaf] / plane);
                record[7] = (int)((tree->peaks[leaf] % plane) / buffers->width);
                record[8] = (int)((tree->peaks[leaf] % plane) % buffers->width);
            }
            fwrite(record, sizeof(int), 9u, out);
        }
        good = (ferror(out) == 0);
        fclose(out);
    }
    free(cells);
    free(frame_table);
    free(links);
    free(contacts);
    return good;
}

static unsigned int object_cell_of_node(const CoherenceInputs *inputs, long node)
{
    const int time = (node >= 0L) ? inputs->key->node_coordinates[(size_t)node * 4u] : -1;
    const bool timed = (time >= 0) && ((unsigned int)time < inputs->volume_frames);
    const int frame = timed ? inputs->tree_index_of_time[time] : -1;
    const bool placed = (frame >= 0) && (inputs->node_leaf[node] >= 0);
    return placed ? inputs->unified_of[inputs->node_offset[(unsigned int)frame]
                                       + inputs->frames[frame].object_of[(unsigned int)inputs->node_leaf[node]]]
                  : 0xFFFFFFFFu;
}

int export_object(const EngineBuffers *buffers, const CoherenceInputs *inputs, const unsigned int *runs,
                         const unsigned int *first_run, const unsigned int *leaf_runs, const TreeRules *rules)
{
    char path[ENGINE_PATH_ROOM];
    const int written = snprintf(path, sizeof(path), "%s/%s.object", rules->object_directory, inputs->sample);
    const unsigned int frame_count = inputs->frame_count;
    const unsigned int cell_count = inputs->unified_first[frame_count];
    const unsigned int link_count = inputs->unified_start[cell_count];
    const unsigned int run_count = first_run[frame_count];
    unsigned int leaf_count = 0u;
    unsigned int edge_count = 0u;
    for (unsigned int frame = 0u; frame < frame_count; frame += 1u)
    {
        leaf_count += inputs->frames[frame].leaf_count;
    }
    for (unsigned int edge = 0u; edge < inputs->key->edge_count; edge += 1u)
    {
        edge_count += (unsigned int)(inputs->edge_status[edge] >= 0);
    }
    unsigned int *const frame_table = (unsigned int *)calloc(((size_t)frame_count + 1u) * 10u, sizeof(unsigned int));
    unsigned int *const leaves = (unsigned int *)malloc(((size_t)leaf_count + 1u) * 4u * sizeof(unsigned int));
    unsigned long long *const sums = (unsigned long long *)calloc(((size_t)cell_count + 1u) * 4u, sizeof(unsigned long long));
    unsigned int *const cells = (unsigned int *)malloc(((size_t)cell_count + 1u) * 4u * sizeof(unsigned int));
    unsigned int *const links = (unsigned int *)malloc(((size_t)link_count + 1u) * 2u * sizeof(unsigned int));
    unsigned int *const edges = (unsigned int *)malloc(((size_t)edge_count + 1u) * 3u * sizeof(unsigned int));
    int good = (written > 0) && ((size_t)written < sizeof(path)) && frame_table && leaves && sums && cells && links
            && edges;

    unsigned int leaf_base = 0u;
    unsigned int aberrant_leaves = 0u;
    unsigned int aberrant_voxels = 0u;
    for (unsigned int frame = 0u; good && (frame < frame_count); frame += 1u)
    {
        const TreeFrame *const tree = &inputs->frames[frame];
        unsigned int *const row = &frame_table[(size_t)frame * 10u];
        row[0] = tree->time;
        row[1] = leaf_base;
        row[2] = tree->leaf_count;
        row[3] = first_run[frame];
        row[4] = first_run[frame + 1u] - first_run[frame];
        row[5] = inputs->unified_first[frame];
        row[6] = inputs->unified_first[frame + 1u] - inputs->unified_first[frame];
        row[7] = inputs->unified_start[inputs->unified_first[frame]];
        row[8] = inputs->unified_start[inputs->unified_first[frame + 1u]] - row[7];
        for (unsigned int leaf = 0u; leaf < tree->leaf_count; leaf += 1u)
        {
            const unsigned int cell = inputs->unified_of[inputs->node_offset[frame] + tree->object_of[leaf]];
            const unsigned int *const range = &leaf_runs[2u * ((size_t)leaf_base + leaf)];
            unsigned int *const record = &leaves[4u * ((size_t)leaf_base + leaf)];
            record[0] = cell;
            record[1] = frame;
            record[2] = range[0];
            record[3] = range[1];
            unsigned int length = 0u;
            for (unsigned int run = range[0]; run < range[0] + range[1]; run += 1u)
            {
                length += (runs[run] & 0xFFu) + 1u;
            }
            const unsigned int over = (unsigned int)(length > tree->sizes[leaf]);
            aberrant_leaves += (unsigned int)(length != tree->sizes[leaf]);
            aberrant_voxels += (over * (length - tree->sizes[leaf])) + ((1u - over) * (tree->sizes[leaf] - length));
            sums[4u * (size_t)cell] += tree->sizes[leaf];
            sums[(4u * (size_t)cell) + 1u] += tree->sums[3u * (size_t)leaf];
            sums[(4u * (size_t)cell) + 2u] += tree->sums[(3u * (size_t)leaf) + 1u];
            sums[(4u * (size_t)cell) + 3u] += tree->sums[(3u * (size_t)leaf) + 2u];
        }
        leaf_base += tree->leaf_count;
    }
    unsigned int wide_sums = 0u;
    for (size_t slot = 0u; good && (slot < (size_t)cell_count * 4u); slot += 1u)
    {
        wide_sums += (unsigned int)!!(sums[slot] >> 32u);
        cells[slot] = (unsigned int)sums[slot];
    }
    fprintf(stderr, "  object %s: %u aberrant leaves, %u aberrant voxels, %u wide sums\n", inputs->sample, aberrant_leaves,
            aberrant_voxels, wide_sums);
    for (unsigned int link = 0u; good && (link < link_count); link += 1u)
    {
        links[2u * link] = (unsigned int)(inputs->unified_link[link] >> 32u);
        links[(2u * link) + 1u] = (unsigned int)(inputs->unified_link[link] & 0xFFFFFFFFULL);
    }
    unsigned int scored = 0u;
    for (unsigned int edge = 0u; good && (edge < inputs->key->edge_count); edge += 1u)
    {
        const long source = node_slot_of(inputs->key, inputs->key->edge_ends[2u * edge]);
        const long target = node_slot_of(inputs->key, inputs->key->edge_ends[(2u * edge) + 1u]);
        edges[3u * scored] = object_cell_of_node(inputs, source);
        edges[(3u * scored) + 1u] = object_cell_of_node(inputs, target);
        edges[(3u * scored) + 2u] = (unsigned int)inputs->edge_status[edge];
        scored += (unsigned int)(inputs->edge_status[edge] >= 0);
    }

    FILE *const out = good ? fopen(path, "wb") : NULL;
    good = good && out;
    if (good)
    {
        const unsigned int cfg_bytes = (unsigned int)rules->cfg_length;
        const unsigned char padding[4] = {0u, 0u, 0u, 0u};
        const unsigned int header[16] = {0x314A424Fu, 1u, frame_count, buffers->depth, buffers->height, buffers->width,
                                         leaf_count, run_count, cell_count, link_count, edge_count, aberrant_leaves,
                                         aberrant_voxels, wide_sums, cfg_bytes, 0u};
        good = (fwrite(header, sizeof(unsigned int), 16u, out) == 16u)
            && (fwrite(frame_table, sizeof(unsigned int), (size_t)frame_count * 10u, out) == (size_t)frame_count * 10u)
            && (fwrite(leaves, sizeof(unsigned int), (size_t)leaf_count * 4u, out) == (size_t)leaf_count * 4u)
            && (fwrite(cells, sizeof(unsigned int), (size_t)cell_count * 4u, out) == (size_t)cell_count * 4u)
            && (fwrite(runs, sizeof(unsigned int), run_count, out) == run_count)
            && (fwrite(links, sizeof(unsigned int), (size_t)link_count * 2u, out) == (size_t)link_count * 2u)
            && (fwrite(edges, sizeof(unsigned int), (size_t)edge_count * 3u, out) == (size_t)edge_count * 3u)
            && (fwrite(rules->cfg_text, 1u, cfg_bytes, out) == cfg_bytes)
            && (fwrite(padding, 1u, (4u - (cfg_bytes & 3u)) & 3u, out) == ((4u - (cfg_bytes & 3u)) & 3u));
        good = (fclose(out) == 0) && good;
    }
    free(frame_table);
    free(leaves);
    free(sums);
    free(cells);
    free(links);
    free(edges);
    return good;
}

int read_coherence(EngineBuffers *buffers, const CoherenceInputs *inputs, FILE *out)
{
    const AnswerKey *const key = inputs->key;
    const size_t voxels = (size_t)buffers->depth * buffers->height * buffers->width;
    const size_t words = (voxels + 63u) / 64u;
    const unsigned int plane = buffers->height * buffers->width;
    unsigned char *const failing_time = (unsigned char *)calloc((size_t)inputs->volume_frames + 1u, 1u);
    int *const leaf_at_peak[2] = {(int *)malloc(voxels * sizeof(int)), (int *)malloc(voxels * sizeof(int))};
    unsigned long long *const mask = (unsigned long long *)malloc(words * sizeof(unsigned long long));
    unsigned char *const leaf_in_cell = (unsigned char *)malloc(voxels / 8u + 1u);
    unsigned int *const unified_size = (unsigned int *)calloc((size_t)inputs->unified_count + 1u, sizeof(unsigned int));
    unsigned int *const landing = (unsigned int *)calloc((size_t)inputs->unified_count + 1u, sizeof(unsigned int));
    unsigned int *const touched = (unsigned int *)malloc(((size_t)inputs->unified_count + 1u) * sizeof(unsigned int));
    size_t cell_room = 1u << 16u;
    unsigned int *cell_voxels = (unsigned int *)malloc(cell_room * sizeof(unsigned int));
    int good = (failing_time != NULL) && (leaf_at_peak[0] != NULL) && (leaf_at_peak[1] != NULL) && (mask != NULL)
            && (leaf_in_cell != NULL) && (unified_size != NULL) && (landing != NULL) && (touched != NULL)
            && (cell_voxels != NULL) && (inputs->volume != NULL);
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        leaf_at_peak[0][voxel] = -1;
        leaf_at_peak[1][voxel] = -1;
    }
    for (unsigned int edge = 0u; (good != 0) && (edge < key->edge_count); edge += 1u)
    {
        if ((inputs->edge_status[edge] >= 1) && (inputs->edge_status[edge] <= 3))
        {
            const long source = node_slot_of(key, key->edge_ends[2u * edge]);
            failing_time[(unsigned int)key->node_coordinates[(size_t)source * 4u]] = 1u;
        }
    }

    for (unsigned int frame = 0u; (good != 0) && (frame + 1u < inputs->frame_count); frame += 1u)
    {
        const TreeFrame *const earlier = &inputs->frames[frame];
        if ((failing_time[earlier->time] == 0u) || (earlier->forward == NULL))
        {
            continue;
        }
        TreeFrame held[2];
        memset(held, 0, sizeof(held));
        for (unsigned int slot = 0u; (good != 0) && (slot < 2u); slot += 1u)
        {
            good = ((earlier->time + slot) < inputs->volume_frames);
            if (good != 0)
            {
                memcpy(buffers->volume, &inputs->volume[(size_t)(earlier->time + slot) * voxels],
                       voxels * sizeof(unsigned short));
            }
            good = (good != 0) && (track_frame_bodies(buffers, slot, &held[slot]) != 0);
            for (unsigned int leaf = 0u; (good != 0) && (leaf < held[slot].leaf_count); leaf += 1u)
            {
                leaf_at_peak[slot][held[slot].peaks[leaf]] = (int)leaf;
            }
        }
        const unsigned int *const labels_before = buffers->labels[0];
        const unsigned int *const labels_after = buffers->labels[1];
        const unsigned long long *const positive_before = buffers->positive[0];
        const unsigned long long *const positive_after = buffers->positive[1];
        const unsigned int offset_before = inputs->node_offset[frame];
        const unsigned int offset_after = inputs->node_offset[frame + 1u];
        const TreeFrame *const later = &inputs->frames[frame + 1u];

        for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
        {
            if (((positive_after[voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
            {
                continue;
            }
            const int leaf = leaf_at_peak[1][labels_after[voxel]];
            if (leaf >= 0)
            {
                unified_size[inputs->unified_of[offset_after + later->object_of[(unsigned int)leaf]]] += 1u;
            }
        }

        for (unsigned int edge = 0u; (good != 0) && (edge < key->edge_count); edge += 1u)
        {
            const int status = inputs->edge_status[edge];
            if ((status < 0) || (status > 3))
            {
                continue;
            }
            const long source = node_slot_of(key, key->edge_ends[2u * edge]);
            const long target = node_slot_of(key, key->edge_ends[2u * edge + 1u]);
            const int *const from = &key->node_coordinates[(size_t)source * 4u];
            const int *const to = &key->node_coordinates[(size_t)target * 4u];
            if (((unsigned int)from[0] != earlier->time) || ((unsigned int)to[0] != earlier->time + 1u))
            {
                continue;
            }
            const unsigned int cell = inputs->unified_of[offset_before
                                                          + earlier->object_of[(unsigned int)inputs->node_leaf[source]]];
            const unsigned int true_target = inputs->unified_of[offset_after
                                                                 + later->object_of[(unsigned int)inputs->node_leaf[target]]];

            memset(leaf_in_cell, 0, voxels / 8u + 1u);
            unsigned int leaves = 0u;
            for (unsigned int leaf = 0u; leaf < earlier->leaf_count; leaf += 1u)
            {
                if (inputs->unified_of[offset_before + earlier->object_of[leaf]] == cell)
                {
                    leaf_in_cell[leaf / 8u] |= (unsigned char)(1u << (leaf % 8u));
                    leaves += 1u;
                }
            }
            memset(mask, 0, words * sizeof(unsigned long long));
            size_t cell_size = 0u;
            for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
            {
                if (((positive_before[voxel / 64u] >> (voxel % 64u)) & 1ULL) == 0ULL)
                {
                    continue;
                }
                const int leaf = leaf_at_peak[0][labels_before[voxel]];
                if ((leaf < 0) || (((leaf_in_cell[(unsigned int)leaf / 8u] >> ((unsigned int)leaf % 8u)) & 1u) == 0u))
                {
                    continue;
                }
                mask[voxel / 64u] |= 1ULL << (voxel % 64u);
                if (cell_size == cell_room)
                {
                    cell_room *= 2u;
                    unsigned int *const grown = (unsigned int *)realloc(cell_voxels, cell_room * sizeof(unsigned int));
                    if (grown == NULL)
                    {
                        good = 0;
                        break;
                    }
                    cell_voxels = grown;
                }
                cell_voxels[cell_size] = (unsigned int)voxel;
                cell_size += 1u;
            }

            ShiftAgreementRequest motion;
            memset(&motion, 0, sizeof(motion));
            motion.axes = 3u;
            motion.extents[0] = buffers->depth;
            motion.extents[1] = buffers->height;
            motion.extents[2] = buffers->width;
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                motion.weights[axis] = AXIS_WEIGHTS[axis];
            }
            motion.before = mask;
            motion.after = positive_after;
            motion.counts = NULL;
            good = (good != 0) && (cell_size > 0u) && (shift_agreement_run(&motion) == 0L);
            if (good == 0)
            {
                break;
            }
            const int true_lag[3] = {to[1] - from[1], to[2] - from[2], to[3] - from[3]};
            const int *const lags[3] = {motion.lag, earlier->lag_to_next, true_lag};
            unsigned long long agreement[3] = {0ULL, 0ULL, 0ULL};
            unsigned int touched_count = 0u;
            for (unsigned int which = 0u; which < 3u; which += 1u)
            {
                for (size_t member = 0u; member < cell_size; member += 1u)
                {
                    const unsigned int voxel = cell_voxels[member];
                    const unsigned int rest = voxel % plane;
                    const long z = (long)(voxel / plane) + (long)lags[which][0];
                    const long y = (long)(rest / buffers->width) + (long)lags[which][1];
                    const long x = (long)(rest % buffers->width) + (long)lags[which][2];
                    if ((z < 0L) || (z >= (long)buffers->depth) || (y < 0L) || (y >= (long)buffers->height)
                     || (x < 0L) || (x >= (long)buffers->width))
                    {
                        continue;
                    }
                    const unsigned int landed = (unsigned int)((z * (long)buffers->height + y) * (long)buffers->width + x);
                    if (((positive_after[landed / 64u] >> (landed % 64u)) & 1ULL) == 0ULL)
                    {
                        continue;
                    }
                    agreement[which] += 1ULL;
                    if (which != 1u)
                    {
                        continue;
                    }
                    const int leaf = leaf_at_peak[1][labels_after[landed]];
                    if (leaf >= 0)
                    {
                        const unsigned int object = inputs->unified_of[offset_after + later->object_of[(unsigned int)leaf]];
                        if (landing[object] == 0u)
                        {
                            touched[touched_count] = object;
                            touched_count += 1u;
                        }
                        landing[object] += 1u;
                    }
                }
            }
            unsigned long long land_max = 0ULL;
            unsigned long long land_sumsq = 0ULL;
            for (unsigned int slot = 0u; slot < touched_count; slot += 1u)
            {
                const unsigned long long count = landing[touched[slot]];
                land_max = (count > land_max) ? count : land_max;
                land_sumsq += count * count;
            }
            const unsigned int land_true = landing[true_target];
            for (unsigned int slot = 0u; slot < touched_count; slot += 1u)
            {
                landing[touched[slot]] = 0u;
            }
            if (out != NULL)
            {
                fprintf(out, "%s\t%u\t%s\t%zu\t%u\t%u\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%llu\t%llu\t%llu\t%u\t%llu\t%llu\t%u\n",
                        inputs->sample, earlier->time, EDGE_STATUS_NAMES[status], cell_size, leaves,
                        unified_size[true_target], motion.lag[0], motion.lag[1], motion.lag[2], earlier->lag_to_next[0],
                        earlier->lag_to_next[1], earlier->lag_to_next[2], true_lag[0], true_lag[1], true_lag[2],
                        agreement[0], agreement[1], agreement[2], land_true, land_max, land_sumsq, touched_count);
            }
            if ((inputs->vis_index != NULL) && (status >= 1) && (status <= 3))
            {
                VisCase view;
                memset(&view, 0, sizeof(view));
                view.edge = edge;
                view.status = status;
                view.earlier = earlier;
                view.later = later;
                view.offset_before = offset_before;
                view.offset_after = offset_after;
                view.leaf_at_peak[0] = leaf_at_peak[0];
                view.leaf_at_peak[1] = leaf_at_peak[1];
                view.from = from;
                view.to = to;
                view.source_leaf = (unsigned int)inputs->node_leaf[source];
                view.cell = cell;
                view.true_target = true_target;
                view.cell_size = cell_size;
                view.leaves = leaves;
                view.target_size = unified_size[true_target];
                view.agree_view = agreement[1];
                view.agree_true = agreement[2];
                view.land_true = land_true;
                view.land_objects = touched_count;
                good = render_case(buffers, inputs, &view);
            }
        }

        for (unsigned int slot = 0u; slot < 2u; slot += 1u)
        {
            for (unsigned int leaf = 0u; leaf < held[slot].leaf_count; leaf += 1u)
            {
                leaf_at_peak[slot][held[slot].peaks[leaf]] = -1;
            }
            free(held[slot].peaks);
            free(held[slot].sizes);
            free(held[slot].sums);
            free(held[slot].joined);
        }
        for (unsigned int node = offset_after; node < inputs->node_offset[frame + 2u]; node += 1u)
        {
            unified_size[inputs->unified_of[node]] = 0u;
        }
    }
    fflush(out);
    free(cell_voxels);
    free(touched);
    free(landing);
    free(unified_size);
    free(leaf_in_cell);
    free(mask);
    free(leaf_at_peak[0]);
    free(leaf_at_peak[1]);
    free(failing_time);
    return good;
}
