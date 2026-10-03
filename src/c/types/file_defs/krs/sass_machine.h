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

// the scheduler's bits above the operation, which no listing prints: the stall, the yield, a write barrier set where
// the result comes back late, a read barrier set where an operand is read late, the wait over six barriers and the
// reuse flags. A barrier field of 7 sets none
#define SASS_STALL_FIRST 105u
#define SASS_YIELD_FIRST 109u
#define SASS_WRITE_BARRIER_FIRST 110u
#define SASS_READ_BARRIER_FIRST 113u
#define SASS_WAIT_FIRST 116u
#define SASS_REUSE_FIRST 122u
#define SASS_BARRIER_NONE 7u
// the longest stall the four bits of the stall field hold, and the wait field set to every one of the six barriers
#define SASS_STALL_LONGEST 15u
#define SASS_WAIT_EVERY 0x3fu
// the bits of the low word that name an operation and its operands' kinds, its operation key
#define SASS_OPERATION_MASK 0xfffull

// 1 where `operation` transfers control or waits, which run on the part can loop or stall it: a branch, a call, a
// return, a barrier, a sleep and a trap. A straight instruction falls through to the next and cannot loop by itself
int sass_operation_control_or_wait(const char *operation);

// how the scheduler holds an operation's result, a property of the operation and not of one encoding of it: ready
// after a fixed count of cycles, back late behind a write barrier its readers wait on, or a store whose operands are
// read late behind a read barrier, which whatever writes those registers next waits on. NVIDIA's compiler gives every
// late operation a write barrier and every store a read barrier over the tree's CUDA sources (monolith_scheduler.md).
// A barrier counts its producers and a wait on it holds until all of them are back, and a late result left without a
// barrier is held behind another of the same operation out of the same unit, its results back in the order they were
// put
enum SassSchedule
{
    SASS_SCHEDULE_FIXED = 0,
    SASS_SCHEDULE_LATE = 1,
    SASS_SCHEDULE_STORE = 2
};

// 1 where the encoding whose high word is `high` sets the barrier whose field begins at `first`,
// SASS_WRITE_BARRIER_FIRST or SASS_READ_BARRIER_FIRST: the result or an operand comes back late, and whatever waits on
// it waits on that barrier
int sass_barrier_set(unsigned long long high, unsigned int first);

// the schedule of `operation`, its modifiers included, read from its name before the first dot, and through `soonest`
// the fewest cycles NVIDIA's compiler leaves between a fixed result and the first instruction that reads it, as
// measured for that operation over the tree's CUDA sources (monolith_scheduler.md). An operation with no measured
// count, and a late result or a store, leave SASS_STALL_LONGEST there
unsigned int sass_operation_schedule(const char *operation, unsigned int *soonest);

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
