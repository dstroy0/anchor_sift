#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Where each pure corpus's distribution is going as it grows.
#
#   Usage:  python tools/dev_env/corpus_growth.py
#
# A corpus of n members is a sample of a distribution, not the distribution. That is why a candidate
# that looks nothing like anything already in the corpus is not thereby disqualified: at this n the
# corpus does not yet cover its own support, and support is still climbing.
#
# So the question is not whether a candidate resembles a member. It is whether the corpus with the
# candidate in it is still on the curve the corpus was already on. This prints that curve, per
# language, so the shape is visible before anything is decided by it.
#
# D_self is the estimator's resolution at each n, section 3. supp and H are section 4, reported
# beside it because D_self falls as the distribution concentrates and would otherwise be read as a
# fact about the language when it is a fact about the sample.

import collections
import glob
import io
import os
import sys

# Every Salishan category on the import path, so this can use a sibling from another one.
for _category in os.scandir(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from anchor_sift import convergence
from language_check import BY_CORPUS, english_texts

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")
SIFTED = os.path.join(CORPORA, "sifted")


def pure_by_language():
    """The known-pure lines of each language, from the eleven hand-read papers.

    Keyed the way language_check.BY_CORPUS is keyed, on the paper title, which is the second
    underscore-separated field of a record's filename and not the first. The first is the speaker.
    """
    held = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        language = BY_CORPUS.get(os.path.basename(path).split("_")[1])
        if not language:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.strip():
                    held[language].append(line.strip())
    return held


def candidates_by_language():
    """The lines the sift put on the language side, keyed by the language each paper names."""
    held = collections.defaultdict(list)
    index = os.path.join(SIFTED, "index.tsv")
    if not os.path.isfile(index):
        return held
    says = {}
    with open(index, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("#") or line.startswith("language\t"):
                continue
            parts = line.rstrip("\n").split("\t")
            if (len(parts) == 4) and parts[0]:
                says[parts[3]] = parts[0]
    for path in sorted(glob.glob(os.path.join(SIFTED, "*.sifted.tsv"))):
        stem = os.path.basename(path)[:-11]
        language = says.get(stem)
        if not language:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#") or line.startswith("page\t"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if (len(parts) == 5) and (parts[1] == "language"):
                    held[language].append(parts[4])
    return held


def show(out, name, lines):
    """One corpus's curve."""
    curve = convergence(lines)
    if not curve:
        out.write("  %-16s too few members to measure\n" % name[:16])
        return
    out.write("\n  %s, %d members\n" % (name, len(lines)))
    out.write("    %-9s %-10s %-9s %-9s %s\n"
              % ("members", "pairs", "D_self", "support", "H"))
    for members, pairs, own, supp, bits in curve:
        out.write("    %-9d %-10d %-9.4f %-9d %.2f\n" % (members, pairs, own, supp, bits))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    pure = pure_by_language()
    found = candidates_by_language()

    out.write("  the known-pure corpora, as they grow\n")
    for name in sorted(pure):
        show(out, name, pure[name])

    out.write("\n\n  the same languages with the sifted candidates added\n")
    for name in sorted(pure):
        if found.get(name):
            show(out, "%s + %d candidates" % (name, len(found[name])),
                 pure[name] + found[name])

    out.write("\n\n  languages held only as candidates, with no hand-read corpus at all\n")
    for name in sorted(found):
        if name not in pure:
            show(out, name, found[name])

    out.write("\n  a curve still climbing in support is a corpus that has not seen its own\n")
    out.write("  alphabet yet, and a candidate unlike every member of it is not thereby wrong\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
