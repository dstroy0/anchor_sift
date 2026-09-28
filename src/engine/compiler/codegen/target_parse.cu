// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// target_parse.cu: the IR's operands and the ruleset's lines read
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

// a text as a .krs file writes it, cut at its parameters: \t, \n and \\ are a tab, a line's end and a backslash, and
// {p} is parameter p's argument where p is one of `parameters`, a brace that opens no parameter's name being itself. 0
// where a backslash begins no escape the format knows
static int ruleset_split(const std::string &text, const std::vector<std::string> &parameters, InstrTemplate *form)
{
    form->pieces.assign(1u, std::string());
    form->slots.clear();
    size_t at = 0u;
    while (at < text.size())
    {
        const char character = text[at];
        const char next = ((at + 1u) < text.size()) ? text[at + 1u] : '\0';
        const size_t close = (character == '{') ? text.find('}', at + 1u) : std::string::npos;
        size_t slot = parameters.size();
        for (size_t parameter = 0u; (close != std::string::npos) && (parameter < parameters.size()); parameter += 1u)
        {
            slot = (text.compare(at + 1u, close - (at + 1u), parameters[parameter]) == 0) ? parameter : slot;
        }
        if ((character == '\\') && (next != 't') && (next != 'n') && (next != '\\'))
        {
            return 0;
        }
        if (character == '\\')
        {
            form->pieces.back() += (next == 't') ? '\t' : ((next == 'n') ? '\n' : '\\');
            at += 2u;
        }
        else if (slot < parameters.size())
        {
            // a parameter's place among a form's few, which fits in 32 bits
            form->slots.push_back((unsigned int)slot);
            form->pieces.push_back(std::string());
            at = close + 1u;
        }
        else
        {
            form->pieces.back() += character;
            at += 1u;
        }
    }
    return 1;
}

