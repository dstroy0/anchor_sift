#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read the settings other people chose for their own languages, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/mine_ngram_orders.py [--take]
#
# The same problem measured here has been worked on for decades, language by language, by people building
# language identifiers and authorship attributors. Their conclusions are about their systems. Their
# settings are about their languages, and nobody writes a setting down as a finding.
#
# A character run length chosen for Chinese is a statement about how much a Chinese character carries. One
# chosen for Finnish is a statement about how long a Finnish word is. If those settings line up across
# many papers with what kind of language each is about, that is a constant nobody set out to publish, and
# it is evidence from outside this work, which almost nothing here has.
#
# The whole bibliography of the field is served as one file with abstracts, so what is mined is the
# abstracts: which languages a paper names, and what run length it reports. An abstract states a setting
# only when the authors thought it worth stating, which is a bias in what can be read and is stated here
# because it cannot be removed.
#
# Nothing is downloaded without --take, and the size is reported first.

import gzip
import io
import os
import re
import statistics
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(CORPORA, "acl_abstracts.bib.gz")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

SOURCE = "https://aclanthology.org/anthology+abstracts.bib.gz"

LANGUAGES = (
    "english", "german", "dutch", "swedish", "danish", "norwegian", "icelandic",
    "french", "spanish", "italian", "portuguese", "romanian", "catalan",
    "russian", "polish", "czech", "slovak", "bulgarian", "serbian", "croatian", "ukrainian",
    "finnish", "estonian", "hungarian",
    "turkish", "arabic", "hebrew", "persian", "urdu", "hindi", "bengali",
    "tamil", "telugu", "kannada", "malayalam",
    "chinese", "japanese", "korean", "vietnamese", "thai", "indonesian", "malay",
    "greek", "basque", "welsh", "irish", "swahili", "amharic", "zulu", "xhosa",
)

# How a run length gets written down in an abstract. The digit forms alone found fifteen papers of
# fifteen hundred, because almost nobody writes 2-gram or 3-gram: they write bigram and trigram, and
# generic n-gram with the letter n, which states no length at all.
ORDERS = (
    re.compile(r"\b(\d)\s*-?\s*gram", re.I),
    re.compile(r"\bn\s*=\s*(\d)\b", re.I),
    re.compile(r"\border\s+(\d)\b", re.I),
)
NAMED = (
    (re.compile(r"\bunigram", re.I), 1),
    (re.compile(r"\bbi[\s-]?gram", re.I), 2),
    (re.compile(r"\btri[\s-]?gram", re.I), 3),
    (re.compile(r"\b(?:quad|four)[\s-]?gram", re.I), 4),
    (re.compile(r"\bfive[\s-]?gram", re.I), 5),
)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    if not os.path.isfile(TARGET):
        request = urllib.request.Request(SOURCE, headers=AGENT, method="HEAD")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                size = int(response.headers.get("Content-Length", 0) or 0)
        except Exception as trouble:
            out.write("  could not ask its size: %s\n" % str(trouble)[:70])
            out.flush()
            return 1
        out.write("  the whole bibliography with abstracts is %.1f megabytes\n" % (size / 1e6))
        if "--take" not in sys.argv:
            out.write("  nothing downloaded. Run with --take to fetch it.\n")
            out.flush()
            return 0
        request = urllib.request.Request(SOURCE, headers=AGENT)
        with urllib.request.urlopen(request, timeout=900) as response:
            blob = response.read()
        with open(TARGET, "wb") as handle:
            handle.write(blob)
        out.write("  taken, %.1f megabytes\n" % (len(blob) / 1e6))

    with gzip.open(TARGET, "rt", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    entries = text.split("\n@")
    out.write("  %d entries in the bibliography\n\n" % len(entries))

    by_language = {}
    for entry in entries:
        lowered = entry.lower()
        if "gram" not in lowered:
            continue
        named = [language for language in LANGUAGES if language in lowered]
        # Only where one language is named, since a paper covering nine says nothing about any of them
        if len(named) != 1:
            continue
        found = []
        for pattern in ORDERS:
            found.extend(int(one) for one in pattern.findall(entry) if 1 <= int(one) <= 9)
        for pattern, order in NAMED:
            found.extend([order] * len(pattern.findall(entry)))
        if not found:
            continue
        by_language.setdefault(named[0], []).extend(found)

    ready = sorted((language for language in by_language if len(by_language[language]) >= 4),
                   key=lambda language: -len(by_language[language]))
    if not ready:
        out.write("  too few papers name one language and state a run length\n")
        out.flush()
        return 0

    out.write("  %-14s %-9s %-11s %s\n" % ("language", "papers", "run length", "what it is"))
    KIND = {
        "chinese": "logographic", "japanese": "mixed script", "korean": "featural",
        "finnish": "agglutinative", "estonian": "agglutinative", "hungarian": "agglutinative",
        "turkish": "agglutinative", "tamil": "agglutinative", "telugu": "agglutinative",
        "kannada": "agglutinative", "malayalam": "agglutinative", "swahili": "agglutinative",
        "zulu": "agglutinative", "arabic": "root and pattern", "hebrew": "root and pattern",
        "amharic": "root and pattern", "vietnamese": "isolating", "thai": "isolating",
        "english": "analytic", "chinese ": "logographic",
    }
    for language in ready:
        marks = by_language[language]
        out.write("  %-14s %-9d %-11s %s\n"
                  % (language, len(marks),
                     "%.2f, %.2f" % (statistics.fmean(marks), statistics.pstdev(marks)),
                     KIND.get(language, "fusional or other")))

    grouped = {}
    for language in ready:
        grouped.setdefault(KIND.get(language, "fusional or other"), []).extend(by_language[language])
    out.write("\n  %-22s %-9s %s\n" % ("kind of language", "readings", "run length"))
    for kind in sorted(grouped, key=lambda kind: statistics.fmean(grouped[kind])):
        marks = grouped[kind]
        if len(marks) >= 6:
            out.write("  %-22s %-9d %.2f\n" % (kind, len(marks), statistics.fmean(marks)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
