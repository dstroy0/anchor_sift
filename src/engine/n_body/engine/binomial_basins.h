/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file binomial_basins.h
 * @brief The residual and its basins in exact integers: binomial smoothing carried in 32 bit limbs,
 *        steepest ascent by exact comparison, membership by sign, adjacency by label equality.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * NO FLOATING POINT VALUE IS FORMED ANYWHERE IN THIS MODULE. The smoothing kernel along an axis is
 * the binomial of an even order n, Pascal's row n, whose weights are integers summing to exactly 2^n.
 * A volume smoothed by orders (nz, ny, nx) is the raw volume scaled by 2^(nz+ny+nx) exactly, so
 *
 *     residual = smoothed * 2^(sum of background orders) - background
 *
 * compares the two smoothings at one common scale with nothing divided and nothing rounded. It is an
 * integer, its sign says whether a voxel stands above its local background, and two voxels are
 * ordered by comparing limbs. A basin's centroid is returned as its integer index sums and its count,
 * never as their quotient.
 *
 * TWO ENGINES, ONE ANSWER. binomial_basins_host is portable C11 and single threaded, and it is the
 * reference. binomial_basins_run is the CUDA engine. Every output of the two must be equal, and
 * src/exact_track.py --grade checks it.
 *
 * @note Reflection at the volume's edges is half-sample, d c b a | a b c d | d c b a.
 */
#ifndef BINOMIAL_BASINS_H
#define BINOMIAL_BASINS_H

#ifdef __cplusplus
extern "C" {
#endif

/* The export spelling for a DLL build, and nothing otherwise. Both arms are defined. */
#if defined(BINOMIAL_BASINS_BUILD_DLL) && BINOMIAL_BASINS_BUILD_DLL && defined(_WIN32)
#define BINOMIAL_BASINS_EXPORT __declspec(dllexport)
#else
#define BINOMIAL_BASINS_EXPORT
#endif

/** @brief Returned where the work was refused. */
#define BINOMIAL_BASINS_REFUSED (-1L)

/** @brief Limbs in every residual value: 288 bits, two's complement. */
#define BINOMIAL_BASINS_LIMBS 9u

/**
 * @brief Largest binomial order applied in one pass.
 *
 * Row 32's largest weight, 601080390, fits 30 bits. A pass sums every tap's weight times one 32 bit limb,
 * at most (2^32 - 1) * 2^32 since row 32's weights sum to 2^32, and then adds the carry from the limb below,
 * at most 2^32 - 1: at most 2^64 - 1, so the sum never wraps. The half-sample reflection folds the line
 * into a symmetric period, which commutes with every centred symmetric pass, so any split of an order into
 * passes gives the same value.
 */
#define BINOMIAL_BASINS_PASS_ORDER 32u

/** @brief Largest room a caller may pass, so a count always fits the long returned. */
#define BINOMIAL_BASINS_ROOM_LIMIT 0x7FFFFFFFu

/**
 * @brief One raw volume, the smoothing orders, and where the answer goes.
 *
 * @note Orders must be even, so every kernel is centred on its voxel, and 16 plus every order plus
 *       one sign bit must fit 32 * BINOMIAL_BASINS_LIMBS bits. A request that does not is refused.
 * @note Every positive peak is a distinct voxel, so `room` equal to the voxel count always suffices.
 *       Where the peaks exceed `room`, the adjacency pairs exceed `adjacency_room`, or the joined pairs
 *       exceed `joined_room`, nothing is written, the peak count is returned and `adjacency_count` and
 *       `joined_count` hold the pair counts, so a caller can size exactly and call again.
 * @note Joined is a truthy relation and carries no level: two basins are joined where any face
 *       between them has both voxels above background. Every joined pair is also an adjacency pair.
 * @note `adjacency` NULL with `adjacency_room` 0 means adjacency is not asked for: none is collected,
 *       sorted or downloaded, and `adjacency_count` is set to 0. Joined pairs are unaffected.
 */
typedef struct
{
    const unsigned short *volume;          /**< Raw intensities, depth*height*width [BORROWS]. */
    unsigned int depth;                    /**< Extent along z. */
    unsigned int height;                   /**< Extent along y. */
    unsigned int width;                    /**< Extent along x. */
    unsigned int smooth_orders[3];         /**< Binomial order of the first smoothing, z y x. */
    unsigned int background_orders[3];     /**< Binomial order of the background smoothing, z y x. */
    unsigned int room;                     /**< Peaks the peak outputs hold. */
    unsigned int *peak_indices;            /**< Out: room peak raster indices, ascending [BORROWS]. */
    unsigned int *sizes;                   /**< Out: room positive voxel counts [BORROWS]. */
    unsigned long long *sums;              /**< Out: room*3 index sums z y x [BORROWS]. */
    unsigned int *peak_limbs;              /**< Out: room*BINOMIAL_BASINS_LIMBS residual limbs at each
                                                peak, least significant first [BORROWS]. */
    unsigned int adjacency_room;           /**< Pairs the adjacency output holds. */
    unsigned int *adjacency;               /**< Out: adjacency_room*2 peak index pairs, lower first,
                                                ascending and unique, both peaks positive [BORROWS]. */
    unsigned int *adjacency_count;         /**< Out: how many pairs exist [BORROWS]. */
    unsigned int *labels;                  /**< Out, optional: each voxel's peak index [BORROWS]. */
    unsigned int *residual_limbs;          /**< Out, optional: voxels*BINOMIAL_BASINS_LIMBS limbs
                                                [BORROWS]. */
    unsigned long long *positive_words;    /**< Out, optional: (voxels + 63) / 64 words, bit v % 64 of
                                                word v / 64 set where voxel v's residual is positive
                                                [BORROWS]. */
    unsigned int joined_room;              /**< Pairs the joined output holds. */
    unsigned int *joined;                  /**< Out: joined_room*2 peak index pairs, lower first,
                                                ascending and unique: two basins sharing a face
                                                whose two voxels are both positive [BORROWS]. */
    unsigned int *joined_count;            /**< Out: how many joined pairs exist [BORROWS]. */
} BinomialBasinsRequest;

/**
 * @brief The reference: portable C11, single threaded.
 *
 * @param[in] args The request [BORROWS].
 * @return         Positive peaks, or BINOMIAL_BASINS_REFUSED.
 */
BINOMIAL_BASINS_EXPORT long binomial_basins_host(const BinomialBasinsRequest *args);

/**
 * @brief The CUDA engine. Same request, same answer as binomial_basins_host.
 *
 * @param[in] args The request [BORROWS].
 * @return         Positive peaks, or BINOMIAL_BASINS_REFUSED.
 */
BINOMIAL_BASINS_EXPORT long binomial_basins_run(const BinomialBasinsRequest *args);

#ifdef __cplusplus
}
#endif

#endif /* BINOMIAL_BASINS_H */
