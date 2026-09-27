// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_source.h"
#include "emit_rules.h"

#include <stdio.h>

#include <string>

// every form the C source's emitter writes, the same way: a step is one call into the operator block and its put, and
// the C source takes no bank and names no register
#define CYCLE_SOURCE_FORMS(form_) \
    form_(PROGRAM_NOTE, "program_note", 6u) \
    form_(LANE_OPEN, "lane_open", 0u) \
    form_(MEMBER_OPEN, "member_open", 3u) \
    form_(RECORD_OPEN, "record_open", 1u) \
    form_(FIELD, "field", 6u) \
    form_(FIELD_SIGNED, "field_signed", 6u) \
    form_(CONSTANT, "constant", 4u) \
    form_(LANE_NUMBER, "lane_number", 2u) \
    form_(PRODUCT, "product", 6u) \
    form_(COMPARE, "compare", 6u) \
    form_(SUM, "sum", 6u) \
    form_(DIFFERENCE, "difference", 6u) \
    form_(XOR, "xor", 6u) \
    form_(AND, "and", 6u) \
    form_(ABSOLUTE, "absolute", 4u) \
    form_(TABLE, "table", 5u) \
    form_(WRAP, "wrap", 5u) \
    form_(GCD, "gcd", 8u) \
    form_(LADDER, "ladder", 7u) \
    form_(QUOTIENT, "quotient", 8u) \
    form_(REMAINDER, "remainder", 8u) \
    form_(EXACT_QUOTIENT, "exact_quotient", 8u) \
    form_(PUT, "put", 5u) \
    form_(LANE_CLOSE, "lane_close", 0u)

#define CYCLE_SOURCE_FORM_NAMED(name_, spelling_, parameters_) CYCLE_SOURCE_FORM_##name_,

enum CycleSourceFormName
{
    CYCLE_SOURCE_FORMS(CYCLE_SOURCE_FORM_NAMED) CYCLE_SOURCE_FORM_COUNT
};

static const CycleRuleName s_cycle_source_form_names[CYCLE_SOURCE_FORM_COUNT] = {
    CYCLE_SOURCE_FORMS(CYCLE_FORM_SPELLED)};

// the lane as C source: NVRTC compiles it, and its header is the operator block's prelude
static const CycleRuleSchema s_cycle_source_schema = {
    "c.krs", "nvrtc", "prelude", s_cycle_source_form_names, CYCLE_SOURCE_FORM_COUNT, NULL, 0u, NULL, 0u};

// The record program as C source, in the ruleset c.krs: each step one call into the operator block, whose registers
// are its places in shared memory, and NVRTC compiles the lane. The emitter decides which call a step makes and with
// what; the ruleset spells the call

