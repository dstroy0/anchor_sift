"""Perturb the field and measure what moves, instead of reading the empty place.

Almost every test in this tree reads a state: bit shares, spectra, swing, co-variation. Those look
at the field itself, and a field that is flat reads flat whatever is done to it. The measurements
that find things in physics are not of that shape. Nobody sees vacuum fluctuation by looking at
vacuum; they see the Lamb shift, the Casimir force, the anomalous moment - a RESPONSE of something
else, with the fluctuation inferred from how the something else moved.

The quantisation here is real rather than borrowed. The field is 256 discrete bits, the excitation
is exactly one bit flipped, and the response is counted in whole bits. Nothing is approximated to a
continuum at any point.

Three response measurements, each a different way of poking it:

  susceptibility  which output bit responds to which INPUT bit. A 512 by 256 table, and the
                  question is whether any cell departs from one half by more than the loudest
                  cell of a fair table does.
  pair response   whether two input bits flipped together move the output differently from the
                  sum of their separate effects. That is a second-order response and it is
                  invisible to any single-bit measurement by construction.
  decay           how the response falls with depth, and whether it falls the same way for every
                  input bit. A bit whose influence dies slower than the rest is a channel.

Every bar is drawn from a null arm running the identical statistic where the answer is known to be
nothing, because six derived bars in this work came in too low.

    python maint/audit/response.py
    python maint/audit/response.py --samples 40000
"""

import argparse
import hashlib
import math
import random


def digest_int(value):
    return int.from_bytes(hashlib.sha256(value.to_bytes(64, "big")).digest(), "big")


def susceptibility(samples, rng, live=True):
    """Per (input bit, output bit), how often the output moves when that input moves.

    With `live` false the twin is an independent draw, so every cell is a fair coin and the table
    is the null: its loudest cell is the bar the real table has to clear.
    """
    table = [[0] * 256 for _ in range(512)]
    hits = [0] * 512
    for _ in range(samples):
        base = rng.getrandbits(512)
        which = rng.randrange(512)
        twin = (base ^ (1 << which)) if live else rng.getrandbits(512)
        diff = digest_int(base) ^ digest_int(twin)
        hits[which] += 1
        row = table[which]
        while diff:
            low = diff & -diff
            row[low.bit_length() - 1] += 1
            diff ^= low
    return table, hits


def loudest_cell(table, hits):
    """The cell furthest from one half, in standard errors, over every cell with enough samples."""
    best = 0.0
    best_at = (0, 0)
    for source in range(512):
        seen = hits[source]
        if seen < 40:
            continue
        spread = 0.5 * math.sqrt(seen)
        for sink in range(256):
            deviation = table[source][sink] - (seen / 2.0)
            z = deviation / spread
            if abs(z) > abs(best):
                best, best_at = z, (source, sink)
    return best, best_at


def pair_response(samples, rng, live=True):
    """Second order: does flipping two input bits move the output differently from the sum?

    For a purely linear response the digest difference from flipping both equals the exclusive-or
    of the two single differences. The count of bits where it does NOT is the nonlinear part, and a
    fair comparison needs the same statistic where nothing is expected.
    """
    excess = []
    for _ in range(samples):
        base = rng.getrandbits(512)
        one = rng.randrange(512)
        two = rng.randrange(512)
        while two == one:
            two = rng.randrange(512)
        plain = digest_int(base)
        first = digest_int(base ^ (1 << one)) ^ plain
        second = digest_int(base ^ (1 << two)) ^ plain
        if live:
            both = digest_int(base ^ (1 << one) ^ (1 << two)) ^ plain
        else:
            both = digest_int(rng.getrandbits(512)) ^ plain
        excess.append(bin(both ^ first ^ second).count("1"))
    middle = sum(excess) / float(len(excess))
    spread = math.sqrt(sum((v - middle) ** 2 for v in excess) / len(excess))
    return middle, spread


