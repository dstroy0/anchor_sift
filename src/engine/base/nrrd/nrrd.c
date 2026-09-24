// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "nrrd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NRRD_BYTES_LIMIT 9223372036854775807ull
#define NRRD_SKIP_CHUNK 4096u
#define NRRD_GZIP_SMALLEST 18ull

typedef enum
{
    NRRD_KIND_OTHER = 0,
    NRRD_KIND_SPACE = 1,
    NRRD_KIND_TIME = 2
} NrrdKind;

typedef enum
{
    NRRD_UNSET = 0,
    NRRD_LITTLE = 1,
    NRRD_BIG = 2
} NrrdEndian;

typedef enum
{
    NRRD_ENCODING_UNSET = 0,
    NRRD_ENCODING_RAW = 1,
    NRRD_ENCODING_GZIP = 2
} NrrdEncoding;

typedef struct
{
    const char *name;
    unsigned int element_bytes;
    EngineElementKind element_kind;
} NrrdType;

typedef struct
{
    const char *name;
    unsigned int timed;
} NrrdSpace;

typedef struct
{
    const char *text;
    unsigned long long length;
} NrrdSpan;

typedef struct
{
    unsigned int dimension;
    unsigned int typed;
    unsigned int element_bytes;
    EngineElementKind element_kind;
    NrrdEndian endian;
    NrrdEncoding encoding;
    unsigned int sizes_count;
    unsigned long long sizes[ENGINE_ARRAY_RANK];
    unsigned int kinds_count;
    NrrdKind kinds[ENGINE_ARRAY_RANK];
    unsigned int directions_count;
    unsigned int directions[ENGINE_ARRAY_RANK];
    unsigned int spaced;
    unsigned int space_timed;
    unsigned long long line_skip;
    unsigned long long byte_skip;
    unsigned int skip_to_end;
    NrrdSpan data_file;
    unsigned int ended;
    unsigned long long header_end;
} NrrdFields;

typedef struct
{
    EngineArrayShape shape;
    unsigned int big_endian;
    unsigned int gzip;
    char *data_path;
    unsigned long long data_offset;
    unsigned long long data_bytes;
    unsigned long long byte_skip;
    unsigned long long file_bytes;
} NrrdLayout;

