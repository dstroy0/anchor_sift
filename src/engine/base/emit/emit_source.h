// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_SOURCE_H
#define EMIT_SOURCE_H

// The lane as C source, a language of the emitter: its ruleset is c.krs, NVRTC compiles it, and its header is the
// operator block's prelude. Each step is one call into the operator block, whose registers are its places in shared
// memory, so the lane holds none of its own

#include "emit.h"

class CycleEmitSource : public CycleEmit
{
public:
    CycleEmitSource(void);

    std::string program(const EngineRecordLayout *layout, const CycleEmitTarget *target, const std::string &header,
                        unsigned int *places, unsigned int *live) override;
};

// the C source's emitter a process holds, its ruleset read at its first call to ruleset()
CycleEmitSource &cycle_emit_source(void);

#endif
