// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the cell_sass_probe*.c pieces share
#ifndef CELL_SASS_PROBE_H
#define CELL_SASS_PROBE_H

// The SASS probe (engine_table.md item 11(f)(a)): the device's machine code found by asking its disassembler, so that
// a ruleset of SASS can be written from what the probes saw. cell_ptx_probe assembles each membership question's
// kernel, the forms of ptx.krs, into a cubin, and the frame with no body into another; nvdisasm lists each, and the
// operations a question's listing holds past the frame's are its forms' machine code. Then each operation seen, keyed
// by the low 12 bits of its encoding, is decoded with each of its 128 bits turned over, one nvdisasm --binary for all
// 129 encodings: a bit that changes a register operand is that operand's field, one that changes the operation's name
// is the operation's, one the disassembler refuses is an encoding the part lacks, and one that changes nothing in the
// text is either control (the stall, yield and barriers the scheduler sets) or unused. Every process is run through the
// cell, whose runner loses nothing when the disassembler fails
#include "cell.h"

#include <stdio.h>

// the longest instruction text kept, and the most instructions a listing holds
#define SASS_TEXT 192u
#define SASS_LISTING_LIMIT 4096u
// the most operands an instruction's text holds, and the longest each is kept
#define SASS_OPERANDS 8u
#define SASS_OPERAND_TEXT 64u
// an operation's encoding and the 128 encodings one bit apart from it
#define SASS_BITS 128u
#define SASS_ENCODINGS (SASS_BITS + 1u)

// one instruction as the disassembler printed it: its address, its text without the ending ';', and its encoding, the
// low word holding the operation and its operands, the high word more operands and the control, both 0 where the
// listing gave no encoding
typedef struct
{
    unsigned long long address;
    char text[SASS_TEXT];
    unsigned long long low;
    unsigned long long high;
} SassInstruction;

typedef struct
{
    unsigned int count;
    SassInstruction instructions[SASS_LISTING_LIMIT];
} SassListing;

// an instruction's text in its parts: the guard predicate ("@P0", "" where it has none), the operation and each
// operand
typedef struct
{
    char predicate[SASS_OPERAND_TEXT];
    char operation[SASS_OPERAND_TEXT];
    unsigned int operands;
    char operand[SASS_OPERANDS][SASS_OPERAND_TEXT];
} SassParts;

// one process run through the cell with its output written to `output_path`, and read into the shared buffer
// (sass_output): its exit status, or -1 where it did not exit, with how it ended printed
int sass_run(char *const *command, const char *output_path);

// the output of the last process sass_run ran
const char *sass_output(void);

// a listing read from a disassembler's output: each line holding an address, "/*0000*/", is an instruction, and a line
// holding only "/* 0x... */" after one is its encoding's high word. 0 where the listing is longer than it holds
int sass_listing_read(const char *output, SassListing *listing);

void sass_parts_read(const char *text, SassParts *parts);

// the encodings decoded by the disassembler for `architecture` ("SM86"), `count` of them, into `texts`: an encoding
// the disassembler refuses has the text "illegal", and one it takes and prints no line for, "unprinted". The encodings
// are written to `path`.bin and decoded, and where any is refused, the rest are written and decoded again. 1, or 0
// where the disassembler failed otherwise
int sass_decode(const char *architecture, const char *path, const unsigned long long *low,
                const unsigned long long *high, unsigned int count, char (*texts)[SASS_TEXT]);

#endif
