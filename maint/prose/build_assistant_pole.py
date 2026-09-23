#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Build the assistant pole from every session transcript on this machine, split by whether the
# writing was under suppression.
#
#   Usage:  python maint/prose/build_assistant_pole.py [--out-dir DIR] [--limit N]
#
# WHY THIS EXISTS
#
# dependence_decay.py cannot separate the poles because the assistant corpus is 39,516 words and the
# human band at that length is 0.129 wide, wider than any separation on offer. Every comparison has
# to be made at the shorter corpus's length, so the assistant side is the binding constraint and more
# assistant text is worth more than a better statistic.
#
# THE SPLIT THIS ADDS, WHICH IS NOT JUST MORE WORDS
#
# session_prose.py names its own confound and calls it a large one: the transcript it drew from was
# written while the assistant was enforcing a banned phrase list across the tree and avoiding those
# phrases in its own messages. A rate measured there is a rate under suppression. It is a floor on
# the register, not an estimate of it.
#
# Most transcripts on this machine were not written under that constraint. docs_check.py runs in
# anchor_sift, BTC and the MMgr tree; it does not run in ProtoCore, embedded_types, idemIP,
# repo_tools or the rest. Prose written in those sessions is the unconstrained register, and it is
# the pole the original could not be.
#
# So the two corpora are kept apart and never merged. Merging them would average a suppressed
# register with an unsuppressed one and report a number belonging to neither, which is the same
# error as pooling arms measured under different conditions.
#
# THE EXTRACTION IS IMPORTED AND NEVER COPIED
#
# session_prose.py owns what counts as assistant prose: text blocks of assistant messages only, no
# user turns, no tool calls, no tool results, no thinking blocks, with code, inline spans and tables
# removed. A second copy of that rule would drift from the first and the two poles would stop being
# comparable. It is imported.

import io
import os
import sys

ANCHOR_SIFT = r"C:\Users\Douglas\Desktop\git_project\anchor_sift\maint\prose"
sys.path.insert(0, ANCHOR_SIFT)

import session_prose  # noqa: E402

PROJECTS = os.path.join(os.path.expanduser("~"), ".claude", "projects")

# The trees where docs_check.py runs, so prose written about them was written under the ban list.
# Matched against the project directory name, which encodes the working directory path.
SUPPRESSED = ("anchor-sift", "BTC", "mmgrwork", "making-money")

# A message shorter than this is an acknowledgement and not prose. session_prose uses the same bar.
FLOOR = 40


def suppressed(project):
    return any(mark.lower() in project.lower() for mark in SUPPRESSED)


def main(argv):
    out_dir = os.path.join("build", "corpora")
    if "--out-dir" in argv:
        out_dir = argv[argv.index("--out-dir") + 1]
    limit = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 0

    # Scope. Without it this walks every session on the machine, which reaches projects that have
    # nothing to do with this work. That is an aggregation of the operator's whole history and it is
    # theirs to authorise, not this tool's to assume: default to the trees this research owns and
    # take anything wider as an explicit argument.
    only = None
    if "--projects" in argv:
        only = tuple(m for m in argv[argv.index("--projects") + 1].split(",") if m)
    elif "--everything" not in argv:
        only = SUPPRESSED

    if not os.path.isdir(PROJECTS):
        print("  no transcripts at %s" % PROJECTS)
        return 2

    transcripts = []
    for project in sorted(os.listdir(PROJECTS)):
        full = os.path.join(PROJECTS, project)
        if not os.path.isdir(full):
            continue
        if only and not any(mark.lower() in project.lower() for mark in only):
            continue
        for name in sorted(os.listdir(full)):
            if name.endswith(".jsonl"):
                transcripts.append((project, os.path.join(full, name)))

    if limit:
        transcripts = transcripts[:limit]

    print("  %d transcripts across %d projects"
          % (len(transcripts), len(set(p for p, _ in transcripts))))

    tally = {}
    held = {True: [], False: []}

    for index, (project, path) in enumerate(transcripts, 1):
        try:
            blocks = session_prose.assistant_text(path)
        except Exception as error:  # noqa: BLE001 - one bad transcript must not stop the sweep
            print("    skipped %s: %s" % (os.path.basename(path), error))
            continue

        cleaned = [session_prose.prose_of(one) for one in blocks]
        cleaned = [one for one in cleaned if len(one) > FLOOR]
        if not cleaned:
            continue

        words = sum(len(one.split()) for one in cleaned)
        mark = suppressed(project)
        held[mark] += cleaned

        row = tally.setdefault(project, [0, 0, mark])
        row[0] += len(cleaned)
        row[1] += words

        if index % 50 == 0:
            print("    %d/%d read" % (index, len(transcripts)))

    os.makedirs(out_dir, exist_ok=True)

    print("")
    print("  %-58s %8s %10s  %s" % ("project", "blocks", "words", "written under"))
    for project in sorted(tally, key=lambda p: -tally[p][1]):
        blocks, words, mark = tally[project]
        print("  %-58s %8d %10d  %s"
              % (project[-58:], blocks, words, "the ban list" if mark else "no constraint"))

    print("")
    for mark, name in ((False, "assistant_unsuppressed.txt"), (True, "assistant_suppressed.txt")):
        target = os.path.join(out_dir, name)
        words = sum(len(one.split()) for one in held[mark])
        with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
            for one in held[mark]:
                handle.write(one)
                handle.write("\n")
        print("  %-44s %9d words, %d blocks" % (target, words, len(held[mark])))

    total = sum(len(one.split()) for one in held[True] + held[False])
    print("")
    print("  %d words of assistant prose against the 39,516 the decay test was bounded by" % total)
    print("")
    print("  The two files are NOT interchangeable and must not be concatenated. One was written")
    print("  while the phrases being counted were under active suppression and the other was not.")
    print("  Quote which pole a number came from.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
