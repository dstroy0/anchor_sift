// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_check.c: one kernel's text found in what a toolchain printed, and every form of the machine
// assembled again and read back, which says whether a form carries what the part read from it (sass_machine.h)
#include "interface_sass_probe.h"

#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <string.h>

unsigned int sass_text_read(const char *output, const char *kernel, char *text, unsigned int room)
{
    char wanted[256];
    snprintf(wanted, sizeof(wanted), ".text.%s,", kernel);
    unsigned int at = 0u;
    int inside = 0;
    const char *walk = output;
    while ((walk != NULL) && (*walk != '\0'))
    {
        const size_t length = strcspn(walk, "\n");
        char line[SASS_TEXT * 2u];
        const size_t taken = (length < (sizeof(line) - 1u)) ? length : (sizeof(line) - 1u);
        memcpy(line, walk, taken);
        line[taken] = '\0';
        // the disassembler's output ends its lines the way the host does, and a carriage return is none of the text
        line[strcspn(line, "\r")] = '\0';
        walk += length + ((walk[length] == '\n') ? 1u : 0u);
        // a listing holds a section a function, and only the kernel's own is written back. .sectioninfo names no
        // section, and the name it shares the front of is not a line that opens one
        const char *const section = strstr(line, ".section");
        if ((section != NULL) && ((section[8] == ' ') || (section[8] == '\t')))
        {
            inside = (strstr(line, wanted) != NULL) ? 1 : 0;
            continue;
        }
        if (inside == 0)
        {
            continue;
        }
        const char *const address = strstr(line, "/*");
        const char *keep = NULL;
        size_t kept = 0u;
        if ((address != NULL) && (strlen(address) > 8u) && (address[6] == '*') && (address[7] == '/'))
        {
            // an instruction: its text lies past the address, /*0000*/, and before the encoding printed after it
            keep = address + 8;
            const char *const encoding = strstr(keep, "/*");
            kept = (encoding != NULL) ? (size_t)(encoding - keep) : strlen(keep);
        }
        else if ((line[0] == '.') && (line[strlen(line) - 1u] == ':'))
        {
            keep = line;
            kept = strlen(line);
        }
        if (keep == NULL)
        {
            continue;
        }
        while ((kept != 0u) && ((keep[kept - 1u] == ' ') || (keep[kept - 1u] == ';')))
        {
            kept -= 1u;
        }
        while ((kept != 0u) && (*keep == ' '))
        {
            keep += 1;
            kept -= 1u;
        }
        if ((kept != 0u) && ((at + kept + 1u) < room))
        {
            memcpy(&text[at], keep, kept);
            at += (unsigned int)kept;
            text[at] = '\n';
            at += 1u;
        }
    }
    text[at] = '\0';
    return at;
}

// the most instructions one check decodes at a time
#define SASS_CHECK_BLOCK 400u

static unsigned long long s_check_low[SASS_CHECK_BLOCK];
static unsigned long long s_check_high[SASS_CHECK_BLOCK];
static char s_check_texts[SASS_CHECK_BLOCK][SASS_TEXT];
static char s_check_asked[SASS_CHECK_BLOCK][SASS_TEXT];

// `text` with .reuse cut out of it, into `without`: reuse lies in the scheduler's bits, which the text does not carry
static void sass_reuse_cut(const char *text, char *without, size_t room)
{
    size_t at = 0u;
    for (const char *walk = text; (*walk != '\0') && (at < (room - 1u)); walk += 1)
    {
        if (strncmp(walk, ".reuse", 6u) == 0)
        {
            walk += 5;
            continue;
        }
        without[at] = *walk;
        at += 1u;
    }
    without[at] = '\0';
}

unsigned int sass_machine_check(const SassMachine *machine, const SassListing *listing, const char *architecture,
                               const char *folder, SassCheck *tally, unsigned int report)
{
    unsigned int filled = 0u;
    unsigned int differed = 0u;
    for (unsigned int number = 0u; number <= listing->count; number += 1u)
    {
        const SassInstruction *const instruction = &listing->instructions[number];
        const int listed = (number < listing->count) && ((instruction->low != 0ull) || (instruction->high != 0ull));
        if (listed)
        {
            tally->checked += 1u;
            unsigned long long low = 0ull;
            unsigned long long high = 0ull;
            // a branch counts its target from itself, and a listing's own branch names where it stands
            if (!sass_assemble(machine, instruction->text, instruction->address, instruction->address,
                               SASS_CONTROL_BASE, &low, &high))
            {
                tally->refused += 1u;
                differed += 1u;
                continue;
            }
            // the scheduler's bits are none of the text's, and the form carries whatever they were when it was seen
            const unsigned long long control = 0xfffffe0000000000ull;
            const int same_bits =
                (low == instruction->low) && ((high | control) == (instruction->high | control));
            tally->same_bits += same_bits ? 1u : 0u;
            SassInstructionParts parts;
            sass_instruction_read(instruction->text, &parts);
            int by_bytes = 0;
            for (unsigned int place = 0u; place < parts.operands; place += 1u)
            {
                by_bytes = by_bytes || (parts.kind[place] == SASS_OPERAND_LABEL) ||
                           (parts.kind[place] == SASS_OPERAND_UNKNOWN);
            }
            // a branch counts its target from where it stands, and a relocated operand is not in the instruction at
            // all: the loader puts it there, and the listing prints what the ELF says it will be. Neither reads back
            // from the bytes alone. For those the bytes are all that can be filled to the listing
            if (by_bytes)
            {
                tally->by_bytes += 1u;
                differed += same_bits ? 0u : 1u;
                if (!same_bits && (differed <= report))
                {
                    printf("  check: %s\n    assembled 0x%016llx 0x%016llx\n    listed    0x%016llx 0x%016llx\n",
                           instruction->text, low, high, instruction->low, instruction->high);
                }
                continue;
            }
            s_check_low[filled] = low;
            s_check_high[filled] = high;
            snprintf(s_check_asked[filled], SASS_TEXT, "%s", instruction->text);
            filled += 1u;
        }
        // the block decoded whenever it is full, and at the end of the listing
        if ((filled == SASS_CHECK_BLOCK) || ((number == listing->count) && (filled != 0u)))
        {
            char path[1024];
            snprintf(path, sizeof(path), "%s/written", folder);
            if (!sass_decode(architecture, path, s_check_low, s_check_high, filled, s_check_texts))
            {
                tally->refused += filled;
                return differed + filled;
            }
            for (unsigned int at = 0u; at < filled; at += 1u)
            {
                char asked[SASS_TEXT];
                char read[SASS_TEXT];
                sass_reuse_cut(s_check_asked[at], asked, sizeof(asked));
                sass_reuse_cut(s_check_texts[at], read, sizeof(read));
                const int same = (strcmp(asked, read) == 0);
                tally->same_text += same ? 1u : 0u;
                differed += same ? 0u : 1u;
                if (!same && (differed <= report))
                {
                    printf("  check: asked %s\n         read  %s\n", asked, read);
                }
            }
            filled = 0u;
        }
    }
    return differed;
}
