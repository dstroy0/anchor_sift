#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find the characters and commands inside a document's math that break before the math is rendered.
#
#   Usage:  python tools/dev_env/math_hazards.py docs/research/anchor-sift-method.md [more.md]
#
# Markdown gets the first pass at the text and the math renderer gets the second, so anything that means
# something to markdown or to HTML is consumed before the formula is ever parsed. Three of these turned up
# in one paper and none of them reported the cause.
#
# A pair of asterisks in one block, as in \pi^{*} used twice, is read as emphasis and the LaTeX between
# them is rewritten. The error that surfaces complains about a brace, because the braces around the
# asterisks are what got eaten.
#
# A raw < is read as the start of a tag and swallows what follows it.
#
# A command the renderer does not carry throws instead of degrading. \operatorname is absent from some
# builds, \mathbb takes only uppercase letters so \mathbb{1} fails, and \mathfrak needs a font that is
# often not shipped.
#
# So the rule this checks is that a character with a meaning in markdown has to be written as a command:
# \ast for the asterisk, \lt and \gt for the angle brackets. Nothing here is repaired. It reports where to
# look, and a hit is a hazard rather than a proven failure, since which of these break depends on the
# renderer the reader happens to use.

import io
import os
import re
import sys

DISPLAY = re.compile(r"\$\$(.+?)\$\$", re.DOTALL)
INLINE = re.compile(r"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)")

# Each rule is written to fire only where the character actually breaks. A checker that reports a
# working formula gets ignored, and then it reports nothing. The first pass of this file flagged
# every \mathbb{E} and \mathbb{Z} in the tree, which are exactly what \mathbb accepts, and 17 of its
# 26 hits were formulas that render correctly.
CHECKS = (
    (re.compile(r"\\operatorname"),
     "\\operatorname is missing from some builds, use \\mathrm"),
    # Only a single uppercase letter is supported. \mathbb{1} and \mathbb{ab} throw.
    (re.compile(r"\\mathbb\{(?![A-Z]\})[^}]*\}"),
     "\\mathbb takes one uppercase letter, this argument is something else"),
    (re.compile(r"\\mathfrak"),
     "\\mathfrak needs a font that is often not shipped, use \\mathcal"),
    (re.compile(r"(?<!\\)\*"),
     "a literal asterisk is read as emphasis, use \\ast"),
    # A tag opener is < followed by a letter or a slash. A < with space around it is arithmetic.
    (re.compile(r"(?<!\\)<[A-Za-z/]"),
     "< followed by a letter is read as a tag opener, use \\lt"),
    # A > only takes on a meaning at the start of a line, where it opens a blockquote
    (re.compile(r"^\s*>", re.MULTILINE),
     "> at the start of a line opens a blockquote, use \\gt or move it"),
    # KaTeX has no align environment. aligned works inside a display block.
    (re.compile(r"\\begin\{(align|eqnarray|gather)\}"),
     "that environment is not in KaTeX, use aligned inside the display block"),
    # A row separator outside an environment has nothing to separate
    (re.compile(r"\\\\(?!\s*\\end)"),
     "a \\\\ row break needs an environment such as aligned around it"),
)

def odd_inline_dollars(line):
    """Whether a line leaves an inline formula unclosed.

    The display delimiters are removed first. A display block legitimately opens on one line and
    closes on another, so counting every dollar sign reports each of those as unclosed.
    """
    without_display = line.replace("$$", "")
    return (len(re.findall(r"(?<!\\)\$", without_display)) % 2) == 1


# Checks that read a whole line rather than one math span
LINE_CHECKS = (
    (odd_inline_dollars,
     "an odd number of inline $ on the line, so a formula is left unclosed"),
)


def unescaped_braces(text):
    """Open and close counts, with the escaped literal braces taken out first."""
    plain = re.sub(r"\\[{}]", "", text)
    return plain.count("{"), plain.count("}")


def line_of(text, at):
    """Which line an offset falls on."""
    return text.count("\n", 0, at) + 1


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if len(sys.argv) < 2:
        out.write("  usage: math_hazards.py <document.md> [more.md]\n")
        out.flush()
        return 1

    total = 0
    for name in sys.argv[1:]:
        if not os.path.isfile(name):
            out.write("\n  %s\n    no such file\n" % name)
            continue
        with open(name, encoding="utf-8", errors="replace") as handle:
            whole = handle.read()

        found = []
        for pattern, kind in ((DISPLAY, "display"), (INLINE, "inline")):
            for span in pattern.finditer(whole):
                body = span.group(1)
                where = line_of(whole, span.start())
                opens, closes = unescaped_braces(body)
                if opens != closes:
                    found.append((where, kind, "braces %d open %d close" % (opens, closes),
                                  body.strip()[:70]))
                for check, complaint in CHECKS:
                    hit = check.search(body)
                    if not hit:
                        continue
                    # An asterisk is only eaten when a second one closes the emphasis
                    if complaint.endswith("use \\ast") and body.count("*") < 2:
                        continue
                    found.append((where, kind, complaint, body.strip()[:70]))

        for where, line in enumerate(whole.splitlines(), 1):
            for check, complaint in LINE_CHECKS:
                if check(line):
                    found.append((where, "line", complaint, line.strip()[:70]))

        out.write("\n  %s\n" % name)
        if not found:
            out.write("    no hazards\n")
            continue
        for where, kind, complaint, snippet in sorted(found):
            out.write("    line %-5d %-8s %s\n" % (where, kind, complaint))
            out.write("      %s\n" % snippet)
            total += 1

    out.write("\n  %d hazard(s). A hit is a hazard and not a proven failure: which of these\n"
              % total)
    out.write("  break depends on the renderer the reader happens to use\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
