// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// monolith_forms.cpp: the forms a lane is written in, each asked of NVIDIA's compiler in one program, and each form of
// sass.krs and ptx.krs read back off what the compiler wrote for it.
//
//     monolith_forms write <c.krs> <monolith.cu> <questions>
//     monolith_forms read <questions> <listing> <ptx> <sass.krs> <ptx.krs> <machine> <record> [apply]
//
// The first decides the lanes of the record programs the host oracle runs (record_programs.h) and gathers every form
// they decide with the banks its arguments come from. A form decided with the same banks is one question. Each
// question is a block of the monolith between two tags, its text the form's own text in c.krs, the meaning every
// target's form shares: every argument the form reads is loaded from `in` and every one it writes stored to `out`,
// each through a volatile access, and nothing a block does crosses a tag. The forms that carry a chain's carry are
// asked in the runs a lane decides them in, a tag between each, the carry held between them. The fixed registers a
// form's text names are loaded the same way.
//
// The second reads the compiler's listing and its PTX a block at a time. A register loaded from `in` is the argument
// it was loaded for and a register stored to `out` is the argument stored; a predicate set from a loaded word, or a
// word selected from a predicate to be stored, is the predicate. What is left in the block is the form, written with
// each register named by its argument. A register or predicate that is no argument is scratch: the first word is
// R254 and the first predicate P6, sass.krs's own, and a block needing more is reported and not written. A number
// argument is named where the number stands once. Each form read is held beside the ruleset's own and written to the
// record whole, and with apply each form every question of which reads whole and alike is written into the ruleset in
// place (read_adopted says what whole is).
#include "../../../c/engine/analysis/cycle/record_programs.h"

// the cubin writer is C and its headers carry no guard of their own: the linkage is named here
extern "C"
{
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"
}

#include "c_target.h"
#include "machine_ir_types.h"
#include "target.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

// ENGINE_IMAGE_BASE reads the ELF header the linker marks with __ehdr_start (engine_config_platform.h), and this
// tool is linked as a PE, where there is none. Nothing here asks for the image base: it is named so the link holds
#if defined(__GNUC__) && !defined(__ELF__)
extern "C" const char __ehdr_start = 0;
#endif

// the tags a question's loads and stores stand behind, past its own tag, which the form's region stands behind
#define MONOLITH_FORMS_LOADS 0x4000u
#define MONOLITH_FORMS_STORES 0x8000u

#define FORM_NAME(name_, text_, parameters_) text_,
static const char *const s_form_names[OPCODE_COUNT] = {OPCODES(FORM_NAME)};
#undef FORM_NAME
#define BANK_NAME(name_, text_) text_,
static const char *const s_bank_names[REGCLASS_COUNT] = {REGCLASSES(BANK_NAME)};
#undef BANK_NAME
#define FIXED_NAME(name_, text_) text_,
static const char *const s_fixed_names[PHYSREG_COUNT] = {PHYSREGS(FIXED_NAME)};
#undef FIXED_NAME

// a form of a ruleset: its parameters and its text, the escapes read
struct KrsForm
{
    std::vector<std::string> parameters;
    std::string text;
};

// a ruleset as this reads it: its forms, its banks' texts and its fixed registers' texts
struct Krs
{
    std::map<std::string, KrsForm> forms;
    std::map<std::string, std::string> banks;
    std::map<std::string, std::string> fixed;
};

// a form's text with \t, \n and \\ read
static std::string krs_unescape(const std::string &text)
{
    std::string read;
    for (size_t at = 0u; at < text.size(); at += 1u)
    {
        if ((text[at] == '\\') && ((at + 1u) < text.size()))
        {
            const char next = text[at + 1u];
            read += (next == 't') ? '\t' : ((next == 'n') ? '\n' : next);
            at += 1u;
            continue;
        }
        read += text[at];
    }
    return read;
}

static std::vector<std::string> words_split(const std::string &text)
{
    std::vector<std::string> words;
    size_t at = 0u;
    while (at < text.size())
    {
        while ((at < text.size()) && (text[at] == ' '))
        {
            at += 1u;
        }
        const size_t end = text.find(' ', at);
        const size_t stop = (end == std::string::npos) ? text.size() : end;
        if (stop > at)
        {
            words.push_back(text.substr(at, stop - at));
        }
        at = stop;
    }
    return words;
}

// the ruleset at `path` read: 1, or 0 where it did not read
static int krs_read(const char *path, Krs *krs)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    std::string line;
    int character = fgetc(file);
    while (character != EOF)
    {
        line.clear();
        while ((character != EOF) && (character != '\n'))
        {
            if (character != '\r')
            {
                line += (char)character;
            }
            character = fgetc(file);
        }
        character = fgetc(file);
        const size_t equals = line.find(" = ");
        if (equals == std::string::npos)
        {
            continue;
        }
        const std::vector<std::string> head = words_split(line.substr(0u, equals));
        const std::string text = line.substr(equals + 3u);
        if ((head.size() >= 2u) && (head[0] == "form"))
        {
            KrsForm form;
            form.parameters.assign(head.begin() + 2, head.end());
            form.text = krs_unescape(text);
            krs->forms[head[1]] = form;
        }
        else if ((head.size() == 2u) && (head[0] == "bank"))
        {
            krs->banks[head[1]] = text;
        }
        else if ((head.size() == 2u) && (head[0] == "fixed"))
        {
            krs->fixed[head[1]] = text;
        }
    }
    fclose(file);
    return 1;
}

static size_t text_count(const std::string &text, const std::string &part)
{
    size_t count = 0u;
    size_t at = text.find(part);
    while (at != std::string::npos)
    {
        count += 1u;
        at = text.find(part, at + part.size());
    }
    return count;
}

static int identifier_character(char character)
{
    return ((character >= 'a') && (character <= 'z')) || ((character >= 'A') && (character <= 'Z')) ||
           ((character >= '0') && (character <= '9')) || (character == '_');
}

// 1 where `name` stands in `text` as a whole identifier
static int text_names(const std::string &text, const std::string &name)
{
    size_t at = text.find(name);
    while (at != std::string::npos)
    {
        const int before = (at == 0u) || !identifier_character(text[at - 1u]);
        const int after = ((at + name.size()) >= text.size()) || !identifier_character(text[at + name.size()]);
        if (before && after)
        {
            return 1;
        }
        at = text.find(name, at + 1u);
    }
    return 0;
}

// `text` with every `{name}` replaced by `put`
static std::string text_fill(const std::string &text, const std::string &name, const std::string &put)
{
    const std::string brace = "{" + name + "}";
    std::string filled;
    size_t at = 0u;
    size_t found = text.find(brace);
    while (found != std::string::npos)
    {
        filled += text.substr(at, found - at) + put;
        at = found + brace.size();
        found = text.find(brace, at);
    }
    return filled + text.substr(at);
}

// ---------------------------------------------------------------------------------------------------------------
// the C types the lane's registers hold, read off c.krs

// The C type each variable c.krs declares in a list of its own, `type a, b, c;`, by the variable's name
static std::map<std::string, std::string> c_declared(const Krs &c)
{
    std::map<std::string, std::string> types;
    for (const auto &entry : c.forms)
    {
        const std::string &text = entry.second.text;
        size_t at = 0u;
        while (at < text.size())
        {
            const size_t end = text.find('\n', at);
            const size_t stop = (end == std::string::npos) ? text.size() : end;
            std::string line = text.substr(at, stop - at);
            at = stop + 1u;
            const size_t first = line.find_first_not_of(' ');
            if ((first == std::string::npos) || (line.find('[') != std::string::npos) ||
                (line.find('(') != std::string::npos) || (line.find('=') != std::string::npos) || (line.back() != ';'))
            {
                continue;
            }
            line = line.substr(first, line.size() - first - 1u);
            const size_t space = line.find(' ');
            if (space == std::string::npos)
            {
                continue;
            }
            const std::string type = line.substr(0u, space);
            std::string names = line.substr(space + 1u);
            size_t from = 0u;
            while (from < names.size())
            {
                const size_t comma = names.find(',', from);
                const size_t until = (comma == std::string::npos) ? names.size() : comma;
                std::string name = names.substr(from, until - from);
                name.erase(0u, name.find_first_not_of(' '));
                name.erase(name.find_last_not_of(' ') + 1u);
                if (!name.empty() && (types.find(name) == types.end()))
                {
                    types[name] = type;
                }
                from = until + 1u;
            }
        }
    }
    return types;
}

// the C type a bank's registers hold: the type its text casts to, or the type its name is declared with as an array
static std::string c_bank_type(const Krs &c, const std::string &bank)
{
    const auto found = c.banks.find(bank);
    if (found == c.banks.end())
    {
        return std::string();
    }
    const std::string &text = found->second;
    if (text.compare(0u, 2u, "((") == 0)
    {
        const size_t space = text.find(' ', 2u);
        return (space == std::string::npos) ? std::string() : text.substr(2u, space - 2u);
    }
    const size_t bracket = text.find('[');
    if (bracket == std::string::npos)
    {
        return std::string();
    }
    const std::string array = text.substr(0u, bracket);
    for (const auto &entry : c.forms)
    {
        const std::string &form = entry.second.text;
        const size_t at = form.find(" " + array + "[");
        if (at == std::string::npos)
        {
            continue;
        }
        size_t begin = form.rfind(' ', at - 1u);
        begin = (begin == std::string::npos) ? 0u : (begin + 1u);
        return form.substr(begin, at - begin);
    }
    return std::string();
}

