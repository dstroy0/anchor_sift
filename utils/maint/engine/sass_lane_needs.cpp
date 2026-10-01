// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Which forms a real lane asks sass.krs for, and which of those the ruleset leaves empty.
//
//     sass_lane_needs
//
// sass.krs leaves 33 of its forms empty, and filling all 33 is not the work: the work is the lane emitted to SASS.
// So the record programs the host oracle runs are laid out and decided for the SASS generator, and every form the
// core decides is counted. A form the lane never decides is not a blocker whatever the ruleset says about it, and a
// form it decides that the ruleset leaves empty is exactly what stands between here and a lane. No device, no
// toolchain, and nothing is written: decide() only says which forms a lane is made of.
#include "record_programs.h"

// the cubin writer is C and its headers carry no guard of their own: the linkage is named here
extern "C"
{
#include "sass_assemble.h"
#include "sass_machine.h"
}

#include "machine_ir_types.h"
#include "ruleset_core_words.h"
#include "ruleset_reader.h"
#include "sass_target.h"
#include "target.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

// ENGINE_IMAGE_BASE reads the ELF header the linker marks with __ehdr_start (engine_config_platform.h), and this
// tool is linked as a PE, where there is none. Nothing here asks for the image base: it is named so the link holds
#if defined(__GNUC__) && !defined(__ELF__)
extern "C" const char __ehdr_start = 0;
#endif

// the schema's forms by their place in it, each with the parameters it takes, as machine_ir_types.h gives them
#define LANE_FORM_TEXT(name_, text_, parameters_) {text_, parameters_},

static const struct
{
    const char *text;
    unsigned int parameters;
} s_forms[OPCODE_COUNT] = {OPCODES(LANE_FORM_TEXT)};

// 1 where the ruleset gives the form at `place` as an error, and that blocks a lane: a nop writes nothing and
// the lane goes on without it, and only an err refuses. The two read the same from the outside, both writing an
// empty text, and the ruleset says which it means
static int lane_form_errors(const Ruleset *rules, unsigned int place)
{
    return rules->form_given[place] == (unsigned char)RULESET_CORE_GIVEN_ERR;
}

// the part's machine file, read once, against which a written lane is assembled
static SassMachine s_machine;
static int s_machine_read;

// Each line of `lane` assembled, and the first that the assembler refuses printed. A lane the generator writes is
// not a lane the part runs: a form the ruleset leaves empty writes nothing and breaks nothing. The text comes
// back whole with its holes in it, and only the assembler says whether what is left is machine code
static unsigned int lane_assembles(const std::string &lane, unsigned int *refused, std::string *first)
{
    static unsigned char code[64];
    unsigned int lines = 0u;
    size_t at = 0u;
    while (at < lane.size())
    {
        const size_t end = lane.find('\n', at);
        const size_t stop = (end == std::string::npos) ? lane.size() : end;
        const std::string line = lane.substr(at, stop - at) + "\n";
        size_t letter = 0u;
        while ((letter < line.size()) && ((line[letter] == ' ') || (line[letter] == '\t')))
        {
            letter += 1u;
        }
        // a label, a note, a directive and a blank line are not instructions and assemble to nothing
        const int instruction = (letter < (line.size() - 1u)) && (line[letter] != '.') && (line[letter] != '/') &&
                                (line.find(':') == std::string::npos) && (line.find('`') == std::string::npos);
        if (instruction != 0)
        {
            lines += 1u;
            if (sass_assemble_lines(&s_machine, line.c_str(), SASS_CONTROL_SAFE, code, sizeof(code)) == 0u)
            {
                *first = (first->empty()) ? line.substr(0u, line.size() - 1u) : *first;
                *refused += 1u;
            }
        }
        at = stop + 1u;
    }
    return lines;
}

