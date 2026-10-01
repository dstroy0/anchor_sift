// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// codegen_lowering.cu: device memory, and the lowering of a program's steps to machine instructions on the
// device
#include "codegen_device_internal.h"

#if (defined(__CUDACC__))

// key_schedule's layout of the encoded program, in one thread (key_schedule_core_record_layout)
__global__ void codegen_layout(KeyScheduleCoreLayout layout, LayoutEnd *ended)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    ended->ok = key_schedule_core_record_layout(&layout);
    ended->end = layout.end;
    ended->at = layout.at;
    ended->file_limbs = layout.file_limbs;
    ended->out_bits = layout.out_bits;
}

void codegen_device_release(DeviceArena *memory)
{
    for (void *const allocation : memory->allocations)
    {
        cudaFree(allocation);
    }
    memory->allocations.clear();
}

// the blocks a kernel over `count` threads takes; 0 where the count is past a grid, which the callers hold below
unsigned int codegen_device_blocks(unsigned long long count)
{
    return (unsigned int)((count + CODEGEN_THREADS - 1u) / CODEGEN_THREADS);
}

// a kernel's launch taken; the memory unusable where the device errored on it
void codegen_device_launched(DeviceArena *memory)
{
    memory->ok = (memory->ok != 0) && (cudaGetLastError() == cudaSuccess);
}

// the assembly printer laid out by the device from what a build kept of it, into `text_layout`, which the caller gives
// back by key_schedule_record_release: 1 where it is laid out, else 0 and why
int asm_printer_program_device(const AsmPrinterProgram *program, EngineRecordLayout *text_layout, std::string *error)
{
    const AsmPrinterProgram &kept = *program;
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {ASM_PRINTER_RECORD_LIMBS, 0u, 0u};
    LayoutRequest request{};
    request.steps = kept.steps.data();
    // the assembly printer's steps are a few hundred, and its fields and tables a handful
    request.count = (unsigned int)kept.steps.size();
    request.field_bits = kept.field_bits.data();
    request.field_offset = kept.field_offset.data();
    request.fields = (unsigned int)kept.field_bits.size();
    request.members = 1u;
    request.in_limbs = in_limbs;
    request.outputs = &kept.output;
    request.output_count = 1u;
    request.tables = kept.tables.data();
    request.table_count = (unsigned int)kept.tables.size();
    request.reuse = 1;
    std::string why;
    if (layout_device(&request, text_layout, &why) == 0)
    {
        *error = "the device did not lay out the assembly printer (" + why + ")";
        return 0;
    }
    return 1;
}

// the assembly printer laid out by the device from what asm_printer_ruleset_build kept of it, into `text_layout`, which
// the caller gives back by key_schedule_record_release: 1 where it is laid out and is the host's word for word, else 0
// and why
int asm_printer_program_placed(const AsmPrinterRuleset *text_rules, EngineRecordLayout *text_layout,
                               std::string *error)
{
    if (asm_printer_program_device(&text_rules->program, text_layout, error) == 0)
    {
        return 0;
    }
    if (layout_same(text_layout, &text_rules->program.layout) == 0)
    {
        key_schedule_record_release(text_layout);
        *error = "the device laid out the assembly printer apart from the host's";
        return 0;
    }
    return 1;
}

// `count` items moved from `from` to `to`, both in device memory, apart from each other
static void codegen_device_move(DeviceArena *memory, MachineInstr *to, const MachineInstr *from,
                                unsigned long long count)
{
    if ((memory->ok != 0) && (count != 0ull))
    {
        memory->ok =
            cudaMemcpy(to, from, (size_t)(count * sizeof(MachineInstr)), cudaMemcpyDeviceToDevice) == cudaSuccess;
    }
}

