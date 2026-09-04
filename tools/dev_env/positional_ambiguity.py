#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether a word's ambiguity depends on where in the sentence it sits, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/positional_ambiguity.py
#
# The syncretism counts gave one number per language, and one number is not usable while reading. What
# would be usable is knowing where the ambiguity sits, because a reader always knows the position of the
# word in hand.
#
# There is already a hint that it is not spread evenly. Two counts came out of the same corpus and they
# disagree: German meets 4.09 readings per word in running text but holds only 1.42 per distinct form. The
# gap between them is frequency weighting, which means the forms carrying several readings are the ones
# used constantly. Frequent forms are function words, and function words occupy constrained places in a
# sentence. If that chain holds, ambiguity is positional.
#
# So this counts readings per word at each of the first ten places in the sentence, per language. A flat
# profile means position buys nothing and the earlier product over ten words was already the right model.
# A varying profile means a walk that knows its position faces a smaller space than one that does not.
#
# The direction of that second result is arithmetic and not a finding: the product of ten numbers is at
# most the tenth power of their average, so a varying profile always produces a smaller product than an
# even one. Only the size of the gap is measured here, and the even-profile product is printed beside it
# so the gap is separable from the inequality that guarantees it.
#
# What this cannot see: a treebank records the reading a word had in the sentence it appeared in, not
# every reading it could have, so a longer corpus finds more ambiguity and languages of unlike corpus size
# are not safely compared. And the tenth place exists only in sentences at least ten words long, which are
# not the same sentences that supply the first place.

import io
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

PLACES = 10
COMMONEST = 100

WHAT_IT_IS = {
    "polish": "seven cases, heavy syncretism",
    "finnish": "fifteen cases, little syncretism",
    "hungarian": "agglutinative",
    "estonian": "fourteen cases",
    "german": "four cases, much syncretism",
    "english": "almost no inflection",
    "vietnamese": "no inflection at all",
    "turkish": "agglutinative",
}


def read_sentences(path, fold_case=True):
    """Every sentence as its words in order, each with the reading that sentence gave it.

    Folding case is the usual move and it costs German the cue its orthography carries, where a
    capital letter mid-sentence marks a noun and the lowercase word of the same letters is a verb.
    Pass fold_case False to keep that cue and count what a German reader actually has in front of
    them.
    """
    sentences = []
    building = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = line.rstrip("\n")
            if not trimmed.strip():
                if building:
                    sentences.append(building)
                    building = []
                continue
            if not trimmed[0].isdigit():
                continue
            parts = trimmed.split("\t")
            if len(parts) < 6 or ("-" in parts[0]) or ("." in parts[0]):
                continue
            form = parts[1].lower() if fold_case else parts[1]
            reading = "%s|%s|%s" % (parts[2].lower(), parts[3], parts[5])
            building.append((form, reading))
    if building:
        sentences.append(building)
    return sentences


def measure(sentences):
    """The readings a word carries overall, at each place, and where the ambiguity is concentrated."""
    seen = {}
    times = {}
    for sentence in sentences:
        for form, reading in sentence:
            seen.setdefault(form, set()).add(reading)
            times[form] = times.get(form, 0) + 1

    met = statistics.fmean(len(seen[form]) for sentence in sentences for form, _ in sentence)
    holds = statistics.fmean(len(readings) for readings in seen.values())

    gathered = [[] for _ in range(PLACES)]
    for sentence in sentences:
        for place, entry in enumerate(sentence[:PLACES]):
            gathered[place].append(len(seen[entry[0]]))
    profile = [statistics.fmean(marks) if marks else float("nan") for marks in gathered]
    depth = [len(marks) for marks in gathered]

    # Ambiguity above one reading, and how much of it the commonest forms carry
    ranked = sorted(times, key=lambda form: -times[form])[:COMMONEST]
    common = set(ranked)
    over_one = sum((len(seen[form]) - 1) * times[form] for form in times)
    from_common = sum((len(seen[form]) - 1) * times[form] for form in common)
    share = (from_common / float(over_one)) if over_one else 0.0

    return met, holds, profile, depth, share, len(seen)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        sentences = read_sentences(os.path.join(CORPORA, name))
        tokens = sum(len(sentence) for sentence in sentences)
        if tokens < 5000:
            continue
        met, holds, profile, depth, share, forms = measure(sentences)
        rows.append((language, tokens, len(sentences), forms, met, holds, profile, depth, share))

    rows.sort(key=lambda row: -row[4])

    out.write("  %-12s %-9s %-9s %-9s %-9s %-9s %s\n"
              % ("language", "tokens", "forms", "per word", "per form", "the gap", "top 100"))
    for language, tokens, count, forms, met, holds, profile, depth, share in rows:
        out.write("  %-12s %-9d %-9d %-9.4f %-9.4f %-9.4f %.4f\n"
                  % (language, tokens, forms, met, holds, met - holds, share))
    out.write("\n  the gap is frequency weighting, and top 100 is the share of all ambiguity\n")
    out.write("  above one reading that the hundred commonest forms carry\n")

    out.write("\n  readings carried at each place in the sentence\n")
    out.write("  %-12s" % "language")
    for place in range(PLACES):
        out.write("%6d" % (place + 1))
    out.write("   spread\n")
    for language, tokens, count, forms, met, holds, profile, depth, share in rows:
        out.write("  %-12s" % language)
        for value in profile:
            out.write("%6.2f" % value)
        spread = (max(profile) - min(profile)) / statistics.fmean(profile)
        out.write("   %.3f\n" % spread)
    out.write("\n  spread is the range across those ten places over their average\n")

    out.write("\n  ten words of running text, with the readings of each multiplied\n")
    out.write("  %-12s %-13s %-13s %-13s %s\n"
              % ("language", "one number", "even profile", "measured", "what position buys"))
    for language, tokens, count, forms, met, holds, profile, depth, share in rows:
        blind = met ** PLACES
        level = statistics.fmean(profile)
        even = level ** PLACES
        knowing = 1.0
        for value in profile:
            knowing *= value
        out.write("  %-12s %-13.4g %-13.4g %-13.4g %.3f of the even profile\n"
                  % (language, blind, even, knowing, knowing / even))

    out.write("\n  one number applies the whole-corpus average ten times over\n")
    out.write("  even profile applies the average of the ten places ten times over\n")
    out.write("  measured multiplies the ten places as they actually came out\n")

    if rows:
        out.write("\n  how the count moves from the first place to the tenth\n")
        for language, tokens, count, forms, met, holds, profile, depth, share in rows:
            out.write("  %-12s %-32s first %.2f, tenth %.2f, %s\n"
                      % (language, WHAT_IT_IS.get(language, ""), profile[0], profile[-1],
                         "falls" if profile[-1] < profile[0] else "climbs"))
        out.write("\n  the tenth place is counted only in sentences that reach it, and those\n")
        out.write("  are not the sentences that supply the first place\n")
        thin = min(row[7][-1] for row in rows)
        out.write("  the thinnest tenth place here rests on %d sentences\n" % thin)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
