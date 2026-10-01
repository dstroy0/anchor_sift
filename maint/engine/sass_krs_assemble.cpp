// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Every form sass.krs writes, assembled against the part's machine file, with no device and no toolchain.
//
//     sass_krs_assemble [ruleset] [machine file]
//
// This is the check that was missing when sass.krs came to name three comparisons no listing ever held. The ruleset
// was read against its schema, and each form's text was checked against the listing it came from, and neither of
// those says whether the assembler can turn that text into the sixteen bytes the part runs. A form this refuses is a
// form the lane cannot be emitted through, whatever the ruleset says.
//
// A parameter's kind is not guessed from its name, because one name is two things in two forms: `left` is a register
// in word_and and a predicate in predicate_xor, `value` a register in test_nonzero and a number in word_set. Each
// form is written instead with every assignment of kinds to its parameters, register first, and holds where any one
// of them assembles. A form that assembles under no assignment is the gap, and the assignment that worked is what
// the form's parameters are.
//
// The forms and their parameters are read from the ruleset's own lines, since the schema keeps only how many
// parameters a form takes. A form the ruleset leaves empty, and a form whose text is a label or a note and carries
// no instruction, are each counted apart: neither is a failure here.
// the cubin writer is C and its headers carry no guard of their own: the linkage is named here
extern "C"
{
#include "sass_assemble.h"
#include "sass_machine.h"
}

#include "sass_target.h"
#include "target.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

// the most parameters a form is written every way of: past this it is written with registers alone, since three to
// the power of the parameters is the assignments tried and the resident's form takes twenty-four
#define KRS_PARAMETERS_SEARCHED 6u

// what one parameter is given, in the order they are tried
enum KrsKind
{
    KRS_REGISTER = 0,
    KRS_PREDICATE = 1,
    KRS_NUMBER = 2,
    KRS_KINDS = 3
};

// a scratch register of each bank, numbered where no argument written here reaches
static std::string krs_scratch(const std::string &bank)
{
    static unsigned int temporaries;
    static unsigned int wides;
    static unsigned int predicates;
    if (bank == "temporary")
    {
        temporaries += 1u;
        return "R" + std::to_string(100u + (temporaries % 8u));
    }
    if (bank == "wide")
    {
        wides += 1u;
        return "R" + std::to_string(120u + (2u * (wides % 4u)));
    }
    if (bank == "predicate")
    {
        predicates += 1u;
        return "P" + std::to_string(predicates % 3u);
    }
    return std::string();
}

// the argument at `place`, of the kind `kind`. A 64-bit form takes registers of an even number, since sass.krs
// writes the pair's second as .hi and a pair begins on an even register
static std::string krs_argument(unsigned int kind, unsigned int place, int wide)
{
    if (kind == KRS_PREDICATE)
    {
        return "P" + std::to_string(place % 3u);
    }
    if (kind == KRS_NUMBER)
    {
        return std::to_string(1u + place);
    }
    return "R" + std::to_string(wide ? (2u * (1u + place)) : (1u + place));
}

// one form of the ruleset: its name, its parameters in order, and whether the ruleset writes anything for it
struct KrsForm
{
    std::string name;
    std::vector<std::string> parameters;
    int empty;
};

// the ruleset's forms read out of its own lines: `form <name> <parameter>... = <text>` and the head of a construct,
// `construct <name> <parameter>...`
static std::vector<KrsForm> krs_forms(const char *path)
{
    std::vector<KrsForm> forms;
    std::ifstream file(path);
    std::string line;
    while (std::getline(file, line))
    {
        std::istringstream words(line);
        std::string kind;
        words >> kind;
        if ((kind != "form") && (kind != "construct"))
        {
            continue;
        }
        KrsForm form;
        form.empty = 0;
        words >> form.name;
        std::string word;
        while (words >> word)
        {
            if (word == "=")
            {
                // a form whose text is empty writes nothing: its line ends at its equals
                form.empty = !(words >> word);
                break;
            }
            form.parameters.push_back(word);
        }
        forms.push_back(form);
    }
    return forms;
}

// 1 where `text` holds a line the part runs: a label, a note and a blank line are none
static int krs_has_instruction(const std::string &text)
{
    size_t at = 0u;
    while (at < text.size())
    {
        const size_t end = text.find('\n', at);
        const size_t stop = (end == std::string::npos) ? text.size() : end;
        size_t first = at;
        while ((first < stop) && ((text[first] == ' ') || (text[first] == '\t')))
        {
            first += 1u;
        }
        if ((first < stop) && (text[first] != '.') && (text[first] != '/') && (text[first] != '#') &&
            (text.find(':', first) > stop))
        {
            return 1;
        }
        at = stop + 1u;
    }
    return 0;
}

