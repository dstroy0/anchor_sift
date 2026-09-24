// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stdlib.h>

#define TEST_ALIGN 64u
#define TEST_LONGEST 4160u
#define TEST_SHIFTS 3u
#define TEST_BUFFER (TEST_LONGEST + 512u)
#define TEST_LENGTHS 520u
#define TEST_ARMS 5u
#define TEST_OPERATIONS 6u
#define TEST_PLANTED 0x80u
#define TEST_BACKGROUND 0xA5u
#define TEST_FILLED 0x3Cu
#define TEST_NONE 0xFFFFFFFFFFFFFFFFull
#define TEST_COLUMNS 12u

typedef struct
{
    unsigned long long cases;
    unsigned long long failures;
    unsigned long long first_failure;
} TestTally;

static _Alignas(TEST_ALIGN) unsigned char test_source[TEST_BUFFER];
static _Alignas(TEST_ALIGN) unsigned char test_other[TEST_BUFFER];
static _Alignas(TEST_ALIGN) unsigned char test_armed[TEST_BUFFER];
static _Alignas(TEST_ALIGN) unsigned char test_expected[TEST_BUFFER];

static const unsigned long long test_shifts[TEST_SHIFTS] = {64ull, 128ull, 192ull};

static const char *const test_operation_names[TEST_OPERATIONS] = {"length", "find", "copy", "move_up", "compare", "fill"};

static unsigned char test_pattern(unsigned long long index)
{
    // the top eight bits of the product are one byte, and the low bit is set so no pattern byte is zero or planted
    return (unsigned char)((((index + 1ull) * 0x9E3779B97F4A7C15ull) >> 56u) | 1ull);
}

static void test_lay(unsigned char *buffer)
{
    for (unsigned long long at = 0ull; at < TEST_BUFFER; at += 1ull)
    {
        buffer[at] = test_pattern(at);
    }
}

static void test_blank(unsigned char *buffer)
{
    for (unsigned long long at = 0ull; at < TEST_BUFFER; at += 1ull)
    {
        buffer[at] = TEST_BACKGROUND;
    }
}

static int test_same(const unsigned char *left, const unsigned char *right)
{
    for (unsigned long long at = 0ull; at < TEST_BUFFER; at += 1ull)
    {
        if (left[at] != right[at])
        {
            return 0;
        }
    }
    return 1;
}

static void test_count(TestTally *tally, int held, unsigned long long length)
{
    tally->cases += 1ull;
    if (held == 0)
    {
        tally->failures += 1ull;
        tally->first_failure = (tally->first_failure == TEST_NONE) ? length : tally->first_failure;
    }
}

static unsigned long long test_naive_length(const unsigned char *text, unsigned long long room)
{
    unsigned long long at = 0ull;
    while ((at < room) && (text[at] != 0u))
    {
        at += 1ull;
    }
    return at;
}

static unsigned long long test_naive_find(const unsigned char *source, unsigned char value, unsigned long long bytes)
{
    unsigned long long at = 0ull;
    while ((at < bytes) && (source[at] != value))
    {
        at += 1ull;
    }
    return at;
}

static int test_naive_compare(const unsigned char *left, const unsigned char *right, unsigned long long bytes)
{
    for (unsigned long long at = 0ull; at < bytes; at += 1ull)
    {
        if (left[at] != right[at])
        {
            return (left[at] < right[at]) ? -1 : 1;
        }
    }
    return 0;
}

static void test_length(const ScripturaArm *arm, TestTally *tally, unsigned long long room)
{
    const unsigned long long places[4] = {room, 0ull, (room == 0ull) ? 0ull : (room - 1ull), room / 2ull};
    for (unsigned int place = 0u; place < 4u; place += 1u)
    {
        test_lay(test_source);
        test_source[room] = 0u;
        test_source[places[place]] = 0u;
        const unsigned long long expected = test_naive_length(test_source, room);
        // the text buffer is read as the characters it holds
        const unsigned long long found = arm->length((const char *)test_source, room);
        test_count(tally, found == expected, room);
    }
}

static void test_find(const ScripturaArm *arm, TestTally *tally, unsigned long long bytes)
{
    const unsigned long long places[4] = {bytes, 0ull, (bytes == 0ull) ? 0ull : (bytes - 1ull), bytes / 2ull};
    for (unsigned int place = 0u; place < 4u; place += 1u)
    {
        test_lay(test_source);
        test_source[bytes] = TEST_PLANTED;
        test_source[places[place]] = TEST_PLANTED;
        const unsigned long long expected = test_naive_find(test_source, TEST_PLANTED, bytes);
        const unsigned long long found = arm->find(test_source, TEST_PLANTED, bytes);
        test_count(tally, found == expected, bytes);
    }
}

static void test_copy(const ScripturaArm *arm, TestTally *tally, unsigned long long bytes)
{
    test_lay(test_source);
    test_blank(test_armed);
    test_blank(test_expected);
    for (unsigned long long at = 0ull; at < bytes; at += 1ull)
    {
        test_expected[at] = test_source[at];
    }
    arm->copy(test_armed, test_source, bytes);
    test_count(tally, test_same(test_armed, test_expected), bytes);
}

