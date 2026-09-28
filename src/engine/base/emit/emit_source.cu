// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_source.h"

// the lane as C source: c.krs, which NVRTC compiles under the prelude, its file and signs in shared memory
EmitSource::EmitSource(void) : EmitLane("c.krs", "nvrtc", "prelude", EMIT_LANE_UNBOUNDED, 1)
{
}

EmitSource &emit_source(void)
{
    static EmitSource emit;
    return emit;
}
