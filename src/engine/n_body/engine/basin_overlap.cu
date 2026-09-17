/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file basin_overlap.cu
 * @brief The CUDA engine for basin_overlap.h: integers only, equal to basin_overlap.c.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * One thread per chunk counts and then packs the voxels positive in both frames, in raster order, into
 * their offsets. Consecutive voxels of a chunk carrying the same pair are packed once, with how many
 * they are, so a basin crossing a row comes back as one run rather than one pair per voxel. The runs are
 * sorted and tallied on the host, and a pair's count is the sum of its runs, so the list is identical to
 * the reference's.
 */

#include "basin_overlap.h"
#include "radix_keys.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define BASIN_OVERLAP_BLOCK 256u

/** @brief Voxels walked by one chunk thread, so raster order survives. */
#define BASIN_OVERLAP_CHUNK 4096u

static_assert(sizeof(unsigned int) == 4u, "basin_overlap: unsigned int must be 32 bits, a peak index");
static_assert(sizeof(unsigned long long) == 8u, "basin_overlap: unsigned long long must be 64 bits, a pair");

/** @brief The view's axes and the lag, as a kernel reads them. */
struct OverlapView
{
    unsigned int axes;
    unsigned int extents[BASIN_OVERLAP_AXES];
    int lag[BASIN_OVERLAP_AXES];
};

/**
 * @brief The position v + lag, or -1 where it falls outside the view, as overlap_moved does.
 *
 * @param[in] view     Axes and lag.
 * @param[in] position Raster position v.
 * @return             Raster position of v + lag, or -1.
 */
__device__ static long long device_overlap_moved(const OverlapView *view, unsigned int position)
{
    unsigned int rest = position;
    long long moved = 0ll;
    long long stride = 1ll;
    for (unsigned int axis = view->axes; axis > 0u; axis -= 1u)
    {
        const long long extent = (long long)view->extents[axis - 1u];
        const long long coordinate = (long long)(rest % view->extents[axis - 1u]) + (long long)view->lag[axis - 1u];
        rest /= view->extents[axis - 1u];
        if ((coordinate < 0ll) || (coordinate >= extent))
        {
            return -1ll;
        }
        moved += coordinate * stride;
        stride *= extent;
    }
    return moved;
}

/**
 * @brief Counts or packs the runs of voxels positive in both frames, one chunk per thread.
 *
 * A run is voxels of the chunk, consecutive among those positive in both frames, carrying one pair.
 *
 * @param[in]  positive_before Sign words, first frame [BORROWS].
 * @param[in]  positive_after  Sign words, next frame [BORROWS].
 * @param[in]  labels_before   Peaks, first frame [BORROWS].
 * @param[in]  labels_after    Peaks, next frame [BORROWS].
 * @param[in]  voxels          Voxel count.
 * @param[in]  chunks          Chunk count.
 * @param[in]  offsets         Where each chunk writes, or NULL to count [BORROWS].
 * @param[out] chunk_counts    Runs per chunk, written when counting [BORROWS].
 * @param[out] pairs           Packed pair per run, written when packing [BORROWS].
 * @param[out] lengths         Voxels per run, written when packing [BORROWS].
 */
