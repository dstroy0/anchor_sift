// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_halves.cu: halves
#include "noise_detector_internal.h"

// One thread a camera pixel: its values in the planes below the middle and in those from it up, each summed over the
// frames.
__global__ static void noise_halves_kernel(const unsigned short *lanes, unsigned long long frames,
                                           unsigned long long depth, unsigned long long pixels,
                                           unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_HALVES_SUMS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_HALVES_SUMS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long voxels = depth * pixels;
    const unsigned long long middle = depth / 2ull;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long pixel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; pixel < pixels;
         pixel += jump)
    {
        unsigned long long lower = 0ull;
        unsigned long long upper = 0ull;
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            for (unsigned long long z = 0ull; z < depth; z += 1ull)
            {
                const unsigned long long value = lanes[(frame * voxels) + (z * pixels) + pixel];
                lower += (z < middle) ? value : 0ull;
                upper += (z < middle) ? 0ull : value;
            }
        }
        atomicAdd(&cells[NOISE_HALVES_LOWER], lower);
        atomicAdd(&cells[NOISE_HALVES_UPPER], upper);
        noise_wide_atomic_add(&cells[NOISE_HALVES_PRODUCT], lower * upper, __umul64hi(lower, upper));
    }
    __syncthreads();
    if (threadIdx.x == 0u)
    {
        atomicAdd(&sums[NOISE_HALVES_LOWER], cells[NOISE_HALVES_LOWER]);
        atomicAdd(&sums[NOISE_HALVES_UPPER], cells[NOISE_HALVES_UPPER]);
        noise_wide_atomic_add(&sums[NOISE_HALVES_PRODUCT], cells[NOISE_HALVES_PRODUCT],
                              cells[NOISE_HALVES_PRODUCT + 1u]);
    }
}

extern "C" long noise_halves_volume(const unsigned short *volume, const unsigned long long extent[4],
                                    NoiseHalvesMeasurement *measurement, EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    if (!NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (measurement != NULL), volume, error,
                              ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long pixels = extent[2] * extent[3];
    const unsigned long long voxels = depth * pixels;
    // sum lo and sum hi are at most the voxel-frames times 65535, below 2^64; sum lo hi is at most that times one
    // pixel's frames and planes times 65535, below 2^128 with it
    const int bounded = (depth >= 2ull) && (frames != 0ull) && (pixels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / 65535ull));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_HALVES_SUMS * sizeof(unsigned long long);
    unsigned long long sums[NOISE_HALVES_SUMS];
    unsigned short *device_lanes = NULL;
    unsigned long long *device_sums = NULL;
    int ok = NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_sums, sum_bytes), &device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemset(device_sums, 0, sum_bytes), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice),
                                         device_lanes, error);
    if (ok != 0)
    {
        const unsigned long long needed = (pixels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_halves_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, depth, pixels, device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    if (ok == 0)
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseHalvesMeasurement read;
    AnchorExactInteger lower;
    AnchorExactInteger upper;
    AnchorExactInteger count;
    AnchorExactInteger term;
    noise_exact_word(&lower, sums[NOISE_HALVES_LOWER]);
    noise_exact_word(&upper, sums[NOISE_HALVES_UPPER]);
    noise_exact_words(&read.covariance, &sums[NOISE_HALVES_PRODUCT]);
    noise_exact_word(&count, pixels);
    // P sum lo hi - sum lo sum hi over P^2 n_lo n_hi, then sum (lo + hi) over P T Z
    const unsigned long long middle = depth / 2ull;
    int formed = (anchor_exact_multiply(&read.covariance, &count, &read.covariance) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&lower, &upper, &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&read.covariance, &term, &read.covariance) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&count, &count, &read.covariance_denominator) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_add(&lower, &upper, &read.level) == ANCHOR_EXACT_OK);
    noise_exact_word(&term, frames * middle);
    formed = formed && (anchor_exact_multiply(&read.covariance_denominator, &term, &read.covariance_denominator) ==
                        ANCHOR_EXACT_OK);
    noise_exact_word(&term, frames * (depth - middle));
    formed = formed && (anchor_exact_multiply(&read.covariance_denominator, &term, &read.covariance_denominator) ==
                        ANCHOR_EXACT_OK);
    noise_exact_word(&term, frames * depth);
    formed = formed && (anchor_exact_multiply(&count, &term, &read.level_denominator) == ANCHOR_EXACT_OK);
    if (!NOISE_DETECTOR_CHECK(formed, &read, error, ENGINE_ERROR_RESOURCE))
    {
        return NOISE_DETECTOR_ERROR;
    }
    *measurement = read;
    return 0L;
}

