// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tiff.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TIFF_LEADING_AXES 3u
#define TIFF_ENTRIES_MAX 65535ull
#define TIFF_TILE_SAMPLES_MAX 16777216ull
#define TIFF_LZW_CODES 4096u
#define TIFF_LZW_CLEAR 256u
#define TIFF_LZW_END 257u
#define TIFF_LZW_FIRST 258u
#define TIFF_LZW_WIDTH_FIRST 9u
#define TIFF_LZW_WIDTH_LAST 12u

typedef enum
{
    TIFF_TAG_WIDTH = 0,
    TIFF_TAG_LENGTH = 1,
    TIFF_TAG_BITS_PER_SAMPLE = 2,
    TIFF_TAG_COMPRESSION = 3,
    TIFF_TAG_FILL_ORDER = 4,
    TIFF_TAG_DESCRIPTION = 5,
    TIFF_TAG_STRIP_OFFSETS = 6,
    TIFF_TAG_SAMPLES_PER_PIXEL = 7,
    TIFF_TAG_ROWS_PER_STRIP = 8,
    TIFF_TAG_STRIP_BYTE_COUNTS = 9,
    TIFF_TAG_PLANAR_CONFIGURATION = 10,
    TIFF_TAG_PREDICTOR = 11,
    TIFF_TAG_TILE_WIDTH = 12,
    TIFF_TAG_TILE_LENGTH = 13,
    TIFF_TAG_TILE_OFFSETS = 14,
    TIFF_TAG_TILE_BYTE_COUNTS = 15,
    TIFF_TAG_SAMPLE_FORMAT = 16,
    TIFF_TAGS = 17
} TiffTag;

static const unsigned long long tiff_tag_numbers[TIFF_TAGS] = {256ull, 257ull, 258ull, 259ull, 266ull, 270ull,
                                                               273ull, 277ull, 278ull, 279ull, 284ull, 317ull,
                                                               322ull, 323ull, 324ull, 325ull, 339ull};

typedef struct
{
    const char *path;
    const EngineIngestTools *tools;
    unsigned long long file_bytes;
    unsigned long long first_ifd;
    unsigned int bigtiff;
    unsigned int big_endian;
    const char *reason;
    char detail[160u];
} TiffFile;

typedef struct
{
    unsigned int present;
    unsigned int type;
    unsigned long long count;
    unsigned char value[8u];
} TiffEntry;

typedef struct
{
    unsigned long long width;
    unsigned long long height;
    unsigned long long page_bytes;
    unsigned int element_bytes;
    EngineElementKind element_kind;
    unsigned long long compression;
    unsigned long long predictor;
    unsigned long long chunk_width;
    unsigned long long chunk_height;
    unsigned long long chunks_across;
    unsigned long long chunks_down;
    TiffEntry offsets;
    TiffEntry byte_counts;
    TiffEntry description;
    unsigned long long next;
} TiffPage;

typedef struct
{
    unsigned int leading;
    unsigned long long extent[TIFF_LEADING_AXES];
    unsigned long long stride[TIFF_LEADING_AXES];
    char axes[TIFF_LEADING_AXES];
} TiffLayout;

typedef struct
{
    unsigned long long *offsets;
    unsigned long long count;
    unsigned long long room;
    unsigned long long highest;
} TiffChain;

typedef struct
{
    unsigned char *packed;
    unsigned long long packed_room;
    unsigned char *chunk;
    unsigned long long chunk_room;
} TiffScratch;

static int tiff_fail(TiffFile *file, const char *reason)
{
    file->reason = (file->reason == NULL) ? reason : file->reason;
    return file->reason == NULL;
}

static int tiff_fail_number(TiffFile *file, const char *before, unsigned long long number, const char *after)
{
    if (file->reason == NULL)
    {
        snprintf(file->detail, sizeof(file->detail), "%s %llu %s", before, number, after);
        file->reason = file->detail;
    }
    return file->reason == NULL;
}

static int tiff_fail_named(TiffFile *file, const char *before, const char *name)
{
    if (file->reason == NULL)
    {
        snprintf(file->detail, sizeof(file->detail), "%s %s", before, name);
        file->reason = file->detail;
    }
    return file->reason == NULL;
}

static int tiff_multiply(TiffFile *file, unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (~0ull / left)))
    {
        return tiff_fail(file, "a size that does not fit in 64 bits");
    }
    *product = left * right;
    return file->reason == NULL;
}

static int tiff_room(TiffFile *file, unsigned char **buffer, unsigned long long *room, unsigned long long needed)
{
    if ((file->reason != NULL) || ((*buffer != NULL) && (needed <= *room)))
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
    *room = (*buffer != NULL) ? asked : 0ull;
    return (*buffer != NULL) ? (file->reason == NULL) : tiff_fail(file, "out of memory");
}

static int tiff_fetch(TiffFile *file, unsigned long long offset, unsigned long long bytes, unsigned char *out)
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

static unsigned long long tiff_unpack(const TiffFile *file, const unsigned char *raw, unsigned int width)
{
    unsigned long long value = 0ull;
    for (unsigned int position = 0u; position < width; position += 1u)
    {
        const unsigned int shift = file->big_endian ? (8u * (width - 1u - position)) : (8u * position);
        value |= ((unsigned long long)raw[position]) << shift;
    }
    return value;
}

static int tiff_open(TiffFile *file, const char *path, const char *member, const EngineIngestTools *tools)
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

static unsigned int tiff_type_bytes(unsigned int type)
{
    return ((type == 1u) || (type == 2u) || (type == 6u) || (type == 7u))   ? 1u
         : ((type == 3u) || (type == 8u))                                    ? 2u
         : ((type == 4u) || (type == 9u) || (type == 11u) || (type == 13u))  ? 4u
         : ((type == 5u) || (type == 10u) || (type == 12u) || (type == 16u) || (type == 17u) || (type == 18u)) ? 8u
                                                                             : 0u;
}

static int tiff_entry_bytes(TiffFile *file, const TiffEntry *entry, unsigned long long total, unsigned char *out)
{
    const unsigned int inline_bytes = file->bigtiff ? 8u : 4u;
    if ((file->reason == NULL) && (total <= inline_bytes))
    {
        memcpy(out, entry->value, (size_t)total);
        return file->reason == NULL;
    }
    return tiff_fetch(file, tiff_unpack(file, entry->value, inline_bytes), total, out);
}

