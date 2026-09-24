// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The root universal: the tower with reversible lookup edges sandwiched between its floors, run on
// camera-law volumes. Three measurements: the root stays exact (random edge programs rebuild every lane
// through the full crystal path of lift, code, wipe, decode, lower); edges fold in order (two edges on
// one floor lay the same crystal as the one table that composes them, and a floor between them blocks
// the fold); and the price (what an unfitted edge costs the magnitude coder, by table width and floor).

#include "sim_camera.h"

#include "compression.h"
#include "tower.h"

#define ROOT_KEY 0x524F4F54ull

#define ROOT_FOUNDER_PURPOSE 0x464F554Eull

#define ROOT_PROGRAM_PURPOSE 0x50524F47ull

#define ROOT_FOLD_PURPOSE 0x464F4C44ull

#define ROOT_COST_PURPOSE 0x434F5354ull

#define ROOT_FOUNDERS 6u

#define ROOT_EXTENTS 2u

#define ROOT_EXACT_VOLUMES 24u

#define ROOT_FOLD_VOLUMES 8u

#define ROOT_COST_VOLUMES 8u

#define ROOT_EDGES_MOST 8u

#define ROOT_EDGES_DRAWN_MOST 6u

#define ROOT_BITS_DRAWN_MOST 12u

#define ROOT_COST_WIDTHS 4u

#define ROOT_PLACES 4u

#define ROOT_FOLD_BITS 8u

#define ROOT_FOLD_FLOOR 1u

#define ROOT_TABLE_ROOM (1u << TOWER_EDGE_INDEX_BITS_MOST)

typedef struct
{
    SimScene scene;
    SimBody body[ROOT_FOUNDERS];
    unsigned long long extent[4];
    unsigned long long lanes;
    unsigned int floors;
    unsigned short *host;
    unsigned short *device;
    unsigned short *rebuilt;
} RootVolume;

typedef struct
{
    unsigned int *table[ROOT_EDGES_MOST];
    TowerEdge edge[ROOT_EDGES_MOST];
    unsigned int count;
} RootProgram;

static unsigned int root_floors(const unsigned long long extent[4])
{
    unsigned long long left[4];
    memcpy(left, extent, sizeof(left));
    unsigned int floors = 0u;
    while ((left[0] > 1ull) || (left[1] > 1ull) || (left[2] > 1ull) || (left[3] > 1ull))
    {
        floors += 1u;
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            left[axis] = (left[axis] + 1ull) / 2ull;
        }
    }
    return floors;
}

// the coefficients an edge at `floor` acts on: the approximation after `floor` halvings of every axis
static unsigned long long root_region(const unsigned long long extent[4], unsigned int floor)
{
    unsigned long long left[4];
    memcpy(left, extent, sizeof(left));
    for (unsigned int level = 0u; level < floor; level += 1u)
    {
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            left[axis] = (left[axis] + 1ull) / 2ull;
        }
    }
    return left[0] * left[1] * left[2] * left[3];
}

static void root_permutation(unsigned int *table, unsigned int bits, unsigned long long key)
{
    const unsigned int entries = 1u << bits;
    for (unsigned int index = 0u; index < entries; index += 1u)
    {
        table[index] = index;
    }
    for (unsigned int index = entries - 1u; index > 0u; index -= 1u)
    {
        // the draw below index + 1 is at most index, a position inside the table
        const unsigned int other = (unsigned int)sim_draw_below(key, index, (unsigned long long)index + 1ull);
        const unsigned int held = table[index];
        table[index] = table[other];
        table[other] = held;
    }
}

static void root_program_draw(RootProgram *program, unsigned int floors, unsigned long long key, int reach_widest)
{
    // the draw below the edge ceiling is far under 2^32
    program->count = 1u + (unsigned int)sim_draw_below(key, 0ull, ROOT_EDGES_DRAWN_MOST);
    for (unsigned int at = 0u; at < program->count; at += 1u)
    {
        const unsigned long long counter = 1ull + (3ull * at);
        TowerEdge *const edge = &program->edge[at];
        // the floor draw is at most floors and the width draw below the width ceiling, both under 2^32
        edge->floor = (unsigned int)sim_draw_below(key, counter, (unsigned long long)floors + 1ull);
        edge->index_bits = 1u + (unsigned int)sim_draw_below(key, counter + 1ull, ROOT_BITS_DRAWN_MOST);
        if ((reach_widest != 0) && (at == 0u))
        {
            edge->index_bits = TOWER_EDGE_INDEX_BITS_MOST;
        }
        root_permutation(program->table[at], edge->index_bits, sim_draw(key, counter + 2ull));
        edge->forward = program->table[at];
    }
}

