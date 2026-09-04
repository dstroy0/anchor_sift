#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Generate corpora from memoryless random processes, as controls for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/gen_monkey_corpus.py
#
# Section 4.13 reports a Zipf slope and a brevity correlation for ten natural corpora and reads their
# agreement as a property of how people produce language. Section 7.4 tests that against a memoryless
# process, since the literature there holds that such a process reproduces the statistics. Characters
# are drawn independently, so nothing links one position to the next and nothing is optimizing.
#
# The first version of this file had one arm weighted by English letter frequencies and one uniform
# arm, with the alphabet fixed at 26 and the delimiter rate at 0.18. Three of those four numbers were
# taken from English, so an English-looking result proved nothing. The sweep below varies the alphabet
# size, the delimiter rate and the shape of the letter distribution, and only one row is allowed to
# carry a measurement taken from a language. What matters is the range of Zipf slopes an arbitrary
# memoryless process reaches, not the value one tuned instance of it reaches.

import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")

TARGET_BYTES = 1200000
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-*/=<>"

# Relative frequencies of English letters. The one row in the sweep carrying a value from a language,
# kept so the seeded case can be compared against the unseeded ones instead of standing alone.
ENGLISH_WEIGHTS = [
    8.17, 1.49, 2.78, 4.25, 12.70, 2.23, 2.02, 6.09, 6.97, 0.15, 0.77, 4.03, 2.41,
    6.75, 7.51, 1.93, 0.10, 5.99, 6.33, 9.06, 2.76, 0.98, 2.36, 0.15, 1.97, 0.07,
]

# name, alphabet size, delimiter share, distribution shape
SWEEP = [
    ("monkey_a26_d18_uniform", 26, 0.18, "uniform"),
    ("monkey_a26_d18_english", 26, 0.18, "english"),
    ("monkey_a08_d18_uniform", 8, 0.18, "uniform"),
    ("monkey_a64_d18_uniform", 64, 0.18, "uniform"),
    ("monkey_a26_d06_uniform", 26, 0.06, "uniform"),
    ("monkey_a26_d35_uniform", 26, 0.35, "uniform"),
    ("monkey_a26_d18_geom90", 26, 0.18, "geom90"),
    ("monkey_a26_d18_geom70", 26, 0.18, "geom70"),
    ("monkey_a64_d06_geom90", 64, 0.06, "geom90"),
    ("monkey_a08_d35_geom70", 8, 0.35, "geom70"),
]


def weights_for(shape, size):
    """Relative letter weights for one arm, or None where every letter is equally likely."""
    if shape == "uniform":
        return None
    if shape == "english":
        return ENGLISH_WEIGHTS[:size]
    # A geometric fall across the alphabet, which is unequal without being taken from any language
    ratio = 0.90 if shape == "geom90" else 0.70
    return [ratio ** index for index in range(size)]


def emit(name, size, delimiter_share, shape, seed):
    """Write one corpus of independent character draws, with a delimiter acting as the boundary."""
    rng = random.Random(seed)
    letters = list(ALPHABET[:size])
    weights = weights_for(shape, size)
    out = []
    total = 0

    while total < TARGET_BYTES:
        if rng.random() < delimiter_share:
            out.append(" ")
            total += 1
            continue
        if weights is None:
            out.append(rng.choice(letters))
        else:
            out.append(rng.choices(letters, weights=weights, k=1)[0])
        total += 1

    body = "".join(out)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".txt")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(body)

    words = body.split()
    print("  %-26s alphabet %2d, delimiter %.2f, %-7s %7d words, %6d distinct"
          % (name, size, delimiter_share, shape, len(words), len(set(words))))


def main():
    seed = 0x5EED
    for name, size, delimiter_share, shape in SWEEP:
        emit(name, size, delimiter_share, shape, seed)
        seed += 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