static const NrrdType nrrd_types[] = {
    {"signed char", 1u, ENGINE_ELEMENT_SIGNED},
    {"int8", 1u, ENGINE_ELEMENT_SIGNED},
    {"int8_t", 1u, ENGINE_ELEMENT_SIGNED},
    {"uchar", 1u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned char", 1u, ENGINE_ELEMENT_UNSIGNED},
    {"uint8", 1u, ENGINE_ELEMENT_UNSIGNED},
    {"uint8_t", 1u, ENGINE_ELEMENT_UNSIGNED},
    {"short", 2u, ENGINE_ELEMENT_SIGNED},
    {"short int", 2u, ENGINE_ELEMENT_SIGNED},
    {"signed short", 2u, ENGINE_ELEMENT_SIGNED},
    {"signed short int", 2u, ENGINE_ELEMENT_SIGNED},
    {"int16", 2u, ENGINE_ELEMENT_SIGNED},
    {"int16_t", 2u, ENGINE_ELEMENT_SIGNED},
    {"ushort", 2u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned short", 2u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned short int", 2u, ENGINE_ELEMENT_UNSIGNED},
    {"uint16", 2u, ENGINE_ELEMENT_UNSIGNED},
    {"uint16_t", 2u, ENGINE_ELEMENT_UNSIGNED},
    {"int", 4u, ENGINE_ELEMENT_SIGNED},
    {"signed int", 4u, ENGINE_ELEMENT_SIGNED},
    {"int32", 4u, ENGINE_ELEMENT_SIGNED},
    {"int32_t", 4u, ENGINE_ELEMENT_SIGNED},
    {"uint", 4u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned int", 4u, ENGINE_ELEMENT_UNSIGNED},
    {"uint32", 4u, ENGINE_ELEMENT_UNSIGNED},
    {"uint32_t", 4u, ENGINE_ELEMENT_UNSIGNED},
    {"longlong", 8u, ENGINE_ELEMENT_SIGNED},
    {"long long", 8u, ENGINE_ELEMENT_SIGNED},
    {"long long int", 8u, ENGINE_ELEMENT_SIGNED},
    {"signed long long", 8u, ENGINE_ELEMENT_SIGNED},
    {"signed long long int", 8u, ENGINE_ELEMENT_SIGNED},
    {"int64", 8u, ENGINE_ELEMENT_SIGNED},
    {"int64_t", 8u, ENGINE_ELEMENT_SIGNED},
    {"ulonglong", 8u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned long long", 8u, ENGINE_ELEMENT_UNSIGNED},
    {"unsigned long long int", 8u, ENGINE_ELEMENT_UNSIGNED},
    {"uint64", 8u, ENGINE_ELEMENT_UNSIGNED},
    {"uint64_t", 8u, ENGINE_ELEMENT_UNSIGNED},
    {"float", 4u, ENGINE_ELEMENT_FLOAT},
    {"double", 8u, ENGINE_ELEMENT_FLOAT}};

static const NrrdSpace nrrd_spaces[] = {
    {"right-anterior-superior", 0u},
    {"RAS", 0u},
    {"left-anterior-superior", 0u},
    {"LAS", 0u},
    {"left-posterior-superior", 0u},
    {"LPS", 0u},
    {"right-anterior-superior-time", 1u},
    {"RAST", 1u},
    {"left-anterior-superior-time", 1u},
    {"LAST", 1u},
    {"left-posterior-superior-time", 1u},
    {"LPST", 1u},
    {"scanner-xyz", 0u},
    {"scanner-xyz-time", 1u},
    {"3D-right-handed", 0u},
    {"3D-left-handed", 0u},
    {"3D-right-handed-time", 1u},
    {"3D-left-handed-time", 1u}};

static const char *const nrrd_ignored[] = {
    "content",     "number",     "block size", "blocksize",    "min",         "max",
    "old min",     "oldmin",     "old max",    "oldmax",       "spacings",    "thicknesses",
    "axis mins",   "axismins",   "axis maxs",  "axismaxs",     "centers",     "centerings",
    "labels",      "units",      "sample units", "sampleunits", "space units", "space origin",
    "measurement frame"};

static const char *const nrrd_refused[] = {"bzip2", "bz2", "ascii", "text", "txt", "hex"};

static const NrrdFields nrrd_empty_fields = {0u,
                                             0u,
                                             0u,
                                             ENGINE_ELEMENT_UNSIGNED,
                                             NRRD_UNSET,
                                             NRRD_ENCODING_UNSET,
                                             0u,
                                             {0ull},
                                             0u,
                                             {NRRD_KIND_OTHER},
                                             0u,
                                             {0u},
                                             0u,
                                             0u,
                                             0ull,
                                             0ull,
                                             0u,
                                             {NULL, 0ull},
                                             0u,
                                             0ull};

static const NrrdLayout nrrd_empty_layout = {{0u, {0ull}, {'\0'}, 0u, ENGINE_ELEMENT_UNSIGNED}, 0u, 0u, NULL, 0ull,
                                             0ull, 0ull, 0ull};

static unsigned int nrrd_fits_memory(unsigned long long bytes)
{
    return ((unsigned long long)(size_t)bytes == bytes) ? 1u : 0u;
}

static unsigned int nrrd_multiply(unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (NRRD_BYTES_LIMIT / left)))
    {
        return 0u;
    }
    *product = left * right;
    return 1u;
}

static unsigned int nrrd_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
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

static void nrrd_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes)
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

