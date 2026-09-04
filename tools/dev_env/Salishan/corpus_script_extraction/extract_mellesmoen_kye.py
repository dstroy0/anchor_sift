#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Lushootseed of Mellesmoen and Kye, ICSNL 61, following that paper's own structure.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_mellesmoen_kye.py
#
# Written for one paper, and this one is not a narrative. It is a phonological analysis of stress in
# the two dialects of Lushootseed, and its language material arrives in five shapes: fifteen tables
# of citation forms, sixteen optimality-theoretic tableaux, six lines of Annie Jack's connected
# speech in Appendix A, thirty-odd phonotactic bullets in Appendix B, and forms cited inline with a
# gloss in quotes throughout the prose.
#
# WHAT IS AND IS NOT A WORD HERE
#
# This is the whole difficulty of the paper and the reason a reader built on characters alone would
# poison the corpus. A tableau prints five candidate forms of one word and the analysis rejects four
# of them. An input in slashes is an abstraction the analysis posits, not a form anybody said. A
# starred form in Appendix B is there precisely because the language does not have it. Every one of
# those carries the same characters as a real word, sits in the same paragraph, and would pass any
# test built on the alphabet.
#
#   attested       Table 9 č̓ə́ƛ̓aʔ, tableau (34b) marked ☞, Appendix B č̓əƛ̓aʔ, Annie Jack's sentences
#   not attested   tableau (34a) (č̓ƛ̓áʔ) and (34c) (č̓əƛ̓áʔ), input /č̓ƛ̓aʔ/, Appendix B *c̓ƛ̓aʔ
#
# So the reader types every line by where the paper put it, and only citation, surface and utterance
# in a Lushootseed dialect reach the pure stream. The losing candidates, the inputs, the starred
# forms and the cognates from four other languages stay in the record and out of the corpus.
#
# THE DIALECTS
#
# Northern and Southern Lushootseed are printed side by side in Tables 8, 9, A1 and A2 and in
# example (18), the same gloss with a different form in each column, and the paper's whole subject
# is that the two differ. A corpus that loses the column has ǰə́šəd and ǰə́səd as two unrelated words
# of one language. The dialect comes from the table's own heading or from the tableau's own title,
# never from the shape of the form.
#
# WHAT IS CHECKED AGAINST WHAT
#
# The control is the hand extraction in ../hand_extraction/Mellesmoen_Kye_ICSNL61.oracle.tsv, which
# was read off the paper by a person and verified against it in both directions. This file is graded
# against that one by reader_check.py. coverage_check.py separately asks the easier question, which
# is whether every token got out of the paper at all.

import io
import os
import re
import sys

from mellesmoen_kye_repair import repaired
from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "Mellesmoen_Kye_ICSNL61.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "MarthaLamont-AnnieJack_AComparativeAnalysisOfStressInNorthernAndSouthernLushootseed"
    "_MellesmoenKye_Salish_lushootseed_2026_mixed.txt")

PAGE = re.compile(r"^===== page \d+ =====$")

# The alphabet this paper writes Lushootseed with, after NFC. Wider than the marks shared across the
# nine other papers, and it has to be: yidád ‘fish trap’, báyac ‘meat’ and x̌il ‘lost’ carry no
# glottal stop, schwa or lateral, and a test built on those three reads them as English.
#
# x is deliberately absent. The language writes x̌ and xʷ, and both of those are found by the caron
# and by ʷ; putting a bare x here made examples, exception, complex, prefix and forty other English
# words into forms of Lushootseed.
ALPHABET = "ʔəɬƛʷščǰᶻθáíúàìù" + "̓̌́̀"

# What only a Salish orthography writes, without the accented vowels the alphabet above also holds.
# Used in the reference list, where a title carries Skwxwú7mesh and nɬeʔkepmxcín beside the Yoruba
# name Olúṣẹ̀yẹ Adéṣọlá, and an accent is what all three have in common.
SALISH = "ʔəɬƛʷščǰᶻθ7" + "̓̌"

# A form followed by its gloss in single quotes. The paper's own way of citing a word in prose, in
# Appendix B and inside the cells of Table 10 and example (1).
FORM_GLOSS = re.compile(r"(\S+)\s+[‘']([^’']*)[’']")

# The note Tables 8 and 9 put after a Southern form whose /a/ surfaces as schwa. Written out because
# it holds a second attested form in square brackets and because the closing parenthesis is missing
# on the t̓ə́q̓ʷab row, so anything counting brackets stops in the wrong place.
REALIZED = re.compile(r"\(/a/ → \[ə\](?:,\s*so\s*realized as \[([^\]]+)\])?\)?")

