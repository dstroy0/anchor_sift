#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Two questions about prior work, asked of the books before they are published.
#
#   python maint/citations/prior_works.py                 report both
#   python maint/citations/prior_works.py --claims        priority claims only
#   python maint/citations/prior_works.py --quotations    quoted passages only
#   python maint/citations/prior_works.py <path> ...      named files or directories
#
# WHAT THIS ASKS THAT citations.py NEXT DOOR DOES NOT
#
# citations.py registers the mathematics this work rests on and refuses a commit while a name is
# used without an author, a year, a title and an identifier. It answers whether a source that IS
# named has been written down properly.
#
# This asks the two questions that survive a clean registry.
#
#   1. A PRIORITY CLAIM WITH NOTHING BEHIND IT. A sentence saying something here is new, first,
#      unprecedented, or absent from the literature is a claim about everybody else's work. It is
#      the one kind of claim this tree cannot check from inside itself, because the evidence for it
#      sits in journals nobody here has read. Either a reference stands near it, or the sentence
#      says plainly that the reading has not been done.
#
#   2. A QUOTED PASSAGE WITH NO ATTRIBUTION. Somebody else's sentences, set in quotation marks,
#      carried in a book that is about to be posted publicly under a license. Unattributed, it is
#      either a copyright problem or a note that was filed in the wrong place. docs_check already
#      finds these spans, to EXEMPT them from its own register checks. Nothing has been asking
#      whether they are attributed.
#
# THE MODEL FOR A GOOD PRIORITY CLAIM IS ALREADY IN THE TREE
#
# theory/crystallography/chapters/chapter_whose_result.tex says an autocorrelation of density in a
# crystal is very unlikely to be new, that the reasonable prior is that it has a name and a
# literature behind it, and that nobody here has done the reading. That paragraph asserts no
# priority and states its own gap, so it needs no citation and passes. Every DISCLAIMER pattern
# below was read off it.
#
# IT REPORTS. A PERSON DECIDES EACH SITE.
#
# No regex can tell a priority claim from a description of somebody else's priority. "no
# narrowed-width formula was found in the literature" is a claim this work is making; "Handschuh
# and Gilbert show" is a claim about theirs, and the second is what a citation looks like. The
# finding names the line and the reader opens it. Exit status is the count, so a pipeline can fail
# on it without a flag, and nothing here refuses a commit on its own.

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

# The books and the pages. src/ and maint/ are excluded: a comment claiming a method is new is
# worth catching too, but the first pass is aimed at what gets posted.
DEFAULT_ROOTS = ("theory", "docs", "README.md")
CHECKED = (".tex", ".md")
SKIP_DIRS = (".git", "build", "site", "deps", "__pycache__", "fixtures")

# How far from a claim a reference may sit and still count as supporting it. A citation in the
# sentence before or after is supporting; one three paragraphs away is not, and counting it would
# let a single reference clear a whole chapter.
WINDOW = 2

# Asserting that something here has not been done before. Each is bounded so it fires on the claim
# and not on a description of somebody else's result: "is new" and never "renew", "first to" and
# never "first, the".
CLAIMS = (
    (r"\b(is|are|was|were) (entirely |completely |genuinely |apparently )?new\b", "asserts newness"),
    (r"\b(the )?first (to|known|published|reported|such)\b", "asserts precedence"),
    (r"\bno (prior|previous|earlier|existing) (work|result|method|paper|formula|treatment)\b",
     "asserts nothing prior exists"),
    (r"\bnot (found|present|reported|described|documented) in the literature\b",
     "asserts absence from the literature"),
    (r"\b(unprecedented|novel|hitherto|heretofore)\b", "asserts novelty"),
    (r"\bnobody (has|had) (ever )?(done|tried|measured|published|reported)\b",
     "asserts nobody has done it"),
    (r"\bfor the first time\b", "asserts a first"),
    (r"\bno (one|body) else\b", "asserts exclusivity"),
    (r"\bhas never been (done|tried|measured|published|reported|attempted)\b",
     "asserts it has never been done"),
    (r"\bno such (formula|method|result|proof|bound|construction) (exists|is known|was found)\b",
     "asserts no such thing exists"),
)

# What makes a priority claim honest without a reference: saying the reading has not been done.
# These are read off the crystallography chapter, which is the worked example.
DISCLAIMERS = (
    r"\bhas not been done\b",
    r"\bnobody here has\b",
    r"\bno priority is claimed\b",
    r"\bunlikely to be new\b",
    r"\balmost certainly been here first\b",
    r"\bthe reading is (missing|what is missing)\b",
    r"\bnot searched\b",
    r"\bno literature (search|review) (has been|was) (done|made|carried out)\b",
    r"\bis a rediscovery\b",
    r"\bwhere that is known the precedent is named\b",
)

