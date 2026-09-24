// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "zstd.h"

#include <stdlib.h>
#include <string.h>

#define ZSTD_FRAME_MAGIC 0xFD2FB528ull
#define ZSTD_SKIPPABLE_MAGIC 0x184D2A50ull
#define ZSTD_SKIPPABLE_MASK 0xFFFFFFF0ull
#define ZSTD_BLOCK_MAXIMUM 131072ull
#define ZSTD_RESULT_MAXIMUM 0x7FFFFFFFFFFFFFFFull
#define ZSTD_REPEATS 3u
#define ZSTD_HUFFMAN_BITS_MAXIMUM 11u
#define ZSTD_HUFFMAN_CELLS 2048u
#define ZSTD_HUFFMAN_WEIGHTS 256u
#define ZSTD_HUFFMAN_DESCRIBED_MAXIMUM 255u
#define ZSTD_WEIGHT_ACCURACY_MAXIMUM 6u
#define ZSTD_WEIGHT_SYMBOLS 12u
#define ZSTD_FSE_ACCURACY_MAXIMUM 9u
#define ZSTD_FSE_CELLS 512u
#define ZSTD_FSE_SYMBOLS 64u
#define ZSTD_LITERAL_LENGTH_SYMBOLS 36u
#define ZSTD_MATCH_LENGTH_SYMBOLS 53u
#define ZSTD_OFFSET_SYMBOLS 32u
#define ZSTD_OFFSET_PREDEFINED_SYMBOLS 29u
#define ZSTD_XXH64_PRIME_ONE 0x9E3779B185EBCA87ull
#define ZSTD_XXH64_PRIME_TWO 0xC2B2AE3D27D4EB4Full
#define ZSTD_XXH64_PRIME_THREE 0x165667B19E3779F9ull
#define ZSTD_XXH64_PRIME_FOUR 0x85EBCA77C2B2AE63ull
#define ZSTD_XXH64_PRIME_FIVE 0x27D4EB2F165667C5ull

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
} ZstdSpan;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    unsigned long long position;
} ZstdForwardStream;

typedef struct
{
    const unsigned char *bytes;
    unsigned long long length;
    long long position;
} ZstdBackwardStream;

typedef struct
{
    unsigned short baseline;
    unsigned char symbol;
    unsigned char bits;
} ZstdFseCell;

typedef struct
{
    ZstdFseCell cells[ZSTD_FSE_CELLS];
    unsigned int accuracy;
    int ready;
} ZstdFseTable;

typedef struct
{
    const long *predefined;
    unsigned int predefined_symbols;
    unsigned int predefined_accuracy;
    unsigned int symbols;
    unsigned int accuracy;
} ZstdTableKind;

typedef struct
{
    unsigned char symbol;
    unsigned char bits;
} ZstdHuffmanCell;

typedef struct
{
    unsigned char literal_buffer[ZSTD_BLOCK_MAXIMUM];
    ZstdHuffmanCell huffman[ZSTD_HUFFMAN_CELLS];
    unsigned int huffman_bits;
    int huffman_ready;
    ZstdFseTable literal_lengths;
    ZstdFseTable match_lengths;
    ZstdFseTable offsets;
    unsigned long long repeat[ZSTD_REPEATS];
    const unsigned char *literals;
    unsigned long long literal_count;
    unsigned long long literals_used;
    unsigned char *out;
    unsigned long long out_room;
    unsigned long long written;
    unsigned long long frame_start;
    unsigned long long block_start;
    unsigned long long window;
    unsigned long long block_maximum;
} ZstdDecoder;

static const long zstd_literal_length_predefined[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    4L, 3L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L, 1L, 2L, 2L,
    2L, 2L, 2L, 2L, 2L, 2L, 2L, 3L, 2L, 1L, 1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L};

static const long zstd_match_length_predefined[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    1L, 4L, 3L, 2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L,
    1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L,
    1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L, -1L, -1L, -1L};

static const long zstd_offset_predefined[ZSTD_OFFSET_PREDEFINED_SYMBOLS] = {
    1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 1L, 1L, 1L, 1L, 1L, 1L,
    1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L, -1L};

static const unsigned int zstd_literal_length_baselines[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    0u,   1u,   2u,   3u,   4u,    5u,    6u,    7u,    8u,     9u,   10u,  11u,
    12u,  13u,  14u,  15u,  16u,   18u,   20u,   22u,   24u,    28u,  32u,  40u,
    48u,  64u,  128u, 256u, 512u,  1024u, 2048u, 4096u, 8192u,  16384u, 32768u, 65536u};

static const unsigned int zstd_literal_length_extra[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,  0u,  0u,  0u,  0u,  0u,  1u,  1u,
    1u, 1u, 2u, 2u, 3u, 3u, 4u, 6u, 7u, 8u, 9u, 10u, 11u, 12u, 13u, 14u, 15u, 16u};