// ---------------------------------------------------------------------------------------------------------------
// the questions

// one argument of a decided form, as a question puts it: a register of a bank, a fixed register or a number
struct Argument
{
    unsigned int kind;
    unsigned int which;
    unsigned int number;
};

// one form a lane decides: its place in the schema and its arguments
struct Asked
{
    unsigned int form;
    std::vector<Argument> arguments;
};

// what the arguments of an asked form come from, which makes two of them one question
static std::string asked_key(const Asked &asked)
{
    std::string key = s_form_names[asked.form];
    for (const Argument &argument : asked.arguments)
    {
        char part[32];
        if (argument.kind == OPERAND_REGISTER)
        {
            snprintf(part, sizeof(part), " r%u", argument.which);
        }
        else if (argument.kind == OPERAND_PHYSREG)
        {
            snprintf(part, sizeof(part), " f%u", argument.which);
        }
        else
        {
            snprintf(part, sizeof(part), " n");
        }
        key += part;
    }
    return key;
}

// 1 where c.krs's text for the form writes the chain's carry, and through `reads` whether it reads it
static int form_carries(const Krs &c, const std::string &name, int *reads)
{
    const auto found = c.forms.find(name);
    const std::string text = (found == c.forms.end()) ? std::string() : found->second.text;
    const size_t named = text_count(text, "carry");
    const size_t written = text_count(text, "&carry");
    *reads = (named > written) ? 1 : 0;
    return (written != 0u) ? 1 : 0;
}

// 1 where the form is a question: c.krs gives it a text that does something with its arguments, and not a declaration,
// a label, a note, a jump or the resident
static int form_asked(const Krs &c, const std::string &name)
{
    const auto found = c.forms.find(name);
    if ((found == c.forms.end()) || found->second.parameters.empty())
    {
        return 0;
    }
    const std::string &text = found->second.text;
    const size_t first = text.find_first_not_of(" \t\n");
    if ((first == std::string::npos) || (text.compare(first, 2u, "//") == 0) ||
        (text.find("goto") != std::string::npos) || (text.find("return") != std::string::npos) ||
        (text.find("__global__") != std::string::npos) || (text.back() != '\n') ||
        (text.find(":\n") != std::string::npos))
    {
        return 0;
    }
    for (const std::string &parameter : found->second.parameters)
    {
        if (text.find("[{" + parameter + "}]") != std::string::npos)
        {
            return 0;
        }
    }
    return 1;
}

// the questions gathered from every lane: each asked form alone, and each run of carrying forms, with the numbers
// they were asked with
struct Gathered
{
    std::vector<std::vector<Asked>> questions;
    std::set<std::string> keys;
};

static void gather_number(std::vector<Asked> &kept, const std::vector<Asked> &seen)
{
    for (size_t one = 0u; one < kept.size(); one += 1u)
    {
        for (size_t at = 0u; at < kept[one].arguments.size(); at += 1u)
        {
            Argument &held = kept[one].arguments[at];
            const unsigned int now = seen[one].arguments[at].number;
            const int number = (held.kind == OPERAND_NUMBER) || (held.kind == OPERAND_SIGNED) ||
                               ((held.kind == OPERAND_REGISTER) && (held.which == REGCLASS_IMMEDIATE));
            // a number of 0 or 1 is the likeliest to be met by a constant the compiler writes of its own
            if (number && (held.number < 2u) && (now >= 2u))
            {
                held.number = now;
            }
        }
    }
}

static void gather_add(Gathered *gathered, const std::vector<Asked> &run)
{
    if (run.empty())
    {
        return;
    }
    // a run that repeats a form asks it once
    std::vector<Asked> kept;
    for (const Asked &asked : run)
    {
        if (kept.empty() || (asked_key(kept.back()) != asked_key(asked)))
        {
            kept.push_back(asked);
        }
    }
    std::string key;
    for (const Asked &asked : kept)
    {
        key += asked_key(asked) + ";";
    }
    if (gathered->keys.insert(key).second)
    {
        gathered->questions.push_back(kept);
        return;
    }
    for (std::vector<Asked> &question : gathered->questions)
    {
        std::string held;
        for (const Asked &asked : question)
        {
            held += asked_key(asked) + ";";
        }
        if (held == key)
        {
            gather_number(question, kept);
        }
    }
}

static void gather_lane(const Krs &c, const HostProgram *program, int reuse, Gathered *gathered)
{
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        printf("  %s: not laid out\n", program->name);
        return;
    }
    std::vector<MachineInstr> items;
    unsigned int places = 0u;
    if (c_target().decided(&loaded.layout, &places, &items) == 0)
    {
        printf("  %s: the core decides no lane for it\n", program->name);
        host_free(&loaded);
        return;
    }
    std::vector<Asked> run;
    for (const MachineInstr &item : items)
    {
        if ((item.form >= OPCODE_COUNT) || !form_asked(c, s_form_names[item.form]))
        {
            continue;
        }
        Asked asked;
        asked.form = item.form;
        for (unsigned int at = 0u; at < codegen_operand_count(item.form); at += 1u)
        {
            asked.arguments.push_back({item.arguments[at].kind, item.arguments[at].which, item.arguments[at].number});
        }
        int reads = 0;
        const int writes = form_carries(c, s_form_names[item.form], &reads);
        if (!writes && !reads)
        {
            gather_add(gathered, std::vector<Asked>{asked});
            continue;
        }
        // a form that writes the carry and does not read it opens a run, and the run before it is done
        if (writes && !reads)
        {
            gather_add(gathered, run);
            run.clear();
        }
        run.push_back(asked);
    }
    gather_add(gathered, run);
    host_free(&loaded);
}

// ---------------------------------------------------------------------------------------------------------------
// the monolith written

struct Writer
{
    const Krs *c;
    std::map<std::string, std::string> declared;
    std::string helpers;
    std::string body;
    std::vector<std::string> questions;
    unsigned int tag;
    unsigned int in_words;
    unsigned int out_words;
};

static unsigned int writer_take(unsigned int *words, const std::string &type)
{
    if (type == "u64")
    {
        *words += (*words & 1u);
        const unsigned int at = *words;
        *words += 2u;
        return at;
    }
    const unsigned int at = *words;
    *words += 1u;
    return at;
}

static std::string writer_load(const std::string &type, unsigned int at)
{
    char text[160];
    if (type == "u64")
    {
        snprintf(text, sizeof(text), "*(volatile const u64 *)&in[%u]", at);
    }
    else if (type == "int")
    {
        snprintf(text, sizeof(text), "((*(volatile const u32 *)&in[%u] != 0u) ? 1 : 0)", at);
    }
    else if (type == "s8")
    {
        snprintf(text, sizeof(text), "(s8)*(volatile const u32 *)&in[%u]", at);
    }
    else
    {
        snprintf(text, sizeof(text), "*(volatile const u32 *)&in[%u]", at);
    }
    return text;
}

static std::string writer_store(const std::string &type, unsigned int at, const std::string &name)
{
    char text[200];
    if (type == "u64")
    {
        snprintf(text, sizeof(text), "        *(volatile u64 *)&out[%u] = %s;\n", at, name.c_str());
    }
    else if (type == "int")
    {
        snprintf(text, sizeof(text), "        *(volatile u32 *)&out[%u] = (%s != 0) ? 1u : 0u;\n", at, name.c_str());
    }
    else if (type == "s8")
    {
        snprintf(text, sizeof(text), "        *(volatile u32 *)&out[%u] = (u32)(int)%s;\n", at, name.c_str());
    }
    else
    {
        snprintf(text, sizeof(text), "        *(volatile u32 *)&out[%u] = %s;\n", at, name.c_str());
    }
    return text;
}

// the C type and the c.krs variable an argument is: a bank's type, a fixed register's, or none for a number
static std::string writer_type(Writer *writer, const Argument &argument, std::string *variable)
{
    variable->clear();
    if ((argument.kind == OPERAND_REGISTER) && (argument.which != REGCLASS_IMMEDIATE))
    {
        return c_bank_type(*writer->c, s_bank_names[argument.which]);
    }
    if (argument.kind == OPERAND_PHYSREG)
    {
        const auto fixed = writer->c->fixed.find(s_fixed_names[argument.which]);
        *variable = (fixed == writer->c->fixed.end()) ? std::string() : fixed->second;
        const auto type = writer->declared.find(*variable);
        return (type == writer->declared.end()) ? std::string() : type->second;
    }
    return std::string();
}

