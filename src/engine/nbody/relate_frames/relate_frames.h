// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RELATE_FRAMES_H
#define RELATE_FRAMES_H

#include "track.h"

int frame_contacts(const TreeFrame *tree, unsigned int **contact_start, unsigned int **contacts);

int relate_frames(EngineBuffers *buffers, TreeFrame *earlier, TreeFrame *later, const TreeRules *rules,
                         StageClock *clocks);

unsigned long long leaf_disagreement(const TreeFrame *earlier, unsigned int leaf, const TreeFrame *later,
                                            unsigned int other, const unsigned int *band);

unsigned long long track_bend(const TreeFrame *before, const TreeFrame *earlier, unsigned int object,
                                     const TreeFrame *later, unsigned int candidate, const TreeFrame *after,
                                     unsigned int by_band);

#endif
