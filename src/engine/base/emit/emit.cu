// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit.h"
#include "emit_rules.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <cstddef>
#include <functional>
#include <initializer_list>
#include <string>
#include <vector>

// 1 where the step reads its operand whole from an earlier step: a local read past its own limbs is not a register
static int emit_program_operand(const EngineRecordLayout *layout, unsigned int at, unsigned int operand,
                                unsigned int limbs)
{
    return (operand < at) && (limbs != 0u) && (limbs <= layout->step_table[operand].limbs);
}

int emit_program_reads_right(unsigned int operation)
{
    return (operation == ENGINE_RECORD_PRODUCT) || (operation == ENGINE_RECORD_SUM)
        || (operation == ENGINE_RECORD_DIFFERENCE) || (operation == ENGINE_RECORD_LADDER)
        || (operation == ENGINE_RECORD_COMPARE) || (operation == ENGINE_RECORD_XOR) || (operation == ENGINE_RECORD_AND)
        || (operation == ENGINE_RECORD_QUOTIENT) || (operation == ENGINE_RECORD_REMAINDER)
        || (operation == ENGINE_RECORD_GCD) || (operation == ENGINE_RECORD_EXACT_QUOTIENT);
}

// 1 where the operation reads a left register: every one but the fields, the constant and the lane's number
int emit_program_reads_left(unsigned int operation)
{
    return (operation != ENGINE_RECORD_FIELD) && (operation != ENGINE_RECORD_FIELD_SIGNED)
        && (operation != ENGINE_RECORD_CONSTANT) && (operation != ENGINE_RECORD_LANE);
}

// 1 where a compiled program holds the step as it is laid: its operands are earlier steps, each read whole (a table
// reads its source's low limb alone, and key_schedule leaves its left_limbs 0), its own limbs lie inside the file, and
// a field reads a member the program has, a signed field's top bit inside its limbs. A step that fails this leaves the
// whole program on the interpreter
int emit_program_held(const EngineRecordLayout *layout, unsigned int at)
{
    const DeviceRecordStep *const step = &layout->step_table[at];
    const unsigned int operation = step->operation;
    const int reads_left = emit_program_reads_left(operation);
    const int reads_left_whole = reads_left && (operation != ENGINE_RECORD_TABLE);
    const int field = (operation == ENGINE_RECORD_FIELD) || (operation == ENGINE_RECORD_FIELD_SIGNED);
    return (step->limbs != 0u) && !(reads_left && (step->left >= at))
        && !(reads_left_whole && !emit_program_operand(layout, at, step->left, step->left_limbs))
        && !(emit_program_reads_right(operation) && !emit_program_operand(layout, at, step->right, step->right_limbs))
        && (((unsigned long long)step->place + step->limbs) <= (unsigned long long)layout->file_limbs)
        && (!field || (step->member < layout->members))
        && ((operation != ENGINE_RECORD_FIELD_SIGNED)
            || ((step->right != 0u) && (((step->right - 1u) / 32u) < step->limbs)));
}

// The rulesets a lane is written in, one a language, each read once a process from its .krs file in
// engine/base/emit/rulesets, or in the folder $CYCLE_RULESETS names. The format is the comment at the head of ptx.krs.
// Each language's emitter names every bank of registers it takes from, every register it passes to a form by name, and
// every form it writes with the parameters each takes, in the schema its class gives the base; a ruleset that lacks
// one of them, holds one they do not name, or gives a form other parameters is refused whole, and the record machine
// sends its programs on to another language or the interpreter. A form is kept cut at its parameters: writing one
// appends its pieces with each argument between them


// the folder rulesets are read from: $CYCLE_RULESETS, else rulesets in this file's folder in the tree it was built from
static std::string emit_ruleset_folder(void)
{
    const char *const named = getenv("CYCLE_RULESETS");
    if ((named != NULL) && (named[0] != '\0'))
    {
        return std::string(named);
    }
    const std::string file = __FILE__;
    const size_t cut = file.find_last_of("/\\");
    return (cut == std::string::npos) ? std::string("rulesets") : (file.substr(0u, cut + 1u) + "rulesets");
}

