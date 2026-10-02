// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// monolith_emit.cpp: the monolith (monolith.cu), a block at a time, held against what our compiler writes.
//
// NVIDIA's listing of the tagged build is the answer key: the instructions between tag n and tag n + 1 are its writing
// of precept n - 1, each with the 128 bits it encoded. For every one, our reader is asked for its text from those bits,
// and our assembler for its bits from that text; the scheduler's bits, 105 to 127, are read apart, since no listing
// prints them. Then the word our compiler writes the block's precept with (word_web.h) is written through sass.krs with
// NVIDIA's own registers, assembled, and set beside NVIDIA's instruction. A precept no word holds is reported with the
// tree the alphabet web writes it as (precepts.h). sass.krs, the machine file and the word web are read as they stand.
//
//     monolith_emit <listing> <block> [machine file]
//     monolith_emit <listing> all <record> [machine file]
//
// The second form runs every block and writes the record, a table a row an instruction and a row our compiler's
// writing, to <record>. It is written whole on every run: it holds what the blocks read now.
//
// The listing is cuobjdump -sass -fun monolith of the build with MONOLITH_TAGGED 1.
extern "C"
{
#include "../../../../../../src/c/transpiler/cubin/sass_assemble.h"
#include "../../../../../../src/c/types/file_defs/krs/sass_machine.h"
}

#include "../../../../../../src/c/transpiler/codegen/word_web.h"
#include "sass_target.h"
#include "target.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

// ENGINE_IMAGE_BASE reads the ELF header the linker marks with __ehdr_start (engine_config_platform.h), and this
// program is linked as a PE, where there is none. Nothing here asks for the image base: it is named so the link holds
#if defined(__GNUC__) && !defined(__ELF__)
extern "C" const char __ehdr_start = 0;
#endif

// the operation's own bits of an encoding's high word: below bit 105 of the 128, where the scheduler's begin
#define EMIT_OPERATION_HIGH ((1ull << 41u) - 1ull)

#define EMIT_NAMED(name_, text_, arity_) text_,

static const char *const s_names[PRECEPT_COUNT] = {PRECEPTS(EMIT_NAMED)};

// one instruction of NVIDIA's listing: where it lies, its text, and its two words
struct EmitLine
{
    unsigned long long address;
    std::string text;
    unsigned long long low;
    unsigned long long high;
};

// `text` with its whitespace run together, and its closing semicolon and the spaces around it gone
static std::string emit_plain(const std::string &text)
{
    std::string plain;
    int space = 0;
    for (const char character : text)
    {
        if ((character == ' ') || (character == '\t') || (character == '\n') || (character == '\r'))
        {
            space = !plain.empty();
            continue;
        }
        if (space != 0)
        {
            plain += ' ';
            space = 0;
        }
        plain += character;
    }
    while (!plain.empty() && ((plain.back() == ';') || (plain.back() == ' ')))
    {
        plain.pop_back();
    }
    return plain;
}

// the hexadecimal word in `text` after `from`, written /* 0x... */; 0 where there is none
static int emit_word(const std::string &text, size_t from, unsigned long long *word)
{
    const size_t at = text.find("/* 0x", from);
    if (at == std::string::npos)
    {
        return 0;
    }
    *word = strtoull(text.c_str() + at + 5u, nullptr, 16);
    return 1;
}

// NVIDIA's listing read into its instructions: each is an address and text with its low word, and the next line
// carries its high word
static std::vector<EmitLine> emit_listing(const char *path)
{
    std::vector<EmitLine> lines;
    std::ifstream file(path);
    std::string line;
    while (std::getline(file, line))
    {
        const size_t open = line.find("/*");
        const size_t close = (open == std::string::npos) ? std::string::npos : line.find("*/", open);
        if ((close == std::string::npos) || (line[open + 2u] == ' '))
        {
            continue;
        }
        EmitLine read;
        read.address = strtoull(line.c_str() + open + 2u, nullptr, 16);
        const size_t text_end = line.find(';', close);
        read.text = emit_plain(line.substr(close + 2u, (text_end == std::string::npos) ? std::string::npos
                                                                                        : (text_end - close - 2u)));
        std::string next;
        if (!emit_word(line, close, &read.low) || !std::getline(file, next) || !emit_word(next, 0u, &read.high))
        {
            continue;
        }
        lines.push_back(read);
    }
    return lines;
}

// the tag a line is, PMTRIG's immediate, or 0 where it is no tag
static unsigned int emit_tag(const EmitLine &line)
{
    return (line.text.rfind("PMTRIG ", 0u) == 0u) ? (unsigned int)strtoul(line.text.c_str() + 7u, nullptr, 16) : 0u;
}