static unsigned int nrrd_blank(char byte)
{
    return ((byte == ' ') || (byte == '\t')) ? 1u : 0u;
}

static NrrdSpan nrrd_trim(NrrdSpan span)
{
    NrrdSpan trimmed = span;
    while ((trimmed.length > 0ull) && nrrd_blank(trimmed.text[0u]))
    {
        trimmed.text += 1u;
        trimmed.length -= 1ull;
    }
    while ((trimmed.length > 0ull) && nrrd_blank(trimmed.text[trimmed.length - 1ull]))
    {
        trimmed.length -= 1ull;
    }
    return trimmed;
}

static unsigned int nrrd_equals(NrrdSpan span, const char *word)
{
    const size_t size = strlen(word);
    return ((span.length == size) && (memcmp(span.text, word, size) == 0)) ? 1u : 0u;
}

static unsigned int nrrd_listed(NrrdSpan span, const char *const *words, size_t count)
{
    unsigned int found = 0u;
    for (size_t word = 0u; word < count; word += 1u)
    {
        found |= nrrd_equals(span, words[word]);
    }
    return found;
}

static unsigned int nrrd_token(NrrdSpan *rest, NrrdSpan *token)
{
    *rest = nrrd_trim(*rest);
    if (rest->length == 0ull)
    {
        return 0u;
    }
    const char closing = (rest->text[0u] == '(') ? ')' : '\0';
    unsigned long long size = 0ull;
    unsigned int closed = 0u;
    while ((size < rest->length) && (closed == 0u) && ((closing != '\0') || !nrrd_blank(rest->text[size])))
    {
        closed = ((closing != '\0') && (rest->text[size] == closing)) ? 1u : 0u;
        size += 1ull;
    }
    token->text = rest->text;
    token->length = size;
    rest->text += size;
    rest->length -= size;
    return 1u;
}

static unsigned int nrrd_unsigned(NrrdSpan span, unsigned long long *value)
{
    unsigned long long total = 0ull;
    if (span.length == 0ull)
    {
        return 0u;
    }
    for (unsigned long long at = 0ull; at < span.length; at += 1ull)
    {
        if ((span.text[at] < '0') || (span.text[at] > '9'))
        {
            return 0u;
        }
        const unsigned long long digit = (unsigned long long)(span.text[at] - '0');
        if (total > ((NRRD_BYTES_LIMIT - digit) / 10ull))
        {
            return 0u;
        }
        total = (total * 10ull) + digit;
    }
    *value = total;
    return 1u;
}

static unsigned int nrrd_single(NrrdSpan value, unsigned long long *number)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    NrrdSpan after = {NULL, 0ull};
    return (nrrd_token(&rest, &token) && nrrd_unsigned(token, number) && !nrrd_token(&rest, &after)) ? 1u : 0u;
}

static unsigned int nrrd_type(NrrdSpan value, NrrdFields *fields)
{
    for (size_t entry = 0u; entry < (sizeof nrrd_types / sizeof nrrd_types[0u]); entry += 1u)
    {
        if (nrrd_equals(value, nrrd_types[entry].name))
        {
            fields->element_bytes = nrrd_types[entry].element_bytes;
            fields->element_kind = nrrd_types[entry].element_kind;
            fields->typed = 1u;
            return 1u;
        }
    }
    fprintf(stderr, "nrrd: type %.*s is refused\n", (int)value.length, value.text);
    return 0u;
}

static unsigned int nrrd_encoding(NrrdSpan value, NrrdFields *fields)
{
    if (nrrd_equals(value, "raw"))
    {
        fields->encoding = NRRD_ENCODING_RAW;
        return 1u;
    }
    if (nrrd_equals(value, "gzip") || nrrd_equals(value, "gz"))
    {
        fields->encoding = NRRD_ENCODING_GZIP;
        return 1u;
    }
    const unsigned int named = nrrd_listed(value, nrrd_refused, sizeof nrrd_refused / sizeof nrrd_refused[0u]);
    fprintf(stderr, "nrrd: encoding %.*s is refused%s\n", (int)value.length, value.text,
            named ? "" : " as unknown");
    return 0u;
}

