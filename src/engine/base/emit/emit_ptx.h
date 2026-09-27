// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_PTX_H
#define EMIT_PTX_H

// The lane as PTX, a language of the emitter: its ruleset is ptx.krs, nvJitLink assembles it against the operator
// block, and its header is asked of NVRTC. Each step is unrolled at its widths into straight-line PTX over registers
// the lane holds itself, and the steps that loop on their values call into the operator block

#include "emit.h"

class CycleEmitPtx : public CycleEmit
{
public:
    CycleEmitPtx(void);

    std::string program(const EngineRecordLayout *layout, const CycleEmitTarget *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;
};

// the PTX emitter a process holds, its ruleset read at its first call to ruleset()
CycleEmitPtx &cycle_emit_ptx(void);

#endif
