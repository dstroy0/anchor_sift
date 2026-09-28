// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef EMIT_SOURCE_H
#define EMIT_SOURCE_H

// The lane as C source, a language of the register lane (emit_lane.h): its ruleset is c.krs, NVRTC compiles it, and
// its header is the prelude. It lays the file and its signs in the thread block's shared memory. A program whose PTX
// holds too great a local frame runs from a small one as C (rule (i), cycle_compile.cu)

#include "emit_lane.h"

class EmitSource : public EmitLane
{
public:
    EmitSource(void);
};

// the C source's emitter a process holds, its ruleset read at its first call to ruleset()
EmitSource &emit_source(void);

#endif
