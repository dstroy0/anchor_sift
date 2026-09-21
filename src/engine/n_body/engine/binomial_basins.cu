#include "binomial_basins.h"
#include "radix_keys.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if !defined(BINOMIAL_BASINS_PROFILE)
#define BINOMIAL_BASINS_PROFILE 0
#endif

#if !defined(BINOMIAL_BASINS_TRANSFORM)
#define BINOMIAL_BASINS_TRANSFORM 1
#endif

#if BINOMIAL_BASINS_TRANSFORM
#include "binomial_transform.h"
#else
static inline int binomial_transform_admits(const unsigned int *extents, const unsigned int *smooth_orders,
                                            const unsigned int *background_orders)
{
    (void)extents;
    (void)smooth_orders;
    (void)background_orders;
    return 0;
}

static inline int binomial_transform_residual(const unsigned short *volume, const unsigned int *extents,
                                              const unsigned int *smooth_orders,
                                              const unsigned int *background_orders, unsigned int *residual)
{
    (void)volume;
    (void)extents;
    (void)smooth_orders;
    (void)background_orders;
    (void)residual;
    return 0;
}
#endif

static void profile_mark(const char *stage)
{
    if (BINOMIAL_BASINS_PROFILE == 0)
    {
        return;
    }
    static unsigned long long last = 0ULL;

    (void)cudaDeviceSynchronize();
    struct timespec now;
    timespec_get(&now, TIME_UTC);

    const unsigned long long micro = (unsigned long long)now.tv_sec * 1000000ULL
                                   + (unsigned long long)now.tv_nsec / 1000ULL;
    if (stage != NULL)
    {
        fprintf(stderr, "    %-22s %8llu us\n", stage, micro - last);
    }
    last = micro;
}

#define BINOMIAL_BASINS_BLOCK 256u

#define BINOMIAL_BASINS_CHUNK 256u

static_assert(sizeof(unsigned int) == 4u, "binomial_basins: unsigned int must be 32 bits, a limb");
static_assert(sizeof(unsigned long long) == 8u,
              "binomial_basins: unsigned long long must be 64 bits, a limb product and its carry");
static_assert(BINOMIAL_BASINS_PASS_ORDER <= 32u,
              "binomial_basins: a pass's weights must sum to at most 2^32, or its limb sum can wrap");

struct DeviceGeometry
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int chunks;
};

struct DeviceOrders
{
    unsigned int order[3];
};

#define BINOMIAL_BASINS_ROW_WIDTH (BINOMIAL_BASINS_PASS_ORDER + 1u)

__device__ static unsigned int device_reflect(long long position, long long length)
{

    if ((position >= 0ll) && (position < length))
    {

        return (unsigned int)position;
    }
    if ((position < 0ll) && (position >= -length))
    {

        return (unsigned int)(-1ll - position);
    }
    if ((position >= length) && (position < (2ll * length)))
    {

        return (unsigned int)((2ll * length) - 1ll - position);
    }
    const long long period = 2ll * length;
    long long folded = position % period;
    if (folded < 0ll)
    {
        folded += period;
    }
    if (folded >= length)
    {
        folded = period - 1ll - folded;
    }

    return (unsigned int)folded;
}

__device__ static int device_compare(const unsigned int *left, const unsigned int *right)
{
    const unsigned int top = BINOMIAL_BASINS_LIMBS - 1u;
    const unsigned int left_top = left[top] ^ 0x80000000u;
    const unsigned int right_top = right[top] ^ 0x80000000u;
    if (left_top != right_top)
    {
        return (left_top < right_top) ? -1 : 1;
    }
    for (unsigned int limb = top; limb > 0u; limb -= 1u)
    {
        if (left[limb - 1u] != right[limb - 1u])
        {
            return (left[limb - 1u] < right[limb - 1u]) ? -1 : 1;
        }
    }
    return 0;
}

__device__ static int device_positive(const unsigned int *value)
{
    if ((value[BINOMIAL_BASINS_LIMBS - 1u] & 0x80000000u) != 0u)
    {
        return 0;
    }
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        if (value[limb] != 0u)
        {
            return 1;
        }
    }
    return 0;
}

__global__ static void load_kernel(const unsigned short *volume, unsigned int voxels, unsigned int *limbs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }

    limbs[voxel * BINOMIAL_BASINS_LIMBS] = (unsigned int)volume[voxel];
}

