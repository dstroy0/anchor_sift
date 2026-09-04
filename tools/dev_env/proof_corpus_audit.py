#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Proof of the posit that the content has to be printed and not only the statistic, from the posits
# section of docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/proof_corpus_audit.py
#
# Nine problems in this work were found by reading output and none by a statistic going out of range. Six
# were a format read as language, being line wrapping, publisher markup, a ruled separator, verse
# numbering, HTML fragments and line width moving an entropy constant. Three were a corpus holding
# something other than its label, German under Hungarian, English under Latin and Ethereum contracts
# under a fabrication format.
#
# The posit is a process rule, so the testable form is whether a check written once would have caught
# them. This is that check, run over every corpus on disk. It earns the posit if it flags the known
# problems, and it earns it twice if it flags something not yet noticed.

import collections
import io
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
WORD = re.compile(r"[^\W\d_]+", re.UNICODE)

# Markers that a corpus carries something besides what it claims
CONTAMINATION = (
    ("gutenberg boilerplate", re.compile(r"PROJECT GUTENBERG", re.IGNORECASE)),
    ("html markup", re.compile(r"</(p|pre|div|body|html|br)>", re.IGNORECASE)),
    ("base64 blob", re.compile(r"[A-Za-z0-9+/]{120,}={0,2}")),
)

# Commonest words, which identify a language well enough to catch a swap
FINGERPRINTS = {
    "english": ("the", "and", "of", "to", "in"),
    "german": ("und", "die", "der", "das", "ist"),
    "french": ("de", "la", "et", "le", "les"),
    "spanish": ("que", "de", "la", "en", "el"),
    "italian": ("di", "che", "il", "la", "per"),
    "portuguese": ("de", "que", "os", "para", "com"),
    "finnish": ("ja", "on", "ei", "se", "niin"),
    "greek": ("και", "του", "την", "της", "στο"),
    "latin": ("et", "in", "est", "non", "cum"),
}

# A language whose name appears in a corpus name, so a swap can be reported by name
NAMED = tuple(FINGERPRINTS)


def wrapped(text):
    """Whether the lines look set to a fixed width, which is a publisher and not an author."""
    lengths = [len(line) for line in text.splitlines() if line.strip()]
    if len(lengths) < 200:
        return None
    spread = statistics.pstdev(lengths)
    middle = statistics.median(lengths)
    return middle, spread


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    flagged = 0
    seen = 0

    for name in sorted(os.listdir(CORPORA)):
        if not name.endswith(".txt"):
            continue
        path = os.path.join(CORPORA, name)
        if os.path.getsize(path) < 40000:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        seen += 1
        stem = name[:-4].lower()
        notes = []

        for label, pattern in CONTAMINATION:
            if pattern.search(text):
                notes.append(label)

        shape = wrapped(text)
        if shape is not None:
            middle, spread = shape
            # A wrapped file holds a tight band of line lengths just under its margin
            if (55 <= middle <= 80) and (spread < 18):
                notes.append("line wrapped at %d" % middle)

        counts = collections.Counter(WORD.findall(text.lower()))
        top = {word for word, _ in counts.most_common(40)}
        claimed = [key for key in NAMED if key in stem]
        if claimed:
            want = FINGERPRINTS[claimed[0]]
            hits = sum(1 for word in want if word in top)
            if hits < 2:
                best = max(FINGERPRINTS,
                           key=lambda key: sum(1 for word in FINGERPRINTS[key] if word in top))
                score = sum(1 for word in FINGERPRINTS[best] if word in top)
                if score >= 3:
                    notes.append("claims %s, looks %s" % (claimed[0], best))
                else:
                    notes.append("claims %s, matches no fingerprint" % claimed[0])

        if notes:
            flagged += 1
            out.write("  %-34s %s\n" % (name[:-4][:34], "; ".join(notes)))

    out.write("\n  %d of %d corpora flagged\n" % (flagged, seen))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