static unsigned int nrrd_space(NrrdSpan value, NrrdFields *fields)
{
    for (size_t entry = 0u; entry < (sizeof nrrd_spaces / sizeof nrrd_spaces[0u]); entry += 1u)
    {
        if (nrrd_equals(value, nrrd_spaces[entry].name))
        {
            fields->spaced = 1u;
            fields->space_timed = nrrd_spaces[entry].timed;
            return 1u;
        }
    }
    return 0u;
}

static unsigned int nrrd_sizes(NrrdSpan value, NrrdFields *fields)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    unsigned int count = 0u;
    while (nrrd_token(&rest, &token))
    {
        unsigned long long size = 0ull;
        if ((count == ENGINE_ARRAY_RANK) || !nrrd_unsigned(token, &size) || (size == 0ull))
        {
            return 0u;
        }
        fields->sizes[count] = size;
        count += 1u;
    }
    fields->sizes_count = count;
    return (count > 0u) ? 1u : 0u;
}

static unsigned int nrrd_kinds(NrrdSpan value, NrrdFields *fields)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    unsigned int count = 0u;
    while (nrrd_token(&rest, &token))
    {
        if (count == ENGINE_ARRAY_RANK)
        {
            return 0u;
        }
        fields->kinds[count] = nrrd_equals(token, "space") ? NRRD_KIND_SPACE
                             : nrrd_equals(token, "time")  ? NRRD_KIND_TIME
                                                           : NRRD_KIND_OTHER;
        count += 1u;
    }
    fields->kinds_count = count;
    return (count > 0u) ? 1u : 0u;
}

static unsigned int nrrd_directions(NrrdSpan value, NrrdFields *fields)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    unsigned int count = 0u;
    while (nrrd_token(&rest, &token))
    {
        const int vector = (token.length >= 2ull) && (token.text[0u] == '(') && (token.text[token.length - 1ull] == ')');
        if ((count == ENGINE_ARRAY_RANK) || (!vector && !nrrd_equals(token, "none")))
        {
            return 0u;
        }
        fields->directions[count] = vector ? 1u : 0u;
        count += 1u;
    }
    fields->directions_count = count;
    return (count > 0u) ? 1u : 0u;
}

static unsigned int nrrd_data_file(NrrdSpan value, NrrdFields *fields)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    const int listed = nrrd_token(&rest, &token) && nrrd_equals(token, "LIST");
    const int formatted = (memchr(value.text, '%', (size_t)value.length) != NULL);
    if ((value.length == 0ull) || listed || formatted)
    {
        fprintf(stderr, "nrrd: a multi-file data file is refused\n");
        return 0u;
    }
    fields->data_file = value;
    return 1u;
}

