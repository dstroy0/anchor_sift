#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Choosing which of a pattern's points to test first, and what that choice is allowed to affect.
#
#   Usage:  from sift.anchors import rarest, spread, jittered, cell_rarest, survivors
#
# The selection rule is free, and that freedom is why a rule exists at all. An anchor is a condition
# copied out of the pattern. Any position genuinely holding the pattern satisfies every anchor,
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
#
# WHICH OF THESE THE ENGINE HOLDS IN C
#
# The kernel is src/engine/nbody/anchor_sift/anchor_sift_*.c. Its placement is choose_offsets, one
# offset in each evenly sized cell at (slot * 7) mod the cell, and its order is
# anchor_steer_probe_order, a stable sort of the placed offsets by rarity in the corpus. The
# functions below the rules, under the kernel's names, are its Python route at anchor_sift 1789287:
# choose_offsets, field_census, steer_magnitude, steer_probe_order, steer_prefers_free,
# sift_anchors_for, sift_choose, sift_count (the naive, in order and free order engines, with the
# reads a counted build tallies), sift_run, steer_count, steer_probe_fits and
# steer_count_with_probes. test/python/sift_test.py grades them against the kernel built alone,
# count for count and read for read, and the two share no code. The kernel's descents, its probe
# sweep and its field projections have no Python route here. rarest, spread, jittered,
# cell_rarest, survivors and positions_by_symbol have no C counterpart.

import collections
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
    period sixteen every anchor lands congruent modulo sixteen. Four probes ask one question four
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


# The kernel's form, src/engine/nbody/anchor_sift/anchor_sift_*.c.

SIFT_ANCHORS = 4
SYMBOLS = 256

Census = collections.namedtuple("Census", ["occurrences", "total", "distinct"])
Sifted = collections.namedtuple("Sifted", ["found", "probes", "verifications"])
Probe = collections.namedtuple("Probe", ["origin", "step", "length"])


def choose_offsets(wanted, needle_len):
    """The kernel's placement: in each of `wanted` evenly sized cells, the offset (slot * 7) mod the cell.

    A cell of one or none places each anchor at its cell's start, and an offset past the needle is
    held at its last position. Every offset is 0 for an empty needle.
    """
    if needle_len == 0:
        return [0] * wanted
    cell = needle_len // wanted
    offsets = []
    for slot in range(wanted):
        inside = ((slot * 7) % cell) if cell > 1 else 0
        offsets.append(min((slot * cell) + inside, needle_len - 1))
    return offsets


def field_census(corpus):
    """How often each byte value occurs, the byte count, and how many values occur."""
    occurrences = [0] * SYMBOLS
    for value in corpus:
        occurrences[value] += 1
    return Census(occurrences, len(corpus), sum(1 for count in occurrences if count))


def steer_magnitude(census, symbol):
    """The byte count less the symbol's own count: larger is rarer, in the order -log P gives."""
    return census.total - census.occurrences[symbol]


def steer_probe_order(offsets, census, needle):
    """The offsets ordered rarest symbol first, stably, as anchor_steer_probe_order leaves them.

    An insertion sort descending by magnitude that stops at an equal magnitude. An offset past the
    needle is not moved, and one already placed reads a magnitude of 0. Nothing moves for an empty
    needle or an empty census.
    """
    ordered = list(offsets)
    if not ordered or len(needle) == 0 or census.total == 0:
        return ordered
    for placed in range(1, len(ordered)):
        moving_offset = ordered[placed]
        if moving_offset >= len(needle):
            continue
        moving = steer_magnitude(census, needle[moving_offset])
        slot = placed
        while slot > 0:
            settled_offset = ordered[slot - 1]
            settled = steer_magnitude(census, needle[settled_offset]) if settled_offset < len(needle) else 0
            if settled >= moving:
                break
            ordered[slot] = ordered[slot - 1]
            slot -= 1
        ordered[slot] = moving_offset
    return ordered


def steer_prefers_free(census):
    """Whether the free order engine is taken: 100 * total^2 below 85 * distinct * sum(count^2).

    That is the effective alphabet total^2 / sum(count^2) below 85/100 of the values used, a skewed
    field. An empty field takes the short circuiting engine.
    """
    if census.total == 0 or census.distinct == 0:
        return False
    squares = sum(count * count for count in census.occurrences)
    return 100 * census.total * census.total < 85 * census.distinct * squares


