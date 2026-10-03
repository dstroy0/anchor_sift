#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Two readings of the gnascor state machine: what a label keeps of its transition, and what repeats on the host.

    python utils/maint/engine/gnascor_measure.py --labels
    python utils/maint/engine/gnascor_measure.py --repeat <runs>

--labels counts, in bits, how much of a transition a label leaves recoverable. A transition is its pair, the
state left and the state reached. Each pair the tables in src/c/transpiler/gnascor.md name is put through every
situation gnascor_read.py decides a label in, every pair weighted alike and every situation alike within it. The
reading is the conditional entropy of the pair given what a branch reads, H(pair | label), taken four ways:

    the tables alone     one name a cell, as the tables print it, over every named cell of the first table
    a bare label         the one label gnascor_read.py decides in the situation
    the clock's label    the same, with a SYNC passage written as its FUZZ+ and FIZZ+ labels
    a GRAY trip's state  the same, with FUZZ into GRAY carrying the state left and FIZZ out of it the state reached

H(pair) less H(pair | label) is the part of the transition the label keeps.

--repeat puts gnascor_scenario.txt to the host as real asks the given number of times, through the
gnascor_trace program utils/maint/engine/chain_check.sh builds, and reads every trace back. It reports how many
cycles read as the scenario implies, how many asks the scenario holds came in past the bound their own run
derived, how many both-held cycles read BUSY in place of DUAL, how many sides of those cycles come in past the
BUSY edge alone and both at once against the count two independent sides would give, how many distinct coherence
clocks the runs print, and the spread of the bound each run derives. A held ask past its bound is a spurious timeout: the bound is
estimated from a finite sample of the host's costs, and the host can still exceed it. The traces are written
under build/engine/repeat/.