// every form `program` decides, counted into `asked`
static void lane_decide(const HostProgram *program, int reuse, unsigned int *asked, unsigned int *laid)
{
    HostLoaded loaded;
    if (host_load(program, reuse, &loaded) == 0)
    {
        printf("  %s: not laid out\n", program->name);
        return;
    }
    *laid += 1u;
    std::vector<MachineInstr> items;
    unsigned int places = 0u;
    if (sass_target().decided(&loaded.layout, &places, &items) == 0)
    {
        printf("  %s: %u steps, the core decides no lane for it\n", program->name, loaded.layout.steps);
        host_free(&loaded);
        return;
    }
    for (const MachineInstr &item : items)
    {
        // the header stands in the items as a form of all ones, and is the listing's opening, not a form
        if (item.form < OPCODE_COUNT)
        {
            asked[item.form] += 1u;
        }
    }
    // and the lane as the generator writes it, to say whether an empty form stops it or is passed over in silence
    const TargetInfo target = {0ull, 8, 6, 12, 0, ""};
    unsigned int lane_places = 0u;
    unsigned int live = 0u;
    const std::string lane = sass_target().program(&loaded.layout, &target, std::string(), &lane_places, &live);
    unsigned int lines = 0u;
    for (size_t at = 0u; at < lane.size(); at += 1u)
    {
        lines += (lane[at] == '\n') ? 1u : 0u;
    }
    unsigned int refused = 0u;
    std::string first;
    const unsigned int instructions = (s_machine_read != 0) ? lane_assembles(lane, &refused, &first) : 0u;
    printf("  %-16s %4u steps, %5zu items, lane %s, %u lines, %u instructions, %u the assembler refuses%s%s\n",
           program->name, loaded.layout.steps, items.size(), lane.empty() ? "REFUSED" : "written", lines,
           instructions, refused, first.empty() ? "" : ", first: ", first.c_str());
    // the first lane written out whole: what a form that writes nothing leaves behind can be read
    static int dumped;
    if ((dumped == 0) && !lane.empty())
    {
        FILE *const file = fopen("build/sass_lane_needs/lane.sass", "wb");
        if (file != NULL)
        {
            fwrite(lane.data(), 1u, lane.size(), file);
            fclose(file);
            dumped = 1;
        }
    }
    host_free(&loaded);
}

int main(void)
{
    const Ruleset *const rules = sass_target().ruleset(1);
    if (rules == NULL)
    {
        return 1;
    }
    s_machine_read = sass_machine_read(&s_machine, "src/engine/compiler/cubin/machines/sm_86");
    printf("machine %s: %u forms\n", s_machine.part, s_machine.forms);
    static unsigned int asked[OPCODE_COUNT];
    unsigned int laid = 0u;
    HostProgram program;
    HostProgram bare;
    // the record programs the host oracle runs, each decided with the registers fresh and again with them reused
    for (int reuse = 0; reuse <= 1; reuse += 1)
    {
        host_arithmetic(&program);
        lane_decide(&program, reuse, asked, &laid);
        host_division(&program);
        lane_decide(&program, reuse, asked, &laid);
        host_bitwise(&program);
        lane_decide(&program, reuse, asked, &laid);
        host_members(&program);
        lane_decide(&program, reuse, asked, &laid);
        host_affine_limit(&program);
        lane_decide(&program, reuse, asked, &laid);
        host_bare_divisor(&bare);
        lane_decide(&bare, reuse, asked, &laid);
        host_inexact(&program, &bare);
        lane_decide(&program, reuse, asked, &laid);
        // the two tables the program reads through, sized as the host oracle sizes them
        unsigned int *const wide = (unsigned int *)malloc(512u * sizeof(unsigned int));
        unsigned int *const narrow = (unsigned int *)malloc(4096u * sizeof(unsigned int));
        host_tables(&program, wide, narrow);
        lane_decide(&program, reuse, asked, &laid);
        free(wide);
        free(narrow);
    }
    unsigned int decided = 0u;
    unsigned int blocking = 0u;
    printf("%u layouts decided for SASS\n", laid);
    // A form the code generator leaves out is never asked of the ruleset, whatever the lane's items hold. SASS
    // answers 0 to program_unit_written: its resident reaches it already built in the part's own compiler's cubin,
    // and the lane is written into that. Counting such a form as blocking reads the lane's item list where the
    // question is what program() puts to the ruleset
    const int writes_unit = sass_target().program_unit_written();
    printf("forms the lane asks for that sass.krs gives as an error, which is what refuses it:\n");
    for (unsigned int place = 0u; place < OPCODE_COUNT; place += 1u)
    {
        const int asked_of_ruleset = (place != (unsigned int)OPCODE_PROGRAM_UNIT) || (writes_unit != 0);
        decided += (asked[place] != 0u) ? 1u : 0u;
        if ((asked[place] != 0u) && asked_of_ruleset && (lane_form_errors(rules, place) != 0))
        {
            blocking += 1u;
            printf("  %-24s asked %u times\n", s_forms[place].text, asked[place]);
        }
    }
    if (writes_unit == 0)
    {
        printf("  (program_unit is asked %u times by the lane's items and never of the ruleset: SASS takes its\n"
               "   resident from the part's own compiler and writes the lane into that cubin)\n",
               asked[OPCODE_PROGRAM_UNIT]);
    }
    printf("forms sass.krs gives as an error that no lane here asks for:\n");
    for (unsigned int place = 0u; place < OPCODE_COUNT; place += 1u)
    {
        if ((asked[place] == 0u) && (lane_form_errors(rules, place) != 0))
        {
            printf("  %-24s never asked\n", s_forms[place].text);
        }
    }
    printf("%u of the schema's %u forms are asked for; %u of those sass.krs gives as an error\n", decided, OPCODE_COUNT,
           blocking);
    return 0;
}