// one step's source, one call into the operator block and its put; 0 for a step this compiler does not hold, which
// leaves the whole program on the interpreter. `wide` is the width the program's scratch is laid at, and the scratch's
// places follow the file's
static int cycle_program_step(const EngineRecordLayout *layout, const CycleRuleset *rules, unsigned int at,
                              unsigned int wide, std::string &text, int *broken)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    if (!cycle_program_held(layout, at))
    {
        return 0;
    }
    // every register is its step's place in the file, and its sign the sign at that place. key_schedule frees an
    // operand's place only once the step after its last reader begins, so no step's value lies over its own operands
    const std::string place = std::to_string(step->place);
    const std::string limbs = std::to_string(step->limbs);
    const std::string left =
        std::to_string(cycle_program_reads_left(operation) ? layout->step_table[step->left].place : 0u);
    const std::string left_limbs = std::to_string(step->left_limbs);
    const std::string right =
        std::to_string(cycle_program_reads_right(operation) ? layout->step_table[step->right].place : 0u);
    const std::string right_limbs = std::to_string(step->right_limbs);
    const std::string scratch = std::to_string(layout->file_limbs);
    const std::string widest = std::to_string(wide);
    if ((operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED))
    {
        cycle_ruleset_write(rules, text,
                            (operation == ENGINE_RECORD_FIELD_SIGNED) ? CYCLE_SOURCE_FORM_FIELD_SIGNED
                                                                      : CYCLE_SOURCE_FORM_FIELD,
                            {std::to_string(step->member), std::to_string(layout->in_limbs[step->member]),
                             std::to_string(step->left), std::to_string(step->right), place, limbs},
                            broken);
    }
    else if (operation == ENGINE_RECORD_CONSTANT)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_CONSTANT,
                            {std::to_string(step->left), std::to_string(step->right), place, limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_LANE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_NUMBER, {place, limbs}, broken);
    }
    else if ((operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_COMPARE)
             || (operation == ENGINE_RECORD_SUM) || (operation == ENGINE_RECORD_DIFFERENCE)
             || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND))
    {
        const CycleSourceFormName form = (operation == ENGINE_RECORD_PRODUCT)    ? CYCLE_SOURCE_FORM_PRODUCT
                                       : (operation == ENGINE_RECORD_COMPARE)    ? CYCLE_SOURCE_FORM_COMPARE
                                       : (operation == ENGINE_RECORD_SUM)        ? CYCLE_SOURCE_FORM_SUM
                                       : (operation == ENGINE_RECORD_DIFFERENCE) ? CYCLE_SOURCE_FORM_DIFFERENCE
                                       : (operation == ENGINE_RECORD_XOR)        ? CYCLE_SOURCE_FORM_XOR
                                                                                 : CYCLE_SOURCE_FORM_AND;
        cycle_ruleset_write(rules, text, form, {place, limbs, left, left_limbs, right, right_limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_ABSOLUTE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_ABSOLUTE, {place, limbs, left, left_limbs}, broken);
    }
    else if (operation == ENGINE_RECORD_TABLE)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_TABLE,
                            {place, limbs, left, std::to_string(step->table_offset), std::to_string(step->index_bits)},
                            broken);
    }
    else if (operation == ENGINE_RECORD_WRAP)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_WRAP,
                            {place, limbs, left, left_limbs, std::to_string(step->wrap_bits)}, broken);
    }
    else if (operation == ENGINE_RECORD_GCD)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_GCD,
                            {place, limbs, left, left_limbs, right, right_limbs, scratch, widest}, broken);
    }
    else if (operation == ENGINE_RECORD_LADDER)
    {
        // a right that is not positive refuses the lane
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LADDER,
                            {place, limbs, left, left_limbs, right, right_limbs, scratch}, broken);
    }
    else if ((operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
             || (operation == ENGINE_RECORD_EXACT_QUOTIENT))
    {
        // a zero divisor, or an exact quotient that leaves a remainder, refuses the lane
        const CycleSourceFormName form = (operation == ENGINE_RECORD_QUOTIENT)    ? CYCLE_SOURCE_FORM_QUOTIENT
                                       : (operation == ENGINE_RECORD_REMAINDER) ? CYCLE_SOURCE_FORM_REMAINDER
                                                                                : CYCLE_SOURCE_FORM_EXACT_QUOTIENT;
        cycle_ruleset_write(rules, text, form, {place, limbs, left, left_limbs, right, right_limbs, scratch, widest},
                            broken);
    }
    else
    {
        // an operation this compiler does not know
        return 0;
    }
    if (step->out_bits != 0u)
    {
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_PUT,
                            {std::to_string(layout->out_limbs), std::to_string(step->out_offset),
                             std::to_string(step->out_bits), place, limbs},
                            broken);
    }
    return 1;
}

CycleEmitSource::CycleEmitSource(void) : CycleEmit(&s_cycle_source_schema)
{
}

CycleEmitSource &cycle_emit_source(void)
{
    static CycleEmitSource emit;
    return emit;
}

// a program's source: its lane, its atoms and its record cleared, then each step one call into the operator block.
// It names the device, NVRTC and the operator block it is linked against, from `target`, and opens with `header`, the
// operator block's prelude; empty where a step is one this compiler does not hold, or a form was written with other
// arguments than it takes. The registers are the operator block's places in shared memory, so the lane holds none of
// its own: its places are the file's and the scratch's, and it reckons no live words
std::string CycleEmitSource::program(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                                     const std::string &header, unsigned int *places, unsigned int *live)
{
    const CycleRuleset *const rules = ready();
    if (rules == NULL)
    {
        return std::string();
    }
    *places = cycle_program_places(layout);
    *live = 0u;
    std::string text;
    int broken = 0;
    char block[32];
    snprintf(block, sizeof(block), "%016llx", target->block_hash);
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_PROGRAM_NOTE,
                        {std::to_string(layout->steps), std::to_string(target->major), std::to_string(target->minor),
                         std::to_string(target->nvrtc_major), std::to_string(target->nvrtc_minor), std::string(block)},
                        &broken);
    text += header;
    const unsigned int wide = cycle_program_wide(layout);
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_OPEN, {}, &broken);
    for (unsigned int member = 0u; member < layout->members; member += 1u)
    {
        // with no index, lane i reads record i of a member, or its one record where it has one
        cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_MEMBER_OPEN,
                            {std::to_string(member), std::to_string(layout->members),
                             std::to_string(layout->in_limbs[member])},
                            &broken);
    }
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_RECORD_OPEN, {std::to_string(layout->out_limbs)}, &broken);
    for (unsigned int at = 0u; at < layout->steps; at += 1u)
    {
        if (!cycle_program_step(layout, rules, at, wide, text, &broken))
        {
            return std::string();
        }
    }
    cycle_ruleset_write(rules, text, CYCLE_SOURCE_FORM_LANE_CLOSE, {}, &broken);
    return (broken != 0) ? std::string() : text;
}
