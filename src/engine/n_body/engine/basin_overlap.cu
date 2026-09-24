/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file basin_overlap.cu
 * @brief The device arm of the lagged overlap count, run length encoded per chunk of voxels.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note One thread walks one chunk of BASIN_OVERLAP_CHUNK consecutive voxels. Neighboring voxels
 *       of one basin usually land in one basin. A chunk yields long runs of one label pair, and a
 *       thread writes a run as a pair and a length instead of one key per voxel.
 * @note Two passes over the same kernel. The first counts each chunk's runs. The host turns the
 *       counts into write offsets, and the second pass writes the runs there. The runs are sorted on
 *       the host with their lengths carried along, and equal pairs are summed. The result equals
 *       basin_overlap_host's pair for pair.
 * @note Every quantity is an integer: voxel indices, labels, lags and counts.
 */

#include "basin_overlap.h"
#include "radix_keys.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define BASIN_OVERLAP_BLOCK 256u

/** @brief Consecutive voxels one thread walks. */
#define BASIN_OVERLAP_CHUNK 256u

static_assert(sizeof(unsigned int) == 4u, "basin_overlap: unsigned int must be 32 bits, a peak index");
static_assert(sizeof(unsigned long long) == 8u, "basin_overlap: unsigned long long must be 64 bits, a pair");

/**
 * @brief The shape and lag a kernel needs, passed by value so no device copy is made.
 */
struct OverlapView
{
    unsigned int axes;                        /**< Axes in use. */
    unsigned int extents[BASIN_OVERLAP_AXES]; /**< Voxels along each axis. */
    int lag[BASIN_OVERLAP_AXES];              /**< Shift per axis. */
};

/**
 * @brief Where a voxel lands after the lag, on the device.
 *
 * @param[in] view     The shape and lag [BORROWS].
 * @param[in] position The voxel's index, last axis fastest.
 * @return             The index it lands on, or -1 where it leaves the volume.
 * @note The same arithmetic as overlap_moved in basin_overlap.c, transcribed, since a __device__
 *       function cannot be shared with the host translation unit.
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
 * @brief One thread per chunk: collapse the chunk's overlapping pairs into runs.
 *
 * @param[in]  positive_before One bit per before voxel [BORROWS].
 * @param[in]  positive_after  One bit per after voxel [BORROWS].
 * @param[in]  labels_before   Label of every before voxel [BORROWS].
 * @param[in]  labels_after    Label of every after voxel [BORROWS].
 * @param[in]  view            The shape and lag.
 * @param[in]  voxels          Voxels per frame.
 * @param[in]  chunks          Chunks covering the frame.
 * @param[in]  offsets         Where each chunk writes its first run, or NULL on the counting pass
 *                             [BORROWS].
 * @param[out] chunk_counts    Runs in each chunk, written on the counting pass only [BORROWS].
 * @param[out] pairs           Pair of each run, written on the writing pass only [BORROWS].
 * @param[out] lengths         Voxels in each run, written on the writing pass only [BORROWS].
 * @note A run is a stretch of voxels, positive and landing on a positive voxel, carrying one label
 *       pair, with any number of skipped voxels between them. The same pair can open several runs
 *       in one chunk, and the host sums them.
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
    // The last chunk ends at the frame's end. The test is on the room left and cannot overflow.
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

        // moved is a voxel index below `voxels`, which fits an unsigned int.
        const unsigned int there = (unsigned int)moved;
        if ((positive_after[there / 64u] & (1ull << (there % 64u))) == 0ull)
        {
            continue;
        }

        const unsigned long long pair = ((unsigned long long)labels_before[voxel] << 32u)
                                      | (unsigned long long)labels_after[there];
        if ((run_length != 0u) && (pair == run_pair))
        {
            run_length += 1u;
            continue;
        }
        // A new pair closes the open run. Only the writing pass stores it. Both passes count it,
        // and the offsets from the first pass line up with the writes of the second.
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
 * @brief Whether the last launch was accepted.
 *
 * @return 1 where no launch error is pending, 0 otherwise.
 * @note Catches a launch the device refused. A fault inside the kernel surfaces at the next
 *       cudaMemcpy, which every caller checks.
 */
