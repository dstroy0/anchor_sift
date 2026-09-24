// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "box_history.h"

#include <cuda_runtime.h>

#define BOX_HISTORY_THREADS 256u

static_assert((ENGINE_HISTORY_BITS * 4u) == 64u, "box_history: a window's counts fill one 64 bit word, a nibble a bit");
static_assert(ENGINE_HISTORY_WINDOW <= 15u, "box_history: a window's count must fit a nibble");

struct BoxHistoryShape
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
};

__device__ static unsigned long long box_history_key_cell(const BoxHistoryShape *shape, unsigned int depth_place,
                                                          unsigned int height_place, unsigned int width_place)
{
    return ((((unsigned long long)depth_place * (shape->height + 1u)) + height_place)
            * (unsigned long long)(shape->width + 1u))
         + width_place;
}

__global__ static void box_history_row_kernel(const unsigned long long *window_counts, BoxHistoryShape shape,
                                              unsigned int bit, unsigned int *key)
{
    const unsigned int line = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (line >= (shape.depth * shape.height))
    {
        return;
    }
    const unsigned int depth_place = line / shape.height;
    const unsigned int height_place = line % shape.height;
    const unsigned long long first = (unsigned long long)line * shape.width;
    unsigned int running = 0u;
    for (unsigned int width_place = 0u; width_place < shape.width; width_place += 1u)
    {
        running += (unsigned int)((window_counts[first + width_place] >> (4u * bit)) & 0xFull);
        key[box_history_key_cell(&shape, depth_place + 1u, height_place + 1u, width_place + 1u)] = running;
    }
}

__global__ static void box_history_column_kernel(BoxHistoryShape shape, unsigned int axis, unsigned int *key)
{
    const unsigned int line = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int across = (axis == 0u) ? shape.height : shape.depth;
    const unsigned int extent = (axis == 0u) ? shape.depth : shape.height;
    if (line >= (across * shape.width))
    {
        return;
    }
    const unsigned int across_place = (line / shape.width) + 1u;
    const unsigned int width_place = (line % shape.width) + 1u;
    unsigned int running = 0u;
    for (unsigned int place = 1u; place <= extent; place += 1u)
    {
        const unsigned long long cell = (axis == 0u) ? box_history_key_cell(&shape, place, across_place, width_place)
                                                     : box_history_key_cell(&shape, across_place, place, width_place);
        running += key[cell];
        key[cell] = running;
    }
}

__global__ static void box_history_gather_kernel(const unsigned int *key, BoxHistoryShape shape,
                                                 const unsigned int *extents, unsigned int bodies,
                                                 unsigned int windows, unsigned int window, unsigned int bit,
                                                 unsigned int *counts)
{
    const unsigned int body = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (body >= bodies)
    {
        return;
    }
    const unsigned int *const extent = &extents[BOX_HISTORY_EXTENT_FIELDS * body];
    const unsigned int empty_box = (unsigned int)((extent[0] > extent[3]) || (extent[1] > extent[4])
                                                  || (extent[2] > extent[5]));
    const unsigned int low_depth = (empty_box != 0u) ? 0u : extent[0];
    const unsigned int low_height = (empty_box != 0u) ? 0u : extent[1];
    const unsigned int low_width = (empty_box != 0u) ? 0u : extent[2];
    const unsigned int high_depth = (empty_box != 0u) ? 0u : (extent[3] + 1u);
    const unsigned int high_height = (empty_box != 0u) ? 0u : (extent[4] + 1u);
    const unsigned int high_width = (empty_box != 0u) ? 0u : (extent[5] + 1u);
    const unsigned int box_count = key[box_history_key_cell(&shape, high_depth, high_height, high_width)]
                                 - key[box_history_key_cell(&shape, low_depth, high_height, high_width)]
                                 - key[box_history_key_cell(&shape, high_depth, low_height, high_width)]
                                 - key[box_history_key_cell(&shape, high_depth, high_height, low_width)]
                                 + key[box_history_key_cell(&shape, low_depth, low_height, high_width)]
                                 + key[box_history_key_cell(&shape, low_depth, high_height, low_width)]
                                 + key[box_history_key_cell(&shape, high_depth, low_height, low_width)]
                                 - key[box_history_key_cell(&shape, low_depth, low_height, low_width)];
    counts[((((unsigned long long)body * windows) + window) * ENGINE_HISTORY_BITS) + bit] = box_count;
}

