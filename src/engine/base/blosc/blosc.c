// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "blosc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BLOSC_HEADER_BYTES 16ull
#define BLOSC_START_BYTES 4ull
#define BLOSC_FORMAT_VERSION 2u
#define BLOSC_FORMAT_BLOSC2_FIRST 3u
#define BLOSC_FORMAT_BLOSC2_LAST 6u
#define BLOSC_CODEC_FORMAT_VERSION 1u
#define BLOSC_FLAG_SHUFFLE 0x01u
#define BLOSC_FLAG_COPIED 0x02u
#define BLOSC_FLAG_BIT_SHUFFLE 0x04u
#define BLOSC_FLAG_RESERVED 0x08u
#define BLOSC_FLAG_UNSPLIT 0x10u
#define BLOSC_CODEC_SHIFT 5u
#define BLOSC_CODEC_COUNT 5u
#define BLOSC_SPLIT_ELEMENT_BYTES_MAX 16ull
#define BLOSC_SPLIT_ELEMENTS_MIN 128ull
#define BLOSC_BUFFER_MAX (2147483647ull - BLOSC_HEADER_BYTES)
#define BLOSC_BLOCK_MAX ((2147483647ull - (255ull * BLOSC_START_BYTES)) / 3ull)
#define BLOSC_BIT_GROUP 8ull
#define BLOSCLZ_FIELD_MASK 0x1Fu
#define BLOSCLZ_MATCH_SHIFT 5u
#define BLOSCLZ_LENGTH_EXTENDED 6ull
#define BLOSCLZ_LENGTH_MINIMUM 3ull
#define BLOSCLZ_EXTENSION_MORE 255u
#define BLOSCLZ_FAR_BASE 8191ull

typedef struct
{
    const unsigned char *chunk;
    unsigned long long chunk_bytes;
    unsigned char *out;
    unsigned long long total_bytes;
    unsigned long long block_bytes;
    unsigned long long element_bytes;
    unsigned int flags;
    unsigned long long streams_from;
    EngineBytesDecode stream_decode;
    unsigned char *shuffled;
} BloscChunk;

static const EngineCodec blosc_codec_slots[BLOSC_CODEC_COUNT] = {
    ENGINE_CODEC_BLOSCLZ, ENGINE_CODEC_LZ4, ENGINE_CODEC_SNAPPY, ENGINE_CODEC_ZLIB, ENGINE_CODEC_ZSTD};

static unsigned long long blosc_word(const unsigned char *at)
{
    return (unsigned long long)at[0u] | ((unsigned long long)at[1u] << 8u) | ((unsigned long long)at[2u] << 16u)
         | ((unsigned long long)at[3u] << 24u);
}

static unsigned long long blosc_transpose(unsigned long long word)
{
    const unsigned long long first = (word ^ (word >> 7u)) & 0x00AA00AA00AA00AAull;
    const unsigned long long paired = word ^ first ^ (first << 7u);
    const unsigned long long second = (paired ^ (paired >> 14u)) & 0x0000CCCC0000CCCCull;
    const unsigned long long quartered = paired ^ second ^ (second << 14u);
    const unsigned long long third = (quartered ^ (quartered >> 28u)) & 0x00000000F0F0F0F0ull;
    return quartered ^ third ^ (third << 28u);
}

static void blosc_byte_unshuffle(const unsigned char *shuffled, unsigned char *out, unsigned long long bytes,
                                 unsigned long long element_bytes)
{
    const unsigned long long elements = bytes / element_bytes;
    for (unsigned long long lane = 0ull; lane < element_bytes; lane += 1ull)
    {
        const unsigned char *const plane = shuffled + (lane * elements);
        for (unsigned long long element = 0ull; element < elements; element += 1ull)
        {
            out[(element * element_bytes) + lane] = plane[element];
        }
    }
    const unsigned long long whole = elements * element_bytes;
    memcpy(out + whole, shuffled + whole, (size_t)(bytes - whole));
}

