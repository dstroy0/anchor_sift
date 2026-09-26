// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "unit_sweep.h"

#include <cuda_runtime.h>

#include <string.h>

#define UNIT_SWEEP_THREADS 256u

#define UNIT_SWEEP_SHARED_BYTES_MOST 49152u

#define UNIT_SWEEP_INPUT_BITS 16u

static_assert((sizeof(unsigned short) * 8u) == UNIT_SWEEP_INPUT_BITS,
              "unit_sweep: UNIT_SWEEP_INPUT_BITS must equal the bits of an unsigned short input voxel");

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define UNIT_SWEEP_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_UNIT_SWEEP, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                        (error_))

#define UNIT_SWEEP_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_UNIT_SWEEP, (unsigned int)__LINE__, \
                       (const void *)(evacaddr_), (error_))

struct UnitSweepShape
{
    unsigned int extent[ENGINE_AXES];
    unsigned long long voxels;
};

struct UnitSweepHeld
{
    unsigned int *narrow_planes;
    unsigned int *wide_planes;
    unsigned long long *disagreements;
    unsigned int *past_width;
    size_t narrow_words;
    size_t wide_words;
};

static UnitSweepHeld s_unit_sweep_held;

__global__ static void unit_sweep_load_kernel(const unsigned short *volume, unsigned long long voxels,
                                              unsigned int limbs, unsigned int *planes)
{
    const unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    planes[voxel] = (unsigned int)volume[voxel];
    for (unsigned int limb = 1u; limb < limbs; limb += 1u)
    {
        planes[((unsigned long long)limb * voxels) + voxel] = 0u;
    }
}

__global__ static void unit_sweep_planes_load_kernel(const unsigned int *input, unsigned int input_limbs,
                                                     unsigned int top_mask, unsigned long long voxels,
                                                     unsigned int limbs, unsigned int *planes,
                                                     unsigned int *past_width)
{
    const unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        planes[((unsigned long long)limb * voxels) + voxel]
            = (limb < input_limbs) ? input[((unsigned long long)limb * voxels) + voxel] : 0u;
    }
    if ((input[((unsigned long long)(input_limbs - 1u) * voxels) + voxel] & top_mask) != 0u)
    {
        atomicOr(past_width, 1u);
    }
}

__global__ static void unit_sweep_widen_kernel(const unsigned int *narrow_planes, unsigned int narrow_limbs,
                                               unsigned long long voxels, unsigned int wide_limbs,
                                               unsigned int *wide_planes)
{
    const unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    for (unsigned int limb = 0u; limb < wide_limbs; limb += 1u)
    {
        wide_planes[((unsigned long long)limb * voxels) + voxel]
            = (limb < narrow_limbs) ? narrow_planes[((unsigned long long)limb * voxels) + voxel] : 0u;
    }
}