__global__ static void overlap_kernel(const unsigned long long *positive_before,
                                      const unsigned long long *positive_after,
                                      const unsigned int *labels_before, const unsigned int *labels_after,
                                      OverlapView view, unsigned int voxels, unsigned int chunks,
                                      const unsigned int *offsets, unsigned int *chunk_counts,
                                      unsigned long long *pairs, unsigned int *lengths)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= chunks)
    {
        return;
    }
    const unsigned int first = chunk * BASIN_OVERLAP_CHUNK;
    const unsigned int past = ((voxels - first) < BASIN_OVERLAP_CHUNK) ? voxels : (first + BASIN_OVERLAP_CHUNK);
    unsigned int slot = (offsets != NULL) ? offsets[chunk] : 0u;
    unsigned int runs = 0u;
    unsigned long long run_pair = 0ull;
    unsigned int run_length = 0u;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((positive_before[voxel / 64u] & (1ull << (voxel % 64u))) == 0ull)
        {
            continue;
        }
        const long long moved = device_overlap_moved(&view, voxel);
        if (moved < 0ll)
        {
            continue;
        }
        // Narrowing is safe: moved lies inside the view, below the voxel count.
        const unsigned int there = (unsigned int)moved;
        if ((positive_after[there / 64u] & (1ull << (there % 64u))) == 0ull)
        {
            continue;
        }
        // Widening each peak index to unsigned long long is exact; the before peak takes the high half.
        const unsigned long long pair = ((unsigned long long)labels_before[voxel] << 32u)
                                      | (unsigned long long)labels_after[there];
        if ((run_length != 0u) && (pair == run_pair))
        {
            run_length += 1u;
            continue;
        }
        if ((run_length != 0u) && (offsets != NULL))
        {
            pairs[slot] = run_pair;
            lengths[slot] = run_length;
            slot += 1u;
        }
        runs += (run_length != 0u) ? 1u : 0u;
        run_pair = pair;
        run_length = 1u;
    }
    if ((run_length != 0u) && (offsets != NULL))
    {
        pairs[slot] = run_pair;
        lengths[slot] = run_length;
    }
    runs += (run_length != 0u) ? 1u : 0u;
    if (offsets == NULL)
    {
        chunk_counts[chunk] = runs;
    }
}

/**
 * @brief Whether the kernel just launched ran without a device error.
 *
 * @return 1 where it did, 0 otherwise.
 */