static int tiff_entry_integers(TiffFile *file, const TiffEntry *entry, unsigned long long *values, unsigned long long count)
{
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    const unsigned int type = entry->type;
    const unsigned int width = (type == 1u)                    ? 1u
                             : (type == 3u)                    ? 2u
                             : ((type == 4u) || (type == 13u)) ? 4u
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

static int tiff_entry_scalar(TiffFile *file, const TiffEntry *entry, unsigned long long fallback, unsigned long long *value)
{
    *value = fallback;
    return entry->present ? tiff_entry_integers(file, entry, value, 1ull) : (file->reason == NULL);
}

static int tiff_ifd_next(TiffFile *file, unsigned long long ifd, unsigned long long *next)
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

static int tiff_page_shape(TiffFile *file, TiffPage *page, const TiffEntry *found)
{
    unsigned long long bits = 1ull;
    unsigned long long fill_order = 1ull;
    unsigned long long samples = 1ull;
    unsigned long long rows_per_strip = ~0ull;
    unsigned long long planar = 1ull;
    unsigned long long sample_format = 1ull;
    unsigned long long tile_width = 0ull;
    unsigned long long tile_length = 0ull;
    tiff_entry_scalar(file, &found[TIFF_TAG_SAMPLES_PER_PIXEL], 1ull, &samples);
    if ((file->reason == NULL) && (samples != 1ull))
    {
        return tiff_fail_number(file, "SamplesPerPixel", samples, "is not supported; only 1 is");
    }
    tiff_entry_scalar(file, &found[TIFF_TAG_WIDTH], 0ull, &page->width);
    tiff_entry_scalar(file, &found[TIFF_TAG_LENGTH], 0ull, &page->height);
    tiff_entry_scalar(file, &found[TIFF_TAG_BITS_PER_SAMPLE], 1ull, &bits);
    tiff_entry_scalar(file, &found[TIFF_TAG_COMPRESSION], 1ull, &page->compression);
    tiff_entry_scalar(file, &found[TIFF_TAG_FILL_ORDER], 1ull, &fill_order);
    tiff_entry_scalar(file, &found[TIFF_TAG_ROWS_PER_STRIP], ~0ull, &rows_per_strip);
    tiff_entry_scalar(file, &found[TIFF_TAG_PLANAR_CONFIGURATION], 1ull, &planar);
    tiff_entry_scalar(file, &found[TIFF_TAG_PREDICTOR], 1ull, &page->predictor);
    tiff_entry_scalar(file, &found[TIFF_TAG_SAMPLE_FORMAT], 1ull, &sample_format);
    tiff_entry_scalar(file, &found[TIFF_TAG_TILE_WIDTH], 0ull, &tile_width);
    tiff_entry_scalar(file, &found[TIFF_TAG_TILE_LENGTH], 0ull, &tile_length);
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if ((page->width == 0ull) || (page->height == 0ull))
    {
        return tiff_fail(file, "a page with no ImageWidth or ImageLength");
    }
    if ((bits != 8ull) && (bits != 16ull) && (bits != 32ull))
    {
        return tiff_fail_number(file, "BitsPerSample", bits, "is not supported; only 8, 16 and 32 are");
    }
    if ((sample_format < 1ull) || (sample_format > 3ull) || ((sample_format == 3ull) && (bits == 8ull)))
    {
        return tiff_fail_number(file, "SampleFormat", sample_format, "is not supported at this BitsPerSample");
    }
    const unsigned long long compression = page->compression;
    if ((compression != 1ull) && (compression != 5ull) && (compression != 8ull) && (compression != 32946ull)
        && (compression != 32773ull) && (compression != 50000ull))
    {
        return tiff_fail_number(file, "Compression", compression, "is not supported");
    }
    if ((page->predictor != 1ull) && (page->predictor != 2ull))
    {
        return tiff_fail_number(file, "Predictor", page->predictor, "is not supported");
    }
    if ((planar != 1ull) && (planar != 2ull))
    {
        return tiff_fail_number(file, "PlanarConfiguration", planar, "is not supported");
    }
    if (fill_order != 1ull)
    {
        return tiff_fail_number(file, "FillOrder", fill_order, "is not supported");
    }
    page->element_bytes = (unsigned int)(bits / 8ull);
    page->element_kind = (sample_format == 1ull)   ? ENGINE_ELEMENT_UNSIGNED
                       : (sample_format == 2ull)   ? ENGINE_ELEMENT_SIGNED
                                                   : ENGINE_ELEMENT_FLOAT;
    unsigned long long samples_per_page = 0ull;
    tiff_multiply(file, page->width, page->height, &samples_per_page);
    tiff_multiply(file, samples_per_page, page->element_bytes, &page->page_bytes);
    const unsigned int tiled = found[TIFF_TAG_TILE_WIDTH].present || found[TIFF_TAG_TILE_LENGTH].present
                            || found[TIFF_TAG_TILE_OFFSETS].present || found[TIFF_TAG_TILE_BYTE_COUNTS].present;
    if (tiled)
    {
        if ((tile_width == 0ull) || (tile_length == 0ull) || !found[TIFF_TAG_TILE_OFFSETS].present
            || !found[TIFF_TAG_TILE_BYTE_COUNTS].present)
        {
            return tiff_fail(file, "a tiled page missing TileWidth, TileLength, TileOffsets or TileByteCounts");
        }
        unsigned long long tile_samples = 0ull;
        tiff_multiply(file, tile_width, tile_length, &tile_samples);
        if ((file->reason == NULL) && (tile_samples > samples_per_page) && (tile_samples > TIFF_TILE_SAMPLES_MAX))
        {
            return tiff_fail(file, "a tile far larger than its page");
        }
        page->chunk_width = tile_width;
        page->chunk_height = tile_length;
        page->offsets = found[TIFF_TAG_TILE_OFFSETS];
        page->byte_counts = found[TIFF_TAG_TILE_BYTE_COUNTS];
    }
    else
    {
        if (!found[TIFF_TAG_STRIP_OFFSETS].present || !found[TIFF_TAG_STRIP_BYTE_COUNTS].present)
        {
            return tiff_fail(file, "a page missing StripOffsets or StripByteCounts");
        }
        if (rows_per_strip == 0ull)
        {
            return tiff_fail(file, "a RowsPerStrip of 0");
        }
        page->chunk_width = page->width;
        page->chunk_height = (rows_per_strip < page->height) ? rows_per_strip : page->height;
        page->offsets = found[TIFF_TAG_STRIP_OFFSETS];
        page->byte_counts = found[TIFF_TAG_STRIP_BYTE_COUNTS];
    }
    page->chunks_across = ((page->width - 1ull) / page->chunk_width) + 1ull;
    page->chunks_down = ((page->height - 1ull) / page->chunk_height) + 1ull;
    unsigned long long chunk_samples = 0ull;
    unsigned long long chunk_bytes = 0ull;
    tiff_multiply(file, page->chunk_width, page->chunk_height, &chunk_samples);
    tiff_multiply(file, chunk_samples, page->element_bytes, &chunk_bytes);
    return file->reason == NULL;
}

static int tiff_page(TiffFile *file, unsigned long long ifd, TiffPage *page)
{
    memset(page, 0, sizeof(*page));
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    const unsigned int count_bytes = file->bigtiff ? 8u : 2u;
    const unsigned int value_bytes = file->bigtiff ? 8u : 4u;
    const unsigned long long entry_bytes = 4ull + (2ull * value_bytes);
    unsigned char head[8u] = {0u};
    if (!tiff_fetch(file, ifd, count_bytes, head))
    {
        return file->reason == NULL;
    }
    const unsigned long long entries = tiff_unpack(file, head, count_bytes);
    if ((entries == 0ull) || (entries > TIFF_ENTRIES_MAX))
    {
        return tiff_fail(file, "an IFD with no tags, or more tags than any image has");
    }
    const unsigned long long table_bytes = (entries * entry_bytes) + value_bytes;
    unsigned char *const table = (unsigned char *)malloc((size_t)table_bytes);
    if (table == NULL)
    {
        return tiff_fail(file, "out of memory");
    }
    TiffEntry found[TIFF_TAGS];
    memset(found, 0, sizeof(found));
    if (tiff_fetch(file, ifd + count_bytes, table_bytes, table))
    {
        for (unsigned long long entry = 0ull; entry < entries; entry += 1ull)
        {
            const unsigned char *const raw = &table[entry * entry_bytes];
            const unsigned long long tag = tiff_unpack(file, raw, 2u);
            const unsigned int type = (unsigned int)tiff_unpack(file, &raw[2u], 2u);
            const unsigned long long count = tiff_unpack(file, &raw[4u], value_bytes);
            const unsigned long long place = tiff_unpack(file, &raw[4u + value_bytes], value_bytes);
            const unsigned long long width = tiff_type_bytes(type);
            const int outside = (width != 0ull) && (count > (value_bytes / width))
                             && ((count > file->file_bytes) || (place > file->file_bytes)
                                 || ((count * width) > (file->file_bytes - place)));
            if (outside)
            {
                tiff_fail_number(file, "the values of tag", tag, "run past the end of the file");
            }
            for (unsigned int slot = 0u; slot < (unsigned int)TIFF_TAGS; slot += 1u)
            {
                if (tag == tiff_tag_numbers[slot])
                {
                    found[slot].present = 1u;
                    found[slot].type = type;
                    found[slot].count = count;
                    memcpy(found[slot].value, &raw[4u + value_bytes], value_bytes);
                }
            }
        }
        page->next = tiff_unpack(file, &table[entries * entry_bytes], value_bytes);
    }
    free(table);
    page->description = found[TIFF_TAG_DESCRIPTION];
    return tiff_page_shape(file, page, found);
}

static int tiff_page_same(const TiffPage *first, const TiffPage *page)
{
    return (first->width == page->width) && (first->height == page->height)
        && (first->element_bytes == page->element_bytes) && (first->element_kind == page->element_kind);
}

static int tiff_page_chunks(TiffFile *file, const TiffPage *page, unsigned long long **offsets, unsigned long long **counts)
{
    *offsets = NULL;
    *counts = NULL;
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    const unsigned long long chunks = page->chunks_across * page->chunks_down;
    if (chunks > file->file_bytes)
    {
        return tiff_fail(file, "more strips or tiles than the file has bytes");
    }
    *offsets = (unsigned long long *)malloc((size_t)(chunks * sizeof(unsigned long long)));
    *counts = (unsigned long long *)malloc((size_t)(chunks * sizeof(unsigned long long)));
    if ((*offsets == NULL) || (*counts == NULL))
    {
        tiff_fail(file, "out of memory");
    }
    tiff_entry_integers(file, &page->offsets, *offsets, chunks);
    tiff_entry_integers(file, &page->byte_counts, *counts, chunks);
    for (unsigned long long chunk = 0ull; (file->reason == NULL) && (chunk < chunks); chunk += 1ull)
    {
        const unsigned long long offset = (*offsets)[chunk];
        const unsigned long long bytes = (*counts)[chunk];
        if ((offset > file->file_bytes) || (bytes > (file->file_bytes - offset)))
        {
            tiff_fail(file, "a strip or tile runs past the end of the file");
        }
    }
    if (file->reason != NULL)
    {
        free(*offsets);
        free(*counts);
        *offsets = NULL;
        *counts = NULL;
    }
    return file->reason == NULL;
}

static long long tiff_lzw_decode(const EngineBytesRequest *request)
{
    if ((request->in_bytes >= 2ull) && (request->in[0u] == 0u) && ((request->in[1u] & 1u) != 0u))
    {
        return ENGINE_BYTES_REFUSED;
    }
    unsigned short prefix[TIFF_LZW_CODES];
    unsigned short length[TIFF_LZW_CODES];
    unsigned char suffix[TIFF_LZW_CODES];
    unsigned char head[TIFF_LZW_CODES];
    for (unsigned int code = 0u; code < TIFF_LZW_CODES; code += 1u)
    {
        prefix[code] = 0u;
        length[code] = (unsigned short)((code < TIFF_LZW_CLEAR) ? 1u : 0u);
        suffix[code] = (unsigned char)(code & 0xFFu);
        head[code] = (unsigned char)(code & 0xFFu);
    }
    unsigned long long produced = 0ull;
    unsigned long long at = 0ull;
    unsigned long accumulator = 0ul;
    unsigned int held = 0u;
    unsigned int width = TIFF_LZW_WIDTH_FIRST;
    unsigned int next = TIFF_LZW_FIRST;
    unsigned int previous = TIFF_LZW_CODES;
    for (;;)
    {
        while ((held < width) && (at < request->in_bytes))
        {
            accumulator = (accumulator << 8u) | (unsigned long)request->in[at];
            at += 1ull;
            held += 8u;
        }
        if (held < width)
        {
            break;
        }
        const unsigned int code = (unsigned int)((accumulator >> (held - width)) & ((1ul << width) - 1ul));
        held -= width;
        accumulator &= (1ul << held) - 1ul;
        if (code == TIFF_LZW_CLEAR)
        {
            width = TIFF_LZW_WIDTH_FIRST;
            next = TIFF_LZW_FIRST;
            previous = TIFF_LZW_CODES;
            continue;
        }
        if (code == TIFF_LZW_END)
        {
            break;
        }
        if ((code > next) || ((previous == TIFF_LZW_CODES) && (code >= TIFF_LZW_CLEAR)))
        {
            return ENGINE_BYTES_REFUSED;
        }
        if ((previous != TIFF_LZW_CODES) && (next < TIFF_LZW_CODES))
        {
            prefix[next] = (unsigned short)previous;
            suffix[next] = (code < next) ? head[code] : head[previous];
            head[next] = head[previous];
            length[next] = (unsigned short)(length[previous] + 1u);
            next += 1u;
            if ((next >= ((1u << width) - 1u)) && (width < TIFF_LZW_WIDTH_LAST))
            {
                width += 1u;
            }
        }
        const unsigned int size = length[code];
        if (size > (request->out_room - produced))
        {
            return ENGINE_BYTES_REFUSED;
        }
        unsigned int walk = code;
        for (unsigned int remaining = size; remaining > 0u; remaining -= 1u)
        {
            request->out[produced + remaining - 1u] = suffix[walk];
            walk = prefix[walk];
        }
        produced += size;
        previous = code;
    }
    return (long long)produced;
}

static long long tiff_packbits_decode(const EngineBytesRequest *request)
{
    unsigned long long produced = 0ull;
    unsigned long long at = 0ull;
    while (at < request->in_bytes)
    {
        const unsigned int header = request->in[at];
        at += 1ull;
        if (header < 128u)
        {
            const unsigned long long literal = (unsigned long long)header + 1ull;
            if ((literal > (request->in_bytes - at)) || (literal > (request->out_room - produced)))
            {
                return ENGINE_BYTES_REFUSED;
            }
            memcpy(&request->out[produced], &request->in[at], (size_t)literal);
            at += literal;
            produced += literal;
        }
        else if (header > 128u)
        {
            const unsigned long long run = 257ull - header;
            if ((at >= request->in_bytes) || (run > (request->out_room - produced)))
            {
                return ENGINE_BYTES_REFUSED;
            }
            memset(&request->out[produced], request->in[at], (size_t)run);
            at += 1ull;
            produced += run;
        }
    }
    return (long long)produced;
}

static void tiff_swap(unsigned char *chunk, unsigned long long elements, unsigned int element_bytes)
{
    for (unsigned long long element = 0ull; element < elements; element += 1ull)
    {
        unsigned char *const bytes = &chunk[element * element_bytes];
        for (unsigned int low = 0u; low < (element_bytes / 2u); low += 1u)
        {
            const unsigned int high = element_bytes - 1u - low;
            const unsigned char kept = bytes[low];
            bytes[low] = bytes[high];
            bytes[high] = kept;
        }
    }
}

static void tiff_undo_differencing(unsigned char *chunk, unsigned long long rows, unsigned long long row_samples,
                                   unsigned int element_bytes)
{
    const unsigned long long row_bytes = row_samples * element_bytes;
    for (unsigned long long row = 0ull; row < rows; row += 1ull)
    {
        unsigned char *const line = &chunk[row * row_bytes];
        for (unsigned long long sample = element_bytes; sample < row_bytes; sample += element_bytes)
        {
            unsigned int carry = 0u;
            for (unsigned int byte = 0u; byte < element_bytes; byte += 1u)
            {
                const unsigned int sum = (unsigned int)line[sample + byte] + (unsigned int)line[sample - element_bytes + byte] + carry;
                line[sample + byte] = (unsigned char)(sum & 0xFFu);
                carry = sum >> 8u;
            }
        }
    }
}

static int tiff_chunk_decode(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long offset,
                             unsigned long long bytes, unsigned long long rows)
{
    const unsigned long long room = page->chunk_width * page->chunk_height * page->element_bytes;
    const unsigned long long needed = rows * page->chunk_width * page->element_bytes;
    const unsigned long long compression = page->compression;
    long long produced = ENGINE_BYTES_REFUSED;
    if (!tiff_room(file, &scratch->chunk, &scratch->chunk_room, room))
    {
        return file->reason == NULL;
    }
    if (compression == 1ull)
    {
        const unsigned long long taken = (bytes < room) ? bytes : room;
        produced = tiff_fetch(file, offset, taken, scratch->chunk) ? (long long)taken : ENGINE_BYTES_REFUSED;
    }
    else
    {
        const EngineBytesDecode decoder = (compression == 5ull)       ? tiff_lzw_decode
                                        : (compression == 32773ull)   ? tiff_packbits_decode
                                        : (compression == 50000ull)   ? file->tools->decode[ENGINE_CODEC_ZSTD]
                                                                      : file->tools->decode[ENGINE_CODEC_ZLIB];
        if (decoder == NULL)
        {
            return tiff_fail_number(file, "Compression", compression, "needs a decoder the engine did not supply");
        }
        tiff_room(file, &scratch->packed, &scratch->packed_room, bytes);
        tiff_fetch(file, offset, bytes, scratch->packed);
        if (file->reason != NULL)
        {
            return file->reason == NULL;
        }
        const EngineBytesRequest request = {scratch->packed, bytes, scratch->chunk, room};
        produced = decoder(&request);
    }
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if ((produced < 0LL) || ((unsigned long long)produced < needed))
    {
        return tiff_fail_number(file, "a strip or tile under Compression", compression, "does not decode to its size");
    }
    if (file->big_endian && (page->element_bytes > 1u))
    {
        tiff_swap(scratch->chunk, rows * page->chunk_width, page->element_bytes);
    }
    if (page->predictor == 2ull)
    {
        tiff_undo_differencing(scratch->chunk, rows, page->chunk_width, page->element_bytes);
    }
    return file->reason == NULL;
}

static int tiff_page_rows(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long row_first,
                          unsigned long long row_past, unsigned char *out)
{
    if ((file->reason != NULL) || (row_first >= row_past))
    {
        return file->reason == NULL;
    }
    unsigned long long *offsets = NULL;
    unsigned long long *counts = NULL;
    if (!tiff_page_chunks(file, page, &offsets, &counts))
    {
        return file->reason == NULL;
    }
    const unsigned long long element_bytes = page->element_bytes;
    const unsigned long long down_first = row_first / page->chunk_height;
    const unsigned long long down_past = ((row_past - 1ull) / page->chunk_height) + 1ull;
    for (unsigned long long down = down_first; (file->reason == NULL) && (down < down_past); down += 1ull)
    {
        const unsigned long long top = down * page->chunk_height;
        const unsigned long long rows_left = page->height - top;
        const unsigned long long rows = (rows_left < page->chunk_height) ? rows_left : page->chunk_height;
        const unsigned long long copy_first = (row_first > top) ? row_first : top;
        const unsigned long long copy_past = (row_past < (top + rows)) ? row_past : (top + rows);
        for (unsigned long long across = 0ull; (file->reason == NULL) && (across < page->chunks_across); across += 1ull)
        {
            const unsigned long long chunk = (down * page->chunks_across) + across;
            if (!tiff_chunk_decode(file, page, scratch, offsets[chunk], counts[chunk], rows))
            {
                break;
            }
            const unsigned long long left = across * page->chunk_width;
            const unsigned long long columns_left = page->width - left;
            const unsigned long long columns = (columns_left < page->chunk_width) ? columns_left : page->chunk_width;
            for (unsigned long long row = copy_first; row < copy_past; row += 1ull)
            {
                const unsigned char *const source = &scratch->chunk[(row - top) * page->chunk_width * element_bytes];
                unsigned char *const target = &out[(((row - row_first) * page->width) + left) * element_bytes];
                memcpy(target, source, (size_t)(columns * element_bytes));
            }
        }
    }
    free(offsets);
    free(counts);
    return file->reason == NULL;
}

static int tiff_chain_add(TiffFile *file, TiffChain *chain, unsigned long long offset)
{
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    for (unsigned long long seen = 0ull; (offset <= chain->highest) && (seen < chain->count); seen += 1ull)
    {
        if (chain->offsets[seen] == offset)
        {
            return tiff_fail(file, "the IFD chain loops back on itself");
        }
    }
    if (chain->count >= file->file_bytes)
    {
        return tiff_fail(file, "more pages than the file can hold");
    }
    if (chain->count == chain->room)
    {
        const unsigned long long room = (chain->room == 0ull) ? 64ull : (chain->room * 2ull);
        const unsigned long long bytes = room * sizeof(unsigned long long);
        if ((unsigned long long)(size_t)bytes != bytes)
        {
            return tiff_fail(file, "more pages than the file can hold");
        }
        unsigned long long *const grown = (unsigned long long *)realloc(chain->offsets, (size_t)bytes);
        if (grown == NULL)
        {
            return tiff_fail(file, "out of memory");
        }
        chain->offsets = grown;
        chain->room = room;
    }
    chain->offsets[chain->count] = offset;
    chain->count += 1ull;
    chain->highest = (offset > chain->highest) ? offset : chain->highest;
    return file->reason == NULL;
}

static char *tiff_description(TiffFile *file, const TiffEntry *entry)
{
    if ((file->reason != NULL) || !entry->present)
    {
        return NULL;
    }
    if ((entry->type != 1u) && (entry->type != 2u) && (entry->type != 7u))
    {
        tiff_fail_number(file, "an ImageDescription of type", entry->type, "rather than text");
        return NULL;
    }
    if ((entry->count == 0ull) || (entry->count > file->file_bytes))
    {
        tiff_fail(file, "an ImageDescription longer than the file");
        return NULL;
    }
    char *const text = (char *)malloc((size_t)(entry->count + 1ull));
    if (text == NULL)
    {
        tiff_fail(file, "out of memory");
        return NULL;
    }
    if (!tiff_entry_bytes(file, entry, entry->count, (unsigned char *)text))
    {
        free(text);
        return NULL;
    }
    text[entry->count] = '\0';
    return text;
}

static int tiff_digits(const char *text, size_t length, unsigned long long *value)
{
    unsigned long long total = 0ull;
    int fits = (length > 0u);
    for (size_t at = 0u; fits && (at < length); at += 1u)
    {
        const int digit = (text[at] >= '0') && (text[at] <= '9');
        const unsigned long long place = digit ? (unsigned long long)(text[at] - '0') : 0ull;
        fits = digit && (total <= ((~0ull - place) / 10ull));
        total = (total * 10ull) + place;
    }
    *value = total;
    return fits;
}

static void tiff_imagej_value(TiffFile *file, const char *text, const char *key, unsigned long long *value, unsigned int *present)
{
    const size_t key_length = strlen(key);
    for (const char *line = text; (line != NULL) && !*present; line = strchr(line, '\n'))
    {
        line += (*line == '\n') ? 1u : 0u;
        if ((strncmp(line, key, key_length) == 0) && (line[key_length] == '='))
        {
            const char *const digits = &line[key_length + 1u];
            const size_t length = strcspn(digits, "\r\n");
            *present = 1u;
            if (!tiff_digits(digits, length, value))
            {
                tiff_fail_named(file, "an ImageJ description with a malformed count:", key);
            }
        }
    }
}

static void tiff_layout_axis(TiffLayout *layout, char axis, unsigned long long extent, unsigned long long stride)
{
    layout->axes[layout->leading] = axis;
    layout->extent[layout->leading] = extent;
    layout->stride[layout->leading] = stride;
    layout->leading += 1u;
}

static int tiff_imagej(TiffFile *file, const char *text, unsigned long long pages, unsigned int pages_known, TiffLayout *layout)
{
    unsigned long long images = 1ull;
    unsigned long long channels = 1ull;
    unsigned long long slices = 1ull;
    unsigned long long frames = 1ull;
    unsigned int images_present = 0u;
    unsigned int channels_present = 0u;
    unsigned int slices_present = 0u;
    unsigned int frames_present = 0u;
    tiff_imagej_value(file, text, "images", &images, &images_present);
    tiff_imagej_value(file, text, "channels", &channels, &channels_present);
    tiff_imagej_value(file, text, "slices", &slices, &slices_present);
    tiff_imagej_value(file, text, "frames", &frames, &frames_present);
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if ((images == 0ull) || (channels == 0ull) || (slices == 0ull) || (frames == 0ull))
    {
        return tiff_fail(file, "an ImageJ description with a count of 0");
    }
    unsigned long long frames_by_slices = 0ull;
    unsigned long long product = 0ull;
    tiff_multiply(file, frames, slices, &frames_by_slices);
    tiff_multiply(file, frames_by_slices, channels, &product);
    images = images_present ? images : product;
    if ((file->reason == NULL) && (product != images))
    {
        return tiff_fail(file, "the ImageJ frames, slices and channels do not multiply to images");
    }
    if ((file->reason == NULL) && pages_known && (images != pages))
    {
        return tiff_fail(file, "the ImageJ images count is not the number of pages");
    }
    if (frames_present)
    {
        tiff_layout_axis(layout, 't', frames, slices * channels);
    }
    if (slices_present)
    {
        tiff_layout_axis(layout, 'z', slices, channels);
    }
    if (channels > 1ull)
    {
        tiff_layout_axis(layout, 'c', channels, 1ull);
    }
    if ((layout->leading == 0u) && (images > 1ull))
    {
        tiff_layout_axis(layout, '\0', images, 1ull);
    }
    return file->reason == NULL;
}

static const char *tiff_xml_element(const char *text, const char *name)
{
    const size_t length = strlen(name);
    for (const char *at = strchr(text, '<'); at != NULL; at = strchr(at + 1u, '<'))
    {
        if (strncmp(at + 1u, name, length) == 0)
        {
            const char after = at[length + 1u];
            if ((after == ' ') || (after == '\t') || (after == '\r') || (after == '\n') || (after == '>') || (after == '/'))
            {
                return at;
            }
        }
    }
    return NULL;
}

static const char *tiff_xml_attribute(const char *tag, const char *tag_end, const char *name, size_t *length)
{
    const size_t name_length = strlen(name);
    for (const char *at = tag + 1u; (size_t)(tag_end - at) > (name_length + 2u); at += 1u)
    {
        const char before = *(at - 1u);
        const int spaced = (before == ' ') || (before == '\t') || (before == '\r') || (before == '\n');
        if (spaced && (strncmp(at, name, name_length) == 0) && (at[name_length] == '=')
            && ((at[name_length + 1u] == '"') || (at[name_length + 1u] == '\'')))
        {
            const char quote = at[name_length + 1u];
            const char *const value = &at[name_length + 2u];
            const char *close = value;
            while ((close < tag_end) && (*close != quote))
            {
                close += 1u;
            }
            if (close >= tag_end)
            {
                return NULL;
            }
            *length = (size_t)(close - value);
            return value;
        }
    }
    return NULL;
}

static int tiff_xml_unsigned(TiffFile *file, const char *tag, const char *tag_end, const char *name, unsigned int required,
                             unsigned long long *value)
{
    size_t length = 0u;
    const char *const text = tiff_xml_attribute(tag, tag_end, name, &length);
    *value = 0ull;
    if ((text == NULL) && !required)
    {
        return file->reason == NULL;
    }
    if ((text == NULL) || !tiff_digits(text, length, value))
    {
        return tiff_fail_named(file, "an OME-XML attribute missing or not a whole number:", name);
    }
    return file->reason == NULL;
}

static void tiff_ome_candidates(TiffFile *file, const char *text)
{
    fprintf(stderr, "tiff: %s holds more than one OME image; each is shown as ID [SizeT SizeZ SizeC SizeY SizeX]:\n", file->path);
    for (const char *pixels = tiff_xml_element(text, "Pixels"); pixels != NULL; pixels = tiff_xml_element(pixels + 1u, "Pixels"))
    {
        const char *const tag_end = strchr(pixels, '>');
        if (tag_end == NULL)
        {
            break;
        }
        size_t id_length = 0u;
        const char *const id = tiff_xml_attribute(pixels, tag_end, "ID", &id_length);
        const char *const names[5u] = {"SizeT", "SizeZ", "SizeC", "SizeY", "SizeX"};
        unsigned long long sizes[5u] = {0ull, 0ull, 0ull, 0ull, 0ull};
        for (unsigned int axis = 0u; axis < 5u; axis += 1u)
        {
            size_t length = 0u;
            const char *const value = tiff_xml_attribute(pixels, tag_end, names[axis], &length);
            if ((value == NULL) || !tiff_digits(value, length, &sizes[axis]))
            {
                sizes[axis] = 0ull;
            }
        }
        const char *const shown = (id != NULL) ? id : "?";
        const int shown_length = (int)((id != NULL) ? id_length : 1u);
        fprintf(stderr, "tiff:   %.*s [%llu %llu %llu %llu %llu]\n", shown_length, shown, sizes[0u], sizes[1u], sizes[2u],
                sizes[3u], sizes[4u]);
    }
}

static int tiff_ome(TiffFile *file, const TiffPage *page, const char *text, unsigned long long pages, unsigned int pages_known,
                    TiffLayout *layout)
{
    const char *const pixels = tiff_xml_element(text, "Pixels");
    if (pixels == NULL)
    {
        return tiff_fail(file, "OME-XML with no Pixels element");
    }
    if (tiff_xml_element(pixels + 1u, "Pixels") != NULL)
    {
        tiff_ome_candidates(file, text);
        return tiff_fail(file, "the OME-XML holds more than one image");
    }
    const char *const pixels_end = strchr(pixels, '>');
    if (pixels_end == NULL)
    {
        return tiff_fail(file, "OME-XML that ends inside the Pixels element");
    }
    unsigned long long extent_x = 0ull;
    unsigned long long extent_y = 0ull;
    unsigned long long extent_z = 0ull;
    unsigned long long extent_c = 0ull;
    unsigned long long extent_t = 0ull;
    tiff_xml_unsigned(file, pixels, pixels_end, "SizeX", 1u, &extent_x);
    tiff_xml_unsigned(file, pixels, pixels_end, "SizeY", 1u, &extent_y);
    tiff_xml_unsigned(file, pixels, pixels_end, "SizeZ", 1u, &extent_z);
    tiff_xml_unsigned(file, pixels, pixels_end, "SizeC", 1u, &extent_c);
    tiff_xml_unsigned(file, pixels, pixels_end, "SizeT", 1u, &extent_t);
    size_t order_length = 0u;
    const char *const order = tiff_xml_attribute(pixels, pixels_end, "DimensionOrder", &order_length);
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if (extent_c != 1ull)
    {
        return tiff_fail_number(file, "an OME SizeC of", extent_c, "is not supported; only 1 is");
    }
    if ((extent_x != page->width) || (extent_y != page->height))
    {
        return tiff_fail(file, "the OME SizeX and SizeY are not the page width and height");
    }
    if ((extent_z == 0ull) || (extent_t == 0ull))
    {
        return tiff_fail(file, "an OME SizeZ or SizeT of 0");
    }
    if ((order == NULL) || (order_length != 5u) || (strncmp(order, "XY", 2u) != 0) || (memchr(order, 'Z', 5u) == NULL)
        || (memchr(order, 'C', 5u) == NULL) || (memchr(order, 'T', 5u) == NULL))
    {
        return tiff_fail(file, "an OME DimensionOrder that is not XY followed by Z, C and T");
    }
    const size_t z_place = (size_t)((const char *)memchr(order, 'Z', 5u) - order);
    const size_t t_place = (size_t)((const char *)memchr(order, 'T', 5u) - order);
    const unsigned long long z_stride = (z_place < t_place) ? 1ull : extent_t;
    const unsigned long long t_stride = (z_place < t_place) ? extent_z : 1ull;
    unsigned long long planes = 0ull;
    tiff_multiply(file, extent_z, extent_t, &planes);
    if ((file->reason == NULL) && pages_known && (planes != pages))
    {
        return tiff_fail(file, "the OME SizeZ and SizeT do not multiply to the number of pages");
    }
    const char *const closing = strstr(pixels_end, "</Pixels");
    const char *const region_end = (closing != NULL) ? closing : (pixels_end + strlen(pixels_end));
    for (const char *data = tiff_xml_element(pixels_end, "TiffData"); (file->reason == NULL) && (data != NULL) && (data < region_end);
         data = tiff_xml_element(data + 1u, "TiffData"))
    {
        const char *const data_end = strchr(data, '>');
        if (data_end == NULL)
        {
            return tiff_fail(file, "OME-XML that ends inside a TiffData element");
        }
        unsigned long long ifd = 0ull;
        unsigned long long first_z = 0ull;
        unsigned long long first_t = 0ull;
        unsigned long long first_c = 0ull;
        tiff_xml_unsigned(file, data, data_end, "IFD", 0u, &ifd);
        tiff_xml_unsigned(file, data, data_end, "FirstZ", 0u, &first_z);
        tiff_xml_unsigned(file, data, data_end, "FirstT", 0u, &first_t);
        tiff_xml_unsigned(file, data, data_end, "FirstC", 0u, &first_c);
        if ((file->reason == NULL)
            && ((first_z >= extent_z) || (first_t >= extent_t) || (first_c != 0ull)
                || (ifd != ((first_z * z_stride) + (first_t * t_stride)))))
        {
            return tiff_fail(file, "an OME TiffData that maps planes out of DimensionOrder");
        }
    }
    tiff_layout_axis(layout, 't', extent_t, t_stride);
    tiff_layout_axis(layout, 'z', extent_z, z_stride);
    return file->reason == NULL;
}

static const char *tiff_ome_start(const char *text)
{
    const char *const element = tiff_xml_element(text, "OME");
    return ((element != NULL) && (element[4u] != '/')) ? element : NULL;
}

static int tiff_layout(TiffFile *file, const TiffPage *page, const char *text, unsigned long long pages, unsigned int pages_known,
                       TiffLayout *layout)
{
    memset(layout, 0, sizeof(*layout));
    if (file->reason != NULL)
    {
        return file->reason == NULL;
    }
    if ((text != NULL) && (strncmp(text, "ImageJ=", 7u) == 0))
    {
        tiff_imagej(file, text, pages, pages_known, layout);
    }
    else if ((text != NULL) && (tiff_ome_start(text) != NULL))
    {
        tiff_ome(file, page, text, pages, pages_known, layout);
    }
    else if ((page->next != 0ull) != (pages > 1ull))
    {
        return tiff_fail(file, "the page count does not match the chain of pages");
    }
    else if (pages > 1ull)
    {
        tiff_layout_axis(layout, '\0', pages, 1ull);
    }
    unsigned long long total = page->page_bytes;
    for (unsigned int axis = 0u; axis < layout->leading; axis += 1u)
    {
        tiff_multiply(file, total, layout->extent[axis], &total);
    }
    return file->reason == NULL;
}

static void tiff_shape(const TiffPage *page, const TiffLayout *layout, EngineArrayShape *shape)
{
    memset(shape, 0, sizeof(*shape));
    for (unsigned int axis = 0u; axis < layout->leading; axis += 1u)
    {
        shape->shape[axis] = layout->extent[axis];
        shape->axes[axis] = layout->axes[axis];
    }
    shape->shape[layout->leading] = page->height;
    shape->axes[layout->leading] = 'y';
    shape->shape[layout->leading + 1u] = page->width;
    shape->axes[layout->leading + 1u] = 'x';
    shape->rank = layout->leading + 2u;
    shape->element_bytes = page->element_bytes;
    shape->element_kind = page->element_kind;
}

static int tiff_shape_equal(const EngineArrayShape *expected, const EngineArrayShape *given)
{
    int equal = (expected->rank == given->rank) && (expected->element_bytes == given->element_bytes)
             && (expected->element_kind == given->element_kind);
    for (unsigned int axis = 0u; equal && (axis < expected->rank); axis += 1u)
    {
        equal = (expected->shape[axis] == given->shape[axis]) && (expected->axes[axis] == given->axes[axis]);
    }
    return equal;
}

static void tiff_report(const TiffFile *file)
{
    fprintf(stderr, "tiff: %s: %s\n", (file->path != NULL) ? file->path : "(no path)", file->reason);
}

long tiff_describe(const EngineDescribeRequest *request)
{
    TiffFile file;
    TiffChain chain = {NULL, 0ull, 0ull, 0ull};
    TiffPage first;
    memset(&first, 0, sizeof(first));
    tiff_open(&file, request->path, request->member, request->tools);
    unsigned long long offset = file.first_ifd;
    while ((file.reason == NULL) && (offset != 0ull))
    {
        TiffPage page;
        unsigned long long *offsets = NULL;
        unsigned long long *counts = NULL;
        tiff_chain_add(&file, &chain, offset);
        tiff_page(&file, offset, &page);
        tiff_page_chunks(&file, &page, &offsets, &counts);
        free(offsets);
        free(counts);
        if (chain.count == 1ull)
        {
            first = page;
        }
        else if ((file.reason == NULL) && !tiff_page_same(&first, &page))
        {
            tiff_fail(&file, "the pages differ in width, height or sample type");
        }
        offset = page.next;
    }
    char *const text = tiff_description(&file, &first.description);
    TiffLayout layout;
    tiff_layout(&file, &first, text, chain.count, 1u, &layout);
    free(text);
    free(chain.offsets);
    if (file.reason != NULL)
    {
        tiff_report(&file);
        return -1L;
    }
    tiff_shape(&first, &layout, request->shape);
    return 0L;
}

static int tiff_read_planes(TiffFile *file, const EngineArrayRead *request, const TiffPage *first, const TiffLayout *layout,
                            TiffScratch *scratch, TiffChain *chain)
{
    unsigned long long inner = 1ull;
    unsigned long long top = (request->past - 1ull) * layout->stride[0u];
    for (unsigned int axis = 1u; axis < layout->leading; axis += 1u)
    {
        inner *= layout->extent[axis];
        top += (layout->extent[axis] - 1ull) * layout->stride[axis];
    }
    unsigned long long next = first->next;
    tiff_chain_add(file, chain, file->first_ifd);
    while ((file->reason == NULL) && (chain->count <= top))
    {
        if (next == 0ull)
        {
            return tiff_fail(file, "the file has fewer pages than its shape");
        }
        tiff_chain_add(file, chain, next);
        tiff_ifd_next(file, next, &next);
    }
    const unsigned long long plane_first = request->first * inner;
    const unsigned long long plane_past = request->past * inner;
    for (unsigned long long plane = plane_first; (file->reason == NULL) && (plane < plane_past); plane += 1ull)
    {
        unsigned long long remainder = plane;
        unsigned long long page_index = 0ull;
        for (unsigned int axis = layout->leading; axis > 0u; axis -= 1u)
        {
            page_index += (remainder % layout->extent[axis - 1u]) * layout->stride[axis - 1u];
            remainder /= layout->extent[axis - 1u];
        }
        TiffPage page;
        tiff_page(file, chain->offsets[page_index], &page);
        if ((file->reason == NULL) && !tiff_page_same(first, &page))
        {
            return tiff_fail(file, "the pages differ in width, height or sample type");
        }
        tiff_page_rows(file, &page, scratch, 0ull, page.height, &request->out[(plane - plane_first) * first->page_bytes]);
    }
    return file->reason == NULL;
}

long long tiff_read(const EngineArrayRead *request)
{
    TiffFile file;
    TiffScratch scratch = {NULL, 0ull, NULL, 0ull};
    TiffChain chain = {NULL, 0ull, 0ull, 0ull};
    TiffPage first;
    TiffLayout layout;
    EngineArrayShape expected;
    const EngineArrayShape *const given = request->shape;
    unsigned long long total = 0ull;
    tiff_open(&file, request->path, request->member, request->tools);
    tiff_page(&file, file.first_ifd, &first);
    char *const text = tiff_description(&file, &first.description);
    const unsigned long long pages = (first.next == 0ull) ? 1ull : ((given->rank == 3u) ? given->shape[0u] : 0ull);
    tiff_layout(&file, &first, text, pages, 0u, &layout);
    free(text);
    tiff_shape(&first, &layout, &expected);
    if ((file.reason == NULL) && !tiff_shape_equal(&expected, given))
    {
        tiff_fail(&file, "the shape given is not this file's shape");
    }
    if ((file.reason == NULL) && ((request->first > request->past) || (request->past > expected.shape[0u])))
    {
        tiff_fail(&file, "a range outside axis 0");
    }
    unsigned long long per_index = expected.element_bytes;
    for (unsigned int axis = 1u; (file.reason == NULL) && (axis < expected.rank); axis += 1u)
    {
        tiff_multiply(&file, per_index, expected.shape[axis], &per_index);
    }
    tiff_multiply(&file, per_index, request->past - request->first, &total);
    if ((file.reason == NULL) && (total > request->out_room))
    {
        tiff_fail(&file, "the output buffer is smaller than the range");
    }
    const unsigned int writing = (file.reason == NULL);
    if (writing && (layout.leading == 0u))
    {
        tiff_page_rows(&file, &first, &scratch, request->first, request->past, request->out);
    }
    else if (writing && (request->past > request->first))
    {
        tiff_read_planes(&file, request, &first, &layout, &scratch, &chain);
    }
    free(scratch.packed);
    free(scratch.chunk);
    free(chain.offsets);
    if (file.reason != NULL)
    {
        if (writing && (total > 0ull))
        {
            memset(request->out, 0, (size_t)total);
        }
        tiff_report(&file);
        return -1LL;
    }
    return (long long)total;
}
