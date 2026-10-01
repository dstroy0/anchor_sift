// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_neighbors.cu: neighbor correlation
#include "noise_detector_internal.h"

static const char *const NOISE_RANGE_NAMES[NOISE_NEIGHBOR_RADII] = {"z", "y", "x", "z2", "z4", "z8", "z16", "z32"};

static const unsigned int NOISE_NEIGHBORS_SHOWN_BINS[NOISE_NEIGHBORS_SHOWN] = {3u, 5u, 9u, 13u, 25u};

__device__ static void noise_neighbors_flush(unsigned long long *cells, unsigned int radius, unsigned int level_bin,
                                             unsigned long long run[NOISE_NEIGHBORS_SUMS])
{
    unsigned long long *const cell = &cells[((radius * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBORS_SUMS];
    for (unsigned int sum = 0u; sum < NOISE_NEIGHBORS_SUMS; sum += 1u)
    {
        if (run[sum] != 0ull)
        {
            atomicAdd(&cell[sum], run[sum]);
        }
        run[sum] = 0ull;
    }
}

// One thread a voxel. At each radius whose voxel is inside the view, every frame pair's difference is multiplied by
// that voxel's, the product's sign kept by summing the raised and lowered products apart.
__global__ static void noise_neighbors_kernel(const unsigned short *lanes, unsigned long long frames,
                                              unsigned long long depth, unsigned long long height,
                                              unsigned long long width, unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_NEIGHBORS_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_NEIGHBORS_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long voxels = depth * height * width;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        const unsigned long long place[ENGINE_AXES] = {voxel / (height * width), (voxel / width) % height,
                                                       voxel % width};
        const unsigned long long extent[ENGINE_AXES] = {depth, height, width};
        const unsigned long long stride[ENGINE_AXES] = {height * width, width, 1ull};
        for (unsigned int radius = 0u; radius < NOISE_NEIGHBOR_RADII; radius += 1u)
        {
            // one voxel along each axis, then 2^(reach - 2) planes along z
            const unsigned int axis = (radius < ENGINE_AXES) ? radius : 0u;
            const unsigned long long apart = (radius < ENGINE_AXES) ? 1ull : (1ull << (radius - 2u));
            if ((place[axis] + apart) >= extent[axis])
            {
                continue;
            }
            const unsigned long long next = voxel + (apart * stride[axis]);
            unsigned long long run[NOISE_NEIGHBORS_SUMS] = {0ull, 0ull, 0ull, 0ull, 0ull};
            unsigned int run_bin = 0u;
            for (unsigned long long frame = 0ull; (frame + 1ull) < frames; frame += 1ull)
            {
                const unsigned int before = lanes[(frame * voxels) + voxel];
                const unsigned int after = lanes[((frame + 1ull) * voxels) + voxel];
                const unsigned int summed_bin = (before + after) >> NOISE_LEVEL_BIN_SHIFT;
                const unsigned int level_bin = (summed_bin < NOISE_LEVEL_BINS) ? summed_bin : (NOISE_LEVEL_BINS - 1u);
                if ((level_bin != run_bin) && (run[NOISE_NEIGHBORS_PAIRS] != 0ull))
                {
                    noise_neighbors_flush(cells, radius, run_bin, run);
                }
                run_bin = level_bin;
                const long long moved = (long long)after - (long long)before;
                const long long next_moved =
                    (long long)lanes[((frame + 1ull) * voxels) + next] - (long long)lanes[(frame * voxels) + next];
                const long long product = moved * next_moved;
                run[NOISE_NEIGHBORS_PAIRS] += 1ull;
                // a square is never negative, and a product's magnitude re-signs to unsigned long long exactly
                run[NOISE_NEIGHBORS_SQUARES] += (unsigned long long)(moved * moved);
                run[NOISE_NEIGHBORS_OTHER_SQUARES] += (unsigned long long)(next_moved * next_moved);
                run[NOISE_NEIGHBORS_RAISED] += (product > 0ll) ? (unsigned long long)product : 0ull;
                run[NOISE_NEIGHBORS_LOWERED] += (product < 0ll) ? (unsigned long long)(-product) : 0ull;
            }
            if (run[NOISE_NEIGHBORS_PAIRS] != 0ull)
            {
                noise_neighbors_flush(cells, radius, run_bin, run);
            }
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_NEIGHBORS_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

long noise_neighbors_sample(const unsigned short *volume, const unsigned long long extent[4],
                            unsigned long long sums[NOISE_NEIGHBORS_CELLS], EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    // every sum is at most one sample's pairs times the widest product, 65535 squared
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_NEIGHBORS_CELLS * sizeof(unsigned long long);
    unsigned short *device_lanes = NULL;
    unsigned long long *device_sums = NULL;
    int ok = NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_sums, sum_bytes), &device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemset(device_sums, 0, sum_bytes), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice),
                                         device_lanes, error);
    if (ok != 0)
    {
        const unsigned long long needed = (voxels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_neighbors_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, extent[1], extent[2],
                                                                   extent[3], device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

// sum d d' against the mean of sum d^2 and sum d'^2, in signed thousandths rounded toward zero: 2000 (raised - lowered)
// / (squares + other squares). For equal spreads it is the correlation. 0 where nothing was summed.
int noise_neighbors_per_mille(const unsigned long long cell[NOISE_NEIGHBORS_SUMS], long long *per_mille)
{
    if ((cell[NOISE_NEIGHBORS_SQUARES] == 0ull) && (cell[NOISE_NEIGHBORS_OTHER_SQUARES] == 0ull))
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger part;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&numerator, cell[NOISE_NEIGHBORS_RAISED]);
    noise_exact_word(&part, cell[NOISE_NEIGHBORS_LOWERED]);
    int ok = anchor_exact_subtract(&numerator, &part, &numerator) == ANCHOR_EXACT_OK;
    noise_exact_word(&part, 2000ull);
    ok = ok && (anchor_exact_multiply(&numerator, &part, &numerator) == ANCHOR_EXACT_OK);
    noise_exact_word(&denominator, cell[NOISE_NEIGHBORS_SQUARES]);
    noise_exact_word(&part, cell[NOISE_NEIGHBORS_OTHER_SQUARES]);
    ok = ok && (anchor_exact_add(&denominator, &part, &denominator) == ANCHOR_EXACT_OK) &&
         (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 1u; ok && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        ok = quotient.limb[limb] == 0u;
    }
    // the magnitude is at most 2000, one limb; the sign is held apart
    *per_mille = ok ? ((long long)quotient.limb[0] * (long long)quotient.sign) : 0ll;
    return ok;
}

static void noise_neighbors_summary(const char *name, const unsigned long long sums[NOISE_NEIGHBORS_CELLS])
{
    for (unsigned int radius = 0u; radius < NOISE_NEIGHBOR_RADII; radius += 1u)
    {
        if (radius == 0u)
        {
            printf("  %-24s %-3s", name, NOISE_RANGE_NAMES[radius]);
        }
        else
        {
            printf("  %-24s %-3s", "", NOISE_RANGE_NAMES[radius]);
        }
        for (unsigned int shown = 0u; shown < NOISE_NEIGHBORS_SHOWN; shown += 1u)
        {
            const unsigned int level_bin = NOISE_NEIGHBORS_SHOWN_BINS[shown];
            long long per_mille = 0ll;
            if (noise_neighbors_per_mille(&sums[((radius * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBORS_SUMS],
                                          &per_mille))
            {
                printf(" %7lld", per_mille);
            }
            else
            {
                printf(" %7s", "-");
            }
        }
        printf("\n");
    }
    fflush(stdout);
}

static int noise_neighbors_rows(FILE *table, const char *name, const unsigned long long sums[NOISE_NEIGHBORS_CELLS])
{
    int ok = 1;
    for (unsigned int radius = 0u; ok && (radius < NOISE_NEIGHBOR_RADII); radius += 1u)
    {
        for (unsigned int level_bin = 0u; ok && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const unsigned long long *const cell =
                &sums[((radius * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBORS_SUMS];
            if (cell[NOISE_NEIGHBORS_PAIRS] == 0ull)
            {
                continue;
            }
            ok = fprintf(table, "%s\t%s\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\n", name, NOISE_RANGE_NAMES[radius],
                         level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u), cell[NOISE_NEIGHBORS_PAIRS],
                         cell[NOISE_NEIGHBORS_SQUARES], cell[NOISE_NEIGHBORS_OTHER_SQUARES],
                         cell[NOISE_NEIGHBORS_RAISED], cell[NOISE_NEIGHBORS_LOWERED]) > 0;
        }
    }
    return ok;
}

extern "C" long noise_neighbors_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_CAPACITY];
    const int written =
        (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_neighbors.tsv", request->set) : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    int ok = NOISE_DETECTOR_CHECK(named && (request->samples != NULL) && (request->load != NULL), request, error,
                                  ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_IO(table != NULL, path, error) &&
             NOISE_DETECTOR_IO(fprintf(table, "sample\taxis\tlowest_mean\tpairs\tsquares\tnext_squares\traised"
                                              "\tlowered\n") > 0,
                               table, error);
    printf("  neighbors: each frame difference times the next voxel's along z, y and x, and the voxel's 2 to 32 planes"
           " on along z (z2 to z32), in bins of 8 by the pair's mean\n");
    printf("  2000 (raised - lowered) / (squares + next squares), signed per mille (independent noise holds 0):\n");
    printf("  %-24s  ", "mean");
    for (unsigned int shown = 0u; shown < NOISE_NEIGHBORS_SHOWN; shown += 1u)
    {
        printf(" %7u", NOISE_NEIGHBORS_SHOWN_BINS[shown] << (NOISE_LEVEL_BIN_SHIFT - 1u));
    }
    printf("\n");
    unsigned long long *const sums =
        (unsigned long long *)malloc((size_t)NOISE_NEIGHBORS_CELLS * sizeof(unsigned long long));
    ok = ok && NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        ok = NOISE_DETECTOR_CHECK(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                  ENGINE_ERROR_REQUEST) &&
             (noise_neighbors_sample(volume, extent, sums, error) == 0L);
        free(volume);
        ok = ok && NOISE_DETECTOR_IO(noise_neighbors_rows(table, name, sums) != 0, table, error);
        if (ok != 0)
        {
            noise_neighbors_summary(name, sums);
        }
    }
    free(sums);
    if (table != NULL)
    {
        ok = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && ok;
    }
    if (ok != 0)
    {
        printf("  neighbors: %u samples in %llu ms; every sum is in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}