static unsigned int nrrd_field(NrrdSpan line, NrrdFields *fields)
{
    const char *const colon = memchr(line.text, ':', (size_t)line.length);
    if (colon == NULL)
    {
        return 0u;
    }
    const unsigned long long key_length = (unsigned long long)(colon - line.text);
    if (((key_length + 1ull) < line.length) && (colon[1u] == '='))
    {
        return 1u;
    }
    const NrrdSpan key = {line.text, key_length};
    const NrrdSpan raw_value = {colon + 1u, line.length - key_length - 1ull};
    const NrrdSpan value = nrrd_trim(raw_value);
    unsigned long long number = 0ull;
    if (nrrd_equals(key, "dimension"))
    {
        const int good = (fields->dimension == 0u) && nrrd_single(value, &number) && (number >= 1ull)
                      && (number <= ENGINE_ARRAY_RANK);
        fields->dimension = good ? (unsigned int)number : 0u;
        return good ? 1u : 0u;
    }
    if (nrrd_equals(key, "type"))
    {
        return nrrd_type(value, fields);
    }
    if (nrrd_equals(key, "encoding"))
    {
        return nrrd_encoding(value, fields);
    }
    if (nrrd_equals(key, "endian"))
    {
        fields->endian = nrrd_equals(value, "little") ? NRRD_LITTLE : nrrd_equals(value, "big") ? NRRD_BIG : NRRD_UNSET;
        return (fields->endian != NRRD_UNSET) ? 1u : 0u;
    }
    if (nrrd_equals(key, "sizes"))
    {
        return nrrd_sizes(value, fields);
    }
    if (nrrd_equals(key, "kinds"))
    {
        return nrrd_kinds(value, fields);
    }
    if (nrrd_equals(key, "space directions"))
    {
        return nrrd_directions(value, fields);
    }
    if (nrrd_equals(key, "space"))
    {
        return nrrd_space(value, fields);
    }
    if (nrrd_equals(key, "space dimension"))
    {
        fields->spaced = (nrrd_single(value, &number) && (number >= 1ull)) ? 1u : 0u;
        return fields->spaced;
    }
    if (nrrd_equals(key, "line skip") || nrrd_equals(key, "lineskip"))
    {
        return nrrd_single(value, &fields->line_skip);
    }
    if (nrrd_equals(key, "byte skip") || nrrd_equals(key, "byteskip"))
    {
        fields->skip_to_end = nrrd_equals(value, "-1");
        return (fields->skip_to_end || nrrd_single(value, &fields->byte_skip)) ? 1u : 0u;
    }
    if (nrrd_equals(key, "data file") || nrrd_equals(key, "datafile"))
    {
        return nrrd_data_file(value, fields);
    }
    if (nrrd_listed(key, nrrd_ignored, sizeof nrrd_ignored / sizeof nrrd_ignored[0u]))
    {
        return 1u;
    }
    fprintf(stderr, "nrrd: field %.*s is not known\n", (int)key.length, key.text);
    return 0u;
}

static unsigned int nrrd_fields(const char *header, unsigned long long length, unsigned int complete, NrrdFields *fields)
{
    unsigned long long at = 0ull;
    unsigned long long line_number = 0ull;
    while (at < length)
    {
        unsigned long long stop = at;
        while ((stop < length) && (header[stop] != '\n'))
        {
            stop += 1ull;
        }
        if ((stop == length) && !complete)
        {
            return 0u;
        }
        const unsigned long long next = (stop < length) ? (stop + 1ull) : stop;
        const unsigned long long line_end = ((stop > at) && (header[stop - 1ull] == '\r')) ? (stop - 1ull) : stop;
        const NrrdSpan line = {header + at, line_end - at};
        if (line_number == 0ull)
        {
            const int magic = (line.length == 8ull) && (memcmp(line.text, "NRRD000", 7u) == 0) && (line.text[7u] >= '1')
                           && (line.text[7u] <= '5');
            if (!magic)
            {
                return 0u;
            }
        }
        else if (line.length == 0ull)
        {
            fields->ended = 1u;
            fields->header_end = next;
            return 1u;
        }
        else if ((line.text[0u] != '#') && !nrrd_field(line, fields))
        {
            return 0u;
        }
        line_number += 1ull;
        at = next;
    }
    return (line_number > 0ull) ? 1u : 0u;
}