__global__ static void box_history_walk_kernel(const unsigned long long *window_counts, BoxHistoryShape shape,
                                               const unsigned int *extents, unsigned int bodies, unsigned int windows,
                                               unsigned int window, const unsigned int *counts,
                                               unsigned long long *disagreements)
{
    const unsigned int body = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (body >= bodies)
    {
        return;
    }
    const unsigned int *const extent = &extents[BOX_HISTORY_EXTENT_FIELDS * body];
    unsigned int walked_counts[ENGINE_HISTORY_BITS];
    for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
    {
        walked_counts[bit] = 0u;
    }
    for (unsigned int depth_place = extent[0]; depth_place <= extent[3]; depth_place += 1u)
    {
        for (unsigned int height_place = extent[1]; height_place <= extent[4]; height_place += 1u)
        {
            const unsigned long long first
                = (((unsigned long long)depth_place * shape.height) + height_place) * shape.width;
            for (unsigned int width_place = extent[2]; width_place <= extent[5]; width_place += 1u)
            {
                const unsigned long long word = window_counts[first + width_place];
                for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
                {
                    walked_counts[bit] += (unsigned int)((word >> (4u * bit)) & 0xFull);
                }
            }
        }
    }
    const unsigned int *const box_counts
        = &counts[(((unsigned long long)body * windows) + window) * ENGINE_HISTORY_BITS];
    unsigned int disagreeing_bits = 0u;
    for (unsigned int bit = 0u; bit < ENGINE_HISTORY_BITS; bit += 1u)
    {
        disagreeing_bits += (walked_counts[bit] != box_counts[bit]) ? 1u : 0u;
    }
    if (disagreeing_bits != 0u)
    {
        atomicAdd(disagreements, (unsigned long long)disagreeing_bits);
    }
}

