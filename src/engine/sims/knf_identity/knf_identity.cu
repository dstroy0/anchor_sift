// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim_camera.h"

#include "entropy_history.h"

#define KNF_KEY 0x4E424F4459ull

#define KNF_WINDOWS 16ull

#define KNF_FRAMES (1ull + ((unsigned long long)ENGINE_HISTORY_WINDOW * KNF_WINDOWS))

#define KNF_SIDE 64ull

#define KNF_FOUNDERS 10u

#define KNF_DIVISIONS 3u

#define KNF_BODIES (KNF_FOUNDERS + (2u * KNF_DIVISIONS))

#define KNF_MOTIONS 48u

#define KNF_DRAWS 19u

#define KNF_SCALES 7u

#define KNF_CONTROLS 64u

#define KNF_CONTROL_SIDE 32ull

#define KNF_FLIPS 8192u

#define KNF_SIGMAS_SQUARED 25ull

#define KNF_BOX_FIELDS 6u

#define KNF_MOTION_PURPOSE 0x4D4F5645ull

#define KNF_NULL_PURPOSE 0x4E554C4Cull

#define KNF_FLIP_PURPOSE 0x464C4950ull

#define KNF_CONTROL_PURPOSE 0x434F4E54ull

static_assert(KNF_WINDOWS <= ENGINE_HISTORY_WINDOWS_MAX, "knf_identity: the run's windows fit the history");
static_assert(KNF_BODIES <= 16u, "knf_identity: a voxel's boxes are one bit a body in 16 bits");
static_assert((1ull << (KNF_SCALES - 1u)) == KNF_SIDE, "knf_identity: the tile sizes run 1 to the side by doubling");

static const unsigned int s_knf_axis_order[6][SIM_AXES] = {{0u, 1u, 2u}, {0u, 2u, 1u}, {1u, 0u, 2u},
                                                           {1u, 2u, 0u}, {2u, 0u, 1u}, {2u, 1u, 0u}};

typedef struct
{
    unsigned long long low;
    unsigned long long high;
} KnfWide;

typedef struct
{
    KnfWide inside;
    KnfWide seam;
    KnfWide body[KNF_BODIES];
} KnfEntangled;

typedef struct
{
    unsigned long long side;
    unsigned long long voxels;
    unsigned long long *history;
    unsigned long long *cloud;
    long long *centred;
} KnfRecord;

typedef struct
{
    int held;
    long long box[KNF_BOX_FIELDS];
} KnfBox;

static AnchorExactInteger s_knf_body_departure[KNF_SCALES][KNF_BODIES];

static void knf_wide_add(KnfWide *sum, long long term)
{
    // a term's two's complement bits; a negative term carries all ones into the high word
    const unsigned long long bits = (unsigned long long)term;
    const unsigned long long low = sum->low + bits;
    sum->high += ((term < 0ll) ? 0xFFFFFFFFFFFFFFFFull : 0ull) + ((low < sum->low) ? 1ull : 0ull);
    sum->low = low;
}

static int knf_wide_equal(const KnfWide *left, const KnfWide *right)
{
    return (left->low == right->low) && (left->high == right->high);
}

