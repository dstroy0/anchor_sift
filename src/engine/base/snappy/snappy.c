// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "snappy.h"

#include <string.h>

#define SNAPPY_PREAMBLE_BYTES 5u
#define SNAPPY_LITERAL 0u
#define SNAPPY_COPY_ONE 1u
#define SNAPPY_COPY_TWO 2u
#define SNAPPY_LONG_LITERAL 60u

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned long long at;
    unsigned char *out;
    unsigned long long expected;
    unsigned long long written;
} SnappyWalk;

static int snappy_preamble(SnappyWalk *walk)
{
    unsigned long long value = 0ull;
    for (unsigned int byte_count = 0u; byte_count < SNAPPY_PREAMBLE_BYTES; byte_count += 1u)
    {
        if (walk->at == walk->in_bytes)
        {
            return 0;
        }
        const unsigned int byte = walk->in[walk->at];
        walk->at += 1ull;
        value |= (unsigned long long)(byte & 0x7Fu) << (7u * byte_count);
        if ((byte & 0x80u) == 0u)
        {
            walk->expected = value;
            return value <= 0xFFFFFFFFull;
        }
    }
    return 0;
}

static unsigned long long snappy_little_endian(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int byte = 0u; byte < count; byte += 1u)
    {
        value |= (unsigned long long)bytes[byte] << (8u * byte);
    }
    return value;
}

static int snappy_literal(SnappyWalk *walk, unsigned int tag)
{
    const unsigned int short_length = tag >> 2u;
    unsigned long long length = (unsigned long long)short_length + 1ull;
    if (short_length >= SNAPPY_LONG_LITERAL)
    {
        const unsigned int length_bytes = short_length - (SNAPPY_LONG_LITERAL - 1u);
        if ((walk->in_bytes - walk->at) < length_bytes)
        {
            return 0;
        }
        length = snappy_little_endian(walk->in + walk->at, length_bytes) + 1ull;
        walk->at += length_bytes;
    }
    if ((length > (walk->in_bytes - walk->at)) || (length > (walk->expected - walk->written)))
    {
        return 0;
    }
    memcpy(walk->out + walk->written, walk->in + walk->at, (size_t)length);
    walk->at += length;
    walk->written += length;
    return 1;
}

static int snappy_copy(SnappyWalk *walk, unsigned int tag)
{
    const unsigned int kind = tag & 3u;
    const unsigned int offset_bytes = (kind == SNAPPY_COPY_ONE) ? 1u : ((kind == SNAPPY_COPY_TWO) ? 2u : 4u);
    if ((walk->in_bytes - walk->at) < offset_bytes)
    {
        return 0;
    }
    const unsigned long long stored = snappy_little_endian(walk->in + walk->at, offset_bytes);
    walk->at += offset_bytes;
    const unsigned long long offset = (kind == SNAPPY_COPY_ONE) ? (((unsigned long long)(tag >> 5u) << 8u) | stored) : stored;
    const unsigned long long length = (kind == SNAPPY_COPY_ONE) ? (4ull + ((tag >> 2u) & 7u)) : ((tag >> 2u) + 1ull);
    if ((offset == 0ull) || (offset > walk->written) || (length > (walk->expected - walk->written)))
    {
        return 0;
    }
    unsigned char *const target = walk->out + walk->written;
    const unsigned char *const source = target - offset;
    if (offset >= length)
    {
        memcpy(target, source, (size_t)length);
    }
    else
    {
        for (unsigned long long copied = 0ull; copied < length; copied += 1ull)
        {
            target[copied] = source[copied];
        }
    }
    walk->written += length;
    return 1;
}

long long snappy_decode(const EngineBytesRequest *request)
{
    SnappyWalk walk = {request->in, request->in_bytes, 0ull, request->out, 0ull, 0ull};
    if (!snappy_preamble(&walk) || (walk.expected > request->out_room))
    {
        return ENGINE_BYTES_REFUSED;
    }
    int good = 1;
    while (good && (walk.at < walk.in_bytes))
    {
        const unsigned int tag = walk.in[walk.at];
        walk.at += 1ull;
        good = ((tag & 3u) == SNAPPY_LITERAL) ? snappy_literal(&walk, tag) : snappy_copy(&walk, tag);
    }
    if (!good || (walk.written != walk.expected))
    {
        if (walk.written != 0ull)
        {
            memset(request->out, 0, (size_t)walk.written);
        }
        return ENGINE_BYTES_REFUSED;
    }
    return (long long)walk.written;
}
