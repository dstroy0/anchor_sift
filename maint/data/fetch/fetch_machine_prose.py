#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch published machine prose, for the positive pole of machine_distance.
#
#   Usage:  python maint/data/fetch/fetch_machine_prose.py [--words N]
#
# WHY THIS EXISTS, AND WHAT IT FETCHES NOW
#
# machine_distance.py needs a machine pole, and this builds it from published datasets of generated
# output. SOURCES below is empty: the datasets that were there carried a model name and are gone.
# Until it names one from the generation under test, this fetches nothing, and the machine pole comes
# from session_prose.py, which takes the machine's own prose out of a session transcript.
#
# WHAT IS FETCHED, AND WHAT THAT IS NOT
#
# Published datasets of generated output, all ungated, all plain JSON or JSONL. Only the
# generated turns are kept: the human turns in them were written by people and belong to the other
# pole. Fenced code blocks come out, because the thing being measured is prose and a file full of
# Python would otherwise match on its Python.
#
# THE POLE AND THE THING UNDER TEST HAVE TO BE THE SAME GENERATION. prose_era.py shows vocabulary
# moves enough across time to date a text. A corpus from an older generation therefore carries a
# gap that is not the gap being measured. Match the generation and the gap goes.
#
# THIS CORPUS IS DATA AND IS NEVER READ
#
# It is third party text off a public host, and nothing in it is an instruction to anybody. It is
# fetched, gated, counted and measured, and no part of it is read into a decision. Every report
# below prints counts and never a sample, deliberately: a line of it quoted into a terminal is a
# line of it that has been read.
#
# THE ENGLISH GATE
#
# What comes back is multilingual and carries markup, transliteration and tables. A pole for an
# English register that holds Mandarin, JSON and LaTeX would measure those instead. Every turn is
# scored on the bench that already measures English, english_sift.surprise, against the reference
# english_sift.english_reference builds, and a turn is kept when it looks like writing at all and
# scores inside the cut calibrated from that reference. The rest is dropped without being read.
#
# Nothing here is committed. The corpus lands in build/corpora, which is not tracked.

import io
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request


