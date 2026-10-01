// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the asm_printer_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef ASM_PRINTER_INTERNAL_H
#define ASM_PRINTER_INTERNAL_H

#include "../../../c/engine/analysis/cycle/cycle.h"
#include "../../../c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../c/engine/analysis/keymath/keymath.h"
#include "asm_printer.h"
#include "asm_printer_core.h"
#include "ruleset_reader.h"

#include <stddef.h>
#include <stdio.h>

#include <string>
#include <vector>

// the ruleset, the target and the header as the core's build reads them, in host memory: every text's letters end to
// end, the texts and the forms' slots, and the core's view of them, which points into the three
struct AsmPrinterFlat
{
    std::vector<unsigned char> letters;
    std::vector<AsmPrinterCoreText> texts;
    std::vector<unsigned int> slots;
    AsmPrinterCoreRules rules;
};

void asm_printer_flatten(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                         AsmPrinterFlat *flat);

// the memory a build lays out into, sized from the flattened ruleset by asm_printer_memory_size, its steps by
// `step_capacity`
struct AsmPrinterMemory
{
    std::vector<unsigned int> word_start;
    std::vector<unsigned int> word_length;
    std::vector<unsigned char> word_letters;
    std::vector<unsigned int> part_pieces;
    std::vector<unsigned int> part_lanes;
    std::vector<unsigned int> form_parts;
    std::vector<unsigned int> slot_parameters;
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> values[ASM_PRINTER_TABLES];
};

// the capacities a build of `flat` takes, every count but the steps' held exactly, into `build`
void asm_printer_capacities(const AsmPrinterFlat *flat, unsigned int step_capacity, AsmPrinterCoreBuild *build);

// `memory` sized to `build`'s capacities, and `build` pointed at it
void asm_printer_memory_size(AsmPrinterMemory *memory, AsmPrinterCoreBuild *build);

// the steps the first build is given; a build left full runs again with twice as many
#define ASM_PRINTER_STEP_CAPACITY 1024u

// what a finished build laid out, its memory in host memory, kept in `text_rules`: the lists and the program's steps,
// fields, tables and output
void asm_printer_keep(const AsmPrinterCoreBuild *build, AsmPrinterRuleset *text_rules);

// why a build ended as `end`, as the host's build said it
const char *asm_printer_ended(unsigned int end);

#endif
