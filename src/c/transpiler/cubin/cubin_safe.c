// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cubin_safe.c: each instruction a kernel reaches read with our own reader and held to the rules in cubin_safe.h
#include "cubin_safe.h"

#include "cubin_write.h"
#include "sass_assemble.h"

#include <string.h>

// the four bits of the stall and the six of the wait, counted from the high word's first bit
#define CUBIN_STALL_SHIFT (SASS_STALL_FIRST - 64u)
#define CUBIN_WAIT_SHIFT (SASS_WAIT_FIRST - 64u)
// the most code sections one image is read for: a kernel and the functions it calls
#define CUBIN_SAFE_SECTIONS 64u

static unsigned long long cubin_word(const unsigned char *bytes)
{
    unsigned long long value = 0ull;
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        value |= (unsigned long long)bytes[byte] << (8u * byte);
    }
    return value;
}

// 1 where `machine` holds a form under the operation key of `low` and none of its forms there transfers control or
// waits
static int cubin_key_straight(const SassMachine *machine, unsigned long long low)
{
    const unsigned long long key = low & SASS_OPERATION_MASK;
    int known = 0;
    for (unsigned int at = 0u; at < machine->forms; at += 1u)
    {
        if ((machine->form[at].low & SASS_OPERATION_MASK) != key)
        {
            continue;
        }
        if (sass_operation_control_or_wait(machine->form[at].operation))
        {
            return 0;
        }
        known = 1;
    }
    return known;
}

// 1 where `parts` is an EXIT, its modifiers whatever they are
static int cubin_exit(const SassInstructionParts *parts)
{
    return (strncmp(parts->operation, "EXIT", 4u) == 0) && ((parts->operation[4] == '\0') || (parts->operation[4] == '.'));
}

// 1 where the EXIT `parts` is taken by every thread that reaches it: no guard, and every operand it prints PT with
// no mark, the predicate always true. `EXIT !PT` is never taken and `EXIT P6` only where P6 holds
static int cubin_exit_ends(const SassInstructionParts *parts)
{
    if (parts->guard[0] != '\0')
    {
        return 0;
    }
    for (unsigned int operand = 0u; operand < parts->operands; operand += 1u)
    {
        if ((strcmp(parts->operand[operand], "PT") != 0) || (parts->mark[operand] != SASS_MARK_NONE))
        {
            return 0;
        }
    }
    return 1;
}

unsigned int cubin_safe(const SassMachine *machine, const unsigned char *code, unsigned long long code_size,
                        unsigned long long *at)
{
    *at = 0ull;
    if ((code_size == 0ull) || ((code_size % 16ull) != 0ull))
    {
        return CUBIN_SAFE_SIZE;
    }
    unsigned int unheld = 0u;
    for (unsigned long long place = 0ull; place < code_size; place += 16ull)
    {
        *at = place;
        const unsigned long long low = cubin_word(&code[place]);
        const unsigned long long high = cubin_word(&code[place + 8u]);
        if (((high >> CUBIN_STALL_SHIFT) & 0xfull) != SASS_STALL_LONGEST)
        {
            return CUBIN_SAFE_STALL;
        }
        if (((high >> CUBIN_WAIT_SHIFT) & 0x3full) != SASS_WAIT_EVERY)
        {
            return CUBIN_SAFE_WAIT;
        }
        char text[256];
        if (!sass_encoding_read(machine, low, high, place, text, sizeof(text)))
        {
            if (!cubin_key_straight(machine, low))
            {
                return CUBIN_SAFE_KEY;
            }
            unheld += 1u;
            if (unheld > 1u)
            {
                return CUBIN_SAFE_UNHELD;
            }
            continue;
        }
        SassInstructionParts parts;
        sass_instruction_read(text, &parts);
        if (cubin_exit(&parts))
        {
            // an EXIT with no guard and no predicate of its own but PT ends every thread that reaches it, and nothing
            // past it runs
            if (cubin_exit_ends(&parts))
            {
                return CUBIN_SAFE;
            }
            continue;
        }
        if (sass_operation_control_or_wait(parts.operation))
        {
            return CUBIN_SAFE_CONTROL;
        }
    }
    return CUBIN_SAFE_EXIT;
}

unsigned int cubin_safe_image(const SassMachine *machine, const unsigned char *image, unsigned long long size,
                              unsigned long long *at)
{
    unsigned long long offsets[CUBIN_SAFE_SECTIONS];
    unsigned long long sizes[CUBIN_SAFE_SECTIONS];
    const unsigned int sections = cubin_code_sections(image, size, offsets, sizes, CUBIN_SAFE_SECTIONS);
    *at = 0ull;
    if (sections == 0u)
    {
        return CUBIN_SAFE_SIZE;
    }
    for (unsigned int section = 0u; section < sections; section += 1u)
    {
        unsigned long long inside = 0ull;
        const unsigned int verdict = cubin_safe(machine, &image[offsets[section]], sizes[section], &inside);
        if (verdict != CUBIN_SAFE)
        {
            *at = offsets[section] + inside;
            return verdict;
        }
    }
    return CUBIN_SAFE;
}

const char *cubin_safe_name(unsigned int verdict)
{
    static const char *const s_names[] = {"safe",
                                          "not a whole count of instructions",
                                          "a stall short of the longest",
                                          "a wait short of all six barriers",
                                          "a control transfer or a wait",
                                          "an operation key unknown or holding a control transfer or a wait",
                                          "a second instruction no form holds",
                                          "no EXIT without a guard"};
    return (verdict < (sizeof(s_names) / sizeof(s_names[0]))) ? s_names[verdict] : "unknown";
}
