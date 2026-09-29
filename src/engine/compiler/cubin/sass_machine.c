// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sass_machine.c: an instruction's text read into its parts, and a part's forms kept, written and read back
#include "sass_machine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// a kind as a machine file writes it, by its place in SassOperandKind, and a mark by its place in SassOperandMark
static const char *const s_kind_names[] = {"unknown",  "register", "predicate", "immediate", "constant",
                                           "address",  "label",    "uniform",   "system"};
static const char *const s_mark_names[] = {"", "-", "~", "!"};

#define SASS_KIND_COUNT (sizeof(s_kind_names) / sizeof(s_kind_names[0]))
#define SASS_MARK_COUNT (sizeof(s_mark_names) / sizeof(s_mark_names[0]))

// 1 where `letter` stands between one token of an instruction and the next. A listing lays its instructions out with
// spaces and a ruleset with tabs, and the two say the same thing: sass.krs writes "\tIADD3 \t{to}, {left}, ..." and
// nvdisasm prints "        IADD3 R8, R0, R1, RZ ;", and this reader takes both
#define SASS_SPACES " \t"

static int sass_is_space(char letter)
{
    return (letter == ' ') || (letter == '\t');
}

// `length` letters of `text` copied into `token`, with the spaces at either end cut and the whole kept below
// SASS_MACHINE_TOKEN letters
static void sass_token_take(char *token, const char *text, size_t length)
{
    while ((length != 0u) && sass_is_space(*text))
    {
        text += 1;
        length -= 1u;
    }
    while ((length != 0u) && sass_is_space(text[length - 1u]))
    {
        length -= 1u;
    }
    const size_t kept = (length < (SASS_MACHINE_TOKEN - 1u)) ? length : (SASS_MACHINE_TOKEN - 1u);
    memcpy(token, text, kept);
    token[kept] = '\0';
}

// 1 where every letter of `text` from `at` is a digit, and there is one
static int sass_all_digits(const char *text, size_t at)
{
    const size_t first = at;
    while ((text[at] >= '0') && (text[at] <= '9'))
    {
        at += 1u;
    }
    return (at != first) && (text[at] == '\0');
}

// 1 where `text` ends in the .hi a ruleset writes for the second register of a 64-bit pair. A ruleset names a
// register by its number alone, and the pair beginning at R14 has no other way to name R15 (sass.krs)
int sass_high_half(const char *text)
{
    const size_t length = strlen(text);
    return (length > 3u) && (strcmp(text + length - 3u, ".hi") == 0);
}

// what kind of thing `text` is, with any mark already cut off it
static unsigned int sass_operand_kind(const char *text)
{
    if (strchr(text, ' ') != NULL)
    {
        return SASS_OPERAND_UNKNOWN;
    }
    // the second register of a pair is a register, and is classified by the one it is named from
    if (sass_high_half(text))
    {
        char stem[SASS_MACHINE_TOKEN];
        const size_t length = strlen(text) - 3u;
        const size_t kept = (length < (SASS_MACHINE_TOKEN - 1u)) ? length : (SASS_MACHINE_TOKEN - 1u);
        memcpy(stem, text, kept);
        stem[kept] = '\0';
        return sass_operand_kind(stem);
    }
    if ((text[0] == 'R') && ((strcmp(text, "RZ") == 0) || sass_all_digits(text, 1u)))
    {
        return SASS_OPERAND_REGISTER;
    }
    if ((text[0] == 'P') && ((strcmp(text, "PT") == 0) || sass_all_digits(text, 1u)))
    {
        return SASS_OPERAND_PREDICATE;
    }
    // URZ is to the uniform registers what RZ is to the numbered ones, and reads the same way
    if ((text[0] == 'U') && (text[1] == 'R') && ((strcmp(text, "URZ") == 0) || sass_all_digits(text, 2u)))
    {
        return SASS_OPERAND_UNIFORM;
    }
    if (strncmp(text, "SR_", 3u) == 0)
    {
        return SASS_OPERAND_SYSTEM;
    }
    if ((text[0] == 'c') && (text[1] == '['))
    {
        return SASS_OPERAND_CONSTANT;
    }
    if ((text[0] == '[') || (strncmp(text, "desc[", 5u) == 0))
    {
        return SASS_OPERAND_ADDRESS;
    }
    if (text[0] == '`')
    {
        return SASS_OPERAND_LABEL;
    }
    if ((text[0] == '0') && (text[1] == 'x'))
    {
        return SASS_OPERAND_IMMEDIATE;
    }
    // a number, with its sign where it carries one. A listing prints these in hex and a ruleset writes them in
    // decimal, and a negative decimal is a number the same as a negative hex: reading the digits from index 0 would
    // put the sign among them and leave -1 as nothing the reader knows
    if (((text[0] == '-') && (text[1] == '0') && (text[2] == 'x')) || sass_all_digits(text, 0u) ||
        ((text[0] == '-') && sass_all_digits(text, 1u)))
    {
        return SASS_OPERAND_IMMEDIATE;
    }
    return SASS_OPERAND_UNKNOWN;
}

