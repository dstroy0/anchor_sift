// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_structure.cu: structure
#include "noise_detector_internal.h"

// a 128 bit value times a factor, kept to 128 bits
__device__ static void noise_wide_scaled(unsigned long long low, unsigned long long high, unsigned long long factor,
                                         unsigned long long *scaled)
{
    scaled[0] = low * factor;
    scaled[1] = __umul64hi(low, factor) + (high * factor);
}

// One thread a voxel and its x neighbor: their totals over the frames give the pair's level bin, M and q, then at
// each lag the pair's frame pairs and their y summed, and the nine sums added to the lag and bin once.
__global__ static void noise_structure_kernel(const unsigned short *lanes, unsigned long long frames,
                                              unsigned long long voxels, unsigned long long width,
                                              unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_STRUCTURE_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_STRUCTURE_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        if (((voxel % width) + 1ull) >= width)
        {
            continue;
        }
        unsigned long long own = 0ull;
        unsigned long long beside = 0ull;
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            own += lanes[(frame * voxels) + voxel];
            beside += lanes[(frame * voxels) + voxel + 1ull];
        }
        // the pair's mean level is (own + beside) / (2 T), and its bin that over 8
        const unsigned long long level_bin = (own + beside) / (16ull * frames);
        if ((level_bin < NOISE_SUMMARY_FIRST_BIN) || (level_bin > NOISE_SUMMARY_LAST_BIN))
        {
            continue;
        }
        const unsigned long long apart = (own > beside) ? (own - beside) : (beside - own);
        // apart is at most 65535 T, below 2^32 for the frames the bound admits. Q fits one word; M is at most twice
        // that, and each product below is kept to 128 bits as its low and high words
        const unsigned long long along = apart * apart;
        const unsigned long long level = own + beside;
        const unsigned long long along_square[2] = {along * along, __umul64hi(along, along)};
        const unsigned long long level_square[2] = {level * level, __umul64hi(level, level)};
        const unsigned long long level_along[2] = {level * along, __umul64hi(level, along)};
        for (unsigned int lag = 0u; lag < NOISE_FLICKER_LAGS; lag += 1u)
        {
            const unsigned long long later = (1ull << lag) * voxels;
            unsigned long long count = 0ull;
            unsigned long long measured = 0ull;
            for (unsigned long long frame = 0ull; (frame + (1ull << lag)) < frames; frame += 1ull)
            {
                const unsigned long long early = (frame * voxels) + voxel;
                const long long moved = ((long long)lanes[early + later] - (long long)lanes[early]) -
                                        ((long long)lanes[early + later + 1ull] - (long long)lanes[early + 1ull]);
                count += 1ull;
                // a square is never negative. It re-signs to unsigned long long exactly
                measured += (unsigned long long)(moved * moved);
            }
            if (count == 0ull)
            {
                continue;
            }
            unsigned long long *const cell =
                &cells[((lag * NOISE_STRUCTURE_BINS) + (unsigned int)(level_bin - NOISE_SUMMARY_FIRST_BIN)) *
                       NOISE_STRUCTURE_WORDS];
            unsigned long long scaled[2];
            atomicAdd(&cell[NOISE_STRUCTURE_PAIRS], count);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_LEVEL], count * level, __umul64hi(count, level));
            noise_wide_scaled(level_square[0], level_square[1], count, scaled);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_LEVEL_SQUARE], scaled[0], scaled[1]);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_ALONG], count * along, __umul64hi(count, along));
            noise_wide_scaled(along_square[0], along_square[1], count, scaled);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_ALONG_SQUARE], scaled[0], scaled[1]);
            noise_wide_scaled(level_along[0], level_along[1], count, scaled);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_LEVEL_ALONG], scaled[0], scaled[1]);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_MEASURED], measured, 0ull);
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_LEVEL_MEASURED], level * measured, __umul64hi(level, measured));
            noise_wide_atomic_add(&cell[NOISE_STRUCTURE_CROSS], along * measured, __umul64hi(along, measured));
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < (NOISE_FLICKER_LAGS * NOISE_STRUCTURE_BINS); entry += blockDim.x)
    {
        const unsigned long long *const cell = &cells[entry * NOISE_STRUCTURE_WORDS];
        unsigned long long *const sum = &sums[entry * NOISE_STRUCTURE_WORDS];
        if (cell[NOISE_STRUCTURE_PAIRS] == 0ull)
        {
            continue;
        }
        atomicAdd(&sum[NOISE_STRUCTURE_PAIRS], cell[NOISE_STRUCTURE_PAIRS]);
        for (unsigned int word = NOISE_STRUCTURE_LEVEL; word < NOISE_STRUCTURE_WORDS; word += 2u)
        {
            noise_wide_atomic_add(&sum[word], cell[word], cell[word + 1u]);
        }
    }
}

