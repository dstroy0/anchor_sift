#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One symbol in one place, whatever the encoding underneath was doing.
#
#   Usage:  from representation.symbols import utf8_shape, reseat
#
# The symbol width is a choice and it is not free. Measurements were taken at eight bits without
# that being justified, which is correct for a Latin script and wrong for a Greek one, where UTF-8
# spends two bytes on a letter: 71.3 percent of a Greek text arrives as two byte sequences against
# 99.4 percent one byte for English. A byte level detector on Greek was measuring half a letter.
# Re-seating the 144 distinct Greek symbols one to a byte recovered the space as the boundary and
# put Greek inside the group on every universal, while moving English by 0.001.
#
# What the width costs, measured: the discrimination per bit read falls with width on every corpus.
# English gives 0.984 at one bit and 0.856 at eight, so the byte slice forfeits 15 percent and a
# sixteen bit symbol forfeits 40. Soundness is indifferent to it, since the proposition never
# mentions a width. What the width moves is cost.
#
# Seats are assigned in order of first appearance and not by frequency. Frequency order would put
# the space at a rank the caller already knows, and the point is that a detector finds the boundary
# on its own.

# The widest alphabet a byte can seat, leaving 0x00 free so nothing downstream reads a terminator.
SEATS_AVAILABLE = 255


def utf8_shape(raw):
    """The sequence widths present, read out of the bytes instead of taken on trust.

    Returns a count per width and -1, or (None, offset) where the bytes are not valid UTF-8. Reading
    the framing instead of assuming the encoding keeps a file that is not UTF-8 from being
    silently re-sliced into nonsense.
    """
    widths = {}
    index = 0

    while index < len(raw):
        lead = raw[index]
        if lead < 0x80:
            span = 1
        elif 0xC2 <= lead <= 0xDF:
            span = 2
        elif 0xE0 <= lead <= 0xEF:
            span = 3
        elif 0xF0 <= lead <= 0xF4:
            span = 4
        else:
            return None, index

        # Every byte after the lead has to be a continuation byte or the framing claim is false
        for step in range(1, span):
            if ((index + step) >= len(raw)) or ((raw[index + step] & 0xC0) != 0x80):
                return None, index

        widths[span] = widths.get(span, 0) + 1
        index += span

    return widths, -1


def reseat(text, keep_layout=False):
    """Every distinct character given one byte, in order of first appearance.

    Returns the seated bytes and the seating, letting a reported boundary byte be read back as the
    character it stands for.

    Line endings are folded unless keep_layout is set. Folding is right for prose, where a publisher
    chose the wrapping, and wrong for source, where a language ignores its own whitespace so every
    break exists because a person put it there. Folding source discards the authored layer and keeps
    what the compiler reads, the opposite of what these measurements look for. It moves H2 by 0.187
    bits.

    Raises ValueError where the text carries more distinct characters than a byte can seat.
    """
    if not keep_layout:
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")

    seating = {}
    out = bytearray()
    for character in text:
        seat = seating.get(character)
        if seat is None:
            if len(seating) >= SEATS_AVAILABLE:
                raise ValueError("alphabet exceeds %d symbols, cannot re-seat in a byte"
                                 % SEATS_AVAILABLE)
            # Seats start at 1 so no symbol lands on 0x00
            seat = len(seating) + 1
            seating[character] = seat
        out.append(seat)
    return out, seating
