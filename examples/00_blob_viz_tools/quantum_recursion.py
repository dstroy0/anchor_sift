#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Quantum recursion on the nonce search: what recursive amplitude amplification costs, and why.

    python examples/00_blob_viz_tools/quantum_recursion.py --check     the controls, each able to fail
    python examples/00_blob_viz_tools/quantum_recursion.py             the recursion accounting

NO NUMPY. examples/00_blob_viz_tools/qubit_trace.py is numpy and this tree bans it. The state vector here is a
plain list of Python complex and the two Grover reflections are written out: a sign flip on the mark,
and twice the mean minus yourself. Both are exact, a sign flip and one mean. Nothing is rounded
that a wider float would fix.

THE QUESTION

Grover searches an unstructured space in root N. Recursion, splitting the search into d nested levels
and amplifying each, costs d times N to the one over two d, which for d near 32 is about seventy-five
oracle calls against root N of billions. That is a large saving, and it is real ONLY if each level can be
amplified on its own, which needs an oracle that reports THIS LEVEL IS RIGHT while the finer levels
are still wrong. That is partial credit, and grover-against-the-chain.md records that a hash is built
to destroy it: every input bit reaches every output bit. No coarse level is separately checkable.

WHAT THIS ADDS

E-nonce-10 measured the classical face of exactly that: the survivor descent, tightening the target
level by level, is a uniform coin flip at every level. Which survivor advances is not predictable
from the set. The coin flip IS the missing partial credit. This simulates the recursion with a
level-credit parameter, from a coin flip, the measured value, to perfect, and reads the cost. At the
coin flip the recursion collapses to plain Grover's root N, the Bennett-Bernstein-Brassard-Vazirani
optimum for a black box. Recursion buys the dimensional split only where the descent leaks, and the
descent does not leak.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import cmath
import math
import sys


def uniform(width):
    """The even superposition a layer of Hadamards on the zero state gives."""
    value = 1.0 / math.sqrt(width)
    return [complex(value, 0.0) for _ in range(width)]


def grover_step(state, marked):
    """One Grover iteration: flip the mark's sign, then reflect about the mean. Written out, exact."""
    flipped = list(state)
    flipped[marked] = -flipped[marked]
    mean = sum(flipped) / len(flipped)
    return [(2.0 * mean) - value for value in flipped]


def marked_probability(width, marked, iterations):
    """The probability the mark is read after `iterations` Grover steps on a space of `width`."""
    state = uniform(width)
    for _ in range(iterations):
        state = grover_step(state, marked)
    return abs(state[marked]) ** 2


def optimal_iterations(width):
    return int(round((math.pi / 4.0) * math.sqrt(width)))


def recursion_cost(total_bits, levels, credit):
    """Oracle calls a level-recursive amplitude amplification spends at a given per-level credit.

    The search is 2^total_bits wide, split into `levels` nested pieces of 2^(total_bits/levels) each. A
    level is amplified in root of its own width steps, but only the fraction `credit` of that
    amplification lands on the right piece: at credit one each level is a clean Grover over its piece
    and the costs ADD, the dimensional split; at credit zero, a coin flip, a level carries no
    information and the whole width must be amplified as one, which is plain Grover. The cost
    interpolates between those on the amplitude the credit places, the honest reading of
    partial information and not an on-off switch.
    """
    whole = (math.pi / 4.0) * math.sqrt(2.0 ** total_bits)
    if levels <= 1:
        return whole
    piece_bits = total_bits / float(levels)
    split = levels * ((math.pi / 4.0) * math.sqrt(2.0 ** piece_bits))
    # Credit one takes the split, credit zero takes the whole; a partial credit places the amplitude
    # between them, since amplification gain goes as the square of the amplitude on the right piece.
    return (credit * credit * split) + ((1.0 - (credit * credit)) * whole)


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # POSITIVE CONTROL. Grover on a space of 256 must peak the mark near the optimal count and then
    # fall back, the rotation not an accumulation. If it does not peak, the simulator is wrong.
    width = 256
    best = optimal_iterations(width)
    start = marked_probability(width, 73, 0)
    peak = marked_probability(width, 73, best)
    past = marked_probability(width, 73, best * 2)
    say("  Grover on 256: P(mark) %.6f at 0, %.6f at the optimal %d, %.6f past it at %d"
        % (start, peak, best, past, best * 2))
    if peak < 0.9:
        say("    FAIL Grover did not concentrate the mark. The simulator is broken")
        failed += 1
    if past >= peak:
        say("    FAIL the probability did not fall back. This is not a rotation")
        failed += 1

    # THE RECURSION AT A COIN FLIP IS PLAIN GROVER. At credit zero the level split must cost the same
    # as one level, root N. If it is cheaper, the model is crediting information a coin flip does not
    # carry.
    whole = recursion_cost(32, 1, 0.0)
    coin = recursion_cost(32, 32, 0.0)
    say("  recursion at a coin flip: %.4e oracle calls against plain Grover's %.4e" % (coin, whole))
    if abs(coin - whole) > 1e-6 * whole:
        say("    FAIL a coin-flip recursion cost less than plain Grover, crediting nothing as something")
        failed += 1

    # PERFECT CREDIT IS THE DIMENSIONAL SPLIT. At credit one, 32 levels must reach the tens of oracle
    # calls grover-against-the-chain.md records, far below root N.
    perfect = recursion_cost(32, 32, 1.0)
    say("  recursion at perfect credit, 32 levels: %.2f oracle calls (the dimensional split)" % perfect)
    if perfect > whole / 1000.0:
        say("    FAIL perfect credit did not collapse the cost. The split is not modeled")
        failed += 1

    say("")
    say("%d check(s) failed" % failed)
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0

    total_bits = 32  # The nonce space, 2^32.
    print("  recursive amplitude amplification on the 2^%d nonce search, 32 nested levels" % total_bits)
    print("  the per-level credit is how much a level's amplification lands on the right piece:")
    print("  0 is the coin flip E-nonce-10 measured, 1 is the partial credit a hash is built to deny")
    print("")
    print("  %14s %20s %18s" % ("per-level credit", "oracle calls", "vs plain Grover"))
    whole = recursion_cost(total_bits, 1, 0.0)
    for credit in (0.0, 0.25, 0.5, 0.75, 0.9, 0.99, 1.0):
        cost = recursion_cost(total_bits, 32, credit)
        print("  %14.2f %20.4e %18s"
              % (credit, cost, "1.0 x" if cost >= whole else "%.3e x" % (whole / cost)))
    print("")
    print("  plain Grover is %.4e oracle calls, the BBBV optimum for a black box." % whole)
    print("  E-nonce-10 measured the per-level credit at 0, a uniform coin flip. The realized cost")
    print("  is the top row: plain Grover, no dimensional split. The recursion buys the tens-of-calls")
    print("  bottom row only if the descent leaks which survivor advances, and it does not.")
    print("")
    print("  and the fleet result stands whatever the credit: parallel Grover over m machines buys")
    print("  root m where classical buys m. The square root that helps one searcher hurts a fleet,")
    print("  and mining is a fleet. Recorded in docs/grover-against-the-chain.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