// a text as a .krs file writes it, cut at its parameters: \t, \n and \\ are a tab, a line's end and a backslash, and
// {p} is parameter p's argument where p is one of `parameters`, a brace that opens no parameter's name being itself. 0
// where a backslash begins no escape the format knows
static int emit_ruleset_cut(const std::string &text, const std::vector<std::string> &parameters, EmitForm *form)
{
    form->pieces.assign(1u, std::string());
    form->slots.clear();
    size_t at = 0u;
    while (at < text.size())
    {
        const char held = text[at];
        const char next = ((at + 1u) < text.size()) ? text[at + 1u] : '\0';
        const size_t close = (held == '{') ? text.find('}', at + 1u) : std::string::npos;
        size_t slot = parameters.size();
        for (size_t parameter = 0u; (close != std::string::npos) && (parameter < parameters.size()); parameter += 1u)
        {
            slot = (text.compare(at + 1u, close - (at + 1u), parameters[parameter]) == 0) ? parameter : slot;
        }
        if ((held == '\\') && (next != 't') && (next != 'n') && (next != '\\'))
        {
            return 0;
        }
        if (held == '\\')
        {
            form->pieces.back() += (next == 't') ? '\t' : ((next == 'n') ? '\n' : '\\');
            at += 2u;
        }
        else if (slot < parameters.size())
        {
            // a parameter's place among a form's few, held whole in 32 bits
            form->slots.push_back((unsigned int)slot);
            form->pieces.push_back(std::string());
            at = close + 1u;
        }
        else
        {
            form->pieces.back() += held;
            at += 1u;
        }
    }
    return 1;
}

// the words of a line's head, split at its spaces
static std::vector<std::string> emit_ruleset_words(const std::string &head)
{
    std::vector<std::string> words;
    size_t at = 0u;
    while (at < head.size())
    {
        const size_t space = head.find(' ', at);
        const size_t end = (space == std::string::npos) ? head.size() : space;
        if (end > at)
        {
            words.push_back(head.substr(at, end - at));
        }
        at = end + 1u;
    }
    return words;
}

// the place of `word` among `count` names, or `count` where it is none of them
static unsigned int emit_ruleset_find(const EmitRuleName *names, unsigned int count, const std::string &word)
{
    unsigned int found = count;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        found = (word == names[at].text) ? at : found;
    }
    return found;
}

// one entry of a ruleset, `kind` the first word of its line and `rest` the rest of the line, read against the
// ruleset's schema; empty where the entry holds, else why it does not
static std::string emit_ruleset_entry(EmitRuleset *rules, const std::string &kind, const std::string &rest)
{
    const EmitRuleSchema *const schema = rules->schema;
    // a named entry's head is its name and parameters, and its text follows the head's "= "
    const size_t equals = rest.find('=');
    const std::vector<std::string> head = emit_ruleset_words(rest.substr(0u, equals));
    const size_t text_at = (equals == std::string::npos) ? rest.size()
                         : ((((equals + 1u) < rest.size()) && (rest[equals + 1u] == ' ')) ? (equals + 2u)
                                                                                          : (equals + 1u));
    const std::string text = rest.substr(text_at);
    const std::string name = head.empty() ? std::string() : head[0];
    const std::vector<std::string> parameters(head.empty() ? head.end() : (head.begin() + 1), head.end());
    EmitForm form;
    if ((kind == "ruleset") || (kind == "toolchain") || (kind == "header"))
    {
        std::string *const value = (kind == "ruleset") ? &rules->name
                                 : ((kind == "toolchain") ? &rules->toolchain : &rules->header);
        if ((equals != std::string::npos) || (head.size() != 1u) || !value->empty())
        {
            return kind + " is not one word given once";
        }
        *value = name;
        return std::string();
    }
    if (kind == "bank")
    {
        const unsigned int bank = emit_ruleset_find(schema->banks, schema->bank_count, name);
        if ((equals == std::string::npos) || (bank == schema->bank_count) || !parameters.empty()
            || (rules->bank_given[bank] != 0u)
            || !emit_ruleset_cut(text, std::vector<std::string>(1u, std::string("n")), &form))
        {
            return "the bank " + name + " is not one the emitter takes from, or is given twice or written wrong";
        }
        rules->banks[bank] = form;
        rules->bank_given[bank] = 1u;
        return std::string();
    }
    if (kind == "fixed")
    {
        const unsigned int fixed = emit_ruleset_find(schema->fixed, schema->fixed_count, name);
        if ((equals == std::string::npos) || (fixed == schema->fixed_count) || !parameters.empty()
            || (rules->fixed_given[fixed] != 0u) || !emit_ruleset_cut(text, std::vector<std::string>(), &form))
        {
            return "the register " + name + " is not one the emitter names, or is given twice or written wrong";
        }
        rules->fixed[fixed] = form.pieces[0];
        rules->fixed_given[fixed] = 1u;
        return std::string();
    }
    if (kind == "form")
    {
        const unsigned int named = emit_ruleset_find(schema->forms, schema->form_count, name);
        if ((equals == std::string::npos) || (named == schema->form_count)
            || (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u)
            || !emit_ruleset_cut(text, parameters, &form))
        {
            return "the form " + name + " is not one the emitter writes, takes other parameters, or is given twice or "
                   "written wrong";
        }
        rules->forms[named] = form;
        rules->form_given[named] = 1u;
        return std::string();
    }
    if (kind == "construct")
    {
        // a construct's head is its name and parameters as a form's is, with no text: its lines follow, to `end`
        const unsigned int named = emit_ruleset_find(schema->forms, schema->form_count, name);
        if ((equals != std::string::npos) || (named == schema->form_count)
            || (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u))
        {
            return "the construct " + name + " is not a form the emitter writes, takes other parameters, or is given "
                   "twice";
        }
        rules->building = named;
        rules->building_parameters = parameters;
        rules->constructs[named].lines.clear();
        return std::string();
    }
    return "no entry is of the kind " + kind;
}

