// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// knf_identity_main.cu: departure, controls and main
#include "knf_identity_internal.h"

static AnchorExactInteger s_knf_body_departure[KNF_SCALES][KNF_BODIES];

static void knf_print_share(ScripturaLine *line, const AnchorExactInteger *part, const AnchorExactInteger *whole)
{
    scriptura_character(line, ' ');
    char text_buffer[32];
    ScripturaLine cell;
    cell.out = text_buffer;
    cell.capacity = sizeof(text_buffer);
    cell.at = 0ull;
    sim_ratio_print(&cell, part, whole, 3u);
    scriptura_finish(&cell);
    scriptura_text_columns(line, text_buffer, 9u);
}

static int knf_departure(SimResults *results, const KnfRecord *record, const unsigned short *boxes,
                         const SimScene *scene, const KnfBox *box, unsigned long long tag, unsigned int *map,
                         unsigned int *slot, const char *name)
{
    static const unsigned long long s_knf_tiles[KNF_SCALES] = {1ull, 2ull, 4ull, 8ull, 16ull, 32ull, 64ull};
    const unsigned long long side = record->side;
    KnfEntangled whole;
    knf_entangle(record, NULL, side, boxes, &whole);
    AnchorExactInteger truth;
    knf_exact_total(&whole, &truth);
    AnchorExactInteger inside_departure[KNF_SCALES];
    AnchorExactInteger between_departure[KNF_SCALES];
    int inside_identified[KNF_SCALES];
    int between_identified[KNF_SCALES];
    AnchorExactInteger free_sum;
    unsigned long long split_matches = 0ull;
    unsigned long long kept_stored = 0ull;
    for (unsigned int scale = 0u; scale < KNF_SCALES; scale += 1u)
    {
        const unsigned long long tile = s_knf_tiles[scale];
        KnfEntangled split;
        knf_entangle(record, NULL, tile, NULL, &split);
        AnchorExactInteger split_total;
        knf_exact_total(&split, &split_total);
        split_matches += (anchor_exact_compare(&split_total, &truth) == 0) ? 1ull : 0ull;
        AnchorExactInteger inside_sum;
        AnchorExactInteger between_sum;
        AnchorExactInteger body_sum[KNF_BODIES];
        anchor_exact_zero(&inside_sum);
        anchor_exact_zero(&between_sum);
        for (unsigned int body = 0u; body < KNF_BODIES; body += 1u)
        {
            anchor_exact_zero(&body_sum[body]);
        }
        inside_identified[scale] = 1;
        between_identified[scale] = 1;
        for (unsigned int draw = 0u; draw < KNF_DRAWS; draw += 1u)
        {
            const unsigned long long counter = (((((tag * KNF_SCALES) + scale) * 2ull) * KNF_DRAWS) + draw);
            KnfEntangled drawn;
            AnchorExactInteger total;
            AnchorExactInteger running;
            knf_inside_draw(map, slot, side, tile, sim_draw(KNF_KEY ^ KNF_NULL_PURPOSE, counter));
            knf_entangle(record, map, tile, boxes, &drawn);
            knf_exact_total(&drawn, &total);
            inside_identified[scale] = inside_identified[scale] && (anchor_exact_compare(&total, &truth) < 0);
            sim_exact_sum(&inside_sum, &total, &running);
            inside_sum = running;
            for (unsigned int body = 0u; body < KNF_BODIES; body += 1u)
            {
                AnchorExactInteger share;
                knf_wide_exact(&drawn.body[body], &share);
                sim_exact_sum(&body_sum[body], &share, &running);
                body_sum[body] = running;
            }
            knf_between_draw(map, slot, side, tile, sim_draw(KNF_KEY ^ KNF_NULL_PURPOSE, counter + KNF_DRAWS));
            knf_entangle(record, map, tile, NULL, &drawn);
            kept_stored += knf_wide_equal(&drawn.inside, &split.inside) ? 1ull : 0ull;
            knf_exact_total(&drawn, &total);
            between_identified[scale] = between_identified[scale] && (anchor_exact_compare(&total, &truth) < 0);
            sim_exact_sum(&between_sum, &total, &running);
            between_sum = running;
        }
        knf_departure_of(&truth, &inside_sum, &inside_departure[scale]);
        knf_departure_of(&truth, &between_sum, &between_departure[scale]);
        free_sum = inside_sum;
        for (unsigned int body = 0u; body < KNF_BODIES; body += 1u)
        {
            AnchorExactInteger body_truth;
            knf_wide_exact(&whole.body[body], &body_truth);
            knf_departure_of(&body_truth, &body_sum[body], &s_knf_body_departure[scale][body]);
        }
    }
    const AnchorExactInteger *const universal = &inside_departure[KNF_SCALES - 1u];
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, ": the entangled entropy against the free null's mean ");
    AnchorExactInteger scaled_truth;
    sim_exact_scaled(&truth, KNF_DRAWS, &scaled_truth);
    sim_ratio_print(line, &scaled_truth, &free_sum, 3u);
    scriptura_text(line, ", identified ");
    scriptura_text(line, (inside_identified[KNF_SCALES - 1u] != 0) ? "yes" : "no");
    scriptura_text(line, "\n    the departure curve, as a share of the free null's departure (");
    scriptura_decimal(line, KNF_DRAWS, 1u);
    scriptura_text(line, " draws a tile size, E past every draw marked *)\n");
    scriptura_text(line, "      tile    inside   between       sum\n");
    for (unsigned int scale = 0u; scale < KNF_SCALES; scale += 1u)
    {
        AnchorExactInteger both;
        sim_exact_sum(&inside_departure[scale], &between_departure[scale], &both);
        scriptura_text(line, "    ");
        scriptura_decimal_columns(line, s_knf_tiles[scale], 6u);
        knf_print_share(line, &inside_departure[scale], universal);
        scriptura_character(line, (inside_identified[scale] != 0) ? '*' : ' ');
        knf_print_share(line, &between_departure[scale], universal);
        scriptura_character(line, (between_identified[scale] != 0) ? '*' : ' ');
        knf_print_share(line, &both, universal);
        scriptura_character(line, '\n');
    }
    sim_check(results, split_matches == KNF_SCALES,
              "at every tile size the whole is its tiles plus its seams, exactly");
    sim_check(results, kept_stored == (KNF_SCALES * KNF_DRAWS),
              "a rigid move of whole tiles keeps every tile's inside exactly");
    sim_check(results, inside_departure[0].sign == 0, "a tile of one voxel shuffles nothing: no departure");
    sim_check(results, between_departure[KNF_SCALES - 1u].sign == 0,
              "one tile moved whole moves nothing: no departure");
    if (box == NULL)
    {
        sim_flush(results);
        return inside_identified[KNF_SCALES - 1u];
    }
    scriptura_text(
        line,
        "    each body's box (zmin..zmax, ymin..ymax, xmin..xmax over its life), its own inside curve as a share of\n");
    scriptura_text(line, "    its free departure, and that departure as a share of the whole's\n");
    scriptura_text(line, "      body parent  born ended  vy vx  box z      y      x           2        4        8      "
                         " 16       32     share\n");
    for (unsigned int index = 0u; index < scene->bodies; index += 1u)
    {
        const SimBody *const body = &scene->body[index];
        scriptura_text(line, "    ");
        scriptura_decimal_columns(line, index, 6u);
        scriptura_character(line, ' ');
        if (body->parent < 0ll)
        {
            scriptura_text(line, "     -");
        }
        else
        {
            // a parent index is non-negative here
            scriptura_decimal_columns(line, (unsigned long long)body->parent, 6u);
        }
        scriptura_decimal_columns(line, body->born, 6u);
        scriptura_decimal_columns(line, body->ended, 6u);
        scriptura_character(line, ' ');
        scriptura_text(line, (body->velocity[1] < 0ll) ? " " : "  ");
        scriptura_signed(line, body->velocity[1]);
        scriptura_text(line, (body->velocity[2] < 0ll) ? " " : "  ");
        scriptura_signed(line, body->velocity[2]);
        scriptura_text(line, "  ");
        if (box[index].filled == 0)
        {
            scriptura_text(line, "never in view\n");
            continue;
        }
        for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
        {
            // a held box's bounds are non-negative and below the side
            scriptura_decimal_columns(line, (unsigned long long)box[index].box[axis], 2u);
            scriptura_character(line, '-');
            scriptura_decimal_columns(line, (unsigned long long)box[index].box[SIM_AXES + axis], 2u);
            scriptura_character(line, ' ');
        }
        for (unsigned int scale = 1u; scale + 1u < KNF_SCALES; scale += 1u)
        {
            knf_print_share(line, &s_knf_body_departure[scale][index], &s_knf_body_departure[KNF_SCALES - 1u][index]);
        }
        knf_print_share(line, &s_knf_body_departure[KNF_SCALES - 1u][index], universal);
        scriptura_character(line, '\n');
    }
    sim_flush(results);
    return inside_identified[KNF_SCALES - 1u];
}

