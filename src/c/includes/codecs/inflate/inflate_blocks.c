// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// inflate_blocks.c: stored, fixed and dynamic blocks, zlib and gzip
#include "inflate_internal.h"

static const unsigned char inflate_code_length_order[INFLATE_CODE_LENGTH_CODES] = {
    16u, 17u, 18u, 0u, 8u, 7u, 9u, 6u, 10u, 5u, 11u, 4u, 12u, 3u, 13u, 2u, 14u, 1u, 15u};

static const unsigned int inflate_crc_table[256u] = {
    0x00000000u, 0x77073096u, 0xEE0E612Cu, 0x990951BAu, 0x076DC419u, 0x706AF48Fu, 0xE963A535u, 0x9E6495A3u, 0x0EDB8832u,
    0x79DCB8A4u, 0xE0D5E91Eu, 0x97D2D988u, 0x09B64C2Bu, 0x7EB17CBDu, 0xE7B82D07u, 0x90BF1D91u, 0x1DB71064u, 0x6AB020F2u,
    0xF3B97148u, 0x84BE41DEu, 0x1ADAD47Du, 0x6DDDE4EBu, 0xF4D4B551u, 0x83D385C7u, 0x136C9856u, 0x646BA8C0u, 0xFD62F97Au,
    0x8A65C9ECu, 0x14015C4Fu, 0x63066CD9u, 0xFA0F3D63u, 0x8D080DF5u, 0x3B6E20C8u, 0x4C69105Eu, 0xD56041E4u, 0xA2677172u,
    0x3C03E4D1u, 0x4B04D447u, 0xD20D85FDu, 0xA50AB56Bu, 0x35B5A8FAu, 0x42B2986Cu, 0xDBBBC9D6u, 0xACBCF940u, 0x32D86CE3u,
    0x45DF5C75u, 0xDCD60DCFu, 0xABD13D59u, 0x26D930ACu, 0x51DE003Au, 0xC8D75180u, 0xBFD06116u, 0x21B4F4B5u, 0x56B3C423u,
    0xCFBA9599u, 0xB8BDA50Fu, 0x2802B89Eu, 0x5F058808u, 0xC60CD9B2u, 0xB10BE924u, 0x2F6F7C87u, 0x58684C11u, 0xC1611DABu,
    0xB6662D3Du, 0x76DC4190u, 0x01DB7106u, 0x98D220BCu, 0xEFD5102Au, 0x71B18589u, 0x06B6B51Fu, 0x9FBFE4A5u, 0xE8B8D433u,
    0x7807C9A2u, 0x0F00F934u, 0x9609A88Eu, 0xE10E9818u, 0x7F6A0DBBu, 0x086D3D2Du, 0x91646C97u, 0xE6635C01u, 0x6B6B51F4u,
    0x1C6C6162u, 0x856530D8u, 0xF262004Eu, 0x6C0695EDu, 0x1B01A57Bu, 0x8208F4C1u, 0xF50FC457u, 0x65B0D9C6u, 0x12B7E950u,
    0x8BBEB8EAu, 0xFCB9887Cu, 0x62DD1DDFu, 0x15DA2D49u, 0x8CD37CF3u, 0xFBD44C65u, 0x4DB26158u, 0x3AB551CEu, 0xA3BC0074u,
    0xD4BB30E2u, 0x4ADFA541u, 0x3DD895D7u, 0xA4D1C46Du, 0xD3D6F4FBu, 0x4369E96Au, 0x346ED9FCu, 0xAD678846u, 0xDA60B8D0u,
    0x44042D73u, 0x33031DE5u, 0xAA0A4C5Fu, 0xDD0D7CC9u, 0x5005713Cu, 0x270241AAu, 0xBE0B1010u, 0xC90C2086u, 0x5768B525u,
    0x206F85B3u, 0xB966D409u, 0xCE61E49Fu, 0x5EDEF90Eu, 0x29D9C998u, 0xB0D09822u, 0xC7D7A8B4u, 0x59B33D17u, 0x2EB40D81u,
    0xB7BD5C3Bu, 0xC0BA6CADu, 0xEDB88320u, 0x9ABFB3B6u, 0x03B6E20Cu, 0x74B1D29Au, 0xEAD54739u, 0x9DD277AFu, 0x04DB2615u,
    0x73DC1683u, 0xE3630B12u, 0x94643B84u, 0x0D6D6A3Eu, 0x7A6A5AA8u, 0xE40ECF0Bu, 0x9309FF9Du, 0x0A00AE27u, 0x7D079EB1u,
    0xF00F9344u, 0x8708A3D2u, 0x1E01F268u, 0x6906C2FEu, 0xF762575Du, 0x806567CBu, 0x196C3671u, 0x6E6B06E7u, 0xFED41B76u,
    0x89D32BE0u, 0x10DA7A5Au, 0x67DD4ACCu, 0xF9B9DF6Fu, 0x8EBEEFF9u, 0x17B7BE43u, 0x60B08ED5u, 0xD6D6A3E8u, 0xA1D1937Eu,
    0x38D8C2C4u, 0x4FDFF252u, 0xD1BB67F1u, 0xA6BC5767u, 0x3FB506DDu, 0x48B2364Bu, 0xD80D2BDAu, 0xAF0A1B4Cu, 0x36034AF6u,
    0x41047A60u, 0xDF60EFC3u, 0xA867DF55u, 0x316E8EEFu, 0x4669BE79u, 0xCB61B38Cu, 0xBC66831Au, 0x256FD2A0u, 0x5268E236u,
    0xCC0C7795u, 0xBB0B4703u, 0x220216B9u, 0x5505262Fu, 0xC5BA3BBEu, 0xB2BD0B28u, 0x2BB45A92u, 0x5CB36A04u, 0xC2D7FFA7u,
    0xB5D0CF31u, 0x2CD99E8Bu, 0x5BDEAE1Du, 0x9B64C2B0u, 0xEC63F226u, 0x756AA39Cu, 0x026D930Au, 0x9C0906A9u, 0xEB0E363Fu,
    0x72076785u, 0x05005713u, 0x95BF4A82u, 0xE2B87A14u, 0x7BB12BAEu, 0x0CB61B38u, 0x92D28E9Bu, 0xE5D5BE0Du, 0x7CDCEFB7u,
    0x0BDBDF21u, 0x86D3D2D4u, 0xF1D4E242u, 0x68DDB3F8u, 0x1FDA836Eu, 0x81BE16CDu, 0xF6B9265Bu, 0x6FB077E1u, 0x18B74777u,
    0x88085AE6u, 0xFF0F6A70u, 0x66063BCAu, 0x11010B5Cu, 0x8F659EFFu, 0xF862AE69u, 0x616BFFD3u, 0x166CCF45u, 0xA00AE278u,
    0xD70DD2EEu, 0x4E048354u, 0x3903B3C2u, 0xA7672661u, 0xD06016F7u, 0x4969474Du, 0x3E6E77DBu, 0xAED16A4Au, 0xD9D65ADCu,
    0x40DF0B66u, 0x37D83BF0u, 0xA9BCAE53u, 0xDEBB9EC5u, 0x47B2CF7Fu, 0x30B5FFE9u, 0xBDBDF21Cu, 0xCABAC28Au, 0x53B39330u,
    0x24B4A3A6u, 0xBAD03605u, 0xCDD70693u, 0x54DE5729u, 0x23D967BFu, 0xB3667A2Eu, 0xC4614AB8u, 0x5D681B02u, 0x2A6F2B94u,
    0xB40BBE37u, 0xC30C8EA1u, 0x5A05DF1Bu, 0x2D02EF8Du};

