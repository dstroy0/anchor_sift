#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Central Salish lexical suffixes Julie Wolfe compares in ICSNL 60.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_wolfe.py
#
# Written for one paper, and this one is a different shape from every other paper here. The others
# are a story told by one speaker in one language. This is a comparative reconstruction: every form
# in it is a lexical suffix cited from a published dictionary of one of eighteen languages, laid out
# in columns under a two-letter abbreviation for the language it came from.
#
# THERE IS NO SINGLE PURE STREAM FOR THIS PAPER
#
# Every other reader writes a .pure.txt holding one language. Pouring these forms into one file
# would build a corpus of Sliammon, Sechelt, Squamish, three kinds of Halkomelem, three kinds of
# Straits, Klallam, Lushootseed, Twana, Tillamook, Quinault and two Tsamosan languages together,
# which is a corpus of no language at all. The language is what the anchor sift is trying to measure,
# so mixing eighteen of them into the thing it measures against is the one mistake that cannot be
# recovered from downstream.
#
# So this writes .pure.tsv instead, with the language in the first column. A reader downstream picks
# the language it wants. The hand extraction carries the same information in its who column, which is
# what reader_check grades against.
#
# WHAT IS HELD OUT
#
# Reconstructions. A form marked with a star is what the author works out that PS or PCS must have
# had, and nobody has ever said one. That is the same distinction salish_marking draws between a
# transcription and a segmentation line, applied to a proto-form.
#
# Predicted reflexes. Tables 6 and 8 give, for each language, the form expected if the reconstruction
# was stressed, the form expected if it was not, and the form actually attested. The extraction does
# not keep the columns apart reliably, so every cell of those two tables is held out. Nothing is lost:
# the attested forms of both tables are also printed in examples (1) and (6), where the columns are
# unambiguous.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, is_language_token, unreached, \
    write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "WolfeICSNL60.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
# The speaker slot is unstated because there is no speaker: every form is cited from a dictionary.
TARGET = os.path.join(
    CORPORA,
    "unstated_LexicalSuffixesAndConnectivesInProtoCentralSalishAndBeyond_Wolfe"
    "_Salish_centralsalish_2025_mixed.txt")

# This paper's inventory. Kept in step with WOLFE in hand_extraction/papers.py: the two files ask
# the same question of the same paper and a difference between them is a hole one of them cannot see.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "ʸːɛεέŋᶿθǰčšĺ" + "áéíóú" + "̌́"

PAGE = re.compile(r"^===== page \d+ =====$")

# What the paper calls each language, expanded to what the who column of the hand extraction says.
# Two letters at the head of a line is the whole of the layout: everything after it belongs to that
# language until the next one arrives.
LANGUAGES = {
    "Sl": "Sliammon", "Se": "Sechelt", "Sq": "Squamish", "Cw": "Cowichan",
    "Ms": "Musqueam", "Ck": "Chilliwack", "Sn": "Saanich", "Sm": "Samish",
    "Sg": "Songish", "Kl": "Klallam", "Ld": "Lushootseed", "Tw": "Twana",
    "Ti": "Tillamook", "Qu": "Quinault", "Ch": "Upper Chehalis", "Cz": "Cowlitz",
}

# The two reconstructed stages. Their forms are worked out, not attested, and are held out of the
# per-language data for that reason.
RECONSTRUCTED = ("PCS", "PS")

# The languages a form can be attested in. Anything else in the who column is a reconstructed stage
# and nobody speaks it, so it is derived and never reaches the per-language data.
SPEAKERS = frozenset(LANGUAGES.values())

# A data line: an optional example number, then the language, then the rest of the row.
OPENS = re.compile(r"^(?:\((\d{1,2})\)\s+)?(%s|PCS|PS)\s+(\S.*)$"
                   % "|".join(sorted(LANGUAGES, key=len, reverse=True)))

# An example or table the row sits under.
EXAMPLE = re.compile(r"^\((\d{1,2})\)\s")
TABLE = re.compile(r"^Table (\d{1,2}):")
SECTION = re.compile(r"^(\d(?:\.\d)?)\s+(\S.*)$")

# The two tables whose cells mix a prediction with an attested form. Held out whole.
PREDICTED_TABLES = ("Table 6", "Table 8")

LAYER = {
    "cited affix": SPOKEN,
    "reconstruction": DERIVED,
    "predicted": DERIVED,
    UNCLASSIFIED: DERIVED,
}