__global__ static void pass_kernel(const unsigned int *source, const unsigned int *weights,
                                   unsigned int order, unsigned int axis, unsigned int limbs_in,
                                   unsigned int limbs_out, DeviceGeometry geometry, unsigned int *destination)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int column = voxel % geometry.width;
    const unsigned int row = (voxel / geometry.width) % geometry.height;
    const unsigned int slice = voxel / plane;
    unsigned int along = column;
    unsigned int length = geometry.width;
    unsigned int stride = 1u;
    if (axis == 0u)
    {
        along = slice;
        length = geometry.depth;
        stride = plane;
    }
    else if (axis == 1u)
    {
        along = row;
        length = geometry.height;
        stride = geometry.width;
    }
    const unsigned int line_start = voxel - (along * stride);

    unsigned long long accumulator[BINOMIAL_BASINS_LIMBS];
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        accumulator[limb] = 0ull;
    }
    for (unsigned int tap = 0u; tap <= order; tap += 1u)
    {

        const long long position = (long long)along + (long long)tap - (long long)(order / 2u);
        const unsigned int read = line_start + (device_reflect(position, (long long)length) * stride);
        for (unsigned int limb = 0u; limb < limbs_in; limb += 1u)
        {

            accumulator[limb] += (unsigned long long)weights[tap]
                               * (unsigned long long)source[(read * BINOMIAL_BASINS_LIMBS) + limb];
        }
    }
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs_out; limb += 1u)
    {
        const unsigned long long total = accumulator[limb] + carry;

        destination[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__global__ static void fused_kernel(const unsigned int *source, const unsigned int *weights, DeviceOrders orders,
                                    unsigned int limbs_in, unsigned int limbs_out, DeviceGeometry geometry,
                                    unsigned int *destination)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const long long column = (long long)(voxel % geometry.width);
    const long long row = (long long)((voxel / geometry.width) % geometry.height);
    const long long slice = (long long)(voxel / plane);
    const unsigned int *const row_z = &weights[orders.order[0] * BINOMIAL_BASINS_ROW_WIDTH];
    const unsigned int *const row_y = &weights[orders.order[1] * BINOMIAL_BASINS_ROW_WIDTH];
    const unsigned int *const row_x = &weights[orders.order[2] * BINOMIAL_BASINS_ROW_WIDTH];
    unsigned long long accumulator[BINOMIAL_BASINS_LIMBS];
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        accumulator[limb] = 0ull;
    }
    for (unsigned int tap_z = 0u; tap_z <= orders.order[0]; tap_z += 1u)
    {

        const unsigned int read_z = device_reflect(slice + (long long)tap_z - (long long)(orders.order[0] / 2u),
                                                   (long long)geometry.depth);
        for (unsigned int tap_y = 0u; tap_y <= orders.order[1]; tap_y += 1u)
        {
            const unsigned int read_y = device_reflect(row + (long long)tap_y - (long long)(orders.order[1] / 2u),
                                                       (long long)geometry.height);

            const unsigned long long weight_zy = (unsigned long long)row_z[tap_z] * (unsigned long long)row_y[tap_y];
            const unsigned int line = ((read_z * geometry.height) + read_y) * geometry.width;
            for (unsigned int tap_x = 0u; tap_x <= orders.order[2]; tap_x += 1u)
            {
                const unsigned int read_x = device_reflect(column + (long long)tap_x - (long long)(orders.order[2] / 2u),
                                                           (long long)geometry.width);
                const unsigned long long weight = weight_zy * (unsigned long long)row_x[tap_x];
                const unsigned int read = line + read_x;
                for (unsigned int limb = 0u; limb < limbs_in; limb += 1u)
                {

                    accumulator[limb] += weight * (unsigned long long)source[(read * BINOMIAL_BASINS_LIMBS) + limb];
                }
            }
        }
    }
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs_out; limb += 1u)
    {
        const unsigned long long total = accumulator[limb] + carry;

        destination[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__global__ static void residual_kernel(const unsigned int *smoothed, const unsigned int *background,
                                       unsigned int whole, unsigned int part, unsigned int voxels,
                                       unsigned int *residual)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int *const scaled = &smoothed[voxel * BINOMIAL_BASINS_LIMBS];
    const unsigned int *const subtracted = &background[voxel * BINOMIAL_BASINS_LIMBS];
    unsigned long long borrow = 0ull;
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        unsigned int shifted = 0u;
        if (limb >= whole)
        {
            shifted = scaled[limb - whole] << part;
            if ((part != 0u) && (limb > whole))
            {
                shifted |= scaled[limb - whole - 1u] >> (32u - part);
            }
        }

        const unsigned long long difference = (1ull << 32u) + (unsigned long long)shifted
                                            - (unsigned long long)subtracted[limb] - borrow;
        residual[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
        borrow = (difference < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__global__ static void ascend_kernel(const unsigned int *residual, DeviceGeometry geometry,
                                     unsigned int *successor, unsigned char *positive)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= geometry.voxels)
    {
        return;
    }
    positive[voxel] = (unsigned char)device_positive(&residual[voxel * BINOMIAL_BASINS_LIMBS]);
    const unsigned int plane = geometry.height * geometry.width;

    const long long column = (long long)(voxel % geometry.width);
    const long long row = (long long)((voxel / geometry.width) % geometry.height);
    const long long slice = (long long)(voxel / plane);
    unsigned int best = voxel;
    for (long long step_slice = -1ll; step_slice <= 1ll; step_slice += 1ll)
    {
        for (long long step_row = -1ll; step_row <= 1ll; step_row += 1ll)
        {
            for (long long step_column = -1ll; step_column <= 1ll; step_column += 1ll)
            {
                const long long at_slice = slice + step_slice;
                const long long at_row = row + step_row;
                const long long at_column = column + step_column;
                if ((at_slice < 0ll) || (at_slice >= (long long)geometry.depth) || (at_row < 0ll)
                 || (at_row >= (long long)geometry.height) || (at_column < 0ll)
                 || (at_column >= (long long)geometry.width))
                {
                    continue;
                }

                const unsigned int neighbour = ((unsigned int)at_slice * plane)
                                             + ((unsigned int)at_row * geometry.width)
                                             + (unsigned int)at_column;
                const int order = device_compare(&residual[neighbour * BINOMIAL_BASINS_LIMBS],
                                                 &residual[best * BINOMIAL_BASINS_LIMBS]);
                if ((order > 0) || ((order == 0) && (neighbour < best)))
                {
                    best = neighbour;
                }
            }
        }
    }
    successor[voxel] = best;
}

__global__ static void jump_kernel(const unsigned int *source, unsigned int voxels,
                                   unsigned int *destination, unsigned int *changed)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
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

__global__ static void census_kernel(const unsigned char *positive, const unsigned int *peak,
                                     const unsigned int *slot_at_peak, DeviceGeometry geometry,
                                     unsigned int *out_sizes, unsigned long long *out_sums)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (positive[voxel] == 0u))
    {
        return;
    }
    const unsigned int slot = slot_at_peak[peak[voxel]];
    const unsigned int plane = geometry.height * geometry.width;
    atomicAdd(&out_sizes[slot], 1u);

    atomicAdd(&out_sums[slot * 3u], (unsigned long long)(voxel / plane));
    atomicAdd(&out_sums[(slot * 3u) + 1u], (unsigned long long)((voxel / geometry.width) % geometry.height));
    atomicAdd(&out_sums[(slot * 3u) + 2u], (unsigned long long)(voxel % geometry.width));
}

