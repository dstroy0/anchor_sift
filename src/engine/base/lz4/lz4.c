// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "lz4.h"

#include <limits.h>
#include <string.h>

#define LZ4_FRAME_MAGIC 0x184D2204u
#define LZ4_SKIPPABLE_MAGIC 0x184D2A50u
#define LZ4_SKIPPABLE_MASK 0xFFFFFFF0u
#define LZ4_MINIMUM_MATCH 4u
#define LZ4_RUN_MASK 15u
#define LZ4_UNCOMPRESSED_BIT 0x80000000u
#define LZ4_PRIME_FIRST 2654435761u
#define LZ4_PRIME_SECOND 2246822519u
#define LZ4_PRIME_THIRD 3266489917u
#define LZ4_PRIME_FOURTH 668265263u
#define LZ4_PRIME_FIFTH 374761393u

_Static_assert(UINT_MAX == 0xFFFFFFFFu, "lz4: unsigned int must be 32 bits wide for the XXH32 lanes and the size words");

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned char *out;
    unsigned long long out_room;
    unsigned long long history_start;
    unsigned long long written;
} Lz4Walk;

typedef struct
{
    const EngineBytesRequest *request;
    unsigned long long at;
    unsigned long long written;
} Lz4Frames;

static unsigned int lz4_little_32(const unsigned char *bytes)
{
    return (unsigned int)bytes[0u] | ((unsigned int)bytes[1u] << 8u) | ((unsigned int)bytes[2u] << 16u)
         | ((unsigned int)bytes[3u] << 24u);
}

static unsigned int lz4_rotate(unsigned int value, unsigned int count)
{
    return (value << count) | (value >> (32u - count));
}

static unsigned int lz4_xxh32_round(unsigned int accumulator, unsigned int lane)
{
    return lz4_rotate(accumulator + (lane * LZ4_PRIME_SECOND), 13u) * LZ4_PRIME_FIRST;
}

static unsigned int lz4_xxh32(const unsigned char *bytes, unsigned long long count)
{
    unsigned long long at = 0ull;
    unsigned int hash = LZ4_PRIME_FIFTH;
    if (count >= 16ull)
    {
        unsigned int lanes[4u] = {LZ4_PRIME_FIRST + LZ4_PRIME_SECOND, LZ4_PRIME_SECOND, 0u, 0u - LZ4_PRIME_FIRST};
        while ((count - at) >= 16ull)
        {
            for (unsigned int lane = 0u; lane < 4u; lane += 1u)
            {
                lanes[lane] = lz4_xxh32_round(lanes[lane], lz4_little_32(bytes + at + (4u * lane)));
            }
            at += 16ull;
        }
        hash = lz4_rotate(lanes[0u], 1u) + lz4_rotate(lanes[1u], 7u) + lz4_rotate(lanes[2u], 12u) + lz4_rotate(lanes[3u], 18u);
    }
    hash += (unsigned int)(count & 0xFFFFFFFFull);
    while ((count - at) >= 4ull)
    {
        hash = lz4_rotate(hash + (lz4_little_32(bytes + at) * LZ4_PRIME_THIRD), 17u) * LZ4_PRIME_FOURTH;
        at += 4ull;
    }
    while (at < count)
    {
        hash = lz4_rotate(hash + ((unsigned int)bytes[at] * LZ4_PRIME_FIFTH), 11u) * LZ4_PRIME_FIRST;
        at += 1ull;
    }
    hash ^= hash >> 15u;
    hash *= LZ4_PRIME_SECOND;
    hash ^= hash >> 13u;
    hash *= LZ4_PRIME_THIRD;
    hash ^= hash >> 16u;
    return hash;
}

static int lz4_extend(const Lz4Walk *walk, unsigned long long *at, unsigned long long *length)
{
    if (*length != LZ4_RUN_MASK)
    {
        return 1;
    }
    unsigned int byte = 255u;
    while (byte == 255u)
    {
        if (*at == walk->in_bytes)
        {
            return 0;
        }
        byte = walk->in[*at];
        *at += 1ull;
        *length += byte;
    }
    return 1;
}

