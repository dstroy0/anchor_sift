// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef STEM_GROUP_H
#define STEM_GROUP_H

// Which members share a stem: groups built on an anchor, by a rule that reads only the members.
//
// Agreement between two members is taken at the coarser of their two floors, and there it is symmetric and still
// not transitive: a first member can agree with a second and the second with a third while the first and the third
// do not. Pairwise agreement names no set, and grouping by it gives an answer that turns on which member was asked
// first. A group here is anchored on one member, and every member of it agrees with that anchor.
//
// The rule. The members are put in one order fixed by what they are: the finest floor first, and between two
// floors alike, by their rows, then by their mark of which rows were measured. The first member with no group
// anchors a new one, and every member with no group that agrees with that anchor joins it. That is repeated until
// every member has a group. The finest member anchors because its answers are the sharpest, and a group read off
// its anchor is read at the floor the anchor can tell apart.
//
// Agreement is a conjunction over rows: every row both members measured differs by no more than the coarser floor,
// and a row one member measured and the other did not separates them. A refused or censored row is an answer, and
// two members that cost the same and differ in what they refused are two members.
//
// What follows from the rule, and what stem_group_check.c holds: every member agrees with its anchor; no anchor
// agrees with an anchor placed before it; and the groups are the same whatever order the members are given in. A
// group is a function of the whole set. A member added to the set can change which member anchors and so which
// members share a stem, and every block written for a group is written again when the set changes.
//
// Every value is an exact integer.

// the most rows one member carries
#define STEM_GROUP_ROWS 64u
// the most members one set holds
#define STEM_GROUP_MEMBERS 256u
// the group a member is given before the rule has placed it
#define STEM_GROUP_NONE 0xffffffffu

// one member: a cost a row, which rows were measured, and the floor the member carries
typedef struct
{
    unsigned long long cost[STEM_GROUP_ROWS];
    // 1 where the row was measured, 0 where it was refused, censored or never asked
    unsigned char measured[STEM_GROUP_ROWS];
    unsigned long long floor;
} StemMember;

// 1 where `one` and `two` agree over `rows` rows at the coarser of their two floors
int stem_group_agree(const StemMember *one, const StemMember *two, unsigned int rows);

// The `count` members grouped by the rule: `group[member]` the index of the member that anchors its group. The count
// of groups, or 0 where `count` or `rows` is past what a set holds
unsigned int stem_group_build(const StemMember *member, unsigned int count, unsigned int rows, unsigned int *group);

#endif
