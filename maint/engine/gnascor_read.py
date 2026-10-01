#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The gnascor state machine, read off a trace of asks: a state each cycle, and a label each transition.

    python maint/engine/gnascor_read.py <trace>
    python maint/engine/gnascor_read.py --check

A trace holds one line a cycle: the kind and cost of the left side's ask, the kind and cost of the
right side's, and the bound both were put under, the kinds as QueryKind in
src/engine/compiler/bootstrap/query_ask.h names them.

    HELD 412 NOT_HELD 380 900

The tables are read out of src/engine/compiler/gnascor.md each run and are never copied here.

A side reads 1 where its ask held inside the bound, and 0 where it did not hold, ended its asker or
came in past the bound. A cycle's state follows from the two sides and from how they read:

    BLOK  a side ended its asker: a hard refusal
    WAIT  one side held and the other answered past the bound: it lags
    BUSY  both held, each costing more than any held ask of the baseline cycles
    DUAL  both held
    LEAD  the left held and the right did not
    RITE  the right held and the left did not
    VOID  neither held

The baseline is the trace's first cycles, put unbound or well inside their bound: the costs of every
held ask in them. Nothing here writes a scale in. The edge BUSY reads against is the baseline's largest
held cost, and the fraction of a cycle TILT reads against is that same cost: a side past its bound by
no more than one held ask's cost lagged, and past it by more it timed out.

A transition is its pair, the state left and the state reached. Where the tables name a pair more than
one way, each name is a candidate and the cycle decides between them. TILT holds where the side that
went to 0 came in past the bound by a fraction of a cycle, and the name beside it takes every other
case. FUSE holds where both sides went to 0 with neither past the bound, and DROP takes every other
case. A name with no condition outranks SYNC, the catch-all. Every transition gets one label.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from order_check import MATRIX_DOC, read_matrices, table_cells  # noqa: E402

KINDS = ("HELD", "NOT_HELD", "PAST_BOUND", "ENDED")

# how many leading cycles of a trace are its baseline
BASELINE_CYCLES = 4


def candidates_of(path=MATRIX_DOC):
    """Every pair the tables name, as {(past, now): [names]}, each name once, in the tables' order."""
    held = {}
    for _where, names, rows in read_matrices(path):
        for pair, name in table_cells(names, rows).items():
            held.setdefault(pair, [])
            if name not in held[pair]:
                held[pair].append(name)
    return held


def read_cycle(line):
    """One trace line as ((left kind, left cost), (right kind, right cost), bound)."""
    words = line.split()
    if len(words) != 5 or words[0] not in KINDS or words[2] not in KINDS:
        raise ValueError("a trace line is: <kind> <cost> <kind> <cost> <bound>, read: %r" % line)
    return (words[0], int(words[1])), (words[2], int(words[3])), int(words[4])


def baseline_of(cycles):
    """The largest cost of any held ask in the baseline cycles, and 0 where none held."""
    costs = [cost for left, right, _bound in cycles[:BASELINE_CYCLES]
             for kind, cost in (left, right) if kind == "HELD"]
    return max(costs) if costs else 0


def state_of(left, right, edge):
    """A cycle's state from its two sides."""
    kinds = (left[0], right[0])
    if "ENDED" in kinds:
        return "BLOK"
    if "HELD" in kinds and "PAST_BOUND" in kinds:
        return "WAIT"
    if kinds == ("HELD", "HELD"):
        if left[1] > edge and right[1] > edge:
            return "BUSY"
        return "DUAL"
    if kinds[0] == "HELD":
        return "LEAD"
    if kinds[1] == "HELD":
        return "RITE"
    return "VOID"


def lagged(side, bound, fraction):
    """Whether a side came in past its bound by no more than a fraction of a cycle."""
    return side[0] == "PAST_BOUND" and (side[1] - bound) <= fraction


def decide(pair, names, left, right, bound, fraction):
    """The one label a transition takes in this cycle, from the names the tables give its pair."""
    if len(names) == 1:
        return names[0]
    gone = [side for side, held in ((left, left[0] == "HELD"), (right, right[0] == "HELD")) if not held]
    if "TILT" in names:
        if gone and all(lagged(side, bound, fraction) for side in gone):
            return "TILT"
        return [name for name in names if name != "TILT"][0]
    if "FUSE" in names:
        if all(side[0] != "PAST_BOUND" for side in gone):
            return "FUSE"
        return [name for name in names if name != "FUSE"][0]
    named = [name for name in names if name != "SYNC"]
    return named[0] if named else "SYNC"


def read_trace(cycles, held=None):
    """The state of every cycle and the label of every transition, as (states, labels)."""
    held = candidates_of() if held is None else held
    edge = baseline_of(cycles)
    states = [state_of(left, right, edge) for left, right, _bound in cycles]
    labels = []
    for at in range(1, len(cycles)):
        pair = (states[at - 1], states[at])
        left, right, bound = cycles[at]
        names = held.get(pair)
        labels.append(decide(pair, names, left, right, bound, edge) if names else None)
    return states, labels


