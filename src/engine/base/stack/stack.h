// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef STACK_H
#define STACK_H

#include "engine_config.h"

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define STACK_VOXELS_AT 20LL

#ifdef _WIN32
#define STACK_SEEK _fseeki64
#else
#define STACK_SEEK fseeko
#endif

FILE *stack_open(const char *path, unsigned int header[4]);

int stack_upload(const char *path, unsigned long long extent[4], unsigned short **device_lanes);

int stack_read_uncached(const char *path, unsigned long long lanes, unsigned short *volume);

long long stack_file_read(const EngineFileRange *range);

long long stack_file_size(const char *path);

#ifdef __cplusplus
}
#endif

#endif
