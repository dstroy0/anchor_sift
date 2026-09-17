#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-5-002
#
# Which anchor rule to prefer once the fate of a survivor is fixed.
#
#   Usage:  python examples/any_corpus/5_sift/survivor_regimes.py corpus.sym [more.sym ...]
#
# The workbook leaves the choice between rarity and separation open and names the term it waits on:
# whether survivors are verified and discarded, or buffered and handed on. This file supplies that
# term. A descent that resumes from a parent's survivors, through the resume field of
# AnchorSteerDescent, is the second case: the child reads only what the parent stored.
#
# Discarded, a survivor costs one verification and is gone. The cost is the count of survivors. A
# wrong size estimate costs nothing here, because nothing is allocated from it.
#
# Buffered, the survivors are stored before the next stage reads them, and the store is sized from
# the product rule's prediction. A survivor past the end of the store is dropped. When the dropped
# alignment is a real occurrence, the next stage misses an occurrence the construction guarantees,
# and the failure is one of correctness.
#
# No headroom factor is chosen. A store holds whole slots, ceil(h * predicted) of them, and it holds
# n survivors exactly when h exceeds (n - 1) / predicted. The multiple each rule needs is that bound
# taken over every needle, computed and printed. The table below it steps the store through powers
# of two up to the largest multiple any rule needed, and the verdict reads those numbers.
#
# Controls. A store of zero slots must drop every planted occurrence, which shows the drop count can
# move at all. The discarded regime must drop none, as the filter's soundness requires. Every
# survivor list is taken twice: once by intersecting position sets, once by walking the occurrences
# of one anchor symbol and comparing the other anchors in place. The two routes share no code, and a
# single disagreement fails the run. The null is the same corpus with its bytes shuffled, holding
# every symbol count and removing every arrangement.
#
# NEEDLE, ANCHORS, TRIALS, SEED and the 50000 symbol floor match selection_rules.py beside this file,
# and the survivor and sizing columns compare with its rows directly.

import io
import math
import os
import random
import statistics
import sys


def repository_root():
    """The directory holding src/engine/python/sift, found by walking up from this file."""
    here = os.path.dirname(os.path.abspath(__file__))
    while not os.path.isdir(os.path.join(here, "src", "engine", "python", "sift")):
        parent = os.path.dirname(here)
        if parent == here:
            raise SystemExit("survivor_regimes.py: no src/engine/python/sift above %s" % __file__)
        here = parent
    return here


sys.path.insert(0, os.path.join(repository_root(), "src", "engine", "python"))

from sift.anchors import cell_rarest, jittered, positions_by_symbol, rarest, spread, survivors  # noqa: E402

NEEDLE = 24
ANCHORS = 3
TRIALS = 200
SEED = 0xA9C40
FLOOR = 50000

RULES = ("rarest", "spread", "jittered", "cell_rarest")


def offsets_for(rule, needle, counts):
    """The anchor offsets a rule picks, called the way selection_rules.py calls it."""
    if rule == "rarest":
        return rarest(needle, counts, ANCHORS)
    if rule == "spread":
        return spread(NEEDLE, ANCHORS)
    if rule == "jittered":
        return jittered(NEEDLE, ANCHORS, random.Random(SEED))
    return cell_rarest(needle, counts, ANCHORS)


def by_intersection(places, needle, offsets, total):
    """Route one: the sift's own intersection, restricted to alignments the needle fits inside."""
    return sorted(start for start in survivors(places, needle, offsets) if 0 <= start <= total - NEEDLE)


def by_scan(seats, needle, offsets, counts):
    """Route two: walk every occurrence of the least common anchor symbol and test the others there."""
    pivot = min(offsets, key=lambda offset: counts[needle[offset]])
    symbol = bytes([needle[pivot]])
    others = [(offset, needle[offset]) for offset in offsets if offset != pivot]
    found = []
    at = seats.find(symbol)
    while at != -1:
        start = at - pivot
        if (0 <= start <= len(seats) - NEEDLE) and all(seats[start + offset] == value
                                                        for offset, value in others):
            found.append(start)
        at = seats.find(symbol, at + 1)
    return found


def needed_multiple(rows):
    """The least h, as a strict lower bound, at which ceil(h * predicted) slots hold every survivor."""
    bound = 0.0
    for kept, _, predicted in rows:
        if len(kept) > 1:
            bound = max(bound, (len(kept) - 1) / predicted)
    return bound


def capacity(multiple, predicted):
    return math.ceil(multiple * predicted)


def overflowed(rows, multiple):
    """Needles whose survivors do not fit a store of ceil(multiple * predicted) slots."""
    return sum(1 for kept, _, predicted in rows if len(kept) > capacity(multiple, predicted))


def real_dropped(rows, multiple):
    """Planted occurrences that land past the end of the store, filled in corpus order."""
    return sum(1 for kept, start, predicted in rows
               if (start is not None) and (start in kept)
               and (kept.index(start) >= capacity(multiple, predicted)))


