#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Hold every public claim against the theory, as the engine holds the device against the host.
#
#   python utils/maint/claims/claim_check.py [--all] [--strict] [<surface> ...]
#
# A surface is a page a reader meets first: README.md, every page under docs/, the README of
# theory/, and the abstract of every research paper. The theory is every other .tex and .md file
# under theory/. With no surface named, all of them are read.
#
# The theory takes a result back in its own words, and a block that holds one of the words in MARK
# is marked. A block is a paragraph, a list item, or one row of a table. A heading does not mark the
# blocks under it: a section headed with one of those words holds the corrected statement beside the
# one it replaced. The theory keeps the claim it took back beside the block that takes it back. A
# claim that was taken back is found in a marked block and usually in one that is not marked as well.
#
# Three kinds of key are read off each block of a surface and of the theory, after number words are
# read as numbers and the commas inside a number are dropped:
#
#   number   four or more digits, a decimal point, or a percent sign
#   pair     N of M, N of the M, N out of M, or N/M
#   phrase   a number beside a word of four or more letters
#
# A block of the theory that holds the key, where it and the statement share three or more words, is
# on the same subject, and it weighs as many as the words the two share. A block that is not marked
# counts as marked where a marked block further down the same file holds the same key and the two
# share three words. Each key on a surface gets one answer from the theory:
#
#   taken back   the marked blocks weigh as much as the rest, or more
#   both         the marked blocks weigh a third of the whole or more
#   nowhere      the theory does not hold it at all; numbers and pairs only, since a phrase alone
#                is too loose to stand for a claim
#   held         anything else; shown with --all
#
# A surface block that is itself marked, or that says a claim was killed, is telling the reader
# about the take back, and its keys are never answered taken back or both.
#
# taken back and both end the run with 1, and with --strict so does nowhere. A finding a person has
# read and found sound goes in claims_read.tsv beside this file, one row of surface, key, answer and
# why; the row quiets that finding and no other, and when the claim or the theory changes the
# answer, the row stops matching and the finding comes back.

import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
THEORY = os.path.join(ROOT, "theory")
READ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claims_read.tsv")

# Of that word only the form ending in ed is read. The theory uses its other forms for a probe that
# rules out an alignment far more than for a result it took back.
MARK = re.compile(r"\b(refuted|withdrawn|withdrew|retracted|retracts|superseded|falsified|not so)\b", re.IGNORECASE)
# A surface block that says something was killed or taken back is telling the reader about the
# take back, not repeating the claim, and is never answered taken back.
KILLED = re.compile(r"\bkill(ed|s)?\b", re.IGNORECASE)
TEX_HEADING = re.compile(r"\\(part|chapter|section|subsection|subsubsection|paragraph)\*?\{")
MD_HEADING = re.compile(r"^(#{1,6})\s")
ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s")

# The fewest words a statement and a block of the theory share, beside the key, before the block
# counts as saying the same thing.
NEAREST = 3

UNITS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
TEENS = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
         "nineteen"]
TENS = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
COMPOUND = re.compile(r"\b(%s)(?:[- ](%s))?\b" % ("|".join(TENS), "|".join(UNITS)))
SMALL = re.compile(r"\b(%s|%s)\b" % ("|".join(UNITS[1:]), "|".join(TEENS)))

# Words that sit beside a number without saying what it counts.
LOOSE = {"than", "that", "this", "these", "those", "with", "from", "into", "over", "under", "each", "every",
         "about", "only", "least", "most", "more", "less", "same", "were", "have", "they", "them", "their",
         "then", "when", "where", "which", "what", "while", "after", "before", "between", "within", "both",
         "also", "just", "some", "such", "here", "there", "page", "line", "lines", "figure", "table",
         "section", "chapter", "equation", "appendix", "version", "copyright"}


def number_words(text):
    """Number words as digits: twenty six as 26, nine as 9.

    one stays a word; it is not a number as often as it is one.
    """
    def compound(found):
        value = (TENS.index(found.group(1)) + 2) * 10
        if found.group(2):
            value += UNITS.index(found.group(2)) + 1
        return str(value)

    def small(found):
        word = found.group(1)
        if word in TEENS:
            return str(TEENS.index(word) + 10)
        return str(UNITS.index(word) + 1)

    return SMALL.sub(small, COMPOUND.sub(compound, text))


