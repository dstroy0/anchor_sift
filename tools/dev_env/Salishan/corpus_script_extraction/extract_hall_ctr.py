#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the nɬeʔkepmxcín transitive forms Hall, Luntzlara, Mellesmoen and Reid cite in ICSNL 61.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_hall_ctr.py
#
# Every form in this paper is printed twice and only one of the two was ever said. The paper sets a
# surface form in square brackets and the underlying form it proposes for it in slashes, side by
# side, all the way through: [wéc̓entis] beside /wéc̓e-n-t-ey-es/, [kíc.ne] beside /kíc-n-t-∅-ene/.
#
# THE DELIMITER IS THE EVIDENCE
#
# That makes the reader's job the paper's own notation. A run inside square brackets is a word;
# a run inside slashes is the authors' analysis of it and holds morpheme boundaries, a null
# morpheme sign and an occasional subscript. Only the bracketed forms reach the pure stream, which
# is the same rule that holds Kim's underlying forms and Wolfe's reconstructions out of theirs.
#
# A star marks a form the analysis predicts and the language does not have. The paper writes it two
# ways, *[kícetxʷ] and [*kícexʷ], so both are tested for.
#
# WHAT THE DERIVATION TABLES HOLD
#
# Examples (24) and (29) to (31) are ordered-rule derivations, and every line between the underlying
# form and the surface form is a stage: kícntene, kícntne, kícnne, kícne. Those carry no delimiter at
# all, because the paper sets them in a column instead. This reader does not try to find them. They
# go out unclassified, which for a form nobody said is the safe direction to be wrong in.
#
# The same is true of the surface forms the prose prints bare, kicnəxʷ and wíktxʷ among them. The
# hand extraction has all of them. This reader misses them, because the alternative is guessing at a
# bare token, and a wrong guess puts a form in the corpus that nobody said.
#
# NOT THIS LANGUAGE
#
# Section 3.1.1 argues from two other languages. ʔayʔaǰuθəm has -θi and St'át'imcets has -ci, and the
# paper's point is that neither can hold an underlying /s/. Newman's proto-Salish *c and *ci are in
# there too. The who column carries all of them, so none reaches a nɬeʔkepmxcín corpus.

import io
import os
import re
import sys

from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "Hall-et-al_-ICSNL_61-1.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "unstated_CtrlAltDeleteTheControlDirectiveAndAssociatedTDeletionInNlekepmxcin"
    "_HallLuntzlaraMellesmoenReid_Salish_nlekepmxcin_2026_mixed.txt")

# Kept in step with HALL_CTR in hand_extraction/papers.py. The dot below is this paper's rounded
# uvular, in x̣íɬ and sóx̣ʷest. The length mark is deliberately absent: all five in the paper are a
# typo for a colon, in English, and carrying it would make verbsː a word of the language.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "̣" + "áéíóúè" + "́" + "ǰθ"

PAGE = re.compile(r"^===== page (\d+) =====$")

TARGET_LANGUAGE = "nɬeʔkepmxcín"

# A surface form. The paper sets every one of them in square brackets and nothing else in the paper
# is bracketed except a gloss label inside one, which carries no character of the language.
SURFACE = re.compile(r"\[([^\[\]\s]+)\]")

# An underlying form. Slashes with no space between them, which is what keeps this off the lone
# slash in {nxʷ1, exʷ2} / …{n, n̓, h, ʔ} and off and/or.
UNDERLYING = re.compile(r"/([^/\s]+)/")

# A form the analysis predicts and the language does not have. The paper stars outside the brackets
# in *[kícetxʷ] and inside them in [*kícexʷ], so the test is for a star in either place.
STAR = "*"

# The one sentence in the paper somebody said. Everything else in it is cited from a dictionary.
# kʷaɬtèzetkʷ introduces herself in the
# acknowledgement footnote, and it is anchored on the paper's own words because it carries no
# delimiter of its own.
INTRODUCTION = re.compile(r"She introduces herself thus:\s*(.+?)\s*‘")

# The speaker of the two examples taken from another paper in this table, which is Bev Phillips
# reading her own story. The citation is what names her.
FROM_PHILLIPS = "Hall and Phillips"

# What is not nɬeʔkepmxcín. Section 3.1.1 argues from these and the who column has to carry them, or
# a Comox suffix arrives in a nɬeʔkepmxcín corpus by falling through a branch.
ELSEWHERE = {
    "θ": "Comox",
    "-θi": "Comox",
    "ʔayʔaǰuθəm": "Comox",
}

# The syllable boundary, which is notation and not a letter. The paper prints [kícne] in one place
# and [kíc.ne] in another for the one word, so leaving the dots in would put two spellings of it in
# the corpus. They come out on the way to the pure file and stay in the record.
SYLLABLE = "."


