// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tiff_io.c: errors, file access and directory entries
#include "tiff_internal.h"

int tiff_fail(TiffFile *file, const char *reason)
{
    file->reason = (file->reason == NULL) ? reason : file->reason;
    return file->reason == NULL;
}

int tiff_fail_number(TiffFile *file, const char *before, unsigned long long number, const char *after)
{
    if (file->reason == NULL)
    {
        snprintf(file->detail, sizeof(file->detail), "%s %llu %s", before, number, after);
        file->reason = file->detail;
    }
    return file->reason == NULL;
}

int tiff_fail_named(TiffFile *file, const char *before, const char *name)
{
    if (file->reason == NULL)
    {
        snprintf(file->detail, sizeof(file->detail), "%s %s", before, name);
        file->reason = file->detail;
    }
    return file->reason == NULL;
}

int tiff_multiply(TiffFile *file, unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (~0ull / left)))
    {
        return tiff_fail(file, "a size that does not fit in 64 bits");
    }
    *product = left * right;
    return file->reason == NULL;
}

int tiff_reserve(TiffFile *file, unsigned char **buffer, unsigned long long *capacity, unsigned long long needed)
{
    if ((file->reason != NULL) || ((*buffer != NULL) && (needed <= *capacity)))
    {
        return file->reason == NULL;
    }
    const unsigned long long asked = (needed == 0ull) ? 1ull : needed;
    if ((unsigned long long)(size_t)asked != asked)
    {
        return tiff_fail(file, "a buffer larger than this machine can address");
    }
    free(*buffer);
    *buffer = (unsigned char *)malloc((size_t)asked);
    *capacity = (*buffer != NULL) ? asked : 0ull;
    return (*buffer != NULL) ? (file->reason == NULL) : tiff_fail(file, "out of memory");
}

int tiff_fetch(TiffFile *file, unsigned long long offset, unsigned long long bytes, unsigned char *out)
{
    if ((file->reason != NULL) || (bytes == 0ull))
    {
        return file->reason == NULL;
    }
    if ((offset > file->file_bytes) || (bytes > (file->file_bytes - offset)))
    {
        return tiff_fail(file, "the file ends before data it points to");
    }
    const EngineFileRange range = {file->path, offset, bytes, out};
    const long long got = file->tools->read(&range);
    if ((got < 0LL) || ((unsigned long long)got != bytes))
    {
        return tiff_fail(file, "the reader could not read the file");
    }
    return file->reason == NULL;
}

unsigned long long tiff_unpack(const TiffFile *file, const unsigned char *raw, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int position = 0u; position < width; position += 1u)
    {
        const unsigned int shift = file->big_endian ? (8u * (width - 1u - position)) : (8u * position);
        value |= ((unsigned long long)raw[position]) << shift;
    }
    return value;
}

int tiff_open(TiffFile *file, const char *path, const char *member, const EngineIngestTools *tools)
{
    memset(file, 0, sizeof(*file));
    file->path = path;
    file->tools = tools;
    if (member != NULL)
    {
        return tiff_fail(file, "a TIFF holds one array, so member must be NULL");
    }
    const long long size = tools->size(path);
    if (size < 8LL)
    {
        return tiff_fail(file, "the file is too short to be a TIFF");
    }
    file->file_bytes = (unsigned long long)size;
    unsigned char header[16u] = {0u};
    if (!tiff_fetch(file, 0ull, 8ull, header))
    {
        return file->reason == NULL;
    }
    const unsigned int little = (header[0u] == 'I') && (header[1u] == 'I');
    const unsigned int big = (header[0u] == 'M') && (header[1u] == 'M');
    if (!little && !big)
    {
        return tiff_fail(file, "the file does not begin with a TIFF byte order mark");
    }
    file->big_endian = big;
    const unsigned long long version = tiff_unpack(file, &header[2u], 2u);
    if (version == 42ull)
    {
        file->first_ifd = tiff_unpack(file, &header[4u], 4u);
    }
    else if (version == 43ull)
    {
        file->bigtiff = 1u;
        if (!tiff_fetch(file, 0ull, 16ull, header))
        {
            return file->reason == NULL;
        }
        if ((tiff_unpack(file, &header[4u], 2u) != 8ull) || (tiff_unpack(file, &header[6u], 2u) != 0ull))
        {
            return tiff_fail(file, "a BigTIFF header with an offset size other than 8");
        }
        file->first_ifd = tiff_unpack(file, &header[8u], 8u);
    }
    else
    {
        return tiff_fail_number(file, "TIFF version", version, "is not supported");
    }
    return (file->first_ifd == 0ull) ? tiff_fail(file, "the file has no pages") : (file->reason == NULL);
}