static void blosc_bit_unshuffle(const unsigned char *shuffled, unsigned char *out, unsigned long long bytes,
                                unsigned long long element_bytes)
{
    const unsigned long long elements = bytes / element_bytes;
    if ((elements % BLOSC_BIT_GROUP) != 0ull)
    {
        memcpy(out, shuffled, (size_t)bytes);
        return;
    }
    const unsigned long long row_bytes = elements / BLOSC_BIT_GROUP;
    for (unsigned long long lane = 0ull; lane < element_bytes; lane += 1ull)
    {
        const unsigned char *const rows = shuffled + (lane * BLOSC_BIT_GROUP * row_bytes);
        for (unsigned long long group = 0ull; group < row_bytes; group += 1ull)
        {
            unsigned long long gathered = 0ull;
            for (unsigned long long bit = 0ull; bit < BLOSC_BIT_GROUP; bit += 1ull)
            {
                gathered |= (unsigned long long)rows[(bit * row_bytes) + group] << (bit * 8ull);
            }
            const unsigned long long transposed = blosc_transpose(gathered);
            unsigned char *const lanes = out + (group * BLOSC_BIT_GROUP * element_bytes) + lane;
            for (unsigned long long element = 0ull; element < BLOSC_BIT_GROUP; element += 1ull)
            {
                lanes[element * element_bytes] = (unsigned char)((transposed >> (element * 8ull)) & 0xFFull);
            }
        }
    }
    const unsigned long long whole = elements * element_bytes;
    memcpy(out + whole, shuffled + whole, (size_t)(bytes - whole));
}

static int blosc_stream(const BloscChunk *chunk, unsigned long long *at, unsigned char *target,
                        unsigned long long stream_bytes)
{
    if ((*at > chunk->chunk_bytes) || ((chunk->chunk_bytes - *at) < BLOSC_START_BYTES))
    {
        return 0;
    }
    const unsigned long long packed_bytes = blosc_word(chunk->chunk + *at);
    const unsigned long long packed_from = *at + BLOSC_START_BYTES;
    if (packed_bytes > (chunk->chunk_bytes - packed_from))
    {
        return 0;
    }
    *at = packed_from + packed_bytes;
    if (packed_bytes == stream_bytes)
    {
        memcpy(target, chunk->chunk + packed_from, (size_t)stream_bytes);
        return 1;
    }
    const EngineBytesRequest inner = {chunk->chunk + packed_from, packed_bytes, target, stream_bytes};
    return chunk->stream_decode(&inner) == (long long)stream_bytes;
}

static int blosc_block(const BloscChunk *chunk, unsigned long long block)
{
    const unsigned long long start = blosc_word(chunk->chunk + BLOSC_HEADER_BYTES + (block * BLOSC_START_BYTES));
    if ((start < chunk->streams_from) || (start >= chunk->chunk_bytes))
    {
        return 0;
    }
    const unsigned long long offset = block * chunk->block_bytes;
    const unsigned long long remaining = chunk->total_bytes - offset;
    const int partial = remaining < chunk->block_bytes;
    const unsigned long long bytes = partial ? remaining : chunk->block_bytes;
    const unsigned long long element_bytes = chunk->element_bytes;
    const int byte_shuffled = ((chunk->flags & BLOSC_FLAG_SHUFFLE) != 0u) && (element_bytes > 1ull);
    const int bit_shuffled = ((chunk->flags & BLOSC_FLAG_BIT_SHUFFLE) != 0u) && (bytes >= element_bytes);
    unsigned char *const destination = chunk->out + offset;
    unsigned char *const target = (byte_shuffled || bit_shuffled) ? chunk->shuffled : destination;
    const int split = ((chunk->flags & BLOSC_FLAG_UNSPLIT) == 0u) && (element_bytes <= BLOSC_SPLIT_ELEMENT_BYTES_MAX)
                   && ((bytes / element_bytes) >= BLOSC_SPLIT_ELEMENTS_MIN) && !partial;
    if (split && ((bytes % element_bytes) != 0ull))
    {
        return 0;
    }
    const unsigned long long streams = split ? element_bytes : 1ull;
    const unsigned long long stream_bytes = bytes / streams;
    unsigned long long at = start;
    for (unsigned long long stream = 0ull; stream < streams; stream += 1ull)
    {
        if (!blosc_stream(chunk, &at, target + (stream * stream_bytes), stream_bytes))
        {
            return 0;
        }
    }
    if (byte_shuffled)
    {
        blosc_byte_unshuffle(target, destination, bytes, element_bytes);
    }
    else if (bit_shuffled)
    {
        blosc_bit_unshuffle(target, destination, bytes, element_bytes);
    }
    return 1;
}