static const unsigned int zstd_match_length_baselines[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    3u,   4u,   5u,   6u,    7u,    8u,    9u,    10u,   11u,   12u,  13u,
    14u,  15u,  16u,  17u,   18u,   19u,   20u,   21u,   22u,   23u,  24u,
    25u,  26u,  27u,  28u,   29u,   30u,   31u,   32u,   33u,   34u,  35u,
    37u,  39u,  41u,  43u,   47u,   51u,   59u,   67u,   83u,   99u,  131u,
    259u, 515u, 1027u, 2051u, 4099u, 8195u, 16387u, 32771u, 65539u};

static const unsigned int zstd_match_length_extra[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u, 1u, 1u, 1u,
    2u, 2u, 3u, 3u, 4u, 4u, 5u, 7u, 8u, 9u, 10u, 11u, 12u, 13u, 14u, 15u, 16u};

static const ZstdTableKind zstd_literal_length_kind = {zstd_literal_length_predefined, ZSTD_LITERAL_LENGTH_SYMBOLS, 6u,
                                                       ZSTD_LITERAL_LENGTH_SYMBOLS, 9u};

static const ZstdTableKind zstd_match_length_kind = {zstd_match_length_predefined, ZSTD_MATCH_LENGTH_SYMBOLS, 6u,
                                                     ZSTD_MATCH_LENGTH_SYMBOLS, 9u};

static const ZstdTableKind zstd_offset_kind = {zstd_offset_predefined, ZSTD_OFFSET_PREDEFINED_SYMBOLS, 5u,
                                               ZSTD_OFFSET_SYMBOLS, 8u};

static const ZstdTableKind zstd_weight_kind = {NULL, 0u, 0u, ZSTD_WEIGHT_SYMBOLS, ZSTD_WEIGHT_ACCURACY_MAXIMUM};

static const unsigned int zstd_dictionary_widths[4u] = {0u, 1u, 2u, 4u};

static const unsigned int zstd_content_widths[4u] = {0u, 2u, 4u, 8u};

static unsigned long long zstd_little_endian(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        value |= (unsigned long long)bytes[place] << (8u * place);
    }
    return value;
}

static void zstd_advance(ZstdSpan *span, unsigned long long count)
{
    span->bytes += count;
    span->length -= count;
}

static unsigned int zstd_high_bit(unsigned long long value)
{
    unsigned int bit = 0u;
    while ((value >> bit) > 1ull)
    {
        bit += 1u;
    }
    return bit;
}

static unsigned long long zstd_bits_at(const unsigned char *bytes, unsigned long long length, unsigned long long first,
                                       unsigned int count)
{
    const unsigned long long byte = first >> 3u;
    const unsigned int skip = (unsigned int)(first & 7ull);
    unsigned long long word = 0ull;
    if ((byte < length) && ((length - byte) >= 8ull))
    {
        const unsigned char *const lane = &bytes[byte];
        word = (unsigned long long)lane[0u] | ((unsigned long long)lane[1u] << 8u) | ((unsigned long long)lane[2u] << 16u)
             | ((unsigned long long)lane[3u] << 24u) | ((unsigned long long)lane[4u] << 32u)
             | ((unsigned long long)lane[5u] << 40u) | ((unsigned long long)lane[6u] << 48u)
             | ((unsigned long long)lane[7u] << 56u);
    }
    else
    {
        for (unsigned int place = 0u; (place < 8u) && ((byte + place) < length); place += 1u)
        {
            word |= (unsigned long long)bytes[byte + place] << (8u * place);
        }
    }
    const unsigned long long mask = (1ull << count) - 1ull;
    return (word >> skip) & mask;
}

static unsigned long long zstd_forward_peek(const ZstdForwardStream *stream, unsigned int count)
{
    return zstd_bits_at(stream->bytes, stream->length, stream->position, count);
}

static int zstd_forward_skip(ZstdForwardStream *stream, unsigned int count)
{
    stream->position += count;
    const unsigned long long whole = stream->position >> 3u;
    const unsigned long long partial = ((stream->position & 7ull) != 0ull) ? 1ull : 0ull;
    return (whole + partial) <= stream->length;
}

static int zstd_backward_open(ZstdBackwardStream *stream, const unsigned char *bytes, unsigned long long length)
{
    stream->bytes = bytes;
    stream->length = length;
    stream->position = 0LL;
    if ((length == 0ull) || (length > ZSTD_BLOCK_MAXIMUM) || (bytes[length - 1ull] == 0u))
    {
        return 0;
    }
    const unsigned int marker = zstd_high_bit(bytes[length - 1ull]);
    stream->position = (long long)(((length - 1ull) * 8ull) + marker);
    return 1;
}

static unsigned long long zstd_backward_peek(const ZstdBackwardStream *stream, unsigned int count)
{
    if ((count == 0u) || (stream->position <= 0LL))
    {
        return 0ull;
    }
    const long long low = stream->position - (long long)count;
    if (low >= 0LL)
    {
        return zstd_bits_at(stream->bytes, stream->length, (unsigned long long)low, count);
    }
    const unsigned int missing = (unsigned int)(0LL - low);
    return zstd_bits_at(stream->bytes, stream->length, 0ull, count - missing) << missing;
}