// the operand at `place` of `parts` taken from `text`: its mark cut off the front, .reuse off the end, and its kind
// read. A minus before a number is the number's sign and no mark
static void sass_operand_take(SassInstructionParts *parts, unsigned int place, const char *text, size_t length)
{
    char token[SASS_MACHINE_TOKEN];
    sass_token_take(token, text, length);
    const size_t token_length = strlen(token);
    if ((token_length > 6u) && (strcmp(token + token_length - 6u, ".reuse") == 0))
    {
        token[token_length - 6u] = '\0';
    }
    unsigned int mark = (token[0] == '-')   ? SASS_MARK_NEGATE
                        : (token[0] == '~') ? SASS_MARK_INVERT
                        : (token[0] == '!') ? SASS_MARK_NOT
                                            : SASS_MARK_NONE;
    const unsigned int marked = sass_operand_kind(token + ((mark == SASS_MARK_NONE) ? 0u : 1u));
    // a minus before a number is the number's own sign, and the operand keeps it
    mark = ((mark == SASS_MARK_NEGATE) && (marked == SASS_OPERAND_IMMEDIATE)) ? SASS_MARK_NONE : mark;
    parts->mark[place] = mark;
    parts->kind[place] = (mark == SASS_MARK_NONE) ? sass_operand_kind(token) : marked;
    memcpy(parts->operand[place], token + ((mark == SASS_MARK_NONE) ? 0u : 1u),
           strlen(token + ((mark == SASS_MARK_NONE) ? 0u : 1u)) + 1u);
}

void sass_instruction_read(const char *text, SassInstructionParts *parts)
{
    memset(parts, 0, sizeof(*parts));
    while (sass_is_space(*text))
    {
        text += 1;
    }
    if (*text == '@')
    {
        const size_t length = strcspn(text, SASS_SPACES);
        sass_token_take(parts->guard, text, length);
        text += length;
        while (sass_is_space(*text))
        {
            text += 1;
        }
    }
    const size_t operation_length = strcspn(text, SASS_SPACES);
    sass_token_take(parts->operation, text, operation_length);
    text += operation_length;
    // the operands, split at each comma outside brackets
    int depth = 0;
    const char *start = text;
    for (const char *walk = text;; walk += 1)
    {
        const char letter = *walk;
        depth += ((letter == '[') || (letter == '(')) ? 1 : 0;
        depth -= ((letter == ']') || (letter == ')')) ? 1 : 0;
        if ((letter == '\0') || ((letter == ',') && (depth == 0)))
        {
            const size_t length = (size_t)(walk - start);
            if ((parts->operands < SASS_MACHINE_OPERANDS) && (strspn(start, SASS_SPACES) < length))
            {
                sass_operand_take(parts, parts->operands, start, length);
                parts->operands += 1u;
            }
            start = walk + 1;
        }
        if (letter == '\0')
        {
            break;
        }
    }
}

// 1 where the two hold the same operation and the same kind and mark at every operand, and the same text at every
// operand the assembler cannot turn into a number: a system register is named, not counted, and two instructions that
// name different ones are two forms, each with the encoding it was seen with
static int sass_form_same(const SassForm *form, const SassInstructionParts *parts)
{
    int same = (strcmp(form->operation, parts->operation) == 0) && (form->operands == parts->operands);
    int by_text = 0;
    for (unsigned int place = 0u; same && (place < form->operands); place += 1u)
    {
        same = (form->kind[place] == parts->kind[place]) && (form->mark[place] == parts->mark[place]);
        by_text = by_text || (form->kind[place] == SASS_OPERAND_SYSTEM) ||
                  (form->kind[place] == SASS_OPERAND_UNKNOWN);
    }
    if (same && by_text)
    {
        SassInstructionParts seen;
        sass_instruction_read(form->text, &seen);
        for (unsigned int place = 0u; same && (place < form->operands); place += 1u)
        {
            same = ((form->kind[place] != SASS_OPERAND_SYSTEM) && (form->kind[place] != SASS_OPERAND_UNKNOWN)) ||
                   (strcmp(seen.operand[place], parts->operand[place]) == 0);
        }
    }
    return same;
}

