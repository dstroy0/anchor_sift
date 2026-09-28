// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// asm_printer_program.cu: the assembly printer's program built
#include "asm_printer_internal.h"

// a word's number among the words, the word taken on where it is new
unsigned int asm_printer_word(AsmPrinterWords *words, const std::string &word)
{
    const auto found = words->numbered.find(word);
    if (found != words->numbered.end())
    {
        return found->second;
    }
    // the words are far fewer than 2^32; the layout refuses more than its tables hold
    const unsigned int number = (unsigned int)words->words.size();
    words->words.push_back(word);
    words->numbered[word] = number;
    return number;
}

unsigned int asm_printer_part(AsmPrinterWords *words, const std::array<unsigned int, ASM_PRINTER_PIECES> &part)
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
static unsigned int asm_printer_index_bits(unsigned long long count)
{
    unsigned int bits = 1u;
    while ((1ull << bits) < count)
    {
        bits += 1u;
    }
    return bits;
}

static unsigned int asm_printer_step(AsmPrinterSteps *printer_steps, EngineRecordOperation operation, unsigned int left,
                                     unsigned int right)
{
    printer_steps->steps.push_back({operation, left, right, 0u});
    // the program's steps are a few hundred
    return (unsigned int)(printer_steps->steps.size() - 1u);
}

static unsigned int asm_printer_constant(AsmPrinterSteps *printer_steps, unsigned int value)
{
    return asm_printer_step(printer_steps, ENGINE_RECORD_CONSTANT, value, 0u);
}

// 1 where left < right, else 0: the compare's order is -1, 0 or 1, and 1 less it, halved toward zero, is 1 only at -1
static unsigned int asm_printer_below(AsmPrinterSteps *printer_steps, unsigned int left, unsigned int right)
{
    const unsigned int order = asm_printer_step(printer_steps, ENGINE_RECORD_COMPARE, left, right);
    const unsigned int lessened = asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, printer_steps->one, order);
    return asm_printer_step(printer_steps, ENGINE_RECORD_QUOTIENT, lessened, printer_steps->two);
}