static unsigned long long zstd_backward_read(ZstdBackwardStream *stream, unsigned int count)
{
    const unsigned long long value = zstd_backward_peek(stream, count);
    stream->position -= (long long)count;
    return value;
}

static int zstd_fse_describe(ZstdSpan *input, const ZstdTableKind *kind, long *counts, unsigned int *accuracy)
{
    ZstdForwardStream stream = {input->bytes, input->length, 0ull};
    const unsigned int found = (unsigned int)zstd_forward_peek(&stream, 4u) + 5u;
    int good = zstd_forward_skip(&stream, 4u) && (found <= kind->accuracy);
    for (unsigned int symbol = 0u; symbol < kind->symbols; symbol += 1u)
    {
        counts[symbol] = 0L;
    }
    long remaining = (1L << found) + 1L;
    long threshold = 1L << found;
    unsigned int width = found + 1u;
    unsigned int symbol = 0u;
    int previous_zero = 0;
    int reading = good;
    while (reading)
    {
        if (previous_zero)
        {
            unsigned int flag = (unsigned int)zstd_forward_peek(&stream, 2u);
            good = zstd_forward_skip(&stream, 2u);
            while (good && (flag == 3u))
            {
                symbol += 3u;
                flag = (unsigned int)zstd_forward_peek(&stream, 2u);
                good = zstd_forward_skip(&stream, 2u) && (symbol < kind->symbols);
            }
            symbol += flag;
            good = good && (symbol < kind->symbols);
            if (!good)
            {
                break;
            }
        }
        const long most = ((2L * threshold) - 1L) - remaining;
        const long peeked = (long)zstd_forward_peek(&stream, width);
        const long low = peeked & (threshold - 1L);
        const long full = peeked & ((2L * threshold) - 1L);
        const int short_form = (low < most);
        const long value = short_form ? low : ((full >= threshold) ? (full - most) : full);
        good = zstd_forward_skip(&stream, short_form ? (width - 1u) : width);
        const long count = value - 1L;
        remaining -= (count >= 0L) ? count : 1L;
        counts[symbol] = count;
        symbol += 1u;
        previous_zero = (count == 0L);
        if ((remaining < threshold) && (remaining > 1L))
        {
            width = zstd_high_bit((unsigned long long)remaining) + 1u;
            threshold = 1L << (width - 1u);
        }
        reading = good && (remaining > 1L) && (symbol < kind->symbols);
    }
    const unsigned long long consumed = (stream.position + 7ull) >> 3u;
    good = good && (remaining == 1L) && (consumed <= input->length);
    if (good)
    {
        zstd_advance(input, consumed);
    }
    *accuracy = found;
    return good;
}

static int zstd_fse_build(ZstdFseTable *table, const long *counts, unsigned int symbols, unsigned int accuracy)
{
    table->ready = 0;
    const unsigned long size = 1ul << accuracy;
    unsigned long total = 0ul;
    for (unsigned int symbol = 0u; symbol < symbols; symbol += 1u)
    {
        total += (counts[symbol] < 0L) ? 1ul : (unsigned long)counts[symbol];
    }
    if ((accuracy > ZSTD_FSE_ACCURACY_MAXIMUM) || (symbols > ZSTD_FSE_SYMBOLS) || (total != size))
    {
        return 0;
    }
    unsigned long next[ZSTD_FSE_SYMBOLS];
    long high = (long)size - 1L;
    for (unsigned int symbol = 0u; symbol < symbols; symbol += 1u)
    {
        next[symbol] = (counts[symbol] < 0L) ? 1ul : (unsigned long)counts[symbol];
        if (counts[symbol] < 0L)
        {
            table->cells[high].symbol = (unsigned char)symbol;
            high -= 1L;
        }
    }
    const unsigned long step = (size >> 1u) + (size >> 3u) + 3ul;
    const unsigned long mask = size - 1ul;
    unsigned long position = 0ul;
    for (unsigned int symbol = 0u; symbol < symbols; symbol += 1u)
    {
        for (long copy = 0L; copy < counts[symbol]; copy += 1L)
        {
            table->cells[position].symbol = (unsigned char)symbol;
            position = (position + step) & mask;
            while ((long)position > high)
            {
                position = (position + step) & mask;
            }
        }
    }
    if (position != 0ul)
    {
        return 0;
    }
    for (unsigned long cell = 0ul; cell < size; cell += 1ul)
    {
        const unsigned int symbol = table->cells[cell].symbol;
        const unsigned long state = next[symbol];
        next[symbol] += 1ul;
        const unsigned int bits = accuracy - zstd_high_bit(state);
        table->cells[cell].bits = (unsigned char)bits;
        table->cells[cell].baseline = (unsigned short)((state << bits) - size);
    }
    table->accuracy = accuracy;
    table->ready = 1;
    return 1;
}

