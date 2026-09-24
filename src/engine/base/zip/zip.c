// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "zip.h"

#include <stdlib.h>
#include <string.h>

#define ZIP_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_ZIP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ZIP_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_ZIP, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define ZIP_TAIL_ROOM 65557ull
#define ZIP_WORD 0xFFFFFFFFull
#define ZIP_HALF 0xFFFFull
#define ZIP_PATH_ROOM ENGINE_PATH_ROOM

static const unsigned char zip_local[4u] = {'P', 'K', 0x03u, 0x04u};

static const unsigned char zip_central[4u] = {'P', 'K', 0x01u, 0x02u};

static const unsigned char zip_end[4u] = {'P', 'K', 0x05u, 0x06u};

static const unsigned char zip_wide_end[4u] = {'P', 'K', 0x06u, 0x06u};

static const unsigned char zip_wide_locator[4u] = {'P', 'K', 0x06u, 0x07u};

static const ZipEntry zip_empty_entry = {NULL, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull};

static unsigned long long zip_load(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

static int zip_fits_memory(unsigned long long bytes)
{
    // narrowing to size_t and widening back is the test: the count survives only when it fits memory
    return ((unsigned long long)(size_t)bytes == bytes) ? 1 : 0;
}

static int zip_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset, unsigned long long bytes,
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
    if (!ZIP_HELD((tools != NULL) && (tools->read != NULL) && (tools->size != NULL) && (path != NULL)
                      && (archive != NULL),
                  &archive, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    memset(archive, 0, sizeof(*archive));
    const long long size = tools->size(path);
    if (!ZIP_IO(size >= 0LL, path, error) || !ZIP_HELD(size >= 22LL, path, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    // a non-negative long long size converts to unsigned long long exactly
    const unsigned long long file_bytes = (unsigned long long)size;
    const unsigned long long tail_bytes = (file_bytes < ZIP_TAIL_ROOM) ? file_bytes : ZIP_TAIL_ROOM;
    unsigned char *const tail = malloc((size_t)tail_bytes);
    if (!ZIP_HELD(tail != NULL, &tail_bytes, error, ENGINE_ERROR_RESOURCE))
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
        record = (signed_here && ((at - 1ull + 22ull + zip_load(candidate + 20u, 2u)) == tail_bytes)) ? (at - 1ull)
                                                                                                        : record;
    }
    if (!ZIP_HELD(record != tail_bytes, path, error, ENGINE_ERROR_REQUEST))
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
    const int located = (end_offset >= 20ull) && zip_fetch(tools, path, end_offset - 20ull, 20ull, locator)
                     && (memcmp(locator, zip_wide_locator, sizeof zip_wide_locator) == 0);
    if (located)
    {
        const unsigned long long record_offset = zip_load(locator + 8u, 8u);
        unsigned char wide[56u];
        if (!ZIP_HELD((zip_load(locator + 4u, 4u) == 0ull) && (zip_load(locator + 16u, 4u) <= 1ull)
                          && (record_offset <= end_offset) && ((end_offset - record_offset) >= 56ull),
                      locator, error, ENGINE_ERROR_REQUEST)
            || !ZIP_IO(zip_fetch(tools, path, record_offset, 56ull, wide), wide, error)
            || !ZIP_HELD(memcmp(wide, zip_wide_end, sizeof zip_wide_end) == 0, wide, error, ENGINE_ERROR_REQUEST))
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
    else if (!ZIP_HELD((entries != ZIP_HALF) && (directory_bytes != ZIP_WORD) && (directory_offset != ZIP_WORD), path,
                       error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    if (!ZIP_HELD((disk == 0ull) && (directory_disk == 0ull) && (disk_entries == entries)
                      && (directory_offset <= file_bytes) && (directory_bytes <= (file_bytes - directory_offset))
                      && (entries <= (directory_bytes / 46ull)),
                  path, error, ENGINE_ERROR_REQUEST)
        || !ZIP_HELD(zip_fits_memory(directory_bytes + 1ull), &directory_bytes, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    unsigned char *const directory = malloc((size_t)directory_bytes + 1u);
    if (!ZIP_HELD(directory != NULL, &directory_bytes, error, ENGINE_ERROR_RESOURCE))
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
    if (!ZIP_HELD((start <= archive->directory_bytes) && ((archive->directory_bytes - start) >= 46ull), at, error,
                  ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned char *const fixed = archive->directory + start;
    if (!ZIP_HELD(memcmp(fixed, zip_central, sizeof zip_central) == 0, fixed, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long name_length = zip_load(fixed + 28u, 2u);
    const unsigned long long extra_length = zip_load(fixed + 30u, 2u);
    const unsigned long long comment_length = zip_load(fixed + 32u, 2u);
    const unsigned long long total = 46ull + name_length + extra_length + comment_length;
    if (!ZIP_HELD(total <= (archive->directory_bytes - start), fixed, error, ENGINE_ERROR_REQUEST))
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
        if (!ZIP_HELD(size <= (extra_length - walk - 4ull), extra, error, ENGINE_ERROR_REQUEST))
        {
            return 0;
        }
        if ((identity == 1ull) && (widened == 0u))
        {
            const unsigned char *const field = extra + walk + 4u;
            const unsigned long long needed = (wide_uncompressed ? 8ull : 0ull) + (wide_compressed ? 8ull : 0ull)
                                            + (wide_offset ? 8ull : 0ull) + (wide_disk ? 4ull : 0ull);
            if (!ZIP_HELD(needed <= size, field, error, ENGINE_ERROR_REQUEST))
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
    if (!ZIP_HELD(((!wide_uncompressed && !wide_compressed && !wide_offset && !wide_disk) || (widened != 0u))
                      && (disk == 0ull),
                  fixed, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    *at = start + total;
    *entry = parsed;
    return 1;
}

static const unsigned char *s_zip_sorting;

static void zip_folder_of(const unsigned char *name, unsigned long long length, unsigned long long *start,
                          unsigned long long *span)
{
    unsigned long long last = length;
    while ((last > 0ull) && (name[last - 1ull] != '/'))
    {
        last -= 1ull;
    }
    if (last == 0ull)
    {
        *start = 0ull;
        *span = 0ull;
        return;
    }
    unsigned long long before = last - 1ull;
    while ((before > 0ull) && (name[before - 1ull] != '/'))
    {
        before -= 1ull;
    }
    *start = before;
    *span = (last - 1ull) - before;
}

static int zip_order_spans(const unsigned char *left, unsigned long long left_length, const unsigned char *right,
                           unsigned long long right_length)
{
    const unsigned long long shorter = (left_length < right_length) ? left_length : right_length;
    const int differ = (shorter != 0ull) ? memcmp(left, right, (size_t)shorter) : 0;
    if (differ != 0)
    {
        return differ;
    }
    return (left_length < right_length) ? -1 : ((left_length > right_length) ? 1 : 0);
}

static int zip_order_entries(const void *left, const void *right)
{
    const unsigned char *const one = s_zip_sorting + *(const unsigned long long *)left;
    const unsigned char *const other = s_zip_sorting + *(const unsigned long long *)right;
    const unsigned long long one_length = zip_load(one + 28u, 2u);
    const unsigned long long other_length = zip_load(other + 28u, 2u);
    unsigned long long one_start = 0ull;
    unsigned long long one_span = 0ull;
    unsigned long long other_start = 0ull;
    unsigned long long other_span = 0ull;
    zip_folder_of(one + 46u, one_length, &one_start, &one_span);
    zip_folder_of(other + 46u, other_length, &other_start, &other_span);
    const int folder = zip_order_spans(one + 46u + one_start, one_span, other + 46u + other_start, other_span);
    return (folder != 0) ? folder : zip_order_spans(one + 46u, one_length, other + 46u, other_length);
}

int zip_archive_index(ZipArchive *archive, EngineError *error)
{
    if (!ZIP_HELD(zip_fits_memory((archive->entries + 1ull) * sizeof(unsigned long long)), &archive->entries, error,
                  ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    unsigned long long *const entry_at = malloc((size_t)(archive->entries + 1ull) * sizeof(unsigned long long));
    if (!ZIP_HELD(entry_at != NULL, &archive->entries, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    unsigned long long at = 0ull;
    for (unsigned long long slot = 0ull; slot < archive->entries; slot += 1ull)
    {
        ZipEntry entry = zip_empty_entry;
        entry_at[slot] = at;
        if (!zip_entry_next(archive, &at, &entry, error))
        {
            free(entry_at);
            return 0;
        }
    }
    s_zip_sorting = archive->directory;
    qsort(entry_at, (size_t)archive->entries, sizeof(unsigned long long), zip_order_entries);
    s_zip_sorting = NULL;
    free(archive->entry_at);
    archive->entry_at = entry_at;
    return 1;
}

static int zip_folder_compare(const ZipArchive *archive, unsigned long long slot, const char *folder,
                              unsigned long long folder_length)
{
    const unsigned char *const fixed = archive->directory + archive->entry_at[slot];
    unsigned long long start = 0ull;
    unsigned long long span = 0ull;
    zip_folder_of(fixed + 46u, zip_load(fixed + 28u, 2u), &start, &span);
    return zip_order_spans(fixed + 46u + start, span, (const unsigned char *)folder, folder_length);
}

int zip_folder_find(const ZipArchive *archive, const char *folder, unsigned long long *first, unsigned long long *count)
{
    *first = 0ull;
    *count = 0ull;
    if ((archive->entry_at == NULL) || (folder == NULL))
    {
        return 0;
    }
    const unsigned long long folder_length = strlen(folder);
    unsigned long long low = 0ull;
    unsigned long long high = archive->entries;
    while (low < high)
    {
        const unsigned long long middle = low + ((high - low) / 2ull);
        if (zip_folder_compare(archive, middle, folder, folder_length) < 0)
        {
            low = middle + 1ull;
        }
        else
        {
            high = middle;
        }
    }
    unsigned long long past = low;
    while ((past < archive->entries) && (zip_folder_compare(archive, past, folder, folder_length) == 0))
    {
        past += 1ull;
    }
    *first = low;
    *count = past - low;
    return 1;
}

int zip_entry_at(const ZipArchive *archive, unsigned long long slot, ZipEntry *entry, EngineError *error)
{
    if (!ZIP_HELD((archive->entry_at != NULL) && (slot < archive->entries), &slot, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned long long at = archive->entry_at[slot];
    return zip_entry_next(archive, &at, entry, error);
}

typedef struct
{
    char path[ZIP_PATH_ROOM];
    ZipArchive archive;
    int held;
} ZipHeld;

static ZipHeld s_zip_held;

const ZipArchive *zip_archive_held(const EngineIngestTools *tools, const char *path, EngineError *error)
{
    if (error == NULL)
    {
        return NULL;
    }
    if (!ZIP_HELD((path != NULL) && (strlen(path) < ZIP_PATH_ROOM), &path, error, ENGINE_ERROR_REQUEST))
    {
        return NULL;
    }
    ZipHeld *const held = &s_zip_held;
    if ((held->held != 0) && (strcmp(held->path, path) == 0))
    {
        return &held->archive;
    }
    zip_held_release();
    if (!zip_archive_open(tools, path, &held->archive, error) || !zip_archive_index(&held->archive, error))
    {
        zip_archive_release(&held->archive);
        return NULL;
    }
    memcpy(held->path, path, strlen(path) + 1u);
    held->held = 1;
    return &held->archive;
}

void zip_held_release(void)
{
    ZipHeld *const held = &s_zip_held;
    if (held->held != 0)
    {
        zip_archive_release(&held->archive);
    }
    memset(held, 0, sizeof(*held));
}

int zip_member_data(const EngineIngestTools *tools, const char *path, const ZipArchive *archive, const ZipEntry *entry,
                    unsigned long long *data_start, EngineError *error)
{
    unsigned char local[30u];
    if (!ZIP_HELD(((entry->flags & 0x41ull) == 0ull) && ((entry->method == 0ull) || (entry->method == 8ull))
                      && (entry->local_offset <= archive->file_bytes)
                      && ((archive->file_bytes - entry->local_offset) >= 30ull),
                  entry, error, ENGINE_ERROR_REQUEST)
        || !ZIP_IO(zip_fetch(tools, path, entry->local_offset, 30ull, local), local, error)
        || !ZIP_HELD(memcmp(local, zip_local, sizeof zip_local) == 0, local, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long start = entry->local_offset + 30ull + zip_load(local + 26u, 2u) + zip_load(local + 28u, 2u);
    if (!ZIP_HELD((start <= archive->file_bytes) && (entry->compressed <= (archive->file_bytes - start)), local, error,
                  ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    *data_start = start;
    return 1;
}

long long zip_member_read(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                          const ZipEntry *entry, unsigned char *out, unsigned long long room, EngineError *error)
{
    if (error == NULL)
    {
        return ZIP_REFUSED;
    }
    unsigned long long data_start = 0ull;
    if (!ZIP_HELD((tools != NULL) && (path != NULL) && (archive != NULL) && (entry != NULL) && (out != NULL)
                      && (entry->uncompressed <= room) && zip_fits_memory(entry->uncompressed)
                      && zip_fits_memory(entry->compressed + 1ull),
                  entry, error, ENGINE_ERROR_REQUEST)
        || !zip_member_data(tools, path, archive, entry, &data_start, error))
    {
        return ZIP_REFUSED;
    }
    if (entry->method == 0ull)
    {
        if (!ZIP_HELD(entry->compressed == entry->uncompressed, entry, error, ENGINE_ERROR_REQUEST)
            || !ZIP_IO(zip_fetch(tools, path, data_start, entry->uncompressed, out), out, error))
        {
            return ZIP_REFUSED;
        }
    }
    else
    {
        const EngineBytesDecode decode = tools->decode[ENGINE_CODEC_DEFLATE];
        if (!ZIP_HELD(decode != NULL, tools, error, ENGINE_ERROR_REQUEST))
        {
            return ZIP_REFUSED;
        }
        unsigned char *const packed = malloc((size_t)entry->compressed + 1u);
        int good = ZIP_HELD(packed != NULL, entry, error, ENGINE_ERROR_RESOURCE)
                && ZIP_IO(zip_fetch(tools, path, data_start, entry->compressed, packed), packed, error);
        if (good)
        {
            const EngineBytesRequest request = {packed, entry->compressed, out, entry->uncompressed};
            const long long made = decode(&request);
            // a non-negative long long count converts to unsigned long long exactly
            good = ZIP_HELD((made >= 0LL) && ((unsigned long long)made == entry->uncompressed), packed, error,
                            ENGINE_ERROR_REQUEST);
        }
        free(packed);
        if (!good)
        {
            return ZIP_REFUSED;
        }
    }
    if (!ZIP_HELD(zip_crc32(out, entry->uncompressed) == entry->crc, &entry->crc, error, ENGINE_ERROR_REQUEST))
    {
        return ZIP_REFUSED;
    }
    // the uncompressed size fits memory, and so fits a long long
    return (long long)entry->uncompressed;
}
