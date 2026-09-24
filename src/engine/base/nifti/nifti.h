// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef NIFTI_H
#define NIFTI_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long nifti_describe(const EngineDescribeRequest *request);

long long nifti_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