static int zstd_weights_decode(const ZstdFseTable *table, const ZstdSpan *payload, unsigned char *weights,
                               unsigned int *described)
{
    ZstdBackwardStream stream;
    if (!zstd_backward_open(&stream, payload->bytes, payload->length))
    {
        return 0;
    }
    unsigned int states[2u];
    states[0u] = (unsigned int)zstd_backward_read(&stream, table->accuracy);
    states[1u] = (unsigned int)zstd_backward_read(&stream, table->accuracy);
    unsigned int count = 0u;
    unsigned int turn = 0u;
    int decoding = 1;
    while (decoding)
    {
        if (count >= ZSTD_HUFFMAN_DESCRIBED_MAXIMUM)
        {
            return 0;
        }
        const ZstdFseCell cell = table->cells[states[turn]];
        weights[count] = cell.symbol;
        count += 1u;
        states[turn] = cell.baseline + (unsigned int)zstd_backward_read(&stream, cell.bits);
        if (stream.position < 0LL)
        {
            if (count >= ZSTD_HUFFMAN_DESCRIBED_MAXIMUM)
            {
                return 0;
            }
            weights[count] = table->cells[states[1u - turn]].symbol;
            count += 1u;
            decoding = 0;
        }
        turn = 1u - turn;
    }
    *described = count;
    return 1;
}

static int zstd_huffman_describe(ZstdDecoder *decoder, ZstdSpan *input)
{
    if (input->length == 0ull)
    {
        return 0;
    }
    unsigned char weights[ZSTD_HUFFMAN_WEIGHTS];
    unsigned int described = 0u;
    const unsigned int header = input->bytes[0u];
    zstd_advance(input, 1ull);
    if (header >= 128u)
    {
        described = header - 127u;
        const unsigned long long packed = (described + 1u) / 2u;
        if (packed > input->length)
        {
            return 0;
        }
        for (unsigned int symbol = 0u; symbol < described; symbol += 1u)
        {
            const unsigned int byte = input->bytes[symbol / 2u];
            weights[symbol] = (unsigned char)(((symbol & 1u) != 0u) ? (byte & 15u) : (byte >> 4u));
        }
        zstd_advance(input, packed);
    }
    else
    {
        if ((header == 0u) || (header > input->length))
        {
            return 0;
        }
        ZstdSpan payload = {input->bytes, header};
        long counts[ZSTD_WEIGHT_SYMBOLS];
        unsigned int accuracy = 0u;
        ZstdFseTable table;
        if (!zstd_fse_describe(&payload, &zstd_weight_kind, counts, &accuracy)
            || !zstd_fse_build(&table, counts, ZSTD_WEIGHT_SYMBOLS, accuracy)
            || !zstd_weights_decode(&table, &payload, weights, &described))
        {
            return 0;
        }
        zstd_advance(input, header);
    }
    unsigned int ranks[ZSTD_HUFFMAN_BITS_MAXIMUM + 1u];
    for (unsigned int weight = 0u; weight <= ZSTD_HUFFMAN_BITS_MAXIMUM; weight += 1u)
    {
        ranks[weight] = 0u;
    }
    unsigned long total = 0ul;
    for (unsigned int symbol = 0u; symbol < described; symbol += 1u)
    {
        const unsigned int weight = weights[symbol];
        if (weight > ZSTD_HUFFMAN_BITS_MAXIMUM)
        {
            return 0;
        }
        ranks[weight] += 1u;
        total += (1ul << weight) >> 1u;
    }
    if (total == 0ul)
    {
        return 0;
    }
    const unsigned int bits = zstd_high_bit(total) + 1u;
    if (bits > ZSTD_HUFFMAN_BITS_MAXIMUM)
    {
        return 0;
    }
    const unsigned long rest = (1ul << bits) - total;
    const unsigned int last = zstd_high_bit(rest) + 1u;
    if ((1ul << (last - 1u)) != rest)
    {
        return 0;
    }
    weights[described] = (unsigned char)last;
    ranks[last] += 1u;
    if ((ranks[1u] < 2u) || ((ranks[1u] & 1u) != 0u))
    {
        return 0;
    }
    unsigned long starts[ZSTD_HUFFMAN_BITS_MAXIMUM + 1u];
    unsigned long running = 0ul;
    for (unsigned int weight = 1u; weight <= bits; weight += 1u)
    {
        starts[weight] = running;
        running += (unsigned long)ranks[weight] << (weight - 1u);
    }
    for (unsigned int symbol = 0u; symbol <= described; symbol += 1u)
    {
        const unsigned int weight = weights[symbol];
        if (weight == 0u)
        {
            continue;
        }
        const unsigned long length = 1ul << (weight - 1u);
        for (unsigned long fill = 0ul; fill < length; fill += 1ul)
        {
            decoder->huffman[starts[weight] + fill].symbol = (unsigned char)symbol;
            decoder->huffman[starts[weight] + fill].bits = (unsigned char)(bits + 1u - weight);
        }
        starts[weight] += length;
    }
    decoder->huffman_bits = bits;
    decoder->huffman_ready = 1;
    return 1;
}

