// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stdint.h>

static unsigned long long scriptura_portable_lead(const void *at, unsigned long long bytes)
{
    // the address is read as an integer only for its low bits, and never converted back
    const unsigned long long past = (unsigned long long)((uintptr_t)at & (uintptr_t)(SCRIPTURA_WORD_BYTES - 1u));
    const unsigned long long to_boundary = (past == 0ull) ? 0ull : (SCRIPTURA_WORD_BYTES - past);
    return (to_boundary < bytes) ? to_boundary : bytes;
}

static unsigned long long scriptura_portable_differ(unsigned long long difference)
{
    return SCRIPTURA_HIGH & ~scriptura_lane_zero(difference);
}

unsigned long long scriptura_portable_length(const char *text, unsigned long long room)
{
    // the text is read as unsigned bytes
    const unsigned char *const bytes = (const unsigned char *)text;
    const unsigned long long lead = scriptura_portable_lead(bytes, room);
    const unsigned long long full = lead + (((room - lead) / SCRIPTURA_WORD_BYTES) * SCRIPTURA_WORD_BYTES);
    const unsigned long long rest = room - full;
    unsigned long long at = 0ull;
    while (at != lead)
    {
        if (bytes[at] == 0u)
        {
            return at;
        }
        at += 1ull;
    }
    while (at != full)
    {
        const unsigned long long zeros = scriptura_lane_zero(scriptura_word_load(bytes + at));
        if (zeros != 0ull)
        {
            return at + scriptura_lane_lowest(zeros);
        }
        at += SCRIPTURA_WORD_BYTES;
    }
    if (rest != 0ull)
    {
        const unsigned long long zeros = scriptura_lane_zero(scriptura_word_load(bytes + at))
                                       & scriptura_mask_lanes_below(rest);
        if (zeros != 0ull)
        {
            return at + scriptura_lane_lowest(zeros);
        }
    }
    return room;
}

unsigned long long scriptura_portable_find(const void *from, unsigned char value, unsigned long long bytes)
{
    // the region is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long lead = scriptura_portable_lead(source, bytes);
    const unsigned long long full = lead + (((bytes - lead) / SCRIPTURA_WORD_BYTES) * SCRIPTURA_WORD_BYTES);
    const unsigned long long rest = bytes - full;
    const unsigned long long broadcast = SCRIPTURA_ONES * value;
    unsigned long long at = 0ull;
    while (at != lead)
    {
        if (source[at] == value)
        {
            return at;
        }
        at += 1ull;
    }
    while (at != full)
    {
        const unsigned long long matching = scriptura_lane_zero(scriptura_word_load(source + at) ^ broadcast);
        if (matching != 0ull)
        {
            return at + scriptura_lane_lowest(matching);
        }
        at += SCRIPTURA_WORD_BYTES;
    }
    if (rest != 0ull)
    {
        const unsigned long long matching = scriptura_lane_zero(scriptura_word_load(source + at) ^ broadcast)
                                          & scriptura_mask_lanes_below(rest);
        if (matching != 0ull)
        {
            return at + scriptura_lane_lowest(matching);
        }
    }
    return bytes;
}

