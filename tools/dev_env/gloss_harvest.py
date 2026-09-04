#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Pull the glossed examples out of an extracted proceedings volume and measure what the English
# translation throws away, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/gloss_harvest.py icsnl2016
#
# Robertson and colleagues end their paper on Lower Chehalis asking for work that makes the literal
# content of Salish words overt, and give the example themselves: the word for people analyzes as
# many=mouths=in.a.longhouse, which no English translation of it carries. They treat that as something a
# lexicographer would recover by hand from an elder's explanation.
#
# It does not have to be recovered by hand, because the interlinear format already holds both halves. An
# example is printed in three lines: the form with its morpheme boundaries, a morpheme by morpheme gloss,
# and a running translation. The second line is what the word composes. The third is what English keeps.
# The difference between them is the metaphor, and it is a subtraction and not an interpretation.
#
# That difference is countable. A word built from five morphemes and translated by one English word has
# four morphemes of scene that the translation discarded, and the ratio of morphemes composed to words
# retained says how much of the picture a reader of the English never sees. It is a lower bound on the
# metaphor and not a measure of it, since a translation can also keep the scene and just be long.
#
# The form lines came out of the PDF with the glottalized and retracted consonants dropped, which would
# ruin any measurement of the phonology. Gloss lines and translation lines are close to plain ASCII and
# came through, and those are the two lines this needs.
#
# What this cannot see: glossing conventions belong to authors and not to the field. Van Eijk marks telic
# reduplication with the equals sign in this same volume where Robertson marks lexical suffixes with it,
# so a count of one symbol across papers counts two different things. Morphemes are therefore counted
# from every boundary mark together, and the per-paper question is left to a reader who opens the paper.

import io
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")

# What a morpheme by morpheme line uses to name a grammatical category
TAGS = re.compile(r"\b(?:[1-3](?:SG|PL|DU)|SG|PL|DU|NOM|ACC|ERG|ABS|GEN|DAT|LOC|ART|DEM|DET|"
                  r"POSS|PASS|CAUS|APPL|TR|INTR|REFL|RECIP|IMPF|PERF|PROG|ASP|TNS|PAST|FUT|"
                  r"IRR|SUBJ|IND|CONJ|NEG|Q|WH|REP|EVID|HYP|INCH|RES|REL|AUG|DIM|TEL|FACT|"
                  r"DISC|COMP|CONCL|CONF|ADH|REIN|KAT|CLF|PL\.|MID|CTR|NCTR|LEX)\b")

# What separates one morpheme from the next, across the conventions in use
BREAKS = re.compile(r"[-=ʬ¬‧.<>{}\[\]‹›]|ˈ")

OPENERS = "‘“\"'"
CLOSERS = "’”\"'"


def is_gloss(line):
    """A line that names grammatical categories is the morpheme by morpheme line.

    An abbreviation key names more categories than any real example does, and it quotes a gloss
    beside each one, so it matches everything an example matches and matches it harder. A key
    chains its definitions with semicolons and colons, which is what rules it out here.
    """
    if (line.count(";") >= 2) or (line.count(": ") >= 2):
        return False
    return len(TAGS.findall(line)) >= 2


def is_translation(line):
    """A line wrapped in quotation marks is the running translation.

    The closing mark is taken as the last one on the line. An English contraction inside a
    translation is written with the same character that closes the quote, and stopping at the
    first one turns 'I didn't sleep' into 'I didn'.
    """
    trimmed = line.strip()
    opened = -1
    for index, symbol in enumerate(trimmed):
        if symbol in OPENERS:
            opened = index
            break
    if opened < 0:
        return None
    closed = -1
    for index in range(len(trimmed) - 1, opened, -1):
        if trimmed[index] in CLOSERS:
            closed = index
            break
    if closed <= (opened + 3):
        return None
    return trimmed[opened + 1:closed].strip()


def morphemes(line):
    """How many pieces the gloss line breaks into, counting every boundary convention."""
    total = 0
    for chunk in line.split():
        if not chunk.strip():
            continue
        pieces = [one for one in BREAKS.split(chunk) if one.strip()]
        total += max(1, len(pieces))
    return total


def harvest(pages):
    """Every glossed example, as the gloss line, the translation, and where it was found."""
    found = []
    for number, text in pages:
        lines = text.splitlines()
        for index, line in enumerate(lines):
            if not is_gloss(line):
                continue
            # The translation sits within the next few lines, past any continued gloss
            english = None
            for ahead in range(index + 1, min(index + 5, len(lines))):
                english = is_translation(lines[ahead])
                if english:
                    break
            if not english:
                continue
            found.append((number, line.strip(), english))
    return found


def main():
    if len(sys.argv) < 2:
        print("usage: gloss_harvest.py <volume name>")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    volume = sys.argv[1]
    source = os.path.join(PAPERS, "%s.txt" % volume)
    if not os.path.isfile(source):
        out.write("  no %s, run icsnl_probe.py first\n" % source)
        out.flush()
        return 1

    with open(source, encoding="utf-8", errors="replace") as handle:
        blob = handle.read()
    parts = re.split(r"\n===== page (\d+) =====\n", blob)
    pages = []
    walk = 1
    while walk + 1 <= len(parts) - 1:
        pages.append((int(parts[walk]), parts[walk + 1]))
        walk += 2

    found = harvest(pages)
    out.write("  %d pages read, %d glossed examples found\n" % (len(pages), len(found)))
    if not found:
        out.flush()
        return 0

    target = os.path.join(PAPERS, "%s_glosses.tsv" % volume)
    ratios = []
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("page\tmorphemes\tenglish_words\tratio\tgloss\ttranslation\n")
        for number, gloss, english in found:
            pieces = morphemes(gloss)
            words = len([one for one in english.split() if one.strip()])
            if words < 1:
                continue
            ratio = pieces / float(words)
            ratios.append(ratio)
            handle.write("%d\t%d\t%d\t%.3f\t%s\t%s\n"
                         % (number, pieces, words, ratio, gloss, english))

    out.write("  written to %s\n" % target)
    out.write("\n  morphemes composed against English words kept\n")
    out.write("  median %.3f, mean %.3f, over %d examples\n"
              % (statistics.median(ratios), statistics.fmean(ratios), len(ratios)))
    out.write("  a ratio above one means the morphology carries more pieces than the\n")
    out.write("  translation keeps words, which is where the scene is being discarded\n")

    steep = sorted(zip(ratios, found), key=lambda pair: -pair[0])[:8]
    out.write("\n  the examples that lose the most, by that ratio\n")
    for ratio, (number, gloss, english) in steep:
        out.write("  %-6.2f page %-4d %s\n" % (ratio, number, english[:66]))
        out.write("         %s\n" % gloss[:100])

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
