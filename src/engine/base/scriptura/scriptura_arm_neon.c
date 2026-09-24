// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stddef.h>

#if ENGINE_TARGET_AARCH64

#include <arm_neon.h>
#include <stdint.h>

#define SCRIPTURA_NEON_BYTES 16u

static unsigned long long scriptura_neon_nibbles(uint8x16_t lanes)
{
    return vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(lanes), 4)), 0);
}

static unsigned long long scriptura_neon_lowest(unsigned long long nibbles)
{
    // the trailing count of a non-zero 64 bit mask is 0 to 63, and over four it is the lane index
    return (unsigned long long)((unsigned int)__builtin_ctzll(nibbles) >> 2u);
}

static unsigned long long scriptura_neon_length(const char *text, unsigned long long room)
{
    if (room == 0ull)
    {
        return 0ull;
    }
    // the address is read as an integer only for its low bits, and never converted back
    const unsigned long long past = (unsigned long long)((uintptr_t)text & (uintptr_t)(SCRIPTURA_NEON_BYTES - 1u));
    // the aligned block holding the first byte is read whole, and the lanes before the text are dropped
    const unsigned char *block = (const unsigned char *)(text - past);
    unsigned long long zeros = scriptura_neon_nibbles(vceqzq_u8(vld1q_u8(block))) >> (past * 4u);
    unsigned long long at = 0ull;
    unsigned long long seen = SCRIPTURA_NEON_BYTES - past;
    while (zeros == 0ull)
    {
        if (seen >= room)
        {
            return room;
        }
        at = seen;
        block += SCRIPTURA_NEON_BYTES;
        seen += SCRIPTURA_NEON_BYTES;
        zeros = scriptura_neon_nibbles(vceqzq_u8(vld1q_u8(block)));
    }
    const unsigned long long found = at + scriptura_neon_lowest(zeros);
    return (found < room) ? found : room;
}

static unsigned long long scriptura_neon_find(const void *from, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_NEON_BYTES)
    {
        return scriptura_portable_find(from, value, bytes);
    }
    // the region is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const uint8x16_t broadcast = vdupq_n_u8(value);
    const unsigned long long last = bytes - SCRIPTURA_NEON_BYTES;
    unsigned long long at = 0ull;
    while (at < last)
    {
        const unsigned long long matching = scriptura_neon_nibbles(vceqq_u8(vld1q_u8(source + at), broadcast));
        if (matching != 0ull)
        {
            return at + scriptura_neon_lowest(matching);
        }
        at += SCRIPTURA_NEON_BYTES;
    }
    const unsigned long long matching = scriptura_neon_nibbles(vceqq_u8(vld1q_u8(source + last), broadcast));
    return (matching != 0ull) ? (last + scriptura_neon_lowest(matching)) : bytes;
}

static void scriptura_neon_copy(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_NEON_BYTES)
    {
        scriptura_portable_copy(to, from, bytes);
        return;
    }
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long last = bytes - SCRIPTURA_NEON_BYTES;
    const uint8x16_t closing = vld1q_u8(source + last);
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_NEON_BYTES)) <= last)
    {
        const uint8x16x4_t block = vld1q_u8_x4(source + at);
        vst1q_u8_x4(target + at, block);
        at += 4u * SCRIPTURA_NEON_BYTES;
    }
    while (at < last)
    {
        vst1q_u8(target + at, vld1q_u8(source + at));
        at += SCRIPTURA_NEON_BYTES;
    }
    vst1q_u8(target + last, closing);
}

static void scriptura_neon_move_up(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_NEON_BYTES)
    {
        scriptura_portable_move_up(to, from, bytes);
        return;
    }
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const uint8x16_t opening = vld1q_u8(source);
    unsigned long long at = bytes;
    while (at > (4u * SCRIPTURA_NEON_BYTES))
    {
        at -= 4u * SCRIPTURA_NEON_BYTES;
        const uint8x16x4_t block = vld1q_u8_x4(source + at);
        vst1q_u8_x4(target + at, block);
    }
    while (at > SCRIPTURA_NEON_BYTES)
    {
        at -= SCRIPTURA_NEON_BYTES;
        vst1q_u8(target + at, vld1q_u8(source + at));
    }
    vst1q_u8(target, opening);
}

static int scriptura_neon_compare(const void *one, const void *other, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_NEON_BYTES)
    {
        return scriptura_portable_compare(one, other, bytes);
    }
    // the regions are read as unsigned bytes
    const unsigned char *const left = (const unsigned char *)one;
    // the regions are read as unsigned bytes
    const unsigned char *const right = (const unsigned char *)other;
    const unsigned long long last = bytes - SCRIPTURA_NEON_BYTES;
    unsigned long long at = 0ull;
    while (at < last)
    {
        const unsigned long long differing =
            scriptura_neon_nibbles(vmvnq_u8(vceqq_u8(vld1q_u8(left + at), vld1q_u8(right + at))));
        if (differing != 0ull)
        {
            const unsigned long long lane = at + scriptura_neon_lowest(differing);
            return (left[lane] < right[lane]) ? -1 : 1;
        }
        at += SCRIPTURA_NEON_BYTES;
    }
    const unsigned long long differing =
        scriptura_neon_nibbles(vmvnq_u8(vceqq_u8(vld1q_u8(left + last), vld1q_u8(right + last))));
    if (differing == 0ull)
    {
        return 0;
    }
    const unsigned long long lane = last + scriptura_neon_lowest(differing);
    return (left[lane] < right[lane]) ? -1 : 1;
}

static void scriptura_neon_fill(void *to, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_NEON_BYTES)
    {
        scriptura_portable_fill(to, value, bytes);
        return;
    }
    // the region is written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    const uint8x16_t spread = vdupq_n_u8(value);
    const uint8x16x4_t block = {{spread, spread, spread, spread}};
    const unsigned long long last = bytes - SCRIPTURA_NEON_BYTES;
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_NEON_BYTES)) <= last)
    {
        vst1q_u8_x4(target + at, block);
        at += 4u * SCRIPTURA_NEON_BYTES;
    }
    while (at < last)
    {
        vst1q_u8(target + at, spread);
        at += SCRIPTURA_NEON_BYTES;
    }
    vst1q_u8(target + last, spread);
}

const ScripturaArm *scriptura_neon_arm(void)
{
    static const ScripturaArm arm = {"neon-unrun",
                                     SCRIPTURA_NEON_BYTES,
                                     scriptura_neon_length,
                                     scriptura_neon_find,
                                     scriptura_neon_copy,
                                     scriptura_neon_move_up,
                                     scriptura_neon_compare,
                                     scriptura_neon_fill};
    return &arm;
}

#else

const ScripturaArm *scriptura_neon_arm(void)
{
    return NULL;
}

#endif