# What a reference looks like in these books: a LaTeX citation, a bracketed key, or a surname
# standing against a year, which is the shape citations.py's second pass reads.
REFERENCES = (
    r"\\(cite|citep|citet|footcite|autocite)\w*\s*[\[{]",
    r"\\ref\s*\{",
    r"\[[A-Z][A-Za-z]+\d{2,4}\]",
    r"\b[A-Z][a-z]+(\s+(and|&)\s+[A-Z][a-z]+)?\s*\(?\b(1[89]\d{2}|20[0-5]\d)\b",
)

# A run of somebody else's sentences in quotation marks. The floor is high on purpose: a quoted
# word or a scare quote is not a passage, and the register checks next door use the same shape at
# the same floor.
PASSAGE = re.compile(r"[\"\u201c][^\"\u201c\u201d]{60,600}[\"\u201d]")

# A quotation mark holding a path, an identifier, or a single term rather than a sentence. A
# passage has to read as prose, so it needs whitespace and a finite verb somewhere in it.
LOOKS_LIKE_PROSE = re.compile(r"\s\w+\s")


def texts(roots):
    """Every checked file under the given roots, taking a file argument as itself."""
    held = []
    for root in roots:
        full = root if os.path.isabs(root) else os.path.join(ROOT, root)
        if os.path.isfile(full):
            if full.endswith(CHECKED):
                held.append(full)
            continue
        for where, dirs, names in os.walk(full):
            dirs[:] = [one for one in dirs if one not in SKIP_DIRS]
            held.extend(os.path.join(where, name) for name in sorted(names)
                        if name.endswith(CHECKED))
    return sorted(held)


def near(lines, at, patterns):
    """Whether any pattern matches within WINDOW lines either side of `at`, inclusive."""
    low = max(0, at - WINDOW)
    high = min(len(lines), at + WINDOW + 1)
    window = " ".join(lines[low:high])
    return any(re.search(one, window) for one in patterns)


def priority_claims(path, lines):
    """Every sentence asserting precedence with no reference and no disclaimer beside it."""
    found = []
    for at, line in enumerate(lines):
        if line.lstrip().startswith("%"):
            continue
        for pattern, what in CLAIMS:
            hit = re.search(pattern, line, re.IGNORECASE)
            if not hit:
                continue
            if near(lines, at, DISCLAIMERS):
                continue
            if near(lines, at, REFERENCES):
                continue
            found.append((at + 1, "%s, with no reference and no disclaimer: %r"
                          % (what, hit.group(0))))
    return found


def quotations(path, lines):
    """Every quoted passage carrying no attribution within WINDOW lines."""
    found = []
    for at, line in enumerate(lines):
        if line.lstrip().startswith("%"):
            continue
        for hit in PASSAGE.finditer(line):
            body = hit.group(0)
            if not LOOKS_LIKE_PROSE.search(body):
                continue
            if near(lines, at, REFERENCES):
                continue
            opening = " ".join(body.split())[:56]
            found.append((at + 1, "quoted passage with no attribution nearby: %s..." % opening))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    wanted = [one for one in sys.argv[1:] if not one.startswith("-")]
    claims_only = "--claims" in sys.argv
    quotes_only = "--quotations" in sys.argv

    roots = wanted or list(DEFAULT_ROOTS)
    held = texts(roots)
    if not held:
        out.write("  no files were read. Nothing was checked, so nothing passed.\n")
        for one in roots:
            out.write("    %s\n" % one)
        out.flush()
        return 2

    claims = 0
    quoted = 0
    for path in held:
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        shown = os.path.relpath(path, ROOT).replace("\\", "/")

        if not quotes_only:
            for at, what in priority_claims(path, lines):
                out.write("  CLAIM %s:%d: %s\n" % (shown, at, what))
                claims += 1
        if not claims_only:
            for at, what in quotations(path, lines):
                out.write("  QUOTE %s:%d: %s\n" % (shown, at, what))
                quoted += 1

    out.write("  %d file(s) read, %d priority claim(s) unsupported, %d quotation(s) unattributed\n"
              % (len(held), claims, quoted))
    out.write("  A person reads these. Neither count is a verdict, and a claim about somebody\n")
    out.write("  else's priority is a citation and not a finding.\n")
    out.flush()
    return claims + quoted


if __name__ == "__main__":
    raise SystemExit(main())
