/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file peak_basins.cu
 * @brief Steepest ascent basins on the device: point uphill, jump pointers to the peak, count.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Every voxel points once at its highest neighbor or itself. Replacing each pointer with its
 *       target's pointer, repeated until nothing changes, takes every voxel to its peak in a number
 *       of passes logarithmic in the longest uphill path.
 * @note A tie in value goes to the lower index. Pointers between equal values then always fall in
 *       index, which rules out a cycle across a plateau, and every path ends at a voxel pointing
 *       at itself.
 */

#include "peak_basins.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define PEAK_BASINS_BLOCK 256u

/** @brief Consecutive voxels one thread walks when counting and writing peaks. */
#define PEAK_BASINS_CHUNK 4096u

/** @brief The most peaks a call reports, the largest count a long holds on every target. */
#define PEAK_BASINS_ROOM_LIMIT 0x7FFFFFFFu

static_assert(sizeof(unsigned int) == 4u, "peak_basins: unsigned int must be 32 bits");
static_assert(sizeof(unsigned long long) == 8u,
              "peak_basins: unsigned long long must be 64 bits to hold a basin's index sums");

/** @brief The shape the kernels read, passed by value. */
struct BasinGeometry
{
    unsigned int depth;  /**< Voxels along the slowest axis. */
    unsigned int height; /**< Voxels along the middle axis. */
    unsigned int width;  /**< Voxels along the fastest axis. */
    unsigned int voxels; /**< Voxels in the volume. */
    unsigned int chunks; /**< Chunks of PEAK_BASINS_CHUNK voxels covering it. */
};

/**
 * @brief One thread per voxel: point at the highest of the 27 voxels around and including it.
 *
 * @param[in]  field     The field [BORROWS].
 * @param[in]  geometry  The shape.
 * @param[out] successor The voxel each voxel points at [BORROWS].
 * @note The volume does not wrap. A neighbor past an edge is skipped.
 */
__global__ static void ascend_kernel(const float *field, BasinGeometry geometry,
                                     unsigned int *successor)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;

    // The entry refuses an extent above 2^31 - 1, so every coordinate fits an int and a step of -1
    // is seen as below zero.
    const int column = (int)(voxel % geometry.width);
    const int row = (int)((voxel / geometry.width) % geometry.height);
    const int slice = (int)(voxel / plane);

    unsigned int best = voxel;
    float best_value = field[voxel];
    for (int step_slice = -1; step_slice <= 1; step_slice += 1)
    {
        for (int step_row = -1; step_row <= 1; step_row += 1)
        {
            for (int step_column = -1; step_column <= 1; step_column += 1)
            {
                const int at_slice = slice + step_slice;
                const int at_row = row + step_row;
                const int at_column = column + step_column;

                if ((at_slice < 0) || (at_slice >= (int)geometry.depth) || (at_row < 0)
                 || (at_row >= (int)geometry.height) || (at_column < 0)
                 || (at_column >= (int)geometry.width))
                {
                    continue;
                }

                const unsigned int neighbour = ((unsigned int)at_slice * plane)
                                             + ((unsigned int)at_row * geometry.width)
                                             + (unsigned int)at_column;
                const float value = field[neighbour];
                if ((value > best_value) || ((value == best_value) && (neighbour < best)))
                {
                    best = neighbour;
                    best_value = value;
                }
            }
        }
    }
    successor[voxel] = best;
}

/**
 * @brief One thread per voxel: replace a pointer with its target's pointer.
 *
 * @param[in]  source      The pointers before this pass [BORROWS].
 * @param[in]  geometry    The shape.
 * @param[out] destination The pointers after this pass [BORROWS].
 * @param[out] changed     Set to 1 where any pointer moved [BORROWS].
 * @note Reads one array and writes another, so every thread sees the whole pass's input and the
 *       result does not depend on thread order.
 */
__global__ static void jump_kernel(const unsigned int *source, BasinGeometry geometry,
                                   unsigned int *destination, unsigned int *changed)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int jumped = source[source[voxel]];
    destination[voxel] = jumped;
    if (jumped != source[voxel])
    {
        atomicMax(changed, 1u);
    }
}

