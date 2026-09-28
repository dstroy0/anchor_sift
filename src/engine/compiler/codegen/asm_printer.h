// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ASM_PRINTER_H
#define ASM_PRINTER_H

// The code generator's text as a record program, the code generator's work where the programs run (engine_table.md item
// 11(f)(a), the code generator on the device). The core decides the forms of the language's ruleset a lane is written
// in (codegen_core.h, MachineInstr); the assembly printer writes their text from the ruleset's own written forms laid
// out as tables, a lane a byte. Each lane reads one form, by the index, finds which of the form's pieces holds its
// byte, and writes that byte: a letter of a piece of the form's text, of a bank's written form around a register's
// number, of a word the ruleset holds whole, or a decimal digit of a number. A lane past its form's end writes 0, which
// no text holds: the text is the lanes' bytes in lane order with the zeros left out. The host lays out once what is the
// ruleset's, the target's and the header's alone (asm_printer_ruleset_build); the forms' records are laid out from the
// items by the functions below, which the device runs (codegen_device.h) and the host oracle runs (asm_printer_host):
// the two lay out them from one source

#include "codegen_core.h"
#include "target.h"

#include <string>
#include <vector>

// the arguments one record of the assembly printer holds, each a word the ruleset holds whole or a number between two
// words (a bank's written form around a register's number); a form with more slots takes a record for each four
#define ASM_PRINTER_SLOTS 4u

// the numbers the program writes are 32-bit words, ten digits at most
#define ASM_PRINTER_DIGITS 10u

// A record of the assembly printer is one form, or four slots of one, as a part: the part's number, the first lane of
// the lanes that write it, and each slot's argument as the word before its number, the word after it, the number, and
// whether it has one. A part is the form's pieces around its slots: the piece before each of its slots, then the piece
// after its last where the form ends there, empty where it goes on in the next part. Its bytes are seventeen atoms in
// order: a piece, then a slot's word before, its number's digits and its word after, four times, then the last piece
#define ASM_PRINTER_PIECES (ASM_PRINTER_SLOTS + 1u)

#define ASM_PRINTER_ATOMS ((4u * ASM_PRINTER_SLOTS) + 1u)

// the record's fields, their bits and where each begins
#define ASM_PRINTER_PART_BITS 16u
#define ASM_PRINTER_FIRST_AT 16u
#define ASM_PRINTER_FIRST_BITS 32u
#define ASM_PRINTER_SLOT_AT 48u
#define ASM_PRINTER_SLOT_BITS 80u
#define ASM_PRINTER_WORD_BITS 16u
#define ASM_PRINTER_NUMBER_BITS 32u
#define ASM_PRINTER_RECORD_BITS (ASM_PRINTER_SLOT_AT + (ASM_PRINTER_SLOTS * ASM_PRINTER_SLOT_BITS))
#define ASM_PRINTER_RECORD_LIMBS ((ASM_PRINTER_RECORD_BITS + 31u) / 32u)

// the most lanes and records the assembly printer runs: a first lane and a record's number are 32-bit fields
#define ASM_PRINTER_LANES_MAX 0x80000000ull

// the assembly printer: its key and layout, as keymath and key_schedule leave them, and what they took, kept so the
// device lays it out again (layout_device, codegen_device.h): its steps, the fields' widths and offsets, its tables,
// each pointing at its values, and the step it outputs
struct AsmPrinterProgram
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    std::vector<EngineRecordStep> steps;
    std::vector<unsigned int> field_bits;
    std::vector<unsigned int> field_offset;
    std::vector<EngineRecordTable> tables;
    std::vector<std::vector<unsigned int>> values;
    unsigned int output;
};

// a slot's argument as the program writes it: the word before its number and the word after, by their numbers among the
// words, and its number where it has one
struct AsmPrinterArgument
{
    unsigned int before;
    unsigned int after;
    unsigned int number;
    unsigned int numbered;
};

// what a ruleset writes, laid out once for a target and a header: the assembly printer and the scratch each form's
// construct takes (ruleset_scratch; none, since the assembly printer refuses a ruleset of constructs); each word's
// length; each part's lanes, the lengths of its pieces; each form's parts, in its order, from form_part_first[form] to
// form_part_first[form + 1] of form_parts, and the parameter each of its slots takes, from form_slot_first[form] to
// form_slot_first[form + 1] of slot_parameters; the words around each bank's register number, each fixed register's
// word, the word "-" before a negative number's digits, the target's hash as the note writes it, and the header's
// part; and the target's compute capability and NVRTC's version as the note writes them
struct AsmPrinterRuleset
{
    AsmPrinterProgram program;
    std::vector<unsigned int> scratch;
    std::vector<unsigned int> word_lengths;
    std::vector<unsigned int> part_lanes;
    std::vector<unsigned int> form_part_first;
    std::vector<unsigned int> form_parts;
    std::vector<unsigned int> form_slot_first;
    std::vector<unsigned int> slot_parameters;
    unsigned int bank_before[REGCLASS_COUNT];
    unsigned int bank_after[REGCLASS_COUNT];
    unsigned int fixed_word[PHYSREG_COUNT];
    unsigned int minus_word;
    unsigned int hash_word;
    unsigned int header_part;
    unsigned int target_numbers[4];
};

