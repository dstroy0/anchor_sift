/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file birth_sweep.cu
 * @brief The threshold sweep on the device: admit, join, census, select, claim, emit, per cut.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Components are held as a union-find forest over voxel indices, joined with atomicMin until
 *       no join changes anything. Every component's root is its lowest voxel index. Admission only
 *       adds voxels, and the forest built at one cut carries into the next.
 * @note Births are compacted with the same two step scheme as the other engines: a count per chunk
 *       of voxels, a prefix sum on the host, then each chunk writes its births at its offset.
 */

#include "birth_sweep.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

/** @brief Threads per block. */
#define BIRTH_SWEEP_BLOCK 256u

/** @brief A voxel's parent while it lies below every cut so far. */
#define BIRTH_SWEEP_OUTSIDE 0xFFFFFFFFu

/** @brief Consecutive voxels one thread walks when counting and writing births. */
#define BIRTH_SWEEP_CHUNK 4096u

/** @brief The most births a call reports, the largest count a long holds on every target. */
#define BIRTH_SWEEP_ROOM_LIMIT 0x7FFFFFFFu

static_assert(sizeof(unsigned int) == 4u,
              "birth_sweep: unsigned int must be 32 bits, since BIRTH_SWEEP_OUTSIDE is its all-ones value");
static_assert(sizeof(unsigned long long) == 8u,
              "birth_sweep: unsigned long long must be 64 bits to hold a component's index sums");

/** @brief The shape the kernels read, passed by value. */
struct SweepGeometry
{
    unsigned int depth;  /**< Voxels along the slowest axis. */
    unsigned int height; /**< Voxels along the middle axis. */
    unsigned int width;  /**< Voxels along the fastest axis. */
    unsigned int voxels; /**< Voxels in the volume. */
    unsigned int chunks; /**< Chunks of BIRTH_SWEEP_CHUNK voxels covering it. */
};

/**
 * @brief Follows parent pointers to a voxel's root.
 *
 * @param[in] parent The forest [BORROWS].
 * @param[in] voxel  An admitted voxel.
 * @return           The root of its component.
 * @note Reads concurrently with other threads' atomicMin writes. A parent only ever falls to a
 *       lower index. The walk ends at a root, if not always the final one.
 */
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

/**
 * @brief Joins the components of two neighboring voxels, hanging the higher root under the lower.
 *
 * @param[in,out] parent    The forest [BORROWS].
 * @param[in]     voxel     An admitted voxel.
 * @param[in]     neighbour A face neighbor of it.
 * @param[out]    changed   Set to 1 where two components were joined [BORROWS].
 * @note Also shortens both voxels' paths to the roots found. A neighbor still outside is skipped.
 */
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

/**
 * @brief One thread per voxel: admit a voxel above the cut as its own component.
 *
 * @param[in,out] parent   The forest [BORROWS].
 * @param[in]     field    The field [BORROWS].
 * @param[in]     cut      The threshold, compared against the voxel's value widened to double.
 * @param[in]     geometry The shape.
 */
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

/**
 * @brief One thread per voxel: join an admitted voxel with its forward face neighbors.
 *
 * @param[in,out] parent   The forest [BORROWS].
 * @param[in]     geometry The shape.
 * @param[out]    changed  Set to 1 where any join changed the forest [BORROWS].
 * @note Only the +1 neighbor on each axis. The -1 neighbor's own thread makes that join, and every
 *       face pair is joined once.
 */
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

/**
 * @brief One thread per voxel: point every admitted voxel straight at its root.
 *
 * @param[in,out] parent   The forest [BORROWS].
 * @param[in]     geometry The shape.
 */
__global__ static void compress_kernel(unsigned int *parent, SweepGeometry geometry)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (parent[voxel] == BIRTH_SWEEP_OUTSIDE))
    {
        return;
    }
    atomicMin(&parent[voxel], device_root(parent, voxel));
}

/**
 * @brief One thread per voxel: zero the census slots of every admitted voxel.
 *
 * @note Every root is an admitted voxel. This zeroes every slot the census will add to.
 */
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

