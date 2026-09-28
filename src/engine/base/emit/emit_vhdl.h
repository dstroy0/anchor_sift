// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_VHDL_H
#define EMIT_VHDL_H

// The lane as VHDL-2008, a language of the register lane (emit_lane.h): its ruleset is vhdl.krs, GHDL analyzes and
// runs it, and its opening lines are the ruleset's own lane_open; the header it is given is empty. The lane is a
// clocked process, and its text is always cut into states: program() cuts it only where the lane itself must be cut,
// at each refusal and each return, and shaped() cuts it by a target's construction set as well

#include "emit_lane.h"

class EmitVhdl : public EmitLane
{
public:
    EmitVhdl(void);

    const EmitLaneShape *program_shape(void) const override;
};

// the VHDL emitter a process holds, its ruleset read at its first call to ruleset()
EmitVhdl &emit_vhdl(void);

#endif
