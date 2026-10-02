// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_take.c: every instruction of a listing whose form the machine file lacks, taken into it with its
// fields.
//
// The forms are taken into a machine of their own, and their fields found by the probe's own reading: each form's 128
// bits turned over one at a time and decoded, the runs of bits that change one printed operand kept as that operand's
// (sass_machine_fields). Each is then put into the machine file with those runs and the file written again. A form
// the machine file already holds is left as it stands, its fields and its encoding untouched.
//
//     interface_sass_probe_take <listing> <machine file> <architecture> <folder>
//     interface_sass_probe_take --fields <machine file> <architecture> <folder>
//
// The second form gives every form the machine file holds its fields again by the probe's reading, prints each form
// whose fields that changes, and writes the file.
//
// The listing is what cuobjdump -sass or nvdisasm prints; the architecture is named as the disassembler names it,
// SM86; the folder holds the encodings the disassembler is given.
#include "interface_sass_probe.h"

#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static SassMachine s_machine;
static SassMachine s_taken;
static SassListing s_listing;

// the file at `path` read as text, or NULL where it does not read
static char *take_file(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return NULL;
    }
    fseek(file, 0L, SEEK_END);
    const long size = ftell(file);
    fseek(file, 0L, SEEK_SET);
    // a size the file reported is at least 0, and a byte past it ends the text
    char *const text = (size >= 0L) ? (char *)malloc((size_t)size + 1u) : NULL;
    const int read = (text != NULL) && (fread(text, 1u, (size_t)size, file) == (size_t)size);
    fclose(file);
    if (read == 0)
    {
        free(text);
        return NULL;
    }
    text[size] = '\0';
    return text;
}

// 1 where two forms' runs of bits are the same
static int take_runs_same(const SassForm *one, const SassForm *other)
{
    int same = (one->runs == other->runs) ? 1 : 0;
    for (unsigned int at = 0u; same && (at < one->runs); at += 1u)
    {
        same = (one->run[at].operand == other->run[at].operand) && (one->run[at].first == other->run[at].first) &&
               (one->run[at].last == other->run[at].last);
    }
    return same;
}

// a form's runs written as the machine file writes them
static void take_runs_print(const SassForm *form)
{
    for (unsigned int at = 0u; at < form->runs; at += 1u)
    {
        printf("%s%u:%u-%u", (at == 0u) ? "" : ";", form->run[at].operand, form->run[at].first, form->run[at].last);
    }
}

// every form of the machine file at `path` given its fields again by the probe's reading, and the file written: the
// forms whose fields the reading changed counted and printed
static int take_fields(const char *path, const char *architecture, const char *folder)
{
    static SassMachine s_was;
    if (!sass_machine_read(&s_machine, path) || !sass_machine_read(&s_was, path))
    {
        fprintf(stderr, "the machine file %s did not read\n", path);
        return 1;
    }
    if (!sass_machine_fields(&s_machine, architecture, folder))
    {
        fprintf(stderr, "a form's fields were not found\n");
        return 1;
    }
    unsigned int changed = 0u;
    for (unsigned int number = 0u; number < s_machine.forms; number += 1u)
    {
        if (take_runs_same(&s_machine.form[number], &s_was.form[number]))
        {
            continue;
        }
        changed += 1u;
        printf("  %s\n    was ", s_machine.form[number].text);
        take_runs_print(&s_was.form[number]);
        printf("\n    now ");
        take_runs_print(&s_machine.form[number]);
        printf("\n");
    }
    printf("interface sass take: %u of %u forms given other fields\n", changed, s_machine.forms);
    if (!sass_machine_write(&s_machine, path))
    {
        fprintf(stderr, "the machine file %s was not written\n", path);
        return 1;
    }
    return 0;
}

int main(int count, char **words)
{
    if ((count == 5) && (strcmp(words[1], "--fields") == 0))
    {
        return take_fields(words[2], words[3], words[4]);
    }
    if (count != 5)
    {
        fprintf(stderr, "interface_sass_probe_take <listing> <machine file> <architecture> <folder>\n"
                        "interface_sass_probe_take --fields <machine file> <architecture> <folder>\n");
        return 2;
    }
    char *const output = take_file(words[1]);
    if ((output == NULL) || !sass_listing_read(output, &s_listing))
    {
        fprintf(stderr, "the listing %s did not read\n", words[1]);
        return 1;
    }
    free(output);
    if (!sass_machine_read(&s_machine, words[2]))
    {
        fprintf(stderr, "the machine file %s did not read\n", words[2]);
        return 1;
    }
    const unsigned int held = s_machine.forms;
    for (unsigned int number = 0u; number < s_listing.count; number += 1u)
    {
        const SassInstruction *const instruction = &s_listing.instructions[number];
        if ((instruction->low == 0ull) && (instruction->high == 0ull))
        {
            continue;
        }
        SassInstructionParts parts;
        sass_instruction_read(instruction->text, &parts);
        if (sass_machine_form(&s_machine, &parts) != NULL)
        {
            continue;
        }
        SassForm *kept = NULL;
        sass_machine_take(&s_taken, instruction->text, instruction->low, instruction->high, &kept);
    }
    printf("interface sass take: %u instructions read, %u forms the machine file of %u forms lacks\n", s_listing.count,
           s_taken.forms, held);
    if (s_taken.forms == 0u)
    {
        return 0;
    }
    if (!sass_machine_fields(&s_taken, words[3], words[4]))
    {
        fprintf(stderr, "a taken form's fields were not found\n");
        return 1;
    }
    for (unsigned int number = 0u; number < s_taken.forms; number += 1u)
    {
        const SassForm *const form = &s_taken.form[number];
        SassForm *kept = NULL;
        const unsigned int before = s_machine.forms;
        if (!sass_machine_take(&s_machine, form->text, form->low, form->high, &kept) || (kept == NULL) ||
            (s_machine.forms == before))
        {
            printf("  not taken: %s\n", form->text);
            continue;
        }
        kept->runs = form->runs;
        memcpy(kept->run, form->run, sizeof(form->run));
        printf("  taken: %s, %u runs of bits\n", form->text, form->runs);
    }
    if (!sass_machine_write(&s_machine, words[2]))
    {
        fprintf(stderr, "the machine file %s was not written\n", words[2]);
        return 1;
    }
    printf("interface sass take: the machine file %s holds %u forms\n", words[2], s_machine.forms);
    return 0;
}
