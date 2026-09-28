// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// root_universal_main.cu: the extent printed and main
#include "root_universal_internal.h"

static void root_extent_print(ScripturaLine *line, const unsigned long long extent[4])
{
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        if (axis != 0u)
        {
            scriptura_text(line, " x ");
        }
        scriptura_decimal(line, extent[axis], 1u);
    }
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    ScripturaLine *const line = &results.line;

    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_range = 8ull;
    camera.shot = 1ull;

    const unsigned long long extent[ROOT_EXTENTS][4] = {{4ull, 12ull, 48ull, 48ull}, {3ull, 13ull, 37ull, 41ull}};
    RootVolume volume[ROOT_EXTENTS];
    memset(volume, 0, sizeof(volume));
    // both volumes' device lanes, the tower's and the coder's pools for the larger, and the table of the widest edge;
    // the coded stream, sized by the values, is left to the kept peak
    unsigned long long declared = (unsigned long long)ROOT_TABLE_CAPACITY * sizeof(unsigned int);
    unsigned long long lanes_declared = 0ull;
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        const unsigned long long lanes = extent[shaped][0] * extent[shaped][1] * extent[shaped][2] * extent[shaped][3];
        declared += lanes * sizeof(unsigned short);
        lanes_declared = (lanes > lanes_declared) ? lanes : lanes_declared;
    }
    declared += tower_reserve_bytes(lanes_declared) + compression_reserve_bytes(lanes_declared);
    int ok = sim_job_submit(&results, "root_universal", 0, NULL, declared);
    unsigned long long lanes_max = 0ull;
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        ok = ok && root_volume_open(&results, &volume[shaped], extent[shaped]);
        lanes_max = (volume[shaped].lanes > lanes_max) ? volume[shaped].lanes : lanes_max;
    }
    RootProgram program;
    memset(&program, 0, sizeof(program));
    for (unsigned int at = 0u; at < ROOT_EDGES_MAX; at += 1u)
    {
        program.table[at] = (unsigned int *)malloc((size_t)ROOT_TABLE_CAPACITY * sizeof(unsigned int));
        ok = ok && (program.table[at] != NULL);
    }
    int *crystal[4];
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        crystal[at] = (int *)malloc((size_t)lanes_max * sizeof(int));
        ok = ok && (crystal[at] != NULL);
    }
    sim_check(&results, ok, "the sim's tables and crystals were held");

    scriptura_text(
        line,
        "  the root universal: the tower with reversible lookup edges between its floors, on camera-law volumes\n");
    scriptura_text(line, "  (signal 200 e plus a ramp of 1 e a column, 6 moving bodies of 150 to 400 e, read variance "
                         "3, fixed pattern 0 to 8)\n\n");

    scriptura_text(
        line,
        "  1. the root stays exact: random edge programs (1 to 6 edges, random floors, widths 1 to 12 bits, and one\n");
    scriptura_text(line, "     20-bit edge per extent) through lift, code, wipe, decode, lower\n");
    scriptura_text(
        line, "  extent (t x z x y x)  floors  volumes  edges laid out  plain exact  edged exact  crystals changed\n");
    sim_flush(&results);
    for (unsigned int shaped = 0u; ok && (shaped < ROOT_EXTENTS); shaped += 1u)
    {
        RootVolume *const here = &volume[shaped];
        unsigned long long plain_exact = 0ull;
        unsigned long long edged_exact = 0ull;
        unsigned long long changed = 0ull;
        unsigned long long edge_count = 0ull;
        for (unsigned int drawn = 0u; ok && (drawn < ROOT_EXACT_VOLUMES); drawn += 1u)
        {
            camera.key = sim_draw(ROOT_KEY, ((unsigned long long)shaped * ROOT_EXACT_VOLUMES) + drawn);
            ok = root_volume_render(&results, here, &camera);
            unsigned long long bits = 0ull;
            int exact = 0;
            ok = ok && root_crystal_trip(&results, here, NULL, 0u, crystal[0], &bits, &exact);
            plain_exact += (exact != 0) ? 1ull : 0ull;
            root_program_draw(&program, here->floors, sim_draw(camera.key, ROOT_PROGRAM_PURPOSE), drawn == 0u);
            ok = ok && root_crystal_trip(&results, here, program.edge, program.count, crystal[1], &bits, &exact);
            edged_exact += (exact != 0) ? 1ull : 0ull;
            changed += (memcmp(crystal[0], crystal[1], (size_t)here->lanes * sizeof(int)) != 0) ? 1ull : 0ull;
            edge_count += program.count;
        }
        scriptura_text(line, "  ");
        root_extent_print(line, here->extent);
        scriptura_decimal_columns(line, here->floors, 11u);
        scriptura_decimal_columns(line, ROOT_EXACT_VOLUMES, 9u);
        scriptura_decimal_columns(line, edge_count, 12u);
        scriptura_decimal_columns(line, plain_exact, 13u);
        scriptura_decimal_columns(line, edged_exact, 13u);
        scriptura_decimal_columns(line, changed, 18u);
        scriptura_character(line, '\n');
        sim_flush(&results);
        sim_check(&results, plain_exact == ROOT_EXACT_VOLUMES, "every plain crystal rebuilt its lanes exactly");
        sim_check(&results, edged_exact == ROOT_EXACT_VOLUMES,
                  "every edged crystal rebuilt its lanes exactly through the coder");
    }

    scriptura_text(line, "\n  2. edges fold in order: on floor 1 of 4 x 12 x 48 x 48, 8-bit edges a then b against the "
                         "one table b(a(i))\n");
    scriptura_text(line, "  volumes  a,b = b(a)  b,a differs  a on 1, b on 2 differs\n");
    sim_flush(&results);
    unsigned long long folds = 0ull;
    unsigned long long orders = 0ull;
    unsigned long long blocks = 0ull;
    RootVolume *const folded = &volume[0];
    for (unsigned int drawn = 0u; ok && (drawn < ROOT_FOLD_VOLUMES); drawn += 1u)
    {
        camera.key = sim_draw(ROOT_KEY ^ ROOT_FOLD_PURPOSE, drawn);
        ok = root_volume_render(&results, folded, &camera);
        unsigned int *const first = program.table[0];
        unsigned int *const second = program.table[1];
        unsigned int *const both = program.table[2];
        root_permutation(first, ROOT_FOLD_BITS, sim_draw(camera.key, 1ull));
        root_permutation(second, ROOT_FOLD_BITS, sim_draw(camera.key, 2ull));
        for (unsigned int index = 0u; index < (1u << ROOT_FOLD_BITS); index += 1u)
        {
            both[index] = second[first[index]];
        }
        TowerEdge pair[2];
        pair[0].floor = ROOT_FOLD_FLOOR;
        pair[0].index_bits = ROOT_FOLD_BITS;
        pair[0].forward = first;
        pair[1].floor = ROOT_FOLD_FLOOR;
        pair[1].index_bits = ROOT_FOLD_BITS;
        pair[1].forward = second;
        TowerEdge single;
        single.floor = ROOT_FOLD_FLOOR;
        single.index_bits = ROOT_FOLD_BITS;
        single.forward = both;
        TowerEdge swapped[2];
        swapped[0] = pair[1];
        swapped[1] = pair[0];
        TowerEdge split[2];
        split[0] = pair[0];
        split[1] = pair[1];
        split[1].floor = ROOT_FOLD_FLOOR + 1u;
        ok = ok && root_lift_crystal(&results, folded, pair, 2u, crystal[0]);
        ok = ok && root_lift_crystal(&results, folded, &single, 1u, crystal[1]);
        ok = ok && root_lift_crystal(&results, folded, swapped, 2u, crystal[2]);
        ok = ok && root_lift_crystal(&results, folded, split, 2u, crystal[3]);
        const size_t bytes = (size_t)folded->lanes * sizeof(int);
        folds += (memcmp(crystal[0], crystal[1], bytes) == 0) ? 1ull : 0ull;
        orders += (memcmp(crystal[0], crystal[2], bytes) != 0) ? 1ull : 0ull;
        blocks += (memcmp(crystal[0], crystal[3], bytes) != 0) ? 1ull : 0ull;
    }
    scriptura_decimal_columns(line, ROOT_FOLD_VOLUMES, 9u);
    scriptura_decimal_columns(line, folds, 12u);
    scriptura_decimal_columns(line, orders, 13u);
    scriptura_decimal_columns(line, blocks, 24u);
    scriptura_character(line, '\n');
    sim_flush(&results);
    // "differs" is read on these keyed draws: tables that agree on every value the crystal holds would lay out the same
    // crystal swapped or split. The last two checks show order and blocking on these volumes, not for every table
    sim_check(&results, folds == ROOT_FOLD_VOLUMES,
              "two edges on one floor fold into the one table that composes them");
    sim_check(&results, orders == ROOT_FOLD_VOLUMES,
              "the fold keeps order: the swapped pair lays out a different crystal");
    sim_check(&results, blocks == ROOT_FOLD_VOLUMES, "a floor between two edges blocks the fold");

    const unsigned int width[ROOT_COST_WIDTHS] = {2u, 4u, 8u, 12u};
    const unsigned int floors = folded->floors;
    const unsigned int place_first[ROOT_PLACES] = {0u, floors / 2u, floors, 0u};
    const unsigned int place_last[ROOT_PLACES] = {0u, floors / 2u, floors, floors};
    unsigned long long plain_bits = 0ull;
    unsigned long long cost[ROOT_COST_WIDTHS][ROOT_PLACES];
    memset(cost, 0, sizeof(cost));
    unsigned long long trips = 0ull;
    unsigned long long exact_trips = 0ull;
    for (unsigned int drawn = 0u; ok && (drawn < ROOT_COST_VOLUMES); drawn += 1u)
    {
        camera.key = sim_draw(ROOT_KEY ^ ROOT_COST_PURPOSE, drawn);
        ok = root_volume_render(&results, folded, &camera);
        unsigned long long bits = 0ull;
        int exact = 0;
        ok = ok && root_crystal_trip(&results, folded, NULL, 0u, NULL, &bits, &exact);
        plain_bits += bits;
        trips += 1ull;
        exact_trips += (exact != 0) ? 1ull : 0ull;
        for (unsigned int wide = 0u; ok && (wide < ROOT_COST_WIDTHS); wide += 1u)
        {
            for (unsigned int placed = 0u; ok && (placed < ROOT_PLACES); placed += 1u)
            {
                root_program_place(&program, width[wide], place_first[placed], place_last[placed],
                                   sim_draw(camera.key, (wide * ROOT_PLACES) + placed));
                ok = root_crystal_trip(&results, folded, program.edge, program.count, NULL, &bits, &exact);
                cost[wide][placed] += bits;
                trips += 1ull;
                exact_trips += (exact != 0) ? 1ull : 0ull;
            }
        }
    }
    const unsigned long long coded = (unsigned long long)ROOT_COST_VOLUMES * folded->lanes;
    scriptura_text(line, "\n  3. the price: coded bits a voxel on 4 x 12 x 48 x 48 over ");
    scriptura_decimal(line, ROOT_COST_VOLUMES, 1u);
    scriptura_text(line, " volumes, one keyed random permutation a floor\n");
    scriptura_text(line, "  no edge: ");
    sim_fraction_print(line, plain_bits, coded, 3u);
    scriptura_text(line, "\n  floor (coefficients touched):  0 (");
    scriptura_decimal(line, root_region(folded->extent, 0u), 1u);
    scriptura_text(line, ")  ");
    scriptura_decimal(line, floors / 2u, 1u);
    scriptura_text(line, " (");
    scriptura_decimal(line, root_region(folded->extent, floors / 2u), 1u);
    scriptura_text(line, ")  ");
    scriptura_decimal(line, floors, 1u);
    scriptura_text(line, " collapsed (");
    scriptura_decimal(line, root_region(folded->extent, floors), 1u);
    scriptura_text(line, ")  every floor\n");
    scriptura_text(line, "  width    floor 0    middle    collapsed    every floor\n");
    for (unsigned int wide = 0u; wide < ROOT_COST_WIDTHS; wide += 1u)
    {
        scriptura_decimal_columns(line, width[wide], 7u);
        for (unsigned int placed = 0u; placed < ROOT_PLACES; placed += 1u)
        {
            scriptura_text(line, (placed == 0u) ? "     " : "    ");
            sim_fraction_print(line, cost[wide][placed], coded, 3u);
        }
        scriptura_character(line, '\n');
    }
    sim_flush(&results);
    sim_check(&results, exact_trips == trips, "every coded crystal, edged or not, rebuilt its lanes exactly");

    sim_check(&results, ok, "every volume rendered, lifted, coded and lowered");
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        free(crystal[at]);
    }
    for (unsigned int at = 0u; at < ROOT_EDGES_MAX; at += 1u)
    {
        free(program.table[at]);
    }
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        root_volume_close(&volume[shaped]);
    }
    return sim_close(&results, "root universal");
}
