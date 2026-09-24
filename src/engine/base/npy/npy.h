// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef NPY_H
#define NPY_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long npy_describe(const EngineDescribeRequest *request);

long long npy_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