def stream(states, labels):
    """The trace as the coherence clock prints it."""
    out = ["[%s]" % states[0]]
    for state, label in zip(states[1:], labels):
        out.append("-(%s)-> [%s]" % (label or "----", state))
    return " ".join(out)


def check():
    """Every rule the reader states, held on traces whose answers are known. The count failed."""
    failed = 0
    held = candidates_of()
    base = [("HELD", 100), ("HELD", 120)]

    def run(rows):
        cycles = [(base[0], base[1], 1000)] * BASELINE_CYCLES + rows
        return read_trace(cycles, held)

    def expect(what, rows, want):
        nonlocal failed
        states, labels = run(rows)
        got = labels[-1]
        if got != want:
            failed += 1
            print("  FAILED: %s: %s, wanted %s, read %s" % (what, stream(states, labels), want, got))

    lead = (("HELD", 100), ("NOT_HELD", 0), 1000)
    rite = (("NOT_HELD", 0), ("HELD", 100), 1000)
    dual = (("HELD", 100), ("HELD", 100), 1000)
    expect("LEAD then RITE is the shift right", [lead, rite], "PASS")
    expect("RITE then LEAD is the shift left", [rite, lead], "BACK")
    # A held side beside one a fraction past its bound is WAIT by the base states: a DUAL whose right side
    # lags reads DUAL to WAIT and never DUAL to LEAD: read off a trace, the lag TILT names arrives as WAIT
    expect("DUAL with the right side a fraction late reads as DUAL to WAIT",
           [dual, (("HELD", 100), ("PAST_BOUND", 1050), 1000)], held_name(held, "DUAL", "WAIT"))
    expect("VOID to DUAL", [(("NOT_HELD", 0), ("NOT_HELD", 0), 1000), dual], "SPRK")
    busy = (("HELD", 900), ("HELD", 950), 1000)
    expect("BUSY to BLOK is gridlock", [busy, (("ENDED", 0), ("HELD", 900), 1000)], "JAMM")
    wait = (("HELD", 100), ("PAST_BOUND", 1050), 1000)
    expect("WAIT to VOID is the timeout", [wait, (("NOT_HELD", 0), ("NOT_HELD", 0), 1000)], "LOSS")

    # the situation decides between two names for one pair
    tilt_right = (("HELD", 100), ("PAST_BOUND", 1050), 1000)
    states, labels = run([dual, tilt_right])
    if states[-1] != "WAIT":
        failed += 1
        print("  FAILED: a held side beside one past its bound reads WAIT, read %s" % states[-1])
    pairs = [
        ("DUAL to LEAD, the right side not held", "DUAL", "LEAD", (("HELD", 100), ("NOT_HELD", 0)), "DROP"),
        ("DUAL to LEAD, the right side a fraction past the bound", "DUAL", "LEAD",
         (("HELD", 100), ("PAST_BOUND", 1050)), "TILT"),
        ("DUAL to LEAD, the right side a timeout past the bound", "DUAL", "LEAD",
         (("HELD", 100), ("PAST_BOUND", 5000)), "DROP"),
        ("DUAL to VOID, both gone at once", "DUAL", "VOID", (("NOT_HELD", 0), ("NOT_HELD", 0)), "FUSE"),
        ("DUAL to VOID, through a timeout", "DUAL", "VOID", (("PAST_BOUND", 5000), ("NOT_HELD", 0)), "DROP"),
        ("BUSY to DUAL", "BUSY", "DUAL", (("HELD", 100), ("HELD", 100)), "SURG"),
    ]
    for what, past, now, sides, want in pairs:
        got = decide((past, now), held[(past, now)], sides[0], sides[1], 1000, 120)
        if got != want:
            failed += 1
            print("  FAILED: %s: wanted %s, read %s" % (what, want, got))

    # every pair the tables name is decided in every situation a side can be in
    situations = [(kind, cost) for kind in KINDS for cost in (0, 100, 1050, 5000)]
    undecided = 0
    for pair, names in held.items():
        for left in situations:
            for right in situations:
                if decide(pair, names, left, right, 1000, 120) not in names:
                    undecided += 1
    if undecided:
        failed += 1
        print("  FAILED: %d situations left a transition with no label from its own candidates" % undecided)
    print("  %d pairs, each decided in all %d situations two sides can be in"
          % (len(held), len(situations) ** 2))
    print("  gnascor read: %d failed" % failed)
    return failed


def held_name(held, past, now):
    """The one name the tables give a pair."""
    return held[(past, now)][0]


def main():
    out = sys.stdout
    out.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        return 1 if check() else 0
    if len(sys.argv) != 2:
        out.write(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        cycles = [read_cycle(line) for line in handle if line.strip() and not line.startswith("#")]
    states, labels = read_trace(cycles)
    out.write(stream(states, labels) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
