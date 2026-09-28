// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_text.h"
#include "emit_rules.h"
#include "../cycle/cycle.h"
#include "../keymath/keymath.h"
#include "../key_schedule/key_schedule.h"

#include <stddef.h>
#include <stdio.h>

#include <array>
#include <map>
#include <string>
#include <vector>

// the fields as the program reads them: the part, the first lane, then each slot's word before, word after, number and
// whether it has one
#define EMIT_TEXT_FIELD_PART 0u
#define EMIT_TEXT_FIELD_FIRST 1u
#define EMIT_TEXT_FIELD_SLOT(slot_, which_) (2u + (4u * (slot_)) + (which_))
#define EMIT_TEXT_FIELDS (2u + (4u * EMIT_TEXT_SLOTS))

// the tables: each part's pieces by part . 8 + piece, each word's length and first letter by its number, the letters
// of every word end to end, ten to each power a digit is taken at, and a byte as itself
enum EmitTextTable
{
    EMIT_TEXT_TABLE_PIECE = 0,
    EMIT_TEXT_TABLE_LENGTH = 1,
    EMIT_TEXT_TABLE_START = 2,
    EMIT_TEXT_TABLE_LETTER = 3,
    EMIT_TEXT_TABLE_POWER = 4,
    EMIT_TEXT_TABLE_BYTE = 5,
    EMIT_TEXT_TABLES = 6
};

// the rows a part takes in the pieces table, a power of two past its pieces
#define EMIT_TEXT_PART_ROWS 8u

// the widest word number, length and letter offset the tables hold, and the widest index a table takes from a 16-bit
// field or entry
#define EMIT_TEXT_TABLE_BITS_MOST 16u

// the text being laid: the words, each once, by their numbers, 0 the empty word; and the parts, each once
struct EmitTextWords
{
    std::vector<std::string> words;
    std::map<std::string, unsigned int> numbered;
    std::vector<std::array<unsigned int, EMIT_TEXT_PIECES>> parts;
    std::map<std::array<unsigned int, EMIT_TEXT_PIECES>, unsigned int> part_numbered;
};

// a word's number among the words, the word taken on where it is new
static unsigned int emit_text_word(EmitTextWords *words, const std::string &word)
{
    const auto found = words->numbered.find(word);
    if (found != words->numbered.end())
    {
        return found->second;
    }
    // the words are far fewer than 2^32; the lay refuses more than its tables hold
    const unsigned int number = (unsigned int)words->words.size();
    words->words.push_back(word);
    words->numbered[word] = number;
    return number;
}

static unsigned int emit_text_part(EmitTextWords *words, const std::array<unsigned int, EMIT_TEXT_PIECES> &part)
{
    const auto found = words->part_numbered.find(part);
    if (found != words->part_numbered.end())
    {
        return found->second;
    }
    const unsigned int number = (unsigned int)words->parts.size();
    words->parts.push_back(part);
    words->part_numbered[part] = number;
    return number;
}

// the least count of index bits that holds `count` rows, at least 1
static unsigned int emit_text_index_bits(unsigned long long count)
{
    unsigned int bits = 1u;
    while ((1ull << bits) < count)
    {
        bits += 1u;
    }
    return bits;
}

// the text program's steps being laid
struct EmitTextSteps
{
    std::vector<EngineRecordStep> steps;
    unsigned int one;
    unsigned int two;
};

static unsigned int emit_text_step(EmitTextSteps *laid, EngineRecordOperation operation, unsigned int left,
                                   unsigned int right)
{
    laid->steps.push_back({operation, left, right, 0u});
    // the program's steps are a few hundred
    return (unsigned int)(laid->steps.size() - 1u);
}

static unsigned int emit_text_constant(EmitTextSteps *laid, unsigned int value)
{
    return emit_text_step(laid, ENGINE_RECORD_CONSTANT, value, 0u);
}

// 1 where left < right, else 0: the compare's order is -1, 0 or 1, and 1 less it, halved toward zero, is 1 only at -1
static unsigned int emit_text_below(EmitTextSteps *laid, unsigned int left, unsigned int right)
{
    const unsigned int order = emit_text_step(laid, ENGINE_RECORD_COMPARE, left, right);
    const unsigned int lessened = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, laid->one, order);
    return emit_text_step(laid, ENGINE_RECORD_QUOTIENT, lessened, laid->two);
}