static int zstd_huffman_stream(const ZstdDecoder *decoder, const unsigned char *bytes, unsigned long long length,
                               unsigned char *out, unsigned long long count)
{
    ZstdBackwardStream stream;
    if (!zstd_backward_open(&stream, bytes, length))
    {
        return 0;
    }
    const unsigned int bits = decoder->huffman_bits;
    for (unsigned long long produced = 0ull; produced < count; produced += 1ull)
    {
        const ZstdHuffmanCell cell = decoder->huffman[zstd_backward_peek(&stream, bits)];
        out[produced] = cell.symbol;
        stream.position -= (long long)cell.bits;
    }
    return stream.position == 0LL;
}

static int zstd_literals(ZstdDecoder *decoder, ZstdSpan *input)
{
    if (input->length == 0ull)
    {
        return 0;
    }
    const unsigned int first = input->bytes[0u];
    const unsigned int kind = first & 3u;
    const unsigned int format = (first >> 2u) & 3u;
    decoder->literals_used = 0ull;
    if (kind < 2u)
    {
        const unsigned int header = ((format & 1u) == 0u) ? 1u : ((format == 1u) ? 2u : 3u);
        if (input->length < header)
        {
            return 0;
        }
        const unsigned long long value = zstd_little_endian(input->bytes, header);
        const unsigned long long regenerated = (header == 1u) ? (value >> 3u) : (value >> 4u);
        if (regenerated > decoder->block_maximum)
        {
            return 0;
        }
        zstd_advance(input, header);
        const unsigned long long needed = (kind == 0u) ? regenerated : 1ull;
        if (input->length < needed)
        {
            return 0;
        }
        if (kind == 0u)
        {
            decoder->literals = input->bytes;
        }
        else
        {
            memset(decoder->literal_buffer, input->bytes[0u], (size_t)regenerated);
            decoder->literals = decoder->literal_buffer;
        }
        decoder->literal_count = regenerated;
        zstd_advance(input, needed);
        return 1;
    }
    const unsigned int header = (format < 2u) ? 3u : ((format == 2u) ? 4u : 5u);
    const unsigned int width = (format < 2u) ? 10u : ((format == 2u) ? 14u : 18u);
    if (input->length < header)
    {
        return 0;
    }
    const unsigned long long value = zstd_little_endian(input->bytes, header);
    const unsigned long long mask = (1ull << width) - 1ull;
    const unsigned long long regenerated = (value >> 4u) & mask;
    const unsigned long long compressed = (value >> (4u + width)) & mask;
    zstd_advance(input, header);
    if ((regenerated > decoder->block_maximum) || (compressed > input->length))
    {
        return 0;
    }
    ZstdSpan payload = {input->bytes, compressed};
    zstd_advance(input, compressed);
    if (kind == 2u)
    {
        if (!zstd_huffman_describe(decoder, &payload))
        {
            return 0;
        }
    }
    else if (!decoder->huffman_ready)
    {
        return 0;
    }
    decoder->literals = decoder->literal_buffer;
    decoder->literal_count = regenerated;
    if (format == 0u)
    {
        return zstd_huffman_stream(decoder, payload.bytes, payload.length, decoder->literal_buffer, regenerated);
    }
    if (payload.length < 6ull)
    {
        return 0;
    }
    const unsigned long long first_size = zstd_little_endian(payload.bytes, 2u);
    const unsigned long long second_size = zstd_little_endian(&payload.bytes[2u], 2u);
    const unsigned long long third_size = zstd_little_endian(&payload.bytes[4u], 2u);
    zstd_advance(&payload, 6ull);
    const unsigned long long leading = first_size + second_size + third_size;
    const unsigned long long segment = (regenerated + 3ull) / 4ull;
    if ((leading > payload.length) || ((3ull * segment) > regenerated))
    {
        return 0;
    }
    const unsigned long long sizes[4u] = {first_size, second_size, third_size, payload.length - leading};
    const unsigned long long lengths[4u] = {segment, segment, segment, regenerated - (3ull * segment)};
    unsigned long long produced = 0ull;
    for (unsigned int stream = 0u; stream < 4u; stream += 1u)
    {
        if (!zstd_huffman_stream(decoder, payload.bytes, sizes[stream], &decoder->literal_buffer[produced], lengths[stream]))
        {
            return 0;
        }
        zstd_advance(&payload, sizes[stream]);
        produced += lengths[stream];
    }
    return 1;
}

static int zstd_table_prepare(ZstdSpan *input, unsigned int mode, const ZstdTableKind *kind, ZstdFseTable *table)
{
    if (mode == 0u)
    {
        return zstd_fse_build(table, kind->predefined, kind->predefined_symbols, kind->predefined_accuracy);
    }
    if (mode == 1u)
    {
        if ((input->length == 0ull) || (input->bytes[0u] >= kind->symbols))
        {
            table->ready = 0;
            return 0;
        }
        table->cells[0u].symbol = input->bytes[0u];
        table->cells[0u].bits = 0u;
        table->cells[0u].baseline = 0u;
        table->accuracy = 0u;
        table->ready = 1;
        zstd_advance(input, 1ull);
        return 1;
    }
    if (mode == 2u)
    {
        long counts[ZSTD_FSE_SYMBOLS];
        unsigned int accuracy = 0u;
        table->ready = 0;
        return zstd_fse_describe(input, kind, counts, &accuracy) && zstd_fse_build(table, counts, kind->symbols, accuracy);
    }
    return table->ready;
}

