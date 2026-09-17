/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file binomial_basins.cu
 * @brief The CUDA engine for binomial_basins.h: integers only, equal to binomial_basins.c.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * ONE THREAD PER VOXEL for every pass, the residual, the ascent, the jumps and the census. A pass and
 * the residual read one volume and write another; the ascent writes only its own voxel; the census
 * accumulates integers with atomicAdd, which no schedule can change. ONE THREAD PER CHUNK wherever
 * raster order must survive: counting and emitting peaks and adjacency pairs. The pairs are then
 * sorted and made unique on the host exactly as the reference does, so both return the same list.
 */

#include "binomial_basins.h"
#include "radix_keys.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Stage timing for measurement builds. Both arms are defined; off, every mark folds away. */
#if !defined(BINOMIAL_BASINS_PROFILE)
#define BINOMIAL_BASINS_PROFILE 0
#endif

/**
 * @brief Prints the whole microseconds since the last mark, under a stage name, in a profile build.
 *
 * @param[in] stage The stage just finished; NULL starts the clock.
 */
static void profile_mark(const char *stage)
{
    if (BINOMIAL_BASINS_PROFILE == 0)
    {
        return;
    }
    static unsigned long long last = 0ULL;
    // Launches queue without waiting, so a stage is only timed once the device has finished it.
    (void)cudaDeviceSynchronize();
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    // Widening: seconds and nanoseconds are nonnegative on this clock.
    const unsigned long long micro = (unsigned long long)now.tv_sec * 1000000ULL
                                   + (unsigned long long)now.tv_nsec / 1000ULL;
    if (stage != NULL)
    {
        fprintf(stderr, "    %-22s %8llu us\n", stage, micro - last);
    }
    last = micro;
}

/** @brief Threads per block. */
#define BINOMIAL_BASINS_BLOCK 256u

/** @brief Voxels walked by one chunk thread where raster order has to be preserved. */
#define BINOMIAL_BASINS_CHUNK 4096u

static_assert(sizeof(unsigned int) == 4u, "binomial_basins: unsigned int must be 32 bits, a limb");
static_assert(sizeof(unsigned long long) == 8u,
              "binomial_basins: unsigned long long must be 64 bits, a limb product and its carry");
static_assert(BINOMIAL_BASINS_PASS_ORDER <= 32u,
              "binomial_basins: a pass's weights must sum to at most 2^32, or its limb sum can wrap");

/** @brief Extents as a kernel reads them, passed by value. */
struct DeviceGeometry
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int chunks;
};

/**
 * @brief The in-line position a half-sample reflected position reads from.
 *
 * @param[in] position Position along the line, possibly outside it.
 * @param[in] length   Line length, at least one.
 * @return             The position inside the line whose value stands there.
 */