static int overlap_launched(void)
{

    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

/**
 * @brief Device and host buffers held between calls.
 *
 * @note Every frame of one recording has one size. Holding the buffers across calls on frames of
 *       that size skips a cudaMalloc and cudaFree per call.
 */
struct HeldOverlap
{
    size_t voxels;                   /**< Voxel count the frame buffers were sized for. */
    unsigned int chunks;             /**< Chunks the count and offset buffers were sized for. */
    int uploads;                     /**< 1 where the four frame buffers are allocated. */
    unsigned long long *before_words; /**< Device copy of the before bits. */
    unsigned long long *after_words; /**< Device copy of the after bits. */
    unsigned int *before_labels;     /**< Device copy of the before labels. */
    unsigned int *after_labels;      /**< Device copy of the after labels. */
    unsigned int *counts;            /**< Device runs per chunk. */
    unsigned int *offsets;           /**< Device write offset per chunk. */
    unsigned int *host_offsets;      /**< Host copy of the counts, turned into offsets in place. */
    size_t run_room;                 /**< Runs the four run buffers hold. */
    unsigned long long *pairs;       /**< Device pair of each run. */
    unsigned int *lengths;           /**< Device length of each run. */
    unsigned long long *host_pairs;  /**< Host copy of the pairs, sorted in place. */
    unsigned int *host_lengths;      /**< Host copy of the lengths, reordered with the pairs. */
};

/** @brief The one set of held buffers. Not safe to use from two threads at once. */
static HeldOverlap s_held_overlap;

/**
 * @brief Frees every held buffer and zeroes the record.
 *
 * @param[in,out] held The buffers [BORROWS].
 * @note cudaFree and free both accept a null pointer. A partly allocated record frees cleanly.
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
 * @brief Makes the held buffers big enough for a frame and a run count.
 *
 * @param[in] voxels  Voxels per frame, or 0 to leave the frame buffers as they are.
 * @param[in] chunks  Chunks covering the frame.
 * @param[in] uploads 1 where the frames arrive from host memory and need device copies.
 * @param[in] runs    Runs the next writing pass will produce.
 * @return            1 where every buffer is in place, 0 where an allocation failed, with every
 *                    buffer released.
 * @note The frame buffers are rebuilt only when the voxel count changes or uploads are newly
 *       needed. The run buffers grow to half again the room asked for, which keeps a slowly rising
 *       run count from reallocating on every frame.
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

        // One more than asked. A count of zero still allocates, and half again for growth.
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
 * @brief Checks a request and copies its shape and lag into a view.
 *
 * @param[in]  args The request [BORROWS].
 * @param[out] view The shape and lag [BORROWS].
 * @return          1 where the request is well formed and a device answers, 0 otherwise.
 * @note Refuses a voxel count within BASIN_OVERLAP_CHUNK of 2^32. The last chunk's start plus a
 *       chunk is computed in unsigned int, and that keeps it from wrapping.
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
 * @brief Runs both passes over frames already on the device and reduces the runs to pairs.
 *
 * @param[in] args            The request, read for its sizes and written through its outputs
 *                            [BORROWS].
 * @param[in] view            The shape and lag.
 * @param[in] positive_before Device before bits [BORROWS].
 * @param[in] positive_after  Device after bits [BORROWS].
 * @param[in] labels_before   Device before labels [BORROWS].
 * @param[in] labels_after    Device after labels [BORROWS].
 * @return                    What basin_overlap_host returns for the same frames, or
 *                            BASIN_OVERLAP_REFUSED where a device step or an allocation failed.
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

    // An exclusive prefix sum turns each chunk's run count into the index of its first run.
    size_t total = 0u;
    for (unsigned int chunk = 0u; (ok != 0) && (chunk < chunks); chunk += 1u)
    {
        const unsigned int count = offsets[chunk];

        // total is at most one run per voxel, below 2^32, and fits the unsigned int.
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

    // Runs of one pair from different chunks become neighbors once sorted, and are summed below.
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

            // distinct is at most BASIN_OVERLAP_ROOM_LIMIT, which a long holds on every target.
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

                    args->peaks_before[slot] = (unsigned int)(pairs[run] >> 32u);
                    args->peaks_after[slot] = (unsigned int)(pairs[run] & 0xFFFFFFFFull);
                    args->counts[slot] = lengths[run];
                    slot += 1u;
                }
            }
        }
    }

    return answer;
}

extern "C" long basin_overlap_run(const BasinOverlapRequest *args)
{
    OverlapView view;
    if (overlap_view(args, &view) == 0)
    {
        return BASIN_OVERLAP_REFUSED;
    }

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

    // The frames are the caller's device memory and need no upload buffers. Passing the held flag
    // through keeps any upload buffers an earlier basin_overlap_run allocated.
    const int ok = hold_overlap((size_t)args->voxels, chunks, s_held_overlap.uploads, 0u);
    return (ok != 0) ? overlap_tally(args, view, args->positive_before, args->positive_after, args->labels_before,
                                     args->labels_after)
                     : BASIN_OVERLAP_REFUSED;
}