__global__ static void chunk_kernel(const unsigned int *residual, const unsigned char *positive,
                                    const unsigned int *peak, unsigned int want_faces,
                                    const unsigned int *peak_offsets, const unsigned int *face_offsets,
                                    const unsigned int *joined_offsets, DeviceGeometry geometry,
                                    unsigned int *chunk_peaks, unsigned int *chunk_faces, unsigned int *chunk_joined,
                                    unsigned int *out_indices, unsigned int *slot_at_peak,
                                    unsigned int *out_limbs, unsigned int *out_faces, unsigned int *out_joined)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const int writing = (peak_offsets != NULL) ? 1 : 0;
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int first = chunk * BINOMIAL_BASINS_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < BINOMIAL_BASINS_CHUNK)
                            ? geometry.voxels
                            : (first + BINOMIAL_BASINS_CHUNK);
    unsigned int peak_slot = (writing != 0) ? peak_offsets[chunk] : 0u;
    unsigned int face_slot = (writing != 0) ? face_offsets[chunk] : 0u;
    unsigned int joined_slot = (writing != 0) ? joined_offsets[chunk] : 0u;

    unsigned int last_face[6] = {0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu};
    unsigned int last_joined[6] = {0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu};
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((peak[voxel] == voxel) && (positive[voxel] != 0u))
        {
            if (writing != 0)
            {
                out_indices[peak_slot] = voxel;

                slot_at_peak[voxel] = peak_slot;
                for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
                {
                    out_limbs[(peak_slot * BINOMIAL_BASINS_LIMBS) + limb] = residual[(voxel * BINOMIAL_BASINS_LIMBS) + limb];
                }
            }
            peak_slot += 1u;
        }
        const unsigned int column = voxel % geometry.width;
        const unsigned int row = (voxel / geometry.width) % geometry.height;
        const unsigned int slice = voxel / plane;
        const unsigned int forward[3] = {voxel + 1u, voxel + geometry.width, voxel + plane};
        const int inside[3] = {(column + 1u) < geometry.width, (row + 1u) < geometry.height,
                               (slice + 1u) < geometry.depth};
        const unsigned int here = peak[voxel];
        for (unsigned int face = 0u; face < 3u; face += 1u)
        {
            if (inside[face] == 0)
            {
                continue;
            }
            const unsigned int there = peak[forward[face]];
            if ((here == there) || (positive[here] == 0u) || (positive[there] == 0u))
            {
                continue;
            }
            const unsigned int low = (here < there) ? here : there;
            const unsigned int high = (here < there) ? there : here;
            if ((want_faces != 0u) && ((last_face[2u * face] != low) || (last_face[(2u * face) + 1u] != high)))
            {
                if (writing != 0)
                {
                    out_faces[face_slot * 2u] = low;
                    out_faces[(face_slot * 2u) + 1u] = high;
                }
                face_slot += 1u;
                last_face[2u * face] = low;
                last_face[(2u * face) + 1u] = high;
            }
            if ((positive[voxel] != 0u) && (positive[forward[face]] != 0u)
             && ((last_joined[2u * face] != low) || (last_joined[(2u * face) + 1u] != high)))
            {
                if (writing != 0)
                {
                    out_joined[joined_slot * 2u] = low;
                    out_joined[(joined_slot * 2u) + 1u] = high;
                }
                joined_slot += 1u;
                last_joined[2u * face] = low;
                last_joined[(2u * face) + 1u] = high;
            }
        }
    }
    if (writing == 0)
    {
        chunk_peaks[chunk] = peak_slot;
        chunk_faces[chunk] = face_slot;
        chunk_joined[chunk] = joined_slot;
    }
}

