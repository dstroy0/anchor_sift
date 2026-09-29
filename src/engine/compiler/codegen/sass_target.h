// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SASS_TARGET_H
#define SASS_TARGET_H

// The lane as SASS, a language of the register lane (code_generator.h): its ruleset is sass.krs, read out of the
// cell's probes, and its header is the opening a listing carries, asked of nvdisasm. Nothing assembles its text yet,
// and sass.krs leaves empty every form no probe gave. No route writes a program with this generator: the cell's
// probes read it, to write their questions in the machine's own code

#include "code_generator.h"

class SassTarget : public CodeGenerator
{
  public:
    SassTarget(void);

    // the part holds one register file and the banks are laid into it end to end: R0 through R239, the registers
    // sass.krs does not pin (R240 through R253 are the lane's fixed words and wides, and RZ is R255)
    unsigned int register_file_holds(void) const override;

    int program_unit_written(void) const override;
};

// the SASS code generator a process holds, its ruleset read at its first call to ruleset()
SassTarget &sass_target(void);

#endif
