#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The Hamming(7,4) code, which rejects a channel's noise by selecting the codeword the parity checks
# allow.
#
#   Usage:  from sift.hamming import encode, syndrome_decode, nearest_decode
#
# Why this is a sift-stage object rather than a transform. A codeword must satisfy three parity checks;
# a received word that fails one or more cannot be a codeword, and each failed check is a necessary
# condition the true word met. Decoding does not reshape the word, it SELECTS: of the sixteen
# codewords, exactly one sits within a single bit-flip of the received word, and that one is chosen.
# It corrects by selecting the unique candidate the necessary conditions leave standing, which is the
# sift's move -- a subset of conditions narrowing a field of candidates to the ones that could be true
# -- carried into coding theory. The channel's noise is rejected not by measuring it but by asking
# which codeword could have produced what arrived.
#
# The error is not one-directional here the way a Bloom filter's or the anchor cascade's is, and the
# difference is worth stating. Those never lose a true item and only admit false ones. A code that
# corrects trades that away for a stronger guarantee inside its radius: within one flip it recovers the
# exact word, and the price is that TWO flips are corrected to the wrong word with the same confidence.
# That is the floor, and it is the Hamming bound, not a defect.
#
# TWO ROUTES, AND WHY THEY AGREE
#
# syndrome_decode computes which parity checks failed and reads their pattern as the position of the
# flipped bit. nearest_decode ignores parity entirely and finds the codeword at least Hamming distance
# from the received word. For a perfect code -- and Hamming(7,4) is one, every 7-bit word sits within
# one flip of exactly one codeword -- these are provably the same decoder. They agree on every input
# by a theorem rather than by luck. That makes their agreement a check on the two implementations, not
# evidence about the data, and a caller shows the check has teeth by breaking one and watching them
# split. Nothing here is bounded and nothing is imported: the code is fixed by its parity structure and
# the arithmetic is bit operations.

# Zero-based indices the three parity checks cover. Positions are the classic 1..7 layout with parity at
# 1, 2, 4; these are those positions less one.
CHECKS = ((0, 2, 4, 6), (1, 2, 5, 6), (3, 4, 5, 6))
DATA_INDICES = (2, 4, 5, 6)
PARITY_INDICES = (0, 1, 3)


def encode(data):
    """Four data bits as a seven-bit codeword, parity set for even parity over each check.

    `data` is four values, each 0 or 1. The data bits take their fixed positions and each parity bit is
    the exclusive-or of the data bits its check covers. Every check reads even on a clean codeword.
    """
    word = [0] * 7
    for slot, index in enumerate(DATA_INDICES):
        word[index] = data[slot] & 1
    for parity, check in zip(PARITY_INDICES, CHECKS):
        word[parity] = 0
        word[parity] = _xor(word, check)
    return word


def _xor(word, positions):
    total = 0
    for position in positions:
        total ^= word[position]
    return total


def _data_of(word):
    return [word[index] for index in DATA_INDICES]


def syndrome_decode(word):
    """Decode by the parity-check syndrome: the failed checks name the flipped bit, and it is flipped.

    The syndrome read as a binary number is the one-based position of the single bit that must flip to
    satisfy every check, or zero when the word already does. Returns the four data bits and the position
    corrected (0 for none). This is the necessary-condition route: it never enumerates a codeword, it
    asks which single flip makes every condition hold.
    """
    fixed = list(word)
    syndrome = 0
    for weight, check in zip((1, 2, 4), CHECKS):
        if _xor(fixed, check):
            syndrome += weight
    if syndrome:
        fixed[syndrome - 1] ^= 1
    return _data_of(fixed), syndrome


def nearest_decode(word):
    """Decode by nearest codeword: the codeword at least Hamming distance from the received word.

    Enumerates all sixteen codewords and keeps the closest. It reads no parity check. It shares no
    arithmetic with syndrome_decode; for this perfect code the two are the same decoder and must agree.
    Returns the four data bits and the position corrected (0 when the word was already a codeword).
    """
    best_distance = None
    best_data = None
    corrected = 0
    for value in range(16):
        data = [(value >> shift) & 1 for shift in range(4)]
        codeword = encode(data)
        distance = sum(1 for a, b in zip(codeword, word) if a != b)
        if (best_distance is None) or (distance < best_distance):
            best_distance = distance
            best_data = data
            corrected = next((index + 1 for index in range(7) if codeword[index] != word[index]), 0)
    return best_data, corrected