const SassForm *sass_machine_form(const SassMachine *machine, const SassInstructionParts *parts)
{
    const SassForm *found = NULL;
    for (unsigned int number = 0u; number < machine->forms; number += 1u)
    {
        found = sass_form_same(&machine->form[number], parts) ? &machine->form[number] : found;
    }
    return found;
}

int sass_machine_take(SassMachine *machine, const char *text, unsigned long long low, unsigned long long high,
                      SassForm **kept)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    const SassForm *const found = sass_machine_form(machine, &parts);
    if (found != NULL)
    {
        *kept = &machine->form[found - machine->form];
        return 1;
    }
    if (machine->forms == SASS_MACHINE_FORMS)
    {
        machine->refused += 1u;
        *kept = NULL;
        return 0;
    }
    SassForm *const form = &machine->form[machine->forms];
    memset(form, 0, sizeof(*form));
    memcpy(form->operation, parts.operation, sizeof(form->operation));
    form->operands = parts.operands;
    for (unsigned int place = 0u; place < parts.operands; place += 1u)
    {
        form->kind[place] = parts.kind[place];
        form->mark[place] = parts.mark[place];
    }
    form->low = low;
    form->high = high;
    snprintf(form->text, sizeof(form->text), "%s", text);
    machine->forms += 1u;
    *kept = form;
    return 1;
}

// the runs of `form` written into `written` as one column, "none" where the probe found it none
static void sass_runs_write(const SassForm *form, char *written, size_t room)
{
    size_t at = 0u;
    written[0] = '\0';
    for (unsigned int number = 0u; number < form->runs; number += 1u)
    {
        const SassRun *const run = &form->run[number];
        const int printed = snprintf(written + at, room - at, "%s%u:%u-%u", (number == 0u) ? "" : ";", run->operand,
                                     run->first, run->last);
        // snprintf gives the letters it would have written, which the room below bounds
        at += ((printed > 0) && ((size_t)printed < (room - at))) ? (size_t)printed : 0u;
    }
    if (form->runs == 0u)
    {
        snprintf(written, room, "none");
    }
}

// one form's runs column read into `form`: 1, or 0 where a run does not read
static int sass_runs_read(SassForm *form, const char *column)
{
    form->runs = 0u;
    if (strcmp(column, "none") == 0)
    {
        return 1;
    }
    const char *at = column;
    while (*at != '\0')
    {
        unsigned int operand = 0u;
        unsigned int first = 0u;
        unsigned int last = 0u;
        if ((sscanf(at, "%u:%u-%u", &operand, &first, &last) != 3) || (form->runs == SASS_MACHINE_RUNS))
        {
            return 0;
        }
        form->run[form->runs].operand = operand;
        form->run[form->runs].first = first;
        form->run[form->runs].last = last;
        form->runs += 1u;
        const size_t length = strcspn(at, ";");
        at += length + ((at[length] == ';') ? 1u : 0u);
    }
    return 1;
}

// the kinds and marks of `form` written into `written` as one column, "none" where it takes no operand
static void sass_kinds_write(const SassForm *form, char *written, size_t room)
{
    size_t at = 0u;
    written[0] = '\0';
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        const int printed = snprintf(written + at, room - at, "%s%s%s", (place == 0u) ? "" : ",",
                                     s_kind_names[form->kind[place]], s_mark_names[form->mark[place]]);
        // snprintf gives the letters it would have written, which the room below bounds
        at += ((printed > 0) && ((size_t)printed < (room - at))) ? (size_t)printed : 0u;
    }
    if (form->operands == 0u)
    {
        snprintf(written, room, "none");
    }
}

int sass_machine_write(const SassMachine *machine, const char *path)
{
    FILE *const file = fopen(path, "w");
    if (file == NULL)
    {
        printf("  sass_machine: %s could not be written\n", path);
        return 0;
    }
    fprintf(file, "forms 1\n");
    fprintf(file, "# The part's instructions as the cell's probes read them back: one line a form, an operation and\n"
                  "# the kind and mark of each printed operand, with the encoding the form was first seen with and\n"
                  "# the instruction it was seen as. The format is the comment at the head of sass_machine.h.\n");
    fprintf(file, "part %s\n", machine->part);
    for (unsigned int number = 0u; number < machine->forms; number += 1u)
    {
        const SassForm *const form = &machine->form[number];
        char kinds[SASS_MACHINE_TOKEN * SASS_MACHINE_OPERANDS];
        char runs[SASS_MACHINE_RUNS * 16u];
        sass_kinds_write(form, kinds, sizeof(kinds));
        sass_runs_write(form, runs, sizeof(runs));
        fprintf(file, "form %s %s 0x%016llx 0x%016llx %s %s\n", form->operation, kinds, form->low, form->high,
                runs, form->text);
    }
    return (fclose(file) == 0) ? 1 : 0;
}

