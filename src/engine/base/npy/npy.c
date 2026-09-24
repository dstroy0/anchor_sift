// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "npy.h"

#include "zip.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NPY_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_NPY, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define NPY_FORTRAN_BLOCK 16777216ull
#define NPY_BYTES_LIMIT 9223372036854775807ull

typedef struct
{
    const EngineIngestTools *tools;
    const char *path;
    unsigned long long base;
    unsigned long long length;
    const unsigned char *memory;
} NpySource;

typedef struct
{
    EngineArrayShape shape;
    unsigned int big_endian;
    unsigned int fortran_order;
    unsigned long long data_offset;
    unsigned long long data_bytes;
} NpyLayout;

typedef struct
{
    const unsigned char *text;
    unsigned long long length;
    unsigned long long at;
} NpyText;

static const NpySource npy_empty_source = {NULL, NULL, 0ull, 0ull, NULL};

static const NpyLayout npy_empty_layout = {{0u, {0ull}, {'\0'}, 0u, ENGINE_ELEMENT_UNSIGNED}, 0u, 0u, 0ull, 0ull};

static const ZipEntry npy_empty_entry = {NULL, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull, 0ull};

static const unsigned char npy_magic[6u] = {0x93u, 'N', 'U', 'M', 'P', 'Y'};

static const unsigned char npy_zip_local[4u] = {'P', 'K', 0x03u, 0x04u};

static const unsigned char npy_zip_end[4u] = {'P', 'K', 0x05u, 0x06u};

static unsigned long long npy_load(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

static unsigned int npy_fits_memory(unsigned long long bytes)
{
    return ((unsigned long long)(size_t)bytes == bytes) ? 1u : 0u;
}

static unsigned int npy_multiply(unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (NPY_BYTES_LIMIT / left)))
    {
        return 0u;
    }
    *product = left * right;
    return 1u;
}

static unsigned int npy_file_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
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

static unsigned int npy_source_fetch(const NpySource *source, unsigned long long offset, unsigned long long bytes,
                                     unsigned char *out)
{
    if ((offset > source->length) || (bytes > (source->length - offset)) || !npy_fits_memory(bytes))
    {
        return 0u;
    }
    if (bytes == 0ull)
    {
        return 1u;
    }
    if (source->memory != NULL)
    {
        memcpy(out, source->memory + offset, (size_t)bytes);
        return 1u;
    }
    return npy_file_fetch(source->tools, source->path, source->base + offset, bytes, out);
}

static void npy_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes)
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

static void npy_space(NpyText *text)
{
    while ((text->at < text->length)
           && ((text->text[text->at] == ' ') || (text->text[text->at] == '\t') || (text->text[text->at] == '\n')
               || (text->text[text->at] == '\r')))
    {
        text->at += 1ull;
    }
}

static unsigned int npy_expect(NpyText *text, unsigned char wanted)
{
    npy_space(text);
    if ((text->at < text->length) && (text->text[text->at] == wanted))
    {
        text->at += 1ull;
        return 1u;
    }
    return 0u;
}

static unsigned int npy_next_is(const NpyText *text, unsigned char wanted)
{
    return ((text->at < text->length) && (text->text[text->at] == wanted)) ? 1u : 0u;
}

static unsigned int npy_quoted(NpyText *text, unsigned long long *start, unsigned long long *end)
{
    npy_space(text);
    if (text->at >= text->length)
    {
        return 0u;
    }
    const unsigned char quote = text->text[text->at];
    if ((quote != '\'') && (quote != '"'))
    {
        return 0u;
    }
    text->at += 1ull;
    *start = text->at;
    while ((text->at < text->length) && (text->text[text->at] != quote))
    {
        if (text->text[text->at] == '\\')
        {
            return 0u;
        }
        text->at += 1ull;
    }
    if (text->at >= text->length)
    {
        return 0u;
    }
    *end = text->at;
    text->at += 1ull;
    return 1u;
}

static unsigned int npy_word(NpyText *text, const char *word)
{
    npy_space(text);
    const size_t size = strlen(word);
    if (((text->length - text->at) < size) || (memcmp(text->text + text->at, word, size) != 0))
    {
        return 0u;
    }
    text->at += size;
    return 1u;
}

static unsigned int npy_named(const unsigned char *spelled, unsigned long long length, const char *name)
{
    const size_t size = strlen(name);
    return ((length == size) && (memcmp(spelled, name, size) == 0)) ? 1u : 0u;
}

