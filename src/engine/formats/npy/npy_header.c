// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// npy_header.c: loading and the header's dictionary
#include "npy_internal.h"

unsigned long long npy_load(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = count; place > 0u; place -= 1u)
    {
        value = (value << 8u) | (unsigned long long)bytes[place - 1u];
    }
    return value;
}

unsigned int npy_fits_memory(unsigned long long bytes)
{
    return ((unsigned long long)(size_t)bytes == bytes) ? 1u : 0u;
}

unsigned int npy_multiply(unsigned long long left, unsigned long long right, unsigned long long *product)
{
    if ((left != 0ull) && (right > (NPY_BYTES_LIMIT / left)))
    {
        return 0u;
    }
    *product = left * right;
    return 1u;
}

unsigned int npy_file_fetch(const EngineIngestTools *tools, const char *path, unsigned long long offset,
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

unsigned int npy_source_fetch(const NpySource *source, unsigned long long offset, unsigned long long bytes,
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

void npy_swap(unsigned char *bytes, unsigned long long total, unsigned int element_bytes)
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

static void npy_space(NpyText *text)
{
    while ((text->at < text->length) && ((text->text[text->at] == ' ') || (text->text[text->at] == '\t') ||
                                         (text->text[text->at] == '\n') || (text->text[text->at] == '\r')))
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
    layout->extent.element_bytes = bytes;
    layout->extent.element_kind = unsigned_kind ? ENGINE_ELEMENT_UNSIGNED
                                  : signed_kind ? ENGINE_ELEMENT_SIGNED
                                                : ENGINE_ELEMENT_FLOAT;
    layout->big_endian = ((order == '>') && (bytes > 1u)) ? 1u : 0u;
    return 1u;
}

static unsigned int npy_extent(NpyText *text, EngineArrayExtent *extent)
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
        extent->sizes[rank] = value;
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
    extent->rank = rank;
    return (rank > 0u) ? 1u : 0u;
}

unsigned int npy_dictionary(const unsigned char *header, unsigned long long length, NpyLayout *layout)
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
            if (!npy_quoted(&text, &value_start, &value_end) ||
                !npy_description(header + value_start, value_end - value_start, layout))
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
            if (!npy_extent(&text, &layout->extent))
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
