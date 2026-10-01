// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TARGET_H
#define TARGET_H

// The code generator: a record program's lane written as text for its target, in that target's ruleset
// (codegen/rulesets). It decides what each step does and the ruleset writes it. It reads no device and loads no
// library: the record machine (cycle/cycle_{sweep,launch}.cu) picks the language, and compiles, links, caches and
// launches what the code generator writes. This header is the base every language inherits; each language's class is in
// its own header

#include "engine_config.h"

#include <functional>
#include <string>
#include <vector>

// the division operations' scratch per lane, in limbs: long division holds the normalized numerator (one limb
// over) and divisor; the gcd holds its three remainders ahead of that; the exact quotient holds the shifted
// numerator and divisor, the inverse with its step product, and the next inverse
#define CODEGEN_RECORD_SCRATCH(wide_) ((5u * (wide_)) + 4u)

// what a compiled program's thread blocks share on the device across one run: the next lane to take, and within one
// launch its start, the thread blocks gone and the check-ins made, laid out as the kernel's own (s_cycle_prelude)
struct CycleHot
{
    unsigned long long next_lane;
    unsigned long long launch_start;
    unsigned long long finished;
    unsigned long long checkins;
};

// the compiled program's argument, laid out as the kernel's own (g_cycle_prelude) declares it: the block is the
// program's EngineProgramBlock as 64-bit words, at its device address, and places a thread's registers in shared memory
struct CycleCompiledLaunch
{
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *error;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    CycleHot *hot;
    unsigned long long *block;
    unsigned long long ttl;
    unsigned long long checkin_every;
    unsigned long long launch_number;
    unsigned long long places;
};

// what a lane is written for, which its first line names: the target, by the hash of its text (the device, the kind
// of link and the prelude), the device's compute capability, NVRTC's version, and the prelude a lane as C source opens
// with
struct TargetInfo
{
    unsigned long long block_hash;
    int major;
    int minor;
    int nvrtc_major;
    int nvrtc_minor;
    const char *prelude;
};

// the place among a lane's forms of a text a code generator takes whole and writes as no form, a header
// (codegen_core.h, MachineInstr)
#define ASM_PRINTER_ALL_ONES 0xFFFFFFFFu

// a ruleset read against its code generator's schema, held once a process
struct Ruleset;

// what a language's code generator asks of its ruleset (ruleset_reader.h)
struct RulesetSchema;

// The code generator's base: what every language shares, and no language. It reads a language's ruleset from its .krs
// file against the schema the language gives it (the file, the toolchain and header its path builds with, and the
// forms, banks and fixed registers its code generator writes), and writes forms in it. A language is a class that
// inherits it, in a file of its own (ptx_target.h, c_target.h), and writes a program's lane in its ruleset
class Target
{
  public:
    Target(const Target &) = delete;
    Target &operator=(const Target &) = delete;
    virtual ~Target();

    // the language's ruleset, read once a process; NULL where it errors, `report` saying which on stderr
    const Ruleset *ruleset(int report);

    // a program's lane in the language under `header`, the places a thread holds in shared memory and the most words
    // it holds live at once (0 where the language does not reckon them); empty where the ruleset is not read, or the
    // program is one the language does not hold
    virtual std::string program(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                                unsigned int *places, unsigned int *live) = 0;

  protected:
    explicit Target(const RulesetSchema *schema);

    // the ruleset once ruleset() has read it, else NULL
    const Ruleset *ready(void) const;

  private:
    Ruleset *rules;
};

// A ruleset read from outside the code generator, by the names its .krs file gives, for a probe that asks the target
// how it answers each form (the cell's membership queries, engine_table.md item 11(f) 4). The code generator itself
// writes by the places in its schema

// form `name` appended to `text`, its arguments in the order of its parameters; 0, and nothing written, where the
// ruleset writes no form of that name or the form takes another count of arguments. Where the ruleset gives the form
// as a construct (a line `construct <name> <parameter>...`, its lines to `end`), each scratch register {bank:n} it
// names is asked of `scratch` by the bank's name once a writing, and 0 where `scratch` answers empty
int ruleset_opcode(const Ruleset *rules, const std::string &name, const std::vector<std::string> &arguments,
                   const std::function<std::string(const std::string &bank)> &scratch, std::string &text);

// register `number` of the bank `bank`; empty where the ruleset has no bank of that name
std::string ruleset_register(const Ruleset *rules, const std::string &bank, unsigned int number);

// the register every lane holds throughout named `name`; empty where the ruleset holds none of that name
std::string ruleset_physreg(const Ruleset *rules, const std::string &name);

#endif