/**
 * @brief One thread per voxel: add a positive voxel to its peak's size and index sums.
 *
 * @param[in]  field       The field [BORROWS].
 * @param[in]  peak        The peak every voxel ascends to [BORROWS].
 * @param[in]  geometry    The shape.
 * @param[out] sizes       Positive voxels per peak [BORROWS].
 * @param[out] slice_sums  Sum of slice indices per peak [BORROWS].
 * @param[out] row_sums    Sum of row indices per peak [BORROWS].
 * @param[out] column_sums Sum of column indices per peak [BORROWS].
 * @note Written as !(value > 0), which also turns away a NaN.
 */
__global__ static void census_kernel(const float *field, const unsigned int *peak,
                                     BasinGeometry geometry, unsigned int *sizes,
                                     unsigned long long *slice_sums, unsigned long long *row_sums,
                                     unsigned long long *column_sums)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || !(field[voxel] > 0.0f))
    {
        return;
    }
    const unsigned int root = peak[voxel];
    const unsigned int plane = geometry.height * geometry.width;
    atomicAdd(&sizes[root], 1u);

    atomicAdd(&slice_sums[root], (unsigned long long)(voxel / plane));
    atomicAdd(&row_sums[root], (unsigned long long)((voxel / geometry.width) % geometry.height));
    atomicAdd(&column_sums[root], (unsigned long long)(voxel % geometry.width));
}

/**
 * @brief One thread per chunk: count the positive peaks in the chunk.
 *
 * @param[in]  field       The field [BORROWS].
 * @param[in]  peak        The peak every voxel ascends to [BORROWS].
 * @param[in]  geometry    The shape.
 * @param[out] chunk_peaks Positive peaks in each chunk [BORROWS].
 */
__global__ static void count_kernel(const float *field, const unsigned int *peak,
                                    BasinGeometry geometry, unsigned int *chunk_peaks)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int first = chunk * PEAK_BASINS_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < PEAK_BASINS_CHUNK)
                            ? geometry.voxels
                            : (first + PEAK_BASINS_CHUNK);
    unsigned int count = 0u;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((peak[voxel] == voxel) && (field[voxel] > 0.0f))
        {
            count += 1u;
        }
    }
    chunk_peaks[chunk] = count;
}

/**
 * @brief One thread per chunk: write each positive peak's index, value, size and sums at the
 *        chunk's offset.
 *
 * @note Peaks come out in ascending voxel index.
 */
__global__ static void emit_kernel(const float *field, const unsigned int *peak,
                                   const unsigned int *sizes, const unsigned long long *slice_sums,
                                   const unsigned long long *row_sums,
                                   const unsigned long long *column_sums,
                                   const unsigned int *offsets, BasinGeometry geometry,
                                   unsigned int *emitted_indices, float *emitted_values,
                                   unsigned int *emitted_sizes, unsigned long long *emitted_slices,
                                   unsigned long long *emitted_rows,
                                   unsigned long long *emitted_columns)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int first = chunk * PEAK_BASINS_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < PEAK_BASINS_CHUNK)
                            ? geometry.voxels
                            : (first + PEAK_BASINS_CHUNK);
    unsigned int slot = offsets[chunk];
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((peak[voxel] == voxel) && (field[voxel] > 0.0f))
        {
            emitted_indices[slot] = voxel;
            emitted_values[slot] = field[voxel];
            emitted_sizes[slot] = sizes[voxel];
            emitted_slices[slot] = slice_sums[voxel];
            emitted_rows[slot] = row_sums[voxel];
            emitted_columns[slot] = column_sums[voxel];
            slot += 1u;
        }
    }
}

