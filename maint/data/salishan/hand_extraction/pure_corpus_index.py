#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write the README that opens the hand extractions, speaker first, from the config and the tables.
#
#   Usage:  python maint/data/salishan/hand_extraction/pure_corpus_index.py
#
# The list of who is in this corpus was kept by hand in refs.md and in the tables both, and two copies
# of a list drift. The names come from paper_config.py and the row counts from the tables. Neither
# is typed twice and refs.md points here instead of restating it.
#
# WHO GETS THE CREDIT
#
# The speaker. Every one of these languages belongs to the people who speak it and none of this work
# exists without them. The corpus everything else is measured against is their words written down.
#
# The names are read from the config and not derived from the who column. That column does several
# jobs across twenty tables, and a first version of this file guessed at it and put linguists in the
# speaker slot on eleven of them. Whose language a paper holds is a fact a person establishes by
# reading the paper, the same way its alphabet is. It is declared and not inferred. Where a paper
# cites a published dictionary and never says who spoke, the entry is empty and this prints that.

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
HERE = os.path.dirname(os.path.abspath(__file__))
ORACLES = os.path.join(ROOT, "build", "oracles")

sys.path.insert(0, os.path.join(os.path.dirname(HERE), "corpus_script_extraction"))
# Built from the repository root and not by counting parents. Counting put this at data/texbuild,
# which has never existed, and the import failed with a missing module instead of a wrong path.
sys.path.insert(0, os.path.join(ROOT, "maint", "texbuild"))

import markdown_to_latex  # noqa: E402
from paper_config import PAPERS  # noqa: E402

# The chapter is the output. theory/ is the source and docs/research points at it. A markdown page
# written beside the tables would be a second copy where the pointer belongs.
# The Salishan book is authored upstream in theory_bucket and reaches this tree as a subtree. The
# chapter is written there. What this produces is carried upstream like any other change to those
# books: a pull overwrites theory_bucket/ here, and a generated chapter left only in this tree goes
# the same way a hand edit does.
INDEX = os.path.join(ROOT, "theory_bucket", "Salishan", "chapters",
                     "chapter_Salishan_pure_corpus_README.tex")


def counted(path):
    """How many rows a table holds, not counting its header."""
    rows = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if (len(fields) < 4) or (fields[0] == "where"):
                continue
            rows += 1
    return rows


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    found = []
    for paper in PAPERS:
        path = os.path.join(ORACLES, paper.oracle)
        found.append((paper, counted(path) if os.path.isfile(path) else 0))

    # Written as markdown into memory and converted once. These lines stay readable as the page
    # they describe and the book still gets TeX.
    with io.StringIO() as handle:
        handle.write("# Whose words these are\n\n")
        handle.write("**Purpose:** Find whose language is in this corpus, and which table holds "
                     "it.\n")
        handle.write("**Scope:** every `.oracle.tsv` in the closed corpus, which reaches this "
                     "tree under `build/oracles` through "
                     "`maint/corpus/verify_private_sync.py`\n\n")
        handle.write("These languages belong to the people who speak them. None of this work "
                     "exists without them. Everything else in this research is measured against "
                     "the tables below, and the tables are their words, written down.\n\n")
        handle.write("Each entry opens with who spoke, because that is whose language it is. A "
                     "linguist wrote the paper and a person read the paper into a table, and "
                     "neither of those is whose language it is. Where a paper cites a published "
                     "dictionary and never says who spoke, the entry says so, and the linguist "
                     "does not go in the who column.\n\n")
        handle.write("Conditions the speakers set are recorded with them below and hold "
                     "wherever this corpus is used.\n\n")
        handle.write("Written by `maint/data/salishan/hand_extraction/pure_corpus_index.py` "
                     "from `maint/data/salishan/corpus_script_extraction/paper_config.py`, "
                     "the only place a speaker's name is typed. Nothing in this chapter is typed "
                     "by hand, and an edit made here is lost the next time that script runs.\n\n")

        for paper, rows in found:
            handle.write("## %s\n\n" % paper.language)
            if paper.speakers:
                for one in paper.speakers:
                    handle.write("* **%s**\n" % one)
            else:
                handle.write("* The paper names no speaker. Its forms are cited from a "
                             "published source.\n")
            handle.write("\n%s, %d rows, `%s`\n\n" % (paper.stem, rows, paper.oracle))
            if paper.note:
                handle.write("%s\n\n" % paper.note)

        handle.write("---\n\n%d tables, %d rows read by hand.\n"
                     % (len(found), sum(one[1] for one in found)))
        written = handle.getvalue()

    body = markdown_to_latex.convert(written, "Whose words these are")
    # The markdown opens with the same heading the chapter now carries, and printing both would set
    # it twice on the page.
    body = body.replace("\\section{Whose words these are}\n\n", "", 1)
    with open(INDEX, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(body)

    out.write("  %d tables indexed, %d rows\n" % (len(found), sum(one[1] for one in found)))
    named = sum(1 for paper, rows in found if paper.speakers)
    out.write("  %d name their speakers, %d cite a published source\n"
              % (named, len(found) - named))
    out.write("  written to %s\n" % os.path.relpath(INDEX, ROOT))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
