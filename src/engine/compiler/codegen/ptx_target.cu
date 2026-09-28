// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "ptx_target.h"

// the lane as PTX: ptx.krs, which nvJitLink assembles, its header asked of NVRTC
PtxTarget::PtxTarget(void) : CodeGenerator("ptx.krs", "nvjitlink", "probe_nvrtc", SCHEDULE_UNBOUNDED, 0)
{
}

PtxTarget &ptx_target(void)
{
    static PtxTarget generator;
    return generator;
}