static int inflate_stored(InflateStream *stream)
{
    inflate_align(stream);
    if ((stream->in_bytes - stream->at) < 4ull)
    {
        return 0;
    }
    const unsigned char *const header = stream->in + stream->at;
    const unsigned int length = (unsigned int)header[0u] | ((unsigned int)header[1u] << 8u);
    const unsigned int complement = (unsigned int)header[2u] | ((unsigned int)header[3u] << 8u);
    if ((length ^ 0xFFFFu) != complement)
    {
        return 0;
    }
    stream->at += 4ull;
    if (((stream->in_bytes - stream->at) < length) || ((stream->out_capacity - stream->written) < length))
    {
        return 0;
    }
    if (length != 0u)
    {
        memcpy(stream->out + stream->written, stream->in + stream->at, (size_t)length);
    }
    stream->at += length;
    stream->written += length;
    return 1;
}

static int inflate_fixed(InflateStream *stream)
{
    unsigned char lengths[INFLATE_LITERAL_CODES + INFLATE_DISTANCE_CODES];
    memset(lengths, 8u, 144u);
    memset(lengths + 144u, 9u, 112u);
    memset(lengths + 256u, 7u, 24u);
    memset(lengths + 280u, 8u, 8u);
    memset(lengths + INFLATE_LITERAL_CODES, 5u, INFLATE_DISTANCE_CODES);
    InflateHuffman literals;
    InflateHuffman distances;
    return inflate_build(&literals, lengths, INFLATE_LITERAL_CODES, 1) &&
           inflate_build(&distances, lengths + INFLATE_LITERAL_CODES, INFLATE_DISTANCE_CODES, 1) &&
           inflate_codes(stream, &literals, &distances);
}

