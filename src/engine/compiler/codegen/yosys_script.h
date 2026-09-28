// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef YOSYS_SCRIPT_H
#define YOSYS_SCRIPT_H

// Yosys's synthesis of a lane GHDL wrote as Verilog, as a script its ruleset yosys.krs writes: which passes run is the
// ruleset's, not the caller's. It writes no lane: program() is always empty, and synthesis() writes the script

#include "target.h"

class YosysScript : public Target
{
  public:
    YosysScript(void);

    std::string program(const EngineRecordLayout *layout, const TargetInfo *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;

    // the script that reads `source`, synthesizes it from the module `top` and measures it, and where `memories` is not
    // empty, writes the coarse netlist's statistics to the log `memories` before the fine stage; empty where the
    // ruleset is not read
    std::string synthesis(const std::string &source, const std::string &top, const std::string &memories);
};

// the Yosys script a process holds, its ruleset read at its first call to ruleset()
YosysScript &yosys_script(void);

#endif
