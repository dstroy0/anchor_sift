// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sass_assemble.c: an operand's value, the fields a shape's operands sit in, and one line assembled
#include "sass_assemble.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the guard predicate: three bits its number and the fourth the negation
#define SASS_GUARD_FIRST 12u
#define SASS_GUARD_BITS 3u
#define SASS_GUARD_NOT 15u
// the scheduler's bits, which no listing prints: the stall, the yield, a write and a read barrier, the wait mask and
// the reuse flags
#define SASS_STALL_FIRST 105u
#define SASS_YIELD_FIRST 109u
#define SASS_WRITE_BARRIER_FIRST 110u
#define SASS_READ_BARRIER_FIRST 113u
#define SASS_WAIT_FIRST 116u
#define SASS_REUSE_FIRST 122u
// a barrier none is waited on or set, the longest stall the field holds, and every barrier waited on
#define SASS_BARRIER_NONE 7u
#define SASS_STALL_LONGEST 15u
#define SASS_WAIT_EVERY 0x3fu
// a branch counts its target from the instruction after it, in a signed field that begins at bit 32 and runs into the
// high word: the one branch the probes read back holds -16, and every bit of it from 32 to 81 is set
#define SASS_BRANCH_FIRST 32u
#define SASS_BRANCH_BITS 50u

// one place a value sits: its first bit, how many bits it holds, and what one of them counts
typedef struct
{
    unsigned int first;
    unsigned int bits;
    unsigned int scale;
} SassField;

// the fields a kind of operand may sit in, in the order an instruction fills them
static const SassField s_register_fields[] = {{16u, 8u, 1u}, {24u, 8u, 1u}, {32u, 8u, 1u}, {64u, 8u, 1u}};
// a predicate operand takes three bits and the fourth negates it; the probes found five places one sits in
static const SassField s_predicate_fields[] = {{68u, 3u, 1u}, {77u, 3u, 1u}, {81u, 3u, 1u}, {84u, 3u, 1u},
                                               {87u, 3u, 1u}};
static const SassField s_immediate_fields[] = {{32u, 32u, 1u}, {72u, 8u, 1u}};
// a constant's offset counts words, and an address's bytes; both lie above the register fields
static const SassField s_constant_fields[] = {{40u, 16u, 4u}};
static const SassField s_offset_fields[] = {{40u, 24u, 1u}};

#define SASS_REGISTER_FIELDS (sizeof(s_register_fields) / sizeof(s_register_fields[0]))
#define SASS_PREDICATE_FIELDS (sizeof(s_predicate_fields) / sizeof(s_predicate_fields[0]))
#define SASS_IMMEDIATE_FIELDS (sizeof(s_immediate_fields) / sizeof(s_immediate_fields[0]))

// where one operand of a shape was placed: the field its value sits in, and for an address the field its offset sits
// in as well
typedef struct
{
    SassField value;
    SassField offset;
    int has_offset;
    int by_text;
} SassPlace;

// `bits` of `value` written from bit `first` of the instruction, a bit at a time, since a branch's target begins in
// the low word and ends in the high one
static void sass_bits_write(unsigned long long *low, unsigned long long *high, unsigned int first, unsigned int bits,
                            unsigned long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int at = first + bit;
        unsigned long long *const word = (at < 64u) ? low : high;
        const unsigned int place = (at < 64u) ? at : (at - 64u);
        *word = (*word & ~(1ull << place)) | (((value >> bit) & 1ull) << place);
    }
}

// the number a register, predicate or uniform register names: RZ is 255 and PT is 7
static unsigned long long sass_register_value(const char *text)
{
    if (strcmp(text, "RZ") == 0)
    {
        return 255ull;
    }
    if (strcmp(text, "PT") == 0)
    {
        return 7ull;
    }
    const char *const digits = text + ((text[0] == 'U') ? 2u : 1u);
    return strtoull(digits, NULL, 10);
}

