#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Build a pure nɬeʔkepmxcín corpus from a paper that prints the same story twice, and verify it against
# itself, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/salish_corpus.py
#
# Hall and Phillips print Bev Phillips's story in three versions, and two of them are the language. Section
# 2 gives it monolingual with a timestamp on every sentence. Section 4 gives the same sentences again as
# the top line of each interlinear block. Neither was derived from the other by us, so they are two
# witnesses to one text and they have to agree.
#
# They need one repair first. The extraction puts a space after every combining mark, so q̓ʷúmqns arrives
# as "q̓ ʷúmqns" and ƛ̓uʔ as "ƛ̓ uʔ". Deleting a space that follows a combining mark fixes it, and that rule
# is mechanical but not safe on its own: a word genuinely ending in a glottalized consonant would be
# welded to the word after it and nothing in the character stream would say so.
#
# Which is what the second witness is for. The repair is applied to both sections independently and the
# results are compared sentence by sentence. Agreement means two renderings of the same sentence, taken
# from different parts of the paper, came out identical after the same repair, and a welding error would
# have to occur identically in both to survive that. Disagreement is printed in full and copied by hand.
#
# Nothing here is generated, translated, or reconstructed. It is one speaker's story, in her language,
# with the spaces the PDF added taken back out.

import io
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

CLOCK = re.compile(r"^\s*\[\s*(\d{1,2}):(\d{2})\s*\]\s*$")
NUMBERED = re.compile(r"^\s*\((\d+)\)\s*(.*)$")
UPPER_TAG = re.compile(r"[A-Z][A-Z0-9./]{1,}")
QUOTED = re.compile(r"[‘'\"“]")

# Words that mark a line as English prose. Deliberately narrow: we, te, e, ne and tu are words of
# nɬeʔkepmxcín, so anything that could collide with the language is left out of this list.
ENGLISH = re.compile(r"\b(?:the|to|is|of|for|and|there|this|that|with|are|was|from|which|"
                     r"convention|orthography|standardized)\b", re.IGNORECASE)

# What tells a segmentation line from the surface line above it
SEGMENTED = ("=", "[", "]", "<", ">", "~")


# The marks the extraction separated from the consonant they belong to: glottalization, ejection,
# retraction. Stress accents are deliberately absent from this list. A word can end in a stressed
# vowel, ʔé is a word of its own, and a rule that closed the space after it would weld ʔé sméƛ̓s into
# one word everywhere. Both witnesses would weld identically, so the cross-check could not see it.
JOINING = "̴̡̢̧̨̰̱̮̹̓̕"


def repair(line):
    """Take out the space the extraction inserted between a consonant's mark and the rest of it."""
    out = []
    for symbol in line:
        if (symbol == " ") and out and (out[-1] in JOINING):
            continue
        out.append(symbol)
    return "".join(out)


def tidy(line):
    """One line with its runs of blanks closed up and its edges trimmed."""
    return " ".join(repair(line).split())


def salish_enough(line):
    """A line carrying the marked consonants and vowels the language is written with."""
    return any(symbol in line for symbol in "ʔʕɬƛəx̣χʷ̓")


def section_two(lines):
    """The monolingual section, as each timestamp and the sentence printed under it."""
    held = []
    refused = []
    building = []
    inside = False
    when = None
    for line in lines:
        trimmed = line.strip()
        # Matched without the accented vowel, since the extraction may hold it decomposed
        if re.match(r"^2\s+n\S*kepmxc", trimmed):
            inside = True
            continue
        if re.match(r"^3\s+English", trimmed):
            inside = False
            continue
        if not inside:
            continue
        ticked = CLOCK.match(line)
        if ticked:
            # A sentence that wrapped across PDF lines is one sentence. Emitting each line
            # separately made the later line overwrite the earlier one downstream, which silently
            # dropped the front of every long sentence.
            if building and (when is not None):
                held.append((when, tidy(" ".join(building))))
            building = []
            when = "%s:%s" % (ticked.group(1), ticked.group(2))
            continue
        if (when is not None) and salish_enough(trimmed) and not trimmed.startswith("====="):
            # A footnote runs across the bottom of these pages and carries ɬ in the language's own
            # name, so it passes the character test. Two English function words rule it out, and two
            # are wanted because we, te and e are words of the language. Every rejection is counted
            # and reported, so nothing leaves without being named.
            if len(set(one.lower() for one in ENGLISH.findall(trimmed))) >= 2:
                refused.append(trimmed)
                continue
            building.append(trimmed)
    if building and (when is not None):
        held.append((when, tidy(" ".join(building))))
    return held, refused


