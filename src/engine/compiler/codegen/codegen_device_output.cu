// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// codegen_device_output.cu: the assembly text written on the device, the step layout, and the entry points
#include "codegen_device_internal.h"

#if (defined(__CUDACC__))

// The lane written on the device, in `device_arena`, which the caller frees, from the step table at `device_steps`, in
// device memory, and the rest of `layout`'s sizes: its forms decided (codegen_device_decide), split by `costs` where it
// is given, laid out as the assembly printer's records, written a lane a byte and gathered. The records and the lanes
// come back to the host after they are laid out, and the text's length after its bytes are gathered
static int codegen_device_written(DeviceArena *device_arena, const EngineRecordLayout *layout,
                                  const DeviceRecordStep *device_steps, const AsmPrinterRuleset *text_rules,
                                  unsigned int places, const ScheduleCosts *costs, std::string *text,
                                  std::string *refused)
{
    DeviceArena &memory = *device_arena;
    MachineInstr *items = NULL;
    unsigned long long item_count = 0ull;
    ScheduleReport report{};
    if (codegen_device_decide(device_arena, layout, device_steps, text_rules->scratch.data(),
                              text_rules->scratch.size(), places, costs, &report, &items, &item_count, refused) == 0)
    {
        return 0;
    }
    // a form given other arguments than it takes breaks the lane, counted here from none
    unsigned int summary[CODEGEN_SUMMARY] = {0u};
    unsigned int *const device_summary = codegen_device_copy(&memory, summary, CODEGEN_SUMMARY);
    // the ruleset's written forms with their lists in device memory, and the records each item takes
    AsmPrinterLists forms = asm_printer_lists(text_rules);
    forms.word_lengths = codegen_device_copy(&memory, text_rules->word_lengths.data(), text_rules->word_lengths.size());
    forms.part_lanes = codegen_device_copy(&memory, text_rules->part_lanes.data(), text_rules->part_lanes.size());
    forms.form_part_first =
        codegen_device_copy(&memory, text_rules->form_part_first.data(), text_rules->form_part_first.size());
    forms.form_parts = codegen_device_copy(&memory, text_rules->form_parts.data(), text_rules->form_parts.size());
    forms.form_slot_first =
        codegen_device_copy(&memory, text_rules->form_slot_first.data(), text_rules->form_slot_first.size());
    forms.slot_parameters =
        codegen_device_copy(&memory, text_rules->slot_parameters.data(), text_rules->slot_parameters.size());
    unsigned long long *const record_counts = codegen_device_take<unsigned long long>(&memory, item_count);
    unsigned long long *const record_first = codegen_device_take<unsigned long long>(&memory, item_count);
    if (memory.ok != 0)
    {
        codegen_device_record_counts<<<codegen_device_blocks(item_count), CODEGEN_THREADS>>>(
            forms, items, item_count, record_counts, device_summary);
        codegen_device_launched(&memory);
    }
    const unsigned long long record_count = codegen_device_scan(&memory, record_counts, record_first, item_count);
    codegen_device_read(&memory, summary, device_summary, CODEGEN_SUMMARY);
    if ((memory.ok != 0) && ((summary[CODEGEN_BROKEN] != 0u) || (record_count >= ASM_PRINTER_LANES_MAX)))
    {
        *refused = (summary[CODEGEN_BROKEN] != 0u) ? "a form breaks the lane"
                                                   : "the text holds more records than the assembly printer holds";
        return 0;
    }
    unsigned int *const records = codegen_device_take<unsigned int>(&memory, record_count * ASM_PRINTER_RECORD_LIMBS);
    unsigned long long *const record_lanes = codegen_device_take<unsigned long long>(&memory, record_count);
    unsigned long long *const lane_first = codegen_device_take<unsigned long long>(&memory, record_count);
    const size_t record_bytes = sizeof(unsigned int) * ASM_PRINTER_RECORD_LIMBS * (size_t)record_count;
    memory.ok = (memory.ok != 0) && (cudaMemset(records, 0, record_bytes) == cudaSuccess);
    if (memory.ok != 0)
    {
        codegen_device_records<<<codegen_device_blocks(item_count), CODEGEN_THREADS>>>(
            forms, items, item_count, record_first, records, record_lanes);
        codegen_device_launched(&memory);
    }
    const unsigned long long lanes = codegen_device_scan(&memory, record_lanes, lane_first, record_count);
    if ((memory.ok != 0) && ((lanes >= ASM_PRINTER_LANES_MAX) || (lanes == 0ull)))
    {
        *refused = "the text holds more lanes than the assembly printer holds";
        return 0;
    }
    unsigned int *const index = codegen_device_take<unsigned int>(&memory, lanes);
    if (memory.ok != 0)
    {
        codegen_device_index<<<codegen_device_blocks(record_count), CODEGEN_THREADS>>>(records, record_count,
                                                                                       lane_first, record_lanes, index);
        codegen_device_launched(&memory);
    }
    if (memory.ok == 0)
    {
        *refused = "the device refused a call";
        return 0;
    }
    // the assembly printer laid out by the device and checked against the host's word for word, then run by the record
    // machine, a lane a byte; its output's offset read before the layout, which the record holds its own of, is given
    // back
    EngineRecordLayout text_layout{};
    if (asm_printer_program_placed(text_rules, &text_layout, refused) == 0)
    {
        return 0;
    }
    const unsigned int output_offset = text_layout.step_table[text_rules->program.output].out_offset;
    CycleRecord *record = NULL;
    EngineError error{};
    const long loaded = cycle_record_load(&text_layout, &record, &error);
    key_schedule_record_release(&text_layout);
    if (loaded == CYCLE_ERROR)
    {
        *refused = "the record machine did not load the assembly printer";
        return 0;
    }
    const unsigned int out_limbs = cycle_record_out_limbs(record);
    unsigned int *const out = codegen_device_take<unsigned int>(&memory, lanes * out_limbs);
    if (memory.ok != 0)
    {
        CycleRecordRunRequest request{};
        request.record = record;
        request.device_in[0] = records;
        request.bodies[0] = record_count;
        request.device_index = index;
        request.count = lanes;
        request.device_out = out;
        request.error = &error;
        memory.ok = cycle_record_run(&request) != CYCLE_ERROR;
    }
    cycle_record_release(record);
    // the bytes that are not 0 gathered in lane order
    unsigned char *const bytes = codegen_device_take<unsigned char>(&memory, lanes);
    unsigned char *const gathered = codegen_device_take<unsigned char>(&memory, lanes);
    int *const gathered_count = codegen_device_take<int>(&memory, 1ull);
    if (memory.ok != 0)
    {
        codegen_device_bytes<<<codegen_device_blocks(lanes), CODEGEN_THREADS>>>(out, lanes, out_limbs, output_offset,
                                                                                bytes);
        codegen_device_launched(&memory);
    }
    size_t select_bytes = 0u;
    memory.ok = (memory.ok != 0) && (cub::DeviceSelect::If(NULL, select_bytes, bytes, gathered, gathered_count,
                                                           (int)lanes, NonzeroByte()) == cudaSuccess);
    void *const select_temporary = codegen_device_take<unsigned char>(&memory, select_bytes);
    memory.ok = (memory.ok != 0) && (cub::DeviceSelect::If(select_temporary, select_bytes, bytes, gathered,
                                                           gathered_count, (int)lanes, NonzeroByte()) == cudaSuccess);
    int length = 0;
    codegen_device_read(&memory, &length, gathered_count, 1ull);
    std::string written((size_t)((length > 0) ? length : 0), '\0');
    codegen_device_read(&memory, &written[0], (const char *)gathered, written.size());
    if (memory.ok == 0)
    {
        *refused = "the device refused a call, or the assembly printer did not run";
        return 0;
    }
    *text = written;
    return 1;
}