static unsigned int nrrd_shape(const NrrdFields *fields, EngineArrayShape *shape)
{
    const int complete = fields->typed && (fields->dimension > 0u) && (fields->sizes_count == fields->dimension)
                      && (fields->encoding != NRRD_ENCODING_UNSET)
                      && ((fields->endian != NRRD_UNSET) || (fields->element_bytes == 1u))
                      && ((fields->kinds_count == 0u) || (fields->kinds_count == fields->dimension))
                      && ((fields->directions_count == 0u) || (fields->directions_count == fields->dimension));
    if (!complete)
    {
        return 0u;
    }
    char labels[ENGINE_ARRAY_RANK];
    unsigned int spatial = 0u;
    unsigned int timed = 0u;
    for (unsigned int axis = 0u; axis < fields->dimension; axis += 1u)
    {
        const NrrdKind kind = (fields->kinds_count != 0u) ? fields->kinds[axis] : NRRD_KIND_OTHER;
        const int directed = fields->spaced && !fields->space_timed && (fields->directions_count != 0u)
                          && (fields->directions[axis] != 0u);
        const int time_axis = (kind == NRRD_KIND_TIME) && (timed == 0u);
        const int space_axis = (kind == NRRD_KIND_SPACE) || ((kind != NRRD_KIND_TIME) && directed);
        labels[axis] = time_axis                        ? 't'
                     : (space_axis && (spatial == 0u)) ? 'x'
                     : (space_axis && (spatial == 1u)) ? 'y'
                     : (space_axis && (spatial == 2u)) ? 'z'
                                                       : '\0';
        timed |= time_axis ? 1u : 0u;
        spatial += space_axis ? 1u : 0u;
    }
    EngineArrayShape built = nrrd_empty_layout.shape;
    built.rank = fields->dimension;
    built.element_bytes = fields->element_bytes;
    built.element_kind = fields->element_kind;
    for (unsigned int axis = 0u; axis < fields->dimension; axis += 1u)
    {
        built.shape[axis] = fields->sizes[fields->dimension - 1u - axis];
        built.axes[axis] = labels[fields->dimension - 1u - axis];
    }
    *shape = built;
    return 1u;
}

static char *nrrd_join(const char *header_path, NrrdSpan name)
{
    const int absolute = (name.text[0u] == '/') || (name.text[0u] == '\\') || ((name.length > 1ull) && (name.text[1u] == ':'));
    size_t directory_length = 0u;
    for (size_t at = 0u; !absolute && (header_path[at] != '\0'); at += 1u)
    {
        directory_length = ((header_path[at] == '/') || (header_path[at] == '\\')) ? (at + 1u) : directory_length;
    }
    char *const joined = malloc(directory_length + (size_t)name.length + 1u);
    if (joined == NULL)
    {
        return NULL;
    }
    memcpy(joined, header_path, directory_length);
    memcpy(joined + directory_length, name.text, (size_t)name.length);
    joined[directory_length + (size_t)name.length] = '\0';
    return joined;
}

static unsigned int nrrd_skip_lines(const EngineIngestTools *tools, const char *path, unsigned long long file_bytes,
                                    unsigned long long lines, unsigned long long *position)
{
    unsigned char chunk[NRRD_SKIP_CHUNK];
    unsigned long long at = *position;
    unsigned long long remaining = lines;
    while (remaining > 0ull)
    {
        if (at >= file_bytes)
        {
            return 0u;
        }
        const unsigned long long want = ((file_bytes - at) < NRRD_SKIP_CHUNK) ? (file_bytes - at) : NRRD_SKIP_CHUNK;
        if (!nrrd_fetch(tools, path, at, want, chunk))
        {
            return 0u;
        }
        unsigned long long used = 0ull;
        while ((used < want) && (remaining > 0ull))
        {
            remaining -= (chunk[used] == '\n') ? 1ull : 0ull;
            used += 1ull;
        }
        at += used;
    }
    *position = at;
    return 1u;
}

