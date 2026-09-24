// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SNAPPY_H
#define SNAPPY_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long long snappy_decode(const EngineBytesRequest *request);

#ifdef __cplusplus
}
#endif

#endif
