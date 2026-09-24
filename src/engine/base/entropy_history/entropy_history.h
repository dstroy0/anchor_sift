// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ENTROPY_HISTORY_H
#define ENTROPY_HISTORY_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ENTROPY_HISTORY_REFUSED (-1L)

long entropy_history_windows(const unsigned long long extent[4], EngineError *error);

typedef struct
{
    const unsigned short *volume;
    unsigned long long extent[4];
    EngineSignum sample;
    EngineHistory *history;
    EngineError *error;
} EntropyHistoryProjectRequest;

long entropy_history_project(const EntropyHistoryProjectRequest *request, unsigned long long *broken);

void entropy_history_report(const EngineHistory *history);

#ifdef __cplusplus
}
#endif

#endif
