#include "max_tree.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_TREE_BLOCK 256u

#define MAX_TREE_TICKS 8u

#define MAX_TREE_JUMPS 2u

#define MAX_TREE_KEY_WORDS ((MAX_TREE_KEY_LIMBS + 1u) / 2u)

#define MAX_TREE_BUCKETS 256u

#define MAX_TREE_KEY_BYTES (BINOMIAL_BASINS_LIMBS * 4u)

__global__ static void max_tree_admit_kernel(const unsigned int *residual, unsigned int voxels,
                                             unsigned int *admits)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int *const limbs = &residual[(size_t)voxel * BINOMIAL_BASINS_LIMBS];
    const unsigned int negative = (limbs[BINOMIAL_BASINS_LIMBS - 1u] >> 31u) & 1u;
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        any |= limbs[limb];
    }
    admits[voxel] = (unsigned int)((negative == 0u) && (any != 0u));
}

__global__ static void max_tree_gather_kernel(const unsigned int *admits, const unsigned int *offsets,
                                              unsigned int voxels, unsigned int *order)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (admits[voxel] != 0u)
    {
        order[offsets[voxel]] = voxel;
    }
}

__global__ static void max_tree_count_kernel(const unsigned int *residual, const unsigned int *order,
                                             unsigned int held, unsigned int at, unsigned int *counts)
{
    __shared__ unsigned int mine[MAX_TREE_BUCKETS];
    for (unsigned int bucket = threadIdx.x; bucket < MAX_TREE_BUCKETS; bucket += blockDim.x)
    {
        mine[bucket] = 0u;
    }
    __syncthreads();
    const unsigned int first = blockIdx.x * blockDim.x;
    const unsigned int slot = first + threadIdx.x;
    if (slot < held)
    {
        const unsigned int voxel = order[slot];
        const unsigned int limb = residual[((size_t)voxel * BINOMIAL_BASINS_LIMBS) + (at / 4u)];
        const unsigned int byte = (~(limb >> ((at % 4u) * 8u))) & 0xFFu;
        atomicAdd(&mine[byte], 1u);
    }
    __syncthreads();
    for (unsigned int bucket = threadIdx.x; bucket < MAX_TREE_BUCKETS; bucket += blockDim.x)
    {
        counts[((size_t)blockIdx.x * MAX_TREE_BUCKETS) + bucket] = mine[bucket];
    }
}