__global__ static void pack_kernel(const unsigned char *positive, unsigned int voxels, unsigned int words,
                                   unsigned long long *packed)
{
    const unsigned int word = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (word >= words)
    {
        return;
    }
    const unsigned int first = word * 64u;
    const unsigned int past = ((voxels - first) < 64u) ? voxels : (first + 64u);
    unsigned long long bits = 0ull;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if (positive[voxel] != 0u)
        {
            bits |= 1ull << (voxel - first);
        }
    }
    packed[word] = bits;
}

static int device_launched(void)
{

    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

struct DeviceBuffers
{
    unsigned short *volume;
    unsigned int *first;
    unsigned int *second;
    unsigned int *smoothed;
    unsigned int *weights;
    unsigned int *successor;
    unsigned int *jumped;
    unsigned int *changed;
    unsigned char *positive;
    unsigned int *slot_at_peak;
    unsigned int *chunk_peaks;
    unsigned int *chunk_faces;
    unsigned int *peak_offsets;
    unsigned int *face_offsets;
    unsigned int *out_indices;
    unsigned int *out_sizes;
    unsigned long long *out_sums;
    unsigned int *out_limbs;
    unsigned int *out_faces;
    unsigned int *host_peak_offsets;
    unsigned int *host_face_offsets;
    unsigned int *host_indices;
    unsigned int *host_sizes;
    unsigned long long *host_sums;
    unsigned int *host_limbs;
    unsigned int *host_faces;
    unsigned int *host_labels;
    unsigned int *host_residual;
    unsigned long long *packed;
    unsigned long long *host_packed;
    unsigned int *chunk_joined;
    unsigned int *joined_offsets;
    unsigned int *out_joined;
    unsigned int *host_joined_offsets;
    unsigned int *host_joined;
};

static int device_unique_pairs(unsigned int *pairs, size_t total, size_t *unique);

static void device_release(DeviceBuffers *buffers)
{
    cudaFree(buffers->volume);
    cudaFree(buffers->first);
    cudaFree(buffers->second);
    cudaFree(buffers->smoothed);
    cudaFree(buffers->weights);
    cudaFree(buffers->successor);
    cudaFree(buffers->jumped);
    cudaFree(buffers->changed);
    cudaFree(buffers->positive);
    cudaFree(buffers->slot_at_peak);
    cudaFree(buffers->chunk_peaks);
    cudaFree(buffers->chunk_faces);
    cudaFree(buffers->peak_offsets);
    cudaFree(buffers->face_offsets);
    cudaFree(buffers->out_indices);
    cudaFree(buffers->out_sizes);
    cudaFree(buffers->out_sums);
    cudaFree(buffers->out_limbs);
    cudaFree(buffers->out_faces);
    free(buffers->host_peak_offsets);
    free(buffers->host_face_offsets);
    free(buffers->host_indices);
    free(buffers->host_sizes);
    free(buffers->host_sums);
    free(buffers->host_limbs);
    free(buffers->host_faces);
    free(buffers->host_labels);
    free(buffers->host_residual);
    cudaFree(buffers->packed);
    free(buffers->host_packed);
    cudaFree(buffers->chunk_joined);
    cudaFree(buffers->joined_offsets);
    cudaFree(buffers->out_joined);
    free(buffers->host_joined_offsets);
    free(buffers->host_joined);
}

struct HeldBuffers
{
    DeviceBuffers buffers;
    size_t voxels;
    size_t peak_room;
    size_t face_room;
    size_t joined_room;
};

static HeldBuffers s_held_buffers;

static int device_hold(size_t voxels, size_t chunks, int smoothing)
{
    HeldBuffers *const held = &s_held_buffers;
    const size_t limb_bytes = voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int);
    if ((held->voxels == voxels) && (voxels != 0u))
    {

        DeviceBuffers *const kept = &held->buffers;
        const int wanted = (smoothing != 0) && (kept->first == NULL);
        int grown = (wanted == 0) ? 1 : 0;
        if (wanted != 0)
        {
            grown = (cudaMalloc((void **)&kept->first, limb_bytes) == cudaSuccess) ? 1 : 0;
            grown = grown && (cudaMalloc((void **)&kept->smoothed, limb_bytes) == cudaSuccess);
        }
        return grown;
    }
    device_release(&held->buffers);
    memset(held, 0, sizeof(*held));
    DeviceBuffers *const buffers = &held->buffers;
    const size_t words = (voxels + 63u) / 64u;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&buffers->volume, voxels * sizeof(unsigned short)) == cudaSuccess);

    ok = ok && ((smoothing == 0) || (cudaMalloc((void **)&buffers->first, limb_bytes) == cudaSuccess));
    ok = ok && (cudaMalloc((void **)&buffers->second, limb_bytes) == cudaSuccess);
    ok = ok && ((smoothing == 0) || (cudaMalloc((void **)&buffers->smoothed, limb_bytes) == cudaSuccess));
    ok = ok && (cudaMalloc((void **)&buffers->weights, (size_t)BINOMIAL_BASINS_ROW_WIDTH * BINOMIAL_BASINS_ROW_WIDTH
                                                       * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->successor, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->jumped, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->changed, sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->positive, voxels) == cudaSuccess);

    ok = ok && (cudaMalloc((void **)&buffers->slot_at_peak, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->chunk_peaks, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->chunk_faces, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->peak_offsets, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->face_offsets, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->chunk_joined, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->joined_offsets, chunks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->packed, words * sizeof(unsigned long long)) == cudaSuccess);
    buffers->host_peak_offsets = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    buffers->host_face_offsets = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    buffers->host_joined_offsets = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    buffers->host_labels = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    buffers->host_packed = (unsigned long long *)malloc(words * sizeof(unsigned long long));
    ok = ok && (buffers->host_peak_offsets != NULL) && (buffers->host_face_offsets != NULL)
      && (buffers->host_joined_offsets != NULL) && (buffers->host_labels != NULL) && (buffers->host_packed != NULL);
    if (ok != 0)
    {
        unsigned int rows[BINOMIAL_BASINS_ROW_WIDTH * BINOMIAL_BASINS_ROW_WIDTH];
        memset(rows, 0, sizeof(rows));
        for (unsigned int order = 0u; order < BINOMIAL_BASINS_ROW_WIDTH; order += 1u)
        {
            unsigned int *const row = &rows[order * BINOMIAL_BASINS_ROW_WIDTH];
            row[0] = 1u;
            for (unsigned int depth = 1u; depth <= order; depth += 1u)
            {
                row[depth] = 1u;
                for (unsigned int at = depth - 1u; at > 0u; at -= 1u)
                {
                    row[at] += row[at - 1u];
                }
            }
        }
        ok = (cudaMemcpy(buffers->weights, rows, sizeof(rows), cudaMemcpyHostToDevice) == cudaSuccess) ? 1 : 0;
    }
    if (ok == 0)
    {
        device_release(buffers);
        memset(held, 0, sizeof(*held));
        return 0;
    }
    held->voxels = voxels;
    return 1;
}

