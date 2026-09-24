// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TIFF_H
#define TIFF_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long tiff_describe(const EngineDescribeRequest *request);

long long tiff_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
