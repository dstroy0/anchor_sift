// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "body_overlap.h"
#include "radix_keys.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define BODY_OVERLAP_BLOCK 256u

#define BODY_OVERLAP_CHUNK 256u

static_assert(sizeof(unsigned int) == 4u, "body_overlap: unsigned int must be 32 bits, a peak index");
static_assert(sizeof(unsigned long long) == 8u, "body_overlap: unsigned long long must be 64 bits, a pair");

struct OverlapView
{
    unsigned int axes;
    unsigned int extents[BODY_OVERLAP_AXES];
    int lag[BODY_OVERLAP_AXES];
    const unsigned int *lag_peaks;
    const int *lag_steps;
    unsigned int lag_count;
};

__device__ static const int *device_overlap_lag_of(const OverlapView *view, unsigned int label)
{
    unsigned int low = 0u;
    unsigned int high = view->lag_count;
    while (low < high)
    {
        const unsigned int middle = low + ((high - low) / 2u);
        low = (view->lag_peaks[middle] < label) ? (middle + 1u) : low;
        high = (view->lag_peaks[middle] < label) ? high : middle;
    }
    const int found = (low < view->lag_count) && (view->lag_peaks[low] == label);
    return (found != 0) ? &view->lag_steps[(unsigned long long)low * view->axes] : view->lag;
}

