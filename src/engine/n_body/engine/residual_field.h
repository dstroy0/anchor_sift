/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file residual_field.h
 * @brief A band-pass residual of a volume in floating point: smoothed minus the smoothed smoothed.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note The volume is correlated with one separable kernel along each axis in turn to give the
 *       smoothed field, the smoothed field with a second kernel to give the background, and the
 *       residual is their difference.
 * @note Floating point throughout, arranged to reproduce scipy.ndimage bit for bit: each axis pass
 *       accumulates in double and narrows to float32, the boundary reflects, and a symmetric kernel's
 *       pairs are summed from the outermost weight inward. binomial_basins.h computes the same kind
 *       of residual in exact integers from binomial kernels.
 * @note Built into the engine library only. Neither src/exact_track.py nor track_driver.cu calls it.
 */
#ifndef RESIDUAL_FIELD_H
#define RESIDUAL_FIELD_H

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Exported from the engine library on a Windows DLL build, empty on every other build. */
#if defined(RESIDUAL_FIELD_BUILD_DLL) && RESIDUAL_FIELD_BUILD_DLL && defined(_WIN32)
#define RESIDUAL_FIELD_EXPORT __declspec(dllexport)
#else
#define RESIDUAL_FIELD_EXPORT
#endif

/** @brief What residual_field_run returns for a request it will not run or could not finish. */
#define RESIDUAL_FIELD_REFUSED (-1L)

/**
 * @brief A volume, the two kernels per axis, and where the residual is written.
 *
 * @note Axis 0 is depth, 1 height and 2 width, and the width index runs fastest. A kernel of
 *       radius r holds 2r + 1 weights. All are copied to the device, and the correlation uses only
 *       the first r + 1, taking the kernel as symmetric about its center.
 */
typedef struct
{
    const float *volume;                /**< depth * height * width voxels [BORROWS]. */
    unsigned int depth;                 /**< Voxels along axis 0. */
    unsigned int height;                /**< Voxels along axis 1. */
    unsigned int width;                 /**< Voxels along axis 2. */
    const double *smooth_kernels[3];    /**< The smoothing kernel of each axis [BORROWS]. */
    unsigned int smooth_radii[3];       /**< Radius of each smoothing kernel. */
    const double *background_kernels[3]; /**< The background kernel of each axis [BORROWS]. */
    unsigned int background_radii[3];   /**< Radius of each background kernel. */
    float *residual;                    /**< Out: smoothed minus background, per voxel [BORROWS]. */
} ResidualFieldRequest;

/**
 * @brief Computes the residual on the device.
 *
 * @param[in] args The volume, kernels and output [BORROWS].
 * @return         0 where the residual was written, or RESIDUAL_FIELD_REFUSED where a pointer is
 *                 null, an extent is 0, a plane passes 2^32 voxels, the volume comes within 256 of
 *                 2^32 voxels, no device answers, or a device step failed.
 * @warning A kernel that is not symmetric is read as though it were, from its left half, and the
 *          result is not the correlation with that kernel.
 */
RESIDUAL_FIELD_EXPORT long residual_field_run(const ResidualFieldRequest *args);

#ifdef __cplusplus
}
#endif

#endif
