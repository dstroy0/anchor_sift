#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Turn the TeX font's encoding back into the orthography, as far as it goes.
#
#   Usage:  from lyon_encoding import drafted
#
# 19-Lyon_ICSNL50_final-78 and 2013_Lindley_Lyon are set in NimbusRomNo9L and TeX-xipa with a custom
# encoding and no ToUnicode map, so what pypdf hands back is glyph codes read as ASCII. Page 1 of
# Lindley prints q̓sápi ɬaʔ ct̓ʕapənwíxʷ and the text holds ’qsápi ìaP c’tQap@nwíxw.
#
# WHAT THIS IS AND IS NOT
#
# It is a draft. Every rule below was read off a rendered page and holds on the pages checked, and
# the output still has to be verified against the page before it counts as the paper. It exists
# because retyping 148 pages by hand introduces its own errors, and a draft a person corrects is
# more accurate than a page a person types from nothing.
#
# WHAT IT CANNOT DO
#
# w is two letters. Page kʷukʷ and page wist both arrive as w, and nothing in the text separates
# them. The rule below labializes a w that follows one of the consonants that take it, which is
# right for kʷ, qʷ, xʷ, x̌ʷ and wrong wherever a real w follows a consonant.
#
# Word boundaries are the other one. The PDF puts a space in front of a letter carrying a mark.
# s ’plá ’ks@lx is one word, iP ’kl is two, and both of them are a space in front of a marked
# letter. Page 25 settles the first as sp̓lák̓səlx and page 24 the second as iʔ k̓l. wa’y and Lyon’s
# are the same case with the space missing instead of inserted.
#
# Those are the sites to read first on any page, and they are why this file is not a repair in
# papers.py: a repair is applied and trusted, and this has to be checked.

import re
import unicodedata

# The marks the extraction prints in front of the letter they belong over, against the combining
# mark each one is. ’ is glottalization and is most of them.
#
# ´ turns up only where the font has no precomposed letter to carry the accent. á é í ó ú arrive
# whole, and the schwa does not, so lasy´@t is the page's lasyə́t and is the one word in this paper
# that needs it.
MOVED = {"’": "̓", "´": "́"}

# What the glyph codes stand for, one for one, wherever they appear in a Salish token. ; was in this
# table until níkmən; showed that it is not one for one: see lengthened().
LETTERS = (
    ("@", "ə"),
    ("ì", "ɬ"),
    ("Q", "ʕ"),
    ("ň", "ƛ"),
)

# The wedge arrives before its letter as well, and only ever sits on x here.
WEDGE = (("ˇx", "x̌"),)

# One place the inserted space is not a question. √ opens a root on a parse line and the root
# follows it immediately, so √ never ends a word and a space after it is always the PDF's. The
# roots that start with a marked letter get one: √ q̓ʷʕay=lqs is √q̓ʷʕay=lqs on the page.
AFTER_ROOT = ("√ ", "√")

# The consonants a following w labializes. A w after anything else, or at the front of a word, is
# the letter w: wist, wa’y, nwíwpəm.
LABIALIZED = "kqxgɣʕǰč"


def moved_marks(token):
    """One token with each spacing mark carried onto the letter it was printed in front of.

    Called only for a token salish() answered for. In the English the same ’ is an apostrophe and
    follows its letter, and moving it turns Lyon’s into Lyons̓.
    """
    out = []
    at = 0
    while at < len(token):
        symbol = token[at]
        combining = MOVED.get(symbol)
        if (combining is not None) and ((at + 1) < len(token)) and token[at + 1].isalpha():
            out.append(token[at + 1])
            out.append(combining)
            at += 2
            continue
        out.append(symbol)
        at += 1
    return "".join(out)


# The characters of the extraction that only the language is written with, so a token holding one of
# them is Salish. These are the codes as they arrive, not what they become: an earlier version of
# this listed ə ɬ ʕ ƛ, which the test never sees, and s’tmQa’lt came through with its ejective marks
# still standing in front of their letters.
#
# The first two characters are the wedge. drafted() runs WEDGE over the whole line before any of
# this, so a wedge that stood on an x is a combining caron by the time the test reads it, and the
# standalone ˇ catches one that stood anywhere else. Writing the pair as the string "x̌" put a bare x
# in the set and made every English word holding one Salish.
#
# √ opens a root on a parse line and appears in no English word, so a token carrying one is Salish.
# Without it in_ks_√’ma came through with the mark still in front of the m, and that is most of the
# parse lines in the five-line format.
MARKS = "̌ˇ@ìQň·√áéíóú"