// the same as the records' layout reads it, its lists where the layout runs: in host memory for the host oracle, in
// device memory for the device
struct AsmPrinterLists
{
    const unsigned int *word_lengths;
    const unsigned int *part_lanes;
    const unsigned int *form_part_first;
    const unsigned int *form_parts;
    const unsigned int *form_slot_first;
    const unsigned int *slot_parameters;
    unsigned int bank_before[REGCLASS_COUNT];
    unsigned int bank_after[REGCLASS_COUNT];
    unsigned int fixed_word[PHYSREG_COUNT];
    unsigned int minus_word;
    unsigned int hash_word;
    unsigned int header_part;
    unsigned int target_numbers[4];
};

// `bits` of `value` laid out into the record's words from bit `at`, which the record's words hold clear
CODEGEN_CORE void asm_printer_bits(unsigned int *record, unsigned int at, unsigned int bits, unsigned int value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int set = (value >> bit) & 1u;
        record[(at + bit) / 32u] |= set << ((at + bit) % 32u);
    }
}

// 1 where an item is one the assembly printer writes: the header, or a form given as many arguments as it takes, as the
// host's writing it asks
CODEGEN_CORE int asm_printer_formed(const MachineInstr *item)
{
    return (item->form == ASM_PRINTER_ALL_ONES) ||
           ((item->form < OPCODE_COUNT) && (item->count == codegen_operand_count(item->form)));
}

// the slots a form's text takes arguments at
CODEGEN_CORE unsigned int asm_printer_slots(const AsmPrinterLists *forms, unsigned int form)
{
    return forms->form_slot_first[form + 1u] - forms->form_slot_first[form];
}

// the records a formed item takes: a form's slots four to a record and one for a form of none, and one for the header
CODEGEN_CORE unsigned int asm_printer_record_count(const AsmPrinterLists *forms, const MachineInstr *item)
{
    const unsigned int slots = (item->form == ASM_PRINTER_ALL_ONES) ? 0u : asm_printer_slots(forms, item->form);
    return (slots == 0u) ? 1u : ((slots + ASM_PRINTER_SLOTS - 1u) / ASM_PRINTER_SLOTS);
}

// argument `parameter` of a formed item as the program writes it, as the host code generator writes it
// (code_generator_text, code_generator.cu): a register as its bank's words around its number, a fixed register as its
// word, a number as its digits, a negative one after the minus; the note's from its step count and the target, and the
// resident's from the launch's layout
CODEGEN_CORE AsmPrinterArgument asm_printer_argument(const AsmPrinterLists *forms, const MachineInstr *item,
                                                     unsigned int parameter)
{
    AsmPrinterArgument argument = {0u, 0u, 0u, 1u};
    if (item->form == OPCODE_PROGRAM_NOTE)
    {
        argument.number = (parameter == 0u) ? item->arguments[0].number
                                            : ((parameter < 5u) ? forms->target_numbers[parameter - 1u] : 0u);
        if (parameter == 5u)
        {
            argument.before = forms->hash_word;
            argument.numbered = 0u;
        }
        return argument;
    }
    if (item->form == OPCODE_PROGRAM_UNIT)
    {
        // the launch's sizes and offsets and the program's commands and states are a few hundred at most
        argument.number = (unsigned int)codegen_unit(parameter);
        return argument;
    }
    const MachineOperand given = item->arguments[(parameter < MACHINE_INSTR_OPERANDS) ? parameter : 0u];
    if (given.kind == OPERAND_REGISTER)
    {
        argument.before = forms->bank_before[given.which];
        argument.after = forms->bank_after[given.which];
        argument.number = given.number;
    }
    else if (given.kind == OPERAND_PHYSREG)
    {
        argument.before = forms->fixed_word[given.which];
        argument.numbered = 0u;
    }
    else if ((given.kind == OPERAND_SIGNED) && (given.number >= 0x80000000u))
    {
        argument.before = forms->minus_word;
        argument.number = 0u - given.number;
    }
    else
    {
        argument.number = given.number;
    }
    return argument;
}

