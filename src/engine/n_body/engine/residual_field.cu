/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file residual_field.cu
 * @brief The floating point band-pass residual on the device, one thread per voxel per axis pass.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Written to reproduce scipy.ndimage.correlate1d applied along each axis in turn, in mode
 *       "reflect": a double accumulator per voxel, the center weight first and then symmetric pairs
 *       from the outermost weight inward, narrowed to float32 after every axis. Floating point
 *       addition is not associative, and a different summation order would give different bits.
 */

#include "residual_field.h"

#include <cuda_runtime.h>

#include <string.h>

/** @brief Threads per block. */
#define RESIDUAL_FIELD_BLOCK 256u

static_assert(sizeof(float) == 4u,
              "residual_field: float must be IEEE binary32, the float32 scipy narrows each pass to");
static_assert(sizeof(double) == 8u,
              "residual_field: double must be IEEE binary64, the line buffer scipy correlates in");

/** @brief The shape, and the axis and kernel radius of one pass, passed to the kernel by value. */
struct CorrelationPass
{
    unsigned int depth;  /**< Voxels along axis 0. */
    unsigned int height; /**< Voxels along axis 1. */
    unsigned int width;  /**< Voxels along axis 2. */
    unsigned int voxels; /**< Voxels in the volume. */
    unsigned int axis;   /**< The axis this pass correlates along. */
    unsigned int radius; /**< The kernel's radius. */
};

/**
 * @brief Folds a position outside a line back into it, the way scipy's "reflect" mode does.
 *
 * @param[in] position A position along the line, possibly negative or past its end.
 * @param[in] length   The line's length.
 * @return             The position reflected into 0 to length - 1.
 * @note The edge sample is repeated: d c b a | a b c d | d c b a. The extension has period twice
 *       the length.
 */
__device__ static unsigned int device_reflect(long long position, long long length)
{
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

    // folded lies in 0 to length - 1, and a line is at most 2^32 voxels long.
    return (unsigned int)folded;
}

/**
 * @brief One thread per voxel: correlate along one axis with a symmetric kernel.
 *
 * @param[in]  source      The volume read [BORROWS].
 * @param[in]  kernel      The kernel's 2r + 1 weights, of which the first r + 1 are used
 *                         [BORROWS].
 * @param[in]  pass        The shape, axis and radius.
 * @param[out] destination The correlated volume [BORROWS].
 */
__global__ static void correlate_kernel(const float *source, const double *kernel,
                                        CorrelationPass pass, float *destination)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= pass.voxels)
    {
        return;
    }
    const unsigned int plane = pass.height * pass.width;
    const unsigned int column = voxel % pass.width;
    const unsigned int row = (voxel / pass.width) % pass.height;
    const unsigned int slice = voxel / plane;

    // The voxel's position along the pass's axis, that axis's length, and the step between
    // neighbors along it.
    unsigned int along = column;
    unsigned int length = pass.width;
    unsigned int stride = 1u;
    if (pass.axis == 0u)
    {
        along = slice;
        length = pass.depth;
        stride = plane;
    }
    else if (pass.axis == 1u)
    {
        along = row;
        length = pass.height;
        stride = pass.width;
    }
    const unsigned int line_start = voxel - (along * stride);
    const double *const center = &kernel[pass.radius];

    double total = (double)source[voxel] * center[0];
    for (unsigned int reach = pass.radius; reach > 0u; reach -= 1u)
    {

        const long long left = (long long)along - (long long)reach;
        const long long right = (long long)along + (long long)reach;
        const double left_value =
            (double)source[line_start + (device_reflect(left, (long long)length) * stride)];
        const double right_value =
            (double)source[line_start + (device_reflect(right, (long long)length) * stride)];

        // The two samples one reach apart share the left weight, as scipy's symmetric path sums
        // them.
        total += (left_value + right_value) * center[-(long long)reach];
    }

    // Narrowed to float32 after every pass, as scipy narrows its output array.
    destination[voxel] = (float)total;
}

/**
 * @brief One thread per voxel: the residual, smoothed minus background, in float32.
 *
 * @param[in]  smoothed   The smoothed volume [BORROWS].
 * @param[in]  background The background volume [BORROWS].
 * @param[in]  voxels     Voxels in the volume.
 * @param[out] residual   The difference [BORROWS].
 */
__global__ static void subtract_kernel(const float *smoothed, const float *background,
                                       unsigned int voxels, float *residual)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    residual[voxel] = smoothed[voxel] - background[voxel];
}

/**
 * @brief Whether the last launch was accepted and ran to completion.
 *
 * @return 1 where neither the launch nor the kernel reported an error, 0 otherwise.
 */
static int residual_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

