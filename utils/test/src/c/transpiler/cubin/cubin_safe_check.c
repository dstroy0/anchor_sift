// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cubin_safe_check.c: cubin_safe held to one case a rule, each made from the machine file's own forms, then every cubin
// named read on the host and its verdict printed. Nothing here touches a device.
//
//     cubin_safe_check <machine file> [<cubin>...]
//
// One line a case and a cubin, and a last line with the checks. Exit 0 where every case gives its rule's verdict, 1
// where one does not, 2 where the machine file did not read. A cubin's verdict is reported and is no check: a cubin
// held off the part is the gate doing its work.
#include "../../../../../../src/c/transpiler/cubin/cubin_safe.h"
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"

#include <stdio.h>
#include <string.h>

#define CHECK_CUBIN_BYTES 1048576u
#define CHECK_CODE_INSTRUCTIONS 4u

static SassMachine s_machine;
static unsigned char s_image[CHECK_CUBIN_BYTES];
static unsigned char s_code[16u * CHECK_CODE_INSTRUCTIONS];
static unsigned int s_checks;
static unsigned int s_failed;

static void check_put(unsigned char *bytes, unsigned long long value)
{
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        bytes[byte] = (unsigned char)((value >> (8u * byte)) & 0xffu);
    }
}

// `high` with its scheduler's bits set to the safe word's stall and wait, its barriers set to none
static unsigned long long check_safe_high(unsigned long long high)
{
    const unsigned long long scheduler = ~0ull << (SASS_STALL_FIRST - 64u);
    high &= ~scheduler;
    high |= (unsigned long long)SASS_STALL_LONGEST << (SASS_STALL_FIRST - 64u);
    high |= (unsigned long long)SASS_BARRIER_NONE << (SASS_WRITE_BARRIER_FIRST - 64u);
    high |= (unsigned long long)SASS_BARRIER_NONE << (SASS_READ_BARRIER_FIRST - 64u);
    high |= (unsigned long long)SASS_WAIT_EVERY << (SASS_WAIT_FIRST - 64u);
    return high;
}

// the instruction at `place` of s_code set to `low` and `high`
static void check_instruction(unsigned int place, unsigned long long low, unsigned long long high)
{
    check_put(&s_code[16u * place], low);
    check_put(&s_code[(16u * place) + 8u], high);
}

static void check_verdict(const char *name, unsigned int instructions, unsigned int wanted)
{
    unsigned long long at = 0ull;
    const unsigned int verdict = cubin_safe(&s_machine, s_code, 16ull * instructions, &at);
    s_checks += 1u;
    if (verdict != wanted)
    {
        s_failed += 1u;
    }
    printf("  %s %s: %s at %llu, where %s was wanted\n", (verdict == wanted) ? "held" : "FAILED", name,
           cubin_safe_name(verdict), at, cubin_safe_name(wanted));
}

// the first form of the machine whose operation is `operation`, or NULL
static const SassForm *check_form(const char *operation)
{
    for (unsigned int at = 0u; at < s_machine.forms; at += 1u)
    {
        if (strcmp(s_machine.form[at].operation, operation) == 0)
        {
            return &s_machine.form[at];
        }
    }
    return NULL;
}

// the form of the machine seen as the instruction `text`, or NULL
static const SassForm *check_form_seen(const char *text)
{
    for (unsigned int at = 0u; at < s_machine.forms; at += 1u)
    {
        if (strcmp(s_machine.form[at].text, text) == 0)
        {
            return &s_machine.form[at];
        }
    }
    return NULL;
}

// `low` with its guard set to PT, the predicate always true: three bits of its number at 12 and the negation at 15
static unsigned long long check_unguarded(unsigned long long low)
{
    return (low & ~0xf000ull) | 0x7000ull;
}

// 1 where some form of the machine sits under the operation key `key`
static int check_key_known(unsigned long long key)
{
    for (unsigned int at = 0u; at < s_machine.forms; at += 1u)
    {
        if ((s_machine.form[at].low & SASS_OPERATION_MASK) == key)
        {
            return 1;
        }
    }
    return 0;
}

// an encoding of `form` with one operation bit past the key turned that no form holds, through `low`: 1, or 0 where
// every such turn is held by some form
static int check_unheld(const SassForm *form, unsigned long long *low)
{
    char text[256];
    for (unsigned int bit = 12u; bit < 64u; bit += 1u)
    {
        const unsigned long long turned = form->low ^ (1ull << bit);
        if (!sass_encoding_read(&s_machine, turned, check_safe_high(form->high), 0ull, text, sizeof(text)))
        {
            *low = turned;
            return 1;
        }
    }
    return 0;
}