static void knf_wide_exact(const KnfWide *wide, AnchorExactInteger *value)
{
    const int negative = (wide->high >> 63u) != 0ull;
    // the magnitude of a negative sum is its two's complement negation across both words
    const unsigned long long low = negative ? (0ull - wide->low) : wide->low;
    const unsigned long long high = negative ? ((~wide->high) + ((wide->low == 0ull) ? 1ull : 0ull)) : wide->high;
    anchor_exact_zero(value);
    // each 64-bit word splits into two 32-bit limbs, low half first
    value->limb[0] = (uint32_t)(low & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(low >> 32u);
    value->limb[2] = (uint32_t)(high & 0xFFFFFFFFull);
    value->limb[3] = (uint32_t)(high >> 32u);
    value->sign = ((low | high) == 0ull) ? 0 : (negative ? -1 : 1);
}

static void knf_exact_total(const KnfEntangled *entangled, AnchorExactInteger *total)
{
    AnchorExactInteger inside;
    AnchorExactInteger seam;
    knf_wide_exact(&entangled->inside, &inside);
    knf_wide_exact(&entangled->seam, &seam);
    sim_exact_sum(&inside, &seam, total);
}

static void knf_departure_of(const AnchorExactInteger *truth, const AnchorExactInteger *drawn_sum,
                             AnchorExactInteger *departure)
{
    AnchorExactInteger scaled;
    sim_exact_scaled(truth, KNF_DRAWS, &scaled);
    sim_exact_less(&scaled, drawn_sum, departure);
}

static void knf_scene(SimScene *scene, SimBody *body, int with_bodies)
{
    memset(scene, 0, sizeof(*scene));
    scene->frames = KNF_FRAMES;
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        scene->extent[axis] = KNF_SIDE;
    }
    scene->background = 40ull;
    scene->ramp = 2ull;
    scene->bodies = (with_bodies != 0) ? KNF_BODIES : 0u;
    scene->body = body;
    if (with_bodies == 0)
    {
        return;
    }
    SimDraws draws;
    draws.key = KNF_KEY;
    draws.counter = 0ull;
    sim_founders_draw(&draws, scene, body, KNF_FOUNDERS);
    for (unsigned int division = 0u; division < KNF_DIVISIONS; division += 1u)
    {
        SimBody *const parent = &body[division];
        const unsigned long long frame = 8ull + (4ull * division);
        parent->ended = frame;
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            SimBody *const daughter = &body[KNF_FOUNDERS + (2u * division) + side];
            const long long sign = (side == 0u) ? -1ll : 1ll;
            *daughter = *parent;
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                daughter->centre[axis] = sim_body_at(parent, frame, axis);
            }
            daughter->centre[1] += sign * (parent->reach[1] / 2ll);
            daughter->velocity[1] = parent->velocity[1] + sign;
            daughter->reach[1] = (parent->reach[1] + 1ll) / 2ll + 1ll;
            daughter->born = frame;
            daughter->ended = KNF_FRAMES;
            daughter->parent = division;
        }
    }
}

static void knf_camera(SimCamera *camera, unsigned long long key, unsigned long long pattern_reach)
{
    memset(camera, 0, sizeof(*camera));
    camera->key = key;
    camera->offset = 100ull;
    camera->gain = 1ull;
    camera->read_square = 3ull;
    camera->pattern_reach = pattern_reach;
    camera->shot = 1ull;
}

static void knf_boxes(const SimScene *scene, KnfBox *box, unsigned short *boxes)
{
    const unsigned long long side = scene->extent[0];
    memset(boxes, 0, (size_t)(side * side * side) * sizeof(unsigned short));
    for (unsigned int index = 0u; index < scene->bodies; index += 1u)
    {
        const SimBody *const body = &scene->body[index];
        KnfBox *const held = &box[index];
        held->held = 0;
        for (unsigned long long frame = body->born; (frame < body->ended) && (frame < scene->frames); frame += 1ull)
        {
            long long low[SIM_AXES];
            long long high[SIM_AXES];
            int seen = 1;
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const long long centre = sim_body_at(body, frame, axis);
                // the side is far below 2^63
                const long long last = (long long)side - 1ll;
                low[axis] = ((centre - body->reach[axis]) < 0ll) ? 0ll : (centre - body->reach[axis]);
                high[axis] = ((centre + body->reach[axis]) > last) ? last : (centre + body->reach[axis]);
                seen = seen && (low[axis] <= high[axis]);
            }
            if (seen == 0)
            {
                continue;
            }
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const int first = held->held == 0;
                held->box[axis] = (first || (low[axis] < held->box[axis])) ? low[axis] : held->box[axis];
                held->box[SIM_AXES + axis] = (first || (high[axis] > held->box[SIM_AXES + axis]))
                                           ? high[axis] : held->box[SIM_AXES + axis];
            }
            held->held = 1;
        }
        if (held->held == 0)
        {
            continue;
        }
        // a held box lies inside the view, so each bound is non-negative and below the side
        for (unsigned long long depth = (unsigned long long)held->box[0]; depth <= (unsigned long long)held->box[3];
             depth += 1ull)
        {
            for (unsigned long long row = (unsigned long long)held->box[1]; row <= (unsigned long long)held->box[4];
                 row += 1ull)
            {
                for (unsigned long long column = (unsigned long long)held->box[2];
                     column <= (unsigned long long)held->box[5]; column += 1ull)
                {
                    // one bit a body, and the bodies fit 16 bits
                    boxes[(((depth * side) + row) * side) + column] |= (unsigned short)(1u << index);
                }
            }
        }
    }
}

