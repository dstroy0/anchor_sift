// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_overlap.cu: the overlap step
#include "max_tree_device_internal.h"

static int max_tree_overlap_step(MaxTreeOverlap *overlap, unsigned int origin, unsigned int level,
                                 MaxTreeOverlapStep *step, MaxTreeOverlapProbe *probes, unsigned char *links_present)
{
    const MaxTreeResident *const resident = &g_max_tree_resident;
    EngineError *const error = overlap->error;
    const unsigned int count = overlap->depth * overlap->height * overlap->width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int origin_slot = overlap->slot[origin];
    if (!MAX_TREE_CHECK((level != 0u) && (level <= resident->kept_top[origin_slot]), step, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned int *const value = &resident->kept_values[origin_slot][(size_t)level * ENGINE_RESIDUAL_LIMBS];
    unsigned int thresholds[2] = {0u, 0u};
    int ok = 1;
    for (unsigned int frame = 0u; (ok != 0) && (frame < 2u); frame += 1u)
    {
        const unsigned int slot = overlap->slot[frame];
        const unsigned int top = resident->kept_top[slot];
        thresholds[frame] = top + 1u;
        ok = MAX_TREE_STATUS_CHECK(
            cudaMemcpy(&overlap->thresholds[frame], &thresholds[frame], sizeof(unsigned int), cudaMemcpyHostToDevice),
            &overlap->thresholds[frame], error);
        if (ok != 0)
        {
            max_tree_overlap_threshold_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
                resident->kept_values[slot], top, value, &overlap->thresholds[frame]);
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), &overlap->thresholds[frame], error);
        }
    }
    ok = ok &&
         MAX_TREE_STATUS_CHECK(
             cudaMemcpy(thresholds, overlap->thresholds, 2u * sizeof(unsigned int), cudaMemcpyDeviceToHost),
             overlap->thresholds, error) &&
         MAX_TREE_STATUS_CHECK(cudaMemset(overlap->tallies, 0, MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int)),
                               overlap->tallies, error);
    for (unsigned int frame = 0u; (ok != 0) && (frame < 2u); frame += 1u)
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->kept_code[overlap->slot[frame]], count,
                                                             thresholds[frame], overlap->ranges[frame],
                                                             overlap->label[frame]);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), overlap->label[frame], error) &&
             max_tree_cc(overlap->ranges[frame], overlap->depth, overlap->height, overlap->width, overlap->label[frame],
                         overlap->moved, overlap->pinned_moved, overlap->blocks_done, error) &&
             MAX_TREE_STATUS_CHECK(cudaMemset(overlap->partners[frame], 0, (size_t)count * sizeof(unsigned int)),
                                   overlap->partners[frame], error) &&
             MAX_TREE_STATUS_CHECK(cudaMemset(overlap->backs[frame], 0, (size_t)count * sizeof(unsigned int)),
                                   overlap->backs[frame], error);
        if (ok != 0)
        {
            max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->ranges[frame], overlap->label[frame], count,
                                                              &overlap->tallies[frame]);
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), &overlap->tallies[frame], error);
        }
    }
    if (ok != 0)
    {
        max_tree_overlap_pairs_kernel<<<spread, MAX_TREE_BLOCK>>>(
            overlap->ranges[0], overlap->label[0], overlap->ranges[1], overlap->label[1], overlap->depth,
            overlap->height, overlap->width, overlap->lag[0], overlap->lag[1], overlap->lag[2], overlap->pairs[0]);
        size_t bytes = overlap->scratch_bytes;
        // the voxel count was held below 2^32 when the frame was cut, and the sort takes it as int
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), overlap->pairs[0], error) &&
             MAX_TREE_STATUS_CHECK(cub::DeviceRadixSort::SortKeys(overlap->scratch, bytes, overlap->pairs[0],
                                                                  overlap->pairs[1], (int)count),
                                   overlap->pairs[1], error);
    }
    if (ok != 0)
    {
        max_tree_overlap_partners_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->pairs[1], count, overlap->partners[0],
                                                                     overlap->partners[1]);
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            max_tree_overlap_one_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->ranges[frame], overlap->label[frame],
                                                                    overlap->partners[frame], count,
                                                                    &overlap->tallies[2u + frame]);
        }
        max_tree_overlap_backs_kernel<<<spread, MAX_TREE_BLOCK>>>(
            overlap->pairs[1], count, overlap->partners[0], overlap->partners[1], overlap->backs[0], overlap->backs[1]);
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            max_tree_overlap_census_kernel<<<spread, MAX_TREE_BLOCK>>>(overlap->ranges[frame], overlap->label[frame],
                                                                       overlap->partners[frame], overlap->backs[frame],
                                                                       count, &overlap->tallies[4u + (3u * frame)]);
        }
        for (unsigned int frame = 0u; frame < 2u; frame += 1u)
        {
            if (overlap->probe_counts[frame] != 0u)
            {
                max_tree_overlap_probe_kernel<<<(overlap->probe_counts[frame] + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                                MAX_TREE_BLOCK>>>(
                    overlap->probe_voxels[frame], overlap->probe_counts[frame], overlap->ranges[frame],
                    overlap->label[frame], overlap->partners[frame], overlap->backs[frame], overlap->probes[frame]);
            }
        }
        if (overlap->link_count != 0u)
        {
            max_tree_overlap_link_kernel<<<(overlap->link_count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                           MAX_TREE_BLOCK>>>(overlap->probe_links, overlap->link_count,
                                                             overlap->probes[0], overlap->probes[1], overlap->pairs[1],
                                                             count, overlap->links_present);
        }
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), overlap->tallies, error);
    }
    ok = ok &&
         ((overlap->probe_counts[0] == 0u) ||
          MAX_TREE_STATUS_CHECK(cudaMemcpy(probes, overlap->probes[0],
                                           (size_t)overlap->probe_counts[0] * sizeof(MaxTreeOverlapProbe),
                                           cudaMemcpyDeviceToHost),
                                probes, error)) &&
         ((overlap->probe_counts[1] == 0u) ||
          MAX_TREE_STATUS_CHECK(cudaMemcpy(&probes[overlap->probe_counts[0]], overlap->probes[1],
                                           (size_t)overlap->probe_counts[1] * sizeof(MaxTreeOverlapProbe),
                                           cudaMemcpyDeviceToHost),
                                &probes[overlap->probe_counts[0]], error)) &&
         ((overlap->link_count == 0u) || MAX_TREE_STATUS_CHECK(cudaMemcpy(links_present, overlap->links_present,
                                                                          overlap->link_count, cudaMemcpyDeviceToHost),
                                                               links_present, error));
    unsigned int tallies[MAX_TREE_OVERLAP_TALLIES] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    ok =
        ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(tallies, overlap->tallies,
                                               MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    overlap->tallies, error);
    step->origin = origin;
    step->level = level;
    step->earlier_code = thresholds[0];
    step->later_code = thresholds[1];
    step->earlier_components = tallies[0];
    step->later_components = tallies[1];
    step->earlier_one = tallies[2];
    step->later_one = tallies[3];
    step->earlier_unpaired = tallies[4];
    step->earlier_mutual = tallies[5];
    step->earlier_forked = tallies[6];
    step->later_unpaired = tallies[7];
    step->later_mutual = tallies[8];
    step->later_forked = tallies[9];
    return ok;
}

