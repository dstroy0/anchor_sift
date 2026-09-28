// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the link_objects_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef LINK_OBJECTS_INTERNAL_H
#define LINK_OBJECTS_INTERNAL_H

#include "link_objects.h"

#include "golden_bands.h"
#include "radix_keys.h"
#include "relate_frames.h"
#include "track.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DAMP_DIMENSIONS 3u

#define SETTLE_ROUNDS 64u

#define FOCUS_PASSES 8u

#define FOCUS_MEMBERS 4u

unsigned long long web_count(const TreeFrame *earlier, unsigned int object, const TreeFrame *later,
                             unsigned int candidate, const unsigned int *near_start, const unsigned int *nearby,
                             const unsigned int *later_near_start, const unsigned int *later_nearby, unsigned int *seen,
                             unsigned int mark);

int settle_links(TreeFrame *earlier, const TreeFrame *later);

void link_objects_mutual(TreeFrame *earlier, const TreeFrame *later, unsigned int objects);

void link_objects_forest(TreeFrame *earlier, const TreeFrame *later, unsigned int objects);

#endif