// why keymath's encoding, where `keymath` is 1, or key_schedule's layout refused the program, from where it ended
static std::string layout_refused(int keymath, const LayoutEnd *ended)
{
    const std::string at = std::to_string(ended->at);
    if (keymath != 0)
    {
        return (ended->end == KEYMATH_CORE_TABLE)    ? "keymath refused step " + at + "'s table"
               : (ended->end == KEYMATH_CORE_OUTPUT) ? "keymath refused output " + at
                                                     : "keymath refused step " + at;
    }
    return (ended->end == KEY_SCHEDULE_CORE_STEP)   ? "key_schedule refused step " + at
           : (ended->end == KEY_SCHEDULE_CORE_FILE) ? "the program's registers are more limbs than the file holds"
                                                    : "the program's outputs are more bits than a record counts";
}

// The program of `request` laid out on the device, in `memory`, which the caller frees: keymath's encoding in one
// thread, run again with an arena twice the size while it fills the one it has, then key_schedule's layout in one
// thread. The step table is left in device memory at `*device_steps`, the tables' values, one after another as keymath
// lays out the key's, at `*device_values`, `*value_count` words, and the rest of the program's sizes laid out in
// `layout`, whose step table and tables' values are not. The host checks the request as keymath_record_encode and
// key_schedule_record_layout do before their cores run, and reads back only how each core ended, the file's limbs and
// the record's bits
static int layout_steps(DeviceArena *memory, const LayoutRequest *request, EngineRecordLayout *layout,
                        DeviceRecordStep **device_steps, unsigned int **device_values, unsigned long long *value_count,
                        std::string *refused)
{
    int asked = (request->steps != NULL) && (request->count != 0u) && (request->outputs != NULL) &&
                (request->output_count != 0u) && (request->output_count <= request->count) &&
                (request->members != 0u) && (request->members <= ENGINE_RECORD_MEMBERS_MAX) &&
                (request->in_limbs != NULL) && ((request->tables != NULL) || (request->table_count == 0u));
    for (unsigned int member = 0u; (asked != 0) && (member < request->members); member += 1u)
    {
        asked = request->in_limbs[member] != 0u;
    }
    if (asked == 0)
    {
        *refused = "the request is not a program keymath and key_schedule take";
        return 0;
    }
    if (request->count >= CODEGEN_COUNT_MAX)
    {
        *refused = "the program has more steps than a scan counts";
        return 0;
    }
    const unsigned int count = request->count;
    // each table's values in device memory, one after another, and its descriptor pointing at them there; a table
    // indexed by more bits than a table holds, or with no values, is refused whole, as keymath could not lay out the
    // key's values
    std::vector<EngineRecordTable> tables(request->table_count);
    std::vector<unsigned long long> table_first(request->table_count);
    std::vector<unsigned long long> table_words(request->table_count);
    unsigned long long words = 0ull;
    for (unsigned int table = 0u; table < request->table_count; table += 1u)
    {
        tables[table] = request->tables[table];
        if ((tables[table].index_bits > ENGINE_RECORD_TABLE_INDEX_BITS_MAX) || (tables[table].values == NULL))
        {
            *refused =
                "table " + std::to_string(table) + " is indexed by more bits than a table holds, or has no values";
            return 0;
        }
        table_first[table] = words;
        // index_bits is at most 32, and the entry count at most 2^32
        const unsigned long long entries = 1ull << tables[table].index_bits;
        table_words[table] = entries * (unsigned long long)((tables[table].out_bits + 31u) / 32u);
        words += table_words[table];
    }
    unsigned int *const values = codegen_device_take<unsigned int>(memory, words);
    for (unsigned int table = 0u; (memory->ok != 0) && (table < request->table_count); table += 1u)
    {
        tables[table].values = &values[table_first[table]];
        if (table_words[table] != 0ull)
        {
            memory->ok =
                cudaMemcpy(&values[table_first[table]], request->tables[table].values,
                           (size_t)(table_words[table] * sizeof(unsigned int)), cudaMemcpyHostToDevice) == cudaSuccess;
        }
    }
    // the program keymath and key_schedule read, in device memory
    const EngineRecordStep *const steps = codegen_device_copy(memory, request->steps, count);
    const unsigned int *const field_bits =
        (request->field_bits != NULL) ? codegen_device_copy(memory, request->field_bits, request->fields) : NULL;
    const unsigned int *const field_offset =
        (request->field_offset != NULL) ? codegen_device_copy(memory, request->field_offset, request->fields) : NULL;
    const unsigned int *const in_limbs = codegen_device_copy(memory, request->in_limbs, request->members);
    const unsigned int *const outputs = codegen_device_copy(memory, request->outputs, request->output_count);
    const EngineRecordTable *const device_tables =
        (request->tables != NULL) ? codegen_device_copy(memory, tables.data(), request->table_count) : NULL;
    LayoutEnd *const device_ended = codegen_device_take<LayoutEnd>(memory, 1ull);
    LayoutEnd ended{};
    // keymath's encoding: each step's term, never-negative mark and form; an arena that filled stays taken until the
    // memory is freed, and the arenas taken are under twice the last
    EngineRecordTerm *const terms = codegen_device_take<EngineRecordTerm>(memory, count);
    unsigned char *const never_negative = codegen_device_take<unsigned char>(memory, count);
    memory->ok = (memory->ok != 0) && (cudaMemset(never_negative, 0, count) == cudaSuccess);
    KeymathCoreEncode encoding{};
    encoding.steps = steps;
    encoding.count = count;
    encoding.field_bits = field_bits;
    encoding.fields = request->fields;
    encoding.members = request->members;
    encoding.outputs = outputs;
    encoding.output_count = request->output_count;
    encoding.tables = device_tables;
    encoding.table_count = request->table_count;
    encoding.terms = terms;
    encoding.never_negative = never_negative;
    encoding.forms = codegen_device_take<KeymathCoreAffine>(memory, count);
    encoding.bound = codegen_device_take<unsigned int>(memory, KEYMATH_BOUND_LIMBS);
    unsigned long long capacity = (unsigned long long)count * KEYMATH_ARENA_PER_STEP;
    do
    {
        encoding.arena.terms = codegen_device_take<KeymathCoreTerm>(memory, capacity);
        encoding.arena.capacity = capacity;
        if (memory->ok != 0)
        {
            codegen_device_encode<<<1u, 1u>>>(encoding, device_ended);
            codegen_device_launched(memory);
        }
        codegen_device_read(memory, &ended, device_ended, 1ull);
        capacity *= 2ull;
    } while ((memory->ok != 0) && (ended.ok == 0) && (ended.end == KEYMATH_CORE_FULL));
    if ((memory->ok != 0) && (ended.ok == 0))
    {
        *refused = layout_refused(1, &ended);
        return 0;
    }
    // key_schedule's layout: each step laid out for the device and placed, and each output placed in the record
    DeviceRecordStep *const record_steps = codegen_device_take<DeviceRecordStep>(memory, count);
    KeyScheduleCoreLayout core_layout{};
    core_layout.terms = terms;
    core_layout.step_count = count;
    core_layout.outputs = outputs;
    core_layout.output_count = request->output_count;
    core_layout.tables = device_tables;
    core_layout.table_count = request->table_count;
    core_layout.field_offset = field_offset;
    core_layout.fields = request->fields;
    core_layout.in_limbs = in_limbs;
    core_layout.reuse = request->reuse;
    core_layout.steps = record_steps;
    core_layout.last_use = codegen_device_take<unsigned int>(memory, count);
    core_layout.ending_first = codegen_device_take<unsigned int>(memory, (unsigned long long)count + 1ull);
    core_layout.ending = codegen_device_take<unsigned int>(memory, count);
    core_layout.freed = codegen_device_take<KeyScheduleBlock>(memory, (unsigned long long)count + 1ull);
    core_layout.table_offset =
        codegen_device_take<unsigned long long>(memory, (unsigned long long)request->table_count + 1ull);
    ended = LayoutEnd{};
    if (memory->ok != 0)
    {
        codegen_layout<<<1u, 1u>>>(core_layout, device_ended);
        codegen_device_launched(memory);
    }
    codegen_device_read(memory, &ended, device_ended, 1ull);
    if (memory->ok == 0)
    {
        *refused = "the device refused a call";
        return 0;
    }
    if (ended.ok == 0)
    {
        *refused = layout_refused(0, &ended);
        return 0;
    }
    // the sizes as key_schedule_record_layout lays it out; the layout held the file to ENGINE_RECORD_LIMBS_MAX limbs
    // and the record's bits to a 31-bit count
    memset(layout, 0, sizeof(*layout));
    layout->steps = count;
    layout->members = request->members;
    layout->file_limbs = (unsigned int)ended.file_limbs;
    for (unsigned int member = 0u; member < request->members; member += 1u)
    {
        layout->in_limbs[member] = request->in_limbs[member];
    }
    layout->out_bits = (unsigned int)ended.out_bits;
    layout->out_limbs = (unsigned int)((ended.out_bits + 31ull) / 32ull);
    *device_steps = record_steps;
    *device_values = values;
    *value_count = words;
    return 1;
}

