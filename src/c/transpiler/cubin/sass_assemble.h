// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// One line of SASS turned into the sixteen bytes the part runs
#ifndef SASS_ASSEMBLE_H
#define SASS_ASSEMBLE_H

// The assembler takes the encoding of the instruction's form (sass_machine.h) as its base and writes the
// instruction's own operands into it. Where each operand sits is not assumed: the base carries its own operands, and
// the fields are found by giving each operand the first field of its kind whose value in the base is the value the
// base printed there. A form whose operands cannot all be placed that way assembles nothing and says so, and so does
// an operand the assembler cannot turn into a number, which must then be the one the base holds.
//
// The fields are the ones the cell's probes found by turning each of an operation's 128 bits over and decoding: a
// guard predicate at 12 to 15, registers at 16 to 23, 24 to 31, 32 to 39 and 64 to 71, an immediate at 32 to 63, a
// second at 72 to 79, predicates at 81 to 83, 84 to 86 and 87 to 89, a constant's offset and an address's at 40 to
// 63, and the scheduler's own bits at 105 to 127.

#include "../../types/file_defs/krs/sass_machine.h"

#include <stddef.h>

// what the assembler does with the scheduler's bits, which no listing prints and no probe read
enum SassControl
{
    // the base's own, for an instruction being written back as it was read
    SASS_CONTROL_BASE = 0,
    // every instruction stalled the soonest its operation's result is read, the longest the field holds where none is
    // measured, and waiting on every barrier, and one whose result comes back late setting a barrier: an order that is
    // always in order
    SASS_CONTROL_SAFE = 1
};

// `text` assembled into `low` and `high` against `machine`. `address` is where the instruction lies in its section,
// which a branch counts its target from; `target` is that target's address, and is read only where the instruction
// takes a label. 1, or 0 with the reason printed
int sass_assemble(const SassMachine *machine, const char *text, unsigned long long address, unsigned long long target,
                  unsigned int control, unsigned long long *low, unsigned long long *high);

// the count of instructions `text` holds, one a line, and each assembled into `code` at sixteen bytes apiece, labels
// resolved from the lines that name them. 0 where a line did not assemble, with the reason printed; `code` holds
// `room` bytes
unsigned int sass_assemble_lines(const SassMachine *machine, const char *text, unsigned int control,
                                 unsigned char *code, unsigned long long room);

// The read back, the assembler run the other way through the same forms and fields. An encoding is held by the
// form whose bits, outside its operands' fields, its guard and the scheduler's bits, are its own; of several, the
// one with the fewest bits left to its operands. Its text is the guard, the operation and each operand read from the
// field the assembler writes it to, a label as the address it lands on: `address` is where the encoding lies. 1, or 0
// where no form holds it. Nothing here changes an encoding: an emitted instruction is read back, never rewritten and
// never optimized: code written to run in constant time runs as it was written.
int sass_encoding_read(const SassMachine *machine, unsigned long long low, unsigned long long high,
                       unsigned long long address, char *text, size_t room);

// A loop is an address added to until it comes back where it began. The walk evaluates one encoding as the
// instruction that takes a loop back: its guard is the flag the loop is steered on alone, and it is taken
// only where the flag is true; one of its label or immediate operands, added to the address after it and kept to the
// field's own width, lands on `target`; and its first operand writes neither a register the loop keeps nor the flag.
// The walk is a bumper a caller turns on or off and stops at any step of: it never changes the encoding, and with it
// off whatever was emitted is what runs.
typedef struct
{
    unsigned long long address;
    unsigned long long target;
    unsigned int flag;
    const unsigned int *live;
    unsigned int lives;
} SassLoopWalk;

// 1 where the encoding comes back to the target on the flag alone and writes nothing the loop keeps. The step it
// stopped at through `step`: 0 no form holds it, 1 its guard, 2 where it lands, 3 what it writes, and 4 where it
// came through every step
int sass_loop_walk(const SassMachine *machine, const SassLoopWalk *walk, unsigned long long low, unsigned long long high,
                   unsigned int *step);

#endif
