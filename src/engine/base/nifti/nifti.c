// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "nifti.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NIFTI_ONE_HEADER 348ull
#define NIFTI_TWO_HEADER 540ull
#define NIFTI_DIMENSIONS 7u
#define NIFTI_BYTES_LIMIT 9223372036854775807ull
#define NIFTI_GZIP_SMALLEST 18ull

typedef struct
{
    const EngineIngestTools *tools;
    const char *path;
    unsigned long long length;
    unsigned char *memory;
} NiftiSource;

typedef struct
{
    EngineArrayShape shape;
    unsigned int big_endian;
    unsigned int paired;
    unsigned int scaled;
    unsigned long long header_bytes;
    unsigned long long data_offset;
    unsigned long long data_bytes;
} NiftiLayout;

typedef struct
{
    unsigned long long code;
    unsigned int element_bytes;
    EngineElementKind element_kind;
} NiftiType;

static const NiftiType nifti_types[] = {{2ull, 1u, ENGINE_ELEMENT_UNSIGNED},  {4ull, 2u, ENGINE_ELEMENT_SIGNED},
                                        {8ull, 4u, ENGINE_ELEMENT_SIGNED},    {16ull, 4u, ENGINE_ELEMENT_FLOAT},
                                        {64ull, 8u, ENGINE_ELEMENT_FLOAT},    {256ull, 1u, ENGINE_ELEMENT_SIGNED},
                                        {512ull, 2u, ENGINE_ELEMENT_UNSIGNED}, {768ull, 4u, ENGINE_ELEMENT_UNSIGNED},
                                        {1024ull, 8u, ENGINE_ELEMENT_SIGNED}, {1280ull, 8u, ENGINE_ELEMENT_UNSIGNED}};

static const unsigned char nifti_one_single[4u] = {'n', '+', '1', 0x00u};

static const unsigned char nifti_one_paired[4u] = {'n', 'i', '1', 0x00u};

static const unsigned char nifti_two_single[8u] = {'n', '+', '2', 0x00u, 0x0Du, 0x0Au, 0x1Au, 0x0Au};

static const unsigned char nifti_two_paired[8u] = {'n', 'i', '2', 0x00u, 0x0Du, 0x0Au, 0x1Au, 0x0Au};

static const NiftiSource nifti_empty_source = {NULL, NULL, 0ull, NULL};

static const NiftiLayout nifti_empty_layout = {{0u, {0ull}, {'\0'}, 0u, ENGINE_ELEMENT_UNSIGNED}, 0u, 0u, 0u, 0ull,
                                               0ull, 0ull};

static unsigned long long nifti_load(const unsigned char *bytes, unsigned int count, unsigned int big_endian)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        const unsigned int at = (big_endian != 0u) ? place : (count - 1u - place);
        value = (value << 8u) | (unsigned long long)bytes[at];
    }
    return value;
}

static unsigned int nifti_fits_memory(unsigned long long bytes)
{
    return ((unsigned long long)(size_t)bytes == bytes) ? 1u : 0u;
}

static unsigned int nifti_multiply(unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (NIFTI_BYTES_LIMIT / left)))
    {
        return 0u;
    }
    *product = left * right;
    return 1u;
}

static unsigned int nifti_file_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
                                     unsigned long long bytes, unsigned char *out)
{
    if (bytes == 0ull)
    {
        return 1u;
    }
    const EngineFileRange range = {path, offset, bytes, out};
    const long long got = tools->read(&range);
    return ((got >= 0LL) && ((unsigned long long)got == bytes)) ? 1u : 0u;
}

static unsigned int nifti_fetch(const NiftiSource *source, unsigned long long offset, unsigned long long bytes,
                                unsigned char *out)
{
    if ((offset > source->length) || (bytes > (source->length - offset)) || !nifti_fits_memory(bytes))
    {
        return 0u;
    }
    if ((source->memory != NULL) && (bytes != 0ull))
    {
        memcpy(out, source->memory + offset, (size_t)bytes);
        return 1u;
    }
    return nifti_file_fetch(source->tools, source->path, offset, bytes, out);
}

static void nifti_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes)
{
    for (unsigned long long start = 0ull; start < total; start += element_bytes)
    {
        for (unsigned int low = 0u; low < (element_bytes / 2u); low += 1u)
        {
            const unsigned int high = element_bytes - 1u - low;
            const unsigned char held = bytes[start + low];
            bytes[start + low] = bytes[start + high];
            bytes[start + high] = held;
        }
    }
}

