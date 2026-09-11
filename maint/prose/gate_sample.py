#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Assemble one continuous sample of this project's prose, for a detector that takes pasted text.
#
#   python maint/prose/gate_sample.py --words 10000 theory
#   python maint/prose/gate_sample.py --words 4000 theory/millennium
#
# Writes build/gate/sample.txt and prints the word count, the character count, and every file that
# went into it with its share. The manifest is the point: a detector returns one number over the
# whole paste, and without a manifest nobody can say afterward what that number was measured on.
#
# The extraction is docs_check's, so this and the banned list read the same words. A .tex arrives
# with its markup blanked and a source file with its code blanked, and neither a path nor a label
# reaches the detector as though it were a sentence.
#
# Files are taken in the order given and truncated at a paragraph boundary when the budget runs out,
# so a sample is a set of whole paragraphs and never a sentence cut in half.
#
# The closed corpus and the private repositories never go in. A pasted sample is published the
# moment it is pasted, and the hand extractions are the papers' text and the speakers' words.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import docs_check

OUT = os.path.join(docs_check.REPOSITORY, "build", "gate", "sample.txt")

CLOSED = ("/private_repos/", "/salishan_corpus/", "/anchor_sift_citations/", "/no_replicate_/")


def closed(path):
    """Whether a path belongs to the closed corpus or a private repository beside this one."""
    walk = os.path.abspath(path).replace("\\", "/")
    return any(one in walk for one in CLOSED)


def paragraphs(path):
    """One file's prose as a list of paragraphs, each carrying the line it starts on."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    said = docs_check.prose_only(path, lines)
    held = []
    for text, where in docs_check.runs(said):
        text = " ".join(text.split())
        if len(text.split()) >= 12:
            held.append((where[0], text))
    return held


def main():
    argv = sys.argv[1:]
    budget = 10000
    if "--words" in argv:
        at = argv.index("--words")
        if (at + 1) >= len(argv):
            raise SystemExit("  gate_sample: --words wants a count")
        budget = int(argv[at + 1])

    skip = {"--words", str(budget)}
    named = [one for one in argv if (one not in skip) and not one.startswith("-")]
    if not named:
        raise SystemExit("  gate_sample: name a file or a directory")

    roots = [one if os.path.exists(one) else os.path.join(docs_check.REPOSITORY, one)
             for one in named]

    held = []
    manifest = []
    words = 0
    refused = 0
    # Not sorted. The order given is the order taken, because the caller put the prose they most
    # want read at the front and a sort would spend the budget alphabetically instead.
    for path in docs_check.walk_markdown(roots):
        if closed(path):
            refused += 1
            continue
        if words >= budget:
            break
        took = 0
        for _line, text in paragraphs(path):
            count = len(text.split())
            if (words + count) > budget:
                break
            held.append(text)
            words += count
            took += count
        if took:
            manifest.append((os.path.relpath(path, docs_check.REPOSITORY).replace("\\", "/"), took))

    body = "\n\n".join(held)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(body)

    for name, took in manifest:
        print("  %6d words  %s" % (took, name))
    if refused:
        print("  %d file(s) held back, closed corpus" % refused)
    print("\n  %d words, %d characters, %d file(s)" % (words, len(body), len(manifest)))
    print("  %s" % os.path.relpath(OUT, docs_check.REPOSITORY).replace("\\", "/"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
