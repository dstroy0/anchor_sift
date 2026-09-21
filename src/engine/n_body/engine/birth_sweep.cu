#include "birth_sweep.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define BIRTH_SWEEP_BLOCK 256u

#define BIRTH_SWEEP_OUTSIDE 0xFFFFFFFFu

#define BIRTH_SWEEP_CHUNK 4096u

#define BIRTH_SWEEP_ROOM_LIMIT 0x7FFFFFFFu

static_assert(sizeof(unsigned int) == 4u,
              "birth_sweep: unsigned int must be 32 bits, since BIRTH_SWEEP_OUTSIDE is its all-ones value");
static_assert(sizeof(unsigned long long) == 8u,
              "birth_sweep: unsigned long long must be 64 bits to hold a component's index sums");

struct SweepGeometry
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int chunks;
};

__device__ static unsigned int device_root(const unsigned int *parent, unsigned int voxel)
{
    unsigned int walk = voxel;
    unsigned int above = parent[walk];
    while (above != walk)
    {
        walk = above;
        above = parent[walk];
    }
    return walk;
}

__device__ static void device_join(unsigned int *parent, unsigned int voxel, unsigned int neighbour,
                                   unsigned int *changed)
{
    if (parent[neighbour] == BIRTH_SWEEP_OUTSIDE)
    {
        return;
    }
    const unsigned int voxel_root = device_root(parent, voxel);
    const unsigned int neighbour_root = device_root(parent, neighbour);

    atomicMin(&parent[voxel], voxel_root);
    atomicMin(&parent[neighbour], neighbour_root);
    if (voxel_root == neighbour_root)
    {
        return;
    }

    const unsigned int lower = (voxel_root < neighbour_root) ? voxel_root : neighbour_root;
    const unsigned int higher = (voxel_root < neighbour_root) ? neighbour_root : voxel_root;
    atomicMin(&parent[higher], lower);
    atomicMax(changed, 1u);
}

__global__ static void admit_kernel(unsigned int *parent, const float *field, double cut,
                                    SweepGeometry geometry)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }

    if ((parent[voxel] == BIRTH_SWEEP_OUTSIDE) && ((double)field[voxel] > cut))
    {
        parent[voxel] = voxel;
    }
}

__global__ static void join_kernel(unsigned int *parent, SweepGeometry geometry,
                                   unsigned int *changed)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (parent[voxel] == BIRTH_SWEEP_OUTSIDE))
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int column = voxel % geometry.width;
    const unsigned int row = (voxel / geometry.width) % geometry.height;
    const unsigned int slice = voxel / plane;

    if ((column + 1u) < geometry.width)
    {
        device_join(parent, voxel, voxel + 1u, changed);
    }
    if ((row + 1u) < geometry.height)
    {
        device_join(parent, voxel, voxel + geometry.width, changed);
    }
    if ((slice + 1u) < geometry.depth)
    {
        device_join(parent, voxel, voxel + plane, changed);
    }
}

__global__ static void compress_kernel(unsigned int *parent, SweepGeometry geometry)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (parent[voxel] == BIRTH_SWEEP_OUTSIDE))
    {
        return;
    }
    atomicMin(&parent[voxel], device_root(parent, voxel));
}

__global__ static void clear_kernel(const unsigned int *parent, SweepGeometry geometry,
                                    unsigned int *sizes, unsigned long long *slice_sums,
                                    unsigned long long *row_sums,
                                    unsigned long long *column_sums, unsigned int *touched)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (parent[voxel] == BIRTH_SWEEP_OUTSIDE))
    {
        return;
    }
    sizes[voxel] = 0u;
    slice_sums[voxel] = 0ull;
    row_sums[voxel] = 0ull;
    column_sums[voxel] = 0ull;
    touched[voxel] = 0u;
}

__global__ static void census_kernel(const unsigned int *parent, const unsigned char *claimed,
                                     SweepGeometry geometry, unsigned int *sizes,
                                     unsigned long long *slice_sums,
                                     unsigned long long *row_sums,
                                     unsigned long long *column_sums, unsigned int *touched)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int root = parent[voxel];
    if (root == BIRTH_SWEEP_OUTSIDE)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    atomicAdd(&sizes[root], 1u);

    atomicAdd(&slice_sums[root], (unsigned long long)(voxel / plane));
    atomicAdd(&row_sums[root], (unsigned long long)((voxel / geometry.width) % geometry.height));
    atomicAdd(&column_sums[root], (unsigned long long)(voxel % geometry.width));
    if (claimed[voxel] != 0u)
    {
        atomicMax(&touched[root], 1u);
    }
}

