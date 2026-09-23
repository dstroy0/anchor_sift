/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_renyi_cuda.h
 * @brief The counting half of the Renyi enumeration, moved to the device.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Only the counting moves. Every statistic, every prediction, every control and every piece
 *       of reporting stays in bench_renyi.cpp and is computed exactly once, because failure mode
 *       fifteen in docs/failure-modes.md is a formula written twice and it has already put two
 *       wrong numbers in this bench's own headline table. A device that filled in its own
 *       histograms and then computed its own deficits would be that mode by construction.
 * @note So the contract here is narrow: hand it a job and a domain, get back the same three
 *       histograms the host threads would have produced, bit for bit. Agreement with the host at a
 *       small domain is the acceptance test and it is exact and not statistical, because both
 *       arms enumerate the same nonces and count the same events.
 * @note The host machine runs a desktop. Enumerating 2^32 nonces on it takes tens of minutes of
 *       twelve threads and a four gigabyte working set; on the device it is seconds and the host
 *       stays idle. This file exists for that, more than for the speed itself.
 */

#ifndef BENCH_RENYI_CUDA_H
#define BENCH_RENYI_CUDA_H

#ifdef __cplusplus
extern "C"
{
#endif

#include <stddef.h>
#include <stdint.h>

    /** @brief The midstate and header tail a nonce is hashed against, as the device needs them. */
    typedef struct
    {
        uint32_t midstate[8];      /**< Chaining value after header bytes 0 through 63. */
        uint32_t merkle_root_tail; /**< Header bytes 64 through 67, big-endian. */
        uint32_t ntime;            /**< Header bytes 68 through 71, big-endian. */
        uint32_t nbits;            /**< Header bytes 72 through 75, big-endian. */
    } RenyiCudaJob;

    /**
     * @brief Reports whether a usable device is present.
     *
     * @param[out] text      Where a one-line description is written, or null [BORROWS].
     * @param[in]  text_size Bytes available at text.
     * @return               Nonzero where the device can be used.
     */
    int renyi_cuda_available(char *text, size_t text_size);

    /**
     * @brief Enumerates a nonce range on the device and fills the same histograms the host would.
     *
     * @param[in]     job          Midstate and header tail [BORROWS].
     * @param[in]     source       0 for SHA256d, 1 for a fixed digest, 2 for the nonce repeated,
     *                             3 for a splitmix64 chain. Same numbering as the host enum.
     * @param[in]     domain       How many nonces, enumerated from zero.
     * @param[in]     phase        Bit offset every window starts at.
     * @param[in,out] byte_window  32 by 256 counters, added to [BORROWS].
     * @param[in,out] word_window  16 by 65536 counters, added to [BORROWS].
     * @param[in,out] leading_zero 257 counters, added to [BORROWS].
     * @param[in,out] wide_window  2^32 bytes of preimage counts, or null to skip [BORROWS].
     * @return                     Nonzero on success.
     * @note Counters are added to and not overwritten, matching the host, and a caller may
     *       accumulate several calls into one set.
     * @warning wide_window costs four gigabytes on the device and four on the host. Where the
     *          device cannot allocate it the call fails instead of silently skipping it, since a
     *          silently skipped family reads as an absent one.
     */
    int renyi_cuda_count(const RenyiCudaJob *job, int source, uint64_t domain, unsigned phase,
                         uint64_t *byte_window, uint64_t *word_window, uint64_t *leading_zero,
                         unsigned char *wide_window);

#ifdef __cplusplus
}
#endif

#endif
