/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_agreement.cu
 * @brief The exact agreement count on a CUDA device, one position per thread.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note There is no arbitrary precision integer here and there does not need to be. A fixed width
 *       limb array is a representation of the same value, and a device register file holds one as
 *       readily as a host register does. Fixed width is the only bound, it is declared, and a value
 *       that will not fit is refused on the host before anything is copied.
 * @note The device arithmetic is the host arithmetic transcribed. It is not shared source, because
 *       __device__ qualification has to sit on every function, and that means the two can drift.
 *       bench_exact_gpu.cu exists to catch it: every count the device returns is compared against
 *       the count the portable host arm returns on the same data.
 * @note Positions arrive already sorted, which is what lets each thread run a binary search with no
 *       coordination. Threads share nothing and write one atomic increment each at most.
 */

#include "exact_arm.h"
#include "exact_gpu.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <string.h>

/** @brief Threads per block. 256 suits every device this is built for and needs no tuning here. */
#define ANCHOR_GPU_BLOCK 256u

/**
 * @brief Orders two magnitudes on the device, ignoring sign.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1, 0 or 1.
 * @note Walks from the top limb down, the same direction the host walks, because the first limb
 *       that differs settles the order and a scaled value carries its information in the high limbs.
 */
__device__ static int device_magnitude_compare(const unsigned int *left, const unsigned int *right)
{
    for (int at = (int)ANCHOR_EXACT_LIMBS - 1; at >= 0; at--)
    {
        if (left[at] != right[at])
        {
            return (left[at] < right[at]) ? -1 : 1;
        }
    }
    return 0;
}

/**
 * @brief Orders two integers on the device, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0, matching anchor_exact_compare on the host.
 */
__device__ static int device_compare(const AnchorExactInteger *left,
                                     const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = device_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Whether a magnitude is entirely zero, on the device.
 *
 * @param[in] value Magnitude [BORROWS].
 * @return          1 where every limb is zero, 0 otherwise.
 */
__device__ static int device_magnitude_is_zero(const unsigned int *value)
{
    for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at++)
    {
        if (value[at] != 0u)
        {
            return 0;
        }
    }
    return 1;
}

/**
 * @brief Adds two magnitudes on the device.
 *
 * @param[in]  left   First magnitude [BORROWS].
 * @param[in]  right  Second magnitude [BORROWS].
 * @param[out] result Sum [BORROWS].
 * @return            1 where a carry ran off the top limb, 0 otherwise.
 */
__device__ static int device_magnitude_add(const unsigned int *left, const unsigned int *right,
                                           unsigned int *result)
{
    unsigned long long carry = 0ull;
    for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at++)
    {
        const unsigned long long total =
            (unsigned long long)left[at] + (unsigned long long)right[at] + carry;
        // Explicit narrowing to a limb. The high half is the carry and is kept, not discarded.
        result[at] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32;
    }
    return (carry != 0ull) ? 1 : 0;
}

/**
 * @brief Subtracts the smaller magnitude from the larger, which the caller has already ordered.
 *
 * @param[in]  left   Magnitude to subtract from, no smaller than right [BORROWS].
 * @param[in]  right  Magnitude to subtract [BORROWS].
 * @param[out] result Difference [BORROWS].
 */
__device__ static void device_magnitude_subtract(const unsigned int *left,
                                                 const unsigned int *right, unsigned int *result)
{
    unsigned long long borrow = 0ull;
    for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at++)
    {
        // The base keeps the arithmetic non negative before the narrowing, so no unsigned wrap has
        // to be reasoned about at the point the limb is stored.
        const unsigned long long total = (1ull << 32) + (unsigned long long)left[at]
                                         - (unsigned long long)right[at] - borrow;
        result[at] = (unsigned int)(total & 0xFFFFFFFFull);
        borrow = (total < (1ull << 32)) ? 1ull : 0ull;
    }
}

/**
 * @brief Adds two integers on the device, sign included.
 *
 * @param[in]  left   First addend [BORROWS].
 * @param[in]  right  Second addend [BORROWS].
 * @param[out] result Sum [BORROWS].
 * @return            1 where the sum fits the fixed width, 0 where it does not.
 */
__device__ static int device_add(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                 AnchorExactInteger *result)
{
    if (left->sign == 0)
    {
        *result = *right;
        return 1;
    }
    if (right->sign == 0)
    {
        *result = *left;
        return 1;
    }

    if (left->sign == right->sign)
    {
        if (device_magnitude_add(left->limb, right->limb, result->limb) != 0)
        {
            return 0;
        }
        result->sign = device_magnitude_is_zero(result->limb) ? 0 : left->sign;
        return 1;
    }

    const int order = device_magnitude_compare(left->limb, right->limb);
    if (order == 0)
    {
        for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at++)
        {
            result->limb[at] = 0u;
        }
        result->sign = 0;
        return 1;
    }
    if (order > 0)
    {
        device_magnitude_subtract(left->limb, right->limb, result->limb);
        result->sign = device_magnitude_is_zero(result->limb) ? 0 : left->sign;
    }
    else
    {
        device_magnitude_subtract(right->limb, left->limb, result->limb);
        result->sign = device_magnitude_is_zero(result->limb) ? 0 : right->sign;
    }
    return 1;
}

/**
 * @brief One thread per position: displace it by the lag and look for where it landed.
 *
 * @param[in]     positions Positions, ascending [BORROWS].
 * @param[in]     values    The value standing at each position [BORROWS].
 * @param[in]     count     How many positions.
 * @param[in]     lag       The offset to test [BORROWS].
 * @param[in,out] agreed    Where the count is accumulated [BORROWS].
 * @note A thread whose displaced position overruns the fixed width contributes nothing, matching
 *       the host, which skips that position rather than reporting a wrapped one.
 */
