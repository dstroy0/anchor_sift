#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Nsyilxcn inchoatives John Lyon surveys in ICSNL 60.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_lyon_inchoatives.py
#
# Elicited from ɬk̓mxnalqs Delphine Derrickson-Armstrong and c̓əskʕáknaʔ Dave Michele of Westbank
# reserve. The data is two tables of 48 roots, each row giving the root, its positive adjective, and
# what it does with each of the three inchoative markers, plus a corpus survey citing cognates from
# six other Salish languages.
#
# A STAR IS NOT A WORD
#
# Most cells of both tables are starred: *piq-p, *x̌aq̓-t, *ʔilxʷ•əxʷ. A starred form is one the
# linguist built and the speakers rejected, and nobody has ever said one. Putting them in a pure
# corpus would seed it with words the language does not have, which is worse than leaving them out,
# because the whole point of the corpus is to say what the language looks like. They are kept in the
# record marked "impossible" and held out of the pure stream. The same goes for the marginal forms
# the paper marks with a question mark.
#
# WHAT IS NOT NSYILXCN
#
# Section 4 cites cognates from Spokane, Secwepemctsín, Lillooet, nxaʔamxčín, Thompson and Coeur
# d'Alene, each behind a two-letter tag. Those are Salish and they are not Nsyilxcn, so the who
# column carries the language and the pure stream takes the Nsyilxcn alone.

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

SOURCE = os.path.join(PAPERS, "LyonICSNL60_Inch-2.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "DelphineDerricksonArmstrong-DaveMichele_NsyilxcnInchoativesAndTheirDistributions"
    "AcrossRootTypes_Lyon_Salish_nsyilxcen_2025_mixed.txt")

# Kept in step with LYON_INCH in hand_extraction/papers.py. The square root sign is in the set
# because it is what makes √piq, √nir, √mir, √yus and √tar visible at all: those carry no other
# character of the shared orthography.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "̌́" + "áíúé" + "ɣš√"

PAGE = re.compile(r"^===== page \d+ =====$")

# The tag the paper puts in front of a cognate, expanded to the language it names.
COGNATES = {
    "Sp": "Spokane", "Sh": "Secwepemctsin", "Li": "Lillooet",
    "Cm": "nxaʔamxčín", "Th": "nɬeʔkepmxcín", "Cr": "Coeur d'Alene",
}

TARGET_LANGUAGE = "Nsyilxcən"

# A row of Table 1 or Table 2: the entry number, then the root, then the rest of the row.
TABLE_ROW = re.compile(r"^(\d{1,2})\s+(√\S+.*)$")

# What the paper marks a rejected form with, and what it marks a marginal one with. Neither is a
# word of the language and neither reaches the pure stream.
REJECTED = "*"
MARGINAL = "?"


def kind_of(token):
    """What a token of the tables is: a form the speakers accepted, rejected, or found marginal."""
    if token.startswith(REJECTED):
        return "impossible"
    if token.startswith(MARGINAL):
        return "candidate"
    return "cited form"


def language_of(tokens, at):
    """Whose form this is, from the nearest cognate tag standing in front of it on the line.

    Section 4 sets a cognate as Sp √p̓ax̌ or Th xʷ[ʔ]úl, so the tag is the token before. Without this
    the Spokane and Thompson forms arrive in a corpus labelled Nsyilxcn, which is the one mistake
    this paper's layout makes easy.
    """
    for back in range(at - 1, max(-1, at - 4), -1):
        plain = tokens[back].strip(".,;:()[]")
        if plain in COGNATES:
            return COGNATES[plain]
    return TARGET_LANGUAGE


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

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        found = TABLE_ROW.match(trimmed)
        if found:
            where = "root %s" % found.group(1)
            trimmed = found.group(2)

        tokens = trimmed.split()
        kept = []
        for at, token in enumerate(tokens):
            plain = token.strip(".,;:()[]“”")
            if not is_language_token(plain, MARKS):
                continue
            kept.append((language_of(tokens, at), kind_of(plain), plain))
        if not kept:
            continue
        for named, kind, plain in kept:
            rows.append((where, named, kind, plain))

    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for page, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % page, "", UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Nsyilxcn Inchoatives and their Distributions Across Root Types.\n")
        handle.write("# John Lyon, University of British Columbia - Okanagan. Proceedings of the\n")
        handle.write("# International Conference on Salish and Neighbouring Languages 60,\n")
        handle.write("# Vancouver, BC: UBCWPL, 2025.\n")
        handle.write("#\n")
        handle.write("# Elicited from ɬk̓mxnalqs Delphine Derrickson-Armstrong and c̓əskʕáknaʔ Dave\n")
        handle.write("# Michele of stq̓aʔtkʷɬniw̓t, the Westbank Reserve.\n")
        handle.write("#\n")
        handle.write("# A starred form was built by the linguist and rejected by the speakers, and\n")
        handle.write("# a form marked with a question mark was judged marginal. Neither is a word\n")
        handle.write("# anybody said, so both are derived and neither reaches the pure stream.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, named, kind, text) in enumerate(rows, 1):
            spoken = (kind == "cited form") and (named == TARGET_LANGUAGE)
            layer = SPOKEN if spoken else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, named or spot, kind, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept_count = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for spot, named, kind, text in rows:
            if (kind != "cited form") or (named != TARGET_LANGUAGE):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = " ".join(run.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept_count += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, named, kind, text in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Nsyilxcn Inchoatives", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d Nsyilxcn forms written to\n  %s\n" % (kept_count, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    counted = {}
    for spot, named, kind, text in rows:
        counted[kind] = counted.get(kind, 0) + 1
    out.write("\n  by kind: %s\n"
              % ", ".join("%s %d" % (one, counted[one]) for one in sorted(counted)))
    languages = {}
    for spot, named, kind, text in rows:
        if kind == "cited form":
            languages[named] = languages.get(named, 0) + 1
    out.write("  by language: %s\n"
              % ", ".join("%s %d" % (one, languages[one]) for one in sorted(languages)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
