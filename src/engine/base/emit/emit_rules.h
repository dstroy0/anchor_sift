// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_RULES_H
#define EMIT_RULES_H

// What the emitter's base (emit.cu) and each language that inherits it (emit_ptx.cu, emit_source.cu) share, and
// no caller outside the emitter reads: a ruleset as read, the schema a language reads it against, and the writer a
// language writes its forms with

#include "emit.h"

#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

// a form, a bank or a held register as a .krs file writes it, and the parameters it takes
struct EmitRuleName
{
    const char *text;
    unsigned int parameters;
};

#define EMIT_FORM_WRITTEN(name_, text_, parameters_) {text_, parameters_},
#define EMIT_BANK_WRITTEN(name_, text_) {text_, 1u},
#define EMIT_FIXED_WRITTEN(name_, text_) {text_, 0u},

// what an emitter asks of its ruleset: the file it is read from, the toolchain and the header the emitter's path
// builds with, and the forms, banks and held registers the emitter names
struct EmitRuleSchema
{
    const char *file;
    const char *toolchain;
    const char *header;
    const EmitRuleName *forms;
    unsigned int form_count;
    const EmitRuleName *banks;
    unsigned int bank_count;
    const EmitRuleName *fixed;
    unsigned int fixed_count;
};

// a text cut at its parameters: pieces[k] comes before the argument of parameter slots[k], and the last piece after the
// last argument, one piece more than slots
struct EmitForm
{
    std::vector<std::string> pieces;
    std::vector<unsigned int> slots;
};

// what one argument of a construct's line is: text written as it stands, the construct's own parameter at a slot, or
// a scratch register of a bank, `number` naming it within one writing of the construct
enum EmitConstructArgumentKind
{
    EMIT_CONSTRUCT_TEXT = 0,
    EMIT_CONSTRUCT_PARAMETER = 1,
    EMIT_CONSTRUCT_SCRATCH = 2
};

struct EmitConstructArgument
{
    EmitConstructArgumentKind kind;
    unsigned int slot;
    unsigned int number;
    std::string text;
};

// one line of a construct: a form, or a construct given before it in the file, and its arguments
struct EmitConstructLine
{
    unsigned int form;
    std::vector<EmitConstructArgument> arguments;
};

// a form built from more basic ones (engine_table.md item 11(f) 5): where the target's own instruction for a form
// leaves its rules, the ruleset gives the form as a construct of the same name and parameters, and each writing of
// the form writes the construct's lines. No lines is the form as its text gives it
struct EmitConstruct
{
    std::vector<EmitConstructLine> lines;
};

// a scratch register a construct takes: a fresh register of the bank at that place in the schema, or empty where the
// writer has none of that bank to give
typedef std::function<std::string(unsigned int bank)> EmitScratch;

// a ruleset read from its file against its emitter's schema: where it was read, and why it was refused where it was;
// its own name, the toolchain that builds its text and where its header comes from; each bank's written form of a
// register, each held register's written form, and each form, by their places in the schema; and which of them the file
// gave, to find one given twice or left out
struct EmitRuleset
{
    const EmitRuleSchema *schema;
    int tried;
    int ready;
    std::string path;
    std::string refused;
    std::string name;
    std::string toolchain;
    std::string header;
    std::vector<EmitForm> banks;
    std::vector<std::string> fixed;
    std::vector<EmitForm> forms;
    std::vector<EmitConstruct> constructs;
    std::vector<unsigned char> bank_given;
    std::vector<unsigned char> fixed_given;
    std::vector<unsigned char> form_given;
    // the construct being read, its place among the forms (the form count where none is), and its parameters' names
    unsigned int building;
    std::vector<std::string> building_parameters;
};

// 1 where the operation reads a right register, and where it reads a left one
int emit_program_reads_right(unsigned int operation);

int emit_program_reads_left(unsigned int operation);

// 1 where a compiled program holds step `at` as it is laid
int emit_program_held(const EngineRecordLayout *layout, unsigned int at);

// form `name` of `rules` appended to `text`, its arguments in the order of its parameters, a construct's scratch
// taken of `scratch`; `broken` set, and nothing written, where they are not as many as the form takes
void emit_ruleset_write_taking(const EmitRuleset *rules, std::string &text, unsigned int name,
                               std::initializer_list<std::string> arguments, const EmitScratch &scratch,
                               int *broken);

// the same, by a writer with no scratch to give
void emit_ruleset_write(const EmitRuleset *rules, std::string &text, unsigned int name,
                        std::initializer_list<std::string> arguments, int *broken);

// the same, its arguments held in a list
void emit_ruleset_write_list(const EmitRuleset *rules, std::string &text, unsigned int name,
                             const std::vector<std::string> &arguments, const EmitScratch &scratch, int *broken);

// the scratch each form of `rules` takes in one writing, four words a form by its place in the schema: the registers it
// takes of the banks at places banks[0], banks[1] and banks[2], and 1 where it takes one of any other bank. A form the
// ruleset gives as its text takes none; a construct takes each scratch register it names once, and what each form it
// writes takes
void emit_ruleset_scratch(const EmitRuleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch);

#endif
