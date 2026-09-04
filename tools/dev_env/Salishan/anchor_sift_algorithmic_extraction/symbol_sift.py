#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Recover a symbol a bad digitization dropped, using the sift and not a person's eye.
#
#   Usage:  python tools/dev_env/Salishan/anchor_sift_algorithmic_extraction/symbol_sift.py <stem>
#
# Some of these PDFs drop a combining mark and leave behind the space the typesetter made room for.
# Davis and Mellesmoen prints xʷəlp-í<p>l̓əx once with the mark and once as xʷəlp-í<p>l əx without it,
# so one word arrives two ways in one file and neither spelling says which is right.
#
# Reading it off a rendered page works and does not scale. Twenty papers at twenty-four pages each is
# a person squinting at four hundred images, and every one of those readings is a judgment nobody can
# check afterward. This asks the algorithm instead, and the answer comes with a number on it.
#
# THE METHOD IS THE ONE boundary_check USES
#
# A break site is a place where the extraction has two tokens and the paper may have had one. The
# candidates are the two tokens joined by each mark the paper writes, and joined by nothing at all,
# which is the reading where the space is a real word boundary.
#
# Each candidate is scored on the runs it makes. Run counts are taken from the tokens that carry no
# break, which is the paper's own undamaged vocabulary, and then flattened to maximum entropy the way
# radix flattens the pooled counts of two dialects: a run common everywhere contributes nothing
# however common it is, and what is left is the part that belongs to this candidate. A restoration
# the language actually has makes runs the paper already uses. A wrong one makes runs nobody wrote.
#
# WHAT MAKES IT A MEASUREMENT AND NOT A GUESS
#
# The same scoring is run with the paper's marks replaced by marks drawn at random from the same
# inventory, many times, and the rate at which a random mark scores as well as the winner is reported
# beside it. A site where the winner does not beat the random draws is a site this cannot read, and
# it says so instead of answering.

import collections
import io
import math
import os
import random
import sys
import unicodedata

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _category in os.scandir(HERE):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from paper_config import by_stem  # noqa: E402
from salish_unsorted import is_language_token  # noqa: E402

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")

# The run widths a candidate is scored at, matching boundary_check. Two characters is a segment and
# its mark, four is about a morpheme in these languages.
WIDTHS = (2, 3, 4)

# How many random draws the winner is scored against. Two hundred puts the resolution of the reported
# rate at half a percent, which is the same budget boundary_check spends.
DRAWS = 200

# How far ahead of the random draws a winner has to stand before it is reported as read. A site where
# the random marks reach the winner's score more than this often is a site with no answer in it.
BEATEN_AT = 0.05

# How long a restoration has to be before it counts as attested by sitting inside another word. Two
# or three characters occur inside almost anything, and letting those through would make every site
# readable and every reading worthless.
INSIDE_FLOOR = 6

# The score a restoration has to clear. A negative score means the runs the restoration makes sit
# below where a flat distribution would put them, which is the reading that this paper does not write
# words shaped like that. Garcia's w ɬ scores -1.4 and is a real word boundary; the same paper's
# Kʷ əɬtəzétkʷu scores 478.0 and is the speaker's own name broken in half.
SCORE_FLOOR = 0.0


def clean_runs(tokens, width):
    """Every run of one width over the tokens that carry no break, counted."""
    counts = collections.Counter()
    for one in tokens:
        for at in range(len(one) - width + 1):
            counts[one[at:at + width]] += 1
    return counts


def flattened(counts):
    """The pooled counts raised to maximum entropy, as the share each run would hold if flat.

    This is the same subtraction radix makes. What a candidate is scored on afterward is its distance
    from this reference and never its raw frequency, so a run that is common everywhere carries no
    weight and a run that belongs to one restoration carries all of it.
    """
    total = sum(counts.values())
    if not (total and counts):
        return {}, 0.0, 0.0
    flat = 1.0 / len(counts)
    return counts, total, flat