// `steps` unit pairs [1, 2, 1] along the axis, each reading the voxel's neighbours with the edge voxel standing in past
// either end, then with `half` set the one unit step [1, 1] an odd order leaves, reading the voxel and the one before
// it with the first voxel standing in before the start. That is the key's window reflected at the edges: a pair keeps
// the line's reflection about the half voxel before its start, and the step after all pairs starts where the key's
// window of the whole order starts, floor((order + 1) / 2) before the voxel.
__global__ static void unit_sweep_axis_kernel(unsigned int *planes, UnitSweepShape shape, unsigned int axis,
                                              unsigned int limbs, unsigned int steps, unsigned int half,
                                              unsigned int bits)
{
    extern __shared__ unsigned int shared_line[];
    const unsigned int length = shape.extent[axis];
    const unsigned long long line = blockIdx.x;
    const unsigned long long plane = (unsigned long long)shape.extent[1] * shape.extent[2];
    const unsigned long long stride = (axis == 0u) ? plane : ((axis == 1u) ? (unsigned long long)shape.extent[2] : 1ull);
    const unsigned long long base = (axis == 0u) ? line
                                  : ((axis == 1u) ? (((line / shape.extent[2]) * plane) + (line % shape.extent[2]))
                                                  : (line * shape.extent[2]));
    unsigned int *front = shared_line;
    unsigned int *back = &shared_line[(size_t)length * limbs];
    const unsigned int input_limbs = (bits + 31u) / 32u;
    for (unsigned int place = threadIdx.x; place < length; place += blockDim.x)
    {
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            front[(limb * length) + place] = (limb < input_limbs)
                                           ? planes[((unsigned long long)limb * shape.voxels) + base + (place * stride)]
                                           : 0u;
            back[(limb * length) + place] = 0u;
        }
    }
    __syncthreads();
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int grown_limbs = (bits + (2u * (step + 1u)) + 31u) / 32u;
        const unsigned int live_limbs = (grown_limbs < limbs) ? grown_limbs : limbs;
        for (unsigned int place = threadIdx.x; place < length; place += blockDim.x)
        {
            const unsigned int left = (place == 0u) ? place : (place - 1u);
            const unsigned int right = ((place + 1u) == length) ? place : (place + 1u);
            unsigned long long carry = 0ull;
            for (unsigned int limb = 0u; limb < live_limbs; limb += 1u)
            {
                const unsigned int *const row = &front[limb * length];
                const unsigned long long total = (unsigned long long)row[left] + (2ull * (unsigned long long)row[place])
                                               + (unsigned long long)row[right] + carry;
                back[(limb * length) + place] = (unsigned int)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
        }
        __syncthreads();
        unsigned int *const former_front = front;
        front = back;
        back = former_front;
    }
    if (half != 0u)
    {
        const unsigned int grown_limbs = (bits + (2u * steps) + 1u + 31u) / 32u;
        const unsigned int live_limbs = (grown_limbs < limbs) ? grown_limbs : limbs;
        for (unsigned int place = threadIdx.x; place < length; place += blockDim.x)
        {
            const unsigned int before = (place == 0u) ? place : (place - 1u);
            unsigned long long carry = 0ull;
            for (unsigned int limb = 0u; limb < live_limbs; limb += 1u)
            {
                const unsigned int *const row = &front[limb * length];
                const unsigned long long total = (unsigned long long)row[before] + (unsigned long long)row[place] + carry;
                back[(limb * length) + place] = (unsigned int)(total & 0xFFFFFFFFull);
                carry = total >> 32u;
            }
        }
        __syncthreads();
        unsigned int *const former_front = front;
        front = back;
        back = former_front;
    }
    const unsigned int final_limbs = (bits + (2u * steps) + half + 31u) / 32u;
    const unsigned int stored_limbs = (final_limbs < limbs) ? final_limbs : limbs;
    for (unsigned int place = threadIdx.x; place < length; place += blockDim.x)
    {
        for (unsigned int limb = 0u; limb < stored_limbs; limb += 1u)
        {
            planes[((unsigned long long)limb * shape.voxels) + base + (place * stride)] = front[(limb * length) + place];
        }
    }
}

__global__ static void unit_sweep_residual_kernel(const unsigned int *narrow_planes, unsigned int narrow_limbs,
                                                  const unsigned int *wide_planes, unsigned int wide_limbs,
                                                  unsigned long long voxels, unsigned int gain, unsigned int limbs,
                                                  unsigned int *residual_lanes)
{
    const unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int gain_limbs = gain / 32u;
    const unsigned int gain_bits = gain % 32u;
    unsigned long long borrow = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        unsigned int shifted_limb = 0u;
        if (limb >= gain_limbs)
        {
            const unsigned int source_limb = limb - gain_limbs;
            shifted_limb = (source_limb < narrow_limbs)
                         ? (narrow_planes[((unsigned long long)source_limb * voxels) + voxel] << gain_bits)
                         : 0u;
            if ((gain_bits != 0u) && (source_limb > 0u) && ((source_limb - 1u) < narrow_limbs))
            {
                shifted_limb |= narrow_planes[((unsigned long long)(source_limb - 1u) * voxels) + voxel]
                             >> (32u - gain_bits);
            }
        }
        const unsigned int wide_limb = (limb < wide_limbs) ? wide_planes[((unsigned long long)limb * voxels) + voxel]
                                                           : 0u;
        const unsigned long long difference = (1ull << 32u) + (unsigned long long)shifted_limb
                                            - (unsigned long long)wide_limb - borrow;
        residual_lanes[(voxel * limbs) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
        borrow = (difference < (1ull << 32u)) ? 1ull : 0ull;
    }
}