long long blosc_decode(const BloscDecodeRequest *request)
{
    if (request->bytes.in_bytes < BLOSC_HEADER_BYTES)
    {
        return ENGINE_BYTES_REFUSED;
    }
    const EngineBytesRequest *const bytes = &request->bytes;
    const unsigned char *const header = bytes->in;
    const unsigned int version = header[0u];
    if ((version >= BLOSC_FORMAT_BLOSC2_FIRST) && (version <= BLOSC_FORMAT_BLOSC2_LAST))
    {
        fprintf(stderr, "blosc: refused a Blosc2 chunk (format version %u); only Blosc1 chunks, format version 2, are decoded\n",
                version);
        return ENGINE_BYTES_REFUSED;
    }
    const unsigned int flags = header[2u];
    const unsigned long long element_bytes = header[3u];
    const unsigned long long total_bytes = blosc_word(header + 4u);
    const unsigned long long block_bytes = blosc_word(header + 8u);
    const unsigned long long chunk_bytes = blosc_word(header + 12u);
    const unsigned int both_shuffles = BLOSC_FLAG_SHUFFLE | BLOSC_FLAG_BIT_SHUFFLE;
    if ((version != BLOSC_FORMAT_VERSION) || (chunk_bytes != bytes->in_bytes) || ((flags & BLOSC_FLAG_RESERVED) != 0u)
        || ((flags & both_shuffles) == both_shuffles) || (element_bytes == 0ull) || (total_bytes > BLOSC_BUFFER_MAX))
    {
        return ENGINE_BYTES_REFUSED;
    }
    if (total_bytes == 0ull)
    {
        return (chunk_bytes == BLOSC_HEADER_BYTES) ? 0ll : ENGINE_BYTES_REFUSED;
    }
    if ((total_bytes > bytes->out_room) || (block_bytes == 0ull) || (block_bytes > total_bytes)
        || (block_bytes > BLOSC_BLOCK_MAX))
    {
        return ENGINE_BYTES_REFUSED;
    }
    if ((flags & BLOSC_FLAG_COPIED) != 0u)
    {
        if (chunk_bytes != (total_bytes + BLOSC_HEADER_BYTES))
        {
            return ENGINE_BYTES_REFUSED;
        }
        memcpy(bytes->out, header + BLOSC_HEADER_BYTES, (size_t)total_bytes);
        return (long long)total_bytes;
    }
    const unsigned int codec = flags >> BLOSC_CODEC_SHIFT;
    if ((header[1u] != BLOSC_CODEC_FORMAT_VERSION) || (codec >= BLOSC_CODEC_COUNT))
    {
        return ENGINE_BYTES_REFUSED;
    }
    const EngineBytesDecode stream_decode = request->decode[blosc_codec_slots[codec]];
    const unsigned long long block_count = (total_bytes + block_bytes - 1ull) / block_bytes;
    if ((stream_decode == NULL) || (block_count > ((chunk_bytes - BLOSC_HEADER_BYTES) / BLOSC_START_BYTES)))
    {
        return ENGINE_BYTES_REFUSED;
    }
    const int shuffled = (flags & both_shuffles) != 0u;
    unsigned char *const scratch = shuffled ? (unsigned char *)malloc((size_t)block_bytes) : NULL;
    if (shuffled && (scratch == NULL))
    {
        return ENGINE_BYTES_REFUSED;
    }
    const BloscChunk chunk = {header, chunk_bytes, bytes->out, total_bytes, block_bytes, element_bytes, flags,
                              BLOSC_HEADER_BYTES + (block_count * BLOSC_START_BYTES), stream_decode, scratch};
    int decoded = 1;
    for (unsigned long long block = 0ull; decoded && (block < block_count); block += 1ull)
    {
        decoded = blosc_block(&chunk, block);
    }
    free(scratch);
    if (!decoded)
    {
        memset(bytes->out, 0, (size_t)total_bytes);
        return ENGINE_BYTES_REFUSED;
    }
    return (long long)total_bytes;
}