// A question holding a number is asked again with another: a form the compiler wrote around the number itself, a power
// of two as a shift or a count folded into a constant, reads apart the second time. The other number keeps a multiple
// of four a multiple of four, as an offset is, and stays below the first where it can, as a count must stay below the
// width; neither is 0 or 1, which the compiler meets in constants of its own
static unsigned int number_alternate(unsigned int number)
{
    if ((number % 4u) == 0u)
    {
        return (number >= 8u) ? (number - 4u) : (number + 4u);
    }
    return (number >= 3u) ? (number - 1u) : (number + 1u);
}

// 1 where a question puts a number to any of its forms
static int question_numbered(const std::vector<Asked> &question)
{
    for (const Asked &asked : question)
    {
        for (const Argument &argument : asked.arguments)
        {
            if ((argument.kind == OPERAND_NUMBER) || (argument.kind == OPERAND_SIGNED) ||
                ((argument.kind == OPERAND_REGISTER) && (argument.which == REGCLASS_IMMEDIATE)))
            {
                return 1;
            }
        }
    }
    return 0;
}

// one question written: its run of forms, each in three regions between tags, its loads, the form and its stores. A
// volatile access does not cross a tag, and the form's region holds none: the compiler cannot fold a load or a store
// into the form
static void writer_question(Writer *writer, const std::vector<Asked> &question, int alternate)
{
    for (size_t one = 0u; one < question.size(); one += 1u)
    {
        const Asked &asked = question[one];
        const std::string name = s_form_names[asked.form];
        const KrsForm &form = writer->c->forms.at(name);
        writer->tag += 1u;
        char line[256];
        snprintf(line, sizeof(line), "\n    MONOLITH_TAG(%u);\n    {\n", MONOLITH_FORMS_LOADS + writer->tag);
        writer->body += line;
        std::string row = std::to_string(writer->tag) + "\t" + name + "\t" + asked_key(asked);
        std::string text = form.text;
        std::string stores;
        const int conditional = (text.find("if (") != std::string::npos);
        for (size_t at = 0u; at < form.parameters.size(); at += 1u)
        {
            const std::string &parameter = form.parameters[at];
            const Argument &argument = asked.arguments[at];
            std::string variable;
            const std::string type = writer_type(writer, argument, &variable);
            if (type.empty())
            {
                const int immediate = (argument.kind == OPERAND_REGISTER);
                const unsigned int value = alternate ? number_alternate(argument.number) : argument.number;
                const std::string number =
                    (argument.kind == OPERAND_SIGNED) ? std::to_string((int)value) : std::to_string(value);
                text = text_fill(text, parameter, immediate ? (number + "u") : number);
                row += "\t" + parameter + "=number:" + number;
                continue;
            }
            const std::string local = "a_" + parameter;
            const size_t named = text_count(text, "{" + parameter + "}");
            const size_t assigned = text_count(text, "{" + parameter + "} =") - text_count(text, "{" + parameter + "} ==");
            const int output = (assigned != 0u);
            const int input = !output || conditional || (named > assigned);
            if (input)
            {
                const unsigned int word = writer_take(&writer->in_words, type);
                writer->body += "        " + type + " " + local + " = " + writer_load(type, word) + ";\n";
                row += "\t" + parameter + "=in:" + std::to_string(word) + ":" + type;
            }
            else
            {
                writer->body += "        " + type + " " + local + ";\n";
            }
            if (output)
            {
                const unsigned int word = writer_take(&writer->out_words, type);
                stores += writer_store(type, word, local);
                row += "\t" + parameter + "=out:" + std::to_string(word) + ":" + type;
            }
            text = text_fill(text, parameter, local);
        }
        // the fixed registers the text names, each loaded as an argument is. The carry is the chain's own
        for (const auto &fixed : writer->c->fixed)
        {
            const std::string &variable = fixed.second;
            const auto type = writer->declared.find(variable);
            if ((type == writer->declared.end()) || !text_names(text, variable))
            {
                continue;
            }
            const unsigned int word = writer_take(&writer->in_words, type->second);
            writer->body += "        const " + type->second + " " + variable + " = " +
                            writer_load(type->second, word) + ";\n";
            row += "\t!" + fixed.first + "=in:" + std::to_string(word) + ":" + type->second;
        }
        for (const char *const variable : {"launch"})
        {
            const auto type = writer->declared.find(variable);
            if ((type != writer->declared.end()) && text_names(text, variable))
            {
                const unsigned int word = writer_take(&writer->in_words, type->second);
                writer->body += "        const " + type->second + " " + variable + " = " +
                                writer_load(type->second, word) + ";\n";
                row += "\t!" + std::string(variable) + "=in:" + std::to_string(word) + ":" + type->second;
            }
        }
        // the carry a form reads is loaded and the carry it writes stored, as every other word it reads and writes
        int reads = 0;
        const int writes = form_carries(*writer->c, name, &reads);
        if (reads)
        {
            const unsigned int word = writer_take(&writer->in_words, "u32");
            writer->body += "        carry = " + writer_load("u32", word) + ";\n";
            row += "\t!carry=in:" + std::to_string(word) + ":u32";
        }
        if (writes)
        {
            const unsigned int word = writer_take(&writer->out_words, "u32");
            stores += writer_store("u32", word, "carry");
            row += "\t!carry=out:" + std::to_string(word) + ":u32";
        }
        snprintf(line, sizeof(line), "        MONOLITH_TAG(%u);\n", writer->tag);
        writer->body += line + text;
        snprintf(line, sizeof(line), "        MONOLITH_TAG(%u);\n", MONOLITH_FORMS_STORES + writer->tag);
        writer->body += line + stores + "    }\n";
        writer->questions.push_back(row);
    }
}

static int forms_write(const char *c_path, const char *monolith_path, const char *questions_path)
{
    Krs c;
    if ((c_target().ruleset(1) == NULL) || !krs_read(c_path, &c))
    {
        fprintf(stderr, "the ruleset %s did not read\n", c_path);
        return 2;
    }
    Gathered gathered;
    HostProgram program;
    HostProgram bare;
    for (int reuse = 0; reuse <= 1; reuse += 1)
    {
        host_arithmetic(&program);
        gather_lane(c, &program, reuse, &gathered);
        host_division(&program);
        gather_lane(c, &program, reuse, &gathered);
        host_bitwise(&program);
        gather_lane(c, &program, reuse, &gathered);
        host_members(&program);
        gather_lane(c, &program, reuse, &gathered);
        host_affine_limit(&program);
        gather_lane(c, &program, reuse, &gathered);
        host_bare_divisor(&bare);
        gather_lane(c, &bare, reuse, &gathered);
        host_inexact(&program, &bare);
        gather_lane(c, &program, reuse, &gathered);
        // the two tables the program reads through, sized as the host oracle sizes them
        unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
        unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
        host_tables(&program, wide, narrow);
        gather_lane(c, &program, reuse, &gathered);
        free(wide);
        free(narrow);
    }
    Writer writer;
    writer.c = &c;
    writer.declared = c_declared(c);
    writer.tag = 0u;
    writer.in_words = 0u;
    writer.out_words = 0u;
    // the helpers the lane's opening defines for the carry chains, everything it holds before the lane itself
    const std::string &open = c.forms.at("lane_open").text;
    writer.helpers = open.substr(0u, open.find("extern \"C\" __device__"));
    for (const std::vector<Asked> &question : gathered.questions)
    {
        writer_question(&writer, question, 0);
        if (question_numbered(question))
        {
            writer_question(&writer, question, 1);
        }
    }
    FILE *const out = fopen(monolith_path, "wb");
    FILE *const rows = fopen(questions_path, "wb");
    if ((out == NULL) || (rows == NULL))
    {
        fprintf(stderr, "the monolith %s or the questions %s was not written\n", monolith_path, questions_path);
        return 2;
    }
    fprintf(out, "// written by monolith_forms from c.krs and the lanes of the record programs; not edited by hand\n"
                 "typedef unsigned int u32;\ntypedef unsigned long long u64;\ntypedef signed char s8;\n\n"
                 "#define MONOLITH_TAG(tag_) asm volatile(\"pmevent.mask %%0;\" ::\"n\"(tag_) : \"memory\")\n"
                 "%s\nextern \"C\" __global__ void monolith_forms(const u32 *in, u32 *out)\n{\n"
                 "    u32 carry = 0u;\n%s\n    MONOLITH_TAG(%u);\n}\n",
            writer.helpers.c_str(), writer.body.c_str(), writer.tag + 1u);
    for (const std::string &row : writer.questions)
    {
        fprintf(rows, "%s\n", row.c_str());
    }
    fclose(out);
    fclose(rows);
    printf("monolith_forms: %zu questions, %u blocks, %u words in and %u out\n", gathered.questions.size(), writer.tag,
           writer.in_words, writer.out_words);
    return 0;
}

// ---------------------------------------------------------------------------------------------------------------
// the forms read back

// what a block's register or predicate holds: an argument, its half, or scratch
struct Held
{
    std::string argument;
    unsigned int half;
    int negated;
};

