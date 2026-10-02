// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef MONOLITH_H
#define MONOLITH_H

// What the monolith (monolith.cu) and its runner agree on: how a costed chain is laid out and where each section's
// count is written. C, read by both.
#include "../../../c/transpiler/codegen/precepts.h"

// the steps in one turn of a costed chain, unrolled; a run is `turns` of them
#define MONOLITH_BLOCK 100u

// the precepts costed: NOP, then NOT and every precept after it through SUB. ERR, BRA and JCC carry no word
#define MONOLITH_COSTED_COUNT 15u

// the precept at place `at_` of the costed run
#define MONOLITH_COSTED(at_) (((at_) == 0u) ? 0u : ((at_) + 1u))

// the costed pairs, each i <= j once, and every section: the singles, then the pairs
#define MONOLITH_PAIR_COUNT ((MONOLITH_COSTED_COUNT * (MONOLITH_COSTED_COUNT + 1u)) / 2u)
#define MONOLITH_SECTIONS (MONOLITH_COSTED_COUNT + MONOLITH_PAIR_COUNT)

// the section the pair of costed places `i_` <= `j_` writes to: past the singles, the rows before row i, then j's place
// in row i
#define MONOLITH_PAIR_SECTION(i_, j_)                                                                                  \
    (MONOLITH_COSTED_COUNT + ((i_) * MONOLITH_COSTED_COUNT) - (((i_) * ((i_) - 1u)) / 2u) + ((j_) - (i_)))

#endif
