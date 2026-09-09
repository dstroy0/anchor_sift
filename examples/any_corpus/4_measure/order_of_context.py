#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-4-005
#
# Does the information in a text close at a finite order, and where does the reading stop working?
#
#   Usage:  python examples/any_corpus/4_measure/order_of_context.py corpus.txt [more.txt ...]
#
# Written as the decomposition it names, the question is exact. The entropy of a block of n symbols
# is the sum of n conditional entropies by the chain rule, each one what that order predicts that
# the orders below it could not, and the object closes if those increments reach zero.
#
# The first answer was wrong and the way it was wrong is the useful part. Over 400000 characters the
# increments rose to order 4 and fell, which was recorded as closure at a finite depth. Over six
# million they rise to order 5, and the value there is larger than order 4 held before. The peak
# moved with the amount of data. That is a measurement running out of samples, and never a text
# doing anything.
#
# So the estimator is checked against a case whose answer is arithmetic instead of estimated. A
# shuffled text's symbols are independent by construction. A block of n of them holds exactly n
# times the entropy of one, and the gap between that and what the estimator returns is the error
# itself. Divided by what pure undersampling predicts it has to be one curve for every text, and a
# text leaving that curve is telling us the reading is wrong.
#
# Matching is run beside it because it has no such wall. At each position the shortest string the
# window behind it has not seen is found. A dependency of any length shows as a long match, and
# nothing needs to be seen many times. Where counting sees four symbols, this sees a quarter of a
# million and is still finding something.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.block_entropy import increments, undersampling_error  # noqa: E402
from measure.match_rate import match_rate  # noqa: E402
from representation.text.corpus import fold_lines  # noqa: E402
from reference.shuffles import scrambled_within  # noqa: E402

CAP = 4000000
LEAST = 300000
RANKS = 12
ORDERS = 7
WINDOWS = (1024, 4096, 16384, 65536)
SEED = 0x51F7


def main():
    if len(sys.argv) < 2:
        print("usage: order_of_context.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = fold_lines(handle.read(CAP))
        if len(text) < LEAST:
            out.write("  %-24s too short\n" % os.path.basename(path)[:-4])
            continue

        counts = {}
        for symbol in text:
            counts[symbol] = counts.get(symbol, 0) + 1
        ranked = sorted(counts, key=lambda symbol: -counts[symbol])[:RANKS - 1]
        seat = {symbol: place for place, symbol in enumerate(ranked)}
        coded = numpy.asarray([seat.get(symbol, RANKS - 1) for symbol in text], dtype=numpy.int64)

        out.write("%s, %d characters folded to %d symbols\n"
                  % (os.path.basename(path)[:-4], len(text), RANKS))

        marks = increments(coded, RANKS, ORDERS)
        out.write("  what each order adds, in bits per symbol\n    %s\n"
                  % "  ".join("%.4f" % value for value in marks))

        out.write("  the estimator's own error, over what pure undersampling predicts\n    ")
        for order in range(1, ORDERS + 1):
            error, ratio = undersampling_error(coded, RANKS, order, SEED)
            out.write("%s  " % ("%.3f" % ratio if ratio is not None else "none"))
        out.write("\n  a value near one is undersampling alone; leaving it means the reading is\n")
        out.write("  outside its range from that order on\n")

        rng = numpy.random.default_rng(SEED)
        scattered = "".join(chr(one) for one in scrambled_within(
            bytearray(min(ord(one), 255) for one in text[:LEAST]), 256, SEED))
        out.write("\n  bits per symbol by matching, as the window behind each position grows\n")
        out.write("  %-12s %s\n" % ("", "  ".join("%9d" % window for window in WINDOWS)))
        for label, series in (("as written", text), ("scrambled", scattered)):
            row = []
            for window in WINDOWS:
                value = match_rate(series, window, numpy.random.default_rng(SEED), samples=800)
                row.append("%9.4f" % value if value is not None else "%9s" % "short")
            out.write("  %-12s %s\n" % (label, "  ".join(row)))
        del rng
        out.write("\n  a rate still falling at the widest window means the text holds something\n")
        out.write("  at that distance, and the scrambled row must not fall at all\n\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
