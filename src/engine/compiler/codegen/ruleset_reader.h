// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RULESET_READER_H
#define RULESET_READER_H

// What the code generator's base (target_*.cu) and each language that inherits it (ptx_target.cu, c_target.cu) share,
// and no caller outside the code generator reads: a ruleset as read, the schema a language reads it against, and the
// writer a language writes its forms with

#include "target.h"

#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

// a form, a bank or a fixed register as a .krs file writes it, and the parameters it takes
struct RulesetName
{
    const char *text;
    unsigned int parameters;
};

#define OPCODE_WRITTEN(name_, text_, parameters_) {text_, parameters_},
#define REGCLASS_WRITTEN(name_, text_) {text_, 1u},
#define PHYSREG_WRITTEN(name_, text_) {text_, 0u},

// what a code generator asks of its ruleset: the file it is read from, the toolchain and the header the code
// generator's path builds with, and the forms, banks and fixed registers the code generator names
struct RulesetSchema
{
    const char *file;
    const char *toolchain;
    const char *header;
    const RulesetName *forms;
    unsigned int form_count;
    const RulesetName *banks;
    unsigned int bank_count;
    const RulesetName *fixed;
    unsigned int fixed_count;
};

// a text cut at its parameters: pieces[k] comes before the argument of parameter slots[k], and the last piece after the
// last argument, one piece more than slots
struct InstrTemplate
{
    std::vector<std::string> pieces;
    std::vector<unsigned int> slots;
};

// what one argument of a construct's line is: text written as it stands, the construct's own parameter at a slot, or
// a scratch register of a bank, `number` naming it within one writing of the construct
enum PseudoOperandKind
{
    PSEUDO_TEXT = 0,
    PSEUDO_PARAMETER = 1,
    PSEUDO_SCRATCH = 2
};

struct PseudoOperand
{
    PseudoOperandKind kind;
    unsigned int slot;
    unsigned int number;
    std::string text;
};

// one line of a construct: a form, or a construct given before it in the file, and its arguments
struct PseudoLine
{
    unsigned int form;
    std::vector<PseudoOperand> arguments;
};

// a form built from more basic ones (engine_table.md item 11(f) 5): where the target's own instruction for a form
// leaves its rules, the ruleset gives the form as a construct of the same name and parameters, and each writing of
// the form writes the construct's lines. No lines is the form as its text gives it
struct Pseudo
{
    std::vector<PseudoLine> lines;
};

// a scratch register a construct takes: a fresh register of the bank at that place in the schema, or empty where the
// writer has none of that bank to give
typedef std::function<std::string(unsigned int bank)> ScratchRegisters;

// a ruleset read from its file against its code generator's schema: where it was read, and why it was refused where it
// was; its own name, the toolchain that builds its text and where its header comes from; each bank's written form of a
// register, each fixed register's written form, and each form, by their places in the schema; and which of them the
// file gave, to find one given twice or left out
struct Ruleset
{
    const RulesetSchema *schema;
    int tried;
    int ready;
    std::string path;
    std::string refused;
    std::string name;
    std::string toolchain;
    std::string header;
    std::vector<InstrTemplate> banks;
    std::vector<std::string> fixed;
    std::vector<InstrTemplate> forms;
    std::vector<Pseudo> constructs;
    std::vector<unsigned char> bank_given;
    std::vector<unsigned char> fixed_given;
    std::vector<unsigned char> form_given;
    // the construct being read, its place among the forms (the form count where none is), and its parameters' names
    unsigned int building;
    std::vector<std::string> building_parameters;
};

// 1 where the operation reads a right register, and where it reads a left one
int ir_reads_right(unsigned int operation);

int ir_reads_left(unsigned int operation);

// 1 where a compiled program holds step `at` as it is laid out
int ir_step_valid(const EngineRecordLayout *layout, unsigned int at);

// form `name` of `rules` appended to `text`, its arguments in the order of its parameters, a construct's scratch
// taken of `scratch`; `broken` set, and nothing written, where they are not as many as the form takes
void ruleset_write_taking(const Ruleset *rules, std::string &text, unsigned int name,
                          std::initializer_list<std::string> arguments, const ScratchRegisters &scratch, int *broken);

// the same, by a writer with no scratch to give
void ruleset_write(const Ruleset *rules, std::string &text, unsigned int name,
                   std::initializer_list<std::string> arguments, int *broken);

// the same, its arguments held in a list
void ruleset_write_list(const Ruleset *rules, std::string &text, unsigned int name,
                        const std::vector<std::string> &arguments, const ScratchRegisters &scratch, int *broken);

// the scratch each form of `rules` takes in one writing, four words a form by its place in the schema: the registers it
// takes of the banks at places banks[0], banks[1] and banks[2], and 1 where it takes one of any other bank. A form the
// ruleset gives as its text takes none; a construct takes each scratch register it names once, and what each form it
// writes takes
void ruleset_scratch(const Ruleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch);

#endif
