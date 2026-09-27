// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_H
#define EMIT_H

// The emitter: a record program's lane written as text for its target, in that target's ruleset (emit/rulesets). It
// decides what each step does and the ruleset spells it. It reads no device and loads no library: the record machine
// (cycle/cycle.cu) names the target, and compiles, links, caches and launches what the emitter writes

#include "engine_config.h"

#include <string>

// the division operations' scratch per lane, in limbs: long division holds the normalized numerator (one limb
// over) and divisor; the gcd holds its three remainders ahead of that; the exact quotient holds the shifted
// numerator and divisor, the inverse with its step product, and the next inverse
#define CYCLE_RECORD_SCRATCH(wide_) ((5u * (wide_)) + 4u)

// what a compiled program's thread blocks share on the device across one run: the next lane to take, and within one
// launch its start, the thread blocks gone and the check-ins made, laid out as the kernel's own (s_cycle_prelude)
struct CycleHot
{
    unsigned long long next_lane;
    unsigned long long launch_start;
    unsigned long long finished;
    unsigned long long checkins;
};

// the compiled program's argument, laid out as the kernel's own (s_cycle_prelude) declares it: the block is the
// program's EngineProgramBlock as 64-bit words, at its device address, and places a thread's registers in shared memory
struct CycleCompiledLaunch
{
    const unsigned int *in[ENGINE_RECORD_MEMBERS_MAX];
    const unsigned int *index;
    const unsigned int *tables;
    unsigned int *out;
    unsigned int *refused;
    unsigned long long bodies[ENGINE_RECORD_MEMBERS_MAX];
    unsigned long long count;
    CycleHot *hot;
    unsigned long long *block;
    unsigned long long ttl;
    unsigned long long checkin_every;
    unsigned long long launch_number;
    unsigned long long places;
};

// what a lane is written against, which its first line names: the operator block it is linked with, by its hash, the
// device's compute capability, NVRTC's version, and the prelude a lane as C source opens with
struct CycleEmitTarget
{
    unsigned long long block_hash;
    int major;
    int minor;
    int nvrtc_major;
    int nvrtc_minor;
    const char *prelude;
};

// a ruleset read against its emitter's schema, held once a process
struct CycleRuleset;

// ptx.krs; NULL where it is refused
const CycleRuleset *cycle_ruleset_ptx(int report);

// c.krs; NULL where it is refused
const CycleRuleset *cycle_ruleset_source(int report);

// a thread's places for a program as C source: the file's, then the scratch's
unsigned int cycle_program_places(const EngineRecordLayout *layout);

// a program's lane as C source in `rules`; empty where the program is one it does not hold
std::string cycle_program_source(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                                 const CycleRuleset *rules);

// a program's lane as PTX in `rules` under `header`, the places a thread holds and the most words live at once; empty
// where the program is one it does not hold
std::string cycle_program_ptx(const EngineRecordLayout *layout, const CycleEmitTarget *target,
                              const CycleRuleset *rules, const std::string &header, unsigned int *places,
                              unsigned int *live);

#endif
