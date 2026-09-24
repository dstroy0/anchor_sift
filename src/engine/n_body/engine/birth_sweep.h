/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file birth_sweep.h
 * @brief The components of a floating point field that first appear, within a size range, as a
 *        threshold is swept through a list of cuts.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note At each cut the voxels above it are joined into face connected components. A component is
 *       born at that cut where its voxel count lies in the size range and none of its voxels belongs
 *       to a component born at an earlier cut. Its voxels are then claimed. Walking the cuts from
 *       high to low, a blob is born once, at the first cut where it stands alone at a size in range.
 * @note The field is floating point and each cut is a double. The cuts and the size range are the
 *       caller's.
 * @note Built into the engine library only. Neither src/exact_track.py nor track_driver.cu calls it.
 */
#ifndef BIRTH_SWEEP_H
#define BIRTH_SWEEP_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(BIRTH_SWEEP_BUILD_DLL) && BIRTH_SWEEP_BUILD_DLL && defined(_WIN32)
#define BIRTH_SWEEP_EXPORT __declspec(dllexport)
#else
#define BIRTH_SWEEP_EXPORT
#endif

/** @brief What birth_sweep_run returns for a request it will not run or could not finish. */
#define BIRTH_SWEEP_REFUSED (-1L)

/** @brief What birth_sweep_run returns where the births outnumber the room given. */
#define BIRTH_SWEEP_ROOM_EXCEEDED (-2L)

/**
 * @brief A field, the cuts to sweep, the size range, and where births are written.
 *
 * @note The width index runs fastest, then height, then depth.
 */
typedef struct
{
    const float *field;      /**< depth * height * width voxels [BORROWS]. */
    unsigned int depth;      /**< Voxels along the slowest axis. */
    unsigned int height;     /**< Voxels along the middle axis. */
    unsigned int width;      /**< Voxels along the fastest axis. */
    const double *cuts;      /**< The thresholds, in the order swept [BORROWS]. */

    unsigned int cut_count;  /**< How many cuts. */
    unsigned int least_voxels; /**< Smallest component that can be born. */
    unsigned int most_voxels; /**< Largest component that can be born. */
    double *centroids;       /**< Out: mean depth, height and width index of each birth [BORROWS]. */
    unsigned int *births;    /**< Out: index into `cuts` each birth happened at [BORROWS]. */
    unsigned int room;       /**< Births the two outputs hold. */

} BirthSweepRequest;

/**
 * @brief Whether a usable device is present.
 *
 * @return 1 where a device answers and a context could be made on it, 0 otherwise.
 */
BIRTH_SWEEP_EXPORT int birth_sweep_device_available(void);

/**
 * @brief Sweeps the cuts on the device and reports every birth.
 *
 * @param[in] args The field, cuts, range and outputs [BORROWS].
 * @return         How many births were written, BIRTH_SWEEP_ROOM_EXCEEDED where they outnumber
 *                 `room`, or BIRTH_SWEEP_REFUSED where a pointer is null, an extent is 0, `room`
 *                 passes 2^31 - 1, the volume comes within 4096 of 2^32 voxels, no device answers,
 *                 or a device step failed.
 * @note A voxel is above a cut where its value, widened to double, is greater than the cut.
 * @note The outputs are written only on success. A refusal part way through the sweep writes
 *       nothing.
 */
BIRTH_SWEEP_EXPORT long birth_sweep_run(const BirthSweepRequest *args);

#ifdef __cplusplus
}
#endif

#endif
