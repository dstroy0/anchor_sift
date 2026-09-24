// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef NRRD_H
#define NRRD_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long nrrd_describe(const EngineDescribeRequest *request);

long long nrrd_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
