// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "vhdl_target.h"

// the lane as VHDL: vhdl.krs, which GHDL analyzes, its opening lines the ruleset's own lane_open; its memory has one
// write port
VhdlTarget::VhdlTarget(void) : CodeGenerator("vhdl.krs", "ghdl", "lane_open", 1u, 0)
{
}

// with no construction set every form costs nothing, and nothing but the write port bounds a state
const ScheduleModel *VhdlTarget::program_schedule_model(void) const
{
    static const ScheduleModel unbounded = {{}, 0u, SCHEDULE_UNBOUNDED, SCHEDULE_UNBOUNDED};
    return &unbounded;
}

VhdlTarget &vhdl_target(void)
{
    static VhdlTarget generator;
    return generator;
}