// the offset a constant names, c[bank][offset], and the bank through `bank`
static unsigned long long sass_constant_value(const char *text, unsigned long long *bank)
{
    const char *const first = strchr(text, '[');
    const char *const second = (first != NULL) ? strchr(first + 1, '[') : NULL;
    *bank = (first != NULL) ? strtoull(first + 1, NULL, 0) : 0ull;
    return (second != NULL) ? strtoull(second + 1, NULL, 0) : 0ull;
}

// the base register an address names, [R2.64+0x4], and its offset through `offset`
static unsigned long long sass_address_value(const char *text, unsigned long long *offset)
{
    const char *const open = strrchr(text, '[');
    const char *const plus = (open != NULL) ? strchr(open, '+') : NULL;
    *offset = (plus != NULL) ? strtoull(plus + 1, NULL, 0) : 0ull;
    return (open != NULL) ? sass_register_value(open + 1) : 0ull;
}

// the value the operand at `place` of `parts` carries, and the field it wants to sit in through `wanted`; 0 where the
// assembler cannot turn it into a number, which leaves it to be matched by its text
static int sass_operand_value(const SassInstructionParts *parts, unsigned int place, unsigned long long address,
                              unsigned long long target, unsigned long long *value, unsigned long long *offset)
{
    const char *const text = parts->operand[place];
    *offset = 0ull;
    switch (parts->kind[place])
    {
    case SASS_OPERAND_REGISTER:
    case SASS_OPERAND_PREDICATE:
    case SASS_OPERAND_UNIFORM:
        *value = sass_register_value(text);
        return 1;
    case SASS_OPERAND_IMMEDIATE:
        *value = (text[0] == '-') ? (unsigned long long)(-(long long)strtoull(text + 1, NULL, 0))
                                  : strtoull(text, NULL, 0);
        return 1;
    case SASS_OPERAND_CONSTANT:
        *value = sass_constant_value(text, offset);
        return 1;
    case SASS_OPERAND_ADDRESS:
        *value = sass_address_value(text, offset);
        return 1;
    case SASS_OPERAND_LABEL:
        // a branch counts its target from the instruction after it
        *value = target - (address + 16ull);
        return 1;
    default:
        return 0;
    }
}

// the fields of `kind`, and how many there are
static const SassField *sass_fields_of(unsigned int kind, unsigned int *count)
{
    switch (kind)
    {
    case SASS_OPERAND_REGISTER:
    case SASS_OPERAND_UNIFORM:
    case SASS_OPERAND_ADDRESS:
        *count = (unsigned int)SASS_REGISTER_FIELDS;
        return s_register_fields;
    case SASS_OPERAND_PREDICATE:
        *count = (unsigned int)SASS_PREDICATE_FIELDS;
        return s_predicate_fields;
    case SASS_OPERAND_IMMEDIATE:
    case SASS_OPERAND_LABEL:
        *count = (unsigned int)SASS_IMMEDIATE_FIELDS;
        return s_immediate_fields;
    case SASS_OPERAND_CONSTANT:
        *count = 1u;
        return s_constant_fields;
    default:
        *count = 0u;
        return NULL;
    }
}

// the field of `kind` that begins inside `run`, or NULL where the kind takes none there. A run is the bits the probe
// saw change one operand, which is the field and whatever lies beside it that changes the same operand: a bit that
// says what kind the operand is, or the low bits of an offset the operation counts in wider units
static const SassField *sass_field_at(unsigned int kind, const SassRun *run)
{
    unsigned int count = 0u;
    const SassField *const fields = sass_fields_of(kind, &count);
    const SassField *found = NULL;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = ((fields[at].first >= run->first) && (fields[at].first <= run->last)) ? &fields[at] : found;
    }
    return found;
}

