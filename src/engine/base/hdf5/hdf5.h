// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef HDF5_H
#define HDF5_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long hdf5_describe(const EngineDescribeRequest *request);

long long hdf5_read(const EngineArrayRead *request);

#ifdef __cplusplus
}
#endif

#endif