__device__ static unsigned int device_reflect(long long position, long long length)
{
    // Inside the line, and one fold past either end, need no division; the result is the fold below's.
    if ((position >= 0ll) && (position < length))
    {
        // Narrowing is safe: position lies in [0, length).
        return (unsigned int)position;
    }
    if ((position < 0ll) && (position >= -length))
    {
        // Narrowing is safe: -1 - position lies in [0, length).
        return (unsigned int)(-1ll - position);
    }
    if ((position >= length) && (position < (2ll * length)))
    {
        // Narrowing is safe: 2 length - 1 - position lies in [0, length).
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
    // Narrowing is safe: folded lies in [0, length) and length is an extent held in unsigned int.
    return (unsigned int)folded;
}

/**
 * @brief Orders two residual values, sign included, as host_compare does.
 *
 * @param[in] left  Limbs of one value [BORROWS].
 * @param[in] right Limbs of the other [BORROWS].
 * @return          -1, 0 or 1.
 */
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

/**
 * @brief Whether a residual value is above zero, as host_positive does.
 *
 * @param[in] value Limbs [BORROWS].
 * @return          1 where positive, 0 otherwise.
 */
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

/**
 * @brief Loads raw intensities into limb zero.
 *
 * @param[in]  volume   Raw intensities [BORROWS].
 * @param[in]  voxels   Voxel count.
 * @param[out] limbs    Limbs, already zeroed [BORROWS].
 */
__global__ static void load_kernel(const unsigned short *volume, unsigned int voxels, unsigned int *limbs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    // Widening unsigned short to unsigned int is exact.
    limbs[voxel * BINOMIAL_BASINS_LIMBS] = (unsigned int)volume[voxel];
}

/**
 * @brief One binomial pass of an even order along one axis, as host_pass does.
 *
 * @param[in]  source      Limbs read [BORROWS].
 * @param[in]  weights     Pascal's row of the order [BORROWS].
 * @param[in]  order       Even order, at most BINOMIAL_BASINS_PASS_ORDER.
 * @param[in]  axis        0 for z, 1 for y, 2 for x.
 * @param[in]  limbs_in    Limbs that can be nonzero in the source.
 * @param[in]  geometry    Extents.
 * @param[out] destination Limbs written [BORROWS].
 */
__global__ static void pass_kernel(const unsigned int *source, const unsigned int *weights,
                                   unsigned int order, unsigned int axis, unsigned int limbs_in,
                                   DeviceGeometry geometry, unsigned int *destination)
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
        // Signed, because a tap before the line's start is reflected, not indexed.
        const long long position = (long long)along + (long long)tap - (long long)(order / 2u);
        const unsigned int read = line_start + (device_reflect(position, (long long)length) * stride);
        for (unsigned int limb = 0u; limb < limbs_in; limb += 1u)
        {
            // Widening both factors to unsigned long long is exact.
            accumulator[limb] += (unsigned long long)weights[tap]
                               * (unsigned long long)source[(read * BINOMIAL_BASINS_LIMBS) + limb];
        }
    }
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        const unsigned long long total = accumulator[limb] + carry;
        // Narrowing to a limb keeps the low 32 bits; the high bits are carried, not lost.
        destination[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

/**
 * @brief residual = smoothed * 2^gain - background, in two's complement across every limb.
 *
 * @param[in]  smoothed    Limbs of the first smoothing [BORROWS].
 * @param[in]  background  Limbs of the background smoothing [BORROWS].
 * @param[in]  whole       Whole limbs of the gain.
 * @param[in]  part        Remaining bits of the gain, below 32.
 * @param[in]  voxels      Voxel count.
 * @param[out] residual    Limbs written [BORROWS].
 */
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
        // The base keeps the difference non-negative before narrowing.
        const unsigned long long difference = (1ull << 32u) + (unsigned long long)shifted
                                            - (unsigned long long)subtracted[limb] - borrow;
        residual[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
        borrow = (difference < (1ull << 32u)) ? 1ull : 0ull;
    }
}

/**
 * @brief Each voxel's successor, the highest of itself and its 26 neighbours, and its sign.
 *
 * @param[in]  residual  Limbs [BORROWS].
 * @param[in]  geometry  Extents.
 * @param[out] successor Where each voxel steps [BORROWS].
 * @param[out] positive  Whether each voxel is above zero [BORROWS].
 */
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
    // Signed coordinates, because a neighbour one step before the volume is tested, not indexed.
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
                // Narrowing is safe: each coordinate was just shown to lie inside the volume.
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

/**
 * @brief One synchronous jump: every successor becomes its successor's successor.
 *
 * @param[in]     source      Successors before [BORROWS].
 * @param[in]     voxels      Voxel count.
 * @param[out]    destination Successors after [BORROWS].
 * @param[in,out] changed     Raised where any successor moved [BORROWS].
 */
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

/**
 * @brief Adds every positive voxel to its peak's count and index sums.
 *
 * @param[in]     positive Whether each voxel is above zero [BORROWS].
 * @param[in]     peak     Each voxel's peak [BORROWS].
 * @param[in]     geometry Extents.
 * @param[in,out] sizes    Positive voxels by peak [BORROWS].
 * @param[in,out] sums     Index sums z y x by peak [BORROWS].
 */
__global__ static void census_kernel(const unsigned char *positive, const unsigned int *peak,
                                     DeviceGeometry geometry, unsigned int *sizes,
                                     unsigned long long *sums)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= geometry.voxels) || (positive[voxel] == 0u))
    {
        return;
    }
    const unsigned int root = peak[voxel];
    const unsigned int plane = geometry.height * geometry.width;
    atomicAdd(&sizes[root], 1u);
    // Widening unsigned int to unsigned long long is exact; the sums need the width, not the terms.
    atomicAdd(&sums[root * 3u], (unsigned long long)(voxel / plane));
    atomicAdd(&sums[(root * 3u) + 1u], (unsigned long long)((voxel / geometry.width) % geometry.height));
    atomicAdd(&sums[(root * 3u) + 2u], (unsigned long long)(voxel % geometry.width));
}