static void scriptura_portable_copy_short(unsigned char *target, const unsigned char *source, unsigned long long bytes)
{
    if (bytes >= SCRIPTURA_WORD_BYTES)
    {
        const unsigned long long half = (bytes > (2ull * SCRIPTURA_WORD_BYTES)) ? SCRIPTURA_WORD_BYTES : 0ull;
        const unsigned long long zeroth = scriptura_word_load(source);
        const unsigned long long first = scriptura_word_load(source + half);
        const unsigned long long second = scriptura_word_load(source + (bytes - SCRIPTURA_WORD_BYTES - half));
        const unsigned long long third = scriptura_word_load(source + (bytes - SCRIPTURA_WORD_BYTES));
        scriptura_word_store(target, zeroth);
        scriptura_word_store(target + half, first);
        scriptura_word_store(target + (bytes - SCRIPTURA_WORD_BYTES - half), second);
        scriptura_word_store(target + (bytes - SCRIPTURA_WORD_BYTES), third);
    }
    else if (bytes >= 4ull)
    {
        unsigned int opening = 0u;
        unsigned int closing = 0u;
        memcpy(&opening, source, 4u);
        memcpy(&closing, source + (bytes - 4ull), 4u);
        memcpy(target, &opening, 4u);
        memcpy(target + (bytes - 4ull), &closing, 4u);
    }
    else if (bytes != 0ull)
    {
        const unsigned char first = source[0];
        const unsigned char middle = source[bytes / 2ull];
        const unsigned char last = source[bytes - 1ull];
        target[0] = first;
        target[bytes / 2ull] = middle;
        target[bytes - 1ull] = last;
    }
}

static void scriptura_portable_block_copy(unsigned char *target, const unsigned char *source)
{
    const unsigned long long zeroth = scriptura_word_load(source);
    const unsigned long long first = scriptura_word_load(source + SCRIPTURA_WORD_BYTES);
    const unsigned long long second = scriptura_word_load(source + (2u * SCRIPTURA_WORD_BYTES));
    const unsigned long long third = scriptura_word_load(source + (3u * SCRIPTURA_WORD_BYTES));
    scriptura_word_store(target, zeroth);
    scriptura_word_store(target + SCRIPTURA_WORD_BYTES, first);
    scriptura_word_store(target + (2u * SCRIPTURA_WORD_BYTES), second);
    scriptura_word_store(target + (3u * SCRIPTURA_WORD_BYTES), third);
}

ENGINE_NOINLINE static void scriptura_portable_copy_long(unsigned char *target, const unsigned char *source,
                                                         unsigned long long bytes)
{
    const unsigned long long last = bytes - (4ull * SCRIPTURA_WORD_BYTES);
    unsigned long long at = 0ull;
    while (at < last)
    {
        scriptura_portable_block_copy(target + at, source + at);
        at += 4ull * SCRIPTURA_WORD_BYTES;
    }
    scriptura_portable_block_copy(target + last, source + last);
}

void scriptura_portable_copy(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    if (bytes <= (4ull * SCRIPTURA_WORD_BYTES))
    {
        scriptura_portable_copy_short(target, source, bytes);
        return;
    }
    scriptura_portable_copy_long(target, source, bytes);
}

ENGINE_NOINLINE static void scriptura_portable_move_up_long(unsigned char *target, const unsigned char *source,
                                                            unsigned long long bytes)
{
    const unsigned long long zeroth = scriptura_word_load(source);
    const unsigned long long first = scriptura_word_load(source + SCRIPTURA_WORD_BYTES);
    const unsigned long long second = scriptura_word_load(source + (2u * SCRIPTURA_WORD_BYTES));
    const unsigned long long third = scriptura_word_load(source + (3u * SCRIPTURA_WORD_BYTES));
    unsigned long long at = bytes;
    while (at > (4ull * SCRIPTURA_WORD_BYTES))
    {
        at -= 4ull * SCRIPTURA_WORD_BYTES;
        scriptura_portable_block_copy(target + at, source + at);
    }
    scriptura_word_store(target, zeroth);
    scriptura_word_store(target + SCRIPTURA_WORD_BYTES, first);
    scriptura_word_store(target + (2u * SCRIPTURA_WORD_BYTES), second);
    scriptura_word_store(target + (3u * SCRIPTURA_WORD_BYTES), third);
}

void scriptura_portable_move_up(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    if (bytes <= (4ull * SCRIPTURA_WORD_BYTES))
    {
        scriptura_portable_copy_short(target, source, bytes);
        return;
    }
    scriptura_portable_move_up_long(target, source, bytes);
}