def plain(text, tex):
    """A line as the keys are read from it: lower case, with no command or link in the way of a number."""
    text = text.lower()
    if tex:
        text = re.sub(r"\\(cite|ref|label|eqref|url|href)\{[^}]*\}", " ", text)
        text = text.replace("\\%", "%").replace("{,}", ",").replace("\\,", ",").replace("~", " ")
        text = re.sub(r"\\[a-z]+\*?", " ", text)
        text = re.sub(r"[{}$\\]", " ", text)
    else:
        text = re.sub(r"`[^`]*`", " ", text)
        text = re.sub(r"\]\([^)]*\)", "]", text)
        text = re.sub(r"https?://\S+", " ", text)
        text = re.sub(r"<[^>]+>", " ", text)
    while True:
        joined = re.sub(r"(?<=\d),(?=\d{3}(?!\d))", "", text)
        if joined == text:
            break
        text = joined
    text = re.sub(r"(\d)\s*percent\b", r"\1%", text)
    text = re.sub(r"(\d)e([-+]?\d)", r"\1 e\2", text)
    text = re.sub(r"'s\b", "", text)
    return number_words(text)


def keys(text, tex):
    """Every key on one line, as (kind, key)."""
    text = plain(text, tex)
    found = set()
    for top, bottom in re.findall(r"(?<![\d.])(\d+)\s*/\s*(\d+)(?![\d.])", text):
        found.add(("pair", "%s of %s" % (top, bottom)))
    tokens = re.findall(r"(?<![a-z0-9.])\d+(?:\.\d+)?%?(?![a-z0-9])|[a-z][a-z-]*", text)
    for i, token in enumerate(tokens):
        if not token[0].isdigit():
            continue
        if "." in token or token.endswith("%") or len(token) >= 4:
            found.add(("number", token))
        rest = tokens[i + 1:i + 4]
        if len(rest) >= 2 and rest[0] == "of" and rest[1][0].isdigit():
            found.add(("pair", "%s of %s" % (token, rest[1])))
        if len(rest) >= 3 and rest[1] in ("of", "the") and rest[0] in ("out", "of") and rest[2][0].isdigit():
            found.add(("pair", "%s of %s" % (token, rest[2])))
        if len(token.rstrip("%")) < 2:
            continue
        for side in (i - 1, i + 1):
            if 0 <= side < len(tokens):
                word = tokens[side].strip("-")
                if len(word) >= 4 and word.isalpha() and word not in LOOSE:
                    found.add(("phrase", "%s %s" % (word, token)))
    return found


def blocks(path):
    """The file as (first line, lines, marked) blocks: a paragraph, or one table row."""
    tex = path.endswith(".tex")
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    out = []
    current = []
    start = 0

    def close():
        if current:
            marked = any(MARK.search(line) for _, line in current)
            out.append((start, list(current), marked))
            current.clear()

    fenced = False
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not tex and stripped.startswith("```"):
            close()
            fenced = not fenced
            continue
        if fenced:
            continue
        if TEX_HEADING.search(line) if tex else MD_HEADING.match(line):
            close()
        row = stripped.startswith("|") if not tex else ("&" in stripped and stripped.endswith("\\\\"))
        if not tex and ITEM.match(line):
            close()
        if not stripped or row:
            close()
            if row:
                start = number
                current.append((number, line))
                close()
            continue
        if not current:
            start = number
        current.append((number, line))
    close()
    return out


def surfaces(given):
    if given:
        return [os.path.abspath(one) for one in given]
    found = [os.path.join(ROOT, "README.md"), os.path.join(THEORY, "README.md")]
    found += sorted(glob.glob(os.path.join(ROOT, "docs", "*.md")))
    found += sorted(glob.glob(os.path.join(THEORY, "**", "frontmatter", "abstract.tex"), recursive=True))
    return [one for one in found if os.path.isfile(one)]


def theory_files(skip):
    for path in sorted(glob.glob(os.path.join(THEORY, "**", "*"), recursive=True)):
        if path.endswith((".tex", ".md")) and os.path.isfile(path) and os.path.abspath(path) not in skip:
            yield path