static unsigned int npy_description(const unsigned char *spelled, unsigned long long length, NpyLayout *layout)
{
    if (length != 3ull)
    {
        return 0u;
    }
    const unsigned char order = spelled[0u];
    const unsigned char kind = spelled[1u];
    const unsigned char digit = spelled[2u];
    if ((digit < '1') || (digit > '8'))
    {
        return 0u;
    }
    const unsigned int bytes = (unsigned int)(digit - '0');
    const int sized = (bytes == 1u) || (bytes == 2u) || (bytes == 4u) || (bytes == 8u);
    const int ordered = (order == '<') || (order == '>') || ((order == '|') && (bytes == 1u));
    const int unsigned_kind = (kind == 'u') || ((kind == 'b') && (bytes == 1u));
    const int signed_kind = (kind == 'i');
    const int float_kind = (kind == 'f') && (bytes >= 2u);
    if (!sized || !ordered || !(unsigned_kind || signed_kind || float_kind))
    {
        return 0u;
    }
    layout->shape.element_bytes = bytes;
    layout->shape.element_kind = unsigned_kind ? ENGINE_ELEMENT_UNSIGNED
                               : signed_kind   ? ENGINE_ELEMENT_SIGNED
                                               : ENGINE_ELEMENT_FLOAT;
    layout->big_endian = ((order == '>') && (bytes > 1u)) ? 1u : 0u;
    return 1u;
}

static unsigned int npy_shape(NpyText *text, EngineArrayShape *shape)
{
    if (!npy_expect(text, '('))
    {
        return 0u;
    }
    unsigned int rank = 0u;
    npy_space(text);
    while ((text->at < text->length) && (text->text[text->at] != ')'))
    {
        if (rank == ENGINE_ARRAY_RANK)
        {
            return 0u;
        }
        unsigned long long value = 0ull;
        const unsigned long long digits = text->at;
        while ((text->at < text->length) && (text->text[text->at] >= '0') && (text->text[text->at] <= '9'))
        {
            const unsigned long long digit = (unsigned long long)(text->text[text->at] - '0');
            if (value > ((NPY_BYTES_LIMIT - digit) / 10ull))
            {
                return 0u;
            }
            value = (value * 10ull) + digit;
            text->at += 1ull;
        }
        if (text->at == digits)
        {
            return 0u;
        }
        text->at += npy_next_is(text, 'L');
        shape->shape[rank] = value;
        rank += 1u;
        npy_space(text);
        if (npy_next_is(text, ','))
        {
            text->at += 1ull;
            npy_space(text);
        }
        else if (!npy_next_is(text, ')'))
        {
            return 0u;
        }
    }
    if (!npy_expect(text, ')'))
    {
        return 0u;
    }
    shape->rank = rank;
    return (rank > 0u) ? 1u : 0u;
}

static unsigned int npy_dictionary(const unsigned char *header, unsigned long long length, NpyLayout *layout)
{
    NpyText text = {header, length, 0ull};
    unsigned int seen = 0u;
    if (!npy_expect(&text, '{'))
    {
        return 0u;
    }
    npy_space(&text);
    while ((text.at < text.length) && (text.text[text.at] != '}'))
    {
        unsigned long long key_start = 0ull;
        unsigned long long key_end = 0ull;
        if (!npy_quoted(&text, &key_start, &key_end) || !npy_expect(&text, ':'))
        {
            return 0u;
        }
        const unsigned char *const key = header + key_start;
        const unsigned long long key_length = key_end - key_start;
        if (npy_named(key, key_length, "descr") && ((seen & 1u) == 0u))
        {
            unsigned long long value_start = 0ull;
            unsigned long long value_end = 0ull;
            if (!npy_quoted(&text, &value_start, &value_end)
                || !npy_description(header + value_start, value_end - value_start, layout))
            {
                return 0u;
            }
            seen |= 1u;
        }
        else if (npy_named(key, key_length, "fortran_order") && ((seen & 2u) == 0u))
        {
            const unsigned int truth = npy_word(&text, "True");
            if (!truth && !npy_word(&text, "False"))
            {
                return 0u;
            }
            layout->fortran_order = truth;
            seen |= 2u;
        }
        else if (npy_named(key, key_length, "shape") && ((seen & 4u) == 0u))
        {
            if (!npy_shape(&text, &layout->shape))
            {
                return 0u;
            }
            seen |= 4u;
        }
        else
        {
            return 0u;
        }
        npy_space(&text);
        if (npy_next_is(&text, ','))
        {
            text.at += 1ull;
            npy_space(&text);
        }
        else if (!npy_next_is(&text, '}'))
        {
            return 0u;
        }
    }
    if (!npy_expect(&text, '}'))
    {
        return 0u;
    }
    npy_space(&text);
    return ((seen == 7u) && (text.at == text.length)) ? 1u : 0u;
}

