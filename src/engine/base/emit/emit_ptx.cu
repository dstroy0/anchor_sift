// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_ptx.h"

// the lane as PTX: ptx.krs, which nvJitLink assembles, its header asked of NVRTC
CycleEmitPtx::CycleEmitPtx(void) : CycleEmitLane("ptx.krs", "nvjitlink", "probe_nvrtc")
{
}

CycleEmitPtx &cycle_emit_ptx(void)
{
    static CycleEmitPtx emit;
    return emit;
}