// a line's operands split at their commas, its operation and guard dropped
static std::vector<std::string> emit_operands(const std::string &text)
{
    std::vector<std::string> operands;
    size_t at = (text[0] == '@') ? (text.find(' ') + 1u) : 0u;
    at = text.find(' ', at);
    while (at != std::string::npos)
    {
        const size_t comma = text.find(',', at + 1u);
        operands.push_back(emit_plain(text.substr(at + 1u, (comma == std::string::npos) ? std::string::npos
                                                                                         : (comma - at - 1u))));
        at = comma;
    }
    return operands;
}

// 1 where `operand` names a register a word can be written with: R and a number, not RZ
static int emit_register(const std::string &operand)
{
    return (operand.size() > 1u) && (operand[0] == 'R') && (operand[1] >= '0') && (operand[1] <= '9');
}

// the word of the web whose tree is precept `precept` alone over its two operands in order, or nullptr
static const Word *emit_word_for(unsigned int precept)
{
    for (unsigned int at = 0u; at < WORD_WEB_COUNT; at += 1u)
    {
        const Word &word = s_word_web[at];
        if ((word.nodes == 1u) && (word.node[0].precept == precept) && (word.node[0].left == PRECEPT_ARG_AT(0u)))
        {
            return &word;
        }
    }
    return nullptr;
}

// the alphabet web's tree for `precept`, written as text, or empty where it has none
static std::string emit_alphabet(unsigned int precept)
{
    for (unsigned int at = 0u; at < PRECEPT_WEB_COUNT; at += 1u)
    {
        if (s_precept_web[at].precept != precept)
        {
            continue;
        }
        std::string tree;
        for (unsigned int node = 0u; node < s_precept_web[at].nodes; node += 1u)
        {
            const PreceptNode &one = s_precept_web[at].node[node];
            tree += (node == 0u) ? "" : ", ";
            tree += std::string(s_names[one.precept]) + "(";
            const unsigned char child[2] = {one.left, one.right};
            for (unsigned int side = 0u; side < 2u; side += 1u)
            {
                const unsigned char leaf = child[side];
                tree += (side == 0u) ? "" : " ";
                tree += (leaf == PRECEPT_NONE)    ? "-"
                        : (leaf == PRECEPT_ZERO)  ? "0"
                        : (leaf == PRECEPT_ONES)  ? "ones"
                        : (leaf >= PRECEPT_ARG)   ? ((leaf == PRECEPT_LEFT) ? "left" : "right")
                                                  : ("n" + std::to_string(leaf));
            }
            tree += ")";
        }
        return tree;
    }
    return std::string();
}

// Whether NVIDIA's block holds the passage: the register its load writes is the register its store reads, and nothing
// past the parameters' moves stands between them. The two registers through `loaded` and `stored`, the reading printed
static int emit_passage(const std::vector<EmitLine> &held, std::string *loaded, std::string *stored)
{
    unsigned int between = 0u;
    for (const EmitLine &line : held)
    {
        const std::vector<std::string> operands = emit_operands(line.text);
        if ((line.text.find("LDG") != std::string::npos) && !operands.empty())
        {
            *loaded = operands.front();
        }
        else if ((line.text.find("STG") != std::string::npos) && !operands.empty())
        {
            *stored = operands.back();
        }
        else if (line.text.find("c[0x0]") == std::string::npos)
        {
            between += 1u;
        }
    }
    const int carried = !loaded->empty() && (*loaded == *stored) && (between == 0u);
    if (carried)
    {
        printf("    NVIDIA's block: the word loaded into %s is stored from %s with nothing between, the passage\n",
               loaded->c_str(), stored->c_str());
    }
    else
    {
        printf("    NVIDIA's block: not the passage, loaded into %s, stored from %s, %u instructions between\n",
               loaded->empty() ? "nothing" : loaded->c_str(), stored->empty() ? "nothing" : stored->c_str(), between);
    }
    return carried;
}


// a scratch register for a bank sass.krs asks one of while writing a form; nothing here writes a form that asks
static std::string emit_scratch(const std::string &)
{
    return "R254";
}

// one row of the record: the block, NVIDIA's instruction and where it lies, what our reader, our assembler and our
// compiler made of it, and the difference read off them. A row for our compiler's writing names no instruction
struct EmitRow
{
    unsigned int block;
    std::string precept;
    std::string address;
    std::string nvidia;
    std::string reader;
    std::string operation;
    std::string scheduler;
    std::string compiler;
    std::string difference;
    // both encodings as bits and the marks under the bits apart, where the operation bits are apart
    std::string bits;
};

static std::vector<EmitRow> s_rows;

// `low` and `high` as 128 bits, bit 127 first, a space between bytes
static std::string emit_binary(unsigned long long low, unsigned long long high)
{
    std::string bits;
    for (int bit = 127; bit >= 0; bit -= 1)
    {
        const unsigned long long word = (bit >= 64) ? high : low;
        bits += ((word >> (unsigned int)(bit % 64)) & 1ull) ? '1' : '0';
        bits += ((bit % 8) == 0 && (bit != 0)) ? " " : "";
    }
    return bits;
}

