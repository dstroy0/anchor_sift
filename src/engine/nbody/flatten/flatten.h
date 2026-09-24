// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef FLATTEN_H
#define FLATTEN_H

#include "max_tree.h"

typedef struct
{
    const char *set;
    char *const *names;
    unsigned int count;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    EngineError *error;
} FlattenSetRequest;

int flatten_set(const FlattenSetRequest *request);

typedef struct
{
    MaxTreeLayout layout;
    unsigned int samples;
    char **names;
    unsigned long long bodies;
    unsigned int *magnitudes;
} FlattenHeld;

int flatten_read(const char *set, FlattenHeld *held, EngineError *error);

void flatten_release(FlattenHeld *held);

#endif