__global__ static void max_tree_scatter_kernel(const unsigned int *residual, const unsigned int *order,
                                               unsigned int held, unsigned int at, const unsigned int *places,
                                               unsigned int *sorted)
{
    const unsigned int block = (blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int first = block * MAX_TREE_BLOCK;
    if (first >= held)
    {
        return;
    }
    unsigned int running[MAX_TREE_BUCKETS];
    for (unsigned int bucket = 0u; bucket < MAX_TREE_BUCKETS; bucket += 1u)
    {
        running[bucket] = places[((size_t)block * MAX_TREE_BUCKETS) + bucket];
    }
    const unsigned int past = ((first + MAX_TREE_BLOCK) < held) ? (first + MAX_TREE_BLOCK) : held;
    for (unsigned int slot = first; slot < past; slot += 1u)
    {
        const unsigned int voxel = order[slot];
        const unsigned int limb = residual[((size_t)voxel * BINOMIAL_BASINS_LIMBS) + (at / 4u)];
        const unsigned int byte = (~(limb >> ((at % 4u) * 8u))) & 0xFFu;
        sorted[running[byte]] = voxel;
        running[byte] += 1u;
    }
}

extern "C" int max_tree_order_agrees(const unsigned int *residual, unsigned int depth, unsigned int height,
                                     unsigned int width)
{
    MaxTree host;
    const long admitted = max_tree_build(residual, depth, height, width, &host);
    if (admitted < 0L)
    {
        return 0;
    }
    const size_t voxels = (size_t)depth * height * width;
    const unsigned int held = host.admitted;
    unsigned int *device_residual = NULL;
    unsigned int *device_admits = NULL;
    unsigned int *device_offsets = NULL;
    unsigned int *device_order = NULL;
    unsigned int *device_sorted = NULL;
    unsigned int *device_counts = NULL;
    unsigned int *device_places = NULL;
    const unsigned int blocks = (unsigned int)((held + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    const unsigned int spread = (unsigned int)((voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
    int ok = (cudaMalloc((void **)&device_residual, voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int))
              == cudaSuccess)
          && (cudaMalloc((void **)&device_admits, voxels * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_offsets, voxels * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_order, ((size_t)held + 1u) * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_sorted, ((size_t)held + 1u) * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_counts, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int))
              == cudaSuccess)
          && (cudaMalloc((void **)&device_places, (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int))
              == cudaSuccess);
    ok = ok && (cudaMemcpy(device_residual, residual,
                           voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (ok != 0)
    {
        max_tree_admit_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, (unsigned int)voxels,
                                                          device_admits);
        ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
    }
    unsigned int *const admits = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const offsets = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    ok = ok && (admits != NULL) && (offsets != NULL);
    ok = ok && (cudaMemcpy(admits, device_admits, voxels * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    unsigned int running = 0u;
    for (size_t voxel = 0u; (ok != 0) && (voxel < voxels); voxel += 1u)
    {
        offsets[voxel] = running;
        running += admits[voxel];
    }
    ok = ok && (running == held);
    ok = ok && (cudaMemcpy(device_offsets, offsets, voxels * sizeof(unsigned int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (ok != 0)
    {
        max_tree_gather_kernel<<<spread, MAX_TREE_BLOCK>>>(device_admits, device_offsets,
                                                           (unsigned int)voxels, device_order);
        ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
    }
    unsigned int *const counts = (unsigned int *)malloc((size_t)blocks * MAX_TREE_BUCKETS
                                                         * sizeof(unsigned int));
    ok = ok && (counts != NULL);
    for (unsigned int at = 0u; (ok != 0) && (at < MAX_TREE_KEY_BYTES); at += 1u)
    {
        max_tree_count_kernel<<<blocks, MAX_TREE_BLOCK>>>(device_residual, device_order, held, at,
                                                           device_counts);
        ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        ok = ok && (cudaMemcpy(counts, device_counts,
                               (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
        unsigned int place = 0u;
        for (unsigned int bucket = 0u; (ok != 0) && (bucket < MAX_TREE_BUCKETS); bucket += 1u)
        {
            for (unsigned int block = 0u; block < blocks; block += 1u)
            {
                const size_t slot = ((size_t)block * MAX_TREE_BUCKETS) + bucket;
                const unsigned int many = counts[slot];
                counts[slot] = place;
                place += many;
            }
        }
        ok = ok && (place == held);
        ok = ok && (cudaMemcpy(device_places, counts,
                               (size_t)blocks * MAX_TREE_BUCKETS * sizeof(unsigned int),
                               cudaMemcpyHostToDevice) == cudaSuccess);
        if (ok != 0)
        {
            const unsigned int walkers = (unsigned int)((blocks + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK);
            max_tree_scatter_kernel<<<walkers, MAX_TREE_BLOCK>>>(device_residual, device_order, held, at,
                                                                  device_places, device_sorted);
            ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        }
        unsigned int *const swap = device_order;
        device_order = device_sorted;
        device_sorted = swap;
    }
    unsigned int *const theirs = (unsigned int *)malloc(((size_t)held + 1u) * sizeof(unsigned int));
    ok = ok && (theirs != NULL);
    ok = ok && (cudaMemcpy(theirs, device_order, (size_t)held * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost) == cudaSuccess);
    int agrees = ok;
    for (unsigned int at = 0u; (agrees != 0) && (at < held); at += 1u)
    {
        if (theirs[at] != host.order[at])
        {
            printf("    the device and the reference part at %u: %u against %u\n", at, theirs[at],
                   host.order[at]);
            agrees = 0;
        }
    }
    free(admits);
    free(offsets);
    free(counts);
    free(theirs);
    cudaFree(device_residual);
    cudaFree(device_admits);
    cudaFree(device_offsets);
    cudaFree(device_order);
    cudaFree(device_sorted);
    cudaFree(device_counts);
    cudaFree(device_places);
    max_tree_release(&host);
    return agrees;
}

__device__ static unsigned int max_tree_admitted(const unsigned int *residual, unsigned int voxel)
{
    const unsigned int *const limbs = &residual[(size_t)voxel * BINOMIAL_BASINS_LIMBS];
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        any |= limbs[limb];
    }
    return (unsigned int)(((limbs[BINOMIAL_BASINS_LIMBS - 1u] >> 31u) == 0u) && (any != 0u));
}

__device__ static unsigned int max_tree_below(const unsigned int *residual, unsigned int left, unsigned int right)
{
    const unsigned int *const one = &residual[(size_t)left * BINOMIAL_BASINS_LIMBS];
    const unsigned int *const other = &residual[(size_t)right * BINOMIAL_BASINS_LIMBS];
    unsigned int decided = 0u;
    unsigned int below = 0u;
    for (unsigned int limb = BINOMIAL_BASINS_LIMBS; limb > 0u; limb -= 1u)
    {
        const unsigned int differs = (unsigned int)(one[limb - 1u] != other[limb - 1u]) & (decided ^ 1u);
        below |= differs & (unsigned int)(one[limb - 1u] < other[limb - 1u]);
        decided |= differs;
    }
    return below;
}

__device__ static unsigned int max_tree_key_limb(const unsigned int *residual, unsigned int weaker,
                                                 unsigned int name, unsigned int limb)
{
    const unsigned int above = (unsigned int)((limb >= 1u) && (limb <= BINOMIAL_BASINS_LIMBS));
    const unsigned int value = residual[((size_t)weaker * BINOMIAL_BASINS_LIMBS) + ((limb - 1u) * above)];
    return (limb == 0u) ? ~name : (value * above);
}

__device__ static unsigned long long max_tree_key_word(const unsigned int *residual, unsigned int weaker,
                                                       unsigned int name, unsigned int word)
{
    const unsigned long long low = max_tree_key_limb(residual, weaker, name, word * 2u);
    const unsigned long long high = max_tree_key_limb(residual, weaker, name, (word * 2u) + 1u);
    return (high << 32u) | low;
}

__device__ static unsigned int max_tree_leads(const unsigned int *residual, unsigned int weaker, unsigned int name,
                                              unsigned int word, const unsigned long long *best)
{
    unsigned int ties = 1u;
    for (unsigned int above = word + 1u; above < MAX_TREE_KEY_WORDS; above += 1u)
    {
        ties &= (unsigned int)(best[above] == max_tree_key_word(residual, weaker, name, above));
    }
    return ties;
}

__global__ static void max_tree_faces_kernel(const unsigned int *residual, unsigned int depth, unsigned int height,
                                             unsigned int width, unsigned char *faces)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int here = max_tree_admitted(residual, voxel);
    unsigned int flags = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int near = voxel + (stride[axis] * inside[axis]);
        const unsigned int binds = inside[axis] & here & max_tree_admitted(residual, near);
        const unsigned int far_weaker = max_tree_below(residual, near, voxel);
        flags |= (binds << axis) | ((binds & far_weaker) << (axis + 3u));
    }
    faces[voxel] = (unsigned char)flags;
}

__global__ static void max_tree_start_kernel(unsigned int voxels, unsigned int *belongs,
                                             unsigned long long *strongest, unsigned char *bound)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = voxel;
    for (unsigned int word = 0u; word < MAX_TREE_KEY_WORDS; word += 1u)
    {
        strongest[((size_t)voxel * MAX_TREE_KEY_WORDS) + word] = 0ull;
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        bound[((size_t)voxel * 3u) + axis] = 0u;
    }
}

__global__ static void max_tree_jump_kernel(unsigned int voxels, unsigned int *belongs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    belongs[voxel] = belongs[belongs[voxel]];
}

__global__ static void max_tree_flatten_kernel(unsigned int voxels, unsigned int *belongs)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    unsigned int at = belongs[voxel];
    while (belongs[at] != at)
    {
        at = belongs[at];
    }
    belongs[voxel] = at;
}

__global__ static void max_tree_choose_kernel(const unsigned int *residual, const unsigned char *faces,
                                              const unsigned int *belongs, unsigned int depth, unsigned int height,
                                              unsigned int width, unsigned int word, unsigned long long *strongest)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int flags = faces[voxel];
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int binds = (flags >> axis) & 1u;
        const unsigned int near = voxel + (stride[axis] * binds);
        const unsigned int other = belongs[near];
        if (other == one)
        {
            continue;
        }
        const unsigned int weaker = (((flags >> (axis + 3u)) & 1u) != 0u) ? near : voxel;
        const unsigned int name = (voxel * 3u) + axis;
        const unsigned long long mine = max_tree_key_word(residual, weaker, name, word);
        if (max_tree_leads(residual, weaker, name, word, &strongest[(size_t)one * MAX_TREE_KEY_WORDS]) != 0u)
        {
            atomicMax(&strongest[((size_t)one * MAX_TREE_KEY_WORDS) + word], mine);
        }
        if (max_tree_leads(residual, weaker, name, word, &strongest[(size_t)other * MAX_TREE_KEY_WORDS]) != 0u)
        {
            atomicMax(&strongest[((size_t)other * MAX_TREE_KEY_WORDS) + word], mine);
        }
    }
}

__global__ static void max_tree_partner_kernel(const unsigned long long *strongest, const unsigned int *belongs,
                                               unsigned int depth, unsigned int height, unsigned int width,
                                               unsigned int *partner)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long low = strongest[(size_t)voxel * MAX_TREE_KEY_WORDS];
    const unsigned int chose = (unsigned int)((belongs[voxel] == voxel) && (low != 0ull));
    if (chose == 0u)
    {
        partner[voxel] = voxel;
        return;
    }
    const unsigned int name = ~(unsigned int)(low & 0xFFFFFFFFull);
    const unsigned int lower = name / 3u;
    const unsigned int axis = name % 3u;
    const unsigned int plane = height * width;
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int one = belongs[lower];
    const unsigned int other = belongs[lower + stride[axis]];
    partner[voxel] = (one == voxel) ? other : one;
}

__global__ static void max_tree_hook_kernel(unsigned long long *strongest, const unsigned int *partner,
                                            unsigned int voxels, unsigned int tick, unsigned int *belongs,
                                            unsigned char *bound, unsigned int *moved, unsigned int *last)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned long long low = strongest[(size_t)voxel * MAX_TREE_KEY_WORDS];
    for (unsigned int word = 0u; word < MAX_TREE_KEY_WORDS; word += 1u)
    {
        strongest[((size_t)voxel * MAX_TREE_KEY_WORDS) + word] = 0ull;
    }
    const unsigned int other = partner[voxel];
    const unsigned int mutual = (unsigned int)(partner[other] == voxel);
    const unsigned int joins = (unsigned int)(other != voxel) & ((mutual ^ 1u) | (unsigned int)(voxel > other));
    if (joins == 0u)
    {
        return;
    }
    belongs[voxel] = other;
    bound[~(unsigned int)(low & 0xFFFFFFFFull)] = 1u;
    moved[0] = 1u;
    last[0] = tick + 1u;
}

static unsigned long long max_tree_microseconds(void)
{
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    return ((unsigned long long)now.tv_sec * 1000000ull) + ((unsigned long long)now.tv_nsec / 1000ull);
}

__global__ static void max_tree_reaches_kernel(const unsigned int *residual, unsigned int voxels,
                                               unsigned int level, unsigned char *reaches)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    reaches[voxel] = (unsigned char)(max_tree_admitted(residual, voxel)
                                     & (max_tree_below(residual, voxel, level) ^ 1u));
}

__global__ static void max_tree_label_start_kernel(const unsigned char *reaches, unsigned int voxels,
                                                   unsigned int *label)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    label[voxel] = (reaches[voxel] != 0u) ? voxel : MAX_TREE_ABSENT;
}

__global__ static void max_tree_spread_kernel(const unsigned char *reaches, const unsigned char *bound,
                                              unsigned int every, unsigned int depth, unsigned int height,
                                              unsigned int width, unsigned int *label, unsigned int *moved)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int plane = height * width;
    const unsigned int z = voxel / plane;
    const unsigned int y = (voxel % plane) / width;
    const unsigned int x = voxel % width;
    const unsigned int inside[3] = {(unsigned int)((z + 1u) < depth), (unsigned int)((y + 1u) < height),
                                    (unsigned int)((x + 1u) < width)};
    const unsigned int stride[3] = {plane, width, 1u};
    const unsigned int here = reaches[voxel];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int near = voxel + (stride[axis] * inside[axis]);
        const unsigned int crosses = inside[axis] & here & (unsigned int)reaches[near]
                                   & (every | (unsigned int)bound[((size_t)voxel * 3u) + axis]);
        if (crosses == 0u)
        {
            continue;
        }
        const unsigned int mine = label[voxel];
        const unsigned int theirs = label[near];
        if (mine == theirs)
        {
            continue;
        }
        const unsigned int was_mine = atomicMin(&label[voxel], theirs);
        const unsigned int was_theirs = atomicMin(&label[near], mine);
        if ((theirs < was_mine) || (mine < was_theirs))
        {
            moved[0] = 1u;
        }
    }
}

