// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_slide.cu: the sliding search
#include "max_tree_device_internal.h"

__global__ static void max_tree_slide_gather_kernel(const unsigned int *probe_voxels, unsigned int probes,
                                                    const unsigned char *ranges, const unsigned int *label,
                                                    unsigned int *probe_labels)
{
    const unsigned int probe = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (probe >= probes)
    {
        return;
    }
    const unsigned int voxel = probe_voxels[probe];
    probe_labels[probe] = (ranges[voxel] != 0u) ? label[voxel] : MAX_TREE_ABSENT;
}

static int max_tree_slide_partition(MaxTreeSlide *slide, unsigned int level, unsigned int *partition,
                                    MaxTreeSlideStep *step)
{
    const MaxTreeResident *const resident = &g_max_tree_resident;
    EngineError *const error = slide->error;
    const unsigned int count = slide->depth * slide->height * slide->width;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    step->level = level;
    step->components = 0u;
    int ok = 1;
    if (level > slide->top)
    {
        for (unsigned int probe = 0u; probe < slide->probes; probe += 1u)
        {
            slide->raw[probe] = MAX_TREE_ABSENT;
        }
    }
    else
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->code, count, level, slide->ranges, slide->label);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), slide->label, error) &&
             max_tree_cc(slide->ranges, slide->depth, slide->height, slide->width, slide->label, slide->moved,
                         slide->pinned_moved, slide->blocks_done, error) &&
             MAX_TREE_STATUS_CHECK(cudaMemset(slide->roots, 0, sizeof(unsigned int)), slide->roots, error);
        if (ok != 0)
        {
            max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(slide->ranges, slide->label, count, slide->roots);
            if (slide->probes != 0u)
            {
                max_tree_slide_gather_kernel<<<(slide->probes + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK,
                                               MAX_TREE_BLOCK>>>(slide->device_probes, slide->probes, slide->ranges,
                                                                 slide->label, slide->probe_labels);
            }
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), slide->probe_labels, error);
        }
        unsigned int roots = 0u;
        int components = 0;
        ok = ok &&
             MAX_TREE_STATUS_CHECK(cudaMemcpy(&roots, slide->roots, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                   slide->roots, error) &&
             MAX_TREE_STATUS_CHECK(
                 cudaMemcpy(&components, &resident->counts[slide->top - level], sizeof(int), cudaMemcpyDeviceToHost),
                 &resident->counts[slide->top - level], error) &&
             ((slide->probes == 0u) ||
              MAX_TREE_STATUS_CHECK(cudaMemcpy(slide->raw, slide->probe_labels,
                                               (size_t)slide->probes * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                    slide->raw, error));
        // components counts the superlevel set's pieces, never negative. It re-signs to unsigned int exactly
        step->components = (unsigned int)components;
        ok = ok && MAX_TREE_CHECK(roots == step->components, slide->roots, error, ENGINE_ERROR_LOGIC);
        slide->labelings += 1u;
    }
    for (unsigned int probe = 0u; probe < slide->probes; probe += 1u)
    {
        unsigned int first = probe;
        for (unsigned int earlier = probe; earlier > 0u; earlier -= 1u)
        {
            first = (slide->raw[earlier - 1u] == slide->raw[probe]) ? (earlier - 1u) : first;
        }
        partition[probe] = (slide->raw[probe] == MAX_TREE_ABSENT) ? MAX_TREE_ABSENT : first;
    }
    return ok;
}