// one line of the construct being read: `end` closes it, and any other line is a form, or a construct given before
// it in the file, and its arguments, split at spaces. An argument that is one of the construct's parameters stands for
// that parameter's argument, {bank:n} for scratch register n of that bank, taken fresh each time the construct is
// written, and any other word for itself. Empty where the line holds, else why it does not
static std::string emit_ruleset_construct_line(EmitRuleset *rules, const std::string &line)
{
    const EmitRuleSchema *const schema = rules->schema;
    EmitConstruct *const construct = &rules->constructs[rules->building];
    const std::string building = schema->forms[rules->building].text;
    if (line == "end")
    {
        if (construct->lines.empty())
        {
            return "the construct " + building + " has no lines";
        }
        rules->form_given[rules->building] = 1u;
        rules->building = schema->form_count;
        return std::string();
    }
    const std::vector<std::string> words = emit_ruleset_words(line);
    const unsigned int named = words.empty() ? schema->form_count
                                             : emit_ruleset_find(schema->forms, schema->form_count, words[0]);
    // a form or construct the file has given already: one given later, or the construct itself, would make a loop
    if ((named == schema->form_count) || (rules->form_given[named] == 0u)
        || ((words.size() - 1u) != schema->forms[named].parameters))
    {
        return "the construct " + building + " writes " + (words.empty() ? std::string() : words[0])
             + ", which the file has not given before it or which takes other arguments";
    }
    EmitConstructLine written;
    written.form = named;
    for (size_t at = 1u; at < words.size(); at += 1u)
    {
        const std::string &word = words[at];
        EmitConstructArgument argument = {EMIT_CONSTRUCT_TEXT, 0u, 0u, word};
        for (size_t parameter = 0u; parameter < rules->building_parameters.size(); parameter += 1u)
        {
            if (word == rules->building_parameters[parameter])
            {
                argument.kind = EMIT_CONSTRUCT_PARAMETER;
                // a parameter's place among a form's few, held whole in 32 bits
                argument.slot = (unsigned int)parameter;
            }
        }
        const size_t colon = word.find(':');
        const int braced = (word.size() > 4u) && (word[0] == '{') && (word[word.size() - 1u] == '}')
                        && (colon != std::string::npos);
        if (braced)
        {
            const unsigned int bank = emit_ruleset_find(schema->banks, schema->bank_count, word.substr(1u, colon - 1u));
            const std::string digits = word.substr(colon + 1u, word.size() - colon - 2u);
            const int counted = !digits.empty() && (digits.size() < 6u)
                             && (digits.find_first_not_of("0123456789") == std::string::npos);
            if ((bank == schema->bank_count) || !counted)
            {
                return "the construct " + building + " takes a scratch register " + word
                     + " of no bank the ruleset gives, or with no number";
            }
            argument.kind = EMIT_CONSTRUCT_SCRATCH;
            argument.slot = bank;
            // five digits at most, held whole in 32 bits
            argument.number = (unsigned int)strtoul(digits.c_str(), NULL, 10);
        }
        written.arguments.push_back(argument);
    }
    construct->lines.push_back(written);
    return std::string();
}

