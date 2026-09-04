#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The one way a corpus is read here, with the purity check built into it, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  from corpus_gate import load, report_on
#
# Twice in this work a file was measured for hours before anyone looked at what was in it. A Greek to
# English lexicon, 21.2 percent Greek and 78.8 percent Latin, stood inside every Greek reading. Seven
# Indic files carrying untranslated English between 1.8 and 30.0 percent inverted a whole language family:
# the pair that separated most recently read as the widest apart of seven, and three of four languages had
# an outsider nearest them. Thirty percent contamination did not give a thirty percent error, it gave the
# opposite of the answer, and three explanations were built on top of it before the input was examined.
#
# A check that has to be remembered does not run. The tool that catches this was written after the lexicon
# and recorded as worth having, and it was not run on the next seven corpora fetched. So it lives here, in
# the only path that opens a corpus, and every reading gets it whether or not anyone thought to ask.
#
# The reason a measurement cannot catch this itself is that it has no idea what its input should look
# like. A distribution of characters is a distribution of characters, and English inside a Telugu file is
# simply part of what Telugu looks like as far as any reading here is concerned. The judgement has to come
# from outside the measurement, and here it comes from Unicode, which knows Latin from Telugu without
# consulting anything this work computed.
#
# What Unicode cannot judge is who said a text, or when. The speech attributed to Chief Seattle is fluent
# monolingual English and passes this gate at any floor it can be given. It reaches a reader through
# Lushootseed, then Chinook Jargon, then English at the podium, then notes published thirty-three years
# later that their author called incomplete, then a 1972 film script that supplied most of what is quoted
# from it now. None of that is in the characters. A pass here means the file is written in the writing it
# claims and means nothing at all about whether it is what it claims to be, and the material most worth
# having is the material where that difference is largest.
#
# Nothing is done silently. A caller says whether foreign matter should be cut out or should stop the
# read, and either way what was found is on the record.

import os
import unicodedata

# What each language is written in, by the name Unicode gives its characters. A language absent from here
# is read without a script check and says so, which is not the same as passing one.
#
# Several are written in more than one and always have been. Serbian is Cyrillic and Latin, officially
# both and interchangeably, and the first run of this gate flagged a Serbian file at 0.340 Cyrillic as
# though a third of it were foreign when it is a Latin Serbian text doing nothing wrong. Kazakh,
# Azerbaijani, Uzbek and Punjabi are the same case. Every entry here is therefore a set, and a language
# passes on any of its own writings.
SCRIPTS = {
    "arabic": "ARABIC", "persian": "ARABIC", "urdu": "ARABIC", "uyghur": "ARABIC",
    "sindhi": "ARABIC", "pashto": "ARABIC",
    "hebrew": "HEBREW", "amharic": "ETHIOPIC", "divehi": "THAANA",
    "greek": "GREEK",
    "russian": "CYRILLIC", "ukrainian": "CYRILLIC", "bulgarian": "CYRILLIC",
    "tajik": "CYRILLIC",
    # Written in either, so either passes
    "serbian": ("CYRILLIC", "LATIN"), "tatar": ("CYRILLIC", "LATIN"),
    "kazakh": ("CYRILLIC", "LATIN"), "azerbaijani": ("LATIN", "CYRILLIC"),
    "uzbek": ("LATIN", "CYRILLIC"), "punjabi": ("GURMUKHI", "ARABIC"),
    "hindi": "DEVANAGARI", "marathi": "DEVANAGARI", "nepali": "DEVANAGARI",
    "sanskrit": "DEVANAGARI",
    "bengali": "BENGALI", "gujarati": "GUJARATI",
    "oriya": "ORIYA", "sinhala": "SINHALA",
    "tamil": "TAMIL", "telugu": "TELUGU", "kannada": "KANNADA", "malayalam": "MALAYALAM",
    "thai": "THAI", "burmese": "MYANMAR", "khmer": "KHMER", "lao": "LAO",
    "korean": "HANGUL", "chinese": "CJK", "georgian": "GEORGIAN", "armenian": "ARMENIAN",
    "japanese": ("CJK", "HIRAGANA", "KATAKANA"),
}

