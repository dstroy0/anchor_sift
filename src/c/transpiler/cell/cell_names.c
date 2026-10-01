// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_names.c: the names a report prints for a probe's ending and its fault
#include "cell.h"

const char *cell_ending_name(CellEnding ending)
{
    switch (ending)
    {
    case CELL_ENDING_NOT_STARTED:
        return "not started";
    case CELL_ENDING_EXITED:
        return "exited";
    case CELL_ENDING_SIGNALED:
        return "signaled";
    case CELL_ENDING_FAULTED:
        return "faulted";
    case CELL_ENDING_OUT_OF_TIME:
        return "out of time";
    default:
        return "unknown";
    }
}

const char *cell_fault_name(CellFault fault)
{
    switch (fault)
    {
    case CELL_FAULT_NONE:
        return "none";
    case CELL_FAULT_ARITHMETIC:
        return "arithmetic";
    case CELL_FAULT_ADDRESS:
        return "address";
    case CELL_FAULT_INSTRUCTION:
        return "instruction";
    case CELL_FAULT_STACK:
        return "stack";
    case CELL_FAULT_TRAP:
        return "trap";
    case CELL_FAULT_ABORT:
        return "abort";
    case CELL_FAULT_OTHER:
        return "other";
    default:
        return "unknown";
    }
}
