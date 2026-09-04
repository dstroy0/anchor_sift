#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Count what a nɬeʔkepmxcín narrative marks as done on purpose and what it marks as merely happening, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/control_values.py HallPhillipsICSNL60
#
# Everything measured in this work split a word's ambiguity two ways, into which kind of word it is and
# which form of it this is. Reading Lillooet showed a third thing marked on the verb that neither column
# holds, whether the actor had control of what happened. Hall and Phillips gloss nɬeʔkepmxcín with four
# values for it, control, limited control, change of state which they name as out of control, and
# autonomous, and they gloss an inferential evidential beside it. So the axis that had no column is
# written on every verb of a story, and it can be counted instead of argued about.
#
# The story is a creation account, which makes the count worth taking. Old One makes the earth, and an
# English reading of it says he made the world on purpose. The glosses do not obviously agree: he scratches
# and piles and throws under control, and the flatland, the pitch and the rock arrive under change of
# state. If that holds across the whole text then the world here is a by-product of a being existing and
# moving, and the grammar says so on every verb, which is not a reading anyone imposed on it.
#
# The abbreviation key lists every one of these tags once, in a footnote, and counting it would put a tally
# of one against each value and call that a distribution. The earlier harvest made exactly this mistake and
# reported an abbreviation key as the richest example in a volume, so the key is found and skipped here.
#
# What this cannot see: one story by one speaker. It says what this text does. It does not say what
# nɬeʔkepmxcín does, and a second text could come out the other way.

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")

# The four values the authors give for control, and the evidential glossed beside them
CONTROL = ("CTR", "LC", "COS", "AUT")
BESIDE = ("INFER", "CAUS", "TR", "MID", "STAT", "INCH", "DVL", "AUG", "PASS", "RECP", "REFL")

# A gloss line names its categories in capitals, joined by the boundary marks the authors define
PIECE = re.compile(r"[A-Z][A-Z0-9./]*")
BOUNDARY = re.compile(r"[-=.~<>\[\]()\s]+")

# Where the authors list every tag once, which is a key and not data
KEY = re.compile(r"Glossing abbreviations are as follows", re.IGNORECASE)


CLOCK = re.compile(r"\[\s*(\d{1,2}):(\d{2})\s*\]")


def gloss_lines(text):
    """Every line naming grammatical categories, with the key left out and the clock carried along.

    The story is timestamped sentence by sentence from the recording, so each gloss can be placed
    at the moment it was spoken. That is what makes an arc through the narrative measurable instead
    of asserted from whichever end happened to be read.
    """
    lines = text.splitlines()
    skipping = False
    when = 0
    kept = []
    for line in lines:
        if KEY.search(line):
            skipping = True
        # The key runs to the end of its footnote, which the next page marker closes
        if skipping:
            if line.startswith("===== page"):
                skipping = False
            continue
        ticked = CLOCK.search(line)
        if ticked:
            when = (int(ticked.group(1)) * 60) + int(ticked.group(2))
        pieces = [one for one in BOUNDARY.split(line) if one]
        tags = [one for one in pieces if PIECE.fullmatch(one) and len(one) >= 2]
        if len(tags) >= 3:
            kept.append((line, tags, when))
    return kept


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    name = sys.argv[1] if len(sys.argv) > 1 else "HallPhillipsICSNL60"
    source = os.path.join(PAPERS, "%s.txt" % name)
    if not os.path.isfile(source):
        out.write("  no %s\n" % source)
        out.flush()
        return 1

    with open(source, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    kept = gloss_lines(text)
    counted = {}
    for line, tags, when in kept:
        for tag in tags:
            counted[tag] = counted.get(tag, 0) + 1

    out.write("  %s\n" % name)
    out.write("  %d gloss lines read, the abbreviation key skipped\n" % len(kept))

    out.write("\n  what the story marks about control\n")
    out.write("  %-10s %-9s %s\n" % ("value", "count", "what it means"))
    meaning = {"CTR": "the actor had control of it",
               "LC": "the actor had limited control",
               "COS": "change of state, which they name out of control",
               "AUT": "autonomous, it did it of itself"}
    total = sum(counted.get(tag, 0) for tag in CONTROL)
    for tag in CONTROL:
        out.write("  %-10s %-9d %s\n" % (tag, counted.get(tag, 0), meaning[tag]))
    out.write("  %-10s %-9d\n" % ("together", total))

    if counted.get("CTR"):
        loose = sum(counted.get(tag, 0) for tag in ("COS", "LC", "AUT"))
        out.write("\n  not under control against under control: %.2f to 1\n"
                  % (loose / float(counted["CTR"])))

    spoken = [when for line, tags, when in kept if when > 0]
    if spoken:
        last = max(spoken)
        bins = 6
        width = (last / float(bins)) or 1.0
        out.write("\n  control through the story, by the minute it was spoken\n")
        out.write("  %-14s %-9s %-9s %s\n" % ("from", "control", "not", "share under control"))
        for step in range(bins):
            low = step * width
            high = (step + 1) * width
            here = [tags for line, tags, when in kept
                    if (when >= low) and (when < high or (step == bins - 1 and when <= high))]
            firm = sum(one.count("CTR") for tags in here for one in tags)
            loose = sum(sum(one.count(tag) for tag in ("COS", "LC", "AUT"))
                        for tags in here for one in tags)
            both = firm + loose
            out.write("  %-14s %-9d %-9d %s\n"
                      % ("%d:%02d" % (int(low) // 60, int(low) % 60), firm, loose,
                         ("%.2f" % (firm / float(both))) if both else "none marked"))
        out.write("  the recording runs %d:%02d\n" % (last // 60, last % 60))

    out.write("\n  what is marked beside it\n")
    for tag in BESIDE:
        if counted.get(tag):
            out.write("  %-10s %d\n" % (tag, counted[tag]))

    # Reduplication and infixation are written into the segmentation line, not the gloss
    reduplicated = text.count("~")
    infixed = len(re.findall(r"<[^>]{1,6}>", text))
    out.write("\n  reduplication marks %d, infixes %d, counted from the segmentation\n"
              % (reduplicated, infixed))

    out.write("\n  the twelve commonest tags in the text\n")
    for tag, times in sorted(counted.items(), key=lambda pair: -pair[1])[:12]:
        out.write("  %-10s %d\n" % (tag, times))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
