// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef VHDL_TARGET_H
#define VHDL_TARGET_H

// The lane as VHDL-2008, a language of the register lane (code_generator.h): its ruleset is vhdl.krs, GHDL analyzes and
// runs it, and its opening lines are the ruleset's own lane_open; the header it is given is empty. The lane is a
// clocked process, and its text is always split into states: program() splits it only where the lane itself must be
// split, at each error and each return, and scheduled() splits it by a target's construction set as well

#include "code_generator.h"

class VhdlTarget : public CodeGenerator
{
  public:
    VhdlTarget(void);

    const ScheduleModel *program_schedule_model(void) const override;
};

// the VHDL code generator a process holds, its ruleset read at its first call to ruleset()
VhdlTarget &vhdl_target(void);

#endif