def kind_of(form):
    """What a bracketed form is: a word of the language, or one the analysis rules out."""
    return "impossible" if (STAR in form) else "cited form"


def spoken_form(form):
    """A surface form as a word: its brackets off and the paper's syllable boundaries out."""
    return form.strip("[]").replace(SYLLABLE, "")


def leftover(text, taken):
    """What is left of a line once the spans already read out of it are cut, by position."""
    kept = []
    at = 0
    for start, end in sorted(taken):
        if start > at:
            kept.append(text[at:start])
        at = max(at, end)
    kept.append(text[at:])
    return " ".join(" ".join(kept).split())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [one.rstrip("\n") for one in handle]

    rows = []
    page = 0

    for line in lines:
        trimmed = " ".join(line.split())
        found = PAGE.match(trimmed)
        if found:
            page = int(found.group(1))
            continue
        if not trimmed:
            continue

        where = "page %d" % page
        who = "Bev Phillips" if (FROM_PHILLIPS in trimmed) else TARGET_LANGUAGE
        taken = []

        speaking = INTRODUCTION.search(trimmed)
        if speaking:
            rows.append((where, "kʷaɬtèzetkʷ", "running speech", speaking.group(1)))
            taken.append(speaking.span(1))

        # The delimiters stay on the form in the record, because the record holds what the page
        # printed and the page printed the brackets. They come off on the way to the pure file,
        # where the entry is the word. The hand extraction records them the same way.
        for found in SURFACE.finditer(trimmed):
            inner = found.group(1)
            rows.append((where, ELSEWHERE.get(inner, who), kind_of(inner), found.group(0)))
            taken.append(found.span(0))

        for found in UNDERLYING.finditer(trimmed):
            inner = found.group(1)
            rows.append((where, ELSEWHERE.get(inner, who), "underlying", found.group(0)))
            taken.append(found.span(0))

        # Whatever the two patterns did not reach. On this paper that is the prose, the glosses, the
        # derivation columns and the bare surface forms, and none of it is sorted here.
        #
        # The spans come out by position. Cutting them by string match instead lost every glottal
        # stop on page 13: the page carries /ʔ/, which yields the one-character form ʔ, and taking
        # that out of the page by name took it out of {n, n̓, h, ʔ}]morpheme-t-___ as well.
        rest = leftover(trimmed, taken)
        if rest:
            rows.append((where, "", UNCLASSIFIED, rest))

    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for at, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % at, "", UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Ctrl-Alt-Delete: The Control Directive and Associated /t/ Deletion in\n")
        handle.write("# nɬeʔkepmxcín. Brent Hall, Noah Luntzlara, Gloria Mellesmoen and Danica\n")
        handle.write("# Reid. Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages 61, Vancouver, BC: UBCWPL, 2026.\n")
        handle.write("#\n")
        handle.write("# Every example is printed twice: a surface form in square brackets and the\n")
        handle.write("# underlying form the authors propose for it in slashes. Only the bracketed\n")
        handle.write("# form was said, and only it reaches the pure file.\n")
        handle.write("#\n")
        handle.write("# The forms are Thompson and Thompson's, out of their 1992 grammar and 1996\n")
        handle.write("# dictionary, except two from Hall and Phillips 2025, which is Bev Phillips\n")
        handle.write("# reading her own story, and the sentence kʷaɬtèzetkʷ introduces herself with\n")
        handle.write("# in the acknowledgement footnote.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, who, kind, text) in enumerate(rows, 1):
            spoken = (kind in ("cited form", "running speech")) and (who != "")
            spoken = spoken and (ELSEWHERE.get(text, TARGET_LANGUAGE) == TARGET_LANGUAGE)
            layer = SPOKEN if spoken else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, who or spot, kind, crossings, content))

    # The words alone. The underlying forms are held out by their kind, the starred ones by theirs,
    # and ʔayʔaǰuθəm and its suffix by the who column.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for spot, who, kind, text in rows:
            if kind not in ("cited form", "running speech"):
                continue
            if who not in (TARGET_LANGUAGE, "Bev Phillips", "kʷaɬtèzetkʷ"):
                continue
            for span, run in tagged_spans(spoken_form(text), MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = " ".join(run.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, who, kind, text in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Ctrl-Alt-Delete", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d nɬeʔkepmxcín words written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    kinds = {}
    for spot, who, kind, text in rows:
        kinds[kind] = kinds.get(kind, 0) + 1
    out.write("\n  by kind: %s\n" % ", ".join("%s %d" % (one, kinds[one]) for one in sorted(kinds)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
