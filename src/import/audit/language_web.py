"""The influence web: which bit reaches which, as a graph, and whether the graph speaks the rotations.

Counting how many bits an influence touches throws away the thing that matters. The structure is
WHICH ones, and that pattern is written by the round function itself: the only ways SHA-256 moves a
bit across positions are

    Sigma0 = ROTR2  xor ROTR13 xor ROTR22      on the a chain
    Sigma1 = ROTR6  xor ROTR11 xor ROTR25      on the e chain
    the schedule spreads, and the carry, which moves one position at a time

So if the web has a grammar, an input bit at position p inside its word should reach output
positions at p minus those amounts, modulo thirty-two, and at nothing else - until the rounds pile
enough of them on top of each other that every position reaches every other and the structure is
gone.

THE WINDOW IS EARLY AND IT CLOSES

By round twenty the graph is complete: everything influences everything, every residue class is
equally occupied, and there is no web left to read. The readable window is the first few rounds,
which is also where the residue result in this tree found its signal. The two are the same
observation reached from opposite directions - one from the dependency spectrum, one from the graph.

    python tools/audit/language_web.py
    python tools/audit/language_web.py --samples 600 --depths 2,3,4,5,6,8
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

SIGMA0 = (2, 13, 22)
SIGMA1 = (6, 11, 25)
CARRY = (1, 31)


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


def web_at(rounds, samples, rng):
    """The residue web: how often an input at position p reaches an output at position q.

    Only the WITHIN-WORD offset is kept, (p - q) mod 32, because that is the quantity a rotation
    acts on. A rotation by r sends every bit to the same offset, so if rotations write the web the
    occupancy piles up on their amounts and nowhere else.
    """
    residue = [0] * 32
    total = 0
    for _ in range(samples):
        block = [rng.getrandbits(32) for _ in range(16)]
        which = rng.randrange(512)
        twin = list(block)
        twin[which // 32] ^= 1 << (which % 32)
        source = which % 32

        diff = compress(block, rounds) ^ compress(twin, rounds)
        while diff:
            low = diff & -diff
            at = low.bit_length() - 1
            sink = at % 32
            residue[(source - sink) % 32] += 1
            total += 1
            diff ^= low
    return residue, total


def main():
    parser = argparse.ArgumentParser(description="Read the influence web's grammar.")
    parser.add_argument("--samples", type=int, default=500)
    parser.add_argument("--depths", default="2,3,4,5,6,8,12,20")
    given = parser.parse_args()
    depths = [int(v) for v in given.depths.split(",")]
    rng = random.Random(0x3AB)

    named = set(SIGMA0) | set(SIGMA1) | set(CARRY) | {0}
    print("  %d excitations per depth, offsets taken within the word, modulo 32" % given.samples)
    print("  the round function moves bits by %s and by the carry, and by nothing else"
          % ", ".join(str(v) for v in sorted(set(SIGMA0) | set(SIGMA1))))
    print()
    print("    rounds   total   flat share   NAMED offsets share   excess   sd")
    for rounds in depths:
        residue, total = web_at(rounds, given.samples, rng)
        if total == 0:
            continue
        flat = len(named) / 32.0
        inside = sum(residue[at] for at in named) / float(total)
        # Under a complete web every offset is equally likely, so the named ones hold exactly
        # their share of the thirty-two. The spread is binomial at this many observations.
        spread = math.sqrt(flat * (1 - flat) / total)
        z = (inside - flat) / spread
        print("    %6d   %5d   %10.4f   %19.4f   %+6.4f   %+6.1f"
              % (rounds, total, flat, inside, inside - flat, z))

    print()
    print("=" * 78)
    print("  THE WEB AT THE EARLIEST READABLE DEPTH")
    print("=" * 78)
    residue, total = web_at(depths[0], given.samples * 2, rng)
    widest = max(residue) or 1
    print()
    print("    offset   share    (* marks an amount the round function actually uses)")
    for at in range(32):
        share = residue[at] / float(total) if total else 0.0
        bar = "#" * int(round(share * 32 * 26))
        mark = " *" if at in named else "  "
        print("    %6d%s  %.4f  %s" % (at, mark, share, bar))

    print()
    print("    A flat column means the web is complete and speaks nothing: every position reaches")
    print("    every other equally. Occupancy piled on the marked rows is the round function's own")
    print("    transport still visible in the graph, before enough rounds stack to erase it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
