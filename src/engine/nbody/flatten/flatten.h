// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef FLATTEN_H
#define FLATTEN_H

#include "max_tree.h"

// one sample's orders, as EngineResidualRequest's: every background order even, a smooth order odd or even
typedef struct
{
    unsigned int smooth[ENGINE_AXES];
    unsigned int background[ENGINE_AXES];
} FlattenOrders;

// `orders` gives each of the `count` samples its own orders. Where it is NULL, every sample takes `smooth_orders` and
// `background_orders`.
typedef struct
{
    const char *set;
    char *const *names;
    unsigned int count;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    const FlattenOrders *orders;
    EngineError *error;
} FlattenSetRequest;

int flatten_set(const FlattenSetRequest *request);

// A flattened set. `orders` holds each sample's orders, and `offset_halves` each sample's residual place per axis in
// half voxels, three a sample, as engine_residual gives it: -1 on an axis whose smooth order is odd and 0 on the
// others. A body's sums sit on its own sample's residual grid.
typedef struct
{
    MaxTreeLayout layout;
    unsigned int samples;
    char **names;
    FlattenOrders *orders;
    int *offset_halves;
    unsigned long long bodies;
    unsigned int *magnitudes;
} FlattenHeld;

int flatten_read(const char *set, FlattenHeld *held, EngineError *error);

void flatten_release(FlattenHeld *held);

#endif