def stem(word):
    """A word with its ending taken off: a word and the same word with s or ed after it are one word."""
    for ending, keep in (("ies", "y"), ("sses", "ss"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")):
        if word.endswith(ending) and len(word) - len(ending) >= 4 and not word.endswith("ss"):
            return word[:len(word) - len(ending)] + keep
    return word


def words(text, tex):
    """The words of a block that say what it is about: four or more letters, not a loose word."""
    return {stem(word) for word in re.findall(r"[a-z]{4,}", plain(text, tex)) if word not in LOOSE}


def joined(body):
    return " ".join(line for _, line in body)


def index(skip):
    """Every key the theory holds, with each place: (path, line, marked, words of its block)."""
    held = {}
    for path in theory_files(skip):
        tex = path.endswith(".tex")
        for first, body, marked in blocks(path):
            text = joined(body)
            about = None
            for key in keys(text, tex):
                if about is None:
                    about = words(text, tex)
                held.setdefault(key, []).append((path, first, marked, about))
    return held


def taken(place, places):
    """The place, marked where a later marked block of the same file takes it back.

    The theory keeps a claim it took back where it stood and puts the block that takes it back after
    it. A block that is not marked is taken back when a marked block further down the same file holds
    the same key and the two share NEAREST words.
    """
    path, line, marked, about = place
    if marked:
        return place
    for other_path, other_line, other_marked, other_about in places:
        if other_marked and other_path == path and other_line > line and len(about & other_about) >= NEAREST:
            return (path, line, True, about)
    return place


def answer(kind, places, about):
    """The answer for one key, and the theory places that decided it.

    Every block of the theory that holds the key, where it and the statement share NEAREST words, is
    on the same subject, and it weighs as many as the words the two share. Where the marked blocks
    weigh as much as the rest, the statement repeats what the theory took back. Where they weigh a
    third of the whole or more, the answer is both, and a person reads the places shown.
    """
    if not places:
        return ("nowhere" if kind != "phrase" else None), []
    places = [taken(place, places) for place in places]
    scored = sorted(((len(about & place[3]), place) for place in places), key=lambda item: -item[0])
    near = [(score, place) for score, place in scored if score >= NEAREST]
    marked = sum(score for score, place in near if place[2])
    unmarked = sum(score for score, place in near if not place[2])
    shown = [place for score, place in near if place[2]]
    if marked == 0:
        return "held", [place for score, place in scored][:1]
    if marked >= unmarked:
        return "taken back", shown
    if marked * 2 >= unmarked:
        return "both", shown
    return "held", [place for score, place in near if not place[2]][:1]


def read_rows():
    rows = set()
    if os.path.isfile(READ):
        with open(READ, encoding="utf-8") as handle:
            next(handle, None)
            for line in handle:
                part = line.rstrip("\r\n").split("\t")
                if len(part) >= 3:
                    rows.add((part[0], part[1], part[2]))
    return rows


def where(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def main():
    parser = argparse.ArgumentParser(description="Hold every public claim against the theory.")
    parser.add_argument("surface", nargs="*",
                        help="pages to read; with none given, README.md, docs/ and every abstract")
    parser.add_argument("--all", action="store_true", help="show held keys as well")
    parser.add_argument("--strict", action="store_true", help="end with 1 on a number or pair the theory does not hold")
    args = parser.parse_args()

    pages = surfaces(args.surface)
    held = index(set(pages))
    silenced = read_rows()
    findings = {"taken back": [], "both": [], "nowhere": [], "held": []}
    quiet = 0
    for page in pages:
        tex = page.endswith(".tex")
        for first, body, marked in blocks(page):
            text = joined(body)
            about = words(text, tex)
            telling = marked or bool(KILLED.search(text))
            for kind, key in sorted(keys(text, tex)):
                verdict, places = answer(kind, held.get((kind, key), []), about)
                if verdict is None:
                    continue
                if telling and verdict in ("taken back", "both"):
                    verdict = "held"
                if (where(page), key, verdict) in silenced:
                    quiet += 1
                    continue
                findings[verdict].append((where(page), first, kind, key, places))

    for verdict in ("taken back", "both", "nowhere") + (("held",) if args.all else ()):
        rows = findings[verdict]
        if not rows:
            continue
        print("== %s: %d" % (verdict, len(rows)))
        for page, number, kind, key, places in rows:
            print("  %s:%d  %s  %s" % (page, number, kind, key))
            for path, line, marked, _ in places[:2]:
                print("      %s %s:%d" % ("marked" if marked else "held", where(path), line))
    total = sum(len(rows) for rows in findings.values())
    print("%d key(s) over %d page(s): %d taken back, %d both, %d nowhere, %d held, %d already read in %s"
          % (total + quiet, len(pages), len(findings["taken back"]), len(findings["both"]),
             len(findings["nowhere"]), len(findings["held"]), quiet, where(READ)))
    failed = findings["taken back"] or findings["both"] or (args.strict and findings["nowhere"])
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