static unsigned int nrrd_locate(const EngineIngestTools *tools, const NrrdFields *fields, const char *data_path,
                                unsigned long long start, NrrdLayout *layout)
{
    const long long size = tools->size(data_path);
    if (size < 0LL)
    {
        return 0u;
    }
    const unsigned long long file_bytes = (unsigned long long)size;
    unsigned long long base = start;
    if ((base > file_bytes) || !nrrd_skip_lines(tools, data_path, file_bytes, fields->line_skip, &base))
    {
        return 0u;
    }
    layout->file_bytes = file_bytes;
    if (fields->encoding == NRRD_ENCODING_RAW)
    {
        const unsigned long long offset = fields->skip_to_end ? (file_bytes - layout->data_bytes) : (base + fields->byte_skip);
        const int fits = (layout->data_bytes <= file_bytes) && (offset >= base) && (offset <= file_bytes)
                      && (layout->data_bytes <= (file_bytes - offset)) && (fields->byte_skip <= file_bytes);
        layout->data_offset = offset;
        return fits ? 1u : 0u;
    }
    unsigned char opening[2u];
    unsigned char trailer[4u];
    const unsigned long long expected = fields->byte_skip + layout->data_bytes;
    const int framed = (tools->decode[ENGINE_CODEC_GZIP] != NULL) && !fields->skip_to_end
                    && (fields->byte_skip <= NRRD_BYTES_LIMIT - layout->data_bytes)
                    && ((file_bytes - base) >= NRRD_GZIP_SMALLEST) && nrrd_fetch(tools, data_path, base, 2ull, opening)
                    && nrrd_fetch(tools, data_path, file_bytes - 4ull, 4ull, trailer) && (opening[0u] == 0x1Fu)
                    && (opening[1u] == 0x8Bu);
    if (!framed)
    {
        return 0u;
    }
    const unsigned long long recorded = (unsigned long long)trailer[0u] | ((unsigned long long)trailer[1u] << 8u)
                                      | ((unsigned long long)trailer[2u] << 16u) | ((unsigned long long)trailer[3u] << 24u);
    layout->data_offset = base;
    layout->byte_skip = fields->byte_skip;
    layout->gzip = 1u;
    return (recorded == (expected & 0xFFFFFFFFull)) ? 1u : 0u;
}

static unsigned int nrrd_layout(const char *path, const char *member, const EngineIngestTools *tools, NrrdLayout *layout)
{
    if (member != NULL)
    {
        fprintf(stderr, "nrrd: %s holds one array; a member was named\n", path);
        return 0u;
    }
    const long long size = tools->size(path);
    if (size < 8LL)
    {
        return 0u;
    }
    const unsigned long long file_bytes = (unsigned long long)size;
    NrrdFields fields = nrrd_empty_fields;
    NrrdLayout built = nrrd_empty_layout;
    int parsed = 0;
    char *header = NULL;
    unsigned long long header_bytes = 1ull;
    for (;;)
    {
        header_bytes = (header_bytes < file_bytes) ? header_bytes : file_bytes;
        free(header);
        header = malloc((size_t)header_bytes + 1u);
        if (header == NULL)
        {
            return 0u;
        }
        fields = nrrd_empty_fields;
        built = nrrd_empty_layout;
        parsed = nrrd_fetch(tools, path, 0ull, header_bytes, (unsigned char *)header)
              && nrrd_fields(header, header_bytes, (header_bytes == file_bytes) ? 1u : 0u, &fields)
              && nrrd_shape(&fields, &built.shape)
              && ((fields.data_file.length != 0ull) || (fields.ended != 0u));
        if (parsed || (header_bytes == file_bytes))
        {
            break;
        }
        header_bytes *= 2ull;
    }
    built.data_bytes = built.shape.element_bytes;
    int good = parsed;
    for (unsigned int axis = 0u; good && (axis < built.shape.rank); axis += 1u)
    {
        good = nrrd_multiply(built.data_bytes, built.shape.shape[axis], &built.data_bytes);
    }
    if (good && (fields.data_file.length != 0ull))
    {
        built.data_path = nrrd_join(path, fields.data_file);
        good = (built.data_path != NULL);
    }
    free(header);
    const char *const data_path = (built.data_path != NULL) ? built.data_path : path;
    const unsigned long long start = (built.data_path != NULL) ? 0ull : fields.header_end;
    good = good && nrrd_locate(tools, &fields, data_path, start, &built);
    if (!good)
    {
        free(built.data_path);
        return 0u;
    }
    built.big_endian = ((fields.endian == NRRD_BIG) && (fields.element_bytes > 1u)) ? 1u : 0u;
    *layout = built;
    return 1u;
}

