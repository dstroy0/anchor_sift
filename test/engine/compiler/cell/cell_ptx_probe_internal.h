// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the cell_ptx_probe_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef CELL_PTX_PROBE_INTERNAL_H
#define CELL_PTX_PROBE_INTERNAL_H

// A probe for the cell's PTX test (engine_table.md item 11(f) 4): questions asked of the device in the ruleset's own
// words. Each question's kernel is written from ptx.krs, one form by its name at a time (target.h), around a frame of
// this probe's own that loads a case's eight input words and stores four output words, and nvJitLink assembles it as
// the engine's PTX path does. The header is asked of NVRTC. One question a process, named by the first word:
//   membership   every arithmetic, test and conversion form the code generator writes, over 65,536 cases of input
//   words, each
//                answer checked against the host's integers; a form's answer where PTX leaves it undefined (a divisor
//                of 0) is printed and not checked. Exit 0 where every defined answer agrees, 1 where one does not
//   address      a load from address 16, which no allocation holds
//   misaligned   a 32-bit load from an address one byte past an allocation's start
//   trap         PTX's trap instruction
//   lacking      elect.sync, which PTX gives sm_90 and later, in a kernel for this device
//   alive        one form over one case, to show a fresh process's device answers
// A question the device refuses prints "error <code> <name>" for the CUDA error it gave, then the error the next
// allocation gives, "after <code> <name>", and exits 3. One the toolchain refuses prints "refused" and its log, and
// exits 4. Exit 2 where the probe could not ask at all
#include "../../../../src/engine/compiler/codegen/ptx_target.h"

#include <cuda_runtime.h>
#include <nvJitLink.h>
#include <nvrtc.h>

#include <stdio.h>
#include <string.h>

#include <functional>
#include <string>
#include <vector>

#define PROBE_CASES 65536u
#define PROBE_IN_WORDS 8u
#define PROBE_OUT_WORDS 4u
#define PROBE_THREADS 256u
// the operands every case draws most of its words from, the edges of 32-bit arithmetic and of a shift
#define PROBE_EDGES 14u

// the answer the host's integers give a case: the output words, and 0 where the rule leaves the answer undefined
typedef std::function<int(const unsigned int *in, unsigned int *out)> ProbeRule;

// one question: its name, the forms that ask it as the kernel's body, the output words it writes and the host's rule
struct ProbeQuestion
{
    std::string name;
    std::string body;
    unsigned int outputs;
    ProbeRule rule;
};

// the registers of each bank a kernel declares: the questions' own below, and above them the scratch a construct
// takes, numbered on through the whole process so that no two scratch registers share a number
#define PROBE_TEMPORARIES 12u
#define PROBE_WIDES 4u
#define PROBE_PREDICATES 4u
#define PROBE_DECLARED 1024u

// the ruleset's written forms and a writer for its forms, which marks the text broken where a form is not written; the
// next scratch register of each bank a construct may take
struct ProbeWriter
{
    const Ruleset *rules;
    int broken;
    unsigned int scratch_temporary;
    unsigned int scratch_wide;
    unsigned int scratch_predicate;
};

std::string probe_temporary(ProbeWriter *writer, unsigned int number);

std::string probe_wide(ProbeWriter *writer, unsigned int number);

void probe_form(ProbeWriter *writer, std::string &text, const char *name, const std::vector<std::string> &arguments);

void probe_case(unsigned int number, unsigned int *in);

std::vector<ProbeQuestion> probe_questions(ProbeWriter *writer);

#endif
