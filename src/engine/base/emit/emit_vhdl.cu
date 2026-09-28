// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_vhdl.h"

// the lane as VHDL: vhdl.krs, which GHDL analyzes, its opening lines the ruleset's own lane_open; its memory has one
// write port
EmitVhdl::EmitVhdl(void) : EmitLane("vhdl.krs", "ghdl", "lane_open", 1u, 0)
{
}

// with no construction set every form costs nothing, and nothing but the write port bounds a state
const EmitLaneShape *EmitVhdl::program_shape(void) const
{
    static const EmitLaneShape unbounded = {{}, 0u, EMIT_LANE_UNBOUNDED, EMIT_LANE_UNBOUNDED};
    return &unbounded;
}

EmitVhdl &emit_vhdl(void)
{
    static EmitVhdl emit;
    return emit;
}
