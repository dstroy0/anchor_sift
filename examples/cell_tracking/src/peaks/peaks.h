// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PEAKS_H
#define PEAKS_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define PEAKS_ERROR (-1L)

    typedef struct
    {
        const unsigned int *device_residual;
        unsigned int depth;
        unsigned int height;
        unsigned int width;
        unsigned int limbs;
        unsigned int capacity;
        unsigned int *voxels;
        unsigned int *levels;
    } PeaksRequest;

    long peaks_find(const PeaksRequest *request);

#ifdef __cplusplus
}
#endif

#endif
