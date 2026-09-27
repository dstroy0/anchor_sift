// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "emit_vhdl.h"

// the lane as VHDL: vhdl.krs, which GHDL analyzes, its opening lines the ruleset's own lane_open
CycleEmitVhdl::CycleEmitVhdl(void) : CycleEmitLane("vhdl.krs", "ghdl", "lane_open")
{
}

CycleEmitVhdl &cycle_emit_vhdl(void)
{
    static CycleEmitVhdl emit;
    return emit;
}
