#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find the language in a paper by knowing English and taking what is left.
#
#   Usage:  python tools/dev_env/english_sift.py <paper stem> [more stems]
#           python tools/dev_env/english_sift.py --check
#
# Every reader in this directory was written against one paper's layout, and each one cost a day of
# finding out how that paper prints a footnote. Fifty papers here have no reader and will not get
# one each.
#
# Douglas put it the other way round: run the algorithm with English as the target, and the thing
# you are sifting for is the noise. That inverts the problem into the half that is well resourced.
# Nobody has to know Nsyilxcən or Lushootseed to find it. What has to be known is English, and a
# line that English does not account for is the language, a page number, or a gloss label, and
# those three are told apart by shape, never by vocabulary.
#
# The measure is the one anchor-sift-method.md describes, in its cheapest form. A line is squashed
# to the byte pairs it contains, k = 256*b_i + b_(i+1), which is a flat index over 2^16 and takes
# no decision about characters at all. That matters here: half the trouble in this directory came
# from fonts that wrote ə as @ and ʔ as P, and a byte pair does not care what a glyph was meant to
# be. Each pair is scored against how often English uses it, and the line's score is the mean
# surprise across its pairs.
#
# The reference is built from the English already sitting in the extracted corpora: the translation
# and gloss lines, which nine readers have already marked as English. That is in-domain English,
# out of the same PDF pipeline, carrying the same typography and the same extraction damage as the
# lines being scored. A reference taken from ordinary prose would differ from the input for reasons
# that have nothing to do with language.

import glob
import io
import math
import os
import re
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

MARKED_SPAN = re.compile(r"([TN])\.([^:{}\s]*):\{([^}]*)\}")
PAGE = re.compile(r"^===== page \d+ =====$")

# The kinds that are English sentences. A gloss is not one: COP=3SBJ D/C=NMLZ=STAT-mix=3POSS is
# written in labels and separators and is about as far from English as the language is, so letting
# it into the reference taught this that English looks like that.
ENGLISH_KINDS = ("translation", "commentary", "word gloss")

# Pairs seen this few times in the reference are treated as unseen. A handful of stray pairs from a
# name or a citation should not make a line look like English.
FLOOR = 3


def pairs_of(text):
    """The byte pairs of a line, as the flat index the method squashes them to."""
    data = text.encode("utf-8")
    return [(data[at] << 8) | data[at + 1] for at in range(len(data) - 1)]