static unsigned int npy_total(const EngineArrayShape *shape, unsigned int from_axis, unsigned long long *total)
{
    unsigned long long product = shape->element_bytes;
    unsigned int empty = 0u;
    for (unsigned int axis = from_axis; axis < shape->rank; axis += 1u)
    {
        empty |= (shape->shape[axis] == 0ull) ? 1u : 0u;
    }
    for (unsigned int axis = from_axis; (empty == 0u) && (axis < shape->rank); axis += 1u)
    {
        if (!npy_multiply(product, shape->shape[axis], &product))
        {
            return 0u;
        }
    }
    *total = (empty != 0u) ? 0ull : product;
    return 1u;
}

static unsigned int npy_layout(const NpySource *source, NpyLayout *layout)
{
    unsigned char preamble[12u];
    const unsigned long long preamble_bytes = (source->length < 12ull) ? source->length : 12ull;
    if ((preamble_bytes < 10ull) || !npy_source_fetch(source, 0ull, preamble_bytes, preamble)
        || (memcmp(preamble, npy_magic, sizeof npy_magic) != 0))
    {
        return 0u;
    }
    const unsigned int major = preamble[6u];
    const unsigned int minor = preamble[7u];
    if ((minor != 0u) || (major < 1u) || (major > 3u) || ((major > 1u) && (preamble_bytes < 12ull)))
    {
        return 0u;
    }
    const unsigned long long header_start = (major == 1u) ? 10ull : 12ull;
    const unsigned long long header_length = npy_load(preamble + 8u, (major == 1u) ? 2u : 4u);
    if (header_length > (source->length - header_start))
    {
        return 0u;
    }
    unsigned char *const header = malloc((size_t)header_length + 1u);
    if (header == NULL)
    {
        return 0u;
    }
    NpyLayout parsed = npy_empty_layout;
    const int understood = npy_source_fetch(source, header_start, header_length, header)
                        && npy_dictionary(header, header_length, &parsed);
    free(header);
    unsigned long long data_bytes = 0ull;
    if (!understood || !npy_total(&parsed.shape, 0u, &data_bytes))
    {
        return 0u;
    }
    parsed.data_offset = header_start + header_length;
    parsed.data_bytes = data_bytes;
    if (data_bytes > (source->length - parsed.data_offset))
    {
        return 0u;
    }
    *layout = parsed;
    return 1u;
}

static unsigned int npy_zip_open(const EngineIngestTools *tools, const char *path, const ZipArchive *archive,
                                 const ZipEntry *entry, NpySource *source, unsigned char **owned, EngineError *error)
{
    if (entry->method == 0ull)
    {
        unsigned long long data_start = 0ull;
        if (!zip_member_data(tools, path, archive, entry, &data_start, error)
            || !NPY_HELD(entry->compressed == entry->uncompressed, entry, error, ENGINE_ERROR_REQUEST))
        {
            return 0u;
        }
        const NpySource stored = {tools, path, data_start, entry->uncompressed, NULL};
        *source = stored;
        return 1u;
    }
    unsigned char *const unpacked = npy_fits_memory(entry->uncompressed + 1ull)
                                  ? malloc((size_t)entry->uncompressed + 1u) : NULL;
    if (!NPY_HELD(unpacked != NULL, entry, error, ENGINE_ERROR_RESOURCE))
    {
        return 0u;
    }
    if (zip_member_read(tools, path, archive, entry, unpacked, entry->uncompressed, error) == ZIP_REFUSED)
    {
        free(unpacked);
        return 0u;
    }
    const NpySource inflated = {tools, path, 0ull, entry->uncompressed, unpacked};
    *source = inflated;
    *owned = unpacked;
    return 1u;
}

static unsigned int npy_zip_candidate(const ZipEntry *entry, const char *member)
{
    const int directory = (entry->name_length > 0ull) && (entry->name[entry->name_length - 1ull] == '/');
    if (directory)
    {
        return 0u;
    }
    if (member == NULL)
    {
        return 1u;
    }
    const size_t member_length = strlen(member);
    const int exact = (entry->name_length == member_length) && (memcmp(entry->name, member, member_length) == 0);
    const int suffixed = (entry->name_length == (member_length + 4u)) && (memcmp(entry->name, member, member_length) == 0)
                      && (memcmp(entry->name + member_length, ".npy", 4u) == 0);
    return (exact || suffixed) ? 1u : 0u;
}