int scriptura_portable_compare(const void *one, const void *other, unsigned long long bytes)
{
    // the regions are read as unsigned bytes
    const unsigned char *const left = (const unsigned char *)one;
    // the regions are read as unsigned bytes
    const unsigned char *const right = (const unsigned char *)other;
    const unsigned long long full = (bytes / SCRIPTURA_WORD_BYTES) * SCRIPTURA_WORD_BYTES;
    const unsigned long long rest = bytes - full;
    unsigned long long at = 0ull;
    while (at != full)
    {
        const unsigned long long left_word = scriptura_word_load(left + at);
        const unsigned long long right_word = scriptura_word_load(right + at);
        if (left_word != right_word)
        {
            const unsigned long long lane = at + scriptura_lane_lowest(scriptura_portable_differ(left_word ^ right_word));
            return (left[lane] < right[lane]) ? -1 : 1;
        }
        at += SCRIPTURA_WORD_BYTES;
    }
    if (rest != 0ull)
    {
        const unsigned long long differing = scriptura_portable_differ(scriptura_word_load(left + at)
                                                                        ^ scriptura_word_load(right + at))
                                           & scriptura_mask_lanes_below(rest);
        if (differing != 0ull)
        {
            const unsigned long long lane = at + scriptura_lane_lowest(differing);
            return (left[lane] < right[lane]) ? -1 : 1;
        }
    }
    return 0;
}

static void scriptura_portable_block_fill(unsigned char *target, unsigned long long spread)
{
    scriptura_word_store(target, spread);
    scriptura_word_store(target + SCRIPTURA_WORD_BYTES, spread);
    scriptura_word_store(target + (2u * SCRIPTURA_WORD_BYTES), spread);
    scriptura_word_store(target + (3u * SCRIPTURA_WORD_BYTES), spread);
}

ENGINE_NOINLINE static void scriptura_portable_fill_long(unsigned char *target, unsigned long long spread,
                                                         unsigned long long bytes)
{
    const unsigned long long last = bytes - (4ull * SCRIPTURA_WORD_BYTES);
    unsigned long long at = 0ull;
    while (at < last)
    {
        scriptura_portable_block_fill(target + at, spread);
        at += 4ull * SCRIPTURA_WORD_BYTES;
    }
    scriptura_portable_block_fill(target + last, spread);
}

void scriptura_portable_fill(void *to, unsigned char value, unsigned long long bytes)
{
    // the region is written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    if (bytes < SCRIPTURA_WORD_BYTES)
    {
        if (bytes >= 4ull)
        {
            const unsigned int half_spread = 0x01010101u * value;
            memcpy(target, &half_spread, 4u);
            memcpy(target + (bytes - 4ull), &half_spread, 4u);
        }
        else if (bytes != 0ull)
        {
            target[0] = value;
            target[bytes / 2ull] = value;
            target[bytes - 1ull] = value;
        }
        return;
    }
    const unsigned long long spread = SCRIPTURA_ONES * value;
    if (bytes <= (4ull * SCRIPTURA_WORD_BYTES))
    {
        const unsigned long long half = (bytes > (2ull * SCRIPTURA_WORD_BYTES)) ? SCRIPTURA_WORD_BYTES : 0ull;
        scriptura_word_store(target, spread);
        scriptura_word_store(target + half, spread);
        scriptura_word_store(target + (bytes - SCRIPTURA_WORD_BYTES - half), spread);
        scriptura_word_store(target + (bytes - SCRIPTURA_WORD_BYTES), spread);
        return;
    }
    scriptura_portable_fill_long(target, spread, bytes);
}

const ScripturaArm *scriptura_portable_arm(void)
{
    static const ScripturaArm arm = {"portable",
                                     SCRIPTURA_WORD_BYTES,
                                     scriptura_portable_length,
                                     scriptura_portable_find,
                                     scriptura_portable_copy,
                                     scriptura_portable_move_up,
                                     scriptura_portable_compare,
                                     scriptura_portable_fill};
    return &arm;
}
