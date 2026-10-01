// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// asm_printer_core_words.h: the build's types, words, parts and steps (asm_printer_core.h includes the parts in order)
#ifndef ASM_PRINTER_CORE_WORDS_H
#define ASM_PRINTER_CORE_WORDS_H

// asm_printer_ruleset_build's work past the schema and the scratch, ported word for word from the host's
// (asm_printer_layout.cu and asm_printer_program.cu as they were): every word and part a lane can be written in,
// numbered in the order the host numbered them, the lists the records' layout reads, the program's steps, fields and
// tables. The host's map of words becomes a search of the words held, which gives each word the same number. The
// device runs it in one thread (codegen_rules.cu), since each word's number depends on every word before it;
// keymath's encoding and key_schedule's layout of the program follow it as they do on the host. The memory is the
// caller's: where a count passes its capacity the build ends full, and the caller grows the capacity and runs it again

#include "asm_printer.h"

// the fields as the program reads them: the part, the first lane, then each slot's word before, word after, number and
// whether it has one
#define ASM_PRINTER_FIELD_PART 0u
#define ASM_PRINTER_FIELD_FIRST 1u
#define ASM_PRINTER_FIELD_SLOT(slot_, which_) (2u + (4u * (slot_)) + (which_))
#define ASM_PRINTER_FIELDS (2u + (4u * ASM_PRINTER_SLOTS))

// the tables: each part's pieces by part . 8 + piece, each word's length and first letter by its number, the letters
// of every word end to end, ten to each power a digit is taken at, and a byte as itself
enum AsmPrinterTable
{
    ASM_PRINTER_TABLE_PIECE = 0,
    ASM_PRINTER_TABLE_LENGTH = 1,
    ASM_PRINTER_TABLE_START = 2,
    ASM_PRINTER_TABLE_LETTER = 3,
    ASM_PRINTER_TABLE_POWER = 4,
    ASM_PRINTER_TABLE_BYTE = 5,
    ASM_PRINTER_TABLES = 6
};

// the rows a part takes in the pieces table, a power of two past its pieces
#define ASM_PRINTER_PART_ROWS 8u

// the widest word number, length and letter offset the tables hold, and the widest index a table takes from a 16-bit
// field or entry
#define ASM_PRINTER_TABLE_BITS_MAX 16u

// the rows the power and byte tables take
#define ASM_PRINTER_POWER_ROWS 16u
#define ASM_PRINTER_BYTE_ROWS 256u

// the digits of the target's hash as the note writes it, sixteen hexadecimal digits
#define ASM_PRINTER_HASH_DIGITS 16u

// how the build ended: every word, part, step and table laid out; a form given as a construct; a header that holds a
// byte 0; a bank that writes its register with other than one number; more words, letters or parts than the tables
// hold; or a count past the caller's capacity
enum AsmPrinterCoreEnd
{
    ASM_PRINTER_CORE_OK = 0,
    ASM_PRINTER_CORE_CONSTRUCT = 1,
    ASM_PRINTER_CORE_HEADER = 2,
    ASM_PRINTER_CORE_BANK = 3,
    ASM_PRINTER_CORE_TABLES = 4,
    ASM_PRINTER_CORE_FULL = 5
};

// a text of the ruleset: `length` letters from `first` of the ruleset's letters
struct AsmPrinterCoreText
{
    unsigned int first;
    unsigned int length;
};

// the ruleset as the build reads it: every text's letters end to end, the texts, and the slots; each form's pieces
// from form_piece_first[form] to form_piece_first[form + 1] of the texts and its slots from form_slot_first[form] to
// form_slot_first[form + 1] of the slots, and 1 where it is given as a construct; each bank's pieces from
// bank_piece_first[bank] and the count of its slots; each fixed register's text and the header's; the target's hash and
// its compute capability and NVRTC's version as the note writes them
struct AsmPrinterCoreRules
{
    const unsigned char *letters;
    const AsmPrinterCoreText *texts;
    const unsigned int *slots;
    unsigned int form_piece_first[OPCODE_COUNT + 1u];
    unsigned int form_slot_first[OPCODE_COUNT + 1u];
    unsigned int form_construct[OPCODE_COUNT];
    unsigned int bank_piece_first[REGCLASS_COUNT];
    unsigned int bank_slots[REGCLASS_COUNT];
    unsigned int fixed_text[PHYSREG_COUNT];
    unsigned int header_text;
    unsigned long long block_hash;
    unsigned int target_numbers[4];
};

