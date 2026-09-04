#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Twana augmentative reduplications Hyung-Soo Kim reanalyzes in ICSNL 52.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_kim_twana.py
#
# The first Twana paper in this set, and Twana has no anchor yet. Every Twana form here is
# Drachman's, from a 1969 dissertation Kim calls the only reliable reference in existence for this,
# so what the paper prints is close to the whole of what is written down.
#
# THE FIRST EXAMPLE IS NOT TWANA
#
# Example (1) sits where the data usually starts and it is Tillamook, in Edel's 1939 transcription,
# with its own vowel letters A, E, U and its own stress mark. Examples (19) and (20) are Thompson
# and Lillooet, and footnote 9 carries Puget Sound Salish, Moses-Columbian and a row of English
# phonetics. A reader that took every numbered example as Twana would seed a Twana corpus with five
# other languages and some English.
#
# WHAT IS NOT A WORD
#
# The derivations are the bulk of the paper and their intermediate lines are underlying forms
# nobody said: *soq̓ʷ-sóq̓ʷay, ʔas-bx̦-báx̦. The paper marks them with an asterisk where it cites one
# and with the cent sign where the form is wrong outright. Both are held out of the pure stream.

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

SOURCE = os.path.join(PAPERS, "Kim_TwanaReduplication_final.txt")

TARGET = os.path.join(
    CORPORA,
    "unstated_TheTruncatedReduplicationInTwana_Kim_Salish_twana_2017_mixed.txt")

# Kept in step with KIM in hand_extraction/papers.py. ɫ is this paper's lateral fricative, a third
# character for it after ɬ and ł, and ˀ is its rule-derived glottal stop against phonemic ʔ.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "ɫˀščóéɔ" + "̦́ʹ"

PAGE = re.compile(r"^===== page \d+ =====$")

# An example number opening a block, which is what says whose forms follow.
EXAMPLE = re.compile(r"^\((\d{1,2})\)")

TARGET_LANGUAGE = "Twana"

# Which numbered example belongs to which language. Everything not named here is Twana.
NOT_TWANA = {1: "Tillamook", 2: "Tillamook", 19: "nɬeʔkepmxcín", 20: "nɬeʔkepmxcín"}

# The footnote that carries three other languages and a row of English phonetics. Its forms are read
# out as unclassified rather than guessed at, because the language changes inside one sentence.
MIXED_FOOTNOTE = 9

# What marks a form nobody said: an underlying or etymological form, and an outright wrong one.
UNDERLYING = "*"
INCORRECT = "¢"


def kind_of(token):
    """What a token is: a form the paper attests, one it reconstructs, or one it rejects."""
    if token.startswith(UNDERLYING):
        return "underlying"
    if token.startswith(INCORRECT):
        return "impossible"
    return "cited form"


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
    named = TARGET_LANGUAGE
    footnote = None

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        found = EXAMPLE.match(trimmed)
        if found:
            number = int(found.group(1))
            where = "(%d)" % number
            named = NOT_TWANA.get(number, TARGET_LANGUAGE)
            footnote = None
        # A footnote opens with its own number at the head of the line. Only the one that mixes
        # languages is tracked, because it is the only one whose forms cannot be attributed.
        elif re.match(r"^%d\s" % MIXED_FOOTNOTE, trimmed):
            footnote = MIXED_FOOTNOTE
            where = "fn%d" % MIXED_FOOTNOTE

        for token in trimmed.split():
            plain = token.strip(".,;:()[]“”‘’")
            if not is_language_token(plain, MARKS):
                continue
            if footnote == MIXED_FOOTNOTE:
                rows.append((where, "", UNCLASSIFIED, plain))
                continue
            rows.append((where, named, kind_of(plain), plain))

    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for page, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % page, "", UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# The truncated reduplication in Twana: Another case of synergistic\n")
        handle.write("# weakening. Hyung-Soo Kim, Hankuk University of Foreign Studies, Korea.\n")
        handle.write("# Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages 52, UBCWPL 45, 2017.\n")
        handle.write("#\n")
        handle.write("# Every Twana form is Drachman (1969), which the paper calls the only\n")
        handle.write("# reliable reference in existence for Twana CVC reduplication.\n")
        handle.write("#\n")
        handle.write("# Example (1) is Tillamook, (19) and (20) are Thompson and Lillooet, and\n")
        handle.write("# footnote 9 mixes Puget Sound Salish, Moses-Columbian and English. The who\n")
        handle.write("# column says which, and the footnote is left unclassified for a person.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, who, kind, text) in enumerate(rows, 1):
            spoken = (kind == "cited form") and (who == TARGET_LANGUAGE)
            layer = SPOKEN if spoken else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, who or spot, kind, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for spot, who, kind, text in rows:
            if (kind != "cited form") or (who != TARGET_LANGUAGE):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = " ".join(run.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, who, kind, text in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "The truncated reduplication in Twana", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d Twana forms written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    languages = {}
    for spot, who, kind, text in rows:
        if kind == "cited form":
            languages[who] = languages.get(who, 0) + 1
    out.write("\n  by language: %s\n"
              % ", ".join("%s %d" % (one, languages[one]) for one in sorted(languages)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
