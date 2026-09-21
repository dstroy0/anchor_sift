#include "residual_field.h"

#include <cuda_runtime.h>

#include <string.h>

#define RESIDUAL_FIELD_BLOCK 256u

static_assert(sizeof(float) == 4u,
              "residual_field: float must be IEEE binary32, the float32 scipy narrows each pass to");
static_assert(sizeof(double) == 8u,
              "residual_field: double must be IEEE binary64, the line buffer scipy correlates in");

struct CorrelationPass
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int axis;
    unsigned int radius;
};

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

    return (unsigned int)folded;
}

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
    const double *const centre = &kernel[pass.radius];

    double total = (double)source[voxel] * centre[0];
    for (unsigned int reach = pass.radius; reach > 0u; reach -= 1u)
    {

        const long long left = (long long)along - (long long)reach;
        const long long right = (long long)along + (long long)reach;
        const double left_value =
            (double)source[line_start + (device_reflect(left, (long long)length) * stride)];
        const double right_value =
            (double)source[line_start + (device_reflect(right, (long long)length) * stride)];

        total += (left_value + right_value) * centre[-(long long)reach];
    }

    destination[voxel] = (float)total;
}

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

static int residual_launched(void)
{
    return ((cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess)) ? 1 : 0;
}

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
    if ((args == NULL) || (args->volume == NULL) || (args->residual == NULL) || (args->depth == 0u)
     || (args->height == 0u) || (args->width == 0u))
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

    const unsigned long long plane = (unsigned long long)args->height
                                   * (unsigned long long)args->width;
    if (plane > 0xFFFFFFFFull)
    {
        return RESIDUAL_FIELD_REFUSED;
    }
    const unsigned long long voxels = plane * (unsigned long long)args->depth;
    int devices = 0;

    if ((voxels > (0xFFFFFFFFull - (unsigned long long)RESIDUAL_FIELD_BLOCK))
     || (cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return RESIDUAL_FIELD_REFUSED;
    }

    CorrelationPass shape;
    memset(&shape, 0, sizeof(shape));
    shape.depth = args->depth;
    shape.height = args->height;
    shape.width = args->width;

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

    float *const scratch[2] = {first_scratch, second_scratch};
    ok = ok && residual_smooth(volume, scratch, args->smooth_kernels, args->smooth_radii, shape,
                               smoothed);
    ok = ok && residual_smooth(smoothed, scratch, args->background_kernels, args->background_radii,
                               shape, background);
    if (ok != 0)
    {

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
