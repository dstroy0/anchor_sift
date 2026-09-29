// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_machine.c: every instruction of the listings taken as a form, and each form's operand fields
// found by turning its bits over, written out as the part's machine file for the assembler (sass_machine.h)
#include "cell_sass_probe.h"

#include "cubin_write.h"
#include "sass_assemble.h"
#include "sass_machine.h"

#include <stdio.h>
#include <string.h>

// the encodings one form is decoded with: itself, and the 128 that are one bit from it
static unsigned long long s_low[SASS_ENCODINGS];
static unsigned long long s_high[SASS_ENCODINGS];
static char s_texts[SASS_ENCODINGS][SASS_TEXT];

void sass_machine_listing(SassMachine *machine, const SassListing *listing)
{
    for (unsigned int number = 0u; number < listing->count; number += 1u)
    {
        const SassInstruction *const instruction = &listing->instructions[number];
        SassForm *kept = NULL;
        // an instruction the listing gave no encoding for says nothing about how its form encodes
        if ((instruction->low != 0ull) || (instruction->high != 0ull))
        {
            sass_machine_take(machine, instruction->text, instruction->low, instruction->high, &kept);
        }
    }
}

// the operand `text` changed against `base`, or the operand count where it changed none of them, more than one of
// them, the operation, or the guard
static unsigned int sass_operand_changed(const SassInstructionParts *base, const char *text)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    if ((strcmp(parts.operation, base->operation) != 0) || (parts.operands != base->operands) ||
        (strcmp(parts.guard, base->guard) != 0))
    {
        return base->operands;
    }
    unsigned int changed = base->operands;
    unsigned int count = 0u;
    for (unsigned int place = 0u; place < base->operands; place += 1u)
    {
        if ((strcmp(parts.operand[place], base->operand[place]) != 0) || (parts.mark[place] != base->mark[place]))
        {
            changed = place;
            count += 1u;
        }
    }
    return (count == 1u) ? changed : base->operands;
}

// a form's encoding and the 128 that are one bit from it, laid into s_low and s_high
static void sass_form_turned(const SassForm *form)
{
    s_low[0] = form->low;
    s_high[0] = form->high;
    for (unsigned int bit = 0u; bit < SASS_BITS; bit += 1u)
    {
        s_low[1u + bit] = s_low[0] ^ ((bit < 64u) ? (1ull << bit) : 0ull);
        s_high[1u + bit] = s_high[0] ^ ((bit >= 64u) ? (1ull << (bit - 64u)) : 0ull);
    }
}

// one form's fields found: each of its 128 bits turned over and decoded, and each run of bits that changes one
// printed operand kept as that operand's. 1, or 0 where the disassembler failed
static int sass_form_fields(SassForm *form, const char *architecture, const char *folder, unsigned int number)
{
    sass_form_turned(form);
    char path[1024];
    snprintf(path, sizeof(path), "%s/form_%03u", folder, number);
    if (!sass_decode(architecture, path, s_low, s_high, SASS_ENCODINGS, s_texts))
    {
        return 0;
    }
    SassInstructionParts base;
    sass_instruction_read(s_texts[0], &base);
    form->runs = 0u;
    unsigned int running = base.operands;
    unsigned int first = 0u;
    for (unsigned int bit = 0u; bit <= SASS_BITS; bit += 1u)
    {
        const unsigned int changed =
            (bit < SASS_BITS) ? sass_operand_changed(&base, s_texts[1u + bit]) : base.operands;
        // a run ends where the operand it changes does, and the two words never share one
        const int joined = (changed == running) && (changed != base.operands) && (bit != 64u);
        if (!joined && (running != base.operands) && (form->runs < SASS_MACHINE_RUNS))
        {
            form->run[form->runs].operand = running;
            form->run[form->runs].first = first;
            form->run[form->runs].last = bit - 1u;
            form->runs += 1u;
        }
        if (!joined)
        {
            running = changed;
            first = bit;
        }
    }
    return 1;
}

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
            // from the bytes alone, so for those the bytes are the whole of what can be filled to the listing
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

// the most bytes a cubin, its code and its text take
#define SASS_CUBIN_BYTES 262144u
#define SASS_CODE_BYTES 65536u
#define SASS_TEXT_BYTES 262144u
#define SASS_EXITS 256u

