#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The kinds of damage a PDF extraction does, one mechanism for each kind, and the way to compose them.
#
#   Usage:  from repairs import one_mark, composed, sequence
#
# refs.md names five kinds of mutation these extractions make: substitution, one symbol for one;
# collapse, two symbols onto one; transposition, a mark moved off its letter; insertion, a space that
# was never in the text; and deletion, a space dropped so two words weld. That list came out of a
# measurement of two papers against their own rendered pages, and this file is the same list written
# as code.
#
# A paper carries some of these kinds and not others, and it declares which in paper_config.py. The
# mechanism is written once here; the count behind each declaration stays with the paper, because it
# is a fact about that paper and not about the mechanism.
#
# WHAT IS HERE AND WHAT IS NOT
#
# Insertion lives in whitespace.py, which is the whole of that kind and is large enough to be its own
# module.
#
# Collapse is nowhere and cannot be anywhere. It destroys a distinction instead of disguising it:
# page kʷ and page wist both arrive as w and nothing separates them afterward. A paper carrying a
# collapse is read off its rendered pages, and that is the only answer there is.
#
# Transposition is not here because the one family that needs it needs a whole conversion table with
# it. lyon_encoding.py is that table and it is that font's grain, not a general one.
#
# Deletion is not here for a different reason: on the papers measured so far it is not decidable from
# the text alone. Davis and Mellesmoen prints l followed by a space for both l̓ with its space
# inserted and a plain l at a real boundary, and q̓íl q-s=a is the second of those while
# n-ká<k>əl -xal is the first. The page settles each one and no rule does.

import unicodedata


def one_mark(was, becomes):
    """Substitution: two codepoints for one mark, written the way the paper's body writes it.

    Correct only where the paper itself writes one letter both ways, which is what makes the two the
    same mark. Where each letter takes only one of them the difference is the orthography, and
    normalizing it is a guess about the language dressed up as a repair.
    """
    def written(line):
        return line.replace(was, becomes)
    return written


def composed():
    """Canonical composition, which is not damage and is not a judgment about any paper.

    Unicode defines a with a combining acute and á as the same character. A table typed at a keyboard
    composes them and a PDF sometimes does not, and without this every accented form written by hand
    is reported as one the paper does not hold.
    """
    def written(line):
        return unicodedata.normalize("NFC", line)
    return written


def corrected(pairs):
    """Deletion: marks the extraction dropped, put back from a table read off the page.

    This is the one grain that cannot be derived from the text, and it is here because the damage it
    repairs is not decidable from the text either. Davis and Mellesmoen prints l followed by a space
    for both l̓ with its space inserted and a plain l at a real boundary, and q̓íl q-s=a is the second
    while n-ká<k>əl -xal is the first. No rule separates them.

    So each pair is evidence, not inference, and it comes from one of two places. Some are read by
    symbol_sift.py, which finds them where the paper prints the same word whole somewhere else and
    reports the rate a random mark would have scored. The rest are read off a rendered page, and the
    entry says which page. A pair with neither provenance does not belong in one of these tables.

    The pairs apply in order and the longer contexts come first, because qʷəl -qʷal út has to be
    taken before qʷal út or the second would fire inside the first and leave it half repaired.

    Both sides of every pair are composed here. A pair is typed into a config file by a person whose
    keyboard may compose an accent or may not, and this grain runs after composed(), so a pattern
    left decomposed matches nothing and fails silently. That cost an afternoon on la-líl təm.
    """
    held = tuple((unicodedata.normalize("NFC", damaged), unicodedata.normalize("NFC", whole))
                 for damaged, whole in pairs)

    def written(line):
        for damaged, whole in held:
            line = line.replace(damaged, whole)
        return line
    return written


def sequence(*steps):
    """One paper's repair, as the grains it carries, in the order they have to run.

    Order matters in one place and it is worth naming. The spaces close while the marks whose space
    was inserted are still separate characters, and composition runs last. Composing a with a
    combining acute into á first takes that acute out of the marks a space can follow, and the space
    it was holding open stays behind. Running composition first cost 164 of one paper's forms.
    """
    def repaired(line):
        for step in steps:
            line = step(line)
        return line
    return repaired