def decay(samples, rng, depths=(2, 4, 6, 8, 10, 12, 16, 20)):
    """How the response grows with depth, and whether every input bit grows alike.

    Reduced-round SHA, one input bit flipped, counting output bits moved. A bit whose influence
    arrives faster or slower than the rest would be a channel, and the spread ACROSS input bits at
    each depth is what says whether any does.
    """
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))), "examples", "proofing"))
    import natural_constants as nc

    MASK = 0xFFFFFFFF
    K = nc.round_constants()
    IV = nc.starting_words()

    def turn(v, n):
        return ((v >> n) | (v << (32 - n))) & MASK

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

    rows = []
    for rounds in depths:
        per_source = [[] for _ in range(512)]
        for _ in range(samples):
            block = [rng.getrandbits(32) for _ in range(16)]
            which = rng.randrange(512)
            twin = list(block)
            twin[which // 32] ^= 1 << (which % 32)
            moved = bin(compress(block, rounds) ^ compress(twin, rounds)).count("1")
            per_source[which].append(moved)
        means = [sum(v) / float(len(v)) for v in per_source if len(v) >= 6]
        middle = sum(means) / len(means)
        spread = math.sqrt(sum((m - middle) ** 2 for m in means) / len(means))
        rows.append((rounds, middle, spread, len(means)))
    return rows


def main():
    parser = argparse.ArgumentParser(description="Response measurements.")
    parser.add_argument("--samples", type=int, default=24000)
    given = parser.parse_args()
    samples = given.samples

    print("  %s excitations per arm, one input bit at a time, response counted in whole bits"
          % format(samples, ","))
    print()
    print("=" * 78)
    print("  1. SUSCEPTIBILITY: which output responds to which input")
    print("=" * 78)
    null_table, null_hits = susceptibility(samples, random.Random(0x11), False)
    null_best, _ = loudest_cell(null_table, null_hits)
    real_table, real_hits = susceptibility(samples, random.Random(0x5EED), True)
    real_best, where = loudest_cell(real_table, real_hits)
    print()
    print("    null arm, loudest of 512x256 cells   %+.2f sd" % null_best)
    print("    real arm, loudest                    %+.2f sd   at input %d, output %d"
          % (real_best, where[0], where[1]))
    print("    verdict  %s" % ("CLEARS" if abs(real_best) > abs(null_best) else "inside the null"))

    print()
    print("=" * 78)
    print("  2. PAIR RESPONSE: is the second order anything")
    print("=" * 78)
    live_mid, live_spread = pair_response(samples // 3, random.Random(0x2A17))
    null_mid, null_spread = pair_response(samples // 3, random.Random(0x2A17), live=False)
    print()
    print("    both-flipped against the sum of singles   mean %.3f bits, spread %.3f"
          % (live_mid, live_spread))
    print("    the same where nothing is expected        mean %.3f bits, spread %.3f"
          % (null_mid, null_spread))
    gap = (live_mid - null_mid) / math.sqrt((live_spread ** 2 + null_spread ** 2)
                                            / (samples // 3))
    print("    separation                               %+.2f sd" % gap)
    print()
    print("    A linear response would put the live arm near zero: both-flipped would equal the")
    print("    exclusive-or of the singles exactly. It does not, and that excess IS the")
    print("    nonlinearity, which is the thing a single-bit measurement cannot see at all.")

    print()
    print("=" * 78)
    print("  3. DECAY: does every input bit arrive at the same rate")
    print("=" * 78)
    print()
    print("    rounds   mean bits moved   spread ACROSS input bits   sources")
    for rounds, middle, spread, seen in decay(max(2000, samples // 8), random.Random(0xDECA)):
        print("    %6d   %15.2f   %24.3f   %7d" % (rounds, middle, spread, seen))
    print()
    print("    The spread column is the one that matters. A bit whose influence arrives faster or")
    print("    slower than the rest is a channel; a spread that is just the sampling noise of the")
    print("    per-source means is not.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
