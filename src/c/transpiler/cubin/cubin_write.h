// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// A cubin written from a kernel's machine code and a cubin the toolchain made for a kernel that takes the same parameters
#ifndef CUBIN_WRITE_H
#define CUBIN_WRITE_H

// A cubin is an ELF, and almost all of it says what the kernel takes and not what it does: its parameters, the
// constant bank they lie in, its notes, its symbols and its relocations. The cell's probes found that between two
// cubins of one kernel only its code, the size of the code, the count of registers it holds and the offsets of its
// exits differ (engine_plan.md, the SASS findings). A cubin is therefore written by taking one the toolchain made
// for a kernel that takes the same parameters and putting new code in it, in place of laying an ELF out from
// nothing: everything the writer does not understand is carried over, never invented.
//
// The template's own kernel decides what fits: the same name, the same parameters, the same constant bank. Give
// the writer code that takes other parameters and the cubin loads and reads the wrong parameters.

// what a cubin is written from
typedef struct
{
    // the cubin the toolchain made, and its size
    const unsigned char *pattern;
    unsigned long long pattern_size;
    // the kernel's name, which names its code section (.text.<kernel>) and its own info section
    const char *kernel;
    // the kernel's machine code, sixteen bytes an instruction, and its size
    const unsigned char *code;
    unsigned long long code_size;
    // how many registers a thread of the kernel holds, which the part reads from the ELF and no instruction declares
    unsigned int registers;
    // where each exit lies in the code, in bytes, which the kernel's info section carries
    const unsigned int *exits;
    unsigned int exit_count;
} CubinWrite;

// the cubin written into `written`, which holds `room` bytes, and its size through `size`. 1, or 0 with the reason
// printed, having written nothing
int cubin_write(const CubinWrite *args, unsigned char *written, unsigned long long room, unsigned long long *size);

// the offsets of the exits in `code`, into `exits`, which holds `room` of them: the count found. An exit is the
// instruction EXIT, whose encoding is taken from `exit_low` masked to the operation's own bits
unsigned int cubin_exits_find(const unsigned char *code, unsigned long long code_size, unsigned long long exit_low,
                              unsigned int *exits, unsigned int room);

// how many registers a thread of `kernel` holds in `pattern`, which its code section carries in the top byte of its
// info; 0 where the pattern holds no such kernel
unsigned int cubin_registers_read(const unsigned char *pattern, const char *kernel);

// every code section of `cubin`, which is `size` bytes, each a section named .text.<function>: the offset of each
// through `offsets` and its length through `sizes`, which hold `room`. The count found, or 0 where there is none or a
// header, a name or a section lies past the cubin's end, or there are more than `room`
unsigned int cubin_code_sections(const unsigned char *cubin, unsigned long long size, unsigned long long *offsets,
                                 unsigned long long *sizes, unsigned int room);

#endif