def english_reference():
    """How often English uses each byte pair.

    Two sources, because they answer different halves of the question. cc_english.txt is four
    megabytes of ordinary English and gives the shape of the language itself. The N spans the nine
    readers wrote, which are the translations, the glosses and the commentary, are English out of
    the same PDFs as the lines being scored, and they carry the same typography and the same
    extraction damage. A reference built only from ordinary prose would differ from the input for
    reasons that have nothing to do with which language a line is in.
    """
    counts = {}
    total = 0
    lines = 0

    bulk = os.path.join(CORPORA, "cc_english.txt")
    if os.path.isfile(bulk):
        with open(bulk, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = line.strip()
                if not trimmed:
                    continue
                lines += 1
                for one in pairs_of(trimmed):
                    counts[one] = counts.get(one, 0) + 1
                    total += 1

    for path in sorted(glob.glob(os.path.join(CORPORA, "*_mixed.txt"))
                       + glob.glob(os.path.join(CORPORA, "*_nomixed.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#"):
                    continue
                for mark, kind, run in MARKED_SPAN.findall(line.rstrip("\n")):
                    if (mark != "N") or not run.strip():
                        continue
                    if not any(one in kind for one in ENGLISH_KINDS):
                        continue
                    lines += 1
                    for one in pairs_of(run):
                        counts[one] = counts.get(one, 0) + 1
                        total += 1
    return counts, total, lines


def counts_of(texts):
    """Byte-pair counts over a body of text, which is the squash of method section 1."""
    held = {}
    total = 0
    for one in texts:
        for pair in pairs_of(one):
            held[pair] = held.get(pair, 0) + 1
            total += 1
    return held, total


def distribution(counts, total):
    """P(k) = c(k) / sum c, the flat distribution over the 2^16 cells."""
    if not total:
        return {}
    return {k: c / total for k, c in counts.items()}


def total_variation(first, second):
    """D(P,Q) = half the sum of |P(k) - Q(k)|, method section 2.

    Between normalized distributions, so it does not care how much text built either one. That is
    the whole reason to use it here: two anchors of different sizes ask the same question, which no
    per-line likelihood managed. Scoring lines against differently sized references made the
    smallest anchor win under one estimator and the largest under the next.
    """
    run = 0.0
    for k in set(first) | set(second):
        run += abs(first.get(k, 0.0) - second.get(k, 0.0))
    return run / 2.0


def support(profile):
    """How many of the 2^16 cells the distribution occupies, method section 4."""
    return sum(1 for one in profile.values() if one > 0)


def entropy(profile):
    """H(P) in bits, method section 4. Reported beside a distance, never instead of it."""
    return -sum(one * math.log2(one) for one in profile.values() if one > 0)


def self_distance(texts):
    """D_self, method section 3: the corpus split at its midpoint and measured against itself.

    This is the resolution of the estimator at this sample size. A distance to another corpus means
    nothing unless it is well clear of this, and a corpus whose D_self is large is simply too small
    to tell from noise.
    """
    held = list(texts)
    if len(held) < 2:
        return 1.0
    middle = len(held) // 2
    first = distribution(*counts_of(held[:middle]))
    second = distribution(*counts_of(held[middle:]))
    if not first or not second:
        return 1.0
    return total_variation(first, second)


def looks_like_writing(text, floor=0.5):
    """Whether a line is written in letters at all, whatever language they spell.

    The surprise measure answers one question, whether English accounts for a line, and two very
    different things fail it. One is another language. The other is a PDF whose font carried a
    shifted character map, where the comes out as 2&# and a page of prose arrives as punctuation.
    Both are equally un-English and only one of them is worth reading.

    2008_Mattina and 2008_Thompson are the second kind and they scored 90 and 95 percent before
    this test existed. What separates them is that writing is made of letters: qawqs. is 83 percent
    letters and 2&#,-+', *'8#" is 14 percent. This does not know which language, and does not need
    to, since the damaged Lushootseed of 1983_Hilbert passes it as easily as clean text would.
    """
    solid = [one for one in text if not one.isspace()]
    if len(solid) < 3:
        return False
    return (sum(1 for one in solid if one.isalpha()) / len(solid)) >= floor


def surprise(text, counts, total):
    """How much a reference fails to account for a line, as mean bits per byte pair.

    Smoothed over the whole 2^16 square the squash defines, one count added to every cell:

        p(k) = (times + 1) / (total + 65536)

    That correction is what §4 of the method calls for and it is not optional. Charging an unseen
    pair log2(total) instead made the penalty depend on how much reference there was, so the
    smallest corpus punished the unknown least and won every comparison it entered. Five language
    anchors of different sizes agreed with the papers' own statements 63 percent of the time under
    that scoring, and every single disagreement named the smallest anchor.

    Averaged over the line, never summed. A long line and a short one stay comparable.
    """
    held = pairs_of(text)
    if not held:
        return 0.0
    floor = total + 65536.0
    run = 0.0
    for one in held:
        run += -math.log2((counts.get(one, 0) + 1.0) / floor)
    return run / len(held)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    counts, total, lines = english_reference()
    if not total:
        out.write("  no English reference, run the extractors first\n")
        out.flush()
        return 1
    out.write("  reference: %d English lines, %d byte pairs, %d distinct\n"
              % (lines, total, len(counts)))

    if (len(sys.argv) > 1) and (sys.argv[1] == "--check"):
        return check(out, counts, total)

    for stem in sys.argv[1:]:
        path = os.path.join(PAPERS, "%s.txt" % stem)
        if not os.path.isfile(path):
            out.write("  no %s\n" % path)
            continue
        scored = []
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = " ".join(line.split())
                if not trimmed or PAGE.match(trimmed):
                    continue
                scored.append((surprise(trimmed, counts, total), trimmed))
        scored.sort(reverse=True)
        out.write("\n  %s: %d lines\n" % (stem, len(scored)))
        out.write("  the twenty English accounts for least\n")
        for score, text in scored[:20]:
            out.write("    %5.2f  %s\n" % (score, text[:88]))
    out.flush()
    return 0


def language_reference():
    """How often the language uses each byte pair, from the corpus known to be pure.

    The second anchor. With only English, a line is either English or not, and not covers a word
    of the language, a gloss written in labels, and a page of font damage alike. With both, a line
    can be nearer one, nearer the other, or near neither, and the third case is the small one.
    """
    counts = {}
    total = 0
    lines = 0
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = line.strip()
                if not trimmed:
                    continue
                lines += 1
                for one in pairs_of(trimmed):
                    counts[one] = counts.get(one, 0) + 1
                    total += 1
    return counts, total, lines


def sorted_into(text, english, language, margin=0.5):
    """Which of the two anchors a line belongs to, or neither.

    Returns "english", "language", or "residue". The margin is in bits per byte pair. A line inside
    it is nearer neither anchor than it is to the other, and those are the glosses, the formatting
    and the damage. That set is small, which is the point of splitting three ways: what is left for
    a person to look at is the part no measure settled.
    """
    if not looks_like_writing(text):
        return "residue"
    to_english = surprise(text, english[0], english[1])
    to_language = surprise(text, language[0], language[1])
    if (to_english - to_language) > margin:
        return "language"
    if (to_language - to_english) > margin:
        return "english"
    return "residue"


def calibrated_cut(counts, total, keep=0.99):
    """The cut that keeps the given share of the known-pure corpus.

    Measured, not chosen. Nine papers were read by hand against their own layouts and their
    .pure.txt files are target-language speech and nothing else, so the score below which the
    language does not fall is a fact about this corpus, and not a threshold somebody picked.
    """
    pure = []
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = line.strip()
                if trimmed and looks_like_writing(trimmed):
                    pure.append(surprise(trimmed, counts, total))
    if not pure:
        return None
    pure.sort()
    return pure[int((1.0 - keep) * len(pure))]


def check(out, counts, total):
    """Set the cut from the corpus that is already known to be pure.

    Nine papers were read by hand, line by line, against their own layout. What came out of that is
    the control: the .pure.txt files hold target-language speech and nothing else, and the N spans
    in the marked files hold the English the same readers set aside. Both sides of the question are
    already answered. The cut is measured here, never chosen.

    The cut is put where it keeps 99 percent of the known-pure lines. Missing language costs more
    than admitting a line of English, because a line wrongly kept is visible to whoever reads it
    next and a line wrongly dropped is not.
    """
    pure = []
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = line.strip()
                if trimmed and looks_like_writing(trimmed):
                    pure.append(surprise(trimmed, counts, total))

    english = []
    for path in sorted(glob.glob(os.path.join(CORPORA, "*_mixed.txt"))
                       + glob.glob(os.path.join(CORPORA, "*_nomixed.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#"):
                    continue
                for mark, kind, run in MARKED_SPAN.findall(line.rstrip("\n")):
                    if (mark != "N") or not run.strip() or not looks_like_writing(run):
                        continue
                    if any(one in kind for one in ENGLISH_KINDS):
                        english.append(surprise(run, counts, total))

    if not pure or not english:
        out.write("  no control to measure against, run the extractors first\n")
        out.flush()
        return 1

    pure.sort()
    english.sort()
    out.write("\n  one anchor, English only\n")
    out.write("    %d known-pure lines, median %.2f\n" % (len(pure), pure[len(pure) // 2]))
    out.write("    %d known-English spans, median %.2f\n"
              % (len(english), english[len(english) // 2]))
    keep = pure[int(0.01 * len(pure))]
    out.write("    cut %.2f keeps %.1f%% of the pure corpus, admits %.1f%% of the English\n"
              % (keep, 100.0 * sum(1 for one in pure if one >= keep) / len(pure),
                 100.0 * sum(1 for one in english if one >= keep) / len(english)))

    # Both anchors, run over the same control. What the second one buys is the residue: lines that
    # are near neither, which is where a gloss and a page of font damage go instead of into one of
    # the two answers.
    other = language_reference()
    mine = (counts, total)
    out.write("\n  two anchors, English and the pure corpus\n")
    counted = {"pure": {}, "english": {}}
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                trimmed = line.strip()
                if trimmed:
                    where = sorted_into(trimmed, mine, other)
                    counted["pure"][where] = counted["pure"].get(where, 0) + 1
    for path in sorted(glob.glob(os.path.join(CORPORA, "*_mixed.txt"))
                       + glob.glob(os.path.join(CORPORA, "*_nomixed.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#"):
                    continue
                for mark, kind, run in MARKED_SPAN.findall(line.rstrip("\n")):
                    if (mark != "N") or not run.strip():
                        continue
                    if any(one in kind for one in ENGLISH_KINDS):
                        where = sorted_into(run, mine, other)
                        counted["english"][where] = counted["english"].get(where, 0) + 1
    for side in ("pure", "english"):
        held = counted[side]
        whole = sum(held.values()) or 1
        out.write("    %-20s %s\n"
                  % (side, ", ".join("%s %d (%.0f%%)" % (one, held.get(one, 0),
                                                         100.0 * held.get(one, 0) / whole)
                                     for one in ("language", "english", "residue"))))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