int codegen_device(const EngineRecordLayout *layout, const AsmPrinterRuleset *text_rules, unsigned int places,
                   const ScheduleCosts *costs, std::string *text, std::string *refused)
{
    DeviceArena memory = {std::vector<void *>(), 1};
    const DeviceRecordStep *const device_steps = codegen_device_copy(&memory, layout->step_table, layout->steps);
    const int written = codegen_device_written(&memory, layout, device_steps, text_rules, places, costs, text, refused);
    codegen_device_release(&memory);
    return written;
}

int layout_device(const LayoutRequest *request, EngineRecordLayout *layout, std::string *refused)
{
    DeviceArena memory = {std::vector<void *>(), 1};
    DeviceRecordStep *device_steps = NULL;
    unsigned int *device_values = NULL;
    unsigned long long value_count = 0ull;
    EngineRecordLayout device_layout{};
    int ok = layout_steps(&memory, request, &device_layout, &device_steps, &device_values, &value_count, refused);
    // the step table and the tables' values read back, laid out as key_schedule_record_layout lays them out
    if (ok != 0)
    {
        device_layout.step_table = (DeviceRecordStep *)malloc((size_t)device_layout.steps * sizeof(DeviceRecordStep));
        device_layout.table_values =
            (value_count != 0ull) ? (unsigned int *)malloc((size_t)(value_count + 1ull) * sizeof(unsigned int)) : NULL;
        device_layout.table_word_count = value_count;
        ok = (device_layout.step_table != NULL) && ((value_count == 0ull) || (device_layout.table_values != NULL));
        if (ok != 0)
        {
            codegen_device_read(&memory, device_layout.step_table, device_steps, device_layout.steps);
            codegen_device_read(&memory, device_layout.table_values, device_values, value_count);
            ok = memory.ok != 0;
        }
        if (ok == 0)
        {
            *refused = (memory.ok != 0) ? "the host could not hold the layout read back" : "the device refused a call";
            free(device_layout.step_table);
            free(device_layout.table_values);
            device_layout = EngineRecordLayout{};
        }
    }
    codegen_device_release(&memory);
    *layout = device_layout;
    return ok;
}

