#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Are the winning ring values composite, carrying a power-of-two factor structure, more than chance.

    python tools/view/nonce_ring_factor.py --check     the controls, each able to fail
    python tools/view/nonce_ring_factor.py             the reading over the corpus

THE CLAIM

A value below the NTT modulus is spottable by its power-of-two structure: its two-adic valuation, the
count of factors of two it carries, and whether it sits low in the ring. A maximum-entropy value has
the geometric valuation distribution any uniform residue has, half odd, a quarter valuation one, and
so on. A value that is composite in this way, not maximum entropy, carries a higher valuation than
that. The claim is that the winning nonce and hash, reduced into the proven ring, are enriched in
these composite values over a uniform residue.

THE MEASURE

For each winning nonce and each winning hash, the residue modulo each proven Proth prime, and its
two-adic valuation. The reading is the mean valuation across the corpus against the geometric null a
uniform residue gives, which has mean one, and a shuffle of the residues as the drawn floor so the
estimator's own bias is carried. A mean valuation over the band is enrichment in composite values.

WHY THE RING AND NOT THE RAW VALUE

The raw nonce is thirty-two bits and its low bits are the nonce's own, but the RESIDUE modulo a Proth
prime folds the whole value through the ring the twiddle proof establishes, a structure that is
spread in the raw bits can concentrate in the residue. That folding is the point of reading it in the
ring rather than as an integer.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
PROOFING = os.path.normpath(os.path.join(HERE, "..", "..", "examples", "proofing"))
if PROOFING not in sys.path:
    sys.path.insert(0, PROOFING)

import build_bend_view  # noqa: E402

MASK = 0xFFFFFFFF
PRIMES = (2013265921, 2281701377, 3892314113)  # The proven Proth primes k*2^27 + 1.


def two_adic(value):
    """The count of factors of two in a positive value, its two-adic valuation. Zero is called 32."""
    if value == 0:
        return 32
    count = 0
    while (value & 1) == 0:
        count += 1
        value >>= 1
    return count


def mean_valuation(values):
    return sum(values) / float(len(values)) if values else 0.0


def shuffle_band(residues, prime, draws, seed):
    """The mean valuation a reshuffle of residues gives: the estimator's floor, drawn not derived.

    A reshuffle of the same residues has the same distribution, so its mean valuation is the null the
    real mean is read against; a real enrichment is a mean the reshuffles do not reach.
    """
    generator = random.Random(seed)
    pool = list(residues)
    scores = []
    for _ in range(draws):
        generator.shuffle(pool)
        scores.append(mean_valuation([two_adic(value) for value in pool]))
    scores.sort()
    count = len(scores)
    return (scores[int(0.025 * (count - 1))], scores[int(0.5 * (count - 1))],
            scores[int(0.975 * (count - 1))])


def uniform_band(prime, count, draws, seed):
    """The mean valuation uniform residues of this ring give, the geometric null at this sample size."""
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        scores.append(mean_valuation([two_adic(generator.randrange(1, prime)) for _ in range(count)]))
    scores.sort()
    length = len(scores)
    return (scores[int(0.025 * (length - 1))], scores[int(0.5 * (length - 1))],
            scores[int(0.975 * (length - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # A UNIFORM RESIDUE HAS MEAN VALUATION ONE. Half the values are odd at valuation zero, a quarter at
    # one, an eighth at two, so the mean is one. If the estimator does not read that, it is wrong.
    generator = random.Random(3)
    uniform = [generator.randrange(1, PRIMES[0]) for _ in range(20000)]
    mean = mean_valuation([two_adic(value) for value in uniform])
    say("  mean two-adic valuation of 20000 uniform residues %.4f (want near 1.0)" % mean)
    if abs(mean - 1.0) > 0.1:
        say("    FAIL a uniform residue does not read mean valuation one")
        failed += 1

    # A PLANTED COMPOSITE SET READS HIGH. Values forced to carry four factors of two have mean
    # valuation at least four, far over the uniform band. If it does not clear it the reading is blind.
    planted = [(generator.randrange(1, PRIMES[0] >> 4) << 4) for _ in range(4000)]
    planted_mean = mean_valuation([two_adic(value) for value in planted])
    band = uniform_band(PRIMES[0], 4000, 200, 11)
    say("  planted values with four factors of two: mean valuation %.4f, uniform band up to %.4f"
        % (planted_mean, band[2]))
    if planted_mean <= band[2]:
        say("    FAIL a planted composite set did not clear the uniform band")
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

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    nonces = [int(block["nonce"]) & MASK for block in blocks]
    hashes = [int(block["id"], 16) for block in blocks]
    print("  %d real blocks, two-adic valuation of the nonce and the hash residue in each proven ring"
          % len(blocks))
    print("  uniform mean is 1.0; over the band is enrichment in composite, non-max-entropy values")
    print("  %14s %6s %14s %22s %10s" % ("value", "prime k", "mean valuation", "uniform band",
                                         "verdict"))
    for name, source in (("nonce", nonces), ("hash", hashes)):
        for prime in PRIMES:
            residues = [value % prime for value in source]
            residues = [value for value in residues if value != 0]
            live = mean_valuation([two_adic(value) for value in residues])
            band = uniform_band(prime, len(residues), 200, prime & 0xFFFF)
            verdict = "OVER" if live > band[2] else ("under" if live < band[0] else "in band")
            print("  %14s %6d %14.4f %10.4f to %.4f %10s"
                  % (name, prime >> 27, live, band[0], band[2], verdict))
    print("")
    print("  a mean valuation OVER the uniform band is the winning values carrying more factors of two")
    print("  in the ring than chance, the composite structure. in band is the boundary: no enrichment.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