static unsigned int nrrd_same_shape(const EngineArrayShape *found, const EngineArrayShape *given)
{
    int same = (found->rank == given->rank) && (found->element_bytes == given->element_bytes)
            && (found->element_kind == given->element_kind);
    for (unsigned int axis = 0u; same && (axis < found->rank); axis += 1u)
    {
        same = (found->shape[axis] == given->shape[axis]) && (found->axes[axis] == given->axes[axis]);
    }
    return same ? 1u : 0u;
}

static unsigned int nrrd_inflate(const EngineIngestTools *tools, const char *data_path, const NrrdLayout *layout,
                                 unsigned long long offset, unsigned long long wanted, unsigned char *out)
{
    const EngineBytesDecode decode = tools->decode[ENGINE_CODEC_GZIP];
    const unsigned long long compressed = layout->file_bytes - layout->data_offset;
    const unsigned long long expected = layout->byte_skip + layout->data_bytes;
    if ((decode == NULL) || !nrrd_fits_memory(compressed) || !nrrd_fits_memory(expected) || (expected == 0ull))
    {
        return 0u;
    }
    unsigned char *const packed = malloc((size_t)compressed);
    unsigned char *const unpacked = malloc((size_t)expected);
    int good = (packed != NULL) && (unpacked != NULL)
            && nrrd_fetch(tools, data_path, layout->data_offset, compressed, packed);
    if (good)
    {
        const EngineBytesRequest request = {packed, compressed, unpacked, expected};
        const long long made = decode(&request);
        good = (made >= 0LL) && ((unsigned long long)made == expected);
    }
    free(packed);
    if (good)
    {
        memcpy(out, unpacked + layout->byte_skip + offset, (size_t)wanted);
    }
    free(unpacked);
    return good ? 1u : 0u;
}

long nrrd_describe(const EngineDescribeRequest *request)
{
    NrrdLayout layout = nrrd_empty_layout;
    if (!nrrd_layout(request->path, request->member, request->tools, &layout))
    {
        return -1L;
    }
    free(layout.data_path);
    *request->shape = layout.shape;
    return 0L;
}

long long nrrd_read(const EngineArrayRead *request)
{
    NrrdLayout layout = nrrd_empty_layout;
    if (!nrrd_layout(request->path, request->member, request->tools, &layout))
    {
        return -1LL;
    }
    const unsigned long long row_bytes = layout.data_bytes / layout.shape.shape[0u];
    const int agrees = nrrd_same_shape(&layout.shape, request->shape) && (request->first <= request->past)
                    && (request->past <= layout.shape.shape[0u]);
    const unsigned long long offset = agrees ? (request->first * row_bytes) : 0ull;
    const unsigned long long wanted = agrees ? ((request->past - request->first) * row_bytes) : 0ull;
    if (!agrees || (wanted > request->out_room) || !nrrd_fits_memory(wanted))
    {
        free(layout.data_path);
        return -1LL;
    }
    const char *const data_path = (layout.data_path != NULL) ? layout.data_path : request->path;
    const unsigned int copied = (wanted == 0ull) ? 1u
                              : (layout.gzip != 0u)
                                  ? nrrd_inflate(request->tools, data_path, &layout, offset, wanted, request->out)
                                  : nrrd_fetch(request->tools, data_path, layout.data_offset + offset, wanted, request->out);
    free(layout.data_path);
    if (!copied)
    {
        memset(request->out, 0, (size_t)wanted);
        return -1LL;
    }
    if (layout.big_endian != 0u)
    {
        nrrd_swap(request->out, wanted, layout.shape.element_bytes);
    }
    return (long long)wanted;
}