static int zstd_output_fits(const ZstdDecoder *decoder, unsigned long long length)
{
    const unsigned long long block_written = decoder->written - decoder->block_start;
    return (length <= (decoder->out_room - decoder->written)) && (length <= (decoder->block_maximum - block_written));
}

static int zstd_literal_copy(ZstdDecoder *decoder, unsigned long long length)
{
    if ((length > (decoder->literal_count - decoder->literals_used)) || !zstd_output_fits(decoder, length))
    {
        return 0;
    }
    memmove(&decoder->out[decoder->written], &decoder->literals[decoder->literals_used], (size_t)length);
    decoder->literals_used += length;
    decoder->written += length;
    return 1;
}

static int zstd_match_copy(ZstdDecoder *decoder, unsigned long long offset, unsigned long long length)
{
    if ((offset > (decoder->written - decoder->frame_start)) || (offset > decoder->window)
        || !zstd_output_fits(decoder, length))
    {
        return 0;
    }
    unsigned char *const target = &decoder->out[decoder->written];
    const unsigned char *const source = target - offset;
    if (offset >= length)
    {
        memcpy(target, source, (size_t)length);
    }
    else
    {
        for (unsigned long long place = 0ull; place < length; place += 1ull)
        {
            target[place] = source[place];
        }
    }
    decoder->written += length;
    return 1;
}

static int zstd_offset_resolve(ZstdDecoder *decoder, unsigned long long offset_value, unsigned long long literal_length,
                               unsigned long long *offset)
{
    if (offset_value > 3ull)
    {
        *offset = offset_value - 3ull;
        decoder->repeat[2u] = decoder->repeat[1u];
        decoder->repeat[1u] = decoder->repeat[0u];
        decoder->repeat[0u] = *offset;
        return 1;
    }
    const unsigned long long slot = (offset_value - 1ull) + ((literal_length == 0ull) ? 1ull : 0ull);
    if (slot == 0ull)
    {
        *offset = decoder->repeat[0u];
        return 1;
    }
    const unsigned long long chosen = (slot == 3ull) ? (decoder->repeat[0u] - 1ull) : decoder->repeat[slot];
    if (chosen == 0ull)
    {
        return 0;
    }
    if (slot != 1ull)
    {
        decoder->repeat[2u] = decoder->repeat[1u];
    }
    decoder->repeat[1u] = decoder->repeat[0u];
    decoder->repeat[0u] = chosen;
    *offset = chosen;
    return 1;
}

static int zstd_sequences(ZstdDecoder *decoder, ZstdSpan *input)
{
    if (input->length == 0ull)
    {
        return 0;
    }
    const unsigned int first = input->bytes[0u];
    const unsigned int header = (first < 128u) ? 1u : ((first < 255u) ? 2u : 3u);
    if (input->length < header)
    {
        return 0;
    }
    const unsigned long long count = (header == 1u)   ? (unsigned long long)first
                                   : (header == 2u) ? ((((unsigned long long)first - 128ull) << 8u) + input->bytes[1u])
                                                    : (zstd_little_endian(&input->bytes[1u], 2u) + 0x7F00ull);
    zstd_advance(input, header);
    if (count == 0ull)
    {
        return (input->length == 0ull) && zstd_literal_copy(decoder, decoder->literal_count);
    }
    if (input->length == 0ull)
    {
        return 0;
    }
    const unsigned int modes = input->bytes[0u];
    zstd_advance(input, 1ull);
    if (((modes & 3u) != 0u) || !zstd_table_prepare(input, modes >> 6u, &zstd_literal_length_kind, &decoder->literal_lengths)
        || !zstd_table_prepare(input, (modes >> 4u) & 3u, &zstd_offset_kind, &decoder->offsets)
        || !zstd_table_prepare(input, (modes >> 2u) & 3u, &zstd_match_length_kind, &decoder->match_lengths))
    {
        return 0;
    }
    ZstdBackwardStream stream;
    if (!zstd_backward_open(&stream, input->bytes, input->length))
    {
        return 0;
    }
    unsigned int literal_state = (unsigned int)zstd_backward_read(&stream, decoder->literal_lengths.accuracy);
    unsigned int offset_state = (unsigned int)zstd_backward_read(&stream, decoder->offsets.accuracy);
    unsigned int match_state = (unsigned int)zstd_backward_read(&stream, decoder->match_lengths.accuracy);
    for (unsigned long long sequence = 0ull; sequence < count; sequence += 1ull)
    {
        const ZstdFseCell literal_cell = decoder->literal_lengths.cells[literal_state];
        const ZstdFseCell offset_cell = decoder->offsets.cells[offset_state];
        const ZstdFseCell match_cell = decoder->match_lengths.cells[match_state];
        const unsigned int offset_code = offset_cell.symbol;
        const unsigned long long offset_value = (1ull << offset_code) + zstd_backward_read(&stream, offset_code);
        const unsigned long long match_length = zstd_match_length_baselines[match_cell.symbol]
                                              + zstd_backward_read(&stream, zstd_match_length_extra[match_cell.symbol]);
        const unsigned long long literal_length = zstd_literal_length_baselines[literal_cell.symbol]
                                                + zstd_backward_read(&stream, zstd_literal_length_extra[literal_cell.symbol]);
        unsigned long long offset = 0ull;
        if (!zstd_offset_resolve(decoder, offset_value, literal_length, &offset) || !zstd_literal_copy(decoder, literal_length)
            || !zstd_match_copy(decoder, offset, match_length))
        {
            return 0;
        }
        if ((sequence + 1ull) < count)
        {
            literal_state = literal_cell.baseline + (unsigned int)zstd_backward_read(&stream, literal_cell.bits);
            match_state = match_cell.baseline + (unsigned int)zstd_backward_read(&stream, match_cell.bits);
            offset_state = offset_cell.baseline + (unsigned int)zstd_backward_read(&stream, offset_cell.bits);
        }
    }
    return (stream.position == 0LL) && zstd_literal_copy(decoder, decoder->literal_count - decoder->literals_used);
}