/**
 * @brief One thread per voxel: add an admitted voxel to its root's size, index sums and touch flag.
 *
 * @param[in]  parent      The compressed forest [BORROWS].
 * @param[in]  claimed     1 at every voxel an earlier birth claimed [BORROWS].
 * @param[in]  geometry    The shape.
 * @param[out] sizes       Voxels per root [BORROWS].
 * @param[out] slice_sums  Sum of slice indices per root [BORROWS].
 * @param[out] row_sums    Sum of row indices per root [BORROWS].
 * @param[out] column_sums Sum of column indices per root [BORROWS].
 * @param[out] touched     1 at a root whose component holds a claimed voxel [BORROWS].
 * @note The sums are integers, and a centroid is formed from them only on the host at the end.
 */
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

/**
 * @brief One thread per chunk: mark the roots born at this cut and count them.
 *
 * @param[in]  parent       The compressed forest [BORROWS].
 * @param[in]  sizes        Voxels per root [BORROWS].
 * @param[in]  touched      1 at a root whose component holds a claimed voxel [BORROWS].
 * @param[in]  geometry     The shape.
 * @param[in]  least_voxels Smallest size born.
 * @param[in]  most_voxels  Largest size born.
 * @param[out] born         1 at every root born at this cut, 0 elsewhere [BORROWS].
 * @param[out] chunk_births Births in each chunk [BORROWS].
 */
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
        // A root in range with no claimed voxel. sizes and touched are read only at a root, the
        // one place clear_kernel and census_kernel have set them this cut.
        const int is_born = (parent[voxel] == voxel) && (sizes[voxel] >= least_voxels)
                         && (sizes[voxel] <= most_voxels) && (touched[voxel] == 0u);
        born[voxel] = is_born ? 1u : 0u;
        count += is_born ? 1u : 0u;
    }
    chunk_births[chunk] = count;
}

/**
 * @brief One thread per voxel: claim every voxel of a component born at this cut.
 *
 * @param[in]  parent   The compressed forest [BORROWS].
 * @param[in]  born     1 at every root born at this cut [BORROWS].
 * @param[in]  geometry The shape.
 * @param[out] claimed  Set to 1 at every voxel of a born component [BORROWS].
 */
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

/**
 * @brief One thread per chunk: write each born root's size and index sums at its chunk's offset.
 *
 * @note Births come out in ascending root index, chunk by chunk.
 */
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

/**
 * @brief Every buffer one sweep uses, device and host, and how many births are staged.
 *
 * @note The staged arrays collect births across every cut and are copied to the caller only when
 *       the whole sweep succeeds.
 */
struct SweepContext
{
    SweepGeometry geometry;                /**< The shape. */
    const BirthSweepRequest *request;      /**< The caller's request [BORROWS]. */
    float *field;                          /**< Device copy of the field. */
    unsigned int *parent;                  /**< Device union-find forest. */
    unsigned char *claimed;                /**< Device claimed flag per voxel. */
    unsigned char *born;                   /**< Device born flag per voxel, this cut. */
    unsigned int *sizes;                   /**< Device voxels per root. */
    unsigned long long *slice_sums;        /**< Device slice index sum per root. */
    unsigned long long *row_sums;          /**< Device row index sum per root. */
    unsigned long long *column_sums;       /**< Device column index sum per root. */
    unsigned int *touched;                 /**< Device touched flag per root. */
    unsigned int *changed;                 /**< Device flag: a join changed the forest. */
    unsigned int *chunk_births;            /**< Device births per chunk. */
    unsigned int *offsets;                 /**< Device write offset per chunk. */
    unsigned int *emitted_sizes;           /**< Device sizes of this cut's births. */
    unsigned long long *emitted_slices;    /**< Device slice sums of this cut's births. */
    unsigned long long *emitted_rows;      /**< Device row sums of this cut's births. */
    unsigned long long *emitted_columns;   /**< Device column sums of this cut's births. */
    unsigned int *host_chunk_births;       /**< Host births per chunk, then offsets. */
    unsigned int *host_emitted_sizes;      /**< Host sizes of this cut's births. */
    unsigned long long *host_emitted_slices; /**< Host slice sums of this cut's births. */
    unsigned long long *host_emitted_rows; /**< Host row sums of this cut's births. */
    unsigned long long *host_emitted_columns; /**< Host column sums of this cut's births. */
    double *staged_centroids;              /**< Every birth's centroid so far. */
    unsigned int *staged_births;           /**< Every birth's cut index so far. */
    unsigned int written;                  /**< Births staged so far. */
};