# A form the paper offers for comparison at the end of a Table 5 row: dᶻəx̌əx̌bíd (cf. dᶻə́x̌əx̌).
COMPARE = re.compile(r"\(cf\.\s*([^)]*)\)\s*$")

# A tableau's title line, which carries the dialect and the word being derived.
TABLEAU = re.compile(r"^\((\d{1,2})\)\s+(.*Lushootseed.*)$")

# A tableau's input row: the underlying form, in slashes, at the head of the constraint columns.
INPUT_ROW = re.compile(r"^\s+(/[^/]+/)")

# A tableau's candidate rows, with the pointing hand on the one the paper calls attested.
CANDIDATE = re.compile(r"^([a-h])\.\s+(☞\s+)?(\S+)")

# A section heading, which ends a table that has no blank line after it. Table 13 is the one.
HEADING = re.compile(r"^(\d+(?:\.\d+)*\s+[A-Z]|Appendix\s+[AB]\b|References\s*$)")

# Which appendix the walk is in, tracked apart from the section heading. Footnote 6 opens with
# "6 Additional glossing abbreviations" and matches the heading pattern above, so it took the walk
# out of Appendix A part way down the page and the last three of Annie Jack's six sentences were
# read as prose.
APPENDIX = re.compile(r"^Appendix\s+([AB])\b")

# One of Annie Jack's sentences, opened by the condition it illustrates. The colon is what separates
# these from Appendix B's numbered cluster headings, which state a constraint instead.
INTERLINEAR = re.compile(r"^\((\d)\)\s+\S.*:\s*$")

# An Appendix B bullet's label, which names the cluster type and is not a word: *RRonset:, SL:, NL:
BULLET_LABEL = re.compile(r"^([^‘’]*?):\s+")

SOUTHERN = "southern"
NORTHERN = "northern"

# A form printed with the language it belongs to, which Appendix A does for every cognate it cites.
# yəšən in Sechelt and ǰəšən in ʔayʔaǰuθəm are printed with no gloss at all, so the language name is
# the only thing marking them as forms and not as more of the sentence.
FORM_IN = re.compile(r"(\S+)\s+in\s+([A-Zʔ][^\s(,.;:]*)")

# What the paper calls each language, and what this corpus calls it. Squamish, Twana, Sechelt and
# ʔayʔaǰuθəm are cited here for comparison and are not Lushootseed, which is the whole reason the
# names are read at all: čalaš ‘hand’ sits in a Lushootseed paper and is a Twana word.
LANGUAGES = {
    "Southern": SOUTHERN,
    "Northern": NORTHERN,
    "Squamish": "squamish",
    "Twana": "twana",
    "Sechelt": "sechelt",
    "ʔayʔaǰuθəm": "ayajuthem",
}

# A parenthesis, and what says it is a reference and not a form. Northern Lushootseed prints its own
# name for itself as (dxʷləšucid), and Bianco 1995:127 sits in the same shape one line away.
PARENTHESIZED = re.compile(r"\(([^()]*)\)")
YEAR = re.compile(r"\b(1[89]|20)\d{2}\b")

LAYER = {
    "citation": SPOKEN,
    "surface": SPOKEN,
    # Named transcription because the other ten readers name it that. One vocabulary across the
    # corpus is worth more than a word that fits this paper slightly better on its own.
    "transcription": SPOKEN,
    # Derived, unlike the nine narratives. Those papers state that the speaker gave her own English
    # for her own story, and this one does not: Annie Jack was recorded by Leon Metcalf in the 1950s
    # and the English under her sentences is the authors' reading of what she said.
    "translation": DERIVED,
    "morphemes": DERIVED,
    "winner": DERIVED,
    "candidate": DERIVED,
    "underlying": DERIVED,
    "impossible": DERIVED,
    "cluster": DERIVED,
    "segment": DERIVED,
    "notation": DERIVED,
    "mention": DERIVED,
    "reference": DERIVED,
    "damage": DERIVED,
    "gloss": DERIVED,
    "essay": DERIVED,
    UNCLASSIFIED: DERIVED,
}

# The kinds that are words of Lushootseed. Everything else in the record is an abstraction, a
# rejected hypothesis, a form of another language, or English.
PURE = ("citation", "surface", "transcription")

