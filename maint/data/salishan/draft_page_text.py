#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write a first draft of what the page says, for a paper whose text is the font's encoding.
#
#   Usage:  python maint/data/salishan/draft_page_text.py <stem>
#
# Writes build/papers/<stem>.page.txt, line for line with the extraction, and a page of one is a page
# of the other. Every rule it applies is in lyon_encoding.py, and the file it writes is a draft: it
# is not the paper until a person has read the rendered page beside it.
#
# closed_spaces is not applied here, although these papers do break words. Its rule is that a space
# after a stacked mark is inserted, and in these two the space lands in front of the mark instead:
# the extraction writes c ’kaPít@t for ck̓aʔítət. Running it after the map welds the wrong pairs,
# turning sti ’m uì into stim̓uɬ, because the mark now sits at the end of a token. Which of these
# spaces is a word boundary is what the page settles: iP ’kl is two words and i ’klíP is one.

import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "corpus_script_extraction"))

from lyon_encoding import drafted  # noqa: E402

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
PAPERS = os.path.join(ROOT, "build", "papers")


def draft(stem):
    """One paper's extraction as a draft of the page, written beside it, and the line count."""
    source = os.path.join(PAPERS, "%s.txt" % stem)
    target = os.path.join(PAPERS, "%s.page.txt" % stem)
    with open(source, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    out = [drafted(one) for one in lines]
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    return target, len(lines)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for stem in sys.argv[1:]:
        target, count = draft(stem)
        out.write("  %s  %d lines\n" % (os.path.basename(target), count))
    out.write("\n  a draft, not the paper. read the rendered page beside it before trusting a line.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
