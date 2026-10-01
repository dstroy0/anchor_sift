// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// target_rulesets.cu: rulesets read, loaded and written
#include "target_internal.h"

// the ruleset at `path` read whole into `rules` against its schema: 1 where its first line is krs 1, every entry holds,
// and every bank, fixed register and form the code generator names is given with the ruleset's name, toolchain and
// header, else 0 with the reason in rules->errored. A line that begins with # is a comment, and a blank line is nothing
static int ruleset_read(Ruleset *rules, const std::string &path)
{
    std::string ruleset_text;
    if (ruleset_file(rules, path, &ruleset_text) == 0)
    {
        return 0;
    }
    // the file read by the core (ruleset_core.h) the device runs as well
    RulesetFlat flat;
    ruleset_flat_schema(rules->schema, &flat);
    RulesetCoreRead read{};
    read.schema = flat.schema;
    read.text = (const unsigned char *)ruleset_text.data();
    // ruleset_file holds a ruleset below RULESET_FILE_MAX letters
    read.text_length = (unsigned int)ruleset_text.size();
    ruleset_capacities(read.text_length, &read);
    RulesetMemory memory;
    ruleset_memory_size(&memory, &read);
    ruleset_core_read(&read);
    ruleset_keep(&read, ruleset_text, rules);
    return rules->error.empty() ? 1 : 0;
}

// a ruleset read once a process into `rules` from its schema's file; NULL where it errors. A ruleset naming
// another toolchain or header than its code generator's path builds with errors with the rest
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
        rules->error =
            "its path builds with " + std::string(schema->toolchain) + " and takes its header from " + schema->header;
    }
    if ((report != 0) && (rules->ready != 0))
    {
        fprintf(stderr, "  cycle: the ruleset %s read from %s\n", rules->name.c_str(), rules->path.c_str());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: the ruleset at %s errors (%s)\n", rules->path.c_str(), rules->error.c_str());
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
        // an err is the operation being an error on this language: it writes nothing and breaks what it was written
        // into. A program that needs it is refused. It is not written with a hole in it. A nop writes nothing and
        // the writing goes on
        if (rules->form_given[name] == (unsigned char)RULESET_CORE_GIVEN_ERR)
        {
            *broken = 1;
            return;
        }
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

void ruleset_scratch(const Ruleset *rules, const unsigned int *banks, std::vector<unsigned int> *scratch)
{
    // laid out by the core (ruleset_core_scratch.h) the device runs as well
    const unsigned int forms = rules->schema->form_count;
    RulesetFlatConstructs flat;
    ruleset_flat_constructs(rules, &flat);
    std::vector<unsigned char> counted((size_t)forms + 1u, (unsigned char)0u);
    std::vector<RulesetCoreFrame> frames((size_t)forms + 1u, RulesetCoreFrame{});
    std::vector<unsigned int> taken_bank(flat.arguments.size(), 0u);
    std::vector<unsigned int> taken_number(flat.arguments.size(), 0u);
    scratch->assign((4u * (size_t)forms) + 1u, 0u);
    RulesetCoreScratch laid_out{};
    laid_out.constructs = flat.constructs.data();
    laid_out.lines = flat.lines.data();
    laid_out.arguments = flat.arguments.data();
    laid_out.form_count = forms;
    laid_out.banks[0] = banks[0];
    laid_out.banks[1] = banks[1];
    laid_out.banks[2] = banks[2];
    laid_out.scratch = scratch->data();
    laid_out.counted = counted.data();
    laid_out.frames = frames.data();
    laid_out.taken_bank = taken_bank.data();
    laid_out.taken_number = taken_number.data();
    ruleset_core_scratch(&laid_out);
    scratch->resize(4u * (size_t)forms);
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
