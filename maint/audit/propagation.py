"""Trace one flipped bit through every interior value, not just to the boundary.

Every other measurement in this tree reads the digest: the state after N rounds, which is the
boundary of the computation. That is the right shape for a physical system, where the interior
cannot be reached and has to be inferred from what escapes. It is the wrong shape here, because
nothing about this interior is hidden.

The whole machine is visible at every instant:

    w[t]                the sixty-four schedule words as they are produced
    a through h         the eight state words after every round
    s1, ch, t1          the three values built on the e chain inside a round
    s0, maj, t2         the three built on the a chain

So a single flipped input bit can be followed through all of it - where it arrives, in what order,
by which of the two chains, and how far it has spread at each point. A boundary reading gives one
number per round; this gives the whole path.

WHAT THE PATH ANSWERS THAT THE BOUNDARY CANNOT

The decay measurement found the spread ACROSS input bits peaking near round ten and collapsing at
both ends, which is a transient. A boundary reading cannot say whether that is one path being slow
or many paths arriving at different times, because it only sees the sum. The interior separates
them: the influence is either sitting in a particular word or it is not.

    python maint/audit/propagation.py
    python maint/audit/propagation.py --samples 400 --rounds 24
"""

import argparse
import math
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import natural_constants as nc

MASK = 0xFFFFFFFF
K = nc.round_constants()
IV = nc.starting_words()
WORDS = ("a", "b", "c", "d", "e", "f", "g", "h")


def turn(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def trace(block, rounds):
    """Every interior value the compression produces, kept rather than discarded.

    Returns the schedule, the state after each round, and the six intermediates inside each round.
    Nothing is summarised here: summarising is what a boundary reading does and it is the thing
    being avoided.
    """
    w = list(block)
    for t in range(16, 64):
        s0 = turn(w[t - 15], 7) ^ turn(w[t - 15], 18) ^ (w[t - 15] >> 3)
        s1 = turn(w[t - 2], 17) ^ turn(w[t - 2], 19) ^ (w[t - 2] >> 10)
        w.append((w[t - 16] + s0 + w[t - 7] + s1) & MASK)

    a, b, c, d, e, f, g, h = IV
    states = [(a, b, c, d, e, f, g, h)]
    inside = []
    for t in range(rounds):
        s1 = turn(e, 6) ^ turn(e, 11) ^ turn(e, 25)
        ch = (e & f) ^ (~e & g)
        t1 = (h + s1 + ch + K[t] + w[t]) & MASK
        s0 = turn(a, 2) ^ turn(a, 13) ^ turn(a, 22)
        maj = (a & b) ^ (a & c) ^ (b & c)
        t2 = (s0 + maj) & MASK
        inside.append((s1, ch, t1, s0, maj, t2))
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
        states.append((a, b, c, d, e, f, g, h))
    return w, states, inside


def weight(value):
    return bin(value).count("1")


def main():
    parser = argparse.ArgumentParser(description="Trace a flip through the interior.")
    parser.add_argument("--samples", type=int, default=300)
    parser.add_argument("--rounds", type=int, default=20)
    given = parser.parse_args()
    rounds = given.rounds
    rng = random.Random(0x74AC)

    # Accumulate the difference weight at every interior site, over many random blocks with one
    # input bit flipped. A site that is still at zero has not been reached; one at sixteen of
    # thirty-two is saturated and carries nothing further.
    state_diff = [[0.0] * 8 for _ in range(rounds + 1)]
    inside_diff = [[0.0] * 6 for _ in range(rounds)]
    schedule_diff = [0.0] * 64
    first_touch = [None] * 6

    for _ in range(given.samples):
        block = [rng.getrandbits(32) for _ in range(16)]
        which = rng.randrange(512)
        twin = list(block)
        twin[which // 32] ^= 1 << (which % 32)

        w_one, s_one, i_one = trace(block, rounds)
        w_two, s_two, i_two = trace(twin, rounds)

        for t in range(64):
            schedule_diff[t] += weight(w_one[t] ^ w_two[t])
        for step in range(rounds + 1):
            for slot in range(8):
                state_diff[step][slot] += weight(s_one[step][slot] ^ s_two[step][slot])
        for step in range(rounds):
            for slot in range(6):
                inside_diff[step][slot] += weight(i_one[step][slot] ^ i_two[step][slot])

    n = float(given.samples)
    print("  %d excitations, %d rounds, every interior value read" % (given.samples, rounds))
    print("  a word is 32 bits, so 16 is saturated and carries nothing further")
    print()

    print("=" * 78)
    print("  THE STATE, ROUND BY ROUND. Only a and e are computed; the rest are carried.")
    print("=" * 78)
    print()
    print("    round " + "".join("%7s" % name for name in WORDS))
    for step in range(0, rounds + 1, max(1, rounds // 12)):
        row = "".join("%7.2f" % (state_diff[step][slot] / n) for slot in range(8))
        print("    %5d %s" % (step, row))

    print()
    print("=" * 78)
    print("  INSIDE THE ROUND: where the influence actually enters")
    print("=" * 78)
    print()
    print("    round      s1      ch      t1      s0     maj      t2")
    names = ("s1", "ch", "t1", "s0", "maj", "t2")
    for step in range(0, rounds, max(1, rounds // 12)):
        row = "".join("%8.2f" % (inside_diff[step][slot] / n) for slot in range(6))
        print("    %5d%s" % (step, row))

    print()
    for slot in range(6):
        for step in range(rounds):
            if (inside_diff[step][slot] / n) > 0.5:
                first_touch[slot] = step
                break
    print("    first round each intermediate is touched at all:")
    print("      " + "   ".join("%s:%s" % (names[slot], first_touch[slot]) for slot in range(6)))

    print()
    print("=" * 78)
    print("  READING")
    print("=" * 78)
    print()
    print("    A boundary reading gives one number per round and cannot say which of the two chains")
    print("    carried the influence or when it entered. The table above says both, because the")
    print("    interior of this machine is not hidden - it was only being ignored.")
    print()
    print("    The shift register is visible directly in the state table: b, c and d repeat a's")
    print("    column one and two and three rounds late, and f, g, h repeat e's, because that is")
    print("    what the round does. Anything in those columns is a copy, not a computation, and")
    print("    only the a and e columns carry new work.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
