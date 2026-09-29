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
#include "sass_machine.h"

#include <stdio.h>

// the longest instruction text kept, and the most instructions a listing holds
#define SASS_TEXT 192u
#define SASS_LISTING_LIMIT 4096u
// the most operands an instruction's text holds, and the longest each is kept
#define SASS_OPERANDS 8u
#define SASS_OPERAND_TEXT 64u
// the most questions and the most operations the probe keeps, and the longest question name
#define SASS_QUESTIONS 256u
#define SASS_OPERATIONS 512u
#define SASS_NAME 160u
// an operation's encoding and the 128 encodings one bit apart from it
#define SASS_BITS 128u
#define SASS_ENCODINGS (SASS_BITS + 1u)
// the bits of the low word that name an operation and its operands' kinds. Every value of these is a question the
// sweep puts to the disassembler, which is what makes that search unbounded by any compiler's output
#define SASS_OPERATION_MASK 0xfffull

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

// The channels this system answers a question on (the .ksc, Doug 29 Sep: "system classification (language map) ...
// which return answers, which return nothing and which are illegal on their own"). A probe is not a thing of its
// own: it is a question put on one of these and the answer read back. Which channels a system has is the system's
// to declare and is never assumed - a part with no compiler and no disassembler still answers on `run`, with fewer
// names and more slowly, and everything above is reached the same way through the one channel it does have
#define SASS_CHANNELS(channel_)                                                                                        \
    channel_(RUN, "run", "the system takes the question as its own code, runs it, and a word comes back")              \
    channel_(DECODE, "decode", "the system's disassembler is handed an encoding and names it")                         \
    channel_(COMPILE, "compile", "the system's compiler is handed a source and emits instructions for it")             \
    channel_(CLOCK, "clock", "two codings of one thing are run against each other and timed")

// What came back. These three are the whole of it: a question is taken and answered, taken and answers nothing a
// reader can see, or refused. The third is the one that prunes - an encoding the decoder names but that no run will
// take is illegal on its own, however well it decoded
#define SASS_CLASSES(class_)                                                                                           \
    class_(ANSWERS, "answers", "the question was put and the answer came back as the question says")                   \
    class_(NOTHING, "nothing", "the question was taken and left nothing a reader here can see")                        \
    class_(ILLEGAL, "illegal", "the question was refused: the system will not take it as it stands")

#define SASS_CHANNEL_NAMED(name_, text_, why_) SASS_CHANNEL_##name_,
#define SASS_CLASS_NAMED(name_, text_, why_) SASS_CLASS_##name_,

enum SassChannel
{
    SASS_CHANNELS(SASS_CHANNEL_NAMED) SASS_CHANNEL_COUNT
};

enum SassClass
{
    SASS_CLASSES(SASS_CLASS_NAMED) SASS_CLASS_COUNT
};

// one question put on one channel, and what came back. The word is what the system answered where the channel gives
// one, and 0 otherwise
typedef struct
{
    unsigned char channel;
    unsigned char answered;
    unsigned int word;
    char question[SASS_TEXT];
} SassClassed;

// one question and its answer kept for the .ksc (cell_sass_probe_class.c)
void sass_class_take(unsigned int channel, unsigned int answered, const char *question, unsigned int word);

// one more question counted on a channel, its text not kept: the decode channel puts tens of thousands of these and
// only the count of each class is worth writing
void sass_class_count(unsigned int channel, unsigned int answered);

// the system's classification written to `machines`/<part>.ksc: 1, or 0 with the reason printed
int sass_class_write(const char *machines, const char *part);

// one operation the listings hold, keyed by the low 12 bits of its encoding: the first instruction seen with it
typedef struct
{
    unsigned int key;
    SassInstruction first;
} SassOperation;

// what one run of the probe has found so far: where its cubins are, which program assembles them, and the part, the
// questions and the operations read out of them
typedef struct
{
    const char *folder;
    const char *prober;
    char architecture[16];
    unsigned int questions;
    char names[SASS_QUESTIONS][SASS_NAME];
    unsigned int operations;
    SassOperation operation[SASS_OPERATIONS];
    unsigned int failed;
} SassProbe;

// one process run through the cell with its output written to `output_path`, and read into the shared buffer
// (sass_output): its exit status, or -1 where it did not exit, with how it ended printed
int sass_run(char *const *command, const char *output_path);

// the cubin at `path` run on the device through cell_ptx_probe over one case, its answer into `answered`: 1, or 0
// with the reason printed (cell_sass_probe_ask.c)
int sass_cubin_answer(SassProbe *probe, const char *path, char *answered, size_t room);

// every question of the cell's own put to the part in code no toolchain wrote, `asked` counting them: how many the
// part answered as the question says
unsigned int sass_cubin_asks(SassProbe *probe, const SassMachine *machine, unsigned int *asked);

// every pair of codings weighed against each other in the part's own clock, `asked` counting the pairs: how many
// gave a reading that stands above the noise
unsigned int sass_cubin_prefers(SassProbe *probe, const SassMachine *machine, unsigned int *asked);

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

// every instruction of `listing` that the listing gave an encoding for taken into `machine` as a form
// (cell_sass_probe_machine.c)
void sass_machine_listing(SassMachine *machine, const SassListing *listing);

