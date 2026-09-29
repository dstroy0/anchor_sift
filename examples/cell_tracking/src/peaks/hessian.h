// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef HESSIAN_H
#define HESSIAN_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define HESSIAN_ERROR (-1L)

// the six second differences at a point, in this order: zz, yy, xx, zy, zx, yx. A pure one is R(+1) + R(-1) - 2R(0)
// along its axis; a mixed one is the numerator R(++) - R(+-) - R(-+) + R(--), with no division by 4
#define HESSIAN_ENTRIES 6u

// the faces that cut a point's 26-neighborhood, one bit each: the point lies on that face's plane
#define HESSIAN_FACE_Z_LOW 0x01u
#define HESSIAN_FACE_Z_HIGH 0x02u
#define HESSIAN_FACE_Y_LOW 0x04u
#define HESSIAN_FACE_Y_HIGH 0x08u
#define HESSIAN_FACE_X_LOW 0x10u
#define HESSIAN_FACE_X_HIGH 0x20u

    // a difference is defined when every axis it reads has neither of its faces cutting the point's neighborhood; an
    // undefined one is written as zero limbs, and the point's faces say which ones they are
    typedef struct
    {
        const unsigned int *device_residual;
        unsigned int depth;
        unsigned int height;
        unsigned int width;
        unsigned int limbs;
        unsigned int count;
        const unsigned int *voxels;
        unsigned int *faces;
        unsigned int *differences;
    } HessianRequest;

    // each difference is limbs + 1 limbs wide, two's complement; `differences` holds count * HESSIAN_ENTRIES of them,
    // point-major, then entry, then limb. Returns the count, or HESSIAN_ERROR
    long hessian_find(const HessianRequest *request);

#ifdef __cplusplus
}
#endif

#endif