/**
 * @brief Correlates a volume along all three axes, depth first.
 *
 * @param[in]  source       The volume [BORROWS].
 * @param[in]  scratch      Two volumes the first two passes write [BORROWS].
 * @param[in]  host_kernels The kernel of each axis, in host memory [BORROWS].
 * @param[in]  radii        The radius of each kernel [BORROWS].
 * @param[in]  shape        The volume's shape.
 * @param[out] destination  The smoothed volume, written by the third pass [BORROWS].
 * @return                  1 where every pass ran, 0 otherwise.
 */
static int residual_smooth(const float *source, float *const *scratch,
                           const double *const *host_kernels, const unsigned int *radii,
                           CorrelationPass shape, float *destination)
{
    const unsigned int blocks = (shape.voxels + RESIDUAL_FIELD_BLOCK - 1u) / RESIDUAL_FIELD_BLOCK;
    const float *reading = source;
    int ok = 1;
    for (unsigned int axis = 0u; (axis < 3u) && (ok != 0); axis += 1u)
    {
        float *const writing = (axis == 2u) ? destination : scratch[axis];

        const size_t weights = ((size_t)radii[axis] * 2u) + 1u;
        double *kernel = NULL;
        ok = (cudaMalloc((void **)&kernel, weights * sizeof(double)) == cudaSuccess) ? 1 : 0;
        ok = ok && (cudaMemcpy(kernel, host_kernels[axis], weights * sizeof(double),
                               cudaMemcpyHostToDevice) == cudaSuccess);
        if (ok != 0)
        {
            CorrelationPass pass = shape;
            pass.axis = axis;
            pass.radius = radii[axis];
            correlate_kernel<<<blocks, RESIDUAL_FIELD_BLOCK>>>(reading, kernel, pass, writing);
            ok = residual_launched();
        }
        cudaFree(kernel);
        reading = writing;
    }
    return ok;
}

extern "C" long residual_field_run(const ResidualFieldRequest *args)
{
    if ((args == NULL) || (args->volume == NULL) || (args->residual == NULL) || (args->depth == 0u) || (args->height == 0u) || (args->width == 0u))
    {
        return RESIDUAL_FIELD_REFUSED;
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if ((args->smooth_kernels[axis] == NULL) || (args->background_kernels[axis] == NULL))
        {
            return RESIDUAL_FIELD_REFUSED;
        }
    }

    const unsigned long long plane = (unsigned long long)args->height * (unsigned long long)args->width;
    if (plane > 0xFFFFFFFFull)
    {
        return RESIDUAL_FIELD_REFUSED;
    }
    const unsigned long long voxels = plane * (unsigned long long)args->depth;
    int devices = 0;

    // A volume within a block of 2^32 voxels would wrap the block count's rounding up.
    if ((voxels > (0xFFFFFFFFull - (unsigned long long)RESIDUAL_FIELD_BLOCK)) || (cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return RESIDUAL_FIELD_REFUSED;
    }

    CorrelationPass shape;
    memset(&shape, 0, sizeof(shape));
    shape.depth = args->depth;
    shape.height = args->height;
    shape.width = args->width;

    // Bounded below 2^32 just above. The count fits the unsigned int.
    shape.voxels = (unsigned int)voxels;
    const size_t bytes = (size_t)voxels * sizeof(float);

    float *volume = NULL;
    float *first_scratch = NULL;
    float *second_scratch = NULL;
    float *smoothed = NULL;
    float *background = NULL;
    int ok = 1;
    ok = ok && (cudaMalloc((void **)&volume, bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&first_scratch, bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&second_scratch, bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&smoothed, bytes) == cudaSuccess);
    ok = ok && (cudaMalloc((void **)&background, bytes) == cudaSuccess);
    ok = ok && (cudaMemcpy(volume, args->volume, bytes, cudaMemcpyHostToDevice) == cudaSuccess);

    // The background is the smoothed field smoothed again, not the raw volume smoothed wider.
    float *const scratch[2] = {first_scratch, second_scratch};
    ok = ok && residual_smooth(volume, scratch, args->smooth_kernels, args->smooth_radii, shape,
                               smoothed);
    ok = ok && residual_smooth(smoothed, scratch, args->background_kernels, args->background_radii,
                               shape, background);
    if (ok != 0)
    {

        // The raw volume is no longer needed, and its buffer takes the residual.
        const unsigned int blocks = (shape.voxels + RESIDUAL_FIELD_BLOCK - 1u) / RESIDUAL_FIELD_BLOCK;
        subtract_kernel<<<blocks, RESIDUAL_FIELD_BLOCK>>>(smoothed, background, shape.voxels, volume);
        ok = residual_launched();
    }
    ok = ok && (cudaMemcpy(args->residual, volume, bytes, cudaMemcpyDeviceToHost) == cudaSuccess);

    cudaFree(volume);
    cudaFree(first_scratch);
    cudaFree(second_scratch);
    cudaFree(smoothed);
    cudaFree(background);
    return (ok != 0) ? 0L : RESIDUAL_FIELD_REFUSED;
}