// the place of `word` among the names, or `count` where it is none of them
static unsigned int sass_name_place(const char *const *names, unsigned int count, const char *word, size_t length)
{
    unsigned int found = count;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = ((strlen(names[at]) == length) && (strncmp(names[at], word, length) == 0)) ? at : found;
    }
    return found;
}

// one form's kinds column read into `form`: 1, or 0 where a kind or a mark is none the writer names
static int sass_kinds_read(SassForm *form, const char *column)
{
    form->operands = 0u;
    if (strcmp(column, "none") == 0)
    {
        return 1;
    }
    const char *at = column;
    while (*at != '\0')
    {
        const size_t length = strcspn(at, ",");
        // the mark is the last letter where it is one, and the kind the rest
        const size_t mark_length = ((length != 0u) && (sass_name_place(s_mark_names, (unsigned int)SASS_MARK_COUNT,
                                                                      at + length - 1u, 1u) != SASS_MARK_COUNT))
                                       ? 1u
                                       : 0u;
        const unsigned int kind =
            sass_name_place(s_kind_names, (unsigned int)SASS_KIND_COUNT, at, length - mark_length);
        const unsigned int mark =
            (mark_length == 0u)
                ? (unsigned int)SASS_MARK_NONE
                : sass_name_place(s_mark_names, (unsigned int)SASS_MARK_COUNT, at + length - 1u, 1u);
        if ((kind == SASS_KIND_COUNT) || (form->operands == SASS_MACHINE_OPERANDS))
        {
            return 0;
        }
        form->kind[form->operands] = kind;
        form->mark[form->operands] = mark;
        form->operands += 1u;
        at += length + ((at[length] == ',') ? 1u : 0u);
    }
    return 1;
}

int sass_machine_read(SassMachine *machine, const char *path)
{
    FILE *const file = fopen(path, "r");
    if (file == NULL)
    {
        printf("  sass_machine: %s could not be read\n", path);
        return 0;
    }
    memset(machine, 0, sizeof(*machine));
    char line[SASS_MACHINE_TEXT + (SASS_MACHINE_TOKEN * (SASS_MACHINE_OPERANDS + 4u))];
    unsigned int version = 0u;
    int broken = 0;
    while (fgets(line, (int)sizeof(line), file) != NULL)
    {
        line[strcspn(line, "\r\n")] = '\0';
        if ((line[0] == '#') || (line[0] == '\0'))
        {
            continue;
        }
        if (strncmp(line, "forms ", 6u) == 0)
        {
            version = (unsigned int)strtoul(line + 6, NULL, 10);
            continue;
        }
        if (strncmp(line, "part ", 5u) == 0)
        {
            // a part's name is short, and a longer one is cut to what the field holds
            snprintf(machine->part, sizeof(machine->part), "%.*s", (int)(sizeof(machine->part) - 1u), line + 5);
            continue;
        }
        if (strncmp(line, "form ", 5u) != 0)
        {
            broken = 1;
            continue;
        }
        char operation[SASS_MACHINE_TOKEN];
        char kinds[SASS_MACHINE_TOKEN * SASS_MACHINE_OPERANDS];
        char runs[SASS_MACHINE_RUNS * 16u];
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        int at = 0;
        // the text past the runs is the instruction the form was seen as, and holds spaces
        if (sscanf(line + 5, "%63s %511s %llx %llx %511s %n", operation, kinds, &low, &high, runs, &at) != 5)
        {
            broken = 1;
            continue;
        }
        if (machine->forms == SASS_MACHINE_FORMS)
        {
            machine->refused += 1u;
            continue;
        }
        SassForm *const form = &machine->form[machine->forms];
        memset(form, 0, sizeof(*form));
        snprintf(form->operation, sizeof(form->operation), "%s", operation);
        snprintf(form->text, sizeof(form->text), "%s", line + 5 + at);
        form->low = low;
        form->high = high;
        broken = sass_kinds_read(form, kinds) ? broken : 1;
        broken = sass_runs_read(form, runs) ? broken : 1;
        machine->forms += 1u;
    }
    fclose(file);
    if ((version != 1u) || broken || (machine->forms == 0u))
    {
        printf("  sass_machine: %s is not a machine file this reads (forms %u, %u read)\n", path, version,
               machine->forms);
        return 0;
    }
    return 1;
}
