#ifndef BASIN_OVERLAP_H
#define BASIN_OVERLAP_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(BASIN_OVERLAP_BUILD_DLL) && BASIN_OVERLAP_BUILD_DLL && defined(_WIN32)
#define BASIN_OVERLAP_EXPORT __declspec(dllexport)
#else
#define BASIN_OVERLAP_EXPORT
#endif

#define BASIN_OVERLAP_REFUSED (-1L)

#define BASIN_OVERLAP_ROOM_LIMIT 0x7FFFFFFFu

#define BASIN_OVERLAP_AXES 8u

typedef struct
{
    const unsigned int *labels_before;
    const unsigned long long *positive_before;
    const unsigned int *labels_after;
    const unsigned long long *positive_after;
    unsigned int axes;
    unsigned int extents[BASIN_OVERLAP_AXES];
    int lag[BASIN_OVERLAP_AXES];
    unsigned int voxels;
    unsigned int room;
    unsigned int *peaks_before;
    unsigned int *peaks_after;
    unsigned int *counts;
} BasinOverlapRequest;

BASIN_OVERLAP_EXPORT long basin_overlap_host(const BasinOverlapRequest *args);

BASIN_OVERLAP_EXPORT long basin_overlap_run(const BasinOverlapRequest *args);

BASIN_OVERLAP_EXPORT long basin_overlap_run_on_device(const BasinOverlapRequest *args);

#ifdef __cplusplus
}
#endif

#endif