// one edge of `bits` on every floor from `first` to `last`, each its own keyed permutation
static void root_program_place(RootProgram *program, unsigned int bits, unsigned int first, unsigned int last,
                               unsigned long long key)
{
    program->count = 0u;
    for (unsigned int floor = first; floor <= last; floor += 1u)
    {
        const unsigned int at = program->count;
        TowerEdge *const edge = &program->edge[at];
        edge->floor = floor;
        edge->index_bits = bits;
        root_permutation(program->table[at], bits, sim_draw(key, floor));
        edge->forward = program->table[at];
        program->count += 1u;
    }
}

static int root_volume_open(SimTally *tally, RootVolume *volume, const unsigned long long shape[4])
{
    memset(&volume->scene, 0, sizeof(volume->scene));
    memcpy(volume->extent, shape, sizeof(volume->extent));
    volume->scene.frames = shape[0];
    volume->scene.extent[0] = shape[1];
    volume->scene.extent[1] = shape[2];
    volume->scene.extent[2] = shape[3];
    volume->scene.background = 200ull;
    volume->scene.ramp = 1ull;
    volume->scene.bodies = ROOT_FOUNDERS;
    volume->lanes = shape[0] * shape[1] * shape[2] * shape[3];
    volume->floors = root_floors(shape);
    volume->host = (unsigned short *)malloc((size_t)volume->lanes * sizeof(unsigned short));
    volume->rebuilt = (unsigned short *)malloc((size_t)volume->lanes * sizeof(unsigned short));
    int good = (volume->host != NULL) && (volume->rebuilt != NULL);
    sim_check(tally, good, "the volume's host lanes were held");
    good = good && sim_took(tally, cudaMalloc((void **)&volume->device, volume->lanes * sizeof(unsigned short)),
                            "device lanes");
    return good;
}

static void root_volume_close(RootVolume *volume)
{
    cudaFree(volume->device);
    free(volume->host);
    free(volume->rebuilt);
}

static int root_volume_render(SimTally *tally, RootVolume *volume, const SimCamera *camera)
{
    SimDraws draws;
    draws.key = camera->key ^ ROOT_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &volume->scene, volume->body, ROOT_FOUNDERS);
    volume->scene.body = volume->body;
    unsigned long long clipped = 0ull;
    int good = sim_render(tally, &volume->scene, camera, volume->device, NULL, NULL, &clipped);
    sim_check(tally, good && (clipped == 0ull), "the volume rendered with nothing clipped");
    good = good && (clipped == 0ull)
        && sim_took(tally, cudaMemcpy(volume->host, volume->device, volume->lanes * sizeof(unsigned short),
                                      cudaMemcpyDeviceToHost),
                    "lanes read");
    return good;
}

static int root_lift_crystal(SimTally *tally, const RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
                             int *crystal)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = volume->device;
    memcpy(lift.extent, volume->extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.edges = edges;
    lift.edge_count = edge_count;
    lift.error = &error;
    int good = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(tally, good, "tower_lift accepted the edge program");
    good = good && sim_took(tally, cudaMemcpy(crystal, coefficients, volume->lanes * sizeof(int), cudaMemcpyDeviceToHost),
                            "crystal read");
    return good;
}

