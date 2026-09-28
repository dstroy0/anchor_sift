// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// zstd_frame.c: sequences, XXH64, blocks, frames and the decoder
#include "zstd_internal.h"

static const long zstd_literal_length_predefined[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    4L, 3L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L,  1L,  2L,  2L,
    2L, 2L, 2L, 2L, 2L, 2L, 2L, 3L, 2L, 1L, 1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L};

static const long zstd_match_length_predefined[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    1L, 4L, 3L, 2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L,  1L,  1L,  1L,  1L,  1L,  1L, 1L,
    1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L, -1L, -1L, -1L};

static const long zstd_offset_predefined[ZSTD_OFFSET_PREDEFINED_SYMBOLS] = {1L, 1L, 1L, 1L, 1L,  1L,  2L,  2L,  2L, 1L,
                                                                            1L, 1L, 1L, 1L, 1L,  1L,  1L,  1L,  1L, 1L,
                                                                            1L, 1L, 1L, 1L, -1L, -1L, -1L, -1L, -1L};

static const unsigned int zstd_literal_length_baselines[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    0u,  1u,  2u,  3u,  4u,  5u,  6u,  7u,  8u,   9u,   10u,  11u,   12u,   13u,   14u,   15u,    16u,    18u,
    20u, 22u, 24u, 28u, 32u, 40u, 48u, 64u, 128u, 256u, 512u, 1024u, 2048u, 4096u, 8192u, 16384u, 32768u, 65536u};

static const unsigned int zstd_literal_length_extra[ZSTD_LITERAL_LENGTH_SYMBOLS] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,  0u,  0u,  0u,  0u,  1u,  1u,
    1u, 1u, 2u, 2u, 3u, 3u, 4u, 6u, 7u, 8u, 9u, 10u, 11u, 12u, 13u, 14u, 15u, 16u};

static const unsigned int zstd_match_length_baselines[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    3u,  4u,  5u,  6u,  7u,  8u,  9u,  10u,  11u,  12u,  13u,   14u,   15u,   16u,   17u,    18u,    19u,   20u,
    21u, 22u, 23u, 24u, 25u, 26u, 27u, 28u,  29u,  30u,  31u,   32u,   33u,   34u,   35u,    37u,    39u,   41u,
    43u, 47u, 51u, 59u, 67u, 83u, 99u, 131u, 259u, 515u, 1027u, 2051u, 4099u, 8195u, 16387u, 32771u, 65539u};

static const unsigned int zstd_match_length_extra[ZSTD_MATCH_LENGTH_SYMBOLS] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,  0u,  0u,  0u,  0u,  0u,  0u, 0u,
    0u, 0u, 0u, 0u, 0u, 1u, 1u, 1u, 1u, 2u, 2u, 3u, 3u, 4u, 4u, 5u, 7u, 8u, 9u, 10u, 11u, 12u, 13u, 14u, 15u, 16u};

static const ZstdTableKind zstd_literal_length_kind = {zstd_literal_length_predefined, ZSTD_LITERAL_LENGTH_SYMBOLS, 6u,
                                                       ZSTD_LITERAL_LENGTH_SYMBOLS, 9u};

static const ZstdTableKind zstd_match_length_kind = {zstd_match_length_predefined, ZSTD_MATCH_LENGTH_SYMBOLS, 6u,
                                                     ZSTD_MATCH_LENGTH_SYMBOLS, 9u};

static const ZstdTableKind zstd_offset_kind = {zstd_offset_predefined, ZSTD_OFFSET_PREDEFINED_SYMBOLS, 5u,
                                               ZSTD_OFFSET_SYMBOLS, 8u};

static const unsigned int zstd_dictionary_widths[4u] = {0u, 1u, 2u, 4u};

static const unsigned int zstd_content_widths[4u] = {0u, 2u, 4u, 8u};

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
    const unsigned long long count = (header == 1u) ? (unsigned long long)first
                                     : (header == 2u)
                                         ? ((((unsigned long long)first - 128ull) << 8u) + input->bytes[1u])
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
    if (((modes & 3u) != 0u) ||
        !zstd_table_prepare(input, modes >> 6u, &zstd_literal_length_kind, &decoder->literal_lengths) ||
        !zstd_table_prepare(input, (modes >> 4u) & 3u, &zstd_offset_kind, &decoder->offsets) ||
        !zstd_table_prepare(input, (modes >> 2u) & 3u, &zstd_match_length_kind, &decoder->match_lengths))
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
        const unsigned long long match_length = zstd_match_length_baselines[match_cell.symbol] +
                                                zstd_backward_read(&stream, zstd_match_length_extra[match_cell.symbol]);
        const unsigned long long literal_length =
            zstd_literal_length_baselines[literal_cell.symbol] +
            zstd_backward_read(&stream, zstd_literal_length_extra[literal_cell.symbol]);
        unsigned long long offset = 0ull;
        if (!zstd_offset_resolve(decoder, offset_value, literal_length, &offset) ||
            !zstd_literal_copy(decoder, literal_length) || !zstd_match_copy(decoder, offset, match_length))
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
        hash = zstd_rotate(lanes[0u], 1u) + zstd_rotate(lanes[1u], 7u) + zstd_rotate(lanes[2u], 12u) +
               zstd_rotate(lanes[3u], 18u);
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
    const unsigned long long content_field =
        zstd_little_endian(&input->bytes[5u + window_width + dictionary_width], content_width);
    const unsigned long long content = content_field + ((content_width == 2u) ? 256ull : 0ull);
    if ((dictionary != 0ull) || ((content_width != 0u) && (content > (decoder->out_capacity - decoder->written))))
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
        return ENGINE_BYTES_ERROR;
    }
    ZstdDecoder *const decoder = (ZstdDecoder *)malloc(sizeof(ZstdDecoder));
    if (decoder == NULL)
    {
        return ENGINE_BYTES_ERROR;
    }
    decoder->out = request->out;
    decoder->out_capacity = request->out_capacity;
    decoder->written = 0ull;
    ZstdSpan input = {request->in, request->in_bytes};
    int ok = 1;
    while (ok && (input.length > 0ull))
    {
        const unsigned long long magic = (input.length >= 4ull) ? zstd_little_endian(input.bytes, 4u) : 0ull;
        const unsigned long long skippable = (input.length >= 8ull) ? zstd_little_endian(&input.bytes[4u], 4u) : 0ull;
        if ((input.length >= 4ull) && (magic == ZSTD_FRAME_MAGIC))
        {
            ok = zstd_frame(decoder, &input);
        }
        else if ((input.length >= 8ull) && ((magic & ZSTD_SKIPPABLE_MASK) == ZSTD_SKIPPABLE_MAGIC) &&
                 (skippable <= (input.length - 8ull)))
        {
            zstd_advance(&input, 8ull + skippable);
        }
        else
        {
            ok = 0;
        }
    }
    const unsigned long long written = decoder->written;
    free(decoder);
    if (!ok || (written > ZSTD_RESULT_MAXIMUM))
    {
        if (written > 0ull)
        {
            memset(request->out, 0, (size_t)written);
        }
        return ENGINE_BYTES_ERROR;
    }
    return (long long)written;
}