static void knf_centre(KnfRecord *record)
{
    for (unsigned long long voxel = 0ull; voxel < record->voxels; voxel += 1ull)
    {
        unsigned long long density[KNF_WINDOWS];
        unsigned long long total = 0ull;
        for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
        {
            const unsigned long long word = record->history[(window * record->voxels) + voxel];
            unsigned long long weighted = 0ull;
            for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
            {
                weighted += ((word >> (4u * bit)) & 0xFull) << bit;
            }
            density[window] = weighted;
            total += weighted;
        }
        for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
        {
            // a density is below 11 * 2^16, so 16 of them, and 16 times one, are far below 2^63
            record->centred[(voxel * KNF_WINDOWS) + window] = (long long)(KNF_WINDOWS * density[window])
                                                            - (long long)total;
        }
    }
}

static int knf_project(SimTally *tally, const unsigned short *lanes, KnfRecord *record)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineHistory history;
    memset(&history, 0, sizeof(history));
    history.history = record->history;
    history.cloud = record->cloud;
    EntropyHistoryProjectRequest request;
    memset(&request, 0, sizeof(request));
    request.volume = lanes;
    request.extent[0] = KNF_FRAMES;
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        request.extent[1u + axis] = record->side;
    }
    request.history = &history;
    request.error = &error;
    unsigned long long broken = 1ull;
    const long status = entropy_history_project(&request, &broken);
    const int good = (status == 0L) && (error.kind == ENGINE_ERROR_NONE) && (broken == 0ull)
                  && (history.windows == KNF_WINDOWS);
    if (good == 0)
    {
        scriptura_text(&tally->line, "    the entropy history refused: module ");
        // a module is a small non-negative enumerator
        scriptura_decimal(&tally->line, (unsigned long long)error.module, 1u);
        scriptura_text(&tally->line, " site ");
        scriptura_decimal(&tally->line, error.site, 1u);
        scriptura_text(&tally->line, ", broken voxels ");
        scriptura_decimal(&tally->line, broken, 1u);
        scriptura_character(&tally->line, '\n');
        return 0;
    }
    knf_centre(record);
    return 1;
}

static long long knf_pair(const long long *one, const long long *other)
{
    long long sum = 0ll;
    for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
    {
        // each centred density is below 2^24 in magnitude, so 16 products stay below 2^52
        sum += one[window] * other[window];
    }
    return sum;
}

// the knf's entangled entropy: every voxel's centred windows against its neighbour's along z, y and x on the torus,
// split into the edges inside a tile of the given side and the seams between tiles; a box's share is its own edges
static void knf_entangle(const KnfRecord *record, const unsigned int *map, unsigned long long tile,
                         const unsigned short *boxes, KnfEntangled *result)
{
    memset(result, 0, sizeof(*result));
    const unsigned long long side = record->side;
    for (unsigned long long depth = 0ull; depth < side; depth += 1ull)
    {
        for (unsigned long long row = 0ull; row < side; row += 1ull)
        {
            for (unsigned long long column = 0ull; column < side; column += 1ull)
            {
                const unsigned long long place[SIM_AXES] = {depth, row, column};
                const unsigned long long voxel = (((depth * side) + row) * side) + column;
                const unsigned long long section = (map != NULL) ? map[voxel] : voxel;
                const long long *const here = &record->centred[section * KNF_WINDOWS];
                for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
                {
                    unsigned long long next[SIM_AXES] = {depth, row, column};
                    next[axis] = (place[axis] + 1ull) % side;
                    const unsigned long long across = (((next[0] * side) + next[1]) * side) + next[2];
                    const unsigned long long other = (map != NULL) ? map[across] : across;
                    const long long term = knf_pair(here, &record->centred[other * KNF_WINDOWS]);
                    const int within = (place[axis] / tile) == (next[axis] / tile);
                    knf_wide_add(within ? &result->inside : &result->seam, term);
                    if (boxes == NULL)
                    {
                        continue;
                    }
                    unsigned int common = (unsigned int)boxes[voxel] & (unsigned int)boxes[across];
                    for (unsigned int body = 0u; common != 0u; body += 1u)
                    {
                        if (((common >> body) & 1u) != 0u)
                        {
                            knf_wide_add(&result->body[body], term);
                            common &= ~(1u << body);
                        }
                    }
                }
            }
        }
    }
}