/** @brief Every buffer one call uses, device and host. */
struct BasinBuffers
{
    float *field;                       /**< Device copy of the field. */
    unsigned int *successor;            /**< Device pointer per voxel, the peak once converged. */
    unsigned int *jumped;               /**< Device pointers being written by a jump pass. */
    unsigned int *changed;              /**< Device flag: a jump moved a pointer. */
    unsigned int *sizes;                /**< Device positive voxels per peak. */
    unsigned long long *slice_sums;     /**< Device slice index sum per peak. */
    unsigned long long *row_sums;       /**< Device row index sum per peak. */
    unsigned long long *column_sums;    /**< Device column index sum per peak. */
    unsigned int *chunk_peaks;          /**< Device peaks per chunk. */
    unsigned int *offsets;              /**< Device write offset per chunk. */
    unsigned int *emitted_indices;      /**< Device index of each peak. */
    float *emitted_values;              /**< Device value of each peak. */
    unsigned int *emitted_sizes;        /**< Device size of each basin. */
    unsigned long long *emitted_slices; /**< Device slice sum of each basin. */
    unsigned long long *emitted_rows;   /**< Device row sum of each basin. */
    unsigned long long *emitted_columns; /**< Device column sum of each basin. */
    unsigned int *host_offsets;         /**< Host peaks per chunk, then offsets. */
    unsigned int *host_indices;         /**< Host copy of the peak indices. */
    float *host_values;                 /**< Host copy of the peak values. */
    unsigned int *host_sizes;           /**< Host copy of the basin sizes. */
    unsigned long long *host_slices;    /**< Host copy of the slice sums. */
    unsigned long long *host_rows;      /**< Host copy of the row sums. */
    unsigned long long *host_columns;   /**< Host copy of the column sums. */
    unsigned int *host_labels;          /**< Host copy of every voxel's peak. */
};

/**
 * @brief Whether the last launch was accepted and ran to completion.
 *
 * @return 1 where neither the launch nor the kernel reported an error, 0 otherwise.
 */
static int basins_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

/**
 * @brief Frees every buffer.
 *
 * @param[in,out] buffers The buffers [BORROWS].
 * @note cudaFree and free both accept a null pointer, so a partly allocated set frees cleanly.
 */
static void basins_release(BasinBuffers *buffers)
{
    cudaFree(buffers->field);
    cudaFree(buffers->successor);
    cudaFree(buffers->jumped);
    cudaFree(buffers->changed);
    cudaFree(buffers->sizes);
    cudaFree(buffers->slice_sums);
    cudaFree(buffers->row_sums);
    cudaFree(buffers->column_sums);
    cudaFree(buffers->chunk_peaks);
    cudaFree(buffers->offsets);
    cudaFree(buffers->emitted_indices);
    cudaFree(buffers->emitted_values);
    cudaFree(buffers->emitted_sizes);
    cudaFree(buffers->emitted_slices);
    cudaFree(buffers->emitted_rows);
    cudaFree(buffers->emitted_columns);
    free(buffers->host_offsets);
    free(buffers->host_indices);
    free(buffers->host_values);
    free(buffers->host_sizes);
    free(buffers->host_slices);
    free(buffers->host_rows);
    free(buffers->host_columns);
    free(buffers->host_labels);
}

/**
 * @brief Takes every voxel to its peak and totals each basin's positive voxels.
 *
 * @param[in,out] buffers  The buffers, with the field uploaded [BORROWS].
 * @param[in]     geometry The shape.
 * @return                 1 where every step succeeded, 0 otherwise.
 * @note The two pointer arrays swap after every pass, and `successor` holds the latest either way.
 */
