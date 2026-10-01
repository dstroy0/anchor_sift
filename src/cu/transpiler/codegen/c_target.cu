// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "c_target.h"

// the lane as C source: c.krs, which NVRTC compiles under the prelude, its file and signs in shared memory
CTarget::CTarget(void) : CodeGenerator("c.krs", "nvrtc", "prelude", SCHEDULE_UNBOUNDED, 1)
{
}

CTarget &c_target(void)
{
    static CTarget generator;
    return generator;
}