static int overlap_launched(void)
{
    // No synchronise: the host's next read waits for the queue, so a launch only has to be accepted.
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

/** @brief The buffers one view needs, held between calls, with the run room they hold. */
struct HeldOverlap
{
    size_t voxels;
    unsigned int chunks;
    int uploads;
    unsigned long long *before_words;
    unsigned long long *after_words;
    unsigned int *before_labels;
    unsigned int *after_labels;
    unsigned int *counts;
    unsigned int *offsets;
    unsigned int *host_offsets;
    size_t run_room;
    unsigned long long *pairs;
    unsigned int *lengths;
    unsigned long long *host_pairs;
    unsigned int *host_lengths;
};

static HeldOverlap s_held_overlap;

/**
 * @brief Releases every held buffer.
 *
 * @param[in,out] held The held buffers [BORROWS].
 */
static void release_overlap(HeldOverlap *held)
{
    cudaFree(held->before_words);
    cudaFree(held->after_words);
    cudaFree(held->before_labels);
    cudaFree(held->after_labels);
    cudaFree(held->counts);
    cudaFree(held->offsets);
    cudaFree(held->pairs);
    cudaFree(held->lengths);
    free(held->host_offsets);
    free(held->host_pairs);
    free(held->host_lengths);
    memset(held, 0, sizeof(*held));
}

/**
 * @brief Holds the view's buffers, allocating only for a different view, and run room for this call's runs.
 *
 * @param[in] voxels  Voxels of the view; 0 asks only for run room.
 * @param[in] chunks  Chunks of the view.
 * @param[in] uploads 1 where the frames are uploaded into held buffers, 0 where the caller holds them on the device.
 * @param[in] runs    Runs this call emits; 0 asks only for the view's buffers.
 * @return            1 on success, 0 on a failure with nothing held.
 */
static int hold_overlap(size_t voxels, unsigned int chunks, int uploads, size_t runs)
{
    HeldOverlap *const held = &s_held_overlap;
    int ok = 1;
    if ((voxels != 0u) && ((held->voxels != voxels) || (held->uploads < uploads)))
    {
        release_overlap(held);
        const size_t words = (voxels + 63u) / 64u;
        if (uploads != 0)
        {
            ok = ok && (cudaMalloc((void **)&held->before_words, words * sizeof(unsigned long long)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&held->after_words, words * sizeof(unsigned long long)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&held->before_labels, voxels * sizeof(unsigned int)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&held->after_labels, voxels * sizeof(unsigned int)) == cudaSuccess);
        }
        ok = ok && (cudaMalloc((void **)&held->counts, (size_t)chunks * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&held->offsets, (size_t)chunks * sizeof(unsigned int)) == cudaSuccess);
        held->host_offsets = (unsigned int *)malloc((size_t)chunks * sizeof(unsigned int));
        ok = ok && (held->host_offsets != NULL);
        held->voxels = voxels;
        held->chunks = chunks;
        held->uploads = uploads;
    }
    if ((ok != 0) && (runs + 1u > held->run_room))
    {
        // Half again as much room, so a slowly growing series does not reallocate every frame.
        const size_t room = (runs + 1u) + (runs + 1u) / 2u;
        cudaFree(held->pairs);
        cudaFree(held->lengths);
        free(held->host_pairs);
        free(held->host_lengths);
        held->pairs = NULL;
        held->lengths = NULL;
        ok = ok && (cudaMalloc((void **)&held->pairs, room * sizeof(unsigned long long)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&held->lengths, room * sizeof(unsigned int)) == cudaSuccess);
        held->host_pairs = (unsigned long long *)malloc(room * sizeof(unsigned long long));
        held->host_lengths = (unsigned int *)malloc(room * sizeof(unsigned int));
        ok = ok && (held->host_pairs != NULL) && (held->host_lengths != NULL);
        held->run_room = (ok != 0) ? room : 0u;
    }
    if (ok == 0)
    {
        release_overlap(held);
    }
    return ok;
}

/**
 * @brief Refuses a request the engines cannot answer, and lays out the view of one that they can.
 *
 * @param[in]  args The request [BORROWS].
 * @param[out] view The view the kernel reads [BORROWS].
 * @return          1 where the request is answerable, 0 where it is refused.
 */
static int overlap_view(const BasinOverlapRequest *args, OverlapView *view)
{
    if ((args == NULL) || (args->labels_before == NULL) || (args->positive_before == NULL)
     || (args->labels_after == NULL) || (args->positive_after == NULL) || (args->voxels == 0u)
     || (args->voxels > (0xFFFFFFFFu - BASIN_OVERLAP_CHUNK)) || (args->room > BASIN_OVERLAP_ROOM_LIMIT)
     || ((args->room != 0u) && ((args->peaks_before == NULL) || (args->peaks_after == NULL)
                                || (args->counts == NULL))))
    {
        return 0;
    }
    if ((args->axes == 0u) || (args->axes > BASIN_OVERLAP_AXES))
    {
        return 0;
    }
    memset(view, 0, sizeof(*view));
    view->axes = args->axes;
    unsigned long long product = 1ull;
    for (unsigned int axis = 0u; axis < args->axes; axis += 1u)
    {
        view->extents[axis] = args->extents[axis];
        view->lag[axis] = args->lag[axis];
        product *= (unsigned long long)args->extents[axis];
    }
    int devices = 0;
    return ((product == (unsigned long long)args->voxels) && (cudaGetDeviceCount(&devices) == cudaSuccess)
            && (devices >= 1)) ? 1 : 0;
}

/**
 * @brief Counts, packs, sorts and tallies the runs of two frames already on the device.
 *
 * @param[in] args            The request, for the room and the outputs [BORROWS].
 * @param[in] view            The view.
 * @param[in] positive_before Device sign words, first frame [BORROWS].
 * @param[in] positive_after  Device sign words, next frame [BORROWS].
 * @param[in] labels_before   Device peaks, first frame [BORROWS].
 * @param[in] labels_after    Device peaks, next frame [BORROWS].
 * @return                    Distinct pairs, or BASIN_OVERLAP_REFUSED.
 */
static long overlap_tally(const BasinOverlapRequest *args, OverlapView view,
                          const unsigned long long *positive_before, const unsigned long long *positive_after,
                          const unsigned int *labels_before, const unsigned int *labels_after)
{
    HeldOverlap *const held = &s_held_overlap;
    const unsigned int chunks = held->chunks;
    const unsigned int blocks = (chunks + BASIN_OVERLAP_BLOCK - 1u) / BASIN_OVERLAP_BLOCK;
    unsigned int *const offsets = held->host_offsets;
    overlap_kernel<<<blocks, BASIN_OVERLAP_BLOCK>>>(positive_before, positive_after, labels_before, labels_after, view,
                                                    args->voxels, chunks, NULL, held->counts, NULL, NULL);
    int ok = overlap_launched();
    ok = ok && (cudaMemcpy(offsets, held->counts, (size_t)chunks * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);

    size_t total = 0u;
    for (unsigned int chunk = 0u; (ok != 0) && (chunk < chunks); chunk += 1u)
    {
        const unsigned int count = offsets[chunk];
        // Narrowing is safe: the running total never exceeds the voxel count.
        offsets[chunk] = (unsigned int)total;
        total += (size_t)count;
    }
    ok = ok && hold_overlap(0u, chunks, held->uploads, total);
    ok = ok && (cudaMemcpy(held->offsets, offsets, (size_t)chunks * sizeof(unsigned int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (ok != 0)
    {
        overlap_kernel<<<blocks, BASIN_OVERLAP_BLOCK>>>(positive_before, positive_after, labels_before, labels_after,
                                                        view, args->voxels, chunks, held->offsets, held->counts,
                                                        held->pairs, held->lengths);
        ok = overlap_launched();
    }
    unsigned long long *const pairs = held->host_pairs;
    unsigned int *const lengths = held->host_lengths;
    ok = ok && (cudaMemcpy(pairs, held->pairs, total * sizeof(unsigned long long), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(lengths, held->lengths, total * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);

    long answer = BASIN_OVERLAP_REFUSED;
    // The same ascending order the reference's qsort gives, reached by radix passes carrying each run's length.
    ok = ok && radix_sort_keyed(pairs, lengths, total);
    if (ok != 0)
    {
        size_t distinct = 0u;
        for (size_t run = 0u; run < total; run += 1u)
        {
            if ((run == 0u) || (pairs[run] != pairs[run - 1u]))
            {
                distinct += 1u;
            }
        }
        if (distinct <= (size_t)BASIN_OVERLAP_ROOM_LIMIT)
        {
            // Narrowing is safe: distinct was just held to BASIN_OVERLAP_ROOM_LIMIT.
            answer = (long)distinct;
            if (distinct <= (size_t)args->room)
            {
                size_t slot = 0u;
                for (size_t run = 0u; run < total; run += 1u)
                {
                    if ((run != 0u) && (pairs[run] == pairs[run - 1u]))
                    {
                        args->counts[slot - 1u] += lengths[run];
                        continue;
                    }
                    // Narrowing to each half keeps exactly the index that was packed there.
                    args->peaks_before[slot] = (unsigned int)(pairs[run] >> 32u);
                    args->peaks_after[slot] = (unsigned int)(pairs[run] & 0xFFFFFFFFull);
                    args->counts[slot] = lengths[run];
                    slot += 1u;
                }
            }
        }
    }
    // The buffers stay held for the next call of the same view.
    return answer;
}

extern "C" long basin_overlap_run(const BasinOverlapRequest *args)
{
    OverlapView view;
    if (overlap_view(args, &view) == 0)
    {
        return BASIN_OVERLAP_REFUSED;
    }
    // Widening unsigned int to size_t is exact.
    const size_t voxels = (size_t)args->voxels;
    const size_t words = (voxels + 63u) / 64u;
    const unsigned int chunks = (args->voxels + BASIN_OVERLAP_CHUNK - 1u) / BASIN_OVERLAP_CHUNK;
    int ok = hold_overlap(voxels, chunks, 1, 0u);
    const HeldOverlap *const held = &s_held_overlap;
    ok = ok && (cudaMemcpy(held->before_words, args->positive_before, words * sizeof(unsigned long long),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(held->after_words, args->positive_after, words * sizeof(unsigned long long),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(held->before_labels, args->labels_before, voxels * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(held->after_labels, args->labels_after, voxels * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    return (ok != 0) ? overlap_tally(args, view, held->before_words, held->after_words, held->before_labels,
                                     held->after_labels)
                     : BASIN_OVERLAP_REFUSED;
}

extern "C" long basin_overlap_run_on_device(const BasinOverlapRequest *args)
{
    OverlapView view;
    if (overlap_view(args, &view) == 0)
    {
        return BASIN_OVERLAP_REFUSED;
    }
    const unsigned int chunks = (args->voxels + BASIN_OVERLAP_CHUNK - 1u) / BASIN_OVERLAP_CHUNK;
    // Widening unsigned int to size_t is exact.
    const int ok = hold_overlap((size_t)args->voxels, chunks, s_held_overlap.uploads, 0u);
    return (ok != 0) ? overlap_tally(args, view, args->positive_before, args->positive_after, args->labels_before,
                                     args->labels_after)
                     : BASIN_OVERLAP_REFUSED;
}
