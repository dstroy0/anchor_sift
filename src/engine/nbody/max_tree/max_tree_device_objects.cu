// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_device_objects.cu: roots, peaks, census, packing and holding
#include "max_tree_device_internal.h"

int max_tree_cc(const unsigned char *ranges, unsigned int depth, unsigned int height, unsigned int width,
                unsigned int *parent, unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done,
                EngineError *error)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int spread = (voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    int ok = 1;
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = MAX_TREE_STATUS_CHECK(cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0), &moved[parity], error);
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            max_tree_cc_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(ranges, depth, height, width, parent, &moved[parity]);
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_cc_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(ranges, voxels, parent);
            }
            ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), parent, error);
        }
        ok = ok && MAX_TREE_STATUS_CHECK(cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                                         cudaMemcpyDeviceToHost, 0),
                                         &pinned_moved[parity], error);
        ok = ok && MAX_TREE_STATUS_CHECK(cudaEventRecord(blocks_done[parity], 0), &blocks_done[parity], error);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = MAX_TREE_STATUS_CHECK(cudaEventSynchronize(blocks_done[previous]), &blocks_done[previous], error);
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    if (ok != 0)
    {
        max_tree_cc_flatten_kernel<<<spread, MAX_TREE_BLOCK>>>(ranges, voxels, parent);
        ok = MAX_TREE_STATUS_CHECK(cudaGetLastError(), parent, error);
    }
    return (ok != 0) && MAX_TREE_STATUS_CHECK(cudaDeviceSynchronize(), parent, error);
}

__global__ void max_tree_roots_kernel(const unsigned char *ranges, const unsigned int *label, unsigned int voxels,
                                      unsigned int *roots)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u) || (label[voxel] != voxel))
    {
        return;
    }
    atomicAdd(roots, 1u);
}

__device__ static unsigned int max_tree_peak_of(const unsigned long long *best, unsigned int root)
{
    return ~(unsigned int)(best[root] & 0xFFFFFFFFull);
}

__global__ void max_tree_peak_kernel(const unsigned int *code, const unsigned char *ranges, const unsigned int *label,
                                     unsigned int voxels, unsigned long long *best)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if ((voxel >= voxels) || (ranges[voxel] == 0u))
    {
        return;
    }
    const unsigned long long key = ((unsigned long long)code[voxel] << 32u) | (unsigned long long)(~voxel);
    unsigned long long *const best_key = &best[label[voxel]];
    if (key > best_key[0])
    {
        atomicMax(best_key, key);
    }
}

__global__ void max_tree_mark_kernel(const unsigned int *residual, const unsigned int *code,
                                     const unsigned char *ranges, const unsigned int *label,
                                     const unsigned long long *best, unsigned int voxels, unsigned int writing,
                                     unsigned int *at_chunk, unsigned int *slot_at, EngineBody *bodies)
{
    const unsigned int chunk = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int first = chunk * MAX_TREE_CHUNK;
    if (first >= voxels)
    {
        return;
    }
    const unsigned int end = ((voxels - first) < MAX_TREE_CHUNK) ? voxels : (first + MAX_TREE_CHUNK);
    unsigned int slot = (writing != 0u) ? at_chunk[chunk] : 0u;
    for (unsigned int voxel = first; voxel < end; voxel += 1u)
    {
        const unsigned int inside = (unsigned int)(ranges[voxel] != 0u);
        const unsigned int root = (inside != 0u) ? label[voxel] : voxel;
        const unsigned int peak = inside & (unsigned int)(max_tree_peak_of(best, root) == voxel);
        if ((peak & writing) != 0u)
        {
            EngineBody *const body = &bodies[slot];
            body->peak = voxel;
            body->code = code[voxel];
            body->parent = 0xFFFFFFFFu;
            body->forward = -1;
            body->backward = -1;
            for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
            {
                body->level[limb] = residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb];
            }
            slot_at[voxel] = slot;
        }
        slot += peak;
    }
    if (writing == 0u)
    {
        at_chunk[chunk] = slot;
    }
}

__global__ void max_tree_object_census_kernel(const unsigned char *ranges, const unsigned int *label,
                                              const unsigned long long *best, const unsigned int *slot_at,
                                              unsigned int depth, unsigned int height, unsigned int width,
                                              EngineBody *bodies, unsigned int *labels)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (ranges[voxel] == 0u)
    {
        labels[voxel] = voxel;
        return;
    }
    const unsigned int peak = max_tree_peak_of(best, label[voxel]);
    labels[voxel] = peak;
    EngineBody *const body = &bodies[slot_at[peak]];
    const unsigned int plane = height * width;
    const unsigned long long z = (unsigned long long)(voxel / plane);
    const unsigned long long y = (unsigned long long)((voxel % plane) / width);
    const unsigned long long x = (unsigned long long)(voxel % width);
    atomicAdd(&body->mass, 1u);
    atomicAdd(&body->sums[0], z);
    atomicAdd(&body->sums[1], y);
    atomicAdd(&body->sums[2], x);
    atomicAdd(&body->moments[0], z * z);
    atomicAdd(&body->moments[1], y * y);
    atomicAdd(&body->moments[2], x * x);
    atomicAdd(&body->moments[3], z * y);
    atomicAdd(&body->moments[4], z * x);
    atomicAdd(&body->moments[5], y * x);
    const unsigned int faces = (unsigned int)(z == 0ull) | ((unsigned int)(z + 1ull == depth) << 1u) |
                               ((unsigned int)(y == 0ull) << 2u) | ((unsigned int)(y + 1ull == height) << 3u) |
                               ((unsigned int)(x == 0ull) << 4u) | ((unsigned int)(x + 1ull == width) << 5u);
    if (faces != 0u)
    {
        atomicOr(&body->touches, faces);
    }
}

