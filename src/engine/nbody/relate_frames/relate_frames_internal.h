// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the relate_frames_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RELATE_FRAMES_INTERNAL_H
#define RELATE_FRAMES_INTERNAL_H

#include "relate_frames.h"

#include "body_overlap.h"
#include "climb_machine.h"
#include "golden_bands.h"
#include "shift_agreement.h"
#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int cast_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later);

int still_triples(EngineBuffers *buffers, TreeFrame *earlier, const TreeFrame *later);

#endif