/**
 * @brief Counts positive peaks and adjacency faces in each chunk.
 *
 * @param[in]  positive     Whether each voxel is above zero [BORROWS].
 * @param[in]  peak         Each voxel's peak [BORROWS].
 * @param[in]  geometry     Extents.
 * @param[out] chunk_peaks  Positive peaks per chunk [BORROWS].
 * @param[out] chunk_faces  Faces between two positive-peaked basins per chunk [BORROWS].
 */
__global__ static void count_kernel(const unsigned char *positive, const unsigned int *peak,
                                    DeviceGeometry geometry, unsigned int *chunk_peaks,
                                    unsigned int *chunk_faces, unsigned int *chunk_joined)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int first = chunk * BINOMIAL_BASINS_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < BINOMIAL_BASINS_CHUNK)
                            ? geometry.voxels
                            : (first + BINOMIAL_BASINS_CHUNK);
    unsigned int peaks = 0u;
    unsigned int faces = 0u;
    unsigned int joins = 0u;
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((peak[voxel] == voxel) && (positive[voxel] != 0u))
        {
            peaks += 1u;
        }
        const unsigned int column = voxel % geometry.width;
        const unsigned int row = (voxel / geometry.width) % geometry.height;
        const unsigned int slice = voxel / plane;
        const unsigned int forward[3] = {voxel + 1u, voxel + geometry.width, voxel + plane};
        const int inside[3] = {(column + 1u) < geometry.width, (row + 1u) < geometry.height,
                               (slice + 1u) < geometry.depth};
        for (unsigned int face = 0u; face < 3u; face += 1u)
        {
            if (inside[face] == 0)
            {
                continue;
            }
            const unsigned int here = peak[voxel];
            const unsigned int there = peak[forward[face]];
            if ((here != there) && (positive[here] != 0u) && (positive[there] != 0u))
            {
                faces += 1u;
                if ((positive[voxel] != 0u) && (positive[forward[face]] != 0u))
                {
                    joins += 1u;
                }
            }
        }
    }
    chunk_peaks[chunk] = peaks;
    chunk_faces[chunk] = faces;
    chunk_joined[chunk] = joins;
}

/**
 * @brief Writes each chunk's peaks and faces at its offsets, in raster order.
 *
 * @param[in]  residual       Limbs [BORROWS].
 * @param[in]  positive       Whether each voxel is above zero [BORROWS].
 * @param[in]  peak           Each voxel's peak [BORROWS].
 * @param[in]  sizes          Positive voxels by peak [BORROWS].
 * @param[in]  sums           Index sums by peak [BORROWS].
 * @param[in]  peak_offsets   Where each chunk's first peak goes [BORROWS].
 * @param[in]  face_offsets   Where each chunk's first face goes [BORROWS].
 * @param[in]  geometry       Extents.
 * @param[out] out_indices    Peak indices [BORROWS].
 * @param[out] out_sizes      Sizes [BORROWS].
 * @param[out] out_sums       Sums, three per peak [BORROWS].
 * @param[out] out_limbs      Residual limbs, BINOMIAL_BASINS_LIMBS per peak [BORROWS].
 * @param[out] out_faces      Pairs, two per face, lower peak first [BORROWS].
 */
