// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// asm_printer_layout.cu: the program and rulesets laid out, and the host's lists
#include "asm_printer_internal.h"

// the assembly printer and its tables laid out from `words` into `program`'s key and layout: 1 where they are, else 0
// and why in `refused`, a text of more words, letters or parts than the tables hold refused
static int asm_printer_program_layout(const AsmPrinterWords *words, AsmPrinterProgram *program, std::string *refused)
{
    unsigned long long letters = 0ull;
    for (const std::string &word : words->words)
    {
        letters += word.size();
    }
    if ((letters >= (1ull << ASM_PRINTER_TABLE_BITS_MAX)) ||
        (words->words.size() > (1ull << ASM_PRINTER_TABLE_BITS_MAX)) ||
        (((unsigned long long)words->parts.size() * ASM_PRINTER_PART_ROWS) > (1ull << ASM_PRINTER_TABLE_BITS_MAX)))
    {
        *refused = "the ruleset and the header hold more words or letters than the assembly printer's tables hold";
        return 0;
    }
    std::vector<unsigned int> values[ASM_PRINTER_TABLES];
    EngineRecordTable tables[ASM_PRINTER_TABLES];
    asm_printer_tables(words, values, tables);
    AsmPrinterSteps printer_steps;
    const unsigned int output = asm_printer_program_build(&printer_steps);
    unsigned int field_bits[ASM_PRINTER_FIELDS];
    unsigned int field_offset[ASM_PRINTER_FIELDS];
    field_bits[ASM_PRINTER_FIELD_PART] = ASM_PRINTER_PART_BITS;
    field_offset[ASM_PRINTER_FIELD_PART] = 0u;
    field_bits[ASM_PRINTER_FIELD_FIRST] = ASM_PRINTER_FIRST_BITS;
    field_offset[ASM_PRINTER_FIELD_FIRST] = ASM_PRINTER_FIRST_AT;
    for (unsigned int slot = 0u; slot < ASM_PRINTER_SLOTS; slot += 1u)
    {
        const unsigned int base = ASM_PRINTER_SLOT_AT + (slot * ASM_PRINTER_SLOT_BITS);
        const unsigned int bits[4] = {ASM_PRINTER_WORD_BITS, ASM_PRINTER_WORD_BITS, ASM_PRINTER_NUMBER_BITS, 1u};
        const unsigned int at[4] = {base, base + ASM_PRINTER_WORD_BITS, base + (2u * ASM_PRINTER_WORD_BITS),
                                    base + (2u * ASM_PRINTER_WORD_BITS) + ASM_PRINTER_NUMBER_BITS};
        for (unsigned int which = 0u; which < 4u; which += 1u)
        {
            field_bits[ASM_PRINTER_FIELD_SLOT(slot, which)] = bits[which];
            field_offset[ASM_PRINTER_FIELD_SLOT(slot, which)] = at[which];
        }
    }
    // what keymath and key_schedule take, kept for the device's layout, each table pointing at its values where they
    // are kept
    program->steps = printer_steps.steps;
    program->field_bits.assign(field_bits, field_bits + ASM_PRINTER_FIELDS);
    program->field_offset.assign(field_offset, field_offset + ASM_PRINTER_FIELDS);
    program->values.assign(values, values + ASM_PRINTER_TABLES);
    program->tables.assign(tables, tables + ASM_PRINTER_TABLES);
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLES; table += 1u)
    {
        program->tables[table].values = program->values[table].data();
    }
    program->output = output;
    EngineError error{};
    // the steps are a few hundred
    const KeymathRecordRequest encode_request = {printer_steps.steps.data(),
                                                 (unsigned int)printer_steps.steps.size(),
                                                 field_bits,
                                                 ASM_PRINTER_FIELDS,
                                                 1u,
                                                 &output,
                                                 1u,
                                                 tables,
                                                 ASM_PRINTER_TABLES,
                                                 &program->key,
                                                 &error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        *refused = "keymath refused the assembly printer";
        keymath_record_release(&program->key);
        return 0;
    }
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {ASM_PRINTER_RECORD_LIMBS, 0u, 0u};
    const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, ASM_PRINTER_FIELDS, in_limbs, 1,
                                                     &program->layout, &error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        *refused = "key_schedule refused the assembly printer";
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    return 1;
}

