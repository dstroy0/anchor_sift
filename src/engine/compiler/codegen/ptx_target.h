// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PTX_TARGET_H
#define PTX_TARGET_H

// The lane as PTX, a language of the register lane (code_generator.h): its ruleset is ptx.krs, nvJitLink assembles it,
// and its header is asked of NVRTC

#include "code_generator.h"

class PtxTarget : public CodeGenerator
{
  public:
    PtxTarget(void);
};

// the PTX code generator a process holds, its ruleset read at its first call to ruleset()
PtxTarget &ptx_target(void);

#endif
