#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch published Opus 5 prose, for the positive pole of claudese_distance.
#
#   Usage:  python maint/data/fetch/fetch_claude_prose.py [--words N]
#
# WHY THIS EXISTS, AND HOW MUCH IT ACTUALLY GETS
#
# claudese_distance.py needs two poles. The human pole is 154 research papers, 759,815 words after
# gating. The assistant pole was one page written by hand, 996 gated words, and a pole that small
# cannot carry a distribution: its own halves sat 0.3647 apart where the human pole's sat 0.0834.
#
# This does not fix that, and the number is worth stating plainly. A search of every Opus 5 dataset
# published finds ten, and most are image captions, token ledgers, or a single example wrapped in
# metadata. Two carry usable assistant prose and one of those answers 401. What lands is about
# fifteen thousand words, not the million this file was first written to fetch.
# docs-check: quoting
#
# The reason is visible in the schema rather than the prose. The largest of them is four megabytes
# docs-check: end quoting
# and 84 percent of that is system prompts: 3,340,667 characters of system against 124,727 of
# assistant. The coding set is mostly code, which is stripped. A public corpus of this model writing
# English at length does not appear to exist yet, and a pole of this size resolves an extreme and
# nothing finer. Say so wherever a number from it is quoted.
#
# AND THE FIFTEEN THOUSAND IS RAW. THE GATED COUNT IS SMALLER AND UNEVEN
#
# Measured 2026-09-09 on a 60,000 word fetch, per upload, before and after words_of:
#
#   Ironwood-LLM-Team/Claude-Opus-5-Coding            4,477 raw    4,079 gated    91 percent
#   beyoru/...-xhigh-workload-agent-preview          10,668 raw      854 gated     8 percent
#
# The second one is not prose. Its gate leaves tool, call, function, get, parameter,
# parameter, which is an agent trace with the tool calls written out, and the English gate throws
# away the rest because the rest is not English writing. It is the larger upload by raw count and
# the smaller by nearly five to one once the gate has run.
#
# So the merged pole is mostly one upload. The label on all three says Opus 5 and they are not the
# same kind of text, which is a defect in the pole and not in the gate. maint/prose/
# oracle_agreement.py is the check for it, and at this size it refuses to place them at all.
#
# WHAT IS FETCHED, AND WHAT THAT IS NOT
#
# Three published datasets of Claude output, all ungated, all plain JSON or JSONL. Only the
# assistant turns are kept: the human turns in them were written by people and belong to the other
# pole. Fenced code blocks come out, because the thing being measured is prose and a file full of
# Python would otherwise match on its Python.
#
# These are published as Claude Opus 5 output. That is the model doing this work, so the pole and
# the thing under test are the same version, which the earlier Claude 3 corpus could not offer.
# The era measurement in prose_era.py showed vocabulary moves enough across time to date a text,
# and a version gap is the same kind of gap. Matching the version removes it.
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
import sys
import urllib.parse
import urllib.request

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(CORPORA, "claude_prose.txt")

# Each upload also lands on its own, because the agreement check compares them against each other
# and a merged file cannot be compared with itself. The merged one stays: it is what the pole is
# built from once the label has been checked.
APART = os.path.join(CORPORA, "claude_prose_by_source")

BLOB = "https://huggingface.co/datasets/%s/resolve/main/%s"

# Dataset, file, and the shape its records take. Ordered so the largest lands first.
#
# Opus 5 only. An earlier version of this list fetched Claude 3 Opus and Claude 3.5 Sonnet, both
# published in 2024, and that corpus was wrong for the question and has been deleted. What it
# measured is worth keeping in mind: the eight phrases this repository had confirmed as the
# assistant signature fired 26.4 times per hundred thousand words here and 1.3 times in that older
# corpus, so they were never the register, they were this tree's own idiolect.
#
# THE LABEL IS A CLAIM AND NOT EVIDENCE
#
# Nobody can verify from the outside that a community upload holds what it claims to. Three
# uploaders are used instead of one for that reason: if three independently published corpora that
# all claim Opus 5 agree with each other more closely than any agrees with a corpus from another
# model, the label is carrying information. If they disagree, one or more of them is mislabeled
# and the pole is not usable. maint/prose/oracle_agreement.py runs that check.
#
# The no_reasoning variants are taken where a dataset offers both. A reasoning trace is a different
# register from an answer, and mixing them would build a pole out of two things.
SOURCES = (
    ("beyoru/Claude-opus-5-xhigh-workload-agent-preview",
     "full_train_no_reasoning.jsonl", "sharegpt-lines"),
    ("beyoru/Claude-Opus-5-safety",
     "full_train_no_reasoning.jsonl", "sharegpt-lines"),
    ("Ironwood-LLM-Team/Claude-Opus-5-Coding",
     "Claude Opus Training.jsonl", "sharegpt-lines"),
)

# Which speaker in a ShareGPT record is the assistant. The human turns are somebody else's prose.
ASSISTANT = ("gpt", "assistant", "claude", "model")

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
    """One assistant turn with its code removed, so what is left is what it wrote in English."""
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
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
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
        # One file per upload, named for the uploader, so the agreement check can ask whether
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
    out.write("    %d words over %d turns, from %d files\n"
              % (counted, len(held), len(used)))
    for dataset, name, turns, words in used:
        out.write("    %-56s %6d turns %8d words\n" % (dataset[:56], turns, words))
    out.write("\n  Published as Claude Opus 5. The label is a claim, not evidence.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