static int device_grow(size_t peaks, size_t faces, size_t joins)
{
    HeldBuffers *const held = &s_held_buffers;
    DeviceBuffers *const buffers = &held->buffers;
    int ok = 1;
    if (peaks + 1u > held->peak_room)
    {

        const size_t room = (peaks + 1u) + (peaks + 1u) / 2u;
        cudaFree(buffers->out_indices);
        cudaFree(buffers->out_sizes);
        cudaFree(buffers->out_sums);
        cudaFree(buffers->out_limbs);
        free(buffers->host_indices);
        free(buffers->host_sizes);
        free(buffers->host_sums);
        free(buffers->host_limbs);
        buffers->out_indices = NULL;
        buffers->out_sizes = NULL;
        buffers->out_sums = NULL;
        buffers->out_limbs = NULL;
        ok = ok && (cudaMalloc((void **)&buffers->out_indices, room * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&buffers->out_sizes, room * sizeof(unsigned int)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&buffers->out_sums, room * 3u * sizeof(unsigned long long)) == cudaSuccess);
        ok = ok && (cudaMalloc((void **)&buffers->out_limbs, room * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int)) == cudaSuccess);
        buffers->host_indices = (unsigned int *)malloc(room * sizeof(unsigned int));
        buffers->host_sizes = (unsigned int *)malloc(room * sizeof(unsigned int));
        buffers->host_sums = (unsigned long long *)malloc(room * 3u * sizeof(unsigned long long));
        buffers->host_limbs = (unsigned int *)malloc(room * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int));
        ok = ok && (buffers->host_indices != NULL) && (buffers->host_sizes != NULL) && (buffers->host_sums != NULL)
          && (buffers->host_limbs != NULL);
        held->peak_room = (ok != 0) ? room : 0u;
    }
    if ((ok != 0) && (faces + 1u > held->face_room))
    {
        const size_t room = (faces + 1u) + (faces + 1u) / 2u;
        cudaFree(buffers->out_faces);
        free(buffers->host_faces);
        buffers->out_faces = NULL;
        ok = (cudaMalloc((void **)&buffers->out_faces, room * 2u * sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
        buffers->host_faces = (unsigned int *)malloc(room * 2u * sizeof(unsigned int));
        ok = ok && (buffers->host_faces != NULL);
        held->face_room = (ok != 0) ? room : 0u;
    }
    if ((ok != 0) && (joins + 1u > held->joined_room))
    {
        const size_t room = (joins + 1u) + (joins + 1u) / 2u;
        cudaFree(buffers->out_joined);
        free(buffers->host_joined);
        buffers->out_joined = NULL;
        ok = (cudaMalloc((void **)&buffers->out_joined, room * 2u * sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
        buffers->host_joined = (unsigned int *)malloc(room * 2u * sizeof(unsigned int));
        ok = ok && (buffers->host_joined != NULL);
        held->joined_room = (ok != 0) ? room : 0u;
    }
    return ok;
}

static int device_unique_pairs(unsigned int *pairs, size_t total, size_t *unique)
{
    *unique = 0u;
    if (total == 0u)
    {
        return 1;
    }

    unsigned long long *const keys = (unsigned long long *)malloc(total * sizeof(unsigned long long));
    if (keys == NULL)
    {
        return 0;
    }
    for (size_t pair = 0u; pair < total; pair += 1u)
    {
        keys[pair] = ((unsigned long long)pairs[pair * 2u] << 32u) | (unsigned long long)pairs[(pair * 2u) + 1u];
    }
    const int sorted = radix_sort_keys(keys, total);
    size_t unique_total = 0u;
    for (size_t pair = 0u; (sorted != 0) && (pair < total); pair += 1u)
    {
        if ((unique_total == 0u) || (keys[pair] != keys[pair - 1u]))
        {

            pairs[unique_total * 2u] = (unsigned int)(keys[pair] >> 32u);
            pairs[(unique_total * 2u) + 1u] = (unsigned int)(keys[pair] & 0xFFFFFFFFull);
            unique_total += 1u;
        }
    }
    free(keys);
    *unique = unique_total;
    return sorted;
}

static int device_smooth(DeviceBuffers *buffers, const unsigned int *orders, unsigned int *bits,
                         DeviceGeometry geometry)
{
    const unsigned int blocks = (geometry.voxels + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;

    DeviceOrders remainders;
    unsigned int remainder_total = 0u;
    unsigned int remainder_axes = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        remainders.order[axis] = orders[axis] % BINOMIAL_BASINS_PASS_ORDER;
        remainder_total += remainders.order[axis];
        remainder_axes += (remainders.order[axis] != 0u) ? 1u : 0u;
    }
    const int fuse = (remainder_axes > 1u) && (remainder_total <= BINOMIAL_BASINS_PASS_ORDER);
    int ok = 1;
    if (fuse != 0)
    {
        const unsigned int limbs_in = (*bits + 31u) / 32u;
        const unsigned int limbs_out = (*bits + remainder_total + 31u) / 32u;
        fused_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers->first, buffers->weights, remainders, limbs_in,
                                                        (limbs_out < BINOMIAL_BASINS_LIMBS) ? limbs_out
                                                                                            : BINOMIAL_BASINS_LIMBS,
                                                        geometry, buffers->second);
        ok = device_launched();
        unsigned int *const swapped = buffers->first;
        buffers->first = buffers->second;
        buffers->second = swapped;
        *bits += remainder_total;
    }
    for (unsigned int axis = 0u; (axis < 3u) && (ok != 0); axis += 1u)
    {
        unsigned int remaining = (fuse != 0) ? (orders[axis] - remainders.order[axis]) : orders[axis];
        while ((remaining > 0u) && (ok != 0))
        {
            const unsigned int order = (remaining > BINOMIAL_BASINS_PASS_ORDER)
                                     ? BINOMIAL_BASINS_PASS_ORDER
                                     : remaining;

            const unsigned int *const row = &buffers->weights[order * BINOMIAL_BASINS_ROW_WIDTH];
            const unsigned int limbs_out = (*bits + order + 31u) / 32u;
            pass_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers->first, row, order, axis, (*bits + 31u) / 32u,
                                                           (limbs_out < BINOMIAL_BASINS_LIMBS) ? limbs_out
                                                                                               : BINOMIAL_BASINS_LIMBS,
                                                           geometry, buffers->second);
            ok = device_launched();
            unsigned int *const swapped = buffers->first;
            buffers->first = buffers->second;
            buffers->second = swapped;
            *bits += order;
            remaining -= order;
        }
    }
    return ok;
}

extern "C" long binomial_basins_run(const BinomialBasinsRequest *args)
{
    if ((args == NULL) || (args->volume == NULL) || (args->adjacency_count == NULL) || (args->joined_count == NULL)
     || (args->depth == 0u) || (args->height == 0u) || (args->width == 0u)
     || (args->room > BINOMIAL_BASINS_ROOM_LIMIT) || (args->adjacency_room > BINOMIAL_BASINS_ROOM_LIMIT)
     || (args->joined_room > BINOMIAL_BASINS_ROOM_LIMIT)
     || ((args->room != 0u) && ((args->peak_indices == NULL) || (args->sizes == NULL)
                                || (args->sums == NULL) || (args->peak_limbs == NULL)))
     || ((args->adjacency_room != 0u) && (args->adjacency == NULL))
     || ((args->joined_room != 0u) && (args->joined == NULL)))
    {
        return BINOMIAL_BASINS_REFUSED;
    }
    unsigned long long total_bits = 16ull + 1ull;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if (((args->smooth_orders[axis] % 2u) != 0u) || ((args->background_orders[axis] % 2u) != 0u))
        {
            return BINOMIAL_BASINS_REFUSED;
        }
        total_bits += (unsigned long long)args->smooth_orders[axis]
                    + (unsigned long long)args->background_orders[axis];
    }

    const unsigned long long plane_count = (unsigned long long)args->height * (unsigned long long)args->width;
    int devices = 0;
    if ((total_bits > (32ull * BINOMIAL_BASINS_LIMBS)) || (plane_count > 0xFFFFFFFFull)
     || (cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return BINOMIAL_BASINS_REFUSED;
    }
    const unsigned long long voxel_count = plane_count * (unsigned long long)args->depth;
    if (voxel_count > (0xFFFFFFFFull / BINOMIAL_BASINS_LIMBS))
    {
        return BINOMIAL_BASINS_REFUSED;
    }

    DeviceGeometry geometry;
    memset(&geometry, 0, sizeof(geometry));
    geometry.depth = args->depth;
    geometry.height = args->height;
    geometry.width = args->width;

    geometry.voxels = (unsigned int)voxel_count;
    geometry.chunks = (geometry.voxels + BINOMIAL_BASINS_CHUNK - 1u) / BINOMIAL_BASINS_CHUNK;

    const size_t voxels = (size_t)geometry.voxels;
    const size_t chunks = (size_t)geometry.chunks;
    const size_t limb_bytes = voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int);
    const unsigned int blocks = (geometry.voxels + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;
    const unsigned int chunk_blocks = (geometry.chunks + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;

    profile_mark(NULL);
    const unsigned int extents[3] = {geometry.depth, geometry.height, geometry.width};
    const int transformed = (BINOMIAL_BASINS_TRANSFORM != 0)
                         && (binomial_transform_admits(extents, args->smooth_orders, args->background_orders) != 0);

    int ok = device_hold(voxels, chunks, (transformed == 0) ? 1 : 0);
    DeviceBuffers &buffers = s_held_buffers.buffers;
    profile_mark("allocate");

    ok = ok && (cudaMemcpy(buffers.volume, args->volume, voxels * sizeof(unsigned short),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if ((ok != 0) && (transformed != 0))
    {

        ok = binomial_transform_residual(buffers.volume, extents, args->smooth_orders, args->background_orders,
                                         buffers.second);
        profile_mark("transform residual");
    }
    if ((ok != 0) && (transformed == 0))
    {

        ok = ok && (cudaMemset(buffers.first, 0, limb_bytes) == cudaSuccess);
        ok = ok && (cudaMemset(buffers.second, 0, limb_bytes) == cudaSuccess);
        if (ok != 0)
        {
            load_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.volume, geometry.voxels, buffers.first);
            ok = device_launched();
        }
        profile_mark("upload and load");
        unsigned int bits = 16u;
        ok = ok && device_smooth(&buffers, args->smooth_orders, &bits, geometry);
        ok = ok && (cudaMemcpy(buffers.smoothed, buffers.first, limb_bytes, cudaMemcpyDeviceToDevice) == cudaSuccess);
        profile_mark("smooth");
        ok = ok && device_smooth(&buffers, args->background_orders, &bits, geometry);
        profile_mark("background");
        const unsigned int gain = args->background_orders[0] + args->background_orders[1]
                                + args->background_orders[2];
        if (ok != 0)
        {
            residual_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.smoothed, buffers.first, gain / 32u,
                                                               gain % 32u, geometry.voxels, buffers.second);
            ok = device_launched();
        }
        profile_mark("residual");
    }
    const unsigned int *const residual = buffers.second;

    if (ok != 0)
    {
        ascend_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(residual, geometry, buffers.successor,
                                                         buffers.positive);
        ok = device_launched();
    }
    profile_mark("ascend");
    unsigned int changed = 1u;
    while ((ok != 0) && (changed != 0u))
    {
        ok = (cudaMemset(buffers.changed, 0, sizeof(unsigned int)) == cudaSuccess) ? 1 : 0;
        if (ok != 0)
        {
            jump_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.successor, geometry.voxels,
                                                           buffers.jumped, buffers.changed);
            ok = device_launched();
        }
        ok = ok && (cudaMemcpy(&changed, buffers.changed, sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
        unsigned int *const swapped = buffers.successor;
        buffers.successor = buffers.jumped;
        buffers.jumped = swapped;
    }
    profile_mark("jump");

    const unsigned int want_faces = (args->adjacency != NULL) ? 1u : 0u;
    if (ok != 0)
    {
        chunk_kernel<<<chunk_blocks, BINOMIAL_BASINS_BLOCK>>>(residual, buffers.positive, buffers.successor,
                                                              want_faces, NULL, NULL,
                                                              NULL, geometry, buffers.chunk_peaks,
                                                              buffers.chunk_faces, buffers.chunk_joined, NULL, NULL,
                                                              NULL, NULL, NULL);
        ok = device_launched();
    }
    ok = ok && (cudaMemcpy(buffers.host_peak_offsets, buffers.chunk_peaks, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_face_offsets, buffers.chunk_faces, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_joined_offsets, buffers.chunk_joined, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    profile_mark("count");

    unsigned long long peak_total = 0ull;
    unsigned long long face_total = 0ull;
    unsigned long long joined_total = 0ull;
    if (ok != 0)
    {

        for (size_t chunk = 0u; chunk < chunks; chunk += 1u)
        {
            const unsigned int peaks = buffers.host_peak_offsets[chunk];
            const unsigned int faces = buffers.host_face_offsets[chunk];
            const unsigned int joins = buffers.host_joined_offsets[chunk];

            buffers.host_peak_offsets[chunk] = (unsigned int)peak_total;
            buffers.host_face_offsets[chunk] = (unsigned int)face_total;
            buffers.host_joined_offsets[chunk] = (unsigned int)joined_total;
            peak_total += (unsigned long long)peaks;
            face_total += (unsigned long long)faces;
            joined_total += (unsigned long long)joins;
        }
    }

    const size_t peaks = (size_t)peak_total;
    const size_t faces = (size_t)face_total;
    const size_t joins = (size_t)joined_total;
    ok = ok && device_grow(peaks, faces, joins);
    ok = ok && (cudaMemcpy(buffers.peak_offsets, buffers.host_peak_offsets, chunks * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.face_offsets, buffers.host_face_offsets, chunks * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.joined_offsets, buffers.host_joined_offsets, chunks * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        chunk_kernel<<<chunk_blocks, BINOMIAL_BASINS_BLOCK>>>(residual, buffers.positive, buffers.successor,
                                                              want_faces,
                                                              buffers.peak_offsets, buffers.face_offsets,
                                                              buffers.joined_offsets, geometry, NULL, NULL, NULL,
                                                              buffers.out_indices, buffers.slot_at_peak,
                                                              buffers.out_limbs,
                                                              buffers.out_faces, buffers.out_joined);
        ok = device_launched();
    }

    ok = ok && (cudaMemset(buffers.out_sizes, 0, peaks * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(buffers.out_sums, 0, peaks * 3u * sizeof(unsigned long long)) == cudaSuccess);
    if (ok != 0)
    {
        census_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.positive, buffers.successor, buffers.slot_at_peak,
                                                         geometry, buffers.out_sizes, buffers.out_sums);
        ok = device_launched();
    }
    profile_mark("emit and census");
    ok = ok && (cudaMemcpy(buffers.host_joined, buffers.out_joined, joins * 2u * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);

    const size_t asked_faces = (args->adjacency != NULL) ? faces : 0u;
    ok = ok && (cudaMemcpy(buffers.host_indices, buffers.out_indices, peaks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_sizes, buffers.out_sizes, peaks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_sums, buffers.out_sums, peaks * 3u * sizeof(unsigned long long),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_limbs, buffers.out_limbs,
                           peaks * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && ((asked_faces == 0u) || (cudaMemcpy(buffers.host_faces, buffers.out_faces,
                                                   asked_faces * 2u * sizeof(unsigned int),
                                                   cudaMemcpyDeviceToHost) == cudaSuccess));
    profile_mark("download outputs");
    if ((ok != 0) && (args->labels != NULL))
    {
        ok = (cudaMemcpy(buffers.host_labels, buffers.successor, voxels * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess) ? 1 : 0;
    }
    if ((ok != 0) && (args->residual_limbs != NULL))
    {
        if (buffers.host_residual == NULL)
        {
            buffers.host_residual = (unsigned int *)malloc(limb_bytes);
        }
        ok = (buffers.host_residual != NULL) ? 1 : 0;
        ok = ok && (cudaMemcpy(buffers.host_residual, residual, limb_bytes, cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    profile_mark("download labels");
    const size_t words = (voxels + 63u) / 64u;
    if ((ok != 0) && (args->positive_words != NULL))
    {

        const unsigned int word_count = (unsigned int)words;
        const unsigned int word_blocks = (word_count + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;
        pack_kernel<<<word_blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.positive, geometry.voxels, word_count,
                                                           buffers.packed);
        ok = device_launched();
        ok = ok && (cudaMemcpy(buffers.host_packed, buffers.packed, words * sizeof(unsigned long long),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }

    profile_mark("pack signs");

    size_t unique_total = 0u;
    ok = ok && device_unique_pairs(buffers.host_faces, asked_faces, &unique_total);
    profile_mark("sort faces");
    size_t joined_unique = 0u;
    ok = ok && device_unique_pairs(buffers.host_joined, joins, &joined_unique);
    profile_mark("sort joined");

    long answer = BINOMIAL_BASINS_REFUSED;
    if ((ok != 0) && (peaks <= (size_t)BINOMIAL_BASINS_ROOM_LIMIT) && (unique_total <= (size_t)BINOMIAL_BASINS_ROOM_LIMIT)
     && (joined_unique <= (size_t)BINOMIAL_BASINS_ROOM_LIMIT))
    {

        *args->adjacency_count = (unsigned int)unique_total;
        *args->joined_count = (unsigned int)joined_unique;
        answer = (long)peaks;
        if ((peaks <= (size_t)args->room) && (unique_total <= (size_t)args->adjacency_room)
         && (joined_unique <= (size_t)args->joined_room))
        {
            if (joined_unique != 0u)
            {
                memcpy(args->joined, buffers.host_joined, joined_unique * 2u * sizeof(unsigned int));
            }
            if (peaks != 0u)
            {
                memcpy(args->peak_indices, buffers.host_indices, peaks * sizeof(unsigned int));
                memcpy(args->sizes, buffers.host_sizes, peaks * sizeof(unsigned int));
                memcpy(args->sums, buffers.host_sums, peaks * 3u * sizeof(unsigned long long));
                memcpy(args->peak_limbs, buffers.host_limbs, peaks * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int));
            }
            if (unique_total != 0u)
            {
                memcpy(args->adjacency, buffers.host_faces, unique_total * 2u * sizeof(unsigned int));
            }
            if (args->labels != NULL)
            {
                memcpy(args->labels, buffers.host_labels, voxels * sizeof(unsigned int));
            }
            if (args->residual_limbs != NULL)
            {
                memcpy(args->residual_limbs, buffers.host_residual, limb_bytes);
            }
            if (args->positive_words != NULL)
            {
                memcpy(args->positive_words, buffers.host_packed, words * sizeof(unsigned long long));
            }
        }
    }
    profile_mark("copy out");
    if (ok == 0)
    {

        device_release(&buffers);
        memset(&s_held_buffers, 0, sizeof(s_held_buffers));
    }
    return answer;
}