static int max_tree_slide_search(MaxTreeSlide *slide, unsigned int low, unsigned int high,
                                 const unsigned int *low_partition, const MaxTreeSlideStep *low_step,
                                 const unsigned int *high_partition)
{
    EngineError *const error = slide->error;
    if (memcmp(low_partition, high_partition, (size_t)slide->probes * sizeof(unsigned int)) == 0)
    {
        return 1;
    }
    if ((high - low) == 1u)
    {
        if (!MAX_TREE_CHECK(slide->step_count < slide->step_capacity, &slide->step_capacity, error,
                            ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        slide->steps[slide->step_count] = *low_step;
        if (slide->partitions != NULL)
        {
            memcpy(&slide->partitions[(size_t)slide->step_count * slide->probes], low_partition,
                   (size_t)slide->probes * sizeof(unsigned int));
        }
        slide->step_count += 1u;
        return 1;
    }
    const unsigned int middle = low + ((high - low) / 2u);
    unsigned int *const middle_partition = (unsigned int *)malloc(((size_t)slide->probes + 1u) * sizeof(unsigned int));
    MaxTreeSlideStep middle_step;
    const int ok = MAX_TREE_CHECK(middle_partition != NULL, &middle_partition, error, ENGINE_ERROR_RESOURCE) &&
                   max_tree_slide_partition(slide, middle, middle_partition, &middle_step) &&
                   max_tree_slide_search(slide, middle, high, middle_partition, &middle_step, high_partition) &&
                   max_tree_slide_search(slide, low, middle, low_partition, low_step, middle_partition);
    free(middle_partition);
    return ok;
}

extern "C" long max_tree_slide(const MaxTreeSlideRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const MaxTreeResident *const resident = &g_max_tree_resident;
    int asked = MAX_TREE_CHECK((request->step_count != NULL) && (request->steps != NULL), request, error,
                               ENGINE_ERROR_REQUEST) &&
                MAX_TREE_CHECK((request->probe_count == 0u) || (request->probe_voxels != NULL), &request->probe_voxels,
                               error, ENGINE_ERROR_REQUEST) &&
                MAX_TREE_CHECK((resident->code != NULL) && (resident->top != 0u) && (resident->last_depth != 0u),
                               resident, error, ENGINE_ERROR_REQUEST);
    for (unsigned int probe = 0u; (asked != 0) && (probe < request->probe_count); probe += 1u)
    {
        asked = MAX_TREE_CHECK(request->probe_voxels[probe] < resident->voxels, &request->probe_voxels[probe], error,
                               ENGINE_ERROR_REQUEST);
    }
    if (asked == 0)
    {
        return MAX_TREE_ERROR;
    }
    MaxTreeSlide slide;
    memset(&slide, 0, sizeof(slide));
    slide.depth = resident->last_depth;
    slide.height = resident->last_height;
    slide.width = resident->last_width;
    slide.top = resident->top;
    slide.probes = request->probe_count;
    slide.steps = request->steps;
    slide.partitions = request->partitions;
    slide.step_capacity = request->step_capacity;
    slide.error = error;
    const size_t voxels = resident->voxels;
    const size_t probe_capacity = (size_t)request->probe_count + 1u;
    unsigned int *device_probes = NULL;
    slide.raw = (unsigned int *)malloc(probe_capacity * sizeof(unsigned int));
    unsigned int *const low_partition = (unsigned int *)malloc(probe_capacity * sizeof(unsigned int));
    unsigned int *const high_partition = (unsigned int *)malloc(probe_capacity * sizeof(unsigned int));
    int ok =
        MAX_TREE_CHECK(slide.raw != NULL, &slide.raw, error, ENGINE_ERROR_RESOURCE) &&
        MAX_TREE_CHECK(low_partition != NULL, &low_partition, error, ENGINE_ERROR_RESOURCE) &&
        MAX_TREE_CHECK(high_partition != NULL, &high_partition, error, ENGINE_ERROR_RESOURCE) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_probes, probe_capacity * sizeof(unsigned int)),
                              &device_probes, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&slide.probe_labels, probe_capacity * sizeof(unsigned int)),
                              &slide.probe_labels, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&slide.ranges, voxels), &slide.ranges, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&slide.label, voxels * sizeof(unsigned int)), &slide.label, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&slide.roots, sizeof(unsigned int)), &slide.roots, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&slide.moved, 3u * sizeof(unsigned int)), &slide.moved, error) &&
        MAX_TREE_STATUS_CHECK(cudaMallocHost((void **)&slide.pinned_moved, 2u * sizeof(unsigned int)),
                              &slide.pinned_moved, error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&slide.blocks_done[0], cudaEventDisableTiming),
                              &slide.blocks_done[0], error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&slide.blocks_done[1], cudaEventDisableTiming),
                              &slide.blocks_done[1], error) &&
        ((request->probe_count == 0u) ||
         MAX_TREE_STATUS_CHECK(cudaMemcpy(device_probes, request->probe_voxels,
                                          (size_t)request->probe_count * sizeof(unsigned int), cudaMemcpyHostToDevice),
                               device_probes, error));
    slide.device_probes = device_probes;
    MaxTreeSlideStep low_step;
    MaxTreeSlideStep high_step;
    ok = ok && max_tree_slide_partition(&slide, 1u, low_partition, &low_step) &&
         max_tree_slide_partition(&slide, slide.top + 1u, high_partition, &high_step) &&
         max_tree_slide_search(&slide, 1u, slide.top + 1u, low_partition, &low_step, high_partition);
    cudaFree(device_probes);
    cudaFree(slide.probe_labels);
    cudaFree(slide.ranges);
    cudaFree(slide.label);
    cudaFree(slide.roots);
    cudaFree(slide.moved);
    cudaFreeHost(slide.pinned_moved);
    if (slide.blocks_done[0] != NULL)
    {
        cudaEventDestroy(slide.blocks_done[0]);
    }
    if (slide.blocks_done[1] != NULL)
    {
        cudaEventDestroy(slide.blocks_done[1]);
    }
    free(slide.raw);
    free(low_partition);
    free(high_partition);
    if (ok == 0)
    {
        return MAX_TREE_ERROR;
    }
    *request->step_count = slide.step_count;
    if (request->top_level != NULL)
    {
        *request->top_level = resident->top;
    }
    if (request->threshold != NULL)
    {
        *request->threshold = resident->threshold;
    }
    if (request->labelings != NULL)
    {
        *request->labelings = slide.labelings;
    }
    return 0L;
}

extern "C" int max_tree_keep_frames(void)
{
    MaxTreeResident *const resident = &g_max_tree_resident;
    if (resident->keeping == 0)
    {
        resident->keeping = 1;
        max_tree_release_resident(resident);
    }
    return 1;
}
