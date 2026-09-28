// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// target_parse.cu: the IR's operands, and where rulesets are found; their lines are read by ruleset_core.h
#include "target_internal.h"

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
static int ir_operand(const EngineRecordLayout *layout, unsigned int at, unsigned int operand, unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= layout->step_table[operand].limbs);
}

int ir_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM) ||
           (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER) ||
           (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) ||
           (operation == ENGINE_RECORD_AND) || (operation == ENGINE_RECORD_QUOTIENT) ||
           (operation == ENGINE_RECORD_REMAINDER) || (operation == ENGINE_RECORD_GCD) ||
           (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

// 1 where the operation reads a left register: every one but the fields, the constant and the lane's number
int ir_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED) &&
           (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid out: its operands are earlier steps, each read whole (a table
// reads its source's low limb alone, and key_schedule leaves its left_limbs 0), its own limbs lie inside the file, and
// a field reads a member the program has, a signed field's top bit inside its limbs. A step that fails this leaves the
// whole program on the interpreter
int ir_step_valid(const EngineRecordLayout *layout, unsigned int at)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const int reads_left = ir_reads_left(operation);
    const int reads_left_all = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at)) &&
           !(reads_left_all && !ir_operand(layout, at, step->left, step->left_limbs)) &&
           !(ir_reads_right(operation) && !ir_operand(layout, at, step->right, step->right_limbs)) &&
           (((unsigned long long)step->place + step->limbs) <= (unsigned long long)layout->file_limbs) &&
           (!field || (step->member < layout->members)) &&
           ((operation != ENGINE_RECORD_FIELD_SIGNED) ||
            ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// The rulesets a lane is written in, one a language, each read once a process from its .krs file in
// engine/compiler/codegen/rulesets, or in the folder $CYCLE_RULESETS names. The format is the comment at the head of
// ptx.krs. Each language's code generator names every bank of registers it takes from, every register it passes to a
// form by name, and every form it writes with the parameters each takes, in the schema its class gives the base; a
// ruleset that lacks one of them, holds one they do not name, or gives a form other parameters is refused whole, and
// the record machine sends its programs on to another language or the interpreter. A form is kept cut at its
// parameters: writing one appends its pieces with each argument between them

// the folder rulesets are read from: $CYCLE_RULESETS, else rulesets in this file's folder in the tree it was built from
std::string ruleset_folder(void)
{
    const char *const named = getenv("CYCLE_RULESETS");
    if ((named != NULL) && (named[0] != '\0'))
    {
        return std::string(named);
    }
    const std::string file = __FILE__;
    const size_t slash = file.find_last_of("/\\");
    return (slash == std::string::npos) ? std::string("rulesets") : (file.substr(0u, slash + 1u) + "rulesets");
}

// the place of `word` among `count` names, or `count` where it is none of them
unsigned int ruleset_find(const RulesetName *names, unsigned int count, const std::string &word)
{
    unsigned int found = count;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = (word == names[at].text) ? at : found;
    }
    return found;
}
