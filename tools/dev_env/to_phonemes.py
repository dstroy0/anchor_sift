#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put five spellings into one set of sounds, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/to_phonemes.py
#
# Words for sounds came out following the border and not the family, and that was measured on spelling.
# Spelling is the wrong thing for this question: Hungarian writes sz for one consonant and Polish writes
# sz for another, so two words said alike are counted apart and two written alike are counted together.
#
# The dictionary was asked for its transcriptions and does not hold any. Hungarian pages carry a template
# that builds the pronunciation from the spelling when the page is drawn, and several Polish pages carry
# nothing at all. That is itself the answer to whether transcriptions would add evidence: they would not,
# because for these five languages the pronunciation is a function of the spelling, which is why a
# template can produce it.
#
# What is still needed is the shared alphabet, and that is a mapping, not a lookup. Each language's
# spelling is turned into the sounds it stands for, so a Hungarian s and a Polish sz both become the same
# symbol when they are the same consonant and different symbols when they are not.
#
# These mappings are mine. They follow the standard descriptions of each orthography, they are applied
# longest spelling first so digraphs are read before their letters, and they ignore length, stress and the
# assimilations that happen across word boundaries. Any error in them is an error in the result, which is
# the price of not asking a service twelve hundred times.

import io
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

# Longest spellings first within each language, since dz must be read before d and z
SOUNDS = {
    "hungarian": (
        ("dzs", "ʤ"), ("cs", "ʧ"), ("dz", "ʣ"), ("gy", "ɟ"), ("ly", "j"), ("ny", "ɲ"),
        ("sz", "s"), ("ty", "c"), ("zs", "ʒ"), ("s", "ʃ"), ("c", "ʦ"), ("á", "a"),
        ("é", "e"), ("í", "i"), ("ó", "o"), ("ö", "ø"), ("ő", "ø"), ("ú", "u"),
        ("ü", "y"), ("ű", "y"), ("j", "j"), ("v", "v"), ("h", "h"),
    ),
    "polish": (
        ("dzi", "ʥ"), ("dź", "ʥ"), ("dż", "ʤ"), ("dz", "ʣ"), ("cz", "ʈʂ"), ("ch", "x"),
        ("sz", "ʂ"), ("rz", "ʐ"), ("ci", "ʨ"), ("si", "ɕ"), ("zi", "ʑ"), ("ni", "ɲ"),
        ("ż", "ʐ"), ("ź", "ʑ"), ("ś", "ɕ"), ("ć", "ʨ"), ("ń", "ɲ"), ("ł", "w"),
        ("ą", "ɔ"), ("ę", "ɛ"), ("ó", "u"), ("w", "v"), ("c", "ʦ"), ("y", "ɨ"),
        ("j", "j"), ("h", "x"),
    ),
    "czech": (
        ("ch", "x"), ("dž", "ʤ"), ("š", "ʃ"), ("č", "ʧ"), ("ž", "ʒ"), ("ř", "ʐ"),
        ("ť", "c"), ("ď", "ɟ"), ("ň", "ɲ"), ("á", "a"), ("é", "e"), ("í", "i"),
        ("ó", "o"), ("ú", "u"), ("ů", "u"), ("ý", "i"), ("ě", "e"), ("c", "ʦ"),
        ("j", "j"), ("v", "v"), ("h", "h"),
    ),
    "finnish": (
        ("ng", "ŋ"), ("ä", "æ"), ("ö", "ø"), ("y", "y"), ("j", "j"), ("v", "v"),
        ("c", "k"), ("z", "ʦ"), ("w", "v"),
    ),
    "estonian": (
        ("š", "ʃ"), ("ž", "ʒ"), ("õ", "ɤ"), ("ä", "æ"), ("ö", "ø"), ("ü", "y"),
        ("y", "y"), ("j", "j"), ("v", "v"), ("b", "p"), ("d", "t"), ("g", "k"),
    ),
}


def spoken(word, language):
    """The word written in sounds instead of in that language's letters."""
    lowered = word.lower()
    parts = lowered.split()
    # A leading call particle is not the sound word, and Polish files many of these that way
    if len(parts) > 1 and parts[0] in ("a", "o", "e"):
        lowered = " ".join(parts[1:])
    lowered = "".join(lowered.split())

    out = []
    index = 0
    table = SOUNDS.get(language, ())
    while index < len(lowered):
        for spelling, sound in table:
            if lowered.startswith(spelling, index):
                out.append(sound)
                index += len(spelling)
                break
        else:
            symbol = lowered[index]
            # Anything not spelled specially keeps its letter, with length marks dropped
            flat = "".join(one for one in unicodedata.normalize("NFD", symbol)
                           if unicodedata.category(one) != "Mn")
            out.append(flat or symbol)
            index += 1
    return "".join(out)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-12s %-8s %-9s %s\n" % ("language", "words", "sounds", "an example"))

    for language in sorted(SOUNDS):
        source = os.path.join(CORPORA, "onom_%s.txt" % language)
        if not os.path.isfile(source):
            continue
        with open(source, encoding="utf-8") as handle:
            words = [line.strip() for line in handle if line.strip()]
        said = {}
        for word in words:
            heard = spoken(word, language)
            if 2 <= len(heard) <= 16:
                said[word] = heard
        target = os.path.join(CORPORA, "said_%s.txt" % language)
        with open(target, "w", encoding="utf-8", newline="") as handle:
            for word in sorted(said):
                handle.write("%s\t%s\n" % (word, said[word]))

        shown = sorted(said)[:2]
        out.write("  %-12s %-8d %-9d %s\n"
                  % (language, len(words), len({said[word] for word in said}),
                     "  ".join("%s to %s" % (word, said[word]) for word in shown)))

    out.write("\n  written by the mappings in this file, which are standard and are not a lookup\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
