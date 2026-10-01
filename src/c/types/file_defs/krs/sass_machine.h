// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The part's instructions as the cell's probes read them back, and one instruction's text in its parts
#ifndef SASS_MACHINE_H
#define SASS_MACHINE_H

// A form is an operation with its modifiers and, for each printed operand, what kind of thing it is and the mark it
// carries (- or ~ on a register, ! on a predicate). Two instructions of one form differ only in the values their
// operand fields hold, and the encoding a form was first seen with is the base every instruction of that form is
// assembled from (sass_assemble.h).
//
// Which bits carry which operand is not guessed. The cell's probe turns each of the form's 128 bits over one at a
// time, disassembles all 129 encodings, and keeps the runs of bits that changed a printed operand; those runs are the
// form's fields. Matching an operand to a field by the value the base happens to hold there is not enough, because a
// field the operation does not use holds 0 and a register or predicate numbered 0 matches it.
//
// A part's own file is machines/<part>. Its first line is `forms 1`, then `part <name>`, then a line a form:
//
//     form <operation> <kind><mark>,... <low> <high> <operand>:<first>-<last>;... <the instruction it was seen as>
//
// where <low> and <high> are the instruction's two 64-bit words in hex, low first, as a listing prints them, and the
// runs are the bits that change each operand, by the operand's place in the printed text.

// the longest instruction text kept, the longest operation or operand, and the most operands an instruction holds
#define SASS_MACHINE_TEXT 192u
#define SASS_MACHINE_TOKEN 64u
#define SASS_MACHINE_OPERANDS 8u
// the most runs of bits one form's operands take between them, and the most forms a machine file holds. The sweep
// puts every operation key to the disassembler from each of several carriers and found 1001 forms on sm_86 at
// 1024, close enough to the ceiling that another carrier or another part would have run into it, and a machine
// that fills up keeps the forms it has and counts the rest in `refused`.
//
// Widening repeats over what it finds for a bounded number of rounds. The count then follows how many operations
// and operand kinds lie that far from what a compiler wrote, and not how many the compiler wrote. Run to its own end
// instead it does not close: the count climbs past what a machine holds. A form is 736
// bytes, which puts this ceiling at 12 MB of a machine, and a run that reaches it says so in `refused` in place of
// dropping forms quietly
#define SASS_MACHINE_RUNS 32u
#define SASS_MACHINE_FORMS 16384u
#define SASS_MACHINE_PART 16u

// what one printed operand is
enum SassOperandKind
{
    // an operand the parts reader did not know, which no instruction of that form can be assembled
    SASS_OPERAND_UNKNOWN = 0,
    SASS_OPERAND_REGISTER = 1,
    SASS_OPERAND_PREDICATE = 2,
    SASS_OPERAND_IMMEDIATE = 3,
    SASS_OPERAND_CONSTANT = 4,
    SASS_OPERAND_ADDRESS = 5,
    SASS_OPERAND_LABEL = 6,
    SASS_OPERAND_UNIFORM = 7,
    SASS_OPERAND_SYSTEM = 8
};

// the mark an operand carries, which the form holds because the bit that puts it there is the operation's, not the
// operand's: the encoding a form was seen with already carries the mark every instruction of that form has
enum SassOperandMark
{
    SASS_MARK_NONE = 0,
    SASS_MARK_NEGATE = 1,
    SASS_MARK_INVERT = 2,
    SASS_MARK_NOT = 3
};

// one instruction's text in its parts: its guard predicate ("@P0", "@!P0" or empty), its operation with its
// modifiers, and each operand with the mark cut off it and .reuse dropped, since reuse lies in the control bits
typedef struct
{
    char guard[SASS_MACHINE_TOKEN];
    char operation[SASS_MACHINE_TOKEN];
    unsigned int operands;
    char operand[SASS_MACHINE_OPERANDS][SASS_MACHINE_TOKEN];
    unsigned int kind[SASS_MACHINE_OPERANDS];
    unsigned int mark[SASS_MACHINE_OPERANDS];
} SassInstructionParts;

// one run of bits that changes one printed operand, as the probe found it
typedef struct
{
    unsigned int operand;
    unsigned int first;
    unsigned int last;
} SassRun;

// one form, the encoding it was first seen with, and the bits its operands sit in
typedef struct
{
    char operation[SASS_MACHINE_TOKEN];
    unsigned int operands;
    unsigned int kind[SASS_MACHINE_OPERANDS];
    unsigned int mark[SASS_MACHINE_OPERANDS];
    unsigned long long low;
    unsigned long long high;
    unsigned int runs;
    SassRun run[SASS_MACHINE_RUNS];
    char text[SASS_MACHINE_TEXT];
} SassForm;

typedef struct
{
    char part[SASS_MACHINE_PART];
    unsigned int forms;
    unsigned int refused;
    SassForm form[SASS_MACHINE_FORMS];
} SassMachine;

// `text` read into its parts, whatever it holds: an operand the reader does not know is kept with the kind
// SASS_OPERAND_UNKNOWN, and the guard is empty where the instruction carries none
// 1 where `text` ends in the .hi a ruleset writes for the second register of a 64-bit pair (sass.krs)
int sass_high_half(const char *text);

void sass_instruction_read(const char *text, SassInstructionParts *parts);

// the encoding of EXIT as `machine` holds it, or 0 where it holds none. A cubin names the offset of every exit in
// its own section, and whatever writes one finds them by this
unsigned long long sass_exit_encoding(const SassMachine *machine);

// an instruction kept in `machine` as a form where it holds none of that form yet, `low` and `high` its encoding
// and `text` the instruction it was seen as; the form it was kept as, or the one already there, through `kept`, whose
// runs the caller fills. 1, or 0 where the machine is full, counted in machine->refused
int sass_machine_take(SassMachine *machine, const char *text, unsigned long long low, unsigned long long high,
                      SassForm **kept);

// the form of `parts`, or NULL where the machine holds none
const SassForm *sass_machine_form(const SassMachine *machine, const SassInstructionParts *parts);

// the machine written to `path`, and read back from it: 1, or 0 with the reason printed
int sass_machine_write(const SassMachine *machine, const char *path);

int sass_machine_read(SassMachine *machine, const char *path);

#endif
