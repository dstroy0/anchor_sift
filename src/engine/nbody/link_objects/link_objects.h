// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef LINK_OBJECTS_H
#define LINK_OBJECTS_H

#include "track.h"

extern unsigned long long g_mutual_alone;

extern unsigned long long g_mutual_split;

extern unsigned long long g_mutual_empty;

extern unsigned long long g_mutual_moved;

extern unsigned long long g_damp_leaves;

extern unsigned long long g_damp_landings;

unsigned long long web_count(const TreeFrame *earlier, unsigned int object, const TreeFrame *later,
                                    unsigned int candidate, const unsigned int *near_start,
                                    const unsigned int *nearby, const unsigned int *later_near_start,
                                    const unsigned int *later_nearby, unsigned int *seen, unsigned int mark);

extern unsigned long long g_web_asked;

extern unsigned long long g_web_moved;

extern unsigned long long g_web_capped;

unsigned int focus_links(TreeFrame *frames, unsigned int frame_count, unsigned int by_band);

int link_objects_unbound(TreeFrame *earlier, const TreeFrame *later, const TreeFrame *before,
                                const TreeFrame *after, const TreeRules *rules);

int link_objects(TreeFrame *earlier, const TreeFrame *later, const TreeRules *rules);

#endif