// a null draw that shuffles the knf's sections inside each tile of the given side, and moves nothing across a seam
static void knf_inside_draw(unsigned int *map, unsigned int *slot, unsigned long long side, unsigned long long tile,
                            unsigned long long key)
{
    const unsigned long long voxels = side * side * side;
    for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
    {
        // a voxel index is below 2^18 here
        map[voxel] = (unsigned int)voxel;
    }
    const unsigned long long across = side / tile;
    unsigned long long counter = 0ull;
    for (unsigned long long tile_depth = 0ull; tile_depth < across; tile_depth += 1ull)
    {
        for (unsigned long long tile_row = 0ull; tile_row < across; tile_row += 1ull)
        {
            for (unsigned long long tile_column = 0ull; tile_column < across; tile_column += 1ull)
            {
                unsigned long long held = 0ull;
                for (unsigned long long depth = tile_depth * tile; depth < (tile_depth + 1ull) * tile; depth += 1ull)
                {
                    for (unsigned long long row = tile_row * tile; row < (tile_row + 1ull) * tile; row += 1ull)
                    {
                        for (unsigned long long column = tile_column * tile; column < (tile_column + 1ull) * tile;
                             column += 1ull)
                        {
                            // a voxel index is below 2^18 here
                            slot[held] = (unsigned int)((((depth * side) + row) * side) + column);
                            held += 1ull;
                        }
                    }
                }
                for (unsigned long long remaining = held; remaining > 1ull; remaining -= 1ull)
                {
                    const unsigned long long pick = sim_draw_below(key, counter, remaining);
                    counter += 1ull;
                    const unsigned int kept = map[slot[remaining - 1ull]];
                    map[slot[remaining - 1ull]] = map[slot[pick]];
                    map[slot[pick]] = kept;
                }
            }
        }
    }
}

// the inverse draw: whole tiles move rigidly to shuffled places, and nothing inside a tile moves against its own
static void knf_between_draw(unsigned int *map, unsigned int *slot, unsigned long long side, unsigned long long tile,
                             unsigned long long key)
{
    const unsigned long long across = side / tile;
    const unsigned long long tiles = across * across * across;
    for (unsigned long long index = 0ull; index < tiles; index += 1ull)
    {
        // a tile index is below 2^18 here
        slot[index] = (unsigned int)index;
    }
    for (unsigned long long remaining = tiles; remaining > 1ull; remaining -= 1ull)
    {
        const unsigned long long pick = sim_draw_below(key, remaining, remaining);
        const unsigned int kept = slot[remaining - 1ull];
        slot[remaining - 1ull] = slot[pick];
        slot[pick] = kept;
    }
    for (unsigned long long depth = 0ull; depth < side; depth += 1ull)
    {
        for (unsigned long long row = 0ull; row < side; row += 1ull)
        {
            for (unsigned long long column = 0ull; column < side; column += 1ull)
            {
                const unsigned long long place = ((((depth / tile) * across) + (row / tile)) * across) + (column / tile);
                const unsigned long long source = slot[place];
                const unsigned long long source_depth = ((source / (across * across)) * tile) + (depth % tile);
                const unsigned long long source_row = (((source / across) % across) * tile) + (row % tile);
                const unsigned long long source_column = ((source % across) * tile) + (column % tile);
                // a voxel index is below 2^18 here
                map[(((depth * side) + row) * side) + column]
                    = (unsigned int)((((source_depth * side) + source_row) * side) + source_column);
            }
        }
    }
}