__global__ static void emit_kernel(const unsigned int *residual, const unsigned char *positive,
                                   const unsigned int *peak, const unsigned int *sizes,
                                   const unsigned long long *sums, const unsigned int *peak_offsets,
                                   const unsigned int *face_offsets, const unsigned int *joined_offsets,
                                   DeviceGeometry geometry, unsigned int *out_indices,
                                   unsigned int *out_sizes, unsigned long long *out_sums,
                                   unsigned int *out_limbs, unsigned int *out_faces,
                                   unsigned int *out_joined)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (chunk >= geometry.chunks)
    {
        return;
    }
    const unsigned int plane = geometry.height * geometry.width;
    const unsigned int first = chunk * BINOMIAL_BASINS_CHUNK;
    const unsigned int past = ((geometry.voxels - first) < BINOMIAL_BASINS_CHUNK)
                            ? geometry.voxels
                            : (first + BINOMIAL_BASINS_CHUNK);
    unsigned int peak_slot = peak_offsets[chunk];
    unsigned int face_slot = face_offsets[chunk];
    unsigned int joined_slot = joined_offsets[chunk];
    for (unsigned int voxel = first; voxel < past; voxel += 1u)
    {
        if ((peak[voxel] == voxel) && (positive[voxel] != 0u))
        {
            out_indices[peak_slot] = voxel;
            out_sizes[peak_slot] = sizes[voxel];
            for (unsigned int axis = 0u; axis < 3u; axis += 1u)
            {
                out_sums[(peak_slot * 3u) + axis] = sums[(voxel * 3u) + axis];
            }
            for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
            {
                out_limbs[(peak_slot * BINOMIAL_BASINS_LIMBS) + limb] =
                    residual[(voxel * BINOMIAL_BASINS_LIMBS) + limb];
            }
            peak_slot += 1u;
        }
        const unsigned int column = voxel % geometry.width;
        const unsigned int row = (voxel / geometry.width) % geometry.height;
        const unsigned int slice = voxel / plane;
        const unsigned int forward[3] = {voxel + 1u, voxel + geometry.width, voxel + plane};
        const int inside[3] = {(column + 1u) < geometry.width, (row + 1u) < geometry.height,
                               (slice + 1u) < geometry.depth};
        for (unsigned int face = 0u; face < 3u; face += 1u)
        {
            if (inside[face] == 0)
            {
                continue;
            }
            const unsigned int here = peak[voxel];
            const unsigned int there = peak[forward[face]];
            if ((here != there) && (positive[here] != 0u) && (positive[there] != 0u))
            {
                out_faces[face_slot * 2u] = (here < there) ? here : there;
                out_faces[(face_slot * 2u) + 1u] = (here < there) ? there : here;
                face_slot += 1u;
                if ((positive[voxel] != 0u) && (positive[forward[face]] != 0u))
                {
                    out_joined[joined_slot * 2u] = (here < there) ? here : there;
                    out_joined[(joined_slot * 2u) + 1u] = (here < there) ? there : here;
                    joined_slot += 1u;
                }
            }
        }
    }
}

/**
 * @brief Packs the sign of every voxel into 64 bit words, one thread per word.
 *
 * @param[in]  positive Whether each voxel is above zero [BORROWS].
 * @param[in]  voxels   Voxel count.
 * @param[in]  words    Word count, (voxels + 63) / 64.
 * @param[out] packed   The words [BORROWS].
 */
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

/**
 * @brief Whether the kernel just launched ran without a device error.
 *
 * @return 1 where it did, 0 otherwise.
 */
static int device_launched(void)
{
    // No synchronise here: kernels queue behind one another, and every host read waits for the queue, so a
    // launch only has to check that it was accepted. Faults surface at the next read.
    return (cudaGetLastError() == cudaSuccess) ? 1 : 0;
}

/** @brief Every buffer one run holds on the device and the host. */
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
    unsigned int *sizes;
    unsigned long long *sums;
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

/**
 * @brief Sorts pairs, lower peak first then higher, and keeps each once, in place, as host_unique_pairs
 *        does.
 *
 * @param[in,out] pairs  The pairs [BORROWS].
 * @param[in]     total  Pairs held.
 * @param[out]    unique Unique pairs, which now lead the buffer [BORROWS].
 * @return               1 on success, 0 where scratch memory could not be had.
 */
static int device_unique_pairs(unsigned int *pairs, size_t total, size_t *unique);

/**
 * @brief Releases every buffer reached, whether or not allocation finished.
 *
 * @param[in,out] buffers The buffers [BORROWS].
 */
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
    cudaFree(buffers->sizes);
    cudaFree(buffers->sums);
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

/** @brief Pascal's rows 0 to BINOMIAL_BASINS_PASS_ORDER, one row per order, each padded to the widest. */
#define BINOMIAL_BASINS_ROW_WIDTH (BINOMIAL_BASINS_PASS_ORDER + 1u)

/** @brief The buffers kept between calls, the extents they were sized for, and the output rooms they hold. */
struct HeldBuffers
{
    DeviceBuffers buffers;
    size_t voxels;
    size_t peak_room;
    size_t face_room;
    size_t joined_room;
};

/** @brief One set of held buffers: the engine serves one caller at a time. */
static HeldBuffers s_held_buffers;

/**
 * @brief Holds every buffer sized by the extents, allocating only where the extents differ from the last call.
 *
 * The weight rows are uploaded here, once, so no smoothing pass waits on a host copy.
 *
 * @param[in] voxels Voxels of the view.
 * @param[in] chunks Chunks of the view.
 * @return           1 with the buffers held, 0 on an allocation failure with nothing held.
 */
