// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_crosstalk.cu: crosstalk and charge
#include "noise_detector_internal.h"

// One thread a voxel. Along y and along x, where the voxel three steps on is inside the view, every frame pair's
// difference is squared and multiplied by the differences one, two and three steps on, each product's sign kept by
// summing the raised and lowered products apart.
__global__ static void noise_crosstalk_kernel(const unsigned short *lanes, unsigned long long frames,
                                              unsigned long long depth, unsigned long long height,
                                              unsigned long long width, unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_CROSSTALK_CELLS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_CROSSTALK_CELLS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long voxels = depth * height * width;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        const unsigned long long place[NOISE_CROSSTALK_AXES] = {(voxel / width) % height, voxel % width};
        const unsigned long long extent[NOISE_CROSSTALK_AXES] = {height, width};
        const unsigned long long stride[NOISE_CROSSTALK_AXES] = {width, 1ull};
        for (unsigned int axis = 0u; axis < NOISE_CROSSTALK_AXES; axis += 1u)
        {
            if ((place[axis] + NOISE_CROSSTALK_STEPS) >= extent[axis])
            {
                continue;
            }
            unsigned long long run[NOISE_CROSSTALK_SUMS];
            for (unsigned int sum = 0u; sum < NOISE_CROSSTALK_SUMS; sum += 1u)
            {
                run[sum] = 0ull;
            }
            for (unsigned long long frame = 0ull; (frame + 1ull) < frames; frame += 1ull)
            {
                const unsigned long long early = (frame * voxels) + voxel;
                const unsigned long long late = early + voxels;
                const long long moved = (long long)lanes[late] - (long long)lanes[early];
                run[0] += 1ull;
                // a square is never negative. It re-signs to unsigned long long exactly
                run[1] += (unsigned long long)(moved * moved);
                for (unsigned int step = 1u; step <= NOISE_CROSSTALK_STEPS; step += 1u)
                {
                    const unsigned long long apart = step * stride[axis];
                    const long long other = (long long)lanes[late + apart] - (long long)lanes[early + apart];
                    const long long product = moved * other;
                    // a product's magnitude re-signs to unsigned long long exactly
                    run[2u * step] += (product > 0ll) ? (unsigned long long)product : 0ull;
                    run[(2u * step) + 1u] += (product < 0ll) ? (unsigned long long)(-product) : 0ull;
                }
            }
            for (unsigned int sum = 0u; sum < NOISE_CROSSTALK_SUMS; sum += 1u)
            {
                if (run[sum] != 0ull)
                {
                    atomicAdd(&cells[(axis * NOISE_CROSSTALK_SUMS) + sum], run[sum]);
                }
            }
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_CROSSTALK_CELLS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

extern "C" long noise_crosstalk_volume(const unsigned short *volume, const unsigned long long extent[4],
                                       NoiseCrosstalkMeasurement *measurement, EngineError *error)
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
    // every sum is at most one sample's pairs times the widest product, 65535 squared
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_CROSSTALK_CELLS * sizeof(unsigned long long);
    unsigned long long sums[NOISE_CROSSTALK_CELLS];
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
        noise_crosstalk_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, extent[1], extent[2],
                                                                   extent[3], device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    if (ok == 0)
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseCrosstalkMeasurement read;
    int formed = 1;
    for (unsigned int axis = 0u; axis < NOISE_CROSSTALK_AXES; axis += 1u)
    {
        const unsigned long long *const cell = &sums[axis * NOISE_CROSSTALK_SUMS];
        read.pairs[axis] = cell[0];
        noise_exact_word(&read.squares[axis], cell[1]);
        for (unsigned int step = 0u; step < NOISE_CROSSTALK_STEPS; step += 1u)
        {
            AnchorExactInteger lowered;
            noise_exact_word(&read.steps[axis][step], cell[2u + (2u * step)]);
            noise_exact_word(&lowered, cell[3u + (2u * step)]);
            formed = formed && (anchor_exact_subtract(&read.steps[axis][step], &lowered, &read.steps[axis][step]) ==
                                ANCHOR_EXACT_OK);
        }
        // V = sum d'^2 - 2 C2
        AnchorExactInteger twice;
        formed = formed && (anchor_exact_add(&read.steps[axis][1], &read.steps[axis][1], &twice) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&read.squares[axis], &twice, &read.spread[axis]) == ANCHOR_EXACT_OK);
    }
    if (!NOISE_DETECTOR_CHECK(formed, &read, error, ENGINE_ERROR_RESOURCE))
    {
        return NOISE_DETECTOR_ERROR;
    }
    *measurement = read;
    return 0L;
}

// the charge pass's sums over one series: sum I over the voxel-frames, then sum d^2 over the frame differences
#define NOISE_CHARGE_SUMS 2u