// the shape's operands placed in the fields the probe's runs name: each operand takes the run that begins where a
// field of its kind begins, and an address takes the offset field beside its base register. 1 where every operand was
// placed, else 0 and the operand that could not be
static int sass_places_find(const SassShape *shape, SassPlace *places, unsigned int *unplaced)
{
    SassInstructionParts base;
    sass_instruction_read(shape->text, &base);
    for (unsigned int place = 0u; place < shape->operands; place += 1u)
    {
        memset(&places[place], 0, sizeof(places[place]));
        const unsigned int kind = shape->kind[place];
        // a label that names a symbol rather than a label of the text is a relocation: the field holds nothing and
        // the loader fills it, so the instruction is held to the one the shape was seen with
        const char *const open = strchr(base.operand[place], '(');
        const int relocated = (kind == SASS_OPERAND_LABEL) && ((open == NULL) || (open[1] != '.'));
        if ((kind == SASS_OPERAND_UNKNOWN) || (kind == SASS_OPERAND_SYSTEM) || relocated)
        {
            // a system register and anything else the assembler cannot count is held to the base's own text
            places[place].by_text = 1;
            continue;
        }
        // a branch's target is its own field, which crosses into the high word and shares its bits with no other
        if (kind == SASS_OPERAND_LABEL)
        {
            places[place].value.first = SASS_BRANCH_FIRST;
            places[place].value.bits = SASS_BRANCH_BITS;
            places[place].value.scale = 1u;
            continue;
        }
        int found = 0;
        for (unsigned int number = 0u; number < shape->runs; number += 1u)
        {
            const SassRun *const run = &shape->run[number];
            if (run->operand != place)
            {
                continue;
            }
            const SassField *const field = sass_field_at(kind, run);
            if (field != NULL)
            {
                places[place].value = *field;
                // a field holds no more bits than the run the probe saw change the operand
                const unsigned int room = (run->last - field->first) + 1u;
                places[place].value.bits = (room < field->bits) ? room : field->bits;
                found = 1;
            }
            if ((kind == SASS_OPERAND_ADDRESS) && (run->first == s_offset_fields[0].first))
            {
                places[place].offset = s_offset_fields[0];
                places[place].has_offset = 1;
            }
        }
        if (found == 0)
        {
            *unplaced = place;
            return 0;
        }
    }
    return 1;
}

// the scheduler's bits, every one of them above bit 63 and so in the high word alone
static void sass_high_write(unsigned long long *high, unsigned int first, unsigned int bits, unsigned long long value)
{
    const unsigned long long mask = (1ull << bits) - 1ull;
    *high = (*high & ~(mask << (first - 64u))) | ((value & mask) << (first - 64u));
}

// the scheduler's bits set so that every instruction waits for every one before it: the longest stall, no reuse, and
// a wait on every barrier. An instruction whose result comes back late has to set a barrier for the wait to have
// anything to wait on, and which instructions those are is read off the shape's own encoding: where the toolchain
// set a barrier for that shape, this sets one too. A barrier no instruction set is already at rest, so waiting on all
// six costs nothing where none was set
static void sass_control_safe(const SassShape *shape, unsigned long long *high)
{
    const unsigned long long was = shape->high;
    const unsigned int wrote =
        (unsigned int)((was >> (SASS_WRITE_BARRIER_FIRST - 64u)) & 7ull) != SASS_BARRIER_NONE;
    const unsigned int read = (unsigned int)((was >> (SASS_READ_BARRIER_FIRST - 64u)) & 7ull) != SASS_BARRIER_NONE;
    sass_high_write(high, SASS_STALL_FIRST, 4u, SASS_STALL_LONGEST);
    sass_high_write(high, SASS_YIELD_FIRST, 1u, 0ull);
    sass_high_write(high, SASS_WRITE_BARRIER_FIRST, 3u, (wrote != 0u) ? 0ull : SASS_BARRIER_NONE);
    sass_high_write(high, SASS_READ_BARRIER_FIRST, 3u, (read != 0u) ? 1ull : SASS_BARRIER_NONE);
    sass_high_write(high, SASS_WAIT_FIRST, 6u, SASS_WAIT_EVERY);
    sass_high_write(high, SASS_REUSE_FIRST, 4u, 0ull);
}

