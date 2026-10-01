// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_flicker.cu: flicker
#include "noise_detector_internal.h"

__device__ static void noise_flicker_flush(unsigned long long *cells, unsigned int lag, unsigned int level_bin,
                                           unsigned long long run[NOISE_FLICKER_SUMS])
{
    unsigned long long *const cell = &cells[((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS];
    for (unsigned int sum = 0u; sum < NOISE_FLICKER_SUMS; sum += 1u)
    {
        if (run[sum] != 0ull)
        {
            atomicAdd(&cell[sum], run[sum]);
        }
        run[sum] = 0ull;
    }
}

// One thread a voxel. Consecutive pairs of a voxel mostly fall in one level bin. A pair adds to the thread's run
// and the run goes to the block's sums only when the bin changes.
__global__ static void noise_flicker_kernel(const unsigned short *lanes, unsigned long long frames,
                                            unsigned long long voxels, unsigned long long width,
                                            unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_FLICKER_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_FLICKER_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        const int beside = ((voxel % width) + 1ull) < width;
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            const unsigned long long apart = 1ull << lag;
            unsigned long long run[NOISE_FLICKER_SUMS] = {0ull, 0ull, 0ull, 0ull};
            unsigned int run_bin = 0u;
            for (unsigned long long frame = 0ull; (frame + apart) < frames; frame += 1ull)
            {
                const unsigned long long early = (frame * voxels) + voxel;
                const unsigned long long late = ((frame + apart) * voxels) + voxel;
                const unsigned int before = lanes[early];
                const unsigned int after = lanes[late];
                const unsigned int summed_bin = (before + after) >> NOISE_LEVEL_BIN_SHIFT;
                const unsigned int level_bin = (summed_bin < NOISE_LEVEL_BINS) ? summed_bin : (NOISE_LEVEL_BINS - 1u);
                if ((level_bin != run_bin) && (run[NOISE_FLICKER_PAIRS] != 0ull))
                {
                    noise_flicker_flush(cells, lag, run_bin, run);
                }
                run_bin = level_bin;
                const long long moved = (long long)after - (long long)before;
                run[NOISE_FLICKER_PAIRS] += 1ull;
                // a square is never negative. It re-signs to unsigned long long exactly
                run[NOISE_FLICKER_SQUARES] += (unsigned long long)(moved * moved);
                if (beside)
                {
                    const long long neighbor_moved = (long long)lanes[late + 1ull] - (long long)lanes[early + 1ull];
                    const long long against_neighbor = moved - neighbor_moved;
                    run[NOISE_FLICKER_NEIGHBOR_PAIRS] += 1ull;
                    run[NOISE_FLICKER_NEIGHBOR_SQUARES] += (unsigned long long)(against_neighbor * against_neighbor);
                }
            }
            if (run[NOISE_FLICKER_PAIRS] != 0ull)
            {
                noise_flicker_flush(cells, lag, run_bin, run);
            }
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_FLICKER_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

long noise_flicker_sample(const unsigned short *volume, const unsigned long long extent[4],
                          unsigned long long sums[NOISE_FLICKER_CELLS], EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long width = extent[3];
    // every sum is at most one sample's pairs times the widest square, and so is every total the summary forms
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (width != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / NOISE_WIDEST_SQUARE));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_FLICKER_CELLS * sizeof(unsigned long long);
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
        noise_flicker_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, voxels, width, device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

void noise_exact_word(AnchorExactInteger *value, unsigned long long word)
{
    anchor_exact_zero(value);
    value->limb[0] = (uint32_t)(word & 0xFFFFFFFFull);
    value->limb[1] = (uint32_t)(word >> 32u);
    value->sign = (word != 0ull) ? 1 : 0;
}

// (squares / pairs) against (first_squares / first_pairs), in thousandths rounded down: the four words multiplied
// across. No mean is ever rounded. 0 where either mean is undefined or the quotient passes 2^64.
int noise_per_mille(unsigned long long squares, unsigned long long pairs, unsigned long long first_squares,
                    unsigned long long first_pairs, unsigned long long *per_mille)
{
    if ((pairs == 0ull) || (first_pairs == 0ull) || (first_squares == 0ull))
    {
        return 0;
    }
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger factor;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    noise_exact_word(&numerator, squares);
    noise_exact_word(&factor, first_pairs);
    int ok = anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK;
    noise_exact_word(&factor, 1000ull);
    ok = ok && (anchor_exact_multiply(&numerator, &factor, &numerator) == ANCHOR_EXACT_OK);
    noise_exact_word(&denominator, first_squares);
    noise_exact_word(&factor, pairs);
    ok = ok && (anchor_exact_multiply(&denominator, &factor, &denominator) == ANCHOR_EXACT_OK) &&
         (anchor_exact_divide(&numerator, &denominator, &quotient, &remainder) == ANCHOR_EXACT_OK);
    for (unsigned int limb = 2u; ok && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        ok = quotient.limb[limb] == 0u;
    }
    *per_mille = ok ? (((unsigned long long)quotient.limb[1] << 32u) | quotient.limb[0]) : 0ull;
    return ok;
}

// every lag's sums pooled over the summary's level bins, means 40 to 199
void noise_flicker_pooled(const unsigned long long sums[NOISE_FLICKER_CELLS],
                          unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS])
{
    memset(pooled, 0, (size_t)NOISE_FLICKER_LAGS * NOISE_FLICKER_SUMS * sizeof(unsigned long long));
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            for (unsigned int sum = 0u; sum < NOISE_FLICKER_SUMS; sum += 1u)
            {
                pooled[lag][sum] += sums[(((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS) + sum];
            }
        }
    }
}

static void noise_flicker_summary(const char *name, const unsigned long long extent[4],
                                  const unsigned long long sums[NOISE_FLICKER_CELLS])
{
    unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS];
    noise_flicker_pooled(sums, pooled);
    printf("  %-24s %llu frames of %llux%llux%llu; means 40 to 199, %llu pairs at lag 1\n", name, extent[0], extent[1],
           extent[2], extent[3], pooled[0][NOISE_FLICKER_PAIRS]);
    const unsigned int kinds[2][2] = {{NOISE_FLICKER_SQUARES, NOISE_FLICKER_PAIRS},
                                      {NOISE_FLICKER_NEIGHBOR_SQUARES, NOISE_FLICKER_NEIGHBOR_PAIRS}};
    const char *const said[2] = {"the frame difference         ", "less its x neighbor's       "};
    for (unsigned int kind = 0u; kind < 2u; kind += 1u)
    {
        printf("    %s", said[kind]);
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            unsigned long long per_mille = 0ull;
            if (noise_per_mille(pooled[lag][kinds[kind][0]], pooled[lag][kinds[kind][1]], pooled[0][kinds[kind][0]],
                                pooled[0][kinds[kind][1]], &per_mille))
            {
                printf(" %6llu", per_mille);
            }
            else
            {
                printf(" %6s", "-");
            }
        }
        printf("\n");
    }
    fflush(stdout);
}

