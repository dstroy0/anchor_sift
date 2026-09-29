// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sass_target.h"

// the lane as SASS: sass.krs, which a cubin writer assembles, its header the listing's own opening
SassTarget::SassTarget(void) : CodeGenerator("sass.krs", "cubin", "probe_nvdisasm", SCHEDULE_UNBOUNDED, 0)
{
}

// R0 through R237. The part has 255 numbered registers and RZ, of which sass.krs pins the top for the lane's own:
// R240 up are its fixed registers, and R238 and R239 are the launch the lane was called with, which open_launch moves
// there and launch_load reads every parameter through. A lane whose banks reach R238 is refused, in place of writing
// over the address its own parameters come from. This is the file's count and not what a lane can take and stay
// fast: an SM holds 65536 registers and runs 1536 threads, so 42 a thread is full occupancy and every one past that
// costs residency
unsigned int SassTarget::register_file_holds(void) const
{
    return 238u;
}

// The resident reaches SASS already built. ptx.krs holds it as 110 instructions of PTX that run, the part's own
// compiler turns those into 248 SASS instructions that run, and a program is put together by writing the lane into
// that cubin's cycle_lane, leaving cycle_program as the compiler wrote it (asked of the part 29 Sep: 247 of the
// resident's 248 instructions came through a lane going in, the one that did not being the empty lane's own).
// sass.krs gives program_unit as an error for that reason, and the form is left out here in place of being asked
// for
int SassTarget::program_unit_written(void) const
{
    return 0;
}

SassTarget &sass_target(void)
{
    static SassTarget generator;
    return generator;
}
