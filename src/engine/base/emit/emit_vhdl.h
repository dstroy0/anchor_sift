// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_VHDL_H
#define EMIT_VHDL_H

// The lane as VHDL-2008, a language of the register lane (emit_lane.h): its ruleset is vhdl.krs, GHDL analyzes and
// runs it, and its opening lines are the ruleset's own lane_open, so the header it is given is empty

#include "emit_lane.h"

class CycleEmitVhdl : public CycleEmitLane
{
public:
    CycleEmitVhdl(void);
};

// the VHDL emitter a process holds, its ruleset read at its first call to ruleset()
CycleEmitVhdl &cycle_emit_vhdl(void);

#endif