static int basins_label(BasinBuffers *buffers, BasinGeometry geometry)
{
    const unsigned int blocks = (geometry.voxels + PEAK_BASINS_BLOCK - 1u) / PEAK_BASINS_BLOCK;
    ascend_kernel<<<blocks, PEAK_BASINS_BLOCK>>>(buffers->field, geometry, buffers->successor);
    int ok = basins_launched();

    unsigned int changed = 1u;
    while ((ok != 0) && (changed != 0u))
    {
        ok = ok && (cudaMemset(buffers->changed, 0, sizeof(unsigned int)) == cudaSuccess);
        jump_kernel<<<blocks, PEAK_BASINS_BLOCK>>>(buffers->successor, geometry, buffers->jumped,
                                                   buffers->changed);
        ok = ok && basins_launched();
        ok = ok && (cudaMemcpy(&changed, buffers->changed, sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);

        unsigned int *const previous = buffers->successor;
        buffers->successor = buffers->jumped;
        buffers->jumped = previous;
    }

    const size_t voxels = (size_t)geometry.voxels;
    ok = ok && (cudaMemset(buffers->sizes, 0, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(buffers->slice_sums, 0, voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMemset(buffers->row_sums, 0, voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMemset(buffers->column_sums, 0, voxels * sizeof(unsigned long long))
                == cudaSuccess);
    if (ok != 0)
    {
        census_kernel<<<blocks, PEAK_BASINS_BLOCK>>>(buffers->field, buffers->successor, geometry,
                                                     buffers->sizes, buffers->slice_sums,
                                                     buffers->row_sums, buffers->column_sums);
        ok = basins_launched();
    }
    return ok;
}

extern "C" long peak_basins_run(const PeakBasinsRequest *args)
{
    if ((args == NULL) || (args->field == NULL) || (args->depth == 0u) || (args->height == 0u)
     || (args->width == 0u) || (args->room > PEAK_BASINS_ROOM_LIMIT)
     || ((args->room != 0u) && ((args->centroids == NULL) || (args->peak_values == NULL)
                                || (args->peak_indices == NULL) || (args->sizes == NULL))))
    {
        return PEAK_BASINS_REFUSED;
    }

    const unsigned long long plane = (unsigned long long)args->height
                                   * (unsigned long long)args->width;
    if (plane > 0xFFFFFFFFull)
    {
        return PEAK_BASINS_REFUSED;
    }
    const unsigned long long voxel_count = plane * (unsigned long long)args->depth;
    int devices = 0;

    // Every index and a chunk's end stay below 2^32, and every coordinate fits the int
    // ascend_kernel computes in.
    if ((voxel_count > (0xFFFFFFFFull - (unsigned long long)PEAK_BASINS_CHUNK))
     || (args->depth > 0x7FFFFFFFu) || (args->height > 0x7FFFFFFFu) || (args->width > 0x7FFFFFFFu)
     || (cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return PEAK_BASINS_REFUSED;
    }

    BasinGeometry geometry;
    memset(&geometry, 0, sizeof(geometry));
    geometry.depth = args->depth;
    geometry.height = args->height;
    geometry.width = args->width;

    // Bounded below 2^32 just above, so the count fits the unsigned int.
    geometry.voxels = (unsigned int)voxel_count;
    geometry.chunks = (geometry.voxels + PEAK_BASINS_CHUNK - 1u) / PEAK_BASINS_CHUNK;

    const size_t voxels = (size_t)geometry.voxels;
    const size_t chunks = (size_t)geometry.chunks;

    BasinBuffers buffers;
    memset(&buffers, 0, sizeof(buffers));
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&buffers.field, voxels * sizeof(float)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.successor, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.jumped, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.changed, sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.sizes, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.slice_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.row_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.column_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.chunk_peaks, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.offsets, chunks * sizeof(unsigned int)) == cudaSuccess);
    buffers.host_offsets = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    ok = ok && (buffers.host_offsets != NULL);
    ok = ok && (cudaMemcpy(buffers.field, args->field, voxels * sizeof(float),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && basins_label(&buffers, geometry);

    const unsigned int chunk_blocks = (geometry.chunks + PEAK_BASINS_BLOCK - 1u) / PEAK_BASINS_BLOCK;
    if (ok != 0)
    {
        count_kernel<<<chunk_blocks, PEAK_BASINS_BLOCK>>>(buffers.field, buffers.successor, geometry,
                                                          buffers.chunk_peaks);
        ok = basins_launched();
    }
    ok = ok && (cudaMemcpy(buffers.host_offsets, buffers.chunk_peaks, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);

    unsigned long long total = 0ull;
    if (ok != 0)
    {

        // An exclusive prefix sum turns each chunk's peak count into the index of its first peak.
        for (size_t chunk = 0u; chunk < chunks; chunk += 1u)
        {
            const unsigned int count = buffers.host_offsets[chunk];

            // total is at most one peak per voxel, below 2^32, and fits the unsigned int.
            buffers.host_offsets[chunk] = (unsigned int)total;
            total += (unsigned long long)count;
        }
    }

    long answer = PEAK_BASINS_REFUSED;
    if ((ok != 0) && ((total == 0ull) || (total > (unsigned long long)args->room)))
    {

        // No peaks, or more than the room holds. The count is returned and nothing is written.
        answer = (total > (unsigned long long)PEAK_BASINS_ROOM_LIMIT) ? PEAK_BASINS_REFUSED
                                                                      : (long)total;
        basins_release(&buffers);
        return answer;
    }

    const size_t peaks = (size_t)total;
    ok = ok && (cudaMalloc((void **)&buffers.emitted_indices, peaks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.emitted_values, peaks * sizeof(float)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.emitted_sizes, peaks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.emitted_slices,
                           peaks * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.emitted_rows,
                           peaks * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers.emitted_columns,
                           peaks * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.offsets, buffers.host_offsets, chunks * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        emit_kernel<<<chunk_blocks, PEAK_BASINS_BLOCK>>>(buffers.field, buffers.successor,
                                                         buffers.sizes, buffers.slice_sums,
                                                         buffers.row_sums, buffers.column_sums,
                                                         buffers.offsets, geometry,
                                                         buffers.emitted_indices,
                                                         buffers.emitted_values,
                                                         buffers.emitted_sizes,
                                                         buffers.emitted_slices,
                                                         buffers.emitted_rows,
                                                         buffers.emitted_columns);
        ok = basins_launched();
    }

    buffers.host_indices = (unsigned int *)malloc(peaks * sizeof(unsigned int));
    buffers.host_values = (float *)malloc(peaks * sizeof(float));
    buffers.host_sizes = (unsigned int *)malloc(peaks * sizeof(unsigned int));
    buffers.host_slices = (unsigned long long *)malloc(peaks * sizeof(unsigned long long));
    buffers.host_rows = (unsigned long long *)malloc(peaks * sizeof(unsigned long long));
    buffers.host_columns = (unsigned long long *)malloc(peaks * sizeof(unsigned long long));
    ok = ok && (buffers.host_indices != NULL) && (buffers.host_values != NULL)
      && (buffers.host_sizes != NULL) && (buffers.host_slices != NULL) && (buffers.host_rows != NULL)
      && (buffers.host_columns != NULL);
    ok = ok && (cudaMemcpy(buffers.host_indices, buffers.emitted_indices, peaks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_values, buffers.emitted_values, peaks * sizeof(float),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_sizes, buffers.emitted_sizes, peaks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_slices, buffers.emitted_slices,
                           peaks * sizeof(unsigned long long), cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_rows, buffers.emitted_rows,
                           peaks * sizeof(unsigned long long), cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_columns, buffers.emitted_columns,
                           peaks * sizeof(unsigned long long), cudaMemcpyDeviceToHost) == cudaSuccess);
    if ((ok != 0) && (args->labels != NULL))
    {

        buffers.host_labels = (unsigned int *)malloc(voxels * sizeof(unsigned int));
        ok = (buffers.host_labels != NULL) ? 1 : 0;
        ok = ok && (cudaMemcpy(buffers.host_labels, buffers.successor, voxels * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }

    // Every output is written here or not at all.
    if (ok != 0)
    {
        if (args->labels != NULL)
        {
            memcpy(args->labels, buffers.host_labels, voxels * sizeof(unsigned int));
        }
        for (size_t slot = 0u; slot < peaks; slot += 1u)
        {

            // A reported peak is positive and counts itself, so every size here is at least 1.
            const double size = (double)buffers.host_sizes[slot];
            args->centroids[slot * 3u] = (double)buffers.host_slices[slot] / size;
            args->centroids[(slot * 3u) + 1u] = (double)buffers.host_rows[slot] / size;
            args->centroids[(slot * 3u) + 2u] = (double)buffers.host_columns[slot] / size;
        }
        memcpy(args->peak_values, buffers.host_values, peaks * sizeof(float));
        memcpy(args->peak_indices, buffers.host_indices, peaks * sizeof(unsigned int));
        memcpy(args->sizes, buffers.host_sizes, peaks * sizeof(unsigned int));

        // peaks is at most `room`, below 2^31, and fits a long on every target.
        answer = (long)peaks;
    }
    basins_release(&buffers);
    return answer;
}
