#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Count choices between semantically identical instruction sequences, for the symbol width discussion in
# Section 4.10 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/asm_idiom.py corpus.txt [more.txt ...]
#
# Every other measurement of a human layer here has to argue that some channel is not machine required.
# Assembly needs no such argument. An instruction set states exactly what each encoding does, and for
# several operations more than one encoding does the identical thing: zeroing a register, testing it
# against zero, adding one to it. The processor cannot tell which was written. So the ratio between them
# carries no machine information whatever, and whatever it is measures a convention held by whoever or
# whatever emitted the text.
#
# Comments are the same case taken to the limit, since an assembler discards them entirely.

import io
import os
import re
import sys

# Pairs that compute the same thing. The first is the idiom, the second the direct form
EQUIVALENT = (
    ("zero a register", r"\bxor\s+(\w+)\s*,\s*\1\b", r"\bmov\s+\w+\s*,\s*0\b"),
    ("test against zero", r"\btest\s+(\w+)\s*,\s*\1\b", r"\bcmp\s+\w+\s*,\s*0\b"),
    ("add one", r"\binc\s+\w+", r"\badd\s+\w+\s*,\s*1\b"),
    ("subtract one", r"\bdec\s+\w+", r"\bsub\s+\w+\s*,\s*1\b"),
)


def main():
    if len(sys.argv) < 2:
        print("usage: asm_idiom.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read().lower()

        lines = text.splitlines()
        commented = sum(1 for line in lines if ";" in line or line.lstrip().startswith("#"))

        out.write("%s, %d lines\n" % (os.path.basename(path), len(lines)))
        out.write("  %-20s %-9s %-9s %s\n" % ("choice", "idiom", "direct", "idiom share"))

        for label, idiom, direct in EQUIVALENT:
            first = len(re.findall(idiom, text))
            second = len(re.findall(direct, text))
            if (first + second) < 10:
                continue
            out.write("  %-20s %-9d %-9d %.3f\n"
                      % (label, first, second, first / float(first + second)))

        out.write("  %-20s %-9d %-9s %.3f\n"
                  % ("lines commented", commented, "", commented / float(max(1, len(lines)))))

        # Which instruction set this is, so a pattern that finds nothing can be told apart from a
        # dialect the patterns were never written for
        seen = {}
        for line in lines:
            stripped = line.strip()
            if (not stripped) or stripped.startswith((".", "#", ";", "/")) or stripped.endswith(":"):
                continue
            token = re.split(r"[\s,]+", stripped)[0]
            if re.fullmatch(r"[a-z][a-z0-9.]{1,9}", token):
                seen[token] = seen.get(token, 0) + 1
        top = sorted(seen.items(), key=lambda pair: -pair[1])[:12]
        out.write("  mnemonics: %s\n" % ", ".join("%s %d" % pair for pair in top))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
