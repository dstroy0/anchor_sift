// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_TEXT_H
#define EMIT_TEXT_H

// The emitter's text as a record program, the emitter's work where the programs run (engine_table.md item
// 11(f)(a), the emitter on the device). The core decides the forms of the language's ruleset a lane is written in
// (emit_core.h, EmitCoreItem); the text program writes their text from the ruleset's own written forms laid as tables,
// a lane a byte. Each lane reads one form, by the index, finds which of the form's pieces holds its byte, and writes
// that byte: a letter of a piece of the form's text, of a bank's written form around a register's number, of a word the
// ruleset holds whole, or a decimal digit of a number. A lane past its form's end writes 0, which no text holds: the
// text is the lanes' bytes in lane order with the zeros left out. The host lays once what is the ruleset's, the target's
// and the header's alone (emit_text_ruleset_lay); the forms' records are laid from the items by the functions below,
// which the device runs (emit_device.h) and the host oracle runs (emit_text_host): the two lay them from one source

#include "emit.h"
#include "emit_core.h"

#include <string>
#include <vector>

// the arguments one record of the text program holds, each a word the ruleset holds whole or a number between two
// words (a bank's written form around a register's number); a form with more slots takes a record for each four
#define EMIT_TEXT_SLOTS 4u

// the numbers the program writes are 32-bit words, ten digits at most
#define EMIT_TEXT_DIGITS 10u

// A record of the text program is one form, or four slots of one, as a part: the part's number, the first lane of
// the lanes that write it, and each slot's argument as the word before its number, the word after it, the number, and
// whether it has one. A part is the form's pieces around its slots: the piece before each of its slots, then the piece
// after its last where the form ends there, empty where it goes on in the next part. Its bytes are seventeen atoms in
// order: a piece, then a slot's word before, its number's digits and its word after, four times, then the last piece
#define EMIT_TEXT_PIECES (EMIT_TEXT_SLOTS + 1u)

#define EMIT_TEXT_ATOMS ((4u * EMIT_TEXT_SLOTS) + 1u)

// the record's fields, their bits and where each begins
#define EMIT_TEXT_PART_BITS 16u
#define EMIT_TEXT_FIRST_AT 16u
#define EMIT_TEXT_FIRST_BITS 32u
#define EMIT_TEXT_SLOT_AT 48u
#define EMIT_TEXT_SLOT_BITS 80u
#define EMIT_TEXT_WORD_BITS 16u
#define EMIT_TEXT_NUMBER_BITS 32u
#define EMIT_TEXT_RECORD_BITS (EMIT_TEXT_SLOT_AT + (EMIT_TEXT_SLOTS * EMIT_TEXT_SLOT_BITS))
#define EMIT_TEXT_RECORD_LIMBS ((EMIT_TEXT_RECORD_BITS + 31u) / 32u)

// the most lanes and records the text program runs: a first lane and a record's number are 32-bit fields
#define EMIT_TEXT_LANES_MOST 0x80000000ull

// the text program: its key and layout, as keymath and key_schedule leave them, and what they took, kept so the
// device lays it again (emit_lay_device, emit_device.h): its steps, the fields' widths and offsets, its tables, each
// pointing at its values, and the step it outputs
struct EmitTextProgram
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> field_bits;
    std::vector<unsigned int> field_offset;
    std::vector<EngineRecordTable> tables;
    std::vector<std::vector<unsigned int>> values;
    unsigned int output;
};

// a slot's argument as the program writes it: the word before its number and the word after, by their numbers among the
// words, and its number where it has one
struct EmitTextArgument
{
    unsigned int before;
    unsigned int after;
    unsigned int number;
    unsigned int numbered;
};

// what a ruleset writes, laid once for a target and a header: the text program and the scratch each form's
// construct takes (emit_ruleset_scratch; none, since the text program refuses a ruleset of constructs); each word's length;
// each part's lanes, the lengths of its pieces; each form's parts, in its order, from form_part_first[form] to
// form_part_first[form + 1] of form_parts, and the parameter each of its slots takes, from form_slot_first[form] to
// form_slot_first[form + 1] of slot_parameters; the words around each bank's register number, each held register's
// word, the word "-" before a negative number's digits, the target's hash as the note writes it, and the header's
// part; and the target's compute capability and NVRTC's version as the note writes them
struct EmitTextRuleset
{
    EmitTextProgram program;
    std::vector<unsigned int> scratch;
    std::vector<unsigned int> word_lengths;
    std::vector<unsigned int> part_lanes;
    std::vector<unsigned int> form_part_first;
    std::vector<unsigned int> form_parts;
    std::vector<unsigned int> form_slot_first;
    std::vector<unsigned int> slot_parameters;
    unsigned int bank_before[EMIT_BANK_COUNT];
    unsigned int bank_after[EMIT_BANK_COUNT];
    unsigned int fixed_word[EMIT_FIXED_COUNT];
    unsigned int minus_word;
    unsigned int hash_word;
    unsigned int header_part;
    unsigned int target_numbers[4];
};

