// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// inflate_huffman.c: the bit reader and Huffman tables
#include "inflate_internal.h"

static const unsigned short inflate_length_base[29u] = {3u,  4u,  5u,  6u,   7u,   8u,   9u,   10u,  11u, 13u,
                                                        15u, 17u, 19u, 23u,  27u,  31u,  35u,  43u,  51u, 59u,
                                                        67u, 83u, 99u, 115u, 131u, 163u, 195u, 227u, 258u};

static const unsigned char inflate_length_extra[29u] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u, 1u, 1u, 1u, 2u, 2u, 2u,
                                                        2u, 3u, 3u, 3u, 3u, 4u, 4u, 4u, 4u, 5u, 5u, 5u, 5u, 0u};

static const unsigned short inflate_distance_base[30u] = {
    1u,   2u,   3u,   4u,   5u,   7u,    9u,    13u,   17u,   25u,   33u,   49u,   65u,    97u,    129u,
    193u, 257u, 385u, 513u, 769u, 1025u, 1537u, 2049u, 3073u, 4097u, 6145u, 8193u, 12289u, 16385u, 24577u};

static const unsigned char inflate_distance_extra[30u] = {0u, 0u, 0u,  0u,  1u,  1u,  2u,  2u,  3u,  3u,
                                                          4u, 4u, 5u,  5u,  6u,  6u,  7u,  7u,  8u,  8u,
                                                          9u, 9u, 10u, 10u, 11u, 11u, 12u, 12u, 13u, 13u};

static void inflate_refill(InflateStream *stream)
{
    while ((stream->bit_count <= 56u) && (stream->at < stream->in_bytes))
    {
        stream->bits |= (unsigned long long)stream->in[stream->at] << stream->bit_count;
        stream->at += 1ull;
        stream->bit_count += 8u;
    }
}

int inflate_take(InflateStream *stream, unsigned int count, unsigned int *value)
{
    if (stream->bit_count < count)
    {
        inflate_refill(stream);
    }
    if (stream->bit_count < count)
    {
        return 0;
    }
    *value = (unsigned int)(stream->bits & ((1ull << count) - 1ull));
    stream->bits >>= count;
    stream->bit_count -= count;
    return 1;
}

void inflate_align(InflateStream *stream)
{
    const unsigned int partial = stream->bit_count & 7u;
    stream->bits >>= partial;
    stream->bit_count -= partial;
    stream->at -= (unsigned long long)(stream->bit_count / 8u);
    stream->bits = 0ull;
    stream->bit_count = 0u;
}

int inflate_build(InflateHuffman *huffman, const unsigned char *lengths, unsigned int count, int single_permitted)
{
    memset(huffman, 0u, sizeof(*huffman));
    unsigned int used = 0u;
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        if (lengths[symbol] != 0u)
        {
            huffman->counts[lengths[symbol]] += 1u;
            used += 1u;
        }
    }
    long long left = 1ll;
    for (unsigned int length = 1u; length <= INFLATE_MAXIMUM_BITS; length += 1u)
    {
        left = (left * 2ll) - (long long)huffman->counts[length];
        if (left < 0ll)
        {
            return 0;
        }
    }
    const int single = single_permitted && (used == 1u) && (huffman->counts[1u] == 1u);
    if ((left > 0ll) && (used != 0u) && !single)
    {
        return 0;
    }
    unsigned int offsets[INFLATE_MAXIMUM_BITS + 2u];
    unsigned int next_code[INFLATE_MAXIMUM_BITS + 1u];
    offsets[1u] = 0u;
    next_code[0u] = 0u;
    unsigned int code = 0u;
    for (unsigned int length = 1u; length <= INFLATE_MAXIMUM_BITS; length += 1u)
    {
        offsets[length + 1u] = offsets[length] + huffman->counts[length];
        code = (code + ((length > 1u) ? huffman->counts[length - 1u] : 0u)) << 1u;
        next_code[length] = code;
    }
    for (unsigned int symbol = 0u; symbol < count; symbol += 1u)
    {
        const unsigned int length = lengths[symbol];
        if (length == 0u)
        {
            continue;
        }
        huffman->symbols[offsets[length]] = (unsigned short)symbol;
        offsets[length] += 1u;
        const unsigned int canonical = next_code[length];
        next_code[length] += 1u;
        if (length > INFLATE_FAST_BITS)
        {
            continue;
        }
        unsigned int reversed = 0u;
        for (unsigned int bit = 0u; bit < length; bit += 1u)
        {
            reversed |= ((canonical >> bit) & 1u) << (length - 1u - bit);
        }
        const unsigned short entry = (unsigned short)((symbol << 4u) | length);
        for (unsigned int fill = reversed; fill < INFLATE_FAST_SIZE; fill += (1u << length))
        {
            huffman->fast[fill] = entry;
        }
    }
    return 1;
}