int sass_assemble(const SassMachine *machine, const char *text, unsigned long long address, unsigned long long target,
                  unsigned int control, unsigned long long *low, unsigned long long *high)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    const SassShape *const shape = sass_machine_shape(machine, &parts);
    if (shape == NULL)
    {
        printf("  sass_assemble: no shape for %s\n", text);
        return 0;
    }
    SassPlace places[SASS_MACHINE_OPERANDS];
    unsigned int unplaced = 0u;
    if (!sass_places_find(shape, places, &unplaced))
    {
        printf("  sass_assemble: operand %u of %s does not place in its own encoding\n", unplaced, shape->text);
        return 0;
    }
    SassInstructionParts base;
    sass_instruction_read(shape->text, &base);
    *low = shape->low;
    *high = shape->high;
    for (unsigned int place = 0u; place < parts.operands; place += 1u)
    {
        if (places[place].by_text != 0)
        {
            if (strcmp(parts.operand[place], base.operand[place]) != 0)
            {
                printf("  sass_assemble: %s takes %s where its shape holds %s\n", text, parts.operand[place],
                       base.operand[place]);
                return 0;
            }
            continue;
        }
        unsigned long long value = 0ull;
        unsigned long long offset = 0ull;
        sass_operand_value(&parts, place, address, target, &value, &offset);
        sass_bits_write(low, high, places[place].value.first, places[place].value.bits,
                        value / places[place].value.scale);
        if (places[place].has_offset != 0)
        {
            sass_bits_write(low, high, places[place].offset.first, places[place].offset.bits, offset);
        }
        // a constant's bank must be the one the shape holds, since the bank's own bits were not found by probing
        if (parts.kind[place] == SASS_OPERAND_CONSTANT)
        {
            unsigned long long bank = 0ull;
            unsigned long long base_bank = 0ull;
            sass_constant_value(parts.operand[place], &bank);
            sass_constant_value(base.operand[place], &base_bank);
            if (bank != base_bank)
            {
                printf("  sass_assemble: %s reads bank %llu where its shape reads %llu\n", text, bank, base_bank);
                return 0;
            }
        }
    }
    const unsigned long long guard = (parts.guard[0] == '\0')
                                         ? 7ull
                                         : sass_register_value(parts.guard + ((parts.guard[1] == '!') ? 2u : 1u));
    sass_bits_write(low, high, SASS_GUARD_FIRST, SASS_GUARD_BITS, guard);
    sass_bits_write(low, high, SASS_GUARD_NOT, 1u, (parts.guard[1] == '!') ? 1ull : 0ull);
    if (control == SASS_CONTROL_SAFE)
    {
        sass_control_safe(shape, high);
    }
    return 1;
}

// the most labels one text names, and the longest a label's name is
#define SASS_LABELS 256u
#define SASS_LABEL_TOKEN 64u

typedef struct
{
    unsigned int count;
    char name[SASS_LABELS][SASS_LABEL_TOKEN];
    unsigned long long address[SASS_LABELS];
} SassLabels;

// one line of a listing taken from `text` into `line` and `text` moved past it: the line with the spaces at either
// end cut, and the ';' a listing ends an instruction with dropped. NULL where the text is spent
static const char *sass_line_take(const char *text, char *line, size_t room)
{
    if ((text == NULL) || (*text == '\0'))
    {
        return NULL;
    }
    const size_t length = strcspn(text, "\n");
    size_t kept = length;
    while ((kept != 0u) && ((text[kept - 1u] == ' ') || (text[kept - 1u] == '\r') || (text[kept - 1u] == ';')))
    {
        kept -= 1u;
    }
    size_t first = 0u;
    while ((first < kept) && (text[first] == ' '))
    {
        first += 1u;
    }
    const size_t taken = ((kept - first) < (room - 1u)) ? (kept - first) : (room - 1u);
    memcpy(line, text + first, taken);
    line[taken] = '\0';
    return text + length + ((text[length] == '\n') ? 1u : 0u);
}