// the same as the records' lay reads it, its lists where the lay runs: in host memory for the host oracle, in device
// memory for the device
struct EmitTextLists
{
    const unsigned int *word_lengths;
    const unsigned int *part_lanes;
    const unsigned int *form_part_first;
    const unsigned int *form_parts;
    const unsigned int *form_slot_first;
    const unsigned int *slot_parameters;
    unsigned int bank_before[EMIT_BANK_COUNT];
    unsigned int bank_after[EMIT_BANK_COUNT];
    unsigned int fixed_word[EMIT_FIXED_COUNT];
    unsigned int minus_word;
    unsigned int hash_word;
    unsigned int header_part;
    unsigned int target_numbers[4];
};

// `bits` of `value` laid into the record's words from bit `at`, which the record's words hold clear
EMIT_CORE void emit_text_bits(unsigned int *record, unsigned int at, unsigned int bits, unsigned int value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int set = (value >> bit) & 1u;
        record[(at + bit) / 32u] |= set << ((at + bit) % 32u);
    }
}

// 1 where an item is one the text program writes: the header, or a form given as many arguments as it takes, as the host's
// writing it asks
EMIT_CORE int emit_text_formed(const EmitCoreItem *item)
{
    return (item->form == EMIT_TEXT_WHOLE)
        || ((item->form < EMIT_FORM_COUNT) && (item->count == emit_core_parameters(item->form)));
}

// the slots a form's text takes arguments at
EMIT_CORE unsigned int emit_text_slots(const EmitTextLists *forms, unsigned int form)
{
    return forms->form_slot_first[form + 1u] - forms->form_slot_first[form];
}

// the records a formed item takes: a form's slots four to a record and one for a form of none, and one for the header
EMIT_CORE unsigned int emit_text_record_count(const EmitTextLists *forms, const EmitCoreItem *item)
{
    const unsigned int slots = (item->form == EMIT_TEXT_WHOLE) ? 0u : emit_text_slots(forms, item->form);
    return (slots == 0u) ? 1u : ((slots + EMIT_TEXT_SLOTS - 1u) / EMIT_TEXT_SLOTS);
}

// argument `parameter` of a formed item as the program writes it, as the host emitter writes it (emit_lane_text,
// emit_lane.cu): a register as its bank's words around its number, a held register as its word, a number as its
// digits, a negative one after the minus; the note's from its step count and the target, and the resident's from the
// launch's layout
EMIT_CORE EmitTextArgument emit_text_argument(const EmitTextLists *forms, const EmitCoreItem *item,
                                              unsigned int parameter)
{
    EmitTextArgument argument = {0u, 0u, 0u, 1u};
    if (item->form == EMIT_FORM_PROGRAM_NOTE)
    {
        argument.number = (parameter == 0u) ? item->arguments[0].number
                        : ((parameter < 5u) ? forms->target_numbers[parameter - 1u] : 0u);
        if (parameter == 5u)
        {
            argument.before = forms->hash_word;
            argument.numbered = 0u;
        }
        return argument;
    }
    if (item->form == EMIT_FORM_PROGRAM_UNIT)
    {
        // the launch's sizes and offsets and the program's commands and states are a few hundred at most
        argument.number = (unsigned int)emit_core_unit(parameter);
        return argument;
    }
    const EmitCoreArgument given = item->arguments[(parameter < EMIT_CORE_ARGUMENTS) ? parameter : 0u];
    if (given.kind == EMIT_CORE_REGISTER)
    {
        argument.before = forms->bank_before[given.which];
        argument.after = forms->bank_after[given.which];
        argument.number = given.number;
    }
    else if (given.kind == EMIT_CORE_FIXED)
    {
        argument.before = forms->fixed_word[given.which];
        argument.numbered = 0u;
    }
    else if ((given.kind == EMIT_CORE_SIGNED) && (given.number >= 0x80000000u))
    {
        argument.before = forms->minus_word;
        argument.number = 0u - given.number;
    }
    else
    {
        argument.number = given.number;
    }
    return argument;
}