def section_four(lines):
    """The interlinear section, as each numbered example's surface line, joined where it wrapped."""
    held = []
    inside = False
    when = None
    building = []
    taking = False

    def close():
        if building and (when is not None):
            held.append((when, tidy(" ".join(building))))
        building.clear()

    for line in lines:
        trimmed = line.strip()
        if re.match(r"^4\s+Interlinear", trimmed):
            inside = True
            continue
        if not inside:
            continue
        ticked = CLOCK.match(line)
        if ticked:
            close()
            when = "%s:%s" % (ticked.group(1), ticked.group(2))
            taking = False
            continue
        numbered = NUMBERED.match(line)
        if numbered:
            close()
            building.append(numbered.group(2))
            taking = True
            continue
        if not taking:
            continue
        if (not trimmed) or trimmed.startswith("====="):
            continue
        # The translation is the last line of an example and closes it
        if QUOTED.search(trimmed):
            taking = False
            continue
        # A long sentence wraps, so its later pieces sit below the segmentation and gloss lines of
        # the piece before. Those two are stepped over instead of ending the example.
        if any(mark in trimmed for mark in SEGMENTED) or UPPER_TAG.search(trimmed):
            continue
        if salish_enough(trimmed):
            building.append(trimmed)
    close()
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    source = os.path.join(PAPERS, "HallPhillipsICSNL60.txt")
    if not os.path.isfile(source):
        out.write("  no %s\n" % source)
        out.flush()
        return 1

    with open(source, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()

    plain, refused = section_two(lines)
    glossed = section_four(lines)
    out.write("  section 2 gave %d sentences, section 4 gave %d\n" % (len(plain), len(glossed)))
    if refused:
        out.write("  %d line(s) in section 2 refused as English footnote text:\n" % len(refused))
        for line in refused:
            out.write("    %s\n" % line[:96])

    by_clock = {}
    for when, text in plain:
        by_clock.setdefault(when, ["", ""])[0] = text
    for when, text in glossed:
        by_clock.setdefault(when, ["", ""])[1] = text

    agreed = []
    differed = []
    only_one = 0
    for when in sorted(by_clock, key=lambda key: (int(key.split(":")[0]), int(key.split(":")[1]))):
        first, second = by_clock[when]
        if not (first and second):
            only_one += 1
            continue
        if first == second:
            agreed.append((when, first))
        else:
            differed.append((when, first, second))

    both = len(agreed) + len(differed)
    out.write("  %d sentences appear in both sections, %d in only one\n" % (both, only_one))
    if both:
        out.write("  %d agree exactly after the repair, %.1f%%\n"
                  % (len(agreed), 100.0 * len(agreed) / both))

    if differed:
        out.write("\n  where the two witnesses disagree, for hand copying\n")
        for when, first, second in differed[:14]:
            out.write("  [%s]\n    section 2: %s\n    section 4: %s\n" % (when, first, second))
        if len(differed) > 14:
            out.write("  and %d more\n" % (len(differed) - 14))

    # Everything is written. A sentence the two printings disagree on is a real sentence with a
    # discrepancy to record, and a sentence that appears in only one of them is a real sentence with
    # no second copy. Dropping either loses text from a language that has very little of it left, so
    # the status is a column and never a filter.
    target = os.path.join(CORPORA, "salish_nlekepmxcin.txt")
    written = 0
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("time\tstatus\ttext\talternate\n")
        for when in sorted(by_clock,
                           key=lambda key: (int(key.split(":")[0]), int(key.split(":")[1]))):
            first, second = by_clock[when]
            if first and second and (first == second):
                handle.write("%s\tagreed\t%s\t\n" % (when, first))
            elif first and second:
                handle.write("%s\tdiffers\t%s\t%s\n" % (when, first, second))
            elif first:
                handle.write("%s\tsection2only\t%s\t\n" % (when, first))
            else:
                handle.write("%s\tsection4only\t%s\t\n" % (when, second))
            written += 1
    out.write("\n  %d sentences written to %s, none discarded\n" % (written, target))
    out.write("  %d agreed, %d differ between the printings, %d in one section only\n"
              % (len(agreed), len(differed), only_one))

    out.write("\n  the first six verified sentences, to be read against the paper\n")
    for when, text in agreed[:6]:
        out.write("  [%s] %s\n" % (when, text))

    everything = [(when, one) for when, pair in by_clock.items() for one in pair if one]
    words = sum(len(text.split()) for when, text in everything)
    letters = sum(1 for when, text in everything for symbol in text if symbol.isalpha())
    left = sum(1 for when, text in everything for index, symbol in enumerate(text)
               if (symbol == " ") and index and (unicodedata.combining(text[index - 1]) != 0))
    out.write("  %d words, %d letters, %d spaces still following a combining mark\n"
              % (words, letters, left))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
