// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CHAIN_BUILD_H
#define CHAIN_BUILD_H

// Every arrangement of primitives that produces a relation.
//
// An operator is a chain, and a chain can be rearranged. A person writing a compiler affords one arrangement for
// each operator, because a person has to write it. Nobody writes these. Every arrangement that works is kept and a
// job takes the one that suits it. What separates the arrangements is cost, and cost is measured on the target.
// Finding them is this file's part of it.
//
// A chain is kept when it answers every case of the relation. The cases are arithmetic and the chain is run over
// them here, with no target involved: a chain that fails a case is wrong everywhere, and there is no reason to ask a
// target about it. A chain that passes is a candidate the target may or may not be able to write.

#include "../codegen/precept_value.h"
#include "ladder.h"

// the most nodes a chain holds. One node is the target having the operator outright, two and three are the
// arrangements worth weighing against one another
#define CHAIN_NODES 3u
// the most chains kept for one relation
#define CHAIN_MOST 2048u
// how many words past the cases an arrangement is put with before it is kept
#define CHAIN_SWEEP 512u

typedef struct
{
    PreceptNode node[CHAIN_NODES];
    unsigned int nodes;
} Chain;

typedef struct
{
    Chain chain[CHAIN_MOST];
    unsigned int chains;
    // arrangements that answered every case and had nowhere to go
    unsigned int over;
    // arrangements tried
    unsigned int tried;
    // arrangements the cases alone let through: all a ladder that stopped at its own cases would hold
    unsigned int fitted;
} ChainSet;

// Every chain of at most CHAIN_NODES nodes that answers `cases` and the relation they belong to, into `set`. The
// count kept. Shorter chains are found first: a set that fills holds the shortest arrangements there are
unsigned int chain_build(ChainSet *set, const LadderQuestion *cases, unsigned int count);

// The same, with `swept` saying whether an arrangement is put with words past the cases before it is kept. Built
// without the sweep, a set holds every arrangement that fits the cases and nothing says which of those is the
// relation: that is a reading of how much the ladder's own cases decide, and it is not a set to derive from
unsigned int chain_build_cases(ChainSet *set, const LadderQuestion *cases, unsigned int count, int swept);

// `set` put into a new order, from `seed`.
//
// The walk finds arrangements in the order it happens to walk them, and that order is a bias of the walk. Timed in
// it, a chain's reading carries where it sat: the first of a run pays for a cold part and the rest do not, and an
// arrangement that only ever gets timed first only ever reads slow. Shuffled, that washes out over runs and leaves
// the difference between the arrangements. A cost from one run is a reading; a cost from many runs put in a
// different order each time is a preference
void chain_shuffle(ChainSet *set, unsigned int seed);

// `chain` written into `text`, which holds `room`, as the operator applied to its operands. The count written
unsigned int chain_text(const Chain *chain, char *text, unsigned int room);

#endif