// One thread a voxel: its frames summed, and its frame differences squared and summed.
__global__ static void noise_charge_kernel(const unsigned short *lanes, unsigned long long frames,
                                           unsigned long long voxels, unsigned long long *sums)
{
    __shared__ unsigned long long cells[NOISE_CHARGE_SUMS];
    for (unsigned int entry = threadIdx.x; entry < NOISE_CHARGE_SUMS; entry += blockDim.x)
    {
        cells[entry] = 0ull;
    }
    __syncthreads();
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long voxel = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; voxel < voxels;
         voxel += jump)
    {
        unsigned long long total = lanes[voxel];
        unsigned long long squares = 0ull;
        for (unsigned long long frame = 1ull; frame < frames; frame += 1ull)
        {
            const unsigned long long here = (frame * voxels) + voxel;
            const long long moved = (long long)lanes[here] - (long long)lanes[here - voxels];
            total += lanes[here];
            // a square is never negative. It re-signs to unsigned long long exactly
            squares += (unsigned long long)(moved * moved);
        }
        if (total != 0ull)
        {
            atomicAdd(&cells[0], total);
        }
        if (squares != 0ull)
        {
            atomicAdd(&cells[1], squares);
        }
    }
    __syncthreads();
    for (unsigned int entry = threadIdx.x; entry < NOISE_CHARGE_SUMS; entry += blockDim.x)
    {
        if (cells[entry] != 0ull)
        {
            atomicAdd(&sums[entry], cells[entry]);
        }
    }
}

// one series' two sums, read on the device
static long noise_charge_sample(const unsigned short *volume, unsigned long long frames, unsigned long long voxels,
                                unsigned long long sums[NOISE_CHARGE_SUMS], EngineError *error)
{
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t sum_bytes = (size_t)NOISE_CHARGE_SUMS * sizeof(unsigned long long);
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
        noise_charge_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(device_lanes, frames, voxels, device_sums);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, sum_bytes, cudaMemcpyDeviceToHost), sums, error);
    }
    cudaFree(device_lanes);
    cudaFree(device_sums);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_charge_series(const unsigned short *bias, const unsigned short *dark,
                                    const unsigned long long extent[4], NoiseChargeMeasurement *measurement,
                                    EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    if (!NOISE_DETECTOR_CHECK((bias != NULL) && (dark != NULL) && (extent != NULL) && (measurement != NULL), bias,
                              error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    // every sum is at most a series' voxel-frames times the widest square, 65535 squared, and twice the frame
    // differences is below 2^64 with it
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / (65535ull * 65535ull)));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    unsigned long long bias_sums[NOISE_CHARGE_SUMS];
    unsigned long long dark_sums[NOISE_CHARGE_SUMS];
    if ((noise_charge_sample(bias, frames, voxels, bias_sums, error) != 0L) ||
        (noise_charge_sample(dark, frames, voxels, dark_sums, error) != 0L))
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseChargeMeasurement read;
    memset(&read, 0, sizeof(read));
    AnchorExactInteger dark_total;
    AnchorExactInteger dark_squares;
    noise_exact_word(&read.offset, bias_sums[0]);
    noise_exact_word(&read.offset_denominator, frames * voxels);
    noise_exact_word(&read.level_free, bias_sums[1]);
    noise_exact_word(&read.level_free_denominator, 2ull * (frames - 1ull) * voxels);
    noise_exact_word(&dark_total, dark_sums[0]);
    noise_exact_word(&dark_squares, dark_sums[1]);
    read.dark_level_denominator = read.offset_denominator;
    read.dark_square_denominator = read.level_free_denominator;
    int formed = (anchor_exact_subtract(&dark_total, &read.offset, &read.dark_level) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&dark_squares, &read.level_free, &read.dark_square) == ANCHOR_EXACT_OK);
    // g = (Q_d - Q_b) M / (2 P (A_d - A_b)), turned to a positive denominator
    read.gain_read = formed && (read.dark_level.sign != 0);
    if (read.gain_read != 0)
    {
        formed = (anchor_exact_multiply(&read.dark_square, &read.offset_denominator, &read.gain) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&read.level_free_denominator, &read.dark_level, &read.gain_denominator) ==
                  ANCHOR_EXACT_OK);
        if (read.dark_level.sign < 0)
        {
            read.gain.sign = -read.gain.sign;
            read.gain_denominator.sign = -read.gain_denominator.sign;
        }
    }
    if (!NOISE_DETECTOR_CHECK(formed, &read, error, ENGINE_ERROR_RESOURCE))
    {
        return NOISE_DETECTOR_ERROR;
    }
    *measurement = read;
    return 0L;
}
