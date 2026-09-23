/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file cuda_miner.h
 * @brief What the host needs to drive the device arm, with no CUDA types in the interface.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note A translation unit that includes this does not need nvcc. That keeps the client compilable
 *       by the same g++ that builds everything else, with the device arm linked in when present.
 */
#ifndef CUDA_MINER_H
#define CUDA_MINER_H

#include <cstddef>
#include <cstdint>

/** @brief Everything one launch needs, copied to the device by value. */
struct CudaScanParameters
{
    uint32_t midstate[8];      /**< Chaining value after header bytes 0 through 63. */
    uint32_t merkle_root_tail; /**< Header bytes 64 through 67, as a schedule word. */
    uint32_t ntime;            /**< Header bytes 68 through 71, as a schedule word. */
    uint32_t nbits;            /**< Header bytes 72 through 75, as a schedule word. */
    uint32_t share_target[8];  /**< Share threshold, most significant word first. */
    uint32_t anchor_is_sound;  /**< Nonzero where the target leaves the top word at zero. */

    /** @brief The chaining value after the rounds no nonce can reach.
     *  @note Filled by cuda_miner_scan, not by the caller. The nonce is message word three and
     *        W[at] draws on at-16, at-15, at-7 and at-2, so the first three rounds read only words
     *        no nonce touches and produce the same state for every one of them. Computing it once
     *        per launch instead of once per thread removes work the device was duplicating across
     *        every thread it ran. */
    uint32_t shared_state[8];

    /** @brief Schedule words sixteen and seventeen, which no nonce reaches either.
     *  @note Filled by cuda_miner_scan. W16 draws on W0, W1, W9 and W14; W17 on W1, W2, W10 and
     *        W15. Word eighteen is the first to draw on word three and so the first a thread must
     *        compute for itself. */
    uint32_t shared_schedule[2];
};

struct CudaMinerContext;

/**
 * @brief Allocates the device buffers one miner needs.
 *
 * @param[in] found_limit How many winning nonces one launch may report.
 * @return                A context, or NULL where the device refused. [OWNS]
 */
CudaMinerContext *cuda_miner_create(uint32_t found_limit);

/**
 * @brief Releases a context.
 *
 * @param[in] context What to release [OWNS].
 */
void cuda_miner_destroy(CudaMinerContext *context);

/**
 * @brief How many nonces cleared the anchor in the last scan on this context.
 *
 * @param[in] context Device buffers [BORROWS].
 * @return            The count, or zero where the context is null or no scan has run.
 * @note Separate from the winner count that cuda_miner_scan reports. A winner cleared the
 *       anchor and then also came in under the threshold; a survivor only cleared the anchor. The
 *       client displays the second alongside the CPU arm's own figure, and reporting the first
 *       under its name made the device look as though it found no survivors at all.
 * @note Valid only until the next scan on the same context, which resets it.
 */
unsigned long long cuda_miner_anchor_survivors(const CudaMinerContext *context);

/**
 * @brief Scans a nonce range on the device.
 *
 * @param[in]  context      Device buffers [BORROWS].
 * @param[in]  parameters   Header tail, midstate and threshold [BORROWS].
 * @param[in]  nonce_base   First nonce to evaluate.
 * @param[in]  nonce_count  How many to evaluate.
 * @param[out] found_nonces Where winners land, at most found_limit of them [BORROWS].
 * @param[out] found_count  How many winners were written [BORROWS].
 * @return                  Nonzero on success. Zero means the launch failed and nothing is valid.
 * @note Winners are reported unordered. A caller wanting the lowest has to take the minimum.
 */
int cuda_miner_scan(CudaMinerContext *context, const CudaScanParameters *parameters,
                    uint32_t nonce_base, uint32_t nonce_count, uint32_t *found_nonces,
                    uint32_t *found_count);

/** @brief What a device survey accumulates. No early exit, every nonce counted. */
struct CudaSurvey
{
    unsigned long long nonces_evaluated;       /**< How many nonces were hashed. */
    unsigned long long bit_one_count[256];     /**< How often each digest bit position was set. */
    unsigned long long leading_zero_count[33]; /**< How many digests carried at least k zero bits. */
};

/**
 * @brief Surveys a nonce range on the device, accumulating bit statistics.
 *
 * @param[in]     context     Device buffers [BORROWS].
 * @param[in]     parameters  Header tail and midstate. share_target is ignored [BORROWS].
 * @param[in]     nonce_base  First nonce to evaluate.
 * @param[in]     nonce_count How many to evaluate.
 * @param[in,out] survey      Counts, added to whatever is already there [BORROWS].
 * @return                    Nonzero on success.
 * @note Exists because the digest field carries no noise. H(digest | input) is zero, and a bias bound
 *       measured here is limited by sample size alone and there is no floor beneath it. More samples
 *       tighten the bound indefinitely, and that makes putting the device on this worthwhile.
 */
int cuda_miner_survey(CudaMinerContext *context, const CudaScanParameters *parameters,
                      uint32_t nonce_base, uint32_t nonce_count, CudaSurvey *survey);

/**
 * @brief Salts the nonce and counts which output bits respond. The keyhole scan.
 *
 * @param[in]     context              Device buffers [BORROWS].
 * @param[in]     parameters           Header tail and midstate [BORROWS].
 * @param[in]     nonce_base           First nonce.
 * @param[in]     nonce_count          How many.
 * @param[in]     salt                 Input difference applied to the nonce.
 * @param[in,out] difference_one_count 256 counters, added to [BORROWS].
 * @return                             Nonzero on success.
 * @note A keyhole is an output bit whose difference is not a fair coin under a fixed input salt.
 *       Under a flat field every counter sits at half the sample size, and any departure is a place
 *       the construction gives something away.
 */
int cuda_miner_keyhole(CudaMinerContext *context, const CudaScanParameters *parameters,
                       uint32_t nonce_base, uint32_t nonce_count, uint32_t salt,
                       unsigned long long *difference_one_count);

/**
 * @brief Describes the device, for a caller that wants to print it.
 *
 * @param[out] text      Where the description lands [BORROWS].
 * @param[in]  text_size How much room it has.
 * @return               Multiprocessor count, or zero where no device is visible.
 */
int cuda_miner_device_report(char *text, size_t text_size);

#endif