static int knf_identified(const KnfRecord *record, unsigned int *map, unsigned int *slot, unsigned long long key_base)
{
    KnfEntangled whole;
    knf_entangle(record, NULL, record->side, NULL, &whole);
    AnchorExactInteger truth;
    knf_exact_total(&whole, &truth);
    int wins = 1;
    for (unsigned int draw = 0u; draw < KNF_DRAWS; draw += 1u)
    {
        knf_inside_draw(map, slot, record->side, record->side, sim_draw(key_base, draw));
        KnfEntangled drawn;
        knf_entangle(record, map, record->side, NULL, &drawn);
        AnchorExactInteger total;
        knf_exact_total(&drawn, &total);
        wins = wins && (anchor_exact_compare(&total, &truth) < 0);
    }
    return wins;
}

static void knf_host_section(const unsigned short *series, unsigned long long *words)
{
    unsigned int counts[ENGINE_HISTORY_BITS];
    for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
    {
        counts[bit] = 0u;
    }
    unsigned long long window = 0ull;
    unsigned int in_window = 0u;
    for (unsigned long long frame = 1ull; frame < KNF_FRAMES; frame += 1ull)
    {
        const unsigned int flipped = (unsigned int)series[frame] ^ (unsigned int)series[frame - 1ull];
        for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
        {
            counts[bit] += (flipped >> bit) & 1u;
        }
        in_window += 1u;
        if ((in_window == ENGINE_HISTORY_WINDOW) || (frame == (KNF_FRAMES - 1ull)))
        {
            unsigned long long packed = 0ull;
            for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
            {
                packed |= (unsigned long long)counts[bit] << (4u * bit);
                counts[bit] = 0u;
            }
            words[window] = packed;
            window += 1ull;
            in_window = 0u;
        }
    }
}

static int knf_section_same(const KnfRecord *record, unsigned long long voxel, const unsigned long long *words)
{
    int same = 1;
    for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
    {
        same = same && (record->history[(window * record->voxels) + voxel] == words[window]);
    }
    return same;
}

static void knf_one_bit(SimTally *tally, const unsigned short *lanes, const KnfRecord *record)
{
    const unsigned long long voxels = record->voxels;
    unsigned short series[KNF_FRAMES];
    unsigned long long words[KNF_WINDOWS];
    unsigned long long mirror_differ = 0ull;
    for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
    {
        for (unsigned long long frame = 0ull; frame < KNF_FRAMES; frame += 1ull)
        {
            series[frame] = lanes[(frame * voxels) + voxel];
        }
        knf_host_section(series, words);
        mirror_differ += (knf_section_same(record, voxel, words) != 0) ? 0ull : 1ull;
    }
    sim_check(tally, mirror_differ == 0ull, "the host's walk of every voxel equals the engine's knf");
    unsigned long long agree = 0ull;
    unsigned long long unchanged = 0ull;
    for (unsigned int flip = 0u; flip < KNF_FLIPS; flip += 1u)
    {
        const unsigned long long key = KNF_KEY ^ KNF_FLIP_PURPOSE;
        const unsigned long long voxel = sim_draw_below(key, 3ull * flip, voxels);
        const unsigned long long frame = sim_draw_below(key, (3ull * flip) + 1ull, KNF_FRAMES);
        // a draw below 16 fits any unsigned int
        const unsigned int bit = (unsigned int)sim_draw_below(key, (3ull * flip) + 2ull, ENGINE_HISTORY_BITS);
        for (unsigned long long at = 0ull; at < KNF_FRAMES; at += 1ull)
        {
            series[at] = lanes[(at * voxels) + voxel];
        }
        // one bit of a 16-bit lane flipped, which stays in the lane's range
        series[frame] = (unsigned short)((unsigned int)series[frame] ^ (1u << bit));
        knf_host_section(series, words);
        const int same = knf_section_same(record, voxel, words);
        // a flip inside a window toggles two of its transitions, which cancel when exactly one of them flipped before
        const int predicted = (frame >= 1ull) && ((frame + 1ull) < KNF_FRAMES) && ((frame % ENGINE_HISTORY_WINDOW) != 0ull)
                           && (((((unsigned int)series[frame - 1ull] ^ (unsigned int)series[frame + 1ull]) >> bit) & 1u)
                               != 0u);
        agree += (same == predicted) ? 1ull : 0ull;
        unchanged += (same != 0) ? 1ull : 0ull;
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  one bit: the host's walk equals the knf at every voxel; of ");
    scriptura_decimal(line, KNF_FLIPS, 1u);
    scriptura_text(line, " single flipped bits, ");
    scriptura_decimal(line, unchanged, 1u);
    scriptura_text(line, " leave the knf unchanged, and the window rule names ");
    scriptura_decimal(line, agree, 1u);
    scriptura_text(line, " of them exactly\n");
    sim_check(tally, agree == KNF_FLIPS, "a flipped bit leaves the knf unchanged exactly when the window rule says");
}

static void knf_motion_place(unsigned long long side, unsigned int motion, const unsigned long long *shift,
                             const unsigned long long *place, unsigned long long *moved)
{
    const unsigned int *const order = s_knf_axis_order[motion / 8u];
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        const unsigned long long taken = place[order[axis]];
        const unsigned long long reflected = ((((motion & 7u) >> axis) & 1u) != 0u) ? (side - 1ull - taken) : taken;
        moved[axis] = (reflected + shift[axis]) % side;
    }
}