int inflate_symbol(InflateStream *stream, const InflateHuffman *huffman, unsigned int *symbol)
{
    if (stream->bit_count < INFLATE_MAXIMUM_BITS)
    {
        inflate_refill(stream);
    }
    const unsigned int entry = huffman->fast[stream->bits & (unsigned long long)(INFLATE_FAST_SIZE - 1u)];
    const unsigned int entry_length = entry & 15u;
    if ((entry_length != 0u) && (entry_length <= stream->bit_count))
    {
        *symbol = entry >> 4u;
        stream->bits >>= entry_length;
        stream->bit_count -= entry_length;
        return 1;
    }
    unsigned int code = 0u;
    unsigned int first = 0u;
    unsigned int passed = 0u;
    for (unsigned int length = 1u; (length <= INFLATE_MAXIMUM_BITS) && (length <= stream->bit_count); length += 1u)
    {
        code |= (unsigned int)((stream->bits >> (length - 1u)) & 1ull);
        const unsigned int count = huffman->counts[length];
        if (code < (first + count))
        {
            *symbol = huffman->symbols[passed + (code - first)];
            stream->bits >>= length;
            stream->bit_count -= length;
            return 1;
        }
        passed += count;
        first = (first + count) << 1u;
        code <<= 1u;
    }
    return 0;
}

int inflate_codes(InflateStream *stream, const InflateHuffman *literals, const InflateHuffman *distances)
{
    for (;;)
    {
        unsigned int symbol = 0u;
        if (!inflate_symbol(stream, literals, &symbol))
        {
            return 0;
        }
        if (symbol < INFLATE_END_OF_BLOCK)
        {
            if (stream->written == stream->out_capacity)
            {
                return 0;
            }
            stream->out[stream->written] = (unsigned char)symbol;
            stream->written += 1ull;
            continue;
        }
        if (symbol == INFLATE_END_OF_BLOCK)
        {
            return 1;
        }
        if (symbol >= INFLATE_LITERAL_LIMIT)
        {
            return 0;
        }
        const unsigned int length_slot = symbol - (INFLATE_END_OF_BLOCK + 1u);
        unsigned int length_extra = 0u;
        if (!inflate_take(stream, inflate_length_extra[length_slot], &length_extra))
        {
            return 0;
        }
        const unsigned long long length = (unsigned long long)inflate_length_base[length_slot] + length_extra;
        unsigned int distance_slot = 0u;
        if (!inflate_symbol(stream, distances, &distance_slot) || (distance_slot >= INFLATE_DISTANCE_LIMIT))
        {
            return 0;
        }
        unsigned int distance_extra = 0u;
        if (!inflate_take(stream, inflate_distance_extra[distance_slot], &distance_extra))
        {
            return 0;
        }
        const unsigned long long distance = (unsigned long long)inflate_distance_base[distance_slot] + distance_extra;
        if ((distance > stream->written) || (length > (stream->out_capacity - stream->written)))
        {
            return 0;
        }
        unsigned char *const target = stream->out + stream->written;
        const unsigned char *const source = target - distance;
        if (distance >= length)
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
        stream->written += length;
    }
}
