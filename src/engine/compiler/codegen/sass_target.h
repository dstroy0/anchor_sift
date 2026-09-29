// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SASS_TARGET_H
#define SASS_TARGET_H

// The lane as SASS, a language of the register lane (code_generator.h): its ruleset is sass.krs, read out of the
// cell's probes, and its header is the opening a listing carries, asked of nvdisasm. Nothing assembles its text yet,
// and sass.krs leaves empty every form no probe gave, so no route writes a program with this generator: the cell's
// probes read it, to write their questions in the machine's own code

#include "code_generator.h"

class SassTarget : public CodeGenerator
{
  public:
    SassTarget(void);
};

// the SASS code generator a process holds, its ruleset read at its first call to ruleset()
SassTarget &sass_target(void);

#endif