static unsigned char s_pattern[SASS_CUBIN_BYTES];
static unsigned char s_cubin[SASS_CUBIN_BYTES];
static unsigned char s_code[SASS_CODE_BYTES];
static char s_text[SASS_TEXT_BYTES];
static unsigned int s_exits[SASS_EXITS];

// `path` read whole into `bytes`, which holds `room` of them: how many were read, 0 where the file was not read
static unsigned long long sass_file_read(const char *path, unsigned char *bytes, unsigned long long room)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        printf("  cubin: %s could not be read\n", path);
        return 0ull;
    }
    const unsigned long long read = (unsigned long long)fread(bytes, 1u, (size_t)room, file);
    fclose(file);
    return read;
}

static int sass_file_write(const char *path, const unsigned char *bytes, unsigned long long size)
{
    FILE *const file = fopen(path, "wb");
    const int written = (file != NULL) && (fwrite(bytes, 1u, (size_t)size, file) == size);
    const int closed = (file != NULL) && (fclose(file) == 0);
    if (!written || !closed)
    {
        printf("  cubin: %s could not be written\n", path);
    }
    return written && closed;
}

// the encoding of EXIT as the machine holds it, or 0 where it holds none
static unsigned long long sass_exit_encoding(const SassMachine *machine)
{
    unsigned long long found = 0ull;
    for (unsigned int number = 0u; number < machine->forms; number += 1u)
    {
        found = (strcmp(machine->form[number].operation, "EXIT") == 0) ? machine->form[number].low : found;
    }
    return found;
}

unsigned int sass_cubin_text(const char *folder, const char *name, char *text, unsigned int room)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.sass", folder, name);
    static unsigned char s_listing[SASS_TEXT_BYTES];
    const unsigned long long listing_size = sass_file_read(path, s_listing, sizeof(s_listing) - 1u);
    if (listing_size == 0ull)
    {
        return 0u;
    }
    s_listing[listing_size] = '\0';
    const unsigned int text_size = sass_text_read((const char *)s_listing, "cell_ask", text, room);
    // the text the listing was turned back into, kept beside it for a reader
    snprintf(path, sizeof(path), "%s/%s.text", folder, name);
    sass_file_write(path, (const unsigned char *)text, text_size);
    return text_size;
}

int sass_cubin_from_text(const SassMachine *machine, const char *folder, const char *pattern, const char *text,
                         const char *into)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.cubin", folder, pattern);
    const unsigned long long pattern_size = sass_file_read(path, s_pattern, sizeof(s_pattern));
    if (pattern_size == 0ull)
    {
        return 0;
    }
    const unsigned int instructions = sass_assemble_lines(machine, text, SASS_CONTROL_SAFE, s_code, sizeof(s_code));
    if (instructions == 0u)
    {
        printf("  cubin: %s assembled nothing\n", into);
        return 0;
    }
    const unsigned long long code_size = 16ull * instructions;
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = pattern_size;
    written.kernel = "cell_ask";
    written.code = s_code;
    written.code_size = code_size;
    written.registers = cubin_registers_read(s_pattern, "cell_ask");
    written.exit_count = cubin_exits_find(s_code, code_size, sass_exit_encoding(machine), s_exits, SASS_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size))
    {
        return 0;
    }
    snprintf(path, sizeof(path), "%s/%s.cubin", folder, into);
    return sass_file_write(path, s_cubin, size);
}

int sass_cubin_round(const SassMachine *machine, const char *folder, const char *name)
{
    char into[256];
    snprintf(into, sizeof(into), "%s_written", name);
    return (sass_cubin_text(folder, name, s_text, sizeof(s_text)) != 0u) &&
           sass_cubin_from_text(machine, folder, name, s_text, into);
}

// 1 where the disassembler named every modifier of `operation`: one it could not name it prints as INVALID<n>, or
// leaves the trailing dot with nothing after it. An encoding whose meaning the disassembler will not state is not a
// form, because assembling from it would write bits nothing can say the part reads
static int sass_operation_named(const char *operation)
{
    const size_t length = strlen(operation);
    return (length != 0u) && (operation[length - 1u] != '.') && (strstr(operation, "INVALID") == NULL);
}

