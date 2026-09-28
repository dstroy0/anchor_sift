// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// codegen_device_rules.cu: the assembly printer's ruleset built on the device, and held to the host's
#include "asm_printer_internal.h"
#include "codegen_device.h"
#include "codegen_device_internal.h"

int asm_printer_ruleset_same(const AsmPrinterRuleset *left, const AsmPrinterRuleset *right)
{
    const AsmPrinterProgram &left_program = left->program;
    const AsmPrinterProgram &right_program = right->program;
    int same = (left->scratch == right->scratch) && (left->word_lengths == right->word_lengths) &&
               (left->part_lanes == right->part_lanes) && (left->form_part_first == right->form_part_first) &&
               (left->form_parts == right->form_parts) && (left->form_slot_first == right->form_slot_first) &&
               (left->slot_parameters == right->slot_parameters) &&
               (memcmp(left->bank_before, right->bank_before, sizeof(left->bank_before)) == 0) &&
               (memcmp(left->bank_after, right->bank_after, sizeof(left->bank_after)) == 0) &&
               (memcmp(left->fixed_word, right->fixed_word, sizeof(left->fixed_word)) == 0) &&
               (left->minus_word == right->minus_word) && (left->hash_word == right->hash_word) &&
               (left->header_part == right->header_part) &&
               (memcmp(left->target_numbers, right->target_numbers, sizeof(left->target_numbers)) == 0) &&
               (left_program.steps.size() == right_program.steps.size()) &&
               (left_program.field_bits == right_program.field_bits) &&
               (left_program.field_offset == right_program.field_offset) &&
               (left_program.values == right_program.values) && (left_program.output == right_program.output) &&
               (left_program.tables.size() == right_program.tables.size());
    for (size_t step = 0u; (same != 0) && (step < left_program.steps.size()); step += 1u)
    {
        const EngineRecordStep &one = left_program.steps[step];
        const EngineRecordStep &other = right_program.steps[step];
        same = (one.operation == other.operation) && (one.left == other.left) && (one.right == other.right) &&
               (one.member == other.member);
    }
    for (size_t table = 0u; (same != 0) && (table < left_program.tables.size()); table += 1u)
    {
        same = (left_program.tables[table].index_bits == right_program.tables[table].index_bits) &&
               (left_program.tables[table].out_bits == right_program.tables[table].out_bits);
    }
    return (same != 0) && (layout_same(&left_program.layout, &right_program.layout) != 0);
}

#if (defined(__CUDACC__))

// the build in one thread (asm_printer_core_ruleset_build), since each word's number depends on every word before it;
// the build held in device memory and left there as it ended, its pointers the device's; its per-form arrays pass a
// kernel's parameters by far, so it is not passed by value
__global__ void codegen_rules_build(AsmPrinterCoreBuild *build)
{
    if (codegen_device_thread() != 0ull)
    {
        return;
    }
    asm_printer_core_ruleset_build(build);
}

// `build`'s memory taken on the device, sized to its capacities, and `build` pointed at it
static void codegen_rules_memory(DeviceArena *memory, AsmPrinterCoreBuild *build)
{
    build->word_start = codegen_device_take<unsigned int>(memory, (unsigned long long)build->word_capacity + 1ull);
    build->word_length = codegen_device_take<unsigned int>(memory, (unsigned long long)build->word_capacity + 1ull);
    build->word_letters = codegen_device_take<unsigned char>(memory, (unsigned long long)build->letter_capacity + 1ull);
    build->part_pieces = codegen_device_take<unsigned int>(
        memory, ((unsigned long long)build->part_capacity * ASM_PRINTER_PIECES) + 1ull);
    build->part_lanes = codegen_device_take<unsigned int>(memory, (unsigned long long)build->part_capacity + 1ull);
    build->form_parts = codegen_device_take<unsigned int>(memory, (unsigned long long)build->form_part_capacity + 1ull);
    build->slot_parameters = codegen_device_take<unsigned int>(memory, (unsigned long long)build->slot_capacity + 1ull);
    build->steps = codegen_device_take<EngineRecordStep>(memory, build->step_capacity);
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLES; table += 1u)
    {
        build->values[table] = codegen_device_take<unsigned int>(memory, build->table_capacity[table]);
    }
}