static int inflate_dynamic(InflateStream *stream)
{
    unsigned int literal_count = 0u;
    unsigned int distance_count = 0u;
    unsigned int code_length_count = 0u;
    if (!inflate_take(stream, 5u, &literal_count) || !inflate_take(stream, 5u, &distance_count) ||
        !inflate_take(stream, 4u, &code_length_count))
    {
        return 0;
    }
    literal_count += 257u;
    distance_count += 1u;
    code_length_count += 4u;
    if ((literal_count > INFLATE_LITERAL_LIMIT) || (distance_count > INFLATE_DISTANCE_LIMIT))
    {
        return 0;
    }
    unsigned char code_lengths[INFLATE_CODE_LENGTH_CODES];
    memset(code_lengths, 0u, sizeof(code_lengths));
    for (unsigned int slot = 0u; slot < code_length_count; slot += 1u)
    {
        unsigned int value = 0u;
        if (!inflate_take(stream, 3u, &value))
        {
            return 0;
        }
        code_lengths[inflate_code_length_order[slot]] = (unsigned char)value;
    }
    InflateHuffman code_huffman;
    if (!inflate_build(&code_huffman, code_lengths, INFLATE_CODE_LENGTH_CODES, 0))
    {
        return 0;
    }
    unsigned char lengths[INFLATE_LITERAL_CODES + INFLATE_DISTANCE_CODES];
    memset(lengths, 0u, sizeof(lengths));
    const unsigned int total = literal_count + distance_count;
    unsigned int filled = 0u;
    while (filled < total)
    {
        unsigned int symbol = 0u;
        if (!inflate_symbol(stream, &code_huffman, &symbol))
        {
            return 0;
        }
        if (symbol < 16u)
        {
            lengths[filled] = (unsigned char)symbol;
            filled += 1u;
            continue;
        }
        if ((symbol == 16u) && (filled == 0u))
        {
            return 0;
        }
        const unsigned char repeated = (unsigned char)((symbol == 16u) ? lengths[filled - 1u] : 0u);
        const unsigned int extra_bits = (symbol == 16u) ? 2u : ((symbol == 17u) ? 3u : 7u);
        const unsigned int base = (symbol == 18u) ? 11u : 3u;
        unsigned int extra = 0u;
        if (!inflate_take(stream, extra_bits, &extra))
        {
            return 0;
        }
        const unsigned int repeat = base + extra;
        if (repeat > (total - filled))
        {
            return 0;
        }
        memset(lengths + filled, repeated, repeat);
        filled += repeat;
    }
    if (lengths[INFLATE_END_OF_BLOCK] == 0u)
    {
        return 0;
    }
    InflateHuffman literals;
    InflateHuffman distances;
    return inflate_build(&literals, lengths, literal_count, 1) &&
           inflate_build(&distances, lengths + literal_count, distance_count, 1) &&
           inflate_codes(stream, &literals, &distances);
}

