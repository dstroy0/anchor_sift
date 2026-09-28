// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_DEVICE_H
#define EMIT_DEVICE_H

// The emitter on the device (engine_table.md item 11(f)(a)): a program's lane written by the device from its step
// table, with no text written on the host. The device lays what each step reads from outside itself, decides each
// step's forms a thread a step (emit_core.h), counted and then written where a scan of the counts puts them, decides the
// lane's own forms in one thread, lays the forms as the text program's records (emit_text.h), runs the text
// program on the record machine, a lane a byte, and gathers the bytes that are not 0 into the text. The host lays once
// what is the ruleset's, the target's and the header's alone (emit_text_ruleset_lay), and reads back the counts that
// size the device's memory and the text. A lane a language clocks is cut into states on the device as well
// (emit_device_items), in one thread, since each state goes on from the one before. The device's text is the host's
// (EmitLane::decided, written by emit_text_host) byte for byte: the forms are the core's on both, and the text program
// writes what the ruleset's text would.
//
// The step table itself is laid on the device as well, from the program's steps: keymath's imprint
// (keymath_core.h) and key_schedule's lay (key_schedule_core.h), each in one thread, since each step reads the steps
// before it, the one keymath_record_imprint and key_schedule_record_lay run on the host. The text program is laid
// there too, from what emit_text_ruleset_lay kept of it, and held to the host's layout word for word before the record
// machine loads it

#include "emit_lane.h"
#include "emit_text.h"

#include <string>
#include <vector>

// a program as keymath and key_schedule take it (KeymathRecordRequest, KeyScheduleRecordRequest): its steps, the fields'
// widths and offsets, its members and the limbs each reads, its outputs and tables, and whether registers are reused
struct EmitLayRequest
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

// the lane of `layout` written by the device in the ruleset `text_rules` was laid from, `places` the places it holds in
// shared memory (the file's where the language lays it there, else 0), cut into states by `cut` where it is given (the
// language's EmitLane::program_cut, where its program() cuts the lane): 1 where it was written, its text in `text`; 0,
// and why in `refused`, where a step is one the lane does not hold, a form breaks the lane, the text is more than the
// text program holds, the device refused a call, or the build has no device
int emit_device(const EngineRecordLayout *layout, const EmitTextRuleset *text_rules, unsigned int places,
                const EmitLaneCut *cut, std::string *text, std::string *refused);

// the program of `request` laid by the device and read back into `layout`, as key_schedule_record_lay lays it and
// key_schedule_record_release releases it: 1 where it was laid; 0, and why in `refused`, where keymath or key_schedule
// refuses it, the device refused a call, or the build has no device
int emit_lay_device(const EmitLayRequest *request, EngineRecordLayout *layout, std::string *refused);

// the lane of the program of `request` written by the device, from the step table the device laid, none of it read
// back: laid as emit_lay_device lays it and written as emit_device writes it
int emit_device_steps(const EmitLayRequest *request, const EmitTextRuleset *text_rules, unsigned int places,
                      const EmitLaneCut *cut, std::string *text, std::string *refused);

// the forms of the lane of `layout` as the device decides them, in the text's order, each construct taking its scratch
// from `scratch` (emit_ruleset_scratch), and read back into `items`: those EmitLane::decided gives, where `cut`
// is NULL, else the lane cut by `cut` into states and `report` told how, as the shaped decided gives them. 1 where they
// were decided; 0, and why in `refused`, where a step is one the lane does not hold, a form breaks the lane, the device
// refused a call, or the build has no device
int emit_device_items(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                      unsigned int places, const EmitLaneCut *cut, EmitLaneShaped *report,
                      std::vector<EmitCoreItem> *items, std::string *refused);

// 1 where two layouts are the same word for word: their shapes, step tables and tables' values
int emit_lay_same(const EngineRecordLayout *left, const EngineRecordLayout *right);

#endif
