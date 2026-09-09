#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Re-slice a text so one symbol occupies one byte, and see what the old slice was measuring.
#
#   Usage:  python examples/any_corpus/1_represent/one_symbol_one_byte.py source target [keep-layout]
#
# The symbol width was chosen at eight bits without that being justified. It is correct for a Latin
# script and wrong for a Greek one, where UTF-8 spends two bytes on a letter: 71.3 percent of a Greek
# text arrives as two byte sequences against 99.4 percent one byte for English. A byte level
# detector there was measuring half a letter.
#
# Re-seating the 144 distinct Greek symbols one to a byte recovered the space as the boundary and put
# Greek inside the group on every universal, while moving English by 0.001. So the re-slicing is not
# doing the work itself.
#
# The framing is read out of the bytes and never taken on trust. A file that is not UTF-8 is
# reported as such instead of being silently re-sliced into nonsense.
#
# Pass keep-layout for a corpus whose line structure was written instead of wrapped. A programming
# language ignores its own whitespace, so every break in one exists because a person put it there,
# and folding it discards the authored layer and moves H2 by 0.187 bits.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.entropy import collision_entropy  # noqa: E402
from representation.text.symbols import reseat, utf8_shape  # noqa: E402


def main():
    if len(sys.argv) < 3:
        print("usage: one_symbol_one_byte.py source target [keep-layout]")
        return 1

    source = sys.argv[1]
    target = sys.argv[2]
    keep_layout = "keep-layout" in sys.argv[3:]

    if not os.path.isfile(source):
        print("no source at %s" % source)
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    with open(source, "rb") as handle:
        raw = handle.read()

    widths, bad = utf8_shape(raw)
    if widths is None:
        out.write("  not valid UTF-8, first offending byte at %d\n" % bad)
        out.flush()
        return 1

    total = sum(widths.values())
    shape = ", ".join("%d byte %.1f%%" % (span, 100.0 * widths[span] / total)
                      for span in sorted(widths))
    out.write("%s\n  %d symbols over %d bytes, %s\n"
              % (os.path.basename(source), total, len(raw), shape))

    try:
        seated, seating = reseat(raw.decode("utf-8"), keep_layout=keep_layout)
    except ValueError as trouble:
        out.write("  %s\n" % trouble)
        out.flush()
        return 1

    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    with open(target, "wb") as handle:
        handle.write(bytes(seated))

    # Written out to let a reported boundary byte be read back as the character it stands for
    with open(target + ".alphabet", "w", encoding="utf-8") as handle:
        for character, seat in sorted(seating.items(), key=lambda pair: pair[1]):
            handle.write("%02X\t%s\tU+%04X\n" % (seat, repr(character), ord(character)))

    before = collision_entropy(raw)[0]
    after = collision_entropy(bytes(seated))[0]
    out.write("  %d distinct symbols re-seated, one byte each\n" % len(seating))
    out.write("  H2 over the raw bytes %.3f, over the re-seated symbols %.3f, moved %.3f\n"
              % (before, after, after - before))
    out.write("  line endings %s\n" % ("kept" if keep_layout else "folded to spaces"))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