static unsigned long long zstd_rotate(unsigned long long value, unsigned int bits)
{
    return (value << bits) | (value >> (64u - bits));
}

static unsigned long long zstd_xxh64_round(unsigned long long accumulator, unsigned long long lane)
{
    const unsigned long long mixed = accumulator + (lane * ZSTD_XXH64_PRIME_TWO);
    return zstd_rotate(mixed, 31u) * ZSTD_XXH64_PRIME_ONE;
}

static unsigned long long zstd_xxh64_merge(unsigned long long hash, unsigned long long lane)
{
    const unsigned long long mixed = hash ^ zstd_xxh64_round(0ull, lane);
    return (mixed * ZSTD_XXH64_PRIME_ONE) + ZSTD_XXH64_PRIME_FOUR;
}

static unsigned long long zstd_xxh64(const unsigned char *bytes, unsigned long long length)
{
    unsigned long long at = 0ull;
    unsigned long long hash = ZSTD_XXH64_PRIME_FIVE;
    if (length >= 32ull)
    {
        unsigned long long lanes[4u] = {ZSTD_XXH64_PRIME_ONE + ZSTD_XXH64_PRIME_TWO, ZSTD_XXH64_PRIME_TWO, 0ull,
                                        0ull - ZSTD_XXH64_PRIME_ONE};
        while ((length - at) >= 32ull)
        {
            for (unsigned int lane = 0u; lane < 4u; lane += 1u)
            {
                lanes[lane] = zstd_xxh64_round(lanes[lane], zstd_little_endian(&bytes[at + (8ull * lane)], 8u));
            }
            at += 32ull;
        }
        hash = zstd_rotate(lanes[0u], 1u) + zstd_rotate(lanes[1u], 7u) + zstd_rotate(lanes[2u], 12u)
             + zstd_rotate(lanes[3u], 18u);
        for (unsigned int lane = 0u; lane < 4u; lane += 1u)
        {
            hash = zstd_xxh64_merge(hash, lanes[lane]);
        }
    }
    hash += length;
    while ((length - at) >= 8ull)
    {
        hash ^= zstd_xxh64_round(0ull, zstd_little_endian(&bytes[at], 8u));
        hash = (zstd_rotate(hash, 27u) * ZSTD_XXH64_PRIME_ONE) + ZSTD_XXH64_PRIME_FOUR;
        at += 8ull;
    }
    if ((length - at) >= 4ull)
    {
        hash ^= zstd_little_endian(&bytes[at], 4u) * ZSTD_XXH64_PRIME_ONE;
        hash = (zstd_rotate(hash, 23u) * ZSTD_XXH64_PRIME_TWO) + ZSTD_XXH64_PRIME_THREE;
        at += 4ull;
    }
    while (at < length)
    {
        hash ^= (unsigned long long)bytes[at] * ZSTD_XXH64_PRIME_FIVE;
        hash = zstd_rotate(hash, 11u) * ZSTD_XXH64_PRIME_ONE;
        at += 1ull;
    }
    hash ^= hash >> 33u;
    hash *= ZSTD_XXH64_PRIME_TWO;
    hash ^= hash >> 29u;
    hash *= ZSTD_XXH64_PRIME_THREE;
    hash ^= hash >> 32u;
    return hash;
}

static int zstd_block(ZstdDecoder *decoder, ZstdSpan *input, int *last)
{
    if (input->length < 3ull)
    {
        return 0;
    }
    const unsigned long long header = zstd_little_endian(input->bytes, 3u);
    const unsigned int kind = (unsigned int)((header >> 1u) & 3ull);
    const unsigned long long size = header >> 3u;
    zstd_advance(input, 3ull);
    *last = (int)(header & 1ull);
    decoder->block_start = decoder->written;
    if ((kind == 3u) || (size > decoder->block_maximum))
    {
        return 0;
    }
    if (kind == 1u)
    {
        if ((input->length == 0ull) || !zstd_output_fits(decoder, size))
        {
            return 0;
        }
        memset(&decoder->out[decoder->written], input->bytes[0u], (size_t)size);
        decoder->written += size;
        zstd_advance(input, 1ull);
        return 1;
    }
    if (size > input->length)
    {
        return 0;
    }
    ZstdSpan content = {input->bytes, size};
    zstd_advance(input, size);
    if (kind == 0u)
    {
        if (!zstd_output_fits(decoder, size))
        {
            return 0;
        }
        memmove(&decoder->out[decoder->written], content.bytes, (size_t)size);
        decoder->written += size;
        return 1;
    }
    return zstd_literals(decoder, &content) && zstd_sequences(decoder, &content);
}

