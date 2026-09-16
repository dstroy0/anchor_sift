#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Where each pure corpus's distribution is going as it grows.
#
#   Usage:  python maint/data/salishan/anchor_sift_algorithmic_extraction/corpus_growth.py
#
# A corpus of n members is a sample of a distribution, not the distribution. A candidate that looks
# nothing like anything already in the corpus is therefore not disqualified: at this n the
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
import subprocess
import sys

# Every Salishan category on the import path, so this can use a sibling from another one.
for _category in os.scandir(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))):
    if _category.is_dir():
        sys.path.insert(0, _category.path)
# The engine's instrument directory, found by walking up to the repository. anchor_sift lives in the
# engine and not beside this file, and nothing on the path above reaches it.
_at = os.path.dirname(os.path.abspath(__file__))
while (_at != os.path.dirname(_at)) and not os.path.isdir(os.path.join(_at, "src", "engine")):
    _at = os.path.dirname(_at)
sys.path.insert(0, os.path.join(_at, "src", "engine", "python", "instrument"))

from anchor_sift import convergence
from language_check import BY_CORPUS, english_texts

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


def pure_by_language():
    """The known-pure lines of each language, from the eleven hand-read papers.

    Keyed the way language_check.BY_CORPUS is keyed, on the paper title, the second
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
