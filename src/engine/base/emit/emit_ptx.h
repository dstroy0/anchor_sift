// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_PTX_H
#define EMIT_PTX_H

// The lane as PTX, a language of the register lane (emit_lane.h): its ruleset is ptx.krs, nvJitLink assembles it, and
// its header is asked of NVRTC

#include "emit_lane.h"

class CycleEmitPtx : public CycleEmitLane
{
public:
    CycleEmitPtx(void);
};

// the PTX emitter a process holds, its ruleset read at its first call to ruleset()
CycleEmitPtx &cycle_emit_ptx(void);

#endif
