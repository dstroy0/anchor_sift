// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zip_archive.c: opening an archive and walking its entries
#include "zip_internal.h"

static const unsigned char zip_central[4u] = {'P', 'K', 0x01u, 0x02u};

static const unsigned char zip_end[4u] = {'P', 'K', 0x05u, 0x06u};

static const unsigned char zip_wide_end[4u] = {'P', 'K', 0x06u, 0x06u};

static const unsigned char zip_wide_locator[4u] = {'P', 'K', 0x06u, 0x07u};

unsigned long long zip_load(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

int zip_fits_memory(unsigned long long bytes)
{
    // narrowing to size_t and widening back is the test: the count survives only when it fits memory
    return ((unsigned long long)(size_t)bytes == bytes) ? 1 : 0;
}

int zip_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset, unsigned long long bytes,
              unsigned char *out)
{
    if (bytes == 0ull)
    {
        return 1;
    }
    const EngineFileRange range = {path, offset, bytes, out};
    const long long got = tools->read(&range);
    // a non-negative long long count converts to unsigned long long exactly
    return ((got >= 0LL) && ((unsigned long long)got == bytes)) ? 1 : 0;
}

unsigned long long zip_crc32(const unsigned char *bytes, unsigned long long length)
{
    unsigned long long table[256u];
    for (unsigned long long entry = 0ull; entry < 256ull; entry += 1ull)
    {
        unsigned long long value = entry;
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            value = ((value & 1ull) != 0ull) ? ((value >> 1u) ^ 0xEDB88320ull) : (value >> 1u);
        }
        table[entry] = value;
    }
    unsigned long long crc = ZIP_WORD;
    for (unsigned long long at = 0ull; at < length; at += 1ull)
    {
        crc = table[(crc ^ bytes[at]) & 0xFFull] ^ (crc >> 8u);
    }
    return crc ^ ZIP_WORD;
}