static void test_move_up(const ScripturaArm *arm, TestTally *tally, unsigned long long bytes)
{
    for (unsigned int shift = 0u; shift < TEST_SHIFTS; shift += 1u)
    {
        const unsigned long long by = test_shifts[shift];
        test_lay(test_armed);
        test_lay(test_expected);
        for (unsigned long long at = bytes; at > 0ull; at -= 1ull)
        {
            test_expected[at - 1ull + by] = test_expected[at - 1ull];
        }
        arm->move_up(test_armed + by, test_armed, bytes);
        test_count(tally, test_same(test_armed, test_expected), bytes);
    }
}

static void test_compare(const ScripturaArm *arm, TestTally *tally, unsigned long long bytes)
{
    test_lay(test_source);
    test_lay(test_other);
    test_count(tally, arm->compare(test_source, test_other, bytes) == 0, bytes);
    const unsigned long long places[3] = {0ull, (bytes == 0ull) ? 0ull : (bytes - 1ull), bytes / 2ull};
    for (unsigned int place = 0u; (place < 3u) && (bytes != 0ull); place += 1u)
    {
        test_lay(test_other);
        test_other[places[place]] = TEST_PLANTED;
        const int below = test_naive_compare(test_source, test_other, bytes);
        test_count(tally, arm->compare(test_source, test_other, bytes) == below, bytes);
        test_count(tally, arm->compare(test_other, test_source, bytes) == -below, bytes);
    }
}

static void test_fill(const ScripturaArm *arm, TestTally *tally, unsigned long long bytes)
{
    test_blank(test_armed);
    test_blank(test_expected);
    for (unsigned long long at = 0ull; at < bytes; at += 1ull)
    {
        test_expected[at] = TEST_FILLED;
    }
    arm->fill(test_armed, TEST_FILLED, bytes);
    test_count(tally, test_same(test_armed, test_expected), bytes);
}

static unsigned int test_lengths(unsigned long long *lengths)
{
    unsigned int count = 0u;
    for (unsigned long long length = 0ull; length <= 320ull; length += 1ull)
    {
        lengths[count] = length;
        count += 1u;
    }
    for (unsigned long long length = 1000ull; length <= 1090ull; length += 1ull)
    {
        lengths[count] = length;
        count += 1u;
    }
    for (unsigned long long length = 4090ull; length <= TEST_LONGEST; length += 1ull)
    {
        lengths[count] = length;
        count += 1u;
    }
    return count;
}

int main(void)
{
    const ScripturaArm *const arms[TEST_ARMS] = {scriptura_portable_arm(), scriptura_avx2_arm(), scriptura_avx512_arm(),
                                                 scriptura_neon_arm(), scriptura_sve_arm()};
    const char *const arm_names[TEST_ARMS] = {"portable", "avx2", "avx512", "neon", "sve"};
    _Static_assert((321u + 91u + 71u) <= TEST_LENGTHS, "scriptura_arm_test: the length list must fit its array");
    unsigned long long lengths[TEST_LENGTHS];
    const unsigned int length_count = test_lengths(lengths);
    const unsigned long long room = 8192ull;
    ScripturaLine line = {(char *)malloc((size_t)room), room, 0ull};
    if (line.out == NULL)
    {
        return 2;
    }
    scriptura_text(&line, "scriptura arms, chosen ");
    scriptura_text(&line, scriptura_arm());
    scriptura_character(&line, '\n');
    unsigned long long failures = 0ull;
    for (unsigned int index = 0u; index < TEST_ARMS; index += 1u)
    {
        const ScripturaArm *const arm = arms[index];
        if (arm == NULL)
        {
            scriptura_text_columns(&line, arm_names[index], TEST_COLUMNS);
            scriptura_text(&line, "absent on this cpu or build\n");
            continue;
        }
        for (unsigned int operation = 0u; operation < TEST_OPERATIONS; operation += 1u)
        {
            TestTally tally = {0ull, 0ull, TEST_NONE};
            for (unsigned int at = 0u; at < length_count; at += 1u)
            {
                const unsigned long long length = lengths[at];
                if (operation == 0u)
                {
                    test_length(arm, &tally, length);
                }
                else if (operation == 1u)
                {
                    test_find(arm, &tally, length);
                }
                else if (operation == 2u)
                {
                    test_copy(arm, &tally, length);
                }
                else if (operation == 3u)
                {
                    test_move_up(arm, &tally, length);
                }
                else if (operation == 4u)
                {
                    test_compare(arm, &tally, length);
                }
                else
                {
                    test_fill(arm, &tally, length);
                }
            }
            failures += tally.failures;
            scriptura_text_columns(&line, arm->name, TEST_COLUMNS);
            scriptura_text_columns(&line, test_operation_names[operation], TEST_COLUMNS);
            scriptura_decimal_columns(&line, tally.cases, 8u);
            scriptura_text(&line, (tally.failures == 0ull) ? " agrees" : " DISAGREES ");
            if (tally.failures != 0ull)
            {
                scriptura_decimal(&line, tally.failures, 1u);
                scriptura_text(&line, " first at length ");
                scriptura_decimal(&line, tally.first_failure, 1u);
            }
            scriptura_character(&line, '\n');
        }
    }
    const int written = scriptura_write(&line, stdout);
    free(line.out);
    return ((written != 0) && (failures == 0ull)) ? 0 : 1;
}
