#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure what folding letter case costs each language, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/case_cue.py
#
# The positional counts were taken with every word folded to lowercase, which is the routine move and is
# wrong for German. A capital letter mid-sentence in German marks a noun, and the same letters written
# lowercase are a verb. Essen is the meal and essen is to eat, and a German reader is never in doubt
# between them because the orthography carries the distinction on the page. Folding the case throws that
# channel away and then reports German as the most ambiguous language in the set, which is a fact about
# the preprocessing and not about German.
#
# Keeping the case lowers the count in every language, because a capitalized word at the start of a
# sentence stops sharing a key with the lowercase word mid-sentence. That drop is not the thing being
# tested. It is the baseline, and the seven other languages supply it.
#
# The test is the same comparison restricted to words at the second place and later, where no word is
# capitalized for being first. Whatever drop survives there comes from a language using capitals
# grammatically inside a sentence. German should show a large one and the others should show close to
# nothing.
#
# The width of the channel is reported beside it: the share of mid-sentence words that carry a capital.
# German capitalizes every noun, English capitalizes proper names, and a language that capitalizes almost
# nothing mid-sentence has no channel to lose.
#
# There is a prediction about position attached to this. German neutralizes its own cue at the first word
# of a sentence, where everything is capitalized whether it is a noun or not. So keeping the case should
# make German's first place stand out further above its own average, since the places after it gain a cue
# the first place cannot have. The ratio of the first place to the profile average is printed both ways.
#
# What this cannot see: a treebank records the reading a word had where it appeared, not every reading it
# could have, so corpora of unlike size are not safely compared against each other. Each language is
# compared only against itself here, which that limit does not reach.

import io
import os
import statistics
import sys

from positional_ambiguity import CORPORA, measure, read_sentences


def readings_per_word(sentences, from_place):
    """Readings per word over the whole lexicon, averaged from a given place in the sentence on."""
    seen = {}
    for sentence in sentences:
        for form, reading in sentence:
            seen.setdefault(form, set()).add(reading)
    marks = [len(seen[form]) for sentence in sentences for form, _ in sentence[from_place:]]
    return statistics.fmean(marks) if marks else float("nan")


def capital_share(sentences, from_place):
    """The share of words from a given place on that are written with a capital first letter."""
    total = 0
    capitals = 0
    for sentence in sentences:
        for form, _ in sentence[from_place:]:
            if not form:
                continue
            total += 1
            if form[0].isupper():
                capitals += 1
    return (capitals / float(total)) if total else float("nan")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        path = os.path.join(CORPORA, name)
        folded = read_sentences(path, fold_case=True)
        kept = read_sentences(path, fold_case=False)
        if sum(len(sentence) for sentence in kept) < 5000:
            continue

        width = capital_share(kept, 1)
        all_folded = readings_per_word(folded, 0)
        all_kept = readings_per_word(kept, 0)
        mid_folded = readings_per_word(folded, 1)
        mid_kept = readings_per_word(kept, 1)

        folded_profile = measure(folded)[2]
        kept_profile = measure(kept)[2]
        folded_spike = folded_profile[0] / statistics.fmean(folded_profile)
        kept_spike = kept_profile[0] / statistics.fmean(kept_profile)

        rows.append((language, width, all_folded, all_kept, mid_folded, mid_kept,
                     folded_spike, kept_spike, kept_profile))

    rows.sort(key=lambda row: -row[1])

    out.write("  how wide the channel is, and what folding it costs over every word\n")
    out.write("  %-12s %-11s %-11s %-11s %s\n"
              % ("language", "caps mid", "folded", "case kept", "drop"))
    for language, width, all_folded, all_kept, mid_f, mid_k, spike_f, spike_k, profile in rows:
        out.write("  %-12s %-11.4f %-11.4f %-11.4f %.1f%%\n"
                  % (language, width, all_folded, all_kept,
                     100.0 * (all_folded - all_kept) / all_folded))
    out.write("\n  caps mid is the share of words past the first that carry a capital\n")

    out.write("\n  the same, counting only words past the first, where nothing is\n")
    out.write("  capitalized for standing at the start of a sentence\n")
    out.write("  %-12s %-11s %-11s %-11s %s\n"
              % ("language", "folded", "case kept", "drop", "what it means"))
    for language, width, all_f, all_k, mid_folded, mid_kept, spike_f, spike_k, profile in rows:
        drop = 100.0 * (mid_folded - mid_kept) / mid_folded
        out.write("  %-12s %-11.4f %-11.4f %-11.1f %s\n"
                  % (language, mid_folded, mid_kept, drop,
                     "uses capitals grammatically" if drop >= 5.0 else "no channel to lose"))

    out.write("\n  the first place against the profile average, both ways\n")
    out.write("  %-12s %-11s %-11s %s\n" % ("language", "folded", "case kept", "moves"))
    for language, width, all_f, all_k, mid_f, mid_k, folded_spike, kept_spike, profile in rows:
        out.write("  %-12s %-11.4f %-11.4f %s\n"
                  % (language, folded_spike, kept_spike,
                     "up" if kept_spike > folded_spike else "down"))

    out.write("\n  german's profile with the case kept\n")
    for language, width, all_f, all_k, mid_f, mid_k, spike_f, spike_k, profile in rows:
        if language != "german":
            continue
        out.write("  %-12s %s\n"
                  % (language, " ".join("%.2f" % value for value in profile)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