// The build: the ruleset it reads, the capacities of the caller's memory, and what it lays out there. The words, each
// once, by their numbers, 0 the empty word: each word's first letter and length, and its letters end to end; the parts,
// each once, ASM_PRINTER_PIECES words each, and each part's lanes; the lists as AsmPrinterRuleset holds them; the
// program's steps, fields, table values and tables, and the step it outputs; and how it ended and where
struct AsmPrinterCoreBuild
{
    AsmPrinterCoreRules rules;
    unsigned int word_capacity;
    unsigned int letter_capacity;
    unsigned int part_capacity;
    unsigned int form_part_capacity;
    unsigned int slot_capacity;
    unsigned int step_capacity;
    unsigned int table_capacity[ASM_PRINTER_TABLES];
    unsigned int words;
    unsigned int letters;
    unsigned int *word_start;
    unsigned int *word_length;
    unsigned char *word_letters;
    unsigned int parts;
    unsigned int *part_pieces;
    unsigned int *part_lanes;
    unsigned int form_part_first[OPCODE_COUNT + 1u];
    unsigned int form_part_count;
    unsigned int *form_parts;
    unsigned int form_slot_first[OPCODE_COUNT + 1u];
    unsigned int slot_count;
    unsigned int *slot_parameters;
    unsigned int bank_before[REGCLASS_COUNT];
    unsigned int bank_after[REGCLASS_COUNT];
    unsigned int fixed_word[PHYSREG_COUNT];
    unsigned int minus_word;
    unsigned int hash_word;
    unsigned int header_part;
    unsigned int target_numbers[4];
    unsigned int step_count;
    EngineRecordStep *steps;
    unsigned int one;
    unsigned int two;
    unsigned int output;
    unsigned int field_bits[ASM_PRINTER_FIELDS];
    unsigned int field_offset[ASM_PRINTER_FIELDS];
    unsigned int *values[ASM_PRINTER_TABLES];
    EngineRecordTable tables[ASM_PRINTER_TABLES];
    unsigned int end;
    int full;
};

// a word's number among the words, `length` letters at `letters` taken on where they are new; 0 where the words or
// letters are past their capacities, the build left full
CODEGEN_CORE unsigned int asm_printer_core_word(AsmPrinterCoreBuild *build, const unsigned char *letters,
                                                unsigned int length)
{
    for (unsigned int number = 0u; number < build->words; number += 1u)
    {
        if (build->word_length[number] != length)
        {
            continue;
        }
        const unsigned char *const held = &build->word_letters[build->word_start[number]];
        unsigned int at = 0u;
        while ((at < length) && (held[at] == letters[at]))
        {
            at += 1u;
        }
        if (at == length)
        {
            return number;
        }
    }
    if ((build->words >= build->word_capacity) || ((build->letter_capacity - build->letters) < length))
    {
        build->full = 1;
        return 0u;
    }
    const unsigned int number = build->words;
    build->word_start[number] = build->letters;
    build->word_length[number] = length;
    for (unsigned int at = 0u; at < length; at += 1u)
    {
        build->word_letters[build->letters + at] = letters[at];
    }
    build->letters += length;
    build->words += 1u;
    return number;
}

// the word of the ruleset's text `text`
CODEGEN_CORE unsigned int asm_printer_core_text(AsmPrinterCoreBuild *build, unsigned int text)
{
    const AsmPrinterCoreText *const given = &build->rules.texts[text];
    return asm_printer_core_word(build, &build->rules.letters[given->first], given->length);
}

// a part's number among the parts, taken on where it is new; 0 where the parts are past their capacity
CODEGEN_CORE unsigned int asm_printer_core_part(AsmPrinterCoreBuild *build, const unsigned int *part)
{
    for (unsigned int number = 0u; number < build->parts; number += 1u)
    {
        const unsigned int *const held = &build->part_pieces[number * ASM_PRINTER_PIECES];
        unsigned int piece = 0u;
        while ((piece < ASM_PRINTER_PIECES) && (held[piece] == part[piece]))
        {
            piece += 1u;
        }
        if (piece == ASM_PRINTER_PIECES)
        {
            return number;
        }
    }
    if (build->parts >= build->part_capacity)
    {
        build->full = 1;
        return 0u;
    }
    const unsigned int number = build->parts;
    for (unsigned int piece = 0u; piece < ASM_PRINTER_PIECES; piece += 1u)
    {
        build->part_pieces[(number * ASM_PRINTER_PIECES) + piece] = part[piece];
    }
    build->parts += 1u;
    return number;
}

// the least count of index bits that holds `count` rows, at least 1
CODEGEN_CORE unsigned int asm_printer_core_index_bits(unsigned long long count)
{
    unsigned int bits = 1u;
    while ((1ull << bits) < count)
    {
        bits += 1u;
    }
    return bits;
}

// a step taken on, its number returned; past the capacity nothing is written and the build is left full
CODEGEN_CORE unsigned int asm_printer_core_step(AsmPrinterCoreBuild *build, EngineRecordOperation operation,
                                                unsigned int left, unsigned int right)
{
    const unsigned int number = build->step_count;
    if (number >= build->step_capacity)
    {
        build->full = 1;
        return number;
    }
    build->steps[number] = {operation, left, right, 0u};
    build->step_count += 1u;
    return number;
}

CODEGEN_CORE unsigned int asm_printer_core_constant(AsmPrinterCoreBuild *build, unsigned int value)
{
    return asm_printer_core_step(build, ENGINE_RECORD_CONSTANT, value, 0u);
}

// 1 where left < right, else 0: the compare's order is -1, 0 or 1, and 1 less it, halved toward zero, is 1 only at -1
CODEGEN_CORE unsigned int asm_printer_core_below(AsmPrinterCoreBuild *build, unsigned int left, unsigned int right)
{
    const unsigned int order = asm_printer_core_step(build, ENGINE_RECORD_COMPARE, left, right);
    const unsigned int lessened = asm_printer_core_step(build, ENGINE_RECORD_DIFFERENCE, build->one, order);
    return asm_printer_core_step(build, ENGINE_RECORD_QUOTIENT, lessened, build->two);
}

#endif
