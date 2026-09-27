// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_LANE_H
#define EMIT_LANE_H

// The register lane, a shape of the emitter that names no language: each step unrolled at its widths into
// straight-line text over registers the lane holds itself, every line a form of the language's ruleset. A language of
// this shape is a class that inherits it and names its ruleset's file, the toolchain that builds its text and where
// its header comes from (emit_ptx.h)

#include "emit.h"

class CycleEmitLane : public CycleEmit
{
public:
    std::string program(const EngineRecordLayout *layout, const CycleEmitTarget *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;

protected:
    CycleEmitLane(const char *file, const char *toolchain, const char *header);
};

#endif
