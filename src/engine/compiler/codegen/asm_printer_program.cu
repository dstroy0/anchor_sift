// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// asm_printer_program.cu: the ruleset flattened for the core's build, its memory, and what the build laid out kept
#include "asm_printer_internal.h"

// `text` taken on as a text of the flattened ruleset, its number returned
static unsigned int asm_printer_flat_text(AsmPrinterFlat *flat, const std::string &text)
{
    // the ruleset's texts and letters are far fewer than 2^32; the build refuses more than its tables hold
    const AsmPrinterCoreText taken = {(unsigned int)flat->letters.size(), (unsigned int)text.size()};
    flat->letters.insert(flat->letters.end(), text.begin(), text.end());
    flat->texts.push_back(taken);
    return (unsigned int)(flat->texts.size() - 1u);
}

// the ruleset, the target and the header flattened for the core: each form's pieces and slots, whether it is given as
// a construct, each bank's pieces and count of slots, each fixed register's text and the header's, in the host's order
void asm_printer_flatten(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                         AsmPrinterFlat *flat)
{
    *flat = AsmPrinterFlat{};
    AsmPrinterCoreRules *const flattened = &flat->rules;
    for (unsigned int form = 0u; form < OPCODE_COUNT; form += 1u)
    {
        // the forms' pieces and slots are a few hundred
        flattened->form_piece_first[form] = (unsigned int)flat->texts.size();
        flattened->form_slot_first[form] = (unsigned int)flat->slots.size();
        flattened->form_construct[form] = rules->constructs[form].lines.empty() ? 0u : 1u;
        for (const std::string &piece : rules->forms[form].pieces)
        {
            asm_printer_flat_text(flat, piece);
        }
        flat->slots.insert(flat->slots.end(), rules->forms[form].slots.begin(), rules->forms[form].slots.end());
    }
    flattened->form_piece_first[OPCODE_COUNT] = (unsigned int)flat->texts.size();
    flattened->form_slot_first[OPCODE_COUNT] = (unsigned int)flat->slots.size();
    for (unsigned int bank = 0u; bank < REGCLASS_COUNT; bank += 1u)
    {
        const InstrTemplate *const bank_form = &rules->banks[bank];
        flattened->bank_piece_first[bank] = (unsigned int)flat->texts.size();
        // a bank's slots are one where it is read, and a count far below 2^32 where it is not
        flattened->bank_slots[bank] = (unsigned int)bank_form->slots.size();
        for (const std::string &piece : bank_form->pieces)
        {
            asm_printer_flat_text(flat, piece);
        }
    }
    for (unsigned int fixed = 0u; fixed < PHYSREG_COUNT; fixed += 1u)
    {
        flattened->fixed_text[fixed] = asm_printer_flat_text(flat, rules->fixed[fixed]);
    }
    flattened->header_text = asm_printer_flat_text(flat, header);
    flattened->block_hash = target->block_hash;
    // a device's compute capability and NVRTC's version are small counts, never negative
    flattened->target_numbers[0] = (unsigned int)target->major;
    flattened->target_numbers[1] = (unsigned int)target->minor;
    flattened->target_numbers[2] = (unsigned int)target->nvrtc_major;
    flattened->target_numbers[3] = (unsigned int)target->nvrtc_minor;
    // a vector's data is NULL where it is empty, and the core reads the letters at 0 for the empty word
    flat->letters.push_back(0u);
    flattened->letters = flat->letters.data();
    flattened->texts = flat->texts.data();
    flat->slots.push_back(0u);
    flattened->slots = flat->slots.data();
}

void asm_printer_capacities(const AsmPrinterFlat *flat, unsigned int step_capacity, AsmPrinterCoreBuild *build)
{
    // every word is a text of the ruleset, the empty word, the minus or the hash; every letter is a text's, the minus's
    // or the hash's; each form takes a part for each four slots and one for none, and the header one more
    unsigned int form_parts = 0u;
    for (unsigned int form = 0u; form < OPCODE_COUNT; form += 1u)
    {
        const unsigned int slots = flat->rules.form_slot_first[form + 1u] - flat->rules.form_slot_first[form];
        form_parts += (slots == 0u) ? 1u : ((slots + ASM_PRINTER_SLOTS - 1u) / ASM_PRINTER_SLOTS);
    }
    // the texts, letters and slots are a few thousand
    build->word_capacity = (unsigned int)flat->texts.size() + 3u;
    build->letter_capacity = (unsigned int)flat->letters.size() + 1u + ASM_PRINTER_HASH_DIGITS;
    build->form_part_capacity = form_parts;
    build->part_capacity = form_parts + 1u;
    build->slot_capacity = flat->rules.form_slot_first[OPCODE_COUNT];
    build->step_capacity = step_capacity;
    // past ASM_PRINTER_TABLE_BITS_MAX the build ends before its tables, so no table is wider
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLE_POWER; table += 1u)
    {
        build->table_capacity[table] = 1u << ASM_PRINTER_TABLE_BITS_MAX;
    }
    build->table_capacity[ASM_PRINTER_TABLE_POWER] = ASM_PRINTER_POWER_ROWS;
    build->table_capacity[ASM_PRINTER_TABLE_BYTE] = ASM_PRINTER_BYTE_ROWS;
}