def sift_anchors_for(period):
    """Anchors worth placing: 1 on a corpus that repeats at a period, 4 where none was found or none is known."""
    return 1 if period else SIFT_ANCHORS


def sift_choose(census):
    """The engine the dispatcher takes, by the kernel's name for it: naive with no census."""
    if census is None:
        return "naive"
    return "anchor_free" if steer_prefers_free(census) else "anchor_inorder"


def sift_count(corpus, needle, engine, anchors=SIFT_ANCHORS):
    """Exact occurrences of the needle by one engine, with the reads a counted build tallies.

    `engine` is "naive", "anchor_inorder" or "anchor_free". Returns Sifted(found, probes,
    verifications): the corpus bytes the anchor probes read and the exact compares made. An empty
    needle goes to the naive engine, which finds it at every alignment.
    """
    needle_len = len(needle)
    alignments = range(len(corpus) - needle_len + 1)
    if engine == "naive" or needle_len == 0:
        found = sum(1 for at in alignments if corpus[at:at + needle_len] == needle)
        return Sifted(found, 0, len(alignments))
    free = engine == "anchor_free"
    offsets = choose_offsets(SIFT_ANCHORS if free else anchors, needle_len)
    found = probes = verifications = 0
    for at in alignments:
        agreeing = [corpus[at + offset] == needle[offset] for offset in offsets]
        if free:
            probes += len(offsets)
        else:
            refuted = agreeing.index(False) if False in agreeing else len(offsets) - 1
            probes += refuted + 1
        if all(agreeing):
            verifications += 1
            found += 1 if corpus[at:at + needle_len] == needle else 0
    return Sifted(found, probes, verifications)


def sift_run(census, period, corpus, needle):
    """The count by the engine the dispatcher takes, the in order engine with sift_anchors_for's anchors."""
    engine = sift_choose(census)
    return sift_count(corpus, needle, engine, sift_anchors_for(period))


def steer_count(corpus, needle, steered):
    """Occurrences with the kernel's four offsets, ordered by rarity in this corpus where `steered` is set.

    Returns (found, probes), the probes being the corpus bytes read, or (0, 0) where the needle is
    longer than the corpus. An empty needle is found at every alignment with no probe read.
    """
    needle_len = len(needle)
    if needle_len > len(corpus):
        return 0, 0
    if needle_len == 0:
        return len(corpus) + 1, 0
    offsets = choose_offsets(SIFT_ANCHORS, needle_len)
    if steered:
        offsets = steer_probe_order(offsets, field_census(corpus), needle)
    return _probed(corpus, needle, [[offset] for offset in offsets])


def steer_probe_fits(probe, needle_len):
    """Whether every position a probe reads lands inside the needle, a line of length above one needing a step."""
    if probe.length == 0 or needle_len == 0 or probe.origin >= needle_len:
        return False
    if probe.length == 1:
        return True
    if probe.step == 0:
        return False
    return (probe.length - 1) <= (needle_len - 1 - probe.origin) // probe.step


def steer_count_with_probes(corpus, needle, probes):
    """Occurrences with the probes given, in the order given, as (found, probes read).

    (0, 0) where the needle is longer than the corpus or any probe does not fit. An empty needle is
    found at every alignment. No probe sends every alignment to the full compare.
    """
    needle_len = len(needle)
    if needle_len > len(corpus):
        return 0, 0
    if needle_len == 0:
        return len(corpus) + 1, 0
    if not all(steer_probe_fits(probe, needle_len) for probe in probes):
        return 0, 0
    return _probed(corpus, needle, [[probe.origin + (step * probe.step) for step in range(probe.length)]
                                    for probe in probes])


def _probed(corpus, needle, probes):
    """(found, bytes read) testing each probe's positions in order, a probe refuting at its first disagreement."""
    needle_len = len(needle)
    found = read = 0
    for at in range(len(corpus) - needle_len + 1):
        standing = True
        for positions in probes:
            for offset in positions:
                read += 1
                if corpus[at + offset] != needle[offset]:
                    standing = False
                    break
            if not standing:
                break
        if standing and corpus[at:at + needle_len] == needle:
            found += 1
    return found, read
