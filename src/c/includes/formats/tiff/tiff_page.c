// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tiff_page.c: a page's extent, its chunks and their decoders
#include "tiff_internal.h"

static const unsigned long long tiff_tag_numbers[TIFF_TAGS] = {256ull, 257ull, 258ull, 259ull, 266ull, 270ull,
                                                               273ull, 277ull, 278ull, 279ull, 284ull, 317ull,
                                                               322ull, 323ull, 324ull, 325ull, 339ull};

static int tiff_page_extent(TiffFile *file, TiffPage *page, const TiffEntry *found)
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
    if ((compression != 1ull) && (compression != 5ull) && (compression != 8ull) && (compression != 32946ull) &&
        (compression != 32773ull) && (compression != 50000ull))
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
                         : (sample_format == 2ull) ? ENGINE_ELEMENT_SIGNED
                                                   : ENGINE_ELEMENT_FLOAT;
    unsigned long long samples_per_page = 0ull;
    tiff_multiply(file, page->width, page->height, &samples_per_page);
    tiff_multiply(file, samples_per_page, page->element_bytes, &page->page_bytes);
    const unsigned int tiled = found[TIFF_TAG_TILE_WIDTH].present || found[TIFF_TAG_TILE_LENGTH].present ||
                               found[TIFF_TAG_TILE_OFFSETS].present || found[TIFF_TAG_TILE_BYTE_COUNTS].present;
    if (tiled)
    {
        if ((tile_width == 0ull) || (tile_length == 0ull) || !found[TIFF_TAG_TILE_OFFSETS].present ||
            !found[TIFF_TAG_TILE_BYTE_COUNTS].present)
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

int tiff_page(TiffFile *file, unsigned long long ifd, TiffPage *page)
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
            const int outside = (width != 0ull) && (count > (value_bytes / width)) &&
                                ((count > file->file_bytes) || (place > file->file_bytes) ||
                                 ((count * width) > (file->file_bytes - place)));
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
    return tiff_page_extent(file, page, found);
}

int tiff_page_same(const TiffPage *first, const TiffPage *page)
{
    return (first->width == page->width) && (first->height == page->height) &&
           (first->element_bytes == page->element_bytes) && (first->element_kind == page->element_kind);
}

int tiff_page_chunks(TiffFile *file, const TiffPage *page, unsigned long long **offsets, unsigned long long **counts)
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
        return ENGINE_BYTES_ERROR;
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
    unsigned int accumulated_bits = 0u;
    unsigned int width = TIFF_LZW_WIDTH_FIRST;
    unsigned int next = TIFF_LZW_FIRST;
    unsigned int previous = TIFF_LZW_CODES;
    for (;;)
    {
        while ((accumulated_bits < width) && (at < request->in_bytes))
        {
            accumulator = (accumulator << 8u) | (unsigned long)request->in[at];
            at += 1ull;
            accumulated_bits += 8u;
        }
        if (accumulated_bits < width)
        {
            break;
        }
        const unsigned int code = (unsigned int)((accumulator >> (accumulated_bits - width)) & ((1ul << width) - 1ul));
        accumulated_bits -= width;
        accumulator &= (1ul << accumulated_bits) - 1ul;
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
            return ENGINE_BYTES_ERROR;
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
        if (size > (request->out_capacity - produced))
        {
            return ENGINE_BYTES_ERROR;
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
            if ((literal > (request->in_bytes - at)) || (literal > (request->out_capacity - produced)))
            {
                return ENGINE_BYTES_ERROR;
            }
            memcpy(&request->out[produced], &request->in[at], (size_t)literal);
            at += literal;
            produced += literal;
        }
        else if (header > 128u)
        {
            const unsigned long long run = 257ull - header;
            if ((at >= request->in_bytes) || (run > (request->out_capacity - produced)))
            {
                return ENGINE_BYTES_ERROR;
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
                const unsigned int sum =
                    (unsigned int)line[sample + byte] + (unsigned int)line[sample - element_bytes + byte] + carry;
                line[sample + byte] = (unsigned char)(sum & 0xFFu);
                carry = sum >> 8u;
            }
        }
    }
}

int tiff_chunk_decode(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long offset,
                      unsigned long long bytes, unsigned long long rows)
{
    const unsigned long long capacity = page->chunk_width * page->chunk_height * page->element_bytes;
    const unsigned long long needed = rows * page->chunk_width * page->element_bytes;
    const unsigned long long compression = page->compression;
    long long produced = ENGINE_BYTES_ERROR;
    if (!tiff_reserve(file, &scratch->chunk, &scratch->chunk_capacity, capacity))
    {
        return file->reason == NULL;
    }
    if (compression == 1ull)
    {
        const unsigned long long taken = (bytes < capacity) ? bytes : capacity;
        produced = tiff_fetch(file, offset, taken, scratch->chunk) ? (long long)taken : ENGINE_BYTES_ERROR;
    }
    else
    {
        const EngineBytesDecode decoder = (compression == 5ull)       ? tiff_lzw_decode
                                          : (compression == 32773ull) ? tiff_packbits_decode
                                          : (compression == 50000ull) ? file->tools->decode[ENGINE_CODEC_ZSTD]
                                                                      : file->tools->decode[ENGINE_CODEC_ZLIB];
        if (decoder == NULL)
        {
            return tiff_fail_number(file, "Compression", compression, "needs a decoder the engine did not supply");
        }
        tiff_reserve(file, &scratch->packed, &scratch->packed_capacity, bytes);
        tiff_fetch(file, offset, bytes, scratch->packed);
        if (file->reason != NULL)
        {
            return file->reason == NULL;
        }
        const EngineBytesRequest request = {scratch->packed, bytes, scratch->chunk, capacity};
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
