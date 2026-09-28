// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_pack.cu: packing the bodies
#include "max_tree_device_internal.h"

static unsigned int max_tree_bits_for(unsigned long long bound)
{
    unsigned int bits = 1u;
    while ((bits < 64u) && ((bound >> bits) != 0ull))
    {
        bits += 1u;
    }
    return bits;
}

extern "C" void max_tree_layout(unsigned int depth, unsigned int height, unsigned int width, unsigned int frames,
                                unsigned int samples, MaxTreeLayout *layout)
{
    const unsigned long long voxels = (unsigned long long)depth * height * width;
    const unsigned long long range[3] = {(depth > 0u) ? (depth - 1u) : 0u, (height > 0u) ? (height - 1u) : 0u,
                                         (width > 0u) ? (width - 1u) : 0u};
    memset(layout, 0, sizeof(*layout));
    layout->bits[MAX_TREE_FIELD_MOMENT_ZZ] = max_tree_bits_for(voxels * range[0] * range[0]);
    layout->bits[MAX_TREE_FIELD_MOMENT_YY] = max_tree_bits_for(voxels * range[1] * range[1]);
    layout->bits[MAX_TREE_FIELD_MOMENT_XX] = max_tree_bits_for(voxels * range[2] * range[2]);
    layout->bits[MAX_TREE_FIELD_MOMENT_ZY] = max_tree_bits_for(voxels * range[0] * range[1]);
    layout->bits[MAX_TREE_FIELD_MOMENT_ZX] = max_tree_bits_for(voxels * range[0] * range[2]);
    layout->bits[MAX_TREE_FIELD_MOMENT_YX] = max_tree_bits_for(voxels * range[1] * range[2]);
    layout->bits[MAX_TREE_FIELD_SUM_Z] = max_tree_bits_for(voxels * range[0]);
    layout->bits[MAX_TREE_FIELD_SUM_Y] = max_tree_bits_for(voxels * range[1]);
    layout->bits[MAX_TREE_FIELD_SUM_X] = max_tree_bits_for(voxels * range[2]);
    layout->bits[MAX_TREE_FIELD_PEAK] = max_tree_bits_for((voxels > 0ull) ? (voxels - 1ull) : 0ull);
    layout->bits[MAX_TREE_FIELD_TOUCHES] = 6u;
    layout->bits[MAX_TREE_FIELD_MASS] = max_tree_bits_for(voxels);
    layout->bits[MAX_TREE_FIELD_LEVEL] = (ENGINE_RESIDUAL_LIMBS * 32u) - 1u;
    layout->bits[MAX_TREE_FIELD_FRAME] = max_tree_bits_for((frames > 0u) ? (frames - 1u) : 0u);
    layout->bits[MAX_TREE_FIELD_SAMPLE] = max_tree_bits_for((samples > 0u) ? (samples - 1u) : 0u);
    unsigned int at = 0u;
    for (unsigned int field = 0u; field < MAX_TREE_FIELDS; field += 1u)
    {
        layout->offset[field] = at;
        at += layout->bits[field];
    }
    layout->total_bits = at;
    layout->limbs = (at + 31u) / 32u;
}

__device__ static unsigned int max_tree_put_field(unsigned int *magnitude, unsigned int offset, unsigned int bits,
                                                  const unsigned int *value, unsigned int limbs)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int within = (unsigned int)(bit < (limbs * 32u));
        const unsigned int set = ((value[(bit / 32u) * within] >> (bit % 32u)) & 1u) & within;
        const unsigned int to = offset + bit;
        magnitude[to / 32u] |= set << (to % 32u);
    }
    unsigned int lost = 0u;
    for (unsigned int bit = 0u; bit < (limbs * 32u); bit += 1u)
    {
        const unsigned int set = (value[bit / 32u] >> (bit % 32u)) & 1u;
        const unsigned int to = offset + bit;
        const unsigned int inside = (unsigned int)(bit < bits);
        const unsigned int magnitude_bit = inside & ((magnitude[(to / 32u) * inside] >> (to % 32u)) & 1u);
        lost += set ^ magnitude_bit;
    }
    return lost;
}

