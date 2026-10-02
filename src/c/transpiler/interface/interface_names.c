// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_names.c: the names a report prints for a probe's ending and its fault
#include "interface.h"

const char *interface_ending_name(InterfaceEnding ending)
{
    switch (ending)
    {
    case INTERFACE_ENDING_NOT_STARTED:
        return "not started";
    case INTERFACE_ENDING_EXITED:
        return "exited";
    case INTERFACE_ENDING_SIGNALED:
        return "signaled";
    case INTERFACE_ENDING_FAULTED:
        return "faulted";
    case INTERFACE_ENDING_OUT_OF_TIME:
        return "out of time";
    default:
        return "unknown";
    }
}

const char *interface_fault_name(InterfaceFault fault)
{
    switch (fault)
    {
    case INTERFACE_FAULT_NONE:
        return "none";
    case INTERFACE_FAULT_ARITHMETIC:
        return "arithmetic";
    case INTERFACE_FAULT_ADDRESS:
        return "address";
    case INTERFACE_FAULT_INSTRUCTION:
        return "instruction";
    case INTERFACE_FAULT_STACK:
        return "stack";
    case INTERFACE_FAULT_TRAP:
        return "trap";
    case INTERFACE_FAULT_ABORT:
        return "abort";
    case INTERFACE_FAULT_OTHER:
        return "other";
    default:
        return "unknown";
    }
}
