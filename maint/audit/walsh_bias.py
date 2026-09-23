"""Every linear approximation at once, by Walsh-Hadamard, instead of a sampled few.

The first version of this search tested mask pairs one at a time: pick some masks, walk the nonces,
count agreements. That is O(masks times nonces) and it samples, so it can only ever report the best
of whatever it happened to draw. Four thousand masks out of four billion is not a search.

The transform does the whole thing. For a fixed output mask beta, put

    g[x] = (-1) ^ parity(digest(x) AND beta)

over a nonce range of length 2^k. The Walsh-Hadamard transform of g gives, at index alpha, exactly
the sum over x of (-1)^(parity(x AND alpha) XOR parity(digest(x) AND beta)). That is the bias of
EVERY input mask simultaneously, in k times 2^k butterfly operations rather than 2^k per mask.

    sampled:     4000 masks, 160 million bignum operations, best-of-what-was-drawn
    transform:   all 2^k masks, k times 2^k integer adds, exhaustive

So the transform is both complete and cheaper, which is the usual shape of using the right algorithm.

OUT OF SAMPLE STILL APPLIES

The transform is exhaustive over masks, so there is no held-out mask space. The held-out axis is the
nonces: the best alpha is found on one range and its bias is then measured on a disjoint range it
never saw. A real approximation holds there and a selection artifact does not, and over 2^k masks
the largest is always large by construction.

    python maint/audit/walsh_bias.py
    python maint/audit/walsh_bias.py --bits 22
"""

import argparse
import array
import hashlib
import math
import struct


def build_signs(first, span, beta):
    """g[x] = +1 or -1 by the parity of digest(first + x) AND beta.

    The array is arbitrary-width on purpose. An earlier version held these in array("i"), which is
    a thirty-two bit signed C integer, and the transform below sums them: after k stages a value can
    reach the full span, so at a span of 2^31 the accumulator wraps and the transform returns
    nonsense that looks like data. That is the same fault as the uint32 overflow found in
    survey_nonces, in an analysis script rather than a kernel.

    The SHA-256 state itself stays at thirty-two bits either side of this, because the mod 2^32 ring
    IS the function and widening it computes a different one. The distinction is the whole point:
    the ring is fixed by definition, the statistics over it grow without bound, and they must not
    share a width.
    """
    signs = [0] * span
    for offset in range(span):
        raw = hashlib.sha256(struct.pack("<Q", first + offset)).digest()
        value = int.from_bytes(raw, "big") & beta
        signs[offset] = 1 if (bin(value).count("1") & 1) == 0 else -1
    return signs


def walsh(signs, bits):
    """In-place Walsh-Hadamard. After it, signs[alpha] is the summed correlation for that mask."""
    span = 1 << bits
    step = 1
    while step < span:
        for start in range(0, span, step * 2):
            for at in range(start, start + step):
                low = signs[at]
                high = signs[at + step]
                signs[at] = low + high
                signs[at + step] = low - high
        step *= 2
    return signs


def measure_direct(first, span, alpha, beta):
    """The bias of one mask pair over a range, counted plainly. Used for the held-out check."""
    total = 0
    for offset in range(span):
        nonce = first + offset
        raw = hashlib.sha256(struct.pack("<Q", nonce)).digest()
        one = bin(nonce & alpha).count("1") & 1
        two = bin(int.from_bytes(raw, "big") & beta).count("1") & 1
        total += 1 if one == two else -1
    return total


def main():
    parser = argparse.ArgumentParser(description="Exhaustive linear approximation by transform.")
    parser.add_argument("--bits", type=int, default=20)
    parser.add_argument("--outputs", type=int, default=6)
    given = parser.parse_args()

    bits = given.bits
    span = 1 << bits
    print("  nonce range 2^%d = %s, so the transform covers all %s input masks"
          % (bits, format(span, ","), format(span, ",")))
    print("  a bias of one standard error here is %.1f counts" % math.sqrt(span))
    print()

    # Output masks: single digest bits, which are the thinnest and therefore the most likely to
    # carry a bias if anything does.
    betas = [(1 << (255 - position), position) for position in range(0, given.outputs * 40, 40)]

    print("    output bit   best input mask   bias (sd)   held-out (sd)   verdict")
    bar = math.sqrt(2.0 * math.log(span))     # the loudest of 2^bits under the null
    for beta, position in betas:
        signs = build_signs(0, span, beta)
        walsh(signs, bits)
        best_at, best = 0, 0
        for alpha in range(1, span):
            if abs(signs[alpha]) > abs(best):
                best_at, best = alpha, signs[alpha]
        found_sd = best / math.sqrt(span)

        # The held-out range: the same mask pair on nonces the transform never touched.
        check = measure_direct(span, span // 4, best_at, beta)
        check_sd = check / math.sqrt(span // 4)
        verdict = "SURVIVES" if abs(check_sd) >= 4.0 else "selection"
        print("    %10d   0x%08x        %+9.2f   %+13.2f   %s"
              % (position, best_at, found_sd, check_sd, verdict))

    print()
    print("    bar for the loudest of %s masks under the null: %.2f sd"
          % (format(span, ","), bar))
    print()
    print("    The found column is the maximum over every mask, so it is large by construction and")
    print("    carries no information on its own. The held-out column is the whole test: a real")
    print("    approximation predicts nonces it never saw, and a selection artifact does not.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
