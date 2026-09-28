// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// target_rulesets.cu: rulesets read, loaded and written
#include "target_internal.h"

// the ruleset at `path` read whole into `rules` against its schema: 1 where its first line is krs 1, every entry holds,
// and every bank, fixed register and form the code generator names is given with the ruleset's name, toolchain and
// header, else 0 with the reason in rules->refused. A line that begins with # is a comment, and a blank line is nothing
static int ruleset_read(Ruleset *rules, const std::string &path)
{
    const RulesetSchema *const schema = rules->schema;
    rules->path = path;
    rules->banks.assign(schema->bank_count, InstrTemplate());
    rules->fixed.assign(schema->fixed_count, std::string());
    rules->forms.assign(schema->form_count, InstrTemplate());
    rules->constructs.assign(schema->form_count, Pseudo());
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
    std::string ruleset_text;
    char block[4096];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        ruleset_text.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    unsigned int number = 0u;
    size_t at = 0u;
    while ((at < ruleset_text.size()) && rules->refused.empty())
    {
        const size_t found = ruleset_text.find('\n', at);
        const size_t end = (found == std::string::npos) ? ruleset_text.size() : found;
        // a checkout that ends its lines with a carriage return as well leaves each line as it was written
        const size_t kept = ((end > at) && (ruleset_text[end - 1u] == '\r')) ? (end - 1u) : end;
        const std::string line = ruleset_text.substr(at, kept - at);
        number += 1u;
        at = end + 1u;
        const size_t space = line.find(' ');
        const int constructing = rules->building != schema->form_count;
        const std::string why =
            (number == 1u)
                ? ((line == "krs 1") ? std::string() : std::string("it is not krs 1"))
                : ((line.empty() || (line[0] == '#'))
                       ? std::string()
                       : (constructing
                              ? ruleset_pseudo_line(rules, line)
                              : ruleset_entry(rules, line.substr(0u, space),
                                              (space == std::string::npos) ? std::string() : line.substr(space + 1u))));
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
// another toolchain or header than its code generator's path builds with is refused with the rest
static const Ruleset *ruleset_load(Ruleset *rules, const RulesetSchema *schema, int report)
{
    if (rules->tried != 0)
    {
        return (rules->ready != 0) ? rules : NULL;
    }
    rules->tried = 1;
    rules->schema = schema;
    rules->ready = ruleset_read(rules, ruleset_folder() + "/" + schema->file);
    if ((rules->ready != 0) && ((rules->toolchain != schema->toolchain) || (rules->header != schema->header)))
    {
        rules->ready = 0;
        rules->refused =
            "its path builds with " + std::string(schema->toolchain) + " and takes its header from " + schema->header;
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
Target::Target(const RulesetSchema *schema) : rules(new Ruleset())
{
    rules->schema = schema;
}

Target::~Target()
{
    delete rules;
}

const Ruleset *Target::ruleset(int report)
{
    return ruleset_load(rules, rules->schema, report);
}

const Ruleset *Target::ready(void) const
{
    return (rules->ready != 0) ? rules : NULL;
}

// form `name` of `rules` appended to `text`, `argument` holding as many arguments as it takes, in the order of its
// parameters: its text cut at them, or where the ruleset gives it as a construct, each of the construct's lines
// written the same way, a scratch register taken of `scratch` the first time a writing names it. `broken` set where a
// scratch register cannot be taken
static void ruleset_opcode_text(const Ruleset *rules, std::string &text, unsigned int name, const std::string *argument,
                                const ScratchRegisters &scratch, int *broken)
{
    const Pseudo *const construct = &rules->constructs[name];
    if (construct->lines.empty())
    {
        const InstrTemplate *const form = &rules->forms[name];
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
    for (const PseudoLine &line : construct->lines)
    {
        std::vector<std::string> arguments;
        for (const PseudoOperand &given : line.arguments)
        {
            size_t found = scratch_taken.size();
            for (size_t at = 0u; (given.kind == PSEUDO_SCRATCH) && (at < scratch_taken.size()); at += 1u)
            {
                found = ((scratch_bank[at] == given.slot) && (scratch_number[at] == given.number)) ? at : found;
            }
            if ((given.kind == PSEUDO_SCRATCH) && (found == scratch_taken.size()))
            {
                const std::string taken = scratch(given.slot);
                *broken = *broken || taken.empty();
                scratch_bank.push_back(given.slot);
                scratch_number.push_back(given.number);
                scratch_taken.push_back(taken);
            }
            arguments.push_back((given.kind == PSEUDO_TEXT)        ? given.text
                                : (given.kind == PSEUDO_PARAMETER) ? argument[given.slot]
                                                                   : scratch_taken[found]);
        }
        ruleset_opcode_text(rules, text, line.form, arguments.data(), scratch, broken);
    }
}

// the scratch a writer with no registers of its own to give answers: none
static std::string ruleset_no_scratch(unsigned int bank)
{
    (void)bank;
    return std::string();
}

// form `name` of `rules` appended to `text`, its arguments in the order of its parameters, a construct's scratch taken
// of `scratch`; `broken` set, and nothing written, where they are not as many as the form takes
void ruleset_write_taking(const Ruleset *rules, std::string &text, unsigned int name,
                          std::initializer_list<std::string> arguments, const ScratchRegisters &scratch, int *broken)
{
    if (arguments.size() != rules->schema->forms[name].parameters)
    {
        *broken = 1;
        return;
    }
    ruleset_opcode_text(rules, text, name, arguments.begin(), scratch, broken);
}

// the same, by a writer with no scratch to give: a construct that takes scratch breaks what it is written into
void ruleset_write(const Ruleset *rules, std::string &text, unsigned int name,
                   std::initializer_list<std::string> arguments, int *broken)
{
    ruleset_write_taking(rules, text, name, arguments, ScratchRegisters(ruleset_no_scratch), broken);
}

void ruleset_write_list(const Ruleset *rules, std::string &text, unsigned int name,
                        const std::vector<std::string> &arguments, const ScratchRegisters &scratch, int *broken)
{
    if (arguments.size() != rules->schema->forms[name].parameters)
    {
        *broken = 1;
        return;
    }
    ruleset_opcode_text(rules, text, name, arguments.data(), scratch, broken);
}

// the scratch form `name` takes in one writing, laid out into its four words of `scratch` once and marked in `counted`:
// each scratch register its lines name, once, and what each form its lines write takes, which a construct given before
// it in the file has laid out, and the recursion ends
static void ruleset_scratch_of(const Ruleset *rules, const unsigned int *banks, unsigned int name,
                               std::vector<unsigned int> *scratch, std::vector<unsigned char> *counted)
{
    if ((*counted)[name] != 0u)
    {
        return;
    }
    (*counted)[name] = 1u;
    std::vector<unsigned int> taken_bank;
    std::vector<unsigned int> taken_number;
    for (const PseudoLine &line : rules->constructs[name].lines)
    {
        for (const PseudoOperand &given : line.arguments)
        {
            int found = 0;
            for (size_t at = 0u; (given.kind == PSEUDO_SCRATCH) && (at < taken_bank.size()); at += 1u)
            {
                found = found || ((taken_bank[at] == given.slot) && (taken_number[at] == given.number));
            }
            if ((given.kind != PSEUDO_SCRATCH) || (found != 0))
            {
                continue;
            }
            taken_bank.push_back(given.slot);
            taken_number.push_back(given.number);
            const unsigned int bank_index =
                (given.slot == banks[0]) ? 0u : ((given.slot == banks[1]) ? 1u : ((given.slot == banks[2]) ? 2u : 3u));
            (*scratch)[(4u * name) + bank_index] =
                (bank_index == 3u) ? 1u : ((*scratch)[(4u * name) + bank_index] + 1u);
        }
        ruleset_scratch_of(rules, banks, line.form, scratch, counted);
        for (unsigned int bank_index = 0u; bank_index < 3u; bank_index += 1u)
        {
            (*scratch)[(4u * name) + bank_index] += (*scratch)[(4u * line.form) + bank_index];
        }
        (*scratch)[(4u * name) + 3u] |= (*scratch)[(4u * line.form) + 3u];
    }
}

void ruleset_scratch(const Ruleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch)
{
    const unsigned int forms = rules->schema->form_count;
    std::vector<unsigned char> counted(forms, (unsigned char)0u);
    scratch->assign(4u * (size_t)forms, 0u);
    for (unsigned int name = 0u; name < forms; name += 1u)
    {
        ruleset_scratch_of(rules, banks, name, scratch, &counted);
    }
}

// a form written by the name its .krs file gives it, for a reader outside the code generator (target.h), a construct's
// scratch taken of `scratch` by its bank's name
int ruleset_opcode(const Ruleset *rules, const std::string &name, const std::vector<std::string> &arguments,
                   const std::function<std::string(const std::string &bank)> &scratch, std::string &text)
{
    const RulesetSchema *const schema = rules->schema;
    const unsigned int named = ruleset_find(schema->forms, schema->form_count, name);
    if ((named == schema->form_count) || (arguments.size() != schema->forms[named].parameters))
    {
        return 0;
    }
    int broken = 0;
    const ScratchRegisters by_place = [&](unsigned int bank) { return scratch(std::string(schema->banks[bank].text)); };
    ruleset_opcode_text(rules, text, named, arguments.data(), by_place, &broken);
    return (broken == 0) ? 1 : 0;
}

std::string ruleset_register(const Ruleset *rules, const std::string &bank, unsigned int number)
{
    const RulesetSchema *const schema = rules->schema;
    const unsigned int named = ruleset_find(schema->banks, schema->bank_count, bank);
    if (named == schema->bank_count)
    {
        return std::string();
    }
    // a bank's written form takes one parameter, the register's number, in every slot it is cut at
    const InstrTemplate *const form = &rules->banks[named];
    std::string written = form->pieces[0];
    for (size_t at = 0u; at < form->slots.size(); at += 1u)
    {
        written += std::to_string(number);
        written += form->pieces[at + 1u];
    }
    return written;
}

std::string ruleset_physreg(const Ruleset *rules, const std::string &name)
{
    const RulesetSchema *const schema = rules->schema;
    const unsigned int named = ruleset_find(schema->fixed, schema->fixed_count, name);
    return (named == schema->fixed_count) ? std::string() : rules->fixed[named];
}
