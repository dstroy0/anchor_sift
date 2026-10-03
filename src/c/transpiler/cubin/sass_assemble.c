// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sass_assemble.c: an operand's value, the fields a form's operands sit in, and one line assembled
#include "sass_assemble.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the guard predicate: three bits its number and the fourth the negation
#define SASS_GUARD_FIRST 12u
#define SASS_GUARD_BITS 3u
#define SASS_GUARD_NOT 15u
// every barrier waited on: the scheduler's fields themselves, and the longest stall they hold, are the form's
// (sass_machine.h)
#define SASS_WAIT_EVERY 0x3fu
// a branch counts its target from the instruction after it, in a signed field that begins at bit 32 and runs into the
// high word: the one branch the probes read back holds -16, and every bit of it from 32 to 81 is set
// a branch's distance in four-byte steps from bit 34 to bit 81: bits 32 and 33 below it are the operation's own,
// as BRA, BRA.U and BRA.DIV show, the same distance with 0, 1 and 2 there
#define SASS_BRANCH_FIRST 34u
#define SASS_BRANCH_BITS 48u
#define SASS_BRANCH_STEP 4u

// one place a value sits: its first bit, how many bits it holds, what one of them counts, and 1 where the field holds
// the value with every bit inverted
typedef struct
{
    unsigned int first;
    unsigned int bits;
    unsigned int scale;
    unsigned int inverted;
} SassField;

// the fields a kind of operand may sit in, in the order an instruction fills them
static const SassField s_register_fields[] = {{16u, 8u, 1u}, {24u, 8u, 1u}, {32u, 8u, 1u}, {64u, 8u, 1u}};
// A predicate operand takes three bits and the fourth negates it; the probes found six places one sits in. A load's
// predicate at 64 holds its number inverted, PT as 000, and a load whose predicate is false writes 0
// (interface_sass_unprinted.md)
static const SassField s_predicate_fields[] = {{64u, 3u, 1u, 1u}, {68u, 3u, 1u}, {77u, 3u, 1u},
                                               {81u, 3u, 1u},     {84u, 3u, 1u}, {87u, 3u, 1u}};
static const SassField s_immediate_fields[] = {{32u, 32u, 1u}, {72u, 8u, 1u}};
// a constant's offset counts words, and an address's bytes; both lie above the register fields
static const SassField s_constant_fields[] = {{40u, 16u, 4u}};
static const SassField s_offset_fields[] = {{40u, 24u, 1u}};
// The uniform register a memory operand reads its descriptor from, in the order an instruction fills them: bits 32 to
// 37 where no other operand holds bit 32, as a load has it, else 64 to 69, as a store has it. A memory operand that
// takes one is an address with a run of its own at bit 101, the bit that says whether the descriptor is printed:
// set, desc[URn]; clear, term[URn]
static const SassField s_descriptor_fields[] = {{32u, 6u, 1u}, {64u, 6u, 1u}};
#define SASS_DESCRIPTOR_FIELDS (sizeof(s_descriptor_fields) / sizeof(s_descriptor_fields[0]))
#define SASS_DESCRIPTOR_SHOWN 101u
// the field's value for URZ, every bit of it set
#define SASS_DESCRIPTOR_ZERO 63ull

#define SASS_REGISTER_FIELDS (sizeof(s_register_fields) / sizeof(s_register_fields[0]))
#define SASS_PREDICATE_FIELDS (sizeof(s_predicate_fields) / sizeof(s_predicate_fields[0]))
#define SASS_IMMEDIATE_FIELDS (sizeof(s_immediate_fields) / sizeof(s_immediate_fields[0]))

