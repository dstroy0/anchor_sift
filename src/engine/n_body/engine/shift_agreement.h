/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file shift_agreement.h
 * @brief The integer shift under which two binary volumes agree at the most voxels, found by exact
 *        correlation.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note For every lag L, the count is how many voxels p are set in the before volume with p + L set
 *       in the after volume. Every count is computed at once as a correlation, carried out as a
 *       number theoretic transform modulo SHIFT_AGREEMENT_PRIME. A count never exceeds the voxel
 *       count, which is refused at or above the prime. Every count comes back exact and never
 *       reduced.
 * @note The chosen lag has the highest count. Among lags tied on count it has the smallest weighted
 *       squared length, sum over axes of weight times lag squared, and among those the lowest index.
 *       With weights from the voxel's physical size per axis, the choice is the tied shift with the
 *       least physical motion.
 * @note The host arm and the device arm return the same lag, count and count volume.
 */
#ifndef SHIFT_AGREEMENT_H
#define SHIFT_AGREEMENT_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(SHIFT_AGREEMENT_BUILD_DLL) && SHIFT_AGREEMENT_BUILD_DLL && defined(_WIN32)
#define SHIFT_AGREEMENT_EXPORT __declspec(dllexport)
#else
#define SHIFT_AGREEMENT_EXPORT
#endif

/** @brief What an entry returns for a request it will not run or could not finish. */
#define SHIFT_AGREEMENT_REFUSED (-1L)

/** @brief The most axes a volume may have. */
#define SHIFT_AGREEMENT_AXES 8u

/**
 * @brief The transform's modulus, 119 * 2^23 + 1, with 3 as a primitive root.
 *
 * @note Its multiplicative group has a subgroup of every power of two up to 2^23. A transform of
 *       every power of two length up to 2^23 therefore has its roots of unity in this field.
 */
#define SHIFT_AGREEMENT_PRIME 998244353u

/**
 * @brief The longest padded axis, the longest transform the prime supports.
 *
 * @note An axis is padded to a power of two at least twice its extent less one, which keeps the
 *       correlation from wrapping around. An extent above half of this is refused.
 */
#define SHIFT_AGREEMENT_LONGEST_AXIS (1u << 23u)

/**
 * @brief Two binary volumes, the tie break weights, and where the chosen lag is written.
 *
 * @note Voxels are numbered with the last axis fastest. Voxel v is set where bit v % 64 of word
 *       v / 64 is set.
 */
typedef struct
{
    unsigned int axes;                          /**< Axes in use, 1 to SHIFT_AGREEMENT_AXES. */
    unsigned int extents[SHIFT_AGREEMENT_AXES]; /**< Voxels along each axis in use. */
    unsigned int weights[SHIFT_AGREEMENT_AXES]; /**< Weight of each axis in the tie break length. */
    const unsigned long long *before;           /**< One bit per before voxel [BORROWS]. */
    const unsigned long long *after;            /**< One bit per after voxel [BORROWS]. */
    int lag[SHIFT_AGREEMENT_AXES];              /**< Out: the chosen lag, 0 past the axes in use. */
    unsigned int agreement;                     /**< Out: voxels agreeing at the chosen lag. */
    unsigned int padded[SHIFT_AGREEMENT_AXES];  /**< Out: each axis's padded length, 0 past. */
    unsigned int *counts;                       /**< Out: the count at every padded lag, or NULL
                                                     where the caller does not want them [BORROWS]. */
} ShiftAgreementRequest;

/**
 * @brief Finds the best agreeing lag on the host.
 *
 * @param[in,out] args The volumes and weights, and where the lag is written [BORROWS].
 * @return             0 where the lag was found, or SHIFT_AGREEMENT_REFUSED where a pointer is
 *                     null, the axes are out of range, an extent is 0 or above half of
 *                     SHIFT_AGREEMENT_LONGEST_AXIS, the voxel count reaches SHIFT_AGREEMENT_PRIME,
 *                     the padded volume passes 2^31 - 1 entries, or an allocation failed.
 * @note `counts` holds the product of the padded lengths entries. A padded coordinate below half
 *       its length is a lag of that coordinate, and one at or above half is the coordinate minus the
 *       length.
 * @note On a refusal nothing in `args` is written.
 * @warning The weighted squared length is summed in 64 bits and nothing checks it. A lag on the
 *          longest axis squares to nearly 2^44, and a weight above 2^20 there passes 2^64 and wraps.
 *          The tie break then compares wrapped lengths.
 */
SHIFT_AGREEMENT_EXPORT long shift_agreement_host(ShiftAgreementRequest *args);

/**
 * @brief Finds the best agreeing lag on the device.
 *
 * @param[in,out] args The volumes and weights, and where the lag is written [BORROWS].
 * @return             What shift_agreement_host returns for the same request, or
 *                     SHIFT_AGREEMENT_REFUSED where no device answers or a device step failed.
 * @note Keeps the after volume's transform from each call. Where the next call's before volume is
 *       that after volume, which is the case walking a recording frame by frame, the before volume's
 *       transform is read off the kept one instead of computed.
 * @note Device buffers are held between calls. The entry is not safe to call from two threads at
 *       once.
 */
SHIFT_AGREEMENT_EXPORT long shift_agreement_run(ShiftAgreementRequest *args);

#ifdef __cplusplus
}
#endif

#endif /* SHIFT_AGREEMENT_H */
