// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zstd_bits.c: bit readers, FSE tables and Huffman weights
#include "zstd_internal.h"

unsigned long long zstd_little_endian(const unsigned char *bytes, unsigned int count)
{
    unsigned long long value = 0ull;
    for (unsigned int place = 0u; place < count; place += 1u)
    {
        value |= (unsigned long long)bytes[place] << (8u * place);
    }
    return value;
}

void zstd_advance(ZstdSpan *span, unsigned long long count)
{
    span->bytes += count;
    span->length -= count;
}

unsigned int zstd_high_bit(unsigned long long value)
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
        word = (unsigned long long)lane[0u] | ((unsigned long long)lane[1u] << 8u) |
               ((unsigned long long)lane[2u] << 16u) | ((unsigned long long)lane[3u] << 24u) |
               ((unsigned long long)lane[4u] << 32u) | ((unsigned long long)lane[5u] << 40u) |
               ((unsigned long long)lane[6u] << 48u) | ((unsigned long long)lane[7u] << 56u);
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
    const unsigned long long byte_position = stream->position >> 3u;
    const unsigned long long partial = ((stream->position & 7ull) != 0ull) ? 1ull : 0ull;
    return (byte_position + partial) <= stream->length;
}

int zstd_backward_open(ZstdBackwardStream *stream, const unsigned char *bytes, unsigned long long length)
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

unsigned long long zstd_backward_peek(const ZstdBackwardStream *stream, unsigned int count)
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

unsigned long long zstd_backward_read(ZstdBackwardStream *stream, unsigned int count)
{
    const unsigned long long value = zstd_backward_peek(stream, count);
    stream->position -= (long long)count;
    return value;
}

int zstd_fse_describe(ZstdSpan *input, const ZstdTableKind *kind, long *counts, unsigned int *accuracy)
{
    ZstdForwardStream stream = {input->bytes, input->length, 0ull};
    const unsigned int found = (unsigned int)zstd_forward_peek(&stream, 4u) + 5u;
    int ok = zstd_forward_skip(&stream, 4u) && (found <= kind->accuracy);
    for (unsigned int symbol = 0u; symbol < kind->symbols; symbol += 1u)
    {
        counts[symbol] = 0L;
    }
    long remaining = (1L << found) + 1L;
    long threshold = 1L << found;
    unsigned int width = found + 1u;
    unsigned int symbol = 0u;
    int previous_zero = 0;
    int measurement = ok;
    while (measurement)
    {
        if (previous_zero)
        {
            unsigned int flag = (unsigned int)zstd_forward_peek(&stream, 2u);
            ok = zstd_forward_skip(&stream, 2u);
            while (ok && (flag == 3u))
            {
                symbol += 3u;
                flag = (unsigned int)zstd_forward_peek(&stream, 2u);
                ok = zstd_forward_skip(&stream, 2u) && (symbol < kind->symbols);
            }
            symbol += flag;
            ok = ok && (symbol < kind->symbols);
            if (!ok)
            {
                break;
            }
        }
        const long maximum = ((2L * threshold) - 1L) - remaining;
        const long peeked = (long)zstd_forward_peek(&stream, width);
        const long low = peeked & (threshold - 1L);
        const long full = peeked & ((2L * threshold) - 1L);
        const int short_form = (low < maximum);
        const long value = short_form ? low : ((full >= threshold) ? (full - maximum) : full);
        ok = zstd_forward_skip(&stream, short_form ? (width - 1u) : width);
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
        measurement = ok && (remaining > 1L) && (symbol < kind->symbols);
    }
    const unsigned long long consumed = (stream.position + 7ull) >> 3u;
    ok = ok && (remaining == 1L) && (consumed <= input->length);
    if (ok)
    {
        zstd_advance(input, consumed);
    }
    *accuracy = found;
    return ok;
}

int zstd_fse_build(ZstdFseTable *table, const long *counts, unsigned int symbols, unsigned int accuracy)
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

int zstd_weights_decode(const ZstdFseTable *table, const ZstdSpan *payload, unsigned char *weights,
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