def forms_in(text):
    """Every token of a row that is a form of the language, with the glosses left behind.

    A row is a form, a gloss in single quotes, and often a second pair of both. The gloss is English
    and is not the language, so the marks decide: a token carrying one is a form. That is the same
    test the coverage check applies, which is why they agree about what is left over.
    """
    held = []
    # The quoted glosses come out first. Without this, a gloss holding an accented English word
    # would be read as a form, and 'fragrance, smell, odour' is three tokens of prose.
    plain = re.sub(r"[‘'][^’']*[’']", " ", text)
    for token in plain.split():
        bare = token.strip(".,;:()[]“”\"")
        if is_language_token(bare, MARKS):
            held.append(bare)
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one.rstrip("\n")) for one in handle]

    rows = []
    where = "front matter"
    language = None

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        found = TABLE.match(trimmed)
        if found:
            where = "Table %s" % found.group(1)
            language = None
        elif EXAMPLE.match(trimmed):
            where = "(%s)" % EXAMPLE.match(trimmed).group(1)
        else:
            heading = SECTION.match(trimmed)
            if heading and (len(trimmed) < 60) and not trimmed.endswith("."):
                where = "§%s" % heading.group(1)
                language = None

        found = OPENS.match(trimmed)
        if found:
            if found.group(1):
                where = "(%s)" % found.group(1)
            language = found.group(2)
            rest = found.group(3)
        else:
            rest = trimmed

        pieces = forms_in(rest)
        if not pieces:
            continue

        if language is None:
            # A form on a line no language opened. Prose citing a suffix does this, and so does a
            # correspondence table whose rows are single letters. Neither is per-language data.
            rows.append((where, "", UNCLASSIFIED, " ".join(pieces)))
            continue

        # The kind says what the row is, and the who column says whose it is. A reconstruction is a
        # cited affix like any other here, because several of them are cited from Kuipers, Kinkade
        # or Pincott by name; what keeps it out of a language corpus is that PCS and PS are not
        # languages anybody speaks, which the who column already says. Resting the purity filter on
        # that column instead of on the kind is what this paper is for.
        kind = "predicted" if (where in PREDICTED_TABLES) else "cited affix"
        named = LANGUAGES.get(language, language)
        for one in pieces:
            rows.append((where, named, kind, one))

    # Every line of the paper no branch above reached, so the marked record holds every token of the
    # language the paper printed and the coverage check has something to find.
    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for page, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % page, "", UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Lexical Suffixes and Connectives in Proto-Central Salish and Beyond.\n")
        handle.write("# Julie Wolfe, University of Victoria. Papers for the International\n")
        handle.write("# Conference on Salish and Neighbouring Languages 60, UBCWPL, 2025.\n")
        handle.write("#\n")
        handle.write("# A comparative reconstruction, not a narrative. Every form is a lexical\n")
        handle.write("# suffix cited from a published dictionary of one of eighteen languages, and\n")
        handle.write("# the who column of each row says which. There is no single target language\n")
        handle.write("# here and no flat pure stream: see the .pure.tsv beside this file.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. A reconstruction is derived because nobody\n")
        handle.write("# ever said one, and the predicted reflexes of Tables 6 and 8 are held out\n")
        handle.write("# for the same reason.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, named, kind, text) in enumerate(rows, 1):
            # Spoken only where a real language wrote it down. A PCS or PS row is worked out, and a
            # predicted reflex is worked out twice over.
            layer = SPOKEN if ((kind == "cited affix") and (named in SPEAKERS)) else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, named or spot, kind, crossings, content))

    # The per-language data, which is what a flat pure file cannot carry for this paper.
    pure = TARGET[:-4] + ".pure.tsv"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        handle.write("who\tform\n")
        for spot, named, kind, text in rows:
            if (kind != "cited affix") or (named not in SPEAKERS):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = (named, " ".join(run.split()))
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\t%s\n" % key)
                kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, named, kind, text in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Lexical Suffixes and Connectives in PCS", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d per-language forms written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    counted = {}
    for spot, named, kind, text in rows:
        if kind == "cited affix":
            counted[named] = counted.get(named, 0) + 1
    out.write("\n  by language: %s\n"
              % ", ".join("%s %d" % (one, counted[one]) for one in sorted(counted)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
