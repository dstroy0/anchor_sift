/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file shift_agreement.h
 * @brief How many set bits of one n dimensional view land on set bits of another, at every lag at
 *        once, counted exactly: the frame's own motion, read off the field.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * For views before and after of the same extents, the agreement at lag l is
 *
 *     agreement(l) = sum over positions v of before(v) * after(v + l)
 *
 * and the lag with the most agreement is how far the view moved. Every lag is counted, with no
 * search window: before is reflected, both views are embedded in a periodic volume padded on every
 * axis to a power of two at least twice the extent less one, so no two lags alias, and the reflected
 * before is convolved with after by separable number theoretic transforms modulo 998244353. Every
 * agreement is at most the set bits of one view, which is below the prime, so every count is the
 * integer and not a residue of it.
 *
 * TWO ENGINES, ONE ANSWER. shift_agreement_host is portable C11 and single threaded, and it is the
 * reference. shift_agreement_run is the CUDA engine. Both return the same lag, agreement and counts.
 *
 * @note Views are bit packed in raster order with the last axis varying fastest: bit b % 64 of word
 *       b / 64 is position b.
 * @note Where several lags share the most agreement, the one returned has the smallest weighted
 *       squared length, sum of weights[i] * lag[i]^2, and then the lowest padded raster index. The
 *       weights carry the view's anisotropy, so a step along a coarse axis counts as the longer step
 *       it is.
 */
#ifndef SHIFT_AGREEMENT_H
#define SHIFT_AGREEMENT_H

#ifdef __cplusplus
extern "C" {
#endif

/* The export spelling for a DLL build, and nothing otherwise. Both arms are defined. */
#if defined(SHIFT_AGREEMENT_BUILD_DLL) && SHIFT_AGREEMENT_BUILD_DLL && defined(_WIN32)
#define SHIFT_AGREEMENT_EXPORT __declspec(dllexport)
#else
#define SHIFT_AGREEMENT_EXPORT
#endif

/** @brief Returned where the work was refused. */
#define SHIFT_AGREEMENT_REFUSED (-1L)

/** @brief Most axes a view may have. The request carries its extents in fixed arrays of this size. */
#define SHIFT_AGREEMENT_AXES 8u

/** @brief The transform modulus, 119 * 2^23 + 1, with primitive root 3. */
#define SHIFT_AGREEMENT_PRIME 998244353u

/** @brief Longest padded axis the modulus has roots of unity for. */
#define SHIFT_AGREEMENT_LONGEST_AXIS (1u << 23u)

/**
 * @brief Two views and where the answer goes.
 *
 * @note padded[i] is the smallest power of two no less than 2 * extents[i] - 1. `counts`, when given,
 *       holds the agreement at every padded lag in padded raster order; lag coordinate p on axis i
 *       is the signed lag p where p < padded[i] / 2 and p - padded[i] otherwise.
 */
typedef struct
{
    unsigned int axes;                                  /**< Axes, 1 to SHIFT_AGREEMENT_AXES. */
    unsigned int extents[SHIFT_AGREEMENT_AXES];         /**< Extent per axis, the first axes entries. */
    unsigned int weights[SHIFT_AGREEMENT_AXES];         /**< Squared length weight per axis. */
    const unsigned long long *before;                   /**< Bit packed view before [BORROWS]. */
    const unsigned long long *after;                    /**< Bit packed view after [BORROWS]. */
    int lag[SHIFT_AGREEMENT_AXES];                      /**< Out: the lag with the most agreement. */
    unsigned int agreement;                             /**< Out: the agreement at that lag. */
    unsigned int padded[SHIFT_AGREEMENT_AXES];          /**< Out: padded extent per axis. */
    unsigned int *counts;                               /**< Out, optional: every padded lag [BORROWS]. */
} ShiftAgreementRequest;

/**
 * @brief The reference: portable C11, single threaded.
 *
 * @param[in,out] args The request; outputs are written into it [BORROWS].
 * @return             0, or SHIFT_AGREEMENT_REFUSED with no output written.
 */
SHIFT_AGREEMENT_EXPORT long shift_agreement_host(ShiftAgreementRequest *args);

/**
 * @brief The CUDA engine. Same request, same answer as shift_agreement_host.
 *
 * @param[in,out] args The request; outputs are written into it [BORROWS].
 * @return             0, or SHIFT_AGREEMENT_REFUSED with no output written.
 */
SHIFT_AGREEMENT_EXPORT long shift_agreement_run(ShiftAgreementRequest *args);

#ifdef __cplusplus
}
#endif

#endif /* SHIFT_AGREEMENT_H */