def measure(seats, counts, places, alphabet, disagreements):
    """Every rule over every needle, both routes, as rows of (survivors, planted start, prediction)."""
    total = len(seats)
    table = {}
    for source in ("from corpus", "independent"):
        rng = random.Random(SEED)
        drawn = []
        for _ in range(TRIALS):
            start = rng.randrange(0, total - NEEDLE)
            if source == "from corpus":
                drawn.append((start, bytes(seats[start:start + NEEDLE])))
            else:
                drawn.append((None, bytes(rng.choice(alphabet) for _ in range(NEEDLE))))

        for rule in RULES:
            rows = []
            for start, needle in drawn:
                offsets = offsets_for(rule, needle, counts)
                kept = by_intersection(places, needle, offsets, total)
                if kept != by_scan(seats, needle, offsets, counts):
                    disagreements.append((rule, source, start))
                predicted = float(total - NEEDLE)
                for offset in offsets:
                    predicted *= counts[needle[offset]] / float(total)
                rows.append((kept, start, predicted))
            table[(rule, source)] = rows
    return table


def report(out, label, seats, controls):
    total = len(seats)
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    places = positions_by_symbol(seats)
    alphabet = sorted(places)
    table = measure(seats, counts, places, alphabet, controls["disagreements"])

    out.write("%s, %d symbols over %d\n" % (label, total, len(alphabet)))
    out.write("  discarded: a survivor is verified once and dropped\n")
    out.write("    %-12s %-12s %-10s %-13s %s\n"
              % ("rule", "needle", "survivors", "sizing error", "real occurrences dropped"))
    for rule in RULES:
        for source in ("from corpus", "independent"):
            rows = table[(rule, source)]
            excess = [len(kept) - (1 if (start is not None and start in kept) else 0)
                      for kept, start, _ in rows]
            errors = [spare / predicted for spare, (_, _, predicted) in zip(excess, rows) if predicted > 0.0]
            dropped = sum(1 for kept, start, _ in rows if start is not None and start not in kept)
            controls["discard_dropped"] += dropped
            out.write("    %-12s %-12s %-10.1f %-13.2f %d\n"
                      % (rule, source, statistics.fmean(excess),
                         statistics.median(errors) if errors else float("nan"), dropped))

    needed = {rule: needed_multiple(table[(rule, "from corpus")] + table[(rule, "independent")])
              for rule in RULES}
    out.write("  buffered: survivors are stored in ceil(h * predicted) slots before the next stage\n")
    out.write("    %-12s %s\n" % ("rule", "store multiple h needed to drop nothing"))
    for rule in RULES:
        out.write("    %-12s %.2f\n" % (rule, needed[rule]))

    top = max(0, math.ceil(math.log2(max(needed.values())))) if max(needed.values()) > 0.0 else 0
    out.write("    store h    " + "".join("%-22s" % rule for rule in RULES) + "\n")
    out.write("    %-10s " % "" + "".join("%-22s" % "overflow / real dropped" for _ in RULES) + "\n")
    for exponent in range(0, top + 2):
        multiple = float(2 ** exponent)
        cells = []
        for rule in RULES:
            rows = table[(rule, "from corpus")] + table[(rule, "independent")]
            cells.append("%-22s" % ("%d / %d" % (overflowed(rows, multiple),
                                                  real_dropped(table[(rule, "from corpus")], multiple))))
        out.write("    2^%-8d " % exponent + "".join(cells) + "\n")

    # The same detector the table uses, at a store of zero slots, where every planted occurrence
    # has to fall past the end. A detector that miscounts rank or capacity reports fewer here.
    for rule in RULES:
        rows = table[(rule, "from corpus")]
        planted = sum(1 for kept, start, _ in rows if start in kept)
        if real_dropped(rows, 0.0) != planted:
            controls["zero_store_failed"] = True

    out.write("  verdict, rarest against spread\n")
    for source in ("from corpus", "independent"):
        verified = {rule: statistics.fmean(len(kept) for kept, _, _ in table[(rule, source)])
                    for rule in ("rarest", "spread")}
        out.write("    discarded, %-11s %s, %.2f survivors to verify against %.2f\n"
                  % (source + ":", "rarest" if verified["rarest"] < verified["spread"] else "spread",
                     min(verified.values()), max(verified.values())))
    out.write("    buffered:  %s, a store of %.2f times its prediction against %.2f\n"
              % ("rarest" if needed["rarest"] < needed["spread"] else "spread",
                 min(needed["rarest"], needed["spread"]), max(needed["rarest"], needed["spread"])))
    out.write("\n")


def main():
    if len(sys.argv) < 2:
        print("usage: survivor_regimes.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    controls = {"disagreements": [], "discard_dropped": 0, "zero_store_failed": False}
    read = []
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            seats = handle.read()
        if len(seats) < FLOOR:
            continue
        read.append(path)
        name = os.path.basename(path)[:-4]
        report(out, name, seats, controls)
        shuffled = bytearray(seats)
        random.Random(SEED).shuffle(shuffled)
        report(out, name + " shuffled (the null)", bytes(shuffled), controls)

    out.write("read:\n")
    for path in read:
        out.write("  %s\n" % path)
    if not read:
        out.write("  nothing: no corpus of %d symbols or more was given, and no row above is a result\n" % FLOOR)
        out.flush()
        return 2

    out.write("controls:\n")
    out.write("  routes disagree on %d needles (must be 0)\n" % len(controls["disagreements"]))
    out.write("  real occurrences dropped when discarded: %d (must be 0)\n" % controls["discard_dropped"])
    out.write("  a zero slot store dropped every planted occurrence: %s\n"
              % ("no" if controls["zero_store_failed"] else "yes"))
    out.flush()
    failed = controls["disagreements"] or controls["discard_dropped"] or controls["zero_store_failed"]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
