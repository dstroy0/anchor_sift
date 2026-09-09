#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Choosing which of a pattern's points to test first, and what that choice is allowed to affect.
#
#   Usage:  from sift.anchors import rarest, spread, jittered, cell_rarest, survivors
#
# The selection rule is free, and that freedom is why a rule exists at all. An anchor is a condition
# copied out of the pattern, so any position genuinely holding the pattern satisfies every anchor,
# whatever chose it. Correctness cannot turn on the rule. The rule moves how many false candidates
# survive, and that is cost.
#
# The C side measures this directly: three rules that share nothing, a sweep of one to eight anchors
# over fourteen geometries. The refusal column reads hold on every row while the candidate column
# moves with the rule. The two columns are graded to different standards: a refusal is a defect, a
# candidate count is a cost.
#
# What the rules trade against each other, measured. Taking the rarest symbols in the needle is the
# best filter and the worst sizer, at a sizing error of 20992 times on English prose while passing
# 15.0 alignments. Spacing the offsets evenly reads nothing of the needle at all and sizes honestly,
# at 2.02 times, while passing 345.8. Neither dominates, and which is right depends on whether
# survivors are verified and discarded or buffered and handed on, since under-provisioning is a
# performance question in the first case and a correctness question in the second.
#
# The best measured filter is the rarest symbol inside each evenly sized cell, which asks for rarity
# and separation together instead of trading one against the other. It passes 5.0 alignments on
# English prose against 15.9 for rarity alone, and brings the median sizing error to 1.11 from 3.55.
# It is not the rule the C kernel uses.

import random


def rarest(needle, counts, wanted):
    """The `wanted` offsets whose symbols occur least often in the corpus.

    The best filter measured and the worst sizer. It selects, by construction, the symbols least
    likely to be positioned independently, since the rare half of a distribution is the half whose
    occurrences gather into passages. A cascade of them therefore survives more often than a product
    of their rates predicts. That gap is the product rule error, seen from the other side.
    """
    return sorted(range(len(needle)), key=lambda index: counts[needle[index]])[:wanted]


def spread(needle_len, wanted):
    """Offsets spaced evenly, reading nothing of the needle at all.

    A rule that cannot examine what it is looking for can still choose where to look. That leaves
    this rule available on a domain whose alphabet has no frequencies to weigh.

    Its defect is that an even comb shares a period with whatever the domain carries. On a corpus of
    period sixteen every anchor lands congruent modulo sixteen, so four probes ask one question four
    times and the survival rate misses the histogram bound by a factor of 4096.
    """
    if wanted <= 1:
        return [0]
    step = (needle_len - 1) / float(wanted - 1)
    return [int(round(step * slot)) for slot in range(wanted)]


def jittered(needle_len, wanted, rng=None):
    """One offset drawn inside each evenly sized cell, keeping the spread and breaking the comb.

    The anchor set then has no period of its own, and even spacing does. Measured, this beats even
    spacing on both corpora tested and passes fewer alignments on English, 337.2 against 345.8.
    """
    draw = rng if rng is not None else random.Random(0x51F7)
    cell = needle_len / float(wanted)
    return [min(needle_len - 1, int(cell * slot) + draw.randrange(max(1, int(cell))))
            for slot in range(wanted)]


def cell_rarest(needle, counts, wanted):
    """The rarest symbol inside each evenly sized cell, asking for rarity and separation together.

    The best filter measured here, and not the one in use. Three anchors over 60 needles pass a mean
    of 5.0 alignments on English prose against 15.9 for global rarity, and 25.4 against 44.1 on C
    source. On a memoryless corpus it costs 1.6 times, passing 6.4 against 3.9, because the cells
    prevent it from taking the three globally rarest symbols. There is no structure to exploit there
    and the cells are pure overhead.
    """
    needle_len = len(needle)
    cell = needle_len / float(wanted)
    picked = []
    for slot in range(wanted):
        low = int(cell * slot)
        high = max(low + 1, min(needle_len, int(cell * (slot + 1))))
        picked.append(min(range(low, high), key=lambda index: counts[needle[index]]))
    return picked


def survivors(places, needle, offsets):
    """Alignments where every anchor agrees, as an intersection of each anchor's own positions.

    `places` maps a symbol to the set of positions holding it. An alignment survives when every
    anchor matches. Taking each anchor's positions, shifting them back by where that anchor sits in
    the needle, and intersecting the results gives exactly those alignments. Because the anchors are
    rare symbols their position sets are short, and the cascade intersects short lists instead of
    scanning the corpus.
    """
    held = None
    for offset in offsets:
        shifted = {index - offset for index in places.get(needle[offset], ())}
        held = shifted if held is None else (held & shifted)
        if not held:
            break
    return held if held is not None else set()


def positions_by_symbol(seats):
    """Where each symbol occurs, as a set per symbol. `survivors` intersects these."""
    places = {}
    for index, value in enumerate(seats):
        places.setdefault(value, set()).add(index)
    return places