// the full crystal path: lift with the edges, code, wipe the held coefficients so only the stream carries
// them, decode, lower with the same edges, and compare the rebuilt lanes with the rendered ones
static int root_crystal_trip(SimTally *tally, RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
                             int *crystal, unsigned long long *bits, int *exact)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    *exact = 0;
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = volume->device;
    memcpy(lift.extent, volume->extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.edges = edges;
    lift.edge_count = edge_count;
    lift.error = &error;
    int good = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(tally, good, "tower_lift accepted the edge program");
    if (good && (crystal != NULL))
    {
        good = sim_took(tally, cudaMemcpy(crystal, coefficients, volume->lanes * sizeof(int), cudaMemcpyDeviceToHost),
                        "crystal read");
    }
    unsigned long long chunks = 0ull;
    const unsigned long long *offsets = NULL;
    const unsigned int *stream = NULL;
    if (good)
    {
        CompressionEncodeRequest code;
        memset(&code, 0, sizeof(code));
        code.device_coefficients = coefficients;
        code.count = volume->lanes;
        code.device_scratch = scratch;
        code.chunks = &chunks;
        code.bits = bits;
        code.offsets = &offsets;
        code.stream = &stream;
        code.error = &error;
        good = (compression_encode(&code) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(tally, good, "compression_encode coded the crystal");
    }
    int *room = NULL;
    if (good)
    {
        good = (tower_room(volume->extent, &room, &error) == 0L)
            && sim_took(tally, cudaMemset(room, 0, volume->lanes * sizeof(int)), "crystal wipe");
        sim_check(tally, good, "the held crystal was wiped before decoding");
    }
    if (good)
    {
        CompressionDecodeRequest decode;
        memset(&decode, 0, sizeof(decode));
        decode.offsets = offsets;
        decode.chunks = chunks;
        decode.stream = stream;
        decode.bits = *bits;
        decode.count = volume->lanes;
        decode.device_coefficients = room;
        decode.error = &error;
        good = (compression_decode(&decode) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(tally, good, "compression_decode read the crystal back");
    }
    unsigned long long mismatches = 1ull;
    if (good)
    {
        const unsigned short *device_rebuilt = NULL;
        TowerLowerRequest lower;
        memset(&lower, 0, sizeof(lower));
        lower.device_lanes = volume->device;
        memcpy(lower.extent, volume->extent, sizeof(lower.extent));
        lower.mismatches = &mismatches;
        lower.device_rebuilt = &device_rebuilt;
        lower.rebuilt = volume->rebuilt;
        lower.edges = edges;
        lower.edge_count = edge_count;
        lower.error = &error;
        good = (tower_lower(&lower) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(tally, good, "tower_lower accepted the edge program");
    }
    if (good)
    {
        *exact = (mismatches == 0ull)
              && (memcmp(volume->rebuilt, volume->host, (size_t)volume->lanes * sizeof(unsigned short)) == 0);
    }
    return good;
}

static void root_shape_print(ScripturaLine *line, const unsigned long long extent[4])
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
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    ScripturaLine *const line = &tally.line;

    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_reach = 8ull;
    camera.shot = 1ull;

    const unsigned long long shape[ROOT_EXTENTS][4] = {{4ull, 12ull, 48ull, 48ull}, {3ull, 13ull, 37ull, 41ull}};
    RootVolume volume[ROOT_EXTENTS];
    memset(volume, 0, sizeof(volume));
    unsigned long long declared = 0ull;
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        declared += shape[shaped][0] * shape[shaped][1] * shape[shaped][2] * shape[shaped][3] * sizeof(unsigned short);
    }
    int good = sim_job_submit(&tally, "root_universal", 0, NULL, declared);
    unsigned long long lanes_most = 0ull;
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        good = good && root_volume_open(&tally, &volume[shaped], shape[shaped]);
        lanes_most = (volume[shaped].lanes > lanes_most) ? volume[shaped].lanes : lanes_most;
    }
    RootProgram program;
    memset(&program, 0, sizeof(program));
    for (unsigned int at = 0u; at < ROOT_EDGES_MOST; at += 1u)
    {
        program.table[at] = (unsigned int *)malloc((size_t)ROOT_TABLE_ROOM * sizeof(unsigned int));
        good = good && (program.table[at] != NULL);
    }
    int *crystal[4];
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        crystal[at] = (int *)malloc((size_t)lanes_most * sizeof(int));
        good = good && (crystal[at] != NULL);
    }
    sim_check(&tally, good, "the sim's tables and crystals were held");

    scriptura_text(line, "  the root universal: the tower with reversible lookup edges between its floors, on camera-law volumes\n");
    scriptura_text(line, "  (signal 200 e plus a ramp of 1 e a column, 6 moving bodies of 150 to 400 e, read variance 3, fixed pattern 0 to 8)\n\n");

    scriptura_text(line, "  1. the root stays exact: random edge programs (1 to 6 edges, random floors, widths 1 to 12 bits, and one\n");
    scriptura_text(line, "     20-bit edge per extent) through lift, code, wipe, decode, lower\n");
    scriptura_text(line, "  extent (t x z x y x)  floors  volumes  edges laid  plain exact  edged exact  crystals changed\n");
    sim_flush(&tally);
    for (unsigned int shaped = 0u; good && (shaped < ROOT_EXTENTS); shaped += 1u)
    {
        RootVolume *const here = &volume[shaped];
        unsigned long long plain_exact = 0ull;
        unsigned long long edged_exact = 0ull;
        unsigned long long changed = 0ull;
        unsigned long long laid = 0ull;
        for (unsigned int drawn = 0u; good && (drawn < ROOT_EXACT_VOLUMES); drawn += 1u)
        {
            camera.key = sim_draw(ROOT_KEY, ((unsigned long long)shaped * ROOT_EXACT_VOLUMES) + drawn);
            good = root_volume_render(&tally, here, &camera);
            unsigned long long bits = 0ull;
            int exact = 0;
            good = good && root_crystal_trip(&tally, here, NULL, 0u, crystal[0], &bits, &exact);
            plain_exact += (exact != 0) ? 1ull : 0ull;
            root_program_draw(&program, here->floors, sim_draw(camera.key, ROOT_PROGRAM_PURPOSE), drawn == 0u);
            good = good && root_crystal_trip(&tally, here, program.edge, program.count, crystal[1], &bits, &exact);
            edged_exact += (exact != 0) ? 1ull : 0ull;
            changed += (memcmp(crystal[0], crystal[1], (size_t)here->lanes * sizeof(int)) != 0) ? 1ull : 0ull;
            laid += program.count;
        }
        scriptura_text(line, "  ");
        root_shape_print(line, here->extent);
        scriptura_decimal_columns(line, here->floors, 11u);
        scriptura_decimal_columns(line, ROOT_EXACT_VOLUMES, 9u);
        scriptura_decimal_columns(line, laid, 12u);
        scriptura_decimal_columns(line, plain_exact, 13u);
        scriptura_decimal_columns(line, edged_exact, 13u);
        scriptura_decimal_columns(line, changed, 18u);
        scriptura_character(line, '\n');
        sim_flush(&tally);
        sim_check(&tally, plain_exact == ROOT_EXACT_VOLUMES, "every plain crystal rebuilt its lanes exactly");
        sim_check(&tally, edged_exact == ROOT_EXACT_VOLUMES,
                  "every edged crystal rebuilt its lanes exactly through the coder");
    }

    scriptura_text(line, "\n  2. edges fold in order: on floor 1 of 4 x 12 x 48 x 48, 8-bit edges a then b against the one table b(a(i))\n");
    scriptura_text(line, "  volumes  a,b = b(a)  b,a differs  a on 1, b on 2 differs\n");
    sim_flush(&tally);
    unsigned long long folds = 0ull;
    unsigned long long orders = 0ull;
    unsigned long long blocks = 0ull;
    RootVolume *const folded = &volume[0];
    for (unsigned int drawn = 0u; good && (drawn < ROOT_FOLD_VOLUMES); drawn += 1u)
    {
        camera.key = sim_draw(ROOT_KEY ^ ROOT_FOLD_PURPOSE, drawn);
        good = root_volume_render(&tally, folded, &camera);
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
        good = good && root_lift_crystal(&tally, folded, pair, 2u, crystal[0]);
        good = good && root_lift_crystal(&tally, folded, &single, 1u, crystal[1]);
        good = good && root_lift_crystal(&tally, folded, swapped, 2u, crystal[2]);
        good = good && root_lift_crystal(&tally, folded, split, 2u, crystal[3]);
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
    sim_flush(&tally);
    sim_check(&tally, folds == ROOT_FOLD_VOLUMES, "two edges on one floor fold into the one table that composes them");
    sim_check(&tally, orders == ROOT_FOLD_VOLUMES, "the fold keeps order: the swapped pair lays a different crystal");
    sim_check(&tally, blocks == ROOT_FOLD_VOLUMES, "a floor between two edges blocks the fold");

    const unsigned int width[ROOT_COST_WIDTHS] = {2u, 4u, 8u, 12u};
    const unsigned int floors = folded->floors;
    const unsigned int place_first[ROOT_PLACES] = {0u, floors / 2u, floors, 0u};
    const unsigned int place_last[ROOT_PLACES] = {0u, floors / 2u, floors, floors};
    unsigned long long plain_bits = 0ull;
    unsigned long long cost[ROOT_COST_WIDTHS][ROOT_PLACES];
    memset(cost, 0, sizeof(cost));
    unsigned long long trips = 0ull;
    unsigned long long exact_trips = 0ull;
    for (unsigned int drawn = 0u; good && (drawn < ROOT_COST_VOLUMES); drawn += 1u)
    {
        camera.key = sim_draw(ROOT_KEY ^ ROOT_COST_PURPOSE, drawn);
        good = root_volume_render(&tally, folded, &camera);
        unsigned long long bits = 0ull;
        int exact = 0;
        good = good && root_crystal_trip(&tally, folded, NULL, 0u, NULL, &bits, &exact);
        plain_bits += bits;
        trips += 1ull;
        exact_trips += (exact != 0) ? 1ull : 0ull;
        for (unsigned int wide = 0u; good && (wide < ROOT_COST_WIDTHS); wide += 1u)
        {
            for (unsigned int placed = 0u; good && (placed < ROOT_PLACES); placed += 1u)
            {
                root_program_place(&program, width[wide], place_first[placed], place_last[placed],
                                   sim_draw(camera.key, (wide * ROOT_PLACES) + placed));
                good = root_crystal_trip(&tally, folded, program.edge, program.count, NULL, &bits, &exact);
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
    sim_flush(&tally);
    sim_check(&tally, exact_trips == trips, "every coded crystal, edged or not, rebuilt its lanes exactly");

    sim_check(&tally, good, "every volume rendered, lifted, coded and lowered");
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        free(crystal[at]);
    }
    for (unsigned int at = 0u; at < ROOT_EDGES_MOST; at += 1u)
    {
        free(program.table[at]);
    }
    for (unsigned int shaped = 0u; shaped < ROOT_EXTENTS; shaped += 1u)
    {
        root_volume_close(&volume[shaped]);
    }
    return sim_close(&tally, "root universal");
}