# Each table by its caption, with how many language columns its rows have and which dialect each
# column is. Read off the table headings in the paper. Table 10 is the odd one: its two columns are
# both Southern and each cell is a form with its own gloss in quotes, so it is handled apart.
TABLES = {
    1: (NORTHERN,),
    2: (NORTHERN,),
    3: (NORTHERN,),
    4: (NORTHERN,),
    5: (NORTHERN,),
    6: (SOUTHERN,),
    7: (SOUTHERN,),
    8: (SOUTHERN, NORTHERN),
    9: (SOUTHERN, NORTHERN),
    11: (SOUTHERN,),
    12: (SOUTHERN,),
    13: (SOUTHERN,),
    "A1": (SOUTHERN, NORTHERN),
    "A2": (SOUTHERN, NORTHERN),
}

TABLE_CAPTION = re.compile(r"^Table (A?\d+)[:.]")

# How a table knows one of its rows has ended, which is not the same question in every table.
#
# Most rows are one line and hold one form, so counting forms works. Tables 8 and 9 put a note after
# the Southern form saying how its /a/ surfaces, and the note wraps across as many as three lines,
# so those rows end when two forms have been seen outside the note. Table A2 is the one where
# counting cannot work at all: its rows carry lab ‘see’, sbadil ‘mountain’, ti and ta, none of which
# holds a character of the alphabet above, and a row of it is over when its parentheses close.
BY_FORMS = "forms"
BY_PARENS = "parentheses"

ENDS = {
    8: BY_FORMS,
    9: BY_FORMS,
    "A1": BY_PARENS,
    "A2": BY_PARENS,
}


def carries_language(text):
    """Whether a string holds a character this paper writes Lushootseed with."""
    return any(one in text for one in ALPHABET)


def language_token(token):
    """Whether one token, stripped of the punctuation around it, is a form of the language."""
    plain = token.strip(".,;:()[]‘’“”'\"…*/→+")
    return bool(plain) and carries_language(plain)


def dialect_named(text):
    """Which dialect a heading or a tableau title names, or nothing where it names neither."""
    if "Southern" in text:
        return SOUTHERN
    if "Northern" in text:
        return NORTHERN
    return ""


def one_dialect(text):
    """The dialect a prose line names, where it names exactly one of them.

    A line naming both is not a line to guess from. §4.2.2.1 opens by contrasting tx̌ʷúd in Northern
    with tə́x̌ʷud in Southern, and either dialect assigned to both forms is wrong. Those come out
    unstated, and reader_check.py counts them. The reader does not invent an answer.
    """
    if ("Southern" in text) and ("Northern" in text):
        return ""
    return dialect_named(text)


def without_note(text):
    """One table row with the note about how its /a/ surfaces taken out, and the form that note held.

    Table 9's t̓ə́q̓ʷab row never closes its parenthesis. The note is matched on its own wording,
    which is why counting brackets is not used here.
    """
    found = REALIZED.search(text)
    if not found:
        return text, ""
    return (text[:found.start()] + " " + text[found.end():]).strip(), (found.group(1) or "")


def table_rows(lines, at, columns, ending):
    """One table's rows, from the line after its caption to the blank line or heading that ends it.

    Caption continuations and column headings are skipped by carrying no character of the alphabet
    while no row has started yet. Once rows have started, a line without one is a gloss the
    typesetter wrapped, and it belongs to the row being built.
    """
    held = []
    buffer = ""
    started = False
    while at < len(lines):
        trimmed = " ".join(lines[at].split())
        if (not trimmed) or PAGE.match(trimmed) or HEADING.match(trimmed):
            break
        at += 1
        if (not started) and (not carries_language(trimmed)):
            continue
        started = True
        buffer = ("%s %s" % (buffer, trimmed)).strip()
        stripped, surface = without_note(buffer)
        if ending == BY_PARENS:
            done = stripped.count("(") == stripped.count(")")
        elif ending == BY_FORMS:
            done = len([one for one in stripped.split() if language_token(one)]) >= len(columns)
        else:
            done = bool([one for one in stripped.split() if language_token(one)])
        if done:
            held.append((buffer, stripped, surface))
            buffer = ""
    if buffer:
        held.append((buffer,) + without_note(buffer))
    return held, at


