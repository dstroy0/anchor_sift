/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_cuda.cu
 * @brief The steering scan on a CUDA device, one alignment per thread over the whole object.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE SAME QUESTION EVERY SCAN ARM ANSWERS, MAPPED OVER THE DEVICE. Held at one needle offset, count
 * the alignments still standing whose corpus byte equals the needle byte. The vector arms widen one
 * compare; this one gives one alignment to each thread and adds a one where that alignment agrees and
 * stands. The reduction is a single atomic increment per agreeing thread, which is what the exact
 * device arm does and needs no tuning at this size.
 *
 * WHAT THIS ARM IS NOT ALLOWED TO DO. It returns the portable arm's count or it has a defect. The
 * value is an integer count of alignments and the two arms agree exactly or one is wrong. That is
 * the contract AnchorSteerEngine carries, the same one the exact arms carry in no_rounding.
 *
 * @note NOT SHARED SOURCE WITH THE HOST ARMS. A device function carries __global__ or __device__ on
 *       every declaration. The kernel cannot be the portable loop compiled twice, and the two can
 *       drift. The GPU build grades every count this arm returns against the portable host arm on
 *       the same data, which is what catches a drift.
 * @note THE WHOLE OBJECT CROSSES THE BUS PER CALL. The corpus and the survivor vector are copied to
 *       the device. This arm pays a transfer a host arm does not. It wins only where the object is
 *       large enough to amortize that,  it is graded and timed.
 * @note A device refusal falls back to a host count instead of returning a sentinel into a table of
 *       counts, matching arm_cuda.cu. A driver comparing arms would otherwise read the sentinel as a
 *       disagreement and blame the scan for what was an allocation failure.
 */

#include "anchor_sift.h"

#include <cuda_runtime.h>

#include <stdio.h>

/** @brief Threads per block. 256 suits every device this is built for and needs no tuning here. */
#define ANCHOR_STEER_GPU_BLOCK 256u

/**
 * @brief One thread per alignment: add one where it stands and its corpus byte is the wanted one.
 *
 * @param[in]     corpus     Bytes under examination [BORROWS].
 * @param[in]     alignments How many alignments the object has.
 * @param[in]     alive      One flag per alignment, non-zero where still standing [BORROWS].
 * @param[in]     wanted     The needle byte being tested.
 * @param[in]     offset     Needle offset the probe sits at.
 * @param[in,out] standing   Where the count is accumulated [BORROWS].
 */
__global__ static void scan_kernel(const unsigned char *corpus, size_t alignments,
                                   const unsigned char *alive, unsigned char wanted, size_t offset,
                                   unsigned int *standing)
{
    const size_t at = (size_t)blockIdx.x * (size_t)blockDim.x + (size_t)threadIdx.x;
    if (at >= alignments)
    {
        return;
    }
    if (alive[at] == 0u)
    {
        return;
    }
    if (corpus[at + offset] == wanted)
    {
        atomicAdd(standing, 1u);
    }
}

extern "C" int anchor_steer_cuda_available(void)
{
    int devices = 0;
    if (cudaGetDeviceCount(&devices) != cudaSuccess)
    {
        return 0;
    }
    return (devices > 0) ? 1 : 0;
}

extern "C" int anchor_steer_cuda_describe(char *text, size_t room)
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

/**
 * @brief Counts on the host, without touching the scan counters, for the device fallback.
 *
 * @note anchor_steer_truthy_after_cuda has already counted the call. The fallback must not reach
 *       anchor_steer_truthy_after_portable, which would count it a second time. The loop is the same
 *       one the portable arm runs.
 */
static size_t scan_host_fallback(const unsigned char *corpus, size_t alignments,
                                 const unsigned char *alive, unsigned char wanted, size_t offset)
{
    size_t standing = 0u;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] == wanted)
        {
            standing += 1u;
        }
    }
    return standing;
}

extern "C" size_t anchor_steer_truthy_after_cuda(const uint8_t *corpus, size_t alignments,
                                                 const uint8_t *alive, uint8_t wanted, size_t offset)
{
    /* Counted before the argument check. A caller passing nothing still records that this arm was
     * the one asked. The claim the counters carry is which arm RAN and not what it returned. */
    anchor_steer_scan_calls += 1u;
    anchor_steer_wide_calls += 1u;

    if ((corpus == NULL) || (alive == NULL) || (alignments == 0u))
    {
        return 0u;
    }

    const unsigned char *host_corpus = (const unsigned char *)corpus;
    const unsigned char *host_alive = (const unsigned char *)alive;
    const size_t corpus_bytes = alignments + offset;

    unsigned char *device_corpus = NULL;
    unsigned char *device_alive = NULL;
    unsigned int *device_standing = NULL;
    size_t answer = (size_t)-1;

    if ((cudaMalloc((void **)&device_corpus, corpus_bytes) != cudaSuccess) || (cudaMalloc((void **)&device_alive, alignments) != cudaSuccess) || (cudaMalloc((void **)&device_standing, sizeof(unsigned int)) != cudaSuccess))
    {
        goto done;
    }

    if ((cudaMemcpy(device_corpus, host_corpus, corpus_bytes, cudaMemcpyHostToDevice) != cudaSuccess) || (cudaMemcpy(device_alive, host_alive, alignments, cudaMemcpyHostToDevice) != cudaSuccess) || (cudaMemset(device_standing, 0, sizeof(unsigned int)) != cudaSuccess))
    {
        goto done;
    }

    {
        const unsigned int blocks = (unsigned int)((alignments + (size_t)ANCHOR_STEER_GPU_BLOCK - 1u) / (size_t)ANCHOR_STEER_GPU_BLOCK);
        scan_kernel<<<blocks, ANCHOR_STEER_GPU_BLOCK>>>(device_corpus, alignments, device_alive,
                                                        (unsigned char)wanted, offset,
                                                        device_standing);
        if ((cudaGetLastError() != cudaSuccess) || (cudaDeviceSynchronize() != cudaSuccess))
        {
            goto done;
        }
    }

    {
        unsigned int held = 0u;
        if (cudaMemcpy(&held, device_standing, sizeof(unsigned int), cudaMemcpyDeviceToHost) != cudaSuccess)
        {
            goto done;
        }
        answer = (size_t)held;
    }

done:
    cudaFree(device_corpus);
    cudaFree(device_alive);
    cudaFree(device_standing);

    if (answer == (size_t)-1)
    {
        return scan_host_fallback(host_corpus, alignments, host_alive, (unsigned char)wanted, offset);
    }
    return answer;
}

extern "C" const AnchorSteerEngine *anchor_steer_cuda_engine(void)
{
    static const AnchorSteerEngine engine = {"cuda", anchor_steer_truthy_after_cuda};

    return anchor_steer_cuda_available() ? &engine : NULL;
}
