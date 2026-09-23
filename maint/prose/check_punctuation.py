#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The whole smart-punctuation family, not the em dash alone.
#
#   Usage:  python maint/prose/check_punctuation.py [root ...]
#
# docs_check.py refuses U+2014 and stops there. The quote characters below are the substitutions a
# word processor, a web paste or a well-meaning editor makes, and each has an ASCII spelling that
# means the same thing. Those are worth reporting.
#
# This reports and does not refuse, for two reasons. docs_check.py owns the commit gate, and
# ASCII-ising a quote inside a quoted string or a test vector can change what a program means, so a
# person decides each site.

import os
import sys

# THE EN DASH IS NOT IN THIS TABLE, AND THE REASON IS THE WHOLE DESIGN OF THE CHECK.
#
# A first version listed it beside the em dash and advised writing a hyphen. That was wrong. This
# corpus's sixteen en dashes are all doing semantic work: numeric ranges, and author pairs. Writing
# Walsh-Hadamard tells a reader Hadamard might be a hyphenated surname; Walsh–Hadamard tells them it
# is two people. ASCII-ising it destroys information.
#
# The corpus settles the wider question too. docs/ carries 74 U+2212 minus signs and a working set of
# arrows, inequalities and set operators. It is a mathematics corpus using mathematical characters
# deliberately, so "unicode punctuation is suspect" would be a rule imported from somewhere else.
#
# The em dash is banned because it is a stylistic tell carrying no information. The en dash carries
# information. docs_check.py is right to refuse one and ignore the other, and this table follows it.
SUSPECT = {
    "—": ("em dash", "-"),
    "‘": ("left single quote", "'"),
    "’": ("right single quote", "'"),
    "“": ("left double quote", '"'),
    "”": ("right double quote", '"'),
}

READ = (".md", ".tex", ".py", ".c", ".h", ".cpp", ".cu", ".ps1", ".sh", ".tsv")

SKIP = {".git", "build", "__pycache__", "node_modules", "logs", "audit", "figures"}


def scan(path):
    findings = []
    # A dangling symlink appears in a directory listing and cannot be opened. os.walk reports the
    # name, so the first run of this crashed on tools/book/build_theory.sh, which is a broken link
    # that README.md and REPRODUCE.md both tell a reader to run. Reporting it beats dying on it.
    if not os.path.isfile(path):
        findings.append((0, "unreadable, a dangling link or a vanished file", "n/a", 0))
        return findings
    with open(path, encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle, 1):
            for character, (name, ascii_form) in SUSPECT.items():
                if character in line:
                    findings.append((number, name, ascii_form, line.count(character)))
    return findings


def main(argv):
    roots = argv[1:] or ["docs", "theory", "tools", "src", "maint", "examples", "README.md"]

    total = 0
    checked = 0
    for root in roots:
        if os.path.isfile(root):
            targets = [root]
        else:
            targets = []
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames if d not in SKIP]
                targets += [os.path.join(dirpath, f) for f in filenames if f.endswith(READ)]

        for path in sorted(targets):
            checked += 1
            for number, name, ascii_form, count in scan(path):
                total += count
                print("  %s:%d: %s (%d), write %s" % (
                    path.replace("\\", "/"), number, name, count, ascii_form))

    # Checking nothing is not passing, the same lesson docs_check.py records against itself.
    if checked == 0:
        print("  no files were read. Nothing was checked, so nothing passed.")
        return 2

    print("  %d file(s) checked, %d substitution(s)" % (checked, total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