def from_table(number, rows):
    """One table's rows as items, each a locator, dialect, kind, form and gloss.

    The forms are the last tokens of the row and the gloss is everything before them, which is the
    only reading that survives Table A2. Four of its Southern and Northern forms, lab, sbadil, ti and
    ta, carry no character of the alphabet, so nothing about the tokens themselves says which of
    them is a word; their position in the row is what says it.
    """
    held = []
    columns = TABLES[number]
    where = "Table %s" % number
    for whole, stripped, surface in rows:
        if number == 5:
            found = COMPARE.search(stripped)
            if found and carries_language(found.group(1)):
                stripped = stripped[:found.start()].strip()
                held.append((where, columns[0], "citation", found.group(1).strip(), ""))
        tokens = stripped.split()
        if len(tokens) < len(columns):
            held.append((where, "", UNCLASSIFIED, stripped, ""))
            continue
        forms = tokens[-len(columns):]
        gloss = " ".join(tokens[:-len(columns)])
        for dialect, form in zip(columns, forms):
            # Table A2 prints two Northern alternants for ‘year’ in one cell, dᶻəlč̓/ǰəlč̓.
            for one in (form.split("/") if ("/" in form) else [form]):
                if one:
                    held.append((where, dialect, "citation", one, gloss))
        if surface:
            held.append((where, columns[0], "surface", "[%s]" % surface, gloss))
    return held


def from_paired_cells(where, dialect, lines):
    """Rows whose every cell is a form with its own gloss in quotes.

    Table 10 and example (1) are printed this way, a stem beside what it becomes, each labelled.
    """
    held = []
    for line in lines:
        for form, gloss in FORM_GLOSS.findall(line):
            plain = form.strip("()[].,;:")
            if carries_language(plain):
                held.append((where, dialect, "citation", plain, gloss))
    return held


def from_comparison(lines):
    """Example (18), which prints a Southern form, a Northern form and one meaning for both."""
    held = []
    for line in lines:
        trimmed = " ".join(line.split())
        found = FORM_GLOSS.search(trimmed)
        if not found:
            continue
        letter = trimmed.split(".")[0].strip()
        where = "(18%s)" % letter if (len(letter) == 1) else "(18)"
        tokens = trimmed[:found.start(2) - 1].split()
        forms = [one for one in tokens if language_token(one)]
        for dialect, form in zip((SOUTHERN, NORTHERN), forms[-2:]):
            held.append((where, dialect, "citation", form, found.group(2)))
    return held


def from_tableau(number, dialect, title, lines):
    """One tableau: the word it derives, the input it posits, and every candidate it weighs.

    The pointing hand is the paper's own mark for the candidate it calls attested, and it is the
    only thing in the block that separates a form of the language from the four candidates the
    analysis exists to rule out.
    """
    where = "(%d)" % number
    held = []
    found = FORM_GLOSS.search(title)
    if found and carries_language(found.group(1)):
        held.append((where, dialect, "citation", found.group(1), found.group(2)))
    for line in lines:
        trimmed = line.rstrip()
        seen = INPUT_ROW.match(trimmed)
        if seen:
            held.append((where, dialect, "underlying", seen.group(1), ""))
            continue
        seen = CANDIDATE.match(" ".join(trimmed.split()) if trimmed.startswith(" ") else trimmed)
        if seen:
            kind = "winner" if seen.group(2) else "candidate"
            held.append(("(%d%s)" % (number, seen.group(1)), dialect, kind, seen.group(3), ""))
    return held


def from_interlinear(number, block):
    """One of Annie Jack's sentences from Appendix A, in the four lines the paper prints it on.

    These six are the only connected speech in the paper. Everything else is a word on its own,
    taken from a dictionary, from Hess, from Bianco, or elicited; these came off a recording made in
    the 1950s and each carries the story and the line it was said in.
    """
    where = "App A (%d)" % number
    held = []
    if len(block) < 4:
        return [(where, "", UNCLASSIFIED, " ".join(block), "")]
    said, morphemes, gloss, english = block[:4]
    held.append((where, SOUTHERN, "transcription", said.strip("… "), ""))
    held.append((where, SOUTHERN, "morphemes", morphemes, ""))
    held.append((where, "", "gloss", gloss, ""))
    held.append((where, SOUTHERN, "translation", english, ""))
    return held


