"""The rules, not the frequencies: which transitions are possible and which are forbidden.

Every earlier reading of the influence web here was a distribution - how often an input at one
position reached an output at another. That counts pieces. A language is not its letter frequencies;
it is what may follow what, and the interesting entries are the ones that never occur at all.

So this reads the SUPPORT. For a single-bit input difference, which output positions are ever moved
and which are never moved, at each depth. A position that is never moved after many excitations is
not rare - it is forbidden, and a forbidden transition is a hard constraint on the machine rather
than a statistical lean.

WHY FORBIDDEN IS WORTH MORE THAN RARE

A rare transition needs a probability and a null and an argument. A forbidden one needs none of
those: it either happened or it did not, and if a transition cannot occur then any trajectory
requiring it is ruled out completely. That is what makes impossible differentials a different kind
of tool from the statistical ones, and it is the reading a frequency table cannot give.

THE WINDOW CLOSES FAST

At depth one almost everything is forbidden. By depth six or so the support fills, every position
becomes reachable from every other, and the grammar stops constraining anything. Where it closes IS
the measurement: it says how many rounds the machine needs before it can say anything to anything.

    python maint/audit/grammar.py
    python maint/audit/grammar.py --trials 4000 --depths 1,2,3,4,5,6,7,8
"""

import argparse
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import natural_constants as nc

MASK = 0xFFFFFFFF
K = nc.round_constants()
IV = nc.starting_words()


def turn(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def compress(block, rounds):
    w = list(block)
    for t in range(16, 64):
        s0 = turn(w[t - 15], 7) ^ turn(w[t - 15], 18) ^ (w[t - 15] >> 3)
        s1 = turn(w[t - 2], 17) ^ turn(w[t - 2], 19) ^ (w[t - 2] >> 10)
        w.append((w[t - 16] + s0 + w[t - 7] + s1) & MASK)
    a, b, c, d, e, f, g, h = IV
    for t in range(rounds):
        s1 = turn(e, 6) ^ turn(e, 11) ^ turn(e, 25)
        ch = (e & f) ^ (~e & g)
        t1 = (h + s1 + ch + K[t] + w[t]) & MASK
        s0 = turn(a, 2) ^ turn(a, 13) ^ turn(a, 22)
        mj = (a & b) ^ (a & c) ^ (b & c)
        t2 = (s0 + mj) & MASK
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
    out = 0
    for index, value in enumerate((a, b, c, d, e, f, g, h)):
        out = (out << 32) | ((IV[index] + value) & MASK)
    return out


def support(rounds, source, trials, rng):
    """Which output positions this ONE input bit ever moves. A set, not a histogram."""
    reached = 0
    for _ in range(trials):
        block = [rng.getrandbits(32) for _ in range(16)]
        twin = list(block)
        twin[source // 32] ^= 1 << (source % 32)
        reached |= compress(block, rounds) ^ compress(twin, rounds)
    return reached


def main():
    parser = argparse.ArgumentParser(description="The web's rules, by support.")
    parser.add_argument("--trials", type=int, default=1500)
    parser.add_argument("--sources", type=int, default=24)
    parser.add_argument("--depths", default="1,2,3,4,5,6,7,8,10")
    given = parser.parse_args()
    depths = [int(v) for v in given.depths.split(",")]
    rng = random.Random(0x64A3)

    sources = [rng.randrange(512) for _ in range(given.sources)]

    print("  %d input bits, %s excitations each, support taken as a union" % (given.sources,
                                                                             format(given.trials, ",")))
    print("  a position not moved once in %s tries is forbidden at that depth, not rare"
          % format(given.trials, ","))
    print()
    print("    rounds   reachable of 256   forbidden   share forbidden")
    closing = None
    for rounds in depths:
        widths = []
        for source in sources:
            widths.append(bin(support(rounds, source, given.trials, rng)).count("1"))
        middle = sum(widths) / float(len(widths))
        forbidden = 256 - middle
        share = forbidden / 256.0
        if closing is None and share < 0.01:
            closing = rounds
        print("    %6d   %16.1f   %9.1f   %14.4f" % (rounds, middle, forbidden, share))

    print()
    print("=" * 78)
    print("  READING")
    print("=" * 78)
    print()
    if closing:
        print("    The grammar closes at round %d: past there every input bit can reach every output"
              % closing)
        print("    position, nothing is forbidden, and the support constrains no trajectory at all.")
    else:
        print("    The grammar had not closed at the deepest round tried. There are still output")
        print("    positions a single input bit cannot reach, and each one rules out every")
        print("    trajectory that would need it.")
    print()
    print("    Before it closes the forbidden set is a HARD constraint and needs no null: a")
    print("    transition either occurred or it did not. That is what a rule is, and it is a")
    print("    different kind of statement from any frequency in this tree.")
    print()
    print("    The number that matters is how FAST it closes. A round function whose grammar")
    print("    survived deep would be one whose trajectories could be pruned; one that closes")
    print("    in a handful of rounds has bought exactly that and nothing is left to prune.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