static void check_cases(void)
{
    const SassForm *const exit = check_form("EXIT");
    const SassForm *const branch = check_form("BRA");
    const SassForm *const straight = check_form("IADD3");
    if ((exit == NULL) || (branch == NULL) || (straight == NULL))
    {
        s_checks += 1u;
        s_failed += 1u;
        printf("  FAILED: the machine file holds no EXIT, BRA or IADD3 to make the cases from\n");
        return;
    }
    // the machine file saw EXIT under a guard; every case's EXIT is given PT, which every thread takes
    const unsigned long long exit_low = check_unguarded(exit->low);
    const unsigned long long exit_high = check_safe_high(exit->high);
    check_instruction(0u, exit_low, exit_high);
    check_verdict("an EXIT alone", 1u, CUBIN_SAFE);
    check_verdict("no instruction", 0u, CUBIN_SAFE_SIZE);
    check_instruction(0u, exit->low, exit_high);
    check_verdict("an EXIT under @P0 and nothing after it", 1u, CUBIN_SAFE_EXIT);
    const SassForm *const never = check_form_seen("@P0 EXIT !PT");
    if (never != NULL)
    {
        check_instruction(0u, check_unguarded(never->low), check_safe_high(never->high));
        check_verdict("EXIT !PT, which no thread takes", 1u, CUBIN_SAFE_EXIT);
    }
    check_instruction(0u, exit_low, exit_high & ~(0xfull << (SASS_STALL_FIRST - 64u)));
    check_verdict("an EXIT with no stall", 1u, CUBIN_SAFE_STALL);
    check_instruction(0u, exit_low, exit_high & ~(0x3full << (SASS_WAIT_FIRST - 64u)));
    check_verdict("an EXIT waiting on nothing", 1u, CUBIN_SAFE_WAIT);
    check_instruction(0u, branch->low, check_safe_high(branch->high));
    check_instruction(1u, exit_low, exit_high);
    check_verdict("a branch before the EXIT", 2u, CUBIN_SAFE_CONTROL);
    check_instruction(0u, straight->low, check_safe_high(straight->high));
    check_verdict("an IADD3 with no EXIT after it", 1u, CUBIN_SAFE_EXIT);
    check_instruction(1u, exit_low, exit_high);
    check_verdict("an IADD3 then an EXIT", 2u, CUBIN_SAFE);
    // the self branch past the last exit is never reached and is not read
    check_instruction(0u, exit_low, exit_high);
    check_instruction(1u, branch->low, branch->high);
    check_verdict("an EXIT then the self branch", 2u, CUBIN_SAFE);
    unsigned long long unheld = 0ull;
    if (check_unheld(straight, &unheld))
    {
        check_instruction(0u, unheld, check_safe_high(straight->high));
        check_instruction(1u, exit_low, exit_high);
        check_verdict("one instruction no form holds, then an EXIT", 2u, CUBIN_SAFE);
        check_instruction(1u, unheld, check_safe_high(straight->high));
        check_instruction(2u, exit_low, exit_high);
        check_verdict("two instructions no form holds", 3u, CUBIN_SAFE_UNHELD);
    }
    for (unsigned long long key = 0ull; key <= SASS_OPERATION_MASK; key += 1ull)
    {
        if (!check_key_known(key))
        {
            check_instruction(0u, (straight->low & ~SASS_OPERATION_MASK) | key, check_safe_high(straight->high));
            check_instruction(1u, exit_low, exit_high);
            check_verdict("an operation key no form sits under", 2u, CUBIN_SAFE_KEY);
            break;
        }
    }
}

int main(int count, char **words)
{
    if ((count < 2) || !sass_machine_read(&s_machine, words[1]))
    {
        fprintf(stderr, "cubin_safe_check <machine file> [<cubin>...]\n");
        return 2;
    }
    check_cases();
    unsigned int safe = 0u;
    for (int at = 2; at < count; at += 1)
    {
        FILE *const file = fopen(words[at], "rb");
        const size_t size = (file != NULL) ? fread(s_image, 1u, sizeof(s_image), file) : 0u;
        if (file != NULL)
        {
            fclose(file);
        }
        unsigned long long where = 0ull;
        const unsigned int verdict = cubin_safe_image(&s_machine, s_image, size, &where);
        safe += (verdict == CUBIN_SAFE) ? 1u : 0u;
        printf("  %s: %s at byte %llu\n", words[at], cubin_safe_name(verdict), where);
    }
    if (count > 2)
    {
        printf("  %u of %d cubins safe to put to the part\n", safe, count - 2);
    }
    printf("cubin safe check: %u checks, %u failed\n", s_checks, s_failed);
    return (s_failed == 0u) ? 0 : 1;
}