__global__ static void max_tree_label_jump_kernel(unsigned int voxels, unsigned int *label)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    const unsigned int held = label[voxel];
    if (held != MAX_TREE_ABSENT)
    {
        label[voxel] = label[held];
    }
}

__global__ static void max_tree_differ_kernel(const unsigned int *across_every, const unsigned int *across_chosen,
                                              unsigned int voxels, unsigned int *differ)
{
    const unsigned int voxel = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (voxel >= voxels)
    {
        return;
    }
    if (across_every[voxel] != across_chosen[voxel])
    {
        atomicAdd(differ, 1u);
    }
}

static int max_tree_label(const unsigned char *reaches, const unsigned char *bound, unsigned int every,
                          unsigned int depth, unsigned int height, unsigned int width, unsigned int *label,
                          unsigned int *moved, unsigned int *pinned_moved, cudaEvent_t *blocks_done)
{
    const unsigned int voxels = depth * height * width;
    const unsigned int spread = (voxels + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    max_tree_label_start_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, voxels, label);
    int ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = (cudaMemsetAsync(&moved[parity], 0, sizeof(unsigned int), 0) == cudaSuccess) ? 1 : 0;
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            max_tree_spread_kernel<<<spread, MAX_TREE_BLOCK>>>(reaches, bound, every, depth, height, width, label,
                                                               &moved[parity]);
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_label_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(voxels, label);
            }
            ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        }
        ok = ok && (cudaMemcpyAsync(&pinned_moved[parity], &moved[parity], sizeof(unsigned int),
                                    cudaMemcpyDeviceToHost, 0) == cudaSuccess);
        ok = ok && (cudaEventRecord(blocks_done[parity], 0) == cudaSuccess);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = (cudaEventSynchronize(blocks_done[previous]) == cudaSuccess) ? 1 : 0;
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    return (ok != 0) && (cudaDeviceSynchronize() == cudaSuccess);
}

