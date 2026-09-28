// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the zip_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef ZIP_INTERNAL_H
#define ZIP_INTERNAL_H

#include "zip.h"

#include <stdlib.h>
#include <string.h>

#define ZIP_CHECK(condition_, evacaddr_, error_, kind_)                                                                \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_ZIP, (unsigned int)__LINE__, (const void *)(evacaddr_),    \
                       (error_))

#define ZIP_IO(condition_, evacaddr_, error_)                                                                          \
    engine_io_check((condition_), ENGINE_MODULE_ZIP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ZIP_TAIL_CAPACITY 65557ull
#define ZIP_WORD 0xFFFFFFFFull
#define ZIP_HALF 0xFFFFull
#define ZIP_PATH_CAPACITY ENGINE_PATH_CAPACITY

static const ZipEntry zip_empty_entry = {NULL, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull};

unsigned long long zip_load(const unsigned char *bytes, unsigned int count);

int zip_fits_memory(unsigned long long bytes);

int zip_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset, unsigned long long bytes,
              unsigned char *out);

unsigned long long zip_crc32(const unsigned char *bytes, unsigned long long length);

int zip_archive_open(const EngineIngestTools *tools, const char *path, ZipArchive *archive, EngineError *error);

void zip_archive_release(ZipArchive *archive);

int zip_entry_next(const ZipArchive *archive, unsigned long long *at, ZipEntry *entry, EngineError *error);

typedef struct
{
    char path[ZIP_PATH_CAPACITY];
    ZipArchive archive;
    int valid;
} ZipResident;

#endif