static void knf_controls(SimResults *results, unsigned short *device_lanes, unsigned short *lanes, KnfRecord *record,
                         unsigned int *map, unsigned int *slot)
{
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = KNF_FRAMES;
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        scene.extent[axis] = KNF_CONTROL_SIDE;
    }
    scene.background = 180ull;
    const unsigned long long voxels = sim_scene_voxels(&scene);
    const unsigned long long lanes_count = scene.frames * voxels;
    record->side = KNF_CONTROL_SIDE;
    record->voxels = voxels;
    unsigned long long projected = 0ull;
    unsigned long long identified = 0ull;
    for (unsigned int control = 0u; control < KNF_CONTROLS; control += 1u)
    {
        SimCamera camera;
        knf_camera(&camera, sim_draw(KNF_KEY ^ KNF_CONTROL_PURPOSE, control), 0ull);
        unsigned long long clipped = 0ull;
        int ok = sim_render(results, &scene, &camera, device_lanes, NULL, NULL, &clipped) && (clipped == 0ull);
        ok = ok &&
             sim_status_check(
                 results, cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                 "control lanes read");
        ok = ok && knf_project(results, lanes, record);
        if (ok == 0)
        {
            continue;
        }
        projected += 1ull;
        identified +=
            (knf_identified(record, map, slot, sim_draw(KNF_KEY ^ KNF_CONTROL_PURPOSE, KNF_CONTROLS + control)) != 0)
                ? 1ull
                : 0ull;
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  the null's own rate: ");
    scriptura_decimal(line, KNF_CONTROLS, 1u);
    scriptura_text(line,
                   " volumes of 32^3 with every voxel drawn alike (no bodies, no ramp, no fixed pattern), each\n");
    scriptura_text(line, "  against ");
    scriptura_decimal(line, KNF_DRAWS, 1u);
    scriptura_text(line, " free spatial draws: ");
    scriptura_decimal(line, identified, 1u);
    scriptura_text(line, " identified, where exchangeability bounds the rate by 1/");
    scriptura_decimal(line, KNF_DRAWS + 1u, 1u);
    scriptura_character(line, '\n');
    const unsigned long long scaled = (KNF_DRAWS + 1ull) * identified;
    const unsigned long long excess = (scaled > KNF_CONTROLS) ? (scaled - KNF_CONTROLS) : 0ull;
    sim_check(results, projected == KNF_CONTROLS, "every control volume renders and projects");
    sim_check(results, (excess * excess) <= (KNF_RANGE_SQUARED * KNF_CONTROLS * (KNF_DRAWS + 1ull)),
              "alike voxels are identified in at most n/(draws + 1) + 5 sqrt(n p) of the n controls");
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    SimBody body[KNF_BODIES];
    memset(body, 0, sizeof(body));
    SimScene scene;
    knf_scene(&scene, body, 1);
    SimCamera camera;
    knf_camera(&camera, KNF_KEY, 8ull);
    const unsigned long long voxels = sim_scene_voxels(&scene);
    const unsigned long long lanes_count = scene.frames * voxels;
    const unsigned long long history_words = KNF_WINDOWS * voxels;
    const unsigned long long cloud_words = KNF_WINDOWS * KNF_WINDOWS;

    unsigned short *lanes = (unsigned short *)malloc((size_t)lanes_count * sizeof(unsigned short));
    unsigned short *moved = (unsigned short *)malloc((size_t)lanes_count * sizeof(unsigned short));
    unsigned int *map = (unsigned int *)malloc((size_t)voxels * sizeof(unsigned int));
    unsigned int *slot = (unsigned int *)malloc((size_t)voxels * sizeof(unsigned int));
    unsigned short *boxes = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    KnfRecord record;
    KnfRecord moved_record;
    record.side = KNF_SIDE;
    record.voxels = voxels;
    record.history = (unsigned long long *)malloc((size_t)history_words * sizeof(unsigned long long));
    record.cloud = (unsigned long long *)malloc((size_t)cloud_words * sizeof(unsigned long long));
    record.centerd = (long long *)malloc((size_t)history_words * sizeof(long long));
    moved_record = record;
    moved_record.history = (unsigned long long *)malloc((size_t)history_words * sizeof(unsigned long long));
    moved_record.cloud = (unsigned long long *)malloc((size_t)cloud_words * sizeof(unsigned long long));
    moved_record.centerd = (long long *)malloc((size_t)history_words * sizeof(long long));
    unsigned short *device_lanes = NULL;
    int ok = (lanes != NULL) && (moved != NULL) && (map != NULL) && (slot != NULL) && (boxes != NULL) &&
             (record.history != NULL) && (record.cloud != NULL) && (record.centerd != NULL) &&
             (moved_record.history != NULL) && (moved_record.cloud != NULL) && (moved_record.centerd != NULL);
    sim_check(&results, ok, "host buffers");
    ok = ok && sim_job_submit(&results, "knf_identity", count, arguments,
                              (4ull * lanes_count * sizeof(unsigned short)) +
                                  ((history_words + cloud_words + 1ull) * sizeof(unsigned long long)));
    ok = ok &&
         sim_status_check(&results, cudaMalloc((void **)&device_lanes, lanes_count * sizeof(unsigned short)), "lanes");

    ScripturaLine *const line = &results.line;
    scriptura_text(line,
                   "  the knf's identity by spatial null permutation: the nbody lattice's law in a 64^3 cube over ");
    scriptura_decimal(line, KNF_FRAMES, 1u);
    scriptura_text(line, " frames,\n  ");
    scriptura_decimal(line, KNF_WINDOWS, 1u);
    scriptura_text(line, " windows of ");
    scriptura_decimal(line, ENGINE_HISTORY_WINDOW, 1u);
    scriptura_text(line, " transitions; a section is one voxel's windows, E couples each with its xyz neighbors\n");
    sim_flush(&results);

    unsigned long long clipped = 0ull;
    ok = ok && sim_render(&results, &scene, &camera, device_lanes, NULL, NULL, &clipped);
    ok = ok &&
         sim_status_check(&results,
                          cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                          "lanes read");
    ok = ok && (clipped == 0ull);
    sim_check(&results, ok, "the lattice renders, no lane clipped");
    KnfBox box[KNF_BODIES];
    memset(box, 0, sizeof(box));
    if (ok)
    {
        knf_boxes(&scene, box, boxes);
        ok = knf_project(&results, lanes, &record);
        sim_check(&results, ok, "the lattice's knf projects, its parity law held at every voxel");
    }
    if (ok)
    {
        knf_one_bit(&results, lanes, &record);
        sim_flush(&results);
        knf_motions(&results, lanes, moved, &record, &moved_record, map);
        sim_flush(&results);
        const int identified = knf_departure(&results, &record, boxes, &scene, box, 0ull, map, slot, "the lattice");
        sim_check(&results, identified, "the lattice's knf is identified past every free spatial draw");
    }

    SimScene empty;
    knf_scene(&empty, body, 0);
    ok = ok && sim_render(&results, &empty, &camera, device_lanes, NULL, NULL, &clipped);
    ok = ok &&
         sim_status_check(&results,
                          cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short), cudaMemcpyDeviceToHost),
                          "empty lanes read");
    ok = ok && (clipped == 0ull) && knf_project(&results, lanes, &record);
    sim_check(&results, ok, "the same scene with no bodies renders and projects");
    if (ok)
    {
        knf_departure(&results, &record, NULL, &empty, NULL, 1ull, map, slot, "the same camera and ramp, no bodies");
        knf_controls(&results, device_lanes, lanes, &record, map, slot);
    }

    cudaFree(device_lanes);
    free(moved_record.centerd);
    free(moved_record.cloud);
    free(moved_record.history);
    free(record.centerd);
    free(record.cloud);
    free(record.history);
    free(boxes);
    free(slot);
    free(map);
    free(moved);
    free(lanes);
    return sim_close(&results, "knf identity");
}
