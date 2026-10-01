// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The construction set of the register lane's VHDL on a part, measured by the machine (engine_table.md item 11(f)):
// each form of vhdl.krs written alone through the ruleset (ruleset_opcode) into a clocked entity whose ports give
// its registers and whose outputs take them, synthesized by GHDL and Yosys, and its cost the longest path from the
// ports to the registers in Yosys's generic cells (ltp -noff). A register parameter is tried as a word and as a wide
// word until GHDL analyzes the form; a predicate is a boolean and a count or an offset the integer 7. A form that
// names what no form alone holds (the lane's opening and close, its states, its memory) is not measured, and costs
// what the lane's schedule model gives a form it does not name. The set is written as a krep KCS file and read back
// whole, and the file is removed where the two differ.
#include "crc.h"
#include "krep.h"
#include "vhdl_target.h"
#include "yosys_script.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

// a form as vhdl.krs names it: its name and its parameters' names
struct ConstructionForm
{
    std::string name;
    std::vector<std::string> parameters;
};

// the forms vhdl.krs gives, in its order, read from its lines `form <name> <parameter>... = <text>`
static std::vector<ConstructionForm> construction_forms(const std::string &path)
{
    std::vector<ConstructionForm> forms;
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return forms;
    }
    std::string text;
    char block[4096];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        text.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    size_t at = 0u;
    while (at < text.size())
    {
        const size_t found = text.find('\n', at);
        const size_t end = (found == std::string::npos) ? text.size() : found;
        const std::string line = text.substr(at, end - at);
        at = end + 1u;
        const size_t equals = line.find('=');
        if ((line.compare(0u, 5u, "form ") != 0) || (equals == std::string::npos))
        {
            continue;
        }
        // the program resident is an entity of its own around the lane, not a form a state holds
        if (line.compare(0u, 18u, "form program_unit ") == 0)
        {
            continue;
        }
        ConstructionForm form;
        size_t word = 5u;
        while (word < equals)
        {
            const size_t space = line.find(' ', word);
            const size_t stop = ((space == std::string::npos) || (space > equals)) ? equals : space;
            if (stop > word)
            {
                if (form.name.empty())
                {
                    form.name = line.substr(word, stop - word);
                }
                else
                {
                    form.parameters.push_back(line.substr(word, stop - word));
                }
            }
            word = stop + 1u;
        }
        forms.push_back(form);
    }
    return forms;
}

// what a parameter is bound to: a predicate a boolean, a count or an offset an integer, and a register a word or a
// wide word
enum ConstructionKind
{
    CONSTRUCTION_BOOLEAN = 0,
    CONSTRUCTION_INTEGER = 1,
    CONSTRUCTION_REGISTER = 2
};

static ConstructionKind construction_kind(const std::string &parameter)
{
    static const char *const predicates[] = {"where", "also"};
    static const char *const integers[] = {"bits", "offset", "at", "count", "state", "error"};
    for (const char *const name : predicates)
    {
        if (parameter == name)
        {
            return CONSTRUCTION_BOOLEAN;
        }
    }
    for (const char *const name : integers)
    {
        if (parameter == name)
        {
            return CONSTRUCTION_INTEGER;
        }
    }
    return CONSTRUCTION_REGISTER;
}

static int construction_write(const std::string &path, const std::string &text)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(text.data(), 1u, text.size(), file) == text.size();
    return (fclose(file) == 0) && written;
}

// the number after `label` on the first line of `path` that holds it, and 1 where a line holds it
static int construction_after(const std::string &path, const char *label, unsigned long long *number)
{
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return 0;
    }
    char line[1024];
    int found = 0;
    while ((found == 0) && (fgets(line, sizeof(line), file) != NULL))
    {
        const char *const at = strstr(line, label);
        found = at != NULL;
        *number = found ? strtoull(at + strlen(label), NULL, 10) : *number;
    }
    fclose(file);
    return found;
}

// the form alone in a clocked entity: each parameter a variable given by a port at the clock and taken by a port
// after the form; the package the lane's opening holds comes first
static std::string construction_entity(const std::string &package, const std::string &form,
                                       const std::vector<std::string> &types)
{
    std::string text = package + "\nlibrary ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
                                 "use work.cycle_program.all;\n\nentity form_alone is\n    port (clock : in std_ulogic";
    for (size_t at = 0u; at < types.size(); at += 1u)
    {
        if (!types[at].empty())
        {
            const std::string name = "x" + std::to_string(at);
            text +=
                ";\n          " + name + "_in : in " + types[at] + ";\n          " + name + "_out : out " + types[at];
        }
    }
    text += ";\n          carry_in : in natural range 0 to 1;\n          carry_out : out natural range 0 to 1);\n"
            "end entity form_alone;\n\narchitecture measured of form_alone is\nbegin\n    alone : process (clock)\n";
    for (size_t at = 0u; at < types.size(); at += 1u)
    {
        text +=
            types[at].empty() ? std::string() : ("        variable x" + std::to_string(at) + " : " + types[at] + ";\n");
    }
    text += "        variable carry : natural range 0 to 1;\n        variable total : unsigned(32 downto 0);\n"
            "        variable product : unsigned(63 downto 0);\n    begin\n        if rising_edge(clock) then\n";
    for (size_t at = 0u; at < types.size(); at += 1u)
    {
        text += types[at].empty() ? std::string()
                                  : ("            x" + std::to_string(at) + " := x" + std::to_string(at) + "_in;\n");
    }
    text += "            carry := carry_in;\n" + form;
    for (size_t at = 0u; at < types.size(); at += 1u)
    {
        text += types[at].empty() ? std::string()
                                  : ("            x" + std::to_string(at) + "_out <= x" + std::to_string(at) + ";\n");
    }
    text += "            carry_out <= carry;\n        end if;\n    end process alone;\nend architecture measured;\n";
    return text;
}