// Every label the ruleset's forms define, as one preamble. A branch names a label another form writes
// (open_error_unless branches to the one label_error_open writes), and the assembler resolves a label from the lines
// of the text it is given: a form written alone has none. Each form that carries no instruction is written with
// every number a branch here is given: whatever a branch names stands in front of it
static std::string krs_labels(const Ruleset *rules, const std::vector<KrsForm> &forms)
{
    std::string preamble;
    for (const KrsForm &form : forms)
    {
        for (unsigned int number = 1u; (form.empty == 0) && (number <= 8u); number += 1u)
        {
            std::vector<std::string> given(form.parameters.size(), std::to_string(number));
            std::string text;
            if ((ruleset_opcode(rules, form.name, given, krs_scratch, text) != 0) && !krs_has_instruction(text) &&
                (text.find(':') != std::string::npos))
            {
                preamble += text;
            }
        }
    }
    return preamble;
}

// how one form came out
enum KrsOutcome
{
    KRS_ASSEMBLED = 0,
    KRS_REFUSED = 1,
    KRS_NO_INSTRUCTION = 2,
    KRS_NOT_WRITTEN = 3
};

// form `form` written every way its parameters can be given and assembled, `wrote` the text of the assignment that
// held or of the last one tried, and `kinds` that assignment
static unsigned int krs_form_assembles(const Ruleset *rules, const SassMachine *machine, const KrsForm &form,
                                       const std::string &labels, std::string *wrote, std::string *kinds)
{
    const int wide = (form.name.find("wide") != std::string::npos) ||
                     (form.name.find("member") != std::string::npos);
    const unsigned int parameters = (unsigned int)form.parameters.size();
    unsigned int assignments = 1u;
    for (unsigned int at = 0u; (at < parameters) && (at < KRS_PARAMETERS_SEARCHED); at += 1u)
    {
        assignments *= KRS_KINDS;
    }
    unsigned int outcome = KRS_NOT_WRITTEN;
    for (unsigned int assignment = 0u; assignment < assignments; assignment += 1u)
    {
        std::vector<std::string> given;
        std::string named;
        unsigned int walk = assignment;
        for (unsigned int place = 0u; place < parameters; place += 1u)
        {
            const unsigned int kind = (place < KRS_PARAMETERS_SEARCHED) ? (walk % KRS_KINDS) : KRS_REGISTER;
            walk = (place < KRS_PARAMETERS_SEARCHED) ? (walk / KRS_KINDS) : walk;
            given.push_back(krs_argument(kind, place, wide));
            named += form.parameters[place] + "=" + given.back() + " ";
        }
        std::string text;
        if (ruleset_opcode(rules, form.name, given, krs_scratch, text) == 0)
        {
            return KRS_NOT_WRITTEN;
        }
        *wrote = text;
        *kinds = named;
        if (!krs_has_instruction(text))
        {
            return KRS_NO_INSTRUCTION;
        }
        outcome = KRS_REFUSED;
        static unsigned char code[4096];
        // the labels stand in front, each at the address the instructions begin at: a branch to one resolves
        const std::string whole = labels + text;
        if (sass_assemble_lines(machine, whole.c_str(), SASS_CONTROL_SAFE, code, sizeof(code)) != 0u)
        {
            return KRS_ASSEMBLED;
        }
    }
    return outcome;
}

int main(int count, char **arguments)
{
    const char *const ruleset = (count > 1) ? arguments[1] : "src/engine/compiler/codegen/rulesets/sass.krs";
    const char *const path = (count > 2) ? arguments[2] : "src/engine/compiler/cubin/machines/sm_86";
    static SassMachine machine;
    if (!sass_machine_read(&machine, path))
    {
        printf("the machine file %s did not read\n", path);
        return 1;
    }
    const Ruleset *const rules = sass_target().ruleset(1);
    if (rules == NULL)
    {
        return 1;
    }
    const std::vector<KrsForm> forms = krs_forms(ruleset);
    const std::string labels = krs_labels(rules, forms);
    printf("machine %s: %u forms; %s: %zu forms\n", machine.part, machine.forms, ruleset, forms.size());
    unsigned int assembled = 0u;
    unsigned int empty = 0u;
    unsigned int refused = 0u;
    unsigned int quiet = 0u;
    for (const KrsForm &form : forms)
    {
        if (form.empty != 0)
        {
            empty += 1u;
            continue;
        }
        std::string wrote;
        std::string kinds;
        const unsigned int outcome = krs_form_assembles(rules, &machine, form, labels, &wrote, &kinds);
        if (outcome == KRS_ASSEMBLED)
        {
            assembled += 1u;
        }
        else if (outcome == KRS_NO_INSTRUCTION)
        {
            quiet += 1u;
        }
        else
        {
            refused += 1u;
            printf("  %s refused, its last writing %s:\n%s", form.name.c_str(),
                   (outcome == KRS_NOT_WRITTEN) ? "not written" : "", wrote.c_str());
        }
    }
    printf("sass.krs: %u forms assembled, %u refused, %u carry no instruction, %u left empty\n", assembled, refused,
           quiet, empty);
    return (refused == 0u) ? 0 : 1;
}
