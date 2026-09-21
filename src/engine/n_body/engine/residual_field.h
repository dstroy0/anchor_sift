#ifndef RESIDUAL_FIELD_H
#define RESIDUAL_FIELD_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(RESIDUAL_FIELD_BUILD_DLL) && RESIDUAL_FIELD_BUILD_DLL && defined(_WIN32)
#define RESIDUAL_FIELD_EXPORT __declspec(dllexport)
#else
#define RESIDUAL_FIELD_EXPORT
#endif

#define RESIDUAL_FIELD_REFUSED (-1L)

typedef struct
{
    const float *volume;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    const double *smooth_kernels[3];
    unsigned int smooth_radii[3];
    const double *background_kernels[3];
    unsigned int background_radii[3];
    float *residual;
} ResidualFieldRequest;

RESIDUAL_FIELD_EXPORT long residual_field_run(const ResidualFieldRequest *args);

#ifdef __cplusplus
}
#endif

#endif