int codegen_device_steps(const LayoutRequest *request, const AsmPrinterRuleset *text_rules, unsigned int places,
                         const ScheduleCosts *costs, std::string *text, std::string *refused)
{
    DeviceArena memory = {std::vector<void *>(), 1};
    DeviceRecordStep *device_steps = NULL;
    unsigned int *device_values = NULL;
    unsigned long long value_count = 0ull;
    EngineRecordLayout device_layout{};
    const int written =
        (layout_steps(&memory, request, &device_layout, &device_steps, &device_values, &value_count, refused) != 0) &&
        (codegen_device_written(&memory, &device_layout, device_steps, text_rules, places, costs, text, refused) != 0);
    codegen_device_release(&memory);
    return written;
}

int codegen_device_instrs(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                          unsigned int places, const ScheduleCosts *costs, ScheduleReport *report,
                          std::vector<MachineInstr> *items, std::string *refused)
{
    DeviceArena memory = {std::vector<void *>(), 1};
    const DeviceRecordStep *const device_steps = codegen_device_copy(&memory, layout->step_table, layout->steps);
    MachineInstr *decided = NULL;
    unsigned long long item_count = 0ull;
    int ok = codegen_device_decide(&memory, layout, device_steps, scratch.data(), scratch.size(), places, costs, report,
                                   &decided, &item_count, refused);
    if (ok != 0)
    {
        items->assign((size_t)item_count, MachineInstr{});
        codegen_device_read(&memory, items->data(), decided, item_count);
        ok = memory.ok != 0;
        *refused = (ok != 0) ? *refused : std::string("the device refused a call");
    }
    codegen_device_release(&memory);
    return ok;
}
#endif
#if !(defined(__CUDACC__))
int codegen_device(const EngineRecordLayout *layout, const AsmPrinterRuleset *text_rules, unsigned int places,
                   const ScheduleCosts *costs, std::string *text, std::string *refused)
{
    (void)layout;
    (void)text_rules;
    (void)places;
    (void)costs;
    (void)text;
    *refused = "the build has no device";
    return 0;
}

int layout_device(const LayoutRequest *request, EngineRecordLayout *layout, std::string *refused)
{
    (void)request;
    (void)layout;
    *refused = "the build has no device";
    return 0;
}

int codegen_device_steps(const LayoutRequest *request, const AsmPrinterRuleset *text_rules, unsigned int places,
                         const ScheduleCosts *costs, std::string *text, std::string *refused)
{
    (void)request;
    (void)text_rules;
    (void)places;
    (void)costs;
    (void)text;
    *refused = "the build has no device";
    return 0;
}

int codegen_device_instrs(const EngineRecordLayout *layout, const std::vector<unsigned int> &scratch,
                          unsigned int places, const ScheduleCosts *costs, ScheduleReport *report,
                          std::vector<MachineInstr> *items, std::string *refused)
{
    (void)layout;
    (void)scratch;
    (void)places;
    (void)costs;
    (void)report;
    (void)items;
    *refused = "the build has no device";
    return 0;
}
#endif
