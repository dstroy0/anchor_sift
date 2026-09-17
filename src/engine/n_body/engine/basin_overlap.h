/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file basin_overlap.h
 * @brief How many voxels each basin of one frame shares with each basin of the next, counted exactly.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * A position v of the first frame is compared with position v + lag of the next, where lag is the
 * view's own motion between the two frames (shift_agreement.h measures it) and every axis of the view
 * may carry one. The pair (peak before at v, peak after at v + lag) is counted when both positions
 * are positive: above background before and above background after. The count is the evidence that
 * two objects are one object continuing, with the view's motion removed. Nothing is predicted and
 * nothing is averaged; it is a tally, so it accumulates over a series with no error to compound.
 * Positions whose v + lag falls outside the view are not counted.
 *
 * TWO ENGINES, ONE ANSWER. basin_overlap_host is portable C11 and single threaded, and it is the
 * reference. basin_overlap_run is the CUDA engine. Both return the same pairs in the same order.
 */
#ifndef BASIN_OVERLAP_H
#define BASIN_OVERLAP_H

#ifdef __cplusplus
extern "C" {
#endif

/* The export spelling for a DLL build, and nothing otherwise. Both arms are defined. */
#if defined(BASIN_OVERLAP_BUILD_DLL) && BASIN_OVERLAP_BUILD_DLL && defined(_WIN32)
#define BASIN_OVERLAP_EXPORT __declspec(dllexport)
#else
#define BASIN_OVERLAP_EXPORT
#endif

/** @brief Returned where the work was refused. */
#define BASIN_OVERLAP_REFUSED (-1L)

/** @brief Largest room a caller may pass, so a count always fits the long returned. */
#define BASIN_OVERLAP_ROOM_LIMIT 0x7FFFFFFFu

/** @brief Most axes a view may have. */
#define BASIN_OVERLAP_AXES 8u

/**
 * @brief Two frames' labels and signs, and where the pairs go.
 *
 * @note Pairs are returned ascending by peak before, then peak after, each pair once with its count.
 *       Where the pairs exceed `room` nothing is written and the pair count is returned, so a caller
 *       can size exactly and call again.
 */
typedef struct
{
    const unsigned int *labels_before;            /**< Each voxel's peak index, first frame [BORROWS]. */
    const unsigned long long *positive_before;    /**< Sign words, first frame [BORROWS]. */
    const unsigned int *labels_after;             /**< Each voxel's peak index, next frame [BORROWS]. */
    const unsigned long long *positive_after;     /**< Sign words, next frame [BORROWS]. */
    unsigned int axes;                            /**< Axes of the view, 1 to BASIN_OVERLAP_AXES. */
    unsigned int extents[BASIN_OVERLAP_AXES];     /**< Extent per axis, raster order, last fastest. */
    int lag[BASIN_OVERLAP_AXES];                  /**< The view's motion from the first frame to the next. */
    unsigned int voxels;                          /**< Voxels in each frame: the product of the extents. */
    unsigned int room;                            /**< Pairs the outputs hold. */
    unsigned int *peaks_before;                   /**< Out: room peak indices, first frame [BORROWS]. */
    unsigned int *peaks_after;                    /**< Out: room peak indices, next frame [BORROWS]. */
    unsigned int *counts;                         /**< Out: room shared positive voxel counts [BORROWS]. */
} BasinOverlapRequest;

/**
 * @brief The reference: portable C11, single threaded.
 *
 * @param[in] args The request [BORROWS].
 * @return         Distinct pairs, or BASIN_OVERLAP_REFUSED.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_host(const BasinOverlapRequest *args);

/**
 * @brief The CUDA engine. Same request, same answer as basin_overlap_host.
 *
 * @param[in] args The request [BORROWS].
 * @return         Distinct pairs, or BASIN_OVERLAP_REFUSED.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_run(const BasinOverlapRequest *args);

/**
 * @brief The CUDA engine over frames the caller already holds on the device: the two label arrays and the
 *        two sign word arrays of the request are device pointers, and nothing is uploaded. Same answer as
 *        basin_overlap_host; the outputs are host pointers, as there.
 *
 * @param[in] args The request [BORROWS].
 * @return         Distinct pairs, or BASIN_OVERLAP_REFUSED.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_run_on_device(const BasinOverlapRequest *args);

#ifdef __cplusplus
}
#endif

#endif /* BASIN_OVERLAP_H */