extern "C" long noise_flicker_volume(const unsigned short *volume, const unsigned long long extent[4],
                                     unsigned long long per_mille[NOISE_FLICKER_LAGS],
                                     unsigned long long neighbor_per_mille[NOISE_FLICKER_LAGS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    unsigned long long *const sums =
        (unsigned long long *)malloc((size_t)NOISE_FLICKER_CELLS * sizeof(unsigned long long));
    int ok = NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (per_mille != NULL) &&
                                      (neighbor_per_mille != NULL),
                                  volume, error, ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE) &&
             (noise_flicker_sample(volume, extent, sums, error) == 0L);
    if (ok != 0)
    {
        unsigned long long pooled[NOISE_FLICKER_LAGS][NOISE_FLICKER_SUMS];
        noise_flicker_pooled(sums, pooled);
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            if (noise_per_mille(pooled[lag][NOISE_FLICKER_SQUARES], pooled[lag][NOISE_FLICKER_PAIRS],
                                pooled[0][NOISE_FLICKER_SQUARES], pooled[0][NOISE_FLICKER_PAIRS], &per_mille[lag]) == 0)
            {
                per_mille[lag] = 0ull;
            }
            if (noise_per_mille(pooled[lag][NOISE_FLICKER_NEIGHBOR_SQUARES], pooled[lag][NOISE_FLICKER_NEIGHBOR_PAIRS],
                                pooled[0][NOISE_FLICKER_NEIGHBOR_SQUARES], pooled[0][NOISE_FLICKER_NEIGHBOR_PAIRS],
                                &neighbor_per_mille[lag]) == 0)
            {
                neighbor_per_mille[lag] = 0ull;
            }
        }
    }
    free(sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_lines_volume(const unsigned short *volume, const unsigned long long extent[4],
                                   long long readings[NOISE_PLANE_READINGS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseLineCell *const cells = (NoiseLineCell *)malloc((size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    // four exact integers, held apart from the stack
    NoisePlanePool *const pool = (NoisePlanePool *)malloc(sizeof(NoisePlanePool));
    NoiseStaticPool still;
    // a volume read alone writes no plane table and so needs no name
    int ok = NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (readings != NULL), volume, error,
                                  ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_CHECK((cells != NULL) && (pool != NULL), &cells, error, ENGINE_ERROR_RESOURCE) &&
             (noise_lines_sample(volume, extent, cells, pool, &still, NULL, NULL, error) == 0L);
    if (ok != 0)
    {
        int valid[NOISE_PLANE_READINGS];
        noise_planes_readings(pool, readings, valid);
        noise_static_readings(&still, &readings[NOISE_STATIC_ROWS], &valid[NOISE_STATIC_ROWS]);
    }
    free(cells);
    free(pool);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_neighbors_volume(const unsigned short *volume, const unsigned long long extent[4],
                                       long long per_mille[NOISE_NEIGHBOR_RADII], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    unsigned long long *const sums =
        (unsigned long long *)malloc((size_t)NOISE_NEIGHBORS_CELLS * sizeof(unsigned long long));
    int ok = NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (per_mille != NULL), volume, error,
                                  ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE) &&
             (noise_neighbors_sample(volume, extent, sums, error) == 0L);
    for (unsigned int radius = 0u; ok && (radius < NOISE_NEIGHBOR_RADII); radius += 1u)
    {
        // each radius's sums pooled over the summary's level bins, means 40 to 199
        unsigned long long pooled[NOISE_NEIGHBORS_SUMS];
        memset(pooled, 0, sizeof(pooled));
        for (unsigned int level_bin = NOISE_SUMMARY_FIRST_BIN; level_bin <= NOISE_SUMMARY_LAST_BIN; level_bin += 1u)
        {
            for (unsigned int sum = 0u; sum < NOISE_NEIGHBORS_SUMS; sum += 1u)
            {
                pooled[sum] += sums[(((radius * NOISE_LEVEL_BINS) + level_bin) * NOISE_NEIGHBORS_SUMS) + sum];
            }
        }
        if (noise_neighbors_per_mille(pooled, &per_mille[radius]) == 0)
        {
            per_mille[radius] = 0ll;
        }
    }
    free(sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_clips_volume(const unsigned short *volume, const unsigned long long extent[4],
                                   unsigned long long counts[NOISE_CLIPS_COUNTS], unsigned int box[NOISE_CLIPS_BOX],
                                   unsigned long long spikes[NOISE_SPIKE_SUMS], EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseClips *const clips = (NoiseClips *)malloc(sizeof(NoiseClips));
    int ok = NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (counts != NULL) && (box != NULL) &&
                                      (spikes != NULL),
                                  volume, error, ENGINE_ERROR_REQUEST) &&
             NOISE_DETECTOR_CHECK(clips != NULL, &clips, error, ENGINE_ERROR_RESOURCE) &&
             (noise_clips_sample(volume, extent, clips, error) == 0L);
    if (ok != 0)
    {
        memcpy(counts, clips->counts, sizeof(clips->counts));
        memcpy(box, clips->box, sizeof(clips->box));
        noise_spikes_pooled(clips, spikes);
    }
    free(clips);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

// one bit an axis of a box, frames (0), z, y and x (3)
#define NOISE_ROOT_AXIS(axis_) (1u << (axis_))

// the axes each term's value is shared along
static const unsigned int NOISE_ROOT_SHARED[NOISE_ROOT_TERMS] = {
    NOISE_ROOT_AXIS(3u), NOISE_ROOT_AXIS(2u), NOISE_ROOT_AXIS(2u) | NOISE_ROOT_AXIS(3u),
    NOISE_ROOT_AXIS(0u) | NOISE_ROOT_AXIS(1u), NOISE_ROOT_AXIS(1u)};

extern "C" void noise_root_extent(unsigned int term, const unsigned long long box[4], unsigned long long pattern[4])
{
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        const int kept = (term < NOISE_ROOT_TERMS) && ((NOISE_ROOT_SHARED[term] & NOISE_ROOT_AXIS(axis)) == 0u);
        pattern[axis] = (kept != 0) ? box[axis] : 1ull;
    }
}
