// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BOX_HISTORY_H
#define BOX_HISTORY_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BOX_HISTORY_REFUSED (-1L)

#define BOX_HISTORY_EXTENT_FIELDS 6u

typedef struct
{
    const EngineHistory *history;
    unsigned int bodies;
    const unsigned int *extents;
    unsigned int *counts;
    unsigned long long *disagreements;
    unsigned long long *microseconds;
} BoxHistoryRequest;

long box_history_gather(const BoxHistoryRequest *request);

#ifdef __cplusplus
}
#endif

#endif