static int device_hold(size_t voxels, size_t chunks)
{
    HeldBuffers *const held = &s_held_buffers;
    if ((held->voxels == voxels) && (voxels != 0u))
    {
        return 1;
    }
    device_release(&held->buffers);
    memset(held, 0, sizeof(*held));
    DeviceBuffers *const buffers = &held->buffers;
    const size_t limb_bytes = voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int);
    const size_t words = (voxels + 63u) / 64u;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&buffers->volume, voxels * sizeof(unsigned short)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->first, limb_bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->second, limb_bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->smoothed, limb_bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->weights, (size_t)BINOMIAL_BASINS_ROW_WIDTH * BINOMIAL_BASINS_ROW_WIDTH
                                                       * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->successor, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->jumped, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->changed, sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->positive, voxels) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->sizes, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&buffers->sums, voxels * 3u * sizeof(unsigned long long)) == cudaSuccess);
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

/**
 * @brief Grows the output buffers where this frame needs more than they hold; they never shrink.
 *
 * @param[in] peaks  Peaks this frame emits.
 * @param[in] faces  Adjacency faces this frame emits.
 * @param[in] joins  Joined faces this frame emits.
 * @return           1 on success, 0 on an allocation failure.
 */
static int device_grow(size_t peaks, size_t faces, size_t joins)
{
    HeldBuffers *const held = &s_held_buffers;
    DeviceBuffers *const buffers = &held->buffers;
    int ok = 1;
    if (peaks + 1u > held->peak_room)
    {
        // Half again as much room, so a slowly growing series does not reallocate every frame.
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
    // A pair packed lower peak high and higher peak low orders as one unsigned 64 bit key exactly as the
    // reference orders the pair, so a radix sort of the keys is the reference's sort.
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
            // Narrowing to each half keeps exactly the peak index packed there.
            pairs[unique_total * 2u] = (unsigned int)(keys[pair] >> 32u);
            pairs[(unique_total * 2u) + 1u] = (unsigned int)(keys[pair] & 0xFFFFFFFFull);
            unique_total += 1u;
        }
    }
    free(keys);
    *unique = unique_total;
    return sorted;
}

/**
 * @brief One separable binomial smoothing on the device, z then y then x, in passes of at most 16.
 *
 * @param[in,out] buffers  Buffers; first holds the input and, on return, the output [BORROWS].
 * @param[in]     orders   Order per axis, each even.
 * @param[in,out] bits     Bits the values fit, updated by each pass [BORROWS].
 * @param[in]     geometry Extents.
 * @return                 1 on success, 0 on a device error.
 */
