// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sass_machine.c: an instruction's text read into its parts, and a part's shapes kept, written and read back
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

// `length` letters of `text` copied into `token`, with the spaces at either end cut and the whole kept below
// SASS_MACHINE_TOKEN letters
static void sass_token_take(char *token, const char *text, size_t length)
{
    while ((length != 0u) && (*text == ' '))
    {
        text += 1;
        length -= 1u;
    }
    while ((length != 0u) && (text[length - 1u] == ' '))
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

// what kind of thing `text` is, with any mark already cut off it
static unsigned int sass_operand_kind(const char *text)
{
    if (strchr(text, ' ') != NULL)
    {
        return SASS_OPERAND_UNKNOWN;
    }
    if ((text[0] == 'R') && ((strcmp(text, "RZ") == 0) || sass_all_digits(text, 1u)))
    {
        return SASS_OPERAND_REGISTER;
    }
    if ((text[0] == 'P') && ((strcmp(text, "PT") == 0) || sass_all_digits(text, 1u)))
    {
        return SASS_OPERAND_PREDICATE;
    }
    if ((text[0] == 'U') && (text[1] == 'R') && sass_all_digits(text, 2u))
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
    if (((text[0] == '-') && (text[1] == '0') && (text[2] == 'x')) || sass_all_digits(text, 0u))
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
    const size_t held = strlen(token);
    if ((held > 6u) && (strcmp(token + held - 6u, ".reuse") == 0))
    {
        token[held - 6u] = '\0';
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
    while (*text == ' ')
    {
        text += 1;
    }
    if (*text == '@')
    {
        const size_t length = strcspn(text, " ");
        sass_token_take(parts->guard, text, length);
        text += length;
        while (*text == ' ')
        {
            text += 1;
        }
    }
    const size_t operation_length = strcspn(text, " ");
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
            if ((parts->operands < SASS_MACHINE_OPERANDS) && (strspn(start, " ") < length))
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
// operand the assembler cannot turn into a number: a system register is named, not counted, so two instructions that
// name different ones are two shapes, each with the encoding it was seen with
static int sass_shape_same(const SassShape *shape, const SassInstructionParts *parts)
{
    int same = (strcmp(shape->operation, parts->operation) == 0) && (shape->operands == parts->operands);
    int by_text = 0;
    for (unsigned int place = 0u; same && (place < shape->operands); place += 1u)
    {
        same = (shape->kind[place] == parts->kind[place]) && (shape->mark[place] == parts->mark[place]);
        by_text = by_text || (shape->kind[place] == SASS_OPERAND_SYSTEM) ||
                  (shape->kind[place] == SASS_OPERAND_UNKNOWN);
    }
    if (same && by_text)
    {
        SassInstructionParts seen;
        sass_instruction_read(shape->text, &seen);
        for (unsigned int place = 0u; same && (place < shape->operands); place += 1u)
        {
            same = ((shape->kind[place] != SASS_OPERAND_SYSTEM) && (shape->kind[place] != SASS_OPERAND_UNKNOWN)) ||
                   (strcmp(seen.operand[place], parts->operand[place]) == 0);
        }
    }
    return same;
}

const SassShape *sass_machine_shape(const SassMachine *machine, const SassInstructionParts *parts)
{
    const SassShape *found = NULL;
    for (unsigned int number = 0u; number < machine->shapes; number += 1u)
    {
        found = sass_shape_same(&machine->shape[number], parts) ? &machine->shape[number] : found;
    }
    return found;
}

int sass_machine_take(SassMachine *machine, const char *text, unsigned long long low, unsigned long long high,
                      SassShape **kept)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    const SassShape *const held = sass_machine_shape(machine, &parts);
    if (held != NULL)
    {
        *kept = &machine->shape[held - machine->shape];
        return 1;
    }
    if (machine->shapes == SASS_MACHINE_SHAPES)
    {
        machine->refused += 1u;
        *kept = NULL;
        return 0;
    }
    SassShape *const shape = &machine->shape[machine->shapes];
    memset(shape, 0, sizeof(*shape));
    memcpy(shape->operation, parts.operation, sizeof(shape->operation));
    shape->operands = parts.operands;
    for (unsigned int place = 0u; place < parts.operands; place += 1u)
    {
        shape->kind[place] = parts.kind[place];
        shape->mark[place] = parts.mark[place];
    }
    shape->low = low;
    shape->high = high;
    snprintf(shape->text, sizeof(shape->text), "%s", text);
    machine->shapes += 1u;
    *kept = shape;
    return 1;
}

// the runs of `shape` written into `written` as one column, "none" where the probe found it none
static void sass_runs_write(const SassShape *shape, char *written, size_t room)
{
    size_t at = 0u;
    written[0] = '\0';
    for (unsigned int number = 0u; number < shape->runs; number += 1u)
    {
        const SassRun *const run = &shape->run[number];
        const int printed = snprintf(written + at, room - at, "%s%u:%u-%u", (number == 0u) ? "" : ";", run->operand,
                                     run->first, run->last);
        // snprintf gives the letters it would have written, which the room below bounds
        at += ((printed > 0) && ((size_t)printed < (room - at))) ? (size_t)printed : 0u;
    }
    if (shape->runs == 0u)
    {
        snprintf(written, room, "none");
    }
}

// one shape's runs column read into `shape`: 1, or 0 where a run does not read
static int sass_runs_read(SassShape *shape, const char *column)
{
    shape->runs = 0u;
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
        if ((sscanf(at, "%u:%u-%u", &operand, &first, &last) != 3) || (shape->runs == SASS_MACHINE_RUNS))
        {
            return 0;
        }
        shape->run[shape->runs].operand = operand;
        shape->run[shape->runs].first = first;
        shape->run[shape->runs].last = last;
        shape->runs += 1u;
        const size_t length = strcspn(at, ";");
        at += length + ((at[length] == ';') ? 1u : 0u);
    }
    return 1;
}

// the kinds and marks of `shape` written into `written` as one column, "none" where it takes no operand
static void sass_kinds_write(const SassShape *shape, char *written, size_t room)
{
    size_t at = 0u;
    written[0] = '\0';
    for (unsigned int place = 0u; place < shape->operands; place += 1u)
    {
        const int printed = snprintf(written + at, room - at, "%s%s%s", (place == 0u) ? "" : ",",
                                     s_kind_names[shape->kind[place]], s_mark_names[shape->mark[place]]);
        // snprintf gives the letters it would have written, which the room below bounds
        at += ((printed > 0) && ((size_t)printed < (room - at))) ? (size_t)printed : 0u;
    }
    if (shape->operands == 0u)
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
    fprintf(file, "kmc 1\n");
    fprintf(file, "# The part's instructions as the cell's probes read them back: one line a shape, an operation and\n"
                  "# the kind and mark of each printed operand, with the encoding the shape was first seen with and\n"
                  "# the instruction it was seen as. The format is the comment at the head of sass_machine.h.\n");
    fprintf(file, "part %s\n", machine->part);
    for (unsigned int number = 0u; number < machine->shapes; number += 1u)
    {
        const SassShape *const shape = &machine->shape[number];
        char kinds[SASS_MACHINE_TOKEN * SASS_MACHINE_OPERANDS];
        char runs[SASS_MACHINE_RUNS * 16u];
        sass_kinds_write(shape, kinds, sizeof(kinds));
        sass_runs_write(shape, runs, sizeof(runs));
        fprintf(file, "shape %s %s 0x%016llx 0x%016llx %s %s\n", shape->operation, kinds, shape->low, shape->high,
                runs, shape->text);
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

// one shape's kinds column read into `shape`: 1, or 0 where a kind or a mark is none the writer names
static int sass_kinds_read(SassShape *shape, const char *column)
{
    shape->operands = 0u;
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
        if ((kind == SASS_KIND_COUNT) || (shape->operands == SASS_MACHINE_OPERANDS))
        {
            return 0;
        }
        shape->kind[shape->operands] = kind;
        shape->mark[shape->operands] = mark;
        shape->operands += 1u;
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
        if (strncmp(line, "kmc ", 4u) == 0)
        {
            version = (unsigned int)strtoul(line + 4, NULL, 10);
            continue;
        }
        if (strncmp(line, "part ", 5u) == 0)
        {
            // a part's name is short, and a longer one is cut to what the field holds
            snprintf(machine->part, sizeof(machine->part), "%.*s", (int)(sizeof(machine->part) - 1u), line + 5);
            continue;
        }
        if (strncmp(line, "shape ", 6u) != 0)
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
        // the text past the runs is the instruction the shape was seen as, and holds spaces
        if (sscanf(line + 6, "%63s %511s %llx %llx %511s %n", operation, kinds, &low, &high, runs, &at) != 5)
        {
            broken = 1;
            continue;
        }
        if (machine->shapes == SASS_MACHINE_SHAPES)
        {
            machine->refused += 1u;
            continue;
        }
        SassShape *const shape = &machine->shape[machine->shapes];
        memset(shape, 0, sizeof(*shape));
        snprintf(shape->operation, sizeof(shape->operation), "%s", operation);
        snprintf(shape->text, sizeof(shape->text), "%s", line + 6 + at);
        shape->low = low;
        shape->high = high;
        broken = sass_kinds_read(shape, kinds) ? broken : 1;
        broken = sass_runs_read(shape, runs) ? broken : 1;
        machine->shapes += 1u;
    }
    fclose(file);
    if ((version != 1u) || broken || (machine->shapes == 0u))
    {
        printf("  sass_machine: %s is not a machine file this reads (kmc %u, %u shapes)\n", path, version,
               machine->shapes);
        return 0;
    }
    return 1;
}