// one argument of a question as written: where it was loaded from or stored to and its type, or the number it was put
struct Role
{
    std::string name;
    std::string kind;
    unsigned int word;
    std::string type;
    std::string number;
    int fixed;
};

struct Question
{
    unsigned int tag;
    std::string form;
    std::string key;
    std::vector<Role> roles;
};

static std::vector<std::string> line_split(const std::string &line, char by)
{
    std::vector<std::string> parts;
    size_t at = 0u;
    while (at <= line.size())
    {
        const size_t end = line.find(by, at);
        const size_t stop = (end == std::string::npos) ? line.size() : end;
        parts.push_back(line.substr(at, stop - at));
        at = stop + 1u;
    }
    return parts;
}

static std::vector<Question> questions_read(const char *path)
{
    std::vector<Question> questions;
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return questions;
    }
    char line[4096];
    while (fgets(line, sizeof(line), file) != NULL)
    {
        std::string text(line);
        text.erase(text.find_last_not_of("\r\n") + 1u);
        const std::vector<std::string> parts = line_split(text, '\t');
        if (parts.size() < 3u)
        {
            continue;
        }
        Question question;
        question.tag = (unsigned int)strtoul(parts[0].c_str(), NULL, 10);
        question.form = parts[1];
        question.key = parts[2];
        for (size_t at = 3u; at < parts.size(); at += 1u)
        {
            const size_t equals = parts[at].find('=');
            if (equals == std::string::npos)
            {
                continue;
            }
            Role role;
            role.fixed = (parts[at][0] == '!');
            role.name = parts[at].substr(role.fixed ? 1u : 0u, equals - (role.fixed ? 1u : 0u));
            const std::vector<std::string> fields = line_split(parts[at].substr(equals + 1u), ':');
            role.kind = fields[0];
            role.word = (fields.size() > 1u) ? (unsigned int)strtoul(fields[1].c_str(), NULL, 10) : 0u;
            role.type = (fields.size() > 2u) ? fields[2] : std::string();
            role.number = (role.kind == "number") ? fields[1] : std::string();
            question.roles.push_back(role);
        }
        questions.push_back(question);
    }
    fclose(file);
    return questions;
}

// an instruction of a listing: its guard, its operation and its operands
struct Instruction
{
    std::string guard;
    std::string operation;
    std::vector<std::string> operands;
};

static std::string trim(const std::string &text)
{
    const size_t first = text.find_first_not_of(" \t");
    if (first == std::string::npos)
    {
        return std::string();
    }
    return text.substr(first, text.find_last_not_of(" \t") - first + 1u);
}

// the operands of `text` split at every comma outside brackets and braces
static std::vector<std::string> operands_split(const std::string &text)
{
    std::vector<std::string> operands;
    int depth = 0;
    std::string one;
    for (const char character : text)
    {
        depth += ((character == '[') || (character == '{')) ? 1 : 0;
        depth -= ((character == ']') || (character == '}')) ? 1 : 0;
        if ((character == ',') && (depth == 0))
        {
            operands.push_back(trim(one));
            one.clear();
            continue;
        }
        one += character;
    }
    if (!trim(one).empty())
    {
        operands.push_back(trim(one));
    }
    return operands;
}

static Instruction instruction_read(const std::string &text)
{
    Instruction instruction;
    std::string rest = trim(text);
    if (!rest.empty() && (rest[0] == '@'))
    {
        const size_t space = rest.find(' ');
        instruction.guard = rest.substr(1u, space - 1u);
        rest = trim(rest.substr(space));
    }
    const size_t space = rest.find_first_of(" \t");
    instruction.operation = rest.substr(0u, space);
    if (space != std::string::npos)
    {
        instruction.operands = operands_split(rest.substr(space));
    }
    return instruction;
}

// the SASS listing's blocks, each tag's instructions, and the instructions before the first tag
static std::map<unsigned int, std::vector<std::string>> sass_blocks(const char *path)
{
    std::map<unsigned int, std::vector<std::string>> blocks;
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return blocks;
    }
    char line[4096];
    unsigned int tag = 0u;
    while (fgets(line, sizeof(line), file) != NULL)
    {
        const std::string text(line);
        // an instruction's line opens with its address between /* and */, in hex with no space; a line of encoding
        // alone opens /* 0x
        const size_t open = text.find("/*");
        const size_t address = text.find("*/");
        if ((open == std::string::npos) || (address == std::string::npos) || (open > address) ||
            !isxdigit((unsigned char)text[open + 2u]))
        {
            continue;
        }
        const size_t end = text.find(" ;", address);
        if (end == std::string::npos)
        {
            continue;
        }
        std::string instruction = trim(text.substr(address + 2u, end - address - 2u));
        size_t reuse = instruction.find(".reuse");
        while (reuse != std::string::npos)
        {
            instruction.erase(reuse, 6u);
            reuse = instruction.find(".reuse");
        }
        if (instruction.compare(0u, 7u, "PMTRIG ") == 0)
        {
            tag = (unsigned int)strtoul(instruction.c_str() + 7, NULL, 16);
            continue;
        }
        blocks[tag].push_back(instruction);
    }
    fclose(file);
    return blocks;
}

// the PTX's blocks, each tag's instructions
static std::map<unsigned int, std::vector<std::string>> ptx_blocks(const char *path)
{
    std::map<unsigned int, std::vector<std::string>> blocks;
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return blocks;
    }
    char line[4096];
    unsigned int tag = 0u;
    int inside = 0;
    while (fgets(line, sizeof(line), file) != NULL)
    {
        std::string text = trim(std::string(line));
        text.erase(text.find_last_not_of("\r\n") + 1u);
        text = trim(text);
        inside = inside || (text.find(".entry monolith_forms") != std::string::npos);
        if (!inside || text.empty() || (text.back() != ';') || (text[0] == '.') || (text.compare(0u, 2u, "//") == 0))
        {
            continue;
        }
        text.pop_back();
        if (text.compare(0u, 13u, "pmevent.mask ") == 0)
        {
            tag = (unsigned int)strtoul(text.c_str() + 13, NULL, 10);
            continue;
        }
        blocks[tag].push_back(trim(text));
    }
    fclose(file);
    return blocks;
}

// a register token of a SASS operand: its start and length, the first at or past `from`; npos where none
static size_t sass_register(const std::string &operand, size_t from, size_t *length)
{
    for (size_t at = from; at < operand.size(); at += 1u)
    {
        const int start = (at == 0u) || !identifier_character(operand[at - 1u]);
        if (!start || ((operand[at] != 'R') && (operand[at] != 'P')))
        {
            continue;
        }
        size_t digits = 0u;
        while (((at + 1u + digits) < operand.size()) && (operand[at + 1u + digits] >= '0') &&
               (operand[at + 1u + digits] <= '9'))
        {
            digits += 1u;
        }
        const int ends = ((at + 1u + digits) >= operand.size()) || !identifier_character(operand[at + 1u + digits]);
        if ((digits != 0u) && ends)
        {
            *length = 1u + digits;
            return at;
        }
    }
    return std::string::npos;
}

// the number of the register `token`, R7 or P3
static unsigned int token_number(const std::string &token)
{
    return (unsigned int)strtoul(token.c_str() + 1, NULL, 10);
}

// the operands an instruction writes: its first, and every predicate standing straight after it, where it writes
// any; none for a store, a reduction, a branch and the rest that write nothing of a register's
static unsigned int sass_written(const Instruction &instruction)
{
    static const char *const s_none[] = {"ST", "RED", "BRA", "BSSY", "BSYNC", "EXIT", "WARPSYNC", "BAR", "CALL", "RET",
                                         "NOP", "ATOM.E.ADD.STRONG.GPU.RZ"};
    for (const char *const none : s_none)
    {
        if (instruction.operation.compare(0u, strlen(none), none) == 0)
        {
            return 0u;
        }
    }
    unsigned int written = instruction.operands.empty() ? 0u : 1u;
    while ((written < instruction.operands.size()) && !instruction.operands[written].empty() &&
           (instruction.operands[written][0] == 'P'))
    {
        written += 1u;
    }
    return written;
}

static int sass_wide_write(const Instruction &instruction)
{
    return (instruction.operation.find(".WIDE") != std::string::npos) ||
           (instruction.operation.find(".64") != std::string::npos);
}

// a block read back into a form's text: 1, or 0 with the reason through `why`
struct Read
{
    std::string text;
    std::string why;
};

// the in and out bases the listing has set up so far, a register each and its pair
struct Bases
{
    int in_low;
    int out_low;
};

static std::string hex_number(const std::string &decimal)
{
    char text[32];
    const long long value = strtoll(decimal.c_str(), NULL, 10);
    if (value < 0)
    {
        snprintf(text, sizeof(text), "-0x%llx", (unsigned long long)(-value));
    }
    else
    {
        snprintf(text, sizeof(text), "0x%llx", (unsigned long long)value);
    }
    return text;
}