// a formed item's records laid from `record` on, as many as emit_text_record_count gives, into `records` held clear:
// each record's part and its slots' arguments, the first lane left for emit_text_first to lay; and the lanes each
// record takes into `record_lanes`, its pieces' letters and each slot's words and ten digits a number, which the lanes
// past its text write as 0
EMIT_CORE void emit_text_records(const EmitTextLists *forms, const EmitCoreItem *item, unsigned long long record,
                                 unsigned int *records, unsigned long long *record_lanes)
{
    if (item->form == EMIT_TEXT_WHOLE)
    {
        emit_text_bits(&records[record * EMIT_TEXT_RECORD_LIMBS], 0u, EMIT_TEXT_PART_BITS, forms->header_part);
        record_lanes[record] = forms->part_lanes[forms->header_part];
        return;
    }
    const unsigned int slots = emit_text_slots(forms, item->form);
    const unsigned int slot_first = forms->form_slot_first[item->form];
    const unsigned int part_first = forms->form_part_first[item->form];
    const unsigned int chunks = emit_text_record_count(forms, item);
    for (unsigned int chunk = 0u; chunk < chunks; chunk += 1u)
    {
        unsigned int *const laid = &records[(record + chunk) * EMIT_TEXT_RECORD_LIMBS];
        const unsigned int part = forms->form_parts[part_first + chunk];
        emit_text_bits(laid, 0u, EMIT_TEXT_PART_BITS, part);
        unsigned long long lanes = forms->part_lanes[part];
        const unsigned int left = slots - (EMIT_TEXT_SLOTS * chunk);
        const unsigned int taken = (left < EMIT_TEXT_SLOTS) ? left : EMIT_TEXT_SLOTS;
        for (unsigned int slot = 0u; slot < taken; slot += 1u)
        {
            const unsigned int parameter = forms->slot_parameters[slot_first + (EMIT_TEXT_SLOTS * chunk) + slot];
            const EmitTextArgument argument = emit_text_argument(forms, item, parameter);
            const unsigned int base = EMIT_TEXT_SLOT_AT + (slot * EMIT_TEXT_SLOT_BITS);
            emit_text_bits(laid, base, EMIT_TEXT_WORD_BITS, argument.before);
            emit_text_bits(laid, base + EMIT_TEXT_WORD_BITS, EMIT_TEXT_WORD_BITS, argument.after);
            emit_text_bits(laid, base + (2u * EMIT_TEXT_WORD_BITS), EMIT_TEXT_NUMBER_BITS, argument.number);
            emit_text_bits(laid, base + (2u * EMIT_TEXT_WORD_BITS) + EMIT_TEXT_NUMBER_BITS, 1u, argument.numbered);
            lanes += (unsigned long long)forms->word_lengths[argument.before] + forms->word_lengths[argument.after]
                   + ((argument.numbered != 0u) ? EMIT_TEXT_DIGITS : 0u);
        }
        record_lanes[record + chunk] = lanes;
    }
}

// a record's first lane laid, below EMIT_TEXT_LANES_MOST as the caller holds the lanes
EMIT_CORE void emit_text_first(unsigned int *records, unsigned long long record, unsigned long long first)
{
    emit_text_bits(&records[record * EMIT_TEXT_RECORD_LIMBS], EMIT_TEXT_FIRST_AT, EMIT_TEXT_FIRST_BITS,
                   (unsigned int)first);
}

// a lane's byte, at the output's offset in its record of the program's out_limbs, below its sign bit
EMIT_CORE unsigned int emit_text_byte(const unsigned int *record, unsigned int out_limbs, unsigned int offset)
{
    const unsigned long long pair = (unsigned long long)record[offset / 32u]
                                  | ((((offset / 32u) + 1u) < out_limbs)
                                         ? ((unsigned long long)record[(offset / 32u) + 1u] << 32u)
                                         : 0ull);
    return (unsigned int)((pair >> (offset % 32u)) & 0xFFull);
}

// the text program and its tables for any lane the core decides in `rules` for `target` under `header`: 1 where it
// is laid, else 0 and why in `refused`. A ruleset that gives a form as a construct is refused, since a construct's
// scratch is the emitter's to take, as is a bank that writes its register with other than one number, a header that
// holds a byte 0, and more words or letters than the tables hold
int emit_text_ruleset_lay(const EmitRuleset *rules, const EmitTarget *target, const std::string &header,
                          EmitTextRuleset *text_rules, std::string *refused);

void emit_text_ruleset_release(EmitTextRuleset *text_rules);

// the rules as the records' lay reads them in host memory, their lists `text_rules`' own
EmitTextLists emit_text_lists(const EmitTextRuleset *text_rules);

// the host oracle: the lane's items (EmitLane::decided) laid as records by the functions above and written by the
// text program on the host (cycle_record_run_host); 1 where it ran, its text in `text`, else 0 and why in `refused`
int emit_text_host(const EmitTextRuleset *text_rules, const std::vector<EmitCoreItem> &items, std::string *text,
                   std::string *refused);

#endif