static void knf_motions(SimTally *tally, const unsigned short *lanes, unsigned short *moved, const KnfRecord *record,
                        KnfRecord *moved_record, unsigned int *target)
{
    const unsigned long long side = record->side;
    const unsigned long long voxels = record->voxels;
    KnfEntangled whole;
    knf_entangle(record, NULL, side, NULL, &whole);
    unsigned long long projected = 0ull;
    unsigned long long carried = 0ull;
    unsigned long long kept = 0ull;
    unsigned long long cloud_kept = 0ull;
    for (unsigned int motion = 0u; motion < KNF_MOTIONS; motion += 1u)
    {
        unsigned long long shift[SIM_AXES];
        for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
        {
            shift[axis] = sim_draw_below(KNF_KEY ^ KNF_MOTION_PURPOSE, (3ull * motion) + axis, side);
        }
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            const unsigned long long place[SIM_AXES] = {voxel / (side * side), (voxel / side) % side, voxel % side};
            unsigned long long to[SIM_AXES];
            knf_motion_place(side, motion, shift, place, to);
            // a voxel index is below 2^18 here
            target[voxel] = (unsigned int)((((to[0] * side) + to[1]) * side) + to[2]);
        }
        for (unsigned long long frame = 0ull; frame < KNF_FRAMES; frame += 1ull)
        {
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                moved[(frame * voxels) + target[voxel]] = lanes[(frame * voxels) + voxel];
            }
        }
        if (knf_project(tally, moved, moved_record) == 0)
        {
            continue;
        }
        projected += 1ull;
        unsigned long long differ = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            int same = 1;
            for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
            {
                same = same && (moved_record->history[(window * voxels) + target[voxel]]
                                == record->history[(window * voxels) + voxel]);
            }
            differ += (same != 0) ? 0ull : 1ull;
        }
        carried += (differ == 0ull) ? 1ull : 0ull;
        KnfEntangled turned;
        knf_entangle(moved_record, NULL, side, NULL, &turned);
        kept += knf_wide_equal(&turned.inside, &whole.inside) ? 1ull : 0ull;
        cloud_kept += (memcmp(moved_record->cloud, record->cloud,
                              (size_t)(KNF_WINDOWS * KNF_WINDOWS) * sizeof(unsigned long long)) == 0) ? 1ull : 0ull;
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  the exact motions (6 axis orders x 8 reflections, each with a keyed torus translation), the data moved\n");
    scriptura_text(line, "  over xyz and projected again: the knf carried as a whole on ");
    scriptura_decimal(line, carried, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, KNF_MOTIONS, 1u);
    scriptura_text(line, ", its entangled entropy unchanged on ");
    scriptura_decimal(line, kept, 1u);
    scriptura_text(line, ", its cloud unchanged on ");
    scriptura_decimal(line, cloud_kept, 1u);
    scriptura_character(line, '\n');
    sim_check(tally, projected == KNF_MOTIONS, "every moved volume projects, its parity law held");
    sim_check(tally, carried == KNF_MOTIONS, "the knf of the moved data is the moved knf, from every exact angle");
    sim_check(tally, kept == KNF_MOTIONS, "the entangled entropy reads the same from every exact angle");
    sim_check(tally, cloud_kept == KNF_MOTIONS, "the cloud reads the same from every exact angle");
}

