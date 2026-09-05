#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Proof of the posit that the symbol width has to match the scale of the structure, from the posits
# section of docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/proof_symbol_width.py
#
# The posit came from three failures: a Greek text read one byte at a time where its script spends two, a
# vocalization read at 8 kHz where its units run seconds, and a protein read with exact voxel equality
# where its coordinates are real. Each was diagnosed after the fact, so the rule is inferred from the
# cases that suggested it.
#
# Proving it needs a domain whose structure sits at one width and no other, so one is built here instead
# of found. A vocabulary of fixed width units is emitted with topical clustering, so the arrangement is
# real, it lives at the unit width, and nothing was placed at any other. slice at the right width
# should show it and slice at any other should not.
#
# The phase is swept as well. A detector is not told where the units begin, and a slice that is the
# right width at the wrong offset splits every unit across two symbols.

import io
import random
import statistics
import sys

UNIT = 4
VOCAB = 48
TOPICS = 12
LENGTH = 240000
MIN_OCCURRENCES = 32
WIDTHS = (1, 2, 3, 4, 5, 6, 8, 12)


def build(rng):
    """A sequence whose only arrangement is clustering of fixed width units."""
    words = []
    seen = set()
    while len(words) < VOCAB:
        word = bytes(rng.randrange(256) for _ in range(UNIT))
        if word not in seen:
            seen.add(word)
            words.append(word)

    # Each topic favours a few words, and the topic changes slowly, so a word recurs in bursts. That is
    # the arrangement the measure looks for, and it exists only between units
    topics = [rng.sample(range(VOCAB), 6) for _ in range(TOPICS)]
    out = bytearray()
    topic = topics[0]
    while len(out) < LENGTH:
        if rng.random() < 0.004:
            topic = topics[rng.randrange(TOPICS)]
        out.extend(words[topic[rng.randrange(len(topic))]])
    return bytes(out[:LENGTH])


def slice(data, width, phase):
    """Group `width` bytes into one symbol, starting at `phase`."""
    return [
        data[start : start + width]
        for start in range(phase, len(data) - width + 1, width)
    ]


def dispersion(symbols):
    seen = {}
    for index, value in enumerate(symbols):
        seen.setdefault(value, []).append(index)
    out = {}
    for value, spots in seen.items():
        if len(spots) < MIN_OCCURRENCES:
            continue
        gaps = [spots[step] - spots[step - 1] for step in range(1, len(spots))]
        mean = statistics.fmean(gaps)
        if mean > 0.0:
            out[value] = statistics.pstdev(gaps) / mean
    return out


def tail_ratio(symbols, seed):
    counts = {}
    for value in symbols:
        counts[value] = counts.get(value, 0) + 1
    live = dispersion(symbols)
    shuffled = list(symbols)
    random.Random(seed).shuffle(shuffled)
    dead = dispersion(shuffled)

    rows = []
    for value, spread in live.items():
        if (value in dead) and (spread > 0.0):
            rows.append((counts[value], dead[value] / spread))
    if len(rows) < 4:
        return float("nan"), len(rows)
    rows.sort(reverse=True)
    marks = [row[1] for row in rows[len(rows) // 2 :]]
    return statistics.fmean(marks), len(rows)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")
    data = build(random.Random(0x5CA1E))
    out.write("  structure built at a width of %d, %d bytes\n\n" % (UNIT, len(data)))
    out.write(
        "  %-8s %-10s %-10s %s\n"
        % ("width", "phase 0", "worst phase", "symbols scored")
    )

    for width in WIDTHS:
        marks = []
        counts = []
        for phase in range(width):
            ratio, scored = tail_ratio(slice(data, width, phase), 0x51F7)
            if ratio == ratio:
                marks.append(ratio)
                counts.append(scored)
        if not marks:
            out.write("  %-8d %-10s %-10s %s\n" % (width, "too few", "", ""))
            continue
        # Lower is a larger departure, so the worst phase is the highest value
        out.write(
            "  %-8d %-10.3f %-10.3f %d\n" % (width, marks[0], max(marks), counts[0])
        )

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