// `text` with each number argument named where its number is a whole token exactly once
static std::string numbers_named(const std::string &text, const Question &question, std::string *why)
{
    std::string named = text;
    for (const Role &role : question.roles)
    {
        if (role.kind != "number")
        {
            continue;
        }
        // a word past the sign bit is also written as the negative it reads as signed
        const unsigned long long word = strtoull(role.number.c_str(), NULL, 10);
        const std::string negative = ((word >= 0x80000000ull) && (word <= 0xffffffffull))
                                         ? std::to_string(-(long long)(0x100000000ull - word))
                                         : role.number;
        for (const std::string &spelled : {hex_number(role.number), role.number, hex_number(negative), negative})
        {
            std::vector<size_t> places;
            size_t at = named.find(spelled);
            while (at != std::string::npos)
            {
                const int before = (at == 0u) || !identifier_character(named[at - 1u]);
                const int after =
                    ((at + spelled.size()) >= named.size()) || !identifier_character(named[at + spelled.size()]);
                if (before && after)
                {
                    places.push_back(at);
                }
                at = named.find(spelled, at + 1u);
            }
            if (places.size() == 1u)
            {
                named = named.substr(0u, places[0]) + "{" + role.name + "}" +
                        named.substr(places[0] + spelled.size());
                break;
            }
            if (places.size() > 1u)
            {
                *why += "the number " + role.number + " stands " + std::to_string(places.size()) + " times; ";
                break;
            }
        }
    }
    return named;
}

static Read sass_read(const Question &question, const std::vector<std::string> &lines, Bases *bases)
{
    Read read;
    // the value each register holds now, by a name of its own: L<n> loaded, W<n>:<register> written by kept
    // instruction n. A value an argument is bound to is named by the argument
    std::map<std::string, std::string> current;
    std::map<std::string, Held> bound;
    struct Kept
    {
        Instruction instruction;
        std::vector<std::string> names;
        std::string guard;
    };
    std::vector<Kept> kept;
    unsigned int loads = 0u;
    auto role_at = [&](const std::string &kind, unsigned int word, unsigned int *half) -> const Role * {
        for (const Role &role : question.roles)
        {
            if ((role.kind == kind) && ((role.word == word) || ((role.type == "u64") && ((role.word + 1u) == word))))
            {
                *half = word - role.word;
                return &role;
            }
        }
        return NULL;
    };
    auto int_role = [&](const std::string &value) -> const Role * {
        const auto found = bound.find(value);
        for (const Role &role : question.roles)
        {
            if ((found != bound.end()) && (role.name == found->second.argument) && (role.type == "int"))
            {
                return &role;
            }
        }
        return NULL;
    };
    auto offset_of = [](const std::string &address) -> unsigned int {
        const size_t plus = address.find('+');
        return (plus == std::string::npos) ? 0u : (unsigned int)strtoul(address.c_str() + plus + 1u, NULL, 16);
    };
    // `operand` with each register it reads written as its value's name between two \x02
    auto read_names = [&](const std::string &operand) -> std::string {
        std::string renamed;
        size_t from = 0u;
        size_t length = 0u;
        size_t found = sass_register(operand, 0u, &length);
        while (found != std::string::npos)
        {
            const std::string token = operand.substr(found, length);
            const auto value = current.find(token);
            renamed += operand.substr(from, found - from);
            renamed += (value != current.end()) ? ("\x02" + value->second + "\x02") : token;
            from = found + length;
            found = sass_register(operand, from, &length);
        }
        return renamed + operand.substr(from);
    };
    for (const std::string &line : lines)
    {
        const Instruction instruction = instruction_read(line);
        const std::string &operation = instruction.operation;
        const std::vector<std::string> &operands = instruction.operands;
        // the bases: a register set from the entry's parameters, `in` at 0x160 and `out` at 0x168
        if ((operands.size() >= 2u) && (operands.back().compare(0u, 10u, "c[0x0][0x1") == 0) &&
            ((operation == "MOV") || (operation == "IMAD.MOV.U32")))
        {
            const unsigned int place = (unsigned int)strtoul(operands.back().c_str() + 7, NULL, 16);
            if ((place >= 0x160u) && (place < 0x170u))
            {
                bases->in_low = (place == 0x160u) ? (int)token_number(operands[0]) : bases->in_low;
                bases->out_low = (place == 0x168u) ? (int)token_number(operands[0]) : bases->out_low;
                continue;
            }
        }
        if (operation.compare(0u, 4u, "ULDC") == 0)
        {
            continue;
        }
        // a load from `in`: the register it writes holds the argument loaded
        if ((operation.compare(0u, 3u, "LDG") == 0) && (operands.size() == 2u) && (operands[1][0] == '[') &&
            ((int)token_number(operands[1].substr(1u)) == bases->in_low))
        {
            unsigned int half = 0u;
            const Role *const role = role_at("in", offset_of(operands[1]) / 4u, &half);
            if (role != NULL)
            {
                const unsigned int first = token_number(operands[0]);
                const unsigned int words = (operation.find(".64") != std::string::npos) ? 2u : 1u;
                for (unsigned int word = 0u; word < words; word += 1u)
                {
                    const std::string value = "L" + std::to_string(loads);
                    loads += 1u;
                    current["R" + std::to_string(first + word)] = value;
                    bound[value] = {role->name, half + word, 0};
                }
                continue;
            }
        }
        // a store to `out`: the value of the register it reads is the argument stored
        if ((operation.compare(0u, 3u, "STG") == 0) && (operands.size() == 2u) && (operands[0][0] == '[') &&
            ((int)token_number(operands[0].substr(1u)) == bases->out_low))
        {
            unsigned int half = 0u;
            const Role *const role = role_at("out", offset_of(operands[0]) / 4u, &half);
            if (role != NULL)
            {
                const unsigned int words = (operation.find(".64") != std::string::npos) ? 2u : 1u;
                for (unsigned int word = 0u; word < words; word += 1u)
                {
                    const std::string token =
                        (operands[1] == "RZ") ? "RZ" : ("R" + std::to_string(token_number(operands[1]) + word));
                    const auto value = current.find(token);
                    if (value == current.end())
                    {
                        read.why += "the compiler stores " + token + " for " + role->name + "; ";
                        continue;
                    }
                    if (value->second[0] == 'L')
                    {
                        read.why += "the compiler stores " + role->name + " straight from a load; ";
                    }
                    bound[value->second] = {role->name, half + word, 0};
                }
                continue;
            }
        }
        Kept one;
        one.instruction = instruction;
        one.names.resize(operands.size());
        const unsigned int written = sass_written(instruction);
        for (size_t at = written; at < operands.size(); at += 1u)
        {
            one.names[at] = read_names(operands[at]);
        }
        one.guard = instruction.guard.empty() ? std::string() : read_names(instruction.guard);
        const std::string id = "W" + std::to_string(kept.size()) + ":";
        for (size_t at = 0u; at < written; at += 1u)
        {
            size_t length = 0u;
            const size_t found = sass_register(operands[at], 0u, &length);
            if (found == std::string::npos)
            {
                one.names[at] = operands[at];
                continue;
            }
            const std::string token = operands[at].substr(found, length);
            current[token] = id + token;
            one.names[at] = operands[at].substr(0u, found) + "\x02" + current[token] + "\x02" +
                            operands[at].substr(found + length);
            if ((at == 0u) && (token[0] == 'R') && sass_wide_write(instruction))
            {
                const std::string next = "R" + std::to_string(token_number(token) + 1u);
                current[next] = id + next;
            }
        }
        kept.push_back(one);
    }
    // a predicate argument read in: the predicate an ISETP.NE sets from the word loaded for it. A predicate argument
    // stored: the word selected from it, 1 where it holds
    auto inside = [](const std::string &name) -> std::string {
        return ((name.size() >= 2u) && (name[0] == '\x02')) ? name.substr(1u, name.size() - 2u) : std::string();
    };
    std::set<size_t> dropped;
    for (size_t at = 0u; at < kept.size(); at += 1u)
    {
        const std::string &operation = kept[at].instruction.operation;
        const std::vector<std::string> &names = kept[at].names;
        if ((operation.compare(0u, 9u, "ISETP.NE.") == 0) && (names.size() == 5u) && (names[1] == "PT") &&
            (names[3] == "RZ") && (names[4] == "PT") && (int_role(inside(names[2])) != NULL))
        {
            bound[inside(names[0])] = {int_role(inside(names[2]))->name, 0u, 0};
            dropped.insert(at);
        }
        if ((operation == "SEL") && (names.size() == 4u) && (int_role(inside(names[0])) != NULL))
        {
            const int inverted = (names[3][0] == '!');
            const std::string predicate = inside(names[3].substr(inverted ? 1u : 0u));
            const int straight = (names[1] == "RZ") && (names[2] == "0x1");
            const int crossed = (names[1] == "0x1") && (names[2] == "RZ");
            if (predicate.empty() || (!straight && !crossed))
            {
                continue;
            }
            const Role *const role = int_role(inside(names[0]));
            const int negated = straight ? !inverted : inverted;
            bound[predicate] = {role->name, 0u, negated};
            bound.erase(inside(names[0]));
            dropped.insert(at);
            read.why += negated ? ("the compiler sets the negation of " + role->name + "; ") : std::string();
        }
    }
    // the pair a 64-bit write gives: where one half is an argument's, the other is the argument's other half
    for (size_t at = 0u; at < kept.size(); at += 1u)
    {
        const Instruction &instruction = kept[at].instruction;
        size_t length = 0u;
        const size_t found = instruction.operands.empty() ? std::string::npos
                                                          : sass_register(instruction.operands[0], 0u, &length);
        if ((found == std::string::npos) || (sass_written(instruction) == 0u) || !sass_wide_write(instruction) ||
            (instruction.operands[0][found] != 'R'))
        {
            continue;
        }
        const unsigned int first = token_number(instruction.operands[0].substr(found, length));
        const std::string low = "W" + std::to_string(at) + ":R" + std::to_string(first);
        const std::string high = "W" + std::to_string(at) + ":R" + std::to_string(first + 1u);
        const auto low_bound = bound.find(low);
        const auto high_bound = bound.find(high);
        if ((low_bound != bound.end()) && (high_bound == bound.end()) && (low_bound->second.half == 0u))
        {
            bound[high] = {low_bound->second.argument, 1u, 0};
        }
        else if ((high_bound != bound.end()) && (low_bound == bound.end()) && (high_bound->second.half == 1u))
        {
            bound[low] = {high_bound->second.argument, 0u, 0};
        }
    }
    // every value left: an argument's, or scratch, named by the compiler's own register for it
    std::map<std::string, std::string> scratch;
    unsigned int scratch_words = 0u;
    unsigned int scratch_predicates = 0u;
    auto resolve = [&](const std::string &with) -> std::string {
        std::string out;
        size_t from = 0u;
        size_t open = with.find('\x02');
        while (open != std::string::npos)
        {
            const size_t close = with.find('\x02', open + 1u);
            out += with.substr(from, open - from);
            const std::string value = with.substr(open + 1u, close - open - 1u);
            const auto argument = bound.find(value);
            if (argument != bound.end())
            {
                const Held &held = argument->second;
                int fixed = 0;
                for (const Role &role : question.roles)
                {
                    fixed = (role.name == held.argument) ? role.fixed : fixed;
                }
                out += (fixed ? ("<" + held.argument + ">") : ("{" + held.argument + "}")) +
                       ((held.half != 0u) ? ".hi" : "");
            }
            else
            {
                const std::string physical = value.substr(value.find(':') + 1u);
                if (scratch.find(physical) == scratch.end())
                {
                    const int predicate = (physical[0] == 'P');
                    unsigned int &taken = predicate ? scratch_predicates : scratch_words;
                    scratch[physical] = (taken == 0u) ? (predicate ? "P6" : "R254") : physical;
                    read.why += (taken == 1u) ? (std::string("more scratch ") + (predicate ? "predicates" : "words") +
                                                 " than one; ")
                                              : std::string();
                    taken += 1u;
                }
                out += scratch[physical];
            }
            from = close + 1u;
            open = with.find('\x02', from);
        }
        return out + with.substr(from);
    };
    std::string text;
    for (size_t at = 0u; at < kept.size(); at += 1u)
    {
        if (dropped.count(at) != 0u)
        {
            continue;
        }
        text += "\t";
        if (!kept[at].guard.empty())
        {
            text += "@" + resolve(kept[at].guard) + " ";
        }
        text += kept[at].instruction.operation;
        for (size_t one = 0u; one < kept[at].names.size(); one += 1u)
        {
            text += ((one == 0u) ? " \t" : ", ") + resolve(kept[at].names[one]);
        }
        text += ";\n";
    }
    read.text = numbers_named(text, question, &read.why);
    return read;
}