static unsigned int nifti_whole(unsigned long long bits, unsigned long long *value)
{
    const unsigned long long exponent = (bits >> 23u) & 0xFFull;
    const unsigned long long mantissa = (bits & 0x7FFFFFull) | 0x800000ull;
    if ((bits & 0x7FFFFFFFull) == 0ull)
    {
        *value = 0ull;
        return 1u;
    }
    if (((bits >> 31u) != 0ull) || (exponent < 127ull) || (exponent > 189ull))
    {
        return 0u;
    }
    if (exponent >= 150ull)
    {
        *value = mantissa << (exponent - 150ull);
        return 1u;
    }
    const unsigned long long shift = 150ull - exponent;
    if ((mantissa & ((1ull << shift) - 1ull)) != 0ull)
    {
        return 0u;
    }
    *value = mantissa >> shift;
    return 1u;
}

static unsigned int nifti_open(const EngineIngestTools *tools, const char *path, NiftiSource *source)
{
    const long long size = tools->size(path);
    unsigned char opening[2u];
    if ((size < 2LL) || !nifti_file_fetch(tools, path, 0ull, 2ull, opening))
    {
        return 0u;
    }
    const unsigned long long file_bytes = (unsigned long long)size;
    if ((opening[0u] != 0x1Fu) || (opening[1u] != 0x8Bu))
    {
        const NiftiSource plain = {tools, path, file_bytes, NULL};
        *source = plain;
        return 1u;
    }
    const EngineBytesDecode decode = tools->decode[ENGINE_CODEC_GZIP];
    unsigned char trailer[4u];
    if ((decode == NULL) || (file_bytes < NIFTI_GZIP_SMALLEST) || !nifti_fits_memory(file_bytes)
        || !nifti_file_fetch(tools, path, file_bytes - 4ull, 4ull, trailer))
    {
        return 0u;
    }
    const unsigned long long expected = nifti_load(trailer, 4u, 0u);
    if ((expected == 0ull) || !nifti_fits_memory(expected))
    {
        return 0u;
    }
    unsigned char *const packed = malloc((size_t)file_bytes);
    unsigned char *const unpacked = malloc((size_t)expected);
    int good = (packed != NULL) && (unpacked != NULL) && nifti_file_fetch(tools, path, 0ull, file_bytes, packed);
    if (good)
    {
        const EngineBytesRequest request = {packed, file_bytes, unpacked, expected};
        const long long made = decode(&request);
        good = (made >= 0LL) && ((unsigned long long)made == expected);
    }
    free(packed);
    if (!good)
    {
        free(unpacked);
        return 0u;
    }
    const NiftiSource inflated = {tools, path, expected, unpacked};
    *source = inflated;
    return 1u;
}