int zip_archive_open(const EngineIngestTools *tools, const char *path, ZipArchive *archive, EngineError *error)
{
    if (error == NULL)
    {
        return 0;
    }
    if (!ZIP_CHECK((tools != NULL) && (tools->read != NULL) && (tools->size != NULL) && (path != NULL) &&
                       (archive != NULL),
                   &archive, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(archive, 0, sizeof(*archive));
    const long long size = tools->size(path);
    if (!ZIP_IO(size >= 0LL, path, error) || !ZIP_CHECK(size >= 22LL, path, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // a non-negative long long size converts to unsigned long long exactly
    const unsigned long long file_bytes = (unsigned long long)size;
    const unsigned long long tail_bytes = (file_bytes < ZIP_TAIL_CAPACITY) ? file_bytes : ZIP_TAIL_CAPACITY;
    unsigned char *const tail = malloc((size_t)tail_bytes);
    if (!ZIP_CHECK(tail != NULL, &tail_bytes, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    const unsigned long long tail_start = file_bytes - tail_bytes;
    unsigned long long record = tail_bytes;
    if (!ZIP_IO(zip_fetch(tools, path, tail_start, tail_bytes, tail), tail, error))
    {
        free(tail);
        return 0;
    }
    for (unsigned long long at = tail_bytes - 21ull; (record == tail_bytes) && (at > 0ull); at -= 1ull)
    {
        const unsigned char *const candidate = tail + at - 1ull;
        const int signed_here = (memcmp(candidate, zip_end, sizeof zip_end) == 0);
        record =
            (signed_here && ((at - 1ull + 22ull + zip_load(candidate + 20u, 2u)) == tail_bytes)) ? (at - 1ull) : record;
    }
    if (!ZIP_CHECK(record != tail_bytes, path, error, ENGINE_ERROR_REQUEST))
    {
        free(tail);
        return 0;
    }
    const unsigned char *const end = tail + record;
    unsigned long long disk = zip_load(end + 4u, 2u);
    unsigned long long directory_disk = zip_load(end + 6u, 2u);
    unsigned long long disk_entries = zip_load(end + 8u, 2u);
    unsigned long long entries = zip_load(end + 10u, 2u);
    unsigned long long directory_bytes = zip_load(end + 12u, 4u);
    unsigned long long directory_offset = zip_load(end + 16u, 4u);
    const unsigned long long end_offset = tail_start + record;
    free(tail);
    unsigned char locator[20u];
    const int located = (end_offset >= 20ull) && zip_fetch(tools, path, end_offset - 20ull, 20ull, locator) &&
                        (memcmp(locator, zip_wide_locator, sizeof zip_wide_locator) == 0);
    if (located)
    {
        const unsigned long long record_offset = zip_load(locator + 8u, 8u);
        unsigned char wide[56u];
        if (!ZIP_CHECK((zip_load(locator + 4u, 4u) == 0ull) && (zip_load(locator + 16u, 4u) <= 1ull) &&
                           (record_offset <= end_offset) && ((end_offset - record_offset) >= 56ull),
                       locator, error, ENGINE_ERROR_REQUEST) ||
            !ZIP_IO(zip_fetch(tools, path, record_offset, 56ull, wide), wide, error) ||
            !ZIP_CHECK(memcmp(wide, zip_wide_end, sizeof zip_wide_end) == 0, wide, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        disk = zip_load(wide + 16u, 4u);
        directory_disk = zip_load(wide + 20u, 4u);
        disk_entries = zip_load(wide + 24u, 8u);
        entries = zip_load(wide + 32u, 8u);
        directory_bytes = zip_load(wide + 40u, 8u);
        directory_offset = zip_load(wide + 48u, 8u);
    }
    else if (!ZIP_CHECK((entries != ZIP_HALF) && (directory_bytes != ZIP_WORD) && (directory_offset != ZIP_WORD), path,
                        error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if (!ZIP_CHECK((disk == 0ull) && (directory_disk == 0ull) && (disk_entries == entries) &&
                       (directory_offset <= file_bytes) && (directory_bytes <= (file_bytes - directory_offset)) &&
                       (entries <= (directory_bytes / 46ull)),
                   path, error, ENGINE_ERROR_REQUEST) ||
        !ZIP_CHECK(zip_fits_memory(directory_bytes + 1ull), &directory_bytes, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    unsigned char *const directory = malloc((size_t)directory_bytes + 1u);
    if (!ZIP_CHECK(directory != NULL, &directory_bytes, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    if (!ZIP_IO(zip_fetch(tools, path, directory_offset, directory_bytes, directory), directory, error))
    {
        free(directory);
        return 0;
    }
    archive->directory = directory;
    archive->directory_bytes = directory_bytes;
    archive->entries = entries;
    archive->file_bytes = file_bytes;
    return 1;
}

void zip_archive_release(ZipArchive *archive)
{
    free(archive->directory);
    free(archive->entry_at);
    memset(archive, 0, sizeof(*archive));
}

int zip_entry_next(const ZipArchive *archive, unsigned long long *at, ZipEntry *entry, EngineError *error)
{
    const unsigned long long start = *at;
    if (!ZIP_CHECK((start <= archive->directory_bytes) && ((archive->directory_bytes - start) >= 46ull), at, error,
                   ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned char *const fixed = archive->directory + start;
    if (!ZIP_CHECK(memcmp(fixed, zip_central, sizeof zip_central) == 0, fixed, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long name_length = zip_load(fixed + 28u, 2u);
    const unsigned long long extra_length = zip_load(fixed + 30u, 2u);
    const unsigned long long comment_length = zip_load(fixed + 32u, 2u);
    const unsigned long long total = 46ull + name_length + extra_length + comment_length;
    if (!ZIP_CHECK(total <= (archive->directory_bytes - start), fixed, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    ZipEntry parsed = zip_empty_entry;
    parsed.name = fixed + 46u;
    parsed.name_length = name_length;
    parsed.flags = zip_load(fixed + 8u, 2u);
    parsed.method = zip_load(fixed + 10u, 2u);
    parsed.crc = zip_load(fixed + 16u, 4u);
    parsed.compressed = zip_load(fixed + 20u, 4u);
    parsed.uncompressed = zip_load(fixed + 24u, 4u);
    parsed.local_offset = zip_load(fixed + 42u, 4u);
    unsigned long long disk = zip_load(fixed + 34u, 2u);
    const int wide_uncompressed = (parsed.uncompressed == ZIP_WORD);
    const int wide_compressed = (parsed.compressed == ZIP_WORD);
    const int wide_offset = (parsed.local_offset == ZIP_WORD);
    const int wide_disk = (disk == ZIP_HALF);
    unsigned int widened = 0u;
    const unsigned char *const extra = fixed + 46u + name_length;
    unsigned long long walk = 0ull;
    while ((extra_length - walk) >= 4ull)
    {
        const unsigned long long identity = zip_load(extra + walk, 2u);
        const unsigned long long size = zip_load(extra + walk + 2u, 2u);
        if (!ZIP_CHECK(size <= (extra_length - walk - 4ull), extra, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if ((identity == 1ull) && (widened == 0u))
        {
            const unsigned char *const field = extra + walk + 4u;
            const unsigned long long needed = (wide_uncompressed ? 8ull : 0ull) + (wide_compressed ? 8ull : 0ull) +
                                              (wide_offset ? 8ull : 0ull) + (wide_disk ? 4ull : 0ull);
            if (!ZIP_CHECK(needed <= size, field, error, ENGINE_ERROR_REQUEST))
            {
                return 0;
            }
            unsigned long long place = 0ull;
            parsed.uncompressed = wide_uncompressed ? zip_load(field + place, 8u) : parsed.uncompressed;
            place += wide_uncompressed ? 8ull : 0ull;
            parsed.compressed = wide_compressed ? zip_load(field + place, 8u) : parsed.compressed;
            place += wide_compressed ? 8ull : 0ull;
            parsed.local_offset = wide_offset ? zip_load(field + place, 8u) : parsed.local_offset;
            place += wide_offset ? 8ull : 0ull;
            disk = wide_disk ? zip_load(field + place, 4u) : disk;
            widened = 1u;
        }
        walk += 4ull + size;
    }
    if (!ZIP_CHECK(((!wide_uncompressed && !wide_compressed && !wide_offset && !wide_disk) || (widened != 0u)) &&
                       (disk == 0ull),
                   fixed, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    *at = start + total;
    *entry = parsed;
    return 1;
}