// ---------------------------------------------------------------------------------------------------------------
// PTX

struct PtxBases
{
    std::string in;
    std::string out;
    std::map<std::string, std::string> parameters;
};

static int ptx_register_start(const std::string &text, size_t at)
{
    return (text[at] == '%') && ((at + 1u) < text.size()) && identifier_character(text[at + 1u]);
}

static Read ptx_read(const Question &question, const std::vector<std::string> &lines, PtxBases *bases)
{
    Read read;
    std::map<std::string, Held> held;
    std::vector<Instruction> kept;
    for (const std::string &line : lines)
    {
        const Instruction instruction = instruction_read(line);
        const std::string &operation = instruction.operation;
        const std::vector<std::string> &operands = instruction.operands;
        if ((operation.compare(0u, 9u, "ld.param.") == 0) && (operands.size() == 2u))
        {
            bases->parameters[operands[0]] = operands[1];
            continue;
        }
        if ((operation.compare(0u, 10u, "cvta.to.gl") == 0) && (operands.size() == 2u))
        {
            const std::string parameter = bases->parameters[operands[1]];
            if (parameter.find("param_0") != std::string::npos)
            {
                bases->in = operands[0];
            }
            if (parameter.find("param_1") != std::string::npos)
            {
                bases->out = operands[0];
            }
            continue;
        }
        auto address = [](const std::string &operand, std::string *base) -> unsigned int {
            const size_t plus = operand.find('+');
            *base = operand.substr(1u, ((plus == std::string::npos) ? (operand.size() - 1u) : plus) - 1u);
            return (plus == std::string::npos) ? 0u : (unsigned int)strtoul(operand.c_str() + plus + 1u, NULL, 10);
        };
        if ((operation.compare(0u, 19u, "ld.volatile.global.") == 0) && (operands.size() == 2u))
        {
            std::string base;
            const unsigned int offset = address(operands[1], &base);
            const Role *role = NULL;
            for (const Role &one : question.roles)
            {
                role = ((base == bases->in) && (one.kind == "in") && (one.word * 4u == offset)) ? &one : role;
            }
            if (role != NULL)
            {
                held[operands[0]] = {role->name, 0u, 0};
                continue;
            }
        }
        if ((operation.compare(0u, 19u, "st.volatile.global.") == 0) && (operands.size() == 2u))
        {
            std::string base;
            const unsigned int offset = address(operands[0], &base);
            const Role *role = NULL;
            for (const Role &one : question.roles)
            {
                role = ((base == bases->out) && (one.kind == "out") && (one.word * 4u == offset)) ? &one : role;
            }
            if (role != NULL)
            {
                held[operands[1]] = {role->name, 0u, 0};
                continue;
            }
        }
        kept.push_back(instruction);
    }
    // a predicate argument read in, and one stored
    std::set<size_t> dropped;
    for (size_t at = 0u; at < kept.size(); at += 1u)
    {
        const Instruction &instruction = kept[at];
        auto int_role = [&](const std::string &token) -> const Role * {
            const auto value = held.find(token);
            const Role *role = NULL;
            for (const Role &one : question.roles)
            {
                role = ((value != held.end()) && (one.name == value->second.argument) && (one.type == "int")) ? &one : role;
            }
            return role;
        };
        if ((instruction.operation.compare(0u, 7u, "setp.ne") == 0) && (instruction.operands.size() == 3u) &&
            (instruction.operands[2] == "0") && (int_role(instruction.operands[1]) != NULL))
        {
            held[instruction.operands[0]] = {int_role(instruction.operands[1])->name, 0u, 0};
            dropped.insert(at);
        }
        if ((instruction.operation.compare(0u, 5u, "selp.") == 0) && (instruction.operands.size() == 4u) &&
            (int_role(instruction.operands[0]) != NULL))
        {
            const Role *const role = int_role(instruction.operands[0]);
            const int negated = (instruction.operands[1] == "0") ? 1 : 0;
            held[instruction.operands[3]] = {role->name, 0u, negated};
            dropped.insert(at);
            if (negated)
            {
                read.why += "the compiler sets the negation of " + role->name + "; ";
            }
        }
    }
    // the PTX's own registers renamed; one no argument holds is a temporary of the compiler's
    std::set<std::string> temporaries;
    std::string text;
    for (size_t at = 0u; at < kept.size(); at += 1u)
    {
        if (dropped.count(at) != 0u)
        {
            continue;
        }
        auto renamed = [&](const std::string &operand) -> std::string {
            std::string out;
            size_t at_char = 0u;
            while (at_char < operand.size())
            {
                if (!ptx_register_start(operand, at_char))
                {
                    out += operand[at_char];
                    at_char += 1u;
                    continue;
                }
                size_t end = at_char + 1u;
                while ((end < operand.size()) && identifier_character(operand[end]))
                {
                    end += 1u;
                }
                const std::string token = operand.substr(at_char, end - at_char);
                const auto value = held.find(token);
                if (value != held.end())
                {
                    const int fixed = [&]() {
                        for (const Role &role : question.roles)
                        {
                            if (role.name == value->second.argument)
                            {
                                return role.fixed;
                            }
                        }
                        return 0;
                    }();
                    out += fixed ? ("<" + value->second.argument + ">") : ("{" + value->second.argument + "}");
                }
                else
                {
                    out += token;
                    if ((token.compare(0u, 4u, "%tid") != 0) && (token.compare(0u, 5u, "%ntid") != 0))
                    {
                        temporaries.insert(token);
                    }
                }
                at_char = end;
            }
            return out;
        };
        const Instruction &instruction = kept[at];
        text += "\t";
        if (!instruction.guard.empty())
        {
            text += "@" + renamed(instruction.guard) + " ";
        }
        text += instruction.operation;
        for (size_t one = 0u; one < instruction.operands.size(); one += 1u)
        {
            text += ((one == 0u) ? " \t" : ", ") + renamed(instruction.operands[one]);
        }
        text += ";\n";
    }
    if (!temporaries.empty())
    {
        read.why += std::to_string(temporaries.size()) + " temporaries of the compiler's; ";
    }
    read.text = numbers_named(text, question, &read.why);
    return read;
}