__global__ static void unit_sweep_compare_kernel(const unsigned int *left, const unsigned int *right,
                                                 unsigned long long lanes, unsigned int limbs,
                                                 unsigned long long *disagreements)
{
    const unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (lane >= lanes)
    {
        return;
    }
    unsigned int difference_bits = 0u;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        difference_bits |= left[(lane * limbs) + limb] ^ right[(lane * limbs) + limb];
    }
    if (difference_bits != 0u)
    {
        atomicAdd(disagreements, 1ull);
    }
}

static int unit_sweep_grow(unsigned int **planes, size_t *room, size_t words, EngineError *error)
{
    if (words <= *room)
    {
        return 1;
    }
    cudaFree(*planes);
    *planes = NULL;
    *room = 0u;
    const int ok = UNIT_SWEEP_TOOK(cudaMalloc((void **)planes, words * sizeof(unsigned int)), planes, error);
    *room = (ok != 0) ? words : 0u;
    return ok;
}

// each axis's unit pairs, floor(order / 2) of them; or with `halves` set, only the one unit step [1, 1] each odd order
// leaves, which runs after every pair either term takes so that the pairs see the line's reflection. `bits` bounds the
// planes' width going in: the limbs a step reads and writes follow from it, and a bound above the width only carries
// limbs of zeros.
static int unit_sweep_axes(unsigned int *planes, const UnitSweepShape *shape, unsigned int limbs,
                           const unsigned int orders[ENGINE_AXES], unsigned int bits, int halves, EngineError *error)
{
    int ok = 1;
    for (unsigned int axis = 0u; (ok != 0) && (axis < ENGINE_AXES); axis += 1u)
    {
        const unsigned int steps = (halves != 0) ? 0u : (orders[axis] / 2u);
        const unsigned int half = (halves != 0) ? (orders[axis] % 2u) : 0u;
        const unsigned int input_bits = bits;
        bits += (2u * steps) + half;
        if ((steps == 0u) && (half == 0u))
        {
            continue;
        }
        const unsigned long long lines = shape->voxels / shape->extent[axis];
        const size_t shared_bytes = 2u * (size_t)shape->extent[axis] * limbs * sizeof(unsigned int);
        ok = UNIT_SWEEP_HELD(lines <= 0x7FFFFFFFull, &shape->extent[axis], error, ENGINE_ERROR_REQUEST)
          && UNIT_SWEEP_HELD(shared_bytes <= UNIT_SWEEP_SHARED_BYTES_MOST, &shape->extent[axis], error,
                             ENGINE_ERROR_REQUEST);
        if (ok != 0)
        {
            // lines was held at or below 2^31 - 1 above, so it narrows to the unsigned int grid size exactly
            unit_sweep_axis_kernel<<<(unsigned int)lines, UNIT_SWEEP_THREADS, shared_bytes>>>(planes, *shape, axis,
                                                                                             limbs, steps, half,
                                                                                             input_bits);
            ok = UNIT_SWEEP_TOOK(cudaGetLastError(), planes, error);
        }
    }
    return ok;
}

