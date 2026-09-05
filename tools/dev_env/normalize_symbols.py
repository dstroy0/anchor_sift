#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Re-slice a corpus so one symbol occupies one byte, for the universals test in
# docs/research/anchor-sift.md.
#
# Section 4.10 says the symbol width is a choice, and the measurements in Sections 4.12 to 4.14 made
# that choice at 8 bits without justifying it. That is correct for a Latin script and wrong for a
# Greek one, where UTF-8 spends two bytes on a letter. A byte-level detector on such a text measures
# code units and reports a byte of a letter as the unit boundary.
#
#   Usage:  python tools/dev_env/normalize_symbols.py source target
#
# UTF-8 announces its own structure, so the width is read out of the bytes and not assumed. A lead
# byte in 0xC2 to 0xDF starts a two byte sequence and a continuation byte lies in 0x80 to 0xBF, which
# is checkable without knowing the language. The Greek alphabet is finite in every era it was written
# in, so the set of symbols is small enough to re-seat in a byte and nothing about the text is lost.
#
# Codepoints are assigned to bytes in order of first appearance. Frequency order would put the space
# at a rank this file already knows, and the point is that the detector finds the boundary on its own.

import os
import sys
from collections import Counter


def utf8_shape(raw):
    """Report the sequence widths present, from the bytes alone.

    Reads UTF-8's own framing instead of taking the encoding on trust, so a file that is not UTF-8
    is reported as such and not silently re-sliced into nonsense.
    """
    widths = Counter()
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

        widths[span] += 1
        index += span

    return widths, -1


def main():
    if len(sys.argv) < 3:
        print("usage: normalize_symbols.py source target")
        return 1

    source = sys.argv[1]
    target = sys.argv[2]

    if not os.path.isfile(source):
        print("no source at %s" % source)
        return 1

    with open(source, "rb") as handle:
        raw = handle.read()

    widths, bad = utf8_shape(raw)
    if widths is None:
        print("not valid UTF-8, first offending byte at %d" % bad)
        return 1

    total = sum(widths.values())
    shape = ", ".join(
        "%d byte %.1f%%" % (span, 100.0 * widths[span] / total)
        for span in sorted(widths)
    )
    print(
        "%s\n  %d symbols over %d bytes, %s"
        % (os.path.basename(source), total, len(raw), shape)
    )

    # A wrapped prose file puts a line ending at a more regular spacing than its own word boundary, and
    # Section 4.13.0 has that artifact winning the detector four times already, so the endings are folded
    # to a space to match what the byte path does before measuring.
    #
    # That is wrong for a source file. A programming language is insensitive to its own whitespace, so
    # every line break and every level of indentation in one exists because a person put it there for
    # another person to read. Folding it discards the authored layer and keeps the part the compiler
    # reads, which is the opposite of what these measurements are looking for. Pass keep-layout for any
    # corpus whose line structure was written instead of wrapped.
    text = raw.decode("utf-8")
    if "keep-layout" not in sys.argv[3:]:
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    alphabet = {}
    out = bytearray()

    for character in text:
        seat = alphabet.get(character)
        if seat is None:
            if len(alphabet) >= 255:
                print("  alphabet exceeds 255 symbols, cannot re-seat in a byte")
                return 1
            # Seats start at 1 so no symbol lands on 0x00 and gets read as a terminator downstream
            seat = len(alphabet) + 1
            alphabet[character] = seat
        out.append(seat)

    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as handle:
        handle.write(bytes(out))

    # Written out so a reported boundary byte can be read back as the character it stands for
    seats = sorted(alphabet.items(), key=lambda pair: pair[1])
    with open(target + ".alphabet", "w", encoding="utf-8") as handle:
        for character, seat in seats:
            handle.write("%02X\t%s\tU+%04X\n" % (seat, repr(character), ord(character)))

    print("  %d distinct symbols re-seated, one byte each" % len(alphabet))
    return 0


if __name__ == "__main__":
    sys.exit(main())