// NVIDIA's encoding and ours bit by bit under each byte's top bit number, and a line marking each bit apart: ^ an
// operation bit, . a scheduler bit
static std::string emit_bits_apart(unsigned long long nvidia_low, unsigned long long nvidia_high,
                                   unsigned long long low, unsigned long long high, const char *label = "ours     ")
{
    std::string numbers = "         ";
    std::string marks = "         ";
    for (int bit = 127; bit >= 0; bit -= 1)
    {
        if ((bit % 8) == 7)
        {
            char top[16];
            snprintf(top, sizeof(top), "%-9d", bit);
            numbers += top;
        }
        const unsigned long long theirs = (((bit >= 64) ? nvidia_high : nvidia_low) >> (unsigned int)(bit % 64)) & 1ull;
        const unsigned long long mine = (((bit >= 64) ? high : low) >> (unsigned int)(bit % 64)) & 1ull;
        marks += (theirs == mine) ? ' ' : ((bit >= 105) ? '.' : '^');
        marks += ((bit % 8) == 0 && (bit != 0)) ? " " : "";
    }
    return numbers + "\n" + "NVIDIA   " + emit_binary(nvidia_low, nvidia_high) + "\n" + label + emit_binary(low, high) +
           "\n" + marks + "\n";
}

static void emit_row(unsigned int block, unsigned int precept, const std::string &address, const std::string &nvidia,
                     const std::string &reader, const std::string &operation, const std::string &scheduler,
                     const std::string &compiler, const std::string &difference, const std::string &bits = "")
{
    s_rows.push_back({block, s_names[precept], address, nvidia, reader, operation, scheduler, compiler, difference, bits});
}

static std::string emit_hex(unsigned long long value, int width)
{
    char text[32];
    snprintf(text, sizeof(text), "%0*llx", width, value);
    return text;
}

// the dotted modifiers of a line's operation, its guard and the operation's own name dropped
static std::vector<std::string> emit_modifiers(const std::string &text)
{
    const size_t begin = (text[0] == '@') ? (text.find(' ') + 1u) : 0u;
    const size_t end = text.find(' ', begin);
    const std::string operation = text.substr(begin, (end == std::string::npos) ? std::string::npos : (end - begin));
    std::vector<std::string> modifiers;
    size_t dot = operation.find('.');
    while (dot != std::string::npos)
    {
        const size_t next = operation.find('.', dot + 1u);
        modifiers.push_back(operation.substr(dot + 1u, (next == std::string::npos) ? std::string::npos : (next - dot - 1u)));
        dot = next;
    }
    return modifiers;
}

// the modifiers of `one` that `other` does not carry, joined
static std::string emit_lacking(const std::string &one, const std::string &other)
{
    const std::vector<std::string> theirs = emit_modifiers(other);
    std::string lacking;
    for (const std::string &modifier : emit_modifiers(one))
    {
        int held = 0;
        for (const std::string &their : theirs)
        {
            held = (their == modifier) ? 1 : held;
        }
        lacking += held ? "" : ((lacking.empty() ? "." : " .") + modifier);
    }
    return lacking;
}

