// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// knf_identity_scene.cu: wide arithmetic, the scene, the camera and the pairs
#include "knf_identity_internal.h"

void knf_wide_add(KnfWide *sum, long long term)
{
    // a term's two's complement bits; a negative term carries all ones into the high word
    const unsigned long long bits = (unsigned long long)term;
    const unsigned long long low = sum->low + bits;
    sum->high += ((term < 0ll) ? 0xFFFFFFFFFFFFFFFFull : 0ull) + ((low < sum->low) ? 1ull : 0ull);
    sum->low = low;
}

int knf_wide_equal(const KnfWide *left, const KnfWide *right)
{
    return (left->low == right->low) && (left->high == right->high);
}

void knf_wide_exact(const KnfWide *wide, AnchorExactInteger *value)
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

void knf_exact_total(const KnfEntangled *entangled, AnchorExactInteger *total)
{
    AnchorExactInteger inside;
    AnchorExactInteger seam;
    knf_wide_exact(&entangled->inside, &inside);
    knf_wide_exact(&entangled->seam, &seam);
    sim_exact_sum(&inside, &seam, total);
}

void knf_departure_of(const AnchorExactInteger *truth, const AnchorExactInteger *drawn_sum,
                      AnchorExactInteger *departure)
{
    AnchorExactInteger scaled;
    sim_exact_scaled(truth, KNF_DRAWS, &scaled);
    sim_exact_less(&scaled, drawn_sum, departure);
}

void knf_scene(SimScene *scene, SimBody *body, int with_bodies)
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
                daughter->center[axis] = sim_body_at(parent, frame, axis);
            }
            daughter->center[1] += sign * (parent->range[1] / 2ll);
            daughter->velocity[1] = parent->velocity[1] + sign;
            daughter->range[1] = (parent->range[1] + 1ll) / 2ll + 1ll;
            daughter->born = frame;
            daughter->ended = KNF_FRAMES;
            daughter->parent = division;
        }
    }
}

void knf_camera(SimCamera *camera, unsigned long long key, unsigned long long pattern_range)
{
    memset(camera, 0, sizeof(*camera));
    camera->key = key;
    camera->offset = 100ull;
    camera->gain = 1ull;
    camera->read_square = 3ull;
    camera->pattern_range = pattern_range;
    camera->shot = 1ull;
}

void knf_boxes(const SimScene *scene, KnfBox *box, unsigned short *boxes)
{
    const unsigned long long side = scene->extent[0];
    memset(boxes, 0, (size_t)(side * side * side) * sizeof(unsigned short));
    for (unsigned int index = 0u; index < scene->bodies; index += 1u)
    {
        const SimBody *const body = &scene->body[index];
        KnfBox *const entry = &box[index];
        entry->filled = 0;
        for (unsigned long long frame = body->born; (frame < body->ended) && (frame < scene->frames); frame += 1ull)
        {
            long long low[SIM_AXES];
            long long high[SIM_AXES];
            int seen = 1;
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const long long center = sim_body_at(body, frame, axis);
                // the side is far below 2^63
                const long long last = (long long)side - 1ll;
                low[axis] = ((center - body->range[axis]) < 0ll) ? 0ll : (center - body->range[axis]);
                high[axis] = ((center + body->range[axis]) > last) ? last : (center + body->range[axis]);
                seen = seen && (low[axis] <= high[axis]);
            }
            if (seen == 0)
            {
                continue;
            }
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const int first = entry->filled == 0;
                entry->box[axis] = (first || (low[axis] < entry->box[axis])) ? low[axis] : entry->box[axis];
                entry->box[SIM_AXES + axis] =
                    (first || (high[axis] > entry->box[SIM_AXES + axis])) ? high[axis] : entry->box[SIM_AXES + axis];
            }
            entry->filled = 1;
        }
        if (entry->filled == 0)
        {
            continue;
        }
        // a held box lies inside the view. Each bound is non-negative and below the side
        for (unsigned long long depth = (unsigned long long)entry->box[0]; depth <= (unsigned long long)entry->box[3];
             depth += 1ull)
        {
            for (unsigned long long row = (unsigned long long)entry->box[1]; row <= (unsigned long long)entry->box[4];
                 row += 1ull)
            {
                for (unsigned long long column = (unsigned long long)entry->box[2];
                     column <= (unsigned long long)entry->box[5]; column += 1ull)
                {
                    // one bit a body, and the bodies fit 16 bits
                    boxes[(((depth * side) + row) * side) + column] |= (unsigned short)(1u << index);
                }
            }
        }
    }
}

static void knf_center(KnfRecord *record)
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
            // a density is below 11 * 2^16. 16 of them, and 16 times one, are far below 2^63
            record->centerd[(voxel * KNF_WINDOWS) + window] =
                (long long)(KNF_WINDOWS * density[window]) - (long long)total;
        }
    }
}

int knf_project(SimResults *results, const unsigned short *lanes, KnfRecord *record)
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
    const int ok =
        (status == 0L) && (error.kind == ENGINE_ERROR_NONE) && (broken == 0ull) && (history.windows == KNF_WINDOWS);
    if (ok == 0)
    {
        scriptura_text(&results->line, "    the entropy history errored: module ");
        // a module is a small non-negative enumerator
        scriptura_decimal(&results->line, (unsigned long long)error.module, 1u);
        scriptura_text(&results->line, " site ");
        scriptura_decimal(&results->line, error.site, 1u);
        scriptura_text(&results->line, ", broken voxels ");
        scriptura_decimal(&results->line, broken, 1u);
        scriptura_character(&results->line, '\n');
        return 0;
    }
    knf_center(record);
    return 1;
}

long long knf_pair(const long long *one, const long long *other)
{
    long long sum = 0ll;
    for (unsigned long long window = 0ull; window < KNF_WINDOWS; window += 1ull)
    {
        // each centerd density is below 2^24 in magnitude. 16 products stay below 2^52
        sum += one[window] * other[window];
    }
    return sum;
}
