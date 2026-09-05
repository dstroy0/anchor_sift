#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Apply reversible transforms to a re-sliced corpus, for Section 7.4 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/transform_corpus.py source.sym
#
# Section 7.4 finds one measure surviving as a separator, the dispersion of a boundary against a
# permutation null, and states its limit: it reports that a corpus is not memoryless, and a structured
# non-linguistic system passes it too. These transforms test both halves of that on one text.
#
# Each transform keeps every symbol inside the seat range the source uses, so the same measurement path
# reads the output and nothing is being compared across a change of representation.
#
#   substitute   one fixed permutation of the seats, which is a monoalphabetic cipher
#   repeatkey    an eight seat repeating key added under modular arithmetic, a Vigenere
#   keystream    a full length pseudorandom addend, which is the one time pad arrangement
#   counter      a deterministic ramp, carrying no text at all
#
# The first two preserve the positions of repeats and the third destroys them. The fourth is the case
# that matters for the limit: it is perfectly regular and not produced by anybody.

import os
import random
import sys

KEY_LENGTH = 8


def load_seats(path):
    with open(path, "rb") as handle:
        return bytearray(handle.read())


def seat_span(seats):
    """Lowest and highest seat in use, so a transform can stay inside the source's own range."""
    return min(seats), max(seats)


def substitute(seats, low, high, rng):
    span = high - low + 1
    table = list(range(span))
    rng.shuffle(table)
    return bytearray(low + table[value - low] for value in seats)


def repeatkey(seats, low, high, rng):
    span = high - low + 1
    key = [rng.randrange(span) for _ in range(KEY_LENGTH)]
    return bytearray(
        low + ((value - low) + key[index % KEY_LENGTH]) % span
        for index, value in enumerate(seats)
    )


def keystream(seats, low, high, rng):
    span = high - low + 1
    return bytearray(
        low + ((value - low) + rng.randrange(span)) % span for value in seats
    )


def counter(seats, low, high, rng):
    span = high - low + 1
    return bytearray(low + (index % span) for index in range(len(seats)))


def repeatkey_coset(seats, low, high, rng):
    """Every KEY_LENGTH'th symbol of a Vigenere, which is one alphabet of it.

    A repeating key sends one plaintext symbol to KEY_LENGTH different ciphertext symbols by position,
    so a measure reading the gaps between one symbol's occurrences sees them split that many ways. The
    positions sharing a key offset were enciphered by a single substitution, so taking every
    KEY_LENGTH'th one undoes the splitting without knowing the key. This is the step a cryptanalyst
    takes after recovering the period, and it separates a pattern that is absent from one this
    measure cannot see.
    """
    enciphered = repeatkey(seats, low, high, rng)
    return bytearray(
        enciphered[index] for index in range(0, len(enciphered), KEY_LENGTH)
    )


def repeatkey_of(length):
    """A Vigenere of a stated key length, for the sweep across key lengths.

    A key of length k sends one plaintext symbol to k ciphertext symbols by position, so the gaps
    between one symbol's occurrences are split k ways and the mean gap grows by k. The word boundary
    here sits near 5.3 symbols, so a key longer than that pushes the split gaps past the point where
    the measure can read them and the result says nothing about whether the pattern is still present.
    Sweeping k from 1 upward keeps the comparison inside the range the measure can see.
    """

    def apply(seats, low, high, rng):
        span = high - low + 1
        key = [rng.randrange(span) for _ in range(length)]
        return bytearray(
            low + ((value - low) + key[index % length]) % span
            for index, value in enumerate(seats)
        )

    return apply


def keystream_coset(seats, low, high, rng):
    """Every KEY_LENGTH'th symbol of a one time pad, as the control for the Vigenere coset.

    Subsampling removes the boundary regularity by itself, so a coset that recovers structure has to be
    checked against a cipher that provably holds none. Any signal appearing in both cosets belongs to
    the subsampling.
    """
    enciphered = keystream(seats, low, high, rng)
    return bytearray(
        enciphered[index] for index in range(0, len(enciphered), KEY_LENGTH)
    )


TRANSFORMS = (
    ("substitute", substitute),
    ("repeatkey_k8_coset", repeatkey_coset),
    ("keystream_coset", keystream_coset),
    ("repeatkey_k1", repeatkey_of(1)),
    ("repeatkey_k2", repeatkey_of(2)),
    ("repeatkey_k3", repeatkey_of(3)),
    ("repeatkey_k4", repeatkey_of(4)),
    ("repeatkey_k8", repeatkey_of(8)),
    ("repeatkey_k16", repeatkey_of(16)),
    ("keystream", keystream),
    ("counter", counter),
)


def main():
    if len(sys.argv) < 2:
        print("usage: transform_corpus.py source.sym")
        return 1

    source = sys.argv[1]
    if not os.path.isfile(source):
        print("no source at %s" % source)
        return 1

    seats = load_seats(source)
    low, high = seat_span(seats)
    stem = source[:-4] if source.endswith(".sym") else source

    for name, apply in TRANSFORMS:
        rng = random.Random(0xC10DE)
        out = apply(seats, low, high, rng)
        target = "%s_%s.sym" % (stem, name)
        with open(target, "wb") as handle:
            handle.write(bytes(out))
        print(
            "  %-42s %d symbols, seats %d to %d"
            % (os.path.basename(target), len(out), min(out), max(out))
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