void asm_printer_memory_size(AsmPrinterMemory *memory, AsmPrinterCoreBuild *build)
{
    // an empty vector's data is NULL, and every list is given at least one word
    memory->word_start.assign((size_t)build->word_capacity + 1u, 0u);
    memory->word_length.assign((size_t)build->word_capacity + 1u, 0u);
    memory->word_letters.assign((size_t)build->letter_capacity + 1u, 0u);
    memory->part_pieces.assign(((size_t)build->part_capacity * ASM_PRINTER_PIECES) + 1u, 0u);
    memory->part_lanes.assign((size_t)build->part_capacity + 1u, 0u);
    memory->form_parts.assign((size_t)build->form_part_capacity + 1u, 0u);
    memory->slot_parameters.assign((size_t)build->slot_capacity + 1u, 0u);
    memory->steps.assign((size_t)build->step_capacity, EngineRecordStep{});
    build->word_start = memory->word_start.data();
    build->word_length = memory->word_length.data();
    build->word_letters = memory->word_letters.data();
    build->part_pieces = memory->part_pieces.data();
    build->part_lanes = memory->part_lanes.data();
    build->form_parts = memory->form_parts.data();
    build->slot_parameters = memory->slot_parameters.data();
    build->steps = memory->steps.data();
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLES; table += 1u)
    {
        memory->values[table].assign(build->table_capacity[table], 0u);
        build->values[table] = memory->values[table].data();
    }
}

void asm_printer_keep(const AsmPrinterCoreBuild *build, AsmPrinterRuleset *text_rules)
{
    text_rules->word_lengths.assign(build->word_length, build->word_length + build->words);
    text_rules->part_lanes.assign(build->part_lanes, build->part_lanes + build->parts);
    text_rules->form_part_first.assign(build->form_part_first, build->form_part_first + OPCODE_COUNT + 1u);
    text_rules->form_parts.assign(build->form_parts, build->form_parts + build->form_part_count);
    text_rules->form_slot_first.assign(build->form_slot_first, build->form_slot_first + OPCODE_COUNT + 1u);
    text_rules->slot_parameters.assign(build->slot_parameters, build->slot_parameters + build->slot_count);
    for (unsigned int bank = 0u; bank < REGCLASS_COUNT; bank += 1u)
    {
        text_rules->bank_before[bank] = build->bank_before[bank];
        text_rules->bank_after[bank] = build->bank_after[bank];
    }
    for (unsigned int fixed = 0u; fixed < PHYSREG_COUNT; fixed += 1u)
    {
        text_rules->fixed_word[fixed] = build->fixed_word[fixed];
    }
    text_rules->minus_word = build->minus_word;
    text_rules->hash_word = build->hash_word;
    text_rules->header_part = build->header_part;
    for (unsigned int number = 0u; number < 4u; number += 1u)
    {
        text_rules->target_numbers[number] = build->target_numbers[number];
    }
    // what keymath and key_schedule take, kept for the device's layout, each table pointing at its values where they
    // are kept
    AsmPrinterProgram *const program = &text_rules->program;
    program->steps.assign(build->steps, build->steps + build->step_count);
    program->field_bits.assign(build->field_bits, build->field_bits + ASM_PRINTER_FIELDS);
    program->field_offset.assign(build->field_offset, build->field_offset + ASM_PRINTER_FIELDS);
    program->values.assign(ASM_PRINTER_TABLES, std::vector<unsigned int>());
    program->tables.assign(build->tables, build->tables + ASM_PRINTER_TABLES);
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLES; table += 1u)
    {
        const size_t rows = (size_t)1u << build->tables[table].index_bits;
        program->values[table].assign(build->values[table], build->values[table] + rows);
        program->tables[table].values = program->values[table].data();
    }
    program->output = build->output;
}

const char *asm_printer_ended(unsigned int end)
{
    switch (end)
    {
    case ASM_PRINTER_CORE_CONSTRUCT:
        return "a form is given as a construct, whose scratch the code generator takes";
    case ASM_PRINTER_CORE_HEADER:
        return "the header holds a byte 0";
    case ASM_PRINTER_CORE_BANK:
        return "a bank writes its register with other than one number";
    case ASM_PRINTER_CORE_TABLES:
        return "the ruleset and the header hold more words or letters than the assembly printer's tables hold";
    default:
        return "the assembly printer's build ran past its memory";
    }
}
