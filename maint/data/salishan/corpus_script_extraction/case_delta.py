#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find formatting damage by matching case-sensitively against a corpus known to be right.
#
#   Usage:  python maint/data/salishan/corpus_script_extraction/case_delta.py
#
# Case carries meaning. Essen capitalized mid-sentence is not essen, and none of these orthographies
# capitalizes at random either: a capital in the middle of a word is labialization in one paper's
# convention, a glottal stop in another's damaged font, and a sentence boundary in neither.
#
# So match twice. A token that the pure corpus holds exactly is right. A token the pure corpus holds
# only once case is folded away is the same word written wrong, and the difference between the two
# counts is the formatting damage in a paper, measured and not guessed at.
#
# This needs the oracle to be true, and it runs against the .pure.txt files instead of the papers.
# Those came out of nine readers written line by line against nine layouts.

import glob
import io
import os
import subprocess
import sys

def _repository_root():
    """This repository, asked of git rather than inferred from a marker directory.

    The marker climbed to before was build/, which the repository PRODUCES rather than CONTAINS, so
    a linked worktree and a never-built clone both lack it. The climb then walked past the root it
    was looking for into another checkout entirely, and every path derived from it pointed at a
    different tree than the tool was run from. That lands on a real repository with real files,
    which is indistinguishable from working.

    A marker infers the root. Git answers it. The climb below is kept only for an exported tree with
    no git directory, and it looks for src/engine, which is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run.

    Git's own variables are cleared first. Inside a hook GIT_DIR is exported, and a rev-parse that
    inherits it answers about that repository rather than about the directory it was asked from,
    returning the current directory instead of the root.
    """
    start = os.path.dirname(os.path.abspath(__file__))
    environment = dict(os.environ)
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_COMMON_DIR"):
        environment.pop(key, None)

    try:
        said = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=start,
                                       stderr=subprocess.PIPE, env=environment)
    except (OSError, subprocess.CalledProcessError):
        said = b""

    top = said.decode("utf-8", "replace").strip()
    if top and os.path.isdir(top):
        return os.path.abspath(top)

    climbed = start
    while (climbed != os.path.dirname(climbed)) \
            and not os.path.isdir(os.path.join(climbed, "src", "engine")):
        climbed = os.path.dirname(climbed)
    return climbed


ROOT = _repository_root()
CORPORA = os.path.join(ROOT, "build", "corpora")
SIFTED = os.path.join(CORPORA, "sifted")

EDGES = ".,!?;:“”‘’\"'()[]…«»{}"


def pure_vocabulary():
    """Every word form the hand-read corpora hold, kept as written and folded."""
    exact = set()
    folded = {}
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                for token in line.split():
                    plain = token.strip(EDGES)
                    if len(plain) < 2:
                        continue
                    exact.add(plain)
                    folded.setdefault(plain.casefold(), set()).add(plain)
    return exact, folded


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    exact, folded = pure_vocabulary()
    if not exact:
        out.write("  no pure corpus to match against, run the nine readers first\n")
        out.flush()
        return 1
    out.write("  oracle: %d forms, %d once case is folded\n" % (len(exact), len(folded)))

    rows = []
    shown = []
    for path in sorted(glob.glob(os.path.join(SIFTED, "*.sifted.tsv"))):
        right = 0
        wrong = 0
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#") or line.startswith("page\t"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 5:
                    continue
                for token in parts[4].split():
                    plain = token.strip(EDGES)
                    if len(plain) < 2:
                        continue
                    if plain in exact:
                        right += 1
                        continue
                    others = folded.get(plain.casefold())
                    if others:
                        wrong += 1
                        if len(shown) < 16:
                            shown.append((plain, sorted(others)[0],
                                          os.path.basename(path)[:-11]))
        if right or wrong:
            rows.append((wrong, right, os.path.basename(path)[:-11]))

    rows.sort(reverse=True)
    out.write("\n  %-44s %-10s %s\n" % ("paper", "as written", "wrong case"))
    for wrong, right, stem in rows[:16]:
        out.write("  %-44s %-10d %d\n" % (stem[:44], right, wrong))

    out.write("\n  %d papers share a form with the oracle, %d forms match as written, "
              "%d only once case is folded\n"
              % (len(rows), sum(one[1] for one in rows), sum(one[0] for one in rows)))
    if shown:
        out.write("\n  what the case match caught\n")
        for got, want, stem in shown:
            out.write("    %-22s the oracle writes %-22s %s\n" % (got, want, stem[:34]))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
