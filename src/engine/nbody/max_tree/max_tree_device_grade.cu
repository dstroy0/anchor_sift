// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_grade.cu: grading the codes
#include "max_tree_device_internal.h"

static int max_tree_grade_codes(const unsigned int *residual, unsigned int depth, unsigned int height,
                                unsigned int width, const unsigned char *coded, unsigned int *differ,
                                EngineError *error)
{
    const size_t voxels = (size_t)depth * height * width;
    unsigned char *faces = NULL;
    unsigned int *belongs = NULL;
    unsigned long long *strongest = NULL;
    unsigned int *partner = NULL;
    unsigned char *bound = NULL;
    unsigned int *moved = NULL;
    unsigned int *pinned = NULL;
    unsigned int *device_differ = NULL;
    cudaEvent_t done[2] = {NULL, NULL};
    int ok =
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&faces, voxels), &faces, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&belongs, voxels * sizeof(unsigned int)), &belongs, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&strongest, voxels * MAX_TREE_KEY_WORDS * sizeof(unsigned long long)),
                              &strongest, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&partner, voxels * sizeof(unsigned int)), &partner, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&bound, voxels * 3u), &bound, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&moved, 3u * sizeof(unsigned int)), &moved, error) &&
        MAX_TREE_STATUS_CHECK(cudaMallocHost((void **)&pinned, 2u * sizeof(unsigned int)), &pinned, error) &&
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_differ, sizeof(unsigned int)), &device_differ, error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&done[0], cudaEventDisableTiming), &done[0], error) &&
        MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&done[1], cudaEventDisableTiming), &done[1], error) &&
        MAX_TREE_STATUS_CHECK(cudaMemset(moved, 0, 3u * sizeof(unsigned int)), moved, error) &&
        MAX_TREE_STATUS_CHECK(cudaMemset(device_differ, 0, sizeof(unsigned int)), device_differ, error);
    ok = ok && max_tree_contract(residual, depth, height, width, faces, belongs, strongest, partner, bound, moved,
                                 pinned, done, error);
    const unsigned int face_count = (unsigned int)(voxels * 3u);
    if (ok != 0)
    {
        max_tree_faces_differ_kernel<<<(face_count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
            bound, coded, face_count, device_differ);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), device_differ, error);
    }
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(differ, device_differ, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                     differ, error);
    ok = ok && MAX_TREE_CHECK(*differ == 0u, coded, error, ENGINE_ERROR_LOGIC);
    cudaFree(faces);
    cudaFree(belongs);
    cudaFree(strongest);
    cudaFree(partner);
    cudaFree(bound);
    cudaFree(moved);
    cudaFreeHost(pinned);
    cudaFree(device_differ);
    if (done[0] != NULL)
    {
        cudaEventDestroy(done[0]);
    }
    if (done[1] != NULL)
    {
        cudaEventDestroy(done[1]);
    }
    return ok;
}