// The lane's forms decided on the device, in `device_arena`, which the caller frees, from the step table at
// `device_steps`, in device memory, and the rest of `layout`'s sizes, whose own step table is not read, each form's
// construct taking its scratch from `scratch`, `scratch_count` words (ruleset_scratch): in the text's order at
// `*text_items`, `*item_count` of them. Where `costs` is given, the body is split into states by it and `report` told
// how, as CodeGenerator::decided splits it. The forms are decided in three phases, each counted and then written, the
// lane going on from one to the next in device memory: the steps' forms and the lane's own through its close; the
// schedule; the body's opening and the end. Every count that sizes the device's memory comes back to the host once: the
// step forms' total and the summary after the steps are counted, each phase's parts after they are counted, and the
// schedule's forms
int codegen_device_decide(DeviceArena *device_arena, const EngineRecordLayout *layout,
                          const DeviceRecordStep *device_steps, const unsigned int *scratch,
                          unsigned long long scratch_count, unsigned int places, const ScheduleCosts *costs,
                          ScheduleReport *report, MachineInstr **text_items, unsigned long long *item_count,
                          std::string *error)
{
    DeviceArena &memory = *device_arena;
    const unsigned int steps = layout->steps;
    if (steps >= CODEGEN_COUNT_MAX)
    {
        *error = "the program has more steps than a scan counts";
        return 0;
    }
    if ((costs != NULL) && (costs->cost.size() != OPCODE_COUNT))
    {
        *error = "the schedule does not give each form a cost";
        return 0;
    }
    // the program as every step reads it, in device memory
    IrProgram program{};
    program.step_count = steps;
    program.members = layout->members;
    program.file_limbs = layout->file_limbs;
    program.out_limbs = layout->out_limbs;
    unsigned int atoms = 0u;
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        program.in_limbs[member] = layout->in_limbs[member];
        program.atom_first[member] = atoms;
        atoms += (member < layout->members) ? layout->in_limbs[member] : 0u;
    }
    program.steps = device_steps;
    program.scratch = codegen_device_copy(&memory, scratch, scratch_count);
    unsigned int *const put_first = codegen_device_take<unsigned int>(&memory, layout->out_limbs);
    unsigned int *const put_last = codegen_device_take<unsigned int>(&memory, layout->out_limbs);
    unsigned int *const atom_reader = codegen_device_take<unsigned int>(&memory, atoms);
    unsigned int *const loops = codegen_device_take<unsigned int>(&memory, steps);
    unsigned int *const loop_first = codegen_device_take<unsigned int>(&memory, steps);
    unsigned long long *const counts = codegen_device_take<unsigned long long>(&memory, steps);
    unsigned long long *const item_first = codegen_device_take<unsigned long long>(&memory, steps);
    unsigned int *const errors = codegen_device_take<unsigned int>(&memory, steps);
    unsigned int summary[CODEGEN_SUMMARY] = {0u};
    // the lane's opening takes %t0 and %w0 before any step does
    summary[CODEGEN_TEMPS_MAX] = 1u;
    summary[CODEGEN_WIDES_MAX] = 1u;
    unsigned int *const device_summary = codegen_device_copy(&memory, summary, CODEGEN_SUMMARY);
    CodegenParts parts{};
    CodegenParts *const device_parts = codegen_device_copy(&memory, &parts, 1ull);
    MachineFunction *const lane_out = codegen_device_take<MachineFunction>(&memory, 1ull);
    const size_t out_bytes = sizeof(unsigned int) * layout->out_limbs;
    memory.ok = (memory.ok != 0) && (cudaMemset(put_first, 0xFF, out_bytes) == cudaSuccess) &&
                (cudaMemset(put_last, 0, out_bytes) == cudaSuccess);
    if ((memory.ok != 0) && (atoms != 0u))
    {
        codegen_device_fill<<<codegen_device_blocks(atoms), CODEGEN_THREADS>>>(atom_reader, atoms, steps);
        codegen_device_launched(&memory);
    }
    program.put_first = put_first;
    program.put_last = put_last;
    program.atom_reader = atom_reader;
    if ((memory.ok != 0) && (steps != 0u))
    {
        codegen_device_facts<<<codegen_device_blocks(steps), CODEGEN_THREADS>>>(program, put_first, put_last,
                                                                                atom_reader, loops);
        codegen_device_launched(&memory);
    }
    if ((memory.ok != 0) && (layout->out_limbs != 0u))
    {
        codegen_device_unlaid<<<codegen_device_blocks(layout->out_limbs), CODEGEN_THREADS>>>(put_first, put_last,
                                                                                             layout->out_limbs);
        codegen_device_launched(&memory);
    }
    // the loops every step writes, a loop number each, as the host's lane numbers them in a 32-bit count
    const unsigned int loop_count = (unsigned int)codegen_device_scan(&memory, loops, loop_first, steps);
    // each step's forms counted, and where each step's begin
    if ((memory.ok != 0) && (steps != 0u))
    {
        codegen_device_count<<<codegen_device_blocks(steps), CODEGEN_THREADS>>>(program, loop_first, counts, errors,
                                                                                device_summary);
        codegen_device_launched(&memory);
    }
    const unsigned long long stepped = codegen_device_scan(&memory, counts, item_first, steps);
    codegen_device_read(&memory, summary, device_summary, CODEGEN_SUMMARY);
    if ((memory.ok != 0) && (summary[CODEGEN_UNHELD] != 0u))
    {
        *error = "a step is one the lane does not hold";
        return 0;
    }
    if (memory.ok != 0)
    {
        codegen_device_left<<<1u, 1u>>>(device_summary, loop_count, lane_out);
        codegen_device_launched(&memory);
    }
    // phase one: the lane's own forms through its close counted, then laid out with the header's item and the steps'
    // forms in the order they are decided, the note, the header, the lane's first form, the declarations, then the body
    // as it runs, its opening, the steps and its close
    if (memory.ok != 0)
    {
        codegen_prologue_epilogue<<<1u, 1u>>>(program, errors, device_summary, lane_out, atoms, places, 0u, 5u, 0, 0u,
                                              device_parts, NULL);
        codegen_device_launched(&memory);
    }
    codegen_device_read(&memory, &parts, device_parts, 1ull);
    parts.count[CODEGEN_HEADER] = 1ull;
    parts.count[CODEGEN_STEPPED] = stepped;
    const unsigned int first_parts[7] = {CODEGEN_NOTE,   CODEGEN_HEADER,  CODEGEN_LANE_OPEN, CODEGEN_DECLARATIONS,
                                         CODEGEN_OPENED, CODEGEN_STEPPED, CODEGEN_CLOSED};
    unsigned long long first_count = 0ull;
    for (const unsigned int part : first_parts)
    {
        parts.at[part] = first_count;
        first_count += parts.count[part];
    }
    if ((memory.ok != 0) && (first_count >= CODEGEN_COUNT_MAX))
    {
        *error = "the lane holds more forms than a scan counts";
        return 0;
    }
    memory.ok =
        (memory.ok != 0) && (cudaMemcpy(device_parts, &parts, sizeof(parts), cudaMemcpyHostToDevice) == cudaSuccess);
    MachineInstr *const decided = codegen_device_take<MachineInstr>(&memory, first_count);
    if ((memory.ok != 0) && (steps != 0u))
    {
        codegen_device_write<<<codegen_device_blocks(steps), CODEGEN_THREADS>>>(program, loop_first, counts, item_first,
                                                                                &decided[parts.at[CODEGEN_STEPPED]]);
        codegen_device_launched(&memory);
    }
    if (memory.ok != 0)
    {
        codegen_prologue_epilogue<<<1u, 1u>>>(program, errors, device_summary, lane_out, atoms, places, 0u, 5u, 0, 0u,
                                              device_parts, decided);
        codegen_device_launched(&memory);
    }
    // the body as it runs, the opening, the steps and the close, one after another
    const MachineInstr *const body = &decided[parts.at[CODEGEN_OPENED]];
    const unsigned long long body_count =
        parts.count[CODEGEN_OPENED] + parts.count[CODEGEN_STEPPED] + parts.count[CODEGEN_CLOSED];
    // phase two: the body split into states, counted, then written; an error's label for the opening and one for each
    // step at most, and each loop the steps wrote
    MachineInstr *scheduled_instrs = NULL;
    unsigned long long scheduled_count = 0ull;
    unsigned int states = 0u;
    if (costs != NULL)
    {
        Schedule device_schedule{};
        device_schedule.cost = codegen_device_copy(&memory, costs->cost.data(), costs->cost.size());
        device_schedule.budget = costs->budget;
        device_schedule.dispatch_error =
            codegen_device_take<MachineOperand>(&memory, (unsigned long long)steps + 1ull);
        device_schedule.dispatch_state = codegen_device_take<unsigned int>(&memory, (unsigned long long)steps + 1ull);
        device_schedule.dispatch_max = steps + 1u;
        device_schedule.loop_state = codegen_device_take<unsigned int>(&memory, (unsigned long long)loop_count + 1ull);
        device_schedule.loop_count = loop_count;
        ScheduleEnd *const device_schedule_end = codegen_device_take<ScheduleEnd>(&memory, 1ull);
        ScheduleEnd schedule_end{};
        if (memory.ok != 0)
        {
            codegen_schedule<<<1u, 1u>>>(program, device_summary, lane_out, device_schedule, costs->writes,
                                         costs->ports, body, body_count, 0ull, NULL, device_schedule_end);
            codegen_device_launched(&memory);
        }
        codegen_device_read(&memory, &schedule_end, device_schedule_end, 1ull);
        scheduled_count = schedule_end.count;
        if ((memory.ok != 0) && (scheduled_count >= CODEGEN_COUNT_MAX))
        {
            *error = "the split lane holds more forms than a scan counts";
            return 0;
        }
        scheduled_instrs = codegen_device_take<MachineInstr>(&memory, scheduled_count);
        if (memory.ok != 0)
        {
            codegen_schedule<<<1u, 1u>>>(program, device_summary, lane_out, device_schedule, costs->writes,
                                         costs->ports, body, body_count, scheduled_count, scheduled_instrs,
                                         device_schedule_end);
            codegen_device_launched(&memory);
        }
        codegen_device_read(&memory, &schedule_end, device_schedule_end, 1ull);
        states = schedule_end.states;
        report->states = schedule_end.states;
        report->maximum = schedule_end.maximum;
        report->over = schedule_end.over;
    }
    // phase three: the body's opening and the lane's end, counted, then written
    const int is_scheduled = (costs != NULL) ? 1 : 0;
    if (memory.ok != 0)
    {
        codegen_prologue_epilogue<<<1u, 1u>>>(program, errors, device_summary, lane_out, atoms, places, 5u, 7u,
                                              is_scheduled, states, device_parts, NULL);
        codegen_device_launched(&memory);
    }
    codegen_device_read(&memory, &parts, device_parts, 1ull);
    parts.at[CODEGEN_BODY_OPEN] = 0ull;
    parts.at[CODEGEN_ENDING] = parts.count[CODEGEN_BODY_OPEN];
    const unsigned long long last_count = parts.count[CODEGEN_BODY_OPEN] + parts.count[CODEGEN_ENDING];
    memory.ok =
        (memory.ok != 0) && (cudaMemcpy(device_parts, &parts, sizeof(parts), cudaMemcpyHostToDevice) == cudaSuccess);
    MachineInstr *const closing = codegen_device_take<MachineInstr>(&memory, last_count);
    if (memory.ok != 0)
    {
        codegen_prologue_epilogue<<<1u, 1u>>>(program, errors, device_summary, lane_out, atoms, places, 5u, 7u,
                                              is_scheduled, states, device_parts, closing);
        codegen_device_launched(&memory);
    }
    // the text's order: the note, the header, the lane's first form and the declarations, the body's opening, the body,
    // split or as it runs, and the end
    const unsigned long long head = parts.count[CODEGEN_NOTE] + parts.count[CODEGEN_HEADER] +
                                    parts.count[CODEGEN_LANE_OPEN] + parts.count[CODEGEN_DECLARATIONS];
    const unsigned long long body_written = (costs != NULL) ? scheduled_count : body_count;
    const unsigned long long total = head + last_count + body_written;
    if ((memory.ok != 0) && (total >= CODEGEN_COUNT_MAX))
    {
        *error = "the lane holds more forms than a scan counts";
        return 0;
    }
    MachineInstr *const text = codegen_device_take<MachineInstr>(&memory, total);
    codegen_device_move(&memory, text, decided, head);
    codegen_device_move(&memory, &text[head], closing, parts.count[CODEGEN_BODY_OPEN]);
    codegen_device_move(&memory, &text[head + parts.count[CODEGEN_BODY_OPEN]],
                        (costs != NULL) ? scheduled_instrs : body, body_written);
    codegen_device_move(&memory, &text[head + parts.count[CODEGEN_BODY_OPEN] + body_written],
                        &closing[parts.at[CODEGEN_ENDING]], parts.count[CODEGEN_ENDING]);
    codegen_device_read(&memory, summary, device_summary, CODEGEN_SUMMARY);
    if (memory.ok == 0)
    {
        *error = "the device errored on a call";
        return 0;
    }
    if (summary[CODEGEN_BROKEN] != 0u)
    {
        *error = "a form breaks the lane";
        return 0;
    }
    *text_items = text;
    *item_count = total;
    return 1;
}
#endif
