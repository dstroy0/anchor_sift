#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether a writer has a mark of their own, and at which unit, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/author_test.py
#
# Seven writers, five works each, all English prose of roughly one period. The language is fixed, the
# script is fixed, the century is nearly fixed, and the only thing left changing is who wrote it.
#
# The night's results predict the two units apart. Reading which character follows which turned out to
# follow a writing system: it pairs Zulu with Xhosa when they share an alphabet, loses Tamil from
# Malayalam when their scripts diverge, and moves twice as far for a change of characters as for no change
# at all. These seven writers share an alphabet entirely, so that reading has nothing to work with and
# should come out near chance.
#
# Word choice is the other unit, and it is where authorship has been found since the disputed Federalist
# papers were settled on function word frequencies alone. It is also the unit where composition drifts
# within a text, which was raised earlier as a fault in the whole approach and shown to be negligible at
# character level. At word level it is not negligible, so the same drift that could not touch the
# character reading is live here.
#
# Both are measured on the same texts, held out one at a time. Guessing gets one in seven.

import io
import os
import re
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 300000
RANKS = 64
COMMON_WORDS = 150


def word_profile(text, vocabulary):
    """How often this text uses each of the words the whole set uses most.

    The words are chosen from every text together and not from each one, so a writer is described by how
    they use a shared vocabulary and not by which vocabulary they happen to have.
    """
    words = re.findall(r"[a-z']+", text.lower())
    if len(words) < 5000:
        return None
    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    total = float(len(words))
    return numpy.asarray([counts.get(word, 0) / total for word in vocabulary],
                         dtype=numpy.float64)


def leave_one_out(rows):
    """Assign each work to the writer whose other works it lands nearest."""
    writers = sorted({row[0] for row in rows})
    correct = 0
    confused = {}
    for index, (writer, _, values) in enumerate(rows):
        best = None
        picked = None
        for other in writers:
            kept = [row[2] for position, row in enumerate(rows)
                    if row[0] == other and position != index]
            if not kept:
                continue
            middle = numpy.mean(numpy.stack(kept), axis=0)
            distance = float(numpy.linalg.norm(values - middle))
            if (best is None) or (distance < best):
                best = distance
                picked = other
        if picked is None:
            continue
        correct += 1 if picked == writer else 0
        if picked != writer:
            confused[(writer, picked)] = confused.get((writer, picked), 0) + 1
    return correct, len(rows), confused


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    loaded = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("author_") and name.endswith(".txt")):
            continue
        writer = name[7:].rsplit("_", 1)[0]
        text, gate = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 2, clean=False)
        if text is None:
            out.write("  %-28s refused by the gate: %s\n" % (name[:28], gate))
            continue
        if len(text) < SAME_LENGTH:
            # The gate's note here read as though the gate had rejected a file it passed
            out.write("  %-28s passed the gate and holds %d characters, under the %d needed\n"
                      % (name[:28], len(text), SAME_LENGTH))
            continue
        loaded.append((writer, name[:-4], text[:SAME_LENGTH]))

    writers = sorted({row[0] for row in loaded})
    if len(writers) < 4:
        out.write("  only %d writers held\n" % len(writers))
        out.flush()
        return 0

    out.write("  %d works by %d writers, each cut to %d characters, so guessing gets %.1f percent\n\n"
              % (len(loaded), len(writers), SAME_LENGTH, 100.0 / len(writers)))
    for writer in writers:
        out.write("  %-14s %d works\n" % (writer, sum(1 for row in loaded if row[0] == writer)))

    counts = {}
    for _, _, text in loaded:
        for word in re.findall(r"[a-z']+", text.lower()):
            counts[word] = counts.get(word, 0) + 1
    vocabulary = sorted(counts, key=lambda word: -counts[word])[:COMMON_WORDS]

    out.write("\n  %-30s %-14s %s\n" % ("reading", "correct", "share"))
    results = []
    for label, maker in (("which character follows which", lambda text: web(text, RANKS)),
                         ("how often each common word", lambda text: word_profile(text, vocabulary))):
        rows = []
        for writer, name, text in loaded:
            values = maker(text)
            if values is not None:
                rows.append((writer, name, values))
        if len(rows) < 8:
            continue
        correct, total, confused = leave_one_out(rows)
        out.write("  %-30s %-14s %.1f percent\n"
                  % (label, "%d of %d" % (correct, total), 100.0 * correct / total))
        results.append((label, rows, confused))

    for label, rows, confused in results:
        held = {}
        for writer, _, values in rows:
            held.setdefault(writer, []).append(values)
        inside = []
        across = []
        for writer, works in held.items():
            for index, one in enumerate(works):
                for two in works[index + 1:]:
                    inside.append(float(numpy.linalg.norm(one - two)))
            for other, theirs in held.items():
                if other <= writer:
                    continue
                for one in works:
                    for two in theirs:
                        across.append(float(numpy.linalg.norm(one - two)))
        if inside and across:
            out.write("\n  %s\n" % label)
            out.write("    two works by one writer     %.4f\n" % statistics.fmean(inside))
            out.write("    two works by two writers    %.4f\n" % statistics.fmean(across))
            out.write("    a writer holds together: %s\n"
                      % ("yes" if statistics.fmean(inside) < statistics.fmean(across) else "no"))
        if confused:
            for (was, went), count in sorted(confused.items(), key=lambda pair: -pair[1])[:4]:
                out.write("    %-12s taken for %-12s %d\n" % (was, went, count))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
