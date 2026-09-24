// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "track.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

void track_error_report(const char *what, const EngineError *error)
{
    static const char *const KINDS[4] = {"none", "request", "resource", "logic"};
    // the kind is one of the four enumerated values, so it re-signs to unsigned int and indexes KINDS exactly
    const unsigned int kind = ((unsigned int)error->kind < 4u) ? (unsigned int)error->kind : 0u;
    // an address converts to uintptr_t exactly, and the image base is at or below every address inside the image
    const uintptr_t base = (uintptr_t)error->imagebase;
    // an address converts to uintptr_t exactly
    const uintptr_t execaddr = (uintptr_t)error->execaddr;
    // the module is one of the enumerated values, so it re-signs to unsigned int exactly
    fprintf(stderr, "  %s: %s error, module %u, site %u, status %d, execaddr +0x%llx, evacaddr %p, frames", what,
            KINDS[kind], (unsigned int)error->module, error->site, error->status,
            (unsigned long long)(execaddr - base), error->evacaddr);
    for (unsigned int frame = 0u; frame < error->frame_count; frame += 1u)
    {
        // an address converts to uintptr_t exactly
        const uintptr_t at = (uintptr_t)error->frames[frame];
        fprintf(stderr, " +0x%llx", (unsigned long long)(at - base));
    }
    fprintf(stderr, "\n");
}

int track_frame_bodies(EngineBuffers *buffers, unsigned int slot, TreeFrame *frame)
{
    EngineBodiesRequest request;
    memset(&request, 0, sizeof(request));
    request.residual.volume = buffers->volume;
    request.residual.depth = buffers->depth;
    request.residual.height = buffers->height;
    request.residual.width = buffers->width;
    memcpy(request.residual.smooth_orders, SMOOTH_ORDERS, sizeof(request.residual.smooth_orders));
    memcpy(request.residual.background_orders, BACKGROUND_ORDERS, sizeof(request.residual.background_orders));
    request.residual.unit_sweep = buffers->unit_sweep;
    request.room = buffers->peak_room;
    request.bodies = buffers->bodies;
    request.labels = buffers->labels[slot];
    request.positive_words = buffers->positive[slot];
    EngineError error;
    memset(&error, 0, sizeof(error));
    request.error = &error;
    EngineLeaves leaves;
    if (engine_frame_bodies(&request, &leaves) == ENGINE_REFUSED)
    {
        track_error_report("bodies", &error);
        return 0;
    }
    frame->leaf_count = leaves.leaf_count;
    frame->peaks = leaves.peaks;
    frame->sizes = leaves.sizes;
    frame->sums = leaves.sums;
    frame->moments = leaves.moments;
    frame->touches = leaves.touches;
    frame->joined = leaves.joined;
    frame->joined_count = leaves.joined_count;
    return 1;
}

void track_group_voxels(EngineBuffers *buffers, unsigned int slot, const unsigned int *labels, const TreeFrame *frame)
{
    EngineGroupRequest request;
    memset(&request, 0, sizeof(request));
    request.voxels = buffers->depth * buffers->height * buffers->width;
    request.labels = labels;
    request.peaks = frame->peaks;
    request.leaf_count = frame->leaf_count;
    request.leaf_at_peak = buffers->leaf_at_peak[slot];
    request.start = buffers->leaf_start[slot];
    request.grouped = buffers->leaf_voxels[slot];
    engine_group_voxels(&request);
}