# A gloss token is plain ASCII, apart from two things. The ligatures the PDF sets its f-words with:
# the whole gloss of one morpheme is one token, so go-n-dip.ﬂuid-MID-3SG.POSS is a single string and
# the one ﬂ in it kept it out of this class. It was then read as Salish and its POSS came out as
# ʔOSS. And the reduplication mark, which the gloss line of the five-line format uses as well as the
# parse line does: C1C2.PL•speak-CAUS came out as C1C2.ʔL•speak-CAUS.
#
# The five-line format's gloss line also carries the morpheme boundaries + and =, and without them
# +get.read-APPL came out as +get.read-AʔʔL and +C1C2.PL•son+DRV as +C1C2.ʔL•son+DRV.
#
# √ stays out. It opens a root on the parse line and appears on no gloss line, and a parse line is
# Salish. The run of two capitals LABEL asks for is what keeps a parse token out of this class
# anyway: a parse is written in lower case and a gloss is not.
GLOSS = re.compile(r"^[A-Za-z0-9.()\[\]/,;:'•+=ﬁﬂﬀﬃﬄ-]+$")
LABEL = re.compile(r"[A-Z]{2}")


def a_gloss(token):
    """Whether a token belongs to a gloss line, where its P is the P of RECIP and PASS.

    A gloss is plain ASCII and carries a run of two or more capitals: RECIP, 3PL.ABS, NOM-son-RED.
    One capital on its own is not enough, because that is also iP and Philosophical.
    """
    return bool(GLOSS.match(token)) and bool(LABEL.search(token))


def salish(token):
    """Whether a token is set in the language's font, so its P is a glottal stop and its ’ a mark.

    P and ’ are the two the encoding cannot decide by itself. P is ʔ throughout the Salish and a
    capital P throughout the English, and both sit on one line: COMP and RECIP head the gloss lines
    while Philosophical and Penticton run through the notes. ’ is the ejective mark in the Salish
    and the apostrophe in Lyon’s and Society’s.

    A token carrying any other mark of the orthography is Salish, and so is one holding a P that is
    not the first letter, which is what iP, smsámaP and nPaysənúlaPxw are and what Philosophical is
    not.

    Two things this misses. A P-initial Salish word with no other mark on it, as Pitx, Pamn and
    Pasil are, comes through as English. So does a word whose ’ the extraction did not put a space
    in front of, because wa’y and Lyon’s are then the same shape and only the page tells them apart.
    Both are among the first things to look for on a page.
    """
    if a_gloss(token):
        return False
    # Qu opening a token is the English digraph, as Quilchena and Queen are. Q is the pharyngeal
    # everywhere else, at the front of Qant and QapnáP included, so the test asks for a tail with no
    # other mark in it and only the English pair comes out. Asking for a plain ASCII tail instead
    # missed Quilchena.’ at the end of a translation, where the closing quote is not ASCII. A Salish
    # word opening ʕu and carrying no other mark would be read as English here, and neither paper
    # holds one.
    if (token[:2] == "Qu") and not any((mark in token[1:]) for mark in MARKS):
        return False
    # An address, where @ is the at sign. The last line of the paper is john.lyon@alumni.ubc.ca and
    # it came out with a schwa in the middle of it. A Salish token is not plain ASCII once its @ is
    # counted, and none of them holds a dot.
    if token.isascii() and ("@" in token) and ("." in token):
        return False
    if any((mark in token) for mark in MARKS):
        return True
    # A ’ that opens a token is the mark waiting for its letter: ’ti is t̓i. One that follows a
    # letter is the apostrophe of Lyon’s and Society’s.
    #
    # An English elision opens with one too. Lyon writes ’til in the translation of stanza 137 and
    # it comes out as t̓il, which is the same shape as ’ti and cannot be told from it inside one
    # token. That is the only one in this paper.
    if token.startswith("’"):
        return True
    # A glottal stop standing alone, left by a break the PDF put in front of it, as ixí P is.
    if token == "P":
        return True
    return "P" in token[1:]