static int noise_flicker_rows(FILE *table, const char *name, const unsigned long long sums[NOISE_FLICKER_CELLS])
{
    int ok = 1;
    for (unsigned int lag = 0u; ok && (lag < NOISE_FLICKER_LAGS); lag += 1u)
    {
        for (unsigned int level_bin = 0u; ok && (level_bin < NOISE_LEVEL_BINS); level_bin += 1u)
        {
            const unsigned long long *const cell = &sums[((lag * NOISE_LEVEL_BINS) + level_bin) * NOISE_FLICKER_SUMS];
            if ((cell[NOISE_FLICKER_PAIRS] == 0ull) && (cell[NOISE_FLICKER_NEIGHBOR_PAIRS] == 0ull))
            {
                continue;
            }
            const unsigned int lowest = level_bin << (NOISE_LEVEL_BIN_SHIFT - 1u);
            ok = fprintf(table, "%s\t%u\t%u\t%llu\t%llu\t%llu\t%llu\n", name, 1u << lag, lowest,
                         cell[NOISE_FLICKER_PAIRS], cell[NOISE_FLICKER_SQUARES], cell[NOISE_FLICKER_NEIGHBOR_PAIRS],
                         cell[NOISE_FLICKER_NEIGHBOR_SQUARES]) > 0;
        }
    }
    return ok;
}

extern "C" long noise_flicker_set(const NoiseSetRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return NOISE_DETECTOR_ERROR;
    }
    EngineError *const error = request->error;
    char path[ENGINE_PATH_CAPACITY];
    const int written =
        (request->set != NULL) ? snprintf(path, sizeof(path), "%s/noise_flicker.tsv", request->set) : -1;
    const int named = (written > 0) && ((size_t)written < sizeof(path));
    FILE *const table = named ? fopen(path, "wb") : NULL;
    int ok = NOISE_DETECTOR_CHECK(named && (request->samples != NULL) && (request->load != NULL), request, error,
                                  ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_IO(table != NULL, path, error) &&
             NOISE_DETECTOR_IO(fprintf(table, "sample\tlag\tlowest_mean\tpairs\tsquares\tneighbor_pairs"
                                              "\tneighbor_squares\n") > 0,
                               table, error);
    printf("  flicker: the structure function D(k), the mean square of I(t + k) - I(t), at lags 1 to 64, in bins of 8"
           " by the pair's mean\n");
    printf("  each lag's mean square against lag 1's, per mille (white noise holds 1000 at every lag):\n");
    printf("    %-29s", "lag");
    for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
    {
        printf(" %6u", 1u << lag);
    }
    printf("\n");
    unsigned long long *const sums =
        (unsigned long long *)malloc((size_t)NOISE_FLICKER_CELLS * sizeof(unsigned long long));
    ok = ok && NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE);
    const unsigned long long began = engine_clock_microseconds();
    for (unsigned int sample = 0u; ok && (sample < request->count); sample += 1u)
    {
        const char *const name = request->samples[sample];
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        unsigned short *volume = NULL;
        ok = NOISE_DETECTOR_CHECK(request->load(request->set, name, extent, &volume, error) == 0L, name, error,
                                  ENGINE_ERROR_REQUEST) &&
             (noise_flicker_sample(volume, extent, sums, error) == 0L);
        free(volume);
        ok = ok && NOISE_DETECTOR_IO(noise_flicker_rows(table, name, sums) != 0, table, error);
        if (ok != 0)
        {
            noise_flicker_summary(name, extent, sums);
        }
    }
    free(sums);
    if (table != NULL)
    {
        ok = NOISE_DETECTOR_IO(fclose(table) == 0, path, error) && ok;
    }
    if (ok != 0)
    {
        printf("  flicker: %u samples in %llu ms; every sum is in %s\n", request->count,
               (engine_clock_microseconds() - began) / 1000ull, path);
    }
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}
