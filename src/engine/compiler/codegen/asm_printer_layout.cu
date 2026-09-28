// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// asm_printer_layout.cu: the program and rulesets laid out, and the host's lists
#include "asm_printer_internal.h"

// the assembly printer's program, as the build kept it, encoded by keymath and laid out by key_schedule into
// `program`'s key and layout: 1 where they are, else 0 and why in `error`
static int asm_printer_program_layout(AsmPrinterProgram *program, std::string *error_message)
{
    EngineError error{};
    // the steps are a few hundred
    const KeymathRecordRequest encode_request = {program->steps.data(),
                                                 (unsigned int)program->steps.size(),
                                                 program->field_bits.data(),
                                                 ASM_PRINTER_FIELDS,
                                                 1u,
                                                 &program->output,
                                                 1u,
                                                 program->tables.data(),
                                                 ASM_PRINTER_TABLES,
                                                 &program->key,
                                                 &error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        *error_message = "keymath errored on the assembly printer";
        keymath_record_release(&program->key);
        return 0;
    }
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {ASM_PRINTER_RECORD_LIMBS, 0u, 0u};
    const KeyScheduleRecordRequest layout_request = {
        &program->key, program->field_offset.data(), ASM_PRINTER_FIELDS, in_limbs, 1, &program->layout, &error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        *error_message = "key_schedule errored on the assembly printer";
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    return 1;
}

// the schema checked and the scratch taken, which are the reader's, then the build: every word and part a lane the core
// decides can be written in, the lists, the program and its tables, laid out by the core (asm_printer_core.h) the
// device runs as well, its steps given twice the memory each time they run past it; then the program encoded and laid
// out
int asm_printer_ruleset_build(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                              AsmPrinterRuleset *text_rules, std::string *error)
{
    *text_rules = AsmPrinterRuleset{};
    if ((rules->schema->form_count != OPCODE_COUNT) || (rules->schema->bank_count != REGCLASS_COUNT) ||
        (rules->schema->fixed_count != PHYSREG_COUNT))
    {
        *error = "the ruleset was read against another code generator's schema than the lane's";
        return 0;
    }
    if (header.find('\0') != std::string::npos)
    {
        *error = "the header holds a byte 0";
        return 0;
    }
    const unsigned int scratch_banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    ruleset_scratch(rules, scratch_banks, &text_rules->scratch);
    AsmPrinterFlat flat;
    asm_printer_flatten(rules, target, header, &flat);
    AsmPrinterMemory memory;
    AsmPrinterCoreBuild build{};
    build.rules = flat.rules;
    unsigned int step_capacity = ASM_PRINTER_STEP_CAPACITY;
    for (;;)
    {
        asm_printer_capacities(&flat, step_capacity, &build);
        asm_printer_memory_size(&memory, &build);
        if (asm_printer_core_ruleset_build(&build) != 0)
        {
            break;
        }
        if ((build.end != ASM_PRINTER_CORE_FULL) || (step_capacity >= (1u << 30u)))
        {
            *error = asm_printer_ended(build.end);
            return 0;
        }
        step_capacity *= 2u;
    }
    asm_printer_keep(&build, text_rules);
    return asm_printer_program_layout(&text_rules->program, error);
}

void asm_printer_ruleset_release(AsmPrinterRuleset *text_rules)
{
    key_schedule_record_release(&text_rules->program.layout);
    keymath_record_release(&text_rules->program.key);
}

AsmPrinterLists asm_printer_lists(const AsmPrinterRuleset *text_rules)
{
    AsmPrinterLists forms{};
    forms.word_lengths = text_rules->word_lengths.data();
    forms.part_lanes = text_rules->part_lanes.data();
    forms.form_part_first = text_rules->form_part_first.data();
    forms.form_parts = text_rules->form_parts.data();
    forms.form_slot_first = text_rules->form_slot_first.data();
    forms.slot_parameters = text_rules->slot_parameters.data();
    for (unsigned int bank = 0u; bank < REGCLASS_COUNT; bank += 1u)
    {
        forms.bank_before[bank] = text_rules->bank_before[bank];
        forms.bank_after[bank] = text_rules->bank_after[bank];
    }
    for (unsigned int fixed = 0u; fixed < PHYSREG_COUNT; fixed += 1u)
    {
        forms.fixed_word[fixed] = text_rules->fixed_word[fixed];
    }
    forms.minus_word = text_rules->minus_word;
    forms.hash_word = text_rules->hash_word;
    forms.header_part = text_rules->header_part;
    for (unsigned int number = 0u; number < 4u; number += 1u)
    {
        forms.target_numbers[number] = text_rules->target_numbers[number];
    }
    return forms;
}

// the host oracle, in the device's order: each item's records counted and laid out, each record's first lane and the
// index laid out from the running sum of the records' lanes, the program run, and the bytes that are not 0 taken in
// lane order
int asm_printer_host(const AsmPrinterRuleset *text_rules, const std::vector<MachineInstr> &items, std::string *text,
                     std::string *error_message)
{
    const AsmPrinterLists forms = asm_printer_lists(text_rules);
    std::vector<unsigned long long> record_first(items.size(), 0ull);
    unsigned long long record_count = 0ull;
    for (size_t at = 0u; at < items.size(); at += 1u)
    {
        if (!asm_printer_formed(&items[at]))
        {
            *error_message = "a form breaks the lane";
            return 0;
        }
        record_first[at] = record_count;
        record_count += asm_printer_record_count(&forms, &items[at]);
    }
    if (record_count >= ASM_PRINTER_LANES_MAX)
    {
        *error_message = "the text holds more records than the assembly printer holds";
        return 0;
    }
    std::vector<unsigned int> records((size_t)(record_count * ASM_PRINTER_RECORD_LIMBS), 0u);
    std::vector<unsigned long long> record_lanes((size_t)record_count, 0ull);
    for (size_t at = 0u; at < items.size(); at += 1u)
    {
        asm_printer_records(&forms, &items[at], record_first[at], records.data(), record_lanes.data());
    }
    unsigned long long lanes = 0ull;
    for (unsigned long long record = 0ull; record < record_count; record += 1ull)
    {
        lanes += record_lanes[record];
    }
    if ((lanes >= ASM_PRINTER_LANES_MAX) || (lanes == 0ull))
    {
        *error_message = "the text holds more lanes than the assembly printer holds";
        return 0;
    }
    std::vector<unsigned int> index;
    index.reserve((size_t)lanes);
    unsigned long long first = 0ull;
    for (unsigned long long record = 0ull; record < record_count; record += 1ull)
    {
        asm_printer_first(records.data(), record, first);
        // a record's number is below 2^31
        index.insert(index.end(), (size_t)record_lanes[record], (unsigned int)record);
        first += record_lanes[record];
    }
    const unsigned int out_limbs = text_rules->program.layout.out_limbs;
    std::vector<unsigned int> out((size_t)(lanes * out_limbs), 0u);
    EngineError error{};
    CycleRecordHostRequest request{};
    request.layout = &text_rules->program.layout;
    request.in[0] = records.data();
    request.bodies[0] = record_count;
    request.index = index.data();
    request.count = lanes;
    request.out = out.data();
    request.error = &error;
    if (cycle_record_run_host(&request) == CYCLE_ERROR)
    {
        *error_message = "the host oracle errored on the assembly printer's run";
        return 0;
    }
    // the one output, the byte, lies at its step's offset in each lane's record
    const unsigned int offset = text_rules->program.layout.step_table[text_rules->program.key.output[0]].out_offset;
    std::string written;
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        const unsigned int byte = asm_printer_byte(&out[(size_t)(lane * out_limbs)], out_limbs, offset);
        if (byte != 0u)
        {
            written += (char)byte;
        }
    }
    *text = written;
    return 1;
}
