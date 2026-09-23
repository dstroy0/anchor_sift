"""Counter-rotate the FUNCTION: SHA-256 against itself with every rotation reversed.

The mirror-arm test could not answer this. Reflecting a point set negates every longitude, which
conjugates every coefficient, which negates every phase - for any data at all. The answer was fixed
by geometry before SHA was consulted, and it came back at 1e-16, which is float64's floor and not a
fact about hashing.

The handedness that could matter is in the function. SHA-256 turns one way, six times, and never the
other:

    Sigma0 = ROTR2  xor ROTR13 xor ROTR22        on the a chain
    Sigma1 = ROTR6  xor ROTR11 xor ROTR25        on the e chain
    sigma0 = ROTR7  xor ROTR18 xor SHR3          in the schedule
    sigma1 = ROTR17 xor ROTR19 xor SHR10         in the schedule

Replacing every ROTR with a ROTL of the same amount gives a function with identical structure and
opposite handedness. Everything else - the constants, the additions, the nonlinear terms, the round
count - is untouched. So the two differ in exactly one property and can be compared.

WHAT EACH OUTCOME MEANS

    same statistics    handedness is cosmetic. The rotation amounts matter, their direction does
                       not, and the design could have gone either way.
    different          the direction is load-bearing, and a reading that is mirror-blind by
                       construction has been discarding something real.

The shifts are left alone on purpose. SHR is not a rotation and has no mirror that preserves the
structure, so reversing it would change the function in a second way and spoil the comparison.

    python maint/audit/handedness.py
"""

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import natural_constants as nc

MASK = 0xFFFFFFFF
K = nc.round_constants()
IV = nc.starting_words()


def rotr(value, amount):
    return ((value >> amount) | (value << (32 - amount))) & MASK


def rotl(value, amount):
    return ((value << amount) | (value >> (32 - amount))) & MASK


def compress(block, handed, rounds=64):
    """One block of SHA-256. handed is +1 for the standard function, -1 for its mirror.

    Only the rotation DIRECTION changes. Amounts, constants, additions, the nonlinear terms and the
    round count are identical, so the two functions differ in one property and nothing else.
    """
    turn = rotr if handed > 0 else rotl
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
        maj = (a & b) ^ (a & c) ^ (b & c)
        t2 = (s0 + maj) & MASK
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
    return [(IV[i] + v) & MASK for i, v in enumerate((a, b, c, d, e, f, g, h))]


def digest_bits(words):
    bits = []
    for word in words:
        for at in range(31, -1, -1):
            bits.append((word >> at) & 1)
    return bits


def survey(handed, trials, rng):
    """Bit shares and the avalanche count, for one handedness."""
    counts = [0] * 256
    flips = []
    for _ in range(trials):
        block = [rng.getrandbits(32) for _ in range(16)]
        one = digest_bits(compress(block, handed))
        for at in range(256):
            counts[at] += one[at]
        changed = list(block)
        changed[rng.randrange(16)] ^= 1 << rng.randrange(32)
        two = digest_bits(compress(changed, handed))
        flips.append(sum(1 for at in range(256) if one[at] != two[at]))
    return counts, flips


def diffusion_depth(handed, trials, rng):
    """The round at which a single input bit first reaches half the output. Chirality, if it is
    load-bearing anywhere, is most likely to show as a difference in how fast the thing mixes."""
    out = []
    for rounds in range(1, 33):
        total = 0
        for _ in range(trials):
            block = [rng.getrandbits(32) for _ in range(16)]
            one = digest_bits(compress(block, handed, rounds))
            changed = list(block)
            changed[rng.randrange(16)] ^= 1 << rng.randrange(32)
            two = digest_bits(compress(changed, handed, rounds))
            total += sum(1 for at in range(256) if one[at] != two[at])
        out.append(total / float(trials))
    return out


def main():
    parser = argparse.ArgumentParser(description="SHA-256 against its mirror.")
    parser.add_argument("--trials", type=int, default=4000)
    given = parser.parse_args()
    trials = given.trials

    print("  %s trials per handedness, same seed so both see identical inputs" % format(trials, ","))
    print()
    print("=" * 76)
    print("  1. OUTPUT BIT SHARES")
    print("=" * 76)
    right_counts, right_flips = survey(+1, trials, random.Random(0x4A17))
    left_counts, left_flips = survey(-1, trials, random.Random(0x4A17))

    se = 0.5 / math.sqrt(trials)
    worst_r = max(abs((c / float(trials)) - 0.5) for c in right_counts) / se
    worst_l = max(abs((c / float(trials)) - 0.5) for c in left_counts) / se
    bar = math.sqrt(2.0 * math.log(256))
    print()
    print("    standard (ROTR)   loudest position %.2f sd" % worst_r)
    print("    mirror   (ROTL)   loudest position %.2f sd" % worst_l)
    print("    bar for the loudest of 256: %.2f sd" % bar)

    print()
    print("=" * 76)
    print("  2. AVALANCHE: output bits changed by one input bit")
    print("=" * 76)
    mr = sum(right_flips) / float(trials)
    ml = sum(left_flips) / float(trials)
    sr = math.sqrt(sum((v - mr) ** 2 for v in right_flips) / trials)
    sl = math.sqrt(sum((v - ml) ** 2 for v in left_flips) / trials)
    gap = (mr - ml) / math.sqrt((sr * sr / trials) + (sl * sl / trials))
    print()
    print("    standard (ROTR)   mean %.4f   spread %.4f   (128.0 is ideal)" % (mr, sr))
    print("    mirror   (ROTL)   mean %.4f   spread %.4f" % (ml, sl))
    print("    separation        %+.2f sd" % gap)

    print()
    print("=" * 76)
    print("  3. DIFFUSION DEPTH: how fast one bit reaches half the output")
    print("=" * 76)
    print()
    deep = max(200, trials // 20)
    right_curve = diffusion_depth(+1, deep, random.Random(0x9C3))
    left_curve = diffusion_depth(-1, deep, random.Random(0x9C3))
    print("    round   standard   mirror     gap")
    worst_round, worst_gap = 0, 0.0
    for index in range(0, 24, 2):
        one, two = right_curve[index], left_curve[index]
        if abs(one - two) > abs(worst_gap):
            worst_round, worst_gap = index + 1, one - two
        print("    %5d   %8.2f   %8.2f   %+7.2f" % (index + 1, one, two, one - two))
    half_right = next((r + 1 for r, v in enumerate(right_curve) if v >= 120.0), None)
    half_left = next((r + 1 for r, v in enumerate(left_curve) if v >= 120.0), None)
    print()
    print("    first round reaching 120 of 256 changed:  standard %s, mirror %s"
          % (half_right, half_left))

    print()
    print("=" * 76)
    print("  READING")
    print("=" * 76)
    print()
    if abs(gap) < 3.0 and half_right == half_left:
        print("    The two are statistically the same. Handedness is cosmetic: the rotation")
        print("    AMOUNTS carry the diffusion and their direction does not, so the design could")
        print("    have turned either way and a mirror-blind reading discards nothing.")
    else:
        print("    The two differ. Rotation direction is load-bearing, and any reading that is")
        print("    mirror-blind by construction has been discarding something the function uses.")
        print("    Largest diffusion gap %.2f bits at round %d." % (worst_gap, worst_round))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
