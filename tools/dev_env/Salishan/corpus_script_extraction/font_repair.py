#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The font substitution the two Lyon papers need, and where each form of it may be applied.
#
#   Usage:  from font_repair import REPAIR, repaired, repaired_prose
#
# Both papers' PDFs wrote plain letters in place of the orthography, so the text arrives as
# iP naPì ʼqwQaylqs where it should read iʔ naʔɬ ʼqwʕaylqs. The mapping was tested and not
# assumed: font_substitution.py applies it to the damaged tokens and counts how many become forms
# attested in Lyon's later papers on the same language. Before the mapping, 1 token of 3599 was
# attested; after it, 811. On the other paper, 2 of 4332 became 965. A wrong mapping cannot do that,
# because a wrong substitution produces strings the language does not contain.
#
# Applying it to every character of both papers was the mistake. P and Q are ordinary capitals in
# Lyon's English, so the repair turned Pierre into ʔierre, Quilchena into ʕuilchena, INCEPT into
# INCEʔT and jmlyon@sfu.ca into jmlyonəsfu.ca. Those went into the record as words and were then
# reported as holes by the coverage check, which is a defect that manufactured its own evidence.
#
# There is no test on a token that separates the two. Paks, Pitx, Psiwst, Qip, Qant and Pums are
# words of the language; Pierre, Peter, Press, Priest and Quilchena are not; and every one of them
# is a capital followed by lowercase ASCII. Measured against the attested-form oracle, a rule that
# skipped that shape skipped ten real words to save eighteen English ones.
#
# What does separate them is where the token sits. These papers print their interlinear a column at
# a time, and the reader knows which column it is holding: the first two are the language and the
# rest are gloss and translation. So the repair comes in two forms. Inside a language column, and
# inside the running text of a story, every substitution applies. Everywhere else only the two that
# cannot be English apply, which leaves an all-caps gloss label and an address alone.

from salish_marking import CAPS_RUN, bare_token, tagged_spans

# The mapping, in order. The caron entries go first because this font writes the caron as its own
# character ahead of the letter it belongs to, so x̌ arrives as ˇx. Replacing the bare letters first
# would consume them and strand the caron.
REPAIR = (("ˇx", "x̌"), ("ˇc", "č"), ("ˇs", "š"),
          ("@", "ə"), ("P", "ʔ"), ("ì", "ɬ"), ("Q", "ʕ"))

# CAPS_RUN comes from salish_marking, which is where every reader here gets it. What it protects is
# the run and not the whole token, because a gloss puts a lexical gloss and a label in one token:
# tell.story-APPL, know+INCH, -manage.to-DIR-3ERG. Guarding whole tokens left those unprotected and
# wrote tell.story-AʔʔL into the record.
#
# Two capitals are required, which is why it is safe here. A single one is how the language arrives,
# in P@ and in the P of iP.


def repaired(text):
    """One line of the language, with every substitution applied.

    For a line known to be the language: a transcription or segmentation column, or the running
    text of a story. Nothing is held back, so Paks becomes ʔaks and Qip becomes ʕip.
    """
    for was, becomes in REPAIR:
        text = text.replace(was, becomes)
    return text


def is_address(token):
    """Whether a token is an email address, whose at sign is its own and not a damaged schwa."""
    if ("@" not in token) or ("." not in token) or not token.isascii():
        return False
    return all(one.islower() for one in token if one.isalpha())


def guarded(token):
    """One token repaired, with its runs of two or more capitals left as they arrived."""
    pieces = []
    at = 0
    for found in CAPS_RUN.finditer(token):
        pieces.append(repaired(token[at:found.start()]))
        pieces.append(found.group(0))
        at = found.end()
    pieces.append(repaired(token[at:]))
    return "".join(pieces)


# Characters that only the damaged orthography writes: the schwa and lateral the font replaced, the
# stranded caron, and the accented vowels these papers mark stress with.
#
# The typographic apostrophe is deliberately absent. This font writes the ejective with it and
# English writes a possessive with it, so Society’s and ’qwQaylqs are alike to any test built on
# one, and an acknowledgment about the American Philosophical Society reached a corpus that way.
ORTHOGRAPHY = "@ìˇáéíóúàèòù"


