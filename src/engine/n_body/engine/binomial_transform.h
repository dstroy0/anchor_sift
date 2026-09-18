#ifndef BINOMIAL_TRANSFORM_H
#define BINOMIAL_TRANSFORM_H

#include "binomial_basins.h"

#ifdef __cplusplus
extern "C" {
#endif

int binomial_transform_admits(const unsigned int *extents, const unsigned int *smooth_orders,
                              const unsigned int *background_orders);

int binomial_transform_residual(const unsigned short *volume, const unsigned int *extents,
                                const unsigned int *smooth_orders, const unsigned int *background_orders,
                                unsigned int *residual);

#ifdef __cplusplus
}
#endif

#endif
