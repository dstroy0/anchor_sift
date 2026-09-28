// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// root_universal_program.cu: floors, regions, programs, volumes and the crystal
#include "root_universal_internal.h"

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
unsigned long long root_region(const unsigned long long extent[4], unsigned int floor)
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

void root_permutation(unsigned int *table, unsigned int bits, unsigned long long key)
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
        const unsigned int temporary = table[index];
        table[index] = table[other];
        table[other] = temporary;
    }
}

void root_program_draw(RootProgram *program, unsigned int floors, unsigned long long key, int range_widest)
{
    // the draw below the edge ceiling is far under 2^32
    program->count = 1u + (unsigned int)sim_draw_below(key, 0ull, ROOT_EDGES_DRAWN_MAX);
    for (unsigned int at = 0u; at < program->count; at += 1u)
    {
        const unsigned long long counter = 1ull + (3ull * at);
        TowerEdge *const edge = &program->edge[at];
        // the floor draw is at most floors and the width draw below the width ceiling, both under 2^32
        edge->floor = (unsigned int)sim_draw_below(key, counter, (unsigned long long)floors + 1ull);
        edge->index_bits = 1u + (unsigned int)sim_draw_below(key, counter + 1ull, ROOT_BITS_DRAWN_MAX);
        if ((range_widest != 0) && (at == 0u))
        {
            edge->index_bits = TOWER_EDGE_INDEX_BITS_MAX;
        }
        root_permutation(program->table[at], edge->index_bits, sim_draw(key, counter + 2ull));
        edge->forward = program->table[at];
    }
}

// one edge of `bits` on every floor from `first` to `last`, each its own keyed permutation
void root_program_place(RootProgram *program, unsigned int bits, unsigned int first, unsigned int last,
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

int root_volume_open(SimResults *results, RootVolume *volume, const unsigned long long extent[4])
{
    memset(&volume->scene, 0, sizeof(volume->scene));
    memcpy(volume->extent, extent, sizeof(volume->extent));
    volume->scene.frames = extent[0];
    volume->scene.extent[0] = extent[1];
    volume->scene.extent[1] = extent[2];
    volume->scene.extent[2] = extent[3];
    volume->scene.background = 200ull;
    volume->scene.ramp = 1ull;
    volume->scene.bodies = ROOT_FOUNDERS;
    volume->lanes = extent[0] * extent[1] * extent[2] * extent[3];
    volume->floors = root_floors(extent);
    volume->host = (unsigned short *)malloc((size_t)volume->lanes * sizeof(unsigned short));
    volume->rebuilt = (unsigned short *)malloc((size_t)volume->lanes * sizeof(unsigned short));
    int ok = (volume->host != NULL) && (volume->rebuilt != NULL);
    sim_check(results, ok, "the volume's host lanes were held");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&volume->device, volume->lanes * sizeof(unsigned short)),
                                "device lanes");
    return ok;
}

void root_volume_close(RootVolume *volume)
{
    cudaFree(volume->device);
    free(volume->host);
    free(volume->rebuilt);
}

int root_volume_render(SimResults *results, RootVolume *volume, const SimCamera *camera)
{
    SimDraws draws;
    draws.key = camera->key ^ ROOT_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &volume->scene, volume->body, ROOT_FOUNDERS);
    volume->scene.body = volume->body;
    unsigned long long clipped = 0ull;
    int ok = sim_render(results, &volume->scene, camera, volume->device, NULL, NULL, &clipped);
    sim_check(results, ok && (clipped == 0ull), "the volume rendered with nothing clipped");
    ok = ok && (clipped == 0ull) &&
         sim_status_check(
             results,
             cudaMemcpy(volume->host, volume->device, volume->lanes * sizeof(unsigned short), cudaMemcpyDeviceToHost),
             "lanes read");
    return ok;
}

int root_lift_crystal(SimResults *results, const RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
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
    int ok = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(results, ok, "tower_lift accepted the edge program");
    ok = ok && sim_status_check(results,
                                cudaMemcpy(crystal, coefficients, volume->lanes * sizeof(int), cudaMemcpyDeviceToHost),
                                "crystal read");
    return ok;
}

// the full crystal path: lift with the edges, code, wipe the kept coefficients so only the stream carries
// them, decode, lower with the same edges, and compare the rebuilt lanes with the rendered ones
int root_crystal_trip(SimResults *results, RootVolume *volume, const TowerEdge *edges, unsigned int edge_count,
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
    int ok = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(results, ok, "tower_lift accepted the edge program");
    if (ok && (crystal != NULL))
    {
        ok = sim_status_check(results,
                              cudaMemcpy(crystal, coefficients, volume->lanes * sizeof(int), cudaMemcpyDeviceToHost),
                              "crystal read");
    }
    unsigned long long chunks = 0ull;
    const unsigned long long *offsets = NULL;
    const unsigned int *stream = NULL;
    if (ok)
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
        ok = (compression_encode(&code) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(results, ok, "compression_encode coded the crystal");
    }
    int *device_buffer = NULL;
    if (ok)
    {
        ok = (tower_capacity(volume->extent, &device_buffer, &error) == 0L) &&
             sim_status_check(results, cudaMemset(device_buffer, 0, volume->lanes * sizeof(int)), "crystal wipe");
        sim_check(results, ok, "the held crystal was wiped before decoding");
    }
    if (ok)
    {
        CompressionDecodeRequest decode;
        memset(&decode, 0, sizeof(decode));
        decode.offsets = offsets;
        decode.chunks = chunks;
        decode.stream = stream;
        decode.bits = *bits;
        decode.count = volume->lanes;
        decode.device_coefficients = device_buffer;
        decode.error = &error;
        ok = (compression_decode(&decode) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(results, ok, "compression_decode read the crystal back");
    }
    unsigned long long mismatches = 1ull;
    if (ok)
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
        ok = (tower_lower(&lower) == 0L) && (error.kind == ENGINE_ERROR_NONE);
        sim_check(results, ok, "tower_lower accepted the edge program");
    }
    if (ok)
    {
        *exact = (mismatches == 0ull) &&
                 (memcmp(volume->rebuilt, volume->host, (size_t)volume->lanes * sizeof(unsigned short)) == 0);
    }
    return ok;
}