// a formed item's records laid out from `record` on, as many as asm_printer_record_count gives, into `records` held
// clear: each record's part and its slots' arguments, the first lane left for asm_printer_first to lay out; and the
// lanes each record takes into `record_lanes`, its pieces' letters and each slot's words and ten digits a number, which
// the lanes past its text write as 0
CODEGEN_CORE void asm_printer_records(const AsmPrinterLists *forms, const MachineInstr *item, unsigned long long record,
                                      unsigned int *records, unsigned long long *record_lanes)
{
    if (item->form == ASM_PRINTER_ALL_ONES)
    {
        asm_printer_bits(&records[record * ASM_PRINTER_RECORD_LIMBS], 0u, ASM_PRINTER_PART_BITS, forms->header_part);
        record_lanes[record] = forms->part_lanes[forms->header_part];
        return;
    }
    const unsigned int slots = asm_printer_slots(forms, item->form);
    const unsigned int slot_first = forms->form_slot_first[item->form];
    const unsigned int part_first = forms->form_part_first[item->form];
    const unsigned int chunks = asm_printer_record_count(forms, item);
    for (unsigned int chunk = 0u; chunk < chunks; chunk += 1u)
    {
        unsigned int *const chunk_record = &records[(record + chunk) * ASM_PRINTER_RECORD_LIMBS];
        const unsigned int part = forms->form_parts[part_first + chunk];
        asm_printer_bits(chunk_record, 0u, ASM_PRINTER_PART_BITS, part);
        unsigned long long lanes = forms->part_lanes[part];
        const unsigned int left = slots - (ASM_PRINTER_SLOTS * chunk);
        const unsigned int taken = (left < ASM_PRINTER_SLOTS) ? left : ASM_PRINTER_SLOTS;
        for (unsigned int slot = 0u; slot < taken; slot += 1u)
        {
            const unsigned int parameter = forms->slot_parameters[slot_first + (ASM_PRINTER_SLOTS * chunk) + slot];
            const AsmPrinterArgument argument = asm_printer_argument(forms, item, parameter);
            const unsigned int base = ASM_PRINTER_SLOT_AT + (slot * ASM_PRINTER_SLOT_BITS);
            asm_printer_bits(chunk_record, base, ASM_PRINTER_WORD_BITS, argument.before);
            asm_printer_bits(chunk_record, base + ASM_PRINTER_WORD_BITS, ASM_PRINTER_WORD_BITS, argument.after);
            asm_printer_bits(chunk_record, base + (2u * ASM_PRINTER_WORD_BITS), ASM_PRINTER_NUMBER_BITS,
                             argument.number);
            asm_printer_bits(chunk_record, base + (2u * ASM_PRINTER_WORD_BITS) + ASM_PRINTER_NUMBER_BITS, 1u,
                             argument.numbered);
            lanes += (unsigned long long)forms->word_lengths[argument.before] + forms->word_lengths[argument.after] +
                     ((argument.numbered != 0u) ? ASM_PRINTER_DIGITS : 0u);
        }
        record_lanes[record + chunk] = lanes;
    }
}

// a record's first lane laid out, below ASM_PRINTER_LANES_MAX as the caller holds the lanes
CODEGEN_CORE void asm_printer_first(unsigned int *records, unsigned long long record, unsigned long long first)
{
    asm_printer_bits(&records[record * ASM_PRINTER_RECORD_LIMBS], ASM_PRINTER_FIRST_AT, ASM_PRINTER_FIRST_BITS,
                     (unsigned int)first);
}

// a lane's byte, at the output's offset in its record of the program's out_limbs, below its sign bit
CODEGEN_CORE unsigned int asm_printer_byte(const unsigned int *record, unsigned int out_limbs, unsigned int offset)
{
    const unsigned long long pair =
        (unsigned long long)record[offset / 32u] |
        ((((offset / 32u) + 1u) < out_limbs) ? ((unsigned long long)record[(offset / 32u) + 1u] << 32u) : 0ull);
    return (unsigned int)((pair >> (offset % 32u)) & 0xFFull);
}

// the assembly printer and its tables for any lane the core decides in `rules` for `target` under `header`: 1 where it
// is laid out, else 0 and why in `refused`. A ruleset that gives a form as a construct is refused, since a construct's
// scratch is the code generator's to take, as is a bank that writes its register with other than one number, a header
// that holds a byte 0, and more words or letters than the tables hold
int asm_printer_ruleset_build(const Ruleset *rules, const TargetInfo *target, const std::string &header,
                              AsmPrinterRuleset *text_rules, std::string *refused);

void asm_printer_ruleset_release(AsmPrinterRuleset *text_rules);

// the rules as the records' layout reads them in host memory, their lists `text_rules`' own
AsmPrinterLists asm_printer_lists(const AsmPrinterRuleset *text_rules);

// the host oracle: the lane's items (CodeGenerator::decided) laid out as records by the functions above and written by
// the assembly printer on the host (cycle_record_run_host); 1 where it ran, its text in `text`, else 0 and why in
// `refused`
int asm_printer_host(const AsmPrinterRuleset *text_rules, const std::vector<MachineInstr> &items, std::string *text,
                     std::string *refused);

#endif