// what the device's build laid out, read back into `memory`, and `host` pointed at it with the build's counts
static void codegen_rules_read(DeviceArena *device_arena, const AsmPrinterCoreBuild *ended, AsmPrinterMemory *memory,
                               AsmPrinterCoreBuild *host)
{
    *host = *ended;
    asm_printer_memory_size(memory, host);
    codegen_device_read(device_arena, host->word_start, ended->word_start, ended->words);
    codegen_device_read(device_arena, host->word_length, ended->word_length, ended->words);
    codegen_device_read(device_arena, host->word_letters, ended->word_letters, ended->letters);
    codegen_device_read(device_arena, host->part_pieces, ended->part_pieces,
                        (unsigned long long)ended->parts * ASM_PRINTER_PIECES);
    codegen_device_read(device_arena, host->part_lanes, ended->part_lanes, ended->parts);
    codegen_device_read(device_arena, host->form_parts, ended->form_parts, ended->form_part_count);
    codegen_device_read(device_arena, host->slot_parameters, ended->slot_parameters, ended->slot_count);
    codegen_device_read(device_arena, host->steps, ended->steps, ended->step_count);
    for (unsigned int table = 0u; table < ASM_PRINTER_TABLES; table += 1u)
    {
        const unsigned long long rows = 1ull << ended->tables[table].index_bits;
        codegen_device_read(device_arena, host->values[table], ended->values[table], rows);
        host->tables[table].values = host->values[table];
    }
}

int asm_printer_ruleset_device(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                               AsmPrinterRuleset *text_rules, std::string *error)
{
    *text_rules = AsmPrinterRuleset{};
    if ((rules->schema->form_count != OPCODE_COUNT) || (rules->schema->bank_count != REGCLASS_COUNT) ||
        (rules->schema->fixed_count != PHYSREG_COUNT))
    {
        *error = "the ruleset was read against another code generator's schema than the lane's";
        return 0;
    }
    const unsigned int scratch_banks[3] = {REGCLASS_TEMPORARY, REGCLASS_WIDE, REGCLASS_PREDICATE};
    if (ruleset_scratch_device(rules, scratch_banks, &text_rules->scratch, error) == 0)
    {
        return 0;
    }
    AsmPrinterFlat flat;
    asm_printer_flatten(rules, target, header, &flat);
    DeviceArena rules_arena{};
    rules_arena.ok = 1;
    AsmPrinterCoreBuild build{};
    build.rules = flat.rules;
    build.rules.letters = codegen_device_copy(&rules_arena, flat.letters.data(), flat.letters.size());
    build.rules.texts = codegen_device_copy(&rules_arena, flat.texts.data(), flat.texts.size());
    build.rules.slots = codegen_device_copy(&rules_arena, flat.slots.data(), flat.slots.size());
    unsigned int step_capacity = ASM_PRINTER_STEP_CAPACITY;
    int built = 0;
    AsmPrinterMemory memory;
    AsmPrinterCoreBuild host{};
    while ((rules_arena.ok != 0) && (built == 0))
    {
        DeviceArena build_arena{};
        build_arena.ok = 1;
        asm_printer_capacities(&flat, step_capacity, &build);
        codegen_rules_memory(&build_arena, &build);
        AsmPrinterCoreBuild *const device_ended = codegen_device_copy(&build_arena, &build, 1ull);
        AsmPrinterCoreBuild ended{};
        if (build_arena.ok != 0)
        {
            codegen_rules_build<<<1u, 1u>>>(device_ended);
            codegen_device_launched(&build_arena);
        }
        codegen_device_read(&build_arena, &ended, device_ended, 1ull);
        if ((build_arena.ok != 0) && (ended.end == ASM_PRINTER_CORE_OK))
        {
            codegen_rules_read(&build_arena, &ended, &memory, &host);
            built = (build_arena.ok != 0) ? 1 : 0;
        }
        const int ok = build_arena.ok;
        codegen_device_release(&build_arena);
        if (ok == 0)
        {
            rules_arena.ok = 0;
        }
        else if ((built == 0) && ((ended.end != ASM_PRINTER_CORE_FULL) || (step_capacity >= (1u << 30u))))
        {
            codegen_device_release(&rules_arena);
            *error = asm_printer_ended(ended.end);
            return 0;
        }
        step_capacity *= 2u;
    }
    const int ok = rules_arena.ok;
    codegen_device_release(&rules_arena);
    if (ok == 0)
    {
        *error = "the device errored on a call";
        return 0;
    }
    asm_printer_keep(&host, text_rules);
    // the program laid out by the device as well; the host's key is not kept, and the output it names is the program's
    return asm_printer_program_device(&text_rules->program, &text_rules->program.layout, error);
}

#else

int asm_printer_ruleset_device(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                               AsmPrinterRuleset *text_rules, std::string *error)
{
    (void)rules;
    (void)target;
    (void)header;
    *text_rules = AsmPrinterRuleset{};
    *error = "the build has no device";
    return 0;
}

#endif