__global__ void max_tree_pack_kernel(const unsigned int *residual, unsigned int voxels, unsigned int words,
                                     unsigned long long *packed)
{
    const unsigned int word = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (word >= words)
    {
        return;
    }
    const unsigned int first = word * 64u;
    const unsigned int end = ((voxels - first) < 64u) ? voxels : (first + 64u);
    unsigned long long bits = 0ull;
    for (unsigned int voxel = first; voxel < end; voxel += 1u)
    {
        bits |= (unsigned long long)max_tree_selected(residual, voxel) << (voxel - first);
    }
    packed[word] = bits;
}

__global__ void max_tree_code_values_kernel(const unsigned int *residual, const unsigned int *order,
                                            const unsigned int *flags, const unsigned int *code, unsigned int voxels,
                                            unsigned int *values)
{
    const unsigned int place = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (place >= voxels)
    {
        return;
    }
    const unsigned int voxel = order[place];
    const unsigned int first = (unsigned int)((place == 0u) || (flags[place] != 0u));
    if ((first & max_tree_selected(residual, voxel)) == 0u)
    {
        return;
    }
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        values[((size_t)code[voxel] * ENGINE_RESIDUAL_LIMBS) + limb] =
            residual[((size_t)voxel * ENGINE_RESIDUAL_LIMBS) + limb];
    }
}

MaxTreeResident g_max_tree_resident;

void max_tree_release_resident(MaxTreeResident *resident)
{
    cudaFree(resident->code);
    cudaFree(resident->order[0]);
    cudaFree(resident->order[1]);
    cudaFree(resident->keys[0]);
    cudaFree(resident->keys[1]);
    cudaFree(resident->scratch);
    cudaFree(resident->faces);
    cudaFree(resident->belongs);
    cudaFree(resident->best);
    cudaFree(resident->partner);
    cudaFree(resident->bound);
    cudaFree(resident->ranges);
    cudaFree(resident->label);
    cudaFree(resident->change);
    cudaFree(resident->counts);
    cudaFree(resident->maximum);
    cudaFree(resident->level);
    cudaFree(resident->moved);
    cudaFreeHost(resident->pinned_moved);
    if (resident->blocks_done[0] != NULL)
    {
        cudaEventDestroy(resident->blocks_done[0]);
    }
    if (resident->blocks_done[1] != NULL)
    {
        cudaEventDestroy(resident->blocks_done[1]);
    }
    cudaFree(resident->roots);
    cudaFree(resident->at_chunk);
    free(resident->host_chunks);
    cudaFree(resident->packed);
    cudaFree(resident->bodies);
    for (unsigned int slot = 0u; slot < 2u; slot += 1u)
    {
        cudaFree(resident->kept_code[slot]);
        cudaFree(resident->kept_values[slot]);
    }
    const int keeping = resident->keeping;
    memset(resident, 0, sizeof(*resident));
    resident->keeping = keeping;
}