// the text program's steps, a lane a byte; its one output is the byte, a table's entry of 8 bits
static unsigned int emit_text_program_build(EmitTextSteps *laid)
{
    laid->one = emit_text_constant(laid, 1u);
    laid->two = emit_text_constant(laid, 2u);
    const unsigned int ten = emit_text_constant(laid, 10u);
    const unsigned int zero_letter = emit_text_constant(laid, (unsigned int)'0');
    const unsigned int rows = emit_text_constant(laid, EMIT_TEXT_PART_ROWS);
    const unsigned int nothing = emit_text_constant(laid, 0u);
    // the record's fields
    const unsigned int part = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_PART, 0u);
    const unsigned int first = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_FIRST, 0u);
    unsigned int before[EMIT_TEXT_SLOTS];
    unsigned int after[EMIT_TEXT_SLOTS];
    unsigned int number[EMIT_TEXT_SLOTS];
    unsigned int numbered[EMIT_TEXT_SLOTS];
    for (unsigned int slot = 0u; slot < EMIT_TEXT_SLOTS; slot += 1u)
    {
        before[slot] = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_SLOT(slot, 0u), 0u);
        after[slot] = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_SLOT(slot, 1u), 0u);
        number[slot] = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_SLOT(slot, 2u), 0u);
        numbered[slot] = emit_text_step(laid, ENGINE_RECORD_FIELD, EMIT_TEXT_FIELD_SLOT(slot, 3u), 0u);
    }
    // the byte's place in its part, below 2^31 as the lay holds the lanes, kept to one word
    const unsigned int lane = emit_text_step(laid, ENGINE_RECORD_LANE, 0u, 0u);
    const unsigned int apart = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, lane, first);
    const unsigned int place = emit_text_step(laid, ENGINE_RECORD_WRAP, apart, 32u);
    // the part's pieces
    const unsigned int part_row = emit_text_step(laid, ENGINE_RECORD_PRODUCT, part, rows);
    unsigned int piece[EMIT_TEXT_PIECES];
    for (unsigned int at = 0u; at < EMIT_TEXT_PIECES; at += 1u)
    {
        const unsigned int row = (at == 0u) ? part_row
                                            : emit_text_step(laid, ENGINE_RECORD_SUM, part_row,
                                                             emit_text_constant(laid, at));
        piece[at] = emit_text_step(laid, ENGINE_RECORD_TABLE, row, EMIT_TEXT_TABLE_PIECE);
    }
    // each slot's number's digits: none where it has no number, else 1 and one more for each power of ten at or below
    // it
    unsigned int digits[EMIT_TEXT_SLOTS];
    for (unsigned int slot = 0u; slot < EMIT_TEXT_SLOTS; slot += 1u)
    {
        unsigned int counted = laid->one;
        unsigned int power = 1u;
        for (unsigned int more = 1u; more < EMIT_TEXT_DIGITS; more += 1u)
        {
            power *= 10u;
            const unsigned int reached =
                emit_text_below(laid, emit_text_constant(laid, power - 1u), number[slot]);
            counted = emit_text_step(laid, ENGINE_RECORD_SUM, counted, reached);
        }
        digits[slot] = emit_text_step(laid, ENGINE_RECORD_PRODUCT, numbered[slot], counted);
    }
    // the atoms in order, each a word by its number or a slot's digits, and its length
    unsigned int word[EMIT_TEXT_ATOMS];
    unsigned int length[EMIT_TEXT_ATOMS];
    unsigned int slot_of[EMIT_TEXT_ATOMS];
    int digited[EMIT_TEXT_ATOMS];
    for (unsigned int atom = 0u; atom < EMIT_TEXT_ATOMS; atom += 1u)
    {
        const unsigned int slot = atom / 4u;
        const unsigned int within = atom % 4u;
        slot_of[atom] = slot;
        digited[atom] = within == 2u;
        word[atom] = (within == 0u) ? piece[slot] : ((within == 1u) ? before[slot] : ((within == 3u) ? after[slot] : 0u));
        length[atom] = (digited[atom] != 0) ? digits[slot]
                                            : emit_text_step(laid, ENGINE_RECORD_TABLE, word[atom],
                                                             EMIT_TEXT_TABLE_LENGTH);
    }
    // where each atom begins in the part's text, and past the last
    unsigned int start[EMIT_TEXT_ATOMS + 1u];
    start[0] = nothing;
    for (unsigned int atom = 0u; atom < EMIT_TEXT_ATOMS; atom += 1u)
    {
        start[atom + 1u] = emit_text_step(laid, ENGINE_RECORD_SUM, start[atom], length[atom]);
    }
    unsigned int below[EMIT_TEXT_ATOMS + 1u];
    for (unsigned int atom = 0u; atom <= EMIT_TEXT_ATOMS; atom += 1u)
    {
        below[atom] = emit_text_below(laid, place, start[atom]);
    }
    // the byte: the letter of the one atom the place lies in, 0 where it lies in none
    unsigned int byte = nothing;
    for (unsigned int atom = 0u; atom < EMIT_TEXT_ATOMS; atom += 1u)
    {
        const unsigned int reached = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, laid->one, below[atom]);
        const unsigned int inside = emit_text_step(laid, ENGINE_RECORD_PRODUCT, reached, below[atom + 1u]);
        const unsigned int offset = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, place, start[atom]);
        unsigned int letter = 0u;
        if (digited[atom] == 0)
        {
            const unsigned int begins = emit_text_step(laid, ENGINE_RECORD_TABLE, word[atom], EMIT_TEXT_TABLE_START);
            const unsigned int at = emit_text_step(laid, ENGINE_RECORD_SUM, begins, offset);
            letter = emit_text_step(laid, ENGINE_RECORD_TABLE, at, EMIT_TEXT_TABLE_LETTER);
        }
        else
        {
            // the digit at `offset` from the left is the number over ten to the digits left after it, modulo ten; a
            // place outside the atom reads some power, never 0, and its letter is not taken
            const unsigned int slot = slot_of[atom];
            const unsigned int last = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, digits[slot], laid->one);
            const unsigned int exponent = emit_text_step(laid, ENGINE_RECORD_DIFFERENCE, last, offset);
            const unsigned int power = emit_text_step(laid, ENGINE_RECORD_TABLE, exponent, EMIT_TEXT_TABLE_POWER);
            const unsigned int shifted = emit_text_step(laid, ENGINE_RECORD_QUOTIENT, number[slot], power);
            const unsigned int digit = emit_text_step(laid, ENGINE_RECORD_REMAINDER, shifted, ten);
            letter = emit_text_step(laid, ENGINE_RECORD_SUM, digit, zero_letter);
        }
        const unsigned int taken = emit_text_step(laid, ENGINE_RECORD_PRODUCT, inside, letter);
        byte = emit_text_step(laid, ENGINE_RECORD_SUM, byte, taken);
    }
    return emit_text_step(laid, ENGINE_RECORD_TABLE, byte, EMIT_TEXT_TABLE_BYTE);
}