extern "C" long max_tree_bind(const MaxTreeBindRequest *request)
{
    if ((request == NULL) || (request->residual == NULL) || (request->bound == NULL)
     || ((request->level_count != 0u) && (request->levels == NULL)))
    {
        return MAX_TREE_REFUSED;
    }
    const unsigned int depth = request->depth;
    const unsigned int height = request->height;
    const unsigned int width = request->width;
    const size_t voxels = (size_t)depth * height * width;
    if ((voxels == 0u) || ((voxels * 3u) >= 0xFFFFFFFFull))
    {
        return MAX_TREE_REFUSED;
    }
    unsigned int *device_residual = NULL;
    unsigned char *device_faces = NULL;
    unsigned int *device_belongs = NULL;
    unsigned long long *device_strongest = NULL;
    unsigned int *device_partner = NULL;
    unsigned char *device_bound = NULL;
    unsigned int *device_moved = NULL;
    unsigned int *pinned_moved = NULL;
    unsigned char *device_reaches = NULL;
    unsigned int *device_across_every = NULL;
    unsigned int *device_across_chosen = NULL;
    unsigned int *device_differ = NULL;
    const unsigned int proved_at = (request->level_count != 0u) ? request->level_count : 1u;
    cudaEvent_t blocks_done[2] = {NULL, NULL};
    int ok = (cudaMalloc((void **)&device_residual, voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int))
              == cudaSuccess)
          && (cudaMalloc((void **)&device_faces, voxels) == cudaSuccess)
          && (cudaMalloc((void **)&device_belongs, voxels * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_strongest, voxels * MAX_TREE_KEY_WORDS * sizeof(unsigned long long))
              == cudaSuccess)
          && (cudaMalloc((void **)&device_partner, voxels * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_bound, voxels * 3u) == cudaSuccess)
          && (cudaMalloc((void **)&device_moved, 3u * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMallocHost((void **)&pinned_moved, 2u * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_differ, proved_at * sizeof(unsigned int)) == cudaSuccess)
          && (cudaEventCreateWithFlags(&blocks_done[0], cudaEventDisableTiming) == cudaSuccess)
          && (cudaEventCreateWithFlags(&blocks_done[1], cudaEventDisableTiming) == cudaSuccess);
    ok = ok && (cudaMemcpy(device_residual, request->residual, voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    ok = ok && (cudaMemset(device_moved, 0, 3u * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaMemset(device_differ, 0, proved_at * sizeof(unsigned int)) == cudaSuccess);
    ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    const unsigned long long began = max_tree_microseconds();
    const unsigned int count = (unsigned int)voxels;
    const unsigned int spread = (count + MAX_TREE_BLOCK - 1u) / MAX_TREE_BLOCK;
    if (ok != 0)
    {
        max_tree_faces_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, depth, height, width, device_faces);
        max_tree_start_kernel<<<spread, MAX_TREE_BLOCK>>>(count, device_belongs, device_strongest, device_bound);
        ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
    }

    int settled = 0;
    unsigned int block = 0u;
    while ((ok != 0) && (settled == 0))
    {
        const unsigned int parity = block % 2u;
        ok = (cudaMemsetAsync(&device_moved[parity], 0, sizeof(unsigned int), 0) == cudaSuccess) ? 1 : 0;
        for (unsigned int tick = 0u; (ok != 0) && (tick < MAX_TREE_TICKS); tick += 1u)
        {
            for (unsigned int jump = 0u; jump < MAX_TREE_JUMPS; jump += 1u)
            {
                max_tree_jump_kernel<<<spread, MAX_TREE_BLOCK>>>(count, device_belongs);
            }
            max_tree_flatten_kernel<<<spread, MAX_TREE_BLOCK>>>(count, device_belongs);
            for (unsigned int word = MAX_TREE_KEY_WORDS; word > 0u; word -= 1u)
            {
                max_tree_choose_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, device_faces, device_belongs,
                                                                   depth, height, width, word - 1u,
                                                                   device_strongest);
            }
            max_tree_partner_kernel<<<spread, MAX_TREE_BLOCK>>>(device_strongest, device_belongs, depth, height,
                                                                width, device_partner);
            max_tree_hook_kernel<<<spread, MAX_TREE_BLOCK>>>(device_strongest, device_partner, count,
                                                             (block * MAX_TREE_TICKS) + tick, device_belongs,
                                                             device_bound, &device_moved[parity],
                                                             &device_moved[2]);
            ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        }
        ok = ok && (cudaMemcpyAsync(&pinned_moved[parity], &device_moved[parity], sizeof(unsigned int),
                                    cudaMemcpyDeviceToHost, 0) == cudaSuccess);
        ok = ok && (cudaEventRecord(blocks_done[parity], 0) == cudaSuccess);
        if ((ok != 0) && (block > 0u))
        {
            const unsigned int previous = 1u - parity;
            ok = (cudaEventSynchronize(blocks_done[previous]) == cudaSuccess) ? 1 : 0;
            settled = ((ok != 0) && (pinned_moved[previous] == 0u)) ? 1 : 0;
        }
        block += 1u;
    }
    ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    const unsigned long long bound_at = max_tree_microseconds();

    if ((ok != 0) && (request->level_count != 0u))
    {
        ok = (cudaMalloc((void **)&device_reaches, voxels) == cudaSuccess)
          && (cudaMalloc((void **)&device_across_every, voxels * sizeof(unsigned int)) == cudaSuccess)
          && (cudaMalloc((void **)&device_across_chosen, voxels * sizeof(unsigned int)) == cudaSuccess);
    }
    for (unsigned int taken = 0u; (ok != 0) && (taken < request->level_count); taken += 1u)
    {
        max_tree_reaches_kernel<<<spread, MAX_TREE_BLOCK>>>(device_residual, count, request->levels[taken],
                                                            device_reaches);
        ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        ok = ok && max_tree_label(device_reaches, device_bound, 1u, depth, height, width, device_across_every,
                                  device_moved, pinned_moved, blocks_done);
        ok = ok && max_tree_label(device_reaches, device_bound, 0u, depth, height, width, device_across_chosen,
                                  device_moved, pinned_moved, blocks_done);
        if (ok != 0)
        {
            max_tree_differ_kernel<<<spread, MAX_TREE_BLOCK>>>(device_across_every, device_across_chosen, count,
                                                               &device_differ[taken]);
            ok = (cudaGetLastError() == cudaSuccess) ? 1 : 0;
        }
    }
    ok = ok && (cudaDeviceSynchronize() == cudaSuccess);
    const unsigned long long proved_at_end = max_tree_microseconds();

    unsigned int last = 0u;
    unsigned int *const differ = (unsigned int *)malloc(proved_at * sizeof(unsigned int));
    ok = ok && (differ != NULL)
            && (cudaMemcpy(request->bound, device_bound, voxels * 3u, cudaMemcpyDeviceToHost) == cudaSuccess)
            && (cudaMemcpy(&last, &device_moved[2], sizeof(unsigned int), cudaMemcpyDeviceToHost) == cudaSuccess)
            && (cudaMemcpy(differ, device_differ, proved_at * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    long chosen = MAX_TREE_REFUSED;
    unsigned int held = 0u;
    if (ok != 0)
    {
        chosen = 0L;
        for (size_t face = 0u; face < (voxels * 3u); face += 1u)
        {
            chosen += (long)(request->bound[face] != 0u);
        }
        for (unsigned int taken = 0u; taken < request->level_count; taken += 1u)
        {
            held += (unsigned int)(differ[taken] == 0u);
        }
    }
    if (request->rounds != NULL)
    {
        *request->rounds = last;
    }
    if (request->levels_held != NULL)
    {
        *request->levels_held = held;
    }
    if (request->bound_microseconds != NULL)
    {
        *request->bound_microseconds = bound_at - began;
    }
    if (request->proved_microseconds != NULL)
    {
        *request->proved_microseconds = proved_at_end - bound_at;
    }
    free(differ);
    cudaFree(device_residual);
    cudaFree(device_faces);
    cudaFree(device_belongs);
    cudaFree(device_strongest);
    cudaFree(device_partner);
    cudaFree(device_bound);
    cudaFree(device_moved);
    cudaFreeHost(pinned_moved);
    cudaFree(device_reaches);
    cudaFree(device_across_every);
    cudaFree(device_across_chosen);
    cudaFree(device_differ);
    cudaEventDestroy(blocks_done[0]);
    cudaEventDestroy(blocks_done[1]);
    return chosen;
}