static void npy_zip_list(const EngineIngestTools *tools, const char *path, const char *member,
                         const ZipArchive *archive, unsigned long long matches)
{
    fprintf(stderr, "npy: %s holds %llu candidate arrays%s%s; name one as the member\n", path, matches,
            (member != NULL) ? " named " : "", (member != NULL) ? member : "");
    unsigned long long at = 0ull;
    for (unsigned long long entry_index = 0ull; entry_index < archive->entries; entry_index += 1ull)
    {
        EngineError probe;
        memset(&probe, 0, sizeof(probe));
        ZipEntry entry = npy_empty_entry;
        if (!zip_entry_next(archive, &at, &entry, &probe))
        {
            return;
        }
        if (!npy_zip_candidate(&entry, member))
        {
            continue;
        }
        NpySource source = npy_empty_source;
        unsigned char *owned = NULL;
        NpyLayout layout = npy_empty_layout;
        const int parsed = npy_zip_open(tools, path, archive, &entry, &source, &owned, &probe)
                        && npy_layout(&source, &layout);
        free(owned);
        fprintf(stderr, "npy:   %.*s ", (int)entry.name_length, (const char *)entry.name);
        if (!parsed)
        {
            fprintf(stderr, "unreadable\n");
            continue;
        }
        fprintf(stderr, "(");
        for (unsigned int axis = 0u; axis < layout.shape.rank; axis += 1u)
        {
            fprintf(stderr, (axis == 0u) ? "%llu" : ", %llu", layout.shape.shape[axis]);
        }
        fprintf(stderr, ")\n");
    }
}

static unsigned int npy_zip_select(const EngineIngestTools *tools, const char *path, const char *member,
                                   const ZipArchive *archive, ZipEntry *chosen, EngineError *error)
{
    unsigned long long matches = 0ull;
    unsigned long long at = 0ull;
    for (unsigned long long entry_index = 0ull; entry_index < archive->entries; entry_index += 1ull)
    {
        ZipEntry entry = npy_empty_entry;
        if (!zip_entry_next(archive, &at, &entry, error))
        {
            return 0u;
        }
        if (npy_zip_candidate(&entry, member))
        {
            matches += 1ull;
            *chosen = entry;
        }
    }
    if (matches > 1ull)
    {
        npy_zip_list(tools, path, member, archive, matches);
    }
    return NPY_HELD(matches == 1ull, &matches, error, ENGINE_ERROR_REQUEST) ? 1u : 0u;
}

static unsigned int npy_resolve(const char *path, const char *member, const EngineIngestTools *tools, NpySource *source,
                                unsigned char **owned, NpyLayout *layout, EngineError *error)
{
    *owned = NULL;
    const long long size = tools->size(path);
    unsigned char magic[4u];
    if (!NPY_HELD((size >= 4LL) && npy_file_fetch(tools, path, 0ull, 4ull, magic), path, error, ENGINE_ERROR_REQUEST))
    {
        return 0u;
    }
    // a size of at least four converts to unsigned long long exactly
    const unsigned long long file_bytes = (unsigned long long)size;
    if (memcmp(magic, npy_magic, sizeof magic) == 0)
    {
        const NpySource whole = {tools, path, 0ull, file_bytes, NULL};
        *source = whole;
        return NPY_HELD((member == NULL) && npy_layout(source, layout), path, error, ENGINE_ERROR_REQUEST) ? 1u : 0u;
    }
    if (!NPY_HELD((memcmp(magic, npy_zip_local, sizeof magic) == 0) || (memcmp(magic, npy_zip_end, sizeof magic) == 0),
                  magic, error, ENGINE_ERROR_REQUEST))
    {
        return 0u;
    }
    ZipArchive archive;
    if (!zip_archive_open(tools, path, &archive, error))
    {
        return 0u;
    }
    ZipEntry entry = npy_empty_entry;
    const int good = npy_zip_select(tools, path, member, &archive, &entry, error)
                  && npy_zip_open(tools, path, &archive, &entry, source, owned, error)
                  && NPY_HELD(npy_layout(source, layout), source, error, ENGINE_ERROR_REQUEST);
    zip_archive_release(&archive);
    if (!good)
    {
        free(*owned);
        *owned = NULL;
    }
    return good ? 1u : 0u;
}

static unsigned int npy_same_shape(const EngineArrayShape *found, const EngineArrayShape *given)
{
    int same = (found->rank == given->rank) && (found->element_bytes == given->element_bytes)
            && (found->element_kind == given->element_kind);
    for (unsigned int axis = 0u; same && (axis < found->rank); axis += 1u)
    {
        same = (found->shape[axis] == given->shape[axis]) && (found->axes[axis] == given->axes[axis]);
    }
    return same ? 1u : 0u;
}