def scored(candidate, counts, total, flat):
    """How far a candidate's runs sit from where a flat distribution would put them.

    Each run is its own term, for the reason radix gives: a run needs enough of itself, not enough of
    the language. A run the paper never writes scores below zero, so a restoration that invents runs
    is pushed down and not merely left unrewarded.
    """
    if not total:
        return 0.0
    held = 0.0
    for width in WIDTHS:
        for at in range(len(candidate) - width + 1):
            run = candidate[at:at + width]
            seen = counts.get(run, 0)
            expected = flat * total
            spread = math.sqrt(expected * (1.0 - flat)) or 1.0
            held += (seen - expected) / spread
    return held


# A plain letter the page set as a raised modifier. This is the collapse kind, which is irreversible
# as a rule: page kʷ and page wist both arrive as w and no rule separates them. Per site it is
# decidable anyway, wherever the paper writes the joined form somewhere it was not collapsed, which is
# the same evidence every other candidate here rests on. Robertson's page 30 names its own symbols as
# (č, š, xʷ) and the text holds ( č, š, x w).
COLLAPSED = {"w": "ʷ"}


def candidates_for(first, second, inventory):
    """Every reading of one break site: a dropped mark, a lost space, or a collapsed modifier."""
    held = [(one, first + one + second) for one in inventory]
    held.append(("", first + second))
    # The second token opening with a letter the page set raised. Taking that letter as the modifier
    # is a third reading and it is the one that recovers a labialization.
    if second and (second[0] in COLLAPSED):
        held.append((COLLAPSED[second[0]], first + COLLAPSED[second[0]] + second[1:]))
    return held


def break_sites(lines, marks, vocabulary, inventory):
    """Every place the extraction has two tokens where the paper writes one word elsewhere.

    An earlier version took every adjacent pair whose halves both looked like words, and it proposed
    joining St’át’imcets to the word after it three dozen times. Any pair can be joined; that a pair
    can be joined is not evidence that it was ever one word.

    The evidence is the paper. This damage drops a mark and leaves the space the typesetter made room
    for, and a paper long enough to print a word twice prints it once damaged and once whole:
    xʷəlp-í<p>l̓əx stands in section 2.2.2 and xʷəlp-í<p>l əx in example (23). So a site is a pair
    whose join, under some mark, is a form this paper writes somewhere it was not broken. The word
    supplies its own answer and nothing here has to be inferred from a page.

    That also bounds what this can do. A word the paper prints once and breaks once is not
    recoverable this way, and it is not reported as though it were.
    """
    held = []
    for number, line in enumerate(lines, 1):
        tokens = line.split()
        for at in range(len(tokens) - 1):
            first, second = tokens[at], tokens[at + 1]
            if not (first and second):
                continue
            if not (first[-1].isalpha() or first[-1] in marks):
                continue
            if not (second[0].isalpha() or second[0] in marks):
                continue
            # The test is on what the join would be and not on the halves. x w is the page's xʷ and
            # neither half carries a mark, so asking the halves skipped every labialization in
            # Robertson while the answer sat in the candidate list.
            #
            # It has to be an attested candidate and not any candidate. Inserting a mark makes every
            # pair look like the language: a way became ạway, which carries a dot below and passes a
            # test on the candidates alone, and the reading a way to away then arrived at score 9.8.
            # Requiring the paper to attest the language-token reading throws all of those out.
            # Which restorations this paper attests. The empty mark is in the list because a real
            # word boundary with a lost space is the other thing this damage looks like.
            #
            # A restoration counts as attested where the paper writes it as a token, and also where
            # the paper writes it inside one. qʷal út is qʷal̓út, which this paper never prints alone
            # and does print inside qʷəqʷal̓út, and a whole-token test reads that site as unreadable
            # while the answer is on the page. A floor on the length keeps a short candidate from
            # matching everything: two or three characters occur inside almost any word.
            attested = []
            for one, joined in candidates_for(first, second, inventory):
                if joined in vocabulary:
                    attested.append((one, joined))
                elif (len(joined) >= INSIDE_FLOOR) and any(joined in word for word in vocabulary):
                    attested.append((one, joined))
            attested = [one for one in attested if is_language_token(one[1], marks)]
            if not attested:
                continue
            held.append((number, first, second, attested))
    return held


