// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CODEGEN_CORE_H
#define CODEGEN_CORE_H

// The register lane's decisions, as one source the host and the device both compile (engine_table.md item 11(f)(a),
// the code generator on the device). For each step it decides which forms of the language's ruleset the step is written
// in and with which arguments, and it decides the lane's declarations, opening, close and resident, and the schedule of
// its body into states; it writes nothing. An argument is a register of a bank by its number, a register the lane holds
// throughout, or a number. The forms it decides are the same on any language, and the ruleset writes them
// (code_generator.cu on the host, the assembly printer on the device, asm_printer.h). What a step decides from outside
// itself is laid out before any step is decided, and steps are decided apart and in any order: each record word's first
// and last put, each atom word's first reader, and the loop number each step begins at. A step writes its forms into a
// sink, or counts them where the sink holds none. A device decides a lane in two passes, a count and a write, a
// thread a step. The lane's own forms come after every step, from what the steps left: the scratch a construct takes
// goes on from where the last step left each bank, as the lane was always written.
//
// The forms and what they do are the lane's as code_generator.cu wrote them before this header held them, form for form
// and argument for argument, and the lane's text is unchanged (engine_table.md item 11(f)(a) holds the two to each
// other).

#include "instruction_selection.h"
#include "lowering.h"
#include "machine_ir.h"
#include "prologue_epilogue.h"
#include "scheduling.h"

#endif