static unsigned int npy_fortran_copy(const NpySource *source, const NpyLayout *layout, unsigned long long first,
                                     unsigned long long count, unsigned char *out)
{
    const EngineArrayShape *const shape = &layout->shape;
    const unsigned long long element = shape->element_bytes;
    const unsigned long long stride = shape->shape[0u];
    unsigned long long output_step[ENGINE_ARRAY_RANK];
    unsigned long long position[ENGINE_ARRAY_RANK];
    unsigned long long columns = 1ull;
    for (unsigned int axis = shape->rank; axis > 0u; axis -= 1u)
    {
        output_step[axis - 1u] = columns;
        position[axis - 1u] = 0ull;
        columns *= (axis > 1u) ? shape->shape[axis - 1u] : 1ull;
    }
    if (columns == 0ull)
    {
        return 1u;
    }
    const unsigned long long run = count * element;
    const unsigned long long column_bytes = stride * element;
    const unsigned long long reach = (run < NPY_FORTRAN_BLOCK) ? (1ull + ((NPY_FORTRAN_BLOCK - run) / column_bytes)) : 1ull;
    const unsigned long long group = (reach < columns) ? reach : columns;
    unsigned char *const block = malloc((size_t)(((group - 1ull) * column_bytes) + run));
    if (block == NULL)
    {
        return 0u;
    }
    unsigned long long place = 0ull;
    unsigned long long column = 0ull;
    unsigned int good = 1u;
    while ((good != 0u) && (column < columns))
    {
        const unsigned long long taken = ((columns - column) < group) ? (columns - column) : group;
        const unsigned long long span = ((taken - 1ull) * column_bytes) + run;
        good = npy_source_fetch(source, layout->data_offset + (((column * stride) + first) * element), span, block);
        for (unsigned long long within = 0ull; (good != 0u) && (within < taken); within += 1ull)
        {
            const unsigned char *const from = block + (within * column_bytes);
            for (unsigned long long row = 0ull; row < count; row += 1ull)
            {
                memcpy(out + (((row * columns) + place) * element), from + (row * element), (size_t)element);
            }
            for (unsigned int axis = 1u; axis < shape->rank; axis += 1u)
            {
                position[axis] += 1ull;
                place += output_step[axis];
                if (position[axis] < shape->shape[axis])
                {
                    break;
                }
                place -= position[axis] * output_step[axis];
                position[axis] = 0ull;
            }
        }
        column += taken;
    }
    free(block);
    return good;
}

long npy_describe(const EngineDescribeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1L;
    }
    NpySource source = npy_empty_source;
    unsigned char *owned = NULL;
    NpyLayout layout = npy_empty_layout;
    const unsigned int resolved = npy_resolve(request->path, request->member, request->tools, &source, &owned, &layout,
                                              request->error);
    free(owned);
    if (!resolved)
    {
        return -1L;
    }
    *request->shape = layout.shape;
    return 0L;
}

long long npy_read(const EngineArrayRead *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return -1LL;
    }
    NpySource source = npy_empty_source;
    unsigned char *owned = NULL;
    NpyLayout layout = npy_empty_layout;
    const unsigned int resolved = npy_resolve(request->path, request->member, request->tools, &source, &owned, &layout,
                                              request->error);
    unsigned long long row_bytes = 0ull;
    const int agrees = resolved && npy_same_shape(&layout.shape, request->shape) && (request->first <= request->past)
                    && (request->past <= layout.shape.shape[0u]) && npy_total(&layout.shape, 1u, &row_bytes);
    const unsigned long long count = agrees ? (request->past - request->first) : 0ull;
    const unsigned long long wanted = count * row_bytes;
    if (!agrees || (wanted > request->out_room) || !npy_fits_memory(wanted))
    {
        free(owned);
        return -1LL;
    }
    if (wanted == 0ull)
    {
        free(owned);
        return 0LL;
    }
    const unsigned int copied = (layout.fortran_order != 0u)
                              ? npy_fortran_copy(&source, &layout, request->first, count, request->out)
                              : npy_source_fetch(&source, layout.data_offset + (request->first * row_bytes), wanted,
                                                 request->out);
    free(owned);
    if (!copied)
    {
        memset(request->out, 0, (size_t)wanted);
        return -1LL;
    }
    if (layout.big_endian != 0u)
    {
        npy_swap(request->out, wanted, layout.shape.element_bytes);
    }
    return (long long)wanted;
}
