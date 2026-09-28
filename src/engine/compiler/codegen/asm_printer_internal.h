// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the asm_printer_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef ASM_PRINTER_INTERNAL_H
#define ASM_PRINTER_INTERNAL_H

#include "../cycle/cycle.h"
#include "../key_schedule/key_schedule.h"
#include "../keymath/keymath.h"
#include "asm_printer.h"
#include "ruleset_reader.h"

#include <stddef.h>
#include <stdio.h>

#include <array>
#include <map>
#include <string>
#include <vector>

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

// the text being laid out: the words, each once, by their numbers, 0 the empty word; and the parts, each once
struct AsmPrinterWords
{
    std::vector<std::string> words;
    std::map<std::string, unsigned int> numbered;
    std::vector<std::array<unsigned int, ASM_PRINTER_PIECES>> parts;
    std::map<std::array<unsigned int, ASM_PRINTER_PIECES>, unsigned int> part_numbered;
};

unsigned int asm_printer_word(AsmPrinterWords *words, const std::string &word);

unsigned int asm_printer_part(AsmPrinterWords *words, const std::array<unsigned int, ASM_PRINTER_PIECES> &part);

// the assembly printer's steps being laid out
struct AsmPrinterSteps
{
    std::vector<EngineRecordStep> steps;
    unsigned int one;
    unsigned int two;
};

unsigned int asm_printer_program_build(AsmPrinterSteps *printer_steps);

void asm_printer_tables(const AsmPrinterWords *words, std::vector<unsigned int> (&values)[ASM_PRINTER_TABLES],
                        EngineRecordTable (&tables)[ASM_PRINTER_TABLES]);

#endif