// what a line is: an instruction, a label, or neither
static int sass_line_is_label(const char *line)
{
    const size_t length = strlen(line);
    return (length != 0u) && (line[length - 1u] == ':');
}

static int sass_line_is_instruction(const char *line)
{
    return (line[0] != '\0') && (line[0] != '.') && (line[0] != '/') && (line[0] != '#') && !sass_line_is_label(line);
}

// the address the labels hold for `operand`, which a listing writes `(.L_x_0); the count where they hold none
static unsigned long long sass_label_address(const SassLabels *labels, const char *operand, int *known)
{
    const char *const open = strchr(operand, '(');
    const size_t length = (open != NULL) ? strcspn(open + 1, ")") : 0u;
    *known = 0;
    unsigned long long found = 0ull;
    for (unsigned int at = 0u; (open != NULL) && (at < labels->count); at += 1u)
    {
        if ((strlen(labels->name[at]) == length) && (strncmp(labels->name[at], open + 1, length) == 0))
        {
            found = labels->address[at];
            *known = 1;
        }
    }
    return found;
}

unsigned int sass_assemble_lines(const SassMachine *machine, const char *text, unsigned int control,
                                 unsigned char *code, unsigned long long room)
{
    static SassLabels s_labels;
    s_labels.count = 0u;
    char line[SASS_MACHINE_TEXT];
    unsigned long long address = 0ull;
    for (const char *walk = sass_line_take(text, line, sizeof(line)); walk != NULL;
         walk = sass_line_take(walk, line, sizeof(line)))
    {
        if (sass_line_is_label(line) && (s_labels.count < SASS_LABELS))
        {
            snprintf(s_labels.name[s_labels.count], SASS_LABEL_TOKEN, "%.*s", (int)(strlen(line) - 1u), line);
            s_labels.address[s_labels.count] = address;
            s_labels.count += 1u;
        }
        address += sass_line_is_instruction(line) ? 16ull : 0ull;
    }
    const unsigned long long bytes = address;
    if (bytes > room)
    {
        printf("  sass_assemble: %llu bytes of code where the room is %llu\n", bytes, room);
        return 0u;
    }
    address = 0ull;
    for (const char *walk = sass_line_take(text, line, sizeof(line)); walk != NULL;
         walk = sass_line_take(walk, line, sizeof(line)))
    {
        if (!sass_line_is_instruction(line))
        {
            continue;
        }
        SassInstructionParts parts;
        sass_instruction_read(line, &parts);
        unsigned long long target = 0ull;
        int known = 1;
        for (unsigned int place = 0u; place < parts.operands; place += 1u)
        {
            const char *const open = strchr(parts.operand[place], '(');
            // a label of the text names where it stands; a symbol is a relocation the loader fills, and the text
            // says nothing about where it will be
            if ((parts.kind[place] == SASS_OPERAND_LABEL) && (open != NULL) && (open[1] == '.'))
            {
                target = sass_label_address(&s_labels, parts.operand[place], &known);
            }
        }
        if (known == 0)
        {
            printf("  sass_assemble: %s names a label the text does not\n", line);
            return 0u;
        }
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        if (!sass_assemble(machine, line, address, target, control, &low, &high))
        {
            return 0u;
        }
        for (unsigned int byte = 0u; byte < 8u; byte += 1u)
        {
            // each word is written low byte first, as the part reads it
            code[address + byte] = (unsigned char)((low >> (8u * byte)) & 0xffu);
            code[address + 8ull + byte] = (unsigned char)((high >> (8u * byte)) & 0xffu);
        }
        address += 16ull;
    }
    return (unsigned int)(bytes / 16ull);
}
