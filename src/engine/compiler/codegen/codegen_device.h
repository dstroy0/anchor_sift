// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CODEGEN_DEVICE_H
#define CODEGEN_DEVICE_H

// The code generator on the device (engine_table.md item 11(f)(a)): a program's lane written by the device from its
// step table, with no text written on the host. The device lays out what each step reads from outside itself, decides
// each step's forms a thread a step (codegen_core.h), counted and then written where a scan of the counts puts them,
// decides the lane's own forms in one thread, lays out the forms as the assembly printer's records (asm_printer.h),
// runs the text program on the record machine, a lane a byte, and gathers the bytes that are not 0 into the text. The
// host lays out once what is the ruleset's, the target's and the header's alone (asm_printer_ruleset_build), and reads
// back the counts that size the device's memory and the text. A lane a language clocks is split into states on the
// device as well (codegen_device_instrs), in one thread, since each state goes on from the one before. The device's
// text is the host's (CodeGenerator::decided, written by asm_printer_host) byte for byte: the forms are the core's on
// both, and the assembly printer writes what the ruleset's text would.
//
// The step table itself is laid out on the device as well, from the program's steps: keymath's encoding
// (keymath_core.h) and key_schedule's layout (key_schedule_core.h), each in one thread, since each step reads the steps
// before it, the one keymath_record_encode and key_schedule_record_layout run on the host. The assembly printer is laid
// out there too, from what asm_printer_ruleset_build kept of it, and checked against the host's layout word for word
// before the record machine loads it

#include "asm_printer.h"
#include "code_generator.h"

#include <string>
#include <vector>

// a program as keymath and key_schedule take it (KeymathRecordRequest, KeyScheduleRecordRequest): its steps, the
// fields' widths and offsets, its members and the limbs each reads, its outputs and tables, and whether registers are
// reused
struct LayoutRequest
{
    const EngineRecordStep *steps;
    unsigned int count;
    const unsigned int *field_bits;
    const unsigned int *field_offset;
    unsigned int fields;
    unsigned int members;
    const unsigned int *in_limbs;
    const unsigned int *outputs;
    unsigned int output_count;
    const EngineRecordTable *tables;
    unsigned int table_count;
    int reuse;
};

// the lane of `layout` written by the device in the ruleset `text_rules` was laid out from, `places` the places it
// holds in shared memory (the file's where the language lays it out there, else 0), split into states by `costs` where
// it is given (the language's CodeGenerator::program_schedule_costs, where its program() splits the lane): 1 where it
// was written, its text in `text`; 0, and why in `refused`, where a step is one the lane does not hold, a form breaks
// the lane, the text is more than the assembly printer holds, the device refused a call, or the build has no device
int codegen_device(const EngineRecordLayout *layout, const AsmPrinterRuleset *text_rules, unsigned int places,
                   const ScheduleCosts *costs, std::string *text, std::string *refused);

// the program of `request` laid out by the device and read back into `layout`, as key_schedule_record_layout lays it
// out and key_schedule_record_release releases it: 1 where it was laid out; 0, and why in `refused`, where keymath or
// key_schedule refuses it, the device refused a call, or the build has no device
int layout_device(const LayoutRequest *request, EngineRecordLayout *layout, std::string *refused);

// the lane of the program of `request` written by the device, from the step table the device laid out, none of it read
// back: laid out as layout_device lays it out and written as codegen_device writes it
int codegen_device_steps(const LayoutRequest *request, const AsmPrinterRuleset *text_rules, unsigned int places,
                         const ScheduleCosts *costs, std::string *text, std::string *refused);

// the forms of the lane of `layout` as the device decides them, in the text's order, each construct taking its scratch
// from `scratch` (ruleset_scratch), and read back into `items`: those CodeGenerator::decided gives, where `costs`
// is NULL, else the lane split by `costs` into states and `report` told how, as the scheduled decided gives them. 1
// where they were decided; 0, and why in `refused`, where a step is one the lane does not hold, a form breaks the lane,
// the device refused a call, or the build has no device
int codegen_device_instrs(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                          unsigned int places, const ScheduleCosts *costs, ScheduleReport *report,
                          std::vector<MachineInstr> *items, std::string *refused);

// 1 where two layouts are the same word for word: their sizes, step tables and tables' values
int layout_same(const EngineRecordLayout *left, const EngineRecordLayout *right);

// asm_printer_ruleset_build on the device: the schema checked and the scratch taken on the host, which are the
// reader's, then the build (asm_printer_core.h) in one device thread and the program laid out by the device
// (layout_device). The program's key is not kept, and its output is the program's. 1 where it is built, else 0 and why
// in `refused`, as the host's build refuses, or where the device refused a call or the build has no device
int asm_printer_ruleset_device(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                               AsmPrinterRuleset *text_rules, std::string *refused);

// 1 where two builds of a ruleset are the same word for word: their scratch and lists, the program's steps, fields,
// tables and output, and its layout
int asm_printer_ruleset_same(const AsmPrinterRuleset *left, const AsmPrinterRuleset *right);

#endif