static int unit_sweep_planes_load(const UnitSweepRequest *request, const UnitSweepShape *shape,
                                  unsigned int narrow_limbs, unsigned int blocks, UnitSweepHeld *buffers,
                                  EngineError *error)
{
    const unsigned int input_limbs = (request->input_bits + 31u) / 32u;
    const unsigned int top_bits = request->input_bits % 32u;
    const unsigned int top_mask = (top_bits == 0u) ? 0u : ~((1u << top_bits) - 1u);
    unsigned int past_width = 0u;
    int ok = (buffers->past_width != NULL)
          || UNIT_SWEEP_TOOK(cudaMalloc((void **)&buffers->past_width, sizeof(unsigned int)), &buffers->past_width,
                             error);
    ok = ok && UNIT_SWEEP_TOOK(cudaMemset(buffers->past_width, 0, sizeof(unsigned int)), buffers->past_width, error);
    if (ok != 0)
    {
        unit_sweep_planes_load_kernel<<<blocks, UNIT_SWEEP_THREADS>>>(request->device_planes, input_limbs, top_mask,
                                                                      shape->voxels, narrow_limbs,
                                                                      buffers->narrow_planes, buffers->past_width);
        ok = UNIT_SWEEP_TOOK(cudaGetLastError(), buffers->narrow_planes, error);
    }
    ok = ok
      && UNIT_SWEEP_TOOK(cudaMemcpy(&past_width, buffers->past_width, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                         buffers->past_width, error);
    return ok && UNIT_SWEEP_HELD(past_width == 0u, &request->input_bits, error, ENGINE_ERROR_REQUEST);
}

extern "C" long unit_sweep_residual(const UnitSweepRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return UNIT_SWEEP_REFUSED;
    }
    EngineError *const error = request->error;
    const int planes_given = (request->device_planes != NULL) ? 1 : 0;
    const int asked = UNIT_SWEEP_HELD(((request->device_volume != NULL) != (planes_given != 0))
                                          && (request->device_out != NULL),
                                      request, error, ENGINE_ERROR_REQUEST)
                   && UNIT_SWEEP_HELD((planes_given == 0)
                                          || ((request->input_bits != 0u)
                                              && (request->input_bits < (32u * request->limbs))),
                                      &request->input_bits, error, ENGINE_ERROR_REQUEST)
                   && UNIT_SWEEP_HELD((request->depth != 0u) && (request->height != 0u) && (request->width != 0u),
                                      &request->depth, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return UNIT_SWEEP_REFUSED;
    }
    const unsigned int input_bits = (planes_given != 0) ? request->input_bits : UNIT_SWEEP_INPUT_BITS;
    unsigned int narrow_bits = input_bits;
    unsigned int gain = 0u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        // an odd background order would subtract the terms half a voxel apart; an odd smooth order moves both alike
        if (!UNIT_SWEEP_HELD((request->background_orders[axis] % 2u) == 0u, &request->background_orders[axis], error,
                             ENGINE_ERROR_REQUEST))
        {
            return UNIT_SWEEP_REFUSED;
        }
        narrow_bits += request->smooth_orders[axis];
        gain += request->background_orders[axis];
    }
    const unsigned int narrow_limbs = (narrow_bits + 31u) / 32u;
    const unsigned int wide_limbs = (narrow_bits + gain + 31u) / 32u;
    if (!UNIT_SWEEP_HELD((narrow_bits + gain + 1u) <= (32u * request->limbs), &request->limbs, error,
                         ENGINE_ERROR_REQUEST))
    {
        return UNIT_SWEEP_REFUSED;
    }
    const UnitSweepShape shape = {{request->depth, request->height, request->width},
                                  (unsigned long long)request->depth * request->height * request->width};
    UnitSweepHeld *const buffers = &s_unit_sweep_held;
    // the caller holds the voxel count below 2^32, so the block count fits unsigned int
    const unsigned int blocks = (unsigned int)((shape.voxels + UNIT_SWEEP_THREADS - 1u) / UNIT_SWEEP_THREADS);
    int ok = unit_sweep_grow(&buffers->narrow_planes, &buffers->narrow_words, (size_t)shape.voxels * narrow_limbs, error)
          && unit_sweep_grow(&buffers->wide_planes, &buffers->wide_words, (size_t)shape.voxels * wide_limbs, error);
    if ((ok != 0) && (planes_given == 0))
    {
        unit_sweep_load_kernel<<<blocks, UNIT_SWEEP_THREADS>>>(request->device_volume, shape.voxels, narrow_limbs,
                                                               buffers->narrow_planes);
        ok = UNIT_SWEEP_TOOK(cudaGetLastError(), buffers->narrow_planes, error);
    }
    ok = ok && ((planes_given == 0) || unit_sweep_planes_load(request, &shape, narrow_limbs, blocks, buffers, error));
    ok = ok && unit_sweep_axes(buffers->narrow_planes, &shape, narrow_limbs, request->smooth_orders, input_bits, 0,
                               error);
    if (ok != 0)
    {
        unit_sweep_widen_kernel<<<blocks, UNIT_SWEEP_THREADS>>>(buffers->narrow_planes, narrow_limbs, shape.voxels,
                                                                wide_limbs, buffers->wide_planes);
        ok = UNIT_SWEEP_TOOK(cudaGetLastError(), buffers->wide_planes, error);
    }
    ok = ok && unit_sweep_axes(buffers->wide_planes, &shape, wide_limbs, request->background_orders, narrow_bits, 0,
                               error);
    // the smooth orders' odd steps last, on both terms alike, once every pair has run
    ok = ok
      && unit_sweep_axes(buffers->narrow_planes, &shape, narrow_limbs, request->smooth_orders, narrow_bits, 1, error)
      && unit_sweep_axes(buffers->wide_planes, &shape, wide_limbs, request->smooth_orders, narrow_bits + gain, 1,
                         error);
    if (ok != 0)
    {
        unit_sweep_residual_kernel<<<blocks, UNIT_SWEEP_THREADS>>>(buffers->narrow_planes, narrow_limbs,
                                                                   buffers->wide_planes, wide_limbs, shape.voxels,
                                                                   gain, request->limbs, request->device_out);
        ok = UNIT_SWEEP_TOOK(cudaGetLastError(), request->device_out, error);
    }
    return (ok != 0) ? 0L : UNIT_SWEEP_REFUSED;
}

