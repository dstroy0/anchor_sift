#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Feed the anchor-sift algorithm the papers and see whether it agrees with what they say they are.
#
#   Usage:  python tools/dev_env/language_check.py
#
# anchor_sift.py holds the algorithm and has nothing in it to tune. This file only decides what to
# hand it, which is the whole of the work: the same measure that says nothing about a whole paper
# says something about a block of one.
#
# Anchors are the corpora nine hand-read papers produced, one per language, plus the English those
# same readers marked. Papers are cut into blocks at the size section 3 was measured at, and each
# block is asked which anchor it is nearest. A paper's own front matter names its language and that
# statement owes nothing to bytes, so agreement is evidence and disagreement names a paper to open.
#
# Every distance is reported beside the resolution that decides whether it may be read at all.

import collections
import glob
import io
import os
import sys

# Every Salishan category on the import path, so this can use a sibling from another one.
for _category in os.scandir(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from anchor_sift import blocked, distance, entropy, reading, self_distance, squash, support
from english_sift import (MARKED_SPAN, PAGE, PAPERS, calibrated_cut, english_reference,
                          looks_like_writing, surprise)
from paper_language import attribution, named_in

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")

# Which language each hand-read corpus is, from its own paper's front matter. Keyed on the paper
# title, which is the second underscore-separated field of a record's filename. A record is named
# <spoken by>_<paper>_<who wrote it down>_Salish_<language>_<year>_<mixed>, so the first field is
# the speaker and looking a title up under it finds nothing.
BY_CORPUS = {
    "ThreeGlossedNlekepmxcinNarratives": "nɬeʔkepmxcín",
    "WhenOldOneCreatedTheEarth": "nɬeʔkepmxcín",
    "FourStoriesByWlwlmelst": "nɬeʔkepmxcín",
    "Cw7aozKati7Lati7KuNaxwit": "St'át'imcets",
    "ITsicwasSQwa7yanakAku7GraveyardValley": "St'át'imcets",
    "MaryGeorgePersonalNarratives": "Comox",
    "ABellaCoolaTale": "Nuxalk",
    "ThreeOkanaganStoriesAboutPriests": "Nsyilxcən",
    "TwelveMoreUpperNicolaOkanaganNarratives": "Nsyilxcən",
    "PokingFunInLushootseed": "Lushootseed",
    "AComparativeAnalysisOfStressInNorthernAndSouthernLushootseed": "Lushootseed",
}


def language_texts():
    """The lines of each language's known-pure corpus."""
    held = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        language = BY_CORPUS.get(os.path.basename(path).split("_")[1])
        if not language:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.strip():
                    held[language].append(line.strip())
    return held


def english_texts():
    """The translation spans the nine readers marked, English out of the same PDFs."""
    held = []
    for path in sorted(glob.glob(os.path.join(CORPORA, "*_mixed.txt"))
                       + glob.glob(os.path.join(CORPORA, "*_nomixed.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#"):
                    continue
                for mark, kind, run in MARKED_SPAN.findall(line.rstrip("\n")):
                    if (mark == "N") and ("translation" in kind) and run.strip():
                        held.append(run.strip())
    return held


def paper_lines(path, english, total, cut):
    """The lines of a paper English does not account for. The noise, which is the subject.

    One anchor screens, and it is English. No language is consulted here and nothing is adjusted
    per language: the question is only whether English explains a line, and the threshold comes
    from the pure corpus, which is known in advance.

    Screening is necessary because a block of a paper is a mixture. Measured whole, every paper sat
    0.635 to 0.818 from every anchor, which is where English sits from all of them, and the gaps
    between candidates were a hundredth of the resolution. The anchors separate cleanly from each
    other, all fifteen pairs. What does not separate is a bag holding both.
    """
    held = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = " ".join(line.split())
            if not trimmed or PAGE.match(trimmed) or not looks_like_writing(trimmed):
                continue
            if surprise(trimmed, english, total) >= cut:
                held.append(trimmed)
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    texts = language_texts()
    texts["English"] = english_texts()
    if len(texts) < 3:
        out.write("  no anchors, run the nine readers first\n")
        out.flush()
        return 1

    anchors = {}
    resolution = 0.0
    out.write("  %-16s %-8s %-9s %-8s %s\n" % ("anchor", "lines", "D_self", "support", "H"))
    for name in sorted(texts):
        lines = texts[name]
        profile, total = squash(lines)
        own = self_distance(lines)
        resolution = max(resolution, own)
        anchors[name] = profile
        out.write("  %-16s %-8d %-9.4f %-8d %.2f\n"
                  % (name, len(lines), own, support(profile), entropy(profile)))
    out.write("\n  resolution taken as the worst anchor D_self, %.4f\n" % resolution)

    # The screen. One anchor, English, and a threshold set by the corpus already known to be pure.
    screen_counts, screen_total, screen_lines = english_reference()
    cut = calibrated_cut(screen_counts, screen_total)
    out.write("  screen: English over %d lines, cut %.2f from the pure corpus\n"
              % (screen_lines, cut))

    agreed = 0
    judged = 0
    unreadable = 0
    disagreed = []
    for path in sorted(glob.glob(os.path.join(PAPERS, "*.txt"))):
        says = attribution(named_in(path))
        if says not in anchors:
            continue
        # One sample per paper, as large as the paper allows. Cutting it into blocks put every
        # sample below what the estimator resolves, which is the same mistake as scoring a line.
        noise = paper_lines(path, screen_counts, screen_total, cut)
        profile, total = squash(noise)
        if total < 2000:
            unreadable += 1
            continue
        # The sample's own split-half is its noise floor. A gap wider than that is a difference,
        # and a gap inside it is the estimator, which is section 3 and nothing else.
        floor = self_distance(noise)
        picked, near, gap, readable = reading(
            [(distance(profile, one), name) for name, one in anchors.items() if name != "English"],
            floor, margin=1.0)
        if not readable:
            unreadable += 1
            continue
        judged += 1
        if picked == says:
            agreed += 1
        else:
            disagreed.append((says, picked, near, gap, floor, os.path.basename(path)[:-4]))

    out.write("\n  %d papers named a language the anchors know\n" % (judged + unreadable))
    out.write("  %d had no block that cleared the resolution\n" % unreadable)
    if judged:
        out.write("  %d were readable, and the distributions agreed with the prose on %d, %.0f%%\n"
                  % (judged, agreed, 100.0 * agreed / judged))
    out.write("\n  where they disagree\n")
    for says, picked, near, gap, floor, stem in disagreed[:10]:
        out.write("    %-36s says %-13s bytes %-13s D %.3f, gap %.3f, floor %.3f\n"
                  % (stem[:36], says, picked, near, gap, floor))
    if not disagreed:
        out.write("    nowhere\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