static int lz4_block(Lz4Walk *walk)
{
    unsigned long long at = 0ull;
    for (;;)
    {
        if (at == walk->in_bytes)
        {
            return 0;
        }
        const unsigned int token = walk->in[at];
        at += 1ull;
        unsigned long long literal_length = token >> 4u;
        if (!lz4_extend(walk, &at, &literal_length))
        {
            return 0;
        }
        if ((literal_length > (walk->in_bytes - at)) || (literal_length > (walk->out_room - walk->written)))
        {
            return 0;
        }
        if (literal_length != 0ull)
        {
            memcpy(walk->out + walk->written, walk->in + at, (size_t)literal_length);
        }
        at += literal_length;
        walk->written += literal_length;
        if (at == walk->in_bytes)
        {
            return 1;
        }
        if ((walk->in_bytes - at) < 2ull)
        {
            return 0;
        }
        const unsigned long long offset = (unsigned long long)walk->in[at] | ((unsigned long long)walk->in[at + 1ull] << 8u);
        at += 2ull;
        if ((offset == 0ull) || (offset > (walk->written - walk->history_start)))
        {
            return 0;
        }
        unsigned long long match_length = token & LZ4_RUN_MASK;
        if (!lz4_extend(walk, &at, &match_length))
        {
            return 0;
        }
        match_length += LZ4_MINIMUM_MATCH;
        if (match_length > (walk->out_room - walk->written))
        {
            return 0;
        }
        unsigned char *const target = walk->out + walk->written;
        const unsigned char *const source = target - offset;
        if (offset >= match_length)
        {
            memcpy(target, source, (size_t)match_length);
        }
        else
        {
            for (unsigned long long copied = 0ull; copied < match_length; copied += 1ull)
            {
                target[copied] = source[copied];
            }
        }
        walk->written += match_length;
    }
}

static long long lz4_refuse(const EngineBytesRequest *request, unsigned long long touched)
{
    if (touched != 0ull)
    {
        memset(request->out, 0, (size_t)touched);
    }
    return ENGINE_BYTES_REFUSED;
}