// the ruleset at `path` read whole into `rules` against its schema: 1 where its first line is krs 1, every entry holds,
// and every bank, held register and form the emitter names is given with the ruleset's name, toolchain and header,
// else 0 with the reason in rules->refused. A line that begins with # is a comment, and a blank line is nothing
static int emit_ruleset_read(EmitRuleset *rules, const std::string &path)
{
    const EmitRuleSchema *const schema = rules->schema;
    rules->path = path;
    rules->banks.assign(schema->bank_count, EmitForm());
    rules->fixed.assign(schema->fixed_count, std::string());
    rules->forms.assign(schema->form_count, EmitForm());
    rules->constructs.assign(schema->form_count, EmitConstruct());
    rules->building = schema->form_count;
    rules->bank_given.assign(schema->bank_count, 0u);
    rules->fixed_given.assign(schema->fixed_count, 0u);
    rules->form_given.assign(schema->form_count, 0u);
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        rules->refused = "it could not be opened";
        return 0;
    }
    std::string whole;
    char block[4096];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        whole.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    unsigned int number = 0u;
    size_t at = 0u;
    while ((at < whole.size()) && rules->refused.empty())
    {
        const size_t found = whole.find('\n', at);
        const size_t end = (found == std::string::npos) ? whole.size() : found;
        // a checkout that ends its lines with a carriage return as well leaves each line as it was written
        const size_t kept = ((end > at) && (whole[end - 1u] == '\r')) ? (end - 1u) : end;
        const std::string line = whole.substr(at, kept - at);
        number += 1u;
        at = end + 1u;
        const size_t space = line.find(' ');
        const int constructing = rules->building != schema->form_count;
        const std::string why = (number == 1u) ? ((line == "krs 1") ? std::string() : std::string("it is not krs 1"))
                              : ((line.empty() || (line[0] == '#'))
                                     ? std::string()
                                     : (constructing ? emit_ruleset_construct_line(rules, line)
                                                     : emit_ruleset_entry(rules, line.substr(0u, space),
                                                                          (space == std::string::npos)
                                                                          ? std::string()
                                                                          : line.substr(space + 1u))));
        if (!why.empty())
        {
            char where[32];
            snprintf(where, sizeof(where), "line %u: ", number);
            rules->refused = where + why;
        }
    }
    if (rules->refused.empty() && (rules->building != schema->form_count))
    {
        rules->refused = "the construct " + std::string(schema->forms[rules->building].text) + " has no end";
    }
    for (unsigned int bank = 0u; rules->refused.empty() && (bank < schema->bank_count); bank += 1u)
    {
        if (rules->bank_given[bank] == 0u)
        {
            rules->refused = "the bank " + std::string(schema->banks[bank].text) + " is not given";
        }
    }
    for (unsigned int fixed = 0u; rules->refused.empty() && (fixed < schema->fixed_count); fixed += 1u)
    {
        if (rules->fixed_given[fixed] == 0u)
        {
            rules->refused = "the register " + std::string(schema->fixed[fixed].text) + " is not given";
        }
    }
    for (unsigned int named = 0u; rules->refused.empty() && (named < schema->form_count); named += 1u)
    {
        if (rules->form_given[named] == 0u)
        {
            rules->refused = "the form " + std::string(schema->forms[named].text) + " is not given";
        }
    }
    if (rules->refused.empty() && (rules->name.empty() || rules->toolchain.empty() || rules->header.empty()))
    {
        rules->refused = "its ruleset, toolchain or header is not named";
    }
    return rules->refused.empty() ? 1 : 0;
}

// a ruleset read once a process into `rules` from its schema's file; NULL where it is refused. A ruleset naming
// another toolchain or header than its emitter's path builds with is refused with the rest
static const EmitRuleset *emit_ruleset_load(EmitRuleset *rules, const EmitRuleSchema *schema, int report)
{
    if (rules->tried != 0)
    {
        return (rules->ready != 0) ? rules : NULL;
    }
    rules->tried = 1;
    rules->schema = schema;
    rules->ready = emit_ruleset_read(rules, emit_ruleset_folder() + "/" + schema->file);
    if ((rules->ready != 0) && ((rules->toolchain != schema->toolchain) || (rules->header != schema->header)))
    {
        rules->ready = 0;
        rules->refused = "its path builds with " + std::string(schema->toolchain) + " and takes its header from "
                       + schema->header;
    }
    if ((report != 0) && (rules->ready != 0))
    {
        fprintf(stderr, "  cycle: the ruleset %s read from %s\n", rules->name.c_str(), rules->path.c_str());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: the ruleset at %s is refused (%s)\n", rules->path.c_str(), rules->refused.c_str());
    }
    return (rules->ready != 0) ? rules : NULL;
}

