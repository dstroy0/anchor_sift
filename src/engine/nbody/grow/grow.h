// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef GROW_H
#define GROW_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GROW_REFUSED (-1L)

long grow_leaves(const EngineBody *bodies, unsigned int count, EngineLeaves *leaves, EngineError *error);

void grow_group_voxels(const EngineGroupRequest *request);

#ifdef __cplusplus
}
#endif

#endif
