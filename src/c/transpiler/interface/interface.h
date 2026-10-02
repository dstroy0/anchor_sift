// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef INTERFACE_H
#define INTERFACE_H

// The interface, a probe runner (engine_table.md item 11(f) 3). A probe is a small program that
// asks the target one question. It runs in a probe process the interface can lose, and the interface records how it ended: the
// exit status, or the signal or fault that ended it, the output it wrote and the time it took. A probe that kills its
// process is answered by its death, and the next question is asked from a fresh process

#include "../../engine/engine_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

    // how a probe ended
    typedef enum
    {
        // the program could not be started, and nothing ran
        INTERFACE_ENDING_NOT_STARTED = 0,
        // it returned from main or called exit: the code is its exit status
        INTERFACE_ENDING_EXITED = 1,
        // a signal ended it (POSIX): the code is the signal's number
        INTERFACE_ENDING_SIGNALED = 2,
        // an exception nothing handled ended it (Windows): the code is its NTSTATUS. An exit status with its top bit
        // set, an NTSTATUS of warning or error severity, is read as the fault that ended the process; a program that
        // exits with one by choice reads as that fault too
        INTERFACE_ENDING_FAULTED = 3,
        // its time ran out and the interface ended it and every process it started
        INTERFACE_ENDING_OUT_OF_TIME = 4
    } InterfaceEnding;

    // the rule a signal or a fault names, the same on every host; the code keeps what the host told apart
    typedef enum
    {
        INTERFACE_FAULT_NONE = 0,
        // an integer division by zero or one that overflows (INT_MIN / -1), or a floating-point trap: SIGFPE, which
        // does not tell them apart, or on Windows 0xC0000094, 0xC0000095 and 0xC000008D to 0xC0000093, which do
        INTERFACE_FAULT_ARITHMETIC = 1,
        // an address the process may not read or write: SIGSEGV or SIGBUS, or 0xC0000005 and 0xC0000006
        INTERFACE_FAULT_ADDRESS = 2,
        // an instruction the part lacks or the process may not run: SIGILL, or 0xC000001D and 0xC0000096
        INTERFACE_FAULT_INSTRUCTION = 3,
        // the stack ran past its end: 0xC00000FD. POSIX delivers it as SIGSEGV, read as an address
        INTERFACE_FAULT_STACK = 4,
        // a trap or breakpoint: SIGTRAP, or 0x80000003
        INTERFACE_FAULT_TRAP = 5,
        // the program ended itself as failed: SIGABRT, or the fail-fast 0xC0000409
        INTERFACE_FAULT_ABORT = 6,
        // any other signal or fault
        INTERFACE_FAULT_OTHER = 7
    } InterfaceFault;

    // a probe: its command, NULL-ended, the program first and found along PATH where it names no folder; the file its
    // output and its errors are written to, together, as they are written (the interface makes it anew); and the most time
    // it is given, 0 for no limit. Its input is empty
    typedef struct
    {
        char *const *command;
        const char *output_path;
        unsigned long long limit_microseconds;
    } InterfaceProbe;

    // what the interface saw: how the probe ended and its code, the rule that names, the bytes of output it wrote, as many
    // of them as `output_capacity` holds read into `output` and ended by a zero byte (the capacity counts that byte),
    // and its wall time. `output` may be NULL with a capacity of 0
    typedef struct
    {
        InterfaceEnding ending;
        unsigned long long code;
        InterfaceFault fault;
        unsigned long long output_bytes;
        char *output;
        unsigned long long output_capacity;
        unsigned long long microseconds;
    } InterfaceAnswer;

    // runs one probe to its end and fills the answer. 0 once the probe has ended, however it ended; -1 where the interface
    // itself failed (the output file could not be made or read, or a started probe could not be waited on), with the
    // error raised in module ENGINE_MODULE_INTERFACE
    long interface_probe_run(const InterfaceProbe *probe, InterfaceAnswer *answer, EngineError *error);

    // the ending's name, and the fault's
    const char *interface_ending_name(InterfaceEnding ending);

    const char *interface_fault_name(InterfaceFault fault);

#ifdef __cplusplus
}
#endif

#endif