// the form's cost measured in `work`: each binding of its registers to words and wide words tried until GHDL analyzes
// the form alone, which is then synthesized; 1 and the cost where one binding holds
static int construction_measure(const Ruleset *rules, const std::string &package, const std::string &work,
                                const ConstructionForm &form, unsigned long long *cost)
{
    const auto none = [](const std::string &bank) {
        (void)bank;
        return std::string();
    };
    // a form's registers are few: the words and wide words they can be bound as are few
    const unsigned int bindings = 1u << (unsigned int)form.parameters.size();
    for (unsigned int binding = 0u; binding < bindings; binding += 1u)
    {
        std::vector<std::string> arguments;
        std::vector<std::string> types;
        int skipped = 0;
        for (size_t at = 0u; at < form.parameters.size(); at += 1u)
        {
            const ConstructionKind kind = construction_kind(form.parameters[at]);
            const int wide = ((binding >> at) & 1u) != 0u;
            // a binding that makes a predicate or an integer wide is the binding before it
            skipped = skipped || (wide && (kind != CONSTRUCTION_REGISTER));
            arguments.push_back((kind == CONSTRUCTION_INTEGER) ? std::string("7") : ("x" + std::to_string(at)));
            types.push_back((kind == CONSTRUCTION_INTEGER)   ? std::string()
                            : (kind == CONSTRUCTION_BOOLEAN) ? std::string("boolean")
                            : wide                           ? std::string("cycle_wide")
                                                             : std::string("cycle_word"));
        }
        std::string text;
        if (skipped || !ruleset_opcode(rules, form.name, arguments, none, text))
        {
            continue;
        }
        if (!construction_write(work + "/alone.vhd", construction_entity(package, text, types)))
        {
            return 0;
        }
        const std::string analyze =
            "cd '" + work + "' && rm -f work-obj08.cf && ghdl -a --std=08 alone.vhd > analyze.log 2>&1";
        if (system(analyze.c_str()) != 0)
        {
            continue;
        }
        const std::string script = yosys_script().synthesis("alone.v", "form_alone", std::string());
        const std::string synthesize =
            "cd '" + work +
            "' && ghdl --synth --std=08 --out=verilog alone.vhd -e form_alone > alone.v 2> synth.log && "
            "yosys -s alone.ys > yosys.log 2>&1";
        *cost = 0ull;
        return !script.empty() && construction_write(work + "/alone.ys", script) && (system(synthesize.c_str()) == 0) &&
               construction_after(work + "/yosys.log", "(length=", cost);
    }
    return 0;
}

int main(int argc, char **argv)
{
    // each line reaches the log as it is written, where stdout is a file: each form is synthesized alone
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc != 4)
    {
        fprintf(stderr, "usage: vhdl_construction_set <work folder> <vhdl.krs> <out .kcs>\n");
        return 2;
    }
    const std::string work(argv[1]);
    const Ruleset *const rules = vhdl_target().ruleset(1);
    const std::vector<ConstructionForm> forms = construction_forms(argv[2]);
    std::string package;
    const auto none = [](const std::string &bank) {
        (void)bank;
        return std::string();
    };
    const std::string package_end = "end package body cycle_program;\n";
    if ((rules == NULL) || forms.empty() || !ruleset_opcode(rules, "lane_open", {}, none, package) ||
        (package.find(package_end) == std::string::npos))
    {
        fprintf(stderr, "  vhdl construction set: the ruleset or its package could not be read\n");
        return 1;
    }
    package = package.substr(0u, package.find(package_end) + package_end.size());
    std::vector<unsigned long long> costs;
    std::string names;
    unsigned int unmeasured = 0u;
    for (const ConstructionForm &form : forms)
    {
        unsigned long long cost = 0ull;
        if (construction_measure(rules, package, work, form, &cost) == 0)
        {
            unmeasured += 1u;
            continue;
        }
        printf("  %-24s %llu\n", form.name.c_str(), cost);
        costs.push_back(cost);
        names += form.name;
        names.push_back('\0');
    }
    // the names packed eight bytes a word, least significant first, the last word padded with zeros
    const size_t name_words = (names.size() + 7u) / 8u;
    std::vector<unsigned long long> words(costs);
    words.resize(costs.size() + name_words, 0ull);
    for (size_t at = 0u; at < names.size(); at += 1u)
    {
        words[costs.size() + (at / 8u)] |= (unsigned long long)(unsigned char)names[at] << (8u * (at % 8u));
    }
    const KrepFormTable table = {costs.size(), name_words, crc_words(CRC_TABLE, words.data(), words.size()),
                                 words.data()};
    EngineError error;
    memset(&error, 0, sizeof(error));
    KrepFormTable back;
    const int written = krep_forms_write(argv[3], &table, &error);
    const int read = written && krep_forms_read(argv[3], &back, &error);
    const int same = read && (back.forms == table.forms) && (back.name_words == table.name_words) &&
                     (back.crc == table.crc) &&
                     (memcmp(back.words, table.words, words.size() * sizeof(unsigned long long)) == 0);
    if (read)
    {
        krep_forms_release(&back);
    }
    if (!same)
    {
        remove(argv[3]);
    }
    printf("  vhdl construction set: %zu forms measured, %u not measured, %s %s\n", costs.size(), unmeasured,
           same ? "written and read back whole to" : "NOT written to", argv[3]);
    return same ? 0 : 1;
}