static void knf_print_share(ScripturaLine *line, const AnchorExactInteger *part, const AnchorExactInteger *whole)
{
    scriptura_character(line, ' ');
    char room[32];
    ScripturaLine cell;
    cell.out = room;
    cell.room = sizeof(room);
    cell.at = 0ull;
    sim_ratio_print(&cell, part, whole, 3u);
    scriptura_finish(&cell);
    scriptura_text_columns(line, room, 9u);
}

static int knf_departure(SimTally *tally, const KnfRecord *record, const unsigned short *boxes, const SimScene *scene,
                         const KnfBox *box, unsigned long long tag, unsigned int *map, unsigned int *slot,
                         const char *name)
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
    unsigned long long split_held = 0ull;
    unsigned long long kept_held = 0ull;
    for (unsigned int scale = 0u; scale < KNF_SCALES; scale += 1u)
    {
        const unsigned long long tile = s_knf_tiles[scale];
        KnfEntangled split;
        knf_entangle(record, NULL, tile, NULL, &split);
        AnchorExactInteger split_total;
        knf_exact_total(&split, &split_total);
        split_held += (anchor_exact_compare(&split_total, &truth) == 0) ? 1ull : 0ull;
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
            kept_held += knf_wide_equal(&drawn.inside, &split.inside) ? 1ull : 0ull;
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
    ScripturaLine *const line = &tally->line;
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
    sim_check(tally, split_held == KNF_SCALES, "at every tile size the whole is its tiles plus its seams, exactly");
    sim_check(tally, kept_held == (KNF_SCALES * KNF_DRAWS), "a rigid move of whole tiles keeps every tile's inside exactly");
    sim_check(tally, inside_departure[0].sign == 0, "a tile of one voxel shuffles nothing: no departure");
    sim_check(tally, between_departure[KNF_SCALES - 1u].sign == 0, "one tile moved whole moves nothing: no departure");
    if (box == NULL)
    {
        sim_flush(tally);
        return inside_identified[KNF_SCALES - 1u];
    }
    scriptura_text(line, "    each body's box (zmin..zmax, ymin..ymax, xmin..xmax over its life), its own inside curve as a share of\n");
    scriptura_text(line, "    its free departure, and that departure as a share of the whole's\n");
    scriptura_text(line, "      body parent  born ended  vy vx  box z      y      x           2        4        8       16       32     share\n");
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
        if (box[index].held == 0)
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
    sim_flush(tally);
    return inside_identified[KNF_SCALES - 1u];
}