// 1 where `text` is an instruction a form can be kept from: the disassembler took it, it names an operation it could
// spell whole, and every operand it prints is a kind the assembler knows where to put
static int sass_widened_holds(const char *text, const SassInstructionParts *base, SassInstructionParts *parts)
{
    if ((strcmp(text, "illegal") == 0) || (strcmp(text, "unprinted") == 0))
    {
        return 0;
    }
    sass_instruction_read(text, parts);
    // the same operation is the form already in hand: its operands moved, or its control bits, neither a new form
    if (!sass_operation_named(parts->operation) || (strcmp(parts->operation, base->operation) == 0))
    {
        return 0;
    }
    for (unsigned int place = 0u; place < parts->operands; place += 1u)
    {
        if (parts->kind[place] == SASS_OPERAND_UNKNOWN)
        {
            return 0;
        }
    }
    return 1;
}

unsigned int sass_machine_widen(SassMachine *machine, const char *architecture, const char *folder)
{
    // the forms the listings gave, before any this pass adds: a form is widened from an instruction the part ran
    const unsigned int listed = machine->forms;
    unsigned int failed = 0u;
    for (unsigned int number = 0u; number < listed; number += 1u)
    {
        sass_form_turned(&machine->form[number]);
        char path[1024];
        snprintf(path, sizeof(path), "%s/widen_%03u", folder, number);
        if (!sass_decode(architecture, path, s_low, s_high, SASS_ENCODINGS, s_texts))
        {
            failed += 1u;
            continue;
        }
        SassInstructionParts base;
        sass_instruction_read(s_texts[0], &base);
        for (unsigned int bit = 0u; bit < SASS_BITS; bit += 1u)
        {
            SassInstructionParts parts;
            SassForm *kept = NULL;
            if (sass_widened_holds(s_texts[1u + bit], &base, &parts))
            {
                sass_machine_take(machine, s_texts[1u + bit], s_low[1u + bit], s_high[1u + bit], &kept);
            }
        }
    }
    printf("cell sass widen: %u forms listed, %u one bit from them, %u forms the disassembler failed\n", listed,
           machine->forms - listed, failed);
    return machine->forms - listed;
}

int sass_machine_fields(SassMachine *machine, const char *architecture, const char *folder)
{
    unsigned int failed = 0u;
    for (unsigned int number = 0u; number < machine->forms; number += 1u)
    {
        failed += sass_form_fields(&machine->form[number], architecture, folder, number) ? 0u : 1u;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/machine", folder);
    // the disassembler spells the part SM86 and everything else here spells it sm_86
    snprintf(machine->part, sizeof(machine->part), "sm_%s", architecture + 2);
    const int written = sass_machine_write(machine, path);
    // the file read back, so that the assembler reading it elsewhere is reading what this wrote
    static SassMachine s_again;
    const int again = written && sass_machine_read(&s_again, path);
    unsigned int differed = again ? 0u : machine->forms;
    for (unsigned int number = 0u; again && (number < machine->forms); number += 1u)
    {
        const SassForm *const was = &machine->form[number];
        const SassForm *const now = &s_again.form[number];
        differed += ((number >= s_again.forms) || (was->low != now->low) || (was->high != now->high) ||
                     (was->runs != now->runs) || (strcmp(was->text, now->text) != 0))
                        ? 1u
                        : 0u;
    }
    printf("cell sass machine: %u forms, %u without fields, %s, %u differing when read back\n", machine->forms,
           failed, written ? "written" : "not written", differed);
    return (written != 0) && (failed == 0u) && (differed == 0u);
}

int sass_machine_same(const SassMachine *machine, const char *machines)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", machines, machine->part);
    static SassMachine s_tree;
    if (!sass_machine_read(&s_tree, path))
    {
        printf("cell sass machine: the tree holds no %s, so this part's is the probe's alone\n", machine->part);
        return 1;
    }
    unsigned int differed = (s_tree.forms == machine->forms) ? 0u : 1u;
    for (unsigned int number = 0u; (number < machine->forms) && (number < s_tree.forms); number += 1u)
    {
        const SassForm *const filled = &s_tree.form[number];
        const SassForm *const found = &machine->form[number];
        differed += ((filled->low != found->low) || (filled->high != found->high) ||
                     (strcmp(filled->text, found->text) != 0) || (filled->runs != found->runs))
                        ? 1u
                        : 0u;
    }
    printf("cell sass machine: the tree's %s holds %u forms, %u of them differing from this run's\n",
           machine->part, s_tree.forms, differed);
    if (differed != 0u)
    {
        printf("  the part or its toolchain has moved: copy the run's machine over %s\n", path);
    }
    return (differed == 0u) ? 1 : 0;
}