def from_bullet(where, text):
    """One Appendix B bullet: what the language permits, and what it does not.

    The starred form is the point of the bullet and is not a word. *ylab is printed to show that
    yəlab is what the language has instead. A corpus holding both holds one word and one sequence
    its own source states cannot occur.
    """
    held = []
    body = BULLET_LABEL.sub("", text.lstrip("• ").strip(), count=1)
    dialect = ""
    if text.lstrip("• ").startswith("SL:"):
        dialect = SOUTHERN
    elif text.lstrip("• ").startswith("NL:"):
        dialect = NORTHERN
    pairs = FORM_GLOSS.findall(body)
    for form, gloss in pairs:
        plain = form.strip("()[],;:")
        if is_form(plain) and not plain.startswith("*"):
            held.append((where, dialect, "citation", plain, gloss))
    if not pairs:
        for token in body.split():
            plain = token.strip("()[],;:")
            if is_form(plain) and not plain.startswith("*"):
                held.append((where, dialect, "citation", plain, ""))
    for token in body.split():
        # The star is the whole claim, so it is what identifies the form. *ylab, *blups and *labd
        # carry no character of the alphabet, exactly as the words they are impossible versions of
        # do not, and a test on characters finds none of the three.
        if token.startswith("*") and (len(token) > 1):
            held.append((where, dialect, "impossible", token.strip(",;:"), ""))
    return held


def named_after(text, at):
    """The language named right after a gloss, where one is, as in čəwaš ‘wife’ in Squamish."""
    found = re.match(r"\s+in\s+([A-Zʔ][^\s(,.;:]*)", text[at:])
    return found.group(1) if found else ""


def is_morpheme(token):
    """Whether a bare token cited in prose is a morpheme this paper is talking about.

    A boundary mark alone is not enough. The extraction leaves a space before the hyphen in several
    English compounds, so post -alveolar, non -moraic and left -aligned all arrive looking like
    bound morphemes. What separates them is length and case: the morphemes this paper cites bare are
    -il, -ac, -al, -d, -ši and dxʷ-, and an English word broken off a compound is longer than four
    letters or carries a capital.
    """
    stem = token.strip("-=")
    if (token == stem) or (not stem) or (len(stem) > 4):
        return False
    return stem.islower() or carries_language(stem)


def is_form(token):
    """Whether a token cited in prose is a form of a language and not an English word.

    Two tests, because two kinds of form are printed here. Most carry a character of the alphabet.
    The bound morphemes do not: -ac ‘tree’, -yalus ‘edge’, -il, -d ‘TR’ and dxʷ- are written in
    plain letters, and only the boundary mark on them says they are morphemes and not English.
    """
    return bool(token) and (carries_language(token)
                            or (token.strip("-=") and (token[0] in "-=" or token[-1] in "-=")))


def from_prose(where, text, other="", fallback=""):
    """Every form the prose cites, in the four ways this paper cites one.

    A form with its gloss in quotes is the common case. A cognate is named by the language it is
    from, čəwaš ‘wife’ in Squamish, and so is a form printed with no gloss at all, ǰəšən in
    ʔayʔaǰuθəm. A dialect's own name for itself arrives parenthesized after the English name of it.
    Anything else carrying the alphabet is kept as a mention, which holds it in the record without
    claiming the paper presented it as a form.

    The dialect is taken from the passage where it names one, and otherwise from the section it
    sits in. §3.2.3 discusses ɬidálgʷiɬ and q̓ílalič without naming a dialect in either sentence,
    because §3 is headed Northern Lushootseed stress pattern and the reader has been told. A passage
    naming both names them about different words, and there nothing decides.
    """
    held = []
    dialect = one_dialect(text) or fallback
    claimed = set()

    for found in FORM_GLOSS.finditer(text):
        plain = found.group(1).strip("()[],;:")
        if (not is_form(plain)) or plain.startswith("*") or plain.startswith("/"):
            continue
        claimed.add(plain)
        held.append((where, LANGUAGES.get(named_after(text, found.end()), dialect),
                     "citation", plain, found.group(2)))

    for found in FORM_IN.finditer(text):
        plain = found.group(1).strip("()[],;:")
        language = LANGUAGES.get(found.group(2))
        if (plain in claimed) or (not language) or not is_form(plain):
            continue
        claimed.add(plain)
        held.append((where, language, "citation", plain, ""))

    for found in PARENTHESIZED.finditer(text):
        inside = found.group(1)
        # A bibliographic parenthesis carries a year and names no form, which is what keeps Bianco
        # and Kuipers out of a corpus of the language. A long parenthesis is a sentence. §6 has a
        # twelve-word aside that happens to mention ʔayʔaǰuθəm.
        if YEAR.search(inside) or (len(inside.split()) > 4):
            continue
        # §2.1 introduces each dialect's own name for itself right after the English name of it:
        # Northern Lushootseed (dxʷləšucid), Southern Lushootseed (xʷəlšucid or txʷəlšucid). The
        # sentence names both dialects and decides nothing, and the words in front of the bracket
        # decide it exactly.
        ahead = one_dialect(" ".join(text[:found.start()].split()[-3:])) or dialect
        for token in inside.split():
            for plain in token.strip("()[],;:").split("/"):
                if (not plain) or (plain in claimed) or plain.startswith("*"):
                    continue
                if not carries_language(plain):
                    continue
                claimed.add(plain)
                held.append((where, LANGUAGES.get(plain, ahead), "citation", plain, ""))

    for token in text.split():
        # Square brackets stay on. The paper puts a cluster in them, [k̓ʷd] and [lč], and a surface
        # realization too, and the brackets are how it says which of the two a string is.
        for plain in token.strip("(),;:.‘’“”…").split("/"):
            if (not plain) or (plain in claimed) or plain.startswith("*"):
                continue
            if (plain in LANGUAGES) and carries_language(plain):
                # ʔayʔaǰuθəm is a word of ʔayʔaǰuθəm wherever it turns up, including inside a
                # section about Lushootseed, and the section's dialect must not reach it. The test
                # is that the name is written in the language it names: Squamish, Twana and Sechelt
                # are English words for languages and are not forms of anything here.
                claimed.add(plain)
                held.append((where, LANGUAGES[plain], "citation", plain, ""))
                continue
            if is_morpheme(plain):
                claimed.add(plain)
                held.append((where, dialect, "citation", plain, ""))
                continue
            # A capital opens an author's name, never a form. These languages are written in lower
            # case, apart from a form opening in ʔ, and Bermúdez, Adéṣọlá and Olú all carry an
            # accented vowel the alphabet holds.
            if plain[0].isupper() or not carries_language(plain):
                continue
            if other and not any(one in plain for one in SALISH):
                continue
            claimed.add(plain)
            held.append((where, other or dialect,
                         "mention" if not other else "reference", plain, ""))
    return held


