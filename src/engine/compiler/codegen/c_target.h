// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef C_TARGET_H
#define C_TARGET_H

// The lane as C source, a language of the register lane (code_generator.h): its ruleset is c.krs, NVRTC compiles it,
// and its header is the prelude. It lays out the file and its signs in the thread block's shared memory. A program
// whose PTX holds too great a local frame runs from a small one as C (rule (i), cycle_compile_*.cu)

#include "code_generator.h"

class CTarget : public CodeGenerator
{
  public:
    CTarget(void);
};

// the C source's code generator a process holds, its ruleset read at its first call to ruleset()
CTarget &c_target(void);

#endif
