// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_ptx.h"

// the lane as PTX: ptx.krs, which nvJitLink assembles, its header asked of NVRTC
EmitPtx::EmitPtx(void) : EmitLane("ptx.krs", "nvjitlink", "probe_nvrtc", EMIT_LANE_UNBOUNDED, 0)
{
}

EmitPtx &emit_ptx(void)
{
    static EmitPtx emit;
    return emit;
}