# Everything else here writes in the Latin alphabet. Listed because a corpus with no entry above went
# unchecked, and 274 of them did on the gate's first run, which is not the same as passing.
for LATIN_LANGUAGE in (
        "english", "french", "german", "spanish", "italian", "portuguese", "dutch",
        "swedish", "danish", "norwegian", "icelandic", "finnish", "estonian", "hungarian",
        "polish", "czech", "slovenian", "croatian", "slovak", "romanian", "albanian",
        "turkish", "vietnamese", "indonesian", "malay", "tagalog", "cebuano", "swahili",
        "afrikaans", "welsh", "irish", "breton", "catalan", "esperanto", "latin",
        "maori", "malagasy", "haitian", "somali", "hausa", "lithuanian", "latvian",
        "bosnian"):
    SCRIPTS.setdefault(LATIN_LANGUAGE, "LATIN")

# Below this share of its own writing, a file is not the language it claims and no reading of it means
# anything. Chosen well under the dirtiest file that still measured correctly once cleaned.
FLOOR = 0.55


# Collections whose language is fixed by what they are and is not in the filename. Without these, 201 of
# 485 corpora swept as never checked, and most of them are ordinary English prose that simply had no entry.
BY_COLLECTION = (
    ("author_", "english"), ("recipe_", "english"), ("rule_", "english"),
    ("kind_", "english"), ("english_", "english"), ("frecipe_", "french"),
    ("greek_", "greek"), ("finnish_", "finnish"), ("german_", "german"),
    ("french_", "french"), ("spanish_", "spanish"),
)


def script_of(name):
    """The writing a corpus is expected to be in, from its filename, or None where nothing is known."""
    stem = os.path.basename(name)
    for prefix, language in BY_COLLECTION:
        if stem.startswith(prefix):
            return language, SCRIPTS[language]
    for prefix in ("lang_", "wiki_", "para2_", "para_", "drav_", "cc_", "source_", "sinitic_"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    stem = stem.rsplit(".", 1)[0]
    for language in sorted(SCRIPTS, key=len, reverse=True):
        if stem.startswith(language):
            return language, SCRIPTS[language]
    return None, None


def belongs(symbol, wanted):
    try:
        name = unicodedata.name(symbol)
    except ValueError:
        return False
    if isinstance(wanted, tuple):
        return any(name.startswith(one) for one in wanted)
    return name.startswith(wanted)


def share_of_own(text, wanted):
    """How much of the writing in a text is the writing it should be."""
    letters = [symbol for symbol in text if symbol.isalpha()]
    if not letters:
        return 0.0, 0
    kept = sum(1 for symbol in letters if belongs(symbol, wanted))
    return kept / float(len(letters)), len(letters)


def strip_foreign(text, wanted):
    """The text with everything outside its own writing removed, one space left where words were."""
    out = []
    for symbol in text:
        if symbol.isspace():
            out.append(" ")
        elif symbol.isalpha() and not belongs(symbol, wanted):
            out.append(" ")
        else:
            out.append(symbol)
    return " ".join("".join(out).split())


def load(path, cap=None, clean=True, floor=FLOOR):
    """Read a corpus, check what writing it is in, and say what was found.

    Returns the text and a line describing the check. Where a language is known and the file falls below
    the floor, the text comes back cleaned when clean is set and comes back as None when it is not, so a
    caller that wants the raw file has to say so and a caller that forgets gets the safe behavior.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read(cap) if cap else handle.read()
    text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")

    language, wanted = script_of(path)
    if wanted is None:
        return text, "%s: no script known for it, unchecked" % os.path.basename(path)

    share, letters = share_of_own(text, wanted)
    if letters < 500:
        return text, "%s: too few letters to check" % os.path.basename(path)
    if share >= 0.98:
        return text, "%s: %.3f its own writing" % (os.path.basename(path), share)
    if share < floor:
        if not clean:
            return None, ("%s: only %.3f its own writing, below %.2f, refused"
                          % (os.path.basename(path), share, floor))
        kept = strip_foreign(text, wanted)
        return kept, ("%s: only %.3f its own writing, cut to it, %d characters left"
                      % (os.path.basename(path), share, len(kept)))
    if clean:
        kept = strip_foreign(text, wanted)
        return kept, ("%s: %.3f its own writing, cut to it, %d characters left"
                      % (os.path.basename(path), share, len(kept)))
    return text, ("%s: %.3f its own writing, left as it is" % (os.path.basename(path), share))


def report_on(paths, out):
    """Check a set of corpora and write what each one is, without measuring anything."""
    for path in paths:
        _, note = load(path, cap=400000, clean=False)
        out.write("  %s\n" % note)