extern "C" long max_tree_overlap(const MaxTreeOverlapRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const MaxTreeResident *const resident = &g_max_tree_resident;
    int asked =
        MAX_TREE_CHECK((request->step_count != NULL) && (request->steps != NULL), request, error,
                       ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((resident->keeping != 0) && (resident->kept_ready[0] != 0u) && (resident->kept_ready[1] != 0u) &&
                           (resident->last_depth != 0u),
                       resident, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->earlier_level_count == 0u) || (request->earlier_levels != NULL),
                       &request->earlier_levels, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->later_level_count == 0u) || (request->later_levels != NULL), &request->later_levels,
                       error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->probe_counts[0] == 0u) || (request->probe_voxels[0] != NULL),
                       &request->probe_voxels[0], error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->probe_counts[1] == 0u) || (request->probe_voxels[1] != NULL),
                       &request->probe_voxels[1], error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK(((request->probe_counts[0] + request->probe_counts[1]) == 0u) || (request->probes != NULL),
                       &request->probes, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->link_count == 0u) ||
                           ((request->probe_links != NULL) && (request->links_present != NULL)),
                       &request->probe_links, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->earlier_level_count + request->later_level_count) <= request->step_capacity,
                       &request->step_capacity, error, ENGINE_ERROR_REQUEST);
    const size_t voxels = resident->voxels;
    for (unsigned int frame = 0u; (asked != 0) && (frame < 2u); frame += 1u)
    {
        for (unsigned int probe = 0u; (asked != 0) && (probe < request->probe_counts[frame]); probe += 1u)
        {
            asked = MAX_TREE_CHECK(request->probe_voxels[frame][probe] < voxels, &request->probe_voxels[frame][probe],
                                   error, ENGINE_ERROR_REQUEST);
        }
    }
    for (unsigned int link = 0u; (asked != 0) && (link < request->link_count); link += 1u)
    {
        asked = MAX_TREE_CHECK((request->probe_links[2u * link] < request->probe_counts[0]) &&
                                   (request->probe_links[(2u * link) + 1u] < request->probe_counts[1]),
                               &request->probe_links[2u * link], error, ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return MAX_TREE_ERROR;
    }
    MaxTreeOverlap overlap;
    memset(&overlap, 0, sizeof(overlap));
    overlap.depth = resident->last_depth;
    overlap.height = resident->last_height;
    overlap.width = resident->last_width;
    overlap.slot[0] = resident->kept_current ^ 1u;
    overlap.slot[1] = resident->kept_current;
    overlap.link_count = request->link_count;
    overlap.error = error;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        overlap.lag[axis] = request->lag[axis];
    }
    unsigned int *device_probe_voxels[2] = {NULL, NULL};
    unsigned int *device_links = NULL;
    int ok = 1;
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        const size_t probes = request->probe_counts[frame];
        overlap.probe_counts[frame] = request->probe_counts[frame];
        ok = ok &&
             ((probes == 0u) ||
              (MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_probe_voxels[frame], probes * sizeof(unsigned int)),
                                     &device_probe_voxels[frame], error) &&
               MAX_TREE_STATUS_CHECK(cudaMemcpy(device_probe_voxels[frame], request->probe_voxels[frame],
                                                probes * sizeof(unsigned int), cudaMemcpyHostToDevice),
                                     device_probe_voxels[frame], error) &&
               MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.probes[frame], probes * sizeof(MaxTreeOverlapProbe)),
                                     &overlap.probes[frame], error)));
        overlap.probe_voxels[frame] = device_probe_voxels[frame];
    }
    const size_t link_words = (size_t)request->link_count * 2u;
    ok = ok && ((request->link_count == 0u) ||
                (MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_links, link_words * sizeof(unsigned int)),
                                       &device_links, error) &&
                 MAX_TREE_STATUS_CHECK(cudaMemcpy(device_links, request->probe_links, link_words * sizeof(unsigned int),
                                                  cudaMemcpyHostToDevice),
                                       device_links, error) &&
                 MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.links_present, request->link_count),
                                       &overlap.links_present, error)));
    overlap.probe_links = device_links;
    // the voxel count was held below 2^32 when the frame was cut, and the sort takes it as int
    ok = ok &&
         MAX_TREE_STATUS_CHECK(cub::DeviceRadixSort::SortKeys(NULL, overlap.scratch_bytes,
                                                              (const unsigned long long *)NULL,
                                                              (unsigned long long *)NULL, (int)voxels),
                               &overlap.scratch_bytes, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc(&overlap.scratch, overlap.scratch_bytes), &overlap.scratch, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.thresholds, 2u * sizeof(unsigned int)), &overlap.thresholds,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.tallies, MAX_TREE_OVERLAP_TALLIES * sizeof(unsigned int)),
                               &overlap.tallies, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.moved, 3u * sizeof(unsigned int)), &overlap.moved, error) &&
         MAX_TREE_STATUS_CHECK(cudaMallocHost((void **)&overlap.pinned_moved, 2u * sizeof(unsigned int)),
                               &overlap.pinned_moved, error) &&
         MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&overlap.blocks_done[0], cudaEventDisableTiming),
                               &overlap.blocks_done[0], error) &&
         MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&overlap.blocks_done[1], cudaEventDisableTiming),
                               &overlap.blocks_done[1], error);
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        ok =
            ok &&
            MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.ranges[frame], voxels), &overlap.ranges[frame], error) &&
            MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.label[frame], voxels * sizeof(unsigned int)),
                                  &overlap.label[frame], error) &&
            MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.partners[frame], voxels * sizeof(unsigned int)),
                                  &overlap.partners[frame], error) &&
            MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.backs[frame], voxels * sizeof(unsigned int)),
                                  &overlap.backs[frame], error) &&
            MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&overlap.pairs[frame], voxels * sizeof(unsigned long long)),
                                  &overlap.pairs[frame], error);
    }
    const size_t probes_a_step = (size_t)request->probe_counts[0] + request->probe_counts[1];
    unsigned int written = 0u;
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->earlier_level_count); taken += 1u)
    {
        ok = max_tree_overlap_step(&overlap, 0u, request->earlier_levels[taken], &request->steps[written],
                                   &request->probes[written * probes_a_step],
                                   &request->links_present[(size_t)written * request->link_count]);
        written += 1u;
    }
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->later_level_count); taken += 1u)
    {
        ok = max_tree_overlap_step(&overlap, 1u, request->later_levels[taken], &request->steps[written],
                                   &request->probes[written * probes_a_step],
                                   &request->links_present[(size_t)written * request->link_count]);
        written += 1u;
    }
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        cudaFree(device_probe_voxels[frame]);
        cudaFree(overlap.probes[frame]);
    }
    cudaFree(device_links);
    cudaFree(overlap.links_present);
    cudaFree(overlap.scratch);
    cudaFree(overlap.thresholds);
    cudaFree(overlap.tallies);
    cudaFree(overlap.moved);
    cudaFreeHost(overlap.pinned_moved);
    if (overlap.blocks_done[0] != NULL)
    {
        cudaEventDestroy(overlap.blocks_done[0]);
    }
    if (overlap.blocks_done[1] != NULL)
    {
        cudaEventDestroy(overlap.blocks_done[1]);
    }
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        cudaFree(overlap.ranges[frame]);
        cudaFree(overlap.label[frame]);
        cudaFree(overlap.partners[frame]);
        cudaFree(overlap.backs[frame]);
        cudaFree(overlap.pairs[frame]);
    }
    if (ok == 0)
    {
        return MAX_TREE_ERROR;
    }
    *request->step_count = written;
    return 0L;
}
