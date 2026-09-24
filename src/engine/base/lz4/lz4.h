// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef LZ4_H
#define LZ4_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

long long lz4_block_decode(const EngineBytesRequest *request);

long long lz4_frame_decode(const EngineBytesRequest *request);

long long lz4_numcodecs_decode(const EngineBytesRequest *request);

#ifdef __cplusplus
}
#endif

#endif
