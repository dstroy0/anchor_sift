#ifndef PEAK_BASINS_H
#define PEAK_BASINS_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(PEAK_BASINS_BUILD_DLL) && PEAK_BASINS_BUILD_DLL && defined(_WIN32)
#define PEAK_BASINS_EXPORT __declspec(dllexport)
#else
#define PEAK_BASINS_EXPORT
#endif

#define PEAK_BASINS_REFUSED (-1L)

typedef struct
{
    const float *field;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    double *centroids;
    float *peak_values;
    unsigned int *peak_indices;
    unsigned int *sizes;
    unsigned int room;
    unsigned int *labels;

} PeakBasinsRequest;

PEAK_BASINS_EXPORT long peak_basins_run(const PeakBasinsRequest *args);

#ifdef __cplusplus
}
#endif

#endif