def read_paper(lines):
    """Every item the paper holds, and every line of it that carried one, in the paper's own order.

    A single walk. Each structure is opened by something the paper prints for a reader to see: a
    table by its caption, a tableau by a title naming a dialect and a glossed word, one of Annie
    Jack's sentences by a numbered condition ending in a colon, a phonotactic bullet by its mark.
    Anything else is prose, and prose is kept whole as well as mined for the forms it cites.
    """
    items = []
    essay = []
    taken = set()
    paragraph = []
    at = 0
    section = "front matter"
    appendix = ""
    # The dialect the last section heading named, carried in a list so flush() can read it. §3 is
    # headed Northern Lushootseed stress pattern and §4 Southern Lushootseed stress pattern, and
    # every subsection under each of them is about that dialect whether or not it says so again.
    heading_dialect = [""]

    def flush():
        """Mine the prose gathered so far and start a new paragraph.

        Called wherever the prose stops, which is a blank line, a page break or any structure. A
        paragraph is the unit because dialect is read from it: one that names Southern and Northern
        both names them about different words and yields no dialect at all, and running two of them
        together would make that true of the whole paper.
        """
        if paragraph:
            where, text = joined(paragraph)
            items.extend(from_prose(where, text,
                                    "reference" if where == "References" else "",
                                    heading_dialect[0]))
            del paragraph[:]

    while at < len(lines):
        line = lines[at]
        trimmed = " ".join(line.split())
        if (not trimmed) or PAGE.match(trimmed):
            flush()
            at += 1
            continue

        found = APPENDIX.match(trimmed)
        if found:
            appendix = found.group(1)
        heading = HEADING.match(trimmed)
        if heading:
            flush()
            section = trimmed
            named = one_dialect(trimmed)
            if named:
                heading_dialect[0] = named
            elif APPENDIX.match(trimmed) or trimmed.startswith("References"):
                heading_dialect[0] = ""

        found = TABLE_CAPTION.match(trimmed)
        if found and (found.group(1) in TABLES or found.group(1) == "10"
                      or found.group(1).lstrip("A").isdigit()):
            number = found.group(1)
            number = number if number.startswith("A") else int(number)
            flush()
            taken.add(at)
            essay.append((at, "Table %s" % number, "essay", trimmed))
            rows, moved = table_rows(lines, at + 1, TABLES.get(number, (SOUTHERN,)),
                                     ENDS.get(number, ""))
            for one in range(at + 1, moved):
                taken.add(one)
                # The row's own line is kept beside the forms taken out of it. Table A2 prints two
                # Northern alternants for ‘year’ in one cell, dᶻəlč̓/ǰəlč̓, and the forms come out
                # separately, so without the line as printed the cell reads as never extracted.
                if " ".join(lines[one].split()):
                    essay.append((one, "Table %s" % number, "essay",
                                  " ".join(lines[one].split())))
            if number in TABLES:
                items.extend(from_table(number, rows))
            elif number == 10:
                items.extend(from_paired_cells("Table 10", SOUTHERN,
                                               [one[0] for one in rows]))
            else:
                for whole, stripped, surface in rows:
                    items.append(("Table %s" % number, "", UNCLASSIFIED, stripped, ""))
            at = moved
            continue

        found = TABLEAU.match(trimmed)
        if found and FORM_GLOSS.search(trimmed):
            number = int(found.group(1))
            dialect = dialect_named(found.group(2))
            flush()
            taken.add(at)
            block = []
            moved = at + 1
            while moved < len(lines):
                ahead = lines[moved].rstrip()
                bare = ahead.strip()
                # Tableau (35) follows (34) with no blank line between them. A title ends a block
                # the same way a blank line does. Without this the Northern derivation of ‘rock’
                # was read as four more candidates of the Southern one.
                if (not bare) or PAGE.match(bare) or HEADING.match(bare):
                    break
                if TABLEAU.match(bare) and FORM_GLOSS.search(bare):
                    break
                block.append(ahead)
                taken.add(moved)
                moved += 1
            items.extend(from_tableau(number, dialect, trimmed, block))
            at = moved
            continue

        if (appendix == "A") and INTERLINEAR.match(trimmed):
            number = int(trimmed[1])
            flush()
            taken.add(at)
            block = []
            moved = at + 1
            while (moved < len(lines)) and (len(block) < 4):
                ahead = " ".join(lines[moved].split())
                moved += 1
                if (not ahead) or PAGE.match(ahead):
                    continue
                block.append(ahead)
                taken.add(moved - 1)
            items.extend(from_interlinear(number, block))
            at = moved
            continue

        if trimmed.startswith("•"):
            flush()
            taken.add(at)
            items.extend(from_bullet(section.split()[0] + " " + section.split()[1]
                                     if len(section.split()) > 1 else section, trimmed))
            essay.append((at, section, "essay", trimmed))
            at += 1
            continue

        if trimmed.startswith("(1) a.") or trimmed.startswith("b. stə́gʷad"):
            flush()
            taken.add(at)
            items.extend(from_paired_cells("(1)", SOUTHERN, [trimmed]))
            essay.append((at, "(1)", "essay", trimmed))
            at += 1
            continue

        if trimmed.startswith("(18)"):
            flush()
            taken.add(at)
            block = []
            moved = at + 1
            while moved < len(lines):
                ahead = " ".join(lines[moved].split())
                if (not ahead) or PAGE.match(ahead) or not re.match(r"^[a-d]\.", ahead):
                    break
                block.append(ahead)
                taken.add(moved)
                moved += 1
            items.extend(from_comparison(block))
            essay.append((at, "(18)", "essay", trimmed))
            at = moved
            continue

        where = "References" if section.startswith("References") else section
        if paragraph and (paragraph[0][0] != where):
            flush()
        # Prose is mined a paragraph at a time and kept a line at a time. The paper breaks a
        # citation across a line as readily as anything else: the root čə́bid ends one line and its
        # gloss ‘douglas fir’ opens the next, sčəbíd-ac is hyphenated across the break in both
        # Figure 7 captions, and Figure 5's caption names Southern on one line and Northern on the
        # next about one word. Read line by line, the first two are invisible and the third is read
        # as a Southern form.
        paragraph.append((where, trimmed))
        essay.append((at, where, "essay", trimmed))
        at += 1

    flush()
    return items, essay