static int device_smooth(DeviceBuffers *buffers, const unsigned int *orders, unsigned int *bits,
                         DeviceGeometry geometry)
{
    const unsigned int blocks = (geometry.voxels + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;
    int ok = 1;
    for (unsigned int axis = 0u; (axis < 3u) && (ok != 0); axis += 1u)
    {
        unsigned int remaining = orders[axis];
        while ((remaining > 0u) && (ok != 0))
        {
            const unsigned int order = (remaining > BINOMIAL_BASINS_PASS_ORDER)
                                     ? BINOMIAL_BASINS_PASS_ORDER
                                     : remaining;
            // The row for this order was uploaded once with the held buffers.
            const unsigned int *const row = &buffers->weights[order * BINOMIAL_BASINS_ROW_WIDTH];
            pass_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers->first, row, order, axis, (*bits + 31u) / 32u,
                                                           geometry, buffers->second);
            ok = device_launched();
            char probe_name[32];
            snprintf(probe_name, sizeof(probe_name), "PASS axis %u order %u limbs %u", axis, order, (*bits + 31u) / 32u);
            profile_mark(probe_name);
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
    // Widening each extent to unsigned long long is exact; the plane is checked before the third
    // multiply so neither product wraps.
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
    // Narrowing is safe: voxel_count was just bounded well below 2^32.
    geometry.voxels = (unsigned int)voxel_count;
    geometry.chunks = (geometry.voxels + BINOMIAL_BASINS_CHUNK - 1u) / BINOMIAL_BASINS_CHUNK;
    // Widening unsigned int to size_t is exact; every size below is built from these.
    const size_t voxels = (size_t)geometry.voxels;
    const size_t chunks = (size_t)geometry.chunks;
    const size_t limb_bytes = voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int);
    const unsigned int blocks = (geometry.voxels + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;
    const unsigned int chunk_blocks = (geometry.chunks + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;

    profile_mark(NULL);
    // The buffers are held between calls and allocated again only for different extents.
    int ok = device_hold(voxels, chunks);
    DeviceBuffers &buffers = s_held_buffers.buffers;
    profile_mark("allocate");

    ok = ok && (cudaMemcpy(buffers.volume, args->volume, voxels * sizeof(unsigned short),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemset(buffers.first, 0, limb_bytes) == cudaSuccess);
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
    const unsigned int *const residual = buffers.second;
    profile_mark("residual");

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

    ok = ok && (cudaMemset(buffers.sizes, 0, voxels * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(buffers.sums, 0, voxels * 3u * sizeof(unsigned long long)) == cudaSuccess);
    if (ok != 0)
    {
        census_kernel<<<blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.positive, buffers.successor, geometry,
                                                         buffers.sizes, buffers.sums);
        ok = device_launched();
    }
    if (ok != 0)
    {
        count_kernel<<<chunk_blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.positive, buffers.successor,
                                                              geometry, buffers.chunk_peaks,
                                                              buffers.chunk_faces, buffers.chunk_joined);
        ok = device_launched();
    }
    ok = ok && (cudaMemcpy(buffers.host_peak_offsets, buffers.chunk_peaks, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_face_offsets, buffers.chunk_faces, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    ok = ok && (cudaMemcpy(buffers.host_joined_offsets, buffers.chunk_joined, chunks * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    profile_mark("census and count");

    unsigned long long peak_total = 0ull;
    unsigned long long face_total = 0ull;
    unsigned long long joined_total = 0ull;
    if (ok != 0)
    {
        // Counts become offsets in place, and the running totals are the counts.
        for (size_t chunk = 0u; chunk < chunks; chunk += 1u)
        {
            const unsigned int peaks = buffers.host_peak_offsets[chunk];
            const unsigned int faces = buffers.host_face_offsets[chunk];
            const unsigned int joins = buffers.host_joined_offsets[chunk];
            // Narrowing is safe: peaks are at most the voxels, faces and joins at most three per
            // voxel, and the voxel count was bounded below 2^32 / 9.
            buffers.host_peak_offsets[chunk] = (unsigned int)peak_total;
            buffers.host_face_offsets[chunk] = (unsigned int)face_total;
            buffers.host_joined_offsets[chunk] = (unsigned int)joined_total;
            peak_total += (unsigned long long)peaks;
            face_total += (unsigned long long)faces;
            joined_total += (unsigned long long)joins;
        }
    }

    // Narrowing is safe: every total is below 2^32 by the bound above.
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
        emit_kernel<<<chunk_blocks, BINOMIAL_BASINS_BLOCK>>>(residual, buffers.positive, buffers.successor,
                                                             buffers.sizes, buffers.sums,
                                                             buffers.peak_offsets, buffers.face_offsets,
                                                             buffers.joined_offsets, geometry,
                                                             buffers.out_indices, buffers.out_sizes,
                                                             buffers.out_sums, buffers.out_limbs,
                                                             buffers.out_faces, buffers.out_joined);
        ok = device_launched();
    }
    profile_mark("emit");
    ok = ok && (cudaMemcpy(buffers.host_joined, buffers.out_joined, joins * 2u * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    // A caller that passes no adjacency buffer has not asked for adjacency: its faces are neither
    // downloaded nor sorted, and its count is zero, as the reference does.
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
        // Narrowing is safe: words is at most voxels / 64 + 1, below 2^32.
        const unsigned int word_count = (unsigned int)words;
        const unsigned int word_blocks = (word_count + BINOMIAL_BASINS_BLOCK - 1u) / BINOMIAL_BASINS_BLOCK;
        pack_kernel<<<word_blocks, BINOMIAL_BASINS_BLOCK>>>(buffers.positive, geometry.voxels, word_count,
                                                           buffers.packed);
        ok = device_launched();
        ok = ok && (cudaMemcpy(buffers.host_packed, buffers.packed, words * sizeof(unsigned long long),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }

    profile_mark("pack signs");
    // The same sort and the same unique pass the reference makes, so the lists are equal.
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
        // Narrowing is safe: every count was just held to BINOMIAL_BASINS_ROOM_LIMIT.
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
        // After a failure nothing held is trusted: the next call allocates afresh.
        device_release(&buffers);
        memset(&s_held_buffers, 0, sizeof(s_held_buffers));
    }
    return answer;
}
