// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tiff_metadata.c: rows, chains, ImageJ and OME metadata
#include "tiff_internal.h"

int tiff_page_rows(TiffFile *file, const TiffPage *page, TiffScratch *scratch, unsigned long long row_first,
                   unsigned long long row_end, unsigned char *out)
{
    if ((file->reason != NULL) || (row_first >= row_end))
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
    const unsigned long long down_end = ((row_end - 1ull) / page->chunk_height) + 1ull;
    for (unsigned long long down = down_first; (file->reason == NULL) && (down < down_end); down += 1ull)
    {
        const unsigned long long top = down * page->chunk_height;
        const unsigned long long rows_left = page->height - top;
        const unsigned long long rows = (rows_left < page->chunk_height) ? rows_left : page->chunk_height;
        const unsigned long long copy_first = (row_first > top) ? row_first : top;
        const unsigned long long copy_end = (row_end < (top + rows)) ? row_end : (top + rows);
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
            for (unsigned long long row = copy_first; row < copy_end; row += 1ull)
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

int tiff_chain_add(TiffFile *file, TiffChain *chain, unsigned long long offset)
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
    if (chain->count == chain->capacity)
    {
        const unsigned long long capacity = (chain->capacity == 0ull) ? 64ull : (chain->capacity * 2ull);
        const unsigned long long bytes = capacity * sizeof(unsigned long long);
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
        chain->capacity = capacity;
    }
    chain->offsets[chain->count] = offset;
    chain->count += 1ull;
    chain->highest = (offset > chain->highest) ? offset : chain->highest;
    return file->reason == NULL;
}

char *tiff_description(TiffFile *file, const TiffEntry *entry)
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

static void tiff_imagej_value(TiffFile *file, const char *text, const char *key, unsigned long long *value,
                              unsigned int *present)
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

void tiff_layout_axis(TiffLayout *layout, char axis, unsigned long long extent, unsigned long long stride)
{
    layout->axes[layout->leading] = axis;
    layout->extent[layout->leading] = extent;
    layout->stride[layout->leading] = stride;
    layout->leading += 1u;
}

int tiff_imagej(TiffFile *file, const char *text, unsigned long long pages, unsigned int pages_known,
                TiffLayout *layout)
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
            if ((after == ' ') || (after == '\t') || (after == '\r') || (after == '\n') || (after == '>') ||
                (after == '/'))
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
        if (spaced && (strncmp(at, name, name_length) == 0) && (at[name_length] == '=') &&
            ((at[name_length + 1u] == '"') || (at[name_length + 1u] == '\'')))
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

static int tiff_xml_unsigned(TiffFile *file, const char *tag, const char *tag_end, const char *name,
                             unsigned int required, unsigned long long *value)
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
    fprintf(stderr, "tiff: %s holds more than one OME image; each is shown as ID [SizeT SizeZ SizeC SizeY SizeX]:\n",
            file->path);
    for (const char *pixels = tiff_xml_element(text, "Pixels"); pixels != NULL;
         pixels = tiff_xml_element(pixels + 1u, "Pixels"))
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
        fprintf(stderr, "tiff:   %.*s [%llu %llu %llu %llu %llu]\n", shown_length, shown, sizes[0u], sizes[1u],
                sizes[2u], sizes[3u], sizes[4u]);
    }
}

int tiff_ome(TiffFile *file, const TiffPage *page, const char *text, unsigned long long pages, unsigned int pages_known,
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
    if ((order == NULL) || (order_length != 5u) || (strncmp(order, "XY", 2u) != 0) ||
        (memchr(order, 'Z', 5u) == NULL) || (memchr(order, 'C', 5u) == NULL) || (memchr(order, 'T', 5u) == NULL))
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
    for (const char *data = tiff_xml_element(pixels_end, "TiffData");
         (file->reason == NULL) && (data != NULL) && (data < region_end);
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
        if ((file->reason == NULL) && ((first_z >= extent_z) || (first_t >= extent_t) || (first_c != 0ull) ||
                                       (ifd != ((first_z * z_stride) + (first_t * t_stride)))))
        {
            return tiff_fail(file, "an OME TiffData that maps planes out of DimensionOrder");
        }
    }
    tiff_layout_axis(layout, 't', extent_t, t_stride);
    tiff_layout_axis(layout, 'z', extent_z, z_stride);
    return file->reason == NULL;
}

const char *tiff_ome_start(const char *text)
{
    const char *const element = tiff_xml_element(text, "OME");
    return ((element != NULL) && (element[4u] != '/')) ? element : NULL;
}