// the tables laid from the words and the parts, each row a word, into `values`, each table's rows a power of two
static void emit_text_tables(const EmitTextWords *words, std::vector<unsigned int> (&values)[EMIT_TEXT_TABLES],
                             EngineRecordTable (&tables)[EMIT_TEXT_TABLES])
{
    const unsigned int part_bits = emit_text_index_bits((unsigned long long)words->parts.size() * EMIT_TEXT_PART_ROWS);
    const unsigned int word_bits = emit_text_index_bits(words->words.size());
    unsigned long long letters = 0ull;
    for (const std::string &word : words->words)
    {
        letters += word.size();
    }
    const unsigned int letter_bits = emit_text_index_bits(letters);
    values[EMIT_TEXT_TABLE_PIECE].assign(1ull << part_bits, 0u);
    for (size_t part = 0u; part < words->parts.size(); part += 1u)
    {
        for (unsigned int piece = 0u; piece < EMIT_TEXT_PIECES; piece += 1u)
        {
            values[EMIT_TEXT_TABLE_PIECE][(part * EMIT_TEXT_PART_ROWS) + piece] = words->parts[part][piece];
        }
    }
    values[EMIT_TEXT_TABLE_LENGTH].assign(1ull << word_bits, 0u);
    values[EMIT_TEXT_TABLE_START].assign(1ull << word_bits, 0u);
    values[EMIT_TEXT_TABLE_LETTER].assign(1ull << letter_bits, 0u);
    unsigned int laid = 0u;
    for (size_t number = 0u; number < words->words.size(); number += 1u)
    {
        const std::string &word = words->words[number];
        // the lay holds every word's length and first letter below 2^16
        values[EMIT_TEXT_TABLE_LENGTH][number] = (unsigned int)word.size();
        values[EMIT_TEXT_TABLE_START][number] = laid;
        for (const char letter : word)
        {
            values[EMIT_TEXT_TABLE_LETTER][laid] = (unsigned int)(unsigned char)letter;
            laid += 1u;
        }
    }
    // ten to each power a 32-bit word has a digit at, and 1 at the rest, where no lane divides by 0
    values[EMIT_TEXT_TABLE_POWER].assign(16u, 1u);
    unsigned int power = 1u;
    for (unsigned int exponent = 0u; exponent < EMIT_TEXT_DIGITS; exponent += 1u)
    {
        values[EMIT_TEXT_TABLE_POWER][exponent] = power;
        power = (exponent < (EMIT_TEXT_DIGITS - 1u)) ? (10u * power) : power;
    }
    values[EMIT_TEXT_TABLE_BYTE].assign(256u, 0u);
    for (unsigned int byte = 0u; byte < 256u; byte += 1u)
    {
        values[EMIT_TEXT_TABLE_BYTE][byte] = byte;
    }
    tables[EMIT_TEXT_TABLE_PIECE] = {part_bits, EMIT_TEXT_WORD_BITS, values[EMIT_TEXT_TABLE_PIECE].data()};
    tables[EMIT_TEXT_TABLE_LENGTH] = {word_bits, EMIT_TEXT_WORD_BITS, values[EMIT_TEXT_TABLE_LENGTH].data()};
    tables[EMIT_TEXT_TABLE_START] = {word_bits, EMIT_TEXT_WORD_BITS, values[EMIT_TEXT_TABLE_START].data()};
    tables[EMIT_TEXT_TABLE_LETTER] = {letter_bits, 8u, values[EMIT_TEXT_TABLE_LETTER].data()};
    // 10^9 is below 2^30
    tables[EMIT_TEXT_TABLE_POWER] = {4u, 30u, values[EMIT_TEXT_TABLE_POWER].data()};
    tables[EMIT_TEXT_TABLE_BYTE] = {8u, 8u, values[EMIT_TEXT_TABLE_BYTE].data()};
}