__global__ static void agreement_kernel(const AnchorExactInteger *positions,
                                        const unsigned long long *values, size_t count,
                                        const AnchorExactInteger *lag, unsigned int *agreed)
{
    const size_t at = (size_t)blockIdx.x * (size_t)blockDim.x + (size_t)threadIdx.x;
    if (at >= count)
    {
        return;
    }

    AnchorExactInteger moved;
    if (device_add(&positions[at], lag, &moved) == 0)
    {
        return;
    }

    size_t low = 0u;
    size_t high = count;
    size_t found = count;
    while (low < high)
    {
        const size_t middle = low + ((high - low) / 2u);
        const int order = device_compare(&positions[middle], &moved);
        if (order == 0)
        {
            found = middle;
            break;
        }
        if (order < 0)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }

    if ((found < count) && (values[found] == values[at]))
    {
        atomicAdd(agreed, 1u);
    }
}

extern "C" int anchor_exact_cuda_available(void)
{
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess)
    {
        return 0;
    }
    return (devices > 0) ? 1 : 0;
}

extern "C" int anchor_exact_cuda_describe(char *text, size_t room)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices <= 0))
    {
        return 0;
    }
    cudaDeviceProp held;
    if (cudaGetDeviceProperties(&held, 0) != cudaSuccess)
    {
        return 0;
    }
    (void)snprintf(text, room, "%s, compute %d.%d, %d SMs", held.name, held.major, held.minor,
                   held.multiProcessorCount);
    return 1;
}

extern "C" size_t anchor_exact_agreement_cuda(const AnchorExactInteger *positions,
                                              const uint64_t *values, size_t count,
                                              const AnchorExactInteger *lag)
{
    if (count == 0u)
    {
        return 0u;
    }

    AnchorExactInteger *device_positions = NULL;
    unsigned long long *device_values = NULL;
    AnchorExactInteger *device_lag = NULL;
    unsigned int *device_agreed = NULL;
    size_t answer = (size_t)-1;

    const size_t position_bytes = count * sizeof(AnchorExactInteger);
    const size_t value_bytes = count * sizeof(unsigned long long);

    if ((cudaMalloc((void **)&device_positions, position_bytes) != cudaSuccess)
        || (cudaMalloc((void **)&device_values, value_bytes) != cudaSuccess)
        || (cudaMalloc((void **)&device_lag, sizeof(AnchorExactInteger)) != cudaSuccess)
        || (cudaMalloc((void **)&device_agreed, sizeof(unsigned int)) != cudaSuccess))
    {
        goto done;
    }

    if ((cudaMemcpy(device_positions, positions, position_bytes, cudaMemcpyHostToDevice)
         != cudaSuccess)
        || (cudaMemcpy(device_values, values, value_bytes, cudaMemcpyHostToDevice) != cudaSuccess)
        || (cudaMemcpy(device_lag, lag, sizeof(AnchorExactInteger), cudaMemcpyHostToDevice)
            != cudaSuccess)
        || (cudaMemset(device_agreed, 0, sizeof(unsigned int)) != cudaSuccess))
    {
        goto done;
    }

    {
        const unsigned int blocks =
            (unsigned int)((count + (size_t)ANCHOR_GPU_BLOCK - 1u) / (size_t)ANCHOR_GPU_BLOCK);
        agreement_kernel<<<blocks, ANCHOR_GPU_BLOCK>>>(device_positions, device_values, count,
                                                       device_lag, device_agreed);
        if ((cudaGetLastError() != cudaSuccess) || (cudaDeviceSynchronize() != cudaSuccess))
        {
            goto done;
        }
    }

    {
        unsigned int held = 0u;
        if (cudaMemcpy(&held, device_agreed, sizeof(unsigned int), cudaMemcpyDeviceToHost)
            != cudaSuccess)
        {
            goto done;
        }
        answer = (size_t)held;
    }

done:
    cudaFree(device_positions);
    cudaFree(device_values);
    cudaFree(device_lag);
    cudaFree(device_agreed);
    return answer;
}

/**
 * @brief The agreement count, as the arm table expects it.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              The count, or the portable count where the device refused the work.
 * @note A refusal falls back to the host instead of returning a sentinel into a table of counts.
 *       A driver comparing arms would otherwise read the sentinel as a disagreement and blame the
 *       arithmetic for what was an allocation failure.
 */
static size_t arm_agreement(const AnchorExactInteger *positions, const uint64_t *values,
                            size_t count, const AnchorExactInteger *lag)
{
    const size_t held = anchor_exact_agreement_cuda(positions, values, count, lag);
    if (held == (size_t)-1)
    {
        return anchor_exact_agreement(positions, values, count, lag);
    }
    return held;
}

/**
 * @brief The arm as a driver sees it. Static storage, so returning its address is safe.
 *
 * @note equal and compare are the portable ones on purpose. One comparison is far too small to be
 *       worth a bus crossing, and only the whole sweep is handed to the device.
 */
static const AnchorExactArm CUDA_ARM = {
    "cuda",
    anchor_exact_equal,
    anchor_exact_compare,
    arm_agreement,
};

extern "C" const AnchorExactArm *anchor_exact_cuda_arm(void)
{
    return anchor_exact_cuda_available() ? &CUDA_ARM : NULL;
}
