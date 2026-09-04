#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grade a reader against the hand extraction it is supposed to reproduce.
#
#   Usage:  python tools/dev_env/Salishan/hand_extraction/reader_check.py
#
# coverage_check.py asks whether every token of the language got out of the paper. That is the
# easier question and a reader can answer it perfectly while being wrong about everything that
# matters: it can file a rejected tableau candidate as a word, put a Squamish cognate in a
# Lushootseed corpus, or read Table 8's two columns as one dialect. Every token would still be
# accounted for.
#
# This asks the harder question. The hand extraction says what each form is, so the reader is graded
# against it form by form, on three things: whether it found the form at all, whether it says the
# same kind, and whether it says the same dialect.
#
# The one it must not fail is kind, because kind decides the pure corpus. A candidate filed as a
# citation puts a form the paper rejects into the corpus, and nothing downstream ever asks again.

import io
import os
import re
import sys
import unicodedata

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")
HERE = os.path.dirname(os.path.abspath(__file__))

# The hand extractions live in the research body, beside the prose that cites them. They are the
# speakers' words written down and they are evidence, not tooling.
ORACLES = os.path.join(ROOT, "docs", "research", "Salishan", "pure_corpus")

sys.path.insert(0, HERE)

from papers import EVERY  # noqa: E402

# What the hand extraction records but a reader is not asked to reproduce. A segment cited on its
# own, a constraint name, a template and a bibliography entry are all things a person names while
# reading a paper so that nothing is left unaccounted for. None of them is a form to extract, and
# the record holds their lines as prose.
NOT_ASKED = ("segment", "notation", "mention", "reference", "damage", "cluster",
             # An English word a paper's damaged mark set reads as a form, and a line of the next
             # paper bound into the same PDF. Both are written down so the count of what a paper
             # holds is honest, and neither is something to extract.
             "english", "foreign")

SOUTHERN = "southern"
NORTHERN = "northern"

# Kinds that make the same claim about a form under two names. A paper printing its story as
# unnumbered prose gets running speech and one printing it as numbered lines gets transcription.
# Both say the speaker said this in the target language, and the pure stream takes both.
SAME = {"running speech": "transcription", "transcription": "transcription"}


def normalized(text):
    return unicodedata.normalize("NFC", " ".join(text.split()))


def oracle_rows(path):
    held = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if (len(fields) < 4) or (fields[0] == "where"):
                continue
            held.append((fields[0], fields[1], fields[2], normalized(fields[3])))
    return held


# One span of a record's content column, written by salish_marking as language.layer.kind:{text}.
# A line the speaker mixed carries several of these, joined with a comma. A row is read as spans and
# not as one string.
#
# The kind may hold a space, and nine of the eleven readers write one that does: symbol note,
# running speech, stage direction, word gloss, free translation, cited example, morpheme entry,
# speaker comment, orthography chart. Excluding whitespace here made every one of those spans
# invisible to this check, which then reported the forms in them as forms the reader never wrote.
SPAN = re.compile(r"([TN])((?:\.[^:{}]*)*):\{")


def spans_of(content):
    """Every span of one content column, as its mark, its kind, and the text inside its braces."""
    held = []
    for found in SPAN.finditer(content):
        at = found.end()
        depth = 1
        while (at < len(content)) and depth:
            if content[at] == "{":
                depth += 1
            elif content[at] == "}":
                depth -= 1
            at += 1
        parts = [one for one in found.group(2).split(".") if one]
        held.append((found.group(1), parts[-1] if parts else "", content[found.end():at - 1]))
    return held


