// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zip_index.c: the index, folders and member data
#include "zip_internal.h"

static const unsigned char zip_local[4u] = {'P', 'K', 0x03u, 0x04u};

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
    if (!ZIP_CHECK(zip_fits_memory((archive->entries + 1ull) * sizeof(unsigned long long)), &archive->entries, error,
                   ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    unsigned long long *const entry_at = malloc((size_t)(archive->entries + 1ull) * sizeof(unsigned long long));
    if (!ZIP_CHECK(entry_at != NULL, &archive->entries, error, ENGINE_ERROR_RESOURCE))
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
    unsigned long long end = low;
    while ((end < archive->entries) && (zip_folder_compare(archive, end, folder, folder_length) == 0))
    {
        end += 1ull;
    }
    *first = low;
    *count = end - low;
    return 1;
}

int zip_entry_at(const ZipArchive *archive, unsigned long long slot, ZipEntry *entry, EngineError *error)
{
    if (!ZIP_CHECK((archive->entry_at != NULL) && (slot < archive->entries), &slot, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    unsigned long long at = archive->entry_at[slot];
    return zip_entry_next(archive, &at, entry, error);
}

static ZipResident s_zip_resident;

const ZipArchive *zip_archive_cached(const EngineIngestTools *tools, const char *path, EngineError *error)
{
    if (error == NULL)
    {
        return NULL;
    }
    if (!ZIP_CHECK((path != NULL) && (strlen(path) < ZIP_PATH_CAPACITY), &path, error, ENGINE_ERROR_REQUEST))
    {
        return NULL;
    }
    ZipResident *const resident = &s_zip_resident;
    if ((resident->valid != 0) && (strcmp(resident->path, path) == 0))
    {
        return &resident->archive;
    }
    zip_resident_release();
    if (!zip_archive_open(tools, path, &resident->archive, error) || !zip_archive_index(&resident->archive, error))
    {
        zip_archive_release(&resident->archive);
        return NULL;
    }
    memcpy(resident->path, path, strlen(path) + 1u);
    resident->valid = 1;
    return &resident->archive;
}

void zip_resident_release(void)
{
    ZipResident *const resident = &s_zip_resident;
    if (resident->valid != 0)
    {
        zip_archive_release(&resident->archive);
    }
    memset(resident, 0, sizeof(*resident));
}

int zip_member_data(const EngineIngestTools *tools, const char *path, const ZipArchive *archive, const ZipEntry *entry,
                    unsigned long long *data_start, EngineError *error)
{
    unsigned char local[30u];
    if (!ZIP_CHECK(((entry->flags & 0x41ull) == 0ull) && ((entry->method == 0ull) || (entry->method == 8ull)) &&
                       (entry->local_offset <= archive->file_bytes) &&
                       ((archive->file_bytes - entry->local_offset) >= 30ull),
                   entry, error, ENGINE_ERROR_REQUEST) ||
        !ZIP_IO(zip_fetch(tools, path, entry->local_offset, 30ull, local), local, error) ||
        !ZIP_CHECK(memcmp(local, zip_local, sizeof zip_local) == 0, local, error, ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    const unsigned long long start =
        entry->local_offset + 30ull + zip_load(local + 26u, 2u) + zip_load(local + 28u, 2u);
    if (!ZIP_CHECK((start <= archive->file_bytes) && (entry->compressed <= (archive->file_bytes - start)), local, error,
                   ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    *data_start = start;
    return 1;
}

long long zip_member_read(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                          const ZipEntry *entry, unsigned char *out, unsigned long long capacity, EngineError *error)
{
    if (error == NULL)
    {
        return ZIP_ERROR;
    }
    unsigned long long data_start = 0ull;
    if (!ZIP_CHECK((tools != NULL) && (path != NULL) && (archive != NULL) && (entry != NULL) && (out != NULL) &&
                       (entry->uncompressed <= capacity) && zip_fits_memory(entry->uncompressed) &&
                       zip_fits_memory(entry->compressed + 1ull),
                   entry, error, ENGINE_ERROR_REQUEST) ||
        !zip_member_data(tools, path, archive, entry, &data_start, error))
    {
        return ZIP_ERROR;
    }
    if (entry->method == 0ull)
    {
        if (!ZIP_CHECK(entry->compressed == entry->uncompressed, entry, error, ENGINE_ERROR_REQUEST) ||
            !ZIP_IO(zip_fetch(tools, path, data_start, entry->uncompressed, out), out, error))
        {
            return ZIP_ERROR;
        }
    }
    else
    {
        const EngineBytesDecode decode = tools->decode[ENGINE_CODEC_DEFLATE];
        if (!ZIP_CHECK(decode != NULL, tools, error, ENGINE_ERROR_REQUEST))
        {
            return ZIP_ERROR;
        }
        unsigned char *const packed = malloc((size_t)entry->compressed + 1u);
        int ok = ZIP_CHECK(packed != NULL, entry, error, ENGINE_ERROR_RESOURCE) &&
                 ZIP_IO(zip_fetch(tools, path, data_start, entry->compressed, packed), packed, error);
        if (ok)
        {
            const EngineBytesRequest request = {packed, entry->compressed, out, entry->uncompressed};
            const long long made = decode(&request);
            // a non-negative long long count converts to unsigned long long exactly
            ok = ZIP_CHECK((made >= 0LL) && ((unsigned long long)made == entry->uncompressed), packed, error,
                           ENGINE_ERROR_REQUEST);
        }
        free(packed);
        if (!ok)
        {
            return ZIP_ERROR;
        }
    }
    if (!ZIP_CHECK(zip_crc32(out, entry->uncompressed) == entry->crc, &entry->crc, error, ENGINE_ERROR_REQUEST))
    {
        return ZIP_ERROR;
    }
    // the uncompressed size fits memory, and so fits a long long
    return (long long)entry->uncompressed;
}
