// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// nrrd_header.c: the header's fields
#include "nrrd_internal.h"

static const NrrdType nrrd_types[] = {{"signed char", 1u, ENGINE_ELEMENT_SIGNED},
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

static const NrrdSpace nrrd_spaces[] = {{"right-anterior-superior", 0u},
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

static const char *const nrrd_refused[] = {"bzip2", "bz2", "ascii", "text", "txt", "hex"};

unsigned int nrrd_fits_memory(unsigned long long bytes)
{
    return ((unsigned long long)(size_t)bytes == bytes) ? 1u : 0u;
}

unsigned int nrrd_multiply(unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (NRRD_BYTES_LIMIT / left)))
    {
        return 0u;
    }
    *product = left * right;
    return 1u;
}

unsigned int nrrd_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
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

void nrrd_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes)
{
    for (unsigned long long start = 0ull; start < total; start += element_bytes)
    {
        for (unsigned int low = 0u; low < (element_bytes / 2u); low += 1u)
        {
            const unsigned int high = element_bytes - 1u - low;
            const unsigned char byte = bytes[start + low];
            bytes[start + low] = bytes[start + high];
            bytes[start + high] = byte;
        }
    }
}

static unsigned int nrrd_blank(char byte)
{
    return ((byte == ' ') || (byte == '\t')) ? 1u : 0u;
}

NrrdSpan nrrd_trim(NrrdSpan span)
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

unsigned int nrrd_equals(NrrdSpan span, const char *word)
{
    const size_t size = strlen(word);
    return ((span.length == size) && (memcmp(span.text, word, size) == 0)) ? 1u : 0u;
}

unsigned int nrrd_listed(NrrdSpan span, const char *const *words, size_t count)
{
    unsigned int found = 0u;
    for (size_t word = 0u; word < count; word += 1u)
    {
        found |= nrrd_equals(span, words[word]);
    }
    return found;
}

unsigned int nrrd_token(NrrdSpan *rest, NrrdSpan *token)
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

unsigned int nrrd_single(NrrdSpan value, unsigned long long *number)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    NrrdSpan after = {NULL, 0ull};
    return (nrrd_token(&rest, &token) && nrrd_unsigned(token, number) && !nrrd_token(&rest, &after)) ? 1u : 0u;
}

unsigned int nrrd_type(NrrdSpan value, NrrdFields *fields)
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

unsigned int nrrd_encoding(NrrdSpan value, NrrdFields *fields)
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
    fprintf(stderr, "nrrd: encoding %.*s is refused%s\n", (int)value.length, value.text, named ? "" : " as unknown");
    return 0u;
}

unsigned int nrrd_space(NrrdSpan value, NrrdFields *fields)
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

unsigned int nrrd_sizes(NrrdSpan value, NrrdFields *fields)
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

unsigned int nrrd_kinds(NrrdSpan value, NrrdFields *fields)
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
        fields->kinds[count] = nrrd_equals(token, "space")  ? NRRD_KIND_SPACE
                               : nrrd_equals(token, "time") ? NRRD_KIND_TIME
                                                            : NRRD_KIND_OTHER;
        count += 1u;
    }
    fields->kinds_count = count;
    return (count > 0u) ? 1u : 0u;
}

unsigned int nrrd_directions(NrrdSpan value, NrrdFields *fields)
{
    NrrdSpan rest = value;
    NrrdSpan token = {NULL, 0ull};
    unsigned int count = 0u;
    while (nrrd_token(&rest, &token))
    {
        const int vector =
            (token.length >= 2ull) && (token.text[0u] == '(') && (token.text[token.length - 1ull] == ')');
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