// Every word and part a lane the core decides can be written in, laid out before any lane is: each form's parts from
// its pieces, its slots four to a part and one part for a form of none, each bank's words around its number, each held
// register's word, the minus, the target's hash and the header, whole
int asm_printer_ruleset_build(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                              AsmPrinterRuleset *text_rules, std::string *refused)
{
    *text_rules = AsmPrinterRuleset{};
    if ((rules->schema->form_count != OPCODE_COUNT) || (rules->schema->bank_count != REGCLASS_COUNT) ||
        (rules->schema->fixed_count != PHYSREG_COUNT))
    {
        *refused = "the ruleset was read against another code generator's schema than the lane's";
        return 0;
    }
    if (header.find('\0') != std::string::npos)
    {
        *refused = "the header holds a byte 0";
        return 0;
    }
    const unsigned int scratch_banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    ruleset_scratch(rules, scratch_banks, &text_rules->scratch);
    AsmPrinterWords words;
    asm_printer_word(&words, std::string());
    for (unsigned int form = 0u; form < OPCODE_COUNT; form += 1u)
    {
        if (!rules->constructs[form].lines.empty())
        {
            *refused = "a form is given as a construct, whose scratch the code generator takes";
            return 0;
        }
        const std::vector<std::string> &pieces = rules->forms[form].pieces;
        const std::vector<unsigned int> &slots = rules->forms[form].slots;
        // the parts and the slots' parameters, a few hundred of each
        text_rules->form_part_first.push_back((unsigned int)text_rules->form_parts.size());
        text_rules->form_slot_first.push_back((unsigned int)text_rules->slot_parameters.size());
        text_rules->slot_parameters.insert(text_rules->slot_parameters.end(), slots.begin(), slots.end());
        for (size_t first_slot = 0u; (first_slot == 0u) || (first_slot < slots.size()); first_slot += ASM_PRINTER_SLOTS)
        {
            const size_t left = slots.size() - first_slot;
            const size_t taken = (left < ASM_PRINTER_SLOTS) ? left : ASM_PRINTER_SLOTS;
            const int last = (first_slot + taken) == slots.size();
            std::array<unsigned int, ASM_PRINTER_PIECES> part{};
            for (size_t slot = 0u; slot < taken; slot += 1u)
            {
                part[slot] = asm_printer_word(&words, pieces[first_slot + slot]);
            }
            part[taken] = last ? asm_printer_word(&words, pieces[slots.size()]) : 0u;
            text_rules->form_parts.push_back(asm_printer_part(&words, part));
            if (last)
            {
                break;
            }
        }
    }
    text_rules->form_part_first.push_back((unsigned int)text_rules->form_parts.size());
    text_rules->form_slot_first.push_back((unsigned int)text_rules->slot_parameters.size());
    for (unsigned int bank = 0u; bank < REGCLASS_COUNT; bank += 1u)
    {
        const InstrTemplate *const bank_form = &rules->banks[bank];
        if (bank_form->slots.size() != 1u)
        {
            *refused = "a bank writes its register with other than one number";
            return 0;
        }
        text_rules->bank_before[bank] = asm_printer_word(&words, bank_form->pieces[0]);
        text_rules->bank_after[bank] = asm_printer_word(&words, bank_form->pieces[1]);
    }
    for (unsigned int fixed = 0u; fixed < PHYSREG_COUNT; fixed += 1u)
    {
        text_rules->fixed_word[fixed] = asm_printer_word(&words, rules->fixed[fixed]);
    }
    char block[32];
    snprintf(block, sizeof(block), "%016llx", target->block_hash);
    text_rules->minus_word = asm_printer_word(&words, std::string("-"));
    text_rules->hash_word = asm_printer_word(&words, std::string(block));
    std::array<unsigned int, ASM_PRINTER_PIECES> header_part{};
    header_part[0] = asm_printer_word(&words, header);
    text_rules->header_part = asm_printer_part(&words, header_part);
    // a device's compute capability and NVRTC's version are small counts, never negative
    text_rules->target_numbers[0] = (unsigned int)target->major;
    text_rules->target_numbers[1] = (unsigned int)target->minor;
    text_rules->target_numbers[2] = (unsigned int)target->nvrtc_major;
    text_rules->target_numbers[3] = (unsigned int)target->nvrtc_minor;
    // each word's length and each part's lanes, below 2^16 as the program's layout holds the letters
    for (const std::string &word : words.words)
    {
        text_rules->word_lengths.push_back((unsigned int)word.size());
    }
    for (const std::array<unsigned int, ASM_PRINTER_PIECES> &part : words.parts)
    {
        unsigned int lanes = 0u;
        for (const unsigned int piece : part)
        {
            lanes += text_rules->word_lengths[piece];
        }
        text_rules->part_lanes.push_back(lanes);
    }
    return asm_printer_program_layout(&words, &text_rules->program, refused);
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
                     std::string *refused)
{
    const AsmPrinterLists forms = asm_printer_lists(text_rules);
    std::vector<unsigned long long> record_first(items.size(), 0ull);
    unsigned long long record_count = 0ull;
    for (size_t at = 0u; at < items.size(); at += 1u)
    {
        if (!asm_printer_formed(&items[at]))
        {
            *refused = "a form breaks the lane";
            return 0;
        }
        record_first[at] = record_count;
        record_count += asm_printer_record_count(&forms, &items[at]);
    }
    if (record_count >= ASM_PRINTER_LANES_MAX)
    {
        *refused = "the text holds more records than the assembly printer holds";
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
        *refused = "the text holds more lanes than the assembly printer holds";
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
        *refused = "the host oracle refused the assembly printer's run";
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