extern "C" long unit_sweep_lanes_compare(const UnitSweepComparison *comparison)
{
    if ((comparison == NULL) || (comparison->error == NULL))
    {
        return UNIT_SWEEP_REFUSED;
    }
    EngineError *const error = comparison->error;
    if (!UNIT_SWEEP_HELD((comparison->device_left != NULL) && (comparison->device_right != NULL)
                             && (comparison->disagreements != NULL),
                         comparison, error, ENGINE_ERROR_REQUEST))
    {
        return UNIT_SWEEP_REFUSED;
    }
    UnitSweepHeld *const buffers = &s_unit_sweep_held;
    int ok = (buffers->disagreements != NULL)
          || UNIT_SWEEP_TOOK(cudaMalloc((void **)&buffers->disagreements, sizeof(unsigned long long)),
                             &buffers->disagreements, error);
    ok = ok
      && UNIT_SWEEP_TOOK(cudaMemset(buffers->disagreements, 0, sizeof(unsigned long long)), buffers->disagreements,
                         error);
    if ((ok != 0) && (comparison->lanes != 0ull))
    {
        // the lanes are voxels, held below 2^32 by the caller, so the block count fits unsigned int
        unit_sweep_compare_kernel<<<(unsigned int)((comparison->lanes + UNIT_SWEEP_THREADS - 1u) / UNIT_SWEEP_THREADS),
                                    UNIT_SWEEP_THREADS>>>(comparison->device_left, comparison->device_right,
                                                          comparison->lanes, comparison->limbs,
                                                          buffers->disagreements);
        ok = UNIT_SWEEP_TOOK(cudaGetLastError(), buffers->disagreements, error);
    }
    ok = ok
      && UNIT_SWEEP_TOOK(cudaMemcpy(comparison->disagreements, buffers->disagreements, sizeof(unsigned long long),
                                    cudaMemcpyDeviceToHost),
                         comparison->disagreements, error);
    return (ok != 0) ? 0L : UNIT_SWEEP_REFUSED;
}

extern "C" void unit_sweep_release(void)
{
    UnitSweepHeld *const buffers = &s_unit_sweep_held;
    cudaFree(buffers->narrow_planes);
    cudaFree(buffers->wide_planes);
    cudaFree(buffers->disagreements);
    cudaFree(buffers->past_width);
    memset(buffers, 0, sizeof(*buffers));
}
