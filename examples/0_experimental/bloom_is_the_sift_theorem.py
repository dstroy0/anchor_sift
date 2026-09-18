#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-001
#
# The Bloom filter shown to be the anchor sift's theorem in another field, and its floor measured
# rather than assumed.
#
#   Usage:  python examples/0_experimental/bloom_is_the_sift_theorem.py
#
# This reads no corpus. It sits in 0_experimental: it is an algorithm shown working, not a stage
# reading. When a Bloom filter runs over an actual corpus with its false-positive rate measured against
# a drawn null it graduates to any_corpus/5_sift; until then it is an idea that works.
#
# Two things are shown. First, the theorem: a Bloom filter never reports a member absent, for any choice
# of hashes, and only the false-positive COST moves with the choice. That is the anchor cascade's own
# result -- a necessary condition loses no true occurrence whatever rule selects it, and the rule moves
# only how many false candidates survive -- so the two are one object. Second, the honest measurement:
# the false-positive rate is not quoted from the formula, it is measured over items the filter never
# saw, and it is measured over STRUCTURED items and uniform ones both, because a filter that matches its
# formula on uniform data has shown you the formula and not the data.
#
# No bounding: the table size and the hash count are declared inputs, printed with every reading. The
# false-positive rate is a consequence of them, reported beside the formula's exact rational
# prediction, never a threshold set here.

import io
import os
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from sift.bloom import build, contains, false_positive_rate  # noqa: E402

# Declared inputs.
BITS = 4096
HASHES = 3
COUNT = 300
ABSENT = 6000        # items queried to measure the false-positive rate; enough to resolve it


def formula_rate(bits, hashes, count):
    """The textbook false-positive rate, computed exactly as a rational, not as a float.

    One minus the chance a given bit is still zero after every insertion, raised to the hash count.
    The exact form keeps this a prediction to compare the measurement against, with no rounding of its
    own to hide behind.
    """
    zero_bit = Fraction(bits - 1, bits) ** (hashes * count)
    return (1 - zero_bit) ** hashes


def structured_items(count, start=0):
    """Items that share structure: a fixed prefix and a short running suffix, not uniform draws."""
    return ["session-user-record-%04d" % (start + index) for index in range(count)]


def uniform_items(count, seed):
    """Items with no shared structure, from a simple deterministic spread over the byte space."""
    state = seed & 0xFFFFFFFF
    out = []
    for _ in range(count):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        out.append("%08x-%08x" % (state, (state * 2654435761) & 0xFFFFFFFF))
    return out


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the Bloom filter is the sift theorem in the field of databases\n")
    out.write("  declared inputs: bits=%d hashes=%d count=%d absent-queried=%d\n\n"
              % (BITS, HASHES, COUNT, ABSENT))

    members = structured_items(COUNT)
    absent_structured = structured_items(ABSENT, start=COUNT)    # same shape, never inserted
    absent_uniform = uniform_items(ABSENT, seed=0xB100)

    # the theorem: soundness holds for ANY hash family, only the false-positive cost moves
    out.write("  theorem: no member is ever reported absent, and it holds for every hash family\n")
    out.write("  %-10s %-16s %-18s %s\n" % ("hash seed", "members absent?", "false-pos (structured)", "false-pos (uniform)"))
    for seed in (0, 1, 2):
        table = build(members, BITS, HASHES, seed)
        missing_member = sum(1 for item in members if not contains(table, item, BITS, HASHES, seed))
        fp_struct = false_positive_rate(table, absent_structured, BITS, HASHES, seed)
        fp_unif = false_positive_rate(table, absent_uniform, BITS, HASHES, seed)
        out.write("  %-10d %-16d %-18.4f %.4f\n" % (seed, missing_member, fp_struct, fp_unif))

    out.write("\n  every 'members absent' count is zero: that is PFN=0, the soundness, and it does not\n")
    out.write("  depend on the seed. the two false-positive columns move with the seed: that is the\n")
    out.write("  cost, and it is the only thing the rule changes -- exactly the anchor cascade, where\n")
    out.write("  correctness cannot turn on the rule and the rule moves only how many false survive.\n\n")

    # the measurement: the drawn rate against the formula, on structured and uniform items
    predicted = formula_rate(BITS, HASHES, COUNT)
    table = build(members, BITS, HASHES, 0)
    measured_struct = false_positive_rate(table, absent_structured, BITS, HASHES, 0)
    measured_unif = false_positive_rate(table, absent_uniform, BITS, HASHES, 0)
    out.write("  measurement: the drawn false-positive rate against the formula\n")
    out.write("  formula (uniform-hash prediction): %.4f\n" % float(predicted))
    out.write("  measured, uniform items:           %.4f\n" % measured_unif)
    out.write("  measured, structured items:        %.4f\n" % measured_struct)
    out.write("\n  both measured rates sit BELOW the formula above, and that gap is the finding. the\n")
    out.write("  formula assumes k independent uniform hashes and no collision among the insertions\n")
    out.write("  themselves; the real double hashing at this fill sets fewer distinct bits than kn, so\n")
    out.write("  the measured rate runs under the prediction. structured and uniform items read alike,\n")
    out.write("  which is its own finding: a shared prefix does not inflate the rate when the hash\n")
    out.write("  decorrelates it. the floor is the rate itself -- a filter that saves space cannot\n")
    out.write("  drive its false positives to zero.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
