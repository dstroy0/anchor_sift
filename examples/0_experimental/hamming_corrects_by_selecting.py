#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Hamming(7,4) rejecting a channel's bit-flips by selecting the codeword the parity checks allow.
#
#   Usage:  python examples/0_experimental/hamming_corrects_by_selecting.py
#
# This reads no corpus, so it sits in 0_experimental: an algorithm shown working, a coding-theory filter
# beside the signal ones. The channel flips bits; the code rejects the flip by choosing, of the sixteen
# codewords, the one within a single flip of what arrived. It corrects by selecting the candidate the
# necessary conditions leave standing, which is the sift's move carried into coding theory.
#
# Two decoders are run: the syndrome, which reads the failed parity checks as the flipped position, and
# the nearest codeword, which reads no parity at all. Hamming(7,4) is a perfect code, so the two are the
# same decoder by a theorem and agree on every word; a deliberately broken syndrome table is run beside
# them to show the agreement has teeth. The floor is the Hamming bound, stated not tuned: within one
# flip the exact word is recovered, and two flips are corrected confidently to the WRONG word, because a
# perfect code leaves no room to tell a double error from a single one elsewhere.

import io
import os
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from sift.hamming import encode, syndrome_decode, nearest_decode, DATA_INDICES  # noqa: E402

SEED = 0x8A33
TRIALS = 400


def broken_syndrome_decode(word):
    """A wrong decoder, to prove the two good ones can split: it never flips, it just reads the word."""
    return [word[index] for index in DATA_INDICES], 0


def flip(word, positions):
    out = list(word)
    for position in positions:
        out[position] ^= 1
    return out


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    rng = random.Random(SEED)
    out.write("  Hamming(7,4) corrects by selecting the codeword the parity checks allow\n")
    out.write("  declared inputs: trials=%d seed=0x%X\n\n" % (TRIALS, SEED))

    # single-bit errors: both routes recover the sent word exactly
    corrected_syn = corrected_near = agree = 0
    for _ in range(TRIALS):
        data = [rng.randint(0, 1) for _ in range(4)]
        sent = encode(data)
        received = flip(sent, [rng.randrange(7)])          # exactly one flip
        syn, _ = syndrome_decode(received)
        near, _ = nearest_decode(received)
        corrected_syn += (syn == data)
        corrected_near += (near == data)
        agree += (syn == near)
    out.write("  single-bit errors over %d trials:\n" % TRIALS)
    out.write("    syndrome recovered the sent word:  %d / %d\n" % (corrected_syn, TRIALS))
    out.write("    nearest  recovered the sent word:  %d / %d\n" % (corrected_near, TRIALS))
    out.write("    the two routes agreed:             %d / %d\n" % (agree, TRIALS))

    # divergence probe: the broken decoder must split from the good ones
    sample = encode([1, 0, 1, 1])
    hit = flip(sample, [4])
    good = syndrome_decode(hit)[0]
    bad = broken_syndrome_decode(hit)[0]
    out.write("\n  divergence probe: broken decoder splits from the good one: %s\n" % (good != bad))

    # null: a clean channel corrects nothing and returns the sent word
    clean_ok = 0
    for _ in range(TRIALS):
        data = [rng.randint(0, 1) for _ in range(4)]
        sent = encode(data)
        syn, position = syndrome_decode(sent)
        clean_ok += ((syn == data) and (position == 0))
    out.write("  null: with no channel error, nothing is corrected: %d / %d untouched\n" % (clean_ok, TRIALS))

    # floor: two-bit errors are corrected confidently to the WRONG word (the Hamming bound)
    miscorrected = still_agree = 0
    for _ in range(TRIALS):
        data = [rng.randint(0, 1) for _ in range(4)]
        sent = encode(data)
        received = flip(sent, rng.sample(range(7), 2))     # exactly two flips
        syn, _ = syndrome_decode(received)
        near, _ = nearest_decode(received)
        if syn != data:
            miscorrected += 1
        if syn == near:
            still_agree += 1
    out.write("\n  floor: two-bit errors, over %d trials:\n" % TRIALS)
    out.write("    corrected to the WRONG word:       %d / %d\n" % (miscorrected, TRIALS))
    out.write("    and the two routes still agreed:   %d / %d\n" % (still_agree, TRIALS))
    out.write("\n  within one flip the recovery is exact and both routes agree by the perfect-code\n")
    out.write("  theorem; the broken probe shows that agreement can fail, so it means something. two\n")
    out.write("  flips are the floor: corrected confidently to a wrong codeword the two routes still\n")
    out.write("  agree on, which is the Hamming bound and not a defect.\n")
    out.flush()
    return 0 if (corrected_syn == TRIALS and corrected_near == TRIALS and agree == TRIALS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
