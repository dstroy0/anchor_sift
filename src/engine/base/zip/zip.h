// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ZIP_H
#define ZIP_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ZIP_REFUSED (-1LL)

typedef struct
{
    const unsigned char *name;
    unsigned long long name_length;
    unsigned long long flags;
    unsigned long long method;
    unsigned long long crc;
    unsigned long long compressed;
    unsigned long long uncompressed;
    unsigned long long local_offset;
} ZipEntry;

typedef struct
{
    unsigned char *directory;
    unsigned long long directory_bytes;
    unsigned long long entries;
    unsigned long long file_bytes;
    unsigned long long *entry_at;
} ZipArchive;

int zip_archive_open(const EngineIngestTools *tools, const char *path, ZipArchive *archive, EngineError *error);

void zip_archive_release(ZipArchive *archive);

int zip_entry_next(const ZipArchive *archive, unsigned long long *at, ZipEntry *entry, EngineError *error);

int zip_archive_index(ZipArchive *archive, EngineError *error);

int zip_folder_find(const ZipArchive *archive, const char *folder, unsigned long long *first, unsigned long long *count);

int zip_entry_at(const ZipArchive *archive, unsigned long long slot, ZipEntry *entry, EngineError *error);

const ZipArchive *zip_archive_held(const EngineIngestTools *tools, const char *path, EngineError *error);

void zip_held_release(void);

int zip_member_data(const EngineIngestTools *tools, const char *path, const ZipArchive *archive, const ZipEntry *entry,
                    unsigned long long *data_start, EngineError *error);

long long zip_member_read(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                          const ZipEntry *entry, unsigned char *out, unsigned long long room, EngineError *error);

unsigned long long zip_crc32(const unsigned char *bytes, unsigned long long length);

#ifdef __cplusplus
}
#endif

#endif