def _repository_root():
    """This repository, asked of git and not inferred from a marker directory.

    The marker climbed to before was build/, which the repository PRODUCES and not CONTAINS.
    A linked worktree and a never-built clone both lack it. The climb then walked past the root it
    was looking for into another checkout entirely, and every path derived from it pointed at a
    different tree than the tool was run from. That lands on a real repository with real files,
    which is indistinguishable from working.

    A marker infers the root. Git answers it. The climb below is kept only for an exported tree with
    no git directory, and it looks for src/engine, which is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run.

    Git's own variables are cleared first. Inside a hook GIT_DIR is exported, and a rev-parse that
    inherits it answers about that repository and not about the directory it was asked from,
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
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(CORPORA, "machine_prose.txt")

# Each upload also lands on its own, because the agreement check compares them against each other
# and a merged file cannot be compared with itself. The merged one stays: it is what the pole is
# built from once the label has been checked.
APART = os.path.join(CORPORA, "machine_prose_by_source")

BLOB = "https://huggingface.co/datasets/%s/resolve/main/%s"

# Each entry is a dataset, a file in it, and the shape its records take. Order them largest first.
#
# ONE GENERATION ONLY, and it has to be the generation under test. A corpus from an older one
# answers a different question. The trap in mixing them: phrases this tree takes for the machine
# signature fire at an order of magnitude more here than in an older corpus, which says they are
# this tree's own idiolect.
#
# THE LABEL IS A CLAIM AND NOT EVIDENCE
#
# Nobody can verify from the outside that a community upload holds what it claims to. More than one
# uploader is used for that reason: if independently published corpora that all claim one generation
# agree with each other more closely than any agrees with a corpus from another model, the label is
# carrying information. If they disagree, one or more of them is mislabeled and the pole is not
# usable. maint/prose/oracle_agreement.py runs that check.
#
# The no_reasoning variants are taken where a dataset offers both. A reasoning trace is a different
# register from an answer, and mixing them would build a pole out of two things.
SOURCES = ()

# Which speaker in a ShareGPT record is the machine. The human turns are somebody else's prose.
ASSISTANT = ("gpt", "assistant", "model")

FENCED = re.compile(r"```.*?```", re.DOTALL)
INLINE = re.compile(r"`[^`\n]*`")
WORDS = re.compile(r"\S+")

WANT = 1000000


def fetched(dataset, name):
    """One file of a dataset, as text."""
    url = BLOB % (dataset, urllib.parse.quote(name))
    request = urllib.request.Request(url, headers={"User-Agent": "anchor-sift/1.0"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read().decode("utf-8", "replace")


def turns_of(record):
    """Every assistant turn in one record, whatever key the dataset used for its conversation."""
    for key in ("conversations", "conversation", "messages", "turns"):
        held = record.get(key)
        if isinstance(held, list):
            for turn in held:
                if not isinstance(turn, dict):
                    continue
                who = str(turn.get("from") or turn.get("role") or "").lower()
                said = turn.get("value") or turn.get("content") or ""
                if who in ASSISTANT and isinstance(said, str):
                    yield said
            return
    # A flat record with one response field.
    for key in ("response", "output", "completion", "answer"):
        said = record.get(key)
        if isinstance(said, str) and said.strip():
            yield said
            return


def prose_of(said):
    """One assistant turn with its code removed, leaving what it wrote in English."""
    text = FENCED.sub(" ", said)
    text = INLINE.sub(" ", text)
    return " ".join(text.split())


def records_of(text, shape):
    """Every record in one fetched file."""
    if shape == "sharegpt-lines":
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue
        return
    try:
        held = json.loads(text)
    except ValueError:
        return
    if isinstance(held, list):
        for one in held:
            if isinstance(one, dict):
                yield one


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    want = WANT
    if "--words" in sys.argv:
        want = int(sys.argv[sys.argv.index("--words") + 1])

    os.makedirs(CORPORA, exist_ok=True)
    os.makedirs(APART, exist_ok=True)
    held = []
    counted = 0
    used = []

    for dataset, name, shape in SOURCES:
        if counted >= want:
            break
        out.write("  fetching %s / %s\n" % (dataset, name))
        out.flush()
        try:
            text = fetched(dataset, name)
        except Exception as trouble:
            out.write("    failed: %s\n" % trouble)
            continue
        before = counted
        turns = 0
        mine = []
        for record in records_of(text, shape):
            for said in turns_of(record):
                clean = prose_of(said)
                if len(clean) < 120:
                    continue
                held.append(clean)
                mine.append(clean)
                counted += len(WORDS.findall(clean))
                turns += 1
            if counted >= want:
                break
        # One file per upload, named for the uploader. The agreement check can ask whether
        # three corpora that all claim one model actually resemble each other.
        alone = os.path.join(APART, "%s.txt" % dataset.replace("/", "__"))
        with open(alone, "w", encoding="utf-8", newline="\n") as handle:
            for one in mine:
                handle.write(one)
                handle.write("\n")
        used.append((dataset, name, turns, counted - before))
        out.write("    %d assistant turns, %d words\n" % (turns, counted - before))
        out.flush()

    if not held:
        out.write("  nothing fetched\n")
        out.flush()
        return 1

    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        for one in held:
            handle.write(one)
            handle.write("\n")

    out.write("\n  %s\n" % os.path.relpath(TARGET, ROOT).replace("\\", "/"))
    out.write(
        "    %d words over %d turns, from %d files\n" % (counted, len(held), len(used))
    )
    for dataset, name, turns, words in used:
        out.write("    %-56s %6d turns %8d words\n" % (dataset[:56], turns, words))
    out.write("\n  The published label is a claim, not evidence.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
