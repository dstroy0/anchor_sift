#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Reversible mappings that remove a stated amount of structure and leave the rest.
#
#   Usage:  from reference.ciphers import substitute, repeat_key, keystream, counter
#
# A shuffle deletes every arrangement at once. These delete a named part of one, and that gives a
# graded background instead of a single floor.
#
# What each one removes. A substitution renames the symbols and moves nothing, so anything reading
# where symbols fall has to return the same value to the last decimal. A repeating key of length k
# sends one plaintext symbol to k ciphertext symbols by position, and a measure reading gaps then
# sees them split k ways. A full length pseudorandom addend destroys the positions outright and is
# the only mapping here that erases anything. A counter carries no text at all and is perfectly
# regular. That last case bounds the limit: it is structured and nobody produced it.
#
# The measured answer is that a cipher cannot remove what this reads unless it spends key equal to
# the message. A substitution reproduces the boundary dispersion to four decimals. A repeating key
# of length 8 leaves a corpus that looks memoryless read whole, and splitting it at stride 8 and
# averaging the cosets returns the plaintext value exactly, since each coset was enciphered by one
# substitution. The one time pad reads 1.004 whole and 1.004 under every coset scan.
#
# Every mapping keeps its output inside the seat range the source uses, so the same measurement
# path reads it and nothing is compared across a change of representation.

import random

# Key length for the plain repeating key cipher.
KEY_LENGTH = 8


def seat_span(seats):
    """Lowest and highest seat in use, letting a mapping stay inside the source's own range."""
    return min(seats), max(seats)


def substitute(seats, seed=0xC10DE):
    """One fixed permutation of the seats, which is a monoalphabetic cipher.

    Relabeling cannot change how often a word recurs or where it falls, so this is the mapping a
    position reading has to be blind to. It is also the check that caught a real defect: the ranking
    sorts symbols by count, so symbols sharing a count are ordered by their label, and relabeling
    moves which of them falls in the rare half. Small, and real.
    """
    low, high = seat_span(seats)
    span = high - low + 1
    table = list(range(span))
    random.Random(seed).shuffle(table)
    return bytearray(low + table[value - low] for value in seats)


def repeat_key(seats, length=KEY_LENGTH, seed=0xC10DE):
    """A key of `length` seats added under modular arithmetic, which is a Vigenere.

    The gaps between one symbol's occurrences are split `length` ways and the mean gap grows by that
    factor. A word boundary sits near 5.3 symbols. A key longer than that pushes the split gaps past
    where the measure can read them, and a result there says nothing about whether the pattern
    survived.
    """
    low, high = seat_span(seats)
    span = high - low + 1
    rng = random.Random(seed)
    key = [rng.randrange(span) for _ in range(length)]
    return bytearray(low + ((value - low) + key[index % length]) % span
                     for index, value in enumerate(seats))


def keystream(seats, seed=0xC10DE):
    """A pseudorandom addend as long as the message. A one time pad has exactly this shape."""
    low, high = seat_span(seats)
    span = high - low + 1
    rng = random.Random(seed)
    return bytearray(low + ((value - low) + rng.randrange(span)) % span for value in seats)


def counter(seats, seed=0xC10DE):
    """A deterministic ramp carrying no text, which is structure nobody produced.

    Here for the limit and not for the cipher. The surviving measure reports that a corpus is not
    memoryless, and this is a corpus that is not memoryless and had no author, so it is the case a
    claim about human production has to answer for. The seed is accepted and ignored so every
    mapping in this module shares one signature.
    """
    del seed
    low, high = seat_span(seats)
    span = high - low + 1
    return bytearray(low + (index % span) for index in range(len(seats)))


def coset(seats, stride, offset=0):
    """Every `stride`-th symbol from `offset`, which is one alphabet of a repeating key.

    The positions sharing a key offset were enciphered by a single substitution, so taking every
    stride-th one undoes the splitting without knowing the key. This is the step a cryptanalyst
    takes after recovering the period.

    Subsampling removes the boundary regularity by itself. Any coset that recovers structure has to
    be checked against a cipher that provably holds none, since a signal appearing in both belongs
    to the subsampling and not to the key.
    """
    return bytearray(seats[offset::stride])
