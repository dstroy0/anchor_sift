/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file binomial_basins.h
 * @brief An exact band-pass residual from binomial kernels, and the steepest ascent basins of its
 *        positive part.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Smoothing by a binomial kernel of order n weights the n + 1 taps by the coefficients of
 *       (1 + x)^n, C(n, k), which sum to 2^n. A smoothed value is the integer sum of weight times
 *       sample, the weighted mean times 2^n, and it is held exactly in
 *       BINOMIAL_BASINS_LIMBS 32 bit limbs. Nothing is divided.
 * @note The residual is the smoothed field scaled by 2^g, g the sum of the background orders,
 *       minus the smoothed field smoothed again by the background kernels. The scaling puts both
 *       terms at one scale, and the difference is exact. It is held in two's complement across the
 *       limbs.
 * @note Every voxel ascends to the highest of the 27 voxels around and including it, a tie going to
 *       the lower index, and a peak's basin is every voxel that ends there. Only positive voxels
 *       count toward a basin, and only a positive peak is reported. Every quantity is an integer:
 *       residuals, sizes and index sums.
 * @note The host arm and the device arm are built to return the same peaks, sizes, sums, residuals
 *       and pairs. Nothing in this tree runs both on one volume and compares them.
 */
#ifndef BINOMIAL_BASINS_H
#define BINOMIAL_BASINS_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(BINOMIAL_BASINS_BUILD_DLL) && BINOMIAL_BASINS_BUILD_DLL && defined(_WIN32)
#define BINOMIAL_BASINS_EXPORT __declspec(dllexport)
#else
#define BINOMIAL_BASINS_EXPORT
#endif

/** @brief What an entry returns for a request it will not run or could not finish. */
#define BINOMIAL_BASINS_REFUSED (-1L)

/**
 * @brief Limbs per residual, 288 bits.
 *
 * @note A 16 bit sample gains one bit per unit of kernel order and one sign bit. The orders may
 *       sum to at most 32 * 9 - 17 = 271. build_driver.sh reads this value to size the exact
 *       integer the tracker's keys use.
 */
#define BINOMIAL_BASINS_LIMBS 9u

/**
 * @brief The highest kernel order applied in one pass along one axis.
 *
 * @note A pass's weights sum to 2^order. At 32 that sum times a limb below 2^32 stays below 2^64,
 *       and a 64 bit accumulator per limb cannot wrap. A higher order runs as several passes.
 */
#define BINOMIAL_BASINS_PASS_ORDER 32u

/** @brief The most peaks or pairs an entry reports, the largest count a long holds everywhere. */
#define BINOMIAL_BASINS_ROOM_LIMIT 0x7FFFFFFFu

    /**
     * @brief A volume, the kernel orders, and where the peaks, pairs and optional fields are written.
     *
     * @note Axis 0 is depth, 1 height and 2 width, and the width index runs fastest. Every order is
     *       even, which keeps the kernel centered on the voxel.
     * @note A pair joins two positive peaks whose basins meet across a face. `adjacency` lists every
     *       such pair. `joined` lists those where the two voxels on either side of the face are both
     *       positive. The basins touch through their positive parts. Both come sorted and unique,
     *       lower peak first.
     */
typedef struct
{
    const unsigned short *volume; /**< depth * height * width samples [BORROWS]. */
    unsigned int depth; /**< Voxels along axis 0. */
    unsigned int height; /**< Voxels along axis 1. */
    unsigned int width; /**< Voxels along axis 2. */
    unsigned int smooth_orders[3]; /**< Smoothing order per axis, each even. */
    unsigned int background_orders[3]; /**< Background order per axis, each even. */
    unsigned int room; /**< Peaks the four peak outputs hold. */
    unsigned int *peak_indices; /**< Out: voxel index of each peak [BORROWS]. */
    unsigned int *sizes; /**< Out: positive voxels in each basin [BORROWS]. */
    unsigned long long *sums; /**< Out: depth, height and width index sums of each
                                            basin's positive voxels, three per peak [BORROWS]. */
    unsigned int *peak_limbs; /**< Out: each peak's residual, BINOMIAL_BASINS_LIMBS
                                            limbs per peak [BORROWS]. */

    unsigned int adjacency_room; /**< Pairs `adjacency` holds. */
    unsigned int *adjacency; /**< Out: pairs of adjacent peaks, two per pair, or
                                      NULL where not wanted [BORROWS]. */

    unsigned int *adjacency_count; /**< Out: adjacent pairs found [BORROWS]. */
    unsigned int *labels; /**< Out: the peak every voxel ascends to, or NULL
                                        [BORROWS]. */
    unsigned int *residual_limbs; /**< Out: every voxel's residual, or NULL [BORROWS]. */

    unsigned long long *positive_words; /**< Out: one bit per voxel, set where the residual is
                                             positive, or NULL [BORROWS]. */

    unsigned int joined_room; /**< Pairs `joined` holds. */
    unsigned int *joined; /**< Out: pairs joined through positive voxels, two per
                                   pair [BORROWS]. */

    unsigned int *joined_count; /**< Out: joined pairs found [BORROWS]. */
} BinomialBasinsRequest;

    /**
     * @brief Computes the residual and its basins on the host.
     *
     * @param[in] args The volume, orders and outputs [BORROWS].
     * @return         How many positive peaks there are, or BINOMIAL_BASINS_REFUSED where a pointer is
     *                 null, an extent is 0, an order is odd, the orders sum past 271, the volume
     *                 passes 2^32 / BINOMIAL_BASINS_LIMBS voxels, a room passes
     *                 BINOMIAL_BASINS_ROOM_LIMIT, or an allocation failed.
     * @note The two counts are written whenever the return is not a refusal. Every other output is
     *       written only where all three rooms hold what was found, which lets a caller size its arrays
     *       from one call and fill them with a second.
     * @note The reference arm. The device arm is graded against it.
     */
BINOMIAL_BASINS_EXPORT long binomial_basins_host(const BinomialBasinsRequest *args);

    /**
     * @brief Computes the residual and its basins on the device.
     *
     * @param[in] args The volume, orders and outputs [BORROWS].
     * @return         What binomial_basins_host returns for the same request, or
     *                 BINOMIAL_BASINS_REFUSED where no device answers or a device step failed.
     * @note Where binomial_transform_admits accepts the shape and orders, the residual comes from
     *       binomial_transform_residual instead of the per-axis passes. It is built to be the same
     *       residual exactly. Nothing in this tree compares the two.
     * @note Device buffers are held between calls. The entry is not safe to call from two threads at
     *       once.
     */
BINOMIAL_BASINS_EXPORT long binomial_basins_run(const BinomialBasinsRequest *args);

#ifdef __cplusplus
}
#endif

#endif
