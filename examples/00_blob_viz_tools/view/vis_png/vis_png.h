// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef VIS_PNG_H
#define VIS_PNG_H

#include "track.h"

#include <stdio.h>

typedef struct
{
    unsigned int edge;
    int status;
    const TreeFrame *earlier;
    const TreeFrame *later;
    unsigned int offset_before;
    unsigned int offset_after;
    const int *leaf_at_peak[2];
    const int *from;
    const int *to;
    unsigned int source_leaf;
    unsigned int cell;
    unsigned int true_target;
    size_t cell_size;
    unsigned int leaves;
    unsigned int target_size;
    unsigned long long agree_view;
    unsigned long long agree_true;
    unsigned int land_true;
    unsigned int land_objects;
} VisCase;

int render_case(const EngineBuffers *buffers, const CoherenceInputs *inputs, const VisCase *view);

#endif