// the words of a line's head, split at its spaces
static std::vector<std::string> ruleset_words(const std::string &head)
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
unsigned int ruleset_find(const RulesetName *names, unsigned int count, const std::string &word)
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
std::string ruleset_entry(Ruleset *rules, const std::string &kind, const std::string &rest)
{
    const RulesetSchema *const schema = rules->schema;
    // a named entry's head is its name and parameters, and its text follows the head's "= "
    const size_t equals = rest.find('=');
    const std::vector<std::string> head = ruleset_words(rest.substr(0u, equals));
    const size_t text_at =
        (equals == std::string::npos)
            ? rest.size()
            : ((((equals + 1u) < rest.size()) && (rest[equals + 1u] == ' ')) ? (equals + 2u) : (equals + 1u));
    const std::string text = rest.substr(text_at);
    const std::string name = head.empty() ? std::string() : head[0];
    const std::vector<std::string> parameters(head.empty() ? head.end() : (head.begin() + 1), head.end());
    InstrTemplate form;
    if ((kind == "ruleset") || (kind == "toolchain") || (kind == "header"))
    {
        std::string *const value =
            (kind == "ruleset") ? &rules->name : ((kind == "toolchain") ? &rules->toolchain : &rules->header);
        if ((equals != std::string::npos) || (head.size() != 1u) || !value->empty())
        {
            return kind + " is not one word given once";
        }
        *value = name;
        return std::string();
    }
    if (kind == "bank")
    {
        const unsigned int bank = ruleset_find(schema->banks, schema->bank_count, name);
        if ((equals == std::string::npos) || (bank == schema->bank_count) || !parameters.empty() ||
            (rules->bank_given[bank] != 0u) ||
            !ruleset_split(text, std::vector<std::string>(1u, std::string("n")), &form))
        {
            return "the bank " + name + " is not one the code generator takes from, or is given twice or written wrong";
        }
        rules->banks[bank] = form;
        rules->bank_given[bank] = 1u;
        return std::string();
    }
    if (kind == "fixed")
    {
        const unsigned int fixed = ruleset_find(schema->fixed, schema->fixed_count, name);
        if ((equals == std::string::npos) || (fixed == schema->fixed_count) || !parameters.empty() ||
            (rules->fixed_given[fixed] != 0u) || !ruleset_split(text, std::vector<std::string>(), &form))
        {
            return "the register " + name + " is not one the code generator names, or is given twice or written wrong";
        }
        rules->fixed[fixed] = form.pieces[0];
        rules->fixed_given[fixed] = 1u;
        return std::string();
    }
    if (kind == "form")
    {
        const unsigned int named = ruleset_find(schema->forms, schema->form_count, name);
        if ((equals == std::string::npos) || (named == schema->form_count) ||
            (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u) ||
            !ruleset_split(text, parameters, &form))
        {
            return "the form " + name +
                   " is not one the code generator writes, takes other parameters, or is given twice or "
                   "written wrong";
        }
        rules->forms[named] = form;
        rules->form_given[named] = 1u;
        return std::string();
    }
    if (kind == "construct")
    {
        // a construct's head is its name and parameters as a form's is, with no text: its lines follow, to `end`
        const unsigned int named = ruleset_find(schema->forms, schema->form_count, name);
        if ((equals != std::string::npos) || (named == schema->form_count) ||
            (parameters.size() != schema->forms[named].parameters) || (rules->form_given[named] != 0u))
        {
            return "the construct " + name +
                   " is not a form the code generator writes, takes other parameters, or is given "
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
std::string ruleset_pseudo_line(Ruleset *rules, const std::string &line)
{
    const RulesetSchema *const schema = rules->schema;
    Pseudo *const construct = &rules->constructs[rules->building];
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
    const std::vector<std::string> words = ruleset_words(line);
    const unsigned int named =
        words.empty() ? schema->form_count : ruleset_find(schema->forms, schema->form_count, words[0]);
    // a form or construct the file has given already: one given later, or the construct itself, would make a loop
    if ((named == schema->form_count) || (rules->form_given[named] == 0u) ||
        ((words.size() - 1u) != schema->forms[named].parameters))
    {
        return "the construct " + building + " writes " + (words.empty() ? std::string() : words[0]) +
               ", which the file has not given before it or which takes other arguments";
    }
    PseudoLine written;
    written.form = named;
    for (size_t at = 1u; at < words.size(); at += 1u)
    {
        const std::string &word = words[at];
        PseudoOperand argument = {PSEUDO_TEXT, 0u, 0u, word};
        for (size_t parameter = 0u; parameter < rules->building_parameters.size(); parameter += 1u)
        {
            if (word == rules->building_parameters[parameter])
            {
                argument.kind = PSEUDO_PARAMETER;
                // a parameter's place among a form's few, which fits in 32 bits
                argument.slot = (unsigned int)parameter;
            }
        }
        const size_t colon = word.find(':');
        const int braced =
            (word.size() > 4u) && (word[0] == '{') && (word[word.size() - 1u] == '}') && (colon != std::string::npos);
        if (braced)
        {
            const unsigned int bank = ruleset_find(schema->banks, schema->bank_count, word.substr(1u, colon - 1u));
            const std::string digits = word.substr(colon + 1u, word.size() - colon - 2u);
            const int counted = !digits.empty() && (digits.size() < 6u) &&
                                (digits.find_first_not_of("0123456789") == std::string::npos);
            if ((bank == schema->bank_count) || !counted)
            {
                return "the construct " + building + " takes a scratch register " + word +
                       " of no bank the ruleset gives, or with no number";
            }
            argument.kind = PSEUDO_SCRATCH;
            argument.slot = bank;
            // five digits at most, which fits in 32 bits
            argument.number = (unsigned int)strtoul(digits.c_str(), NULL, 10);
        }
        written.arguments.push_back(argument);
    }
    construct->lines.push_back(written);
    return std::string();
}
