#ifndef BIRTH_SWEEP_H
#define BIRTH_SWEEP_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(BIRTH_SWEEP_BUILD_DLL) && BIRTH_SWEEP_BUILD_DLL && defined(_WIN32)
#define BIRTH_SWEEP_EXPORT __declspec(dllexport)
#else
#define BIRTH_SWEEP_EXPORT
#endif

#define BIRTH_SWEEP_REFUSED (-1L)

#define BIRTH_SWEEP_ROOM_EXCEEDED (-2L)

typedef struct
{
    const float *field;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    const double *cuts;

    unsigned int cut_count;
    unsigned int least_voxels;
    unsigned int most_voxels;
    double *centroids;
    unsigned int *births;
    unsigned int room;

} BirthSweepRequest;

BIRTH_SWEEP_EXPORT int birth_sweep_device_available(void);

BIRTH_SWEEP_EXPORT long birth_sweep_run(const BirthSweepRequest *args);

#ifdef __cplusplus
}
#endif

#endif