extern "C" long box_history_gather(const BoxHistoryRequest *request)
{
    if ((request == NULL) || (request->history == NULL) || (request->history->history == NULL)
     || (request->extents == NULL) || (request->counts == NULL) || (request->disagreements == NULL)
     || (request->microseconds == NULL) || (request->history->extent[1] > 0xFFFFFull)
     || (request->history->extent[2] > 0xFFFFFull) || (request->history->extent[3] > 0xFFFFFull))
    {
        return BOX_HISTORY_REFUSED;
    }
    const unsigned long long start_microseconds = engine_clock_microseconds();
    const unsigned long long voxels
        = request->history->extent[1] * request->history->extent[2] * request->history->extent[3];
    if (voxels > (0xFFFFFFFFull / 15ull))
    {
        return BOX_HISTORY_REFUSED;
    }
    const BoxHistoryShape shape = {(unsigned int)request->history->extent[1],
                                   (unsigned int)request->history->extent[2],
                                   (unsigned int)request->history->extent[3]};
    const unsigned int windows = (unsigned int)request->history->windows;
    const size_t key_cells = (size_t)(shape.depth + 1u) * (shape.height + 1u) * (shape.width + 1u);
    const size_t count_entries = (size_t)request->bodies * windows * ENGINE_HISTORY_BITS;
    unsigned long long *device_window_counts = NULL;
    unsigned int *device_key = NULL;
    unsigned int *device_extents = NULL;
    unsigned int *device_counts = NULL;
    unsigned long long *device_disagreements = NULL;
    int steps_succeeded
        = (cudaMalloc((void **)&device_window_counts, (size_t)voxels * sizeof(unsigned long long)) == cudaSuccess)
       && (cudaMalloc((void **)&device_key, key_cells * sizeof(unsigned int)) == cudaSuccess)
       && (cudaMalloc((void **)&device_extents,
                      ((size_t)request->bodies * BOX_HISTORY_EXTENT_FIELDS + 1u) * sizeof(unsigned int))
           == cudaSuccess)
       && (cudaMalloc((void **)&device_counts, (count_entries + 1u) * sizeof(unsigned int)) == cudaSuccess)
       && (cudaMalloc((void **)&device_disagreements, sizeof(unsigned long long)) == cudaSuccess)
       && (cudaMemset(device_disagreements, 0, sizeof(unsigned long long)) == cudaSuccess)
       && (cudaMemcpy(device_extents, request->extents,
                      (size_t)request->bodies * BOX_HISTORY_EXTENT_FIELDS * sizeof(unsigned int),
                      cudaMemcpyHostToDevice)
           == cudaSuccess);
    const unsigned int rows = shape.depth * shape.height;
    const unsigned int height_columns = shape.depth * shape.width;
    const unsigned int depth_columns = shape.height * shape.width;
    const unsigned int body_blocks = (request->bodies + BOX_HISTORY_THREADS - 1u) / BOX_HISTORY_THREADS;
    for (unsigned int window = 0u; steps_succeeded && (window < windows); window += 1u)
    {
        steps_succeeded = (cudaMemcpy(device_window_counts, &request->history->history[(size_t)window * voxels],
                                      (size_t)voxels * sizeof(unsigned long long), cudaMemcpyHostToDevice)
                           == cudaSuccess);
        for (unsigned int bit = 0u; steps_succeeded && (bit < ENGINE_HISTORY_BITS); bit += 1u)
        {
            steps_succeeded = (cudaMemset(device_key, 0, key_cells * sizeof(unsigned int)) == cudaSuccess);
            if (steps_succeeded)
            {
                box_history_row_kernel<<<(rows + BOX_HISTORY_THREADS - 1u) / BOX_HISTORY_THREADS, BOX_HISTORY_THREADS>>>(
                    device_window_counts, shape, bit, device_key);
                box_history_column_kernel<<<(height_columns + BOX_HISTORY_THREADS - 1u) / BOX_HISTORY_THREADS,
                                            BOX_HISTORY_THREADS>>>(shape, 1u, device_key);
                box_history_column_kernel<<<(depth_columns + BOX_HISTORY_THREADS - 1u) / BOX_HISTORY_THREADS,
                                            BOX_HISTORY_THREADS>>>(shape, 0u, device_key);
            }
            if (steps_succeeded && (request->bodies != 0u))
            {
                box_history_gather_kernel<<<body_blocks, BOX_HISTORY_THREADS>>>(
                    device_key, shape, device_extents, request->bodies, windows, window, bit, device_counts);
            }
            steps_succeeded = steps_succeeded && (cudaGetLastError() == cudaSuccess);
        }
        if (steps_succeeded && (request->bodies != 0u))
        {
            box_history_walk_kernel<<<body_blocks, BOX_HISTORY_THREADS>>>(device_window_counts, shape, device_extents,
                                                                          request->bodies, windows, window,
                                                                          device_counts, device_disagreements);
            steps_succeeded = (cudaGetLastError() == cudaSuccess);
        }
    }
    unsigned long long host_disagreements = 0ull;
    steps_succeeded = steps_succeeded && (cudaDeviceSynchronize() == cudaSuccess)
                   && (cudaMemcpy(&host_disagreements, device_disagreements, sizeof(unsigned long long),
                                  cudaMemcpyDeviceToHost)
                       == cudaSuccess)
                   && (cudaMemcpy(request->counts, device_counts, count_entries * sizeof(unsigned int),
                                  cudaMemcpyDeviceToHost)
                       == cudaSuccess);
    cudaFree(device_window_counts);
    cudaFree(device_key);
    cudaFree(device_extents);
    cudaFree(device_counts);
    cudaFree(device_disagreements);
    if (steps_succeeded)
    {
        *request->disagreements = host_disagreements;
        *request->microseconds = engine_clock_microseconds() - start_microseconds;
    }
    return steps_succeeded ? 0L : BOX_HISTORY_REFUSED;
}