// the base holds its language's ruleset from construction, unread, and reads it at the first call to ruleset()
Emitter::Emitter(const EmitRuleSchema *schema) : rules(new EmitRuleset())
{
    rules->schema = schema;
}

Emitter::~Emitter()
{
    delete rules;
}

const EmitRuleset *Emitter::ruleset(int report)
{
    return emit_ruleset_load(rules, rules->schema, report);
}

const EmitRuleset *Emitter::ready(void) const
{
    return (rules->ready != 0) ? rules : NULL;
}

// form `name` of `rules` appended to `text`, `argument` holding as many arguments as it takes, in the order of its
// parameters: its text cut at them, or where the ruleset gives it as a construct, each of the construct's lines
// written the same way, a scratch register taken of `scratch` the first time a writing names it. `broken` set where a
// scratch register cannot be taken
static void emit_ruleset_form_text(const EmitRuleset *rules, std::string &text, unsigned int name,
                                const std::string *argument, const EmitScratch &scratch, int *broken)
{
    const EmitConstruct *const construct = &rules->constructs[name];
    if (construct->lines.empty())
    {
        const EmitForm *const form = &rules->forms[name];
        text += form->pieces[0];
        for (size_t at = 0u; at < form->slots.size(); at += 1u)
        {
            text += argument[form->slots[at]];
            text += form->pieces[at + 1u];
        }
        return;
    }
    // the scratch registers this writing has taken, each by its bank and number
    std::vector<unsigned int> scratch_bank;
    std::vector<unsigned int> scratch_number;
    std::vector<std::string> scratch_taken;
    for (const EmitConstructLine &line : construct->lines)
    {
        std::vector<std::string> arguments;
        for (const EmitConstructArgument &given : line.arguments)
        {
            size_t found = scratch_taken.size();
            for (size_t at = 0u; (given.kind == EMIT_CONSTRUCT_SCRATCH) && (at < scratch_taken.size()); at += 1u)
            {
                found = ((scratch_bank[at] == given.slot) && (scratch_number[at] == given.number)) ? at : found;
            }
            if ((given.kind == EMIT_CONSTRUCT_SCRATCH) && (found == scratch_taken.size()))
            {
                const std::string taken = scratch(given.slot);
                *broken = *broken || taken.empty();
                scratch_bank.push_back(given.slot);
                scratch_number.push_back(given.number);
                scratch_taken.push_back(taken);
            }
            arguments.push_back((given.kind == EMIT_CONSTRUCT_TEXT)        ? given.text
                                : (given.kind == EMIT_CONSTRUCT_PARAMETER) ? argument[given.slot]
                                                                            : scratch_taken[found]);
        }
        emit_ruleset_form_text(rules, text, line.form, arguments.data(), scratch, broken);
    }
}

// the scratch a writer with no registers of its own to give answers: none
static std::string emit_ruleset_no_scratch(unsigned int bank)
{
    (void)bank;
    return std::string();
}

// form `name` of `rules` appended to `text`, its arguments in the order of its parameters, a construct's scratch taken
// of `scratch`; `broken` set, and nothing written, where they are not as many as the form takes
void emit_ruleset_write_taking(const EmitRuleset *rules, std::string &text, unsigned int name,
                                       std::initializer_list<std::string> arguments, const EmitScratch &scratch,
                                       int *broken)
{
    if (arguments.size() != rules->schema->forms[name].parameters)
    {
        *broken = 1;
        return;
    }
    emit_ruleset_form_text(rules, text, name, arguments.begin(), scratch, broken);
}

// the same, by a writer with no scratch to give: a construct that takes scratch breaks what it is written into
void emit_ruleset_write(const EmitRuleset *rules, std::string &text, unsigned int name,
                                std::initializer_list<std::string> arguments, int *broken)
{
    emit_ruleset_write_taking(rules, text, name, arguments, EmitScratch(emit_ruleset_no_scratch), broken);
}

void emit_ruleset_write_list(const EmitRuleset *rules, std::string &text, unsigned int name,
                             const std::vector<std::string> &arguments, const EmitScratch &scratch, int *broken)
{
    if (arguments.size() != rules->schema->forms[name].parameters)
    {
        *broken = 1;
        return;
    }
    emit_ruleset_form_text(rules, text, name, arguments.data(), scratch, broken);
}