__global__ static void max_tree_pack_bodies_kernel(const EngineBody *bodies, unsigned int count, MaxTreeLayout layout,
                                                   unsigned int sample, unsigned int frame, unsigned int *magnitudes,
                                                   unsigned long long *mismatches)
{
    const unsigned int slot = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (slot >= count)
    {
        return;
    }
    const EngineBody *const body = &bodies[slot];
    unsigned int *const magnitude = &magnitudes[(size_t)slot * layout.limbs];
    for (unsigned int limb = 0u; limb < layout.limbs; limb += 1u)
    {
        magnitude[limb] = 0u;
    }
    unsigned int lost = 0u;
    for (unsigned int moment = 0u; moment < 6u; moment += 1u)
    {
        const unsigned int limbs[2] = {(unsigned int)(body->moments[moment] & 0xFFFFFFFFull),
                                       (unsigned int)(body->moments[moment] >> 32u)};
        lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_MOMENT_ZZ + moment],
                                   layout.bits[MAX_TREE_FIELD_MOMENT_ZZ + moment], limbs, 2u);
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int limbs[2] = {(unsigned int)(body->sums[axis] & 0xFFFFFFFFull),
                                       (unsigned int)(body->sums[axis] >> 32u)};
        lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_SUM_Z + axis],
                                   layout.bits[MAX_TREE_FIELD_SUM_Z + axis], limbs, 2u);
    }
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_PEAK], layout.bits[MAX_TREE_FIELD_PEAK],
                               &body->peak, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_TOUCHES], layout.bits[MAX_TREE_FIELD_TOUCHES],
                               &body->touches, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_MASS], layout.bits[MAX_TREE_FIELD_MASS],
                               &body->mass, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_LEVEL], layout.bits[MAX_TREE_FIELD_LEVEL],
                               body->level, ENGINE_RESIDUAL_LIMBS);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_FRAME], layout.bits[MAX_TREE_FIELD_FRAME],
                               &frame, 1u);
    lost += max_tree_put_field(magnitude, layout.offset[MAX_TREE_FIELD_SAMPLE], layout.bits[MAX_TREE_FIELD_SAMPLE],
                               &sample, 1u);
    if (lost != 0u)
    {
        atomicAdd(mismatches, (unsigned long long)lost);
    }
}

extern "C" long max_tree_pack(const MaxTreePackRequest *request)
{
    MaxTreeResident *const resident = &g_max_tree_resident;
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_ERROR;
    }
    EngineError *const error = request->error;
    const int asked =
        MAX_TREE_CHECK(request->layout != NULL, &request->layout, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK(request->device_magnitudes != NULL, &request->device_magnitudes, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK(request->mismatches != NULL, &request->mismatches, error, ENGINE_ERROR_REQUEST) &&
        MAX_TREE_CHECK(resident->voxels != 0u, &resident->voxels, error, ENGINE_ERROR_REQUEST);
    if (asked == 0)
    {
        return MAX_TREE_ERROR;
    }
    const unsigned int bodies = (unsigned int)resident->last_bodies;
    unsigned long long *device_lost = NULL;
    int ok =
        MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&device_lost, sizeof(unsigned long long)), &device_lost, error) &&
        MAX_TREE_STATUS_CHECK(cudaMemset(device_lost, 0, sizeof(unsigned long long)), device_lost, error);
    if ((ok != 0) && (bodies != 0u))
    {
        max_tree_pack_bodies_kernel<<<(bodies + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK, MAX_TREE_BLOCK>>>(
            resident->bodies, bodies, *request->layout, request->sample, request->frame, request->device_magnitudes,
            device_lost);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), request->device_magnitudes, error);
    }
    unsigned long long lost = 0ull;
    ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpy(&lost, device_lost, sizeof(unsigned long long), cudaMemcpyDeviceToHost),
                                     device_lost, error);
    cudaFree(device_lost);
    *request->mismatches = lost;
    ok = ok && MAX_TREE_CHECK(lost == 0ull, request->device_magnitudes, error, ENGINE_ERROR_LOGIC);
    return (ok != 0) ? (long)bodies : MAX_TREE_ERROR;
}