__global__ static void select_kernel(const unsigned int *parent, const unsigned int *sizes,
                                     const unsigned int *touched, SweepGeometry geometry,
                                     unsigned int least_voxels, unsigned int most_voxels,
                                     unsigned char *born, unsigned int *chunk_births)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int first = chunk * BIRTH_SWEEP_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < BIRTH_SWEEP_CHUNK)
                            ? geometry.voxels
                            : (first + BIRTH_SWEEP_CHUNK);
    unsigned int count = 0u;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        const int is_born = (parent[voxel] == voxel) && (sizes[voxel] >= least_voxels)
                         && (sizes[voxel] <= most_voxels) && (touched[voxel] == 0u);
        born[voxel] = is_born ? 1u : 0u;
        count += is_born ? 1u : 0u;
    }
    chunk_births[chunk] = count;
}

__global__ static void claim_kernel(const unsigned int *parent, const unsigned char *born,
                                    SweepGeometry geometry, unsigned char *claimed)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int root = parent[voxel];
    if ((root != BIRTH_SWEEP_OUTSIDE) && (born[root] != 0u))
    {
        claimed[voxel] = 1u;
    }
}

__global__ static void emit_kernel(const unsigned char *born, const unsigned int *sizes,
                                   const unsigned long long *slice_sums,
                                   const unsigned long long *row_sums,
                                   const unsigned long long *column_sums,
                                   const unsigned int *offsets, SweepGeometry geometry,
                                   unsigned int *emitted_sizes, unsigned long long *emitted_slices,
                                   unsigned long long *emitted_rows,
                                   unsigned long long *emitted_columns)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int first = chunk * BIRTH_SWEEP_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < BIRTH_SWEEP_CHUNK)
                            ? geometry.voxels
                            : (first + BIRTH_SWEEP_CHUNK);
    unsigned int slot = offsets[chunk];
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if (born[voxel] != 0u)
        {
            emitted_sizes[slot] = sizes[voxel];
            emitted_slices[slot] = slice_sums[voxel];
            emitted_rows[slot] = row_sums[voxel];
            emitted_columns[slot] = column_sums[voxel];
            slot += 1u;
        }
    }
}

struct SweepContext
{
    SweepGeometry geometry;
    const BirthSweepRequest *request;
    float *field;
    unsigned int *parent;
    unsigned char *claimed;
    unsigned char *born;
    unsigned int *sizes;
    unsigned long long *slice_sums;
    unsigned long long *row_sums;
    unsigned long long *column_sums;
    unsigned int *touched;
    unsigned int *changed;
    unsigned int *chunk_births;
    unsigned int *offsets;
    unsigned int *emitted_sizes;
    unsigned long long *emitted_slices;
    unsigned long long *emitted_rows;
    unsigned long long *emitted_columns;
    unsigned int *host_chunk_births;
    unsigned int *host_emitted_sizes;
    unsigned long long *host_emitted_slices;
    unsigned long long *host_emitted_rows;
    unsigned long long *host_emitted_columns;
    double *staged_centroids;
    unsigned int *staged_births;
    unsigned int written;
};

static int sweep_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

static unsigned int sweep_blocks(unsigned int items)
{
    return (items + BIRTH_SWEEP_BLOCK - 1u) / BIRTH_SWEEP_BLOCK;
}

