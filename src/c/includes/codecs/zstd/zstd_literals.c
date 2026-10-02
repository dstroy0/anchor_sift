// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zstd_literals.c: Huffman streams, literals, tables and copies
#include "zstd_internal.h"

static const ZstdTableKind zstd_weight_kind = {NULL, 0u, 0u, ZSTD_WEIGHT_SYMBOLS, ZSTD_WEIGHT_ACCURACY_MAXIMUM};

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
        if (!zstd_fse_describe(&payload, &zstd_weight_kind, counts, &accuracy) ||
            !zstd_fse_build(&table, counts, ZSTD_WEIGHT_SYMBOLS, accuracy) ||
            !zstd_weights_decode(&table, &payload, weights, &described))
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

int zstd_literals(ZstdDecoder *decoder, ZstdSpan *input)
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
        if (!zstd_huffman_stream(decoder, payload.bytes, sizes[stream], &decoder->literal_buffer[produced],
                                 lengths[stream]))
        {
            return 0;
        }
        zstd_advance(&payload, sizes[stream]);
        produced += lengths[stream];
    }
    return 1;
}

int zstd_table_prepare(ZstdSpan *input, unsigned int mode, const ZstdTableKind *kind, ZstdFseTable *table)
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
        return zstd_fse_describe(input, kind, counts, &accuracy) &&
               zstd_fse_build(table, counts, kind->symbols, accuracy);
    }
    return table->ready;
}

int zstd_output_fits(const ZstdDecoder *decoder, unsigned long long length)
{
    const unsigned long long block_written = decoder->written - decoder->block_start;
    return (length <= (decoder->out_capacity - decoder->written)) &&
           (length <= (decoder->block_maximum - block_written));
}

int zstd_literal_copy(ZstdDecoder *decoder, unsigned long long length)
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

int zstd_match_copy(ZstdDecoder *decoder, unsigned long long offset, unsigned long long length)
{
    if ((offset > (decoder->written - decoder->frame_start)) || (offset > decoder->window) ||
        !zstd_output_fits(decoder, length))
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

int zstd_offset_resolve(ZstdDecoder *decoder, unsigned long long offset_value, unsigned long long literal_length,
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