// where one operand of a form was placed: the field its value sits in, and for an address the field its offset sits
// in as well
typedef struct
{
    SassField value;
    SassField offset;
    int has_offset;
    int by_text;
    // for a memory operand that reads a descriptor, the field its uniform register sits in
    SassField descriptor;
    int has_descriptor;
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

// The number a register, predicate or uniform register names: RZ is 255 and PT is 7. A name ending in .hi is the
// high half of what it is written on (sass.krs), which for a register is the second register of a 64-bit pair, one
// past the one it is named from; RZ has no second half, since a pair of zero words reads zero at both. The high half
// of a number is its high word, which sass_operand_value takes
static unsigned long long sass_register_value(const char *text)
{
    if (strncmp(text, "RZ", 2u) == 0)
    {
        return 255ull;
    }
    if (strncmp(text, "PT", 2u) == 0)
    {
        return 7ull;
    }
    const char *const digits = text + ((text[0] == 'U') ? 2u : 1u);
    return strtoull(digits, NULL, 10) + (sass_high_half(text) ? 1ull : 0ull);
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
    {
        // .hi is the high half of the thing it is written on, whatever that thing is (sass.krs): for a register it
        // is the pair's second register, and for a number it is the number's high word. strtoull stops at the dot:
        // so the stem is read and shifted; a negative number is shifted as the 64-bit word it is written into
        const unsigned long long whole = (text[0] == '-')
                                             ? (unsigned long long)(-(long long)strtoull(text + 1, NULL, 0))
                                             : strtoull(text, NULL, 0);
        *value = sass_high_half(text) ? (whole >> 32u) : whole;
        return 1;
    }
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
// saw change one operand, being the field and whatever lies beside it that changes the same operand. A bit that
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

// the form's operands placed in the fields the probe's runs name: each operand takes the run that begins where a
// field of its kind begins, and an address takes the offset field beside its base register. 1 where every operand was
// placed, else 0 and the operand that could not be
static int sass_places_find(const SassForm *form, SassPlace *places, unsigned int *unplaced)
{
    SassInstructionParts base;
    sass_instruction_read(form->text, &base);
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        memset(&places[place], 0, sizeof(places[place]));
        const unsigned int kind = form->kind[place];
        // a label that names a symbol and not a label of the text is a relocation: the field holds nothing and
        // the loader fills it. The instruction is then checked against the one the form was seen with
        const char *const open = strchr(base.operand[place], '(');
        const int relocated = (kind == SASS_OPERAND_LABEL) && ((open == NULL) || (open[1] != '.'));
        if ((kind == SASS_OPERAND_UNKNOWN) || (kind == SASS_OPERAND_SYSTEM) || relocated)
        {
            // a system register and anything else the assembler cannot count is checked against the base's own text
            places[place].by_text = 1;
            continue;
        }
        // a branch's target is its own field, which crosses into the high word and shares its bits with no other
        if (kind == SASS_OPERAND_LABEL)
        {
            places[place].value.first = SASS_BRANCH_FIRST;
            places[place].value.bits = SASS_BRANCH_BITS;
            places[place].value.scale = SASS_BRANCH_STEP;
            continue;
        }
        // A number in the bits a branch's distance sits in is that distance: the probe found its run beginning there and
        // reaching into the high word. A run that begins there and ends inside the low word is a field of its own, as
        // BPT.TRAP's code is, three bits from bit 34
        int distance = 0;
        for (unsigned int number = 0u; (kind == SASS_OPERAND_IMMEDIATE) && (number < form->runs); number += 1u)
        {
            distance = distance || ((form->run[number].operand == place) &&
                                    (form->run[number].first == SASS_BRANCH_FIRST) && (form->run[number].last >= 63u));
        }
        if (distance)
        {
            places[place].value.first = SASS_BRANCH_FIRST;
            places[place].value.bits = SASS_BRANCH_BITS;
            places[place].value.scale = SASS_BRANCH_STEP;
            continue;
        }
        int found = 0;
        for (unsigned int number = 0u; number < form->runs; number += 1u)
        {
            const SassRun *const run = &form->run[number];
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
        // a memory operand with a run of its own at the bit that shows the descriptor reads one, and its uniform
        // register takes the first descriptor field no run of the form holds
        int shown = 0;
        for (unsigned int number = 0u; (kind == SASS_OPERAND_ADDRESS) && (number < form->runs); number += 1u)
        {
            shown = shown || ((form->run[number].operand == place) && (form->run[number].first == SASS_DESCRIPTOR_SHOWN) &&
                              (form->run[number].last == SASS_DESCRIPTOR_SHOWN));
        }
        for (unsigned int at = 0u; shown && (places[place].has_descriptor == 0) && (at < SASS_DESCRIPTOR_FIELDS); at += 1u)
        {
            const SassField *const field = &s_descriptor_fields[at];
            int held = 0;
            for (unsigned int number = 0u; number < form->runs; number += 1u)
            {
                held = held || ((form->run[number].first < (field->first + field->bits)) &&
                                (form->run[number].last >= field->first));
            }
            if (held == 0)
            {
                places[place].descriptor = *field;
                places[place].has_descriptor = 1;
            }
        }
        // Where no field of the operand's kind begins inside a run of its own, the widest run the probe saw change the
        // operand is its field, from the run's first bit and as long as the run: BPT.TRAP's code begins at bit 34,
        // where no immediate field of the list above begins. An operand a field above places is placed there as it was
        const int counted = (kind == SASS_OPERAND_IMMEDIATE) || (kind == SASS_OPERAND_REGISTER) ||
                            (kind == SASS_OPERAND_PREDICATE) || (kind == SASS_OPERAND_UNIFORM);
        const SassRun *widest = NULL;
        for (unsigned int number = 0u; (found == 0) && counted && (number < form->runs); number += 1u)
        {
            const SassRun *const run = &form->run[number];
            const int wider = (widest == NULL) || ((run->last - run->first) > (widest->last - widest->first));
            widest = ((run->operand == place) && wider) ? run : widest;
        }
        if ((found == 0) && (widest != NULL))
        {
            places[place].value.first = widest->first;
            places[place].value.bits = (widest->last - widest->first) + 1u;
            places[place].value.scale = 1u;
            found = 1;
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
// anything to wait on, and a store has to set one for whatever writes its operands next: which instructions those
// are is the operation's schedule (sass_operation_schedule), and a barrier the form's own encoding sets is set too. A
// barrier no instruction set is already at rest, and waiting on all six costs nothing where none was set
static void sass_control_safe(const SassForm *form, unsigned long long *high)
{
    unsigned int soonest = 0u;
    const unsigned int schedule = sass_operation_schedule(form->operation, &soonest);
    const int wrote = (schedule == SASS_SCHEDULE_LATE) || sass_barrier_set(form->high, SASS_WRITE_BARRIER_FIRST);
    const int read = (schedule == SASS_SCHEDULE_STORE) || sass_barrier_set(form->high, SASS_READ_BARRIER_FIRST);
    sass_high_write(high, SASS_STALL_FIRST, 4u, SASS_STALL_LONGEST);
    sass_high_write(high, SASS_YIELD_FIRST, 1u, 0ull);
    sass_high_write(high, SASS_WRITE_BARRIER_FIRST, 3u, wrote ? 0ull : SASS_BARRIER_NONE);
    sass_high_write(high, SASS_READ_BARRIER_FIRST, 3u, read ? 1ull : SASS_BARRIER_NONE);
    sass_high_write(high, SASS_WAIT_FIRST, 6u, SASS_WAIT_EVERY);
    sass_high_write(high, SASS_REUSE_FIRST, 4u, 0ull);
}

int sass_assemble(const SassMachine *machine, const char *text, unsigned long long address, unsigned long long target,
                  unsigned int control, unsigned long long *low, unsigned long long *high)
{
    SassInstructionParts parts;
    sass_instruction_read(text, &parts);
    const SassForm *const form = sass_machine_form(machine, &parts);
    if (form == NULL)
    {
        printf("  sass_assemble: no form for %s\n", text);
        return 0;
    }
    SassPlace places[SASS_MACHINE_OPERANDS];
    unsigned int unplaced = 0u;
    if (!sass_places_find(form, places, &unplaced))
    {
        printf("  sass_assemble: operand %u of %s does not place in its own encoding\n", unplaced, form->text);
        return 0;
    }
    // two operands a form prints from one field, as BAR.SYNC R0, R0 prints its one register, name one value
    for (unsigned int place = 0u; place < parts.operands; place += 1u)
    {
        for (unsigned int other = place + 1u; (places[place].by_text == 0) && (other < parts.operands); other += 1u)
        {
            unsigned long long one = 0ull;
            unsigned long long two = 0ull;
            unsigned long long offset = 0ull;
            const int shared = (places[other].by_text == 0) && (places[other].value.first == places[place].value.first);
            if (shared && sass_operand_value(&parts, place, address, target, &one, &offset) &&
                sass_operand_value(&parts, other, address, target, &two, &offset) && (one != two))
            {
                printf("  sass_assemble: %s names two values for the one field operands %u and %u share\n", text, place,
                       other);
                return 0;
            }
        }
    }
    SassInstructionParts base;
    sass_instruction_read(form->text, &base);
    *low = form->low;
    *high = form->high;
    // An operand the form holds and does not print keeps the bits the form was seen with. NVIDIA writes !PT into the
    // carry-in IMAD reads as IMAD.X and PT into the predicate ISETP reads as .EX, and the part answers alike at every
    // value of either without its modifier (interface_sass_unprinted.md)
    for (unsigned int place = 0u; place < parts.operands; place += 1u)
    {
        if (places[place].by_text != 0)
        {
            if (strcmp(parts.operand[place], base.operand[place]) != 0)
            {
                printf("  sass_assemble: %s takes %s where its form holds %s\n", text, parts.operand[place],
                       base.operand[place]);
                return 0;
            }
            continue;
        }
        unsigned long long value = 0ull;
        unsigned long long offset = 0ull;
        sass_operand_value(&parts, place, address, target, &value, &offset);
        const unsigned long long counted = value / places[place].value.scale;
        sass_bits_write(low, high, places[place].value.first, places[place].value.bits,
                        (places[place].value.inverted != 0u) ? ~counted : counted);
        if (places[place].has_offset != 0)
        {
            sass_bits_write(low, high, places[place].offset.first, places[place].offset.bits, offset);
        }
        // A memory operand that names its descriptor writes the uniform register into the descriptor field and says
        // whether it is shown: desc[URn] sets bit 101 and term[URn] clears it. One that names none keeps both as its
        // form holds them
        const int named = (strncmp(parts.operand[place], "desc[", 5u) == 0) ||
                          (strncmp(parts.operand[place], "term[", 5u) == 0);
        if ((places[place].has_descriptor != 0) && named)
        {
            const char *const uniform = parts.operand[place] + 5;
            const unsigned long long descriptor = (strncmp(uniform, "URZ", 3u) == 0) ? SASS_DESCRIPTOR_ZERO
                                                                                    : sass_register_value(uniform);
            sass_bits_write(low, high, places[place].descriptor.first, places[place].descriptor.bits, descriptor);
            sass_bits_write(low, high, SASS_DESCRIPTOR_SHOWN, 1u, (parts.operand[place][0] == 'd') ? 1ull : 0ull);
        }
        // a constant's bank must be the one the form holds, since the bank's own bits were not found by probing
        if (parts.kind[place] == SASS_OPERAND_CONSTANT)
        {
            unsigned long long bank = 0ull;
            unsigned long long base_bank = 0ull;
            sass_constant_value(parts.operand[place], &bank);
            sass_constant_value(base.operand[place], &base_bank);
            if (bank != base_bank)
            {
                printf("  sass_assemble: %s reads bank %llu where its form reads %llu\n", text, bank, base_bank);
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
        sass_control_safe(form, high);
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
    // a listing indents with spaces and a ruleset with tabs, and both end an instruction with a semicolon
    while ((kept != 0u) && ((text[kept - 1u] == ' ') || (text[kept - 1u] == '\t') || (text[kept - 1u] == '\r') ||
                            (text[kept - 1u] == ';')))
    {
        kept -= 1u;
    }
    size_t first = 0u;
    while ((first < kept) && ((text[first] == ' ') || (text[first] == '\t')))
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

// `bits` bits of an encoding from bit `first`
static unsigned long long sass_bits_read(unsigned long long low, unsigned long long high, unsigned int first,
                                         unsigned int bits)
{
    unsigned long long value = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int at = first + bit;
        const unsigned long long word = (at < 64u) ? low : high;
        const unsigned int place = (at < 64u) ? at : (at - 64u);
        value |= ((word >> place) & 1ull) << bit;
    }
    return value;
}

// `value` read as a two's complement number `bits` wide
static long long sass_signed(unsigned long long value, unsigned int bits)
{
    if ((bits == 0u) || (bits >= 64u))
    {
        return (long long)value;
    }
    const unsigned long long top = 1ull << (bits - 1u);
    return (long long)((value ^ top) - top);
}

// the bits a form leaves to its operands, its guard and the scheduler, set in `low` and `high`, and how many
static unsigned int sass_open_bits(const SassForm *form, const SassPlace *places, unsigned long long *low,
                                   unsigned long long *high)
{
    *low = 0ull;
    *high = 0ull;
    sass_bits_write(low, high, SASS_GUARD_FIRST, SASS_GUARD_BITS + 1u, ~0ull);
    sass_bits_write(low, high, SASS_STALL_FIRST, 128u - SASS_STALL_FIRST, ~0ull);
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        if (places[place].by_text != 0)
        {
            continue;
        }
        sass_bits_write(low, high, places[place].value.first, places[place].value.bits, ~0ull);
        if (places[place].has_offset != 0)
        {
            sass_bits_write(low, high, places[place].offset.first, places[place].offset.bits, ~0ull);
        }
        if (places[place].has_descriptor != 0)
        {
            sass_bits_write(low, high, places[place].descriptor.first, places[place].descriptor.bits, ~0ull);
            sass_bits_write(low, high, SASS_DESCRIPTOR_SHOWN, 1u, ~0ull);
        }
    }
    // an operand the form holds and does not print is the operand's, whatever value an encoding gives it
    for (unsigned int number = 0u; number < form->runs; number += 1u)
    {
        const SassRun *const run = &form->run[number];
        if (run->operand >= form->operands)
        {
            sass_bits_write(low, high, run->first, (run->last - run->first) + 1u, ~0ull);
        }
    }
    unsigned int count = 0u;
    for (unsigned int bit = 0u; bit < 64u; bit += 1u)
    {
        count += (unsigned int)(((*low >> bit) & 1ull) + ((*high >> bit) & 1ull));
    }
    return count;
}

// 1 where an operand of the form is a label that names a symbol, whose field holds nothing to read
static int sass_form_relocated(const SassForm *form, const SassPlace *places)
{
    int relocated = 0;
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        relocated = relocated || ((form->kind[place] == SASS_OPERAND_LABEL) && (places[place].by_text != 0));
    }
    return relocated;
}

// 1 where `form` is `other`'s operation and reads as a label an operand `other` reads as a number: a branch's distance
// is read as the place it lands, which a number in the same bits does not say
static int sass_form_lands(const SassForm *form, const SassForm *other)
{
    if ((other == NULL) || (strcmp(form->operation, other->operation) != 0) || (form->operands != other->operands))
    {
        return 0;
    }
    int lands = 0;
    for (unsigned int place = 0u; place < form->operands; place += 1u)
    {
        lands = lands || ((form->kind[place] == SASS_OPERAND_LABEL) && (other->kind[place] == SASS_OPERAND_IMMEDIATE));
    }
    return lands;
}

// the form whose own bits the encoding holds outside what it leaves open, and that form's places through `places`.
// Of several: one that reads every field before one with a relocated label, whose field holds nothing; a label
// before a number of the same operation; then the one leaving the fewest bits open. NULL where none holds it
// the most forms one encoding is held by that the reader weighs
#define SASS_HOLDERS 32u

// one form that holds an encoding, where its operands sit, and how many bits it leaves to them
typedef struct
{
    const SassForm *form;
    SassPlace places[SASS_MACHINE_OPERANDS];
    unsigned int open;
} SassHolder;

// 1 where `named` is `plain` with modifiers added: the two share their name up to its first dot, and every modifier
// `plain` carries `named` carries too, as IMAD.IADD carries IMAD's and IMAD.MOV.U32 carries IMAD.U32's
static int sass_name_within(const char *plain, const char *named)
{
    const size_t length = strcspn(plain, ".");
    int within = (strcspn(named, ".") == length) && (strncmp(plain, named, length) == 0) &&
                 (strlen(plain) < strlen(named));
    for (const char *walk = plain + length; within && (*walk == '.'); walk += 1u + strcspn(walk + 1, "."))
    {
        const size_t modifier = 1u + strcspn(walk + 1, ".");
        int carried = 0;
        for (const char *seek = named + length; !carried && (*seek == '.'); seek += 1u + strcspn(seek + 1, "."))
        {
            carried = ((1u + strcspn(seek + 1, ".")) == modifier) && (strncmp(seek, walk, modifier) == 0);
        }
        within = carried;
    }
    return within;
}

// How `holder` stands against `sibling` where `holder` takes its name from one value of an operand: a sibling holding
// the same encoding, with the same operation's name before its first dot, the same kinds and the same marks, is named
// shorter, and the two forms' own values of an operand differ. -1 where the encoding's value there is not `holder`'s,
// which names it away; 1 where every such value is `holder`'s, which names it; 0 where the two are no such pair.
// IMAD.MOV and IMAD.IADD are IMAD with a multiplier of 0 and of 1, and IMAD.MOV is IMAD with RZ as the register it
// multiplies by: an encoding with any other multiplier is IMAD's
static int sass_holder_named(const SassHolder *holder, const SassHolder *sibling, unsigned long long low,
                             unsigned long long high)
{
    const SassForm *const form = holder->form;
    const SassForm *const other = sibling->form;
    int same = (form != other) && sass_name_within(other->operation, form->operation) &&
               (form->operands == other->operands);
    for (unsigned int place = 0u; same && (place < form->operands); place += 1u)
    {
        same = (form->kind[place] == other->kind[place]) && (form->mark[place] == other->mark[place]);
    }
    int differs = 0;
    int away = 0;
    for (unsigned int place = 0u; same && (place < form->operands); place += 1u)
    {
        const SassField *const field = &holder->places[place].value;
        const SassField *const field_other = &sibling->places[place].value;
        if ((holder->places[place].by_text != 0) || (field->bits == 0u) || (field_other->bits == 0u))
        {
            continue;
        }
        const unsigned long long own = sass_bits_read(form->low, form->high, field->first, field->bits);
        const unsigned long long theirs = sass_bits_read(other->low, other->high, field_other->first,
                                                         field_other->bits);
        const unsigned long long given = sass_bits_read(low, high, field->first, field->bits);
        // the value a name is taken from is a multiplier of 0 or 1, a number 0 or 1 or the register RZ; a register
        // the two forms' encodings were seen with apart from that is the encoding's own and names nothing
        const int naming = ((form->kind[place] == SASS_OPERAND_IMMEDIATE) && (own <= 1ull)) ||
                           ((form->kind[place] == SASS_OPERAND_REGISTER) && (own == 255ull));
        differs = differs || (naming && (own != theirs));
        away = away || (naming && (own != theirs) && (given != own));
    }
    return away ? -1 : (differs ? 1 : 0);
}

static const SassForm *sass_encoding_form(const SassMachine *machine, unsigned long long low, unsigned long long high,
                                          SassPlace *places)
{
    SassHolder holders[SASS_HOLDERS];
    unsigned int held = 0u;
    for (unsigned int number = 0u; (number < machine->forms) && (held < SASS_HOLDERS); number += 1u)
    {
        SassHolder *const holder = &holders[held];
        holder->form = &machine->form[number];
        unsigned int unplaced = 0u;
        if (!sass_places_find(holder->form, holder->places, &unplaced))
        {
            continue;
        }
        unsigned long long open_low = 0ull;
        unsigned long long open_high = 0ull;
        holder->open = sass_open_bits(holder->form, holder->places, &open_low, &open_high);
        if ((((low ^ holder->form->low) & ~open_low) == 0ull) && (((high ^ holder->form->high) & ~open_high) == 0ull))
        {
            held += 1u;
        }
    }
    const SassHolder *found = NULL;
    int found_relocated = 1;
    for (unsigned int number = 0u; number < held; number += 1u)
    {
        const SassHolder *const holder = &holders[number];
        int away = 0;
        for (unsigned int other = 0u; (away == 0) && (other < held); other += 1u)
        {
            away = (sass_holder_named(holder, &holders[other], low, high) < 0);
        }
        if (away != 0)
        {
            continue;
        }
        const SassForm *const form = holder->form;
        const SassForm *const was = (found != NULL) ? found->form : NULL;
        const int relocated = sass_form_relocated(form, holder->places);
        // a form a value names takes the encoding from the sibling it is named past, and keeps it from that sibling
        const int named = (found != NULL) && (sass_holder_named(holder, found, low, high) > 0);
        const int kept = (found != NULL) && (sass_holder_named(found, holder, low, high) > 0);
        const int fewer = (found == NULL) || named || (!kept && (holder->open < found->open));
        const int better = (found == NULL) || (found_relocated && !relocated) ||
                           ((relocated == found_relocated) &&
                            (sass_form_lands(form, was) || (!sass_form_lands(was, form) && fewer)));
        if (better)
        {
            found = holder;
            found_relocated = relocated;
        }
    }
    if (found != NULL)
    {
        memcpy(places, found->places, sizeof(found->places));
    }
    return (found != NULL) ? found->form : NULL;
}

// the text of operand `at`, read from where the assembler writes it
static void sass_operand_read(const SassForm *form, const SassInstructionParts *base, const SassPlace *place,
                              unsigned int at, unsigned long long low, unsigned long long high,
                              unsigned long long address, char *operand, size_t room)
{
    static const char *const s_marks[] = {"", "-", "~", "!"};
    const char *const mark = (form->mark[at] < (sizeof(s_marks) / sizeof(s_marks[0]))) ? s_marks[form->mark[at]] : "";
    if (place->by_text != 0)
    {
        snprintf(operand, room, "%s%s", mark, base->operand[at]);
        return;
    }
    const unsigned long long held = sass_bits_read(low, high, place->value.first, place->value.bits);
    const unsigned long long mask = (place->value.bits < 64u) ? ((1ull << place->value.bits) - 1ull) : ~0ull;
    const unsigned long long value = ((place->value.inverted != 0u) ? (~held & mask) : held) * place->value.scale;
    switch (form->kind[at])
    {
    case SASS_OPERAND_REGISTER:
        (value == 255ull) ? snprintf(operand, room, "%sRZ", mark) : snprintf(operand, room, "%sR%llu", mark, value);
        return;
    case SASS_OPERAND_UNIFORM:
        (value == 63ull) ? snprintf(operand, room, "%sURZ", mark) : snprintf(operand, room, "%sUR%llu", mark, value);
        return;
    case SASS_OPERAND_PREDICATE:
        (value == 7ull) ? snprintf(operand, room, "%sPT", mark) : snprintf(operand, room, "%sP%llu", mark, value);
        return;
    case SASS_OPERAND_IMMEDIATE:
        if (place->value.first == SASS_BRANCH_FIRST)
        {
            // a distance, signed over its field
            const long long distance =
                sass_signed(value / place->value.scale, place->value.bits) * (long long)place->value.scale;
            snprintf(operand, room, "%s%s0x%llx", mark, (distance < 0) ? "-" : "",
                     (unsigned long long)((distance < 0) ? -distance : distance));
            return;
        }
        snprintf(operand, room, "%s0x%llx", mark, value);
        return;
    case SASS_OPERAND_LABEL:
        // a branch counts its target from the instruction after it, and the field holds a two's complement distance
        snprintf(operand, room, "`(0x%llx)",
                 address + 16ull +
                     (unsigned long long)(sass_signed(value / place->value.scale, place->value.bits) *
                                          (long long)place->value.scale));
        return;
    case SASS_OPERAND_CONSTANT:
    {
        unsigned long long bank = 0ull;
        sass_constant_value(base->operand[at], &bank);
        snprintf(operand, room, "%sc[0x%llx][0x%llx]", mark, bank, value);
        return;
    }
    case SASS_OPERAND_ADDRESS:
    {
        const unsigned long long offset =
            (place->has_offset != 0) ? sass_bits_read(low, high, place->offset.first, place->offset.bits) : 0ull;
        const char *const wide = (strstr(base->operand[at], ".64") != NULL) ? ".64" : "";
        char named[16];
        (value == 255ull) ? snprintf(named, sizeof(named), "RZ%s", wide)
                          : snprintf(named, sizeof(named), "R%llu%s", value, wide);
        // a memory operand that reads a descriptor names its uniform register, desc[] where bit 101 shows it and term[]
        // where it does not
        char held[24] = "";
        if (place->has_descriptor != 0)
        {
            const unsigned long long descriptor =
                sass_bits_read(low, high, place->descriptor.first, place->descriptor.bits);
            const int shown = (int)sass_bits_read(low, high, SASS_DESCRIPTOR_SHOWN, 1u);
            (descriptor == SASS_DESCRIPTOR_ZERO) ? snprintf(held, sizeof(held), "%s[URZ]", shown ? "desc" : "term")
                                                 : snprintf(held, sizeof(held), "%s[UR%llu]", shown ? "desc" : "term",
                                                            descriptor);
        }
        (offset == 0ull) ? snprintf(operand, room, "%s[%s]", held, named)
                         : snprintf(operand, room, "%s[%s+0x%llx]", held, named, offset);
        return;
    }
    default:
        snprintf(operand, room, "%s%s", mark, base->operand[at]);
        return;
    }
}

int sass_encoding_read(const SassMachine *machine, unsigned long long low, unsigned long long high,
                       unsigned long long address, char *text, size_t room)
{
    SassPlace places[SASS_MACHINE_OPERANDS];
    const SassForm *const form = sass_encoding_form(machine, low, high, places);
    if (form == NULL)
    {
        snprintf(text, room, "no form");
        return 0;
    }
    SassInstructionParts base;
    sass_instruction_read(form->text, &base);
    const unsigned long long guard = sass_bits_read(low, high, SASS_GUARD_FIRST, SASS_GUARD_BITS);
    const unsigned long long negated = sass_bits_read(low, high, SASS_GUARD_NOT, 1u);
    size_t at = 0u;
    if ((guard != 7ull) || (negated != 0ull))
    {
        char predicate[16];
        (guard == 7ull) ? snprintf(predicate, sizeof(predicate), "PT")
                        : snprintf(predicate, sizeof(predicate), "P%llu", guard);
        at += (size_t)snprintf(text + at, room - at, "@%s%s ", (negated != 0ull) ? "!" : "", predicate);
    }
    at += (size_t)snprintf(text + at, (at < room) ? (room - at) : 0u, "%s", form->operation);
    for (unsigned int place = 0u; (place < form->operands) && (at < room); place += 1u)
    {
        char operand[SASS_MACHINE_TOKEN];
        sass_operand_read(form, &base, &places[place], place, low, high, address, operand, sizeof(operand));
        at += (size_t)snprintf(text + at, room - at, "%s%s", (place == 0u) ? " " : ", ", operand);
    }
    return 1;
}

int sass_loop_walk(const SassMachine *machine, const SassLoopWalk *walk, unsigned long long low, unsigned long long high,
                   unsigned int *step)
{
    unsigned int stopped = 0u;
    int through = 0;
    SassPlace places[SASS_MACHINE_OPERANDS];
    const SassForm *const form = sass_encoding_form(machine, low, high, places);
    if (form != NULL)
    {
        stopped = 1u;
        const unsigned long long guard = sass_bits_read(low, high, SASS_GUARD_FIRST, SASS_GUARD_BITS);
        const unsigned long long negated = sass_bits_read(low, high, SASS_GUARD_NOT, 1u);
        if ((guard == walk->flag) && (negated == 0ull))
        {
            stopped = 2u;
            int lands = 0;
            for (unsigned int place = 0u; place < form->operands; place += 1u)
            {
                const unsigned int kind = form->kind[place];
                if ((places[place].by_text != 0) || ((kind != SASS_OPERAND_LABEL) && (kind != SASS_OPERAND_IMMEDIATE)))
                {
                    continue;
                }
                const unsigned long long value =
                    sass_bits_read(low, high, places[place].value.first, places[place].value.bits) *
                    places[place].value.scale;
                const long long distance = sass_signed(value / places[place].value.scale, places[place].value.bits) *
                                           (long long)places[place].value.scale;
                const unsigned long long landing = walk->address + 16ull + (unsigned long long)distance;
                lands = lands || (landing == walk->target);
            }
            if (lands)
            {
                stopped = 3u;
                int writes = 0;
                if ((form->operands > 0u) && (places[0].by_text == 0))
                {
                    const unsigned long long first =
                        sass_bits_read(low, high, places[0].value.first, places[0].value.bits);
                    for (unsigned int kept = 0u; (form->kind[0] == SASS_OPERAND_REGISTER) && (kept < walk->lives);
                         kept += 1u)
                    {
                        writes = writes || (first == walk->live[kept]);
                    }
                    writes = writes || ((form->kind[0] == SASS_OPERAND_PREDICATE) && (first == walk->flag));
                }
                if (!writes)
                {
                    stopped = 4u;
                    through = 1;
                }
            }
        }
    }
    if (step != NULL)
    {
        *step = stopped;
    }
    return through;
}
