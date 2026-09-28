// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CELL_H
#define CELL_H

// The cell, a probe runner (engine_table.md item 11(f) 3; posit 12 of 26 September). A probe is a small program that
// asks the target one question. It runs in a child process the cell can lose, and the cell records how it ended: the
// exit status, or the signal or fault that ended it, the output it wrote and the time it took. A probe that kills its
// process is answered by its death, and the next question is asked from a fresh process

#include "engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

    // how a probe ended
    typedef enum
    {
        // the program could not be started, and nothing ran
        CELL_ENDING_NOT_STARTED = 0,
        // it returned from main or called exit: the code is its exit status
        CELL_ENDING_EXITED = 1,
        // a signal ended it (POSIX): the code is the signal's number
        CELL_ENDING_SIGNALED = 2,
        // an exception nothing handled ended it (Windows): the code is its NTSTATUS. An exit status with its top bit
        // set, an NTSTATUS of warning or error severity, is read as the fault that ended the process; a program that
        // exits with one by choice reads as that fault too
        CELL_ENDING_FAULTED = 3,
        // its time ran out and the cell ended it and every process it started
        CELL_ENDING_OUT_OF_TIME = 4
    } CellEnding;

    // the rule a signal or a fault names, the same on every host; the code keeps what the host told apart
    typedef enum
    {
        CELL_FAULT_NONE = 0,
        // an integer division by zero or one that overflows (INT_MIN / -1), or a floating-point trap: SIGFPE, which
        // does not tell them apart, or on Windows 0xC0000094, 0xC0000095 and 0xC000008D to 0xC0000093, which do
        CELL_FAULT_ARITHMETIC = 1,
        // an address the process may not read or write: SIGSEGV or SIGBUS, or 0xC0000005 and 0xC0000006
        CELL_FAULT_ADDRESS = 2,
        // an instruction the part lacks or the process may not run: SIGILL, or 0xC000001D and 0xC0000096
        CELL_FAULT_INSTRUCTION = 3,
        // the stack ran past its end: 0xC00000FD. POSIX delivers it as SIGSEGV, read as an address
        CELL_FAULT_STACK = 4,
        // a trap or breakpoint: SIGTRAP, or 0x80000003
        CELL_FAULT_TRAP = 5,
        // the program ended itself as failed: SIGABRT, or the fail-fast 0xC0000409
        CELL_FAULT_ABORT = 6,
        // any other signal or fault
        CELL_FAULT_OTHER = 7
    } CellFault;

    // a probe: its command, NULL-ended, the program first and found along PATH where it names no folder; the file its
    // output and its errors are written to, together, as they are written (the cell makes it anew); and the most time
    // it is given, 0 for no limit. Its input is empty
    typedef struct
    {
        char *const *command;
        const char *output_path;
        unsigned long long limit_microseconds;
    } CellProbe;

    // what the cell saw: how the probe ended and its code, the rule that names, the bytes of output it wrote, as many
    // of them as `output_capacity` holds read into `output` and ended by a zero byte (the capacity counts that byte),
    // and its wall time. `output` may be NULL with a capacity of 0
    typedef struct
    {
        CellEnding ending;
        unsigned long long code;
        CellFault fault;
        unsigned long long output_bytes;
        char *output;
        unsigned long long output_capacity;
        unsigned long long microseconds;
    } CellAnswer;

    // runs one probe to its end and fills the answer. 0 once the probe has ended, however it ended; -1 where the cell
    // itself failed (the output file could not be made or read, or a started probe could not be waited on), with the
    // error raised in module ENGINE_MODULE_CELL
    long cell_probe_run(const CellProbe *probe, CellAnswer *answer, EngineError *error);

    // the ending's name, and the fault's
    const char *cell_ending_name(CellEnding ending);

    const char *cell_fault_name(CellFault fault);

#ifdef __cplusplus
}
#endif

#endif
