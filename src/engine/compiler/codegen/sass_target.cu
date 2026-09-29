// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sass_target.h"

// the lane as SASS: sass.krs, which a cubin writer assembles, its header the listing's own opening
SassTarget::SassTarget(void) : CodeGenerator("sass.krs", "cubin", "probe_nvdisasm", SCHEDULE_UNBOUNDED, 0)
{
}

unsigned int SassTarget::register_file_holds(void) const
{
    return 240u;
}

SassTarget &sass_target(void)
{
    static SassTarget generator;
    return generator;
}
