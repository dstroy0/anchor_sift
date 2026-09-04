#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask whether the square is ever the best description of a text, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/descriptor_bakeoff.py
#
# Which character follows which is four thousand ninety six numbers and has carried every language claim
# in this work. It has now been matched or beaten twice by something far smaller: a twenty one bin
# histogram of word lengths tied it on families, and a three number ratio of scripts beat it nearly five
# to one on Japanese authorship. So the question is whether there is any task here it wins.
#
# Six descriptions of the same texts are run against four questions. The one that matters most as a
# comparison is the marginal, which is how often each character is used and nothing about what follows
# what. It is the square with its structure removed. If the marginal matches the square, then the
# transitions the square exists to hold are worth nothing, and every result in this section rests on
# letter frequencies.
#
# Each question is scored the same way, by holding one text out and asking whether it lands with its own
# group. Guessing is stated for each so a score can be read without knowing how many groups there are.

import io
import os
import re
import statistics
import sys
import unicodedata
import zipfile

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from language_tree import FAMILY
from parallel_web import MORE
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = 64
LONGEST_WORD = 20


def marginal(text, ranks=RANKS):
    """How often each character is used, and nothing about what follows what.

    Always the full width, with zeros where a text has fewer symbols than that. A text using fifty
    characters would otherwise return fifty numbers where another returns sixty four, and the two could
    not be compared at all.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]
    total = float(sum(counts[symbol] for symbol in ordered))
    if total <= 0:
        return None
    values = numpy.zeros(ranks, dtype=numpy.float64)
    for place, symbol in enumerate(ordered):
        values[place] = counts[symbol] / total
    return values


def word_histogram(text):
    words = [word for word in re.split(r"\s+", text) if word]
    if len(words) < 2000:
        return None
    lengths = numpy.asarray([min(len(word), LONGEST_WORD) for word in words])
    spread = numpy.bincount(lengths, minlength=LONGEST_WORD + 1).astype(numpy.float64)
    return spread / spread.sum()


def word_two(text):
    words = [word for word in re.split(r"\s+", text) if word]
    if len(words) < 2000:
        return None
    lengths = numpy.asarray([float(min(len(word), LONGEST_WORD)) for word in words])
    return numpy.asarray([lengths.mean(), lengths.std()], dtype=numpy.float64)


def shape_two(text):
    """How many symbols the text effectively uses, and what share the commonest takes."""
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    total = float(len(text))
    shares = numpy.asarray([count / total for count in counts.values()])
    if len(shares) < 2:
        return None
    return numpy.asarray([1.0 / float((shares * shares).sum()), float(shares.max())],
                         dtype=numpy.float64)


DESCRIPTORS = (
    ("which character follows which", 4096, lambda text: web(text, RANKS)),
    ("the same, coarser", 256, lambda text: web(text, 16)),
    ("how often each character is used", RANKS, marginal),
    ("how the word lengths are spread", LONGEST_WORD + 1, word_histogram),
    ("word length, mean and spread", 2, word_two),
    ("alphabet size and commonest share", 2, shape_two),
)


def score(rows, groups_of):
    """Hold each text out and see whether it lands with its own group."""
    labels = sorted({groups_of(row) for row in rows})
    right = 0
    scored = 0
    for index, row in enumerate(rows):
        mine = groups_of(row)
        if sum(1 for other in rows if groups_of(other) == mine) < 2:
            continue
        scored += 1
        best = None
        picked = None
        for label in labels:
            kept = [other[1] for position, other in enumerate(rows)
                    if groups_of(other) == label and position != index]
            if not kept:
                continue
            distance = float(numpy.linalg.norm(row[1] - numpy.mean(numpy.stack(kept), axis=0)))
            if (best is None) or (distance < best):
                best = distance
                picked = label
        right += 1 if picked == mine else 0
    return right, scored, len(labels)


def load_texts(prefix, strip, cut, group):
    out = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith(prefix) and name.endswith(".txt")):
            continue
        text, _ = load(os.path.join(CORPORA, name), cap=cut * 2, clean=True)
        if (text is None) or (len(text) < cut):
            continue
        out.append((group(name[strip:-4]), text[:cut]))
    return out


def german_texts(cut, per_century=45):
    out = []
    for century in ("1600-1699", "1700-1799", "1800-1899"):
        path = os.path.join(CORPORA, "dta_%s.zip" % century)
        if not os.path.isfile(path):
            continue
        kept = 0
        with zipfile.ZipFile(path) as bundle:
            for name in sorted(bundle.namelist()):
                if kept >= per_century or not name.endswith(".txt"):
                    continue
                try:
                    text = bundle.read(name).decode("utf-8", errors="replace")
                except Exception:
                    continue
                text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
                if len(text) < cut:
                    continue
                out.append((century, text[:cut]))
                kept += 1
    return out


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    families = dict(FAMILY)
    families.update(MORE)

    tasks = []
    held = load_texts("para_", 5, 300000, lambda stem: families.get(stem, "?"))
    tasks.append(("which family a language is in", [row for row in held if row[0] != "?"]))
    tasks.append(("which writer wrote it, english",
                  load_texts("author_", 7, 200000, lambda stem: stem.rsplit("_", 1)[0])))
    tasks.append(("which writer wrote it, japanese",
                  load_texts("jp_", 3, 30000, lambda stem: stem.rsplit("_", 2)[0])))
    tasks.append(("which century it is from, german", german_texts(60000)))

    for title, rows in tasks:
        if len(rows) < 8:
            out.write("  %s: too few texts\n\n" % title)
            continue
        out.write("  %s, %d texts\n" % (title, len(rows)))
        out.write("    %-36s %-9s %-13s %s\n" % ("description", "numbers", "found", "share"))
        best = None
        for label, count, maker in DESCRIPTORS:
            described = []
            for group, text in rows:
                values = maker(text)
                if values is not None:
                    described.append((group, values))
            if len(described) < 8:
                out.write("    %-36s %-9d %s\n" % (label, count, "cannot be measured here"))
                continue
            right, scored, groups = score(described, lambda row: row[0])
            if not scored:
                continue
            share = 100.0 * right / scored
            out.write("    %-36s %-9d %-13s %.1f percent\n"
                      % (label, count, "%d of %d" % (right, scored), share))
            if (best is None) or (share > best[0]):
                best = (share, label, count)
        if best:
            out.write("    guessing gets %.1f percent, and the best here is %s at %d numbers\n\n"
                      % (100.0 / max(len({row[0] for row in rows}), 1), best[1], best[2]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