static int lz4_frame(Lz4Frames *frames)
{
    const EngineBytesRequest *const request = frames->request;
    const unsigned char *const frame = request->in + frames->at;
    const unsigned long long available = request->in_bytes - frames->at;
    if (available < 4ull)
    {
        return 0;
    }
    const unsigned int magic = lz4_little_32(frame);
    if ((magic & LZ4_SKIPPABLE_MASK) == LZ4_SKIPPABLE_MAGIC)
    {
        if (available < 8ull)
        {
            return 0;
        }
        const unsigned long long skipped = lz4_little_32(frame + 4u);
        if ((available - 8ull) < skipped)
        {
            return 0;
        }
        frames->at += 8ull + skipped;
        return 1;
    }
    if ((magic != LZ4_FRAME_MAGIC) || (available < 7ull))
    {
        return 0;
    }
    const unsigned int flags = frame[4u];
    const unsigned int descriptor = frame[5u];
    const unsigned int block_code = (descriptor >> 4u) & 7u;
    if (((flags >> 6u) != 1u) || ((flags & 3u) != 0u) || ((descriptor & 0x8Fu) != 0u) || (block_code < 4u))
    {
        return 0;
    }
    const unsigned long long block_maximum = 1ull << (8u + (2u * block_code));
    const int independent = (flags & 0x20u) != 0u;
    const unsigned long long block_checksum = ((flags & 0x10u) != 0u) ? 4ull : 0ull;
    const int sized = (flags & 8u) != 0u;
    const int content_checksum = (flags & 4u) != 0u;
    const unsigned long long descriptor_length = sized ? 10ull : 2ull;
    if ((available - 4ull) < (descriptor_length + 1ull))
    {
        return 0;
    }
    if (frame[4u + descriptor_length] != ((lz4_xxh32(frame + 4u, descriptor_length) >> 8u) & 0xFFu))
    {
        return 0;
    }
    unsigned long long content_size = 0ull;
    for (unsigned int byte = 0u; sized && (byte < 8u); byte += 1u)
    {
        content_size |= (unsigned long long)frame[6u + byte] << (8u * byte);
    }
    if (sized && (content_size > (request->out_room - frames->written)))
    {
        return 0;
    }
    unsigned long long cursor = 5ull + descriptor_length;
    const unsigned long long frame_start = frames->written;
    for (;;)
    {
        if ((available - cursor) < 4ull)
        {
            return 0;
        }
        const unsigned int block_word = lz4_little_32(frame + cursor);
        cursor += 4ull;
        if (block_word == 0u)
        {
            break;
        }
        const unsigned long long block_size = block_word & ~LZ4_UNCOMPRESSED_BIT;
        if ((block_size > block_maximum) || ((available - cursor) < (block_size + block_checksum)))
        {
            return 0;
        }
        const unsigned char *const block = frame + cursor;
        if ((block_checksum != 0ull) && (lz4_little_32(block + block_size) != lz4_xxh32(block, block_size)))
        {
            return 0;
        }
        if ((block_word & LZ4_UNCOMPRESSED_BIT) != 0u)
        {
            if (block_size > (request->out_room - frames->written))
            {
                return 0;
            }
            if (block_size != 0ull)
            {
                memcpy(request->out + frames->written, block, (size_t)block_size);
            }
            frames->written += block_size;
        }
        else
        {
            const unsigned long long room_left = request->out_room - frames->written;
            const unsigned long long room = frames->written + ((room_left < block_maximum) ? room_left : block_maximum);
            Lz4Walk walk = {block, block_size, request->out, room, independent ? frames->written : frame_start, frames->written};
            const int decoded = lz4_block(&walk);
            frames->written = walk.written;
            if (!decoded)
            {
                return 0;
            }
        }
        cursor += block_size + block_checksum;
    }
    const unsigned long long produced = frames->written - frame_start;
    if (content_checksum)
    {
        if ((available - cursor) < 4ull)
        {
            return 0;
        }
        if (lz4_little_32(frame + cursor) != lz4_xxh32(request->out + frame_start, produced))
        {
            return 0;
        }
        cursor += 4ull;
    }
    if (sized && (content_size != produced))
    {
        return 0;
    }
    frames->at += cursor;
    return 1;
}

long long lz4_block_decode(const EngineBytesRequest *request)
{
    Lz4Walk walk = {request->in, request->in_bytes, request->out, request->out_room, 0ull, 0ull};
    if (!lz4_block(&walk))
    {
        return lz4_refuse(request, walk.written);
    }
    return (long long)walk.written;
}

long long lz4_frame_decode(const EngineBytesRequest *request)
{
    Lz4Frames frames = {request, 0ull, 0ull};
    int good = (request->in_bytes != 0ull);
    while (good && (frames.at < request->in_bytes))
    {
        good = lz4_frame(&frames);
    }
    if (!good)
    {
        return lz4_refuse(request, frames.written);
    }
    return (long long)frames.written;
}

long long lz4_numcodecs_decode(const EngineBytesRequest *request)
{
    if (request->in_bytes < 4ull)
    {
        return ENGINE_BYTES_REFUSED;
    }
    const unsigned long long declared = lz4_little_32(request->in);
    if (declared > request->out_room)
    {
        return ENGINE_BYTES_REFUSED;
    }
    Lz4Walk walk = {request->in + 4u, request->in_bytes - 4ull, request->out, declared, 0ull, 0ull};
    if (!lz4_block(&walk) || (walk.written != declared))
    {
        return lz4_refuse(request, walk.written);
    }
    return (long long)walk.written;
}
