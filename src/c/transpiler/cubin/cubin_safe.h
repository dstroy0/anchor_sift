// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Whether a kernel's machine code may be put to the part, read on the host before the driver is handed it
#ifndef CUBIN_SAFE_H
#define CUBIN_SAFE_H

// A cubin the driver is handed runs as it is written. Machine code our own assembler wrote, or a probe turned one bit
// of, is read here first with our own reader against the machine file, and goes to the part only where every
// instruction it reaches holds to these, in order:
//
//   1. its scheduler's bits wait on all six barriers and stall at least the soonest its operation's result is read
//      (sass_operation_schedule), the longest where none is measured or no form holds the instruction: no
//      instruction reads a result that is not back;
//   2. where a form of the machine file holds its encoding, that form neither transfers control nor waits
//      (sass_operation_control_or_wait), EXIT alone excepted;
//   3. where no form holds it, its operation key holds forms and no form under the key transfers control or waits.
//      Whatever its other bits say, it falls through to the next instruction. One instruction at most is held by no
//      form: the one a probe asks about;
//   4. an EXIT with no guard is reached: no thread runs off the end of the code.
//
// The code is read from its first instruction to its first EXIT with no guard, and nothing past it is read, since
// nothing reaches it: the self branch and the padding after a kernel's last exit are never run. Nothing here changes
// the code.

#include "../../types/file_defs/krs/sass_machine.h"

// what the code was found to be: safe, or the first rule an instruction broke
enum CubinSafe
{
    CUBIN_SAFE = 0,
    CUBIN_SAFE_SIZE = 1,
    CUBIN_SAFE_STALL = 2,
    CUBIN_SAFE_WAIT = 3,
    CUBIN_SAFE_CONTROL = 4,
    CUBIN_SAFE_KEY = 5,
    CUBIN_SAFE_UNHELD = 6,
    CUBIN_SAFE_EXIT = 7
};

// The verdict on `code`, `code_size` bytes of sixteen-byte instructions, against `machine`: CUBIN_SAFE, or the rule
// broken, with the offset of the instruction that broke it through `at`. CUBIN_SAFE_SIZE where the size is 0 or not a
// whole count of instructions, CUBIN_SAFE_EXIT where the code ends before an EXIT with no guard
unsigned int cubin_safe(const SassMachine *machine, const unsigned char *code, unsigned long long code_size,
                        unsigned long long *at);

// The verdict on every code section of the cubin `image`, `size` bytes, held to cubin_safe one section after another:
// CUBIN_SAFE where every section is, or the first rule broken, with the offset in the image of the instruction that
// broke it through `at`. CUBIN_SAFE_SIZE where the image holds no code section it can read
unsigned int cubin_safe_image(const SassMachine *machine, const unsigned char *image, unsigned long long size,
                              unsigned long long *at);

// the verdict's name, for a line that reports it
const char *cubin_safe_name(unsigned int verdict);

#endif