Nothing here is copied from the tables: they are read out of gnascor.md each run, as gnascor_read.py reads them.
"""

import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gnascor_read import (BASELINE_CYCLES, KINDS, MATRIX_DOC, baseline_of, candidates_of,  # noqa: E402
                          check_scenario, decide, read_cycle, read_trace, stream)
from order_check import read_matrices, table_cells  # noqa: E402

TOP = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SCENARIO = os.path.join(HERE, "gnascor_scenario.txt")
BUILT = os.path.join(TOP, "build", "engine")

# the situations gnascor_read.py's own check decides every pair in: each kind at each cost, against a bound of
# 1000 and a held edge of 120
SITUATIONS = [(kind, cost) for kind in KINDS for cost in (0, 100, 1050, 5000)]
BOUND = 1000
EDGE = 120


def entropy_given(weights):
    """H(pair | label) in bits, from {label: {pair: weight}}."""
    total = sum(weight for pairs in weights.values() for weight in pairs.values())
    held = 0.0
    for pairs in weights.values():
        mass = sum(pairs.values())
        for weight in pairs.values():
            held += (weight / total) * math.log2(mass / weight)
    return held


def tables_alone(path=MATRIX_DOC):
    """{label: {pair: 1}} over the cells of the first table, as printed."""
    where, names, rows = read_matrices(path)[0]
    weights = {}
    for pair, name in table_cells(names, rows).items():
        weights.setdefault(name, {})[pair] = 1
    return weights


def situated(clock_form, gray_form=False):
    """{label: {pair: weight}} over every pair and every situation, each pair weighing 1 in total."""
    held = candidates_of()
    weights = {}
    share = 1.0 / (len(SITUATIONS) ** 2)
    for pair, names in held.items():
        for left in SITUATIONS:
            for right in SITUATIONS:
                label = decide(pair, names, left, right, BOUND, EDGE)
                if clock_form and label == "SYNC":
                    label = "FUZZ+%s FIZZ+%s" % pair
                if gray_form and label == "FUZZ":
                    label = "FUZZ+%s" % pair[0]
                if gray_form and label == "FIZZ":
                    label = "FIZZ+%s" % pair[1]
                bucket = weights.setdefault(label, {})
                bucket[pair] = bucket.get(pair, 0.0) + share
    return weights


def labels():
    """Print what each reading keeps of a transition."""
    first = tables_alone()
    count = sum(len(pairs) for pairs in first.values())
    lost = entropy_given(first)
    print("  the tables alone: %d cells, %d names, H(pair) %.3f bits, H(pair | name) %.3f, kept %.3f"
          % (count, len(first), math.log2(count), lost, math.log2(count) - lost))
    shared(first)
    pairs = len(candidates_of())
    readings = (("a bare label", False, False), ("the clock's label", True, False),
                ("the clock's label, a GRAY trip carrying its state", True, True))
    for title, clock_form, gray_form in readings:
        weights = situated(clock_form, gray_form)
        lost = entropy_given(weights)
        print("  %s: %d pairs, %d labels, H(pair) %.3f bits, H(pair | label) %.3f, kept %.3f"
              % (title, pairs, len(weights), math.log2(pairs), lost, math.log2(pairs) - lost))
        shared(weights)
    return 0


def shared(weights):
    """Print every label that more than one pair reaches, and the bits of its pair it leaves unread."""
    for name, pairs in sorted(weights.items(), key=lambda item: (-len(item[1]), item[0])):
        if len(pairs) > 1:
            print("    %-5s reached from %2d pairs, leaves %.3f bits of the pair unread"
                  % (name, len(pairs), entropy_given({name: pairs})))


def repeat(runs):
    """Put the scenario to the host the given number of times and read every trace back."""
    program = os.path.join(BUILT, "gnascor_trace")
    if os.path.isfile(program + ".exe"):
        program += ".exe"
    if not os.path.isfile(program):
        print("  no gnascor_trace under %s: run utils/maint/engine/chain_check.sh first" % BUILT)
        return 2
    out = os.path.join(BUILT, "repeat")
    os.makedirs(out, exist_ok=True)
    with open(SCENARIO, encoding="utf-8") as handle:
        specs = [tuple(line.split()) for line in handle if line.strip()]
    both_held = [at for at, spec in enumerate(specs) if spec == ("held", "held")]
    held_sides = [(at, side) for at, spec in enumerate(specs) for side in (0, 1) if spec[side] == "held"]
    wrong = 0
    busy = 0
    spurious = 0
    sides_over = 0
    both_over = 0
    clocks = {}
    bounds = []
    for run in range(1, runs + 1):
        trace = os.path.join(out, "trace_%d.txt" % run)
        subprocess.run([program, SCENARIO, trace], check=True, stdout=subprocess.DEVNULL)
        with open(trace, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
        head = lines[0].split()
        bounds.append(int(head[head.index("bound") + 1]))
        cycles = [read_cycle(line) for line in lines if line.strip() and not line.startswith("#")]
        states, read = read_trace(cycles)
        traced = states[BASELINE_CYCLES:]
        busy += sum(1 for at in both_held if traced[at] == "BUSY")
        asked = cycles[BASELINE_CYCLES:]
        edge = baseline_of(cycles)
        for at in both_held:
            over = [asked[at][side][1] > edge for side in (0, 1)]
            sides_over += sum(over)
            both_over += 1 if all(over) else 0
        spurious += sum(1 for at, side in held_sides if asked[at][side][0] == "PAST_BOUND")
        clock = stream(states[BASELINE_CYCLES:], read[BASELINE_CYCLES:])
        clocks[clock] = clocks.get(clock, 0) + 1
        with open(os.devnull, "w", encoding="utf-8") as quiet:
            saved = sys.stdout
            sys.stdout = quiet
            try:
                wrong += check_scenario(SCENARIO, trace)
            finally:
                sys.stdout = saved
    bounds.sort()
    print("  %d runs of %d cycles, %d cycles read as other than the scenario implies" % (runs, len(specs), wrong))
    print("  %d of %d held asks came in past the bound their run derived" % (spurious, runs * len(held_sides)))
    print("  %d of %d both-held cycles read BUSY in place of DUAL" % (busy, runs * len(both_held)))
    pairs = runs * len(both_held)
    share = sides_over / (2.0 * pairs)
    print("  %d of %d sides of those cycles past the edge, a share of %.4f; both at once %d, where sides apart from"
          " each other give %.2f" % (sides_over, 2 * pairs, share, both_over, pairs * share * share))
    print("  %d distinct coherence clocks; the most common printed by %d of %d runs"
          % (len(clocks), max(clocks.values()), runs))
    print("  bound in clock counts: least %d, median %d, most %d"
          % (bounds[0], bounds[len(bounds) // 2], bounds[-1]))
    return 0


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) == 2 and sys.argv[1] == "--labels":
        return labels()
    if len(sys.argv) == 3 and sys.argv[1] == "--repeat" and sys.argv[2].isdigit():
        return repeat(int(sys.argv[2]))
    sys.stdout.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