def carries_orthography(token):
    """Whether a token holds something only the damaged orthography writes.

    A capital P or Q inside a token is one: English does not put a capital in the middle of a word,
    and iP, kwaP and naPì all do. At the front of a token it is not, because that is how Pierre,
    Priest and Philosophical arrive as well as how Paks does, and a word-initial capital decides
    nothing on its own.
    """
    if any(one in token for one in ORTHOGRAPHY):
        return True
    return any(one in "PQ" for one in token[1:])


def language_line(text, floor=1):
    """Whether a line of a damaged paper is the language and not a line of English prose.

    One token is enough, which is why the test above has to be the sharp one. These stories wrap
    across the page and leave lines as short as sámaP. and t@mxwúlaPxw., and asking for two threw
    forty-nine of them out of one paper's running text. Asking for one, on a test that a capital at
    the front of an English word cannot satisfy, keeps them and still refuses an acknowledgment
    about the American Philosophical Society.
    """
    return sum(1 for token in text.split() if carries_orthography(token)) >= floor


def repaired_line(text):
    """One line repaired a span at a time, English kept and the language restored.

    For anywhere the reader has no column to go on: a footnote, a reference, a line of front matter,
    a leftover after a free translation, a block whose cycle slipped. A whole-line choice is not
    enough for those, because one reference line carries both a word of the language and the word
    Papers, and whichever repair the line is given is wrong for half of it.

    So a line carrying the language is cut into its English and target spans and each span takes
    its own repair. The span rule already requires two English-looking tokens in a row before it
    opens an English span, which keeps a lone Paks among target words on the target side of the cut.

    A line carrying none of the language is not cut at all. The span rule counts a word of under
    three letters as not English, so at, an, in and BC break an English sentence into single words
    and leave Quilchena as a lone token joining a target span that is not there. Asking first
    whether the line is the language at all settles that, and twenty-eight occurrences with it.
    """
    if not language_line(text):
        return repaired_english(text)
    out = []
    for mark, run in tagged_spans(text):
        out.append(repaired_english(run) if mark == "N" else repaired_prose(run))
    return " ".join(out)


def english_word_shape(token):
    """Whether a token is an ordinary English word or name: ASCII, one capital, at the front.

    Tested on the token with the punctuation around it taken off. Quilchena.’ closes with a
    typographic apostrophe, and asking whether the whole token is ASCII answered no and sent the
    name to be repaired inside a translation that had already been called English.
    """
    plain = bare_token(token)
    letters = [one for one in plain if one.isalpha()]
    if (len(letters) < 3) or not plain.isascii():
        return False
    return letters[0].isupper() and all(one.islower() for one in letters[1:])


def repaired_english(text):
    """One line of Lyon's own English, with every substitution that would break a word held back.

    For a gloss, a translation, a commentary, an acknowledgment, or any line the reader has already
    decided is English. Here a capital at the front of a word is left alone, which repaired_prose
    cannot do: a line that might still hold Paks or Qip needs that capital repaired, and a line
    already known to be English does not. Knowing which line is which is the whole difference, and
    it comes from the reader's own structure. Nothing the token carries decides it.
    """
    out = []
    for token in text.split():
        if is_address(token) or english_word_shape(token):
            out.append(token)
        else:
            out.append(guarded(token))
    return " ".join(out)


def repaired_prose(text):
    """One line that is not a language column, with the ambiguous substitutions held back.

    For a gloss, a translation, a commentary, or any of Lyon's own writing. A gloss label and an
    address keep every character they arrived with. Everything else is repaired, since a word of
    the language cited inside an English sentence still needs its characters back.

    What this does not save is an English word in ordinary case: Pierre and Quilchena are repaired
    here and come out wrong. That is deliberate. Paks, Pitx, Pums, Qant and Qip are words of the
    language in the same shape, and measured against the attested-form oracle a rule that skipped
    the shape lost ten real words to save eighteen English ones. The language wins that trade.
    """
    out = []
    for token in text.split():
        out.append(token if is_address(token) else guarded(token))
    return " ".join(out)