def joined(paragraph):
    """One paragraph's lines as a single string, with the words the line break split put together.

    A line ending in a hyphen was broken inside a word, so it joins with nothing between. Every
    other line ends a word and joins with a space.
    """
    where = paragraph[0][0]
    out = ""
    for one, text in paragraph:
        if out.endswith("-"):
            out += text
        elif out:
            out += " " + text
        else:
            out = text
    return where, out


def marked(kind, dialect, text):
    """One item written in the T and N convention, as language.layer.kind:{text}.

    T is Lushootseed. A cognate from Squamish, Twana, Sechelt or ʔayʔaǰuθəm is language and is not
    this language, so it is N, which is what keeps čalaš out of a Lushootseed corpus.
    """
    mark = "T" if (dialect in (SOUTHERN, NORTHERN)) else "N"
    return "%s.%s.%s:{%s}" % (mark, LAYER.get(kind, DERIVED), kind, text)


def switches_in(text):
    """How many times a line crosses between languages."""
    return max(0, len(tagged_spans(text)) - 1)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [repaired(one.rstrip("\n")) for one in handle]

    items, essay = read_paper(lines)

    rows = []
    for number, (where, dialect, kind, form, gloss) in enumerate(items, 1):
        rows.append((number, where, dialect, kind, form, gloss))
    for at, where, kind, text in essay:
        rows.append((0, where, "", kind, text, ""))

    missed = unreached(lines, covered_tokens(one[4] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append((0, "page %d" % page, "", UNCLASSIFIED, text, ""))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# A Comparative Analysis of Stress in Northern and Southern Lushootseed.\n")
        handle.write("# Gloria Mellesmoen, University of British Columbia, and Ted Kye,\n")
        handle.write("# University of Washington. ICSNL 61.\n")
        handle.write("# Recordings of Martha Lamont, Northern, and Annie Jack, Southern, made by\n")
        handle.write("# Leon Metcalf in the 1950s and held by the Burke Museum, with forms also\n")
        handle.write("# from Bates, Hess and Hilbert 1994, Hess 1977 and Bianco 1995.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Lushootseed, N is anything else, and a\n")
        handle.write("# cognate cited from Squamish, Twana, Sechelt or ʔayʔaǰuθəm is N.\n")
        handle.write("#\n")
        handle.write("# Only citation, surface and utterance are words of the language. A losing\n")
        handle.write("# tableau candidate is a form the paper's own analysis rejects, an\n")
        handle.write("# underlying form in slashes is an abstraction, and a starred form in\n")
        handle.write("# Appendix B is there to say the language does not have it. All three carry\n")
        handle.write("# the same characters as a real word and none of them reaches the pure\n")
        handle.write("# stream.\n")
        handle.write("#\n")
        handle.write("# The where column carries the paper's own locator, which this paper needs\n")
        handle.write("# and the narrative papers do not: its material is in fifteen tables and\n")
        handle.write("# sixteen tableaux, not in one running story, and Table 8 and Table 9\n")
        handle.write("# print the same gloss twice with a different form under each dialect.\n")
        handle.write("line\twhere\tdialect\tkind\tswitches\tcontent\n")
        for number, where, dialect, kind, text, gloss in rows:
            content = marked(kind, dialect, text)
            handle.write("line#${%d}\t%s\t%s\t%s\t%d\t%s\n"
                         % (number, where, dialect, kind, switches_in(text), content))

    pure = TARGET[:-4] + ".pure.txt"
    by_dialect = {SOUTHERN: [], NORTHERN: []}
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for number, where, dialect, kind, text, gloss in rows:
            if (kind not in PURE) or (dialect not in by_dialect):
                continue
            key = " ".join(text.split())
            # A bound morpheme is a citation and is not a word. -ac ‘tree’, -yalus ‘edge’, -il and
            # dxʷ- are all real and none of them was ever said on its own, so they stay in the
            # record and out of a corpus of things people said.
            if key and ((key[0] in "-=") or (key[-1] in "-=")):
                continue
            if not key or (key in already):
                continue
            already.add(key)
            by_dialect[dialect].append(key)
            handle.write("%s\n" % key)
            kept += 1

    for dialect, held in by_dialect.items():
        with open("%s.pure.%s.txt" % (TARGET[:-4], dialect), "w",
                  encoding="utf-8", newline="") as handle:
            for one in held:
                handle.write("%s\n" % one)

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, one[1], UNKNOWN_KIND, "", one[4])
               for one in rows if one[3] == UNCLASSIFIED]
    flagged.extend(missed)
    # The one join the space repair is known to get wrong, named here so nobody has to find it.
    flagged.append((34, "App A", UNKNOWN_KIND, "ǰč",
                    "the palatal series is cited in prose as /ǰ č č̓ š/ and the repair joined the "
                    "first two, because ǰ ends in a caron with one space after it exactly as a "
                    "broken word does"))
    stuck_count = write_unsorted(stuck, "Mellesmoen and Kye, ICSNL 61", flagged)

    counted = {}
    for number, where, dialect, kind, text, gloss in rows:
        counted[kind] = counted.get(kind, 0) + 1
    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language forms written to\n  %s\n"
              % (kept, os.path.basename(pure)))
    out.write("    %d Southern, %d Northern\n"
              % (len(by_dialect[SOUTHERN]), len(by_dialect[NORTHERN])))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))
    out.write("\n  by kind: %s\n"
              % ", ".join("%s %d" % (one, counted[one]) for one in sorted(counted)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