// the assembly printer's steps, a lane a byte; its one output is the byte, a table's entry of 8 bits
unsigned int asm_printer_program_build(AsmPrinterSteps *printer_steps)
{
    printer_steps->one = asm_printer_constant(printer_steps, 1u);
    printer_steps->two = asm_printer_constant(printer_steps, 2u);
    const unsigned int ten = asm_printer_constant(printer_steps, 10u);
    const unsigned int zero_letter = asm_printer_constant(printer_steps, (unsigned int)'0');
    const unsigned int rows = asm_printer_constant(printer_steps, ASM_PRINTER_PART_ROWS);
    const unsigned int nothing = asm_printer_constant(printer_steps, 0u);
    // the record's fields
    const unsigned int part = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_PART, 0u);
    const unsigned int first = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_FIRST, 0u);
    unsigned int before[ASM_PRINTER_SLOTS];
    unsigned int after[ASM_PRINTER_SLOTS];
    unsigned int number[ASM_PRINTER_SLOTS];
    unsigned int numbered[ASM_PRINTER_SLOTS];
    for (unsigned int slot = 0u; slot < ASM_PRINTER_SLOTS; slot += 1u)
    {
        before[slot] = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_SLOT(slot, 0u), 0u);
        after[slot] = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_SLOT(slot, 1u), 0u);
        number[slot] = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_SLOT(slot, 2u), 0u);
        numbered[slot] = asm_printer_step(printer_steps, ENGINE_RECORD_FIELD, ASM_PRINTER_FIELD_SLOT(slot, 3u), 0u);
    }
    // the byte's place in its part, below 2^31 as the layout holds the lanes, kept to one word
    const unsigned int lane = asm_printer_step(printer_steps, ENGINE_RECORD_LANE, 0u, 0u);
    const unsigned int apart = asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, lane, first);
    const unsigned int place = asm_printer_step(printer_steps, ENGINE_RECORD_WRAP, apart, 32u);
    // the part's pieces
    const unsigned int part_row = asm_printer_step(printer_steps, ENGINE_RECORD_PRODUCT, part, rows);
    unsigned int piece[ASM_PRINTER_PIECES];
    for (unsigned int at = 0u; at < ASM_PRINTER_PIECES; at += 1u)
    {
        const unsigned int row = (at == 0u) ? part_row
                                            : asm_printer_step(printer_steps, ENGINE_RECORD_SUM, part_row,
                                                               asm_printer_constant(printer_steps, at));
        piece[at] = asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, row, ASM_PRINTER_TABLE_PIECE);
    }
    // each slot's number's digits: none where it has no number, else 1 and one more for each power of ten at or below
    // it
    unsigned int digits[ASM_PRINTER_SLOTS];
    for (unsigned int slot = 0u; slot < ASM_PRINTER_SLOTS; slot += 1u)
    {
        unsigned int counted = printer_steps->one;
        unsigned int power = 1u;
        for (unsigned int more = 1u; more < ASM_PRINTER_DIGITS; more += 1u)
        {
            power *= 10u;
            const unsigned int reached =
                asm_printer_below(printer_steps, asm_printer_constant(printer_steps, power - 1u), number[slot]);
            counted = asm_printer_step(printer_steps, ENGINE_RECORD_SUM, counted, reached);
        }
        digits[slot] = asm_printer_step(printer_steps, ENGINE_RECORD_PRODUCT, numbered[slot], counted);
    }
    // the atoms in order, each a word by its number or a slot's digits, and its length
    unsigned int word[ASM_PRINTER_ATOMS];
    unsigned int length[ASM_PRINTER_ATOMS];
    unsigned int slot_of[ASM_PRINTER_ATOMS];
    int digited[ASM_PRINTER_ATOMS];
    for (unsigned int atom = 0u; atom < ASM_PRINTER_ATOMS; atom += 1u)
    {
        const unsigned int slot = atom / 4u;
        const unsigned int within = atom % 4u;
        slot_of[atom] = slot;
        digited[atom] = within == 2u;
        word[atom] =
            (within == 0u) ? piece[slot] : ((within == 1u) ? before[slot] : ((within == 3u) ? after[slot] : 0u));
        length[atom] = (digited[atom] != 0)
                           ? digits[slot]
                           : asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, word[atom], ASM_PRINTER_TABLE_LENGTH);
    }
    // where each atom begins in the part's text, and past the last
    unsigned int start[ASM_PRINTER_ATOMS + 1u];
    start[0] = nothing;
    for (unsigned int atom = 0u; atom < ASM_PRINTER_ATOMS; atom += 1u)
    {
        start[atom + 1u] = asm_printer_step(printer_steps, ENGINE_RECORD_SUM, start[atom], length[atom]);
    }
    unsigned int below[ASM_PRINTER_ATOMS + 1u];
    for (unsigned int atom = 0u; atom <= ASM_PRINTER_ATOMS; atom += 1u)
    {
        below[atom] = asm_printer_below(printer_steps, place, start[atom]);
    }
    // the byte: the letter of the one atom the place lies in, 0 where it lies in none
    unsigned int byte = nothing;
    for (unsigned int atom = 0u; atom < ASM_PRINTER_ATOMS; atom += 1u)
    {
        const unsigned int reached =
            asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, printer_steps->one, below[atom]);
        const unsigned int inside = asm_printer_step(printer_steps, ENGINE_RECORD_PRODUCT, reached, below[atom + 1u]);
        const unsigned int offset = asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, place, start[atom]);
        unsigned int letter = 0u;
        if (digited[atom] == 0)
        {
            const unsigned int begins =
                asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, word[atom], ASM_PRINTER_TABLE_START);
            const unsigned int at = asm_printer_step(printer_steps, ENGINE_RECORD_SUM, begins, offset);
            letter = asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, at, ASM_PRINTER_TABLE_LETTER);
        }
        else
        {
            // the digit at `offset` from the left is the number over ten to the digits left after it, modulo ten; a
            // place outside the atom reads some power, never 0, and its letter is not taken
            const unsigned int slot = slot_of[atom];
            const unsigned int last =
                asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, digits[slot], printer_steps->one);
            const unsigned int exponent = asm_printer_step(printer_steps, ENGINE_RECORD_DIFFERENCE, last, offset);
            const unsigned int power =
                asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, exponent, ASM_PRINTER_TABLE_POWER);
            const unsigned int shifted = asm_printer_step(printer_steps, ENGINE_RECORD_QUOTIENT, number[slot], power);
            const unsigned int digit = asm_printer_step(printer_steps, ENGINE_RECORD_REMAINDER, shifted, ten);
            letter = asm_printer_step(printer_steps, ENGINE_RECORD_SUM, digit, zero_letter);
        }
        const unsigned int taken = asm_printer_step(printer_steps, ENGINE_RECORD_PRODUCT, inside, letter);
        byte = asm_printer_step(printer_steps, ENGINE_RECORD_SUM, byte, taken);
    }
    return asm_printer_step(printer_steps, ENGINE_RECORD_TABLE, byte, ASM_PRINTER_TABLE_BYTE);
}