// block `block` of the listing held against our reader, our assembler and our compiler, printed and recorded
static void emit_block(const std::vector<EmitLine> &lines, unsigned int block, const SassMachine *machine,
                       const Ruleset *rules)
{
    const unsigned int precept = block - 1u;
    std::vector<EmitLine> held;
    int inside = 0;
    for (const EmitLine &line : lines)
    {
        const unsigned int tag = emit_tag(line);
        inside = (tag == block) ? 1 : ((tag != 0u) ? 0 : inside);
        if ((inside != 0) && (tag == 0u))
        {
            held.push_back(line);
        }
    }
    printf("block %u: precept %s, %zu instructions between tag %u and tag %u\n", block, s_names[precept], held.size(),
           block, block + 1u);

    unsigned int read_same = 0u;
    unsigned int assembled_same = 0u;
    unsigned int control_same = 0u;
    for (const EmitLine &line : held)
    {
        const std::string address = emit_hex(line.address, 5);
        printf("  %s  %s\n", address.c_str(), line.text.c_str());
        char text[256];
        const int read = sass_encoding_read(machine, line.low, line.high, line.address, text, sizeof(text));
        const std::string ours = read ? emit_plain(text) : std::string();
        // whether the machine file holds a form for the instruction's text, its operation and the kinds of its
        // operands, apart from whether that form holds these bits
        SassInstructionParts parts;
        sass_instruction_read(line.text.c_str(), &parts);
        const int text_held = (sass_machine_form(machine, &parts) != nullptr);
        const std::string unread = text_held ? "a form holds its text and not its bits" : "no form holds its text";
        const std::string reader = !read ? unread : ((ours == line.text) ? "same" : ours);
        read_same += (read && (ours == line.text)) ? 1u : 0u;
        printf("         our reader: %s\n", !read ? unread.c_str() : ((ours == line.text) ? "the same text" : ours.c_str()));
        // A branch's target is the address its text names. The listing prints it bare and our assembler reads a bare
        // number as the immediate itself: it is put to the assembler as a label, `(0x...), which it counts from the
        // instruction after the branch, and the address is given as the label's
        const size_t branch = line.text.find("BRA 0x");
        const unsigned long long target =
            (branch == std::string::npos) ? 0ull : strtoull(line.text.c_str() + branch + 6u, nullptr, 16);
        const std::string put = (branch == std::string::npos)
                                    ? line.text
                                    : (line.text.substr(0u, branch + 4u) + "`(" + line.text.substr(branch + 4u) + ")");
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        if (!sass_assemble(machine, put.c_str(), line.address, target, SASS_CONTROL_BASE, &low, &high))
        {
            printf("         our assembler: refused it\n");
            // where a form holds the text, its own encoding beside NVIDIA's shows where the operand it cannot place
            // lies against the fields it holds
            const SassForm *const form = sass_machine_form(machine, &parts);
            const std::string sample = (form == nullptr) ? std::string()
                                                         : emit_bits_apart(line.low, line.high, form->low, form->high,
                                                                           "the form ");
            if (!sample.empty())
            {
                printf("           NVIDIA's against the form's own encoding:\n%s", sample.c_str());
            }
            emit_row(block, precept, address, line.text, reader, "refused", "-", "",
                     text_held ? "a form holds its text and places none of an operand" : "no form in the machine file",
                     sample);
            continue;
        }
        const int operation = (low == line.low) && ((high & EMIT_OPERATION_HIGH) == (line.high & EMIT_OPERATION_HIGH));
        const int control = ((high & ~EMIT_OPERATION_HIGH) == (line.high & ~EMIT_OPERATION_HIGH));
        assembled_same += operation ? 1u : 0u;
        control_same += control ? 1u : 0u;
        printf("         our assembler: operation bits %s, scheduler bits %s\n", operation ? "the same" : "apart",
               control ? "the same" : "apart");
        // the bits the operation is apart at, the high word's counted from 64
        std::string apart;
        for (unsigned int bit = 0u; (operation == 0) && (bit < 105u); bit += 1u)
        {
            const unsigned long long theirs = (bit < 64u) ? ((line.low >> bit) & 1ull) : ((line.high >> (bit - 64u)) & 1ull);
            const unsigned long long mine = (bit < 64u) ? ((low >> bit) & 1ull) : ((high >> (bit - 64u)) & 1ull);
            apart += (theirs != mine) ? ((apart.empty() ? "" : " ") + std::to_string(bit)) : "";
        }
        const std::string bits = operation ? std::string() : emit_bits_apart(line.low, line.high, low, high);
        if (!operation)
        {
            printf("           apart at bit %s\n%s", apart.c_str(), bits.c_str());
        }
        if (!control)
        {
            printf("           scheduler NVIDIA %06llx, ours %06llx\n", line.high >> 41u, high >> 41u);
        }
        const std::string scheduler = control ? "same" : ("NVIDIA " + emit_hex(line.high >> 41u, 6) + ", ours " +
                                                          emit_hex(high >> 41u, 6));
        const std::string difference = (!read && !operation && text_held) ? "a form holds its text, not these bits"
                                       : (!read && !operation)            ? "no form in the machine file"
                                       : !operation                       ? "operation bits apart"
                                       : !control                         ? "scheduler bits"
                                                                          : "none";
        emit_row(block, precept, address, line.text, reader, operation ? "same" : ("apart at bit " + apart), scheduler,
                 "", difference, bits);
    }
    printf("  of %zu: our reader gave NVIDIA's text for %u, our assembler NVIDIA's operation bits for %u and its "
           "scheduler bits for %u\n",
           held.size(), read_same, assembled_same, control_same);

    // NOP is gnascor's passage: GRAY between FUZZ and FIZZ, the word carried in and carried out as it came, written as
    // no instruction
    if (precept == PRECEPT_NOP)
    {
        printf("  our compiler: NOP is the passage, GRAY between FUZZ and FIZZ (gnascor): no instruction, the word "
               "carried out as it came in\n");
        std::string loaded;
        std::string stored;
        const int carried = emit_passage(held, &loaded, &stored);
        emit_row(block, precept, "", "", "", "", "", "the passage, no instruction",
                 carried ? "none: NVIDIA's block is the passage" : "NVIDIA's block is not the passage");
        return;
    }

    // MOV has two candidates and the part's clock chooses between them: the passage, the copy written as no
    // instruction where the register the word is read into is the register it is written from; and the copy word
    // (word_copy, word_web.h) written through sass.krs as an instruction
    if (precept == PRECEPT_MOV)
    {
        printf("  our compiler, candidate 1, the passage: no instruction, the registers the copy joins made one\n");
        std::string loaded;
        std::string stored;
        const int carried = emit_passage(held, &loaded, &stored);
        emit_row(block, precept, "", "", "", "", "", "candidate 1, the passage, no instruction",
                 carried ? "none: NVIDIA's block is the passage" : "NVIDIA's block is not the passage");
        const std::string to = stored.empty() ? "R9" : stored;
        const std::string from = loaded.empty() ? "R9" : loaded;
        std::string written;
        if (ruleset_opcode(rules, "word_copy", {to, from}, emit_scratch, written) == 0)
        {
            printf("  our compiler, candidate 2, the copy word: sass.krs writes no word_copy form\n");
            emit_row(block, precept, "", "", "", "", "", "candidate 2, word_copy", "sass.krs writes no word_copy form");
            return;
        }
        const std::string plain = emit_plain(written);
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        const int assembles = sass_assemble(machine, plain.c_str(), 0ull, 0ull, SASS_CONTROL_BASE, &low, &high);
        printf("  our compiler, candidate 2, the copy word: %s, %s\n", plain.c_str(),
               assembles ? "which assembles, one instruction where NVIDIA's block holds none" : "which does not assemble");
        emit_row(block, precept, "", "", "", "", "", "candidate 2, word_copy: " + plain,
                 assembles ? "one instruction where NVIDIA's block holds none" : "does not assemble");
        return;
    }

    // ERR has two candidates and the part's clock chooses between them, not this: a trap where it stands, the way
    // NVIDIA writes it, a branch past the trap on the flag; and a branch to a handler, the error word (word_web.h),
    // written through sass.krs on NVIDIA's predicate and landing on the label label_error writes
    if (precept == PRECEPT_ERR)
    {
        const EmitLine *trap = nullptr;
        const EmitLine *guard = nullptr;
        for (const EmitLine &line : held)
        {
            trap = (line.text.find("TRAP") != std::string::npos) ? &line : trap;
            guard = (line.text.find("BRA") != std::string::npos) ? &line : guard;
        }
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        const int trap_written = (trap != nullptr) && sass_assemble(machine, trap->text.c_str(), trap->address, 0ull,
                                                                    SASS_CONTROL_BASE, &low, &high);
        SassInstructionParts trap_parts;
        if (trap != nullptr)
        {
            sass_instruction_read(trap->text.c_str(), &trap_parts);
        }
        const int trap_held = (trap != nullptr) && (sass_machine_form(machine, &trap_parts) != nullptr);
        const char *const trap_reading = (trap == nullptr) ? "NVIDIA's block holds no trap"
                                         : trap_written    ? "the trap assembles"
                                         : trap_held       ? "a form holds the trap and places none of its operand, and it cannot be written yet"
                                                           : "the machine file holds no form for the trap, and it cannot be written yet";
        printf("  our compiler, candidate 1, a trap in place: %s\n", trap_reading);
        emit_row(block, precept, "", "", "", "", "", "candidate 1, a trap in place", trap_reading);
        // the predicate the branch is taken on: NVIDIA's guard with its negation dropped, since the handler is gone to
        // where the flag is set and NVIDIA's branch passes the trap where it is clear
        std::string where = "P0";
        if ((guard != nullptr) && (guard->text[0] == '@'))
        {
            const size_t space = guard->text.find(' ');
            where = guard->text.substr((guard->text[1] == '!') ? 2u : 1u, space - ((guard->text[1] == '!') ? 2u : 1u));
        }
        std::string written;
        const int branch = ruleset_opcode(rules, "error", {where, "1"}, emit_scratch, written);
        const int label = branch && ruleset_opcode(rules, "label_error", {"1"}, emit_scratch, written);
        if (!label)
        {
            printf("  our compiler, candidate 2, a branch to a handler: sass.krs writes no error or label_error form\n");
            emit_row(block, precept, "", "", "", "", "", "candidate 2, a branch to a handler",
                     "sass.krs writes no error or label_error form");
            return;
        }
        static unsigned char code[256];
        const unsigned int assembled = sass_assemble_lines(machine, written.c_str(), SASS_CONTROL_BASE, code,
                                                           sizeof(code));
        std::string reads;
        for (unsigned int at = 0u; at < assembled; at += 1u)
        {
            unsigned long long word_low = 0ull;
            unsigned long long word_high = 0ull;
            memcpy(&word_low, &code[16u * at], 8u);
            memcpy(&word_high, &code[(16u * at) + 8u], 8u);
            char text[256];
            reads += sass_encoding_read(machine, word_low, word_high, 16ull * at, text, sizeof(text)) ? emit_plain(text)
                                                                                                       : "(unread)";
            reads += (at + 1u < assembled) ? "; " : "";
        }
        printf("  our compiler, candidate 2, a branch to a handler, error on %s: %s\n", where.c_str(),
               (assembled == 0u) ? "does not assemble" : reads.c_str());
        printf("    against NVIDIA's %s: the branch is taken where the flag is set and lands on the handler, where "
               "NVIDIA's passes the trap where it is clear\n",
               (guard == nullptr) ? "block, which holds no branch" : guard->text.c_str());
        emit_row(block, precept, "", "", "", "", "", "candidate 2, error on " + where + ": " + reads,
                 (assembled == 0u) ? "does not assemble"
                                   : "taken where the flag is set, to a handler; NVIDIA's passes a trap where it is clear");
        return;
    }

    // JCC is the loop_back word (word_web.h), a jump taken on a predicate to a label, written through sass.krs on the
    // predicate NVIDIA's branch is guarded by and landing on the label loop_label writes; its guard's sense is kept
    if (precept == PRECEPT_JCC)
    {
        const EmitLine *guard = nullptr;
        for (const EmitLine &line : held)
        {
            guard = ((line.text[0] == '@') && (line.text.find("BRA") != std::string::npos)) ? &line : guard;
        }
        if (guard == nullptr)
        {
            printf("  our compiler: loop_back, and NVIDIA's block holds no guarded branch\n");
            emit_row(block, precept, "", "", "", "", "", "loop_back", "NVIDIA's block holds no guarded branch");
            return;
        }
        const std::string where = guard->text.substr(1u, guard->text.find(' ') - 1u);
        std::string written;
        // loop_back's parameters are the loop's number, then the predicate
        const int branch = ruleset_opcode(rules, "loop_back", {"1", where}, emit_scratch, written);
        const int label = branch && ruleset_opcode(rules, "loop_label", {"1"}, emit_scratch, written);
        static unsigned char code[256];
        const unsigned int assembled =
            label ? sass_assemble_lines(machine, written.c_str(), SASS_CONTROL_BASE, code, sizeof(code)) : 0u;
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        memcpy(&low, &code[0], 8u);
        memcpy(&high, &code[8], 8u);
        char text[256];
        const std::string reads = (assembled == 0u) ? std::string("does not assemble")
                                  : sass_encoding_read(machine, low, high, guard->address, text, sizeof(text))
                                      ? emit_plain(text)
                                      : std::string("(unread)");
        // the jump's guard and operation held against NVIDIA's, its target apart: the label here lands where
        // loop_label stands and NVIDIA's lands past its block
        const unsigned long long guard_bits = 0xf000ull;
        const unsigned long long operation_bits = 0xfffull;
        const int same_guard = (assembled != 0u) && ((low & guard_bits) == (guard->low & guard_bits));
        const int same_operation = (assembled != 0u) && ((low & operation_bits) == (guard->low & operation_bits));
        printf("  our compiler, loop_back on %s: %s\n", where.c_str(), reads.c_str());
        printf("    against NVIDIA's %s: the guard %s, the operation %s, the target its own label's\n",
               guard->text.c_str(), same_guard ? "the same" : "apart", same_operation ? "the same" : "apart");
        emit_row(block, precept, emit_hex(guard->address, 5), guard->text, "", "", "", "loop_back on " + where + ": " + reads,
                 (assembled == 0u) ? "does not assemble"
                                   : (std::string("guard ") + (same_guard ? "the same" : "apart") + ", operation " +
                                      (same_operation ? "the same" : "apart") + ", target its own label's"));
        return;
    }

    // the precept as our compiler writes it: the word whose tree is that precept alone, through sass.krs
    const Word *const word = emit_word_for(precept);
    if (word == nullptr)
    {
        const std::string tree = emit_alphabet(precept);
        const std::string reading = tree.empty() ? "the alphabet web holds no tree for it"
                                                 : ("the alphabet web writes it " + tree);
        printf("  our compiler: no word is %s alone; %s\n", s_names[precept], reading.c_str());
        emit_row(block, precept, "", "", "", "", "", "no word; " + reading, "no word");
        return;
    }
    // NVIDIA's instruction for the precept: the block's one line that writes a register from registers and is not a
    // load, a store or a move of a parameter
    const EmitLine *core = nullptr;
    for (const EmitLine &line : held)
    {
        const int moves = (line.text.find("LDG") != std::string::npos) || (line.text.find("STG") != std::string::npos) ||
                          (line.text.find("c[0x0]") != std::string::npos);
        core = moves ? core : &line;
    }
    if (core == nullptr)
    {
        printf("  our compiler: %s, and NVIDIA's block holds no instruction past its loads and stores\n", word->name);
        emit_row(block, precept, "", "", "", "", "", word->name, "NVIDIA's block holds no instruction for it");
        return;
    }
    // the registers the instruction names, a negation or a complement in front of one dropped: the word is written
    // with the register, and its form puts any negation itself
    std::vector<std::string> registers;
    for (const std::string &operand : emit_operands(core->text))
    {
        const std::string bare = ((operand[0] == '-') || (operand[0] == '~')) ? operand.substr(1u) : operand;
        if (emit_register(bare))
        {
            registers.push_back(bare);
        }
    }
    if (registers.size() < (size_t)(1u + word->reads))
    {
        printf("  our compiler: %s, and NVIDIA's %s names too few registers to write it with\n", word->name,
               core->text.c_str());
        emit_row(block, precept, "", "", "", "", "", word->name, "NVIDIA's instruction names too few registers");
        return;
    }
    // the destination first, then the leaves in NVIDIA's order, and for two leaves the other order as well. The record
    // keeps the order whose operation bits are apart from NVIDIA's at the fewest places
    std::string recorded_compiler;
    std::string recorded_difference;
    unsigned int recorded_apart = ~0u;
    std::string recorded_bits;
    for (unsigned int order = 0u; order < ((word->reads == 2u) ? 2u : 1u); order += 1u)
    {
        std::vector<std::string> given = {registers[0]};
        for (unsigned int leaf = 0u; leaf < word->reads; leaf += 1u)
        {
            const unsigned int place = (order == 0u) ? leaf : (word->reads - 1u - leaf);
            given.push_back(registers[1u + place]);
        }
        std::string written;
        if (ruleset_opcode(rules, word->name, given, emit_scratch, written) == 0)
        {
            printf("  our compiler: %s is not written by sass.krs\n", word->name);
            emit_row(block, precept, "", "", "", "", "", word->name, "sass.krs writes no form for it");
            return;
        }
        const std::string plain = emit_plain(written);
        unsigned long long low = 0ull;
        unsigned long long high = 0ull;
        const int assembles =
            sass_assemble(machine, plain.c_str(), core->address, 0ull, SASS_CONTROL_BASE, &low, &high);
        const int same = assembles && (low == core->low) &&
                         ((high & EMIT_OPERATION_HIGH) == (core->high & EMIT_OPERATION_HIGH));
        printf("  our compiler, %s with its leaves %s: %s\n", word->name, (order == 0u) ? "in NVIDIA's order" : "swapped",
               plain.c_str());
        printf("    against NVIDIA's %s at %05llx: %s\n", core->text.c_str(), core->address,
               !assembles ? "ours does not assemble" : (same ? "the same operation bits" : "operation bits apart"));
        const std::string lacking = emit_lacking(core->text, plain);
        const std::string extra = emit_lacking(plain, core->text);
        std::string difference = !assembles ? "ours does not assemble"
                                 : same     ? ("none, leaves " + std::string((order == 0u) ? "in NVIDIA's order" : "swapped"))
                                            : "operation bits apart";
        difference += lacking.empty() ? "" : ("; NVIDIA's carries " + lacking + " and ours does not");
        difference += extra.empty() ? "" : ("; ours carries " + extra + " and NVIDIA's does not");
        // the places the operation bits are apart at; a writing that does not assemble is apart everywhere
        unsigned int places = assembles ? 0u : 105u;
        for (unsigned int bit = 0u; assembles && (bit < 105u); bit += 1u)
        {
            const unsigned long long theirs = (bit < 64u) ? ((core->low >> bit) & 1ull) : ((core->high >> (bit - 64u)) & 1ull);
            const unsigned long long mine = (bit < 64u) ? ((low >> bit) & 1ull) : ((high >> (bit - 64u)) & 1ull);
            places += (theirs != mine) ? 1u : 0u;
        }
        if (places < recorded_apart)
        {
            recorded_apart = places;
            recorded_compiler = word->name + std::string(": ") + plain;
            recorded_difference = difference + (same ? "" : ("; apart at " + std::to_string(places) + " bits"));
            recorded_bits = (same || !assembles) ? std::string() : emit_bits_apart(core->low, core->high, low, high);
        }
        if (same)
        {
            break;
        }
    }
    if (!recorded_bits.empty())
    {
        printf("    the closest writing against NVIDIA's, bit by bit:\n%s", recorded_bits.c_str());
    }
    emit_row(block, precept, emit_hex(core->address, 5), core->text, "", "", "", recorded_compiler, recorded_difference,
             recorded_bits);
}

