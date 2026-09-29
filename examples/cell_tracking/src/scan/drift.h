// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef DRIFT_H
#define DRIFT_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define DRIFT_ERROR (-1L)

// the words of a frame's positive set: one bit a voxel, bit v % 64 of word v / 64, v the linear index
// z * height * width + y * width + x, as the engine's drift (shift_agreement) reads it
#define DRIFT_WORDS(voxels) (((unsigned long long)(voxels) + 63ull) / 64ull)

    typedef struct
    {
        const unsigned int *device_residual;
        unsigned int depth;
        unsigned int height;
        unsigned int width;
        unsigned int limbs;
        unsigned long long *positive;
    } DriftPositiveRequest;

    // the frame's positive set [R > 0], packed on the host into DRIFT_WORDS(voxels) words; returns how many voxels are
    // in it, or DRIFT_ERROR
    long drift_positive(const DriftPositiveRequest *request);

    // the drift's weights from the voxel's size: sigma = voxel_pm / gcd(voxel_pm), w = sigma * sigma on each axis.
    // Returns 1, or 0 when a size is zero or a squared sigma does not fit 32 bits, with the weights then left unwritten
    int drift_weights(const unsigned long long voxel_pm[ENGINE_AXES], unsigned int weights[ENGINE_AXES]);

#ifdef __cplusplus
}
#endif

#endif
