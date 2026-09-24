/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file peak_basins.h
 * @brief The basins of attraction of a floating point field under steepest ascent, one per peak.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Every voxel points to its highest neighbor among the 26 around it and itself, a tie going
 *       to the lower index, and following the pointers ends at a peak. A peak's basin is every
 *       voxel whose pointers end there. Only voxels with a value above zero count toward a basin's
 *       size and centroid, and only a peak above zero is reported.
 * @note The comparisons between field values are exact. The field is floating point, and the
 *       centroid is an integer index sum divided in double.
 * @note Built into the engine library only. Neither src/exact_track.py nor track_driver.cu calls it.
 */
#ifndef PEAK_BASINS_H
#define PEAK_BASINS_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(PEAK_BASINS_BUILD_DLL) && PEAK_BASINS_BUILD_DLL && defined(_WIN32)
#define PEAK_BASINS_EXPORT __declspec(dllexport)
#else
#define PEAK_BASINS_EXPORT
#endif

/** @brief What peak_basins_run returns for a request it will not run or could not finish. */
#define PEAK_BASINS_REFUSED (-1L)

/**
 * @brief A field and where its peaks are written.
 *
 * @note The width index runs fastest, then height, then depth. Peaks are written in ascending
 *       voxel index.
 */
typedef struct
{
    const float *field;         /**< depth * height * width voxels [BORROWS]. */
    unsigned int depth;         /**< Voxels along the slowest axis. */
    unsigned int height;        /**< Voxels along the middle axis. */
    unsigned int width;         /**< Voxels along the fastest axis. */
    double *centroids;          /**< Out: mean depth, height and width index of each basin's
                                     positive voxels [BORROWS]. */
    float *peak_values;         /**< Out: the field at each peak [BORROWS]. */
    unsigned int *peak_indices; /**< Out: the voxel index of each peak [BORROWS]. */
    unsigned int *sizes;        /**< Out: positive voxels in each basin [BORROWS]. */
    unsigned int room;          /**< Peaks the four outputs hold. */
    unsigned int *labels;       /**< Out: the peak every voxel ascends to, or NULL where not wanted
                                     [BORROWS]. */

} PeakBasinsRequest;

/**
 * @brief Finds every positive peak and its basin on the device.
 *
 * @param[in] args The field and outputs [BORROWS].
 * @return         How many positive peaks there are, or PEAK_BASINS_REFUSED where a pointer is
 *                 null, an extent is 0 or above 2^31 - 1, the volume comes within 4096 of 2^32
 *                 voxels, no device answers, or a device step failed.
 * @note A count of 0, or one above `room`, writes nothing and returns the count. A count above
 *       2^31 - 1 is refused.
 */
PEAK_BASINS_EXPORT long peak_basins_run(const PeakBasinsRequest *args);

#ifdef __cplusplus
}
#endif

#endif