def record_rows(path):
    """Every item a reader wrote, as where, who, kind, form.

    The kind comes out of the span marker. The eleven records do not share a column layout: three of
    them have no kind column at all and the rest disagree on where it sits. Every one of them writes
    the marker, because salish_marking writes it.

    The speaker or dialect is read from a column when the record has one under that name. Several
    records do not have one, and their papers never established who was speaking.
    """
    held = []
    columns = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if not columns:
                columns = fields
                continue
            where = fields[1] if len(fields) > 1 else ""
            who = ""
            for name in ("speaker", "dialect"):
                if (name in columns) and (columns.index(name) < len(fields)):
                    who = fields[columns.index(name)]
                    break
            for mark, kind, text in spans_of(fields[-1]):
                held.append((where, who, kind, normalized(text)))
    return held, any((one in columns) for one in ("speaker", "dialect"))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    failed = 0
    waiting = []
    # A paper with a hand extraction and no reader yet. It is not graded either, and counting it as
    # graded is how this file reported 12 of 12 on the day the twelfth paper had a table and no
    # reader. The two lists are kept apart because the thing to do about them is different.
    unwritten = []
    for name, stem, record, repair, marks in EVERY:
        table = os.path.join(ORACLES, name)
        written = os.path.join(CORPORA, record)
        if not os.path.isfile(table):
            waiting.append(stem)
            continue
        if not os.path.isfile(written):
            out.write("  no record on disk for %s, run its reader first\n" % stem)
            unwritten.append(stem)
            failed += 1
            continue

        every = oracle_rows(table)
        wanted = [one for one in every if one[2] not in NOT_ASKED]
        got, names_who = record_rows(written)

        # What the paper holds at all, taken from every row of the hand extraction. A segment or a
        # constraint name is not a form the reader is asked to find, and finding one is not the
        # reader inventing something either.
        asked = {one[3] for one in every}
        dialects = {}
        for where, dialect, kind, form in every:
            dialects.setdefault((kind, form), set()).add(dialect)

        out.write("  %s\n" % name)
        out.write("    %d forms asked for, %d items the reader wrote\n" % (len(wanted), len(got)))

        by_form = {}
        for where, dialect, kind, form in got:
            by_form.setdefault(form, []).append((where, dialect, kind))

        # What the reader said it could not sort. A form it flagged is a different thing from a form
        # it got wrong without noticing: the first is the reader doing its job, and the second is
        # the defect this check exists to find.
        flagged = set()
        stuck = written[:-4] + ".unclassifiable.tsv"
        if os.path.isfile(stuck):
            with open(stuck, encoding="utf-8") as handle:
                columns = []
                for line in handle:
                    fields = line.rstrip("\n").split("\t")
                    if not columns:
                        columns = fields
                        continue
                    # Read by column name. Taking it by position broke the moment a paper column
                    # was added to the front of the flag file, and every flagged form was then
                    # counted as one the reader had silently missed.
                    if ("where" in columns) and (columns.index("where") < len(fields)):
                        flagged.add(fields[columns.index("where")])

        missing = []
        said_so = []
        wrong_kind = []
        wrong_dialect = []
        undecided = []
        for where, dialect, kind, form in wanted:
            found = by_form.get(form)
            if not found:
                (said_so if (where in flagged) else missing).append((where, kind, form))
                continue
            wanted_kind = SAME.get(kind, kind)
            if not any(SAME.get(one[2], one[2]) == wanted_kind for one in found):
                wrong_kind.append((where, kind, form, sorted({one[2] for one in found})))
                continue
            said = sorted({one[1] for one in found
                           if SAME.get(one[2], one[2]) == wanted_kind})
            # A record with no speaker or dialect column was never asked who was talking, and
            # grading it on an answer its paper's reader does not give is asking a question of the
            # wrong file. The hand extraction still records it.
            if not names_who:
                continue
            if dialect in ("", "unstated", "none"):
                continue
            # čalaš ‘hand’ is printed as Twana and as Squamish in one sentence, so either answer is
            # the paper's answer and asking for one of them would be asking for a coin toss.
            if dialects.get((kind, form), set()) & set(said):
                continue
            if dialect in said:
                continue
            # A form the paper states is the same in both dialects is right under either name and
            # right under neither. Table 1 and Table 6 both print ɬúkʷaɬ, and §4.1 says so.
            if (dialect == "both") and (said and set(said) <= {SOUTHERN, NORTHERN, ""}):
                continue
            # Claiming nothing is not the same as claiming the wrong thing. The reader declines a
            # dialect wherever the passage names both of them. That is counted here and is not
            # graded as an error.
            if said == [""]:
                undecided.append((where, kind, form, dialect))
                continue
            wrong_dialect.append((where, kind, form, dialect, said))

        # Prose the reader kept whole is not a form it claims to have extracted, and neither is a
        # line of somebody else's paper bound into the same PDF.
        ignored = NOT_ASKED + ("essay", "gloss", "note", "commentary", "free translation")
        # A reader item that opens with a wanted form and runs past it is that form, taken too far.
        # It is reported once, where it was flagged or missed, and counting it again here as
        # something the reader made up would turn one defect into two.
        overrun = sorted(asked, key=len, reverse=True)
        extra = sorted({(kind, form) for where, dialect, kind, form in got
                        if (form not in asked) and (kind not in ignored)
                        and not any(form.startswith(one) for one in overrun if len(one) > 12)})

        out.write("    %d forms the reader did not find\n" % len(missing))
        for where, kind, form in missing:
            out.write("      %-12s %-11s %s\n" % (where, kind, form))
        out.write("    %d forms the reader could not bound and flagged as such\n" % len(said_so))
        for where, kind, form in said_so:
            out.write("      %-12s %-11s %s\n" % (where, kind, form[:70]))
        out.write("    %d forms the reader typed differently\n" % len(wrong_kind))
        for where, kind, form, said in wrong_kind:
            out.write("      %-12s %-11s %-26s reader said %s\n"
                      % (where, kind, form, ", ".join(said)))
        out.write("    %d forms the reader put in the wrong dialect\n" % len(wrong_dialect))
        for where, kind, form, dialect, said in wrong_dialect:
            out.write("      %-12s %-11s %-26s %s, reader said %s\n"
                      % (where, kind, form, dialect, ", ".join(one or "none" for one in said)))
        out.write("    %d forms the reader invented\n" % len(extra))
        for kind, form in extra:
            out.write("      %-11s %s\n" % (kind, form))
        out.write("    %d forms whose dialect the reader would not claim\n" % len(undecided))
        for where, kind, form, dialect in undecided:
            out.write("      %-12s %-11s %-26s the paper's is %s\n" % (where, kind, form, dialect))

        failed += len(missing) + len(wrong_kind) + len(wrong_dialect) + len(extra)

    out.write("\n  %d of %d readers are graded against a hand extraction\n"
              % (len(EVERY) - len(waiting) - len(unwritten), len(EVERY)))
    if waiting:
        out.write("  ungraded until their paper is read by hand:\n")
        for stem in waiting:
            out.write("    %s\n" % stem)
    if unwritten:
        out.write("  read by hand and ungraded until a reader is written:\n")
        for stem in unwritten:
            out.write("    %s\n" % stem)
    out.write("\n  %s\n" % ("every reader reproduces its hand extraction" if not failed
                            else "%d disagreements to work through" % failed))
    out.flush()
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