// a 128 bit sum from its low and high words
void noise_exact_words(AnchorExactInteger *value, const unsigned long long *words)
{
    NoiseWide wide;
    wide.low = words[0];
    wide.high = words[1];
    noise_exact_wide(value, &wide);
}

// pooled gains a bin's centerd sum N sum u v - sum u sum v, exactly
static int noise_centerd_add(AnchorExactInteger *pooled, const AnchorExactInteger *count,
                             const AnchorExactInteger *first, const AnchorExactInteger *second,
                             const AnchorExactInteger *product)
{
    AnchorExactInteger term;
    return noise_exact_add_product(pooled, count, product) &&
           (anchor_exact_multiply(first, second, &term) == ANCHOR_EXACT_OK) &&
           (anchor_exact_subtract(pooled, &term, pooled) == ANCHOR_EXACT_OK);
}

extern "C" long noise_structure_volume(const unsigned short *volume, const unsigned long long extent[4],
                                       NoiseStructureMeasurement *measurement, EngineError *error)
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
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long width = extent[3];
    int bounded =
        (frames >= 2ull) && (frames <= 65536ull) && (width >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels));
    // every sum is at most the frame pairs times the widest q^2, (65535 T)^4, which must stay below 2^128; the
    // widest q y, (65535 T)^2 131070^2, is no wider for T of 2 or more
    AnchorExactInteger bound;
    AnchorExactInteger factor;
    noise_exact_word(&bound, frames * voxels);
    noise_exact_word(&factor, 65535ull * frames);
    for (unsigned int power = 0u; bounded && (power < 4u); power += 1u)
    {
        bounded = anchor_exact_multiply(&bound, &factor, &bound) == ANCHOR_EXACT_OK;
    }
    for (unsigned int limb = 4u; bounded && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        bounded = bound.limb[limb] == 0u;
    }
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_STRUCTURE_CELLS * sizeof(unsigned long long);
    unsigned long long *const sums = (unsigned long long *)malloc(sum_bytes);
    unsigned short *device_lanes = NULL;
    unsigned long long *device_sums = NULL;
    int ok = NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_sums, sum_bytes), &device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemset(device_sums, 0, sum_bytes), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice),
                                         device_lanes, error);
    if (ok != 0)
    {
        const unsigned long long needed = (voxels + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_structure_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, voxels, width, device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    if (ok == 0)
    {
        free(sums);
        return NOISE_DETECTOR_ERROR;
    }
    // the measurement's 28 exact integers are held off the stack
    NoiseStructureMeasurement *const read = (NoiseStructureMeasurement *)malloc(sizeof(NoiseStructureMeasurement));
    if (!NOISE_DETECTOR_CHECK(read != NULL, &read, error, ENGINE_ERROR_RESOURCE))
    {
        free(sums);
        return NOISE_DETECTOR_ERROR;
    }
    int formed = 1;
    // a bin's sums as exact integers: N, then M, M^2, q, q^2, M q, y, M y and q y
    AnchorExactInteger count;
    AnchorExactInteger level;
    AnchorExactInteger level_square;
    AnchorExactInteger along;
    AnchorExactInteger along_square;
    AnchorExactInteger level_along;
    AnchorExactInteger measured;
    AnchorExactInteger level_measured;
    AnchorExactInteger cross;
    // the centerd sums pooled over the bins: MM, QQ, MQ, MY and QY
    AnchorExactInteger centerd[NOISE_STRUCTURE_CENTERD];
    AnchorExactInteger term;
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
    AnchorExactInteger total_along;
    AnchorExactInteger total_measured;
    AnchorExactInteger scale;
    // D_a is per (L - L_x)^2 = q / T^2. The level scale is T^2
    noise_exact_word(&scale, frames * frames);
    for (unsigned int lag = 0u; formed && (lag < NOISE_FLICKER_LAGS); lag += 1u)
    {
        unsigned long long pairs = 0ull;
        for (unsigned int entry = 0u; entry < NOISE_STRUCTURE_CENTERD; entry += 1u)
        {
            anchor_exact_zero(&centerd[entry]);
        }
        anchor_exact_zero(&total_along);
        anchor_exact_zero(&total_measured);
        for (unsigned int level_bin = 0u; formed && (level_bin < NOISE_STRUCTURE_BINS); level_bin += 1u)
        {
            const unsigned long long *const cell =
                &sums[((lag * NOISE_STRUCTURE_BINS) + level_bin) * NOISE_STRUCTURE_WORDS];
            pairs += cell[NOISE_STRUCTURE_PAIRS];
            noise_exact_word(&count, cell[NOISE_STRUCTURE_PAIRS]);
            noise_exact_words(&level, &cell[NOISE_STRUCTURE_LEVEL]);
            noise_exact_words(&level_square, &cell[NOISE_STRUCTURE_LEVEL_SQUARE]);
            noise_exact_words(&along, &cell[NOISE_STRUCTURE_ALONG]);
            noise_exact_words(&along_square, &cell[NOISE_STRUCTURE_ALONG_SQUARE]);
            noise_exact_words(&level_along, &cell[NOISE_STRUCTURE_LEVEL_ALONG]);
            noise_exact_words(&measured, &cell[NOISE_STRUCTURE_MEASURED]);
            noise_exact_words(&level_measured, &cell[NOISE_STRUCTURE_LEVEL_MEASURED]);
            noise_exact_words(&cross, &cell[NOISE_STRUCTURE_CROSS]);
            formed = noise_centerd_add(&centerd[0], &count, &level, &level, &level_square) &&
                     noise_centerd_add(&centerd[1], &count, &along, &along, &along_square) &&
                     noise_centerd_add(&centerd[2], &count, &level, &along, &level_along) &&
                     noise_centerd_add(&centerd[3], &count, &level, &measured, &level_measured) &&
                     noise_centerd_add(&centerd[4], &count, &along, &measured, &cross) &&
                     (anchor_exact_add(&total_along, &along, &total_along) == ANCHOR_EXACT_OK) &&
                     (anchor_exact_add(&total_measured, &measured, &total_measured) == ANCHOR_EXACT_OK);
        }
        // q's slope with M held: Num = MM QY - MQ MY over Den = MM QQ - MQ^2
        formed = formed && (anchor_exact_multiply(&centerd[0], &centerd[1], &denominator) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&centerd[2], &centerd[2], &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&denominator, &term, &denominator) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&centerd[0], &centerd[4], &numerator) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&centerd[2], &centerd[3], &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&numerator, &term, &numerator) == ANCHOR_EXACT_OK);
        if (formed == 0)
        {
            break;
        }
        read->pairs[lag] = pairs;
        // the pooled centerd sums are the entries of a Gram matrix. MM QQ - MQ^2 is never negative, and it is 0
        // only where every bin's centerd q is one multiple of its centerd M
        read->read[lag] = denominator.sign > 0;
        anchor_exact_zero(&read->slope[lag]);
        anchor_exact_zero(&read->slope_denominator[lag]);
        anchor_exact_zero(&read->intercept[lag]);
        anchor_exact_zero(&read->intercept_denominator[lag]);
        if (read->read[lag] == 0)
        {
            continue;
        }
        // the intercept in q's units: (sum Y Den - Num sum A) / (sum N Den)
        noise_exact_word(&count, pairs);
        formed = (anchor_exact_multiply(&numerator, &scale, &read->slope[lag]) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&total_measured, &denominator, &read->intercept[lag]) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&numerator, &total_along, &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&read->intercept[lag], &term, &read->intercept[lag]) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&count, &denominator, &read->intercept_denominator[lag]) == ANCHOR_EXACT_OK);
        read->slope_denominator[lag] = denominator;
    }
    free(sums);
    if (!NOISE_DETECTOR_CHECK(formed, read, error, ENGINE_ERROR_RESOURCE))
    {
        free(read);
        return NOISE_DETECTOR_ERROR;
    }
    *measurement = *read;
    free(read);
    return 0L;
}