// `text` as a code span, doubled where it holds a backtick of its own
static std::string emit_code(const std::string &text)
{
    if (text.empty())
    {
        return "";
    }
    return (text.find('`') == std::string::npos) ? ("`" + text + "`") : ("`` " + text + " ``");
}

// the record written as a table to `path`
static int emit_record(const char *path, const char *listing)
{
    FILE *const file = fopen(path, "w");
    if (file == nullptr)
    {
        fprintf(stderr, "the record %s did not open\n", path);
        return 0;
    }
    fprintf(file, "# The monolith held against our compiler\n\n");
    fprintf(file, "Written by `monolith_emit %s all <this file>` and written again on every run. ", listing);
    fprintf(file, "Each block of the monolith's tagged build is NVIDIA's writing of one precept. ");
    fprintf(file, "A row with an address is one of NVIDIA's instructions held against our reader and our assembler; ");
    fprintf(file, "a row with a compiler column is our compiler's writing of the block's precept. ");
    fprintf(file, "Scheduler bits are 105 to 127, apart from the operation's.\n\n");
    unsigned int instructions = 0u;
    unsigned int formless = 0u;
    unsigned int unheld = 0u;
    unsigned int unplaced = 0u;
    unsigned int operation_apart = 0u;
    unsigned int scheduler_apart = 0u;
    for (const EmitRow &row : s_rows)
    {
        instructions += row.address.empty() || row.nvidia.empty() || row.reader.empty() ? 0u : 1u;
        formless += (row.difference == "no form in the machine file") ? 1u : 0u;
        unheld += (row.difference == "a form holds its text, not these bits") ? 1u : 0u;
        unplaced += (row.difference == "a form holds its text and places none of an operand") ? 1u : 0u;
        operation_apart += (row.difference == "operation bits apart") ? 1u : 0u;
        scheduler_apart += (!row.scheduler.empty() && (row.scheduler != "same") && (row.scheduler != "-")) ? 1u : 0u;
    }
    fprintf(file, "%u of NVIDIA's instructions read: %u with no form in the machine file, %u whose text a form holds "
                  "and whose bits it does not, %u whose text a form holds with an operand it places none of, %u with "
                  "operation bits apart, %u with scheduler bits apart.\n\n",
            instructions, formless, unheld, unplaced, operation_apart, scheduler_apart);
    fprintf(file, "| block | precept | address | NVIDIA | our reader | our assembler | scheduler | our compiler | difference |\n");
    fprintf(file, "|---|---|---|---|---|---|---|---|---|\n");
    for (const EmitRow &row : s_rows)
    {
        fprintf(file, "| %u | %s | %s | %s | %s | %s | %s | %s | %s |\n", row.block, row.precept.c_str(),
                row.address.c_str(), emit_code(row.nvidia).c_str(),
                ((row.reader == "same") || (row.reader == "no form holds its text") ||
                 (row.reader == "a form holds its text and not its bits") || row.reader.empty())
                    ? row.reader.c_str()
                    : emit_code(row.reader).c_str(),
                row.operation.c_str(), row.scheduler.c_str(), emit_code(row.compiler).c_str(),
                row.difference.c_str());
    }
    // every row whose operation bits are apart, NVIDIA's encoding and ours bit by bit, bit 127 first
    fprintf(file, "\n## Bits apart\n\n");
    fprintf(file, "Each instruction whose operation bits are apart from NVIDIA's, both encodings bit by bit with bit 127 "
                  "first under each byte's top bit; `^` marks an operation bit apart and `.` a scheduler bit apart.\n");
    for (const EmitRow &row : s_rows)
    {
        if (row.bits.empty())
        {
            continue;
        }
        fprintf(file, "\nBlock %u, %s, `%s`%s\n\n```\n%s```\n", row.block, row.precept.c_str(), row.nvidia.c_str(),
                row.compiler.empty() ? ", our assembler" : (", " + row.compiler).c_str(), row.bits.c_str());
    }
    fclose(file);
    printf("the record of %zu rows written to %s\n", s_rows.size(), path);
    return 1;
}

