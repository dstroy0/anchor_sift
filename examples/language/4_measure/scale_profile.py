#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Describe a text by what it gains at each distance, not by one number, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/scale_profile.py
#
# Matching against a growing window shows every text still gaining at 262144 characters, so no single
# window holds a text and the rate at any one of them is a reading of that choice. What the sweep produces
# is not one number but a curve: how much a text knows at each distance, and how much each further
# distance adds.
#
# That curve is worth testing as a description of a language in its own right. The reading used until now
# is which character follows which, and one language read from two unrelated places sits 0.0867 apart
# while two languages read from one place sit 0.0936 apart, so where a text came from carries nearly as
# much as what language it is in. If what a language gains at each distance belongs to the language, that
# margin widens. If it belongs to the subject or the translator, it does not.
#
# The shuffle is subtracted at every window, since the estimator drifts with the window on its own and
# both arms carry that drift equally.

import io
import os
import statistics
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.match_rate import match_rate  # noqa: E402
from representation.text.corpus import SOURCES, load_by_source  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 700000
LEAST = 300000
WINDOWS = (512, 2048, 8192, 32768, 131072)
SAMPLES = 900
LONGEST = 300
SEED = 0x51F7


def gaps(text):
    """What the text knows at each distance, over what the same symbols shuffled know."""
    scattered = list(text)
    numpy.random.default_rng(SEED).shuffle(scattered)
    scattered = "".join(scattered)

    profile = []
    for window in WINDOWS:
        if len(text) < (window * 3):
            return None
        # Each arm drawn from its own copy of the seed, so the two sample the same positions
        live = match_rate(text, window, numpy.random.default_rng(SEED), SAMPLES, LONGEST)
        dead = match_rate(scattered, window, numpy.random.default_rng(SEED), SAMPLES, LONGEST)
        if (live is None) or (dead is None):
            return None
        profile.append(dead - live)

    # The curve and what each further distance adds to it, the part a single window cannot hold
    steps = [profile[index] - profile[index - 1] for index in range(1, len(profile))]
    return numpy.asarray(profile + steps, dtype=numpy.float64)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    gathered = {}
    counted = {}
    for key, texts in load_by_source(CORPORA, cap=CAP, least=LEAST).items():
        rows = [values for values in (gaps(text) for text in texts) if values is not None]
        if rows:
            gathered[key] = numpy.mean(numpy.stack(rows), axis=0)
            counted[key[0]] = counted.get(key[0], 0) + 1
    for source, _, _ in SOURCES:
        out.write("  read %d languages from %s\n" % (counted.get(source, 0), source))
    out.flush()

    sources = [source for source, _, _ in SOURCES]
    counts = {}
    for source, language in gathered:
        counts.setdefault(language, []).append(source)
    several = sorted(language for language, held in counts.items() if len(held) >= 2)
    if len(several) < 5:
        out.write("\n  only %d languages are held from more than one place\n" % len(several))
        out.flush()
        return 0

    same_language = []
    for language in several:
        held = [gathered[(source, language)] for source in sources
                if (source, language) in gathered]
        for index, one in enumerate(held):
            for two in held[index + 1:]:
                same_language.append(float(numpy.linalg.norm(one - two)))

    same_source = []
    for source in sources:
        here = [gathered[(source, language)] for language in several
                if (source, language) in gathered]
        for index, one in enumerate(here):
            for two in here[index + 1:]:
                same_source.append(float(numpy.linalg.norm(one - two)))

    correct = 0
    total = 0
    for source, language in sorted(gathered):
        if language not in several:
            continue
        others = [key for key in gathered if key[0] != source]
        if not others:
            continue
        total += 1
        nearest = min(others, key=lambda key: float(
            numpy.linalg.norm(gathered[(source, language)] - gathered[key])))
        correct += 1 if nearest[1] == language else 0

    one = statistics.fmean(same_language)
    two = statistics.fmean(same_source)
    out.write("\n  %d languages held from more than one place\n" % len(several))
    out.write("  one language read from two places      %.4f\n" % one)
    out.write("  two languages read from one place      %.4f\n" % two)
    out.write("  ratio, lower means it belongs to the language   %.3f\n" % (one / two))
    out.write("  matched its own language elsewhere     %d of %d\n" % (correct, total))
    out.write("\n  which symbol follows which gave 0.926 and 44 of 100 on the same question\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
