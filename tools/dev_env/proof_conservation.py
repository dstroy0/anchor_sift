#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Proof of the posit that a quantity failing to conserve indicates the instrument, from the posits
# section of docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/proof_conservation.py corpus.sym
#
# The posit came from one case, where the same measure over a quarter, a half and the whole of a corpus
# gave 1.41, 1.25 and 19684 and the discontinuity was a mean over a heavy tail. One case is an anecdote.
#
# Proving it means stating what the measure should be invariant to and checking each. Relabelling the
# symbols cannot change gaps between occurrences, so it has to conserve exactly. Reading the corpus
# backwards reverses every gap sequence and leaves the gaps themselves, so it has to conserve exactly as
# well. Truncation and duplication should conserve approximately if the corpus is homogeneous. Block
# shuffling and added noise should move it, and a transformation that fails to move it is as much a
# defect as one that moves what should hold still.
#
# Reseeding the null is the important row. The measure is a live quantity divided by one taken from a
# shuffle, and the shuffle carries its own randomness, so the spread over seeds is the floor below which
# no difference between two corpora means anything. That floor has been used all through this work and
# never measured.

import io
import os
import random
import statistics
import sys

MIN_OCCURRENCES = 32
SEEDS = 12


def dispersion(seats):
    seen = {}
    for index, value in enumerate(seats):
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


def tail(seats, seed):
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    live = dispersion(seats)
    shuffled = bytearray(seats)
    random.Random(seed).shuffle(shuffled)
    dead = dispersion(shuffled)
    rows = []
    for value, spread in live.items():
        if (value in dead) and (spread > 0.0):
            rows.append((counts[value], dead[value] / spread))
    if len(rows) < 4:
        return float("nan")
    rows.sort(reverse=True)
    return statistics.fmean(row[1] for row in rows[len(rows) // 2:])


def relabel(seats, rng):
    table = list(range(256))
    rng.shuffle(table)
    return bytearray(table[value] for value in seats)


def block_shuffle(seats, span, rng):
    blocks = [seats[start:start + span] for start in range(0, len(seats), span)]
    rng.shuffle(blocks)
    out = bytearray()
    for block in blocks:
        out.extend(block)
    return out


def add_noise(seats, share, rng):
    out = bytearray(seats)
    alphabet = sorted(set(seats))
    for index in rng.sample(range(len(out)), int(len(out) * share)):
        out[index] = rng.choice(alphabet)
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: proof_conservation.py corpus.sym")
        return 1
    path = sys.argv[1]
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")

    # The floor first, since every other row has to be read against it
    marks = [tail(seats, 0x51F7 + step) for step in range(SEEDS)]
    marks = [value for value in marks if value == value]
    floor = statistics.pstdev(marks)
    base = statistics.fmean(marks)
    out.write("  %s, %d symbols\n" % (os.path.basename(path)[:-4], len(seats)))
    out.write("  null reseeded %d times: mean %.4f, sd %.4f, range %.4f to %.4f\n\n"
              % (len(marks), base, floor, min(marks), max(marks)))

    rng = random.Random(0xF1009)
    cases = (
        ("relabel symbols", relabel(seats, rng), "exact"),
        ("read backwards", bytearray(reversed(seats)), "exact"),
        ("first half", seats[:len(seats) // 2], "close"),
        ("second half", seats[len(seats) // 2:], "close"),
        ("doubled", seats + seats, "close"),
        ("block shuffle 4096", block_shuffle(seats, 4096, random.Random(0xB10C)), "moves"),
        ("noise at 5%", add_noise(seats, 0.05, random.Random(0x0135)), "moves"),
    )

    out.write("  %-20s %-9s %-10s %-9s %s\n"
              % ("transform", "tail", "shift", "in floors", "expected"))
    for label, changed, expected in cases:
        value = tail(changed, 0x51F7)
        shift = value - base
        floors = abs(shift) / floor if floor > 0 else float("inf")
        out.write("  %-20s %-9.4f %+-10.4f %-9.1f %s\n" % (label, value, shift, floors, expected))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