int max_tree_reserve(size_t voxels, EngineError *error)
{
    MaxTreeResident *const resident = &g_max_tree_resident;
    if ((resident->voxels == voxels) && (voxels != 0u))
    {
        return 1;
    }
    max_tree_release_resident(resident);
    const size_t chunks = (voxels + MAX_TREE_CHUNK - 1u) / MAX_TREE_CHUNK;
    const size_t words = (voxels + 63u) / 64u;
    const int items = (int)voxels;
    size_t sort_bytes = 0u;
    size_t scan_bytes = 0u;
    size_t max_bytes = 0u;
    cub::DoubleBuffer<unsigned int> no_keys(NULL, NULL);
    cub::DoubleBuffer<unsigned int> no_values(NULL, NULL);
    int ok = MAX_TREE_STATUS_CHECK(cub::DeviceRadixSort::SortPairs(NULL, sort_bytes, no_keys, no_values, items),
                                   &sort_bytes, error) &&
             MAX_TREE_STATUS_CHECK(cub::DeviceScan::InclusiveSum(NULL, scan_bytes, (const unsigned int *)NULL,
                                                                 (unsigned int *)NULL, items),
                                   &scan_bytes, error) &&
             MAX_TREE_STATUS_CHECK(cub::DeviceReduce::Max(NULL, max_bytes, (const int *)NULL, (int *)NULL, items),
                                   &max_bytes, error);
    resident->scratch_bytes = (sort_bytes > scan_bytes) ? sort_bytes : scan_bytes;
    resident->scratch_bytes = (max_bytes > resident->scratch_bytes) ? max_bytes : resident->scratch_bytes;
    ok = ok &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->code, voxels * sizeof(unsigned int)), &resident->code,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->order[0], voxels * sizeof(unsigned int)),
                               &resident->order[0], error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->order[1], voxels * sizeof(unsigned int)),
                               &resident->order[1], error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->keys[0], voxels * sizeof(unsigned int)),
                               &resident->keys[0], error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->keys[1], voxels * sizeof(unsigned int)),
                               &resident->keys[1], error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc(&resident->scratch, resident->scratch_bytes), &resident->scratch, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->faces, voxels), &resident->faces, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->belongs, voxels * sizeof(unsigned int)),
                               &resident->belongs, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->best, voxels * sizeof(unsigned long long)),
                               &resident->best, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->partner, voxels * sizeof(unsigned int)),
                               &resident->partner, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->bound, voxels * 3u), &resident->bound, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->ranges, voxels), &resident->ranges, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->label, voxels * sizeof(unsigned int)), &resident->label,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->change, (voxels + 2u) * sizeof(int)), &resident->change,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->counts, (voxels + 2u) * sizeof(int)), &resident->counts,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->maximum, sizeof(int)), &resident->maximum, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->level, sizeof(unsigned int)), &resident->level, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->moved, 3u * sizeof(unsigned int)), &resident->moved,
                               error) &&
         MAX_TREE_STATUS_CHECK(cudaMallocHost((void **)&resident->pinned_moved, 2u * sizeof(unsigned int)),
                               &resident->pinned_moved, error) &&
         MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&resident->blocks_done[0], cudaEventDisableTiming),
                               &resident->blocks_done[0], error) &&
         MAX_TREE_STATUS_CHECK(cudaEventCreateWithFlags(&resident->blocks_done[1], cudaEventDisableTiming),
                               &resident->blocks_done[1], error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->roots, sizeof(unsigned int)), &resident->roots, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->at_chunk, chunks * sizeof(unsigned int)),
                               &resident->at_chunk, error) &&
         MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->packed, words * sizeof(unsigned long long)),
                               &resident->packed, error);
    resident->host_chunks = (unsigned int *)malloc(chunks * sizeof(unsigned int));
    ok = ok && MAX_TREE_CHECK(resident->host_chunks != NULL, &resident->host_chunks, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int slot = 0u; (resident->keeping != 0) && (slot < 2u); slot += 1u)
    {
        ok = ok &&
             MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->kept_code[slot], voxels * sizeof(unsigned int)),
                                   &resident->kept_code[slot], error) &&
             MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->kept_values[slot],
                                              (voxels + 2u) * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                                   &resident->kept_values[slot], error);
    }
    if (ok == 0)
    {
        max_tree_release_resident(resident);
        return 0;
    }
    resident->voxels = voxels;
    return 1;
}

int max_tree_grow_bodies(size_t bodies, EngineError *error)
{
    MaxTreeResident *const resident = &g_max_tree_resident;
    if ((bodies + 1u) <= resident->body_capacity)
    {
        return 1;
    }
    const size_t capacity = (bodies + 1u) + ((bodies + 1u) / 2u);
    cudaFree(resident->bodies);
    resident->bodies = NULL;
    const int ok = MAX_TREE_STATUS_CHECK(cudaMalloc((void **)&resident->bodies, capacity * sizeof(EngineBody)),
                                         &resident->bodies, error);
    resident->body_capacity = (ok != 0) ? capacity : 0u;
    return ok;
}

#define MAX_TREE_STAGES 9u
static const char *const MAX_TREE_STAGE_NAMES[MAX_TREE_STAGES] = {"codes", "contract", "levels",   "label", "peak",
                                                                  "mark",  "census",   "download", "grade"};
static unsigned long long s_max_tree_stage_us[MAX_TREE_STAGES];
int s_max_tree_profile = -1;

void max_tree_stage(unsigned int stage, unsigned long long *mark)
{
    if (s_max_tree_profile <= 0)
    {
        return;
    }
    (void)cudaDeviceSynchronize();
    const unsigned long long now = engine_clock_microseconds();
    s_max_tree_stage_us[stage] += now - *mark;
    *mark = now;
}

extern "C" void max_tree_profile_report(void)
{
    for (unsigned int stage = 0u; (s_max_tree_profile > 0) && (stage < MAX_TREE_STAGES); stage += 1u)
    {
        printf("    %-10s %8llu ms\n", MAX_TREE_STAGE_NAMES[stage], s_max_tree_stage_us[stage] / 1000ull);
    }
}