// the tables laid out from the words and the parts, each row a word, into `values`, each table's rows a power of two
void asm_printer_tables(const AsmPrinterWords *words, std::vector<unsigned int> (&values)[ASM_PRINTER_TABLES],
                        EngineRecordTable (&tables)[ASM_PRINTER_TABLES])
{
    const unsigned int part_bits =
        asm_printer_index_bits((unsigned long long)words->parts.size() * ASM_PRINTER_PART_ROWS);
    const unsigned int word_bits = asm_printer_index_bits(words->words.size());
    unsigned long long letters = 0ull;
    for (const std::string &word : words->words)
    {
        letters += word.size();
    }
    const unsigned int letter_bits = asm_printer_index_bits(letters);
    values[ASM_PRINTER_TABLE_PIECE].assign(1ull << part_bits, 0u);
    for (size_t part = 0u; part < words->parts.size(); part += 1u)
    {
        for (unsigned int piece = 0u; piece < ASM_PRINTER_PIECES; piece += 1u)
        {
            values[ASM_PRINTER_TABLE_PIECE][(part * ASM_PRINTER_PART_ROWS) + piece] = words->parts[part][piece];
        }
    }
    values[ASM_PRINTER_TABLE_LENGTH].assign(1ull << word_bits, 0u);
    values[ASM_PRINTER_TABLE_START].assign(1ull << word_bits, 0u);
    values[ASM_PRINTER_TABLE_LETTER].assign(1ull << letter_bits, 0u);
    unsigned int letter_count = 0u;
    for (size_t number = 0u; number < words->words.size(); number += 1u)
    {
        const std::string &word = words->words[number];
        // the layout holds every word's length and first letter below 2^16
        values[ASM_PRINTER_TABLE_LENGTH][number] = (unsigned int)word.size();
        values[ASM_PRINTER_TABLE_START][number] = letter_count;
        for (const char letter : word)
        {
            values[ASM_PRINTER_TABLE_LETTER][letter_count] = (unsigned int)(unsigned char)letter;
            letter_count += 1u;
        }
    }
    // ten to each power a 32-bit word has a digit at, and 1 at the rest, where no lane divides by 0
    values[ASM_PRINTER_TABLE_POWER].assign(16u, 1u);
    unsigned int power = 1u;
    for (unsigned int exponent = 0u; exponent < ASM_PRINTER_DIGITS; exponent += 1u)
    {
        values[ASM_PRINTER_TABLE_POWER][exponent] = power;
        power = (exponent < (ASM_PRINTER_DIGITS - 1u)) ? (10u * power) : power;
    }
    values[ASM_PRINTER_TABLE_BYTE].assign(256u, 0u);
    for (unsigned int byte = 0u; byte < 256u; byte += 1u)
    {
        values[ASM_PRINTER_TABLE_BYTE][byte] = byte;
    }
    tables[ASM_PRINTER_TABLE_PIECE] = {part_bits, ASM_PRINTER_WORD_BITS, values[ASM_PRINTER_TABLE_PIECE].data()};
    tables[ASM_PRINTER_TABLE_LENGTH] = {word_bits, ASM_PRINTER_WORD_BITS, values[ASM_PRINTER_TABLE_LENGTH].data()};
    tables[ASM_PRINTER_TABLE_START] = {word_bits, ASM_PRINTER_WORD_BITS, values[ASM_PRINTER_TABLE_START].data()};
    tables[ASM_PRINTER_TABLE_LETTER] = {letter_bits, 8u, values[ASM_PRINTER_TABLE_LETTER].data()};
    // 10^9 is below 2^30
    tables[ASM_PRINTER_TABLE_POWER] = {4u, 30u, values[ASM_PRINTER_TABLE_POWER].data()};
    tables[ASM_PRINTER_TABLE_BYTE] = {8u, 8u, values[ASM_PRINTER_TABLE_BYTE].data()};
}