// the scratch form `name` takes in one writing, laid into its four words of `scratch` once and marked in `counted`: each
// scratch register its lines name, once, and what each form its lines write takes, which a construct given before it
// in the file has laid, and the recursion ends
static void emit_ruleset_scratch_of(const EmitRuleset *rules, const unsigned int *banks, unsigned int name,
                                    std::vector<unsigned int> *scratch, std::vector<unsigned char> *counted)
{
    if ((*counted)[name] != 0u)
    {
        return;
    }
    (*counted)[name] = 1u;
    std::vector<unsigned int> taken_bank;
    std::vector<unsigned int> taken_number;
    for (const EmitConstructLine &line : rules->constructs[name].lines)
    {
        for (const EmitConstructArgument &given : line.arguments)
        {
            int found = 0;
            for (size_t at = 0u; (given.kind == EMIT_CONSTRUCT_SCRATCH) && (at < taken_bank.size()); at += 1u)
            {
                found = found || ((taken_bank[at] == given.slot) && (taken_number[at] == given.number));
            }
            if ((given.kind != EMIT_CONSTRUCT_SCRATCH) || (found != 0))
            {
                continue;
            }
            taken_bank.push_back(given.slot);
            taken_number.push_back(given.number);
            const unsigned int held = (given.slot == banks[0]) ? 0u
                                    : ((given.slot == banks[1]) ? 1u : ((given.slot == banks[2]) ? 2u : 3u));
            (*scratch)[(4u * name) + held] = (held == 3u) ? 1u : ((*scratch)[(4u * name) + held] + 1u);
        }
        emit_ruleset_scratch_of(rules, banks, line.form, scratch, counted);
        for (unsigned int held = 0u; held < 3u; held += 1u)
        {
            (*scratch)[(4u * name) + held] += (*scratch)[(4u * line.form) + held];
        }
        (*scratch)[(4u * name) + 3u] |= (*scratch)[(4u * line.form) + 3u];
    }
}

void emit_ruleset_scratch(const EmitRuleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch)
{
    const unsigned int forms = rules->schema->form_count;
    std::vector<unsigned char> counted(forms, (unsigned char)0u);
    scratch->assign(4u * (size_t)forms, 0u);
    for (unsigned int name = 0u; name < forms; name += 1u)
    {
        emit_ruleset_scratch_of(rules, banks, name, scratch, &counted);
    }
}

// a form written by the name its .krs file gives it, for a reader outside the emitter (emit.h), a construct's scratch
// taken of `scratch` by its bank's name
int emit_ruleset_form(const EmitRuleset *rules, const std::string &name, const std::vector<std::string> &arguments,
                      const std::function<std::string(const std::string &bank)> &scratch, std::string &text)
{
    const EmitRuleSchema *const schema = rules->schema;
    const unsigned int named = emit_ruleset_find(schema->forms, schema->form_count, name);
    if ((named == schema->form_count) || (arguments.size() != schema->forms[named].parameters))
    {
        return 0;
    }
    int broken = 0;
    const EmitScratch by_place = [&](unsigned int bank) {
        return scratch(std::string(schema->banks[bank].text));
    };
    emit_ruleset_form_text(rules, text, named, arguments.data(), by_place, &broken);
    return (broken == 0) ? 1 : 0;
}

std::string emit_ruleset_register(const EmitRuleset *rules, const std::string &bank, unsigned int number)
{
    const EmitRuleSchema *const schema = rules->schema;
    const unsigned int named = emit_ruleset_find(schema->banks, schema->bank_count, bank);
    if (named == schema->bank_count)
    {
        return std::string();
    }
    // a bank's written form takes one parameter, the register's number, in every slot it is cut at
    const EmitForm *const form = &rules->banks[named];
    std::string written = form->pieces[0];
    for (size_t at = 0u; at < form->slots.size(); at += 1u)
    {
        written += std::to_string(number);
        written += form->pieces[at + 1u];
    }
    return written;
}

std::string emit_ruleset_fixed(const EmitRuleset *rules, const std::string &name)
{
    const EmitRuleSchema *const schema = rules->schema;
    const unsigned int named = emit_ruleset_find(schema->fixed, schema->fixed_count, name);
    return (named == schema->fixed_count) ? std::string() : rules->fixed[named];
}
