// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BODY_OVERLAP_H
#define BODY_OVERLAP_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(BODY_OVERLAP_BUILD_DLL) && BODY_OVERLAP_BUILD_DLL && defined(_WIN32)
#define BODY_OVERLAP_EXPORT __declspec(dllexport)
#else
#define BODY_OVERLAP_EXPORT
#endif

#define BODY_OVERLAP_REFUSED (-1L)

#define BODY_OVERLAP_ROOM_LIMIT 0x7FFFFFFFu

#define BODY_OVERLAP_AXES 8u

typedef struct
{
    const unsigned int *labels_before;
    const unsigned long long *positive_before;
    const unsigned int *labels_after;
    const unsigned long long *positive_after;
    unsigned int axes;
    unsigned int extents[BODY_OVERLAP_AXES];
    int lag[BODY_OVERLAP_AXES];
    unsigned int voxels;
    unsigned int room;
    unsigned int *peaks_before;
    unsigned int *peaks_after;
    unsigned int *counts;
    const unsigned int *lag_peaks;
    const int *lag_steps;
    unsigned int lag_count;
} BodyOverlapRequest;

BODY_OVERLAP_EXPORT long body_overlap_host(const BodyOverlapRequest *args);

BODY_OVERLAP_EXPORT long body_overlap_run(const BodyOverlapRequest *args);

BODY_OVERLAP_EXPORT long body_overlap_run_on_device(const BodyOverlapRequest *args);

#ifdef __cplusplus
}
#endif

#endif