static void knf_controls(SimTally *tally, unsigned short *device_lanes, unsigned short *lanes, KnfRecord *record,
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
        int good = sim_render(tally, &scene, &camera, device_lanes, NULL, NULL, &clipped) && (clipped == 0ull);
        good = good && sim_took(tally, cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short),
                                                  cudaMemcpyDeviceToHost), "control lanes read");
        good = good && knf_project(tally, lanes, record);
        if (good == 0)
        {
            continue;
        }
        projected += 1ull;
        identified += (knf_identified(record, map, slot, sim_draw(KNF_KEY ^ KNF_CONTROL_PURPOSE, KNF_CONTROLS + control))
                       != 0) ? 1ull : 0ull;
    }
    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  the null's own rate: ");
    scriptura_decimal(line, KNF_CONTROLS, 1u);
    scriptura_text(line, " volumes of 32^3 with every voxel drawn alike (no bodies, no ramp, no fixed pattern), each\n");
    scriptura_text(line, "  against ");
    scriptura_decimal(line, KNF_DRAWS, 1u);
    scriptura_text(line, " free spatial draws: ");
    scriptura_decimal(line, identified, 1u);
    scriptura_text(line, " identified, where exchangeability bounds the rate by 1/");
    scriptura_decimal(line, KNF_DRAWS + 1u, 1u);
    scriptura_character(line, '\n');
    const unsigned long long scaled = (KNF_DRAWS + 1ull) * identified;
    const unsigned long long excess = (scaled > KNF_CONTROLS) ? (scaled - KNF_CONTROLS) : 0ull;
    sim_check(tally, projected == KNF_CONTROLS, "every control volume renders and projects");
    sim_check(tally, (excess * excess) <= (KNF_SIGMAS_SQUARED * KNF_CONTROLS * (KNF_DRAWS + 1ull)),
              "alike voxels are identified within 5 sigma of 1/(draws + 1)");
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
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
    record.centred = (long long *)malloc((size_t)history_words * sizeof(long long));
    moved_record = record;
    moved_record.history = (unsigned long long *)malloc((size_t)history_words * sizeof(unsigned long long));
    moved_record.cloud = (unsigned long long *)malloc((size_t)cloud_words * sizeof(unsigned long long));
    moved_record.centred = (long long *)malloc((size_t)history_words * sizeof(long long));
    unsigned short *device_lanes = NULL;
    int good = (lanes != NULL) && (moved != NULL) && (map != NULL) && (slot != NULL) && (boxes != NULL)
            && (record.history != NULL) && (record.cloud != NULL) && (record.centred != NULL)
            && (moved_record.history != NULL) && (moved_record.cloud != NULL) && (moved_record.centred != NULL);
    sim_check(&tally, good, "host buffers");
    good = good && sim_job_submit(&tally, "knf_identity", count, arguments,
                                  (4ull * lanes_count * sizeof(unsigned short))
                                      + ((history_words + cloud_words + 1ull) * sizeof(unsigned long long)));
    good = good && sim_took(&tally, cudaMalloc((void **)&device_lanes, lanes_count * sizeof(unsigned short)), "lanes");

    ScripturaLine *const line = &tally.line;
    scriptura_text(line, "  the knf's identity by spatial null permutation: the nbody lattice's law in a 64^3 cube over ");
    scriptura_decimal(line, KNF_FRAMES, 1u);
    scriptura_text(line, " frames,\n  ");
    scriptura_decimal(line, KNF_WINDOWS, 1u);
    scriptura_text(line, " windows of ");
    scriptura_decimal(line, ENGINE_HISTORY_WINDOW, 1u);
    scriptura_text(line, " transitions; a section is one voxel's windows, E couples each with its xyz neighbours\n");
    sim_flush(&tally);

    unsigned long long clipped = 0ull;
    good = good && sim_render(&tally, &scene, &camera, device_lanes, NULL, NULL, &clipped);
    good = good && sim_took(&tally, cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short),
                                               cudaMemcpyDeviceToHost), "lanes read");
    good = good && (clipped == 0ull);
    sim_check(&tally, good, "the lattice renders, no lane clipped");
    KnfBox box[KNF_BODIES];
    memset(box, 0, sizeof(box));
    if (good)
    {
        knf_boxes(&scene, box, boxes);
        good = knf_project(&tally, lanes, &record);
        sim_check(&tally, good, "the lattice's knf projects, its parity law held at every voxel");
    }
    if (good)
    {
        knf_one_bit(&tally, lanes, &record);
        sim_flush(&tally);
        knf_motions(&tally, lanes, moved, &record, &moved_record, map);
        sim_flush(&tally);
        const int identified = knf_departure(&tally, &record, boxes, &scene, box, 0ull, map, slot, "the lattice");
        sim_check(&tally, identified, "the lattice's knf is identified past every free spatial draw");
    }

    SimScene empty;
    knf_scene(&empty, body, 0);
    good = good && sim_render(&tally, &empty, &camera, device_lanes, NULL, NULL, &clipped);
    good = good && sim_took(&tally, cudaMemcpy(lanes, device_lanes, lanes_count * sizeof(unsigned short),
                                               cudaMemcpyDeviceToHost), "empty lanes read");
    good = good && (clipped == 0ull) && knf_project(&tally, lanes, &record);
    sim_check(&tally, good, "the same scene with no bodies renders and projects");
    if (good)
    {
        knf_departure(&tally, &record, NULL, &empty, NULL, 1ull, map, slot, "the same camera and ramp, no bodies");
        knf_controls(&tally, device_lanes, lanes, &record, map, slot);
    }

    cudaFree(device_lanes);
    free(moved_record.centred);
    free(moved_record.cloud);
    free(moved_record.history);
    free(record.centred);
    free(record.cloud);
    free(record.history);
    free(boxes);
    free(slot);
    free(map);
    free(moved);
    free(lanes);
    return sim_close(&tally, "knf identity");
}
