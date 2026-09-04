#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Separate what a language is from what it is written in, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/script_confound.py
#
# Grouping languages by which symbol follows which put Greek nearest Hebrew. Those two share no family, no
# contact worth the name and no vocabulary, and what they do share is being written in neither Latin nor
# Cyrillic. That is the script reaching the measure, and it sits inside a result reported as recovering
# language families, so it has to be measured and not noted.
#
# Writing the same text in Latin letters is the test. A transliteration keeps every sound and every word
# and changes only the symbols carrying them, so anything that moves was being carried by the script.
# Greek should leave Hebrew and go toward the languages it is related to. Russian and Serbian are
# transliterated too, since Cyrillic is a second script with several languages in it and they should stay
# together whichever alphabet they are written in.
#
# The mapping is the ordinary romanization, one letter to one or two, and it is approximate. What matters
# here is that it is the same text under different symbols, and no mapping error can move a language into
# its own family by accident.

import io
import os
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from language_tree import FAMILY
from web_alphabet import CAP, LEAST, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = 64
RECAST = ("greek", "russian", "serbian", "hebrew")

GREEK = {
    "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i", "θ": "th",
    "ι": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "π": "p",
    "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "y", "φ": "f", "χ": "ch", "ψ": "ps",
    "ω": "o",
}

CYRILLIC = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z",
    "и": "i", "й": "j", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p",
    "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch",
    "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    "ђ": "dj", "ј": "j", "љ": "lj", "њ": "nj", "ћ": "c", "џ": "dz",
}

HEBREW = {
    "א": "a", "ב": "b", "ג": "g", "ד": "d", "ה": "h", "ו": "v", "ז": "z", "ח": "ch",
    "ט": "t", "י": "y", "כ": "k", "ך": "k", "ל": "l", "מ": "m", "ם": "m", "נ": "n",
    "ן": "n", "ס": "s", "ע": "a", "פ": "p", "ף": "f", "צ": "ts", "ץ": "ts", "ק": "q",
    "ר": "r", "ש": "sh", "ת": "t",
}


def recast(text):
    """The same text written in Latin letters, sounds and words untouched."""
    # Accents stripped first so a Greek letter carrying one still finds its entry
    flattened = "".join(mark for mark in unicodedata.normalize("NFD", text)
                        if unicodedata.category(mark) != "Mn")
    out = []
    for symbol in flattened.lower():
        if symbol in GREEK:
            out.append(GREEK[symbol])
        elif symbol in CYRILLIC:
            out.append(CYRILLIC[symbol])
        elif symbol in HEBREW:
            out.append(HEBREW[symbol])
        else:
            out.append(symbol)
    return "".join(out)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    holding = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        values = web(text, RANKS)
        if values is not None:
            holding.setdefault(language, []).append(values)
        if language in RECAST:
            turned = web(recast(text), RANKS)
            if turned is not None:
                holding.setdefault(language + " in latin", []).append(turned)

    names = sorted(language for language in holding if len(holding[language]) >= 2)
    middles = {name: numpy.mean(numpy.stack(holding[name]), axis=0) for name in names}

    out.write("  %-22s %-20s %-11s %s\n" % ("language", "nearest", "distance", "family of nearest"))
    for name in names:
        marks = sorted((float(numpy.linalg.norm(middles[name] - middles[other])), other)
                       for other in names
                       if other != name and other.replace(" in latin", "") != name.replace(
                           " in latin", ""))
        if not marks:
            continue
        distance, nearest = marks[0]
        if name.replace(" in latin", "") in RECAST:
            out.write("  %-22s %-20s %-11.5f %s\n"
                      % (name, nearest, distance,
                         FAMILY.get(nearest.replace(" in latin", ""), "unknown")))

    out.write("\n  what the change of script was worth, in distance to a few fixed languages\n")
    out.write("  %-22s %-11s %-11s %-11s %s\n"
              % ("language", "to hebrew", "to german", "to italian", "to russian"))
    for name in names:
        base = name.replace(" in latin", "")
        if base not in RECAST:
            continue
        row = []
        for target in ("hebrew", "german", "italian", "russian"):
            if (target in middles) and (target != base):
                row.append("%.5f" % float(numpy.linalg.norm(middles[name] - middles[target])))
            else:
                row.append("itself")
        out.write("  %-22s %-11s %-11s %-11s %s\n" % (name, row[0], row[1], row[2], row[3]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