/**
 * @brief Whether the last launch was accepted and ran to completion.
 *
 * @return 1 where neither the launch nor the kernel reported an error, 0 otherwise.
 */
static int sweep_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

/**
 * @brief Blocks covering a count of items.
 *
 * @param[in] items Items, one per thread.
 * @return          Blocks of BIRTH_SWEEP_BLOCK threads.
 */
static unsigned int sweep_blocks(unsigned int items)
{
    return (items + BIRTH_SWEEP_BLOCK - 1u) / BIRTH_SWEEP_BLOCK;
}

/**
 * @brief Allocates every buffer, marks every voxel outside and uploads the field.
 *
 * @param[in,out] context The sweep, with its geometry and request set [BORROWS].
 * @return                1 where every step succeeded, 0 otherwise. sweep_release frees whatever
 *                        was allocated either way.
 * @note The emit buffers take `room` + 1 entries. A room of 0 still allocates. One cut's births
 *       never exceed `room`, since a cut that would pass it refuses before emitting.
 */
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

    // Every byte 0xFF makes every parent BIRTH_SWEEP_OUTSIDE.
    ok = ok && (cudaMemset(context->parent, 0xFF, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(context->claimed, 0, voxels) == cudaSuccess);
    ok = ok && (cudaMemcpy(context->field, context->request->field, voxels * sizeof(float),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    return ok;
}

/**
 * @brief Frees every buffer of a sweep.
 *
 * @param[in,out] context The sweep [BORROWS].
 * @note cudaFree and free both accept a null pointer. A partly allocated sweep frees cleanly.
 */
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

/**
 * @brief Admits the voxels above a cut and joins the forest until it stops changing.
 *
 * @param[in,out] context The sweep [BORROWS].
 * @param[in]     cut     The threshold.
 * @return                1 where every step succeeded, 0 otherwise.
 * @note The join repeats until a pass changes nothing, each pass one launch and one copy of the
 *       flag back to the host. No bound on the number of passes is set or checked.
 */
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

/**
 * @brief Finds the births at the current cut, claims them and stages their centroids.
 *
 * @param[in,out] context The sweep, labeled at this cut [BORROWS].
 * @param[in]     step    The cut's index, recorded with each birth.
 * @return                Births at this cut, BIRTH_SWEEP_ROOM_EXCEEDED where the staged births
 *                        would pass `room`, or BIRTH_SWEEP_REFUSED where a device step failed.
 * @note The centroid is each integer index sum divided by the size, in double, per axis.
 */
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

    // An exclusive prefix sum turns each chunk's birth count into the index of its first birth.
    unsigned long long total = 0ull;
    for (unsigned int chunk = 0u; chunk < context->geometry.chunks; chunk += 1u)
    {
        const unsigned int count = context->host_chunk_births[chunk];

        // total is at most one birth per voxel, below 2^32, and fits the unsigned int.
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

    // births is at most `room`, below 2^31, and fits a long on every target.
    return (long)births;
}

extern "C" int birth_sweep_device_available(void)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }

    // cudaFree(NULL) creates the context and returns an error where the device cannot hold one.
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

    // Every voxel index stays below BIRTH_SWEEP_OUTSIDE, which marks a voxel outside, and a chunk's
    // end stays below 2^32.
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

    // Bounded below 2^32 just above. The count fits the unsigned int.
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