static unsigned int nifti_header(const unsigned char *bytes, unsigned long long available, NiftiLayout *layout)
{
    if (available < NIFTI_ONE_HEADER)
    {
        return 0u;
    }
    const unsigned long long little = nifti_load(bytes, 4u, 0u);
    const unsigned int big_endian = ((little == NIFTI_ONE_HEADER) || (little == NIFTI_TWO_HEADER)) ? 0u : 1u;
    const unsigned long long header_bytes = nifti_load(bytes, 4u, big_endian);
    if (((header_bytes != NIFTI_ONE_HEADER) && (header_bytes != NIFTI_TWO_HEADER)) || (available < header_bytes))
    {
        return 0u;
    }
    const int second = (header_bytes == NIFTI_TWO_HEADER);
    const int single = second ? (memcmp(bytes + 4u, nifti_two_single, sizeof nifti_two_single) == 0)
                              : (memcmp(bytes + 344u, nifti_one_single, sizeof nifti_one_single) == 0);
    const int paired = second ? (memcmp(bytes + 4u, nifti_two_paired, sizeof nifti_two_paired) == 0)
                              : (memcmp(bytes + 344u, nifti_one_paired, sizeof nifti_one_paired) == 0);
    if (!single && !paired)
    {
        return 0u;
    }
    const unsigned int dimension_bytes = second ? 8u : 2u;
    const unsigned long long negative = second ? 0x8000000000000000ull : 0x8000ull;
    const unsigned char *const dimensions_at = bytes + (second ? 16u : 40u);
    unsigned long long dimensions[NIFTI_DIMENSIONS + 1u];
    for (unsigned int slot = 0u; slot <= NIFTI_DIMENSIONS; slot += 1u)
    {
        dimensions[slot] = nifti_load(dimensions_at + (slot * dimension_bytes), dimension_bytes, big_endian);
    }
    const unsigned long long rank = dimensions[0u];
    if ((rank < 1ull) || (rank > NIFTI_DIMENSIONS))
    {
        return 0u;
    }
    const unsigned long long datatype = nifti_load(bytes + (second ? 12u : 70u), 2u, big_endian);
    const unsigned long long bitpix = nifti_load(bytes + (second ? 14u : 72u), 2u, big_endian);
    NiftiLayout built = nifti_empty_layout;
    unsigned int typed = 0u;
    for (size_t entry = 0u; entry < (sizeof nifti_types / sizeof nifti_types[0u]); entry += 1u)
    {
        if (nifti_types[entry].code == datatype)
        {
            built.shape.element_bytes = nifti_types[entry].element_bytes;
            built.shape.element_kind = nifti_types[entry].element_kind;
            typed = 1u;
        }
    }
    if ((typed == 0u) || (bitpix != (8ull * built.shape.element_bytes)))
    {
        fprintf(stderr, "nifti: datatype %llu with bitpix %llu is refused\n", datatype, bitpix);
        return 0u;
    }
    unsigned long long data_bytes = built.shape.element_bytes;
    built.shape.rank = (unsigned int)rank;
    for (unsigned int axis = 0u; axis < built.shape.rank; axis += 1u)
    {
        const unsigned int slot = built.shape.rank - axis;
        const unsigned long long extent = dimensions[slot];
        if ((extent == 0ull) || (extent >= negative) || !nifti_multiply(data_bytes, extent, &data_bytes))
        {
            return 0u;
        }
        built.shape.shape[axis] = extent;
        built.shape.axes[axis] = (slot == 1u) ? 'x' : (slot == 2u) ? 'y' : (slot == 3u) ? 'z' : (slot == 4u) ? 't' : '\0';
    }
    const unsigned long long wide_offset = nifti_load(bytes + 168u, 8u, big_endian);
    unsigned long long data_offset = wide_offset;
    const int placed = second ? (wide_offset < negative)
                              : (nifti_whole(nifti_load(bytes + 108u, 4u, big_endian), &data_offset) != 0u);
    if (!placed || (single && (data_offset < header_bytes)))
    {
        return 0u;
    }
    const unsigned long long slope = second ? nifti_load(bytes + 176u, 8u, big_endian) : nifti_load(bytes + 112u, 4u, big_endian);
    const unsigned long long magnitude = slope & (second ? 0x7FFFFFFFFFFFFFFFull : 0x7FFFFFFFull);
    const unsigned long long one = second ? 0x3FF0000000000000ull : 0x3F800000ull;
    built.scaled = ((magnitude != 0ull) && (slope != one)) ? 1u : 0u;
    built.big_endian = ((big_endian != 0u) && (built.shape.element_bytes > 1u)) ? 1u : 0u;
    built.paired = paired ? 1u : 0u;
    built.header_bytes = header_bytes;
    built.data_offset = data_offset;
    built.data_bytes = data_bytes;
    *layout = built;
    return 1u;
}

static unsigned int nifti_letter_is(char spelled, char lower)
{
    return ((spelled == lower) || (spelled == (char)(lower - 'a' + 'A'))) ? 1u : 0u;
}

static char *nifti_sibling(const char *path, const char *from, const char *to, unsigned int toggle_gzip)
{
    const size_t length = strlen(path);
    const int gzipped = (length >= 3u) && (path[length - 3u] == '.') && nifti_letter_is(path[length - 2u], 'g')
                     && nifti_letter_is(path[length - 1u], 'z');
    const size_t stem_end = gzipped ? (length - 3u) : length;
    if ((stem_end < 4u) || (path[stem_end - 4u] != '.') || !nifti_letter_is(path[stem_end - 3u], from[0u])
        || !nifti_letter_is(path[stem_end - 2u], from[1u]) || !nifti_letter_is(path[stem_end - 1u], from[2u]))
    {
        return NULL;
    }
    const int ends_gzipped = gzipped ? (toggle_gzip == 0u) : (toggle_gzip != 0u);
    char *const sibling = malloc(stem_end + 4u);
    if (sibling == NULL)
    {
        return NULL;
    }
    memcpy(sibling, path, stem_end);
    for (size_t letter = 0u; letter < 3u; letter += 1u)
    {
        const char original = path[stem_end - 3u + letter];
        const int upper = (original >= 'A') && (original <= 'Z');
        sibling[stem_end - 3u + letter] = upper ? (char)(to[letter] - 'a' + 'A') : to[letter];
    }
    memcpy(sibling + stem_end, ends_gzipped ? ".gz" : "", ends_gzipped ? 4u : 1u);
    return sibling;
}

