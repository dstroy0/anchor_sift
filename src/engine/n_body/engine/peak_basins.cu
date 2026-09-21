#include "peak_basins.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define PEAK_BASINS_BLOCK 256u

#define PEAK_BASINS_CHUNK 4096u

#define PEAK_BASINS_ROOM_LIMIT 0x7FFFFFFFu

static_assert(sizeof(unsigned int) == 4u, "peak_basins: unsigned int must be 32 bits");
static_assert(sizeof(unsigned long long) == 8u,
              "peak_basins: unsigned long long must be 64 bits to hold a basin's index sums");

struct BasinGeometry
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int chunks;
};

__global__ static void ascend_kernel(const float *field, BasinGeometry geometry,
                                     unsigned int *successor)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;

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

struct BasinBuffers
{
    float *field;
    unsigned int *successor;
    unsigned int *jumped;
    unsigned int *changed;
    unsigned int *sizes;
    unsigned long long *slice_sums;
    unsigned long long *row_sums;
    unsigned long long *column_sums;
    unsigned int *chunk_peaks;
    unsigned int *offsets;
    unsigned int *emitted_indices;
    float *emitted_values;
    unsigned int *emitted_sizes;
    unsigned long long *emitted_slices;
    unsigned long long *emitted_rows;
    unsigned long long *emitted_columns;
    unsigned int *host_offsets;
    unsigned int *host_indices;
    float *host_values;
    unsigned int *host_sizes;
    unsigned long long *host_slices;
    unsigned long long *host_rows;
    unsigned long long *host_columns;
    unsigned int *host_labels;
};

static int basins_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

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

        for (size_t chunk = 0u; chunk < chunks; chunk += 1u)
        {
            const unsigned int count = buffers.host_offsets[chunk];

            buffers.host_offsets[chunk] = (unsigned int)total;
            total += (unsigned long long)count;
        }
    }

    long answer = PEAK_BASINS_REFUSED;
    if ((ok != 0) && ((total == 0ull) || (total > (unsigned long long)args->room)))
    {

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

    if (ok != 0)
    {
        if (args->labels != NULL)
        {
            memcpy(args->labels, buffers.host_labels, voxels * sizeof(unsigned int));
        }
        for (size_t slot = 0u; slot < peaks; slot += 1u)
        {

            const double size = (double)buffers.host_sizes[slot];
            args->centroids[slot * 3u] = (double)buffers.host_slices[slot] / size;
            args->centroids[(slot * 3u) + 1u] = (double)buffers.host_rows[slot] / size;
            args->centroids[(slot * 3u) + 2u] = (double)buffers.host_columns[slot] / size;
        }
        memcpy(args->peak_values, buffers.host_values, peaks * sizeof(float));
        memcpy(args->peak_indices, buffers.host_indices, peaks * sizeof(unsigned int));
        memcpy(args->sizes, buffers.host_sizes, peaks * sizeof(unsigned int));

        answer = (long)peaks;
    }
    basins_release(&buffers);
    return answer;
}