def lengthened(line):
    """One line with ; read as the length mark where the letter it lengthens follows it.

    Lyon writes length with a raised dot and the font gives it the semicolon's code, so ya;Qt is
    ya·ʕt and ’qsá;;;pi is q̓sá···pi. He also ends a clause with a semicolon, and the page prints
    ník ’m@n; iP k ’wúl ’m@ns, where a run mapped without asking makes a word of níkmən·.

    Run over the whole line, before the tokens are split, because the mark survives the inserted
    space and the test needs to see across it. qw@mí;; ’wt is one word: the run is followed by a
    space and then the ’ that the space was inserted in front of. níkmən; is followed by a space and
    a plain letter, which is the sentence carrying on.
    """
    out = []
    at = 0
    while at < len(line):
        if line[at] != ";":
            out.append(line[at])
            at += 1
            continue
        end = at
        while (end < len(line)) and (line[end] == ";"):
            end += 1
        after = line[end:end + 2]
        # The letter it lengthens comes next, and one of two things can stand between. A spacing
        # mark waiting for that letter, as ’kwu;’l-s has. An inserted space in front of that mark,
        # as qw@mí;; ’wt has. A space with a plain letter after it is the sentence carrying on,
        # which is what keeps níkmən; iP apart.
        carries = bool(after) and (after[0].isalpha() or (after[0] in MOVED)
                                   or ((after[0] == " ") and (len(after) > 1)
                                       and (after[1] in MOVED)))
        out.append(("·" * (end - at)) if carries else line[at:end])
        at = end
    return "".join(out)


# What the look-back steps over on its way to the consonant. Lyon brackets a segment he is
# reconstructing and parenthesizes one he is restoring, and the page labializes across both:
# [k̓]w is [k̓]ʷ in stanza 176 and n-t̓ək̓[w] is n-t̓ək̓[ʷ] in stanza 6. A combining mark is stepped
# over for the same reason, since the mark sits on the consonant doing the labializing.
TRANSPARENT = "[]()"


def labialized(line):
    """One line with w read as ʷ where it follows a consonant that takes labialization."""
    out = []
    for symbol in line:
        if (symbol == "w") and out:
            at = len(out) - 1
            while (at >= 0) and ((out[at] in TRANSPARENT) or unicodedata.combining(out[at])):
                at -= 1
            if (at >= 0) and (out[at].lower() in LABIALIZED):
                out.append("ʷ")
                continue
        out.append(symbol)
    return "".join(out)


def drafted(line):
    """One line of the extraction as a draft of what the page says, to be checked against the page.

    Token by token, because a line is mixed. One gloss line reads COMP DET native.person and the
    transcription above it reads ɬaʔ iʔ sqilxʷ, and the two want opposite answers about P and ’.

    The wedge goes first and over the whole line: ˇx is x̌ in the Salish and appears nowhere else,
    and it is what makes a token look Salish to the test that follows.

    The length mark goes over the whole line too, and for the same reason: lengthened() has to see
    across the inserted space to tell qw@mí;; ’wt from níkmən; iP.

    LETTERS runs on a Salish token only. Its codes are ordinary characters elsewhere, and ; was the
    one that showed it: Lyon ends a clause with a semicolon in his English, and mapping the line
    without asking turned long ago over there; we came into over there· we came.
    """
    for before, after in WEDGE:
        line = line.replace(before, after)
    line = line.replace(*AFTER_ROOT)
    line = lengthened(line)
    held = []
    for token in line.split(" "):
        if salish(token):
            # LETTERS first. moved_marks carries a mark onto the letter after it and asks whether
            # that letter is one, and @ is not: lasy´@t kept its acute standing in front until the
            # schwa was a schwa.
            for before, after in LETTERS:
                token = token.replace(before, after)
            token = moved_marks(token).replace("P", "ʔ")
        held.append(token)
    return unicodedata.normalize("NFC", labialized(" ".join(held)))