// a form's text as one line for a table: tabs and line ends written as a space and a semicolon run
static std::string text_flat(const std::string &text)
{
    std::string flat;
    int space = 0;
    for (const char character : text)
    {
        if ((character == '\t') || (character == ' ') || (character == '\n'))
        {
            space = space || !flat.empty();
            if (character == '\n')
            {
                flat += " |";
            }
            continue;
        }
        if (space && !flat.empty() && (flat.back() != ' '))
        {
            flat += ' ';
        }
        space = 0;
        flat += character;
    }
    while (!flat.empty() && ((flat.back() == '|') || (flat.back() == ' ')))
    {
        flat.pop_back();
    }
    return flat;
}

static std::string cell(const std::string &text)
{
    std::string out;
    for (const char character : text)
    {
        out += (character == '|') ? std::string("\\|") : std::string(1u, character);
    }
    return out;
}

// a question's three regions joined, its loads, its form and its stores
static std::vector<std::string> regions_joined(const std::map<unsigned int, std::vector<std::string>> &blocks,
                                               unsigned int tag)
{
    std::vector<std::string> joined;
    for (const unsigned int region : {MONOLITH_FORMS_LOADS + tag, tag, MONOLITH_FORMS_STORES + tag})
    {
        const auto found = blocks.find(region);
        if (found != blocks.end())
        {
            joined.insert(joined.end(), found->second.begin(), found->second.end());
        }
    }
    return joined;
}

// the instructions a form's text holds, a line each
static size_t text_instructions(const std::string &text)
{
    return text_count(text, "\n");
}

// the part's machine file, against which a SASS form read is assembled before it is written
static SassMachine s_machine;
static int s_machine_read;

// 1 where every line of `text`, a SASS form whose parameters are named, assembles against the machine file: each word
// parameter given a register pair of its own from R10, whose .hi the assembler reads as the pair's second, each
// predicate parameter a predicate from P0, and each number parameter the number its question put
static int sass_assembles(const std::string &text, const Question &question)
{
    if (!s_machine_read)
    {
        return 0;
    }
    std::string filled = text;
    unsigned int pair = 10u;
    unsigned int predicate = 0u;
    for (const Role &role : question.roles)
    {
        if (role.fixed)
        {
            continue;
        }
        if (role.kind == "number")
        {
            filled = text_fill(filled, role.name, role.number);
            continue;
        }
        if (role.type == "int")
        {
            filled = text_fill(filled, role.name, "P" + std::to_string(predicate));
            predicate += 1u;
            continue;
        }
        filled = text_fill(filled, role.name, "R" + std::to_string(pair));
        pair += 2u;
    }
    static unsigned char code[256];
    size_t from = 0u;
    while (from < filled.size())
    {
        const size_t end = filled.find('\n', from);
        const size_t stop = (end == std::string::npos) ? filled.size() : end;
        const std::string line = filled.substr(from, stop - from) + "\n";
        from = stop + 1u;
        if (trim(line).size() <= 1u)
        {
            continue;
        }
        if (sass_assemble_lines(&s_machine, line.c_str(), SASS_CONTROL_SAFE, code, sizeof(code)) == 0u)
        {
            return 0;
        }
    }
    return 1;
}

// 1 where `text` reaches memory through a space named: SASS's global load and store, PTX's .global
static int text_spaced(const std::string &text, int sass)
{
    return sass ? ((text.find("LDG") != std::string::npos) || (text.find("STG") != std::string::npos))
                : (text.find(".global") != std::string::npos);
}

// A form read is written into a ruleset where it is the form whole: it names every parameter the ruleset's form takes,
// each fixed register it names is one the ruleset names, it holds no register of the compiler's own past the scratch
// the ruleset keeps, and the reading left nothing unsettled. It holds no branch, whose target is the monolith's own
// address. Where the ruleset's form reaches memory through a named space and the reading does not, the question named
// none: c.krs writes an address as a plain pointer. Of two correct writings the one of fewer instructions stands: a
// reading longer than the ruleset's form is not written. The text it is written as, or empty with the reason through
// `why`
static std::string read_adopted(const Read &read, const Krs &rules, const Question &question, int sass,
                                std::string *why)
{
    const std::string &form = question.form;
    const auto found = rules.forms.find(form);
    const std::string now = (found == rules.forms.end()) ? std::string() : found->second.text;
    if ((read.text.find("BRA") != std::string::npos) || (read.text.find("bra ") != std::string::npos))
    {
        *why = "the reading holds a branch";
        return std::string();
    }
    if (text_spaced(now, sass) && !read.text.empty() && !text_spaced(read.text, sass))
    {
        *why = "the question names no address space";
        return std::string();
    }
    if (!now.empty() && !read.text.empty() && (text_instructions(read.text) > text_instructions(now)))
    {
        *why = "the compiler writes " + std::to_string(text_instructions(read.text)) + " instructions where the "
               "ruleset writes " + std::to_string(text_instructions(now));
        return std::string();
    }
    if (read.text.empty())
    {
        *why = "the compiler writes no instruction for it";
        return std::string();
    }
    if (!read.why.empty())
    {
        *why = read.why;
        return std::string();
    }
    if (found == rules.forms.end())
    {
        *why = "the ruleset holds no form of the name";
        return std::string();
    }
    for (const std::string &parameter : found->second.parameters)
    {
        if (read.text.find("{" + parameter + "}") == std::string::npos)
        {
            *why = "the reading does not name " + parameter;
            return std::string();
        }
    }
    std::string text = read.text;
    size_t open = text.find('<');
    while (open != std::string::npos)
    {
        const size_t close = text.find('>', open);
        const std::string fixed = text.substr(open + 1u, close - open - 1u);
        const auto named = rules.fixed.find(fixed);
        if (named == rules.fixed.end())
        {
            *why = "the ruleset names no fixed register " + fixed;
            return std::string();
        }
        text = text.substr(0u, open) + named->second + text.substr(close + 1u);
        open = text.find('<', open);
    }
    // a register of the compiler's own left in the text: one the reading did not name
    for (size_t at = 0u; at < text.size(); at += 1u)
    {
        const int start = (at == 0u) || !identifier_character(text[at - 1u]);
        if (!start)
        {
            continue;
        }
        if (sass && (text[at] == 'R') && ((at + 1u) < text.size()) && (text[at + 1u] >= '0') && (text[at + 1u] <= '9'))
        {
            const unsigned int number = token_number(text.substr(at));
            const int ruleset = (number >= 238u);
            if (!ruleset)
            {
                *why = "the reading leaves the compiler's register R" + std::to_string(number);
                return std::string();
            }
        }
        if (sass && (text[at] == 'P') && ((at + 1u) < text.size()) && (text[at + 1u] >= '0') && (text[at + 1u] <= '5'))
        {
            *why = "the reading leaves the compiler's predicate " + text.substr(at, 2u);
            return std::string();
        }
    }
    if (sass && !sass_assembles(text, question))
    {
        *why = "the machine file holds no form for it";
        return std::string();
    }
    return text;
}

// a form's text written back as a ruleset line holds it: \t, \n and \\ escaped
static std::string krs_escape(const std::string &text)
{
    std::string escaped;
    for (const char character : text)
    {
        escaped += (character == '\t') ? std::string("\\t")
                   : (character == '\n') ? std::string("\\n")
                   : (character == '\\') ? std::string("\\\\")
                                         : std::string(1u, character);
    }
    return escaped;
}

// the ruleset at `path` with the text of each form `adopted` names written in place: the count written, or -1 where
// the file was not read or written
static int krs_apply(const char *path, const std::map<std::string, std::string> &adopted)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return -1;
    }
    std::string whole;
    char block[65536];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        whole.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    int written = 0;
    std::string out;
    size_t at = 0u;
    while (at < whole.size())
    {
        const size_t end = whole.find('\n', at);
        const size_t stop = (end == std::string::npos) ? whole.size() : end;
        std::string line = whole.substr(at, stop - at);
        const size_t equals = line.find(" = ");
        if ((line.compare(0u, 5u, "form ") == 0) && (equals != std::string::npos))
        {
            const std::vector<std::string> head = words_split(line.substr(0u, equals));
            const auto found = (head.size() >= 2u) ? adopted.find(head[1]) : adopted.end();
            if (found != adopted.end())
            {
                const std::string replaced = line.substr(0u, equals + 3u) + krs_escape(found->second);
                written += (replaced != line) ? 1 : 0;
                line = replaced;
            }
        }
        out += line + ((end == std::string::npos) ? "" : "\n");
        at = stop + 1u;
    }
    FILE *const back = fopen(path, "wb");
    if ((back == NULL) || (fwrite(out.data(), 1u, out.size(), back) != out.size()) || (fclose(back) != 0))
    {
        return -1;
    }
    return written;
}