int main(int count, char **arguments)
{
    const int all = (count > 2) && (strcmp(arguments[2], "all") == 0);
    if ((count < 3) || (count > 5) || (all && (count < 4)))
    {
        fprintf(stderr, "monolith_emit <listing> <block> [machine file]\nmonolith_emit <listing> all <record> [machine "
                        "file]\n");
        return 2;
    }
    const int machine_at = all ? 4 : 3;
    const char *const path = (count > machine_at) ? arguments[machine_at] : "src/c/transpiler/cubin/machines/sm_86";
    static SassMachine machine;
    if (!sass_machine_read(&machine, path))
    {
        fprintf(stderr, "the machine file %s did not read\n", path);
        return 1;
    }
    const Ruleset *const rules = sass_target().ruleset(1);
    if (rules == nullptr)
    {
        return 1;
    }
    const std::vector<EmitLine> lines = emit_listing(arguments[1]);
    if (all)
    {
        for (unsigned int block = 1u; block <= PRECEPT_COUNT; block += 1u)
        {
            emit_block(lines, block, &machine, rules);
        }
        return emit_record(arguments[3], arguments[1]) ? 0 : 1;
    }
    const unsigned int block = (unsigned int)strtoul(arguments[2], nullptr, 10);
    if ((block == 0u) || (block > PRECEPT_COUNT))
    {
        fprintf(stderr, "a block is 1 to %u, the tag before precept block - 1\n", (unsigned int)PRECEPT_COUNT);
        return 2;
    }
    emit_block(lines, block, &machine, rules);
    return 0;
}