def inventory(text, marks):
    """The combining marks this paper writes, which are the candidates for a dropped one."""
    held = collections.Counter()
    for symbol in text:
        if unicodedata.combining(symbol) and (symbol in marks):
            held[symbol] += 1
    return [one for one, times in held.most_common()]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if len(sys.argv) < 2:
        out.write("  usage: symbol_sift.py <stem>\n")
        out.flush()
        return 1
    stem = sys.argv[1]
    paper = by_stem(stem)
    if not paper:
        out.write("  %s is not in paper_config\n" % stem)
        out.flush()
        return 1

    path = os.path.join(PAPERS, "%s.txt" % stem)
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = [one.rstrip("\n") for one in handle]
    if paper.repair:
        lines = [paper.repair(one) for one in lines]

    marks = paper.marks
    text = "\n".join(lines)
    # A paper whose alphabet carries no combining mark still has the other half of this damage: a
    # space the extraction put where the paper had none. Nater's etymologies are that case, and
    # bailing out on them left the one class this could read unasked.
    candidates_marks = inventory(text, marks)

    # Every token the paper writes, which is what a restoration has to be found in.
    vocabulary = collections.Counter()
    for line in lines:
        for one in line.split():
            vocabulary[one] += 1

    sites = break_sites(lines, marks, vocabulary, candidates_marks)
    broken = set()
    for number, first, second, attested in sites:
        broken.add(first)
        broken.add(second)
    clean = [one for line in lines for one in line.split()
             if is_language_token(one, marks) and (one not in broken)]

    out.write("  %s\n" % stem)
    out.write("    %d sites where a join is a form this paper writes elsewhere\n" % len(sites))
    out.write("    %d clean tokens for the reference, %d marks in the inventory\n"
              % (len(clean), len(candidates_marks)))
    out.write("    marks: %s\n" % " ".join("U+%04X" % ord(one) for one in candidates_marks))

    counts = {}
    for width in WIDTHS:
        counts[width] = clean_runs(clean, width)
    pooled = collections.Counter()
    for width in WIDTHS:
        pooled.update(counts[width])
    table, total, flat = flattened(pooled)

    # The null. A site is only interesting where the paper attests one restoration and not several,
    # so the rate to beat is how often a mark drawn at random from the inventory also lands on a form
    # this paper writes. That rate is measured over every site rather than assumed.
    chance = 0
    trials = 0
    drawn = random.Random(0)
    pool = candidates_marks + sorted(set(COLLAPSED.values()))
    for number, first, second, attested in sites:
        for _ in range(DRAWS):
            trials += 1
            joined = first + drawn.choice(pool) + second
            if joined in vocabulary:
                chance += 1
            elif (len(joined) >= INSIDE_FLOOR) and any(joined in word for word in vocabulary):
                chance += 1
    rate = (chance / float(trials)) if trials else 0.0

    out.write("\n    a random mark from the inventory lands on a form this paper writes %.3f of\n"
              % rate)
    out.write("    the time, over %d draws, which is the rate a reading here has to beat\n" % trials)

    out.write("\n    %-30s %-30s %-8s %s\n"
              % ("as extracted", "the paper's own spelling", "score", "other readings"))
    read = 0
    ambiguous = 0
    declined = 0
    for number, first, second, attested in sites:
        if len(attested) > 1:
            ambiguous += 1
            continue
        one, joined = attested[0]
        mark = scored(joined, table, total, flat)
        if mark < SCORE_FLOOR:
            declined += 1
            continue
        read += 1
        out.write("    %-30s %-30s %-8.1f %s\n"
                  % (("%s %s" % (first, second))[:30], joined[:30], mark, "none"))

    out.write("\n    %d sites read, %d declined on score, %d left for a person because the\n"
              % (read, declined, ambiguous))
    out.write("    paper attests more than one restoration\n")
    out.write("    a word this paper prints once and breaks once cannot be read this way, and is\n")
    out.write("    not counted above\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
