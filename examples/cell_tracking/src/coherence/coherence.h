// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef COHERENCE_H
#define COHERENCE_H

#include "track.h"

#include <stdio.h>

void links_of_node(const NodeIndex *index, unsigned int node, const unsigned int **first, unsigned int *count);

int export_room(const EngineBuffers *buffers, const CoherenceInputs *inputs, const char *directory);

int export_object(const EngineBuffers *buffers, const CoherenceInputs *inputs, const unsigned int *runs,
                         const unsigned int *first_run, const unsigned int *leaf_runs, const TreeRules *rules);

int read_coherence(EngineBuffers *buffers, const CoherenceInputs *inputs, FILE *out);

#endif
