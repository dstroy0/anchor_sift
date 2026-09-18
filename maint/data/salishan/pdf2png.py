#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Render a paper's pages as images, which lets a person read the page and not the extraction.
#
#   Usage:  python maint/data/salishan/pdf2png.py <stem> <first> <last> [scale]
#
# The text under build/papers is what pypdf could recover, and on these papers that is not what the
# page says. Lyon's Okanagan comes out as ˇx@cm@ncut where the page prints x̌əcməncut: the caron
# arrives before its letter, the schwa as @, the glottal stop as P. Words break mid-token, and the
# five-line interlinear arrives one token per line with the surface run into its own parse.
#
# A hand extraction taken off that text records the extractor. The page is the source. The page
# is what gets read, and the images go under build/pages. That path reaches pages/ in the closed
# corpus, the way build/papers and build/oracles reach papers/ and oracles/. A paper's PDF, its
# text and the pictures a reader worked from all sit in one place.

import os
import subprocess
import sys

import pypdfium2


def _repository_root():
    """This repository, asked of git.

    The marker climbed to before was build/, which the repository PRODUCES  so
    a linked worktree and a never-built clone both lack it. The climb then walked past the root it
    was looking for into another checkout entirely, and every path derived from it pointed at a
    different tree than the tool was run from. That lands on a real repository with real files,
    which is indistinguishable from working.

    A marker infers the root. Git answers it. The climb below is kept only for an exported tree with
    no git directory, and it looks for src/engine, which is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run.

    Git's own variables are cleared first. Inside a hook GIT_DIR is exported, and a rev-parse that
    inherits it answers about that repository
    returning the current directory instead of the root.
    """
    start = os.path.dirname(os.path.abspath(__file__))
    environment = dict(os.environ)
    for key in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_PREFIX",
        "GIT_COMMON_DIR",
    ):
        environment.pop(key, None)

    try:
        said = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start,
            stderr=subprocess.PIPE,
            env=environment,
        )
    except (OSError, subprocess.CalledProcessError):
        said = b""

    top = said.decode("utf-8", "replace").strip()
    if top and os.path.isdir(top):
        return os.path.abspath(top)

    climbed = start
    while (climbed != os.path.dirname(climbed)) and not os.path.isdir(
        os.path.join(climbed, "src", "engine")
    ):
        climbed = os.path.dirname(climbed)
    return climbed


ROOT = _repository_root()
PAPERS = os.path.join(ROOT, "build", "papers")
PAGES = os.path.join(ROOT, "build", "pages")


def rendered(stem, first, last, scale):
    """Every page of one paper between first and last, written as a PNG, newest path last."""
    source = os.path.join(PAPERS, "%s.pdf" % stem)
    into = os.path.join(PAGES, stem)
    if not os.path.isdir(into):
        os.makedirs(into)
    document = pypdfium2.PdfDocument(source)
    held = []
    for number in range(first, min(last, len(document)) + 1):
        name = os.path.join(into, "page_%03d.png" % number)
        document[number - 1].render(scale=scale).to_pil().save(name)
        held.append(name)
    return held


def main():
    stem = sys.argv[1]
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    last = int(sys.argv[3]) if len(sys.argv) > 3 else first
    # 3 puts a 12pt body around 50px tall, which is where a stacked diacritic stops guessing.
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
    for name in rendered(stem, first, last, scale):
        print(name)


if __name__ == "__main__":
    raise SystemExit(main())