static char *nifti_existing_sibling(const EngineIngestTools *tools, const char *path, const char *from, const char *to)
{
    for (unsigned int toggle = 0u; toggle < 2u; toggle += 1u)
    {
        char *const sibling = nifti_sibling(path, from, to, toggle);
        if ((sibling != NULL) && (tools->size(sibling) >= 0LL))
        {
            return sibling;
        }
        free(sibling);
    }
    return NULL;
}

static unsigned int nifti_prepare(const char *path, const char *member, const EngineIngestTools *tools,
                                  unsigned int noting, NiftiLayout *layout, NiftiSource *data, char **image_path)
{
    *image_path = NULL;
    if (member != NULL)
    {
        fprintf(stderr, "nifti: %s holds one image; a member was named\n", path);
        return 0u;
    }
    char *const header_owned = nifti_existing_sibling(tools, path, "img", "hdr");
    const char *const header_path = (header_owned != NULL) ? header_owned : path;
    NiftiSource header = nifti_empty_source;
    unsigned char bytes[NIFTI_TWO_HEADER];
    NiftiLayout built = nifti_empty_layout;
    const int parsed = nifti_open(tools, header_path, &header)
                    && nifti_fetch(&header, 0ull, (header.length < NIFTI_TWO_HEADER) ? header.length : NIFTI_TWO_HEADER, bytes)
                    && nifti_header(bytes, (header.length < NIFTI_TWO_HEADER) ? header.length : NIFTI_TWO_HEADER, &built);
    if (!parsed || ((built.paired == 0u) && (header_owned != NULL)))
    {
        free(header.memory);
        free(header_owned);
        return 0u;
    }
    if (built.paired == 0u)
    {
        *data = header;
    }
    else
    {
        free(header.memory);
        *image_path = nifti_existing_sibling(tools, header_path, "hdr", "img");
        NiftiSource image = nifti_empty_source;
        if ((*image_path == NULL) || !nifti_open(tools, *image_path, &image))
        {
            free(*image_path);
            *image_path = NULL;
            free(header_owned);
            return 0u;
        }
        *data = image;
    }
    if ((built.data_offset > data->length) || (built.data_bytes > (data->length - built.data_offset)))
    {
        free(data->memory);
        data->memory = NULL;
        free(*image_path);
        *image_path = NULL;
        free(header_owned);
        return 0u;
    }
    if ((noting != 0u) && (built.scaled != 0u))
    {
        fprintf(stderr, "nifti: %s has a scl_slope that is not 1; the raw stored values are read, unscaled\n", header_path);
    }
    free(header_owned);
    *layout = built;
    return 1u;
}

static unsigned int nifti_same_shape(const EngineArrayShape *found, const EngineArrayShape *given)
{
    int same = (found->rank == given->rank) && (found->element_bytes == given->element_bytes)
            && (found->element_kind == given->element_kind);
    for (unsigned int axis = 0u; same && (axis < found->rank); axis += 1u)
    {
        same = (found->shape[axis] == given->shape[axis]) && (found->axes[axis] == given->axes[axis]);
    }
    return same ? 1u : 0u;
}

long nifti_describe(const EngineDescribeRequest *request)
{
    NiftiLayout layout = nifti_empty_layout;
    NiftiSource data = nifti_empty_source;
    char *image_path = NULL;
    if (!nifti_prepare(request->path, request->member, request->tools, 1u, &layout, &data, &image_path))
    {
        return -1L;
    }
    free(data.memory);
    free(image_path);
    *request->shape = layout.shape;
    return 0L;
}

long long nifti_read(const EngineArrayRead *request)
{
    NiftiLayout layout = nifti_empty_layout;
    NiftiSource data = nifti_empty_source;
    char *image_path = NULL;
    if (!nifti_prepare(request->path, request->member, request->tools, 0u, &layout, &data, &image_path))
    {
        return -1LL;
    }
    const unsigned long long row_bytes = layout.data_bytes / layout.shape.shape[0u];
    const int agrees = nifti_same_shape(&layout.shape, request->shape) && (request->first <= request->past)
                    && (request->past <= layout.shape.shape[0u]);
    const unsigned long long wanted = agrees ? ((request->past - request->first) * row_bytes) : 0ull;
    const int copied = agrees && (wanted <= request->out_room)
                    && nifti_fetch(&data, layout.data_offset + (request->first * row_bytes), wanted, request->out);
    free(data.memory);
    free(image_path);
    if (!copied)
    {
        if (agrees && (wanted <= request->out_room) && nifti_fits_memory(wanted))
        {
            memset(request->out, 0, (size_t)wanted);
        }
        return -1LL;
    }
    if (layout.big_endian != 0u)
    {
        nifti_swap(request->out, wanted, layout.shape.element_bytes);
    }
    return (long long)wanted;
}