extern "C" long max_tree_objects(const MaxTreeObjectsRequest *request)
{
    if (s_max_tree_profile < 0)
    {
        s_max_tree_profile = (getenv("MAX_TREE_PROFILE") != NULL) ? 1 : 0;
    }
    unsigned long long stage_mark = engine_clock_microseconds();
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const unsigned int depth = request->depth;
    const unsigned int height = request->height;
    const unsigned int width = request->width;
    const size_t voxels = (size_t)depth * height * width;
    const int asked =
        MAX_TREE_CHECK(request->device_residual != NULL, &request->device_residual, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((request->capacity == 0u) || (request->bodies != NULL), &request->bodies, error,
                       ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK((voxels != 0u) && ((voxels * 3u) < 0xFFFFFFFFull), &request->depth, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_ERROR;
    }
    MaxTreeResident *const resident = &g_max_tree_resident;
    int ok = max_tree_reserve(voxels, error);
    const unsigned int count = (unsigned int)voxels;
    const int items = (int)count;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int chunks = (count + MAX_TREE_CHUNK - 1u) / MAX_TREE_CHUNK;
    const unsigned int chunk_spread = (chunks + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    const unsigned int words = (count + 63u) / 64u;
    const unsigned int *const residual = request->device_residual;

    cub::DoubleBuffer<unsigned int> keys(resident->keys[0], resident->keys[1]);
    cub::DoubleBuffer<unsigned int> order(resident->order[0], resident->order[1]);
    if (ok != 0)
    {
        max_tree_iota_kernel<<<spread, MAX_TREE_BLOCK>>>(count, order.Current());
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), order.Current(), error);
    }
    for (unsigned int limb = 0u; (ok != 0) && (limb < ENGINE_RESIDUAL_LIMBS); limb += 1u)
    {
        max_tree_code_gather_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), count, limb, keys.Current());
        size_t bytes = resident->scratch_bytes;
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), keys.Current(), error) &&
             MAX_TREE_STATUS_CHECK(cub::DeviceRadixSort::SortPairs(resident->scratch, bytes, keys, order, items),
                                   resident->scratch, error);
    }
    unsigned int *const flags = keys.Current();
    unsigned int *const ranks = keys.Alternate();
    if (ok != 0)
    {
        max_tree_code_flags_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), count, flags);
        size_t bytes = resident->scratch_bytes;
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), flags, error) &&
             MAX_TREE_STATUS_CHECK(cub::DeviceScan::InclusiveSum(resident->scratch, bytes, flags, ranks, items), ranks,
                                   error);
    }
    if (ok != 0)
    {
        max_tree_code_scatter_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), ranks, count,
                                                                 resident->code);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->code, error);
    }
    unsigned int top = 0u;
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(&top, &ranks[count - 1u], sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                     &ranks[count - 1u], error);
    top += 1u;
    max_tree_stage(0u, &stage_mark);

    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->moved, 0, 3u * sizeof(unsigned int)), resident->moved, error);
    ok = ok && max_tree_code_contract(resident->code, depth, height, width, resident->faces, resident->belongs,
                                      resident->best, resident->partner, resident->bound, resident->moved,
                                      resident->pinned_moved, resident->blocks_done, error);
    max_tree_stage(1u, &stage_mark);
    unsigned int faces_differ = 0u;
    ok = ok && ((request->grade == 0u) ||
                max_tree_grade_codes(residual, depth, height, width, resident->bound, &faces_differ, error));
    max_tree_stage(8u, &stage_mark);

    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->change, 0, ((size_t)top + 1u) * sizeof(int)),
                                     resident->change, error);
    if (ok != 0)
    {
        max_tree_code_levels_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->code, resident->bound, depth, height, width,
                                                                resident->change);
        max_tree_reverse_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(resident->change, top,
                                                                                                  resident->counts);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->counts, error);
    }
    if (ok != 0)
    {
        size_t bytes = resident->scratch_bytes;
        ok = MAX_TREE_STATUS_CHECK(
            cub::DeviceScan::InclusiveSum(resident->scratch, bytes, resident->counts, resident->counts, (int)top),
            resident->counts, error);
        bytes = resident->scratch_bytes;
        ok = ok && MAX_TREE_STATUS_CHECK(
                       cub::DeviceReduce::Max(resident->scratch, bytes, resident->counts, resident->maximum, (int)top),
                       resident->maximum, error);
    }
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->level, 0xFF, sizeof(unsigned int)), resident->level, error);
    if (ok != 0)
    {
        max_tree_level_pick_kernel<<<(top + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
            resident->counts, top, resident->maximum, resident->level);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->level, error);
    }
    int expected = 0;
    unsigned int level_code = 0u;
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(&expected, resident->maximum, sizeof(int), cudaMemcpyDeviceToHost),
                                     resident->maximum, error);
    ok = ok &&
         MAX_TREE_STATUS_CHECK(cudaMemcpy(&level_code, resident->level, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                               resident->level, error);
    level_code = ((top > 1u) && (level_code != 0xFFFFFFFFu)) ? level_code : 1u;
    max_tree_stage(2u, &stage_mark);

    if (ok != 0)
    {
        max_tree_cc_start_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->code, count, level_code, resident->ranges,
                                                             resident->label);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->label, error);
    }
    ok = ok && max_tree_cc(resident->ranges, depth, height, width, resident->label, resident->moved,
                           resident->pinned_moved, resident->blocks_done, error);
    unsigned int found = 0u;
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->roots, 0, sizeof(unsigned int)), resident->roots, error);
    if (ok != 0)
    {
        max_tree_roots_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->ranges, resident->label, count, resident->roots);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->roots, error);
    }
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(&found, resident->roots, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                     resident->roots, error);
    max_tree_stage(3u, &stage_mark);

    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->best, 0, voxels * sizeof(unsigned long long)), resident->best,
                                     error);
    if (ok != 0)
    {
        max_tree_peak_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->code, resident->ranges, resident->label, count,
                                                         resident->best);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->best, error);
    }
    max_tree_stage(4u, &stage_mark);

    if (ok != 0)
    {
        max_tree_mark_kernel<<<chunk_spread, MAX_TREE_BLOCK>>>(residual, resident->code, resident->ranges,
                                                               resident->label, resident->best, count, 0u,
                                                               resident->at_chunk, NULL, NULL);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->at_chunk, error);
    }
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(resident->host_chunks, resident->at_chunk,
                                                (size_t)chunks * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                                     resident->host_chunks, error);
    unsigned long long bodies = 0ull;
    for (unsigned int chunk = 0u; (ok != 0) && (chunk < chunks); chunk += 1u)
    {
        const unsigned int here = resident->host_chunks[chunk];
        resident->host_chunks[chunk] = (unsigned int)bodies;
        bodies += (unsigned long long)here;
    }
    ok = ok && max_tree_grow_bodies((size_t)bodies, error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(resident->at_chunk, resident->host_chunks,
                                                (size_t)chunks * sizeof(unsigned int), cudaMemcpyHostToDevice),
                                     resident->at_chunk, error);
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemset(resident->bodies, 0, ((size_t)bodies + 1u) * sizeof(EngineBody)),
                                     resident->bodies, error);
    if (ok != 0)
    {
        max_tree_mark_kernel<<<chunk_spread, MAX_TREE_BLOCK>>>(residual, resident->code, resident->ranges,
                                                               resident->label, resident->best, count, 1u,
                                                               resident->at_chunk, resident->partner, resident->bodies);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->bodies, error);
    }
    max_tree_stage(5u, &stage_mark);
    if (ok != 0)
    {
        max_tree_object_census_kernel<<<spread, MAX_TREE_BLOCK>>>(resident->ranges, resident->label, resident->best,
                                                                  resident->partner, depth, height, width,
                                                                  resident->bodies, resident->belongs);
        if (request->positive_words != NULL)
        {
            max_tree_pack_kernel<<<(words + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
                residual, count, words, resident->packed);
        }
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->bodies, error);
    }
    max_tree_stage(6u, &stage_mark);
    ok = ok && MAX_TREE_CHECK(((long long)found == (long long)expected) && ((unsigned long long)found == bodies),
                              resident->roots, error, ENGINE_ERROR_LOGIC);
    ok = ok && MAX_TREE_CHECK((request->bodies == NULL) || (bodies <= (unsigned long long)request->capacity),
                              &request->capacity, error, ENGINE_ERROR_REQUEST);
    ok = ok && ((request->labels == NULL) ||
                MAX_TREE_STATUS_CHECK(cudaMemcpy(request->labels, resident->belongs, voxels * sizeof(unsigned int),
                                                 cudaMemcpyDeviceToHost),
                                      request->labels, error));
    ok = ok && ((request->positive_words == NULL) ||
                MAX_TREE_STATUS_CHECK(cudaMemcpy(request->positive_words, resident->packed,
                                                 (size_t)words * sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                                      request->positive_words, error));
    ok = ok && ((request->bodies == NULL) || (bodies == 0ull) ||
                MAX_TREE_STATUS_CHECK(cudaMemcpy(request->bodies, resident->bodies, (size_t)bodies * sizeof(EngineBody),
                                                 cudaMemcpyDeviceToHost),
                                      request->bodies, error));
    max_tree_stage(7u, &stage_mark);
    const unsigned int keep_slot = resident->kept_current ^ 1u;
    if ((ok != 0) && (resident->keeping != 0))
    {
        resident->kept_ready[keep_slot] = 0u;
        ok = MAX_TREE_STATUS_CHECK(cudaMemcpy(resident->kept_code[keep_slot], resident->code,
                                              voxels * sizeof(unsigned int), cudaMemcpyDeviceToDevice),
                                   resident->kept_code[keep_slot], error) &&
             MAX_TREE_STATUS_CHECK(cudaMemset(resident->kept_values[keep_slot], 0,
                                              ((size_t)top + 1u) * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                                   resident->kept_values[keep_slot], error);
    }
    if ((ok != 0) && (resident->keeping != 0))
    {
        max_tree_code_values_kernel<<<spread, MAX_TREE_BLOCK>>>(residual, order.Current(), flags, resident->code, count,
                                                                resident->kept_values[keep_slot]);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), resident->kept_values[keep_slot], error);
        resident->kept_top[keep_slot] = top;
        resident->kept_ready[keep_slot] = (unsigned int)ok;
        resident->kept_current = keep_slot;
    }
    if (request->level_code != NULL)
    {
        *request->level_code = level_code;
    }
    if (request->faces_differ != NULL)
    {
        *request->faces_differ = faces_differ;
    }
    if (request->proof_count != NULL)
    {
        *request->proof_count = (unsigned int)(ok != 0);
    }
    if (ok == 0)
    {
        max_tree_release_resident(resident);
        return MAX_TREE_ERROR;
    }
    resident->last_bodies = (size_t)bodies;
    resident->top = top;
    resident->threshold = level_code;
    resident->last_depth = depth;
    resident->last_height = height;
    resident->last_width = width;
    return (long)bodies;
}