static int zstd_frame(ZstdDecoder *decoder, ZstdSpan *input)
{
    if (input->length < 5ull)
    {
        return 0;
    }
    const unsigned int descriptor = input->bytes[4u];
    const unsigned int single = (descriptor >> 5u) & 1u;
    const unsigned int checksum = (descriptor >> 2u) & 1u;
    const unsigned int window_width = (single != 0u) ? 0u : 1u;
    const unsigned int dictionary_width = zstd_dictionary_widths[descriptor & 3u];
    const unsigned int content_width = ((descriptor >> 6u) == 0u) ? single : zstd_content_widths[descriptor >> 6u];
    const unsigned int header = 5u + window_width + dictionary_width + content_width;
    if ((((descriptor >> 3u) & 1u) != 0u) || (input->length < header))
    {
        return 0;
    }
    const unsigned int window_byte = input->bytes[5u];
    const unsigned long long window_base = 1ull << (10u + (window_byte >> 3u));
    const unsigned long long dictionary = zstd_little_endian(&input->bytes[5u + window_width], dictionary_width);
    const unsigned long long content_field
        = zstd_little_endian(&input->bytes[5u + window_width + dictionary_width], content_width);
    const unsigned long long content = content_field + ((content_width == 2u) ? 256ull : 0ull);
    if ((dictionary != 0ull) || ((content_width != 0u) && (content > (decoder->out_room - decoder->written))))
    {
        return 0;
    }
    decoder->window = (single != 0u) ? content : (window_base + ((window_base >> 3u) * (window_byte & 7u)));
    decoder->block_maximum = (decoder->window < ZSTD_BLOCK_MAXIMUM) ? decoder->window : ZSTD_BLOCK_MAXIMUM;
    decoder->frame_start = decoder->written;
    decoder->huffman_ready = 0;
    decoder->literal_lengths.ready = 0;
    decoder->match_lengths.ready = 0;
    decoder->offsets.ready = 0;
    decoder->repeat[0u] = 1ull;
    decoder->repeat[1u] = 4ull;
    decoder->repeat[2u] = 8ull;
    zstd_advance(input, header);
    int last = 0;
    while (!last)
    {
        if (!zstd_block(decoder, input, &last))
        {
            return 0;
        }
    }
    const unsigned long long produced = decoder->written - decoder->frame_start;
    if ((content_width != 0u) && (produced != content))
    {
        return 0;
    }
    if (checksum == 0u)
    {
        return 1;
    }
    if (input->length < 4ull)
    {
        return 0;
    }
    const unsigned long long stored = zstd_little_endian(input->bytes, 4u);
    const unsigned long long hash = zstd_xxh64(&decoder->out[decoder->frame_start], produced);
    zstd_advance(input, 4ull);
    return stored == (hash & 0xFFFFFFFFull);
}

long long zstd_decode(const EngineBytesRequest *request)
{
    if (request->in_bytes == 0ull)
    {
        return ENGINE_BYTES_REFUSED;
    }
    ZstdDecoder *const decoder = (ZstdDecoder *)malloc(sizeof(ZstdDecoder));
    if (decoder == NULL)
    {
        return ENGINE_BYTES_REFUSED;
    }
    decoder->out = request->out;
    decoder->out_room = request->out_room;
    decoder->written = 0ull;
    ZstdSpan input = {request->in, request->in_bytes};
    int good = 1;
    while (good && (input.length > 0ull))
    {
        const unsigned long long magic = (input.length >= 4ull) ? zstd_little_endian(input.bytes, 4u) : 0ull;
        const unsigned long long skippable = (input.length >= 8ull) ? zstd_little_endian(&input.bytes[4u], 4u) : 0ull;
        if ((input.length >= 4ull) && (magic == ZSTD_FRAME_MAGIC))
        {
            good = zstd_frame(decoder, &input);
        }
        else if ((input.length >= 8ull) && ((magic & ZSTD_SKIPPABLE_MASK) == ZSTD_SKIPPABLE_MAGIC)
                 && (skippable <= (input.length - 8ull)))
        {
            zstd_advance(&input, 8ull + skippable);
        }
        else
        {
            good = 0;
        }
    }
    const unsigned long long written = decoder->written;
    free(decoder);
    if (!good || (written > ZSTD_RESULT_MAXIMUM))
    {
        if (written > 0ull)
        {
            memset(request->out, 0, (size_t)written);
        }
        return ENGINE_BYTES_REFUSED;
    }
    return (long long)written;
}