// the text program and its tables laid from `words` into `program`'s key and layout: 1 where they are, else 0 and
// why in `refused`, a text of more words, letters or parts than the tables hold refused
static int emit_text_program_lay(const EmitTextWords *words, EmitTextProgram *program, std::string *refused)
{
    unsigned long long letters = 0ull;
    for (const std::string &word : words->words)
    {
        letters += word.size();
    }
    if ((letters >= (1ull << EMIT_TEXT_TABLE_BITS_MOST))
        || (words->words.size() > (1ull << EMIT_TEXT_TABLE_BITS_MOST))
        || (((unsigned long long)words->parts.size() * EMIT_TEXT_PART_ROWS) > (1ull << EMIT_TEXT_TABLE_BITS_MOST)))
    {
        *refused = "the ruleset and the header hold more words or letters than the text program's tables hold";
        return 0;
    }
    std::vector<unsigned int> values[EMIT_TEXT_TABLES];
    EngineRecordTable tables[EMIT_TEXT_TABLES];
    emit_text_tables(words, values, tables);
    EmitTextSteps laid;
    const unsigned int output = emit_text_program_build(&laid);
    unsigned int field_bits[EMIT_TEXT_FIELDS];
    unsigned int field_offset[EMIT_TEXT_FIELDS];
    field_bits[EMIT_TEXT_FIELD_PART] = EMIT_TEXT_PART_BITS;
    field_offset[EMIT_TEXT_FIELD_PART] = 0u;
    field_bits[EMIT_TEXT_FIELD_FIRST] = EMIT_TEXT_FIRST_BITS;
    field_offset[EMIT_TEXT_FIELD_FIRST] = EMIT_TEXT_FIRST_AT;
    for (unsigned int slot = 0u; slot < EMIT_TEXT_SLOTS; slot += 1u)
    {
        const unsigned int base = EMIT_TEXT_SLOT_AT + (slot * EMIT_TEXT_SLOT_BITS);
        const unsigned int bits[4] = {EMIT_TEXT_WORD_BITS, EMIT_TEXT_WORD_BITS, EMIT_TEXT_NUMBER_BITS, 1u};
        const unsigned int at[4] = {base, base + EMIT_TEXT_WORD_BITS, base + (2u * EMIT_TEXT_WORD_BITS),
                                    base + (2u * EMIT_TEXT_WORD_BITS) + EMIT_TEXT_NUMBER_BITS};
        for (unsigned int which = 0u; which < 4u; which += 1u)
        {
            field_bits[EMIT_TEXT_FIELD_SLOT(slot, which)] = bits[which];
            field_offset[EMIT_TEXT_FIELD_SLOT(slot, which)] = at[which];
        }
    }
    // what keymath and key_schedule take, kept for the device's lay, each table pointing at its values where they are
    // kept
    program->steps = laid.steps;
    program->field_bits.assign(field_bits, field_bits + EMIT_TEXT_FIELDS);
    program->field_offset.assign(field_offset, field_offset + EMIT_TEXT_FIELDS);
    program->values.assign(values, values + EMIT_TEXT_TABLES);
    program->tables.assign(tables, tables + EMIT_TEXT_TABLES);
    for (unsigned int table = 0u; table < EMIT_TEXT_TABLES; table += 1u)
    {
        program->tables[table].values = program->values[table].data();
    }
    program->output = output;
    EngineError error{};
    // the steps are a few hundred
    const KeymathRecordRequest imprint = {laid.steps.data(), (unsigned int)laid.steps.size(), field_bits,
                                          EMIT_TEXT_FIELDS,  1u, &output, 1u, tables, EMIT_TEXT_TABLES,
                                          &program->key,      &error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        *refused = "keymath refused the text program";
        keymath_record_release(&program->key);
        return 0;
    }
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {EMIT_TEXT_RECORD_LIMBS, 0u, 0u};
    const KeyScheduleRecordRequest lay = {&program->key, field_offset, EMIT_TEXT_FIELDS, in_limbs, 1,
                                          &program->layout, &error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        *refused = "key_schedule refused the text program";
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    return 1;
}

// Every word and part a lane the core decides can be written in, laid before any lane is: each form's parts from its
// pieces, its slots four to a part and one part for a form of none, each bank's words around its number, each held
// register's word, the minus, the target's hash and the header, whole
int emit_text_ruleset_lay(const EmitRuleset *rules, const EmitTarget *target, const std::string &header,
                          EmitTextRuleset *text_rules, std::string *refused)
{
    *text_rules = EmitTextRuleset{};
    if ((rules->schema->form_count != EMIT_FORM_COUNT) || (rules->schema->bank_count != EMIT_BANK_COUNT)
        || (rules->schema->fixed_count != EMIT_FIXED_COUNT))
    {
        *refused = "the ruleset was read against another emitter's schema than the lane's";
        return 0;
    }
    if (header.find('\0') != std::string::npos)
    {
        *refused = "the header holds a byte 0";
        return 0;
    }
    const unsigned int scratch_banks[3] = {EMIT_BANK_TEMPORARY, EMIT_BANK_WIDE, EMIT_BANK_PREDICATE};
    emit_ruleset_scratch(rules, scratch_banks, &text_rules->scratch);
    EmitTextWords words;
    emit_text_word(&words, std::string());
    for (unsigned int form = 0u; form < EMIT_FORM_COUNT; form += 1u)
    {
        if (!rules->constructs[form].lines.empty())
        {
            *refused = "a form is given as a construct, whose scratch the emitter takes";
            return 0;
        }
        const std::vector<std::string> &pieces = rules->forms[form].pieces;
        const std::vector<unsigned int> &slots = rules->forms[form].slots;
        // the parts and the slots' parameters, a few hundred of each
        text_rules->form_part_first.push_back((unsigned int)text_rules->form_parts.size());
        text_rules->form_slot_first.push_back((unsigned int)text_rules->slot_parameters.size());
        text_rules->slot_parameters.insert(text_rules->slot_parameters.end(), slots.begin(), slots.end());
        for (size_t first_slot = 0u; (first_slot == 0u) || (first_slot < slots.size()); first_slot += EMIT_TEXT_SLOTS)
        {
            const size_t left = slots.size() - first_slot;
            const size_t taken = (left < EMIT_TEXT_SLOTS) ? left : EMIT_TEXT_SLOTS;
            const int last = (first_slot + taken) == slots.size();
            std::array<unsigned int, EMIT_TEXT_PIECES> part{};
            for (size_t slot = 0u; slot < taken; slot += 1u)
            {
                part[slot] = emit_text_word(&words, pieces[first_slot + slot]);
            }
            part[taken] = last ? emit_text_word(&words, pieces[slots.size()]) : 0u;
            text_rules->form_parts.push_back(emit_text_part(&words, part));
            if (last)
            {
                break;
            }
        }
    }
    text_rules->form_part_first.push_back((unsigned int)text_rules->form_parts.size());
    text_rules->form_slot_first.push_back((unsigned int)text_rules->slot_parameters.size());
    for (unsigned int bank = 0u; bank < EMIT_BANK_COUNT; bank += 1u)
    {
        const EmitForm *const bank_form = &rules->banks[bank];
        if (bank_form->slots.size() != 1u)
        {
            *refused = "a bank writes its register with other than one number";
            return 0;
        }
        text_rules->bank_before[bank] = emit_text_word(&words, bank_form->pieces[0]);
        text_rules->bank_after[bank] = emit_text_word(&words, bank_form->pieces[1]);
    }
    for (unsigned int fixed = 0u; fixed < EMIT_FIXED_COUNT; fixed += 1u)
    {
        text_rules->fixed_word[fixed] = emit_text_word(&words, rules->fixed[fixed]);
    }
    char block[32];
    snprintf(block, sizeof(block), "%016llx", target->block_hash);
    text_rules->minus_word = emit_text_word(&words, std::string("-"));
    text_rules->hash_word = emit_text_word(&words, std::string(block));
    std::array<unsigned int, EMIT_TEXT_PIECES> header_part{};
    header_part[0] = emit_text_word(&words, header);
    text_rules->header_part = emit_text_part(&words, header_part);
    // a device's compute capability and NVRTC's version are small counts, never negative
    text_rules->target_numbers[0] = (unsigned int)target->major;
    text_rules->target_numbers[1] = (unsigned int)target->minor;
    text_rules->target_numbers[2] = (unsigned int)target->nvrtc_major;
    text_rules->target_numbers[3] = (unsigned int)target->nvrtc_minor;
    // each word's length and each part's lanes, below 2^16 as the program's lay holds the letters
    for (const std::string &word : words.words)
    {
        text_rules->word_lengths.push_back((unsigned int)word.size());
    }
    for (const std::array<unsigned int, EMIT_TEXT_PIECES> &part : words.parts)
    {
        unsigned int lanes = 0u;
        for (const unsigned int piece : part)
        {
            lanes += text_rules->word_lengths[piece];
        }
        text_rules->part_lanes.push_back(lanes);
    }
    return emit_text_program_lay(&words, &text_rules->program, refused);
}

void emit_text_ruleset_release(EmitTextRuleset *text_rules)
{
    key_schedule_record_release(&text_rules->program.layout);
    keymath_record_release(&text_rules->program.key);
}

EmitTextLists emit_text_lists(const EmitTextRuleset *text_rules)
{
    EmitTextLists forms{};
    forms.word_lengths = text_rules->word_lengths.data();
    forms.part_lanes = text_rules->part_lanes.data();
    forms.form_part_first = text_rules->form_part_first.data();
    forms.form_parts = text_rules->form_parts.data();
    forms.form_slot_first = text_rules->form_slot_first.data();
    forms.slot_parameters = text_rules->slot_parameters.data();
    for (unsigned int bank = 0u; bank < EMIT_BANK_COUNT; bank += 1u)
    {
        forms.bank_before[bank] = text_rules->bank_before[bank];
        forms.bank_after[bank] = text_rules->bank_after[bank];
    }
    for (unsigned int fixed = 0u; fixed < EMIT_FIXED_COUNT; fixed += 1u)
    {
        forms.fixed_word[fixed] = text_rules->fixed_word[fixed];
    }
    forms.minus_word = text_rules->minus_word;
    forms.hash_word = text_rules->hash_word;
    forms.header_part = text_rules->header_part;
    for (unsigned int number = 0u; number < 4u; number += 1u)
    {
        forms.target_numbers[number] = text_rules->target_numbers[number];
    }
    return forms;
}

// the host oracle, in the device's order: each item's records counted and laid, each record's first lane and the index
// laid from the running sum of the records' lanes, the program run, and the bytes that are not 0 taken in lane order
int emit_text_host(const EmitTextRuleset *text_rules, const std::vector<EmitCoreItem> &items, std::string *text,
                   std::string *refused)
{
    const EmitTextLists forms = emit_text_lists(text_rules);
    std::vector<unsigned long long> record_first(items.size(), 0ull);
    unsigned long long record_count = 0ull;
    for (size_t at = 0u; at < items.size(); at += 1u)
    {
        if (!emit_text_formed(&items[at]))
        {
            *refused = "a form breaks the lane";
            return 0;
        }
        record_first[at] = record_count;
        record_count += emit_text_record_count(&forms, &items[at]);
    }
    if (record_count >= EMIT_TEXT_LANES_MOST)
    {
        *refused = "the text holds more records than the text program holds";
        return 0;
    }
    std::vector<unsigned int> records((size_t)(record_count * EMIT_TEXT_RECORD_LIMBS), 0u);
    std::vector<unsigned long long> record_lanes((size_t)record_count, 0ull);
    for (size_t at = 0u; at < items.size(); at += 1u)
    {
        emit_text_records(&forms, &items[at], record_first[at], records.data(), record_lanes.data());
    }
    unsigned long long lanes = 0ull;
    for (unsigned long long record = 0ull; record < record_count; record += 1ull)
    {
        lanes += record_lanes[record];
    }
    if ((lanes >= EMIT_TEXT_LANES_MOST) || (lanes == 0ull))
    {
        *refused = "the text holds more lanes than the text program holds";
        return 0;
    }
    std::vector<unsigned int> index;
    index.reserve((size_t)lanes);
    unsigned long long first = 0ull;
    for (unsigned long long record = 0ull; record < record_count; record += 1ull)
    {
        emit_text_first(records.data(), record, first);
        // a record's number is below 2^31
        index.insert(index.end(), (size_t)record_lanes[record], (unsigned int)record);
        first += record_lanes[record];
    }
    const unsigned int out_limbs = text_rules->program.layout.out_limbs;
    std::vector<unsigned int> out((size_t)(lanes * out_limbs), 0u);
    EngineError error{};
    CycleRecordHostRequest request{};
    request.layout = &text_rules->program.layout;
    request.in[0] = records.data();
    request.bodies[0] = record_count;
    request.index = index.data();
    request.count = lanes;
    request.out = out.data();
    request.error = &error;
    if (cycle_record_run_host(&request) == CYCLE_REFUSED)
    {
        *refused = "the host oracle refused the text program's run";
        return 0;
    }
    // the one output, the byte, lies at its step's offset in each lane's record
    const unsigned int offset =
        text_rules->program.layout.step_table[text_rules->program.key.output[0]].out_offset;
    std::string written;
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        const unsigned int byte = emit_text_byte(&out[(size_t)(lane * out_limbs)], out_limbs, offset);
        if (byte != 0u)
        {
            written += (char)byte;
        }
    }
    *text = written;
    return 1;
}
