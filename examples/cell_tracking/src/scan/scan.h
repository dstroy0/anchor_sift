// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SCAN_H
#define SCAN_H

#include "engine.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define SCAN_ERROR (-1L)

#define SCAN_READINGS 65536u

    typedef struct
    {
        const char *set;
        char *const *samples;
        unsigned int count;
        unsigned int smooth_orders[ENGINE_AXES];
        unsigned int background_orders[ENGINE_AXES];
        unsigned long long voxel_pm[ENGINE_AXES];
        EngineError *error;
    } ScanRequest;

    long scan_set(const ScanRequest *request);

#ifdef __cplusplus
}
#endif

#endif
