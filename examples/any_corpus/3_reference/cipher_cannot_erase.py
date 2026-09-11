#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-3-001
#
# A cipher cannot remove what this measure reads unless its key is as long as the message.
#
#   Usage:  python examples/any_corpus/3_reference/cipher_cannot_erase.py corpus.sym
#
# Four operations, graded by how much they remove. A substitution renames the symbols and moves
# nothing. A reading of where symbols fall has to come back identical. A repeating key of length
# k sends one plaintext symbol to k ciphertext symbols by position, so the gaps are split k ways and
# the whole ciphertext can look memoryless. Taking every k-th symbol undoes the splitting without
# knowing the key, since each coset was enciphered by a single substitution, and averaging all k
# cosets loses no length at all because every symbol lands in exactly one of them.
#
# A pseudorandom addend as long as the message is the only operation here that erases anything.
#
# The counter is not a cipher and is the case that matters for the limit. It is perfectly regular
# and nobody produced it, so it is what a claim about human production has to answer for.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.dispersion import rare_half  # noqa: E402
from reference.ciphers import coset, counter, keystream, repeat_key, substitute  # noqa: E402

KEY_LENGTHS = (1, 2, 3, 4, 8, 16)


def show(out, label, value, note=""):
    if value is None:
        out.write("  %-28s %-10s %s\n" % (label, "none", "too few symbols cleared the floor"))
        return
    out.write("  %-28s %-10.4f %s\n" % (label, value, note))


def main():
    if len(sys.argv) < 2:
        print("usage: cipher_cannot_erase.py corpus.sym")
        return 1

    path = sys.argv[1]
    if not os.path.isfile(path):
        print("no corpus at %s" % path)
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())

    out.write("%s, %d symbols\n\n" % (os.path.basename(path), len(seats)))
    out.write("  %-28s %-10s %s\n" % ("transform", "rare half", "what it did"))

    show(out, "plaintext", rare_half(seats))
    show(out, "substitution", rare_half(substitute(seats)),
         "renames the symbols and moves nothing")

    for length in KEY_LENGTHS:
        enciphered = repeat_key(seats, length)
        show(out, "repeating key of %d" % length, rare_half(enciphered),
             "gaps split %d ways" % length)

    out.write("\n  the cosets of a repeating key of 8, which undo the splitting\n")
    enciphered = repeat_key(seats, 8)
    live = [rare_half(coset(enciphered, 8, offset)) for offset in range(8)]
    dead = [rare_half(coset(seats, 8, offset)) for offset in range(8)]
    live = [one for one in live if one is not None]
    dead = [one for one in dead if one is not None]
    if live and dead:
        out.write("  %-28s %.4f\n" % ("over 8 ciphertext cosets", sum(live) / len(live)))
        out.write("  %-28s %.4f\n" % ("over 8 plaintext cosets", sum(dead) / len(dead)))
        out.write("  the two agree because each coset was enciphered by one substitution\n")

    out.write("\n")
    show(out, "one time pad", rare_half(keystream(seats)),
         "the only one that erases anything")
    show(out, "counter", rare_half(counter(seats)),
         "no dispersion at all, so the measure declines to divide by it")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