// Every operation one bit from a form the listings gave, taken into `machine` as a form of its own: each listed
// form's 128 bits are turned over and decoded, and a decode that prints a different operation is an instruction the
// compiler never wrote and the part still answers for. This is how a spelling reaches the machine without being
// guessed: ISETP.EQ.U32.AND, ISETP.EQ.U32.AND.EX and ISETP.LT.AND are each one bit from a comparison the listings
// did hold, and sass.krs names all three only because the compiler read zero and below off the negations instead.
//
// Two things a widened form is not. It is decodable, not run: only a question that assembles one and runs it says
// the part executes it. And its operand bits are the ones the form it came from held, which the new operation may
// read as something else - PLOP3.LUT is one bit from SHF.L.U32, and it decodes with a register standing where a
// predicate belongs, so its form carries that kind and no predicate operation can be written from it. An operation
// reached this way is the part saying the encoding is legal, not a form ready to assemble from. The count taken
unsigned int sass_machine_widen(SassMachine *machine, const char *architecture, const char *folder);

// Every operation the part has a coding for, asked of its disassembler without starting from anything a compiler
// wrote (Doug, 29 Sep: "we can unbound the search entirely to find new words we didn't know existed").
//
// Widening asks what lies one bit from a form some compiler emitted, which bounds the search by what a compiler
// happens to write. The encoding's own structure lifts that bound. The low 12 bits of the low word key the
// operation and its operands' kinds, and the probe already found that much, so 4096 questions reach every operation
// the disassembler will name. The carrier for all of them is a form the part ran, with its key cut out and each key
// in turn put back, which leaves every bit that is not the key holding what a real instruction held.
//
// What comes back is read the same way widening reads it, with one difference: a widened form is kept where it
// names something other than the form it came from, and a swept one came from no form, so every operation named
// here is one to keep. The operand bits belong to the carrier and not to the operation they now sit under, the same
// caveat widening carries; sass_machine_fields finds each kept form's fields afterward by turning its own bits. The
// count of forms this added
unsigned int sass_machine_sweep(SassMachine *machine, const char *architecture, const char *folder);

// each form's operand fields found by turning its 128 bits over and decoding, and the machine written to
// `folder`/machine: 1, or 0 where a form's fields were not found or the file was not written
int sass_machine_fields(SassMachine *machine, const char *architecture, const char *folder);

// the machine file the tree holds for this part, in `machines`, checked against the one this run learned: 1 where the two
// agree, or where the tree holds none for this part; 0 where they differ, with what to do printed
int sass_machine_same(const SassMachine *machine, const char *machines);

// how a check of the assembler came out: how many instructions were written back, how many of them the assembler
// refused, how many came out as the very bytes the listing gave, and how many read back as the text they were
// written from. The bytes are the stronger reading and the text is the true one: the probes found bits an
// instruction carries that no listing prints (LDG's 32 to 39), so two instructions that print the same can differ
typedef struct
{
    unsigned int checked;
    unsigned int refused;
    unsigned int same_bits;
    unsigned int same_text;
    unsigned int by_bytes;
} SassCheck;

// every instruction of `listing` assembled from its text alone, checked against the encoding the listing gave it and then
// disassembled and checked against the text it was written from, counted into `tally`: how many did not read back, with the
// first `report` of them printed
unsigned int sass_machine_check(const SassMachine *machine, const SassListing *listing, const char *architecture,
                                const char *folder, SassCheck *tally, unsigned int report);

// a listing's own output turned back into the text it was written from, one instruction or label a line, into `text`,
// which holds `room` letters: how many were written
unsigned int sass_text_read(const char *output, const char *kernel, char *text, unsigned int room);

// the listing of `name` in `folder` turned back into the text it was written from, into `text`, and kept beside it as
// <name>.text: how many letters, 0 where the listing was not read
unsigned int sass_cubin_text(const char *folder, const char *name, char *text, unsigned int room);

// `text` assembled into the section `kernel` of a cubin made from `pattern`.cubin, written as `into`.cubin in the
// folder: 1, or 0 with the reason printed. Every other section of the pattern is carried over untouched, which is
// what lets one function of a cubin be replaced where another is left as the part's own compiler wrote it
int sass_cubin_kernel(const SassMachine *machine, const char *folder, const char *pattern, const char *text,
                      const char *into, const char *kernel);

// the same, into the probe's own question kernel
int sass_cubin_from_text(const SassMachine *machine, const char *folder, const char *pattern, const char *text,
                         const char *into);

// A lane of our own written into the resident's cubin, in place of the empty cycle_lane the resident was built
// with. This is how a SASS program is put together, and why sass.krs gives program_unit as an error without that
// being a gap: the resident is 110 instructions of PTX the part's compiler turns into SASS that already runs, and
// re-deriving it from a ruleset would throw that away. The lane is the part we write; the resident is the part we
// ask for and keep
int sass_cubin_lane_into(const SassMachine *machine, const char *folder, const char *text, const char *into);

// the kernel `name` in `folder` written again out of its own listing, as <name>_written.cubin
int sass_cubin_round(const SassMachine *machine, const char *folder, const char *name);

#endif