static int forms_read(const char *questions_path, const char *listing, const char *ptx, const char *sass_krs,
                      const char *ptx_krs, const char *machine, const char *record, int apply)
{
    const std::vector<Question> questions = questions_read(questions_path);
    s_machine_read = sass_machine_read(&s_machine, machine);
    Krs sass;
    Krs ptx_rules;
    if (questions.empty() || !krs_read(sass_krs, &sass) || !krs_read(ptx_krs, &ptx_rules))
    {
        fprintf(stderr, "the questions, sass.krs or ptx.krs did not read\n");
        return 2;
    }
    const std::map<unsigned int, std::vector<std::string>> sass_lines = sass_blocks(listing);
    const std::map<unsigned int, std::vector<std::string>> ptx_lines = ptx_blocks(ptx);
    FILE *const out = fopen(record, "wb");
    if (out == NULL)
    {
        fprintf(stderr, "the record %s was not written\n", record);
        return 2;
    }
    Bases bases = {-1, -1};
    PtxBases ptx_bases;
    const std::vector<std::string> none;
    Question nothing;
    const auto opening = sass_lines.find(0u);
    sass_read(nothing, (opening != sass_lines.end()) ? opening->second : none, &bases);
    const auto ptx_opening = ptx_lines.find(0u);
    ptx_read(nothing, (ptx_opening != ptx_lines.end()) ? ptx_opening->second : none, &ptx_bases);
    fprintf(out, "# The forms read off NVIDIA's compiler\n\n");
    fprintf(out, "Written by `monolith_forms.sh` whole on every run. Every form the lanes of the record programs decide "
                 "is asked of NVIDIA's compiler once for each set of banks its arguments come from, its question the "
                 "form's own text in `c.krs`, in one program between tags (`monolith_forms.cpp`). Each block of the "
                 "listing and of the PTX is read back into the form it is, its registers named by the arguments they "
                 "hold, and held beside the form `sass.krs` and `ptx.krs` give. A fixed register is named in angle "
                 "brackets, and the ruleset names it. A form every question of which reads whole and alike is the "
                 "ruleset's form, written into it by `monolith_forms.sh apply`; any other keeps the ruleset's text, "
                 "and the reason stands beside it.\n\n");
    fprintf(out, "| tag | form | banks | SASS read | PTX read | note |\n|---|---|---|---|---|---|\n");
    // each form's readings: the text every question gave where all gave one whole, else empty with the reason
    struct Verdict
    {
        std::string text;
        std::string why;
        int seen;
    };
    std::map<std::string, Verdict> sass_verdicts;
    std::map<std::string, Verdict> ptx_verdicts;
    auto settle = [](std::map<std::string, Verdict> &verdicts, const std::string &form, const std::string &text,
                     const std::string &why) {
        Verdict &verdict = verdicts[form];
        if (verdict.seen == 0)
        {
            verdict = {text, why, 1};
            return;
        }
        if (!verdict.text.empty() && (text != verdict.text))
        {
            verdict.why = text.empty() ? why : "the questions read apart";
            verdict.text.clear();
        }
    };
    for (const Question &question : questions)
    {
        const Read read = sass_read(question, regions_joined(sass_lines, question.tag), &bases);
        if ((getenv("MONOLITH_FORMS_TAG") != NULL) && (strtoul(getenv("MONOLITH_FORMS_TAG"), NULL, 10) == question.tag))
        {
            printf("tag %u: in R%d out R%d, %zu lines, text [%s] why [%s]\n", question.tag, bases.in_low,
                   bases.out_low, regions_joined(sass_lines, question.tag).size(), read.text.c_str(), read.why.c_str());
            for (const std::string &line : regions_joined(sass_lines, question.tag))
            {
                printf("  %s\n", line.c_str());
            }
        }
        const Read ptx_one = ptx_read(question, regions_joined(ptx_lines, question.tag), &ptx_bases);
        std::string sass_why;
        std::string ptx_why;
        const std::string sass_text = read_adopted(read, sass, question, 1, &sass_why);
        const std::string ptx_text = read_adopted(ptx_one, ptx_rules, question, 0, &ptx_why);
        settle(sass_verdicts, question.form, sass_text, sass_why);
        settle(ptx_verdicts, question.form, ptx_text, ptx_why);
        const size_t space = question.key.find(' ');
        const std::string banks = (space == std::string::npos) ? std::string() : question.key.substr(space + 1u);
        fprintf(out, "| %u | %s | %s | `%s` | `%s` | %s%s%s |\n", question.tag, question.form.c_str(), banks.c_str(),
                cell(text_flat(read.text)).c_str(), cell(text_flat(ptx_one.text)).c_str(), cell(sass_why).c_str(),
                (!sass_why.empty() && !ptx_why.empty()) ? " / " : "", cell(ptx_why).c_str());
    }
    std::map<std::string, std::string> sass_adopted;
    std::map<std::string, std::string> ptx_adopted;
    fprintf(out, "\n## By form\n\n| form | sass.krs | SASS read | | ptx.krs | PTX read | |\n|---|---|---|---|---|---|---|\n");
    unsigned int sass_same = 0u;
    unsigned int ptx_same = 0u;
    for (const auto &entry : sass_verdicts)
    {
        const std::string &form = entry.first;
        const Verdict &sass_verdict = entry.second;
        const Verdict &ptx_verdict = ptx_verdicts[form];
        const auto sass_form = sass.forms.find(form);
        const auto ptx_form = ptx_rules.forms.find(form);
        const std::string sass_now = (sass_form != sass.forms.end()) ? sass_form->second.text : std::string();
        const std::string ptx_now = (ptx_form != ptx_rules.forms.end()) ? ptx_form->second.text : std::string();
        auto state = [](const Verdict &verdict, const std::string &now, unsigned int *same) -> std::string {
            if (verdict.text.empty())
            {
                return "kept: " + verdict.why;
            }
            if (verdict.text == now)
            {
                *same += 1u;
                return "same";
            }
            return "read";
        };
        const std::string sass_state = state(sass_verdict, sass_now, &sass_same);
        const std::string ptx_state = state(ptx_verdict, ptx_now, &ptx_same);
        if (sass_state == "read")
        {
            sass_adopted[form] = sass_verdict.text;
        }
        if (ptx_state == "read")
        {
            ptx_adopted[form] = ptx_verdict.text;
        }
        fprintf(out, "| %s | `%s` | `%s` | %s | `%s` | `%s` | %s |\n", form.c_str(), cell(text_flat(sass_now)).c_str(),
                cell(text_flat(sass_verdict.text)).c_str(), cell(sass_state).c_str(), cell(text_flat(ptx_now)).c_str(),
                cell(text_flat(ptx_verdict.text)).c_str(), cell(ptx_state).c_str());
    }
    fprintf(out, "\n%zu questions over %zu forms. Of the forms, sass.krs already gives %u as read and %zu are read "
                 "otherwise; ptx.krs gives %u as read and %zu are read otherwise.\n",
            questions.size(), sass_verdicts.size(), sass_same, sass_adopted.size(), ptx_same, ptx_adopted.size());
    fclose(out);
    printf("monolith_forms: %zu questions over %zu forms; sass.krs: %u same, %zu read otherwise; ptx.krs: %u same, %zu "
           "read otherwise; the record written to %s\n",
           questions.size(), sass_verdicts.size(), sass_same, sass_adopted.size(), ptx_same, ptx_adopted.size(),
           record);
    if (apply)
    {
        const int sass_written = krs_apply(sass_krs, sass_adopted);
        const int ptx_written = krs_apply(ptx_krs, ptx_adopted);
        printf("monolith_forms: %d forms written into %s and %d into %s\n", sass_written, sass_krs, ptx_written,
               ptx_krs);
        if ((sass_written < 0) || (ptx_written < 0))
        {
            return 2;
        }
    }
    return 0;
}

int main(int count, char **words)
{
    if ((count == 5) && (strcmp(words[1], "write") == 0))
    {
        return forms_write(words[2], words[3], words[4]);
    }
    if (((count == 9) || (count == 10)) && (strcmp(words[1], "read") == 0))
    {
        return forms_read(words[2], words[3], words[4], words[5], words[6], words[7], words[8],
                          (count == 10) && (strcmp(words[9], "apply") == 0));
    }
    fprintf(stderr, "monolith_forms write <c.krs> <monolith.cu> <questions>\n"
                    "monolith_forms read <questions> <listing> <ptx> <sass.krs> <ptx.krs> <machine> <record> "
                    "[apply]\n");
    return 2;
}