static int inflate_blocks(InflateStream *stream)
{
    unsigned int last_block = 0u;
    while (last_block == 0u)
    {
        unsigned int header = 0u;
        if (!inflate_take(stream, 3u, &header))
        {
            return 0;
        }
        last_block = header & 1u;
        const unsigned int block_type = header >> 1u;
        const int ok = (block_type == 0u)   ? inflate_stored(stream)
                       : (block_type == 1u) ? inflate_fixed(stream)
                       : (block_type == 2u) ? inflate_dynamic(stream)
                                            : 0;
        if (!ok)
        {
            return 0;
        }
    }
    inflate_align(stream);
    return 1;
}

static unsigned int inflate_adler(const unsigned char *bytes, unsigned long long count)
{
    unsigned long long low = 1ull;
    unsigned long long high = 0ull;
    unsigned long long at = 0ull;
    while (at < count)
    {
        const unsigned long long run_end = ((count - at) > INFLATE_ADLER_RUN) ? (at + INFLATE_ADLER_RUN) : count;
        while (at < run_end)
        {
            low += bytes[at];
            high += low;
            at += 1ull;
        }
        low %= INFLATE_ADLER_MODULUS;
        high %= INFLATE_ADLER_MODULUS;
    }
    return (unsigned int)((high << 16u) | low);
}

static unsigned int inflate_crc(const unsigned char *bytes, unsigned long long count)
{
    unsigned int crc = 0xFFFFFFFFu;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        crc = inflate_crc_table[(crc ^ bytes[at]) & 0xFFu] ^ (crc >> 8u);
    }
    return crc ^ 0xFFFFFFFFu;
}

static unsigned int inflate_little_32(const unsigned char *bytes)
{
    return (unsigned int)bytes[0u] | ((unsigned int)bytes[1u] << 8u) | ((unsigned int)bytes[2u] << 16u) |
           ((unsigned int)bytes[3u] << 24u);
}

static unsigned long long inflate_skip_string(const unsigned char *bytes, unsigned long long cursor,
                                              unsigned long long available)
{
    while ((cursor < available) && (bytes[cursor] != 0u))
    {
        cursor += 1ull;
    }
    return (cursor < available) ? (cursor + 1ull) : 0ull;
}

static long long inflate_error(const EngineBytesRequest *request, unsigned long long touched)
{
    if (touched != 0ull)
    {
        memset(request->out, 0, (size_t)touched);
    }
    return ENGINE_BYTES_ERROR;
}

long long inflate_raw_decode(const EngineBytesRequest *request)
{
    InflateStream stream = {request->in, request->in_bytes, 0ull, 0ull, 0u, request->out, request->out_capacity, 0ull};
    if (!inflate_blocks(&stream) || (stream.at != stream.in_bytes))
    {
        return inflate_error(request, stream.written);
    }
    return (long long)stream.written;
}

