#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure the error in the entropy reading against a case whose answer is known, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/bias_calibration.py
#
# Whether a text closes at a finite order came out differently at two sample sizes: the increments peaked
# at order 4 over 400000 characters and at order 5 over six million, and the peak moved with the data
# instead of staying with the text. That is the estimator failing, and it was being corrected by
# subtracting a shuffled text's increments from the real ones, which mixes the error with whatever the
# shuffle's own estimate did.
#
# The shuffle does not need estimating. Its symbols are independent by construction, so the true entropy
# of a block of n of them is exactly n times the entropy of one, and that is arithmetic and not a
# measurement. Comparing it to what the estimator returns gives the error exactly, at every order, for
# every text.
#
# That also makes the error checkable instead of assumed. An error that comes only from counting too few
# samples in too many bins depends on the bins and the samples and on nothing else, so once it is divided
# by the bins seen over the samples taken it must be one curve for every text here. A text that leaves
# that curve is not telling us about language. It is telling us the reading is wrong.

import io
import math
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from order_increments import CAP, LEAST, RANKS, SEED, WANTED

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

ORDERS = 7


def counted(coded, order, width):
    """Block counts at one length, and how many distinct blocks were actually seen."""
    if len(coded) <= order:
        return None, None, None
    placed = numpy.zeros(len(coded) - order + 1, dtype=numpy.int64)
    for step in range(order):
        placed = (placed * width) + coded[step:len(coded) - order + 1 + step]
    counts = numpy.bincount(placed).astype(numpy.float64)
    counts = counts[counts > 0]
    shares = counts / counts.sum()
    return float(-(shares * numpy.log2(shares)).sum()), len(counts), float(counts.sum())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the error in the reading, in bits, against a case whose answer is arithmetic\n\n")
    header = "  ".join("%8s" % ("order %d" % (order + 1)) for order in range(ORDERS))
    out.write("  %-22s %s\n" % ("text", header))

    gathered = []
    for label, name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue

        counts = {}
        for symbol in text:
            counts[symbol] = counts.get(symbol, 0) + 1
        ranked = sorted(counts, key=lambda symbol: -counts[symbol])[:RANKS - 1]
        seat = {symbol: place for place, symbol in enumerate(ranked)}
        coded = numpy.asarray([seat.get(symbol, RANKS - 1) for symbol in text], dtype=numpy.int64)

        scattered = coded.copy()
        numpy.random.default_rng(SEED).shuffle(scattered)

        # The shuffle's symbols are independent, so a block of n of them holds exactly n times the
        # entropy of one. Nothing here is estimated.
        shares = numpy.bincount(coded, minlength=RANKS).astype(numpy.float64)
        shares = shares[shares > 0] / len(coded)
        single = float(-(shares * numpy.log2(shares)).sum())

        row = []
        marks = []
        for order in range(1, ORDERS + 1):
            measured, seen, taken = counted(scattered, order, RANKS)
            if measured is None:
                break
            error = (order * single) - measured
            row.append("%8.4f" % error)
            marks.append((order, error, seen, taken))
        gathered.append((label, single, marks))
        out.write("  %-22s %s\n" % (label, "  ".join(row)))

    out.write("\n  the same error divided by the bins seen over the samples taken\n")
    out.write("  %-22s %s\n" % ("text", header))
    for label, single, marks in gathered:
        row = []
        for order, error, seen, taken in marks:
            expected = (seen - 1) / (2.0 * taken * math.log(2.0))
            row.append("%8.3f" % (error / expected) if expected > 0 else "%8s" % "none")
        out.write("  %-22s %s\n" % (label, "  ".join(row)))

    out.write("\n  one curve for every text means the error is only undersampling\n")
    out.write("  a text leaving that curve means the reading itself is wrong\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