unsigned int tiff_type_bytes(unsigned int type)
{
    return ((type == 1u) || (type == 2u) || (type == 6u) || (type == 7u))                                        ? 1u
           : ((type == 3u) || (type == 8u))                                                                      ? 2u
           : ((type == 4u) || (type == 9u) || (type == 11u) || (type == 13u))                                    ? 4u
           : ((type == 5u) || (type == 10u) || (type == 12u) || (type == 16u) || (type == 17u) || (type == 18u)) ? 8u
                                                                                                                 : 0u;
}

int tiff_entry_bytes(TiffFile *file, const TiffEntry *entry, unsigned long long total, unsigned char *out)
{
    const unsigned int inline_bytes = file->bigtiff ? 8u : 4u;
    if ((file->reason == NULL) && (total <= inline_bytes))
    {
        memcpy(out, entry->value, (size_t)total);
        return file->reason == NULL;
    }
    return tiff_fetch(file, tiff_unpack(file, entry->value, inline_bytes), total, out);
}

int tiff_entry_integers(TiffFile *file, const TiffEntry *entry, unsigned long long *values, unsigned long long count)
{
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    const unsigned int type = entry->type;
    const unsigned int width = (type == 1u)                       ? 1u
                               : (type == 3u)                     ? 2u
                               : ((type == 4u) || (type == 13u))  ? 4u
                               : ((type == 16u) || (type == 18u)) ? 8u
                                                                  : 0u;
    if (width == 0u)
    {
        return tiff_fail_number(file, "a tag of type", type, "where an integer belongs");
    }
    if (entry->count != count)
    {
        return tiff_fail(file, "a tag holds a different number of values than the image needs");
    }
    if (count > file->file_bytes)
    {
        return tiff_fail(file, "a tag holds more values than the file has bytes");
    }
    unsigned char *const raw = (unsigned char *)values;
    if (!tiff_entry_bytes(file, entry, count * width, raw))
    {
        return file->reason == NULL;
    }
    for (unsigned long long position = count; position > 0ull; position -= 1ull)
    {
        const unsigned long long element = position - 1ull;
        values[element] = tiff_unpack(file, &raw[element * width], width);
    }
    return file->reason == NULL;
}

int tiff_entry_scalar(TiffFile *file, const TiffEntry *entry, unsigned long long fallback, unsigned long long *value)
{
    *value = fallback;
    return entry->present ? tiff_entry_integers(file, entry, value, 1ull) : (file->reason == NULL);
}

int tiff_ifd_next(TiffFile *file, unsigned long long ifd, unsigned long long *next)
{
    const unsigned int count_bytes = file->bigtiff ? 8u : 2u;
    const unsigned int value_bytes = file->bigtiff ? 8u : 4u;
    const unsigned long long entry_bytes = 4ull + (2ull * value_bytes);
    unsigned char raw[8u] = {0u};
    *next = 0ull;
    if (!tiff_fetch(file, ifd, count_bytes, raw))
    {
        return file->reason == NULL;
    }
    const unsigned long long entries = tiff_unpack(file, raw, count_bytes);
    if ((entries == 0ull) || (entries > TIFF_ENTRIES_MAX))
    {
        return tiff_fail(file, "an IFD with no tags, or more tags than any image has");
    }
    if (!tiff_fetch(file, ifd + count_bytes + (entries * entry_bytes), value_bytes, raw))
    {
        return file->reason == NULL;
    }
    *next = tiff_unpack(file, raw, value_bytes);
    return file->reason == NULL;
}
