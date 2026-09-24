/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file basin_overlap.h
 * @brief Counts, for every pair of labels, how many positive voxels of one frame land on positive
 *        voxels of the next after an integer shift.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note Each frame arrives as a label per voxel and a bit per voxel marking it positive. A positive
 *       before voxel is moved by the lag, one integer per axis. Where it lands inside the volume on
 *       a positive after voxel, the pair of labels at the two ends gains one. The counts are exact
 *       voxel counts. src/exact_track.py passes them to heaviest_matching_run as link weights, and
 *       track_driver.cu reads them through basin_overlap_run_on_device.
 * @note Three entries share one contract: the host arm, the device arm fed from host memory, and
 *       the device arm fed from device memory. All three return the same pairs and counts.
 */
#ifndef BASIN_OVERLAP_H
#define BASIN_OVERLAP_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(BASIN_OVERLAP_BUILD_DLL) && BASIN_OVERLAP_BUILD_DLL && defined(_WIN32)
#define BASIN_OVERLAP_EXPORT __declspec(dllexport)
#else
#define BASIN_OVERLAP_EXPORT
#endif

/** @brief What an entry returns for a request it will not run or could not finish. */
#define BASIN_OVERLAP_REFUSED (-1L)

/** @brief The most pairs an entry reports, the largest count a long holds on every target. */
#define BASIN_OVERLAP_ROOM_LIMIT 0x7FFFFFFFu

/** @brief The most axes a volume may have. */
#define BASIN_OVERLAP_AXES 8u

/**
 * @brief Two labeled frames, the shift between them, and where the pairs are written.
 *
 * @note Voxels are numbered with the last axis fastest. Voxel v is positive where bit v % 64 of
 *       word v / 64 is set.
 */
typedef struct
{
    const unsigned int *labels_before;          /**< Label of every before voxel [BORROWS]. */
    const unsigned long long *positive_before;  /**< One bit per before voxel [BORROWS]. */
    const unsigned int *labels_after;           /**< Label of every after voxel [BORROWS]. */
    const unsigned long long *positive_after;   /**< One bit per after voxel [BORROWS]. */
    unsigned int axes;                          /**< Axes in use, 1 to BASIN_OVERLAP_AXES. */
    unsigned int extents[BASIN_OVERLAP_AXES];   /**< Voxels along each axis in use. */
    int lag[BASIN_OVERLAP_AXES];                /**< Shift applied to a before voxel, per axis. */
    unsigned int voxels;                        /**< Voxels per frame, the product of the extents. */
    unsigned int room;                          /**< Pairs the three output arrays hold. */
    unsigned int *peaks_before;                 /**< Before label of each pair [BORROWS]. */
    unsigned int *peaks_after;                  /**< After label of each pair [BORROWS]. */
    unsigned int *counts;                       /**< Voxels each pair overlaps on [BORROWS]. */
} BasinOverlapRequest;

/**
 * @brief Counts the overlapping label pairs on the host.
 *
 * @param[in] args The frames, the lag and the output arrays [BORROWS].
 * @return         How many distinct pairs overlap, or BASIN_OVERLAP_REFUSED where a pointer is
 *                 null, the axes are out of range, the extents do not multiply to `voxels`, `room`
 *                 passes BASIN_OVERLAP_ROOM_LIMIT, or an allocation failed.
 * @note The pairs are written in ascending order of before label, then after label, and only where
 *       `room` holds all of them. A return above `room` writes nothing and names the room needed.
 * @note The reference arm. The device arms are graded against it.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_host(const BasinOverlapRequest *args);

/**
 * @brief Counts the overlapping label pairs on the device, from frames in host memory.
 *
 * @param[in] args The frames in host memory, the lag and the output arrays [BORROWS].
 * @return         What basin_overlap_host returns for the same request, or BASIN_OVERLAP_REFUSED
 *                 where no device answers, `voxels` is within 256 of 2^32, or a device step
 *                 failed.
 * @note Device buffers are held between calls and reused while the voxel count stays the same.
 *       The entry is not safe to call from two threads at once.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_run(const BasinOverlapRequest *args);

/**
 * @brief Counts the overlapping label pairs on the device, from frames already in device memory.
 *
 * @param[in] args The frames in device memory, the lag and host output arrays [BORROWS].
 * @return         What basin_overlap_run returns for the same frames.
 * @note The four frame pointers are device pointers and are read in place, with no upload. The
 *       output arrays are host memory.
 */
BASIN_OVERLAP_EXPORT long basin_overlap_run_on_device(const BasinOverlapRequest *args);

#ifdef __cplusplus
}
#endif

#endif
