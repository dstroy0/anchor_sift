#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether the web separates written languages from generated text, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/signature_control.py
#
# The web of an alphabet puts 15 of 22 languages nearest a language in their own family, and the pairs it
# forms first are the correct ones. That establishes it as a signature of a language. It does not
# establish that what it reads is human, which is the stronger claim and needs something written by no
# one to compare against.
#
# The generated corpora are that comparison and they were made for it: a chain over an alphabet, at three
# sizes, with uniform and geometric weightings and one weighted to English letter frequencies, at three
# depths. They have a distribution and no meaning. If the web reads something human then every one of them
# should sit outside every language, and if they mix in then it reads a distribution that writing happens
# to have and generated text can have too.
#
# The English weighted chain is the sharpest of them, since it was given a real language's letter
# frequencies on purpose. If the web is fooled by anything it should be fooled by that one, and it is
# reported separately for that reason.
#
# Source code is included as a third kind: written by people, and not a natural language.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import CAP, LEAST, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = 64


def load(name):
    path = os.path.join(CORPORA, name)
    if name.endswith(".sym"):
        with open(path, "rb") as handle:
            raw = handle.read(CAP)
        text = "".join(chr(value) for value in raw)
    else:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
    return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    kinds = {}
    for name in sorted(os.listdir(CORPORA)):
        if name.startswith("lang_") and name.endswith(".txt"):
            kind, label = "language", name[5:].rsplit("_", 1)[0]
        elif name.startswith("monkey_") and name.endswith(".txt"):
            kind, label = "generated", name[7:-4]
        elif name.startswith("csource_") and name.endswith(".sym"):
            kind, label = "source", name[:-4]
        else:
            continue
        text = load(name)
        if len(text) < LEAST:
            continue
        values = web(text, RANKS)
        if values is not None:
            kinds.setdefault((kind, label), []).append(values)

    entries = [(kind, label, numpy.mean(numpy.stack(values), axis=0))
               for (kind, label), values in sorted(kinds.items())]
    languages = [row for row in entries if row[0] == "language"]
    if (len(languages) < 8) or (len(entries) - len(languages) < 2):
        out.write("  not enough of one kind to compare\n")
        out.flush()
        return 0

    out.write("  %-30s %-11s %-16s %-11s %s\n"
              % ("corpus", "kind", "nearest", "distance", "nearest is"))
    crossings = 0
    for kind, label, values in entries:
        marks = []
        for other_kind, other_label, other in entries:
            if other_label == label:
                continue
            marks.append((float(numpy.linalg.norm(values - other)), other_kind, other_label))
        marks.sort()
        distance, near_kind, near_label = marks[0]
        if kind != near_kind:
            crossings += 1
        if kind != "language":
            out.write("  %-30s %-11s %-16s %-11.5f %s\n"
                      % (label, kind, near_label, distance, near_kind))

    # How far the two kinds sit from each other against how far each sits from its own
    def spread(left, right):
        return numpy.mean([float(numpy.linalg.norm(one[2] - two[2]))
                           for one in left for two in right if one[1] != two[1]])

    made = [row for row in entries if row[0] == "generated"]
    out.write("\n  mean distance among the languages      %.5f\n" % spread(languages, languages))
    out.write("  mean distance among the generated      %.5f\n" % spread(made, made))
    out.write("  mean distance between the two kinds    %.5f\n" % spread(languages, made))
    out.write("\n  %d of %d corpora have their nearest neighbour in another kind\n"
              % (crossings, len(entries)))

    english = [row for row in made if "english" in row[1]]
    if english:
        marks = sorted((float(numpy.linalg.norm(english[0][2] - row[2])), row[0], row[1])
                       for row in entries if row[1] != english[0][1])
        out.write("  the chain given English letter frequencies is nearest %s, which is %s\n"
                  % (marks[0][2], marks[0][1]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