__device__ static long long device_overlap_moved(const OverlapView *view, unsigned int position, unsigned int label)
{
    const int *const lag = device_overlap_lag_of(view, label);
    unsigned int rest = position;
    long long moved = 0ll;
    long long stride = 1ll;
    for (unsigned int axis = view->axes; axis > 0u; axis -= 1u)
    {
        const long long extent = (long long)view->extents[axis - 1u];
        const long long coordinate = (long long)(rest % view->extents[axis - 1u]) + (long long)lag[axis - 1u];
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

__global__ static void overlap_kernel(const unsigned long long *positive_before,
                                      const unsigned long long *positive_after, const unsigned int *labels_before,
                                      const unsigned int *labels_after, OverlapView view, unsigned int voxels,
                                      unsigned int chunks, const unsigned int *offsets, unsigned int *chunk_counts,
                                      unsigned long long *pairs, unsigned int *lengths)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= chunks)
    {
        return;
    }
    const unsigned int first = chunk * BODY_OVERLAP_CHUNK;
    const unsigned int end = ((voxels - first) < BODY_OVERLAP_CHUNK) ? voxels : (first + BODY_OVERLAP_CHUNK);
    unsigned int slot = (offsets != NULL) ? offsets[chunk] : 0u;
    unsigned int runs = 0u;
    unsigned long long run_pair = 0ull;
    unsigned int run_length = 0u;
    for (unsigned int voxel = first; voxel < end; voxel += 1u)
    {
        if ((positive_before[voxel / 64u] & (1ull << (voxel % 64u))) == 0ull)
        {
            continue;
        }
        const long long moved = device_overlap_moved(&view, voxel, labels_before[voxel]);
        if (moved < 0ll)
        {
            continue;
        }
        const unsigned int there = (unsigned int)moved;
        if ((positive_after[there / 64u] & (1ull << (there % 64u))) == 0ull)
        {
            continue;
        }
        const unsigned long long pair =
            ((unsigned long long)labels_before[voxel] << 32u) | (unsigned long long)labels_after[there];
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

static int overlap_launched(void)
{
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

struct OverlapResident
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
    size_t run_capacity;
    unsigned long long *pairs;
    unsigned int *lengths;
    unsigned long long *host_pairs;
    unsigned int *host_lengths;
    size_t lag_capacity;
    unsigned int *lag_peaks;
    int *lag_steps;
};

static OverlapResident s_overlap_resident;

static void release_overlap(OverlapResident *resident)
{
    cudaFree(resident->before_words);
    cudaFree(resident->after_words);
    cudaFree(resident->before_labels);
    cudaFree(resident->after_labels);
    cudaFree(resident->counts);
    cudaFree(resident->offsets);
    cudaFree(resident->pairs);
    cudaFree(resident->lengths);
    cudaFree(resident->lag_peaks);
    cudaFree(resident->lag_steps);
    free(resident->host_offsets);
    free(resident->host_pairs);
    free(resident->host_lengths);
    memset(resident, 0, sizeof(*resident));
}

static int reserve_overlap(size_t voxels, unsigned int chunks, int uploads, size_t runs)
{
    OverlapResident *const resident = &s_overlap_resident;
    int ok = 1;
    if ((voxels != 0u) && ((resident->voxels != voxels) || (resident->uploads < uploads)))
    {
        release_overlap(resident);
        const size_t words = (voxels + 63u) / 64u;
        if (uploads != 0)
        {
            ok =
                ok && (cudaMalloc((void **)&resident->before_words, words * sizeof(unsigned long long)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&resident->after_words, words * sizeof(unsigned long long)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&resident->before_labels, voxels * sizeof(unsigned int)) == cudaSuccess);
            ok = ok && (cudaMalloc((void **)&resident->after_labels, voxels * sizeof(unsigned int)) == cudaSuccess);
        }
        ok = ok && (cudaMalloc((void **)&resident->counts, (size_t)chunks * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&resident->offsets, (size_t)chunks * sizeof(unsigned int)) == cudaSuccess);
        resident->host_offsets = (unsigned int *)malloc((size_t)chunks * sizeof(unsigned int));
        ok = ok && (resident->host_offsets != NULL);
        resident->voxels = voxels;
        resident->chunks = chunks;
        resident->uploads = uploads;
    }
    if ((ok != 0) && (runs + 1u > resident->run_capacity))
    {
        const size_t capacity = (runs + 1u) + (runs + 1u) / 2u;
        cudaFree(resident->pairs);
        cudaFree(resident->lengths);
        free(resident->host_pairs);
        free(resident->host_lengths);
        resident->pairs = NULL;
        resident->lengths = NULL;
        ok = ok && (cudaMalloc((void **)&resident->pairs, capacity * sizeof(unsigned long long)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&resident->lengths, capacity * sizeof(unsigned int)) == cudaSuccess);
        resident->host_pairs = (unsigned long long *)malloc(capacity * sizeof(unsigned long long));
        resident->host_lengths = (unsigned int *)malloc(capacity * sizeof(unsigned int));
        ok = ok && (resident->host_pairs != NULL) && (resident->host_lengths != NULL);
        resident->run_capacity = (ok != 0) ? capacity : 0u;
    }
    if (ok == 0)
    {
        release_overlap(resident);
    }
    return ok;
}

static int overlap_view(const BodyOverlapRequest *args, OverlapView *view)
{
    if ((args == NULL) || (args->labels_before == NULL) || (args->positive_before == NULL) ||
        (args->labels_after == NULL) || (args->positive_after == NULL) || (args->voxels == 0u) ||
        (args->voxels > (0xFFFFFFFFu - BODY_OVERLAP_CHUNK)) || (args->capacity > BODY_OVERLAP_CAPACITY_LIMIT) ||
        ((args->capacity != 0u) &&
         ((args->peaks_before == NULL) || (args->peaks_after == NULL) || (args->counts == NULL))))
    {
        return 0;
    }
    if ((args->axes == 0u) || (args->axes > BODY_OVERLAP_AXES))
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
    return ((product == (unsigned long long)args->voxels) && (cudaGetDeviceCount(&devices) == cudaSuccess) &&
            (devices >= 1))
               ? 1
               : 0;
}

static int overlap_lags(const BodyOverlapRequest *args, OverlapView *view)
{
    OverlapResident *const resident = &s_overlap_resident;
    view->lag_peaks = NULL;
    view->lag_steps = NULL;
    view->lag_count = 0u;
    if (args->lag_count == 0u)
    {
        return 1;
    }
    if ((args->lag_peaks == NULL) || (args->lag_steps == NULL))
    {
        return 0;
    }
    int ok = 1;
    if ((size_t)args->lag_count > resident->lag_capacity)
    {
        cudaFree(resident->lag_peaks);
        cudaFree(resident->lag_steps);
        resident->lag_peaks = NULL;
        resident->lag_steps = NULL;
        ok = (cudaMalloc((void **)&resident->lag_peaks, (size_t)args->lag_count * sizeof(unsigned int)) ==
              cudaSuccess) &&
             (cudaMalloc((void **)&resident->lag_steps, (size_t)args->lag_count * args->axes * sizeof(int)) ==
              cudaSuccess);
        resident->lag_capacity = (ok != 0) ? (size_t)args->lag_count : 0u;
    }
    ok = ok &&
         (cudaMemcpy(resident->lag_peaks, args->lag_peaks, (size_t)args->lag_count * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess) &&
         (cudaMemcpy(resident->lag_steps, args->lag_steps, (size_t)args->lag_count * args->axes * sizeof(int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    view->lag_peaks = resident->lag_peaks;
    view->lag_steps = resident->lag_steps;
    view->lag_count = (ok != 0) ? args->lag_count : 0u;
    return ok;
}

static long overlap_results(const BodyOverlapRequest *args, OverlapView view, const unsigned long long *positive_before,
                            const unsigned long long *positive_after, const unsigned int *labels_before,
                            const unsigned int *labels_after)
{
    OverlapResident *const resident = &s_overlap_resident;
    const unsigned int chunks = resident->chunks;
    const unsigned int blocks = (chunks + BODY_OVERLAP_BLOCK - 1u) / BODY_OVERLAP_BLOCK;
    unsigned int *const offsets = resident->host_offsets;
    overlap_kernel<<<blocks, BODY_OVERLAP_BLOCK>>>(positive_before, positive_after, labels_before, labels_after, view,
                                                   args->voxels, chunks, NULL, resident->counts, NULL, NULL);
    int ok = overlap_launched();
    ok = ok && (cudaMemcpy(offsets, resident->counts, (size_t)chunks * sizeof(unsigned int), cudaMemcpyDeviceToHost) ==
                cudaSuccess);

    size_t total = 0u;
    for (unsigned int chunk = 0u; (ok != 0) && (chunk < chunks); chunk += 1u)
    {
        const unsigned int count = offsets[chunk];
        offsets[chunk] = (unsigned int)total;
        total += (size_t)count;
    }
    ok = ok && reserve_overlap(0u, chunks, resident->uploads, total);
    ok = ok && (cudaMemcpy(resident->offsets, offsets, (size_t)chunks * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
                cudaSuccess);
    if (ok != 0)
    {
        overlap_kernel<<<blocks, BODY_OVERLAP_BLOCK>>>(positive_before, positive_after, labels_before, labels_after,
                                                       view, args->voxels, chunks, resident->offsets, resident->counts,
                                                       resident->pairs, resident->lengths);
        ok = overlap_launched();
    }
    unsigned long long *const pairs = resident->host_pairs;
    unsigned int *const lengths = resident->host_lengths;
    ok = ok && (cudaMemcpy(pairs, resident->pairs, total * sizeof(unsigned long long), cudaMemcpyDeviceToHost) ==
                cudaSuccess);
    ok = ok &&
         (cudaMemcpy(lengths, resident->lengths, total * sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess);

    long answer = BODY_OVERLAP_ERROR;
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
        if (distinct <= (size_t)BODY_OVERLAP_CAPACITY_LIMIT)
        {
            answer = (long)distinct;
            if (distinct <= (size_t)args->capacity)
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

extern "C" long body_overlap_run(const BodyOverlapRequest *args)
{
    OverlapView view;
    if (overlap_view(args, &view) == 0)
    {
        return BODY_OVERLAP_ERROR;
    }
    const size_t voxels = (size_t)args->voxels;
    const size_t words = (voxels + 63u) / 64u;
    const unsigned int chunks = (args->voxels + BODY_OVERLAP_CHUNK - 1u) / BODY_OVERLAP_CHUNK;
    int ok = reserve_overlap(voxels, chunks, 1, 0u);
    const OverlapResident *const resident = &s_overlap_resident;
    ok = ok && (cudaMemcpy(resident->before_words, args->positive_before, words * sizeof(unsigned long long),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(resident->after_words, args->positive_after, words * sizeof(unsigned long long),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(resident->before_labels, args->labels_before, voxels * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(resident->after_labels, args->labels_after, voxels * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && overlap_lags(args, &view);
    return (ok != 0) ? overlap_results(args, view, resident->before_words, resident->after_words,
                                       resident->before_labels, resident->after_labels)
                     : BODY_OVERLAP_ERROR;
}

extern "C" long body_overlap_run_on_device(const BodyOverlapRequest *args)
{
    OverlapView view;
    if (overlap_view(args, &view) == 0)
    {
        return BODY_OVERLAP_ERROR;
    }
    const unsigned int chunks = (args->voxels + BODY_OVERLAP_CHUNK - 1u) / BODY_OVERLAP_CHUNK;
    const int ok =
        reserve_overlap((size_t)args->voxels, chunks, s_overlap_resident.uploads, 0u) && overlap_lags(args, &view);
    return (ok != 0) ? overlap_results(args, view, args->positive_before, args->positive_after, args->labels_before,
                                       args->labels_after)
                     : BODY_OVERLAP_ERROR;
}