static int sweep_allocate(SweepContext *context)
{

    const size_t voxels = (size_t)context->geometry.voxels;
    const size_t chunks = (size_t)context->geometry.chunks;
    const size_t slots = (size_t)context->request->room + 1u;
    int ok = 1;

    ok = ok && (cudaMalloc((void **)&context->field, voxels * sizeof(float)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->parent, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->claimed, voxels) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->born, voxels) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->sizes, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->slice_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->row_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->column_sums,
                           voxels * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->touched, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->changed, sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->chunk_births,
                           chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->offsets, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->emitted_sizes,
                           slots * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->emitted_slices,
                           slots * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->emitted_rows,
                           slots * sizeof(unsigned long long)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&context->emitted_columns,
                           slots * sizeof(unsigned long long)) == cudaSuccess);

    context->host_chunk_births = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    context->host_emitted_sizes = (unsigned int *)malloc(slots * sizeof(unsigned int));
    context->host_emitted_slices = (unsigned long long *)malloc(slots * sizeof(unsigned long long));
    context->host_emitted_rows = (unsigned long long *)malloc(slots * sizeof(unsigned long long));
    context->host_emitted_columns = (unsigned long long *)malloc(slots * sizeof(unsigned long long));
    context->staged_centroids = (double *)malloc(slots * 3u * sizeof(double));
    context->staged_births = (unsigned int *)malloc(slots * sizeof(unsigned int));
    ok = ok && (context->host_chunk_births != NULL) && (context->host_emitted_sizes != NULL)
      && (context->host_emitted_slices != NULL) && (context->host_emitted_rows != NULL)
      && (context->host_emitted_columns != NULL) && (context->staged_centroids != NULL)
      && (context->staged_births != NULL);

    ok = ok && (cudaMemset(context->parent, 0xFF, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(context->claimed, 0, voxels) == cudaSuccess);
    ok = ok && (cudaMemcpy(context->field, context->request->field, voxels * sizeof(float),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    return ok;
}

static void sweep_release(SweepContext *context)
{
    cudaFree(context->field);
    cudaFree(context->parent);
    cudaFree(context->claimed);
    cudaFree(context->born);
    cudaFree(context->sizes);
    cudaFree(context->slice_sums);
    cudaFree(context->row_sums);
    cudaFree(context->column_sums);
    cudaFree(context->touched);
    cudaFree(context->changed);
    cudaFree(context->chunk_births);
    cudaFree(context->offsets);
    cudaFree(context->emitted_sizes);
    cudaFree(context->emitted_slices);
    cudaFree(context->emitted_rows);
    cudaFree(context->emitted_columns);
    free(context->host_chunk_births);
    free(context->host_emitted_sizes);
    free(context->host_emitted_slices);
    free(context->host_emitted_rows);
    free(context->host_emitted_columns);
    free(context->staged_centroids);
    free(context->staged_births);
}

static int sweep_label(SweepContext *context, double cut)
{
    const unsigned int blocks = sweep_blocks(context->geometry.voxels);
    admit_kernel<<<blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->field, cut,
                                                context->geometry);
    int ok = sweep_launched();

    unsigned int changed = 1u;
    while ((ok != 0) && (changed != 0u))
    {
        ok = ok && (cudaMemset(context->changed, 0, sizeof(unsigned int)) == cudaSuccess);
        join_kernel<<<blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->geometry,
                                                   context->changed);
        ok = ok && sweep_launched();
        ok = ok && (cudaMemcpy(&changed, context->changed, sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }

    if (ok != 0)
    {
        compress_kernel<<<blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->geometry);
        ok = sweep_launched();
    }
    return ok;
}

static long sweep_births(SweepContext *context, unsigned int step)
{

    const BirthSweepRequest *const request = context->request;
    const unsigned int voxel_blocks = sweep_blocks(context->geometry.voxels);
    const unsigned int chunk_blocks = sweep_blocks(context->geometry.chunks);

    clear_kernel<<<voxel_blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->geometry,
                                                      context->sizes, context->slice_sums,
                                                      context->row_sums, context->column_sums,
                                                      context->touched);
    int ok = sweep_launched();
    if (ok != 0)
    {
        census_kernel<<<voxel_blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->claimed,
                                                           context->geometry, context->sizes,
                                                           context->slice_sums, context->row_sums,
                                                           context->column_sums, context->touched);
        ok = sweep_launched();
    }
    if (ok != 0)
    {
        select_kernel<<<chunk_blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->sizes,
                                                           context->touched, context->geometry,
                                                           request->least_voxels,
                                                           request->most_voxels, context->born,
                                                           context->chunk_births);
        ok = sweep_launched();
    }
    ok = ok && (cudaMemcpy(context->host_chunk_births, context->chunk_births,
                           (size_t)context->geometry.chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    if (ok == 0)
    {
        return BIRTH_SWEEP_REFUSED;
    }

    unsigned long long total = 0ull;
    for (unsigned int chunk = 0u; chunk < context->geometry.chunks; chunk += 1u)
    {
        const unsigned int count = context->host_chunk_births[chunk];

        context->host_chunk_births[chunk] = (unsigned int)total;
        total += (unsigned long long)count;
    }
    if (total == 0ull)
    {
        return 0L;
    }
    if (((unsigned long long)context->written + total) > (unsigned long long)request->room)
    {
        return BIRTH_SWEEP_ROOM_EXCEEDED;
    }

    const unsigned int births = (unsigned int)total;

    claim_kernel<<<voxel_blocks, BIRTH_SWEEP_BLOCK>>>(context->parent, context->born,
                                                      context->geometry, context->claimed);
    ok = sweep_launched();
    ok = ok && (cudaMemcpy(context->offsets, context->host_chunk_births,
                           (size_t)context->geometry.chunks * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        emit_kernel<<<chunk_blocks, BIRTH_SWEEP_BLOCK>>>(context->born, context->sizes,
                                                         context->slice_sums, context->row_sums,
                                                         context->column_sums, context->offsets,
                                                         context->geometry, context->emitted_sizes,
                                                         context->emitted_slices,
                                                         context->emitted_rows,
                                                         context->emitted_columns);
        ok = sweep_launched();
    }
    ok = ok && (cudaMemcpy(context->host_emitted_sizes, context->emitted_sizes,
                           (size_t)births * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(context->host_emitted_slices, context->emitted_slices,
                           (size_t)births * sizeof(unsigned long long), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(context->host_emitted_rows, context->emitted_rows,
                           (size_t)births * sizeof(unsigned long long), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    ok = ok && (cudaMemcpy(context->host_emitted_columns, context->emitted_columns,
                           (size_t)births * sizeof(unsigned long long), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    if (ok == 0)
    {
        return BIRTH_SWEEP_REFUSED;
    }

    for (unsigned int birth = 0u; birth < births; birth += 1u)
    {
        const size_t slot = (size_t)context->written + (size_t)birth;

        const double size = (double)context->host_emitted_sizes[birth];
        context->staged_centroids[slot * 3u] = (double)context->host_emitted_slices[birth] / size;
        context->staged_centroids[(slot * 3u) + 1u] = (double)context->host_emitted_rows[birth] / size;
        context->staged_centroids[(slot * 3u) + 2u] =
            (double)context->host_emitted_columns[birth] / size;
        context->staged_births[slot] = step;
    }
    context->written += births;

    return (long)births;
}

extern "C" int birth_sweep_device_available(void)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }

    return (cudaFree(NULL) == cudaSuccess) ? 1 : 0;
}

extern "C" long birth_sweep_run(const BirthSweepRequest *args)
{
    if ((args == NULL) || (args->field == NULL) || ((args->cuts == NULL) && (args->cut_count != 0u))
     || (args->depth == 0u) || (args->height == 0u) || (args->width == 0u)
     || ((args->room != 0u) && ((args->centroids == NULL) || (args->births == NULL)))
     || (args->room > BIRTH_SWEEP_ROOM_LIMIT))
    {
        return BIRTH_SWEEP_REFUSED;
    }

    const unsigned long long plane = (unsigned long long)args->height
                                   * (unsigned long long)args->width;
    if (plane > (unsigned long long)BIRTH_SWEEP_OUTSIDE)
    {
        return BIRTH_SWEEP_REFUSED;
    }
    const unsigned long long voxels = plane * (unsigned long long)args->depth;

    if ((voxels > (unsigned long long)(BIRTH_SWEEP_OUTSIDE - BIRTH_SWEEP_CHUNK))
     || (birth_sweep_device_available() == 0))
    {
        return BIRTH_SWEEP_REFUSED;
    }

    SweepContext context;
    memset(&context, 0, sizeof(context));
    context.request = args;
    context.geometry.depth = args->depth;
    context.geometry.height = args->height;
    context.geometry.width = args->width;

    context.geometry.voxels = (unsigned int)voxels;
    context.geometry.chunks = (context.geometry.voxels + BIRTH_SWEEP_CHUNK - 1u) / BIRTH_SWEEP_CHUNK;

    long answer = BIRTH_SWEEP_REFUSED;
    if (sweep_allocate(&context) != 0)
    {
        answer = 0L;
        for (unsigned int step = 0u; step < args->cut_count; step += 1u)
        {
            if (sweep_label(&context, args->cuts[step]) == 0)
            {
                answer = BIRTH_SWEEP_REFUSED;
                break;
            }
            const long births = sweep_births(&context, step);
            if (births < 0L)
            {
                answer = births;
                break;
            }
        }
    }

    if (answer == 0L)
    {

        const size_t written = (size_t)context.written;
        if (written != 0u)
        {
            memcpy(args->centroids, context.staged_centroids, written * 3u * sizeof(double));
            memcpy(args->births, context.staged_births, written * sizeof(unsigned int));
        }

        answer = (long)context.written;
    }
    sweep_release(&context);
    return answer;
}