static void blosc_match_copy(unsigned char *out, unsigned long long written, unsigned long long distance,
                             unsigned long long length)
{
    unsigned char *const to = out + written;
    const unsigned char *const from = to - distance;
    if (distance >= length)
    {
        memcpy(to, from, (size_t)length);
        return;
    }
    for (unsigned long long step = 0ull; step < length; step += 1ull)
    {
        to[step] = from[step];
    }
}

long long blosclz_decode(const EngineBytesRequest *request)
{
    const unsigned char *const in = request->in;
    const unsigned long long in_bytes = request->in_bytes;
    unsigned char *const out = request->out;
    const unsigned long long room = request->out_room;
    if (in_bytes == 0ull)
    {
        return 0ll;
    }
    unsigned long long at = 1ull;
    unsigned long long written = 0ull;
    unsigned int control = in[0u] & BLOSCLZ_FIELD_MASK;
    for (;;)
    {
        if (control <= BLOSCLZ_FIELD_MASK)
        {
            const unsigned long long literal = (unsigned long long)control + 1ull;
            if ((literal > (room - written)) || (literal > (in_bytes - at)))
            {
                return ENGINE_BYTES_REFUSED;
            }
            memcpy(out + written, in + at, (size_t)literal);
            written += literal;
            at += literal;
            if (at >= in_bytes)
            {
                return (long long)written;
            }
            control = in[at];
            at += 1ull;
            continue;
        }
        unsigned long long length = (unsigned long long)(control >> BLOSCLZ_MATCH_SHIFT) - 1ull;
        const unsigned int near_high = control & BLOSCLZ_FIELD_MASK;
        if (length == BLOSCLZ_LENGTH_EXTENDED)
        {
            unsigned int extension = BLOSCLZ_EXTENSION_MORE;
            while (extension == BLOSCLZ_EXTENSION_MORE)
            {
                if ((at + 1ull) >= in_bytes)
                {
                    return ENGINE_BYTES_REFUSED;
                }
                extension = in[at];
                at += 1ull;
                length += extension;
            }
        }
        else if ((at + 1ull) >= in_bytes)
        {
            return ENGINE_BYTES_REFUSED;
        }
        const unsigned int code = in[at];
        at += 1ull;
        length += BLOSCLZ_LENGTH_MINIMUM;
        unsigned long long distance = ((unsigned long long)near_high << 8u) + code + 1ull;
        if ((code == BLOSCLZ_EXTENSION_MORE) && (near_high == BLOSCLZ_FIELD_MASK))
        {
            if ((at + 1ull) >= in_bytes)
            {
                return ENGINE_BYTES_REFUSED;
            }
            distance = ((unsigned long long)in[at] << 8u) + (unsigned long long)in[at + 1ull] + BLOSCLZ_FAR_BASE + 1ull;
            at += 2ull;
        }
        if ((length > (room - written)) || (distance > written) || (at >= in_bytes))
        {
            return ENGINE_BYTES_REFUSED;
        }
        control = in[at];
        at += 1ull;
        blosc_match_copy(out, written, distance, length);
        written += length;
    }
}