long long inflate_zlib_decode(const EngineBytesRequest *request)
{
    if (request->in_bytes < 2ull)
    {
        return ENGINE_BYTES_ERROR;
    }
    const unsigned int method = request->in[0u];
    const unsigned int flags = request->in[1u];
    const int header_ok = ((method & 15u) == 8u) && ((method >> 4u) <= 7u) &&
                          ((((method << 8u) | flags) % 31u) == 0u) && ((flags & 0x20u) == 0u);
    if (!header_ok)
    {
        return ENGINE_BYTES_ERROR;
    }
    InflateStream stream = {request->in + 2u, request->in_bytes - 2ull, 0ull, 0ull, 0u,
                            request->out,     request->out_capacity,    0ull};
    if (!inflate_blocks(&stream) || ((stream.in_bytes - stream.at) != 4ull))
    {
        return inflate_error(request, stream.written);
    }
    const unsigned char *const trailer = stream.in + stream.at;
    const unsigned int stored = ((unsigned int)trailer[0u] << 24u) | ((unsigned int)trailer[1u] << 16u) |
                                ((unsigned int)trailer[2u] << 8u) | (unsigned int)trailer[3u];
    if (stored != inflate_adler(stream.out, stream.written))
    {
        return inflate_error(request, stream.written);
    }
    return (long long)stream.written;
}

static int inflate_gzip_member(const EngineBytesRequest *request, unsigned long long *at, unsigned long long *total)
{
    const unsigned char *const member = request->in + *at;
    const unsigned long long available = request->in_bytes - *at;
    if (available < INFLATE_GZIP_HEADER)
    {
        return 0;
    }
    const unsigned int flags = member[3u];
    if ((member[0u] != 0x1Fu) || (member[1u] != 0x8Bu) || (member[2u] != 8u) || ((flags & 0xE0u) != 0u))
    {
        return 0;
    }
    unsigned long long cursor = INFLATE_GZIP_HEADER;
    if ((flags & 4u) != 0u)
    {
        if ((available - cursor) < 2ull)
        {
            return 0;
        }
        const unsigned long long extra_length =
            (unsigned long long)member[cursor] | ((unsigned long long)member[cursor + 1ull] << 8u);
        cursor += 2ull;
        if ((available - cursor) < extra_length)
        {
            return 0;
        }
        cursor += extra_length;
    }
    if ((flags & 8u) != 0u)
    {
        cursor = inflate_skip_string(member, cursor, available);
        if (cursor == 0ull)
        {
            return 0;
        }
    }
    if ((flags & 16u) != 0u)
    {
        cursor = inflate_skip_string(member, cursor, available);
        if (cursor == 0ull)
        {
            return 0;
        }
    }
    if ((flags & 2u) != 0u)
    {
        if ((available - cursor) < 2ull)
        {
            return 0;
        }
        const unsigned int header_check = (unsigned int)member[cursor] | ((unsigned int)member[cursor + 1ull] << 8u);
        if (header_check != (inflate_crc(member, cursor) & 0xFFFFu))
        {
            return 0;
        }
        cursor += 2ull;
    }
    InflateStream stream = {member + cursor,
                            available - cursor,
                            0ull,
                            0ull,
                            0u,
                            request->out + *total,
                            request->out_capacity - *total,
                            0ull};
    const int inflated = inflate_blocks(&stream);
    *total += stream.written;
    if (!inflated || ((stream.in_bytes - stream.at) < INFLATE_GZIP_TRAILER))
    {
        return 0;
    }
    const unsigned char *const trailer = stream.in + stream.at;
    const int trailer_ok = (inflate_little_32(trailer) == inflate_crc(stream.out, stream.written)) &&
                           (inflate_little_32(trailer + 4u) == (unsigned int)(stream.written & 0xFFFFFFFFull));
    *at += cursor + stream.at + INFLATE_GZIP_TRAILER;
    return trailer_ok;
}

long long inflate_gzip_decode(const EngineBytesRequest *request)
{
    unsigned long long at = 0ull;
    unsigned long long total = 0ull;
    int ok = (request->in_bytes != 0ull);
    while (ok && (at < request->in_bytes))
    {
        ok = inflate_gzip_member(request, &at, &total);
    }
    if (!ok)
    {
        return inflate_error(request, total);
    }
    return (long long)total;
}
